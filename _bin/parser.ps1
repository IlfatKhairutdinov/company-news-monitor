# parser.ps1 v9 - final
# Regex matching, priorities, cache, Yandex News
# SAVE AS UTF-8 WITH BOM (Russian chars in regex)


# ============================================================
# SETTINGS
# ============================================================

# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

$maxAgeDays         = 7
$httpTimeoutSec     = 40
$enableYandexNews   = $false   # <-- было $true
$yandexDelayMs      = 5000
$yandexTopN         = 20

# ============================================================
# TLS
# ============================================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor `
    [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

# ============================================================
# PATHS
# ============================================================

# ============================================================
# LOAD KEYWORDS
# ============================================================
if (-not (Test-Path $keywordsFile)) {
    Write-Host "ERROR: $keywordsFile not found. Run RUN_MERGE.bat first." -ForegroundColor Red
    Read-Host "Press Enter to exit"; exit 1
}

$keywordLines = Get-Content $keywordsFile -Encoding UTF8
if ($keywordLines.Count -gt 0) {
    $keywordLines[0] = $keywordLines[0].TrimStart([char]0xFEFF)
}

$keyData = @{}
$hKeys = New-Object System.Collections.Generic.List[string]
$mKeys = New-Object System.Collections.Generic.List[string]
$lKeys = New-Object System.Collections.Generic.List[string]

foreach ($line in $keywordLines) {
    if (-not $line) { continue }
    $line = $line.Trim()
    if (-not $line) { continue }
    $m = [regex]::Match($line, '^([HML]),(.+)$')
    if (-not $m.Success) { continue }
    $prio = $m.Groups[1].Value
    $word = $m.Groups[2].Value.Trim()
    if (-not $word) { continue }
    $lower = $word.ToLower()
    if ($keyData.ContainsKey($lower)) { continue }
    $keyData[$lower] = @{ word = $word; prio = $prio }
    if ($prio -eq 'H') { $hKeys.Add($word) }
    elseif ($prio -eq 'M') { $mKeys.Add($word) }
    else { $lKeys.Add($word) }
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "           NEWS PARSER v9" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ("Keywords:  H=" + $hKeys.Count + "  M=" + $mKeys.Count + "  L=" + $lKeys.Count)
Write-Host ("Filter:    last " + $maxAgeDays + " day(s)")
Write-Host ("Yandex:    " + $(if ($enableYandexNews) { "ON (top $yandexTopN)" } else { "OFF" }))
Write-Host ""

# ============================================================
# BUILD REGEX
# ============================================================
function Escape-KeywordRegex {
    param([string]$w)
    $esc = [regex]::Escape($w)
    # Short keywords (<=4 chars) - use cyrillic word boundaries
    if ($w.Length -le 8) {
    	return "(?<![А-Яа-яЁёA-Za-z0-9])$esc(?![А-Яа-яЁёA-Za-z0-9])"
    }
    return $esc
}

$patterns = @()
foreach ($kv in $keyData.Values) {
    $patterns += Escape-KeywordRegex $kv.word
}
$patternStr = ($patterns -join '|')

try {
    $kwRegex = [regex]::new($patternStr, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    Write-Host ("Regex compiled: pattern length " + $patternStr.Length + " chars") -ForegroundColor Green
} catch {
    Write-Host ("ERROR compiling regex: " + $_.Exception.Message) -ForegroundColor Red
    Read-Host "Press Enter to exit"; exit 1
}

function Find-MatchedKeys {
    param([string]$text)
    if (-not $text) { return @() }
    $seen = @{}
    foreach ($m in $kwRegex.Matches($text)) {
        $matched = $m.Value.ToLower()
        if ($keyData.ContainsKey($matched)) {
            $seen[$matched] = $keyData[$matched]
        }
    }
    return @($seen.Values)
}

# ============================================================
# LOAD SEEN URLS CACHE
# ============================================================
$seenUrls = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $seenUrlsFile) {
    Get-Content $seenUrlsFile -Encoding UTF8 | ForEach-Object {
        $u = $_.Trim()
        if ($u) { [void]$seenUrls.Add($u) }
    }
    Write-Host ("Cache loaded: " + $seenUrls.Count + " URLs seen before") -ForegroundColor DarkGray
}

$cutoff = (Get-Date).AddDays(-$maxAgeDays)

# ============================================================
# HELPERS
# ============================================================
function ConvertTo-XmlDocument {
    param($response)
    $bytes = $null
    try { $bytes = $response.RawContentStream.ToArray() } catch { }
    if (-not $bytes -or $bytes.Length -eq 0) { return $null }
    $enc = $null
    $headLen = [Math]::Min(200, $bytes.Length)
    $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $headLen)
    if ($head -match 'encoding\s*=\s*["'']([^"'']+)["'']') {
        try { $enc = [System.Text.Encoding]::GetEncoding($matches[1]) } catch { }
    }
    if (-not $enc) { $enc = [System.Text.Encoding]::UTF8 }
    $text = $enc.GetString($bytes).TrimStart([char]0xFEFF)
    $trimmed = $text.TrimStart()
    if (-not $trimmed.StartsWith("<?xml") -and -not $trimmed.StartsWith("<rss") -and
        -not $trimmed.StartsWith("<feed") -and -not $trimmed.StartsWith("<rdf")) {
        return $null
    }
    try { return [xml]$text } catch { return $null }
}

function Get-NodeText {
    param($node)
    if ($null -eq $node) { return "" }
    if ($node -is [string]) { return $node }
    if ($node -is [System.Array]) {
        if ($node.Count -gt 0) { return (Get-NodeText $node[0]) }
        return ""
    }
    try { if ($node.InnerText) { return $node.InnerText } } catch { }
    return [string]$node
}

function Get-ItemLink {
    param($item)
    if ($null -eq $item.link) { return "" }
    $links = @($item.link)
    foreach ($l in $links) {
        if ($l -is [System.Xml.XmlElement] -and $l.HasAttribute("href")) {
            $rel = $l.GetAttribute("rel")
            if (-not $rel -or $rel -eq "alternate") { return $l.GetAttribute("href") }
        }
    }
    foreach ($l in $links) {
        if ($l -is [System.Xml.XmlElement] -and $l.InnerText) { return $l.InnerText }
        if ($l -is [string] -and $l) { return $l }
    }
    return ""
}

function Make-AbsoluteUrl {
    param([string]$Link, [string]$BaseUrl)
    if (-not $Link) { return "" }
    $Link = $Link.Trim()
    if ($Link -match '^https?://') { return $Link }
    if ($Link -match '^//') { return "https:$Link" }
    try {
        $base = [System.Uri]$BaseUrl
        return ([System.Uri]::new($base, $Link)).AbsoluteUri
    } catch { return $Link }
}

function Parse-RssDate {
    param([string]$s)
    if (-not $s) { return $null }
    $s = $s.Trim()
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor `
              [System.Globalization.DateTimeStyles]::AdjustToUniversal
    try { return [DateTime]::Parse($s, $inv, $styles).ToLocalTime() } catch { }
    try { return [DateTime]::Parse($s, $inv) } catch { }
    return $null
}

# ============================================================
# BEZFORMATA HTML
# ============================================================
function Get-BezformataNews {
    param([string]$Url)
    $out = @()
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $httpTimeoutSec `
            -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36" `
            -Headers @{
                "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                "Accept-Language" = "ru-RU,ru;q=0.9,en;q=0.8"
            } -ErrorAction Stop
        $html = $resp.Content
        # [System.IO.File]::WriteAllText($debugPath, $html, [System.Text.Encoding]::UTF8)
        $sl = [System.Text.RegularExpressions.RegexOptions]::Singleline
        $articleRe = [regex]::new('<article[^>]*class="(?:hottopicline|newtopicline)"[^>]*>(?<body>.*?)</article>', $sl)
        foreach ($am in $articleRe.Matches($html)) {
            $body = $am.Groups['body'].Value
            $urlM = [regex]::Match($body, 'href="(?<u>https?://[^"]+bezformata\.com/listnews/[^"]+)"')
            if (-not $urlM.Success) { continue }
            $titleM = [regex]::Match($body, 'itemprop="headline"[^>]*>(?<t>[^<]+)<')
            if (-not $titleM.Success) { continue }
            $title = [System.Net.WebUtility]::HtmlDecode($titleM.Groups['t'].Value.Trim())
            $dateM = [regex]::Match($body, 'itemprop="datePublished"\s+content="(?<d>[^"]+)"')
            $dateRaw = if ($dateM.Success) { $dateM.Groups['d'].Value } else { "" }
            $descM = [regex]::Match($body, '<div class="(?:hottopicannouncebox|newannouncebox)"[^>]*>(?<d>.*?)</div>', $sl)
            $desc = ""
            if ($descM.Success) {
                $desc = [regex]::Replace($descM.Groups['d'].Value, '<[^>]+>', ' ')
                $desc = [System.Net.WebUtility]::HtmlDecode($desc)
                $desc = [regex]::Replace($desc, '\s+', ' ').Trim()
            }
            $out += [PSCustomObject]@{
                Title = $title; Link = $urlM.Groups['u'].Value
                Description = $desc; DateRaw = $dateRaw; DateObj = Parse-RssDate $dateRaw
            }
        }
    } catch { Write-Host ("  BezFormata error: " + $_.Exception.Message) -ForegroundColor Red }
    return $out
}

