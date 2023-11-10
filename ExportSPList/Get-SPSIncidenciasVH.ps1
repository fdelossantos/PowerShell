
$SiteUrl = "https://tenant.sharepoint.com/"
$ListName = "ListName"

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

        
        $listItemVersionHistory += [PSCustomObject]@{
            ListName = $ListName
            VersionLabel = $version.VersionLabel
            VersionId = $version.VersionId
            IsCurrentVersion = $version.IsCurrentVersion
            Created = $version.Created
            FieldValues = $fieldValuesFormatted | ConvertTo-Json -Compress
            Title = $fieldValues['Title']
            Numero = $fieldValues['Numero']
            Fecha = $fieldValues['Fecha']
            Tipo_x0020_de_x0020_Incidencia = $fieldValues['Tipo_x0020_de_x0020_Incidencia'].LookupValue
            Sucursal = $fieldValues['Sucursal'].LookupValue
            Fecha_x0020_y_x0020_Hora_x0020_I = $fieldValues['Fecha_x0020_y_x0020_Hora_x0020_I']
            Descripcion = $fieldValues['Descripcion']
            Titulo = $fieldValues['Titulo']
            Sector_x0020_a_x0020_Asignar = $fieldValues['Sector_x0020_a_x0020_Asignar'].LookupValue
            Estado = $fieldValues['Estado'].LookupValue
            Enviar_x0020_a = $fieldValues['Enviar_x0020_a']
            CC = $fieldValues['CC']
            Tratamiento_x0020_inmediato = $fieldValues['Tratamiento_x0020_inmediato']
            Historial_x0020_accidentes_x002f = $fieldValues['Historial_x0020_accidentes_x002f']
            ID = $fieldValues['ID']
            Modified = $fieldValues['Modified']
            Author = $fieldValues['Author'].LookupValue
            Editor = $fieldValues['Editor'].LookupValue
            AnalisisdeCausa = $fieldValues['AnalisisdeCausa']
        }
    }

} 


# Write-Output $listItemVersionHistory
$listItemVersionHistory | Export-Csv -Path "c:\Work\lista-ListName.csv" -Delimiter ";" -Encoding utf8