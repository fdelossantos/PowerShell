# Parámetros
$server = "mail.domain.uy"
$port = 995  # Puerto estándar para POP3 sobre SSL
$username = "dom\user"
$password = Read-Host "Ingrese la contraseña"

$client = New-Object Net.Sockets.TcpClient

$client.Connect($server, $port)

$stream = $client.GetStream()

# Opciones
$sslOptions = New-Object System.Net.Security.SslClientAuthenticationOptions
$sslOptions.TargetHost = $server
$sslOptions.EnabledSslProtocols = [System.Security.Authentication.SslProtocols]::Tls12
$sslOptions.EncryptionPolicy = [System.Net.Security.EncryptionPolicy]::RequireEncryption
# $sslOptions.ClientCertificates = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection
$sslOptions.CertificateRevocationCheckMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck


$sslStream = New-Object System.Net.Security.SslStream($stream, $false)

#$sslStream = New-Object System.Net.Security.SslStream($stream, $false, {
#        param($sender, $certificate, $chain, $sslPolicyErrors)
#       return $true}, $null)
    
$sslStream.AuthenticateAsClient($sslOptions)

$reader = New-Object System.IO.StreamReader($sslStream)
$writer = New-Object System.IO.StreamWriter($sslStream)
$writer.AutoFlush = $true


$response = $reader.ReadLine()
Write-Host "Response: $response"


$writer.WriteLine("USER $username")
$response = $reader.ReadLine()
Write-Host "Response USER: $response"

$writer.WriteLine("PASS $password")
$response = $reader.ReadLine()
Write-Host "Response PASS: $response"

$writer.WriteLine("QUIT")
$reader.ReadLine()
$sslStream.Close()
$stream.Close()
$client.Close()