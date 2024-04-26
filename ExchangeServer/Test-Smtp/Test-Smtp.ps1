$smtpServer = "mail.domain.uy"
$smtpPort = 26
$smtpUser = "dom\user"
$smtpPassword = Read-Host "Ingresar contraseña" -AsSecureString
$useSSL = $true

$from = "user@domain.uy"
$to = "destinatario@correo.com"
$subject = "Prueba de conexión SMTP"
$body = "Este es un correo de prueba enviado desde PowerShell para probar la conexión SMTP."

$smtpClient = New-Object Net.Mail.SmtpClient($smtpServer, $smtpPort)
$smtpClient.EnableSsl = $useSSL
$smtpClient.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPassword)

try {
    $mailMessage = New-Object System.Net.Mail.MailMessage($from, $to, $subject, $body)
    $smtpClient.Send($mailMessage)
    Write-Host "Correo enviado con éxito."
} catch {
    Write-Host "Error al enviar el correo: $_"
}