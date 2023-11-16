# Obtener todos los buzones de usuario
$mailboxes = Get-Mailbox -ResultSize Unlimited

# Crear una lista para almacenar los dominios únicos
$uniqueDomains = @()

# Recorrer cada buzón de usuario
foreach ($mailbox in $mailboxes) {
    # Obtener el dominio de la dirección de correo electrónico principal
    $domain = ($mailbox.PrimarySmtpAddress -Split "@")[1]

    # Agregar el dominio a la lista de dominios únicos si no existe previamente
    if ($domain -notin $uniqueDomains) {
        $uniqueDomains += $domain
    }
}

# Mostrar la lista de dominios únicos obtenidos
Write-Host "Dominios únicos encontrados:"
$uniqueDomains