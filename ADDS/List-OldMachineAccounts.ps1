Import-Module ActiveDirectory

$Server = "AD01.dominio.local"
$DaysInactive = 180
$DaysSinceCreated = 60
$CsvPath = ".\Equipos_AD_Inactivos.csv"

$Cutoff = (Get-Date).AddDays(-$DaysInactive)
$CreatedCutoff = (Get-Date).AddDays(-$DaysSinceCreated)

$Computers = Get-ADComputer -Server $Server -LDAPFilter "(&(objectCategory=computer)(!(primaryGroupID=516)))" -Properties Enabled,OperatingSystem,lastLogonTimestamp,PasswordLastSet,whenCreated

$Result = foreach ($Computer in $Computers) {
    $LastLogonTimestamp = $null

    if ($Computer.lastLogonTimestamp) {
        $LastLogonTimestamp = [DateTime]::FromFileTime($Computer.lastLogonTimestamp)
    }

    $ActivityDates = @($LastLogonTimestamp, $Computer.PasswordLastSet) | Where-Object { $_ }

    $LastActivity = $null

    if ($ActivityDates) {
        $LastActivity = $ActivityDates | Sort-Object -Descending | Select-Object -First 1
    }

    $Reason = $null

    if ($Computer.Enabled -eq $false -and $Computer.whenCreated -lt $CreatedCutoff) {
        $Reason = "Cuenta de equipo deshabilitada"
    }
    elseif ($LastLogonTimestamp -and $Computer.PasswordLastSet -and $LastLogonTimestamp -lt $Cutoff -and $Computer.PasswordLastSet -lt $Cutoff) {
        $Reason = "lastLogonTimestamp y PasswordLastSet anteriores a $DaysInactive dias"
    }
    elseif (-not $LastLogonTimestamp -and $Computer.PasswordLastSet -and $Computer.PasswordLastSet -lt $Cutoff -and $Computer.whenCreated -lt $CreatedCutoff) {
        $Reason = "Sin lastLogonTimestamp y PasswordLastSet anterior a $DaysInactive dias"
    }
    elseif (-not $LastLogonTimestamp -and -not $Computer.PasswordLastSet -and $Computer.whenCreated -lt $CreatedCutoff) {
        $Reason = "Sin lastLogonTimestamp ni PasswordLastSet y creada hace mas de $DaysSinceCreated dias"
    }

    if ($Reason) {
        [PSCustomObject]@{
            Name = $Computer.Name
            SamAccountName = $Computer.SamAccountName
            DistinguishedName = $Computer.DistinguishedName
            Enabled = $Computer.Enabled
            OperatingSystem = $Computer.OperatingSystem
            WhenCreated = if ($Computer.whenCreated) { $Computer.whenCreated.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            LastLogonTimestamp = if ($LastLogonTimestamp) { $LastLogonTimestamp.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            PasswordLastSet = if ($Computer.PasswordLastSet) { $Computer.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            LastActivity = if ($LastActivity) { $LastActivity.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            Reason = $Reason
        }
    }
}

$Result | Sort-Object LastActivity,Name | Export-Csv -Path $CsvPath -Delimiter ";" -NoTypeInformation -Encoding UTF8

$Result | Sort-Object LastActivity,Name