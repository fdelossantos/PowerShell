$username = '$user'
$password = "password"

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))

$userAgent = "powershell/1.0"

$apiUrl = "https://azurewebapp.scm.azurewebsites.net/api/triggeredwebjobs/webjobname/run"

Invoke-WebRequest -Uri $apiUrl -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -UserAgent $userAgent -Method POST