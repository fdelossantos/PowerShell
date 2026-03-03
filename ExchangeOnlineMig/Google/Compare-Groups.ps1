<#
============================================================
Control post-migración – Validación simple de M365 Groups vs Google CSV
Valida por cada grupo (según GoogleGroups.csv):

- Existe en Microsoft 365 (Get-UnifiedGroup)
- DisplayName coincide
- PrimarySmtpAddress coincide (por lookup)
- Recibe remitentes externos: RequireSenderAuthenticationEnabled = False
- Envían copia a usuarios: (a) AutoSubscribeNewMembers = True, y (b) SubscribersCount vs MembersCount (control práctico)
- Tiene alias smtp:user@o365.dominio en EmailAddresses
- Cantidad de miembros:
    - ExpectedMemberCount (desde GoogleGroupMembers_Flat.csv filtrando por Accepted Domains del tenant)
    - ActualMemberCount (Members)
    - SubscriberCount (Subscribers)
Salida:
- CSV con flags y “differences” para resolver manualmente

Supuestos:
- Exchange Online PowerShell ya conectado
- GoogleGroups.csv y GoogleGroupMembers_Flat.csv existen (como en tu export)
============================================================
#>

# =========================
# Config
# =========================
$WorkDir   = "E:\Work\GroupsMigration"
$ExportDir = Join-Path $WorkDir "export"

$GroupsCsv   = Join-Path $ExportDir "GoogleGroups.csv"
$MembersCsv  = Join-Path $ExportDir "GoogleGroupMembers_Flat.csv"
$ReportCsv   = Join-Path $ExportDir "GroupsAudit_Report.csv"

# =========================
# Helpers
# =========================
function Get-O365AliasFromPrimarySmtp {
    param([Parameter(Mandatory)][string]$SmtpAddress)

    $parts = $SmtpAddress.Split("@", 2)
    "{0}@o365.{1}" -f $parts[0], $parts[1]
}

function Get-DomainFromEmail {
    param([Parameter(Mandatory)][string]$Email)

    if ($Email -notmatch "@") { return "" }
    $Email.Split("@", 2)[1].ToLowerInvariant()
}

function Has-ProxyAddress {
    param(
        [Parameter(Mandatory)]$EmailAddresses,     # array of proxy strings or proxy objects -> ToString()
        [Parameter(Mandatory)][string]$ProxyToFind # e.g. "smtp:alias@domain"
    )

    $needle = $ProxyToFind.ToLowerInvariant()
    foreach ($p in $EmailAddresses) {
        if ($null -eq $p) { continue }
        $s = $p.ToString().ToLowerInvariant()
        if ($s -eq $needle) { return $true }
    }
    return $false
}

# =========================
# Load input CSVs
# =========================
$googleGroups = Import-Csv $GroupsCsv
$membersFlat  = Import-Csv $MembersCsv

# =========================
# Tenant accepted domains (para filtrar externos en "expected")
# =========================
Write-Host "Loading Accepted Domains (Get-AcceptedDomain)..."
$acceptedDomainList = Get-AcceptedDomain |
    ForEach-Object { $_.DomainName.ToString().ToLowerInvariant() } |
    Sort-Object -Unique

$AcceptedDomains = [System.Collections.Generic.HashSet[string]]::new([string[]]$acceptedDomainList)
Write-Host ("Accepted domains loaded: {0}" -f $AcceptedDomains.Count)

# =========================
# Build expected member counts from Google members file (INTERNAL only)
# =========================
Write-Host "Building expected member counts from GoogleGroupMembers_Flat.csv (internal domains only)..."
$expectedMembersByGroup = @{}  # GroupEmail(lower) -> HashSet of member emails(lower)

foreach ($r in $membersFlat) {
    $ge = $r.GroupEmail
    $me = $r.MemberEmail

    if ([string]::IsNullOrWhiteSpace($ge) -or [string]::IsNullOrWhiteSpace($me)) { continue }

    $geKey = $ge.ToLowerInvariant()
    $domain = Get-DomainFromEmail -Email $me

    if (-not $AcceptedDomains.Contains($domain)) {
        continue
    }

    if (-not $expectedMembersByGroup.ContainsKey($geKey)) {
        $expectedMembersByGroup[$geKey] = [System.Collections.Generic.HashSet[string]]::new()
    }

    [void]$expectedMembersByGroup[$geKey].Add($me.ToLowerInvariant())
}

# =========================
# Bulk load existing M365 groups
# =========================
Write-Host "Loading Microsoft 365 Groups (Get-UnifiedGroup -ResultSize Unlimited)..."
$exoGroups = Get-UnifiedGroup -ResultSize Unlimited

$exoByPrimary = @{} # primary(lower) -> group object
foreach ($eg in $exoGroups) {
    $smtp = $eg.PrimarySmtpAddress.ToString().ToLowerInvariant()
    $exoByPrimary[$smtp] = $eg
}

Write-Host ("M365 groups loaded: {0}" -f $exoByPrimary.Count)
Write-Host ""

# =========================
# Audit loop
# =========================
$results = New-Object System.Collections.Generic.List[object]

$total = $googleGroups.Count
$i = 0

