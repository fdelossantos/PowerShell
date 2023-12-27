<#
.SYNOPSIS

 Creates HTML Email Signatures and configures in OWA for all members of an organization in Exchange Online, or a specific one.

.DESCRIPTION

 This script creates and distributes email signatures for Exchange Online, for all users or a specific one. The created signature
 files are also stored in Azure Blob Container, where also can be retreived by client-side script to be set on Outlook Client en Windows.
 
 Execution considers the existence of 2 templates, but can be modified for one or many. The only parameter it allows is a given UserID
 ($env:USERNAME or %username%) and when specified it creates and sets OWA signature to the specified user. If no user is specified the script
 will process all existing users in Exchange Online.
 
 The script reads an existing html template and replaces text with queried data from Exchange Online (AzureAD), then writes an ouput .htm
 file based on each template, for each user.
 
 IMPORTANT: HTML templates are code-only. All images should be stored on public Image repositories and referenced by URL (https)
 
 
.PARAMETER

	UserID		If defined, the value of $env:USERNAME or %username% for domain users.
    
.NOTES 
	
	File Name: 	owa-signatures.ps1
	Version:	v1.0
	Date:		2020-12-02
	
	Authors:	Federico de los Santos - federico.delossantos@antatec.com
				Ignacio Garcia - ignacio@antatec.com
					
	Company:	Antares Techgroup
	URL:		www.antatec.com

    References:	https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
	
	Requires:	- PowerShell v2.0
				- Module "ExchangeOnlineManagement"
				- Module "Az"
				- App-only authentication for unattended scripts in the EXO V2 module.
	
	Fixes/Changes:
	
		Version 1.0	- First release

.EXAMPLE

	.\owa-signatures.ps1						-- For all users in Exchange Online organization.
	
	.\owa-signatures.ps1 -UserID username		-- For "username" in Exchange Online organization.	
	
	TASK Scheduler
	%SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe
	-executionpolicy bypass C:\Mazars\Scripts\owa-signatures.ps1
#>

<#

DISCLAIMER: This script should be thoroughly tested before use in a Production environment. You have a royalty-free right to use,  
modify, reproduce, and distribute this script file in any way you find useful, provided that you agree that the creator, owner    
above has no warranty, obligations, or liability for such use.                                                                    

#>

param([switch] $UserID)


### VARIABLE SETUP =============================================================================================================

# Remote Exchange & Azure Tenant  variables

$configs = Get-Content -Raw ".\.configs.json" | ConvertFrom-Json -ErrorAction Stop

$OrganizationName = $configs.OrganizationName	# Exchange Online organizarion name
$Application=$configs.Application				# AzureAD application ID
$Tumbprint=$configs.Tumbprint					# Certificate Tumbprint
$AzureTenant=$configs.AzureTenant				# Azure Tenant ID
$resourceGroupName=$configs.resourceGroupName	# Azure Resource Group Name
$storageAccName=$configs.storageAccName			# Azure Storage Account name
$ContainerName = $configs.ContainerName			# Azure Blob Container name
$emailDomain = $configs.emailDomain
# Local variables

$strTemplatePath = $configs.strTemplatePath		# Template HTML file path
$strSignaturesPath = $configs.strSignaturesPath	# Output path for HTML signatures


### IMPORT MODULES =============================================================================================================

# Import rewuired modules
Import-Module ExchangeOnlineManagement
#Import-Module Az
Import-Module Az.Storage
Import-module Az.Accounts

### EXECUTION START ============================================================================================================

cls
Write-Host @"

=============================================================================
          EXCHANGE ONLINE EMAIL SIGNATURE GENERATOR AND DEPLOYER
=============================================================================

Exchange Organization: $($OrganizationName)

Connecting with Exchange Online...
"@


# Connecting Exchange Onlline

Connect-ExchangeOnline -AppId $Application -CertificateThumbprint $Tumbprint -Organization $OrganizationName -ShowBanner:$false | Out-Null


Write-Host "Done. `n `nConnecting to Azure Tenant..."


# Connecting Azure Tenant

Connect-AzAccount -CertificateThumbprint $Tumbprint -ApplicationId $Application -Tenant $AzureTenant | Out-Null
$ctx=(Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccName).Context

# Get Last run date as an Extended Property
$lastRunRegistry = Get-ItemProperty -Path "HKCU:\Software\OWASignatures\" -Name "LastRun" -ErrorAction SilentlyContinue
if ($null -eq $lastRunRegistry) {
    $lastRunDate = [DateTime]0
}
else {
    $lastRunDate = $lastRunRegistry.LastRun
}
#$lastRunDate = (Get-Date).AddDays(-1)

#Define Run Mode (specific user or all mailboxes)

