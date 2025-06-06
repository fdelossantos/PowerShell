# ejecutar previamente New-RootSelfSignedCertificate.ps1

# Con el OID de Server Authentication
$params = @{
       Type = 'Custom'
       Subject = 'CN=app.formula.loca'
       DnsName = 'app.formula.loca'
       KeySpec = 'Signature'
       KeyExportPolicy = 'Exportable'
       KeyLength = 2048
       HashAlgorithm = 'sha256'
       NotAfter = (Get-Date).AddMonths(24)
       CertStoreLocation = 'Cert:\CurrentUser\My'
       Signer = $cert
       TextExtension = @(
        '2.5.29.37={text}1.3.6.1.5.5.7.3.1')
   }

   # Con el OID de Client Authentication
$params = @{
       Type = 'Custom'
       Subject = 'CN=app.formula.loca'
       DnsName = 'app.formula.loca'
       KeySpec = 'Signature'
       KeyExportPolicy = 'Exportable'
       KeyLength = 2048
       HashAlgorithm = 'sha256'
       NotAfter = (Get-Date).AddMonths(24)
       CertStoreLocation = 'Cert:\CurrentUser\My'
       Signer = $cert
       TextExtension = @(
        '2.5.29.37={text}1.3.6.1.5.5.7.3.2')
   }

# Con los OID de Client y Server Authentication
# No lo probé, pero podría funcionar
$params = @{
       Type = 'Custom'
       Subject = 'CN=app.formula.loca'
       DnsName = 'app.formula.loca'
       KeySpec = 'Signature'
       KeyExportPolicy = 'Exportable'
       KeyLength = 2048
       HashAlgorithm = 'sha256'
       NotAfter = (Get-Date).AddMonths(24)
       CertStoreLocation = 'Cert:\CurrentUser\My'
       Signer = $cert
       TextExtension = @(
        '2.5.29.37={text}1.3.6.1.5.5.7.3.1',
        '2.5.29.37={text}1.3.6.1.5.5.7.3.2')
   }


New-SelfSignedCertificate @params
#Este certificado lo cargan en el almacen personal de la cuenta de equipo del servidor.
