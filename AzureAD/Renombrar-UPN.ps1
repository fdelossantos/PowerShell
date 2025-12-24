# Requisitos (referencia):
# - Microsoft Graph PowerShell
# - Permisos típicos para actualizar UPN: User.ReadWrite.All (y, según el caso, Directory.ReadWrite.All)
# - Se asume que ya se está conectado (Connect-MgGraph) y con el perfil/permiso adecuado.

# =========================
# Parámetros 
# =========================
$OldSuffix = "@domain.onmicrosoft.com"
$NewSuffix = "@domain.com.uy"

# EXACTAMENTE 2 usuarios a excluir (UPN actuales)
$ExcludedUPNs = @(
    "jp@domain.onmicrosoft.com",
    "fd@domain.onmicrosoft.com"
)

# Log
$LogPath = Join-Path $PSScriptRoot ("UPNChangeLog-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Write-Log {
    param(
        [Parameter(Mandatory)] [string] $Message
    )
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $LogPath -Append -Encoding utf8
    Write-Host $line
}

Write-Log "Inicio. OldSuffix=$OldSuffix NewSuffix=$NewSuffix"
Write-Log "Exclusiones: $($ExcludedUPNs -join ', ')"

# =========================
# Obtención de usuarios
# =========================
# Solo Member (excluye Guest). Trae lo mínimo necesario.
$Users = Get-MgUser -All -Filter "userType eq 'Member'" -Property "id,displayName,userPrincipalName" |
    Select-Object Id, DisplayName, UserPrincipalName

Write-Log ("Usuarios Member encontrados: {0}" -f $Users.Count)

# =========================
# Proceso
# =========================
$CountUpdated = 0
$CountSkipped = 0
$CountErrors  = 0

foreach ($User in $Users) {

    $CurrentUPN = $User.UserPrincipalName

    if ([string]::IsNullOrWhiteSpace($CurrentUPN)) {
        Write-Log ("SKIP (UPN vacío): {0} [{1}]" -f $User.DisplayName, $User.Id)
        $CountSkipped++
        continue
    }

    if ($ExcludedUPNs -contains $CurrentUPN) {
        Write-Log ("SKIP (excluido): {0} ({1})" -f $User.DisplayName, $CurrentUPN)
        $CountSkipped++
        continue
    }

    if (-not $CurrentUPN.EndsWith($OldSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Log ("SKIP (no coincide sufijo): {0} ({1})" -f $User.DisplayName, $CurrentUPN)
        $CountSkipped++
        continue
    }

    $NewUPN = $CurrentUPN.Substring(0, $CurrentUPN.Length - $OldSuffix.Length) + $NewSuffix

    if ($NewUPN -eq $CurrentUPN) {
        Write-Log ("SKIP (sin cambios): {0} ({1})" -f $User.DisplayName, $CurrentUPN)
        $CountSkipped++
        continue
    }

    try {
        Update-MgUser -UserId $User.Id -UserPrincipalName $NewUPN

        Write-Log ("OK: {0}  {1} -> {2}" -f $User.DisplayName, $CurrentUPN, $NewUPN)
        $CountUpdated++
    }
    catch {
        Write-Log ("ERROR: {0} ({1}) -> {2}. Detalle: {3}" -f $User.DisplayName, $CurrentUPN, $NewUPN, $_.Exception.Message)
        $CountErrors++
    }
}

Write-Log "Fin. Updated=$CountUpdated Skipped=$CountSkipped Errors=$CountErrors"
Write-Log ("Log guardado en: {0}" -f $LogPath)
