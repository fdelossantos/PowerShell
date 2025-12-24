[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $MailboxesFilePath,
    [Parameter(Mandatory)]
    [string]
    $ResultsFilePath
)

$buzones = Get-Content $MailboxesFilePath
$resultados = @()
foreach ($buzon in $buzones) {
    Write-Host "Procesando buzón: $buzon"
    
    # Obtener estadísticas del buzón de archivo
    $statsMain = Get-MailboxStatistics -Identity $buzon
    $statsArchive = Get-MailboxStatistics -Identity $buzon -Archive
    
    # Crear un objeto personalizado para almacenar la información
    $obj = [PSCustomObject]@{
        DisplayName   = $statsMain.DisplayName
        Email = $buzon
        MainTotalItemSize = $statsMain.TotalItemSize
        MainItemCount     = $statsMain.ItemCount
        ArchiveTotalItemSize = $statsArchive.TotalItemSize
        ArchiveItemCount     = $statsArchive.ItemCount
    }
    $resultados += $obj
    $obj | Export-Csv -Path $ResultsFilePath -Append -NoTypeInformation -Encoding UTF8 -Delimiter ";"
}

$resultados | ft
