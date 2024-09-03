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
    [string]$passwordServer

)

$paramSet = $PSCmdlet.ParameterSetName

if ($paramSet -eq 'Multiple') {
    Write-Output "Iniciando la migración para el usuario: $user"
    ADMT USER /includefile:"$userListFilePath" /SD:"$sourceDomain" /TD:"$destinationDomain" /TO:"$targetOU" /migratesids:YES /passwordoption:copy /passwordserver:"$passwordServer" /disableoption:targetsameassource /migrategroups:yes /conflictoptions:merge
    Write-Output "Migración completada para múltiples usuarios."
}
else {
    Write-Output "Iniciando la migración para el usuario: $userName"
    ADMT USER /N "$userName" /SD:"$sourceDomain" /TD:"$destinationDomain" /TO:"$targetOU" /migratesids:YES /passwordoption:copy /passwordserver:"$passwordServer" /disableoption:targetsameassource /migrategroups:yes /conflictoptions:merge
    Write-Output "Migración completada para el usuario: $userName"
}
