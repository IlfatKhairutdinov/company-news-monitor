# paths.ps1 - все пути проекта в одном месте
# Подключается автоматически из каждого скрипта

$ProjectRoot = Split-Path $PSScriptRoot -Parent

# === Config ===
$configPath     = Join-Path $ProjectRoot "_config\config.txt"
$inputXlsx      = Join-Path $ProjectRoot "_config\counterparties.xlsx"
$keywordsManual = Join-Path $ProjectRoot "_config\keywords_manual.txt"
$yandexKwFile   = Join-Path $ProjectRoot "_config\yandex_keywords.txt"

# === Data ===
$inputCsv      = Join-Path $ProjectRoot "_data\companies.csv"
$outputCsv     = Join-Path $ProjectRoot "_data\companies.csv"
$rawFile       = Join-Path $ProjectRoot "_data\companies_raw.json"
$keywordsFile  = Join-Path $ProjectRoot "_data\keywords_all.csv"
$outputKw      = Join-Path $ProjectRoot "_data\keywords_auto.csv"
$outKw         = Join-Path $ProjectRoot "_data\keywords_checko.csv"
$outFile       = Join-Path $ProjectRoot "_data\keywords_checko_fsrar_clean.csv"
$srcFile       = Join-Path $ProjectRoot "_data\keywords_checko_fsrar.csv"
$outputRaw     = Join-Path $ProjectRoot "_data\companies_raw.json"
$cacheFile     = Join-Path $ProjectRoot "_data\dadata_cache.json"
$seenUrlsFile  = Join-Path $ProjectRoot "_data\seen_urls.txt"

# Отдельные пути к keyword-файлам (для merge_keywords.ps1)
$kwAutoFile    = Join-Path $ProjectRoot "_data\keywords_auto.csv"
$kwCheckoFile  = Join-Path $ProjectRoot "_data\keywords_checko.csv"
$kwFsrarFile   = Join-Path $ProjectRoot "_data\keywords_checko_fsrar_clean.csv"
$kwManualFile  = Join-Path $ProjectRoot "_config\keywords_manual.txt"

# === FSRAR ===
$fsrarCsv   = Join-Path $ProjectRoot "_fsrar\fsrar_all.csv"
$outFsrc    = Join-Path $ProjectRoot "_fsrar\fsrar_all.csv"
$debugFile  = Join-Path $ProjectRoot "_fsrar\fsrar_neighbors.csv"
$zipDir     = Join-Path $ProjectRoot "_fsrar\fsrar_opendata"
$extractDir = Join-Path $ProjectRoot "_fsrar\fsrar_extracted"

# === Results ===
$resultsHigh = Join-Path $ProjectRoot "_results\results_high.txt"
$resultsMed  = Join-Path $ProjectRoot "_results\results_medium.txt"
$resultsLow  = Join-Path $ProjectRoot "_results\results_low.txt"
$resultsAll  = Join-Path $ProjectRoot "_results\results_all.txt"
$resultsCsv  = Join-Path $ProjectRoot "_results\results.csv"
$logFile     = Join-Path $ProjectRoot "_results\sources_log.txt"
$outReport   = Join-Path $ProjectRoot "_results\regions_report.txt"

# === Tech ===
$debugPath = Join-Path $ProjectRoot "_tech\bezformata_debug.html"

# Псевдонимы для совместимости со старыми скриптами
$manualTxt = $keywordsManual
$yandexKw  = $yandexKwFile

# === Secrets (не в git) ===
$secretsFile = Join-Path $PSScriptRoot "secrets.ps1"
if (Test-Path $secretsFile) { . $secretsFile }