Connect-ExchangeOnline

# Dominio interno para completar alias
$dominio = "dominio.com.uy"

# Archivo CSV delimitado por ;
$datos = Import-Csv -Path "E:\Work\NS\dl3.csv" -Delimiter ';'

# Lista para registrar errores
$errores = @()

foreach ($fila in $datos) {

    $displayName = $fila.DisplayName
    $primaryEmail = $fila.PrimaryEmail
    $miembros = $fila.Members -split ','

    Write-Host "`nCreando lista de distribución: $displayName ($primaryEmail)..."

    # Crear la DL si no existe
    $dl = Get-DistributionGroup -Identity $primaryEmail -ErrorAction SilentlyContinue
    if (-not $dl) {
        $dl = New-DistributionGroup -Name $displayName `
                                    -DisplayName $displayName `
                                    -PrimarySmtpAddress $primaryEmail `
                                    -Type Distribution
    }

    # Habilitar recepción externa
    Set-DistributionGroup -Identity $primaryEmail -RequireSenderAuthenticationEnabled $false

    foreach ($m in $miembros) {

        $m = $m.Trim()

        # Determinar si es alias o email completo
        if ($m -match "@") {
            $email = $m
        } else {
            $email = "$m@$dominio"
        }

        # Validar si existe como usuario o como DL
        $obj = Get-Recipient -Identity $email -ErrorAction SilentlyContinue

        if ($null -eq $obj) {
            Write-Warning "No se encontró el miembro '$m' para agregar a $primaryEmail"
            $errores += [PSCustomObject]@{
                Lista   = $primaryEmail
                Miembro = $m
                Motivo  = "No existe en el tenant"
            }
            continue
        }

        # Intentar agregar
        try {
            Add-DistributionGroupMember -Identity $primaryEmail -Member $email -ErrorAction Stop
            Write-Host "Agregado: $email"
        }
        catch {
            Write-Warning "Error agregando $email a $primaryEmail"
            $errores += [PSCustomObject]@{
                Lista   = $primaryEmail
                Miembro = $email
                Motivo  = $_.Exception.Message
            }
        }
    }
}

# Reporte final
if ($errores.Count -gt 0) {
    Write-Host "`n--- RESUMEN DE ERRORES ---" -ForegroundColor Yellow
    $errores | Format-Table -AutoSize
} else {
    Write-Host "`nTodas las listas y miembros fueron procesados sin errores." -ForegroundColor Green
}