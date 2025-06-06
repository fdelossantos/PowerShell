$URL = "http://app.formula.loca" 

# Inicialización de contadores
$clusterNodes = @{}
$arrNodes = @{}

# Tiempo de ejecución
$duration = 60  # en segundos
$interval = 1   # en segundos
$startTime = Get-Date

Write-Host "Iniciando test de NLB y ARR por $duration segundos..."

while ((Get-Date) -lt $startTime.AddSeconds($duration)) {
    try {
        # Realiza la solicitud HTTP y obtiene los headers
        $response = Invoke-WebRequest -Uri $URL -Method GET -UseBasicParsing

        # Extrae los headers relevantes
        $xClusterNode = $response.Headers["X-Clusternode"]
        $xArrNode = $response.Headers["X-Arrnode"]

        # Mostrar los valores recibidos
        Write-Host "X-Clusternode: $xClusterNode | X-Arrnode: $xArrNode"

        # Contabiliza los valores
        if ($xClusterNode) {
            if (-not $clusterNodes.ContainsKey($xClusterNode)) {
                $clusterNodes[$xClusterNode] = 0
            }
            $clusterNodes[$xClusterNode]++
        }

        if ($xArrNode) {
            if (-not $arrNodes.ContainsKey($xArrNode)) {
                $arrNodes[$xArrNode] = 0
            }
            $arrNodes[$xArrNode]++
        }

    } catch {
        Write-Host "Error en la solicitud HTTP: $_"
    }

    Start-Sleep -Seconds $interval
}

# Mostrar resultados
Write-Host "`n--- Estadísticas finales ---"

Write-Host "`nX-Clusternode:"
foreach ($key in $clusterNodes.Keys) {
    Write-Host "  $key : $($clusterNodes[$key]) veces"
}

Write-Host "`nX-Arrnode:"
foreach ($key in $arrNodes.Keys) {
    Write-Host "  $key : $($arrNodes[$key]) veces"
}
