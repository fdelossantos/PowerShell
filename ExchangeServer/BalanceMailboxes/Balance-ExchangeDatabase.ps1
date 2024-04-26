[CmdletBinding(SupportsShouldProcess=$True)]
param(
    [Parameter(Mandatory)]
    [string]$origen = "Base1-Estandar-1",
    [Parameter(Mandatory)]
    [string[]]$destinos = @("Base1-Estandar-2", "Base1-Estandar-3"),
    [Parameter(Mandatory)]
    [string]$logFile = "C:\temp\MovimientoBuzones.log"
)

#TotalItemSize no viene en numérico
# 3.565 GB (3,827,586,391 bytes)
$buzones = Get-MailboxStatistics -Database $origen | Sort-Object TotalItemSize -Descending

$i = 0
$ahora = Get-Date

# Recorrer los buzones de a 3
foreach ($buzon in $buzones) {
    # Calcular índice de destino basado en el contador
    $indexDestino = $i % 3
    $destino = $destinos[$indexDestino - 1] # El índice empieza en cero

    $horainicio = $ahora.AddHours($i)
    
    # Sólo mover los 2 primeros buzones de cada terna
    if ($indexDestino -lt 2) {
        # Ejecutar el movimiento del buzón
        if ($PSCmdlet.ShouldProcess()){
            Write-Host "Moviendo buzón $($buzon.MailboxGuid) a $destino con inicio $horainicio".
            New-MoveRequest -Identity $buzon.MailboxGuid -TargetDatabase $destino -AllowLargeItems -StartAfter $horainicio -WhatIf
        }
        else {
            Write-Host "Moviendo buzón $($buzon.MailboxGuid) a $destino con inicio $horainicio".
            New-MoveRequest -Identity $buzon.MailboxGuid -TargetDatabase $destino -AllowLargeItems -StartAfter $horainicio
        }

        # Registrar el movimiento
        $log = "Moved: $($buzon.DisplayName) a $destino"
        Add-Content -Path $logFile -Value $log
    } else {
        # Buzón que no se mueve
        $log = "Skipped: $($buzon.DisplayName)"
        Add-Content -Path $logFile -Value $log
    }
    
    $i++
}

# Finalizar script
Write-Host "Proceso completado. Log en: $logFile"