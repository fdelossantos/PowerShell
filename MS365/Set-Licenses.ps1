# CSV esperado:
# UPN,Licencia
# usuario@dominio.com,ENTERPRISEPACK
# usuario2@dominio.com,contoso:SPE_E3

$CsvPath = "E:\Work\Maosol\Licencias.csv"

Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement

Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "Organization.Read.All"

$LicenciasDisponibles = Get-MgSubscribedSku -All

$Usuarios = Import-Csv -Path $CsvPath

$Total = $Usuarios.Count
$Contador = 0

foreach ($Usuario in $Usuarios) {

    $Contador++

    $Upn = $Usuario.UPN.Trim()
    $LicenciaCsv = $Usuario.Licencia.Trim()

    Write-Progress `
        -Activity "Asignando licencias" `
        -Status "$Contador de $Total - $Upn" `
        -PercentComplete (($Contador / $Total) * 100)

    Write-Host "Procesando $Upn con licencia $LicenciaCsv..."

    try {

        # Permite que el CSV tenga ENTERPRISEPACK o tenant:ENTERPRISEPACK
        if ($LicenciaCsv -like "*:*") {
            $SkuPartNumber = ($LicenciaCsv -split ":", 2)[1]
        }
        else {
            $SkuPartNumber = $LicenciaCsv
        }

        $Sku = $LicenciasDisponibles | Where-Object {
            $_.SkuPartNumber -eq $SkuPartNumber
        }

        if (-not $Sku) {
            Write-Warning "No se encontró la licencia '$LicenciaCsv' para $Upn"
            continue
        }

        if ($Sku.Count -gt 1) {
            Write-Warning "La licencia '$LicenciaCsv' devolvió más de una coincidencia. Se omite $Upn"
            continue
        }

        $LicenciaAsignada = @{
            SkuId = $Sku.SkuId
        }
        Update-MgUser -UserId $Upn  -UsageLocation "UY"
    
        Set-MgUserLicense `
            -UserId $Upn `
            -AddLicenses @($LicenciaAsignada) `
            -RemoveLicenses @()

        Write-Host "OK - Licencia $($Sku.SkuPartNumber) asignada a $Upn" -ForegroundColor Green
    }
    catch {
        Write-Warning "ERROR procesando $Upn"
        Write-Warning $_.Exception.Message

        if ($_.ErrorDetails.Message) {
            Write-Warning $_.ErrorDetails.Message
        }
    }
}

Write-Progress `
    -Activity "Asignando licencias" `
    -Completed

# Disconnect-MgGraph

# Get-MgSubscribedSku -All | Select-Object SkuPartNumber, SkuId, ConsumedUnits, @{Name = "Enabled"; Expression = { $_.PrepaidUnits.Enabled }} | Sort-Object SkuPartNumber | Format-Table -AutoSize