# pc-tuneup.ps1 - Windows Home-Use Optimierung
# Als Administrator ausfuehren: Rechtsklick > "Mit PowerShell ausfuehren"

#requires -RunAsAdministrator

Write-Host "=== PC Tune-Up gestartet ===`n" -ForegroundColor Cyan

# --- 1. Autostart anzeigen ---
Write-Host "[1] Autostart-Programme:" -ForegroundColor Yellow
Get-CimInstance Win32_StartupCommand |
    Select-Object Name, Command, Location |
    Format-Table -AutoSize
Write-Host "Deaktivieren ueber: Task-Manager > Autostart (Strg+Shift+Esc)`n"

# --- 2. Temp-Dateien aufraeumen ---
Write-Host "[2] Temp-Dateien werden geloescht..." -ForegroundColor Yellow
$paths = @($env:TEMP, "$env:WINDIR\Temp")
$freedMB = 0
foreach ($p in $paths) {
    if (Test-Path $p) {
        $before = (Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue |
                   Measure-Object Length -Sum).Sum
        Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $freedMB += [math]::Round($before / 1MB, 0)
    }
}
# Papierkorb leeren
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Host "Freigegeben: ~$freedMB MB + Papierkorb`n" -ForegroundColor Green

# --- 3. Energieeinstellungen (Hoechstleistung) ---
Write-Host "[3] Energieplan wird gesetzt..." -ForegroundColor Yellow
powercfg /setactive SCHEME_MIN          # Hoechstleistung
powercfg /change monitor-timeout-ac 15  # Bildschirm aus nach 15 min
powercfg /change standby-timeout-ac 0   # Kein automatischer Standby
Write-Host "Hoechstleistung aktiv`n" -ForegroundColor Green

# --- 4. Schnell-Check ---
Write-Host "[4] System-Status:" -ForegroundColor Yellow
$os = Get-CimInstance Win32_OperatingSystem
$ramFreeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$disk = Get-PSDrive C
Write-Host "RAM frei: $ramFreeGB / $ramTotalGB GB"
Write-Host "Disk C: frei: $([math]::Round($disk.Free/1GB,1)) GB`n"

Write-Host "=== Fertig ===" -ForegroundColor Cyan