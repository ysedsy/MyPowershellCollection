# backup-mirror.ps1 - Mirror folders to a backup destination with logging
# Run as Administrator if backing up protected locations

param(
    [string[]]$Sources = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Pictures"),
    [Parameter(Mandatory=$true)][string]$Destination,   # e.g. "E:\Backup" or "\\NAS\share"
    [switch]$Mirror,        # delete files in dest that no longer exist in source (DANGEROUS - off by default)
    [switch]$Run            # without this: dry-run only (shows what would change)
)

$logDir  = "$env:USERPROFILE\_BackupLogs"
$logFile = "$logDir\backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

Write-Host "=== Backup Mirror ===`n" -ForegroundColor Cyan

# Verify destination
if (-not (Test-Path $Destination)) {
    Write-Host "Destination not found: $Destination" -ForegroundColor Red
    $make = Read-Host "Create it? (yes/no)"
    if ($make -eq "yes") { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    else { Write-Host "Aborted."; return }
}

# Validate sources
$validSources = $Sources | Where-Object { Test-Path $_ }
if (-not $validSources) { Write-Host "No valid source folders." -ForegroundColor Red; return }

Write-Host "Sources:" -ForegroundColor Yellow
$validSources | ForEach-Object { Write-Host "    $_" }
Write-Host "Destination: $Destination"
Write-Host "Mode: $(if ($Mirror) {'MIRROR (deletes extra files in dest)'} else {'COPY (adds/updates only)'})" -ForegroundColor $(if ($Mirror) {'Red'} else {'Green'})
Write-Host "Run: $(if ($Run) {'LIVE'} else {'DRY-RUN (nothing written)'})`n" -ForegroundColor Cyan

# robocopy flags
#  /E      = include subdirs, even empty
#  /MIR    = mirror (adds /PURGE - deletes extras). Only if -Mirror.
#  /R:2    = retry twice on failure
#  /W:5    = wait 5s between retries
#  /NP     = no per-file progress (cleaner log)
#  /L      = LIST ONLY (dry-run)
#  /TEE    = output to console AND log
$base = @("/E", "/R:2", "/W:5", "/NP", "/NDL", "/TEE")
if ($Mirror) { $base += "/MIR" }
if (-not $Run) { $base += "/L" }

if ($Mirror -and $Run) {
    Write-Host "WARNING: Mirror mode will DELETE files in the destination" -ForegroundColor Red
    Write-Host "that no longer exist in the source. This cannot be undone here.`n" -ForegroundColor Red
    $ok = Read-Host "Type 'MIRROR' to confirm"
    if ($ok -ne "MIRROR") { Write-Host "Aborted."; return }
}

foreach ($src in $validSources) {
    # Each source gets its own subfolder in the destination (by leaf name)
    $leaf = Split-Path $src -Leaf
    $dest = Join-Path $Destination $leaf
    Write-Host "`n--- $src  ->  $dest ---" -ForegroundColor White
    $args = @($src, $dest) + $base + @("/LOG+:$logFile")
    robocopy @args | Out-Host
}

Write-Host "`nDone. Log: $logFile" -ForegroundColor Green
if (-not $Run) { Write-Host "This was a DRY-RUN. Add -Run to copy for real.`n" -ForegroundColor Yellow }
