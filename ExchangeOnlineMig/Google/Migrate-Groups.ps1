# =========================
# Config
# =========================
$WorkDir = "E:\Work\GroupsMigration"
$ExportDir = Join-Path $WorkDir "export"
$MembersDir = Join-Path $ExportDir "members_raw"
$WaitTimeoutSeconds = 180
$WaitPollSeconds = 2
$NewUnifiedGroupMaxAttempts = 2
$NewUnifiedGroupRetryDelaySeconds = 1
$DefaultGroupOwnerUpn = "group-owner@domain.com"
$AddDefaultOwnerAsMember = $false
$AddDefaultOwnerAsSubscriber = $false


$GroupsCsv = Join-Path $ExportDir "GoogleGroups.csv"
$AllMembersCsv = Join-Path $ExportDir "GoogleGroupMembers_Flat.csv"

# NUEVO: archivo para Address Mapping
$AddressMapFile = Join-Path $ExportDir "AddressMapping_Groups.txt"

$LogFile = Join-Path $WorkDir "MigrationActions.log"

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
    param(
        [Parameter(Mandatory)]
        [string]$SmtpAddress
    )

    $parts = $SmtpAddress.Split("@", 2)
    $local = $parts[0]
    $domain = $parts[1]

    # group@domain.com -> group@o365.domain.com
    return ("{0}@o365.{1}" -f $local, $domain)
}

function Get-SafeAliasFromSmtp {
    param(
        [Parameter(Mandatory)]
        [string]$SmtpAddress
    )

    $local = $SmtpAddress.Split("@", 2)[0]
    $alias = ($local -replace "[^a-zA-Z0-9_]", "-").Trim("-")

    if ([string]::IsNullOrWhiteSpace($alias)) {
        $alias = "group-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
    }

    if ($alias.Length -gt 64) {
        $alias = $alias.Substring(0, 64)
    }

    return $alias
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

    if ($EmailAddress -notmatch "@") { return $false }

    $domain = ($EmailAddress.Split("@", 2)[1]).ToLowerInvariant()
    return $DomainsSet.Contains($domain)
}

