# Parámetros
$user = 'DLopez'          # UPN o SAM de la cuenta afectada
$horasAntes  = 1                       # Ventana de tiempo (horas) antes de cada bloqueo
$horasDespues = 1                      # Ventana de tiempo (horas) después de cada bloqueo

# Dominio
$DCs = Get-ADDomainController -Filter * | Select-Object -Expand HostName

function Get-LockoutEvents {
    param(
        [string[]]$DomainControllers,
        [string]  $SamOrUpn,
        [int]     $HoursBefore  = 1,
        [int]     $HoursAfter   = 1
    )

    foreach ($dc in $DomainControllers) {

        # 1. Obtener todos los eventos 4740 (bloqueo) del usuario en este DC
        $lockouts = Get-WinEvent -ComputerName $dc -FilterHashtable @{LogName='Security'; Id=4740; Data=$SamOrUpn} -ErrorAction SilentlyContinue

        $total = $lockouts.Count
        $index = 0

        foreach ($e in $lockouts) {
            # 2. Barra de progreso
            $index++
            $pct = if ($total) { [int](($index / $total) * 100) } else { 100 }
            Write-Progress -Activity "Procesando bloqueos en $dc" `
                           -Status    "Evento $index de $total" `
                           -PercentComplete $pct

            # 3. Definir ventana temporal alrededor del bloqueo
            $from = $e.TimeCreated.AddHours(-$HoursBefore)
            $to   = $e.TimeCreated.AddHours( $HoursAfter)

            # 4. Obtener eventos relacionados (4625, 4771, 4776)
            $related = Get-WinEvent -ComputerName $dc `
                         -FilterHashtable @{
                             LogName   = 'Security'
                             Id        = @(4625, 4771, 4776)
                             StartTime = $from
                             EndTime   = $to
                             Data      = $SamOrUpn
                         } -ErrorAction SilentlyContinue

            # 5. Salida formateada
            [pscustomobject]@{
                DC             = $dc
                LockoutTime    = $e.TimeCreated
                CallerComputer = $e.Properties[1].Value
                RelatedEvents  = $related | Select-Object TimeCreated, Id, Message
            }
        }

        # 6. Completar la barra de progreso para este DC
        if ($total) {
            Write-Progress -Activity "Procesando bloqueos en $dc" -Completed
        }
    }
}


# Ejecución
$datos = Get-LockoutEvents -DomainControllers $DCs -SamOrUpn $user -HoursBefore $horasAntes -HoursAfter $horasDespues
$datos | Format-List *
