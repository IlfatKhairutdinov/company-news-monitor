@echo off
chcp 65001 >nul
title SETUP PARSER
cd /d "%~dp0"

set PARSER_NO_PAUSE=1

echo ===========================================
echo  SETUP - update companies and keywords
echo ===========================================
echo.

echo [1/5] Excel -^> companies.csv
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\excel_to_csv.ps1"

echo.
echo [2/5] DaData enrich (names + directors)
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\enrich.ps1"

echo.
echo [3/5] DaData affiliated (addresses)
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\enrich2.ps1"

echo.
echo [4/5] Expand company names
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\expand_keywords.ps1"

echo.
echo [5/5] Merge keywords
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\merge_keywords.ps1"

echo.
echo ===========================================
echo   DONE. Now run ЗАПУСТИТЬ.bat
echo ===========================================
pause