# ============================================================
# RSS SOURCES
# ============================================================
$sources = @(
    @{ Name = "NN News";              Url = "https://nnews.nnov.ru/rss" },
    @{ Name = "NNTV";                 Url = "https://nntv.tv/rss" },
    @{ Name = "Habr IT";              Url = "https://habr.com/ru/rss/news/?fl=ru" },
    @{ Name = "Lenta.ru";             Url = "https://lenta.ru/rss/news" },
    @{ Name = "TASS";                 Url = "https://tass.ru/rss/v2.xml" },
    @{ Name = "Vedomosti";            Url = "https://www.vedomosti.ru/rss/news" },
    @{ Name = "Kommersant (news)";    Url = "https://www.kommersant.ru/RSS/news.xml" },
    @{ Name = "Kommersant (main)";    Url = "https://www.kommersant.ru/RSS/main.xml" },
    @{ Name = "Ria.ru";               Url = "https://ria.ru/export/rss2/index.xml" },
    @{ Name = "Gazeta.ru";            Url = "https://www.gazeta.ru/export/rss/first.xml" },
    @{ Name = "Interfax";             Url = "https://www.interfax.ru/rss.asp" },
    @{ Name = "RT";                   Url = "https://russian.rt.com/rss" },
    @{ Name = "CNews";                Url = "https://www.cnews.ru/inc/rss/news.xml" },
    @{ Name = "Российская Газета";    Url = "https://rg.ru/xml/index.xml" },
    @{ Name = "PravdaReport";         Url = "https://www.pravdareport.com/export.xml" },
    @{ Name = "Московский Комсомолец";Url = "https://www.mk.ru/rss/index.xml" },
    @{ Name = "NEWSru.com";           Url = "https://rss.newsru.com/top/big/" },
    @{ Name = "Life.ru";              Url = "https://life.ru/rss" },
        # --- Добавлено 2026-10-07: источники из Контур.Фокуса ---
    @{ Name = "Retail.ru";           Url = "https://www.retail.ru/rss/news/" },
    @{ Name = "New Retail";          Url = "https://new-retail.ru/rss/" },
    @{ Name = "Retailer.ru";         Url = "https://retailer.ru/feed/" },
    @{ Name = "Финмаркет";           Url = "https://www.finmarket.ru/rss/news.asp" },
    @{ Name = "Москвич Mag";         Url = "https://moskvichmag.ru/feed/" },
    @{ Name = "МК Экономика";        Url = "https://www.mk.ru/rss/economics/index.xml" },
    @{ Name = "МК Происшествия";     Url = "https://www.mk.ru/rss/incident/index.xml" },
    @{ Name = "МК Общество";         Url = "https://www.mk.ru/rss/social/index.xml" },
    @{ Name = "URBC.Ru";             Url = "https://urbc.ru/rss.xml" },
    @{ Name = "МК Спорт";            Url = "https://www.mk.ru/rss/sport/index.xml" },
    @{ Name = "МК Культура";         Url = "https://www.mk.ru/rss/culture/index.xml" }
)

