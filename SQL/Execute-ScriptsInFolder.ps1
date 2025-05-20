<#
.SYNOPSIS
    Procesa secuencialmente todos los scripts .sql de un directorio,
    envolviéndolos en transacción, habilitando IDENTITY_INSERT para una tabla
    y ejecutándolos contra un Azure SQL DB, con logs de éxito y error.

.PARAMETER ScriptsFolder
    Carpeta que contiene los archivos .sql generados (numerados 00000001.sql, …).

.PARAMETER ServerInstance
    Nombre de tu servidor Azure SQL (p.ej. myserver.database.windows.net).

.PARAMETER Database
    Nombre de la base de datos en Azure SQL.

.PARAMETER Username
    Usuario SQL (opcional si usas autenticación integrada).

.PARAMETER Password
    Contraseña SQL (omitir si usas autenticación integrada).

.PARAMETER IdentityInsertTable
    Nombre completo de la tabla para la que se activará IDENTITY_INSERT
    (formato: Esquema.Tabla). Si no se especifica, no se usa SET IDENTITY_INSERT.

.PARAMETER LogSuccessFile
    Ruta al archivo de log de éxitos (por defecto: .\success.log).

.PARAMETER LogErrorFile
    Ruta al archivo de log de errores (por defecto: .\error.log).
#>
param(
    [Parameter(Mandatory)]
    [string]$ScriptsFolder,

    [Parameter(Mandatory)]
    [string]$ServerInstance,

    [Parameter(Mandatory)]
    [string]$Database,

    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter(Mandatory)]
    [string]$Password,
    [string]$LogSuccessFile = ".\success.log",
    [string]$LogErrorFile   = ".\error.log"
)

# Prepara logs (sobrescribe si existen)
"" | Out-File -Encoding utf8 -FilePath $LogSuccessFile
"" | Out-File -Encoding utf8 -FilePath $LogErrorFile

# Función helper para Invoke-Sqlcmd con o sin credenciales
function Run-Script {
    param(
        [string]$FilePath
    )
    if ($Username -and $Password) {
        Invoke-Sqlcmd `
          -ServerInstance $ServerInstance `
          -Database       $Database `
          -Username       $Username `
          -Password       $Password `
          -InputFile      $FilePath `
          -ErrorAction    Stop
    }
    else {
        Invoke-Sqlcmd `
          -ServerInstance $ServerInstance `
          -Database       $Database `
          -InputFile      $FilePath `
          -ErrorAction    Stop
    }
}

# Obtiene la lista de scripts ordenados por nombre
$files       = Get-ChildItem -Path $ScriptsFolder -Filter '*.sql' | Sort-Object Name
$totalFiles  = $files.Count
$fileIndex   = 0

foreach ($fileInfo in $files) {
    $fileIndex++
    $filePath  = $fileInfo.FullName
    $fileName  = $fileInfo.Name
    $tsStart   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    # Cuenta líneas (streaming)
    $lineCount = (Get-Content $filePath -ReadCount 4096 | Measure-Object -Line).Lines

    # Registra inicio en ambos logs
    $startEntry = "[$tsStart] START: #$fileIndex/$totalFiles '$fileName' -> $lineCount lines"
    Add-Content -Path $LogSuccessFile -Value $startEntry
    Add-Content -Path $LogErrorFile   -Value $startEntry

    # Envolvimiento en transacción + IDENTITY_INSERT
    try {
        $content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::Unicode)

        # Construye envoltura
        $wrapperLines = @()
        $wrapperLines += "BEGIN TRANSACTION;"
        $wrapperLines += $content
        $wrapperLines += "COMMIT;"

        # Guarda de nuevo
        [System.IO.File]::WriteAllLines(
            $filePath,
            $wrapperLines,
            [System.Text.Encoding]::Unicode
        )

        # Ejecuta el script
        Run-Script -FilePath $filePath

        $tsSucc = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $succEntry = "[$tsSucc] SUCCESS: '$fileName'"
        Add-Content -Path $LogSuccessFile -Value $succEntry
    }
    catch {
        $tsErr  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $msg    = $_.Exception.Message.Trim()
        $failEntry = "[$tsErr] ERROR: '$fileName' -> $msg"
        Add-Content -Path $LogErrorFile -Value $failEntry
    }

    # Actualiza barra de progreso
    $pct = [int](($fileIndex/$totalFiles)*100)
    Write-Progress `
      -Activity "Procesando scripts SQL" `
      -Status   "($fileIndex/$totalFiles) $fileName" `
      -PercentComplete $pct
}

Write-Host "Finalizado: $fileIndex de $totalFiles archivos procesados."
