# fsrar_unpack.ps1 - unpack downloaded ZIP and analyze XML structure



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not (Test-Path $extractDir)) { New-Item -ItemType Directory -Path $extractDir | Out-Null }

# Find the zip
$zip = Get-ChildItem -Path $zipDir -Filter "*.zip" | Select-Object -First 1
if (-not $zip) {
    Write-Host "ERROR: no .zip found in $zipDir" -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}

Write-Host ("Unpacking: " + $zip.FullName)
Write-Host ("Size: " + [Math]::Round($zip.Length/1MB, 2) + " MB")

# Unpack
Expand-Archive -Path $zip.FullName -DestinationPath $extractDir -Force
Write-Host "Unpacked OK" -ForegroundColor Green
Write-Host ""

# List all files
$files = Get-ChildItem -Path $extractDir -Recurse -File
Write-Host ("Total files: " + $files.Count)
foreach ($f in $files) {
    Write-Host ("  " + $f.FullName.Replace($extractDir, "") + "  [" + [Math]::Round($f.Length/1KB, 1) + " KB]")
}
Write-Host ""

# Find the main XML/CSV data file (the biggest one)
$dataFile = $files | Sort-Object Length -Descending | Select-Object -First 1
Write-Host ("Largest file: " + $dataFile.FullName)
Write-Host ("Size: " + [Math]::Round($dataFile.Length/1MB, 2) + " MB")
Write-Host ""

# Show first 5000 chars
if ($dataFile.Extension -match '\.(xml|csv|txt)') {
    Write-Host "=== First 5000 chars ===" -ForegroundColor Cyan
    $head = Get-Content $dataFile.FullName -TotalCount 100 -Encoding UTF8
    Write-Host ($head -join "`n").Substring(0, [Math]::Min(5000, ($head -join "`n").Length))
}

# Also check if there is a structure (schema) file
$structFile = $files | Where-Object { $_.Name -match 'structure' } | Select-Object -First 1
if ($structFile) {
    Write-Host ""
    Write-Host ("=== Structure file: " + $structFile.Name + " ===") -ForegroundColor Cyan
    $structContent = Get-Content $structFile.FullName -TotalCount 200 -Encoding UTF8
    Write-Host ($structContent -join "`n").Substring(0, [Math]::Min(4000, ($structContent -join "`n").Length))
}

if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