# ============================================================
# PARSE
# ============================================================
$allResults = New-Object System.Collections.Generic.List[object]
$logLines = @()
$okCount = 0
$failCount = 0
$totalFound = 0
$skippedByDate = 0
$skippedAsDup = 0

function Add-FoundResult {
    param($title, $link, $sourceName, $dateObj, $dateRaw, $desc)
    $script:totalFound++
    $fullText = "$title $desc"
    $matched = Find-MatchedKeys $fullText
    if ($matched.Count -eq 0) { return $false }

    # Dedup by URL
    $key = if ($link) { $link } else { "$sourceName|$title" }
    if ($seenUrls.Contains($key)) {
        $script:skippedAsDup++
        return $false
    }
    [void]$seenUrls.Add($key)

    # Highest priority among matched
    $bestPrio = 'L'
    foreach ($mk in $matched) {
        if ($mk.prio -eq 'H') { $bestPrio = 'H'; break }
        if ($mk.prio -eq 'M' -and $bestPrio -ne 'H') { $bestPrio = 'M' }
    }

    $matchedStr = ($matched | Sort-Object { $_.prio }, { $_.word } | ForEach-Object { "[$($_.prio)] $($_.word)" }) -join "; "

    $script:allResults.Add([PSCustomObject]@{
        Source = $sourceName
        Title = $title
        Link = $link
        Date = if ($dateObj) { $dateObj } else { $null }
        DateRaw = $dateRaw
        Priority = $bestPrio
        Matched = $matchedStr
    })
    return $true
}

