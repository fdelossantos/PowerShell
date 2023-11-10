$hash =@{}
$archivo = import-csv C:\Work\uno.csv -Delimiter "," -Encoding utf8

foreach ($fila in $archivo) {
    if ($hash[$fila.Name] -eq $null) {
        $hash.add($fila.Name, $fila.Lastlogon)
        }

    else {
        if ($hash[$fila.Name] -lt $fila.Lastlogon) {
            $hash[$fila.Name] = $fila.Lastlogon
        }
    }
}

$exportable = @()
$hash.GetEnumerator() | Sort-Object $_.Key |
    ForEach-Object{
        $myObject = [PSCustomObject]@{
            Name = $_.Name
            Value = [datetime]::FromFileTime($_.Value)
        }
        $exportable += $myObject
    }
$exportable | Export-Csv C:\Work\salida.csv -Delimiter ";" -NoTypeInformation -Encoding utf8