# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [9.0.0] - 2026-10-01

### Added
- Multi-source keyword base construction (DaData API + FSRAR Open Data)
- Streaming XML parser for 10 GB FSRAR dump (1.67M records in 14 min, < 200 MB RAM)
- Compiled regex matching engine — ~40× faster than naive `.Contains()` loops
- Priority-based filtering (H/M/L) with three separate output reports
- Address normalization for Russian format variations (`ул.` vs `УЛИЦА`, `ё → е`)
- Persistent URL cache (`seen_urls.txt`) — each article shown only once
- 19 RSS sources (federal + regional) + BezFormata HTML scraping
- Centralized path management via `_bin\paths.ps1`
- Secrets externalized to `_bin\secrets.ps1` (gitignored)

### Changed
- Project restructured into `_bin/`, `_config/`, `_data/`, `_fsrar/`, `_results/`, `_tech/`
- Excel input now uses pipe-delimited intermediate format to handle quotes in names
- All interactive scripts support `PARSER_NO_PAUSE=1` for batch execution

### Removed
- Legacy `config.txt` (superseded by `keywords_all.csv`)
- Non-working sources: Izvestia (HTTP 429), Царьград (connection refused), Meduza (timeout)

### Known Issues
- Yandex News RSS requires manual captcha solving; disabled by default
- Google News RSS blocked on some corporate networks

## [8.3.0] - 2026-09-30

### Added
- BezFormata HTML parser (regional news without RSS)
- HTML vs. XML detection to prevent parser crashes on non-RSS pages
- UTF-8 BOM handling in config files

### Fixed
- `[xml]` cast failing on `<DOCTYPE html>` from non-RSS sources
- Cyrillic encoding issues in `.ps1` files under PowerShell 5.1

## [8.0.0] - 2026-09-29

### Added
- TLS 1.2 enforcement for legacy corporate proxies
- Compile-time regex building
- Structured logging (`sources_log.txt`)
- Excel-to-CSV converter with auto column detection

### Fixed
- UTF-8 reading of `config.txt` (was being parsed as CP1251)
- `$item.title` extraction from XML nodes

## [1.0.0] - 2026-09-28

### Added
- Initial version: 20 RSS sources, keyword matching via `.Contains()`
- Configuration file `config.txt`
- Output to single `results.txt`