<#
.SYNOPSIS
  Monitor y automatización de Migration Batches hasta completar (Complete + Approve + Report + Licencias).

.DESCRIPTION
  - Mantiene tabla en memoria con estado y timestamps por batch.
  - Detecta batches nuevos o eliminados durante ejecución.
  - Para batches en Synced: ejecuta Complete-MigrationBatch una sola vez.
  - Para NeedsApproval: ejecuta aprobación, con reintento cada 3 iteraciones si persiste.
  - Para Completed: genera archivo de mapeo (Original -> Routing con prefijo o365 al dominio)
    y mueve usuarios de grupo "sin Exchange" a "con Exchange".
  - Para Failed: no actúa, lo reporta.
  - Condición de salida por defecto: termina cuando solo quedan Completed o Failed (o ninguno).

.PARAMETER OutputFolder
  Carpeta donde se escriben los archivos <Identity>.txt

.PARAMETER IterationSleepSeconds
  Espera entre iteraciones

.PARAMETER StopWhenOnlyCompletedOrFailed
  Default: $true (recomendado). Si $false, el loop nunca termina mientras exista Failed.

.PARAMETER WhatIf
  Simula acciones (Complete/Aprobación/Licencias) sin ejecutarlas realmente.
#>


[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory=$false)]
  [string]$OutputFolder = ".\BatchMappings",

  [Parameter(Mandatory=$false)]
  [int]$IterationSleepSeconds = 120
)

#region Helpers

function Ensure-Folder {
  param([Parameter(Mandatory=$true)][string]$Path)

  if (-not (Test-Path -Path $Path)) {
    New-Item -Path $Path -ItemType Directory | Out-Null
  }
}

function Get-RoutingAddress {
  param([Parameter(Mandatory=$true)][string]$Email)

  $parts = $Email.Split("@")
  if ($parts.Count -ne 2) {
    return $null
  }

  $local = $parts[0]
  $domain = $parts[1]
  return "$local@o365.$domain"
}

function Safe-FileNameFromIdentity {
  param([Parameter(Mandatory=$true)][string]$Identity)

  $invalid = [IO.Path]::GetInvalidFileNameChars()
  $name = $Identity

  foreach ($c in $invalid) {
    $name = $name.Replace($c, "_")
  }

  return $name
}

function Write-BatchMappingFile {
  param(
    [Parameter(Mandatory=$true)][string]$BatchIdentity,
    [Parameter(Mandatory=$true)][string]$Folder
  )

  $users = @()
  try {
    $users = Get-MigrationUser -BatchId $BatchIdentity -ResultSize Unlimited -ErrorAction Stop
  }
  catch {
    Write-Host "  [ERROR] No pude listar MigrationUsers del batch '$BatchIdentity': $($_.Exception.Message)" -ForegroundColor Red
    return $null
  }

  $seen = @{}
  $lines = New-Object System.Collections.Generic.List[string]

  foreach ($u in $users) {

    $original = $null
    if ($null -ne $u.EmailAddress -and ($u.EmailAddress.ToString()).Trim() -ne "") {
      $original = $u.EmailAddress.ToString().Trim()
    }
    else {
      $original = $u.Identity.ToString().Trim()
    }

    if ($original -notmatch "@") {
      continue
    }

    $key = $original.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
      continue
    }

    $routing = Get-RoutingAddress -Email $original
    if ($null -eq $routing) {
      continue
    }

    $seen[$key] = $true
    $lines.Add("$original,$routing") | Out-Null
  }

  Ensure-Folder -Path $Folder

  $fileName = (Safe-FileNameFromIdentity -Identity $BatchIdentity) + ".txt"
  $fullPath = Join-Path -Path $Folder -ChildPath $fileName

  try {
    $lines | Set-Content -Path $fullPath -Encoding UTF8
    return $fullPath
  }
  catch {
    Write-Host "  [ERROR] No pude escribir archivo de mapeo '$fullPath': $($_.Exception.Message)" -ForegroundColor Red
    return $null
  }
}

