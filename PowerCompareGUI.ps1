<#
.SYNOPSIS
    PowerShell folder comparison utility.

.DESCRIPTION
    Folder comparison utility using Windows Forms interface where user initially selects two folders to be compared and hits Button `Compare`.
	These folders are processed recursively and	Verified Hash is shown for Each matched pair of objects.
	Output visualized in table (matched Rows higlighted in Gray.
	Other (non-matched) rows shown in Red (file/folder only in Folder 1), Green (file/folder only in Folder 2) and Yellow (matching filenames, but hashes differ).
	Resulting table can be exported to csv file `Folder_Comparison_Report.csv` hitting Button `Export to Csv`).

.EXAMPLE
    .\PowerCompareGUI.ps1
    Runs the script.

.NOTES
    Author:       soyuiz
    Date:         2026-09-18
    Version:      1.0.0
    Required Privileges: Administrator
    
.LINK
    https://github.com/soyuiz11/PowerCompareGUI
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Create the main form
$form = New-Object Windows.Forms.Form
$form.Text = "PowerCompareGUI (Hash Verified & Exportable) @1.0.0"
$form.Size = New-Object Drawing.Size @(1000,650)
$form.StartPosition = "CenterScreen"

# Create the "Folder 1" label
$folder1Label = New-Object Windows.Forms.Label
$folder1Label.Text = "Folder 1:"
$folder1Label.Size = New-Object Drawing.Size @(50,25)
$folder1Label.Location = New-Object Drawing.Point @(50,50)
$form.Controls.Add($folder1Label)

# Create the "Folder 1" text box
$folder1TextBox = New-Object Windows.Forms.TextBox
$folder1TextBox.Size = New-Object Drawing.Size @(250,25)
$folder1TextBox.Location = New-Object Drawing.Point @(105,50)
$form.Controls.Add($folder1TextBox)

# Create the "Browse" button for "Folder 1"
$browseButton1 = New-Object Windows.Forms.Button
$browseButton1.Text = "Browse"
$browseButton1.Size = New-Object Drawing.Size @(100,25)
$browseButton1.Location = New-Object Drawing.Point @(360,50)
$form.Controls.Add($browseButton1)
$browseButton1.Add_Click({
    $folderBrowserDialog = New-Object Windows.Forms.FolderBrowserDialog
    if ($folderBrowserDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $folder1TextBox.Text = $folderBrowserDialog.SelectedPath
    }
})

# Create the "Folder 2" label
$folder2Label = New-Object Windows.Forms.Label
$folder2Label.Text = "Folder 2:"
$folder2Label.Size = New-Object Drawing.Size @(50,25)
$folder2Label.Location = New-Object Drawing.Point @(470,50)
$form.Controls.Add($folder2Label)

# Create the "Folder 2" text box
$folder2TextBox = New-Object Windows.Forms.TextBox
$folder2TextBox.Size = New-Object Drawing.Size @(250,25)
$folder2TextBox.Location = New-Object Drawing.Point @(525,50)
$form.Controls.Add($folder2TextBox)

# Create the "Browse" button for "Folder 2"
$browseButton2 = New-Object Windows.Forms.Button
$browseButton2.Text = "Browse"
$browseButton2.Size = New-Object Drawing.Size @(100,25)
$browseButton2.Location = New-Object Drawing.Point @(780,50)
$form.Controls.Add($browseButton2)
$browseButton2.Add_Click({
    $folderBrowserDialog = New-Object Windows.Forms.FolderBrowserDialog
    if ($folderBrowserDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $folder2TextBox.Text = $folderBrowserDialog.SelectedPath
    }
})

# Create the "Compare" button
$compareButton = New-Object Windows.Forms.Button
$compareButton.Text = "Compare"
$compareButton.Size = New-Object Drawing.Size @(100,25)
$compareButton.Location = New-Object Drawing.Point @(50,100)
$form.Controls.Add($compareButton)

# Create the "Export CSV" button
$exportButton = New-Object Windows.Forms.Button
$exportButton.Text = "Export to CSV"
$exportButton.Size = New-Object Drawing.Size @(120,25)
$exportButton.Location = New-Object Drawing.Point @(160,100)
$exportButton.Enabled = $false
$form.Controls.Add($exportButton)

# --- CREATE LISTVIEW ONCE ON FORM LOAD ---
$listView = New-Object Windows.Forms.ListView
$listView.Size = New-Object Drawing.Size @(900,430)
$listView.Location = New-Object Drawing.Point @(50,150)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true

# Add columns to the list view
$null = $listView.Columns.Add("Relative Path / Name", 220, [System.Windows.Forms.HorizontalAlignment]::Left)
$null = $listView.Columns.Add("Type", 60, [System.Windows.Forms.HorizontalAlignment]::Left)
$null = $listView.Columns.Add("Folder 1 Presence", 240, [System.Windows.Forms.HorizontalAlignment]::Left)
$null = $listView.Columns.Add("Folder 2 Presence", 240, [System.Windows.Forms.HorizontalAlignment]::Left)
$null = $listView.Columns.Add("Result Status", 120, [System.Windows.Forms.HorizontalAlignment]::Left)
$form.Controls.Add($listView)

# Global tracking target cache
$script:comparisonResults = @()

