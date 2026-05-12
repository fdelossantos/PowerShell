$CsvPath = "C:\temp\shared.csv"

Connect-ExchangeOnline

$rows = Import-Csv -Path $CsvPath -Delimiter ";"

$headers = ($rows[0].PSObject.Properties).Name
$upnColumn = $headers[0]
$sharedMailboxes = $headers | Select-Object -Skip 1

foreach ($row in $rows) {
    $userUpn = $row.$upnColumn.Trim()

    foreach ($sharedMailbox in $sharedMailboxes) {
        $value = $row.$sharedMailbox.ToString().Trim()

        if ($value -eq "1") {
            Write-Host "$userUpn -> $sharedMailbox"

            Add-MailboxPermission `
                -Identity $sharedMailbox `
                -User $userUpn `
                -AccessRights FullAccess `
                -InheritanceType All `
                -AutoMapping $false

            Add-RecipientPermission `
                -Identity $sharedMailbox `
                -Trustee $userUpn `
                -AccessRights SendAs `
                -Confirm:$false
        }
    }
}