# --- RSS ---
foreach ($source in $sources) {
    Write-Host ("[" + $source.Name + "] " + $source.Url)
    try {
        $response = Invoke-WebRequest -Uri $source.Url -UseBasicParsing -TimeoutSec $httpTimeoutSec `
            -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) NewsParser/9.0" -ErrorAction Stop
        $xml = ConvertTo-XmlDocument $response
        if ($null -eq $xml) {
            Write-Host "  SKIP: not RSS/XML" -ForegroundColor DarkYellow
            $failCount++
            $logLines += "FAIL|$($source.Name)|$($source.Url)|not XML"
            continue
        }
        $items = @()
        if ($xml.rss -and $xml.rss.channel -and $xml.rss.channel.item) { $items = @($xml.rss.channel.item) }
        elseif ($xml.feed -and $xml.feed.entry) { $items = @($xml.feed.entry) }
        elseif ($xml.'rdf:RDF' -and $xml.'rdf:RDF'.item) { $items = @($xml.'rdf:RDF'.item) }

        $found = 0
        foreach ($item in $items) {
            $title = Get-NodeText $item.title
            $link  = Make-AbsoluteUrl (Get-ItemLink $item) $source.Url
            $desc  = Get-NodeText $item.description
            if (-not $desc) { $desc = Get-NodeText $item.summary }
            try {
                $ce = Get-NodeText $item.'content:encoded'
                if ($ce) { $desc = "$desc $ce" }
            } catch { }
            $dateRaw = Get-NodeText $item.pubDate
            if (-not $dateRaw) { $dateRaw = Get-NodeText $item.published }
            if (-not $dateRaw) { $dateRaw = Get-NodeText $item.updated }
            $dateObj = Parse-RssDate $dateRaw
            if ($dateObj -and $dateObj -lt $cutoff) { $skippedByDate++; continue }

            if (Add-FoundResult $title $link $source.Name $dateObj $dateRaw $desc) { $found++ }
        }
        Write-Host ("  found: " + $found) -ForegroundColor $(if ($found -gt 0) { "Yellow" } else { "DarkGray" })
        $okCount++
        $logLines += "OK|$($source.Name)|$($source.Url)|found=$found"
    } catch {
        Write-Host ("  ERROR: " + $_.Exception.Message) -ForegroundColor Red
        $failCount++
        $logLines += "FAIL|$($source.Name)|$($source.Url)|$($_.Exception.Message)"
    }
}

# --- BezFormata регионы (HTML) ---
$bezRegions = @(
    @{ Name = "Нижний Новгород";  Slug = "nnovgorod" },
    @{ Name = "Москва";           Slug = "moskva" },
    @{ Name = "Санкт-Петербург";  Slug = "sanktpeterburg" },
    @{ Name = "Екатеринбург";     Slug = "ekaterinburg" },
    @{ Name = "Казань";           Slug = "kazan" },
    @{ Name = "Красноярск";       Slug = "krasnoyarsk" },
    @{ Name = "Новосибирск";      Slug = "novosibirsk" },
    @{ Name = "Омск";             Slug = "omsk" },
    @{ Name = "Самара";           Slug = "samara" },
    @{ Name = "Улан-Удэ";         Slug = "ulanude" },
    @{ Name = "Краснодар";        Slug = "krasnodar" },
    @{ Name = "Хабаровск";        Slug = "habarovsk" }
)

Write-Host ""
Write-Host ("[BezFormata: " + $bezRegions.Count + " регионов]") -ForegroundColor Magenta

foreach ($region in $bezRegions) {
    $url = "https://$($region.Slug).bezformata.com/listnews/"
    Write-Host ("  [" + $region.Name + "] ") -NoNewline

    try {
        $bez = Get-BezformataNews $url
        $found = 0
        foreach ($item in $bez) {
            if ($item.DateObj -and $item.DateObj -lt $cutoff) { $skippedByDate++; continue }
            if (Add-FoundResult $item.Title $item.Link ("BezFormata " + $region.Name) $item.DateObj $item.DateRaw $item.Description) {
                $found++
            }
        }
        if ($found -gt 0) {
            Write-Host ("FOUND: " + $found) -ForegroundColor Yellow
        } else {
            Write-Host "no matches" -ForegroundColor DarkGray
        }
        $okCount++
        $logLines += "OK  |BezFormata $($region.Name)|$url|found=$found"
    } catch {
        $msg = $_.Exception.Message
        if ($msg.Length -gt 50) { $msg = $msg.Substring(0, 50) + "..." }
        Write-Host ("ERROR: " + $msg) -ForegroundColor Red
        $failCount++
        $logLines += "FAIL|BezFormata $($region.Name)|$url|$msg"
    }

    # Пауза между регионами, чтобы не получить rate limit
    Start-Sleep -Milliseconds 1500
}

# --- Yandex News RSS ---
if ($enableYandexNews) {
    Write-Host ""
    Write-Host "[Yandex News RSS]" -ForegroundColor Magenta

    $yandexKeys = @()
    if (Test-Path $yandexKwFile) {
        $yandexKeys = Get-Content $yandexKwFile -Encoding UTF8 | ForEach-Object {
            $_.Trim().TrimStart([char]0xFEFF)
        } | Where-Object { $_ -and -not $_.StartsWith("#") }
    }
    if ($yandexKeys.Count -eq 0) {
        $yandexKeys = $hKeys | Select-Object -First $yandexTopN
    } else {
        $yandexKeys = $yandexKeys | Select-Object -First $yandexTopN
    }

    Write-Host ("  Using " + $yandexKeys.Count + " keywords")

    $yOk = 0
    $yFail = 0
    $yFound = 0

    foreach ($kw in $yandexKeys) {
        $enc = [System.Uri]::EscapeDataString($kw)
        $url = "https://news.yandex.ru/yandsearch?text=$enc&rpt=nnews2&format=rss"
        Write-Host ("  Yandex: " + $kw) -NoNewline
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $httpTimeoutSec `
                -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36" `
                -ErrorAction Stop
            $xml = ConvertTo-XmlDocument $resp
            if ($null -eq $xml) {
                Write-Host " -> HTML (probably captcha)" -ForegroundColor DarkYellow
                $yFail++
                Start-Sleep -Milliseconds $yandexDelayMs
                continue
            }
            $items = @()
            if ($xml.rss -and $xml.rss.channel -and $xml.rss.channel.item) { $items = @($xml.rss.channel.item) }
            foreach ($item in $items) {
                $title = Get-NodeText $item.title
                $link = Make-AbsoluteUrl (Get-ItemLink $item) $url
                $desc = Get-NodeText $item.description
                $dateRaw = Get-NodeText $item.pubDate
                $dateObj = Parse-RssDate $dateRaw
                if ($dateObj -and $dateObj -lt $cutoff) { continue }
                if (Add-FoundResult $title $link "Yandex News" $dateObj $dateRaw $desc) { $yFound++ }
            }
            Write-Host (" -> " + $items.Count + " items") -ForegroundColor DarkGray
            $yOk++
        } catch {
            Write-Host (" -> ERROR: " + $_.Exception.Message) -ForegroundColor Red
            $yFail++
        }
        Start-Sleep -Milliseconds $yandexDelayMs
    }

    Write-Host ("  Yandex: OK=$yOk  FAIL=$yFail  found=$yFound") -ForegroundColor Cyan
    $logLines += "INFO|Yandex News|OK=$yOk FAIL=$yFail found=$yFound"
}

