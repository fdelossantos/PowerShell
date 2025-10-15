param(
  [Parameter(Mandatory)][string]$AdCsv,
  [Parameter(Mandatory)][string]$GoogleCsv,
  [Parameter(Mandatory)][string]$OutCsv,
  [char]$Delimiter = ';' 
)

$adSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
Import-Csv -Path $AdCsv | ForEach-Object {
  $e = ($_.ADDSEmail).ToString().Trim()
  if ($e) { [void]$adSet.Add($e) }
}

Import-Csv -Path $GoogleCsv |
  Where-Object {
    $pe = ($_.primaryEmail).ToString().Trim()
    $pe -and -not $adSet.Contains($pe)
  } |
  Select-Object `
    @{n='displayName';e={
        $dn = $_."name.displayName"
        if ([string]::IsNullOrWhiteSpace($dn)) { $dn = $_."name.fullName" }
        if ([string]::IsNullOrWhiteSpace($dn)) { $dn = $_.displayName }
        if ([string]::IsNullOrWhiteSpace($dn)) {
          $gn = $_."name.givenName"; $sn = $_."name.familyName"
          $dn = ("$gn $sn").Trim()
        }
        $dn
      }},
    @{n='primaryEmail';e={$_.primaryEmail}},
    @{n='orgUnitPath';e={$_.orgUnitPath}} |
  Export-Csv -Path $OutCsv -NoTypeInformation -Encoding utf8BOM -Delimiter $Delimiter
