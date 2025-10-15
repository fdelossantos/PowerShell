param (
    [Parameter(Mandatory)]
    [String]$DominioOriginal, 
    [Parameter(Mandatory)]
    [String]$NuevoDominio,
    [Parameter(Mandatory)]
    [String]$SearchBase
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

# Timestamps y rutas de salida
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$logPath = Join-Path -Path (Get-Location) -ChildPath ("log-{0}.txt" -f $ts)
$csvPath = Join-Path -Path (Get-Location) -ChildPath ("result-{0}.csv" -f $ts)

# Inicializar CSV con encabezados
"SamAccountName;OldUPN;NewUPN" | Out-File -FilePath $csvPath -Encoding UTF8

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logPath -Value $line
    Write-Host $line
}

Write-Log "Inicio. DominioOriginal=$DominioOriginal NuevoDominio=$NuevoDominio SearchBase=$SearchBase"

# Obtener todos los usuarios cuyo UPN termine en el dominio original
$parametros = @{
    Filter     = "UserPrincipalName -like '*@$DominioOriginal'"
    Properties = "UserPrincipalName","SamAccountName"
    SearchBase = $SearchBase
}

try {
    $usuarios = Get-ADUser @parametros
    Write-Log ("Usuarios encontrados: {0}" -f ($usuarios | Measure-Object).Count)
} catch {
    Write-Log ("ERROR obteniendo usuarios: {0}" -f $_.Exception.Message)
    throw
}

# Iterar a través de los usuarios y cambiar el UPN
foreach ($usuario in $usuarios) {
    $oldUPN = $usuario.UserPrincipalName
    # Asegura reemplazo solo al final del UPN (dominio)
    $newUPN = $oldUPN -replace ([regex]::Escape($DominioOriginal) + '$'), $NuevoDominio

    Write-Log ("Cambiar UPN de {0} de {1} a {2}" -f $usuario.SamAccountName, $oldUPN, $newUPN)

    try {
        Set-ADUser -Identity $usuario.SamAccountName -UserPrincipalName $newUPN

        # Registrar acción en CSV
        [pscustomobject]@{
            SamAccountName = $usuario.SamAccountName
            OldUPN         = $oldUPN
            NewUPN         = $newUPN
        } | Export-Csv -Path $csvPath -NoTypeInformation -Append -Delimiter ";"
    } catch {
        Write-Log ("ERROR cambiando UPN de {0}: {1}" -f $usuario.SamAccountName, $_.Exception.Message)

        # Registrar igualmente la acción intentada en el CSV
        [pscustomobject]@{
            SamAccountName = $usuario.SamAccountName
            OldUPN         = $oldUPN
            NewUPN         = $newUPN
        } | Export-Csv -Path $csvPath -NoTypeInformation -Append -Delimiter ";"
    }
}

Write-Log "Proceso completado. Log: $logPath CSV: $csvPath"
