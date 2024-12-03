Get-ChildItem -Path "C:\temp\remplazar" -Filter "*.txt" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'FSBCN01', '10.32.1.230' | Set-Content $_.FullName
}
