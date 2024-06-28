# Ensure the directories exist
$directoryPath = "C:/gridsec/splunk"
$logDirectoryPath = "C:/gridsec/splunk/script_output"

# Function to create directory if it does not exist
function Ensure-Directory {
    param (
        [Parameter(Mandatory=$true)]
        [string]$path
    )
    if (-Not (Test-Path -Path $path)) {
        try {
            New-Item -Path $path -ItemType Directory -ErrorAction Stop
            Write-Host "Created directory: $path"
        } catch {
            Write-Host "Failed to create directory: $path. Error: $_" "ERROR"
            exit 1
        }
    } else {
        Write-Host "Directory already exists: $path"
    }
}

# Function to write output logs
function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$level] - $message" | Out-File -FilePath "$logDirectoryPath/get_system_info_script_run_output.log" -Append
}

# Function to get hostname
function Get-Hostname {
    try {
        $hostname = hostname
        Write-Log "Retrieved hostname: $hostname"
        return $hostname
    } catch {
        Write-Log "Failed to retrieve hostname. Error: $_" "ERROR"
        exit 1
    }
}

# Function to get host IP addresses
function Get-IPs {
    param (
        [string]$hostname
    )
    try {
        $ipAddresses = [System.Net.Dns]::GetHostAddresses($hostname)
        $ipV4List = @()
        $ipV6List = @()
        foreach ($ip in $ipAddresses) {
            if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                if (-not ($ip.IPAddressToString -match "^169\.254\.")) {
                    $ipV4List += $ip.IPAddressToString
                }
            } elseif ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                $ipV6List += $ip.IPAddressToString
            }
        }
        if ($ipV4List.Count -eq 0) {
            Write-Log "No valid IPv4 address found for hostname: $hostname" "ERROR"
            exit 1
        }
        return @{
            IPv4 = $ipV4List
            IPv6 = $ipV6List
        }
    } catch {
        Write-Log "Failed to retrieve IP addresses for hostname: $hostname. Error: $_" "ERROR"
        exit 1
    }
}

# Function to get Windows server type
function Get-ServerType {
    try {
        $domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
        switch ($domainRole) {
            0 { $serverType = "standalone_workstation"; Write-Log "Server type is Standalone Workstation" }
            1 { $serverType = "member_workstation"; Write-Log "Server type is Member Workstation" }
            2 { $serverType = "standalone_server"; Write-Log "Server type is Standalone Server" }
            3 { $serverType = "member_server"; Write-Log "Server type is Member Server" }
            4 { $serverType = "backup_domain_controller"; Write-Log "Server type is Backup Domain Controller" }
            5 { $serverType = "primary_domain_controller"; Write-Log "Server type is Primary Domain Controller" }
        }
        return $serverType
    } catch {
        Write-Log "Failed to determine server type. Error: $_" "ERROR"
        exit 1
    }
}

# Function to get all local drives and percentage full
function Get-DriveInfo {
    try {
        $drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        $driveInfo = @()
        foreach ($drive in $drives) {
            $percentFree = [math]::Round((($drive.FreeSpace / $drive.Size) * 100), 2)
            $percentFull = [math]::Round((100 - $percentFree), 2)
            $driveInfo += @{
                DriveLetter = $drive.DeviceID
                SizeGB = [math]::Round(($drive.Size / 1GB), 2)
                FreeSpaceGB = [math]::Round(($drive.FreeSpace / 1GB), 2)
                PercentFree = $percentFree
                PercentFull = $percentFull
            }
        }
        Write-Log "Retrieved drive information"
        return $driveInfo
    } catch {
        Write-Log "Failed to retrieve drive information. Error: $_" "ERROR"
        exit 1
    }
}

