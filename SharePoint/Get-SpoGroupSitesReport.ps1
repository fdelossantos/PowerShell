param(
    [Parameter(Mandatory = $true)]
    [string]$TenantName,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$Tenant,

    [string]$AdminUrl,

    [string]$CertificatePasswordPath,

    [string[]]$SiteUrls,

    [string]$OutFolder = ".\SharePointSitesReport",

    [switch]$PreciseFileCount
)

if (-not $AdminUrl) {
    $AdminUrl = "https://$TenantName-admin.sharepoint.com"
}

if (-not $CertificatePasswordPath) {
    $CertificatePasswordPath = Join-Path $PSScriptRoot "pass.txt"
}

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Path $OutFolder -Force | Out-Null

$JsonPath = Join-Path $OutFolder "SharePointSitesReport.json"
$HtmlPath = Join-Path $OutFolder "SharePointSitesReport.html"

if (-not (Test-Path -LiteralPath $CertificatePasswordPath)) {
    throw "No se encontro el archivo de password del certificado: $CertificatePasswordPath"
}

$certificatePasswordText = (Get-Content -LiteralPath $CertificatePasswordPath -Raw).Trim()

if ([string]::IsNullOrWhiteSpace($certificatePasswordText)) {
    throw "El archivo de password del certificado esta vacio: $CertificatePasswordPath"
}

$CertificatePassword = ConvertTo-SecureString -String $certificatePasswordText -AsPlainText -Force
$resolvedCertificatePath = (Resolve-Path -LiteralPath $CertificatePath).Path
$graphCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $resolvedCertificatePath,
    $CertificatePassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
)

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Reports
Import-Module Microsoft.Graph.Sites
Import-Module Microsoft.Graph.Files

Connect-MgGraph `
    -ClientId $ClientId `
    -TenantId $Tenant `
    -Certificate $graphCertificate `
    -NoWelcome

function Normalize-SiteUrl {
    param(
        [string]$SiteUrl
    )

    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        return $null
    }

    return $SiteUrl.Trim().TrimEnd("/").ToLowerInvariant()
}

function Convert-ToPersonObject {
    param(
        [object]$DirectoryObject
    )

    $userPrincipalName = $null
    $mail = $null
    $displayName = $null
    $id = $null
    $objectType = $null

    if ($DirectoryObject.Id) {
        $id = $DirectoryObject.Id
    }

    if ($DirectoryObject.AdditionalProperties) {
        if ($DirectoryObject.AdditionalProperties.ContainsKey("@odata.type")) {
            $objectType = $DirectoryObject.AdditionalProperties["@odata.type"]
        }

        if ($DirectoryObject.AdditionalProperties.ContainsKey("displayName")) {
            $displayName = $DirectoryObject.AdditionalProperties["displayName"]
        }

        if ($DirectoryObject.AdditionalProperties.ContainsKey("userPrincipalName")) {
            $userPrincipalName = $DirectoryObject.AdditionalProperties["userPrincipalName"]
        }

        if ($DirectoryObject.AdditionalProperties.ContainsKey("mail")) {
            $mail = $DirectoryObject.AdditionalProperties["mail"]
        }
    }

    [pscustomobject]@{
        Id                = $id
        ObjectType        = $objectType
        DisplayName       = $displayName
        UserPrincipalName = $userPrincipalName
        Mail              = $mail
    }
}

