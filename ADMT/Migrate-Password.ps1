# Script para migrar usuarios con ADMT o para migrar las contraseñas cambiadas de usuarios ya migrados

# Para migrar un usuario único
# .\Migrate-UserWithPassword.ps1 -userName usuariodos -sourceDomain dominio.local -destinationDomain nuevodominio.local -targetOU "TestMig" -passwordServer DC01 -destServer SRV01

# Para migrar un lote de usuarios
# Crear un archivo con los nombres de usuario o identidades, uno por línea de archivo
# .\Migrate-UserWithPassword.ps1 -userListFilePath C:\temp\usuarios.txt -sourceDomain dominio.local -destinationDomain nuevodominio.local -targetOU "TestMig" -passwordServer DC01 -destServer SRV01

param (
    [Parameter(ParameterSetName = 'Multiple', Mandatory=$true, Position=0)]
    [string]$userListFilePath,

    [Parameter(ParameterSetName = 'Single', Mandatory=$true, Position=0)]
    [string]$userName,

    [Parameter(ParameterSetName = 'Multiple', Mandatory=$true)]
    [Parameter(ParameterSetName = 'Single', Mandatory=$true)]
    [string]$sourceDomain,

    [Parameter(ParameterSetName = 'Multiple', Mandatory=$true)]
    [Parameter(ParameterSetName = 'Single', Mandatory=$true)]
    [string]$destinationDomain,

    [Parameter(ParameterSetName = 'Multiple', Mandatory=$true)]
    [Parameter(ParameterSetName = 'Single', Mandatory=$true)]
    [string]$targetOU,

    [Parameter(ParameterSetName = 'Multiple', Mandatory=$true)]
    [Parameter(ParameterSetName = 'Single', Mandatory=$true)]
    [string]$passwordServer,

    [Parameter(ParameterSetName = 'Multiple', Mandatory=$true)]
    [Parameter(ParameterSetName = 'Single', Mandatory=$true)]
    [string]$destServer

)

$paramSet = $PSCmdlet.ParameterSetName

if ($paramSet -eq 'Multiple') {
    Write-Output "Iniciando la migración para el usuario: $user"
    ADMT USER /includefile:"$userListFilePath" /SD:"$sourceDomain" /TD:"$destinationDomain" /TO:"$targetOU" /passwordoption:copy /passwordserver:"$passwordServer" /disableoption:targetsameassource /migrategroups:yes /conflictoptions:merge
    
    Write-Host "Esperando sincronización del dominio"
    $users = Get-Content $userListFilePath
    foreach ($user in $users) {
        0..20 | foreach { Start-Sleep -Seconds 1; Write-Host "." -NoNewline } 
        Write-Host ""

        Set-ADUser -Server $destServer -ChangePasswordAtLogon $false -Identity $user
        Write-Host "$user está listo."
    }

    Write-Output "Migración completada para múltiples usuarios."
}
else {
    Write-Output "Iniciando la migración para el usuario: $userName"
    ADMT USER /N "$userName" /SD:"$sourceDomain" /TD:"$destinationDomain" /TO:"$targetOU" /passwordoption:copy /passwordserver:"$passwordServer" /disableoption:targetsameassource /migrategroups:yes /conflictoptions:merge
    Write-Host "Esperando sincronización del dominio"
    0..20 | foreach { Start-Sleep -Seconds 1; Write-Host "." -NoNewline } 
    Write-Host ""
    Set-ADUser -Server $destServer -ChangePasswordAtLogon $false -Identity $userName
    Write-Output "Migración completada para el usuario: $userName"
} 
