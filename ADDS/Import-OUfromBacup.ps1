param (
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,

    [Parameter(Mandatory=$false)]
    [string]$GPOName = $null,

    [switch]$ReplaceIfExists
)

function Import-GPOFromBackup {
    param (
        [string]$GPOBackupPath,
        [switch]$Replace
    )

    # Get the backup information
    $BackupInfo = Get-GPOBackup -Path $GPOBackupPath

    # Check if the GPO already exists
    $ExistingGPO = Get-GPO -Name $BackupInfo.DisplayName -ErrorAction SilentlyContinue

    if ($ExistingGPO) {
        if ($Replace) {
            # Remove the existing GPO
            Remove-GPO -Name $BackupInfo.DisplayName -Confirm:$false
            Write-Host "Existing GPO '$($BackupInfo.DisplayName)' has been removed."
        } else {
            Write-Host "GPO '$($BackupInfo.DisplayName)' already exists. Skipping import."
            return
        }
    }

    # Import the GPO from the backup
    Import-GPO -BackupId $BackupInfo.Id -Path $GPOBackupPath -Domain $env:USERDNSDOMAIN -CreateIfNeeded
    Write-Host "GPO '$($BackupInfo.DisplayName)' has been imported successfully."
}

if (-not (Test-Path -Path $BackupPath)) {
    Write-Host "Backup path '$BackupPath' does not exist."
    exit
}

if ($GPOName) {
    # Import a specific GPO
    $GPOBackupPath = Join-Path -Path $BackupPath -ChildPath $GPOName
    if (Test-Path -Path $GPOBackupPath) {
        Import-GPOFromBackup -GPOBackupPath $GPOBackupPath -Replace:$ReplaceIfExists
    } else {
        Write-Host "Specified GPO backup '$GPOName' does not exist at path '$BackupPath'."
    }
} else {
    # Import all GPOs
    $GPOBackupDirs = Get-ChildItem -Path $BackupPath -Directory
    foreach ($GPOBackupDir in $GPOBackupDirs) {
        Import-GPOFromBackup -GPOBackupPath $GPOBackupDir.FullName -Replace:$ReplaceIfExists
    }
}

Write-Host "Import process completed."
