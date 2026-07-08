# Requiere Microsoft Graph PowerShell SDK
# Install-Module Microsoft.Graph -Scope CurrentUser

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Identity.DirectoryManagement

$SourcePrefix = "OU-"
$TargetPrefix = "UNI - "

$Scopes = @(
    "AdministrativeUnit.ReadWrite.All",
    "Group.ReadWrite.All",
    "GroupMember.ReadWrite.All",
    "User.Read.All"
)

Connect-MgGraph -Scopes $Scopes

function Get-MailNickname {
    param(
        [string]$DisplayName,
        [string]$AdministrativeUnitId
    )

    $Text = $DisplayName.ToLowerInvariant()
    $Text = $Text -replace "\s+", "-"
    $Text = $Text -replace "[^a-z0-9._-]", ""
    $Text = $Text.Trim("-")

    $Suffix = $AdministrativeUnitId.Substring(0, 8)

    if ($Text.Length -gt 55) {
        $Text = $Text.Substring(0, 55)
    }

    return "$Text-$Suffix"
}

function Get-AdministrativeUnitUsers {
    param(
        [string]$AdministrativeUnitId
    )

    $Users = @()
    $Uri = "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$AdministrativeUnitId/members/microsoft.graph.user?`$select=id,displayName,userPrincipalName"

    do {
        $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri
        $Users += $Response.value
        $Uri = $Response.'@odata.nextLink'
    }
    while ($Uri)

    return $Users
}

$AdministrativeUnits = Get-MgDirectoryAdministrativeUnit -All |
    Where-Object { $_.DisplayName -like "$SourcePrefix*" } |
    Sort-Object DisplayName

Write-Host "Administrative Units encontradas: $($AdministrativeUnits.Count)"
Write-Host ""

foreach ($AdministrativeUnit in $AdministrativeUnits) {
    $OldName = $AdministrativeUnit.DisplayName
    $NewName = $OldName -replace "^$([regex]::Escape($SourcePrefix))", $TargetPrefix

    Write-Host "Procesando: $OldName"
    Write-Host "Grupo destino: $NewName"

    $ExistingGroup = Get-MgGroup `
        -Filter "displayName eq '$($NewName.Replace("'", "''"))'" `
        -All

    if ($ExistingGroup.Count -gt 1) {
        Write-Warning "Hay más de un grupo llamado '$NewName'. Se omite esta AU."
        Write-Host ""
        continue
    }

    if ($ExistingGroup.Count -eq 1) {
        $Group = $ExistingGroup[0]
        Write-Host "Grupo existente encontrado. Se usará el grupo existente."
    }
    else {
        $MailNickname = Get-MailNickname `
            -DisplayName $NewName `
            -AdministrativeUnitId $AdministrativeUnit.Id

        $GroupBody = @{
            displayName             = $NewName
            mailNickname            = $MailNickname
            mailEnabled             = $true
            securityEnabled         = $false
            groupTypes              = @("Unified")
            resourceBehaviorOptions = @("WelcomeEmailDisabled")
        }

        $Group = New-MgGroup -BodyParameter $GroupBody

        Write-Host "Grupo creado. Id: $($Group.Id)"
    }

    $Users = Get-AdministrativeUnitUsers -AdministrativeUnitId $AdministrativeUnit.Id

    Write-Host "Usuarios encontrados en la AU: $($Users.Count)"

    foreach ($User in $Users) {
        Write-Host "  Usuario: $($User.userPrincipalName)"

        $MemberBody = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($User.id)"
        }

        try {
            New-MgGroupMemberByRef `
                -GroupId $Group.Id `
                -BodyParameter $MemberBody `
                -ErrorAction Stop

            Write-Host "    Agregado al grupo."
        }
        catch {
            $Message = $_.Exception.Message

            if ($Message -like "*added object references already exist*") {
                Write-Host "    Ya era miembro del grupo."
            }
            else {
                Write-Warning "    No se pudo agregar al grupo. No se removerá de la AU. Error: $Message"
                continue
            }
        }

        try {
            Remove-MgDirectoryAdministrativeUnitMemberByRef `
                -AdministrativeUnitId $AdministrativeUnit.Id `
                -DirectoryObjectId $User.id `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Host "    Removido de la AU."
        }
        catch {
            Write-Warning "    No se pudo remover de la AU. Error: $($_.Exception.Message)"
        }
    }

    Write-Host ""
}

Write-Host "Proceso finalizado."