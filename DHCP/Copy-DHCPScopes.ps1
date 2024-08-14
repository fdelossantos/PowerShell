param(    
    [Parameter(Mandatory)]
    [string]$destino
)

# This script copy all the Scopes in a DHCP server including:
#   * Scope range
#   * Scope Options
#   * Exclusions
#   * Reservations
# Run in origin server and copy to the server in the param $destino

$scopes = Get-DhcpServerv4Scope

foreach ($scope in $scopes) {

    #if ($scope.StartRange.IPAddressToString -like "10.1.*" -or $scope.StartRange.IPAddressToString -like "192.168.*"){

        # Crear el ámbito
        Add-DhcpServerv4Scope -ComputerName $destino -StartRange $scope.StartRange -EndRange $scope.EndRange -Name $scope.Name -LeaseDuration $scope.LeaseDuration -SubnetMask $scope.SubnetMask

        Set-DhcpServerv4Scope -State InActive -ScopeId $scope.ScopeId

        # Obtener las opciones
        $router = (Get-DhcpServerv4OptionValue -ScopeId $scope.ScopeId).Where({$_.OptionId -eq '3'}).Value
        $domainname = (Get-DhcpServerv4OptionValue -ScopeId $scope.ScopeId).Where({$_.OptionId -eq '15'}).Value
        # Agregar las opciones
        Set-DhcpServerv4OptionValue -ScopeId $scope.ScopeId -ComputerName $destino -DnsDomain $domainname -Router $router

        # Obtener las exclusiones
        $exclusions = Get-DhcpServerv4ExclusionRange -ScopeId $scope.ScopeId
        # Agregar las exclusiones
        foreach ($exclusion in $exclusions) {
            Add-Dhcpserverv4ExclusionRange -ComputerName $destino -ScopeId $scope.ScopeId -StartRange $exclusion.StartRange -EndRange $exclusion.EndRange
        }

        # Obtener las reservas
        $reserves = Get-DhcpServerv4Reservation -ScopeId $scope.ScopeId
        # Agregar las reservas
        foreach ($reserve in $reserves) {
            Add-DhcpServerv4Reservation -ScopeId $scope.ScopeId -ComputerName $destino -IPAddress $reserve.IPAddress -ClientId $reserve.ClientId -Name $reserve.Name -Description $reserve.Description
        }
    #}
} 
