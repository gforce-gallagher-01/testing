# Import the Active Directory module
Import-Module ActiveDirectory

# Define the path to the domain accounts directory
$domainAccountsDir = "C:\gridsec\domainaccounts"

# Get the directory with the latest timestamp
$latestDir = Get-ChildItem -Path $domainAccountsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1

# Define the path to the success file
$successFilePath = "$latestDir\success.txt"

# Validate the success file
if (-not (Test-Path -Path $successFilePath)) {
    Write-Error "Success file not found at path: $successFilePath"
    return
}

# Read the success file
$lines = Get-Content -Path $successFilePath

# Loop through each line in the success file
foreach ($line in $lines) {
    # Parse the username and groups from the line
    if ($line -match "(.+) - Created user and added to groups: (.+)") {
        $username = $Matches[1]
        $groups = $Matches[2] -split ', '

        # Remove the user from the groups
        foreach ($group in $groups) {
            try {
                Remove-ADGroupMember -Identity $group -Members $username -Confirm:$false
                Write-Host "Successfully removed $username from $group"
            } catch {
                Write-Error "Failed to remove $username from $group: $_"
            }
        }

        # Remove the user
        try {
            Remove-ADUser -Identity $username -Confirm:$false
            Write-Host "Successfully removed user $username"
        } catch {
            Write-Error "Failed to remove user $username: $_"
        }
    }
}