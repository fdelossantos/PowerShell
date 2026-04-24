$CsvPath = "E:\Work\___\Batches\Batch004-SharedDrives.csv"
$TenantName = "empresa"
$DefaultOwner = "defaultowner@empresa.com"
$StorageQuotaMB = 1024

function Remove-Accents {
    param(
        [string]$Text
    )

    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder

    foreach ($char in $normalized.ToCharArray()) {
        $unicodeCategory = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($unicodeCategory -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }

    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Get-SafeSiteUrlSegment {
    param(
        [string]$SharedDriveName
    )

    $nameNoAccents = Remove-Accents $SharedDriveName
    $nameNoSpaces = $nameNoAccents -replace '\s+', ''
    $safeName = $nameNoSpaces -replace '[^A-Za-z0-9\-_]', ''

    return "SD-$safeName"
}

function Save-WorkingCsv {
    param(
        [array]$Rows,
        [string]$Path
    )

    $Rows |
        ForEach-Object {
            '"' + ($_.SharedDriveName -replace '"', '""') + '","' + ($_.SiteUrl -replace '"', '""') + '"'
        } |
        Set-Content -Path $Path -Encoding UTF8
}

$AdminUrl = "https://$TenantName-admin.sharepoint.com"
$RootUrl = "https://$TenantName.sharepoint.com/sites"

Write-Host ""
Write-Host "Conectando a SharePoint Online..." -ForegroundColor Cyan
Connect-SPOService -Url $AdminUrl -UseSystemBrowser $true

$rows = Import-Csv -Path $CsvPath -Header SharedDriveName,SiteUrl

$pendingRows = @(
    $rows |
    Where-Object { [string]::IsNullOrWhiteSpace($_.SiteUrl) }
)

$total = $pendingRows.Count
$index = 0

Write-Host ""
Write-Host "Filas pendientes: $total" -ForegroundColor Yellow

foreach ($row in $pendingRows) {
    $index++

    $sharedDriveNameWithSlash = $row.SharedDriveName.Trim()
    $sharedDriveName = $sharedDriveNameWithSlash.TrimStart('/').Trim()

    Write-Host ""
    Write-Host "[$index/$total] Procesando Shared Drive: $sharedDriveNameWithSlash" -ForegroundColor Yellow

    $siteSegment = Get-SafeSiteUrlSegment -SharedDriveName $sharedDriveName
    $siteUrl = "$RootUrl/$siteSegment"

    Write-Host "[$index/$total] URL del sitio: $siteUrl" -ForegroundColor DarkCyan

    $aclCsv = gam print shareddriveacls matchname "$sharedDriveName" oneitemperrow fields emailaddress,role,type 2>$null | ConvertFrom-Csv

    $owners = @(
        $aclCsv |
        Where-Object {
            $_.emailaddress -and
            $_.type -ne "domain" -and
            $_.role -eq "organizer"
        } |
        Select-Object -ExpandProperty emailaddress -Unique
    )

    $members = @(
        $aclCsv |
        Where-Object {
            $_.emailaddress -and
            $_.type -ne "domain" -and
            $_.role -ne "organizer"
        } |
        Select-Object -ExpandProperty emailaddress -Unique
    )

    if (-not $owners -or $owners.Count -eq 0) {
        $owners = @($DefaultOwner)
        Write-Host "[$index/$total] No había propietario en Google. Se usará: $DefaultOwner" -ForegroundColor DarkYellow
    }

    $primaryOwner = $owners[0]

    Write-Host "[$index/$total] Creando sitio..." -ForegroundColor Cyan
    New-SPOSite `
        -Url $siteUrl `
        -Title $sharedDriveName `
        -Owner $primaryOwner `
        -Template "STS#3" `
        -StorageQuota $StorageQuotaMB `
        -NoWait

    Start-Sleep -Seconds 10

    $ownersGroupName = "$sharedDriveName Owners"
    $membersGroupName = "$sharedDriveName Members"

    Write-Host "[$index/$total] Agregando propietarios..." -ForegroundColor Cyan
    foreach ($owner in $owners) {
        try {
            Add-SPOUser -Site $siteUrl -LoginName $owner -Group $ownersGroupName
            Set-SPOUser -Site $siteUrl -LoginName $owner -IsSiteCollectionAdmin $true
            Write-Host "    OK Owner: $owner" -ForegroundColor Green
        }
        catch {
            Write-Host "    ERROR Owner: $owner" -ForegroundColor Red
        }
    }

    Write-Host "[$index/$total] Agregando miembros..." -ForegroundColor Cyan
    foreach ($member in $members) {
        try {
            Add-SPOUser -Site $siteUrl -LoginName $member -Group $membersGroupName
            Write-Host "    OK Member: $member" -ForegroundColor Green
        }
        catch {
            Write-Host "    ERROR Member: $member" -ForegroundColor Red
        }
    }

    $row.SiteUrl = $siteUrl
    Save-WorkingCsv -Rows $rows -Path $CsvPath

    Write-Host "[$index/$total] URL escrita en CSV: $siteUrl" -ForegroundColor Green
    Write-Host "[$index/$total] Sitio completado." -ForegroundColor Magenta
}

Write-Host ""
Write-Host "Proceso finalizado." -ForegroundColor Cyan