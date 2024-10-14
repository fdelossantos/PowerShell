[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$FolderBase,
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    [Parameter(Mandatory=$true)]
    [string]$NewDomain,
    [Parameter(Mandatory=$false)]
    [string]$TermDictionary=".\migratentfstranslations.json"
)

# Load Translations
$dict = Get-Content $TermDictionary -Raw | ConvertFrom-Json

# -------- Processing root folder --------

$Folder = $FolderBase

Write-Host "Processing $Folder"

$acl = Get-Acl $Folder

foreach ($ace in $acl) {
    foreach ($rule in $ace.Access) {
        $usuarioviejo = $rule.IdentityReference.Value

        if ($usuarioviejo -eq "Todos" -or $usuarioviejo -eq "Everyone") {
            continue
        }

        $user = $usuarioviejo -replace $OldDomain, $NewDomain
        foreach ($key in $dict.PSObject.Properties.Name){
            $value= $dict.$key
            $user = $user -replace [regex]::Escape($key), $value
        }
        #$user = $user -replace "Admins. del dominio", "Domain Admins"
        #$user = $user -replace "Usuarios del dominio", "Domain Users"
        Write-Host "Getting user '$user' for '$usuarioviejo'."
        #$idRef = New-Object System.Security.Principal.NTAccount($user)
    
        $permission1 = $user,$rule.FileSystemRights, $rule.InheritanceFlags, $rule.PropagationFlags, $rule.AccessControlType
        $newrule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission1
    
        $acl.AddAccessRule($newrule)
    }
}
Write-Host "Setting acl for $Folder"
Set-Acl $Folder $acl

# -------- Processing subfolders --------

$Folders = Get-childItem $FolderBase -Recurse -Directory

foreach ($TempFolder in $Folders)
{
    
    if ($TempFolder.BaseName -eq "lost+found") {
        continue
    }
    $Folder = $TempFolder.FullName

    Write-Host "Processing $Folder"

    $acl = Get-Acl $Folder

    foreach ($ace in $acl) {
        foreach ($rule in $ace.Access) {
            $usuarioviejo = $rule.IdentityReference.Value
            if ($usuarioviejo -eq "Todos" -or $usuarioviejo -eq "Everyone") {
                continue
            }
            $user = $usuarioviejo -replace $OldDomain, $NewDomain
            foreach ($key in $dict.PSObject.Properties.Name){
                $value= $dict.$key
                $user = $user -replace [regex]::Escape($key), $value
            }
            Write-Host "Getting user '$user' for '$usuarioviejo'."
            #$idRef = New-Object System.Security.Principal.NTAccount($user)
        
            $permission1 = $user,$rule.FileSystemRights, $rule.InheritanceFlags, $rule.PropagationFlags, $rule.AccessControlType
            $newrule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission1
        
            $acl.AddAccessRule($newrule)
        }
    }
    Write-Host "Setting acl for $Folder"
    Set-Acl $Folder $acl
}

Write-Host "Finished!"