<#
USAGE: 
Enable-ArchivingToUser -Identity federicod -MRMPolicyName "Company MRM Policy" -ArchiveName = "My Archive" -MonitorTimes 10

URL: https://github.com/fdelossantos/PowerShell/blob/master/ExchangeOnline/Enable-ArchivingToUser.ps1
#>

param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Identity,

    [Parameter]
    [string]$MRMPolicyName = "Default MRM Policy",

    [Parameter]
    [string]$ArchiveName = "Archivo",

    [Parameter]
    [int]$MonitorTimes = 2
)

Connect-ExchangeOnline

$guidUserMailbox = (Get-EXOMailbox $Identity).Guid

Enable-Mailbox -Identity $Identity -Archive -ArchiveName $ArchiveName
Start-Sleep -Seconds 10
$guidArchiveMailbox = (Get-Mailbox $Identity).ArchiveGuid

Set-Mailbox -Identity $Identity -RetentionPolicy $MRMPolicyName

Start-ManagedFolderAssistant -Identity $guidUserMailbox -ErrorAction SilentlyContinue

Start-Sleep -Seconds 10

for ($i = 0; $i -lt $MonitorTimes; $i++) {
    $itemsUserMailbox = (Get-MailboxStatistics -Identity $guidUserMailbox).ItemCount
    $itemsArchiveMailbox = (Get-MailboxStatistics -Identity $guidArchiveMailbox).ItemCount

    $resultado = [PSCustomObject]@{
        ItemsUserMailbox = $itemsUserMailbox
        ItemsArchiveMailbox = $itemsArchiveMailbox
    }
    Start-Sleep -Seconds 10
    $resultado
}