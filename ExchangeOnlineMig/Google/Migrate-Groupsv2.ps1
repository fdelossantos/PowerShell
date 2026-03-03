# ============================================================
# Migrate Google Groups (Distribution Lists) -> Microsoft 365 Groups
# - Exports groups + members from Google via GAM7 (to disk)
# - Creates/updates Microsoft 365 Groups (no Teams)
# - Allows external senders (RequireSenderAuthenticationEnabled:$false)
# - Ensures members are subscribed (Subscribers) so they receive copies
# - Adds alias with subdomain o365 (user@o365.domain)
# - Skips adding members whose domain is not an Accepted Domain (external)
# - Ensures a default owner "Group Owner" (group-owner@domain.com) is Owner of every group
# - Removes conflicting MailContact/MailUser with same SMTP before creation (with waits)
# - Waits for group creation visibility (timeout 180s)
# ============================================================

# =========================
# Config
# =========================
$WorkDir = "C:\Temp\GroupsMigration"
$ExportDir = Join-Path $WorkDir "export"
$MembersDir = Join-Path $ExportDir "members_raw"

$GroupsCsv = Join-Path $ExportDir "GoogleGroups.csv"
$AllMembersCsv = Join-Path $ExportDir "GoogleGroupMembers_Flat.csv"
$AddressMapFile = Join-Path $ExportDir "AddressMapping_Groups.txt"

$LogFile = Join-Path $WorkDir "MigrationActions.log"

# Wait/poll settings
$WaitTimeoutSeconds = 180
$WaitPollSeconds = 2

# Default group owner (service account)
$DefaultGroupOwnerUpn = "group-owner@domain.com"

# Optional: also add the default owner as Member/Subscribers
$AddDefaultOwnerAsMember = $false
$AddDefaultOwnerAsSubscriber = $false

New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
New-Item -Path $MembersDir -ItemType Directory -Force | Out-Null

# =========================
# Logging
# =========================
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$ts] $Message" -Encoding UTF8
}

# =========================
# Helpers
# =========================
function Get-O365AliasFromPrimarySmtp {
    param([Parameter(Mandatory)][string]$SmtpAddress)

    $parts = $SmtpAddress.Split("@", 2)
    $local = $parts[0]
    $domain = $parts[1]

    "{0}@o365.{1}" -f $local, $domain
}

function Get-SafeAliasFromSmtp {
    param([Parameter(Mandatory)][string]$SmtpAddress)

    $local = $SmtpAddress.Split("@", 2)[0]
    $alias = ($local -replace "[^a-zA-Z0-9_]", "-").Trim("-")

    if ([string]::IsNullOrWhiteSpace($alias)) {
        $alias = "group-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
    }

    if ($alias.Length -gt 64) {
        $alias = $alias.Substring(0, 64)
    }

    $alias
}

function Wait-Until {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutSeconds = 180,
        [int]$PollSeconds = 2
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        $ok = $false

        try {
            $ok = & $Condition
        }
        catch {
            $ok = $false
        }

        if ($ok) {
            return
        }

        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $msg = "TIMEOUT waiting for: $Description (>${TimeoutSeconds}s). Aborting script."
            Write-Log $msg
            throw $msg
        }

        Start-Sleep -Seconds $PollSeconds
    }
}

function Is-InternalTenantAddress {
    param(
        [Parameter(Mandatory)][string]$EmailAddress,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$DomainsSet
    )

    if ($EmailAddress -notmatch "@") {
        return $false
    }

    $domain = ($EmailAddress.Split("@", 2)[1]).ToLowerInvariant()
    $DomainsSet.Contains($domain)
}

# =========================
# Tenant domains (Accepted Domains)
# =========================
Write-Log "Loading tenant accepted domains from Exchange Online (Get-AcceptedDomain)"

$TenantDomains = Get-AcceptedDomain |
    ForEach-Object { $_.DomainName.ToString().ToLowerInvariant() } |
    Sort-Object -Unique

$TenantDomainsSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$TenantDomains)

Write-Log ("Loaded {0} accepted domains: {1}" -f $TenantDomains.Count, ($TenantDomains -join ", "))

# =========================
# Phase 1 - Export from Google (GAM7) to disk
# =========================
Write-Log "=== START Phase 1: Export from Google (GAM7) ==="

