# Máquinas Virtuales
$Prefijo = "Proyecto"
$VM01 = "$Prefijo-DC01"			# Nombre de VM 01
$VM02 = "$Prefijo-DFS01"		# Nombre de VM 02
$VM03 = "$Prefijo-MBX01"		# Nombre de VM 03
$VM04 = "$Prefijo-SQL01"		# Nombre de VM 04
$VM05 = "$Prefijo-IIS01"		# Nombre de VM 05

$CantidadDeVM = 5
$Procesadores = 2

# Memoria RAM
$RAM01 = 2GB					# RAM nivel 1
$RAM02 = 4GB					# RAM nivel 2
$RAM03 = 8GB					# RAM nivel 2
$UsarMemoriaDinamica = $true

# HDD
$DISK0 = 50GB		    		# Tamaño de disco C
$DISK1 = 80GB		    		# Tamaño de disco D

# Rutas a discos base, ISO y carpetas
$VMLOC = "D:\Hyper-V\$Prefijo"													# Ubicación de VM
$DiscoOrigen1 = "C:\Hyper-V\DISM\Virtual Hard Disks\DiscoBase1-Disk0.vhdx" # VHD SO 1 con Sysprep
#$DiscoOrigen2 = "D:\Hyper-V\Virtual hard disks\Template - Windows 10 1909 en-us.vhdx"															# VHD SO 2 con Sysprep
$NombreDiscoBase1 = "DiscoBase1"											# Nombre disco destino SO 1
#$NombreDiscoBase2 = "DiscoBase2"											# Nombre disco destino SO 2

# Virtual Switch
$NetworkSwitch1 = "Interno"		# Nombre de Switch Virtual
$NetworkSwitch2 = "Default Switch"		# Nombre de Switch Virtual

# ------------------------------------------------------------------------------------------------------

# Crear carpeta de VMs, copiar disco base 
MD $VMLOC -ErrorAction SilentlyContinue
MD "$VMLOC\\Virtual Hard Disks" -ErrorAction SilentlyContinue
COPY $DiscoOrigen1 "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx"
Set-ItemProperty "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx" -name IsReadOnly -value $true
if ($DiscoOrigen2 -ne "") {
    COPY $DiscoOrigen2 "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase2-Disk0.vhdx"
    Set-ItemProperty "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase2-Disk0.vhdx" -name IsReadOnly -value $true
}

# Se puede crear un Virtual Switch
$TestSwitch = Get-VMSwitch -Name $NetworkSwitch1 -ErrorAction SilentlyContinue; if ($TestSwitch.Count -EQ 0){New-VMSwitch -Name $NetworkSwitch1 -SwitchType Private}

# Crear discos de sistema
New-VHD –ParentPath "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx" –Path "$VMLOC\\$VM01\\Virtual Hard Disks\\$VM01-Disk0.vhdx" -Differencing
if ($CantidadDeVM -gt 1) {New-VHD –ParentPath "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx" –Path "$VMLOC\\$VM02\\Virtual Hard Disks\\$VM02-Disk0.vhdx" -Differencing}
if ($CantidadDeVM -gt 2) {New-VHD –ParentPath "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx" –Path "$VMLOC\\$VM03\\Virtual Hard Disks\\$VM03-Disk0.vhdx" -Differencing}
if ($CantidadDeVM -gt 3) {New-VHD -ParentPath "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx" –Path "$VMLOC\\$VM04\\Virtual Hard Disks\\$VM04-Disk0.vhdx" -Differencing}
if ($CantidadDeVM -gt 4) {New-VHD -ParentPath "$VMLOC\\Virtual Hard Disks\\$NombreDiscoBase1-Disk0.vhdx" –Path "$VMLOC\\$VM05\\Virtual Hard Disks\\$VM05-Disk0.vhdx" -Differencing}

# Crear Máquinas Virtuales
New-VM -Name $VM01 -Path $VMLOC -MemoryStartupBytes $RAM02 -VHDPath "$VMLOC\\$VM01\\Virtual Hard Disks\\$VM01-Disk0.vhdx" -SwitchName $NetworkSwitch1 -Generation 2
if ($CantidadDeVM -gt 1) {New-VM -Name $VM02 -Path $VMLOC -MemoryStartupBytes $RAM02 -VHDPath "$VMLOC\\$VM02\\Virtual Hard Disks\\$VM02-Disk0.vhdx" -SwitchName $NetworkSwitch1 -Generation 2}
if ($CantidadDeVM -gt 2) {New-VM -Name $VM03 -Path $VMLOC -MemoryStartupBytes $RAM03 -VHDPath "$VMLOC\\$VM03\\Virtual Hard Disks\\$VM03-Disk0.vhdx" -SwitchName $NetworkSwitch1 -Generation 2}
if ($CantidadDeVM -gt 3) {New-VM -Name $VM04 -Path $VMLOC -MemoryStartupBytes $RAM02 -VHDPath "$VMLOC\\$VM04\\Virtual Hard Disks\\$VM04-Disk0.vhdx" -SwitchName $NetworkSwitch1 -Generation 2}
if ($CantidadDeVM -gt 4) {New-VM -Name $VM05 -Path $VMLOC -MemoryStartupBytes $RAM02 -VHDPath "$VMLOC\\$VM05\\Virtual Hard Disks\\$VM05-Disk0.vhdx" -SwitchName $NetworkSwitch1 -Generation 2}

# Establecer memoria fija
Set-VMMemory -VMName $VM01 -DynamicMemoryEnabled $UsarMemoriaDinamica -ErrorAction SilentlyContinue
Set-VMMemory -VMName $VM02 -DynamicMemoryEnabled $UsarMemoriaDinamica -ErrorAction SilentlyContinue
Set-VMMemory -VMName $VM03 -DynamicMemoryEnabled $UsarMemoriaDinamica -ErrorAction SilentlyContinue
Set-VMMemory -VMName $VM04 -DynamicMemoryEnabled $UsarMemoriaDinamica -ErrorAction SilentlyContinue
Set-VMMemory -VMName $VM05 -DynamicMemoryEnabled $UsarMemoriaDinamica -ErrorAction SilentlyContinue


# Establecer procesadores
Set-VMProcessor $VM01 -Count $Procesadores -ErrorAction SilentlyContinue
Set-VMProcessor $VM02 -Count $Procesadores -ErrorAction SilentlyContinue
Set-VMProcessor $VM03 -Count $Procesadores -ErrorAction SilentlyContinue
Set-VMProcessor $VM04 -Count $Procesadores -ErrorAction SilentlyContinue
Set-VMProcessor $VM05 -Count $Procesadores -ErrorAction SilentlyContinue

# Quitar checkpoints automáticos
Set-VM -VMName $VM01 -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue
Set-VM -VMName $VM02 -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue
Set-VM -VMName $VM03 -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue
Set-VM -VMName $VM04 -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue
Set-VM -VMName $VM05 -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue

# Iniciar Máquinas Virtuales
Start-VM $VM01
if ($CantidadDeVM -gt 1) {
    Start-Sleep -s 30
    Start-VM $VM02
}
if ($CantidadDeVM -gt 2) {
    Start-Sleep -s 30
    Start-VM $VM03
}
if ($CantidadDeVM -gt 3) {
    Start-Sleep -s 30
    Start-VM $VM04
}
if ($CantidadDeVM -gt 4) {
    Start-Sleep -s 30
    Start-VM $VM05
}