function Get-GroupCreator {
    param(
        [string]$GroupId
    )

    $filter = "activityDisplayName eq 'Add group' and targetResources/any(t:t/id eq '$GroupId')"

    try {
        $auditEvents = Get-MgAuditLogDirectoryAudit -Filter $filter -All -Property @(
            "activityDateTime",
            "activityDisplayName",
            "initiatedBy",
            "targetResources"
        )

        $event = $auditEvents |
            Sort-Object ActivityDateTime |
            Select-Object -First 1

        if (-not $event) {
            return [pscustomobject]@{
                Found             = $false
                DisplayName       = $null
                UserPrincipalName = $null
                AppDisplayName    = $null
                DateTime          = $null
                Reason            = "No encontrado en audit logs o fuera de retención"
            }
        }

        $userDisplayName = $null
        $userPrincipalName = $null
        $appDisplayName = $null

        if ($event.InitiatedBy.User) {
            $userDisplayName = $event.InitiatedBy.User.DisplayName
            $userPrincipalName = $event.InitiatedBy.User.UserPrincipalName
        }

        if ($event.InitiatedBy.App) {
            $appDisplayName = $event.InitiatedBy.App.DisplayName
        }

        return [pscustomobject]@{
            Found             = $true
            DisplayName       = $userDisplayName
            UserPrincipalName = $userPrincipalName
            AppDisplayName    = $appDisplayName
            DateTime          = $event.ActivityDateTime
            Reason            = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Found             = $false
            DisplayName       = $null
            UserPrincipalName = $null
            AppDisplayName    = $null
            DateTime          = $null
            Reason            = $_.Exception.Message
        }
    }
}

function Get-GraphSiteFromUrl {
    param(
        [string]$SiteUrl
    )

    $uri = [uri]$SiteUrl
    $hostname = $uri.Host
    $path = $uri.AbsolutePath.TrimEnd("/")

    $graphSiteId = "$hostname`:$path"

    try {
        $site = Get-MgSite `
            -SiteId $graphSiteId `
            -Property "id,displayName,webUrl,createdDateTime,lastModifiedDateTime,sharepointIds" `
            -ErrorAction Stop 2>$null

        return $site
    }
    catch {
        return $null
    }
}

function Get-SiteCollectionIdFromGraphSite {
    param(
        [object]$GraphSite
    )

    if (-not $GraphSite) {
        return $null
    }

    if ($GraphSite.SharepointIds -and $GraphSite.SharepointIds.SiteId) {
        return [string]$GraphSite.SharepointIds.SiteId
    }

    if ($GraphSite.Id -and ([string]$GraphSite.Id).Contains(",")) {
        return ([string]$GraphSite.Id).Split(",")[1]
    }

    return $null
}

function Get-SharePointUsageIndexes {
    param(
        [string]$ReportFolder
    )

    $usageByUrl = @{}
    $usageBySiteId = @{}
    $usageCsvPath = Join-Path $ReportFolder "SharePointSiteUsageDetail.csv"

    try {
        Remove-Item -LiteralPath $usageCsvPath -Force -ErrorAction SilentlyContinue

        Get-MgReportSharePointSiteUsageDetail `
            -Period D7 `
            -OutFile $usageCsvPath `
            -ErrorAction Stop 2>$null

        if (-not (Test-Path -LiteralPath $usageCsvPath)) {
            throw "Graph Reports no genero el archivo CSV esperado."
        }

        foreach ($row in (Import-Csv -LiteralPath $usageCsvPath)) {
            $siteUrl = $row."Site URL"
            $siteId = $row."Site Id"

            if ($siteUrl) {
                $usageByUrl[(Normalize-SiteUrl -SiteUrl $siteUrl)] = $row
            }

            if ($siteId) {
                $usageBySiteId[[string]$siteId] = $row
            }
        }
    }
    catch {
        $message = $_.Exception.Message -replace "(\r?\n).*", ""
        Write-Warning "No se pudo leer Microsoft Graph Reports para uso/storage de SharePoint. El reporte continua sin esos datos agregados. Detalle: $message"
    }

    return [pscustomobject]@{
        ByUrl    = $usageByUrl
        BySiteId = $usageBySiteId
    }
}

