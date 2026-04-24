param(
    [int]$Throttle = 10,
    [string]$InternalDomains = "domain.com",
    [string]$WorkDirName = "gam_filesharecounts",
    [string]$UsersCsvName = "users.csv",
    [string]$OutCsvName = "filesharecounts_all.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1) Asegurar que todo corre relativo a la carpeta del script (working dir consistente)
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $ScriptRoot

$WorkDir     = Join-Path $ScriptRoot $WorkDirName
$TempDir     = Join-Path $WorkDir "temp"
$UsersCsv    = Join-Path $WorkDir $UsersCsvName
$OutCsv      = Join-Path $WorkDir $OutCsvName
$DoneFile    = Join-Path $WorkDir "done.txt"
$Inflight    = Join-Path $WorkDir "inflight.json"

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Read-LinesSafe([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    Get-Content -Path $Path -Encoding UTF8 | Where-Object { $_ -and $_.Trim() -ne "" }
}

function Write-Inflight([string[]]$Users) {
    $obj = [pscustomobject]@{
        startedUtc = (Get-Date).ToUniversalTime().ToString("o")
        users      = $Users
    }
    $obj | ConvertTo-Json -Depth 3 | Set-Content -Path $Inflight -Encoding UTF8
}

function Read-InflightUsers {
    if (-not (Test-Path $Inflight)) { return @() }
    try {
        $raw = Get-Content -Path $Inflight -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj.users) { return @() }
        return [string[]]$obj.users
    } catch {
        return @()
    }
}

function Append-CsvFile {
    param(
        [string]$SourceCsv,
        [string]$TargetCsv
    )

    if (-not (Test-Path $SourceCsv)) { return }

    $srcLines = Get-Content -Path $SourceCsv -Encoding UTF8
    if ($srcLines.Count -eq 0) { return }

    if (-not (Test-Path $TargetCsv) -or ((Get-Item $TargetCsv).Length -eq 0)) {
        # primer write: copia todo (incluye header)
        $srcLines | Set-Content -Path $TargetCsv -Encoding UTF8
        return
    }

    # ya existe: saltear header del source (línea 1)
    if ($srcLines.Count -ge 2) {
        $srcLines | Select-Object -Skip 1 | Add-Content -Path $TargetCsv -Encoding UTF8
    }
}

# 2) Generar users.csv si no existe, usando redirect csv (no stdout)
if (-not (Test-Path $UsersCsv)) {
    Write-Host "Generando lista de usuarios -> $UsersCsv"
    # Usamos un set mínimo de columnas para garantizar primaryEmail
    # Nota: print users soporta especificar campos/columnas en GAM (varía según variante).
    # Si tu GAM no acepta "primaryEmail" como campo, quítalo y parseamos luego la columna existente.
    & gam redirect csv $UsersCsv print users primaryEmail 1>$null 2>$null
}

if (-not (Test-Path $UsersCsv) -or ((Get-Item $UsersCsv).Length -eq 0)) {
    throw "users.csv no fue generado o quedó vacío: $UsersCsv"
}

# 3) Cargar y ordenar usuarios
$usersRows = Import-Csv -Path $UsersCsv
if ($usersRows.Count -eq 0) { throw "users.csv no tiene filas: $UsersCsv" }

# Intentar detectar columna email (primaryEmail es lo típico)
$emailProp = @("primaryEmail","email","User","user","Email","mail") |
    Where-Object { $usersRows[0].PSObject.Properties.Name -contains $_ } |
    Select-Object -First 1

if (-not $emailProp) {
    throw "No pude identificar la columna email en users.csv. Columnas: $($usersRows[0].PSObject.Properties.Name -join ', ')"
}

$allUsers = $usersRows |
    ForEach-Object { [string]($_.$emailProp) } |
    Where-Object { $_ -and $_.Trim() -ne "" } |
    Sort-Object -Unique

$doneSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($u in (Read-LinesSafe $DoneFile)) { [void]$doneSet.Add($u) }

# Resume: reintentar primero inflight que no estén done
$retry = @()
foreach ($u in (Read-InflightUsers)) {
    if ($u -and (-not $doneSet.Contains($u))) { $retry += $u }
}

$pending = @()
foreach ($u in $allUsers) {
    if (-not $doneSet.Contains($u)) { $pending += $u }
}

if ($retry.Count -gt 0) {
    $retrySet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($u in $retry) { [void]$retrySet.Add($u) }
    $pending = @($retry + ($pending | Where-Object { -not $retrySet.Contains($_) }))
    Write-Host "Resume detectado: reintentando primero el último batch incompleto ($($retry.Count) usuarios)."
}

if ($pending.Count -eq 0) {
    Write-Host "No hay usuarios pendientes. Nada que hacer."
    exit 0
}

Write-Host "Usuarios totales: $($allUsers.Count)"
Write-Host "Completados: $($doneSet.Count)"
Write-Host "Pendientes:   $($pending.Count)"
Write-Host "Salida final: $OutCsv"
Write-Host ""

# 4) Loop en batches de 10, paralelizando cada batch
$globalDoneBase = $doneSet.Count
$completedNow = 0

for ($i = 0; $i -lt $pending.Count; $i += $Throttle) {

    $batch = $pending[$i..([Math]::Min($i + $Throttle - 1, $pending.Count - 1))]
    Write-Inflight $batch

    Write-Host "Batch $([int]($i / $Throttle) + 1) - Usuarios:"
    $batch | ForEach-Object { Write-Host "  - $_" }

    # Lanzar jobs (cada uno genera SU csv temporal con redirect csv)
    $jobs = foreach ($u in $batch) {
        $safe = ($u -replace '[^a-zA-Z0-9._-]', '_')
        $tmpCsv = Join-Path $TempDir ("filesharecounts_{0}.csv" -f $safe)

        Start-ThreadJob -ArgumentList $u, $tmpCsv, $InternalDomains -ScriptBlock {
            param($UserEmail, $TmpCsvPath, $InternalDomainsInner)

            # Asegurar que no quede basura previa
            if (Test-Path $TmpCsvPath) { Remove-Item $TmpCsvPath -Force }

            # IMPORTANT: usar redirect csv para que GAM escriba el archivo, sin depender de stdout
            # También silenciamos stdout/stderr para evitar contaminación (progreso, logs).
            & gam redirect csv $TmpCsvPath user $UserEmail print filesharecounts excludetrashed internaldomains $InternalDomainsInner 1>$null 2>$null

            [pscustomobject]@{
                user   = $UserEmail
                tmpCsv = $TmpCsvPath
            }
        }
    }

    $batchDone = 0
    while ($batchDone -lt $batch.Count) {
        $j = Wait-Job -Job $jobs -Any
        $r = Receive-Job -Job $j
        Remove-Job -Job $j | Out-Null
        $jobs = $jobs | Where-Object { $_.Id -ne $j.Id }

        $userFinished = [string]$r.user
        $tmpCsv       = [string]$r.tmpCsv

        # Append al CSV final desde el hilo principal
        Append-CsvFile -SourceCsv $tmpCsv -TargetCsv $OutCsv

        # Marcar done (checkpoint)
        if (-not $doneSet.Contains($userFinished)) {
            Add-Content -Path $DoneFile -Value $userFinished -Encoding UTF8
            [void]$doneSet.Add($userFinished)
        }

        if (Test-Path $tmpCsv) { Remove-Item $tmpCsv -Force }

        $batchDone++
        $completedNow++

        $overallDone  = $globalDoneBase + $completedNow
        $percent = [math]::Round(($overallDone / $allUsers.Count) * 100, 1)

        Write-Progress `
            -Activity "GAM filesharecounts (redirect csv)" `
            -Status "Completados: $overallDone / $($allUsers.Count) | Batch: $batchDone / $($batch.Count) | Último: $userFinished" `
            -PercentComplete $percent
    }

    # Batch completo: limpiar inflight para no reintentar de más
    if (Test-Path $Inflight) { Remove-Item $Inflight -Force }

    Write-Host "Batch completado."
    Write-Host ""
}

Write-Progress -Activity "GAM filesharecounts (redirect csv)" -Completed
Write-Host "Listo. CSV final: $OutCsv"
Write-Host "Checkpoint: $DoneFile"