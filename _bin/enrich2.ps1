# enrich2.ps1 - извлекает точные связи (директора, адреса) через DaData
# Читает: companies_raw.json
# Пишет: keywords_checko.csv
# Кэш: affiliated_cache.json
# ВАЖНО: нет русских букв в коде



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not $dadataKey) {
    Write-Host "ERROR: DaData API key is empty." -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}
if (-not (Test-Path $rawFile)) {
    Write-Host "ERROR: $rawFile not found. Run SETUP.bat first." -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
    exit 1
}

# --- Кэш ---
$cache = @{}
if (Test-Path $cacheFile) {
    try {
        $json = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $cache[$p.Name] = $p.Value }
        Write-Host ("Кэш загружен: " + $cache.Count + " записей")
    } catch { Write-Host "Кэш повреждён, игнорируем" -ForegroundColor Yellow }
}

$raw = Get-Content $rawFile -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("Компаний в исходных данных: " + $raw.Count)

$kwM = New-Object System.Collections.Generic.HashSet[string] # Учредители/Руководители
$kwL = New-Object System.Collections.Generic.HashSet[string] # Связанные компании

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

# --- Функции запросов к DaData ---
function Get-AffiliatedCompanies {
    param([string]$Inn)
    $body = @{ query = $Inn; count = 50 } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "https://suggestions.dadata.ru/suggestions/api/4_1/rs/findAffiliated/party" `
            -Method Post -Headers @{ "Authorization" = "Token $dadataKey"; "Content-Type" = "application/json"; "Accept" = "application/json" } `
            -Body $body -TimeoutSec 30 -ErrorAction Stop
        return $r.suggestions
    } catch { return @() }
}

function Find-CompaniesByAddress {
    param([string]$AddressPart)
    $body = @{ query = $AddressPart; count = 20; type = "LEGAL" } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/party" `
            -Method Post -Headers @{ "Authorization" = "Token $dadataKey"; "Content-Type" = "application/json"; "Accept" = "application/json" } `
            -Body $body -TimeoutSec 30 -ErrorAction Stop
        return $r.suggestions
    } catch { return @() }
}

# --- Основной цикл ---
$idx = 0
foreach ($c in $raw) {
    $idx++
    $inn = "$($c.inn)".Trim()
    if (-not $inn -or $inn -notmatch '^\d{10,12}$') { continue }

    Write-Host ("[" + $idx + "/" + $raw.Count + "] ИНН " + $inn)

    # 1. Связи по директору
    if ($c.management -and $c.management.name) {
        $directorName = $c.management.name
        Add-M $directorName
        $cacheKey = "mgr_$($inn)"
        if (-not $cache.ContainsKey($cacheKey)) {
            Write-Host "  -> поиск компаний директора: $directorName"
            $affiliated = Get-AffiliatedCompanies -Inn $inn
            foreach ($item in $affiliated) {
                Add-L $item.value
                if ($item.data.founders) { foreach ($f in $item.data.founders) { if ($f.fio) { Add-M ($f.fio.surname + ' ' + $f.fio.name + ' ' + $f.fio.patronymic) } } }
            }
            $cache[$cacheKey] = $true
            Start-Sleep -Milliseconds 300 # Небольшая пауза
        } else { Write-Host "  -> [кэш] директор" -ForegroundColor DarkGray }
    }

    # 2. Связи по адресу
    if ($c.address -and $c.address.value) {
        $address = $c.address.value
        # Берём только часть "улица, дом" для поиска
        if ($address -match '(ул\.?|пр\.?|пер\.?|б-р|ш\.?)\s+[^,]+,\s*д\.?\s*\d+[^,]*') {
            $addrPart = $matches[0]
            $cacheKey = "addr_$($inn)"
            if (-not $cache.ContainsKey($cacheKey)) {
                Write-Host "  -> поиск по адресу: $addrPart"
                $found = Find-CompaniesByAddress -AddressPart $addrPart
                foreach ($item in $found) {
                    if ($item.data.inn -ne $inn) { Add-L $item.value }
                }
                $cache[$cacheKey] = $true
                Start-Sleep -Milliseconds 300
            } else { Write-Host "  -> [кэш] адрес" -ForegroundColor DarkGray }
        }
    }
}

# --- Сохранение ---
$cache | ConvertTo-Json -Depth 10 | Out-File $cacheFile -Encoding UTF8

$lines = @()
foreach ($w in ($kwM | Sort-Object)) { $lines += ("M," + $w) }
foreach ($w in ($kwL | Sort-Object)) { $lines += ("L," + $w) }
[System.IO.File]::WriteAllLines($outKw, $lines, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  M (учредители/руководители): " + $kwM.Count)
Write-Host ("  L (связанные компании):     " + $kwL.Count)
Write-Host ("  Всего ключей (M+L):         " + ($kwM.Count + $kwL.Count))
Write-Host ("  Файл: " + $outKw)
Write-Host "===========================================" -ForegroundColor Green

if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
