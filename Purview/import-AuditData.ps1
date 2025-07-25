$datos = Import-Csv .\downloadedauditdata.csv
$datos | foreach { ConvertFrom-Json $_.AuditData | Export-Csv .\plainauditdata.csv -Delimiter ";" -Append -NoTypeInformation -Encoding utf8 -Force } 