# PowerShell
My PowerShell functions to help me in my day by day

Test-CopiedFiles

This cmdlet helps the user to check if the copied files to another medium (like an external drive) has been copied without errors.

Parameters

string sourceFolder = Default: current folder. Folder where the original files resides.
string destFolder = (Required) Folder where the copied files resides.
string sourceMask = Default: "*.*". Mask to apply for filtering. This can be a file name or use Get-ChildItem wildcards.