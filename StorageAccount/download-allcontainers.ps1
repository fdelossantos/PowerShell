$StorageAccountName = ""
$DestRoot = (Join-Path $PWD "sa-$StorageAccountName")
$accountkey = ""
$sastoken = "?"
$accountUrl = "https://$StorageAccountName.blob.core.windows.net"
New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null

$containers = az storage container list --account-name $StorageAccountName --query "[].name" -o tsv --auth-mode key --account-key "$accountkey"

foreach ($c in $containers) {
  $dst = Join-Path $DestRoot $c
  New-Item -ItemType Directory -Path $dst -Force | Out-Null
  azcopy copy "$accountUrl/$c/$sastoken" "$dst" --recursive=true
}
Write-Host "Listo. Descargado en $DestRoot"
