@echo off
title UPDATE FSRAR DATA
cd /d "%~dp0"

echo ===========================================
echo  UPDATE FSRAR DATA
echo ===========================================
echo.
echo This will download ~300 MB and process 10 GB XML.
echo Takes 20-30 minutes. Do not close the window.
echo.

set PARSER_NO_PAUSE=1

echo [1/5] Downloading open data...
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\fsrar_opendata.ps1"

echo.
echo [2/5] Unpacking XML...
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\fsrar_unpack.ps1"

echo.
echo [3/5] Parsing 1.6M records (10-15 min)...
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\fsrar_parse.ps1"

echo.
echo [4/5] Matching with our companies...
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\fsrar_match.ps1"

echo.
echo [5/5] Cleaning neighbors...
powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\fsrar_clean.ps1"

echo.
echo ===========================================
echo   DONE
echo ===========================================
echo.
echo Now run Õ¿—“–Œ… ¿.bat to merge new keywords.
pause