# Function to get external NAT IP address
function Get-ExternalIP {
    try {
        $response = Invoke-WebRequest -Uri "https://ipconfig.io" -UseBasicParsing
        $ipAddress = ($response.Content -match '<td>([\d\.]+)</td>') | Out-Null
        $externalIP = $matches[1]
        Write-Log "Retrieved external NAT IP: $externalIP"
        return $externalIP
    } catch {
        Write-Log "Failed to retrieve external NAT IP address. Error: $_" "ERROR"
        exit 1
    }
}

# Main script logic wrapped in a try-catch block
try {
    # Ensure main and log directories exist
    Ensure-Directory -path $directoryPath
    Ensure-Directory -path $logDirectoryPath
    Write-Log "Directories ensured"

    # Get hostname and IP addresses
    $hostname = Get-Hostname
    $ipAddresses = Get-IPs -hostname $hostname

    # Get server type
    $serverType = Get-ServerType

    # Get the current time zone
    $currentTimeZone = [TimeZoneInfo]::Local

    # Get the current timestamp
    $currentTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Get external NAT IP address
    $externalIP = Get-ExternalIP

    # Create a flat object with all the required fields
    $data = @{
        UTC_Offset = $currentTimeZone.BaseUtcOffset.ToString()
        server_type = $serverType
        Timestamp = $currentTimestamp
        host = $hostname
        Daylight_Time_Name = $currentTimeZone.DaylightName
        Standard_Time_Name = $currentTimeZone.StandardName
        Current_Time_Zone = $currentTimeZone.DisplayName
        ipaddress = $ipAddresses.IPv4[0]
        external_nat = $externalIP
    }

    # Add additional IPv4 addresses if any
    for ($i = 1; $i -lt $ipAddresses.IPv4.Count; $i++) {
        $data["ipaddress-$(($i - 1).ToString("D2"))"] = $ipAddresses.IPv4[$i]
    }

    # Add IPv6 addresses if any
    if ($ipAddresses.IPv6.Count -gt 0) {
        $data["ipaddressv6"] = $ipAddresses.IPv6[0]
        for ($i = 1; $i -lt $ipAddresses.IPv6.Count; $i++) {
            $data["ipaddressv6-$(($i).ToString("D2"))"] = $ipAddresses.IPv6[$i]
        }
    }

    # Get all drive information and append it to the data object
    $driveInfo = Get-DriveInfo
    foreach ($drive in $driveInfo) {
        $data["Drive_$($drive.DriveLetter.TrimEnd(':'))_SizeGB"] = [math]::Round($drive.SizeGB, 2)
        $data["Drive_$($drive.DriveLetter.TrimEnd(':'))_FreeSpaceGB"] = [math]::Round($drive.FreeSpaceGB, 2)
        $data["Drive_$($drive.DriveLetter.TrimEnd(':'))_PercentFree"] = [math]::Round($drive.PercentFree, 2)
        $data["Drive_$($drive.DriveLetter.TrimEnd(':'))_PercentFull"] = [math]::Round($drive.PercentFull, 2)
    }

    # Convert the data object to JSON
    $json = $data | ConvertTo-Json -ErrorAction Stop | ConvertFrom-Json | ConvertTo-Json -Depth 10
    Write-Log "Converted data to JSON: $json"

    # File path for the JSON file with timestamp
    $fileTimestamp = Get-Date -Format "yyyyMMddHHmmss"
    $filePath = "$directoryPath/system_details_$fileTimestamp.json"

    # Save JSON to file
    $json | Out-File -FilePath $filePath -ErrorAction Stop
    Write-Log "Successfully wrote JSON to file: $filePath"

    # Keep only the last 4 copies in the directory (log output clean up)
    $files = Get-ChildItem -Path $directoryPath | Where-Object { $_.Name -like "system_details_*.json" } | Sort-Object CreationTime -Descending
    if ($files.Count -gt 4) {
        $files | Select-Object -Skip 4 | Remove-Item -Force
        Write-Log "Removed old JSON files, kept only the last 4 copies"
    }
} catch {
    Write-Log "Script execution failed. Error: $_" "ERROR"
    exit 1
}

# Debugging output
Write-Output "JSON Output: $json"
