# Automatización de App Registrations para SharePoint Online con Sites.Selected

## Objetivo

Este script automatiza la creación de una **App Registration en Microsoft Entra ID** para que una aplicación pueda acceder a un sitio específico de SharePoint Online utilizando permisos restringidos mediante **Sites.Selected**.

El objetivo es evitar la asignación de permisos amplios como `Sites.Read.All`, `Sites.ReadWrite.All` o `Sites.FullControl.All` sobre todo el tenant. En su lugar, la aplicación queda autorizada únicamente sobre el sitio indicado.

## Alcance del script

El script realiza las siguientes tareas:

1. Crea una App Registration en Microsoft Entra ID.
2. Agrega permisos de aplicación `Sites.Selected` para:

   * Microsoft Graph
   * SharePoint Online
3. Concede Admin Consent para esos permisos.
4. Crea el Service Principal asociado.
5. Asigna como Owner al usuario que ejecuta el script.
6. Genera un certificado autofirmado.
7. Carga el certificado público en la App Registration.
8. Exporta el certificado con clave privada a formato PFX.
9. Otorga permisos explícitos sobre el sitio de SharePoint indicado.
10. Genera un archivo de instrucciones con los datos necesarios para los desarrolladores.

## Requisitos previos

### Permisos del usuario ejecutor

El usuario que ejecuta el script debe tener permisos suficientes en el tenant. El uso previsto es que sea ejecutado por un **Global Administrator**.

El usuario debe poder:

* Crear App Registrations.
* Crear Service Principals.
* Conceder Admin Consent.
* Asignar permisos sobre sitios de SharePoint Online usando Microsoft Graph.
* Leer información del usuario autenticado y del tenant.

### PowerShell

Se recomienda ejecutar el script con **PowerShell 7**.

### Módulos requeridos

El script valida la existencia y versión mínima de los siguientes módulos:

* `Microsoft.Graph.Authentication`
* `Microsoft.Graph.Applications`
* `Microsoft.Graph.Sites`

La versión mínima esperada es:

```powershell
2.20.0
```

Para instalar o actualizar Microsoft Graph PowerShell:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

o:

```powershell
Update-Module Microsoft.Graph
```

## Permisos solicitados durante la conexión

El script se conecta a Microsoft Graph solicitando los siguientes scopes delegados para el usuario administrador:

```text
Application.ReadWrite.All
AppRoleAssignment.ReadWrite.All
Directory.Read.All
Sites.FullControl.All
User.Read
```

Estos permisos son necesarios para crear la aplicación, conceder permisos de aplicación y asignar el permiso granular al sitio de SharePoint.

## Parámetros del script

### `AppName`

Nombre de la App Registration.

Ejemplo:

```powershell
-AppName "SPO-MyApplication"
```

Este nombre también se usa como nombre del certificado.

### `SiteUrl`

URL del sitio de SharePoint Online al que se otorgará acceso.

Ejemplo:

```powershell
-SiteUrl "https://tenant.sharepoint.com/sites/MyAppSite/"
```

Debe ser la URL del sitio, no una URL de biblioteca, carpeta, archivo o página interna.

### `SitePermission`

Nivel de permiso que se otorgará a la aplicación sobre el sitio.

Valores admitidos:

```text
Read
Write
Manage
FullControl
```

Ejemplo:

```powershell
-SitePermission Write
```

### `TenantId`

Identificador del tenant de Microsoft Entra ID.

Ejemplo:

```powershell
-TenantId "00000000-0000-0000-0000-000000000000"
```

Este parámetro debe utilizarse siempre para evitar crear la aplicación en un tenant equivocado.

### `CertificateValidMonths`

Duración del certificado, expresada en meses.

Ejemplo:

```powershell
-CertificateValidMonths 12
```

Importante: Microsoft Graph no permite cargar un certificado en `keyCredentials` con una vigencia superior a un año. Por eso el valor máximo admitido por el script debe ser de 12 meses o menos.

### `OutputPath`

Carpeta donde se exportarán el certificado PFX y el archivo de instrucciones.

Ejemplo:

```powershell
-OutputPath "C:\\Temp\\AppRegistrations"
```

Si no se indica, se usa una carpeta local llamada `AppRegistrationOutput`.

### `AllowDuplicateDisplayName`

