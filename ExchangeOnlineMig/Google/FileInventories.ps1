param(
  [int]$HeartbeatMinutes = 5,
  [string]$OutRoot = ".\gam_drive_inventories",

  # Si lo pasás, el script usa esta carpeta como OutDir (para retomar).
  # Ejemplo: -RunId "20260304_173339"
  [string]$RunId = "20260305_094825",

  # Retoma a partir de esta OU (incluyéndola). Ejemplo: -ResumeFromOU "/No SSO"
  [string]$ResumeFromOU = "/No SSO",

  # Si está activo, si ya existen ambos CSV y tienen líneas > 1, salta esa OU.
  [switch]$SkipIfComplete
)

$SkipIfComplete = $true

# ===== Base: siempre relativo al script =====
$BaseDir = if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $BaseDir

$outRootFull = if ([System.IO.Path]::IsPathRooted($OutRoot)) { $OutRoot } else { Join-Path $BaseDir $OutRoot }

if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = Get-Date -Format "yyyyMMdd_HHmmss"
}

$outDir = Join-Path $outRootFull $RunId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$log     = Join-Path $outDir "run.log"
$ouCsv   = Join-Path $outDir "TopLevelOUs.csv"
$summary = Join-Path $outDir "summary.csv"

function Log([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString("o"), $m
  $line | Tee-Object -FilePath $log -Append | Out-Null
}

function Sanitize([string]$ou) {
  $name = $ou -replace '^/',''
  $name = $name -replace '[\/ ]','_'
  $name = $name -replace '[^A-Za-z0-9._-]','_'
  if ([string]::IsNullOrWhiteSpace($name)) { $name = "ROOT" }
  return $name
}

function Run-CmdWithHeartbeat {
  param(
    [string]$Label,
    [string]$CmdLine,
    [int]$HeartbeatMinutes = 5
  )

  $start = Get-Date
  Log "Inicio: $Label"
  Log "CMD: $CmdLine"

  # Ejecutar en cmd.exe para que > y 2> funcionen tal cual consola
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $CmdLine" -WorkingDirectory $BaseDir -PassThru -WindowStyle Hidden

  $hb = [TimeSpan]::FromMinutes($HeartbeatMinutes)
  $next = (Get-Date).Add($hb)

  while (-not $p.HasExited) {
    if ((Get-Date) -ge $next) {
      $elapsed = (Get-Date) - $start
      Log ("Sigue corriendo: {0} | elapsed {1:dd\.hh\:mm\:ss} | pid {2}" -f $Label, $elapsed, $p.Id)
      $next = (Get-Date).Add($hb)
    }
    Start-Sleep -Seconds 5
  }

  $rc = $p.ExitCode
  $dur = (Get-Date) - $start
  if ($rc -eq 0) {
    Log ("Fin OK: {0} | duration {1:dd\.hh\:mm\:ss}" -f $Label, $dur)
  } else {
    Log ("Fin ERROR: {0} | rc={1} | duration {2:dd\.hh\:mm\:ss}" -f $Label, $rc, $dur)
  }

  return @{ Rc = $rc; Seconds = [int]$dur.TotalSeconds }
}

Log "BaseDir: $BaseDir"
Log "OutDir: $outDir"

# ===== 1) OUs top-level =====
# Usamos redirect csv de GAM directo a archivo, y además capturamos errores a un .stderr
$ouErr = Join-Path $outDir "TopLevelOUs.stderr"

$cmdOU = 'gam redirect csv "{0}" print ous toplevelonly fields orgunitpath 1>nul 2>"{1}"' -f $ouCsv, $ouErr
$rOU = Run-CmdWithHeartbeat -Label "Descubrir OUs top-level" -CmdLine $cmdOU -HeartbeatMinutes $HeartbeatMinutes

if (-not (Test-Path $ouCsv) -or ((Get-Item $ouCsv).Length -lt 5)) {
  Log "ERROR: TopLevelOUs.csv no se generó o está vacío. Ver $ouErr"
  throw "No se pudo generar el inventario de OUs."
}

$ous = Import-Csv $ouCsv |
  ForEach-Object {
    if ($_.orgUnitPath) { $_.orgUnitPath }
    elseif ($_.orgunitpath) { $_.orgunitpath }
    else { $null }
  } |
  Where-Object { $_ -and $_ -ne "/" }

$total = $ous.Count
Log ("OUs detectadas: {0}" -f $total)

if (-not (Test-Path $summary)) {
  "ou_path,safe_name,sizes_csv,anyone_csv,sizes_rc,anyone_rc,sizes_lines,anyone_lines,sizes_seconds,anyone_seconds" |
    Out-File -FilePath $summary -Encoding utf8
} else {
  Log "Resume: summary.csv ya existe, se mantiene y se seguirá agregando."
}

$projectStart = Get-Date
$ok1=0; $fail1=0; $ok2=0; $fail2=0

for ($i=0; $i -lt $total; $i++) {
  $ou = $ous[$i]
  $safe = Sanitize $ou

  # --- ResumeFromOU: saltar hasta que aparezca esa OU (incluyéndola) ---
if (-not [string]::IsNullOrWhiteSpace($ResumeFromOU)) {
  if ($ou -ne $ResumeFromOU) {
    Log "ResumeFromOU activo: saltando OU $ou (aún no llegamos a $ResumeFromOU)"
    continue
  } else {
    Log "ResumeFromOU alcanzado: $ResumeFromOU. A partir de aquí se procesan todas las OUs."
    $ResumeFromOU = ""  # desactiva el skip para el resto del loop
  }
}

# --- SkipIfComplete: si ya existen outputs válidos, no repetir ---
$out1 = Join-Path $outDir ("{0}_filelist_sizes.csv" -f $safe)
$out2 = Join-Path $outDir ("{0}_anyone_shares.csv" -f $safe)

if ($SkipIfComplete) {
  $okOut1 = (Test-Path $out1) -and ((Get-Content $out1 -ErrorAction SilentlyContinue).Count -gt 1)
  $okOut2 = (Test-Path $out2) -and ((Get-Content $out2 -ErrorAction SilentlyContinue).Count -gt 1)

  if ($okOut1 -and $okOut2) {
    Log "SkipIfComplete: OU $ou ya tiene outputs completos, se omite."
    continue
  }
}

  $elapsed = (Get-Date) - $projectStart
  $done = $i
  $avg = if ($done -gt 0) { [TimeSpan]::FromSeconds($elapsed.TotalSeconds / $done) } else { [TimeSpan]::Zero }
  $remain = $total - $done
  $eta = [TimeSpan]::FromSeconds($avg.TotalSeconds * $remain)

  $pct = [int](($i+1) * 100 / $total)
  Write-Progress -Activity "Inventarios Google Drive por OU (Top Level)" `
    -Status ("OU {0}/{1}: {2} | elapsed {3:dd\.hh\:mm\:ss} | ETA {4:dd\.hh\:mm\:ss}" -f ($i+1), $total, $ou, $elapsed, $eta) `
    -PercentComplete $pct

  Log "------------------------------------------------------------"
  Log ("OU: {0}" -f $ou)

  # ===== 5) sizes =====
  $out1 = Join-Path $outDir ("{0}_filelist_sizes.csv" -f $safe)
  $err1 = Join-Path $outDir ("{0}_filelist_sizes.stderr" -f $safe)

  $cmd1 = 'gam ou_and_children "{0}" print filelist id name owners mimetype quotabytesused modifiedtime 1>"{1}" 2>"{2}"' -f $ou, $out1, $err1
  $r1 = Run-CmdWithHeartbeat -Label "Sizes OU=$ou" -CmdLine $cmd1 -HeartbeatMinutes $HeartbeatMinutes

  $lines1 = if (Test-Path $out1) { (Get-Content $out1 -ErrorAction SilentlyContinue).Count } else { 0 }
  if ($r1.Rc -eq 0 -and $lines1 -gt 1) { $ok1++ } else { $fail1++ }
  Log ("Sizes: rc={0} lines={1} totals ok={2} fail={3}" -f $r1.Rc, $lines1, $ok1, $fail1)

  # ===== 6) anyone =====
  $out2 = Join-Path $outDir ("{0}_anyone_shares.csv" -f $safe)
  $err2 = Join-Path $outDir ("{0}_anyone_shares.stderr" -f $safe)

  $cmd2 = 'gam ou_and_children "{0}" print filelist id name owners permissions oneitemperrow pmfilter pm type anyone 1>"{1}" 2>"{2}"' -f $ou, $out2, $err2
  $r2 = Run-CmdWithHeartbeat -Label "AnyoneShares OU=$ou" -CmdLine $cmd2 -HeartbeatMinutes $HeartbeatMinutes

  $lines2 = if (Test-Path $out2) { (Get-Content $out2 -ErrorAction SilentlyContinue).Count } else { 0 }
  if ($r2.Rc -eq 0 -and $lines2 -gt 1) { $ok2++ } else { $fail2++ }
  Log ("AnyoneShares: rc={0} lines={1} totals ok={2} fail={3}" -f $r2.Rc, $lines2, $ok2, $fail2)

  ('"{0}","{1}","{2}","{3}",{4},{5},{6},{7},{8},{9}' -f `
    $ou, $safe, (Split-Path $out1 -Leaf), (Split-Path $out2 -Leaf), `
    $r1.Rc, $r2.Rc, $lines1, $lines2, $r1.Seconds, $r2.Seconds) |
    Out-File -FilePath $summary -Append -Encoding utf8
}

Write-Progress -Activity "Inventarios Google Drive por OU (Top Level)" -Completed

$totalDur = (Get-Date) - $projectStart
Log "============================================================"
Log "FINALIZADO"
Log ("Duración total: {0:dd\.hh\:mm\:ss}" -f $totalDur)
Log ("Sizes -> ok={0} fail={1}" -f $ok1, $fail1)
Log ("AnyoneShares -> ok={0} fail={1}" -f $ok2, $fail2)
Log ("Resumen CSV: {0}" -f $summary)
Log ("Salida completa: {0}" -f $outDir)