foreach ($g in $googleGroups) {
    $i++

    $groupEmail = $g.email
    if ([string]::IsNullOrWhiteSpace($groupEmail)) { continue }

    $googleName = $g.name
    if ([string]::IsNullOrWhiteSpace($googleName)) {
        $googleName = $groupEmail.Split("@", 2)[0]
    }

    Write-Progress -Activity "Audit de grupos (M365 vs Google)" `
        -Status ("{0}/{1} - {2}" -f $i, $total, $groupEmail) `
        -PercentComplete ([int](($i / $total) * 100))

    $primaryLower = $groupEmail.ToLowerInvariant()
    $exists = $exoByPrimary.ContainsKey($primaryLower)

    $m365Name = ""
    $nameMatch = $false

    $requireSenderAuth = $null
    $externalOk = $false

    $autoSubscribe = $null
    $autoSubscribeOk = $false

    $hasO365Alias = $false

    $expectedCount = 0
    $actualMembersCount = $null
    $actualSubscribersCount = $null
    $membersCountMatchExpected = $false
    $subscribersMatchMembers = $false

    $diffs = New-Object System.Collections.Generic.List[string]

    # expected members count (internal only)
    if ($expectedMembersByGroup.ContainsKey($primaryLower)) {
        $expectedCount = $expectedMembersByGroup[$primaryLower].Count
    }
    else {
        $expectedCount = 0
    }

    if (-not $exists) {
        $diffs.Add("MissingInM365") | Out-Null

        $results.Add([pscustomobject]@{
            GroupEmail                     = $groupEmail
            GoogleDisplayName              = $googleName
            M365DisplayName                = ""
            ExistsInM365                    = $false
            DisplayNameMatch               = $false

            RequireSenderAuthenticationEnabled = ""
            AcceptsExternalSenders_OK      = $false

            AutoSubscribeNewMembers        = ""
            AutoSubscribe_OK               = $false

            HasO365Alias                   = $false

            ExpectedMemberCount_Internal   = $expectedCount
            ActualMemberCount              = ""
            MembersCountMatchExpected      = $false

            ActualSubscriberCount          = ""
            SubscribersMatchMembers        = $false

            Differences                    = ($diffs -join ";")
        }) | Out-Null

        continue
    }

    $exo = $exoByPrimary[$primaryLower]

    # Name
    $m365Name = $exo.DisplayName
    $nameMatch = ($m365Name -eq $googleName)
    if (-not $nameMatch) { $diffs.Add("DisplayNameMismatch") | Out-Null }

    # External senders (RequireSenderAuthenticationEnabled should be False)
    $requireSenderAuth = $exo.RequireSenderAuthenticationEnabled
    $externalOk = ($requireSenderAuth -eq $false)
    if (-not $externalOk) { $diffs.Add("ExternalSendersNotAllowed") | Out-Null }

    # AutoSubscribeNewMembers (switch -> property True/False)
    $autoSubscribe = $exo.AutoSubscribeNewMembers
    $autoSubscribeOk = ($autoSubscribe -eq $true)
    if (-not $autoSubscribeOk) { $diffs.Add("AutoSubscribeNewMembersOff") | Out-Null }

    # o365 alias as proxy
    $o365Alias = Get-O365AliasFromPrimarySmtp -SmtpAddress $groupEmail
    $hasO365Alias = Has-ProxyAddress -EmailAddresses $exo.EmailAddresses -ProxyToFind ("smtp:{0}" -f $o365Alias)
    if (-not $hasO365Alias) { $diffs.Add("MissingO365Alias") | Out-Null }

    # Members count + Subscribers count
    try {
        $actualMembersCount = (Get-UnifiedGroupLinks -Identity $groupEmail -LinkType Members -ResultSize Unlimited).Count
    }
    catch {
        $actualMembersCount = $null
        $diffs.Add("CannotReadMembers") | Out-Null
    }

    try {
        $actualSubscribersCount = (Get-UnifiedGroupLinks -Identity $groupEmail -LinkType Subscribers -ResultSize Unlimited).Count
    }
    catch {
        $actualSubscribersCount = $null
        $diffs.Add("CannotReadSubscribers") | Out-Null
    }

    if ($null -ne $actualMembersCount) {
        $membersCountMatchExpected = ($actualMembersCount -eq $expectedCount)
        if (-not $membersCountMatchExpected) { $diffs.Add("MemberCountMismatch") | Out-Null }
    }

    # "Envían mails a todos": control simple -> Subscribers == Members
    if (($null -ne $actualMembersCount) -and ($null -ne $actualSubscribersCount)) {
        $subscribersMatchMembers = ($actualSubscribersCount -eq $actualMembersCount)
        if (-not $subscribersMatchMembers) { $diffs.Add("SubscribersNotEqualMembers") | Out-Null }
    }

    $results.Add([pscustomobject]@{
        GroupEmail                     = $groupEmail
        GoogleDisplayName              = $googleName
        M365DisplayName                = $m365Name
        ExistsInM365                    = $true
        DisplayNameMatch               = $nameMatch

        RequireSenderAuthenticationEnabled = $requireSenderAuth
        AcceptsExternalSenders_OK      = $externalOk

        AutoSubscribeNewMembers        = $autoSubscribe
        AutoSubscribe_OK               = $autoSubscribeOk

        HasO365Alias                   = $hasO365Alias

        ExpectedMemberCount_Internal   = $expectedCount
        ActualMemberCount              = $actualMembersCount
        MembersCountMatchExpected      = $membersCountMatchExpected

        ActualSubscriberCount          = $actualSubscribersCount
        SubscribersMatchMembers        = $subscribersMatchMembers

        Differences                    = ($diffs -join ";")
    }) | Out-Null
}

Write-Progress -Activity "Audit de grupos (M365 vs Google)" -Completed -Status "Listo"

# =========================
# Export report
# =========================
$results |
    Export-Csv -Path $ReportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host ""
Write-Host "Report generated:"
Write-Host $ReportCsv
