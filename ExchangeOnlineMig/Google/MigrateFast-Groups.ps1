<# 
============================================================
Phase 2 (v2) – Rápido
CAMBIO: Alias único = <localpart>_<dominioSanitizado>
Ejemplo:
  ventas@domain.com        -> Alias: ventas_domain-com
  ventas@otraempresa.com  -> Alias: ventas_otraempresa-com
============================================================
#>

# =========================
# Config
# =========================
$WorkDir = "E:\Work\GroupsMigration"
$ExportDir = Join-Path $WorkDir "export"

$GroupsCsv = Join-Path $ExportDir "GoogleGroups2.csv"
$MembersCsv = Join-Path $ExportDir "GoogleGroupMembers_Flat.csv"

$ServiceOwnerUpn = "group-owner@domain.com"

# Performance tuning
$BatchSizeMembers = 200

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

function Get-SafeAliasWithDomainSuffix {
    param([Parameter(Mandatory)][string]$SmtpAddress)

    $parts = $SmtpAddress.Split("@", 2)
    $local = $parts[0]
    $domain = $parts[1].ToLowerInvariant()

    # Sanitizar local: solo [a-zA-Z0-9_], el resto -> -
    $localSafe = ($local -replace "[^a-zA-Z0-9_]", "-").Trim("-")
    if ([string]::IsNullOrWhiteSpace($localSafe)) {
        $localSafe = "group-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
    }

    # Dominio como sufijo: reemplazar '.' por '-' y sanitizar
    $domainSafe = ($domain -replace "\.", "-")
    $domainSafe = ($domainSafe -replace "[^a-z0-9-]", "-").Trim("-")

    $alias = "{0}_{1}" -f $localSafe, $domainSafe

    # Límite práctico (Alias suele limitarse a 64)
    if ($alias.Length -gt 64) {
        $alias = $alias.Substring(0, 64)
        $alias = $alias.Trim("-","_")
    }

    if ([string]::IsNullOrWhiteSpace($alias)) {
        $alias = "group-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
    }

    $alias
}

function Get-InternalMembers {
    param(
        [Parameter(Mandatory)][string[]]$MemberEmails,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$AcceptedDomains,
        [Parameter(Mandatory)][string]$GroupEmail
    )

    $internal = New-Object System.Collections.Generic.List[string]

    foreach ($m in $MemberEmails) {
        if ([string]::IsNullOrWhiteSpace($m)) { continue }

        $domain = Get-DomainFromEmail -Email $m
        if ($AcceptedDomains.Contains($domain)) {
            $internal.Add($m)
        }
        else {
            Write-Host ("[EXTERNAL] Skipped {0} (Group: {1})" -f $m, $GroupEmail)
        }
    }

    $internal.ToArray()
}

function Add-GroupMembersInBatches {
    param(
        [Parameter(Mandatory)][string]$GroupIdentity,
        [Parameter(Mandatory)][string[]]$Members,
        [int]$BatchSize = 200
    )

    if ($null -eq $Members -or $Members.Count -eq 0) { return }

    $total = $Members.Count
    $idx = 0

    while ($idx -lt $total) {
        $take = [Math]::Min($BatchSize, $total - $idx)
        $batch = $Members[$idx..($idx + $take - 1)]

        try {
            Add-UnifiedGroupLinks -Identity $GroupIdentity -LinkType Members -Links $batch -ErrorAction Stop | Out-Null
        }
        catch {
            # Para velocidad y simplicidad, ignoramos fallos por duplicados/no resolubles
        }

        $idx += $take
    }
}

# =========================
# Pre-load
# =========================
$googleGroups = Import-Csv $GroupsCsv

Write-Host "Loading tenant accepted domains (Get-AcceptedDomain)..."
$acceptedDomainList = Get-AcceptedDomain |
    ForEach-Object { $_.DomainName.ToString().ToLowerInvariant() } |
    Sort-Object -Unique

$AcceptedDomains = [System.Collections.Generic.HashSet[string]]::new([string[]]$acceptedDomainList)
Write-Host ("Accepted domains loaded: {0}" -f $AcceptedDomains.Count)

Write-Host "Loading group members from CSV..."
$membersFlat = Import-Csv $MembersCsv

$membersByGroup = @{}
foreach ($row in $membersFlat) {
    $ge = $row.GroupEmail
    $me = $row.MemberEmail
    if ([string]::IsNullOrWhiteSpace($ge)) { continue }

    if (-not $membersByGroup.ContainsKey($ge)) {
        $membersByGroup[$ge] = New-Object System.Collections.Generic.List[string]
    }

    if (-not [string]::IsNullOrWhiteSpace($me)) {
        $membersByGroup[$ge].Add($me)
    }
}