Write-Log "Exporting Google groups to $GroupsCsv"
& gam redirect csv "$GroupsCsv" print groups fields email name | Out-Null

if (Test-Path $AllMembersCsv) { Remove-Item $AllMembersCsv -Force }
"GroupEmail,GroupName,MemberEmail,Role" | Out-File -FilePath $AllMembersCsv -Encoding UTF8 -Force

if (Test-Path $AddressMapFile) { Remove-Item $AddressMapFile -Force }
Clear-Content -Path $AddressMapFile -ErrorAction SilentlyContinue

$googleGroups = Import-Csv $GroupsCsv
$gCount = $googleGroups.Count
$gIndex = 0

foreach ($g in $googleGroups) {
    $gIndex++
    $groupEmail = $g.email
    $groupName = $g.name
    if ([string]::IsNullOrWhiteSpace($groupName)) { $groupName = $groupEmail.Split("@")[0] }

    Write-Progress -Activity "Exportando miembros desde Google" `
        -Status ("{0}/{1} - {2}" -f $gIndex, $gCount, $groupEmail) `
        -PercentComplete ([int](($gIndex / $gCount) * 100))

    $o365Address = Get-O365AliasFromPrimarySmtp -SmtpAddress $groupEmail
    Add-Content -Path $AddressMapFile -Value ("{0},{1}" -f $groupEmail, $o365Address) -Encoding UTF8

    $rawMembersCsv = Join-Path $MembersDir ("members_{0}.csv" -f ($groupEmail -replace "[^a-zA-Z0-9@._-]", "_"))

    Write-Log "Exporting members for group $groupEmail to $rawMembersCsv"
    & gam redirect csv "$rawMembersCsv" print group-members group "$groupEmail" | Out-Null

    $members = @()
    if (Test-Path $rawMembersCsv) { $members = Import-Csv $rawMembersCsv }

    foreach ($m in $members) {
        $line = ('"{0}","{1}","{2}","{3}"' -f $groupEmail, $groupName, $m.email, $m.role)
        Add-Content -Path $AllMembersCsv -Value $line -Encoding UTF8
    }
}

Write-Progress -Activity "Exportando miembros desde Google" -Completed -Status "Listo"
Write-Log "=== END Phase 1: Export from Google (GAM7) ==="

# =========================
# Phase 2 - Create/Update in Microsoft 365
# =========================
Write-Log "=== START Phase 2: Create/Update Microsoft 365 Groups in Exchange Online ==="

$groupsFromDisk = Import-Csv $GroupsCsv
$membersFlat = Import-Csv $AllMembersCsv
$membersByGroup = $membersFlat | Group-Object GroupEmail -AsHashTable -AsString

