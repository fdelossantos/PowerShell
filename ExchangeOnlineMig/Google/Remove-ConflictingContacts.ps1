# ============================================================
# Remove-ConflictingContactsFromGoogleGroups.ps1
# Lee GoogleGroups.csv y elimina MailContacts/MailUsers que
# coincidan con la dirección de correo del grupo (Identity).
# Muestra en pantalla qué encontró y qué borró.
# ============================================================

$GroupsCsv = "E:\Work\VPC\GroupsMigration\export\GoogleGroups.csv"

$groups = Import-Csv $GroupsCsv

foreach ($g in $groups) {
    $groupEmail = $g.email

    if ([string]::IsNullOrWhiteSpace($groupEmail)) {
        continue
    }

    Write-Host ""
    Write-Host "==> Checking: $groupEmail"

    # Buscar contacto por Identity (igual que en tu script principal)
    $contact = $null
    try {
        $contact = Get-MailContact -Identity $groupEmail -ErrorAction Stop
    }
    catch {
        $contact = $null
    }

    if ($null -ne $contact) {
        Write-Host ("Found MailContact: {0} | PrimarySmtpAddress: {1}" -f $contact.Identity, $contact.PrimarySmtpAddress)
        Remove-MailContact -Identity $contact.Identity -Confirm:$false
        Write-Host ("Removed MailContact: {0}" -f $contact.Identity)
        continue
    }

    # Buscar MailUser por Identity (por si el objeto no es MailContact)
    $mailUser = $null
    try {
        $mailUser = Get-MailUser -Identity $groupEmail -ErrorAction Stop
    }
    catch {
        $mailUser = $null
    }

    if ($null -ne $mailUser) {
        Write-Host ("Found MailUser: {0} | PrimarySmtpAddress: {1}" -f $mailUser.Identity, $mailUser.PrimarySmtpAddress)
        Remove-MailUser -Identity $mailUser.Identity -Confirm:$false
        Write-Host ("Removed MailUser: {0}" -f $mailUser.Identity)
        continue
    }

    Write-Host "No MailContact/MailUser found."
}
