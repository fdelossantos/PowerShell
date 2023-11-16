<#
.SYNOPSIS
Delete-IISLogFiles.ps1 - Maintenance of IIS Log File

.DESCRIPTION 
Just delete the log files older than 7 days.

A log file is written every run.

.PARAMETER IISLogPath
The IIS log directory to cleanup.

.PARAMETER ScriptLogFolder
Script log path

.EXAMPLE
.\Delete-IISLogFiles.ps1 -LogPath "C:\inetpub\Logfiles\W3SVC1"
This example will compress the log files in "D:\IIS Logs\W3SVC1" and leave
the zip files in that location.

.EXAMPLE
Create a Basic Task in the Windows Task Scheduler
Program: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Arguments: -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Delete-IISLogFiles.ps1" -IISLogPath "C:\inetpub\logs\LogFiles" -ScriptLogFolder "C:\Scripts\LogsIIS"
Start in: C:\Scripts\LogsIIS

.LINK
https://github.com/fdelossantos/PowerShell

.NOTES
Author: Federico de los Santos
X:	https://twitter.com/federicod
Github:	https://github.com/fdelossantos

License:

The MIT License (MIT)

Copyright (c) 2023 Federico de los Santos

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

#>


[CmdletBinding()]
param (
	[Parameter(Mandatory)]
	[string]$IISLogPath,
    [Parameter(Mandatory)]
	[string]$ScriptLogFolder
	)


# +--------------------------------------------+
# |                 Variables                  |
# +--------------------------------------------+

$now = Get-Date
$output = "$ScriptLogFolder\$($now.ToString("yyyy-MM-dd"))_Delete_IIS_Logs.log"

# +--------------------------------------------+
# |                 Functions                  |
# +--------------------------------------------+

Function Write-Logfile($entry)
{
    # Write to log file
	$timestamp = Get-Date -DisplayHint Time
	"$timestamp $entry" | Out-File $output -Append
}

# +--------------------------------------------+
# |                    MAIN                    |
# +--------------------------------------------+

#Log file is overwritten each time the script is run to avoid
#very large log files from growing over time

$timestamp = Get-Date -DisplayHint DateTime
$timestamp | Out-File $output
"SERVER NAME: $($env:computername)" | Out-File $output -Append
Write-Logfile "Starting at $now"


# Test if path is correct
if ((Test-Path $IISLogPath) -ne $true)
{
    Write-Logfile "Log folder $IISLogPath was not found"
    EXIT
}

# Get list of log files older than 7 days
$filesToDelete = Get-ChildItem -Path "$($IISLogPath)\*.log" -Recurse | Where-Object {$_.CreationTime -lt $now.AddDays(-7) -and $_.PSIsContainer -eq $false}


foreach($file in $filesToDelete) 
{ 
    Write-Logfile "Removing $($file.FullName)."
    $Error.Clear()
    try {
        Remove-Item $file
        Write-Logfile "File removed succesfully."
    }
    catch {
        Write-Logfile "ERROR removing $($file.FullName)."
        Write-Logfile $Error
    }
    
}

Write-Logfile "Finish processing."