# ==========================
# CONFIGURACIÓN
# ==========================
$configs = Get-Content -Raw ".\Get-ReportMFAbyCountry.configs.json" | ConvertFrom-Json -ErrorAction Stop

$TenantId = $configs.TenantId
$ClientId=$configs.ClientId
$CertThumbprint=$configs.CertThumbprint
$MfaGroupName = $configs.MfaGroupName
$GeoPrefix = $configs.GeoPrefix
$DaysBack = $configs.DaysBack

$OutputPath      = ".\$(Get-date -Format 'yyyy-MM-dd hhmm') Reporte-Usuarios-GEO-MFA-Mailbox.csv"

# ==========================
# CONEXIÓN A MICROSOFT GRAPH
# ==========================

# Import-Module Microsoft.Graph

# Perfil v1.0
# Select-MgProfile -Name "v1.0"

# App-only con certificado (recomendado)
Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertThumbprint

# Si quisieras hacerlo delegando, podrías usar:
# Connect-MgGraph -Scopes "AuditLog.Read.All","Directory.Read.All"

# ==========================
# OBTENER SIGN-INS ÚLTIMOS 60 DÍAS
# ==========================

$startDate   = (Get-Date).AddDays($DaysBack).ToUniversalTime()
$startFilter = $startDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

$filter = "createdDateTime ge $startFilter"

Write-Host "Obteniendo sign-ins desde $startFilter..."

# Ten en cuenta la retención real de logs según la licencia (puede ser menor a 60 días)
$allSignIns = Get-MgAuditLogSignIn -Filter $filter -All

# Solo usuarios con UserId y UPN
$allSignIns = $allSignIns | Where-Object { $_.UserId -ne $null -and $_.UserPrincipalName -ne $null -and $_.UserPrincipalName -ne "" }

# ==========================
# ÚLTIMO SIGN-IN POR USUARIO
# ==========================

$grouped = $allSignIns | Group-Object -Property UserPrincipalName

$usersFromSignins = @()

foreach ($g in $grouped) {
    $latest = $g.Group | Sort-Object -Property CreatedDateTime -Descending | Select-Object -First 1

    $userInfo = [PSCustomObject]@{
        UserId            = $latest.UserId
        DisplayName       = $latest.UserDisplayName
        UserPrincipalName = $latest.UserPrincipalName.ToLower()
    }

    $usersFromSignins += $userInfo
}

Write-Host "Usuarios con al menos un inicio de sesión en la ventana: $($usersFromSignins.Count)"

# ==========================
# GRUPOS MFA Y GEO
# ==========================

Write-Host "Obteniendo grupo MFA '$MfaGroupName'..."
$mfaGroup = Get-MgGroup -Filter "displayName eq '$MfaGroupName'"

if (-not $mfaGroup) {
    throw "No se encontró el grupo '$MfaGroupName'."
}

# Si hubiese más de uno, toma el primero
$mfaGroup = $mfaGroup | Select-Object -First 1

Write-Host "Grupo MFA encontrado: $($mfaGroup.Id) - $($mfaGroup.DisplayName)"

Write-Host "Obteniendo grupos con prefijo '$GeoPrefix'..."
$geoGroups = Get-MgGroup -Filter "startswith(displayName,'$GeoPrefix')" -All

if (-not $geoGroups) {
    Write-Host "Advertencia: no se encontraron grupos GEO con ese prefijo."
}

# ==========================
# MIEMBROS DEL GRUPO MFA
# ==========================

Write-Host "Obteniendo miembros del grupo MFA..."
$mfaMembers = Get-MgGroupMember -GroupId $mfaGroup.Id -All

$mfaMemberIds = [System.Collections.Generic.HashSet[string]]::new()

foreach ($m in $mfaMembers) {
    [void]$mfaMemberIds.Add($m.Id)
}

# ==========================
# MIEMBROS DE GRUPOS GEO
# ==========================

$geoMembership = @{}

foreach ($geo in $geoGroups) {
    Write-Host "Cargando miembros de GEO '$($geo.DisplayName)'..."
    $members = Get-MgGroupMember -GroupId $geo.Id -All

    foreach ($m in $members) {
        if (-not $geoMembership.ContainsKey($m.Id)) {
            $geoMembership[$m.Id] = New-Object System.Collections.Generic.List[string]
        }

        $geoMembership[$m.Id].Add($geo.DisplayName)
    }
}

# ==========================
# CONEXIÓN A EXCHANGE ONLINE
# ==========================

Import-Module ExchangeOnlineManagement

# Opción 1: App-only con la misma App Registration (necesita Exchange.ManageAsApp y Application Access Policy)
Connect-ExchangeOnline -AppId $ClientId -CertificateThumbprint $CertThumbprint -Organization "vpccom.onmicrosoft.com" -ShowBanner:$false

# Opción 2: Delegado con cuenta administrativa (más simple si ya la usas)
# Connect-ExchangeOnline -ShowBanner:$false

# ==========================
# CONSTRUCCIÓN DEL REPORTE
# ==========================

$results = @()

foreach ($u in $usersFromSignins) {

    # ¿Está en el grupo MFA?
    $isMfaUser = $mfaMemberIds.Contains($u.UserId)

    # ¿En qué GEO(s) está?
    if ($geoMembership.ContainsKey($u.UserId)) {
        $geoNames = $geoMembership[$u.UserId] | Sort-Object -Unique
        $geoName  = $geoNames -join ", "
    }
    else {
        $geoName  = "Sin GEO"
    }

    # Tipo de buzón en Exchange Online
    $mailboxType = "Sin buzón"

    $mbx = Get-Mailbox -Identity $u.UserPrincipalName -ErrorAction SilentlyContinue

    if ($mbx) {
        switch ($mbx.RecipientTypeDetails.ToString()) {
            "UserMailbox"   { $mailboxType = "User" }
            "SharedMailbox" { $mailboxType = "Shared" }
            "RoomMailbox"   { $mailboxType = "Room" }
            default         { $mailboxType = $mbx.RecipientTypeDetails.ToString() }
        }
    }

    $results += [PSCustomObject]@{
        DisplayName       = $u.DisplayName
        UserPrincipalName = $u.UserPrincipalName
        GeoGroup          = $geoName
        InMfaGroup        = if ($isMfaUser) { "Sí" } else { "No" }
        MailboxType       = $mailboxType
    }
}

# ==========================
# EXPORTAR A CSV
# ==========================

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Delimiter ';' -Encoding UTF8

Write-Host "Reporte generado en: $OutputPath"
