# excel_to_csv.ps1 - reads counterparties.xlsx, writes companies.csv
# Uses pipe | delimiter to avoid issues with quotes in company names
# NO RUSSIAN CHARACTERS IN CODE



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not (Test-Path $inputXlsx)) {
    Write-Host "ERROR: file not found: $inputXlsx" -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $wb = $excel.Workbooks.Open($inputXlsx, $false, $true)
    $ws = $wb.Sheets(1)
    $used = $ws.UsedRange
    $rows = $used.Rows.Count
    $cols = $used.Columns.Count

    Write-Host "Rows: $rows, Cols: $cols"
    Write-Host ""

    # INN header in cyrillic (char codes)
    $innHeader = [string]([char]0x0418) + [string]([char]0x041D) + [string]([char]0x041D)
    $innIdx = -1

    # Method 1: by header
    for ($c = 1; $c -le $cols; $c++) {
        $h = "$($used.Cells(1, $c).Text)".Trim().ToUpper()
        if ($h -eq $innHeader) { $innIdx = $c; break }
    }

    # Method 2: by content
    if ($innIdx -lt 0) {
        for ($c = 1; $c -le $cols; $c++) {
            $hits = 0
            $limit = [Math]::Min(11, $rows)
            for ($r = 2; $r -le $limit; $r++) {
                $v = "$($used.Cells($r, $c).Text)".Trim()
                $d = ($v -replace '\D', '')
                if ($d.Length -ge 10 -and $d.Length -le 12) { $hits++ }
            }
            if ($hits -ge 2) { $innIdx = $c; break }
        }
    }

    if ($innIdx -lt 0) {
        Write-Host "ERROR: cannot detect INN column." -ForegroundColor Red
        $wb.Close($false); $excel.Quit()
        if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
        exit 1
    }

    $nameIdx = -1
    for ($c = 1; $c -le $cols; $c++) {
        if ($c -ne $innIdx) { $nameIdx = $c; break }
    }

    Write-Host "Name column: $nameIdx, INN column: $innIdx"
    Write-Host ""

    # Pipe delimiter, no quoting
    $outLines = @("name|inn")
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $added = 0
    $skipped = 0

    for ($r = 2; $r -le $rows; $r++) {
        $name = "$($used.Cells($r, $nameIdx).Text)".Trim()
        $innRaw = "$($used.Cells($r, $innIdx).Text)".Trim()

        $digits = ($innRaw -replace '\D', '')
        if ($digits.Length -lt 10 -or $digits.Length -gt 12) {
            $skipped++
            continue
        }
        $inn = $digits

        if (-not $name) { $skipped++; continue }

        # Remove all quote-like characters from name
        $name = $name -replace '[\u00AB\u00BB\u2018\u2019\u201C\u201D"]', ''
        $name = $name -replace '\s+', ' '
        $name = $name.Trim()

        # Remove pipe if it accidentally got into a name
        $name = $name -replace '\|', ' '

        if ($name.Length -lt 2) { $skipped++; continue }
        if ($seen.Contains($inn)) { continue }
        [void]$seen.Add($inn)

        $outLines += ($name + '|' + $inn)
        $added++
    }

    [System.IO.File]::WriteAllLines($outputCsv, $outLines, (New-Object System.Text.UTF8Encoding $true))

    Write-Host "Saved: $added companies, skipped: $skipped"
    Write-Host "Output: $outputCsv"

    $wb.Close($false)
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($used)  | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws)    | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wb)    | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    [GC]::Collect() | Out-Null
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    try { $excel.Quit() } catch {}
}

if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
