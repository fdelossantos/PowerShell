Set-Location "C:\Work\HB\GPO\ReportsXML_WSUS"
$archivos = Get-ChildItem *

foreach ($gpoReport in $archivos) {
    [xml]$report = Get-Content $gpoReport.FullName
    #Select-Xml -Xml $report -XPath "//GPO"
    $report.DocumentElement.User.ExtensionData
    $report.GPO.Name #Nombre de la GPO
    
}