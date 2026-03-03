# gam print resources allfields > gws_resources.csv
# gam print buildings allfields > gws_buildings.csv
Import-Module ExchangeOnlineManagement

# =========================
# CONFIG (hardcoded)
# =========================
$CompanyDomain = "domain.com"

$gwsResourcesPath = ".\gws_resources.csv"
$gwsBuildingsPath = ".\gws_buildings.csv"

if (-not (Test-Path $gwsResourcesPath)) { throw "No existe $gwsResourcesPath" }
if (-not (Test-Path $gwsBuildingsPath)) { throw "No existe $gwsBuildingsPath" }

$resources = Import-Csv $gwsResourcesPath
$buildings = Import-Csv $gwsBuildingsPath

# =========================
# Conexión EXO
# =========================
Connect-ExchangeOnline -ShowBanner:$false

# =========================
# Buildings: buildingId -> buildingName
# =========================
$buildingById = @{}
foreach ($b in $buildings) {
  $id = $b.buildingId
  if ([string]::IsNullOrWhiteSpace($id)) { continue }

  $name = $b.buildingName
  if ([string]::IsNullOrWhiteSpace($name)) { $name = $b.name }

  if (-not [string]::IsNullOrWhiteSpace($name)) {
    $buildingById[$id] = $name
  }
}

# =========================
# Helpers
# =========================
function Convert-ToAscii {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

  $norm = $Text.Normalize([Text.NormalizationForm]::FormD)
  $filtered = -join ($norm.ToCharArray() | Where-Object {
    [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'
  })
  return $filtered
}

function New-AliasFromResourceName {
  param([string]$ResourceName)

  if ([string]::IsNullOrWhiteSpace($ResourceName)) { return $null }

  $base = Convert-ToAscii $ResourceName
  $base = $base.ToLowerInvariant().Trim()

  # separadores típicos -> '-'
  $base = $base -replace '[\s/\\|,;:+]+', '-'

  # Permitido: a-z 0-9 . _ -
  $alias = ($base -replace '[^a-z0-9._-]', '-')

  # Limpieza
  $alias = $alias -replace '-{2,}', '-'
  $alias = $alias.Trim('-','.')

  if ([string]::IsNullOrWhiteSpace($alias)) { $alias = "room" }

  # Longitud práctica
  if ($alias.Length -gt 64) {
    $alias = $alias.Substring(0, 64).Trim('-','.')
    if ([string]::IsNullOrWhiteSpace($alias)) { $alias = "room" }
  }

  return $alias
}

function Try-ParseInt {
  param([string]$Value)
  $out = 0
  if ([int]::TryParse($Value, [ref]$out)) { return $out }
  return $null
}

function Split-Tags {
  param([string]$Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }

  $clean = $Raw -replace '[\[\]\{\}"“”]', ''
  $parts = $clean -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

  $uniq = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $parts) { [void]$uniq.Add($p) }

  return $uniq.ToArray()
}

function Test-RecipientExistsByAlias {
  param([string]$Alias)

  if ([string]::IsNullOrWhiteSpace($Alias)) { return $false }

  try {
    $r = Get-EXORecipient -Filter "Alias -eq '$Alias'" -ErrorAction Stop
    return ($null -ne $r)
  } catch {
    return $false
  }
}

function Test-RecipientExistsBySmtp {
  param([string]$SmtpAddress)

  if ([string]::IsNullOrWhiteSpace($SmtpAddress)) { return $false }

  # 1) intento directo (funciona si coincide con Identity/Primary)
  try {
    $r = Get-EXORecipient -Identity $SmtpAddress -ErrorAction Stop
    if ($r) { return $true }
  } catch {}

  # 2) buscar en proxies (EmailAddresses incluye SMTP: y smtp:)
  # Nota: filtro exacto suele funcionar mejor que -like
  $needle = "SMTP:$SmtpAddress"
  try {
    $r2 = Get-EXORecipient -Filter "EmailAddresses -eq '$needle'" -ErrorAction Stop
    return ($null -ne $r2)
  } catch {
    return $false
  }
}

function Get-UniqueAliasAndSmtp {
  param(
    [string]$BaseAlias,
    [string]$Domain
  )

  if ([string]::IsNullOrWhiteSpace($BaseAlias)) { $BaseAlias = "room" }

  $aliasCandidate = $BaseAlias
  $i = 0

  while ($true) {
    $smtpCandidate = "$aliasCandidate@$Domain"

    $aliasInUse = Test-RecipientExistsByAlias -Alias $aliasCandidate
    $smtpInUse  = Test-RecipientExistsBySmtp  -SmtpAddress $smtpCandidate

    if (-not $aliasInUse -and -not $smtpInUse) {
      return [pscustomobject]@{
        Alias = $aliasCandidate
        Smtp  = $smtpCandidate
      }
    }

    $i++
    if ($i -gt 200) { throw "No pude resolver alias/SMTP únicos para base '$BaseAlias'." }

    $suffix = "-$i"
    $trimLen = [Math]::Max(1, 64 - $suffix.Length)
    $aliasCandidate = ($BaseAlias.Substring(0, [Math]::Min($BaseAlias.Length, $trimLen))) + $suffix
    $aliasCandidate = $aliasCandidate.Trim('-','.')
    if ([string]::IsNullOrWhiteSpace($aliasCandidate)) { $aliasCandidate = "room$suffix" }
  }
}