function Ensure-GroupConfigAndMembership {
    param(
        [Parameter(Mandatory)][string]$GroupEmail,
        [Parameter(Mandatory)][string]$O365AliasSmtp,
        [Parameter(Mandatory)][string[]]$DesiredMembers,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$DomainsSet,
        [Parameter(Mandatory)][string]$DefaultOwnerUpn,
        [bool]$AddOwnerAsMember = $false,
        [bool]$AddOwnerAsSubscriber = $false
    )

    # 0) Ensure default owner
    $currentOwners = @()
    try {
        $currentOwners = Get-UnifiedGroupLinks -Identity $GroupEmail -LinkType Owners -ResultSize Unlimited |
            ForEach-Object { $_.PrimarySmtpAddress.ToString().ToLowerInvariant() }
    }
    catch {
        $currentOwners = @()
        Write-Log "WARNING reading current Owners for $($GroupEmail): $($_.Exception.Message)"
    }

    $ownerLower = $DefaultOwnerUpn.ToLowerInvariant()

    if ($ownerLower -notin $currentOwners) {
        Write-Log "Adding default owner: $DefaultOwnerUpn -> $GroupEmail"
        try {
            Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Owners -Links $DefaultOwnerUpn | Out-Null
            Write-Log "Added default owner: $DefaultOwnerUpn -> $GroupEmail"
        }
        catch {
            Write-Log "WARNING adding default owner $DefaultOwnerUpn to $($GroupEmail): $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Default owner already present: $DefaultOwnerUpn -> $GroupEmail"
    }

    if ($AddOwnerAsMember) {
        Write-Log "Ensuring default owner is also Member: $DefaultOwnerUpn -> $GroupEmail"
        try { Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -Links $DefaultOwnerUpn | Out-Null }
        catch { Write-Log "WARNING ensuring default owner as Member in $($GroupEmail): $($_.Exception.Message)" }
    }

    if ($AddOwnerAsSubscriber) {
        Write-Log "Ensuring default owner is also Subscriber: $DefaultOwnerUpn -> $GroupEmail"
        try { Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Subscribers -Links $DefaultOwnerUpn | Out-Null }
        catch { Write-Log "WARNING ensuring default owner as Subscriber in $($GroupEmail): $($_.Exception.Message)" }
    }

    # 1) Re-apply configuration (external senders + auto-subscribe)
    try {
        Set-UnifiedGroup -Identity $GroupEmail -RequireSenderAuthenticationEnabled:$false -AutoSubscribeNewMembers | Out-Null
        Write-Log "Configured RequireSenderAuthenticationEnabled=False and AutoSubscribeNewMembers=ON for $GroupEmail"
    }
    catch {
        Write-Log "WARNING configuring RequireSenderAuthenticationEnabled/AutoSubscribeNewMembers for $($GroupEmail): $($_.Exception.Message)"
    }

    # 2) Ensure alias o365
    try {
        Set-UnifiedGroup -Identity $GroupEmail -EmailAddresses @{ Add = ("smtp:{0}" -f $O365AliasSmtp) } | Out-Null
        Write-Log "Ensured alias smtp:$O365AliasSmtp on $GroupEmail (added if missing)"
    }
    catch {
        Write-Log "WARNING ensuring alias smtp:$O365AliasSmtp on $($GroupEmail): $($_.Exception.Message)"
    }

    # 3) Filter external members by tenant accepted domains
    $internalMembers = @()

    foreach ($addr in $DesiredMembers) {
        if ([string]::IsNullOrWhiteSpace($addr)) { continue }

        if (Is-InternalTenantAddress -EmailAddress $addr -DomainsSet $DomainsSet) {
            $internalMembers += $addr
        }
        else {
            Write-Log "External member detected (skipped): $addr (Group: $GroupEmail)"
        }
    }

    # 4) Sync Members (add missing)
    $currentMembers = @()
    try {
        $currentMembers = Get-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -ResultSize Unlimited |
            ForEach-Object { $_.PrimarySmtpAddress.ToString() }
    }
    catch {
        $currentMembers = @()
        Write-Log "WARNING reading current Members for $($GroupEmail): $($_.Exception.Message)"
    }

    $membersToAdd = $internalMembers | Where-Object { $_ -and ($_ -notin $currentMembers) }

    foreach ($m in $membersToAdd) {
        Write-Log "Adding member: $m -> $GroupEmail"
        try { Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -Links $m | Out-Null }
        catch { Write-Log "WARNING adding member $m to $($GroupEmail): $($_.Exception.Message)" }
    }

    # 5) Sync Subscribers (add missing)
    $currentSubscribers = @()
    try {
        $currentSubscribers = Get-UnifiedGroupLinks -Identity $GroupEmail -LinkType Subscribers -ResultSize Unlimited |
            ForEach-Object { $_.PrimarySmtpAddress.ToString() }
    }
    catch {
        $currentSubscribers = @()
        Write-Log "WARNING reading current Subscribers for $($GroupEmail): $($_.Exception.Message)"
    }

    $subsToAdd = $internalMembers | Where-Object { $_ -and ($_ -notin $currentSubscribers) }

    foreach ($s in $subsToAdd) {
        Write-Log "Subscribing member: $s -> $GroupEmail"
        try { Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Subscribers -Links $s | Out-Null }
        catch { Write-Log "WARNING subscribing $s to $($GroupEmail): $($_.Exception.Message)" }
    }
}

$total = $groupsFromDisk.Count
$i = 0

foreach ($g in $groupsFromDisk) {
    $i++
    $groupEmail = $g.email
    $groupName = $g.name
    if ([string]::IsNullOrWhiteSpace($groupName)) { $groupName = $groupEmail.Split("@")[0] }

    Write-Progress -Activity "Migrando grupos a Microsoft 365" `
        -Status ("{0}/{1} - {2}" -f $i, $total, $groupEmail) `
        -PercentComplete ([int](($i / $total) * 100))

    Write-Log "---- START Group: $groupEmail ($groupName) ----"

    $memberRows = $membersByGroup[$groupEmail]
    if ($null -eq $memberRows) { $memberRows = @() }
    $desiredMembers = $memberRows | ForEach-Object { $_.MemberEmail } | Sort-Object -Unique

    $o365AliasSmtp = Get-O365AliasFromPrimarySmtp -SmtpAddress $groupEmail

    $existing = $null
    try { $existing = Get-UnifiedGroup -Identity $groupEmail -ErrorAction Stop } catch { $existing = $null }

    if ($null -eq $existing) {

        # Remove conflicting MailContact/MailUser with same identity/email
        $contact = $null
        $mailUser = $null

        try { $contact = Get-MailContact -Identity $groupEmail -ErrorAction Stop } catch { $contact = $null }
        try { $mailUser = Get-MailUser -Identity $groupEmail -ErrorAction Stop } catch { $mailUser = $null }

        if ($null -ne $contact) {
            Write-Log "Found MailContact using $groupEmail. Removing: $($contact.Identity)"
            Remove-MailContact -Identity $contact.Identity -Confirm:$false | Out-Null
            Write-Log "Remove-MailContact issued for $($contact.Identity)"

            Wait-Until `
                -Description "MailContact $groupEmail to be fully removed" `
                -TimeoutSeconds $WaitTimeoutSeconds `
                -PollSeconds $WaitPollSeconds `
                -Condition {
                    try { Get-MailContact -Identity $groupEmail -ErrorAction Stop | Out-Null; $false }
                    catch { $true }
                }

            Write-Log "Confirmed MailContact removal for $groupEmail"
        }
        elseif ($null -ne $mailUser) {
            Write-Log "Found MailUser using $groupEmail. Removing: $($mailUser.Identity)"
            Remove-MailUser -Identity $mailUser.Identity -Confirm:$false | Out-Null
            Write-Log "Remove-MailUser issued for $($mailUser.Identity)"

            Wait-Until `
                -Description "MailUser $groupEmail to be fully removed" `
                -TimeoutSeconds $WaitTimeoutSeconds `
                -PollSeconds $WaitPollSeconds `
                -Condition {
                    try { Get-MailUser -Identity $groupEmail -ErrorAction Stop | Out-Null; $false }
                    catch { $true }
                }

            Write-Log "Confirmed MailUser removal for $groupEmail"
        }
        else {
            Write-Log "No MailContact/MailUser found for $groupEmail. Proceeding."
        }

        Write-Log "Group does NOT exist in Microsoft 365: $groupEmail. Creating."

        $alias = Get-SafeAliasFromSmtp -SmtpAddress $groupEmail

        New-UnifiedGroup -DisplayName $groupName -Alias $alias -PrimarySmtpAddress $groupEmail | Out-Null
        Write-Log "New-UnifiedGroup issued for $groupEmail (Alias: $alias)"

        Wait-Until `
            -Description "UnifiedGroup $groupEmail to become visible" `
            -TimeoutSeconds $WaitTimeoutSeconds `
            -PollSeconds $WaitPollSeconds `
            -Condition {
                try { Get-UnifiedGroup -Identity $groupEmail -ErrorAction Stop | Out-Null; $true }
                catch { $false }
            }

        Write-Log "Confirmed UnifiedGroup exists for $groupEmail"
    }
    else {
        Write-Log "Group exists in Microsoft 365: $groupEmail. Syncing members and configuration."
    }

    Ensure-GroupConfigAndMembership `
        -GroupEmail $groupEmail `
        -O365AliasSmtp $o365AliasSmtp `
        -DesiredMembers $desiredMembers `
        -DomainsSet $TenantDomainsSet `
        -DefaultOwnerUpn $DefaultGroupOwnerUpn `
        -AddOwnerAsMember $AddDefaultOwnerAsMember `
        -AddOwnerAsSubscriber $AddDefaultOwnerAsSubscriber

    Write-Log "---- END Group: $groupEmail ----"
}

Write-Progress -Activity "Migrando grupos a Microsoft 365" -Completed -Status "Listo"
Write-Log "=== END Phase 2: Create/Update Microsoft 365 Groups in Exchange Online ==="
