# disk-usage-gui.ps1 - Largest files, regex filter, delete to Recycle Bin, auto-rescan
# Recoverable: deleted files go to the Recycle Bin

param(
    [string]$Path = "$env:USERPROFILE",
    [int]$TopFiles = 100,
    [int]$MinSizeMB = 50
)

if (-not (Test-Path $Path))
{ Write-Host "Path not found: $Path" -ForegroundColor Red; return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$minBytes = $MinSizeMB * 1MB

# --- Scan function: returns the TopFiles largest files >= min size ---
function Get-LargeFiles
{
    Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $minBytes } |
        Sort-Object Length -Descending |
        Select-Object -First $TopFiles
}

# --- Build the form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Disk Usage - regex filter, delete to Recycle Bin"
$form.Size = New-Object System.Drawing.Size(950, 640)
$form.StartPosition = "CenterScreen"

# Regex search row
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Regex:"
$lblSearch.Location = New-Object System.Drawing.Point(10, 14)
$lblSearch.Size = New-Object System.Drawing.Size(50, 20)
$form.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(60, 11)
$txtSearch.Size = New-Object System.Drawing.Size(500, 25)
$txtSearch.Text = ".*"          # Default: matcht alles (Suche optional)
$form.Controls.Add($txtSearch)

# Toggle: filename vs full path
$chkPath = New-Object System.Windows.Forms.CheckBox
$chkPath.Text = "Match full path (off = filename only)"
$chkPath.Location = New-Object System.Drawing.Point(575, 12)
$chkPath.Size = New-Object System.Drawing.Size(260, 22)
$form.Controls.Add($chkPath)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Location = New-Object System.Drawing.Point(10, 40)
$lblInfo.Size = New-Object System.Drawing.Size(915, 20)
$form.Controls.Add($lblInfo)

# Grid
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(10, 65)
$grid.Size = New-Object System.Drawing.Size(915, 480)
$grid.Anchor = "Top,Bottom,Left,Right"
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.AutoSizeColumnsMode = "Fill"

$colCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.HeaderText = "Delete"; $colCheck.Name = "Delete"; $colCheck.FillWeight = 8
$grid.Columns.Add($colCheck) | Out-Null
$colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.HeaderText = "Size (MB)"; $colSize.Name = "Size"; $colSize.ReadOnly = $true; $colSize.FillWeight = 12
$grid.Columns.Add($colSize) | Out-Null
$colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.HeaderText = "Path"; $colPath.Name = "Path"; $colPath.ReadOnly = $true; $colPath.FillWeight = 80
$grid.Columns.Add($colPath) | Out-Null
$form.Controls.Add($grid)

# State: the current full scan result (unfiltered)
$script:allFiles = @()

# --- Populate the grid from $script:allFiles, applying the regex filter ---
function Update-Grid
{
    $grid.Rows.Clear()
    $pattern = $txtSearch.Text
    $useFull = $chkPath.Checked
    $shown = 0
    foreach ($f in $script:allFiles)
    {
        $target = if ($useFull)
        { $f.FullName
        } else
        { $f.Name
        }
        if ($pattern)
        {
            try
            {
                if ($target -notmatch $pattern)
                { continue
                }
                $txtSearch.BackColor = [System.Drawing.Color]::White
            } catch
            {
                # invalid regex: flag the field, show nothing filtered
                $txtSearch.BackColor = [System.Drawing.Color]::MistyRose
                continue
            }
        }
        $row = $grid.Rows.Add()
        $grid.Rows[$row].Cells["Delete"].Value = $false
        $grid.Rows[$row].Cells["Size"].Value = [math]::Round($f.Length / 1MB, 1)
        $grid.Rows[$row].Cells["Path"].Value = $f.FullName
        $shown++
    }
    if (-not $pattern)
    { $txtSearch.BackColor = [System.Drawing.Color]::White
    }
    $lblInfo.Text = "Showing $shown of $($script:allFiles.Count) files under: $Path"
}

# --- Full rescan from disk, then refresh grid ---
function Invoke-Rescan
{
    $lblInfo.Text = "Scanning $Path ..."
    $form.Refresh()
    $script:allFiles = @(Get-LargeFiles)
    Update-Grid
}

# Live filtering as you type / toggle
$txtSearch.Add_TextChanged({ Update-Grid })
$chkPath.Add_CheckedChanged({ Update-Grid })

# Double-click to open in default app (ignore checkbox column)
$grid.Add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0)
        { return
        }
        if ($grid.Columns[$e.ColumnIndex].Name -eq "Delete")
        { return
        }
        $p = $grid.Rows[$e.RowIndex].Cells["Path"].Value
        if ($p -and (Test-Path $p))
        {
            try
            { Start-Process -FilePath $p -ErrorAction Stop
            } catch
            { [System.Windows.Forms.MessageBox]::Show("Could not open:`n$p`n`n$($_.Exception.Message)", "Open failed") | Out-Null
            }
        } else
        {
            [System.Windows.Forms.MessageBox]::Show("File no longer exists:`n$p", "Not found") | Out-Null
        }
    })

# Buttons
$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "Delete selected (Recycle Bin)"
$btnDelete.Size = New-Object System.Drawing.Size(220, 30)
$btnDelete.Location = New-Object System.Drawing.Point(10, 555)
$btnDelete.Anchor = "Bottom,Left"
$form.Controls.Add($btnDelete)

$btnRescan = New-Object System.Windows.Forms.Button
$btnRescan.Text = "Rescan now"
$btnRescan.Size = New-Object System.Drawing.Size(120, 30)
$btnRescan.Location = New-Object System.Drawing.Point(240, 555)
$btnRescan.Anchor = "Bottom,Left"
$btnRescan.Add_Click({ Invoke-Rescan })
$form.Controls.Add($btnRescan)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Size = New-Object System.Drawing.Size(100, 30)
$btnClose.Location = New-Object System.Drawing.Point(370, 555)
$btnClose.Anchor = "Bottom,Left"
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

$btnDelete.Add_Click({
        $grid.EndEdit()
        $toDelete = @()
        foreach ($row in $grid.Rows)
        {
            if ($row.Cells["Delete"].Value -eq $true)
            { $toDelete += $row.Cells["Path"].Value
            }
        }
        if ($toDelete.Count -eq 0)
        {
            [System.Windows.Forms.MessageBox]::Show("Nothing selected.", "Info") | Out-Null; return
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Send $($toDelete.Count) file(s) to the Recycle Bin?", "Confirm", "YesNo", "Question")
        if ($confirm -ne "Yes")
        { return
        }

        $done = 0
        foreach ($p in $toDelete)
        {
            try
            {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $p,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                $done++
            } catch
            {
                Write-Host "Failed: $p  ($($_.Exception.Message))" -ForegroundColor Red
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Sent $done file(s) to Recycle Bin. Rescanning...", "Done") | Out-Null
        # Full rescan so the next-largest files appear; keeps current regex filter
        Invoke-Rescan
    })

# Initial scan
$form.Add_Shown({ $form.Activate(); Invoke-Rescan })
[void]$form.ShowDialog()
