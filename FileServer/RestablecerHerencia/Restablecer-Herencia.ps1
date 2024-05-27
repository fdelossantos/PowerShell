$Folders = Get-childItem \\storage\Usuarios\Registros -Recurse -Directory
$InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$PropagationFlag = [System.Security.AccessControl.PropagationFlags]::None
$objType = [System.Security.AccessControl.AccessControlType]::Allow 

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