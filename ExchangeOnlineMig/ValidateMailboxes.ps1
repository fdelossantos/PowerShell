# Requiere:
# - $buzonesgoogle ya cargado (columna primaryEmail)
$buzonesgoogle = Import-Csv .\20260204BuzonesGoogle.csv
# - Sesión conectada a Exchange Online
# - Microsoft Graph ya conectado

# -------------------------
# Config: orden y mapeo de SKUs permitidos
# -------------------------
$SkuOrder = @(
    @{ SkuPartNumber = 'SPE_F1';                      SkuId = '66b55226-6b4f-492c-910c-a3b7a3c9d993' }
    @{ SkuPartNumber = 'O365_BUSINESS_PREMIUM';       SkuId = 'f245ecc8-75af-4f8e-b61f-27d8114de5f3' }
    @{ SkuPartNumber = 'SPB';                         SkuId = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46' }
    @{ SkuPartNumber = 'Microsoft_365_E3_(no_Teams)'; SkuId = 'dcf0408c-aaec-446c-afd4-43e3683943ea' }
    @{ SkuPartNumber = 'SPE_E3';                      SkuId = '05e9a617-0261-4cee-bb44-138d3ef5d965' }
    @{ SkuPartNumber = 'Microsoft_365_E5_(no_Teams)'; SkuId = '18a4bd3f-0b5b-4887-b04f-61dd0ee15f5e' }
    @{ SkuPartNumber = 'EXCHANGESTANDARD';            SkuId = '4b9405b0-7788-4568-add1-99614e613b69' }
    @{ SkuPartNumber = 'EXCHANGEENTERPRISE';          SkuId = '19ec0d23-8335-4cbd-94ac-6050e30712fa' }
    @{ SkuPartNumber = 'EXCHANGEARCHIVE_ADDON';       SkuId = 'ee02fd1b-340e-4a4b-b355-4a514e4c8943' }
)

$SkuIdToPart = @{}
$SkuPartToIndex = @{}
for ($i = 0; $i -lt $SkuOrder.Count; $i++) {
    $SkuIdToPart[$SkuOrder[$i].SkuId] = $SkuOrder[$i].SkuPartNumber
    $SkuPartToIndex[$SkuOrder[$i].SkuPartNumber] = $i
}

# -------------------------
# Helpers
# -------------------------
function Convert-SizeToMB {
    param($Size)

    if (-not $Size) { return $null }

    $bytes = $null

    try {
        if ($Size.PSObject.Methods.Name -contains 'ToBytes') {
            $bytes = [int64]$Size.ToBytes()
        }
        elseif ($Size.PSObject.Properties.Name -contains 'Value') {
            $v = $Size.Value
            if ($v -and ($v.PSObject.Methods.Name -contains 'ToBytes')) {
                $bytes = [int64]$v.ToBytes()
            }
        }
    }
    catch {
        $bytes = $null
    }

    if ($bytes -eq $null) {
        $s = [string]$Size
        if ($s -match '\(([\d\.,]+)\sbytes\)') {
            $raw = $matches[1]
            $digitsOnly = ($raw -replace '[^\d]', '')
            if ($digitsOnly) {
                $bytes = [int64]$digitsOnly
            }
        }
    }

    if ($bytes -eq $null) { return $null }

    [math]::Round($bytes / 1MB, 2)
}

function Get-OrderedLicenses {
    param($AssignedLicenses)

    $lic1 = ''
    $lic2 = ''

    if (-not $AssignedLicenses) {
        return @($lic1, $lic2)
    }

    $assignedSkuIds = @()
    foreach ($al in $AssignedLicenses) {
        if ($al -and $al.SkuId) {
            $assignedSkuIds += $al.SkuId.ToString()
        }
    }

    $matchedParts = @()
    foreach ($skuId in $assignedSkuIds) {
        if ($SkuIdToPart.ContainsKey($skuId)) {
            $matchedParts += $SkuIdToPart[$skuId]
        }
    }

    if ($matchedParts.Count -eq 0) {
        return @($lic1, $lic2)
    }

    # Fuerza array para evitar bug de "primer caracter" cuando queda como string escalar
    $sortedUnique = @(
        $matchedParts |
        Sort-Object { $SkuPartToIndex[$_] } |
        Select-Object -Unique
    )

    if ($sortedUnique.Count -ge 1) { $lic1 = [string]$sortedUnique[0] }
    if ($sortedUnique.Count -ge 2) { $lic2 = [string]$sortedUnique[1] }

    @($lic1, $lic2)
}

function Get-GeoGroupName {
    param([Parameter(Mandatory = $true)][string]$UserIdOrUpn)

    $geoNames = @()

    try {
        $memberOf = Get-MgUserMemberOf -UserId $UserIdOrUpn -All -Property 'id,displayName' -ErrorAction Stop
        foreach ($obj in $memberOf) {
            $dn = $obj.AdditionalProperties['displayName']
            if ($dn -and ([string]$dn).StartsWith('GEO -')) {
                $geoNames += [string]$dn
            }
        }
    }
    catch {
        $geoNames = @()
    }

    if ($geoNames.Count -eq 0) { return '' }
    if ($geoNames.Count -eq 1) { return $geoNames[0] }
    'Múltiple'
}

function Get-MigrationStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,
        [Parameter(Mandatory = $true)]
        [bool]$MailboxExists,

        # Diagnóstico opcional
        [Parameter(Mandatory = $false)]
        [string]$DiagPath
    )

    function Write-DiagLine {
        param([string]$Line)
        if ($DiagPath) {
            $ts = (Get-Date).ToString("s")
            "$ts`t$Line" | Out-File -FilePath $DiagPath -Append -Encoding UTF8
        }
    }

    $migUsers = @()
    $err = $null

    # 1) Intento directo con retry (latencia/replicación/transitorios)
    for ($attempt = 1; $attempt -le 1; $attempt++) {
        $err = $null
        try {
            $migUsers = @(Get-MigrationUser -Identity $Email -ErrorAction Stop -ErrorVariable err)
            break
        }
        catch {
            Write-DiagLine "Get-MigrationUser -Identity failed (attempt $attempt) for $Email. Error: $($_.Exception.Message)"
            Start-Sleep -Milliseconds (1 * $attempt)
            $migUsers = @()
        }
    }

    # 2) Fallback: si sigue vacío, listar y filtrar (Identity mismatch)
    if (-not $migUsers -or $migUsers.Count -eq 0) {
        try {
            # Nota: esto puede ser costoso si hay muchos; úsalo solo en fallback.
            $all = @(Get-MigrationUser -ResultSize Unlimited -ErrorAction Stop)

            $migUsers = @(
                $all | Where-Object {
                    ($_.UserId -eq $Email) -or
                    ([string]$_.Identity -like "*$Email*")
                }
            )

            Write-DiagLine "Fallback filter used for $Email. Matches: $($migUsers.Count)"
        }
        catch {
            Write-DiagLine "Fallback list/filter failed for $Email. Error: $($_.Exception.Message)"
            $migUsers = @()
        }
    }

    # 3) Aplicar reglas de negocio
    if (-not $migUsers -or $migUsers.Count -eq 0) {
        if ($MailboxExists) { return 'Microsoft' }
        return 'Google'
    }

    if ($migUsers.Count -eq 1) {
        return [string]$migUsers[0].Status
    }

    # 4) Varios resultados: Primary (robustez: tolerar variantes)
    $primary = @($migUsers | Where-Object { $_.MailboxIdentifier -eq 'Primary' })

    if ($primary.Count -eq 1) {
        return [string]$primary[0].Status
    }

    # Si no hay Primary, loguear para análisis
    Write-DiagLine ("Multiple MigrationUsers for {0} but Primary not unique. " -f $Email +
        "Count={0}; Identifiers={1}; Identities={2}" -f
        $migUsers.Count,
        (($migUsers | ForEach-Object { $_.MailboxIdentifier }) -join ','),
        (($migUsers | ForEach-Object { [string]$_.Identity }) -join ',')
    )

    return 'Error'
}

