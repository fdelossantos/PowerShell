# Crea un script de powershell que acepte como parámetro un nombre de usuario, un dominio de origen y un dominio de destino. Estos parámetros son obligatorios.
# Los dominios son FQDN de dominios de Active Directory.
# El script dejará un log con las acciones realizadas. El nombre del log tendrá el formato "Migration attempt $username yyyy-MM-dd hhmmss.log"
# El script conecta al primero dominio, de origen, y busca el usuario de Activ Directory. Se usará el valor de SID para los siguientes pasos.
# Luego conecta al segundo dominio, de destino, y obtiene el usuario con el mismo nombre usado anteriormente. Se usará el SID en los siguientes pasos.
# En el log se almacenará la salida estándar de los comandos Get-ADUser para esos usuarios.
# A continuación, el script se conecta a un servidor SQL Server llamado AXDEV01 y a la base de datos de nombre AXDB; estos valores son parámetros opcionales.
# En la tabla USERINFO modificará 2 campos: el campo SID y el campo NETWORKDOMAIN para el usuario, cuyo valor está en el campo ID, el cual es clave primaria de la tabla.
# La modificación consiste en cambiar el SID original por el nuevo y el dominio original por el nuevo.
# El script validará primero que el SID registrado en la tabla sea el mismo que el de origen. En caso contrario validará si el usuario ya estaba modificado o si se encontró un SID no reconocido.
# Cualquiera sea el resultado de la validación, se registrará en el log.
# En caso de que las validaciones sean superadas, el script registrará la sentencia SQL a realizar en el log y además dejará registrada la sentencia para la vuelta atrás.
# Luego del registro procederá a la ejecución del UPDATE y mostrará en pantalla el resultado de la ejecución y además registrará en el log.

param (
    [Parameter(Mandatory=$true)]
    [string]$username,

    [Parameter(Mandatory=$true)]
    [string]$sourceDomain,

    [Parameter(Mandatory=$true)]
    [string]$destinationDomain,

    [string]$sqlServer = "AXDEV01",

    [string]$database = "AXDB"
)

# Configuración del log
$logFileName = "Migration attempt $username $(Get-Date -Format 'yyyy-MM-dd HHmmss').log"
$logFilePath = Join-Path -Path $env:TEMP -ChildPath $logFileName

# Función para escribir en el log
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

Write-Log "Iniciando migración para el usuario $username"

# Conectando al dominio de origen
Write-Log "Conectando al dominio de origen: $sourceDomain"
$sourceUser = Get-ADUser -Server $sourceDomain -Identity $username -Properties SID | Out-String
Write-Log "Información del usuario en el dominio de origen: $sourceUser"

# Obteniendo el SID del usuario en el dominio de origen
$sourceUserSID = (Get-ADUser -Server $sourceDomain -Identity $username -Properties SID).SID.Value

# Conectando al dominio de destino
Write-Log "Conectando al dominio de destino: $destinationDomain"
$destinationUser = Get-ADUser -Server $destinationDomain -Identity $username -Properties SID | Out-String
Write-Log "Información del usuario en el dominio de destino: $destinationUser"

# Obteniendo el SID del usuario en el dominio de destino
$destinationUserSID = (Get-ADUser -Server $destinationDomain -Identity $username -Properties SID).SID.Value

# Conectando al servidor SQL y base de datos
Write-Log "Conectando al servidor SQL $sqlServer y a la base de datos $database"
$connectionString = "Server=$sqlServer;Database=$database;Integrated Security=True;"
$query = "SELECT SID, NETWORKDOMAIN FROM USERINFO WHERE ID = '$username'"

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()

    $command = $connection.CreateCommand()
    $command.CommandText = $query
    $reader = $command.ExecuteReader()

    if ($reader.Read()) {
        $currentSID = $reader["SID"]
        $currentDomain = $reader["NETWORKDOMAIN"]

        Write-Log "SID en la base de datos: $currentSID"
        Write-Log "Dominio en la base de datos: $currentDomain"

        if ($currentSID -eq $sourceUserSID) {
            # Preparar las sentencias SQL
            $updateQuery = "UPDATE USERINFO SET SID = '$destinationUserSID', NETWORKDOMAIN = '$destinationDomain' WHERE ID = '$username'"
            $rollbackQuery = "UPDATE USERINFO SET SID = '$sourceUserSID', NETWORKDOMAIN = '$sourceDomain' WHERE ID = '$username'"

            Write-Log "Sentencia SQL de actualización: $updateQuery"
            Write-Log "Sentencia SQL de rollback: $rollbackQuery"

            # Ejecutar la sentencia de actualización
            $command.CommandText = $updateQuery
            $result = $command.ExecuteNonQuery()

            Write-Log "Resultado de la ejecución del UPDATE: $result"
        } elseif ($currentSID -eq $destinationUserSID) {
            Write-Log "El SID en la base de datos ya es el SID del dominio de destino. No se requiere ninguna acción."
        } else {
            Write-Log "El SID en la base de datos no coincide con el SID de origen ni con el SID de destino. Acción no reconocida."
        }
    } else {
        Write-Log "No se encontró el usuario en la base de datos."
    }

    $reader.Close()
    $connection.Close()
} catch {
    Write-Log "Error durante la conexión o ejecución en SQL Server: $_"
}

Write-Log "Migración completada."
