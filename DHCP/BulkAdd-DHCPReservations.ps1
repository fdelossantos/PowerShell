# Input: servers.txt, a tab-separated value with 2 columns: Nombre, IP
$DHCPServerName = "SRVDC01"
$ScopeId = "10.1.1.0"

$servers = Import-Csv .\servers.txt -Delimiter "`t"
foreach ($computer in $servers) {
    $macAddress = ""
    try{
        $resultados = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $computer.Nombre -ErrorAction Stop
        $macAddress = ($resultados | where {$_.IPAddress -contains $computer.IP} | Select-Object -Property MACAddress).MACAddress
        if (-not ([string]::IsNullOrEmpty($macAddress))) {
            Write-Host "$($computer.Nombre) have a MAC $($macAddress)"
        }
    }
    catch {
        Write-Host "$($computer.Nombre) is not Windows or does not allow WMI."
        Test-Connection $computer.IP -Count 1 -Quiet
        $macAddress = (Get-NetNeighbor -IPAddress $computer.IP).LinkLayerAddress
        if (-not ([string]::IsNullOrEmpty($macAddress))) {
            Write-Host "$($computer.Nombre) have a MAC $($macAddress)"
        }
    }
    $macStr = $macAddress.Replace(":", "").Replace("-", "")

    if (-not ([string]::IsNullOrEmpty($macStr))) {
        try {
            Add-DhcpServerv4Reservation -ScopeId $ScopeId -ComputerName $DHCPServerName -IPAddress $computer.IP `
            -ClientId $macStr -Name $computer.Nombre -Type Dhcp -ErrorAction Stop

            Write-Host "Added: $($computer.Nombre) ($($computer.IP)) with MAC $($macAddress)"
        }
        catch {
            Write-Host "Cannot add reservation for $($computer.Nombre). $($Error[0].Exception)."
        }
    }
}