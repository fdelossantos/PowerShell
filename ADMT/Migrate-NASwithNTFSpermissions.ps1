[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Folder,
    [Parameter(Mandatory=$false)]
    [string]$OldDomain = "GMTR",
    [Parameter(Mandatory=$false)]
    [string]$NewDomain = "FVMZES"
)

# $FolderBase = "\\fsbcn01\Administracion"
$FolderBase = "\\10.32.2.254\ignacio_test"

$Folders = Get-childItem $FolderBase -Recurse -Directory

foreach ($TempFolder in $Folders)
{
    if ($TempFolder.BaseName -eq "lost+found") {
        continue
    }
    $Folder = $TempFolder.FullName


    $acl = Get-Acl $Folder

    foreach ($ace in $acl) {
        #$newace = $ace.Access
        foreach ($rule in $ace.Access) {
            $usuarioviejo = $rule.IdentityReference.Value
    
            $user = $usuarioviejo -replace $OldDomain, $NewDomain
            $idRef = New-Object System.Security.Principal.NTAccount($user)
        
            # $rule.IdentityReference = $idRef
            $permission1 = $user,$rule.FileSystemRights, $rule.InheritanceFlags, $rule.PropagationFlags, $rule.AccessControlType
            $newrule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission1
        
            $acl.AddAccessRule($newrule)
        }
    
    }
    Set-Acl $Folder $acl
}