[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Carpeta,
    [Parameter(Mandatory)]
    [string]$ArchivoSalida
)

$exportable = @()

$archivos = Get-ChildItem $Carpeta # -Include "*.xml"
foreach ($item in $archivos) {
    [xml]$politica = Get-Content -Path $item.FullName
    
    if ($politica.DocumentElement.Computer.Enabled) #true si habilitado
    {
        # Buscamos extensiones de Computer
        $extensiones = $politica.DocumentElement.Computer.ExtensionData
        # La columna "Name" tiene el tipo de extensión
        foreach($linea in $extensiones){
            $myObject = [PSCustomObject]@{
                File = $item.Name
                Section = "Computer"
                Extension = $linea.Name
            }
            $exportable += $myObject
        }

    }
    if ($politica.DocumentElement.User.Enabled) #true si habilitado
    {
        # Buscamos extensiones de User
        $extensiones = $politica.DocumentElement.User.ExtensionData
        # La columna "Name" tiene el tipo de extensión
        foreach($linea in $extensiones){
            $myObject = [PSCustomObject]@{
                File = $item.Name
                Section = "User"
                Extension = $linea.Name
            }
            $exportable += $myObject
        }
    }

}

$exportable | Export-Csv $ArchivoSalida -Delimiter ";" -NoTypeInformation -Encoding utf8