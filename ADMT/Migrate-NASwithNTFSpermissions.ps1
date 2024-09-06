[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$Folder
)

#$Folders = Get-childItem \\fsbcn01\Administracion -Recurse -Directory

$Folder = \\fsbcn01\Administracion

$acl = Get-Acl $Folder

foreach ($ace in $acl) {
    $newace = $ace.Access
    $usuarioviejo = $ace.Access.IdentityReference

    $user = $ace.Access.IdentityReference -replace "GMTR", "FVMZES"
    $idRef = New-Object System.Security.Principal.NTAccount($user)

    $newace.IdentityReference = $idRef

    $acl.AddAccessRule($accessRule)
}



$permission1 = "Dominio\Domain Admins","Full Control", $InheritanceFlag, $PropagationFlag, $objType
$accessRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
foreach ($TempFolder in $Folders)
{
    $Folder = $TempFolder.FullName

    $acl = Get-Acl $Folder
    
    $permission1 = "Dominio\Domain Admins","Full Control", $InheritanceFlag, $PropagationFlag, $objType
    $accessRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule $permission1
    $permission2 = "Dominio\UsuariosRegistros","Modify", $InheritanceFlag, $PropagationFlag, $objType
    $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule $permission2

    $acl.AddAccessRule($accessRule)
    $acl.AddAccessRule($accessRule2)
    
    Set-Acl $Folder $acl
} 