# Are the workspaces Premium or Premium Per User (PPU) - then Enhanced Metadata is often enabled
# If Pro, then Enhanced Metadata is not available



# Connect to Power BI
Connect-PowerBIServiceAccount

# Workspace IDs (replace with your actual Dev/Prod workspace IDs)
$workspaceDev = "60d5553a-751f-45c1-a717-1880b996ea89"
$workspaceProd = "0320659e-abdb-4a73-bfce-5d3916eaca61"

# Output folder for CSVs (replace with a folder you want)
$outputFolder = "C:\Users\0798399\Documents\PBI_Diffs"

# Create folder if it doesn't exist
if (-not (Test-Path $outputFolder)) {
New-Item -ItemType Directory -Path $outputFolder
}

# Get datasets
$devDatasets = Get-PowerBIDataset -WorkspaceId $workspaceDev
$prodDatasets = Get-PowerBIDataset -WorkspaceId $workspaceProd

# Compare dataset names
$datasetDiff = Compare-Object -ReferenceObject $devDatasets.Name -DifferenceObject $prodDatasets.Name |
Select-Object InputObject, SideIndicator
$datasetDiff | Export-Csv -Path "$outputFolder\DatasetDiff.csv" -NoTypeInformation
Write-Host "Saved DatasetDiff.csv in $outputFolder"

# Compare tables and measures (names only)
foreach ($ds in $devDatasets) {
$matching = $prodDatasets | Where-Object { $_.Name -eq $ds.Name }
if ($matching) {
Write-Host "Comparing tables and measures for dataset $($ds.Name)"

# Tables in Dev
$devTables = $ds.Tables | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue
$prodTables = $matching.Tables | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue

if ($devTables -or $prodTables) {
$tableDiff = Compare-Object -ReferenceObject $devTables -DifferenceObject $prodTables |
Select-Object InputObject, SideIndicator
$tableDiff | Export-Csv -Path "$outputFolder\$($ds.Name)_TableDiff.csv" -NoTypeInformation
Write-Host "Saved $($ds.Name)_TableDiff.csv in $outputFolder"
}

# Measures in Dev
$devMeasures = $ds.Measures | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue
$prodMeasures = $matching.Measures | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue

if ($devMeasures -or $prodMeasures) {
$measureDiff = Compare-Object -ReferenceObject $devMeasures -DifferenceObject $prodMeasures |
Select-Object InputObject, SideIndicator
$measureDiff | Export-Csv -Path "$outputFolder\$($ds.Name)_MeasureDiff.csv" -NoTypeInformation
Write-Host "Saved $($ds.Name)_MeasureDiff.csv in $outputFolder"
}
}
}