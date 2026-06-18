# disk-cleanup.ps1 - Clean up disk + find duplicates (full protection)
# Run as Administrator

#requires -RunAsAdministrator

param(
    [string[]]$ScanPaths = @("E:\", "F:\"),
    [switch]$RemoveDuplicates,
    [int]$MaxDuplicates = 500,          # Safety brake: limit
    [int]$MinSizeKB = 10                # Minimum size in KB
)

$quarantine = "$env:USERPROFILE\_Duplicates_Quarantine"
$logFile    = "$quarantine\cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# === PROTECTION 1: Locked folders ===
$protectedFolders = @(
    "$env:WINDIR", "${env:ProgramFiles}", "${env:ProgramFiles(x86)}",
    "$env:ProgramData", "$env:LOCALAPPDATA", "$env:APPDATA",
    "$env:SystemDrive\`$Recycle.Bin",
    "$env:SystemDrive\System Volume Information",
    "$env:OneDrive", "$env:USERPROFILE\OneDrive", "$env:USERPROFILE\Dropbox"
) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLower() }

# === PROTECTION: Locked folder names (anywhere in path) ===
$lockedNames = @(".git", ".svn", "node_modules", "$Recycle.Bin")

# === PROTECTION 2: Locked file types ===
$lockedExtensions = @(
    ".exe", ".dll", ".sys", ".msi", ".bat", ".cmd", ".ps1",
    ".com", ".scr", ".drv", ".cpl", ".ocx", ".ini", ".lnk"
)