Permite crear una App Registration aunque ya exista otra con el mismo Display Name.

Uso:

```powershell
-AllowDuplicateDisplayName
```

No se recomienda usarlo salvo que exista un motivo operativo claro.

## Ejemplo de ejecución

```powershell
.\\New-AppRegistrationSPO.ps1 `
    -AppName "SPO-MyApp" `
    -SiteUrl "https://tenant.sharepoint.com/sites/MyAppSite/" `
    -SitePermission Write `
    -TenantId "00000000-0000-0000-0000-000000000000" `
    -CertificateValidMonths 12 `
    -OutputPath "C:\\Temp\\AppRegistrations"
```

Durante la ejecución, el script solicitará por pantalla la contraseña para exportar el certificado PFX.

## Resultado esperado

Al finalizar correctamente, el script genera:

1. Una App Registration en Microsoft Entra ID.
2. Un Service Principal asociado.
3. Permisos de aplicación:

   * Microsoft Graph / `Sites.Selected`
   * SharePoint Online / `Sites.Selected`
4. Admin Consent concedido.
5. Certificado público cargado en la App Registration.
6. Certificado PFX exportado localmente.
7. Permiso explícito sobre el sitio de SharePoint.
8. Archivo de instrucciones para los desarrolladores.

## Archivos generados

En la carpeta de salida se generan archivos similares a:

```text
SPO-SAPWorkplace.pfx
SPO-SAPWorkplace-instrucciones.txt
```

El archivo de instrucciones incluye:

* Tenant ID
* Client ID
* Application Object ID
* Service Principal Object ID
* Nombre de la aplicación
* Owner asignado
* URL del sitio autorizado
* Site ID
* Permiso otorgado
* Ruta del certificado PFX
* Thumbprint del certificado
* Fecha de vencimiento del certificado

## Información para desarrolladores

La aplicación debe autenticarse usando el flujo **client credentials con certificado**.

Datos requeridos:

* Tenant ID
* Client ID
* Certificado PFX
* Contraseña del PFX
* Thumbprint del certificado, si la librería lo requiere

Para Microsoft Graph, el recurso/scope habitual es:

```text
https://graph.microsoft.com/.default
```

Para SharePoint REST, el recurso/scope debe corresponder al host de SharePoint:

```text
https://tenant.sharepoint.com/.default
```

Ejemplo:

```text
https://tenant.sharepoint.com/.default
```

## Consideraciones sobre Sites.Selected

El permiso `Sites.Selected` por sí solo no da acceso a ningún sitio.

La secuencia correcta es:

1. Agregar `Sites.Selected` a la App Registration.
2. Conceder Admin Consent.
3. Otorgar permiso explícito sobre uno o más sitios.

El script realiza los tres pasos.

Sin el permiso explícito sobre el sitio, la aplicación no podrá acceder al contenido aunque tenga `Sites.Selected` concedido.

## Niveles de permiso sobre el sitio

Los niveles usados por Microsoft Graph para permisos sobre sitios son:

|Valor|Uso esperado|
|-|-|
|`read`|Lectura|
|`write`|Lectura y escritura|
|`manage`|Administración de listas y contenido|
|`fullcontrol`|Control total sobre el sitio|

El script acepta los valores en formato PowerShell:

```text
Read
Write
Manage
FullControl
```

Internamente los convierte al formato esperado por Microsoft Graph.

## Consideraciones sobre certificados

El script genera un certificado autofirmado y lo carga como credencial de la App Registration.

La clave privada se exporta a un archivo PFX protegido con contraseña.

La contraseña:

* No se guarda en el script.
* No se escribe en pantalla.
* No se incluye en el archivo de instrucciones.
* Debe ser transmitida al equipo de desarrollo por un canal seguro.

### Vigencia máxima

Microsoft Graph valida el vencimiento del certificado al cargarlo en la App Registration. La vigencia no debe superar un año.

Para evitar errores de borde, el script debe enviar las fechas a Microsoft Graph:

* En UTC.
* Sin fracciones de segundo.
* Tomadas desde la validez real del certificado.
* Con `endDateTime` dentro del rango admitido por Graph.

Ejemplo de formato válido:

```text
2027-07-07T16:43:33Z
```

## Validaciones incluidas

El script valida:

