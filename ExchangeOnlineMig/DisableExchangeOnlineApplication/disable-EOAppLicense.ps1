# Este script está sin terminar. Son ideas de cómo lograrlo. 
# La opción de usar una "License Option" parece no fucionar actualmente.

# Define the SkuId for Microsoft 365 Business Basic and Exchange Online Plan 1
$BusinessBasicSkuId = "O365_BUSINESS_ESSENTIALS"
$ExchangeOnlinePlan1Service = "EXCHANGE_S_STANDARD"
$ArchivingAddon = "EXCHANGE_S_ARCHIVE_ADDON"
$ExchangeFoundation = "EXCHANGE_S_FOUNDATION"

Connect-MsolService

Connect-Graph -Scopes User.ReadWrite.All, Organization.Read.All

$SkuSuscriptos = Get-MgSubscribedSku -All

$usuarios = Get-MsolUser -All | where {$_.Licenses.AccountSkuId -contains 'reseller-account:SPB'}

$EmsSku = Get-MgSubscribedSku -All | Where SkuPartNumber -eq $BusinessBasicSkuId # "SPB", O365_BUSINESS_PREMIUM, "O365_BUSINESS_ESSENTIALS"
 
$disabledPlans = $EmsSku.ServicePlans | where ServicePlanName -in $ExchangeOnlinePlan1Service | Select -ExpandProperty ServicePlanId
$addLicenses = @(
  @{SkuId = $EmsSku.SkuId
    DisabledPlans = $disabledPlans
  }
  )
foreach ($usuario in $usuarios) { 
    Set-MgUserLicense -UserId $usuario.ObjectId -AddLicenses $addLicenses -RemoveLicenses @()
}
