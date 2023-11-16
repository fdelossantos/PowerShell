# Obtener todos los buzones de usuario
$mailboxes = Get-Mailbox -ResultSize Unlimited

# Crear una lista para almacenar los dominios únicos
$uniqueDomains = @()

# Recorrer cada buzón de usuario
foreach ($mailbox in $mailboxes) {
    # Obtener el dominio de la dirección de correo electrónico principal
    $domain = ($mailbox.PrimarySmtpAddress -split "@")[1]

    # Agregar el dominio a la lista de dominios únicos si no existe previamente
    if ($domain -notin $uniqueDomains) {
        $uniqueDomains += $domain
    }
}

# Recorrer cada dominio único
foreach ($domain in $uniqueDomains) {
    Write-Host "Consultando registros TXT para el dominio: $domain"
    
    # Obtener los registros TXT del dominio
    $txtRecords = Resolve-DnsName -Name $domain -Type TXT

    # Recorrer cada registro TXT
    foreach ($txtRecord in $txtRecords) {
        $txtValue = $txtRecord.Strings -join ""

        # Verificar si es un registro SPF
        if ($txtValue -like "v=spf1*") {
            Write-Host "Registro SPF encontrado para el dominio: $domain"

            # Verificar si el registro SPF no incluye la entrada "ipv4:0.0.0.0"
            if ($txtValue -notlike "*ipv4:0.0.0.0*") {
                Write-Host "La entrada 'ipv4:0.0.0.0' no está presente en el registro SPF del dominio: $domain"

                # Construir el nuevo valor del registro SPF
                $newTxtValue = "$txtValue ipv4:0.0.0.0"

                # Mostrar la línea para el cambio del registro SPF
                Write-Host "Se debe cambiar el registro SPF del dominio $($domain):"
                Write-Host "Antes: $txtValue"
                Write-Host "Después: $newTxtValue"
                Write-Host ""
            }
        }
    }
}
