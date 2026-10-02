# analyze_regions.ps1 - finds regions of our companies
# SAVE AS UTF-8 WITH BOM



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

$raw = Get-Content $rawFile -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "Analyzing regions of our 298 companies..." -ForegroundColor Cyan
Write-Host ""

# --- Map region code to name ---
$regionNames = @{
    "01" = "Адыгея"; "02" = "Башкортостан"; "03" = "Бурятия"; "04" = "Алтай";
    "05" = "Дагестан"; "06" = "Ингушетия"; "07" = "Кабардино-Балкария";
    "08" = "Калмыкия"; "09" = "Карачаево-Черкессия"; "10" = "Карелия";
    "11" = "Коми"; "12" = "Марий Эл"; "13" = "Мордовия"; "14" = "Саха (Якутия)";
    "15" = "Северная Осетия"; "16" = "Татарстан"; "17" = "Тыва"; "18" = "Удмуртия";
    "19" = "Хакасия"; "20" = "Чечня"; "21" = "Чувашия"; "22" = "Алтайский край";
    "23" = "Краснодарский край"; "24" = "Красноярский край"; "25" = "Приморский край";
    "26" = "Ставропольский край"; "27" = "Хабаровский край"; "28" = "Амурская";
    "29" = "Архангельская"; "30" = "Астраханская"; "31" = "Белгородская";
    "32" = "Брянская"; "33" = "Владимирская"; "34" = "Волгоградская";
    "35" = "Вологодская"; "36" = "Воронежская"; "37" = "Ивановская";
    "38" = "Иркутская"; "39" = "Калининградская"; "40" = "Калужская";
    "41" = "Камчатский край"; "42" = "Кемеровская"; "43" = "Кировская";
    "44" = "Костромская"; "45" = "Курганская"; "46" = "Курская";
    "47" = "Ленинградская"; "48" = "Липецкая"; "49" = "Магаданская";
    "50" = "Московская"; "51" = "Мурманская"; "52" = "Нижегородская";
    "53" = "Новгородская"; "54" = "Новосибирская"; "55" = "Омская";
    "56" = "Оренбургская"; "57" = "Орловская"; "58" = "Пензенская";
    "59" = "Пермский край"; "60" = "Псковская"; "61" = "Ростовская";
    "62" = "Рязанская"; "63" = "Самарская"; "64" = "Саратовская";
    "65" = "Сахалинская"; "66" = "Свердловская"; "67" = "Смоленская";
    "68" = "Тамбовская"; "69" = "Тверская"; "70" = "Томская";
    "71" = "Тульская"; "72" = "Тюменская"; "73" = "Ульяновская";
    "74" = "Челябинская"; "75" = "Забайкальский край"; "76" = "Ярославская";
    "77" = "Москва"; "78" = "Санкт-Петербург"; "79" = "Еврейская АО";
    "83" = "Ненецкий АО"; "86" = "Ханты-Мансийский АО"; "87" = "Чукотский АО";
    "89" = "Ямало-Ненецкий АО"; "91" = "Крым"; "92" = "Севастополь";
    "94" = "ЛНР/ДНР/Запорожье/Херсон"
}

# --- From DaData: analyze our companies ---
$regionCounts = @{}
foreach ($c in $raw) {
    if ($c.address -and $c.address.data -and $c.address.data.region_iso_code) {
        $iso = $c.address.data.region_iso_code
        if ($iso -match 'RU-([A-Z]+)') {
            $code = $matches[1]
            if (-not $regionCounts.ContainsKey($code)) { $regionCounts[$code] = 0 }
            $regionCounts[$code]++
        }
    }
}

Write-Host "=== Regions of our companies (from DaData) ===" -ForegroundColor Yellow
$report = @("=== Regions report ===", "")

$report += "--- From DaData (companies_raw.json) ---"
foreach ($kv in ($regionCounts.GetEnumerator() | Sort-Object Value -Descending)) {
    $line = "  $($kv.Key)  : $($kv.Value) companies"
    Write-Host $line
    $report += $line
}

# --- From FSRAR: which regions had licenses of our companies ---
Write-Host ""
Write-Host "Scanning FSRAR for our INNs (may take 3-5 min)..." -ForegroundColor Cyan

$ourInns = New-Object System.Collections.Generic.HashSet[string]
foreach ($c in $raw) { if ($c.inn) { [void]$ourInns.Add("$($c.inn)".Trim()) } }

$fsrarRegionCounts = @{}
$reader = [System.IO.StreamReader]::new($fsrarCsv, [System.Text.Encoding]::UTF8)
$null = $reader.ReadLine()
$lineNum = 0
while (($line = $reader.ReadLine()) -ne $null) {
    $lineNum++
    $p = $line -split ';', 7
    if ($p.Count -lt 7) { continue }
    if (-not $ourInns.Contains($p[0].Trim())) { continue }

    # Region is in field 5 (index 5 = activity) - not what we need
    # Field 3 (address) is text. Use the branch_addr field (4) which has region code
    # Actually, FSRAR CSV has: inn;kpp;name;legal_addr;branch_addr;activity;status
    # Region code is not saved separately. Parse from branch_addr.
    $ba = $p[4]
    # Look for common region names
    foreach ($regCode in $regionNames.Keys) {
        $regName = $regionNames[$regCode]
        if ($ba -match [regex]::Escape($regName)) {
            if (-not $fsrarRegionCounts.ContainsKey($regCode)) { $fsrarRegionCounts[$regCode] = 0 }
            $fsrarRegionCounts[$regCode]++
            break
        }
    }
}
$reader.Close()

Write-Host ""
Write-Host "=== Regions where our companies have licenses (from FSRAR) ===" -ForegroundColor Yellow
$report += ""
$report += "--- From FSRAR (branch addresses) ---"
foreach ($kv in ($fsrarRegionCounts.GetEnumerator() | Sort-Object Value -Descending)) {
    $regName = if ($regionNames[$kv.Key]) { $regionNames[$kv.Key] } else { "?" }
    $line = "  $($kv.Key) $regName : $($kv.Value) licenses"
    Write-Host $line
    $report += $line
}

# --- Combine and recommend ---
$allRegions = New-Object System.Collections.Generic.HashSet[string]
foreach ($k in $regionCounts.Keys) { [void]$allRegions.Add($k) }
foreach ($k in $fsrarRegionCounts.Keys) { [void]$allRegions.Add($k) }

Write-Host ""
Write-Host ("=== TOTAL: " + $allRegions.Count + " unique regions ===") -ForegroundColor Green
$report += ""
$report += "--- Recommended regions: $($allRegions.Count) ---"
foreach ($r in ($allRegions | Sort-Object)) {
    $n = if ($regionNames[$r]) { $regionNames[$r] } else { "?" }
    $c1 = if ($regionCounts[$r]) { $regionCounts[$r] } else { 0 }
    $c2 = if ($fsrarRegionCounts[$r]) { $fsrarRegionCounts[$r] } else { 0 }
    $line = "  $r $n  (DaData: $c1, FSRAR: $c2)"
    Write-Host $line
    $report += $line
}

[System.IO.File]::WriteAllLines($outReport, $report, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host ("Report saved: " + $outReport)
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
