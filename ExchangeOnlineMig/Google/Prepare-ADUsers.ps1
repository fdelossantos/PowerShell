param(
  [Parameter(Mandatory=$true)] [string]$InputFile,
  [Parameter(Mandatory=$true)] [string]$AdServer,
  [Parameter(Mandatory=$true)] [string]$AppId,
  [Parameter(Mandatory=$true)] [string]$Organization,
  [Parameter(Mandatory=$true)] [string]$CertThumbprint,
  [string]$OutputNotFoundFile
)

# Derivar archivo de salida si no se especifica
if (-not $OutputNotFoundFile -or [string]::IsNullOrWhiteSpace($OutputNotFoundFile)) {
  $dir = Split-Path -Path $InputFile -Parent
  $base = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputNotFoundFile = Join-Path $dir "$base-NotFound-$stamp.txt"
}

# Cargar entradas
$emails = Get-Content -Path $InputFile | Where-Object { $_ } | ForEach-Object { $_.Trim() }

# Conexión a EXO (App Registration + Cert)
Connect-ExchangeOnline -AppId $AppId -Organization $Organization -CertificateThumbprint $CertThumbprint -ShowBanner:$false

$total = $emails.Count
$index = 0
$notFound = @()

foreach ($email in $emails) {
  $index = $index + 1
  Write-Progress -Activity "Procesando usuarios" -Status "Email: $($email) | Procesados: $index/$total | No encontrados: $($notFound.Count)" -PercentComplete ([int](($index / $total) * 100))

  # Buscar mailbox según $email y en caso que no exista, seguir adelante
  Write-Host "Verificando mailbox para $email ..."
  $buzon = $null
  $buzon = Get-Mailbox -Identity $email -ErrorAction SilentlyContinue | Out-Null
  if ($buzon) {
    # Ya tiene mailbox, saltar
    Write-Host "  -> Ya tiene mailbox. Saltando..."
    continue
  }

  Write-Host "  -> No tiene mailbox. Preparando AD..."
  # Buscar usuario por UPN
  $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$email'" -Server $AdServer -Properties mail,proxyAddresses,targetAddress,mailNickname
  if (-not $adUser) {
    $notFound += $email
    continue
  }

  # mail si está vacío
  if ([string]::IsNullOrWhiteSpace($adUser.mail)) {
    Set-ADUser -Identity $adUser.DistinguishedName -Replace @{ mail = $email } -Server $AdServer
  }

  # Construir variantes de dominio
  $parts = $email.Split('@')
  $local = $parts[0]
  $domain = $parts[1]
  $o365 = "$local@o365.$domain"
  $gsuite = "$local@gsuite.$domain"

  # proxyAddresses: primaria SMTP:$email y secundaria smtp:$o365 (preservando secundarias actuales)
  $current = @()
  if ($adUser.proxyAddresses) { $current = @($adUser.proxyAddresses) }
  $kept = @()
  foreach ($a in $current) {
    if ($a -notlike 'SMTP:*') { $kept += $a }
  }
  # Evitar duplicados simplonamente
  $primary = "SMTP:$email"
  $secondary = "smtp:$o365"
  $final = @()
  foreach ($a in $kept) { if ($final -notcontains $a) { $final += $a } }
  if ($final -notcontains $primary) { $final += $primary }
  if ($final -notcontains $secondary) { $final += $secondary }
  Set-ADUser -Identity $adUser.DistinguishedName -Replace @{ proxyAddresses = $final } -Server $AdServer

  # targetAddress: SMTP:usuario@gsuite.dominio
  Set-ADUser -Identity $adUser.DistinguishedName -Replace @{ targetAddress = "SMTP:$gsuite" } -Server $AdServer

  # mailNickname = email con @ -> _
  $nick = $email -replace '@','_'
  Set-ADUser -Identity $adUser.DistinguishedName -Replace @{ mailNickname = $nick } -Server $AdServer


}

Write-Progress -Activity "Procesando usuarios" -Completed

# Guardar no encontrados y mostrar resumen
if ($notFound.Count -gt 0) {
  $notFound | Set-Content -Path $OutputNotFoundFile -Encoding UTF8
  Write-Host "No encontrados: $($notFound.Count). Archivo: $OutputNotFoundFile"
} else {
  Write-Host "Todos los emails tuvieron coincidencia en AD."
}

Disconnect-ExchangeOnline -Confirm:$false
