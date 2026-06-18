# disk-undo.ps1 - Restore moved duplicates
param(
    [Parameter(Mandatory=$true)][string]$MapFile
)

if (-not (Test-Path $MapFile)) {
    Write-Host "Map file not found: $MapFile" -ForegroundColor Red; return
}

Write-Host "=== Undo: Restore files ===`n" -ForegroundColor Cyan
$entries = Import-Csv $MapFile -Delimiter ';'
Write-Host "$($entries.Count) files will be moved back.`n"

$ok = Read-Host "Continue? (yes/no)"
if ($ok -ne "yes") { Write-Host "Aborted."; return }

$success = 0; $failed = 0
foreach ($e in $entries) {
    if (Test-Path $e.Quarantine) {
        # Recreate destination folder if needed
        $destFolder = Split-Path $e.Original -Parent
        if (-not (Test-Path $destFolder)) {
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
        }
        # Don't overwrite if something is already there
        if (Test-Path $e.Original) {
            Write-Host "Already exists, skipped: $($e.Original)" -ForegroundColor Yellow
            $failed++
        } else {
            Move-Item $e.Quarantine $e.Original -Force -ErrorAction SilentlyContinue
            if (Test-Path $e.Original) { $success++ } else { $failed++ }
        }
    } else {
        Write-Host "Quarantine file missing: $($e.Quarantine)" -ForegroundColor DarkGray
        $failed++
    }
}
Write-Host "`nRestored: $success | Problems: $failed`n" -ForegroundColor Green