function Convert-UsageBytesToMB {
    param(
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $bytes = 0L

    if ([long]::TryParse([string]$Value, [ref]$bytes)) {
        return [math]::Round($bytes / 1MB, 2)
    }

    return $null
}

function Convert-UsageInt {
    param(
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $number = 0L

    if ([long]::TryParse([string]$Value, [ref]$number)) {
        return $number
    }

    return $null
}

function Get-GroupSiteMap {
    param(
        [string[]]$TargetSiteUrls
    )

    $normalizedTargets = @{}

    foreach ($targetSiteUrl in $TargetSiteUrls) {
        $normalizedTarget = Normalize-SiteUrl -SiteUrl $targetSiteUrl

        if ($normalizedTarget) {
            $normalizedTargets[$normalizedTarget] = $true
        }
    }

    $groupSiteMap = @{}

    try {
        Write-Host "Mapeando Microsoft 365 Groups contra sitios..."

        $groups = Get-MgGroup `
            -All `
            -Filter "groupTypes/any(c:c eq 'Unified')" `
            -Property @(
                "id",
                "displayName",
                "mail",
                "mailNickname",
                "createdDateTime",
                "visibility",
                "groupTypes"
            )

        $groupByRequestId = @{}
        $groupList = @($groups)

        for ($offset = 0; $offset -lt $groupList.Count; $offset += 20) {
            $requests = @()
            $end = [math]::Min($offset + 19, $groupList.Count - 1)

            for ($i = $offset; $i -le $end; $i++) {
                $candidateGroup = $groupList[$i]
                $requestId = [string]$i
                $groupByRequestId[$requestId] = $candidateGroup

                $requests += @{
                    id     = $requestId
                    method = "GET"
                    url    = "/groups/$($candidateGroup.Id)/sites/root?`$select=id,webUrl,displayName"
                }
            }

            if ($requests.Count -eq 0) {
                continue
            }

            $batchResponse = Invoke-MgGraphRequest `
                -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/`$batch" `
                -Body (@{ requests = $requests } | ConvertTo-Json -Depth 5) `
                -ContentType "application/json"

            foreach ($response in $batchResponse.responses) {
                if ($response.status -ne 200) {
                    continue
                }

                $candidateGroup = $groupByRequestId[[string]$response.id]
                $normalizedGroupSiteUrl = Normalize-SiteUrl -SiteUrl $response.body.webUrl

                if (-not $normalizedGroupSiteUrl) {
                    continue
                }

                if ($normalizedTargets.Count -eq 0 -or $normalizedTargets.ContainsKey($normalizedGroupSiteUrl)) {
                    $groupSiteMap[$normalizedGroupSiteUrl] = [pscustomobject]@{
                        Group = $candidateGroup
                        Site  = [pscustomobject]@{
                            Id          = $response.body.id
                            WebUrl      = $response.body.webUrl
                            DisplayName = $response.body.displayName
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "No se pudo mapear grupos de Microsoft 365 contra sitios. El reporte continua sin owners/members de grupo cuando no haya GroupId. Detalle: $($_.Exception.Message)"
    }

    return $groupSiteMap
}

function Get-DriveFileCountRecursive {
    param(
        [string]$DriveId,
        [string]$ItemId = "root"
    )

    $count = 0

    try {
        if ($ItemId -eq "root") {
            $children = Get-MgDriveRootChild -DriveId $DriveId -All
        }
        else {
            $children = Get-MgDriveItemChild -DriveId $DriveId -DriveItemId $ItemId -All
        }

        foreach ($child in $children) {
            if ($child.File) {
                $count++
            }

            if ($child.Folder) {
                $count += Get-DriveFileCountRecursive -DriveId $DriveId -ItemId $child.Id
            }
        }
    }
    catch {
    }

    return $count
}

function Get-SiteFileCount {
    param(
        [string]$SiteUrl,
        [switch]$Precise
    )

    if (-not $Precise) {
        return [pscustomobject]@{
            Success          = $false
            Mode             = "Skipped"
            FileCount        = $null
            ApproximateItems = $null
            Libraries        = @()
            Error            = "Conteo preciso omitido. Use -PreciseFileCount para recorrer archivos, o conceda Reports.Read.All para usar el reporte agregado de Graph."
        }
    }

    try {
        $graphSite = Get-GraphSiteFromUrl -SiteUrl $SiteUrl

        if (-not $graphSite) {
            return [pscustomobject]@{
                Success          = $false
                Mode             = $null
                FileCount        = $null
                ApproximateItems = $null
                Libraries        = @()
                Error            = "No se pudo resolver el sitio por Graph"
            }
        }

        $drives = Get-MgSiteDrive -SiteId $graphSite.Id -All

        $totalCount = 0
        $libraries = @()

        foreach ($drive in $drives) {
            $driveCount = Get-DriveFileCountRecursive -DriveId $drive.Id

            $totalCount += $driveCount

            $libraries += [pscustomobject]@{
                Title            = $drive.Name
                ApproximateItems = $null
                PreciseFiles     = $driveCount
            }
        }

        return [pscustomobject]@{
            Success          = $true
            Mode             = "GraphRecursive"
            FileCount        = $totalCount
            ApproximateItems = $null
            Libraries        = $libraries
            Error            = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success          = $false
            Mode             = $null
            FileCount        = $null
            ApproximateItems = $null
            Libraries        = @()
            Error            = $_.Exception.Message
        }
    }
}

if ($SiteUrls -and $SiteUrls.Count -gt 0) {
    $sites = @(
        foreach ($siteUrl in $SiteUrls) {
            $graphSite = Get-GraphSiteFromUrl -SiteUrl $siteUrl

            if (-not $graphSite) {
                Write-Warning "No se pudo resolver el sitio por Graph: $siteUrl"

                [pscustomobject]@{
                    Title                = $siteUrl
                    Url                  = $siteUrl
                    CreationTime         = $null
                    LastModifiedDateTime = $null
                StorageUsageCurrent  = $null
                GroupId              = $null
                SiteCollectionId     = $null
                Source               = "Unresolved"
                ResolveError         = "No se pudo resolver el sitio por Graph"
            }

                continue
            }

            [pscustomobject]@{
                Title                = $graphSite.DisplayName
                Url                  = $graphSite.WebUrl
                CreationTime         = $graphSite.CreatedDateTime
                LastModifiedDateTime = $graphSite.LastModifiedDateTime
                StorageUsageCurrent  = $null
                GroupId              = $null
                SiteCollectionId     = Get-SiteCollectionIdFromGraphSite -GraphSite $graphSite
                Source               = "Graph"
                ResolveError         = $null
            }
        }
    )
}
else {
    Import-Module PnP.PowerShell

    Connect-PnPOnline `
        -Url $AdminUrl `
        -ClientId $ClientId `
        -CertificatePath $resolvedCertificatePath `
        -CertificatePassword $CertificatePassword `
        -Tenant $Tenant

    $sites = @(
        Get-PnPTenantSite -Detailed |
            Where-Object {
                $_.Template -like "GROUP*"
            }
    )
}

if (-not $sites -or $sites.Count -eq 0) {
    throw "No se encontraron sitios para procesar."
}

foreach ($site in $sites) {
    if (-not $site.Url) {
        throw "Se encontro un sitio sin URL en la coleccion de entrada."
    }
}

$usageIndexes = Get-SharePointUsageIndexes -ReportFolder $OutFolder
$groupSiteMap = Get-GroupSiteMap -TargetSiteUrls @($sites | ForEach-Object { $_.Url })

$report = @()
$index = 0

foreach ($site in $sites) {
    $index++
    Write-Host "[$index/$($sites.Count)] Procesando $($site.Url)"

    $group = $null
    $owners = @()
    $members = @()
    $creator = $null

    $groupId = $null

    if ($site.GroupId -and $site.GroupId -ne [guid]::Empty) {
        $groupId = $site.GroupId.ToString()
    }

    $normalizedSiteUrl = Normalize-SiteUrl -SiteUrl $site.Url
    $mappedGroupSite = $null

    if (-not $groupId -and $groupSiteMap.ContainsKey($normalizedSiteUrl)) {
        $mappedGroupSite = $groupSiteMap[$normalizedSiteUrl]
        $groupId = $mappedGroupSite.Group.Id
    }

    if ($groupId) {
        try {
            if ($mappedGroupSite) {
                $group = $mappedGroupSite.Group
            }
            else {
                $group = Get-MgGroup `
                    -GroupId $groupId `
                    -Property @(
                        "id",
                        "displayName",
                        "mail",
                        "mailNickname",
                        "createdDateTime",
                        "visibility",
                        "groupTypes"
                    )
            }

            $owners = Get-MgGroupOwner -GroupId $groupId -All |
                ForEach-Object {
                    Convert-ToPersonObject -DirectoryObject $_
                }

            $members = Get-MgGroupMember -GroupId $groupId -All |
                ForEach-Object {
                    Convert-ToPersonObject -DirectoryObject $_
                }

            $creator = Get-GroupCreator -GroupId $groupId
        }
        catch {
            $creator = [pscustomobject]@{
                Found             = $false
                DisplayName       = $null
                UserPrincipalName = $null
                AppDisplayName    = $null
                DateTime          = $null
                Reason            = $_.Exception.Message
            }
        }
    }
    else {
        $creator = [pscustomobject]@{
            Found             = $false
            DisplayName       = $null
            UserPrincipalName = $null
            AppDisplayName    = $null
            DateTime          = $null
            Reason            = "El sitio no tiene GroupId asociado"
        }
    }

    $usage = $null

    if ($usageIndexes.ByUrl.ContainsKey($normalizedSiteUrl)) {
        $usage = $usageIndexes.ByUrl[$normalizedSiteUrl]
    }
    elseif ($site.SiteCollectionId -and $usageIndexes.BySiteId.ContainsKey([string]$site.SiteCollectionId)) {
        $usage = $usageIndexes.BySiteId[[string]$site.SiteCollectionId]
    }

    $storageUsedMB = $site.StorageUsageCurrent

    if ($null -eq $storageUsedMB -and $usage) {
        $storageUsedMB = Convert-UsageBytesToMB -Value $usage."Storage Used (Byte)"
    }

    $usageFileCount = $null
    $activeFileCount = $null

    if ($usage) {
        $usageFileCount = Convert-UsageInt -Value $usage."File Count"
        $activeFileCount = Convert-UsageInt -Value $usage."Active File Count"
    }

    if ($PreciseFileCount) {
        $fileCount = Get-SiteFileCount -SiteUrl $site.Url -Precise
    }
    elseif ($null -ne $usageFileCount) {
        $fileCount = [pscustomobject]@{
            Success          = $true
            Mode             = "GraphReportsD7"
            FileCount        = $usageFileCount
            ApproximateItems = $null
            Libraries        = @()
            Error            = $null
        }
    }
    else {
        $fileCount = Get-SiteFileCount -SiteUrl $site.Url
    }

    $report += [pscustomobject]@{
        Name              = $site.Title
        Url               = $site.Url
        CreatedDate       = $site.CreationTime
        LastModifiedDate  = $site.LastModifiedDateTime
        SiteResolveError  = $site.ResolveError
        LastActivityDate  = if ($usage) { $usage."Last Activity Date" } else { $null }
        StorageUsedMB     = $storageUsedMB
        FileCount         = $fileCount.FileCount
        FileCountMode     = $fileCount.Mode
        FileCountError    = $fileCount.Error
        UsageFileCount    = $usageFileCount
        ActiveFileCount   = $activeFileCount
        GroupId           = $groupId
        GroupDisplayName  = $group.DisplayName
        GroupMail         = $group.Mail
        GroupCreatedDate  = $group.CreatedDateTime
        GroupVisibility   = $group.Visibility
        GroupCreator      = $creator
        Owners            = $owners
        Members           = $members
        DocumentLibraries = $fileCount.Libraries
    }
}

$report |
    ConvertTo-Json -Depth 20 |
    Set-Content -Path $JsonPath -Encoding UTF8

$jsonForHtml = $report |
    ConvertTo-Json -Depth 20

$jsonForHtml = $jsonForHtml.Replace("</", "<\/")

$html = @'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>SharePoint Sites Report</title>
<style>
body {
    font-family: Segoe UI, Arial, sans-serif;
    margin: 24px;
    background: #f7f7f7;
    color: #222;
}
h1 {
    margin-bottom: 4px;
}
.summary {
    margin-bottom: 16px;
    color: #555;
}
input {
    width: 100%;
    padding: 10px;
    font-size: 14px;
    margin: 12px 0 16px 0;
    box-sizing: border-box;
}
table {
    width: 100%;
    border-collapse: collapse;
    background: white;
}
th, td {
    border-bottom: 1px solid #ddd;
    padding: 8px;
    text-align: left;
    vertical-align: top;
}
th {
    background: #eee;
    position: sticky;
    top: 0;
}
tr:hover {
    background: #fafafa;
}
button {
    padding: 4px 8px;
    cursor: pointer;
}
.details {
    display: none;
    background: #fff;
    border: 1px solid #ddd;
    margin: 8px 0 16px 0;
    padding: 12px;
}
.people {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
}
.person {
    padding: 4px 0;
    border-bottom: 1px solid #eee;
}
.small {
    color: #666;
    font-size: 12px;
}
.badge {
    display: inline-block;
    padding: 2px 6px;
    border-radius: 4px;
    background: #eee;
    font-size: 12px;
}
pre {
    white-space: pre-wrap;
    background: #f2f2f2;
    padding: 8px;
}
</style>
</head>
<body>
<h1>SharePoint Sites Report</h1>
<div class="summary" id="summary"></div>
<input id="search" placeholder="Buscar por nombre, URL, propietario, miembro, grupo o creador..." />

<table id="sitesTable">
<thead>
<tr>
<th></th>
<th>Nombre</th>
<th>URL</th>
<th>Creación</th>
<th>Storage MB</th>
<th>Archivos</th>
<th>Grupo</th>
<th>Creador grupo</th>
<th>Owners</th>
<th>Members</th>
</tr>
</thead>
<tbody></tbody>
</table>

<script id="data" type="application/json">
__REPORT_JSON__
</script>

<script>
const raw = document.getElementById("data").textContent;
const data = JSON.parse(raw);

function asArray(value) {
    if (!value) return [];
    return Array.isArray(value) ? value : [value];
}

function esc(value) {
    if (value === null || value === undefined) return "";
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
}

function personText(p) {
    const dn = p.DisplayName || "";
    const upn = p.UserPrincipalName || p.Mail || "";
    if (dn && upn) return dn + " <" + upn + ">";
    return dn || upn || p.Id || "";
}

function peopleHtml(items) {
    const arr = asArray(items);
    if (arr.length === 0) return "<span class='small'>Sin datos</span>";

    return arr.map(p => {
        return "<div class='person'><b>" + esc(p.DisplayName || "(sin display name)") + "</b><br><span class='small'>" +
            esc(p.UserPrincipalName || p.Mail || p.Id || "") +
            "</span></div>";
    }).join("");
}

function librariesHtml(items) {
    const arr = asArray(items);
    if (arr.length === 0) return "<span class='small'>Sin datos</span>";

    let rows = arr.map(l => {
        return "<tr><td>" + esc(l.Title) + "</td><td>" +
            esc(l.ApproximateItems) + "</td><td>" +
            esc(l.PreciseFiles ?? "") + "</td></tr>";
    }).join("");

    return "<table><thead><tr><th>Biblioteca</th><th>Items aprox.</th><th>Archivos precisos</th></tr></thead><tbody>" + rows + "</tbody></table>";
}

function searchableText(site) {
    const owners = asArray(site.Owners).map(personText).join(" ");
    const members = asArray(site.Members).map(personText).join(" ");
    const creator = site.GroupCreator ? [
        site.GroupCreator.DisplayName,
        site.GroupCreator.UserPrincipalName,
        site.GroupCreator.AppDisplayName
    ].join(" ") : "";

    return [
        site.Name,
        site.Url,
        site.GroupDisplayName,
        site.GroupMail,
        creator,
        owners,
        members
    ].join(" ").toLowerCase();
}

function render() {
    const query = document.getElementById("search").value.toLowerCase();
    const tbody = document.querySelector("#sitesTable tbody");
    tbody.innerHTML = "";

    const filtered = data.filter(site => searchableText(site).includes(query));

    document.getElementById("summary").textContent =
        "Sitios: " + filtered.length + " visibles de " + data.length + " totales";

    filtered.forEach((site, i) => {
        const owners = asArray(site.Owners);
        const members = asArray(site.Members);
        const creator = site.GroupCreator || {};

        const tr = document.createElement("tr");
        tr.innerHTML = `
            <td><button onclick="toggleDetails('d${i}')">+</button></td>
            <td>${esc(site.Name)}</td>
            <td><a href="${esc(site.Url)}" target="_blank">${esc(site.Url)}</a></td>
            <td>${esc(site.CreatedDate || "")}</td>
            <td>${esc(site.StorageUsedMB ?? "")}</td>
            <td>${esc(site.FileCount ?? "")}<br><span class="small">${esc(site.FileCountMode || "")}</span></td>
            <td>${esc(site.GroupDisplayName || "")}<br><span class="small">${esc(site.GroupMail || site.GroupId || "")}</span></td>
            <td>${esc(creator.DisplayName || creator.AppDisplayName || "")}<br><span class="small">${esc(creator.UserPrincipalName || creator.Reason || "")}</span></td>
            <td><span class="badge">${owners.length}</span></td>
            <td><span class="badge">${members.length}</span></td>
        `;
        tbody.appendChild(tr);

        const detailsTr = document.createElement("tr");
        detailsTr.innerHTML = `
            <td colspan="10">
                <div class="details" id="d${i}">
                    <h3>${esc(site.Name)}</h3>
                    <p><b>URL:</b> <a href="${esc(site.Url)}" target="_blank">${esc(site.Url)}</a></p>
                    <p><b>GroupId:</b> ${esc(site.GroupId || "")}</p>
                    <p><b>Grupo creado:</b> ${esc(site.GroupCreatedDate || "")}</p>
                    <p><b>Creador:</b> ${esc(creator.DisplayName || creator.AppDisplayName || "")} ${esc(creator.UserPrincipalName || "")}</p>
                    <p><b>Nota creador:</b> ${esc(creator.Reason || "")}</p>
                    <p><b>Error resolución sitio:</b> ${esc(site.SiteResolveError || "")}</p>
                    <p><b>Error conteo archivos:</b> ${esc(site.FileCountError || "")}</p>

                    <div class="people">
                        <div>
                            <h4>Propietarios</h4>
                            ${peopleHtml(site.Owners)}
                        </div>
                        <div>
                            <h4>Miembros</h4>
                            ${peopleHtml(site.Members)}
                        </div>
                    </div>

                    <h4>Bibliotecas documentales</h4>
                    ${librariesHtml(site.DocumentLibraries)}
                </div>
            </td>
        `;
        tbody.appendChild(detailsTr);
    });
}

function toggleDetails(id) {
    const el = document.getElementById(id);
    el.style.display = el.style.display === "block" ? "none" : "block";
}

document.getElementById("search").addEventListener("input", render);
render();
</script>
</body>
</html>
'@

$html = $html.Replace("__REPORT_JSON__", $jsonForHtml)

$html | Set-Content -Path $HtmlPath -Encoding UTF8

Write-Host ""
Write-Host "Reporte JSON: $JsonPath"
Write-Host "Reporte HTML: $HtmlPath"
