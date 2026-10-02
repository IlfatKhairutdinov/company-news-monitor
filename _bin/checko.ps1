# checko.ps1 v2 - slow but reliable, handles 429
# Reads: companies_raw.json
# Writes: keywords_checko.csv
# Cache: checko_cache.json (resumes from where it stopped)
# NO RUSSIAN CHARACTERS IN CODE



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

$delayMs       = 2500      # base delay
$jitterMs      = 800       # random addition 0..jitterMs
$retry429Sleep = 60        # seconds to wait on 429
$maxRetries    = 3         # per-company retries on 429

if (-not (Test-Path $rawFile)) {
    Write-Host "ERROR: $rawFile not found. Run SETUP.bat first." -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}

# --- Load cache ---
$cache = @{}
if (Test-Path $cacheFile) {
    try {
        $json = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $cache[$p.Name] = $p.Value }
        Write-Host ("Cache loaded: " + $cache.Count + " entries (will skip these)")
    } catch { Write-Host "Cache corrupted, ignoring" -ForegroundColor Yellow }
}

$raw = Get-Content $rawFile -Raw -Encoding UTF8 | ConvertFrom-Json
$total = $raw.Count
Write-Host ("Companies total: " + $total)
Write-Host ""

$kwM = New-Object System.Collections.Generic.HashSet[string]
$kwL = New-Object System.Collections.Generic.HashSet[string]

function Clean-Word {
    param([string]$w)
    if (-not $w) { return "" }
    $w = [System.Net.WebUtility]::HtmlDecode($w)
    $w = $w -replace '[\u00AB\u00BB\u2018\u2019\u201C\u201D"]', ''
    $w = $w -replace '\s+', ' '
    return $w.Trim()
}

function Add-M { param([string]$w); $w = Clean-Word $w; if ($w.Length -ge 3 -and $w -notmatch '^\d+$') { [void]$kwM.Add($w) } }
function Add-L { param([string]$w); $w = Clean-Word $w; if ($w.Length -ge 3 -and $w -notmatch '^\d+$') { [void]$kwL.Add($w) } }

function Fetch-WithRetry {
    param([string]$Ogrn)
    $url = "https://checko.ru/company/$Ogrn"
    $attempt = 0
    while ($attempt -lt $maxRetries) {
        $attempt++
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 `
                -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" `
                -Headers @{
                    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                    "Accept-Language" = "ru-RU,ru;q=0.9,en;q=0.8"
                } `
                -ErrorAction Stop
            return $resp.Content
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match '429' -or $msg -match 'Too Many') {
                Write-Host ("  [429] attempt $attempt/$maxRetries - sleeping " + $retry429Sleep + "s") -ForegroundColor Yellow
                Start-Sleep -Seconds $retry429Sleep
                continue
            }
            Write-Host ("  ERROR: " + $msg) -ForegroundColor Red
            return $null
        }
    }
    Write-Host "  [429] giving up after $maxRetries attempts" -ForegroundColor Red
    return $null
}

function Parse-CheckoHtml {
    param([string]$Html)
    $sl = [System.Text.RegularExpressions.RegexOptions]::Singleline
    $result = [PSCustomObject]@{
        Management       = @()
        FoundersPhysical = @()
        FoundersLegal    = @()
        Connections      = @()
    }

    $mgmt = [regex]::Match($Html, '<section id="management"[^>]*>(?<b>.*?)</section>', $sl)
    if ($mgmt.Success) {
        foreach ($m in [regex]::Matches($mgmt.Groups['b'].Value, 'href="/person/\d+"[^>]*>(?<n>[^<]+)</a>')) {
            $result.Management += (Clean-Word $m.Groups['n'].Value)
        }
    }

    $founders = [regex]::Match($Html, '<section id="founders"[^>]*>(?<b>.*?)</section>', $sl)
    if ($founders.Success) {
        $fb = $founders.Groups['b'].Value
        foreach ($m in [regex]::Matches($fb, 'href="/person/\d+"[^>]*>(?<n>[^<]+)</a>')) {
            $result.FoundersPhysical += (Clean-Word $m.Groups['n'].Value)
        }
        foreach ($m in [regex]::Matches($fb, 'href="/company/(?!select)[^"?#]+"[^>]*>(?<n>[^<]+)</a>')) {
            $result.FoundersLegal += (Clean-Word $m.Groups['n'].Value)
        }
    }

    $conn = [regex]::Match($Html, '<section id="connections"[^>]*>(?<b>.*?)</section>', $sl)
    if ($conn.Success) {
        $cb = $conn.Groups['b'].Value
        foreach ($m in [regex]::Matches($cb, 'href="/company/[^"?#]+"\s+title="(?<full>[^"]+)"')) {
            $result.Connections += (Clean-Word $m.Groups['full'].Value)
        }
        foreach ($m in [regex]::Matches($cb, 'href="/company/[^?#"]+"[^>]*>(?<short>[^<]+)</a>')) {
            $result.Connections += (Clean-Word $m.Groups['short'].Value)
        }
    }
    return $result
}

$idx = 0
$processed = 0
$fromCache = 0
$fetched = 0
$errors = 0
$consecutive429 = 0

foreach ($c in $raw) {
    $idx++
    $ogrn = "$($c.ogrn)".Trim()
    if ($ogrn -notmatch '^\d{13}$') { continue }

    # Cache hit?
    if ($cache.ContainsKey($ogrn)) {
        $data = $cache[$ogrn]
        $fromCache++
    } else {
        Write-Host ("[" + $idx + "/" + $total + "] OGRN " + $ogrn + " - fetching")
        $html = Fetch-WithRetry $ogrn
        if (-not $html) {
            $errors++
            $consecutive429++
            if ($consecutive429 -ge 3) {
                Write-Host "3 failed fetches in a row - stopping." -ForegroundColor Red
                break
            }
            continue
        }
        $consecutive429 = 0
        $data = Parse-CheckoHtml $html
        $cache[$ogrn] = $data
        $fetched++

        # Save cache often
        if ($fetched % 5 -eq 0) {
            $cache | ConvertTo-Json -Depth 10 | Out-File $cacheFile -Encoding UTF8
            Write-Host ("  [saved cache, total new: " + $fetched + "]") -ForegroundColor DarkGray
        }

        Start-Sleep -Milliseconds ($delayMs + (Get-Random -Maximum $jitterMs))
    }

    # Apply to keyword sets
    foreach ($n in $data.Management)       { Add-M $n }
    foreach ($n in $data.FoundersPhysical) { Add-M $n }
    foreach ($n in $data.FoundersLegal)    { Add-M $n }
    foreach ($n in $data.Connections)      { Add-L $n }

    $processed++
}

$cache | ConvertTo-Json -Depth 10 | Out-File $cacheFile -Encoding UTF8

$lines = @()
foreach ($w in ($kwM | Sort-Object)) { $lines += ("M," + $w) }
foreach ($w in ($kwL | Sort-Object)) { $lines += ("L," + $w) }
[System.IO.File]::WriteAllLines($outKw, $lines, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  M (founders):            " + $kwM.Count)
Write-Host ("  L (related companies):   " + $kwL.Count)
Write-Host ("  Total checko keys:       " + ($kwM.Count + $kwL.Count))
Write-Host ""
Write-Host ("  Companies processed:     " + $processed)
Write-Host ("    from cache:            " + $fromCache)
Write-Host ("    fetched new:           " + $fetched)
Write-Host ("  Errors:                  " + $errors)
Write-Host ("  Cache: " + $cacheFile)
Write-Host ("  Output: " + $outKw)
Write-Host "===========================================" -ForegroundColor Green

if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
