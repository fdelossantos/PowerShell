# PowerShell 7
# Script: Move-Users-To-ExclusionOU.ps1
#
# Entrada esperada:
#   CSV con una columna de usuarios, con o sin encabezado.
#
# Ejemplos válidos:
#   Email
#   usuario1@dominio.com
#   usuario2@dominio.com
#
# O sin encabezado:
#   usuario1@dominio.com
#   usuario2@dominio.com

$CsvPath = ".\Exclusion.csv"
$ExclusionOuName = "Exclusion"

function Invoke-Gam {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $output = & gam @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
        Success  = ($exitCode -eq 0)
    }
}

function Get-UsersFromCsv {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $lines = Get-Content -Path $Path |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $users = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $firstColumn = ($line -split ",")[0].Trim().Trim('"')

        if ($firstColumn -match '^(User|Email|UPN|PrimaryEmail|primaryEmail|correo|usuario)$') {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($firstColumn)) {
            $users.Add($firstColumn)
        }
    }

    return $users
}

function Get-UserOrgUnitPath {
    param(
        [Parameter(Mandatory)]
        [string] $UserEmail
    )

    $result = Invoke-Gam -Arguments @(
        "info",
        "user",
        $UserEmail,
        "quick",
        "formatjson"
    )

    if (-not $result.Success) {
        return [pscustomobject]@{
            Success = $false
            OrgUnitPath = $null
            Error = ($result.Output -join "`n")
        }
    }

    try {
        $jsonText = $result.Output -join "`n"
        $userInfo = $jsonText | ConvertFrom-Json

        $ou = $userInfo.orgUnitPath

        if ([string]::IsNullOrWhiteSpace($ou)) {
            $ou = $userInfo.organizations.orgUnitPath
        }

        return [pscustomobject]@{
            Success = $true
            OrgUnitPath = $ou
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            OrgUnitPath = $null
            Error = "No se pudo interpretar la salida JSON de GAM. Salida: $($result.Output -join "`n")"
        }
    }
}

function Join-OrgUnitPath {
    param(
        [Parameter(Mandatory)]
        [string] $ParentOu,

        [Parameter(Mandatory)]
        [string] $ChildOuName
    )

    if ($ParentOu -eq "/") {
        return "/$ChildOuName"
    }

    return "$ParentOu/$ChildOuName"
}

function Test-OrgUnitExists {
    param(
        [Parameter(Mandatory)]
        [string] $OrgUnitPath
    )

    $result = Invoke-Gam -Arguments @(
        "info",
        "ou",
        $OrgUnitPath,
        "nousers"
    )

    return $result.Success
}

function New-OrgUnit {
    param(
        [Parameter(Mandatory)]
        [string] $OrgUnitPath
    )

    $result = Invoke-Gam -Arguments @(
        "create",
        "ou",
        $OrgUnitPath
    )

    return $result
}

function Move-UserToOrgUnit {
    param(
        [Parameter(Mandatory)]
        [string] $UserEmail,

        [Parameter(Mandatory)]
        [string] $TargetOrgUnitPath
    )

    $result = Invoke-Gam -Arguments @(
        "update",
        "user",
        $UserEmail,
        "ou",
        $TargetOrgUnitPath
    )

    return $result
}

$users = Get-UsersFromCsv -Path $CsvPath
$total = $users.Count
$current = 0

Write-Host ""
Write-Host "Usuarios a procesar: $total"
Write-Host "OU hija objetivo: $ExclusionOuName"
Write-Host ""

foreach ($user in $users) {
    $current++

    Write-Host "[$current/$total] Usuario: $user"

    Write-Progress `
        -Activity "Moviendo usuarios a OU Exclusion" `
        -Status "Procesando $user ($current de $total)" `
        -PercentComplete (($current / $total) * 100)

    $userOuResult = Get-UserOrgUnitPath -UserEmail $user

    if (-not $userOuResult.Success) {
        Write-Host "  ERROR: No se pudo obtener la OU actual del usuario." -ForegroundColor Red
        Write-Host "  Detalle: $($userOuResult.Error)" -ForegroundColor DarkRed
        Write-Host ""
        continue
    }

    $currentOu = $userOuResult.OrgUnitPath

    if ([string]::IsNullOrWhiteSpace($currentOu)) {
        Write-Host "  ERROR: GAM no devolvió orgUnitPath para el usuario." -ForegroundColor Red
        Write-Host ""
        continue
    }

    Write-Host "  OU actual: $currentOu"

    if ($currentOu -match "/$([regex]::Escape($ExclusionOuName))$") {
        Write-Host "  Acción: el usuario ya está en una OU '$ExclusionOuName'. No se mueve." -ForegroundColor Yellow
        Write-Host ""
        continue
    }

    $targetOu = Join-OrgUnitPath -ParentOu $currentOu -ChildOuName $ExclusionOuName

    Write-Host "  OU destino: $targetOu"

    $ouExists = Test-OrgUnitExists -OrgUnitPath $targetOu

    if ($ouExists) {
        Write-Host "  OU destino: ya existe." -ForegroundColor Cyan
    }
    else {
        Write-Host "  OU destino: no existe. Creando..." -ForegroundColor Yellow

        $createResult = New-OrgUnit -OrgUnitPath $targetOu

        if (-not $createResult.Success) {
            Write-Host "  ERROR: No se pudo crear la OU destino." -ForegroundColor Red
            Write-Host "  Detalle: $($createResult.Output -join "`n")" -ForegroundColor DarkRed
            Write-Host ""
            continue
        }

        Write-Host "  OU destino: creada correctamente." -ForegroundColor Green
    }

    Write-Host "  Moviendo usuario a $targetOu..."

    $moveResult = Move-UserToOrgUnit -UserEmail $user -TargetOrgUnitPath $targetOu

    if (-not $moveResult.Success) {
        Write-Host "  ERROR: No se pudo mover el usuario." -ForegroundColor Red
        Write-Host "  Detalle: $($moveResult.Output -join "`n")" -ForegroundColor DarkRed
        Write-Host ""
        continue
    }

    Write-Host "  Acción: usuario movido correctamente." -ForegroundColor Green
    Write-Host ""
}

Write-Progress -Activity "Moviendo usuarios a OU Exclusion" -Completed

Write-Host "Proceso finalizado."