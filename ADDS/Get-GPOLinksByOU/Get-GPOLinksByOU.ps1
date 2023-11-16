param
(
    [Parameter(Mandatory)]
    [string]$CarpetaSalida
)

$todasGPO = (Get-GPO -All).Id

$todasOU = Get-ADOrganizationalUnit -Filter "*"

# Crear tabla
$table = @()
$vinculadas = @()

# Procesa la raíz del dominio
$dominio = (Get-ADDomain).DistinguishedName
$herencia = Get-GPInheritance -Target $dominio
$gpoLinksId = ($herencia.GpoLinks.GpoId) -join ","
foreach ($enlace in $herencia.GpoLinks){
    if($enlace.GpoId -notin $vinculadas){
        $vinculadas += $enlace.GpoId
    }
}
$gpoLinksDN = ($herencia.GpoLinks.DisplayName) -join ","
$InheritedGpoLinksId = ($herencia.InheritedGpoLinks.GpoId) -join ","
$InheritedGpoLinksDN = ($herencia.InheritedGpoLinks.DisplayName) -join ","

$row = [PSCustomObject]@{
    "Name" = $herencia.Name
    "Path" = $herencia.Path
    "ContainerType" = $herencia.ContainerType
    "GpoInheritanceBlocked" = $herencia.GpoInheritanceBlocked
    "GpoLinksId" = $gpoLinksId
    "GpoLinksDN" = $gpoLinksDN
    "InheritedGpoLinksId" = $InheritedGpoLinksId
    "InheritedGpoLinksDN" = $InheritedGpoLinksDN
}
$table += $row

# Procesa todas las OU
foreach ($ou in $todasOU) {
    $herencia = $ou | Get-GPInheritance

    $gpoLinksId = ($herencia.GpoLinks.GpoId) -join ","
    foreach ($enlace in $herencia.GpoLinks){
        if($enlace.GpoId -notin $vinculadas){
            $vinculadas += $enlace.GpoId
        }
    }
    $gpoLinksDN = ($herencia.GpoLinks.DisplayName) -join ","
    $InheritedGpoLinksId = ($herencia.InheritedGpoLinks.GpoId) -join ","
    $InheritedGpoLinksDN = ($herencia.InheritedGpoLinks.DisplayName) -join ","

    $row = [PSCustomObject]@{
        "Name" = $herencia.Name
        "Path" = $herencia.Path
        "ContainerType" = $herencia.ContainerType
        "GpoInheritanceBlocked" = $herencia.GpoInheritanceBlocked
        "GpoLinksId" = $gpoLinksId
        "GpoLinksDN" = $gpoLinksDN
        "InheritedGpoLinksId" = $InheritedGpoLinksId
        "InheritedGpoLinksDN" = $InheritedGpoLinksDN
    }
    $table += $row
}

# Exportar tabla
$table | Export-Csv "$($CarpetaSalida)\vinculos.csv" -Delimiter ";" -Encoding UTF8 -NoTypeInformation

$todasGPO | Export-Csv "$($CarpetaSalida)\todasGPO.csv" -Delimiter ";" -Encoding UTF8 -NoTypeInformation
$vinculadas | Export-Csv "$($CarpetaSalida)\vinculadas.csv" -Delimiter ";" -Encoding UTF8 -NoTypeInformation

# Busca las que no están vinculadas. Aparecen con SideIndicator "<="
$c = Compare-Object -ReferenceObject $todasGPO -DifferenceObject $vinculadas -PassThru
$c | Export-Csv "$($CarpetaSalida)\diferencias.csv" -Delimiter ";" -Encoding UTF8 -NoTypeInformation