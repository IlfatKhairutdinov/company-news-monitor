# merge_keywords.ps1 - combine all keyword sources into keywords_all.csv
# SAVE AS UTF-8 WITH BOM

# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

# Приоритет по каждому источнику
$sources = @(
    @{ Path = $kwAutoFile;   Prio = "H";   Name = "keywords_auto.csv" }
    @{ Path = $kwCheckoFile; Prio = "ML";  Name = "keywords_checko.csv" }
    @{ Path = $kwFsrarFile;  Prio = "L";   Name = "keywords_checko_fsrar_clean.csv" }
    @{ Path = $kwManualFile; Prio = "MAN"; Name = "keywords_manual.txt" }
)

$byWord = @{}
$stats  = @{ H = 0; M = 0; L = 0; skipped = 0 }
$prioRank = @{ "H" = 3; "M" = 2; "L" = 1 }

function Add-Key {
    param([string]$Prio, [string]$Word)
    if (-not $Word) { return }
    $w = $Word.Trim()
    $w = $w -replace '[\u00AB\u00BB\u2018\u2019\u201C\u201D"]', ''
    $w = $w -replace '\s+', ' '
    $w = $w.Trim()
    if ($w.Length -lt 3) { $script:stats.skipped++; return }
    if ($w -match '^\d+$') { $script:stats.skipped++; return }

    $key = $w.ToLower()
    if ($byWord.ContainsKey($key)) {
        $existing = $byWord[$key]
        if ($prioRank[$Prio] -gt $prioRank[$existing.prio]) {
            $existing.prio = $Prio
        }
    } else {
        $byWord[$key] = @{ word = $w; prio = $Prio }
    }
}

# --- Process each file ---
foreach ($src in $sources) {
    if (-not (Test-Path $src.Path)) {
        Write-Host ("SKIP (not found): " + $src.Name) -ForegroundColor DarkYellow
        continue
    }

    Write-Host ("Reading: " + $src.Name) -ForegroundColor Cyan
    $lines = Get-Content $src.Path -Encoding UTF8
    $count = 0

    foreach ($line in $lines) {
        if (-not $line) { continue }
        $line = $line.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith("#")) { continue }

        # "PRIO,value" формат
        $m = [regex]::Match($line, '^([HML]),(.+)$')
        if ($m.Success) {
            Add-Key $m.Groups[1].Value $m.Groups[2].Value
            $count++
            continue
        }

        # "PRIO|value" формат (ручной)
        $m = [regex]::Match($line, '^([HML])\|(.+)$')
        if ($m.Success) {
            Add-Key $m.Groups[1].Value $m.Groups[2].Value
            $count++
            continue
        }

        # Голое значение - только для ручного файла, ставим L
        if ($src.Prio -eq "MAN") {
            Add-Key "L" $line
            $count++
        }
    }
    Write-Host ("  lines: " + $count)
}

# --- Save to keywords_all.csv (НЕ в $outFile!) ---
$out = @()
foreach ($kv in ($byWord.GetEnumerator() | Sort-Object { $_.Value.prio }, { $_.Value.word })) {
    $out += ("$($kv.Value.prio),$($kv.Value.word)")
    $stats[$kv.Value.prio]++
}

# Retry logic for locked file
$attempt = 0
$maxAttempts = 5
while ($attempt -lt $maxAttempts) {
    $attempt++
    try {
        [System.IO.File]::WriteAllLines($keywordsFile, $out, (New-Object System.Text.UTF8Encoding $true))
        break
    } catch {
        Write-Host ("  File locked, retry $attempt/$maxAttempts...") -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        if ($attempt -eq $maxAttempts) {
            Write-Host ("  FAILED after $maxAttempts attempts: " + $_.Exception.Message) -ForegroundColor Red
            throw
        }
    }
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  H (high):   " + $stats.H)
Write-Host ("  M (medium): " + $stats.M)
Write-Host ("  L (low):    " + $stats.L)
Write-Host ("  Skipped:    " + $stats.skipped)
Write-Host ("  TOTAL:      " + ($stats.H + $stats.M + $stats.L))
Write-Host ""
Write-Host ("  Output: " + $keywordsFile)
Write-Host "===========================================" -ForegroundColor Green
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}