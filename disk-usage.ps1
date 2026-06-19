# disk-usage.ps1 - Report largest files and folders under a path
# Read-only - never modifies anything

param(
    [string]$Path = "$env:USERPROFILE",
    [int]$TopFiles = 20,
    [int]$TopFolders = 15,
    [int]$MinSizeMB = 50          # ignore files smaller than this in the file list
)

if (-not (Test-Path $Path))
{ Write-Host "Path not found: $Path" -ForegroundColor Red; return 
}

Write-Host "=== Disk Usage Report ===" -ForegroundColor Cyan
Write-Host "Scanning: $Path`n" -ForegroundColor DarkGray

# --- Drive overview ---
$drive = Get-PSDrive -Name ($Path.Substring(0,1)) -ErrorAction SilentlyContinue
if ($drive)
{
    $usedGB  = [math]::Round($drive.Used / 1GB, 1)
    $freeGB  = [math]::Round($drive.Free / 1GB, 1)
    $totalGB = $usedGB + $freeGB
    $pct     = [math]::Round(($usedGB / $totalGB) * 100, 0)
    Write-Host "Drive $($drive.Name): $usedGB GB used / $totalGB GB total ($pct% full, $freeGB GB free)`n" -ForegroundColor Yellow
}

Write-Host "Collecting files (this can take a while on large folders)..." -ForegroundColor DarkGray
$allFiles = Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue

# --- Largest files ---
$minBytes = $MinSizeMB * 1MB
Write-Host "`n[ Top $TopFiles largest files (>= $MinSizeMB MB) ]" -ForegroundColor Cyan
$allFiles |
    Where-Object { $_.Length -ge $minBytes } |
    Sort-Object Length -Descending |
    Select-Object -First $TopFiles |
    ForEach-Object {
        "{0,8:N0} MB   {1}" -f ($_.Length / 1MB), $_.FullName
    } | Write-Host

# --- Largest top-level subfolders ---
Write-Host "`n[ Top $TopFolders largest folders (first level under path) ]" -ForegroundColor Cyan
$subDirs = Get-ChildItem $Path -Directory -ErrorAction SilentlyContinue
$folderSizes = foreach ($d in $subDirs)
{
    $size = (Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
    [PSCustomObject]@{ Folder = $d.FullName; SizeMB = [math]::Round($size / 1MB, 0) }
}
$folderSizes |
    Sort-Object SizeMB -Descending |
    Select-Object -First $TopFolders |
    ForEach-Object { "{0,8:N0} MB   {1}" -f $_.SizeMB, $_.Folder } |
    Write-Host

# --- File-type breakdown ---
Write-Host "`n[ Space by file type (top 10) ]" -ForegroundColor Cyan
$allFiles |
    Group-Object Extension |
    ForEach-Object {
        [PSCustomObject]@{
            Type  = if ($_.Name)
            { $_.Name 
            } else
            { "(none)" 
            }
            SizeMB = [math]::Round(($_.Group | Measure-Object Length -Sum).Sum / 1MB, 0)
            Count = $_.Count
        }
    } |
    Sort-Object SizeMB -Descending |
    Select-Object -First 10 |
    ForEach-Object { "{0,8:N0} MB   {1,-8}  ({2} files)" -f $_.SizeMB, $_.Type, $_.Count } |
    Write-Host

Write-Host "`nDone (read-only, nothing was changed).`n" -ForegroundColor Green
