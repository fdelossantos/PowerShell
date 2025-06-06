# ============================================
# Parámetros y conexión
# ============================================
# Ruta al CSV 
#$CsvPath = ".\usuarios.csv"
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$CsvPath
)

# Escopes necesarios para crear usuarios, gestionar grupos y licencias
$Scopes = @(
    "User.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All",
    "GroupMember.ReadWrite.All",
    "LicenseAssignment.ReadWrite.All"
)

# Conectar a Microsoft Graph
Connect-MgGraph -Scopes $Scopes

# ============================================
# Obtener el SkuId de la licencia Microsoft 365 F1
# ============================================
$skuF1 = Get-MgSubscribedSku -All |
    Where-Object { $_.SkuPartNumber -eq 'M365_F1_COMM' }

if (-not $skuF1) {
    Write-Error "No se encontró la suscripción 'M365_F1_COMM'."
    return
}
$skuIdF1 = $skuF1.SkuId

# ============================================
# Procesar cada línea del CSV
# ============================================
Import-Csv -Path $CsvPath -Delimiter ';' | ForEach-Object {

    $u = $_  # alias más corto

    try {
        # -----------------------------
        # 1. Crear usuario
        # -----------------------------
        $passwordProfile = @{
            ForceChangePasswordNextSignIn = $false
            Password                       = $u.password
        }

        $newUser = New-MgUser `
            -AccountEnabled `
            -DisplayName   $u.displayname `
            -MailNickName  $u.username `
            -UserPrincipalName $u.upn `
            -PasswordProfile   $passwordProfile `
            -GivenName    $u.name `
            -Surname      $u.surname `
            -UsageLocation 'UY'                

        Write-Host "✔ Usuario creado: $($u.upn) (Id: $($newUser.Id))"

<#         if ($u.adminUnitId) {

            $BodyParameter = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)"
            }

            New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $u.adminUnitId -BodyParameter $BodyParameter
            Write-Host "  • Agregado a la Unidad Administrativa $($u.adminUnitId)"
        } #>


        # -----------------------------
        # 2. Añadir a grupo
        # -----------------------------

        $grp = Get-MgGroup -Filter "displayName eq '$($u.group)'" -All
        if ($grp.Count -gt 0) {
            $groupId = $grp.Id
        }
        else {
            Write-Warning "⚠ Grupo no encontrado: '$($u.group)'. Se omite."
            return
        }


        # Añadir miembro
        New-MgGroupMember `
            -GroupId           $groupId `
            -DirectoryObjectId $newUser.Id

        Write-Host "  • Añadido al grupo: $($u.group)"

        # -----------------------------
        # 3. Asignar licencia F1
        # -----------------------------
        try {
            Set-MgUserLicense `
                -UserId        $newUser.Id `
                -AddLicenses   @{ SkuId = $skuIdF1 } `
                -RemoveLicenses @()                # sin licencias a remover

            Write-Host "  • Licencia F1 asignada."
        }
        catch {
            Write-Warning "  • No hay licencias F1 disponibles para $($u.upn). Error: $_"
        }

    }
    catch {
        Write-Error "✗ Falló al procesar $($u.upn): $_"
    }
}