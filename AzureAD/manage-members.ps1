# Este script toma los miembros de un grupo, los agrega a un segundo grupo 
# y los elimina de un tercer grupo.

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $GuidGrupoOrigen,
    [Parameter(Mandatory)]
    [string] $GuidGrupoDestino,
    [Parameter(Mandatory)]
    [string] $GuidGrupoQuitar
)
Connect-MgGraph -Scopes "Group.ReadWrite.All","GroupMember.Read.All","GroupMember.ReadWrite.All","User.ReadWrite.All"
# Los usuarios tienen que estar en una lista.
$grupoorigen = Get-MgGroup -GroupId $GuidGrupoOrigen
$grupodestino = Get-MgGroup -GroupId $GuidGrupoDestino
$grupoquitar = Get-MgGroup -GroupId $GuidGrupoQuitar

# Agregamos los usuarios al grupo MFA
Get-MgGroupMember -GroupId $grupoorigen.Id -All | 
    Select-Object -ExpandProperty Id | 
        ForEach-Object { 
            New-MgGroupMemberByRef -GroupId $grupodestino.Id `
            -BodyParameter @{ '@odata.id'="https://graph.microsoft.com/v1.0/directoryObjects/$_"} 
        }
# Quitamos los usuarios de autenticación sencilla.
Get-MgGroupMember -GroupId $grupoorigen.Id -All | 
    Select-Object -ExpandProperty Id | 
        ForEach-Object { 
            Remove-MgGroupMemberByRef -GroupId $grupoquitar.Id -DirectoryObjectId $_ 
        }