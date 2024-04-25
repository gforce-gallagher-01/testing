# testing
This PowerShell script retrieves the latest success file from the domain accounts directory and processes the information within the success file.

It imports the Active Directory module to enable interactions with Active Directory objects.

The script retrieves the latest directory within the specified path and then constructs the path to the success file within that directory.

It validates the presence of the success file at the specified path to ensure that the script can proceed.

The script reads the content of the success file and processes each line.

For each line in the success file, it parses the username and groups from the line and then proceeds to remove the user from the specified groups within Active Directory.

After removing the user from the groups, the script attempts to remove the user from Active Directory entirely.

Overall, this script is designed to handle the cleanup process for user accounts and groups in Active Directory based on the information provided in the success file. It removes the user from specified groups and ultimately removes the user from Active Directory. Any errors encountered during the process are logged for further review.
