<# 
.SYNOPSIS 
Uninstall Fonts from users devices
 
.DESCRIPTION 
Below script will Uninstall all fonts copied inside Fonts directory to a target device 
 
.NOTES     
        Name       : Font Uninstallation Script
        Author     : Jatin Makhija  
        Version    : 1.0.0  
        DateCreated: 31-Jan-2023
        Blog       : https://cloudinfra.net
         
.LINK 
https://cloudinfra.net 
#>
#Get all fonts from Fonts Folder 
$Fonts = Get-ChildItem .\Fonts
$regpath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
foreach ($Font in $Fonts) {
    $fontname = $font.name
    $fontbasename = $font.basename
    If ($Font.Extension -eq ".ttf")  {$fontvalue = $Font.Basename + " (TrueType)"}
    elseif($Font.Extension -eq ".otf") {$fontvalue = $Font.Basename + " (OpenType)"}
    else {Write-Host " Font Extenstion not supported " -ForegroundColor blue -backgroundcolor white; break} 
    #Remove Font from Windows folder
    Remove-Item C:\windows\fonts\$fontname -force -EA SilentlyContinue
    #Delete corresponding registry keys for the font
    Remove-ItemProperty -Path $regpath -Name $fontvalue -force -EA SilentlyContinue
}