# ============================================================
# SAVE RESULTS
# ============================================================
function Format-Result {
    param($r)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("===========================================")
    [void]$sb.AppendLine("Source:    $($r.Source)")
    [void]$sb.AppendLine("Title:     $($r.Title)")
    [void]$sb.AppendLine("Link:      $($r.Link)")
    if ($r.Date) { [void]$sb.AppendLine("Date:      $($r.Date.ToString('yyyy-MM-dd HH:mm'))") }
    [void]$sb.AppendLine("Priority:  $($r.Priority)")
    [void]$sb.AppendLine("Matched:   $($r.Matched)")
    [void]$sb.AppendLine("")
    return $sb.ToString()
}

$h = $allResults | Where-Object { $_.Priority -eq 'H' }
$m = $allResults | Where-Object { $_.Priority -eq 'M' }
$l = $allResults | Where-Object { $_.Priority -eq 'L' }

$header = @(
    "===========================================",
    "  NEWS PARSER v9 - $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
    "  Keywords: H=$($hKeys.Count) M=$($mKeys.Count) L=$($lKeys.Count)",
    "  Filter: last $maxAgeDays days",
    "  Sources OK: $okCount, Failed: $failCount",
    "  Found total: $($allResults.Count)  (H:$($h.Count) M:$($m.Count) L:$($l.Count))",
    "  Skipped by date: $skippedByDate",
    "  Skipped as dup: $skippedAsDup",
    "===========================================",
    ""
) -join "`n"

