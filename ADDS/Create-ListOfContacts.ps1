$ou = "OU=Contactos,DC=contoso,DC=com"
$rows = Import-Csv .\usuarios.csv

foreach ($r in $rows) {
    $email = $r.primaryEmail
    if (-not $email) { continue }

    $local, $domain = $email -split '@', 2
    $alias  = $local
    $target = "SMTP:$local@gsuite.$domain"

    # Toma fullName si existe; si no, arma con given/family si están presentes
    $name = $r.fullName
    if (-not $name -or $name.Trim() -eq "") {
        $name = @($r.givenName, $r.familyName) -join ' '
        $name = $name.Trim()
        if ($name -eq "") { $name = $email }
    }
    $nick = $email -replace '@','_'
    # $contact = New-ADObject -Type contact -Name $name -Path $ou -OtherAttributes @{ displayName = $name }

    New-ADObject -Name $name -Type contact -Path $ou -Server $AdServer `
        -OtherAttributes @{
            mail = $email;
            displayName = $name;
            mailNickname = $nick;
            targetAddress = $target
        }
}
