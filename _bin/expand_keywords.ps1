# expand_keywords.ps1 - extracts clean company names from legal-form-prefixed keys
# SAVE AS UTF-8 WITH BOM

# Автоподключение путей
. "$PSScriptRoot\paths.ps1"

$sourceFile = $kwAutoFile                    # _data\keywords_auto.csv
$outputFile = Join-Path $ProjectRoot "_data\keywords_auto.csv"    # перезаписываем тот же

Write-Host ""
Write-Host "Expanding company names..." -ForegroundColor Cyan

# ------------------------------------------------------------
# Stop-list of generic words that match too much noise
# ------------------------------------------------------------
$stopWords = @(
    'РЕГИОН', 'МИР', 'ПРЕМЬЕР', 'СТАНДАРТ', 'ИНВЕСТ', 'ПОБЕДИТ',
    'ПАРТНЁР', 'ПАРТНЕР', 'ФЛАГМАН', 'АРСЕНАЛ', 'ЭКСТРА', 'АВАНГАРД',
    'СЕВЕРНЫЙ', 'ЭКСПРЕСС', 'ИСТОК', 'КОД', 'АЛЬТАИР', 'МЕЛЬНИК',
    'ДЕСЯТКА', 'КРИСТИ', 'ЭКСПЕДИЦИЯ', 'ЭКСПЕРТ', 'ЭКСПО', 'ЭФИР',
    'ПРЕМЬЕРА', 'КОМПАНИЯ', 'ГРУППА', 'ГРУПП', 'ХОЛДИНГ', 'ЦЕНТР',
    'БИЗНЕС', 'ПРОЕКТ', 'СТРОЙ', 'ТОРГ', 'ПРОМ', 'ТЕХ', 'СЕРВИС',
    'СИСТЕМА', 'СЕТЬ', 'ПЛЮС', 'НОВЫЙ', 'СТАРЫЙ', 'СТОЛИЦА', 'ГОРОД'
)

# ---------- Legal form prefixes ----------
$legalPrefixes = @(
    'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ',
    'ПУБЛИЧНОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО',
    'ЗАКРЫТОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО',
    'ОТКРЫТОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО',
    'АКЦИОНЕРНОЕ ОБЩЕСТВО',
    'ИНДИВИДУАЛЬНЫЙ ПРЕДПРИНИМАТЕЛЬ',
    'ООО', 'ОАО', 'ЗАО', 'ПАО', 'АО', 'ИП'
)

function Extract-CleanNames {
    param([string]$rawName)

    $out = @()

    # Normalize quotes to straight "
    $name = $rawName
    $name = $name -replace '[«»"""]', '"'
    $name = $name -replace '\s+', ' '
    $name = $name.Trim()

    # --- 1. Try to extract quoted part ---
    $quoteMatches = [regex]::Matches($name, '"([^"]+)"')
    foreach ($m in $quoteMatches) {
        $inner = $m.Groups[1].Value.Trim()

        # Min length 3
        if ($inner.Length -lt 3) { continue }

        # Skip if too generic
        if ($stopWords -contains $inner.ToUpper()) { continue }

        # Single word: require length >= 8
        $wordCount = ($inner -split '\s+').Count
        if ($wordCount -eq 1 -and $inner.Length -lt 8) { continue }

        $out += $inner
    }
    if ($out.Count -gt 0) {
        return $out | Select-Object -Unique
    }

    # --- 2. No quotes: strip legal prefix from the beginning ---
    $upper = $name.ToUpper()
    foreach ($prefix in $legalPrefixes) {
        if ($upper.StartsWith($prefix + ' ')) {
            $rest = $name.Substring($prefix.Length).Trim()

            # Min length 3
            if ($rest.Length -lt 3) { return @() }

            # Skip if too generic
            if ($stopWords -contains $rest.ToUpper()) { return @() }

            # Single word: require length >= 8
            $wordCount = ($rest -split '\s+').Count
            if ($wordCount -eq 1 -and $rest.Length -lt 8) { return @() }

            $out += $rest
            return $out | Select-Object -Unique
        }
        if ($upper -eq $prefix) {
            return @()    # key is ONLY legal form, useless
        }
    }

    return @()
}

# ---------- Read source ----------
if (-not (Test-Path $sourceFile)) {
    Write-Host ("ERROR: source not found: " + $sourceFile) -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$lines = Get-Content $sourceFile -Encoding UTF8
if ($lines.Count -gt 0 -and $lines[0]) {
    $lines[0] = $lines[0].TrimStart([char]0xFEFF)
}

# ---------- Pass 1: collect existing ----------
$existing = @{}    # lower -> @{prio; word}
foreach ($line in $lines) {
    if (-not $line) { continue }
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }

    $m = [regex]::Match($line, '^([HML]),(.+)$')
    if (-not $m.Success) { continue }
    $prio = $m.Groups[1].Value
    $word = $m.Groups[2].Value.Trim()

    $lower = $word.ToLower()
    if (-not $existing.ContainsKey($lower)) {
        $existing[$lower] = @{ prio = $prio; word = $word }
    }
}

$originalCount = $existing.Count

# ---------- Pass 2: extract clean names ----------
$newFound = @{}    # lower -> originalCase
foreach ($kv in $existing.Values) {
    if ($kv.prio -ne 'H') { continue }

    # Only try to expand if key looks like it has a legal form
    $looksLikeCompany = $false
    $upper = $kv.word.ToUpper()
    foreach ($prefix in $legalPrefixes) {
        if ($upper.StartsWith($prefix)) { $looksLikeCompany = $true; break }
    }
    if (-not $looksLikeCompany) { continue }

    $cleanNames = Extract-CleanNames $kv.word
    foreach ($cn in $cleanNames) {
        $cnLower = $cn.ToLower()
        # Skip if key already exists as original or we already added it
        if ($existing.ContainsKey($cnLower)) { continue }
        if ($newFound.ContainsKey($cnLower)) { continue }
        # Skip too-short (would produce noise)
        if ($cn.Length -lt 3) { continue }
        $newFound[$cnLower] = $cn
    }
}

# ---------- Build output ----------
$output = @()
# originals first, preserving order
foreach ($kv in $existing.Values) {
    $output += "$($kv.prio),$($kv.word)"
}
# then new H-keys
foreach ($cn in $newFound.Values) {
    $output += "H,$cn"
}

[System.IO.File]::WriteAllLines($outputFile, $output, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  Before:              " + $originalCount)
Write-Host ("  New clean names:     " + $newFound.Count)
Write-Host ("  After:               " + ($originalCount + $newFound.Count))
Write-Host ""
Write-Host ("  Sample new keys:")
$sample = $newFound.Values | Select-Object -First 10
foreach ($s in $sample) {
    Write-Host ("    H," + $s) -ForegroundColor Yellow
}
Write-Host ("  Output: " + $outputFile)
Write-Host "===========================================" -ForegroundColor Green
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}