# Helper function to get relative files and SHA256 content fingerprints
function Get-FolderInventory ($basePath) {
    $inventory = @{}
    if (-not (Test-Path $basePath)) { return $inventory }
    $items = Get-ChildItem $basePath -Recurse
    foreach ($item in $items) {
        $relativePath = $item.FullName.Substring($basePath.Length).TrimStart('\')
        $hash = ""
        if (-not $item.PSIsContainer) {
            try {
                $hash = (Get-FileHash $item.FullName -Algorithm SHA256).Hash
            } catch {
                $hash = "ERROR_READING_FILE"
            }
        }
        $inventory[$relativePath] = @{
            Name        = $item.Name
            FullName    = $item.FullName
            IsContainer = $item.PSIsContainer
            Hash        = $hash
        }
    }
    return $inventory
}

# Action when "Compare" is clicked
$compareButton.Add_Click({
    $listView.Items.Clear()
    $exportButton.Enabled = $false
    $script:comparisonResults = @()
    $folder1 = $folder1TextBox.Text
    $folder2 = $folder2TextBox.Text

    if (-not (Test-Path $folder1) -or -not (Test-Path $folder2)) {
        [System.Windows.Forms.MessageBox]::Show("Please select two valid folder paths first.", "Error")
        return
    }

    $inventory1 = Get-FolderInventory -basePath $folder1
    $inventory2 = Get-FolderInventory -basePath $folder2

    $allRelativePaths = ($inventory1.Keys + $inventory2.Keys) | Select-Object -Unique | Sort-Object

    if ($allRelativePaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Both selected directories are empty.", "Comparison Complete")
        return
    }

    $mismatches = 0
    foreach ($relPath in $allRelativePaths) {
        $in1 = $inventory1.ContainsKey($relPath)
        $in2 = $inventory2.ContainsKey($relPath)
        
        $item = New-Object Windows.Forms.ListViewItem
        $item.UseItemStyleForSubItems = $false 
        
        $typeStr = "File"
        $f1Presence = ""
        $f2Presence = ""
        $statusText = ""
        $bgColor = [System.Drawing.Color]::White
        $fgColor = [System.Drawing.Color]::Black

        if (($in1 -and $inventory1[$relPath].IsContainer) -or ($in2 -and $inventory2[$relPath].IsContainer)) {
            $typeStr = "Folder"
        }

        # Assessment Processing Logic
        if ($in1 -and -not $in2) {
            $f1Presence = $inventory1[$relPath].FullName
            $f2Presence = "Absent"
            $statusText = "Only in Folder 1"
            $bgColor = [System.Drawing.Color]::FromArgb(255, 230, 230) 
            $mismatches++
        }
        elseif (-not $in1 -and $in2) {
            $f1Presence = "Absent"
            $f2Presence = $inventory2[$relPath].FullName
            $statusText = "Only in Folder 2"
            $bgColor = [System.Drawing.Color]::FromArgb(230, 245, 230) 
            $mismatches++
        }
        else {
            if ($typeStr -eq "File") {
                $hash1 = $inventory1[$relPath].Hash
                $hash2 = $inventory2[$relPath].Hash
                if ($hash1 -ne $hash2) {
                    $f1Presence = "Match (" + $hash1.Substring(0,8) + "...)"
                    $f2Presence = "Match (" + $hash2.Substring(0,8) + "...)"
                    $statusText = "Modified Content"
                    $bgColor = [System.Drawing.Color]::FromArgb(255, 255, 204) 
                    $mismatches++
                } else {
                    $f1Presence = "Identical (" + $hash1.Substring(0,8) + "...)"
                    $f2Presence = "Identical (" + $hash2.Substring(0,8) + "...)"
                    $statusText = "Identical Match"
                    $bgColor = [System.Drawing.Color]::FromArgb(240, 240, 240) 
                    $fgColor = [System.Drawing.Color]::Gray
                }
            } else {
                $f1Presence = $inventory1[$relPath].FullName
                $f2Presence = $inventory2[$relPath].FullName
                $statusText = "Identical Match"
                $bgColor = [System.Drawing.Color]::FromArgb(240, 240, 240) 
                $fgColor = [System.Drawing.Color]::Gray
            }
        }

        # Apply structural settings to ListView
        $item.Text = $relPath
        $null = $item.SubItems.Add($typeStr)
        $null = $item.SubItems.Add($f1Presence)
        $null = $item.SubItems.Add($f2Presence)
        $null = $item.SubItems.Add($statusText)
        
        foreach ($sub in $item.SubItems) {
            $sub.BackColor = $bgColor
            $sub.ForeColor = $fgColor
        }
        
        $null = $listView.Items.Add($item)
        
        $script:comparisonResults += [PSCustomObject]@{
            "Relative Path"     = $relPath
            "Type"              = $typeStr
            "Folder 1 Presence" = $f1Presence
            "Folder 2 Presence" = $f2Presence
            "Result Status"     = $statusText
        }
    }

    if ($script:comparisonResults.Count -gt 0) {
        $exportButton.Enabled = $true
    }

    if ($mismatches -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Folders match perfectly! All identical hashes verified.", "Comparison Complete")
    }
})

# Action when "Export to CSV" is clicked
$exportButton.Add_Click({
    if ($script:comparisonResults.Count -eq 0) { return }
    $saveFileDialog = New-Object Windows.Forms.SaveFileDialog
    $saveFileDialog.Filter = "CSV Files (*.csv)|*.csv"
    $saveFileDialog.Title = "Save Comparison Report"
    $saveFileDialog.FileName = "Folder_Comparison_Report.csv"
    
    if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $script:comparisonResults | Export-Csv -Path $saveFileDialog.FileName -NoTypeInformation -Encoding UTF8
            $msgPath = $saveFileDialog.FileName
            [System.Windows.Forms.MessageBox]::Show("Report successfully exported to field path location: `n`n$msgPath", "Success")
        } 
        catch {
            $err = $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show("Failed to export CSV: $err", "Error")
        }
    }
})

# Show the form
[void]$form.ShowDialog()