# --- Logging function ---
function Write-Log($text) {
    $line = "$(Get-Date -Format 'HH:mm:ss')  $text"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# --- Folder protection check ---
function Test-Protected($path) {
    $p = $path.TrimEnd('\').ToLower()
    foreach ($g in $protectedFolders) {
        if ($p -eq $g -or $p.StartsWith($g + '\')) { return $true }
    }
    foreach ($n in $lockedNames) {
        if ($p -split '\\' -contains $n.ToLower()) { return $true }
    }
    return $false
}

Write-Host "=== Disk Cleanup (full protection) ===`n" -ForegroundColor Cyan

# Ensure log folder exists
if (-not (Test-Path $quarantine)) { New-Item -ItemType Directory -Path $quarantine | Out-Null }
Write-Log "=== Cleanup started ==="

# Check input paths
$validPaths = @()
foreach ($path in $ScanPaths) {
    if (Test-Protected $path) {
        Write-Host "BLOCKED (protected): $path" -ForegroundColor Red
        Write-Log "BLOCKED: $path"
    } elseif (-not (Test-Path $path)) {
        Write-Host "Not found: $path" -ForegroundColor DarkGray
    } else {
        $validPaths += $path
    }
}
if (-not $validPaths) {
    Write-Host "`nNo valid paths. Aborting.`n" -ForegroundColor Red
    return
}

# === PROTECTION: Whitelist confirmation ===
Write-Host "`nThe following folders will be scanned:" -ForegroundColor Yellow
$validPaths | ForEach-Object { Write-Host "    $_" }
$ok = Read-Host "`nScan these folders? (yes/no)"
if ($ok -ne "yes") { Write-Host "Aborted."; Write-Log "Aborted by user."; return }

# --- 1. Clean up temp ---
Write-Host "`n[1] Deleting temp files..." -ForegroundColor Yellow
foreach ($p in @($env:TEMP, "$env:WINDIR\Temp")) {
    if (Test-Path $p) {
        Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Host "Temp + Recycle Bin cleaned`n" -ForegroundColor Green
Write-Log "Temp + Recycle Bin cleaned"

# --- 2. Find duplicates ---
Write-Host "[2] Searching for duplicates..." -ForegroundColor Yellow
$minBytes = $MinSizeKB * 1KB

$all = foreach ($path in $validPaths) {
    Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            (-not $_.Attributes.ToString().Contains("ReparsePoint")) -and  # PROTECTION: no symlinks/junctions
            ($_.Length -ge $minBytes) -and                                  # PROTECTION: minimum size
            ($lockedExtensions -notcontains $_.Extension.ToLower()) -and    # PROTECTION 2: extension
            (-not (Test-Protected $_.DirectoryName))                        # PROTECTION 1: folder
        }
}

$candidates = $all | Group-Object Length | Where-Object Count -gt 1
$hashTable = @{}
foreach ($group in $candidates) {
    foreach ($file in $group.Group) {
        $h = (Get-FileHash $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
        if ($h) {
            if (-not $hashTable.ContainsKey($h)) { $hashTable[$h] = @() }
            $hashTable[$h] += $file
        }
    }
}
$dupGroups = @($hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })

if (-not $dupGroups) {
    Write-Host "`nNo duplicates found.`n" -ForegroundColor Green
    Write-Log "No duplicates found."
    return
}

# --- 3. Report ---
Write-Host "`n[3] Duplicates found:" -ForegroundColor Yellow
$savedMB = 0; $dupCount = 0
foreach ($g in $dupGroups) {
    $files = $g.Value | Sort-Object LastWriteTime
    Write-Host "`n  Group ($([math]::Round($files[0].Length/1MB,2)) MB):" -ForegroundColor White
    Write-Host "    KEEP:      $($files[0].FullName)" -ForegroundColor Green
    $files | Select-Object -Skip 1 | ForEach-Object {
        Write-Host "    DUPLICATE: $($_.FullName)" -ForegroundColor Red
        $savedMB += $_.Length / 1MB; $dupCount++
    }
}
Write-Host "`nDuplicates: $dupCount | Recoverable: ~$([math]::Round($savedMB,0)) MB`n" -ForegroundColor Cyan
Write-Log "Found: $dupCount duplicates (~$([math]::Round($savedMB,0)) MB)"

# === PROTECTION: Count limit ===
if ($dupCount -gt $MaxDuplicates) {
    Write-Host "STOP: $dupCount duplicates exceed limit ($MaxDuplicates)." -ForegroundColor Red
    Write-Host "Check your scan paths or raise -MaxDuplicates deliberately.`n" -ForegroundColor Yellow
    Write-Log "ABORT: Limit exceeded ($dupCount > $MaxDuplicates)"
    return
}

# --- 4. Remove ---
if (-not $RemoveDuplicates) {
    Write-Host "Report only. To move: .\disk-cleanup.ps1 -RemoveDuplicates`n" -ForegroundColor Yellow
    return
}

$answer = Read-Host "Move $dupCount duplicates to quarantine? (yes/no)"
if ($answer -ne "yes") { Write-Host "Aborted."; Write-Log "Move aborted."; return }

# Mapping file for undo (original path <-> quarantine path)
$mapFile = "$quarantine\undo_map_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
"Quarantine;Original" | Set-Content $mapFile

foreach ($g in $dupGroups) {
    $files = $g.Value | Sort-Object LastWriteTime
    $files | Select-Object -Skip 1 | ForEach-Object {
        if (-not (Test-Protected $_.DirectoryName) -and
            ($lockedExtensions -notcontains $_.Extension.ToLower())) {
            $destName = "{0}_{1}" -f (Get-Random), $_.Name
            $dest = Join-Path $quarantine $destName
            $origin = $_.FullName
            Move-Item $origin $dest -Force -ErrorAction SilentlyContinue
            if (Test-Path $dest) {
                "$dest;$origin" | Add-Content $mapFile
                Write-Log "MOVED: $origin  ->  $dest"
            }
        }
    }
}
Write-Host "`nDone. Moved to: $quarantine" -ForegroundColor Green
Write-Host "Log:  $logFile" -ForegroundColor DarkGray
Write-Host "Undo: .\disk-undo.ps1 -MapFile `"$mapFile`"`n" -ForegroundColor Yellow
Write-Log "=== Cleanup finished ==="