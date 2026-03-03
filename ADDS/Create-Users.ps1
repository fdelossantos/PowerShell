# Requiere el módulo ActiveDirectory en el servidor (RSAT/AD DS Tools).
# Archivos en la misma carpeta que el script:
# - cuentas.txt  (1 UPN por línea)
# - usuarios-gw.csv (export de Google Workspace con columnas: primaryEmail, name.givenName, name.familyName, name.fullName)
# - semillas.txt (1 animal por línea; usar la lista provista arriba)
#
# Salida:
# - credenciales-creadas.txt (fullname, UPN y contraseña, más una línea en blanco)

$ErrorActionPreference = "Stop"

$dcServer = "DC01"
$ouPath  = "OU=MX,OU=NoSincronizaNube,DC=dominio,DC=local"

$cuentasPath  = Join-Path -Path $PSScriptRoot -ChildPath "cuentas.txt"
$csvPath      = Join-Path -Path $PSScriptRoot -ChildPath "usuarios.csv"
$semillasPath = Join-Path -Path $PSScriptRoot -ChildPath "semillas.txt"
$outPath      = Join-Path -Path $PSScriptRoot -ChildPath "credenciales-creadas.txt"

$upns = Get-Content -Path $cuentasPath -Encoding UTF8 |
    Where-Object { $_ -and $_.Trim().Length -gt 0 } |
    ForEach-Object { $_.Trim() }

$semillas = Get-Content -Path $semillasPath -Encoding UTF8 |
    Where-Object { $_ -and $_.Trim().Length -gt 0 } |
    ForEach-Object { $_.Trim() }

if (-not $semillas -or $semillas.Count -lt 1)
{
    throw "El archivo semillas.txt no contiene valores."
}

$simbolos = @("*", "-", "+", "/")
$seedIndex = 0

$usuariosCsv = Import-Csv -Path $csvPath

# Diccionario por primaryEmail para búsqueda rápida
$usuariosPorEmail = @{}
foreach ($u in $usuariosCsv)
{
    if ($null -ne $u.primaryEmail -and $u.primaryEmail.Trim().Length -gt 0)
    {
        $key = $u.primaryEmail.Trim().ToLowerInvariant()
        $usuariosPorEmail[$key] = $u
    }
}

# Inicializa/limpia el archivo de salida
"" | Out-File -FilePath $outPath -Encoding UTF8

foreach ($upn in $upns)
{
    $upnKey = $upn.ToLowerInvariant()

    $csvUser = $null
    if ($usuariosPorEmail.ContainsKey($upnKey))
    {
        $csvUser = $usuariosPorEmail[$upnKey]
    }
    else
    {
        Write-Host "No se encontró en CSV el usuario con primaryEmail = $upn. Se omite."
        continue
    }

    $existing = Get-ADUser -Server $dcServer -Filter "UserPrincipalName -eq '$upn'" -ErrorAction SilentlyContinue

    if ($null -ne $existing)
    {
        Write-Host "Ya existe: $upn"
        continue
    }

    $givenName  = $csvUser."name.givenName"
    $familyName = $csvUser."name.familyName"
    $fullName   = $csvUser."name.fullName"
    $primaryEmail = $csvUser.primaryEmail

    $seed = $semillas[$seedIndex]
    $seedIndex = $seedIndex + 1
    if ($seedIndex -ge $semillas.Count)
    {
        $seedIndex = 0
    }

    $symbol = Get-Random -InputObject $simbolos
    $digits = Get-Random -Minimum 0 -Maximum 10000
    $digits4 = "{0:D4}" -f $digits

    $plainPassword = "$seed$symbol$digits4"
    $securePassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force

    $localPart = $upn.Split("@")[0]
    $domainPart = $upn.Split("@")[1]

    $mailNickname = $primaryEmail.Replace("@", "_")

    $targetAddress = "SMTP:$localPart@gsuite.$domainPart"

    $proxyPrimary = "SMTP:$primaryEmail"
    $proxySecondary = "smtp:$localPart@o365.$domainPart"
    $proxyAddresses = @($proxyPrimary, $proxySecondary)

    New-ADUser `
        -Server $dcServer `
        -Path $ouPath `
        -Name $fullName `
        -SamAccountName $localPart `
        -UserPrincipalName $upn `
        -GivenName $givenName `
        -Surname $familyName `
        -DisplayName $fullName `
        -Enabled $true `
        -AccountPassword $securePassword `
        -OtherAttributes @{
            mail = $primaryEmail
            mailNickname = $mailNickname
            targetAddress = $targetAddress
            proxyAddresses = $proxyAddresses
        }

    Write-Host "Creado: $upn"

    $line1 = $fullName
    $line2 = $upn
    $line3 = $plainPassword

    $line1 | Out-File -FilePath $outPath -Encoding UTF8 -Append
    $line2 | Out-File -FilePath $outPath -Encoding UTF8 -Append
    $line3 | Out-File -FilePath $outPath -Encoding UTF8 -Append
    ""     | Out-File -FilePath $outPath -Encoding UTF8 -Append
}
 