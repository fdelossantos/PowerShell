# Ejecutar PS sin privilegios elevados
# Esto genera el certificado raíz, que queda en el almacen personal del usuario
$params = @{
    Type = 'Custom'
    Subject = 'CN=FormulaLocaRootCert'
    KeySpec = 'Signature'
    KeyExportPolicy = 'Exportable'
    KeyUsage = 'CertSign'
    KeyUsageProperty = 'Sign'
    KeyLength = 2048
    HashAlgorithm = 'sha256'
    NotAfter = (Get-Date).AddYears(10)
    CertStoreLocation = 'Cert:\CurrentUser\My'
}
$cert = New-SelfSignedCertificate @params
# El certificado queda cargado en la variable $cert para poder usarlo para firmar certificados cliente.
# Hay que exportarlo sin la clave privada para distribuirlo por GPO
Export-Certificate -Cert $cert -FilePath 'C:\Temp\FormulaLocaRootCert.cer' -Type CERT

# si cerraron la ventana de powershell, pueden cargar el certificado raiz con:
$cert = Get-ChildItem cert:\CurrentUser\My\<thumbprint>
