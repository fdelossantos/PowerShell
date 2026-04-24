param(
  [Parameter(Mandatory = $true)]
  [string]$TargetOU,

  [string]$OutRoot = ".\gam_drive_inventories",

  # Si lo pasás, reutiliza la misma carpeta de salida.
  [string]$RunId = "20260305_094825",

  # Si ya existen ambos CSV con contenido, no vuelve a ejecutar.
  [switch]$SkipIfComplete,

  # Por si quieres forzar gam.exe o una ruta concreta.
  [string]$GamCommand = "gam"
)

$BaseDir = if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $BaseDir

$outRootFull = if ([System.IO.Path]::IsPathRooted($OutRoot)) { $OutRoot } else { Join-Path $BaseDir $OutRoot }

if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = Get-Date -Format "yyyyMMdd_HHmmss"
}

$outDir = Join-Path $outRootFull $RunId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Log([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date).ToString("o"), $Message
  $line | Tee-Object -FilePath $sessionLog -Append
}

function Sanitize([string]$Value) {
  $name = $Value -replace '^/', ''
  $name = $name -replace '[\\/ ]', '_'
  $name = $name -replace '[^A-Za-z0-9._-]', '_'
  if ([string]::IsNullOrWhiteSpace($name)) { $name = "ROOT" }
  return $name
}

function Get-LineCount([string]$Path) {
  if (-not (Test-Path $Path)) { return 0 }
  return (Get-Content $Path -ErrorAction SilentlyContinue).Count
}

function Run-GamRedirectCsv {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$ConsoleLogPath,

    [Parameter(Mandatory = $true)]
    [string[]]$GamArgs
  )

  $start = Get-Date
  Log "------------------------------------------------------------"
  Log "Inicio: $Label"
  Log "CSV: $CsvPath"
  Log "Args: $($GamArgs -join ' ')"

  if (Test-Path $CsvPath) {
    Remove-Item $CsvPath -Force -ErrorAction SilentlyContinue
  }

  # GAM escribe el CSV directamente al archivo.
  # La salida visible/progreso de GAM se muestra en pantalla y además se guarda en log.
  & $GamCommand redirect csv $CsvPath @GamArgs 2>&1 | Tee-Object -FilePath $ConsoleLogPath -Append

  $rc = $LASTEXITCODE
  $duration = (Get-Date) - $start
  $lines = Get-LineCount $CsvPath

  if ($rc -eq 0) {
    Log ("Fin OK: {0} | duración {1:dd\.hh\:mm\:ss} | líneas CSV {2}" -f $Label, $duration, $lines)
  } else {
    Log ("Fin ERROR: {0} | rc={1} | duración {2:dd\.hh\:mm\:ss} | líneas CSV {3}" -f $Label, $rc, $duration, $lines)
  }

  return [PSCustomObject]@{
    Label   = $Label
    Rc      = $rc
    Seconds = [int]$duration.TotalSeconds
    Lines   = $lines
    CsvPath = $CsvPath
    LogPath = $ConsoleLogPath
  }
}

$safeOU = Sanitize $TargetOU
$sessionLog = Join-Path $outDir ("{0}_session.log" -f $safeOU)

$sizesCsv = Join-Path $outDir ("{0}_filelist_sizes.csv" -f $safeOU)
$sizesLog = Join-Path $outDir ("{0}_filelist_sizes.console.log" -f $safeOU)

$anyoneCsv = Join-Path $outDir ("{0}_anyone_shares.csv" -f $safeOU)
$anyoneLog = Join-Path $outDir ("{0}_anyone_shares.console.log" -f $safeOU)

$summaryCsv = Join-Path $outDir "summary_single_ou.csv"

Log "BaseDir: $BaseDir"
Log "OutDir: $outDir"
Log "TargetOU: $TargetOU"
Log "GamCommand: $GamCommand"

if ($SkipIfComplete) {
  $sizesOk = (Get-LineCount $sizesCsv) -gt 1
  $anyoneOk = (Get-LineCount $anyoneCsv) -gt 1

  if ($sizesOk -and $anyoneOk) {
    Log "SkipIfComplete: ambos CSV ya existen y tienen contenido. No se ejecuta nada."
    exit 0
  }
}

$resultSizes = Run-GamRedirectCsv `
  -Label "Sizes OU=$TargetOU" `
  -CsvPath $sizesCsv `
  -ConsoleLogPath $sizesLog `
  -GamArgs @(
    "ou_and_children", $TargetOU,
    "print", "filelist",
    "id", "name", "owners", "mimetype", "quotabytesused", "modifiedtime"
  )

$resultAnyone = Run-GamRedirectCsv `
  -Label "AnyoneShares OU=$TargetOU" `
  -CsvPath $anyoneCsv `
  -ConsoleLogPath $anyoneLog `
  -GamArgs @(
    "ou_and_children", $TargetOU,
    "print", "filelist",
    "id", "name", "owners", "permissions",
    "oneitemperrow",
    "pmfilter", "pm", "type", "anyone"
  )

if (-not (Test-Path $summaryCsv)) {
  'ou_path,safe_name,sizes_csv,anyone_csv,sizes_rc,anyone_rc,sizes_lines,anyone_lines,sizes_seconds,anyone_seconds' |
    Out-File -FilePath $summaryCsv -Encoding utf8
}

('"{0}","{1}","{2}","{3}",{4},{5},{6},{7},{8},{9}' -f `
  $TargetOU,
  $safeOU,
  (Split-Path $sizesCsv -Leaf),
  (Split-Path $anyoneCsv -Leaf),
  $resultSizes.Rc,
  $resultAnyone.Rc,
  $resultSizes.Lines,
  $resultAnyone.Lines,
  $resultSizes.Seconds,
  $resultAnyone.Seconds) |
  Out-File -FilePath $summaryCsv -Append -Encoding utf8

Log "============================================================"
Log ("FINALIZADO OU {0}" -f $TargetOU)
Log ("Sizes -> rc={0}, líneas={1}, archivo={2}" -f $resultSizes.Rc, $resultSizes.Lines, $resultSizes.CsvPath)
Log ("Anyone -> rc={0}, líneas={1}, archivo={2}" -f $resultAnyone.Rc, $resultAnyone.Lines, $resultAnyone.CsvPath)
Log ("Resumen -> {0}" -f $summaryCsv)

if ($resultSizes.Rc -ne 0 -or $resultAnyone.Rc -ne 0) {
  exit 1
}

exit 0