# -------------------------
# Caches (Graph y Migración)
# -------------------------
$UserCache = @{}
$GeoCache  = @{}
$MigCache  = @{}

# -------------------------
# Proceso principal
# -------------------------
$resultado = foreach ($row in $buzonesgoogle) {
    $email = $row.primaryEmail

    # Exchange Online
    $mbx = $null
    $st  = $null
    $existe = $false

    try {
        $mbx = Get-Mailbox -Identity $email -ErrorAction Stop
        $existe = $true

        try {
            $st = Get-MailboxStatistics -Identity $email -ErrorAction Stop
        }
        catch {
            $st = $null
        }
    }
    catch {
        $mbx = $null
        $st  = $null
        $existe = $false
    }

    # MigStatus (EXO Migration)
    $migStatus = ''
    if ($MigCache.ContainsKey($email)) {
        $migStatus = $MigCache[$email]
    }
    else {
        # $migStatus = Get-MigrationStatus -Email $email -MailboxExists $existe
        $migStatus = Get-MigrationStatus -Email $email -MailboxExists $existe -DiagPath ".\MigDiag.tsv"

        $MigCache[$email] = $migStatus
    }

    # Graph: usuario
    $mgUser = $null
    if ($UserCache.ContainsKey($email)) {
        $mgUser = $UserCache[$email]
    }
    else {
        try {
            $mgUser = Get-MgUser -UserId $email -Property 'id,userPrincipalName,assignedLicenses' -ErrorAction Stop
        }
        catch {
            $mgUser = $null
        }
        $UserCache[$email] = $mgUser
    }

    # Licencias (Graph)
    $lic1 = ''
    $lic2 = ''
    if ($mgUser) {
        $lics = Get-OrderedLicenses -AssignedLicenses $mgUser.AssignedLicenses
        $lic1 = $lics[0]
        $lic2 = $lics[1]
    }

    # GEO group (Graph)
    $geoGroup = ''
    if ($mgUser -and $mgUser.Id) {
        if ($GeoCache.ContainsKey($mgUser.Id)) {
            $geoGroup = $GeoCache[$mgUser.Id]
        }
        else {
            $geoGroup = Get-GeoGroupName -UserIdOrUpn $mgUser.Id
            $GeoCache[$mgUser.Id] = $geoGroup
        }
    }

    # Normalización tamaños a MB
    $totalDeletedMB = if ($st) { Convert-SizeToMB -Size $st.TotalDeletedItemSize } else { $null }
    $totalItemMB    = if ($st) { Convert-SizeToMB -Size $st.TotalItemSize } else { $null }

    # Normalización LastInteractionTime
    $lastInteraction = $null
    if ($st -and $st.LastInteractionTime) {
        if ($st.LastInteractionTime -ne [datetime]'1600-12-31T22:00:00') {
            $lastInteraction = $st.LastInteractionTime
        }
    }

    [pscustomobject]@{
        Email                    = $email
        Exists                   = $existe

        MigStatus                = $migStatus

        Licencia1                = $lic1
        Licencia2                = $lic2
        GeoGroup                 = $geoGroup

        # Get-Mailbox
        ProhibitSendReceiveQuota = if ($mbx) { $mbx.ProhibitSendReceiveQuota } else { $null }
        RetentionPolicy          = if ($mbx) { $mbx.RetentionPolicy } else { $null }
        ArchiveGuid              = if ($mbx) { $mbx.ArchiveGuid } else { $null }
        ArchiveStatus            = if ($mbx) { $mbx.ArchiveStatus } else { $null }
        SKUAssigned              = if ($mbx) { $mbx.SKUAssigned } else { $null }
        UsageLocation            = if ($mbx) { $mbx.UsageLocation } else { $null }
        DisplayName              = if ($mbx) { $mbx.DisplayName } else { $null }
        RecipientTypeDetails     = if ($mbx) { $mbx.RecipientTypeDetails } else { $null }

        # Get-MailboxStatistics (normalizados)
        TotalDeletedItemSizeMB   = $totalDeletedMB
        TotalItemSizeMB          = $totalItemMB
        ItemCount                = if ($st) { $st.ItemCount } else { $null }
        LastInteractionTime      = $lastInteraction
    }
}

$resultado | Export-Csv .\MailboxValidation_Stats_Licenses.csv -NoTypeInformation -Encoding UTF8
