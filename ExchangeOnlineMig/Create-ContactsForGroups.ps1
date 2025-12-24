# Conectar a Exchange Online
Connect-ExchangeOnline

# Importar CSV de grupos
$groups = Import-Csv -Path .\groups.csv

# Crear contactos por cada grupo
foreach ($g in $groups) {
    $email = $g.email.Trim()
    if ([string]::IsNullOrWhiteSpace($email)) { continue }

    $displayName = if ($g.name) { $g.name.Trim() } else { $email.Split('@')[0] }
    $alias = ($email.Replace('@','_') -replace '[^a-zA-Z0-9._-]', '').ToLower()

    New-MailContact `
        -Name $displayName `
        -DisplayName $displayName `
        -Alias $alias `
        -ExternalEmailAddress $email
}
