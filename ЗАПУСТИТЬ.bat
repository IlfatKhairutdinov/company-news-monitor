@echo off
title NEWS PARSER
cd /d "%~dp0"

if not exist "_data\keywords_all.csv" (
    echo ERROR: keywords_all.csv not found
    echo Run НАСТРОЙКА.bat first
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "_bin\parser.ps1"
pause