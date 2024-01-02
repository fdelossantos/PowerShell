# Parameters
$configs = Get-Content -Raw ".\.configs.json" | ConvertFrom-Json -ErrorAction Stop

$cfToken = $configs.cfToken
$company = $configs.company
$domain = $configs.domain
$contact = $configs.contact
$basePathLog = $configs.basePathLog
# ---------

$stringDate = (Get-Date).ToString('yyyyMMdd')
$pathLog = "$basePathLog\$($company)$($stringDate).txt"
Start-Transcript -Path $pathLog
$error.Clear()

Import-Module Posh-Acme

$pArgs = @{
    CFToken = ConvertTo-SecureString -String $cfToken  -AsPlainText -Force
}

$stringDate = (Get-Date).ToString('yyyyMMdd')
$friendlyName = "$company $($stringDate)"

New-PACertificate $domain,"*.$domain" -Plugin Cloudflare -PluginArgs $pArgs -Install -FriendlyName $friendlyName -AcceptTOS -Contact $contact
$thumb = (Get-PACertificate).Thumbprint
$certificado = Get-PACertificate | fl

Import-Module IISAdministration
$sitios = Get-IISSite
$tabla = @{}
foreach ($sitio in $sitios ) {
    $nombre = $sitio.Name
    $bindings = Get-IISSiteBinding -Name $nombre -Protocol https

    foreach ($binding in $bindings) {
        $bindinginfo = $binding.bindingInformation
        $tabla.Add($nombre, $bindinginfo)
    }
}

foreach ($sitio in $tabla.Keys) { 
    Remove-IISSiteBinding -Name $sitio -Protocol https -BindingInformation $tabla[$sitio] -Confirm:$false -ErrorAction SilentlyContinue
    New-IISSiteBinding -Name $sitio -BindingInformation $tabla[$sitio] -Protocol https -CertificateThumbPrint $thumb -CertStoreLocation 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue
}

Stop-Transcript

Send-MailMessage -From $configs.MailFrom -To $configs.MailContact -Subject "Renovación de Certificado $domain" -Body "Resultado:\n\n $certificado \n\ Errores:\n\n $error" -Attachments $pathLog -SmtpServer $configs.SmtpServer -Encoding 'UTF8'