$enc = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($resultsHigh, $header + (($h | ForEach-Object { Format-Result $_ }) -join "`n"), $enc)
[System.IO.File]::WriteAllText($resultsMed,  $header + (($m | ForEach-Object { Format-Result $_ }) -join "`n"), $enc)
[System.IO.File]::WriteAllText($resultsLow,  $header + (($l | ForEach-Object { Format-Result $_ }) -join "`n"), $enc)
[System.IO.File]::WriteAllText($resultsAll,  $header + (($allResults | Sort-Object Priority, { $_ | ConvertTo-Json } | ForEach-Object { Format-Result $_ }) -join "`n"), $enc)

if ($allResults.Count -gt 0) {
    $csv = $allResults | Sort-Object Priority | Select-Object Source, Priority, Title, Link, @{n='Date';e={ if ($_.Date) { $_.Date.ToString('yyyy-MM-dd HH:mm') } else { '' } }}, Matched
    $csv | Export-Csv -Path $resultsCsv -NoTypeInformation -Encoding UTF8
}

# Save seen urls (max 50000)
$toKeep = @($seenUrls | Select-Object -Last 50000)
if ($toKeep.Count -eq 0) { $toKeep = @() }
[System.IO.File]::WriteAllLines($seenUrlsFile, [string[]]$toKeep, $enc)

# Save log
$logHeader = @("SOURCES LOG - $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", "") + $logLines
[System.IO.File]::WriteAllLines($logFile, $logHeader, $enc)

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  FOUND:        " + $allResults.Count)
Write-Host ("    HIGH:       " + $h.Count)
Write-Host ("    MEDIUM:     " + $m.Count)
Write-Host ("    LOW:        " + $l.Count)
Write-Host ("  Sources OK:   " + $okCount)
Write-Host ("  Sources FAIL: " + $failCount)
Write-Host ("  Skipped date: " + $skippedByDate)
Write-Host ("  Skipped dup:  " + $skippedAsDup)
Write-Host ""
Write-Host ("  results_high.txt    " + $resultsHigh)
Write-Host ("  results_medium.txt  " + $resultsMed)
Write-Host ("  results_low.txt     " + $resultsLow)
Write-Host ("  results.csv         " + $resultsCsv)
Write-Host "===========================================" -ForegroundColor Green
Read-Host "Press Enter to exit"
