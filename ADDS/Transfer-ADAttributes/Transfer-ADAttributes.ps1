# THIS SCRIPT HAS NOT BEEN TESTED AND IS OBSOLETE BECAUSE ADMT INCLUDE THIS FEATURE BY EXTRA CONFIGURATION


# PowerShell Script para sincronizar los atributos que no migra ADMT
# Hay que correrlo en el servidor de destino
# Establece una sesión remota en el AD de origen.

### PARAMETROS
# Archivo plano con usuarios
$userListPath = "C:\Temp\usuarios.txt"

# Usuario para conectar al dominio de origen
$remoteADUsername = "dominio\administrator"
# (La contraseña la pide al conectar)
$remoteADServer = "dc01.example.com"

# Importar módulo de AD local
Import-Module ActiveDirectory

#Cargar el archivo
$usernames = Get-Content $userListPath

# Establecer conexión al AD de origen
$remoteADSession = New-PSSession -ComputerName $remoteADServer -Credential $remoteADUsername

# Importar módulo de AD en la sesión remota
Import-PSSession -Session $remoteADSession -Module ActiveDirectory -AllowClobber

Write-Host "Sesión conectada. Comienza el procesamiento."

foreach ($username in $usernames) {
    # Usuario original (remoto)
    # OJO que puede haber más atributos!!!!
    $remoteUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -Properties proxyAddresses, mail, EmailAddress,mS-DS-ConsistencyGuid,protocolSettings,targetAddress -Server $remoteADServer

    if ($remoteUser -ne $null) {
        # Obteniendo el usuario migrado
        $localUser = Get-ADUser -Filter "SamAccountName -eq '$username'" `
        -Properties proxyAddresses, mail, EmailAddress,mS-DS-ConsistencyGuid,protocolSettings,targetAddress

        if ($localUser -ne $null) {
            # Preparar una hashtable con los atributos a remplazar
            $propertiesToUpdate = @{
                "proxyaddresses" = $remoteUser.proxyaddresses # Este no se si funcionará así porque es multivaluado.
                "mail" = $remoteUser.mail
                "EmailAddress" = $remoteUser.EmailAddress
                "mS-DS-ConsistencyGuid" = $remoteUser.'mS-DS-ConsistencyGuid' # No llegué a probar si esto funciona así.
                "protocolSettings" = $remoteUser.protocolSettings
                "targetAddress" = $remoteUser.targetAddress
            }

            # Replazar los valores de los atributos
            Set-ADUser -Identity $localUser -Replace $propertiesToUpdate
            Write-Host "Atributos actualizados para $username."
        } else {
            Write-Host "El usuario $username todavía no fue migrado."
        }
    } else {
        Write-Host "El nombre de usuario $username es incorrecto."
    }
}

Write-Host "Procesamiento completado."

Remove-PSSession -Session $remoteADSession