* Que los módulos requeridos estén instalados.
* Que los módulos tengan una versión mínima esperada.
* Que la URL sea absoluta.
* Que la URL use HTTPS.
* Que la URL parezca corresponder a SharePoint Online.
* Que no se esté pasando una URL de archivo, carpeta o página interna.
* Que el nombre de la aplicación no esté duplicado, salvo que se use `AllowDuplicateDisplayName`.
* Que el sitio pueda resolverse mediante Microsoft Graph.
* Que existan los Service Principals de Microsoft Graph y SharePoint Online.
* Que existan los roles de aplicación `Sites.Selected`.

## Errores frecuentes

### `KeyCredentialsInvalidEndDate`

Ejemplo:

```text
Key credential end date is invalid.
InvalidKeyEndDate
keyCredentials.endDateTime
```

Causa habitual:

* El certificado tiene una vigencia superior a un año.
* El `endDateTime` enviado a Graph supera por segundos o milisegundos el vencimiento real del certificado.
* El payload incluye fracciones de segundo que dejan el valor fuera del rango aceptado.

Corrección:

* Usar una vigencia máxima de 12 meses.
* Enviar fechas en formato `yyyy-MM-ddTHH:mm:ssZ`.
* Tomar `startDateTime` y `endDateTime` desde el certificado generado.
* Evitar fracciones de segundo.
* Restar un segundo al `endDateTime` enviado a Graph si es necesario.

### La App Registration se creó, pero el script falló después

Si el script falla después de crear la aplicación, pueden quedar objetos parcialmente creados.

En ese caso se recomienda eliminar la App Registration y el Service Principal antes de volver a ejecutar.

Ejemplo:

```powershell
Connect-MgGraph -TenantId "<TenantId>" -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All"

Remove-MgServicePrincipal -ServicePrincipalId "<ServicePrincipalObjectId>"

Remove-MgApplication -ApplicationId "<ApplicationObjectId>"
```

También puede buscarse el Service Principal por Client ID:

```powershell
$appId = "<ClientId>"

$sp = Get-MgServicePrincipal -Filter "appId eq '$appId'"

if ($sp) {
    Remove-MgServicePrincipal -ServicePrincipalId $sp.Id
}
```

## Seguridad

El script no genera client secrets.

La autenticación de la aplicación se realiza mediante certificado, lo cual es preferible a secretos simétricos para este tipo de integración.

Recomendaciones:

* Guardar el PFX en una ubicación segura.
* Transmitir la contraseña del PFX por un canal separado.
* Registrar la fecha de vencimiento del certificado.
* Renovar el certificado antes del vencimiento.
* Otorgar siempre el menor permiso posible sobre el sitio.
* Usar `Read` cuando la aplicación no necesite escribir.
* Evitar `FullControl` salvo que exista una justificación técnica concreta.
* Eliminar App Registrations que hayan quedado creadas por pruebas fallidas.

## Operación recomendada

1. Confirmar el tenant correcto.
2. Confirmar la URL exacta del sitio de SharePoint.
3. Confirmar el nivel de permiso requerido.
4. Ejecutar el script con `TenantId` explícito.
5. Guardar el PFX en una ubicación segura.
6. Entregar al equipo de desarrollo:

   * Tenant ID
   * Client ID
   * Ruta o copia segura del PFX
   * Contraseña del PFX por canal separado
   * URL del sitio autorizado
   * Alcance autorizado
7. Registrar la fecha de vencimiento del certificado.
8. Programar la renovación antes del vencimiento.

## Ejemplo de salida exitosa

```text
FINALIZADO
Tenant Id: 00000000-0000-0000-0000-000000000000
Client Id: 00000000-0000-0000-0000-000000000000
PFX: C:\\Temp\\AppRegistrations\\SPO-MyApp.pfx
Vencimiento certificado UTC: 2027-07-07T16:43:33Z
Instrucciones: C:\\Temp\\AppRegistrations\\SPO-MyApp-instrucciones.txt
```

## Resultado funcional

Después de una ejecución exitosa, la aplicación queda lista para ser usada por los desarrolladores sin pasos manuales adicionales en Entra ID ni en SharePoint Online.

La aplicación tendrá permisos únicamente sobre el sitio indicado y no sobre todos los sitios del tenant.