function Try-ApproveSkippedItems {
  param(
    [Parameter(Mandatory=$true)][string]$Identity,
    [Parameter(Mandatory=$false)][switch]$WhatIfMode
  )

  if ($WhatIfMode) {
    Write-Host "  [WHATIF] Set-MigrationBatch -Identity `"$Identity`" -ApproveSkippedItems" -ForegroundColor DarkYellow
    return $true
  }

  try {
    Set-MigrationBatch -Identity $Identity -ApproveSkippedItems -ErrorAction Stop | Out-Null
    return $true
  }
  catch {
    Write-Host "  [ERROR] Falló aprobación (ApproveSkippedItems) para batch '$Identity': $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

function Update-LicensesViaGroups {
  param(
    [Parameter(Mandatory=$true)][string[]]$UserEmails,
    [Parameter(Mandatory=$true)][hashtable]$LicenseMap,
    [Parameter(Mandatory=$false)][switch]$WhatIfMode
  )

  foreach ($email in $UserEmails) {

    $mgUser = $null
    try {
      $mgUser = Get-MgUser -UserId $email -ErrorAction Stop
    }
    catch {
      Write-Host "  [ERROR] No pude resolver usuario en Graph '$email': $($_.Exception.Message)" -ForegroundColor Red
      continue
    }

    $memberOf = @()
    try {
      $memberOf = Get-MgUserMemberOf -UserId $mgUser.Id -All -ErrorAction Stop
    }
    catch {
      Write-Host "  [ERROR] No pude leer MemberOf para '$email': $($_.Exception.Message)" -ForegroundColor Red
      continue
    }

    $groupIds = @()
    foreach ($o in $memberOf) {
      if ($null -ne $o.Id) {
        $groupIds += $o.Id
      }
    }

    $matchedWo = $null
    foreach ($woId in $LicenseMap.Keys) {
      if ($groupIds -contains $woId) {
        $matchedWo = $woId
        break
      }
    }

    if ($null -eq $matchedWo) {
      Write-Host "  [INFO] '$email' no está en un grupo 'sin Exchange' de la tabla. No hago cambios." -ForegroundColor DarkGray
      continue
    }

    $wId = $LicenseMap[$matchedWo]

    if ($WhatIfMode) {
      Write-Host "  [WHATIF] Remove user '$email' from group $matchedWo" -ForegroundColor DarkYellow
      Write-Host "  [WHATIF] Add user '$email' to group $wId" -ForegroundColor DarkYellow
      continue
    }

    try {
      Remove-MgGroupMemberByRef -GroupId $matchedWo -DirectoryObjectId $mgUser.Id -ErrorAction Stop
    }
    catch {
      Write-Host "  [ERROR] No pude quitar '$email' del grupo $($matchedWo): $($_.Exception.Message)" -ForegroundColor Red
    }

    try {
      $body = @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($mgUser.Id)"
      }
      New-MgGroupMemberByRef -GroupId $wId -BodyParameter $body -ErrorAction Stop | Out-Null
      Write-Host "  [OK] Licencia por grupos actualizada para '$email'." -ForegroundColor Green
    }
    catch {
      Write-Host "  [ERROR] No pude agregar '$email' al grupo $($wId): $($_.Exception.Message)" -ForegroundColor Red
    }
  }
}

#endregion Helpers

#region License Group Map (ids)
$LicenseGroupPairs = @(
  [pscustomobject]@{ WoId="<guid>"; WId="<guid>" }
  [pscustomobject]@{ WoId=""; WId="" }
  [pscustomobject]@{ WoId=""; WId="" }
  [pscustomobject]@{ WoId=""; WId="" }
  [pscustomobject]@{ WoId=""; WId="" }
)

$LicenseMap = @{}
foreach ($p in $LicenseGroupPairs) {
  $LicenseMap[$p.WoId] = $p.WId
}
#endregion

#region In-Memory Table
#$BatchTable = @{}
#$Iteration = 0

Ensure-Folder -Path $OutputFolder

Write-Host "== Monitor de Migration Batches ==" -ForegroundColor Cyan
Write-Host "OutputFolder: $OutputFolder"
Write-Host "Sleep: $IterationSleepSeconds s"
#endregion

# Estados "no terminales" (los que justifican mantener el loop corriendo)
$NonTerminalStatuses = @(
  "Created",
  "Syncing",
  "Synced",
  "NeedsApproval",
  "Completing"
)

while ($true) {
  $Iteration++
  Write-Host ""
  Write-Host ("--- Iteración #{0} ({1}) ---" -f $Iteration, (Get-Date)) -ForegroundColor Cyan

  # 1) Listar batches actuales
  $currentBatches = @()
  try {
    $currentBatches = Get-MigrationBatch -ResultSize Unlimited -ErrorAction Stop
  }
  catch {
    Write-Host "[FATAL] No pude listar batches: $($_.Exception.Message)" -ForegroundColor Red
    break
  }

  # 2) Detectar nuevos y cargar a tabla
  foreach ($b in $currentBatches) {
    $id = $b.Identity.ToString()

    if (-not $BatchTable.ContainsKey($id)) {

      # Si en la primera ejecución aparece Completed, ignorarlo
      if ($Iteration -eq 1 -and $b.Status.ToString() -eq "Completed") {
        continue
      }

      $BatchTable[$id] = [pscustomobject]@{
        Identity                 = $id
        InitialStatus            = $b.Status.ToString()
        DetectedAt               = Get-Date

        NeedsApprovalAt          = $null
        CompletingAt             = $null
        CompletedAt              = $null
        FailedAt                 = $null

        CompleteIssued           = $false
        CompleteIssuedAt         = $null

        NeedsApprovalIterations  = 0
        LastApproveAttemptAt     = $null

        MappingFilePath          = $null
        LicenseUpdated           = $false

        LastKnownStatus          = $b.Status.ToString()
      }

      Write-Host "[NEW] Detectado batch: $id (InitialStatus=$($b.Status))" -ForegroundColor Green
    }
  }

  # 3) Procesar tabla en memoria (no iteramos batches directos para evitar inconsistencias por adds/deletes)
  $recentlyCompleted = New-Object System.Collections.Generic.List[string]
  $stillFailed = New-Object System.Collections.Generic.List[string]
  $corruptedNow = New-Object System.Collections.Generic.List[string]

  foreach ($trackedId in @($BatchTable.Keys)) {

    $row = $BatchTable[$trackedId]

    $batch = $null
    try {
      $batch = Get-MigrationBatch -Identity $trackedId -ErrorAction Stop
    }
    catch {
      # "no encontrado": lo ignoramos porque deriva de acción del técnico
      $BatchTable.Remove($trackedId) | Out-Null
      continue
    }

    $status = $batch.Status.ToString()
    $row.LastKnownStatus = $status

    switch ($status) {

      "Syncing" {
        # No hacer nada
      }

      "Synced" {
        if (-not $row.CompleteIssued) {
          if ($PSCmdlet.ShouldProcess($trackedId, "Complete-MigrationBatch -SyncAndComplete")) {
            try {
              Complete-MigrationBatch -Identity $trackedId -SyncAndComplete -ErrorAction Stop | Out-Null
              $row.CompleteIssued = $true
              $row.CompleteIssuedAt = Get-Date
              Write-Host "[ACTION] Complete-MigrationBatch -SyncAndComplete ejecutado en '$trackedId'." -ForegroundColor Green
            }
            catch {
              Write-Host "[ERROR] Complete-MigrationBatch falló en '$trackedId': $($_.Exception.Message)" -ForegroundColor Red
            }
          }
        }
      }

      "NeedsApproval" {
        if ($null -eq $row.NeedsApprovalAt) {
          $row.NeedsApprovalAt = Get-Date
        }

        $row.NeedsApprovalIterations++

        $shouldAttempt = $false
        if ($null -eq $row.LastApproveAttemptAt) {
          $shouldAttempt = $true
        }
        elseif (($row.NeedsApprovalIterations % 3) -eq 0) {
          $shouldAttempt = $true
        }

        if ($shouldAttempt) {
          $row.LastApproveAttemptAt = Get-Date
          Write-Host "[ACTION] Intentando ApproveSkippedItems para '$trackedId' (iterNeedsApproval=$($row.NeedsApprovalIterations))" -ForegroundColor Yellow

          $ok = Try-ApproveSkippedItems -Identity $trackedId -WhatIfMode:([bool]$WhatIfPreference)
          if ($ok) {
            # la transición puede demorar
          }
        }
      }

      "Completing" {
        if ($null -eq $row.CompletingAt) {
          $row.CompletingAt = Get-Date
        }
      }

      "Completed" {
        if ($null -eq $row.CompletedAt) {
          $row.CompletedAt = Get-Date
          $recentlyCompleted.Add($trackedId) | Out-Null
        }

        if ($null -eq $row.MappingFilePath) {
          $path = Write-BatchMappingFile -BatchIdentity $trackedId -Folder $OutputFolder
          if ($null -ne $path) {
            $row.MappingFilePath = $path
            Write-Host "[REPORT] Nuevo batch completado: '$trackedId'. Archivo de mapeo: $path" -ForegroundColor Cyan
          }
        }

        if (-not $row.LicenseUpdated) {
          $emails = @()

          if ($null -ne $row.MappingFilePath -and (Test-Path $row.MappingFilePath)) {
            $content = Get-Content -Path $row.MappingFilePath -ErrorAction SilentlyContinue
            foreach ($line in $content) {
              $parts = $line.Split(",")
              if ($parts.Count -ge 1) {
                $e = $parts[0].Trim()
                if ($e -match "@") {
                  $emails += $e
                }
              }
            }
            $emails = $emails | Sort-Object -Unique
          }

          if ($emails.Count -gt 0) {
            Write-Host "[ACTION] Actualizando licencias por grupos para '$trackedId' ($($emails.Count) usuarios)" -ForegroundColor Green
            Update-LicensesViaGroups -UserEmails $emails -LicenseMap $LicenseMap -WhatIfMode:([bool]$WhatIfPreference)
            $row.LicenseUpdated = $true
          }
          else {
            Write-Host "  [WARN] No pude obtener emails para licencias en '$trackedId'." -ForegroundColor Yellow
          }
        }
      }

      "Failed" {
        if ($null -eq $row.FailedAt) {
          $row.FailedAt = Get-Date
        }
        $stillFailed.Add($trackedId) | Out-Null
      }

      "Corrupted" {
        $corruptedNow.Add($trackedId) | Out-Null
      }

      # Stopped / Removing u otros por acción del técnico: ignorar
      default {
        # Sin ruido. Si querés, podés loguear estados inesperados aquí.
      }
    }

    $BatchTable[$trackedId] = $row
  }

  # 4) Resumen por iteración
  $completedCount = 0
  $needsApprovalCount = 0
  $failedCount = 0
  $nonTerminalCount = 0

  foreach ($k in $BatchTable.Keys) {
    $s = $BatchTable[$k].LastKnownStatus

    if ($s -eq "Completed") { $completedCount++ }
    if ($s -eq "NeedsApproval") { $needsApprovalCount++ }
    if ($s -eq "Failed") { $failedCount++ }
    if ($NonTerminalStatuses -contains $s) { $nonTerminalCount++ }
  }

  Write-Host ""
  Write-Host ("Resumen: Completed={0} | NoTerminal={1} | NeedsApproval={2} | Failed={3}" -f $completedCount, $nonTerminalCount, $needsApprovalCount, $failedCount) -ForegroundColor Cyan

  if ($recentlyCompleted.Count -gt 0) {
    Write-Host "Recientemente completados (nuevo mapping):" -ForegroundColor Green
    foreach ($x in $recentlyCompleted) {
      $p = $BatchTable[$x].MappingFilePath
      if ($null -ne $p) {
        Write-Host "  - $x  (mapping: $p)" -ForegroundColor Green
      }
      else {
        Write-Host "  - $x" -ForegroundColor Green
      }
    }
  }

  if ($stillFailed.Count -gt 0) {
    Write-Host "Batches en Failed (para análisis técnico):" -ForegroundColor Red
    foreach ($x in $stillFailed) {
      Write-Host "  - $x" -ForegroundColor Red
    }
  }

  if ($corruptedNow.Count -gt 0) {
    Write-Host "Batches en Corrupted (intervención manual requerida):" -ForegroundColor Magenta
    foreach ($x in $corruptedNow) {
      Write-Host "  - $x" -ForegroundColor Magenta
    }
  }

  # 5) Condición de salida: si NO quedan batches en estados no terminales, termina
  if ($nonTerminalCount -eq 0) {
    Write-Host ""
    Write-Host "No quedan batches en estados no terminales (Created/Syncing/Synced/NeedsApproval/Completing). Termino ejecución." -ForegroundColor Cyan
    break
  }

  Start-Sleep -Seconds $IterationSleepSeconds
}
