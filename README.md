# Company News Monitor

> PowerShell-based OSINT system for monitoring mentions of companies, their executives, and business addresses across Russian news sources.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows)](https://microsoft.com/windows)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Made with](https://img.shields.io/badge/made%20with-%E2%9D%A4-red)]()

---

## The Problem

Manually tracking news mentions of a portfolio of 300+ companies across **federal** and **regional** Russian media is impossible. Google Alerts misses regional outlets (many of them don't have RSS at all), and commercial monitoring services charge per query.

This project solves it with a **fully local, zero-cost pipeline** built on open data and free APIs.

## What It Does

1. **Builds a keyword base** automatically from a list of companies (name + INN):
   - Fetches company data via [DaData API](https://dadata.ru/) — directors, addresses, OKVED
   - Mines [FSRAR Open Data](https://fsrar.gov.ru/opendata) — government alcohol/tobacco licensing registry (10 GB XML, 1.7M records)
   - Finds related companies by shared directors and addresses

2. **Monitors 19+ news sources** — federal (TASS, Kommersant, Vedomosti, RBC) and regional (NN News, BezFormata)

3. **Matches with compiled regex** — 2000+ keywords in a single pass, ~50× faster than naive loops

4. **Outputs three filtered reports** by priority:
   - `results_high.txt` — companies, executives
   - `results_medium.txt` — regions, industry
   - `results_low.txt` — general context

## Key Features

| Feature | Details |
|---|---|
| **Multi-source enrichment** | DaData API + FSRAR Open Data + cross-referencing |
| **Streaming XML parser** | Reads 10 GB FSRAR dump with 8 MB chunks — no OOM |
| **Priority-based filtering** | H/M/L classification keeps signal-to-noise ratio high |
| **Regex compilation** | Single compiled pattern for 2000+ keywords |
| **Address normalization** | Handles Russian street variations (`ул.` vs `УЛИЦА`, `ё → е`) |
| **URL cache** | Each article shown only once across runs |
| **UTF-8 safe** | Full Cyrillic support in scripts, configs, outputs |
| **Zero install** | Runs on any corporate Windows with PowerShell 5.1 — no admin rights |

## Architecture

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ counterparties   │    │  DaData API      │    │  FSRAR Open      │
│ (xlsx: name+INN) │───▶│  enrich.ps1      │───▶│  Data (10 GB XML)│
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
│             MERGE  →  keywords_all.csv  (1959 keywords)          │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │  parser.ps1 (v9)       │
                    │  19 RSS + HTML         │
                    │  Compiled regex match  │
                    │  URL cache             │
                    └────────────────────────┘
                                 │
                ┌────────────────┼────────────────┐
                ▼                ▼                ▼
        results_high.txt  results_medium.txt  results_low.txt
```

## Tech Stack

- **PowerShell 5.1** — core scripting
- **DaData API** — company enrichment (free tier: 10K req/day)
- **FSRAR Open Data** — government licensing registry (XML, 1.7M rows)
- **Selenium WebDriver** — browser automation for dynamic pages
- **Excel COM** — reading source spreadsheets
- **StreamReader + Regex** — streaming XML parsing of 10 GB dumps
- **Compiled `System.Text.RegularExpressions.Regex`** — pattern matching at C-level speed

## Getting Started

### Prerequisites

- Windows 10/11
- PowerShell 5.1 (built-in)
- Microsoft Excel (for source `.xlsx`)
- [DaData API key](https://dadata.ru/api/) (free)
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

4. (Optional) Configure keywords in `_config\keywords_manual.txt`.

### Usage

```powershell
# First run: build keyword base (5–10 min)
.\НАСТРОЙКА.bat

# Daily: parse news and write reports
.\ЗАПУСТИТЬ.bat

# Monthly: refresh FSRAR open data (20–30 min)
.\ОБНОВИТЬ_ФСРАР.bat
```

After running, check `_results\results_high.txt` for matches.

## Example Output

```
===========================================
Source:    Kommersant (news)
Title:     Компания «Ромашка» выиграла тендер на поставку
Link:      https://www.kommersant.ru/doc/8991422
Date:      2026-10-01 15:36
Priority:  H
Matched:   [H] ООО Ромашка; [M] Москва
===========================================
```

## Project Structure

```
.
├── README.md
├── LICENSE
├── .gitignore
├── ЗАПУСТИТЬ.bat              # daily runner
├── НАСТРОЙКА.bat              # rebuild keyword base
├── ОБНОВИТЬ_ФСРАР.bat         # refresh FSRAR data
├── _bin/                       # all scripts
│   ├── paths.ps1               # centralized path config
│   ├── secrets.ps1             # API key (gitignored)
│   ├── parser.ps1              # main news parser
│   ├── enrich.ps1              # DaData enrichment
│   ├── enrich2.ps1             # affiliated companies
│   ├── fsrar_parse.ps1         # streaming XML parser
│   └── ...
├── _config/                    # user input
│   ├── counterparties.xlsx     # company list (gitignored)
│   └── keywords_manual.txt     # manual keywords (gitignored)
├── _data/                      # intermediate data (gitignored)
├── _fsrar/                     # government data (gitignored, 11 GB)
├── _results/                   # parser output (gitignored)
└── _tech/                      # dev artifacts (gitignored)
```

## Known Limitations

- **Windows-only** — uses Excel COM and `Read-Host` for interactive prompts.
- **Single-threaded** — 19 sources processed sequentially; parallelization is on the roadmap.
- **FSRAR XML is 10 GB uncompressed** — requires ~12 GB free disk space.
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