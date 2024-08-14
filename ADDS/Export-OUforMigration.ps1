# Define the path where the GPO backups will be saved
$BackupPath = "C:\GPO_Backups"

# Create the directory if it does not exist
if (-not (Test-Path -Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath
}

# Get all the GPOs in the domain
$GPOs = Get-GPO -All

# Loop through each GPO and export it
foreach ($GPO in $GPOs) {
    $GPOName = $GPO.DisplayName
    $GPOBackupPath = Join-Path -Path $BackupPath -ChildPath $GPOName

    # Export the GPO to the specified backup path
    Backup-GPO -Name $GPOName -Path $GPOBackupPath -Comment "Backup on $(Get-Date)"
}

Write-Host "All GPOs have been exported successfully to $BackupPath"
