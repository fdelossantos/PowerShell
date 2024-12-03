# Ruta del archivo Excel y módulo de PowerShell necesario
$excelFilePath = "E:\Work\Mazars\BR\export-app-registrations.xlsx"
Import-Module Microsoft.Graph.Applications

# Autenticación al tenant de destino (reemplaza con tu método preferido)
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Función para cargar datos del archivo Excel
function Import-ExcelData {
    $excelData = Import-Excel -Path $excelFilePath -WorksheetName "AppRegistrationList"
    return $excelData
}

# Importar datos del archivo
$appData = Import-ExcelData

# Crear reporte de configuraciones manuales
$manualConfigReport = @()

foreach ($app in $appData) {
    # Crear la aplicación en el tenant de destino
<#     $appParams = @{
        DisplayName                  = "BRA-" + $app.displayName
        #IdentifierUris               = $app.identifierUris -replace '\[|\]', '' -split ','
        Web                          = @{
            RedirectUris             = $app.'web.redirectUris' -replace '\[|\]', '' -split ','
            #HomepageUrl              = $app.'web.homePageUrl'
            #LogoutUrl                = $app.'web.logoutUrl'
            ImplicitGrantSettings    = @{
                EnableIdTokenIssuance = [bool]$app.'web.implicitGrantSettings.enableIdTokenIssuance'
                EnableAccessTokenIssuance = [bool]$app.'web.implicitGrantSettings.enableAccessTokenIssuance'
            }
        }
    } #>
    $DisplayName                  = "BRA-" + $app.displayName
    #IdentifierUris               = $app.identifierUris -replace '\[|\]', '' -split ','
    $webParams = @{
        #RedirectUris             = $app.'web.redirectUris' -replace '\[|\]', '' -split ','
        #HomepageUrl              = $app.'web.homePageUrl'
        #LogoutUrl                = $app.'web.logoutUrl'
        ImplicitGrantSettings    = @{
            EnableIdTokenIssuance = [bool]$app.'web.implicitGrantSettings.enableIdTokenIssuance'
            EnableAccessTokenIssuance = [bool]$app.'web.implicitGrantSettings.enableAccessTokenIssuance'
        }
    }

    $newApp = New-MgApplication -DisplayName $DisplayName `
        -SignInAudience AzureADMyOrg -Web $webParams
        
<#         @{
            ImplicitGrantSettings    = @{
                EnableIdTokenIssuance = $true
            }
        } #>

    Update-MgApplication -ApplicationId $newApp.Id -Web @{
        ImplicitGrantSettings    = @{
            EnableIdTokenIssuance = $true
        }
    }

    # Verificar configuración de certificados y secretos
    $manualTasks = @()
    if ($app.keyCredentials -ne "[]") {
        $manualTasks += "Configurar certificado (keyCredentials)"
    }
    if ($app.passwordCredentials -ne "[]") {
        $manualTasks += "Configurar secreto (passwordCredentials)"
    }

    # Agregar tareas manuales al reporte
    if ($manualTasks.Count -gt 0) {
        $manualConfigReport += [PSCustomObject]@{
            ApplicationName = $app.displayName
            ManualTasks     = $manualTasks -join  "; "
        }
    }

    Write-Host "Aplicación '$($app.displayName)' creada exitosamente."
}

# Exportar reporte de tareas manuales
$manualConfigReport | Export-Csv -Path "E:\Work\Mazars\BR\manual_config_report.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ";"
Write-Host "Reporte de configuraciones manuales generado en 'manual_config_report.csv'."