if (($UserID) -and ($args -ne "")) {
    
	Write-Host "Verifying User: $args"
	
	$Mbx = Get-EXORecipient -Identity "$args@$emailDomain" -RecipientTypeDetails UserMailbox -ResultSize Unlimited -PropertySets All -ErrorAction Stop
	$ProgDelta = 1; $CheckCount = 0
	$MbxCount = 1

} else {

	$isPlural = "es"

	$Mbx = Get-EXORecipient -RecipientTypeDetails UserMailbox -ResultSize Unlimited -PropertySets All `
			| Where-Object {$_.WhenChanged -ge $lastRunDate}
	$MbxCount = $Mbx.count
	if ($MbxCount -ne 0){
		$ProgDelta = 100/$MbxCount; $CheckCount = 0
	}
	else {
		$ProgDelta = 0
	}     
}

Write-Host "Done. `n `nRetrieving user data form Exchange and generating signatures..."

# Processing Mailboxes
ForEach ($M in $Mbx) {
    $MbxNumber++
    $MbxStatus = $M.DisplayName + " ["+ $MbxNumber +"/" + $MbxCount + "]"
    Write-Progress -Activity "Procesando buzón" -Status $MbxStatus -PercentComplete $CheckCount
    $CheckCount += $ProgDelta

    # User Data
    $username = ($M.WindowsLiveID -split '@')[0]
    $strName = $M.DisplayName
    $strTitle = $M.Title
    $strCompany = $M.Company
    $strDepartment = " - "+$M.Department; if ($strDepartment -eq " - " ) { $strDepartment = "" }
    $strStreet = $M.Office
    $strEmail = $M.PrimarySmtpAddress

    # Not used
    $strCred = $M.Notes
    $strPhone = $M.Phone
    $strCity =   $M.City
    $strPostCode = $M.PostalCode
    $strCountry = $M.CountryOrRegion
    $strFuncion = $M.Description

    # Non-existent
    # $strWebsite = $M.wWWHomePage
    # $strFax = $M.facsimileTelephoneNumber
    
    
    # Define template files array
	$strTemplates = (Get-ChildItem -Path "$strTemplatePath" -Filter "template*.htm").FullName
	
	# Process templates and create signature files
	Foreach ($t in $strTemplates) {
		$a,$b = "$t" -split "_"
		$source_file = "$t"
		$destination_file =  "$($strSignaturesPath)\$($username)_$b"
		(Get-Content $source_file) | Foreach-Object {
			$_ -replace 'DISPLAYNAME', "$strName" `
			   -replace 'TITLE', "$strTitle" `
			   -replace 'COMPANYNAME', "$strCompany" `
			   -replace ' - DEPARTMENT', "$strDepartment" `
			   -replace 'EMAIL', "$strEmail" `
			   -replace 'STREETADDR', "$strStreet" `
			   -replace 'PHONE', "$strPhone" `
			   -replace 'CITY', "$strCity" `
			   -replace 'POSTCODE', "$strPostCode" `
			   -replace 'COUNTRY', "$strCountry" `
			   -replace 'FUNCTION', "$strFunction" `
		} | Set-Content $destination_file -Encoding UTF8 -Force
	}
	
	# Find signature files for OWA.
	
	[string]$strOwaSignatureNew = (Get-Content (Get-ChildItem -Path "$strSignaturesPath" -Filter "$($username)_NEW.htm").FullName)
    #[string]$strOwaSignatureReply = (Get-Content (Get-ChildItem -Path "$strSignaturesPath" -Filter "$($username)_NEW.htm").FullName)

	# Write signatures for new an reply emails to OWA profile and set default.
	
    Set-MailboxMessageConfiguration -Identity $M.Identity -SignatureHTML $strOwaSignatureNew -AutoAddSignature $True -AutoAddSignatureOnReply $True
    #Set-MailboxMessageConfiguration -Identity $M.Identity -SignatureHTML $strOwaSignatureReply -AutoAddSignature $False -AutoAddSignatureOnReply $True
    
	# Define user signatures files array
	
	$strSignatures = (Get-ChildItem -Path "$strSignaturesPath" -Filter "$($username)*.htm").FullName

	# Copy user signatures to Azure Blob Container
    
	Foreach ($s in $strSignatures) {
		$c,$d = "$s" -split "_"
		Set-AzStorageBlobContent -File "$s" -Container $ContainerName -Blob "$($username)_$d" -Context $ctx -Force | Out-Null
	}

}

# Save the current date as an Extended Property
$currentDate = Get-Date
if ((Test-Path -Path "HKCU:\Software\OWASignatures\") -eq $false) {
	New-Item -Path "HKCU:\Software" -Name "OWASignatures"
}
Set-ItemProperty -Path "HKCU:\Software\OWASignatures\" -Name "LastRun" -Value $currentDate


Write-Host "Done. `n `nDisconnecting form online services..."

Disconnect-ExchangeOnline  -Confirm:$false *>&1 | Out-Null
Disconnect-AzAccount -Confirm:$false *>&1 | Out-Null

write-host "Done. `n"

Write-Host @"
Process completed successfully.
Signatures created/updated for $($MbxCount) mailbox$($isPlural).
"@

Get-PSSession | Remove-PSSession