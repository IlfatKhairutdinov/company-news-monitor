# Architecture

Technical deep-dive into how Company News Monitor works under the hood.

## Table of Contents

- [Data Flow](#data-flow)
- [Keyword Base Construction](#keyword-base-construction)
- [Streaming XML Parser](#streaming-xml-parser)
- [Regex Matching Engine](#regex-matching-engine)
- [Address Normalization](#address-normalization)
- [Priority-Based Merging](#priority-based-merging)
- [URL Cache and Deduplication](#url-cache-and-deduplication)
- [Design Decisions](#design-decisions)
- [Performance Numbers](#performance-numbers)

---

## Data Flow

```text
[counterparties.xlsx]        ← user input: company name + INN
        │
        ▼
[excel_to_csv.ps1]           ← Excel COM → companies.csv
        │
        ▼
[companies.csv]              ← pipe-delimited: name|inn
        │
        ├──────────────────┬──────────────────┐
        ▼                  ▼                  ▼
[enrich.ps1]        [enrich2.ps1]      [checko.ps1]
(DaData API)        (DaData findAff)   (Checko HTML)
        │                  │                  │
        ▼                  ▼                  ▼
keywords_auto.csv   keywords_checko.csv  keywords_checko_fsrar.csv
(H: 870)            (M: 278)             (L: 1148)
        │                  │                  │
        └──────────────────┴──────────────────┘
                           │
                           ▼
                  [merge_keywords.ps1]
                           │
                           ▼
                  keywords_all.csv  (1959)
                           │
                           ▼
                  [parser.ps1 v9]    ← 19 sources + BezFormata HTML
                           │
                           ▼
              results_high/medium/low.txt
```

---

## Keyword Base Construction

The parser's accuracy depends entirely on keyword quality. We build the base from **three independent sources**:

### 1. DaData — company enrichment (`enrich.ps1`)

For each INN we query DaData's `findById/party`:

- **H-priority**: short and full company name, director's name
- **M-priority**: founders (physical persons and legal entities)

The free tier allows 10,000 requests/day — enough for ~300 companies plus their founders.

### 2. DaData — affiliated parties (`enrich2.ps1`)

Two additional endpoints:

- `findAffiliated/party` — all companies where the director is founder/manager
- `suggest/party` — search by address fragments

Result: **M-priority** keywords for cross-linked companies.

### 3. FSRAR Open Data (`fsrar_parse.ps1`)

The Federal Service for Alcohol Market Regulation publishes a full licensing registry as a **10 GB XML file**. We mine it for:

- Companies with a license at the same address as one of our targets
- Matching KPP (tax registration code) regions

Result: **L-priority** keywords — neighboring companies in shared buildings.

---

## Streaming XML Parser

The FSRAR dump is ~10.5 GB uncompressed. Loading it via `[xml]$content` would consume **~50 GB RAM** and crash on any normal machine.

### Approach: chunked StreamReader

```powershell
$reader = [System.IO.StreamReader]::new($xmlPath, [Text.Encoding]::UTF8, $true, 1048576)
$chunkSize = 8 * 1024 * 1024     # 8 MB of characters
$buffer = New-Object char[] $chunkSize
$pending = ''

while (($read = $reader.Read($buffer, 0, $chunkSize)) -gt 0) {
    $chunk = $pending + [string]::new($buffer, 0, $read)
    $pending = ''
    $parts = $chunk -split '</row>'
    $pending = $parts[-1]        # last incomplete row goes to next iteration
    foreach ($row in $parts[0..($parts.Length - 2)]) {
        # extract fields with pre-compiled Regex
    }
}
```

### Key optimizations

1. **8 MB chunks** — 10× faster than 1 MB, still RAM-safe
2. **`-split '</row>'`** instead of Regex — orders of magnitude faster for simple delimiter split
3. **Pre-compiled Regex** per field, created once before the loop
4. **StreamWriter buffered** output to CSV — never holds more than one row in memory

Result: **1.67M records parsed in 14 minutes**, peak RAM < 200 MB.

---

## Regex Matching Engine

### The naive approach

For 2000 keywords × 500 articles × 20 sources = **20,000,000 `.Contains()` calls** per run. That's several minutes of CPU time.

### Our approach: one compiled regex

```powershell
$patterns = foreach ($kw in $keyData.Values) {
    $esc = [regex]::Escape($kw.word)
    if ($kw.word.Length -le 4) {
        # Short keywords get Cyrillic word boundaries
        "(?<![А-Яа-яЁёA-Za-z0-9])$esc(?![А-Яа-яЁёA-Za-z0-9])"
    } else {
        $esc
    }
}
$kwRegex = [regex]::new(($patterns -join '|'), 'IgnoreCase')
```

Then per article:

```powershell
foreach ($m in $kwRegex.Matches($fullText)) {
    $matched = $m.Value.ToLower()
    # ...
}
```

### Why this is faster

| Aspect | `.Contains()` loop | Compiled Regex |
|---|---|---|
| Regex objects created | 2000 per article | 1 per run |
| Engine | Interpreted, PowerShell-level | Compiled .NET, C-level |
| Case handling | Manual `.ToLower()` per check | `RegexOptions.IgnoreCase` |
| Throughput | ~50k checks/sec | ~2M checks/sec |

**~40× speedup** measured on real data.

### Word boundaries for short keywords

Short keywords (`ГАЗ`, `Юта`, `Спар`) would match substrings (`газировка`, `юта_что_то`, `спартакиада`). We wrap them in negative lookarounds:

```regex
(?<![А-Яа-яЁёA-Za-z0-9])ГАЗ(?![А-Яа-яЁёA-Za-z0-9])
```

This ensures the keyword is a **standalone token** — surrounded by non-word characters (spaces, punctuation, digits if not part of another word).

---

## Address Normalization

Russian addresses in government data and DaData vary wildly:

| Source | Address |
|---|---|
| DaData | `г Москва, ул Дзержинского, д 1, офис 4` |
| FSRAR | `РОССИЯ,,СВЕРДЛОВСКАЯ ОБЛ,, Верхняя Пышма г,, Калинина ул, д. 39` |
| СМИ | `Москва, улица Дзержинского, дом 1` |

### Normalization pipeline

```powershell
function Extract-AddressKey {
    param([string]$addr)
    $a = $addr.ToLower() -replace 'ё', 'е'
    $a = $a -replace 'г\.', ' г ' -replace 'ул\.', ' ул ' -replace 'д\.', ' д '
    $a = $a -replace '[^а-я0-9]+', ' '
    $tokens = $a -split '\s+' | Where-Object { $_ -ne '' }

    $city = ''; $street = ''; $house = ''
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -eq 'г' -and $i+1 -lt $tokens.Count) { $city = $tokens[$i+1]; $i++; continue }
        if ($tokens[$i] -eq 'ул' -and $i+1 -lt $tokens.Count) { $street = $tokens[$i+1]; $i++; continue }
        if ($tokens[$i] -eq 'д' -and $i+1 -lt $tokens.Count) { $house = $tokens[$i+1]; $i++; continue }
    }
    if ($city -and $street) { return "$city|$street|$house" }
    return ''
}
```

Result: `москва|дзержинского|1` for all three variants above.

### Matching

Two addresses are considered **the same building** if their normalized keys match on **city + street** (house number optional, because different databases use different formats for the same physical location).

---

## Priority-Based Merging

The same person might be a **founder** (M) of one company and a **director** (H) of another. When merging keyword sources, we keep the **highest priority**:

```powershell
if ($prioRank[$newPrio] -gt $prioRank[$existing.prio]) {
    $existing.prio = $newPrio
}
```

Priority ranking: `H = 3, M = 2, L = 1`.

### Why

- A director name in **H** gets into `results_high.txt` — the report users actually read.
- Same name in **M** would go to `results_medium.txt` — lower visibility.
- Duplicates across sources are removed by lowercase key.

Real-world result: 870 H + 278 M + 1148 L = **1448 unique keywords** (not 2296 — because of cross-source overlaps).

---

## URL Cache and Deduplication

News feeds re-publish the same articles across days. Without caching, the user sees the same headline 5–10 times.

### Solution: persistent URL set

```powershell
$seenUrlsFile = Join-Path $ProjectRoot "_data\seen_urls.txt"
$seenUrls = New-Object System.Collections.Generic.HashSet[string]
Get-Content $seenUrlsFile -Encoding UTF8 | ForEach-Object {
    [void]$seenUrls.Add($_.Trim())
}
```

During parsing:

```powershell
$key = if ($link) { $link } else { "$sourceName|$title" }
if ($seenUrls.Contains($key)) { continue }
[void]$seenUrls.Add($key)
```

At the end:

```powershell
$toKeep = @($seenUrls | Select-Object -Last 50000)
[System.IO.File]::WriteAllLines($seenUrlsFile, [string[]]$toKeep, $enc)
```

### Size management

- Cap at 50,000 entries — enough for ~6 months of daily runs
- Old URLs gracefully "expire" from the top
- Removed articles can reappear if absolutely necessary, but this is rare

---

## Design Decisions

### Why PowerShell instead of Python?

- **Zero install** on locked-down corporate Windows — PowerShell 5.1 ships with the OS
- **Native Excel COM** — no `openpyxl`/`pandas` dependency
- **Native XML/Regex/HTTP** — no `pip install requests lxml beautifulsoup4`
- **Scheduled Tasks friendly** — one command to register a daily job
- **No admin rights** for installation

Trade-off: single-threaded by default, cryptic error messages. Both mitigable.

### Why not an existing monitoring service?

Commercial services (Brand Analytics, Медиалогия, YouScan) charge **50,000–500,000 ₽/year** for similar coverage. This tool:

- Runs on free DaData tier
- Uses public FSRAR Open Data
- Respects source ToS (RSS is a published interface)
- **Total cost: 0 ₽**

Limitation: manual captcha solving for Yandex News; no sentiment analysis; no historical archive beyond what sources expose via RSS.

### Why single-compiled regex instead of Aho-Corasick?

Aho-Corasick would be faster still (~10× over compiled regex), but:

- Not available in PowerShell standard library
- Would require a .NET assembly or P/Invoke
- Current speed (40× over naive loops) is enough for 2000 keywords × 500 articles

If the keyword base grows to 20,000+, Aho-Corasick becomes worth the complexity.

---

## Performance Numbers

Measured on a real dataset (298 companies, 1448 keywords, 19 sources):

| Stage | Time | Peak RAM |
|---|---|---|
| `excel_to_csv.ps1` | 3 sec | 30 MB |
| `enrich.ps1` (298 INNs, cache cold) | 8 min | 80 MB |
| `enrich.ps1` (cache warm) | 15 sec | 80 MB |
| `enrich2.ps1` | 12 min | 120 MB |
| `fsrar_opendata.ps1` (300 MB download) | 4 min | 20 MB |
| `fsrar_unpack.ps1` | 2 min | 150 MB |
| `fsrar_parse.ps1` (10 GB XML → 790 MB CSV) | 14 min | 200 MB |
| `fsrar_match.ps1` (2 passes over 790 MB) | 8 min | 180 MB |
| `merge_keywords.ps1` | 2 sec | 40 MB |
| `parser.ps1` (19 sources, 500 articles) | 45 sec | 90 MB |
| **Full cold run** | **~50 min** | **< 250 MB** |
| **Daily run (cache warm)** | **~60 sec** | **< 100 MB** |

Disk usage:
- `_fsrar\fsrar_extracted\` — 10.5 GB (uncompressed XML)
- `_fsrar\fsrar_all.csv` — 790 MB
- `_data\` — total ~15 MB
- `_results\` — ~500 KB

---

## Possible Future Optimizations

1. **Parallel source fetching** via `RunspacePool` — 19 sources in 3 sec instead of 45
2. **SQLite URL cache** — replaces text file, handles millions of entries
3. **Aho-Corasick matching** — for keyword bases > 10,000
4. **Incremental FSRAR updates** — server provides daily diffs, we currently re-download all
5. **Web UI** — Flask/FastAPI on top of `results.csv`