# fsrar_clean.ps1 v2 - clean up FSRAR neighbors list
# SAVE AS UTF-8 WITH BOM



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not (Test-Path $srcFile)) {
    Write-Host "ERROR: $srcFile not found" -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}; exit 1
}

$raw = Get-Content $srcFile -Encoding UTF8
# Strip BOM from first line if present
if ($raw.Count -gt 0) {
    $raw[0] = $raw[0].TrimStart([char]0xFEFF)
}

$kept = @()
$skippedInn = 0
$skippedShort = 0
$skippedNoLegalForm = 0
$skippedBadFormat = 0

$legalForms = @('ООО', 'ОАО', 'ЗАО', 'ПАО', ' АО ', 'ИП ',
                'ОБЩЕСТВО', 'АКЦИОНЕРНОЕ', 'ПУБЛИЧНОЕ', 'ЗАКРЫТОЕ',
                'ОТКРЫТОЕ', 'ИНДИВИДУАЛЬНЫЙ')

foreach ($line in $raw) {
    if (-not $line) { continue }
    $line = $line.Trim()
    if (-not $line) { continue }

    # Format: <H|M|L>,<value>  - value may contain commas
    $m = [regex]::Match($line, '^([HML]),(.+)$')
    if (-not $m.Success) {
        $skippedBadFormat++
        continue
    }
    $prio = $m.Groups[1].Value
    $val  = $m.Groups[2].Value.Trim()

    if (-not $val) {
        $skippedShort++
        continue
    }

    # Skip INN (only digits, 10-12 chars)
    if ($val -match '^\d{10,12}$') {
        $skippedInn++
        continue
    }

    # Skip too short
    if ($val.Length -lt 6) {
        $skippedShort++
        continue
    }

    # Skip if no legal form keyword (case insensitive)
    $upper = $val.ToUpper()
    $hasForm = $false
    foreach ($form in $legalForms) {
        if ($upper.Contains($form)) { $hasForm = $true; break }
    }
    if (-not $hasForm) {
        $skippedNoLegalForm++
        continue
    }

    $kept += "$prio,$val"
}

[System.IO.File]::WriteAllLines($outFile, $kept, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  Input lines:     " + $raw.Count)
Write-Host ("  Kept:            " + $kept.Count)
Write-Host ("  Skipped INN:     " + $skippedInn)
Write-Host ("  Skipped short:   " + $skippedShort)
Write-Host ("  Skipped no-form: " + $skippedNoLegalForm)
Write-Host ("  Skipped bad fmt: " + $skippedBadFormat)
Write-Host ""
Write-Host ("  Output: " + $outFile)
Write-Host "===========================================" -ForegroundColor Green
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