Write-Host "Loading existing Microsoft 365 Groups (Get-UnifiedGroup -ResultSize Unlimited)..."
$existingGroups = Get-UnifiedGroup -ResultSize Unlimited

$existingByPrimary = @{}
foreach ($eg in $existingGroups) {
    $smtp = $eg.PrimarySmtpAddress.ToString().ToLowerInvariant()
    $existingByPrimary[$smtp] = $eg
}

Write-Host ("Existing groups loaded: {0}" -f $existingByPrimary.Count)
Write-Host ""

# =========================
# Main loop
# =========================
$totalGroups = $googleGroups.Count
$processed = 0

foreach ($g in $googleGroups) {
    $processed++

    $groupEmail = $g.email
    $groupName = $g.name

    if ([string]::IsNullOrWhiteSpace($groupEmail)) { continue }

    if ([string]::IsNullOrWhiteSpace($groupName)) {
        $groupName = $groupEmail.Split("@", 2)[0]
    }

    Write-Progress -Activity "Migrando grupos a Microsoft 365 (Phase 2 v2)" `
        -Status ("{0}/{1} - {2}" -f $processed, $totalGroups, $groupEmail) `
        -PercentComplete ([int](($processed / $totalGroups) * 100))

    $primaryLower = $groupEmail.ToLowerInvariant()
    $alias = Get-SafeAliasWithDomainSuffix -SmtpAddress $groupEmail
    $o365Alias = Get-O365AliasFromPrimarySmtp -SmtpAddress $groupEmail

    $rawMembers = @()
    if ($membersByGroup.ContainsKey($groupEmail)) {
        $rawMembers = $membersByGroup[$groupEmail].ToArray() | Sort-Object -Unique
    }

    if ($rawMembers.Count -eq 0) {
        Write-Host ("[WARN] No members found for group {0}, skipping." -f $groupEmail)
        continue
    }

    $internalMembers = Get-InternalMembers -MemberEmails $rawMembers -AcceptedDomains $AcceptedDomains -GroupEmail $groupEmail

    $exists = $existingByPrimary.ContainsKey($primaryLower)

    if (-not $exists) {
        $emailAddresses = @(
            ("SMTP:{0}" -f $groupEmail)
            ("smtp:{0}" -f $o365Alias)
        )

        Write-Host ("[CREATE] {0} <{1}> Alias:{2}" -f $groupName, $groupEmail, $alias)

        try {
            New-UnifiedGroup `
                -DisplayName $groupName `
                -Alias $alias `
                -PrimarySmtpAddress $groupEmail `
                -RequireSenderAuthenticationEnabled $false `
                -AutoSubscribeNewMembers `
                -Owner $ServiceOwnerUpn `
                -EmailAddresses $emailAddresses | Out-Null
        }
        catch {
            Write-Host ("[ERROR] New-UnifiedGroup failed for {0}: {1}" -f $groupEmail, $_.Exception.Message)
            continue
        }

        try {
            $created = Get-UnifiedGroup -Identity $groupEmail -ErrorAction Stop
            $existingByPrimary[$primaryLower] = $created
        }
        catch { }
    }
    else {
        Write-Host ("[UPDATE] {0} <{1}>" -f $groupName, $groupEmail)

        try {
            Set-UnifiedGroup `
                -Identity $groupEmail `
                -RequireSenderAuthenticationEnabled:$false `
                -AutoSubscribeNewMembers | Out-Null
        }
        catch {
            Write-Host ("[WARN] Set-UnifiedGroup failed for {0}: {1}" -f $groupEmail, $_.Exception.Message)
        }

        try {
            Set-UnifiedGroup -Identity $groupEmail -EmailAddresses @{ Add = ("smtp:{0}" -f $o365Alias) } | Out-Null
        }
        catch { }

        try { Add-UnifiedGroupLinks -Identity $groupEmail -LinkType Members -Links $ServiceOwnerUpn | Out-Null } catch { }
        try { Add-UnifiedGroupLinks -Identity $groupEmail -LinkType Owners -Links $ServiceOwnerUpn | Out-Null } catch { }
    }

    if ($null -ne $internalMembers -and $internalMembers.Count -gt 0) {
        Add-GroupMembersInBatches -GroupIdentity $groupEmail -Members $internalMembers -BatchSize $BatchSizeMembers
    }
}

Write-Progress -Activity "Migrando grupos a Microsoft 365 (Phase 2 v2)" -Completed -Status "Listo"
Write-Host ""
Write-Host "Done."
