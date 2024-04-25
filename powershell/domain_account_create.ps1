# Define the path for the success and failure files
$folderPath = "C:\gridsec\domainaccounts\domaincreate-$timestamp"
New-Item -ItemType Directory -Force -Path $folderPath
$successFilePath = "$folderPath\success.txt"
$failureFilePath = "$folderPath\failure.txt"

# Read the CSV file
$users = Import-Csv -Path $csvFilePath

# Loop through each user in the CSV file
$jobs = foreach ($user in $users) {
    Start-Job -ScriptBlock {
        param($user, $successFilePath, $failureFilePath)

        # Check if the user already exists
        if (Get-ADUser -Filter { SamAccountName -eq $user.user }) {
            "$($user.user) - User already exists" | Out-File -FilePath $failureFilePath -Append
            return
        }

        # Generate a random password of minimum length 16
        $password = ConvertTo-SecureString -String ([System.Web.Security.Membership]::GeneratePassword(16, 2)) -AsPlainText -Force

        # Create the user
        try {
            New-ADUser -SamAccountName $user.user -UserPrincipalName $user.email -Name $user.user -Description $user.Description -Enabled $true -PasswordNeverExpires $true -PassThru -AccountPassword $password | Out-File -FilePath $successFilePath -Append
            $passwordInfo = [PSCustomObject]@{
                User = $user.user
                Password = $password
            }
            $passwordInfo | Export-Csv -Path "$folderPath\$($user.user)_password.csv" -NoTypeInformation -Append

            # Add the user to domain groups
            $groups = @()
            for ($i = 1; $i -le 4; $i++) {
                $group = $user."domaingroup0$i"
                if ($group) {
                    Add-ADGroupMember -Identity $group -Members $user.user -ErrorAction SilentlyContinue
                    $groups += $group
                }
            }
            # Output the user and their groups to the success file
            "$($user.user) - Created user and added to groups: $($groups -join ', ')" | Out-File -FilePath $successFilePath -Append
        } catch {
            "$($user.user) - Failed to create user: $_" | Out-File -FilePath $failureFilePath -Append
        }
    } -ArgumentList $user, $successFilePath, $failureFilePath
}

# Wait for all jobs to complete
$jobs | Wait-Job | Receive-Job