function New-UnifiedGroupWithRetry {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$PrimarySmtpAddress,
        [int]$MaxAttempts = 4,
        [int]$DelaySeconds = 3
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++

        try {
            Write-Log "New-UnifiedGroup attempt $attempt/$MaxAttempts for $PrimarySmtpAddress"
            New-UnifiedGroup `
                -DisplayName $DisplayName `
                -Alias $Alias `
                -PrimarySmtpAddress $PrimarySmtpAddress | Out-Null

            Write-Log "New-UnifiedGroup succeeded for $PrimarySmtpAddress (attempt $attempt)"
            return
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Log "New-UnifiedGroup failed for $PrimarySmtpAddress (attempt $attempt): $lastError"

            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }

    $msg = "New-UnifiedGroup failed after $MaxAttempts attempts for $PrimarySmtpAddress. Last error: $lastError"
    Write-Log $msg
    throw $msg
}


# =========================
# Tenant domains (Accepted Domains)
# =========================
Write-Log "Loading tenant accepted domains from Exchange Online (Get-AcceptedDomain)"

$TenantDomains = Get-AcceptedDomain |
    ForEach-Object { $_.DomainName.ToString().ToLowerInvariant() } |
    Sort-Object -Unique

# Para lookup rápido
$TenantDomainsSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$TenantDomains)

Write-Log ("Loaded {0} accepted domains: {1}" -f $TenantDomains.Count, ($TenantDomains -join ", "))


# =========================
# Phase 1 - Export from Google (GAM7) to disk
# =========================
Write-Log "=== START Phase 1: Export from Google (GAM7) ==="

Write-Log "Exporting Google groups to $GroupsCsv"
# & gam redirect csv "$GroupsCsv" print groups fields email name | Out-Null

# Flat members file
# if (Test-Path $AllMembersCsv) { Remove-Item $AllMembersCsv -Force }
# "GroupEmail,GroupName,MemberEmail,Role" | Out-File -FilePath $AllMembersCsv -Encoding UTF8 -Force

# NUEVO: Address mapping file
# if (Test-Path $AddressMapFile) { Remove-Item $AddressMapFile -Force }
# (Sin header; si quisieras header: "Original,O365" | Out-File ...)
# "" | Out-File -FilePath $AddressMapFile -Encoding UTF8 -Force
# Clear-Content -Path $AddressMapFile -ErrorAction SilentlyContinue

$googleGroups = Import-Csv $GroupsCsv

$gCount = $googleGroups.Count
$gIndex = 0

<# foreach ($g in $googleGroups) {
    $gIndex++
    $groupEmail = $g.email
    $groupName = $g.name

    if ([string]::IsNullOrWhiteSpace($groupName)) {
        $groupName = $groupEmail.Split("@")[0]
    }

    Write-Progress -Activity "Exportando miembros desde Google" `
        -Status ("{0}/{1} - {2}" -f $gIndex, $gCount, $groupEmail) `
        -PercentComplete ([int](($gIndex / $gCount) * 100))

    # NUEVO: escribir mapping original -> o365
    $o365Address = Get-O365AliasFromPrimarySmtp -SmtpAddress $groupEmail
    Add-Content -Path $AddressMapFile -Value ("{0},{1}" -f $groupEmail, $o365Address) -Encoding UTF8

    $rawMembersCsv = Join-Path $MembersDir ("members_{0}.csv" -f ($groupEmail -replace "[^a-zA-Z0-9@._-]", "_"))

    Write-Log "Exporting members for group $groupEmail to $rawMembersCsv"
    # & gam redirect csv "$rawMembersCsv" print group-members "$groupEmail" fields email role | Out-Null
    # & gam redirect csv "$rawMembersCsv" print group-members group "$groupEmail" fields email role | Out-Null
    & gam redirect csv "$rawMembersCsv" print group-members group "$groupEmail" | Out-Null

    $members = @()
    if (Test-Path $rawMembersCsv) {
        $members = Import-Csv $rawMembersCsv
    }

    foreach ($m in $members) {
        $line = ('"{0}","{1}","{2}","{3}"' -f $groupEmail, $groupName, $m.email, $m.role)
        Add-Content -Path $AllMembersCsv -Value $line -Encoding UTF8
    }
} #>

Write-Progress -Activity "Exportando miembros desde Google" -Completed -Status "Listo"
Write-Log "=== END Phase 1: Export from Google (GAM7) ==="

# =========================
# Phase 2 - Process from disk and create/update in Microsoft 365
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

    # 0) Ensure default owner (must be Member before Owner)
    $ownerLower = $DefaultOwnerUpn.ToLowerInvariant()

    # Read current members
    $currentMembers = @()
    try {
        $currentMembers = Get-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -ResultSize Unlimited |
            ForEach-Object { $_.PrimarySmtpAddress.ToString().ToLowerInvariant() }
    }
    catch {
        $currentMembers = @()
        Write-Log "WARNING reading current Members for $($GroupEmail): $($_.Exception.Message)"
    }

    # Ensure owner is a Member first
    if ($ownerLower -notin $currentMembers) {
        Write-Log "Adding default owner as Member (required): $DefaultOwnerUpn -> $GroupEmail"
        try {
            Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -Links $DefaultOwnerUpn | Out-Null
            Write-Log "Added default owner as Member: $DefaultOwnerUpn -> $GroupEmail"
        }
        catch {
            Write-Log "WARNING adding default owner as Member in $($GroupEmail): $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Default owner already Member: $DefaultOwnerUpn -> $GroupEmail"
    }

    # Read current owners
    $currentOwners = @()
    try {
        $currentOwners = Get-UnifiedGroupLinks -Identity $GroupEmail -LinkType Owners -ResultSize Unlimited |
            ForEach-Object { $_.PrimarySmtpAddress.ToString().ToLowerInvariant() }
    }
    catch {
        $currentOwners = @()
        Write-Log "WARNING reading current Owners for $($GroupEmail): $($_.Exception.Message)"
    }

    # Ensure owner in Owners
    if ($ownerLower -notin $currentOwners) {
        Write-Log "Adding default owner as Owner: $DefaultOwnerUpn -> $GroupEmail"
        try {
            Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Owners -Links $DefaultOwnerUpn | Out-Null
            Write-Log "Added default owner as Owner: $DefaultOwnerUpn -> $GroupEmail"
        }
        catch {
            Write-Log "WARNING adding default owner as Owner in $($GroupEmail): $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Default owner already Owner: $DefaultOwnerUpn -> $GroupEmail"
    }

    # Optional: subscriber (send copies)
    if ($AddOwnerAsSubscriber) {
        Write-Log "Ensuring default owner is also Subscriber: $DefaultOwnerUpn -> $GroupEmail"
        try {
            Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Subscribers -Links $DefaultOwnerUpn | Out-Null
        }
        catch {
            Write-Log "WARNING ensuring default owner as Subscriber in $($GroupEmail): $($_.Exception.Message)"
        }
    }

    # 1) Reaplicar configuración: aceptar externos + auto-subscribe
    try {
        # RequireSenderAuthenticationEnabled:$false => permite remitentes externos
        # AutoSubscribeNewMembers => switch (sin valor)
        Set-UnifiedGroup -Identity $GroupEmail -RequireSenderAuthenticationEnabled $false -AutoSubscribeNewMembers -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Configured RequireSenderAuthenticationEnabled=False and AutoSubscribeNewMembers=ON for $GroupEmail"
    }
    catch {
        Write-Log "WARNING configuring RequireSenderAuthenticationEnabled/AutoSubscribeNewMembers for $($GroupEmail): $($_.Exception.Message)"
    }

    # 2) Asegurar alias o365 (si ya existe, el cmdlet puede fallar por duplicado; lo ignoramos con warning)
    try {
        Set-UnifiedGroup -Identity $GroupEmail -EmailAddresses @{ Add = ("smtp:{0}" -f $O365AliasSmtp) } -ErrorAction SilentlyContinue | Out-Null
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


    # 4) Sincronizar miembros (agregar faltantes)
    $currentMembers = @()
    try {
        $currentMembers = Get-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -ResultSize Unlimited |
            ForEach-Object { $_.PrimarySmtpAddress.ToString() }
    }
    catch {
        $currentMembers = @()
        Write-Log "WARNING reading current Members for $($GroupEmail): $($_.Exception.Message)"
    }



    #$membersToAdd = $DesiredMembers | Where-Object { $_ -and ($_ -notin $currentMembers) }
    $membersToAdd = $internalMembers | Where-Object { $_ -and ($_ -notin $currentMembers) }


    foreach ($m in $membersToAdd) {
        Write-Log "Adding member: $m -> $GroupEmail"
        try {
            Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Members -Links $m -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Log "WARNING adding member $m to $($GroupEmail): $($_.Exception.Message)"
        }
    }

    # 4) Sincronizar subscribers (para “send copies”)
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
        try {
            Add-UnifiedGroupLinks -Identity $GroupEmail -LinkType Subscribers -Links $s -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Log "WARNING subscribing $s to $($GroupEmail): $($_.Exception.Message)"
        }
    }
}

$total = $groupsFromDisk.Count
$i = 0

foreach ($g in $groupsFromDisk) {
    $i++
    $groupEmail = $g.email
    $groupName  = $g.name
    if ([string]::IsNullOrWhiteSpace($groupName)) { $groupName = $groupEmail.Split("@")[0] }

    Write-Progress -Activity "Migrando grupos a Microsoft 365" `
        -Status ("{0}/{1} - {2}" -f $i, $total, $groupEmail) `
        -PercentComplete ([int](($i / $total) * 100))

    Write-Log "---- START Group: $groupEmail ($groupName) ----"

    # Desired members from disk (unique)
    $memberRows = $membersByGroup[$groupEmail]
    if ($null -eq $memberRows) { $memberRows = @() }
    $desiredMembers = $memberRows | ForEach-Object { $_.MemberEmail } | Sort-Object -Unique

    $o365AliasSmtp = Get-O365AliasFromPrimarySmtp -SmtpAddress $groupEmail

    # Exists?
    $existing = $null
    try { $existing = Get-UnifiedGroup -Identity $groupEmail -ErrorAction Stop } catch { $existing = $null }

    if ($null -eq $existing) {

        # Antes de crear: eliminar contacto/mailuser que ocupe la dirección
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
                    try {
                        Get-MailContact -Identity $groupEmail -ErrorAction Stop | Out-Null
                        return $false
                    }
                    catch {
                        return $true
                    }
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
                    try {
                        Get-MailUser -Identity $groupEmail -ErrorAction Stop | Out-Null
                        return $false
                    }
                    catch {
                        return $true
                    }
                }

            Write-Log "Confirmed MailUser removal for $groupEmail"
        }
        else {
            Write-Log "No MailContact/MailUser found for $groupEmail. Proceeding."
        }

        Write-Log "Group does NOT exist in Microsoft 365: $groupEmail. Creating."

        $alias = Get-SafeAliasFromSmtp -SmtpAddress $groupEmail
        Write-Log "Creating group in Microsoft 365: $groupEmail"
        Write-Host "Creating group: $groupEmail (Alias: $alias, Name: $groupName)"
        Start-Sleep -Seconds 2 # pequeño delay para evitar throttling
        New-UnifiedGroupWithRetry -DisplayName $groupName -Alias $alias -PrimarySmtpAddress $groupEmail -MaxAttempts $NewUnifiedGroupMaxAttempts -DelaySeconds $NewUnifiedGroupRetryDelaySeconds

        Write-Log "Created group in Microsoft 365: $groupEmail (Alias: $alias)"

        Wait-Until `
            -Description "UnifiedGroup $groupEmail to become visible" `
            -TimeoutSeconds $WaitTimeoutSeconds `
            -PollSeconds $WaitPollSeconds `
            -Condition {
                try {
                    Get-UnifiedGroup -Identity $groupEmail -ErrorAction Stop | Out-Null
                    return $true
                }
                catch {
                    return $false
                }
            }

        Write-Log "Confirmed UnifiedGroup exists for $groupEmail"
    }
    else {
        Write-Log "Group exists in Microsoft 365: $groupEmail. Syncing members and configuration."
    }

    # Siempre: asegurar configuración + alias + membresía/subscripción
    if ($null -ne $desiredMembers) {
    Ensure-GroupConfigAndMembership `
        -GroupEmail $groupEmail `
        -O365AliasSmtp $o365AliasSmtp `
        -DesiredMembers $desiredMembers `
        -DomainsSet $TenantDomainsSet `
        -DefaultOwnerUpn $DefaultGroupOwnerUpn `
        -AddOwnerAsMember $AddDefaultOwnerAsMember `
        -AddOwnerAsSubscriber $AddDefaultOwnerAsSubscriber    
    }
    

    Write-Log "---- END Group: $groupEmail ----"
}

