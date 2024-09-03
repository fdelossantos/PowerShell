# CRea un script para automatizar la ejecución del script anterior para realizar varias migraciones basadas en un archivo de texto que lista en cada línea el nombre de los usuarios a migrar. Los parámetros que no sean username, deben ser los mismos y pasarse tal cual al script de migración.

param (
    [Parameter(Mandatory=$true)]
    [string]$userListFilePath,

    [Parameter(Mandatory=$true)]
    [string]$sourceDomain,

    [Parameter(Mandatory=$true)]
    [string]$destinationDomain,

    [string]$sqlServer = "AXDEV01",

    [string]$database = "AXDB",

    [Parameter(Mandatory=$true)]
    [string]$migrationScriptPath
)

# Verificar que el archivo de lista de usuarios exista
if (-Not (Test-Path $userListFilePath)) {
    Write-Error "El archivo de lista de usuarios '$userListFilePath' no existe."
    exit 1
}

# Leer el archivo de texto que contiene los nombres de usuario
$users = Get-Content $userListFilePath

foreach ($user in $users) {
    # Eliminar espacios en blanco alrededor del nombre de usuario
    $user = $user.Trim()

    if (-Not [string]::IsNullOrWhiteSpace($user)) {
        Write-Output "Iniciando la migración para el usuario: $user"

        # Construir los argumentos para llamar al script de migración
        $arguments = @(
            "-username", $user,
            "-sourceDomain", $sourceDomain,
            "-destinationDomain", $destinationDomain,
            "-sqlServer", $sqlServer,
            "-database", $database
        )

        # Ejecutar el script de migración con los argumentos especificados
        try {
            & $migrationScriptPath @arguments
            Write-Output "Migración completada para el usuario: $user"
        } catch {
            Write-Error "Error durante la migración del usuario $($user): $_"
        }
    } else {
        Write-Output "Línea vacía o no válida en el archivo de lista de usuarios, omitiendo."
    }
}

Write-Output "Migración en lote completada."
