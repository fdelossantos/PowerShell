<# 
.SYNOPSIS
  Exporta usuarios y grupos asignados a Enterprise Applications (Service Principals) de Entra ID.

.DESCRIPTION
  - Entrada: archivo de texto con una Enterprise App por línea.
      * Mejor: Service Principal Object ID (GUID).
      * También acepta: Application (client) ID (GUID) o DisplayName exacto (si es único).
  - Salida: CSV (UTF-8 con BOM) con columnas:
      "Nombre de Enterprise Application","UPN de usuario","Display Name de grupo"

.PARAMETER InputFilePath
  Ruta del archivo de texto con la lista de Enterprise Apps.

.PARAMETER OutputCsvPath
  Ruta del CSV de salida.

.EJEMPLO
  .\Export-EA-Assignments.ps1 -InputFilePath .\enterpriseApps.txt -OutputCsvPath .\EA_Asignaciones.csv

#>

param(
  [Parameter(Mandatory = $true)]
  [string]$InputFilePath,

  [Parameter(Mandatory = $true)]
  [string]$OutputCsvPath
)

# --- Comprobaciones iniciales ---
if (-not (Test-Path -Path $InputFilePath)) {
  throw "No se encontró el archivo de entrada: $InputFilePath"
}

# Carga de Microsoft Graph
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
  Write-Host "Instalando módulo Microsoft.Graph..." -ForegroundColor Yellow
  Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
#Import-Module Microsoft.Graph

# Conexión a Graph si hace falta
try {
  $ctx = Get-MgContext
  if (-not $ctx) {
    Connect-MgGraph -Scopes "Directory.Read.All","Application.Read.All","AppRoleAssignment.ReadWrite.All"
  }
} catch {
  Connect-MgGraph -Scopes "Directory.Read.All","Application.Read.All","AppRoleAssignment.ReadWrite.All"
}

$ctx = Get-MgContext

# --- Función: resolver una Enterprise App (Service Principal) a partir de un identificador ---
function Resolve-ServicePrincipal {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Identifier
  )
  # Limpieza básica
  $id = $Identifier.Trim()
  if ([string]::IsNullOrWhiteSpace($id)) { return $null }

  # Si empieza con # es comentario
  if ($id.StartsWith('#')) { return $null }

  # ¿Es GUID?
  $asGuid = [ref]([guid]::Empty)
  $isGuid = [guid]::TryParse($id, $asGuid)

  # 1) Intentar como Object ID (ServicePrincipalId)
  if ($isGuid) {
    $sp = $null
    try {
      $sp = Get-MgServicePrincipal -ServicePrincipalId $id -ErrorAction Stop
      if ($sp) { return $sp }
    } catch { 
      # Error
      Write-Host $Error[0].Exception.Message -ForegroundColor DarkGray
      return $null
    }
  }

#   # 2) Intentar como Application (client) ID
#   if ($isGuid -and -not $sp) {
#     $candidates = Get-MgServicePrincipal -Filter "appId eq '$id'" -ConsistencyLevel eventual -All
#     if ($candidates.Count -eq 1) { return $candidates[0] }
#     elseif ($candidates.Count -gt 1) {
#       Write-Warning "El Application ID '$id' devuelve múltiples Service Principals. Especifique el Object ID."
#       return $null
#     }
#   }

#   # 3) Intentar como DisplayName exacto (si es único)
#   $safeName = $id.Replace("'","''")
#   $byName = Get-MgServicePrincipal -Filter "displayName eq '$safeName'" -ConsistencyLevel eventual -All
#   if ($byName.Count -eq 1) { return $byName[0] }
#   elseif ($byName.Count -gt 1) {
#     Write-Warning "El nombre '$id' no es único. Use el Object ID del Service Principal."
#   } else {
#     Write-Warning "No se encontró Service Principal para '$id'."
#   }
#   return $null
}

# --- Función: exportar CSV en UTF-8 con BOM (para Excel/PS 5.1) ---
function Export-CsvUtf8Bom {
  param(
    [Parameter(Mandatory=$true)] [System.Collections.IEnumerable]$Data,
    [Parameter(Mandatory=$true)] [string]$Path
  )
  $lines = $Data | ConvertTo-Csv -NoTypeInformation -Delimiter ";"
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllLines($Path, $lines, $utf8Bom)
}

# --- Proceso principal ---
$results = New-Object System.Collections.Generic.List[object]

# Leer entradas
$identifiers = Get-Content -Path $InputFilePath -ErrorAction Stop

foreach ($identifier in $identifiers) {
  $sp = Resolve-ServicePrincipal -Identifier $identifier
  if (-not $sp) { continue }

  Write-Host "Procesando: $($sp.DisplayName)  (Object ID: $($sp.Id))" -ForegroundColor Cyan

  # Obtener asignaciones (usuarios/grupos) de la Enterprise App
  # /servicePrincipals/{id}/appRoleAssignedTo
  try {
    $assignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All
  } catch {
    Write-Warning "No se pudieron leer asignaciones para '$($sp.DisplayName)': $($_.Exception.Message)"
    continue
  }

  if (-not $assignments -or $assignments.Count -eq 0) {
    # Sin filas si no hay asignaciones (puedes cambiar este bloque si quieres crear una fila vacía)
    continue
  }

  foreach ($a in $assignments) {
    switch ($a.PrincipalType) {
      'User' {
        # Necesitamos el UPN
        $upn = $null
        try {
          $u = Get-MgUser -UserId $a.PrincipalId -Property userPrincipalName -ErrorAction Stop
          $upn = $u.UserPrincipalName
        } catch {
          Write-Warning "No se pudo resolver UPN para UserId $($a.PrincipalId)."
        }

        $results.Add([pscustomobject]@{
          'Nombre de Enterprise Application' = $sp.DisplayName
          'UPN de usuario'                   = $upn
          'Display Name de grupo'            = ''
        })
      }
      'Group' {
        # Ya tenemos el nombre del grupo en PrincipalDisplayName
        $results.Add([pscustomobject]@{
          'Nombre de Enterprise Application' = $sp.DisplayName
          'UPN de usuario'                   = ''
          'Display Name de grupo'            = $a.PrincipalDisplayName
        })
      }
      Default {
        # Ignorar otros tipos (ServicePrincipal, etc.) porque el requerimiento pide solo usuarios y grupos
        continue
      }
    }
  }
}

# Exportar CSV (UTF-8 con BOM)
if ($results.Count -gt 0) {
  $dir = Split-Path -Path $OutputCsvPath -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Export-CsvUtf8Bom -Data $results -Path $OutputCsvPath
  Write-Host "Listo. CSV generado en: $OutputCsvPath" -ForegroundColor Green
} else {
  Write-Host "No se generaron filas (¿no había asignaciones o no se resolvieron las apps?)." -ForegroundColor Yellow
}
