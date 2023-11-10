# Configuración del sitio de IIS
$nombreSitioIIS = "Autodiscover"  # Reemplaza esto con el nombre de tu sitio en IIS
$puerto = 80

# Lista de nombres de dominio
$nombresDominio = @(
"dominiouno.com.uy",
"dominiodos.com.uy"
)

# Función para agregar el binding a un sitio de IIS
function AgregarBindingIIS {
    param (
        [string]$sitioIIS,
        [string]$dominio,
        [int]$puerto
    )

    $binding = Get-WebBinding -Name $sitioIIS -Protocol "http" -Port $puerto -HostHeader "autodiscover.$dominio" -ErrorAction SilentlyContinue
    if ($binding -eq $null) {
        Write-Host "Agregando binding para el dominio $dominio en el sitio $sitioIIS en el puerto $puerto..."
        New-WebBinding -Name $sitioIIS -Protocol "http" -Port $puerto -HostHeader "autodiscover.$dominio"
        Write-Host "Binding agregado exitosamente."
    } else {
        Write-Host "El binding para el dominio autodiscover.$dominio ya existe en el sitio $sitioIIS en el puerto $puerto."
    }
}

# Verificar que el módulo WebAdministration esté cargado
if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    Import-Module WebAdministration
}

# Agregar el binding para cada dominio en la lista
foreach ($dominio in $nombresDominio) {
    AgregarBindingIIS -sitioIIS $nombreSitioIIS -dominio $dominio -puerto $puerto
}
