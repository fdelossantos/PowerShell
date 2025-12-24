# Parámetros
$ExchangePlan2SkuId = [Guid]'19ec0d23-8335-4cbd-94ac-6050e30712fa'  # EXCHANGEENTERPRISE
$SizeThresholdGB = 50

# Conexiones (omite si ya las tienes abiertas)
Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All"
Connect-ExchangeOnline

# 1. Obtener usuarios con licencia Exchange Online Plan 2 (EXCHANGEENTERPRISE)
#    Para evitar complicar el filtro OData, traemos usuarios y filtramos en memoria.
$licensedUsers = Get-MgUser -All -Property "Id,UserPrincipalName,DisplayName,AssignedLicenses" |
    Where-Object { $_.AssignedLicenses.SkuId -contains $ExchangePlan2SkuId }

Write-Host "Usuarios con licencia EXCHANGEENTERPRISE encontrados:" $licensedUsers.Count

# 2. Recorrer usuarios y obtener tamaño del buzón
$result = @()

foreach ($user in $licensedUsers) {
    # Puede haber usuarios con licencia pero sin buzón, así que controlamos el error
    $stats = Get-ExoMailboxStatistics -Identity $user.UserPrincipalName -ErrorAction SilentlyContinue

    if (-not $stats) {
        continue
    }

    # TotalItemSize es un tipo ByteQuantifiedSize
    $sizeBytes = $stats.TotalItemSize.Value.ToBytes()
    $sizeGB = [math]::Round($sizeBytes / 1GB, 2)

    if ($sizeGB -lt $SizeThresholdGB) {
        $result += [pscustomobject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            SizeGB            = $sizeGB
        }
    }
}

# 3. Mostrar solo los buzones con menos de 50 GB
$result |
    Sort-Object SizeGB |
    Format-Table DisplayName, UserPrincipalName, SizeGB -AutoSize
