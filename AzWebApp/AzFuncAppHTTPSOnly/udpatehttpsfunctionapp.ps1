$tenant = "dominio.com"
$subscription= "00000000-0000-0000-0000-000000000000"

Connect-AzAccount -Tenant $tenant -Subscription $subscription -ErrorAction Stop

$apps = Get-AzFunctionApp | where {$_.HttpsOnly -ne $true } 

foreach ($app in $apps)
{
    $app.HttpsOnly = $true
    Update-AzFunctionApp -InputObject $app
}