# =========================
# Main loop
# =========================
foreach ($r in $resources) {

  # Column fallbacks (GAM puede variar headers)
  $resourceName = $r.resourceName
  if ([string]::IsNullOrWhiteSpace($resourceName)) { $resourceName = $r.name }

  $capacityRaw  = $r.capacity
  $buildingId   = $r.buildingId
  $floorName    = $r.floorName
  $floorSection = $r.floorSection
  if ([string]::IsNullOrWhiteSpace($floorSection)) { $floorSection = $r.floorsection }

  $featuresRaw  = $r.featureInstances
  if ([string]::IsNullOrWhiteSpace($featuresRaw)) { $featuresRaw = $r.features }

  # Validación mínima: sin nombre no hay forma razonable de generar correo/alias
  if ([string]::IsNullOrWhiteSpace($resourceName)) {
    Write-Warning "SKIP: recurso sin resourceName/name (no puedo generar alias/SMTP)."
    continue
  }

  # Building name
  $buildingName = $null
  if (-not [string]::IsNullOrWhiteSpace($buildingId) -and $buildingById.ContainsKey($buildingId)) {
    $buildingName = $buildingById[$buildingId]
  } else {
    $buildingName = $r.building
  }

  # Alias + SMTP desde resourceName (sin usar resourceEmail de Google)
  $baseAlias = New-AliasFromResourceName -ResourceName $resourceName
  $unique = Get-UniqueAliasAndSmtp -BaseAlias $baseAlias -Domain $CompanyDomain

  $alias = $unique.Alias
  $smtp  = $unique.Smtp

  # Si por alguna razón ya existe el smtp (carrera, datos raros), omitimos
  if (Test-RecipientExistsBySmtp -SmtpAddress $smtp) {
    Write-Host "EXISTS (SMTP): $smtp. Se omite."
    continue
  }

  # Crear Room Mailbox
  try {
    Write-Host "CREATE: '$resourceName' -> $smtp (alias=$alias)"

    New-Mailbox -Room `
      -Name $resourceName `
      -DisplayName $resourceName `
      -Alias $alias `
      -PrimarySmtpAddress $smtp `
      -ErrorAction Stop

  } catch {
    Write-Error "ERROR creando mailbox para '$resourceName' ($smtp). $($_.Exception.Message)"
    continue
  }

  # Set-Place (metadata) usando Identity = SMTP generado
  try {
    $cap = Try-ParseInt $capacityRaw
    $floorInt = Try-ParseInt $floorName

    $tags = @()
    if (-not [string]::IsNullOrWhiteSpace($floorSection)) { $tags += $floorSection }
    $tags += (Split-Tags $featuresRaw)
    $tags = $tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $setPlaceParams = @{
      Identity = $smtp
    }

    if ($cap -ne $null) { $setPlaceParams["Capacity"] = $cap }
    if (-not [string]::IsNullOrWhiteSpace($buildingName)) { $setPlaceParams["Building"] = $buildingName }

    if ($floorInt -ne $null) { $setPlaceParams["Floor"] = $floorInt }
    if (-not [string]::IsNullOrWhiteSpace($floorName)) { $setPlaceParams["FloorLabel"] = $floorName }

    if ($tags.Count -gt 0) { $setPlaceParams["Tags"] = $tags }

    if ($setPlaceParams.Keys.Count -gt 1) {
      Set-Place @setPlaceParams -ErrorAction Stop
    }

  } catch {
    Write-Warning "WARN Set-Place para $($smtp): $($_.Exception.Message)"
  }

  # CalendarProcessing (AutoAccept)
  try {
    Set-CalendarProcessing -Identity $smtp `
      -AutomateProcessing AutoAccept `
      -AddOrganizerToSubject $true `
      -DeleteComments $false `
      -DeleteSubject $false `
      -RemovePrivateProperty $false `
      -ErrorAction Stop
  } catch {
    Write-Warning "WARN Set-CalendarProcessing para $($smtp): $($_.Exception.Message)"
  }
}

Disconnect-ExchangeOnline -Confirm:$false
Write-Host "DONE."