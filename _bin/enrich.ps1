# enrich.ps1 v2 - reads companies.csv + keywords_manual.txt
# Queries DaData for H-keys, merges with manual M/L/H
# NO RUSSIAN CHARACTERS IN CODE



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not $dadataKey) {
    Write-Host "ERROR: DaData API key is empty." -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}
if (-not (Test-Path $inputCsv)) {
    Write-Host "ERROR: $inputCsv not found. Run SETUP.bat first." -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}

# Load cache
$cache = @{}
if (Test-Path $cacheFile) {
    try {
        $json = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $cache[$p.Name] = $p.Value }
        Write-Host ("Cache: " + $cache.Count + " entries")
    } catch { Write-Host "Cache corrupted" -ForegroundColor Yellow }
}

function Get-PartyData {
    param([string]$Inn)
    if ($cache.ContainsKey($Inn)) {
        Write-Host ("  [cache] " + $Inn) -ForegroundColor DarkGray
        return $cache[$Inn]
    }
    $body = @{ query = $Inn; branch_type = "MAIN" } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod `
            -Uri "https://suggestions.dadata.ru/suggestions/api/4_1/rs/findById/party" `
            -Method Post `
            -Headers @{
                "Authorization" = "Token $dadataKey"
                "Content-Type"  = "application/json"
                "Accept"        = "application/json"
            } `
            -Body $body -TimeoutSec 30 -ErrorAction Stop
        if ($r.suggestions -and $r.suggestions.Count -gt 0) {
            $cache[$Inn] = $r.suggestions[0].data
            return $r.suggestions[0].data
        }
    } catch {
        Write-Host ("  API ERROR: " + $_.Exception.Message) -ForegroundColor Red
    }
    return $null
}

$kw = @{
    H = New-Object System.Collections.Generic.HashSet[string]
    M = New-Object System.Collections.Generic.HashSet[string]
    L = New-Object System.Collections.Generic.HashSet[string]
}

function Add-Kw {
    param([string]$Priority, [string]$Word)
    if (-not $Word) { return }
    $w = $Word.Trim()
    $w = $w -replace '[\u00AB\u00BB\u2018\u2019\u201C\u201D"]', ''
    $w = $w -replace '\s+', ' '
    $w = $w.Trim()
    if ($w.Length -lt 3) { return }
    if ($w -match '^\d+$') { return }
    [void]$kw[$Priority].Add($w)
}

# --- Pass 1: DaData for companies ---
$companies = Import-Csv -Path $inputCsv -Delimiter '|' -Encoding UTF8
Write-Host ("Companies: " + $companies.Count)
Write-Host ""

$fetched = @{}
$allData = @()

$idx = 0
foreach ($c in $companies) {
    $idx++
    $inn = "$($c.inn)".Trim()
    if (-not $inn) { continue }
    if ($fetched.ContainsKey($inn)) { continue }

    Write-Host ("[" + $idx + "/" + $companies.Count + "] INN " + $inn)

    $data = Get-PartyData $inn
    if (-not $data) { Write-Host "  no data" -ForegroundColor DarkYellow; continue }

    $fetched[$inn] = $data
    $allData += $data

    if ($data.name) {
        if ($data.name.short_with_opf) { Add-Kw 'H' $data.name.short_with_opf }
        if ($data.name.full_with_opf)  { Add-Kw 'H' $data.name.full_with_opf }
    }
    if ($data.management -and $data.management.name) { Add-Kw 'H' $data.management.name }
}

# --- Pass 2: manual keywords ---
if (Test-Path $manualTxt) {
    Write-Host ""
    Write-Host "Reading manual file..." -ForegroundColor Cyan
    $mlines = Get-Content $manualTxt -Encoding UTF8
    $mAdded = 0
    foreach ($line in $mlines) {
        $l = $line.Trim()
        if (-not $l) { continue }
        if ($l.StartsWith("#")) { continue }
        if ($l -notmatch '^([HML])\|(.+)$') { continue }
        $prio = $Matches[1]
        $word = $Matches[2].Trim()
        if (-not $word) { continue }
        Add-Kw $prio $word
        $mAdded++
    }
    Write-Host ("  Manual lines added: " + $mAdded)
} else {
    Write-Host ""
    Write-Host "keywords_manual.txt not found - skipping" -ForegroundColor DarkYellow
}

# --- Save ---
$cache | ConvertTo-Json -Depth 20 | Out-File $cacheFile -Encoding UTF8
$allData | ConvertTo-Json -Depth 20 | Out-File $outputRaw -Encoding UTF8

$lines = @()
foreach ($prio in 'H','M','L') {
    foreach ($word in ($kw[$prio] | Sort-Object)) {
        $lines += ($prio + "," + $word)
    }
}
[System.IO.File]::WriteAllLines($outputKw, $lines, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  H (names + directors):  " + $kw['H'].Count)
Write-Host ("  M (founders, manual):   " + $kw['M'].Count)
Write-Host ("  L (related, manual):    " + $kw['L'].Count)
Write-Host ("  Total:                  " + ($kw['H'].Count + $kw['M'].Count + $kw['L'].Count))
Write-Host "===========================================" -ForegroundColor Green

if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
