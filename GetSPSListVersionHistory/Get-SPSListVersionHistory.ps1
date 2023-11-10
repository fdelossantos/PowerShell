param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ListName,

    #[Parameter(Mandatory)]
    #[ValidateNotNullOrEmpty()]
    #[int]$ItemId,

    [string]$FieldNames = ""
)
#$FieldNames = "Numero,FechaReclamo,Title,Sucursal,Motivo"
Connect-PnPOnline -Url $SiteUrl -Interactive

$todosLosItems = Get-PnPListItem -List $ListName -PageSize 2000 -ScriptBlock { Param($items) $items.Context.ExecuteQuery()}

$listItemVersionHistory = @()

foreach ($item in $todosLosItems) {
    #$geitem = Get-PnPListItem -List $ListName -Id $ItemId
    $file = Get-PnPProperty -ClientObject $item -Property File #FieldValues
    $versions = Get-PnPProperty -ClientObject $item -Property Versions
    #$fileVersions = Get-PnPProperty -ClientObject $file -Property Versions


    
    foreach ($version in $versions) {   

        #$checkInComment = $fileVersions | Where-Object { $_.VersionLabel -eq $version.VersionLabel } | Select-Object -ExpandProperty CheckInComment
        $fieldValues = $version.FieldValues

        $fieldValuesFormatted = New-Object -TypeName PSObject
        foreach ($field in $fieldValues.GetEnumerator()) {
            $fieldName = $field.Key
            $fieldValue = $field.Value
            if ([string]::IsNullOrEmpty($FieldNames) -or ($FieldNames.Split(',') -contains $fieldName)) {
                $fieldValuesFormatted | Add-Member -MemberType NoteProperty -Name $fieldName -Value $fieldValue
            }
        }    
    
        $listItemVersionHistory += [PSCustomObject]@{
            ListName = $ListName
            VersionLabel = $version.VersionLabel
            VersionId = $version.VersionId
            IsCurrentVersion = $version.IsCurrentVersion
            Created = $version.Created
            #CreatedBy = Get-PnPProperty -ClientObject $version.CreatedBy -Property Title
            FieldValues = $fieldValuesFormatted | ConvertTo-Json -Compress
            #CheckInComment = $checkInComment
        }
    }

} 


# Write-Output $listItemVersionHistory
$listItemVersionHistory | Export-Csv -Path "c:\Work\lista.csv" -Delimiter ";" -Encoding utf8