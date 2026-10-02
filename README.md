# Company News Monitor

> PowerShell-based OSINT system for monitoring mentions of companies, their executives and business addresses across Russian news sources.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

The system solves a specific business problem: **automatic tracking of any public mention of a given list of companies** (name + INN) in Russian media, including regional outlets that are not indexed by Google News.

Unlike typical RSS aggregators, it combines **six independent data sources** to build a comprehensive keyword base and then searches news feeds for matches.

## Key Features

| Feature | Description |
|---|---|
| **Multi-source keyword building** | Auto-extracts company names, directors, addresses, and affiliated companies |
| **DaData API integration** | Enriches 300 companies → 870+ high-priority keywords |
| **FSRAR open data mining** | Parses a 10 GB XML dump (1.7M records) to find address-based neighbors |
| **19 RSS sources + HTML scraping** | Federal (TASS, Kommersant, Vedomosti) and regional (NN News, BezFormata) |
| **Regex-optimized matching** | Single compiled regex for 2000+ keywords, 10–50× faster than naive loops |
| **Priority-based filtering** | H/M/L classification separates signal from noise |
| **Deduplication & caching** | News shown only once, URL cache between runs |
| **UTF-8 safe** | Full Cyrillic support in scripts, configs and outputs |

## Tech Stack

- **PowerShell 5.1** — core language
- **DaData API** — company data enrichment (free tier: 10K req/day)
- **FSRAR Open Data** — government alcohol/tobacco licensing registry
- **Selenium WebDriver** — browser automation for JS-heavy pages
- **Excel COM** — reading source spreadsheets
- **StreamReader / Regex** — streaming XML parsing of 10 GB dumps
- **Yandex/Google News RSS** — keyword-based search

## Architecture

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ counterparties   │    │  DaData API      │    │  FSRAR Open      │
│ (xlsx: name+INN) │───▶│  enrich          │───▶│  Data (10 GB XML)│
└──────────────────┘    └──────────────────┘    └──────────────────┘
         │                       │                       │
         │                       ▼                       ▼
         │              ┌──────────────────┐    ┌──────────────────┐
         │              │ keywords_auto    │    │ keywords_fsrar   │
         │              │ (870 H)          │    │ (1148 L)         │
         │              └──────────────────┘    └──────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                  MERGE → keywords_all.csv (1959)                 │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │  News Parser (v9)      │
                    │  19 RSS + HTML + API   │
                    │  Compiled regex match  │
                    └────────────────────────┘
                                 │
                ┌────────────────┼────────────────┐
                ▼                ▼                ▼
        results_high.txt  results_medium.txt  results_low.txt
```

## Getting Started

### Prerequisites

- Windows 10/11
- PowerShell 5.1 (built-in)
- Microsoft Excel (for source xlsx)
- DaData API key (free) → https://dadata.ru/api/
- Chrome + ChromeDriver (only for `ОБНОВИТЬ_ФСРАР.bat`)

### Installation

1. Clone the repository:
   ```powershell
   git clone https://github.com/IlfatKhairutdinov/company-news-monitor.git
   cd company-news-monitor
   ```

2. Create `_bin\secrets.ps1`:
   ```powershell
   $dadataKey = "YOUR_DADATA_API_KEY_HERE"
   ```

3. Prepare `_config\counterparties.xlsx` with two columns: `Наименование`, `ИНН`.

4. Configure keywords in `_config\keywords_manual.txt` (optional).

### Usage

```powershell
# First run: build keyword base (5–10 min)
.\НАСТРОЙКА.bat

# Daily: parse news and write reports
.\ЗАПУСТИТЬ.bat

# Monthly: refresh FSRAR data
.\ОБНОВИТЬ_ФСРАР.bat
```

Output: `_results\results_high.txt`, `results_medium.txt`, `results_low.txt`, `results.csv`.

## Project Structure

```
.
├── README.md
├── LICENSE
├── .gitignore
├── ЗАПУСТИТЬ.bat             # daily runner
├── НАСТРОЙКА.bat             # rebuild keywords
├── ОБНОВИТЬ_ФСРАР.bat        # refresh gov data
├── _bin/                     # scripts
│   ├── paths.ps1             # all paths in one place
│   ├── secrets.ps1           # API key (gitignored)
│   ├── parser.ps1            # main parser
│   ├── enrich.ps1            # DaData enrichment
│   ├── fsrar_parse.ps1       # streaming XML parser
│   └── ...
├── _config/                  # user input (gitignored)
│   ├── counterparties.xlsx
│   └── keywords_manual.txt
├── _data/                    # intermediate data (gitignored)
├── _fsrar/                   # gov data (gitignored)
├── _results/                 # outputs (gitignored)
└── _tech/                    # dev artifacts (gitignored)
```

## Known Limitations

- **Windows-only**: uses Excel COM and `Read-Host` for interactive prompts.
- **Single-threaded**: 19 sources processed sequentially; parallelization is on the roadmap.
- **FSRAR XML is 10 GB uncompressed**: requires ~12 GB free disk space.
- **Yandex News** may require captcha solving → disabled by default.

## Roadmap

- [ ] Parallel source processing via Runspace Pools
- [ ] SQLite backend for URL cache (replace plain text file)
- [ ] Docker container for portable deployment
- [ ] Web UI on top of `results.csv`
- [ ] Telegram bot notifications for high-priority matches

## License

MIT — see [LICENSE](LICENSE)

## Contact

**Ilfat Khairutdinov** — [GitHub](https://github.com/IlfatKhairutdinov)
