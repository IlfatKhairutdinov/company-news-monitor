# fsrar_opendata.ps1 v2 - finds and downloads FSRAR Open Data file


# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = "https://fsrar.gov.ru/opendata/7710747640-reestrlic"
Write-Host ("Fetching: " + $url) -ForegroundColor Cyan

try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60 `
        -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" `
        -ErrorAction Stop

    Write-Host ("Page size: " + $resp.Content.Length + " bytes") -ForegroundColor Green

    $pageFile = Join-Path $outDir "opendata_page.html"
    [System.IO.File]::WriteAllText($pageFile, $resp.Content, [System.Text.Encoding]::UTF8)
    Write-Host ("Saved page: " + $pageFile)

    # Find links to actual data files
    $linkRe = [regex]'href="(?<u>[^"]+\.(xml|csv|zip|json|rar|7z|txt))"'
    $found = $linkRe.Matches($resp.Content)
    Write-Host ""
    if ($found.Count -gt 0) {
        Write-Host ("Found " + $found.Count + " data file links:") -ForegroundColor Yellow
        foreach ($m in $found) {
            $link = $m.Groups['u'].Value
            if ($link -notmatch '^https?://') {
                $base = [System.Uri]$url
                $link = ([System.Uri]::new($base, $link)).AbsoluteUri
            }
            Write-Host ("  " + $link)
        }

        # Take first data file and try to download
        $firstLink = $found[0].Groups['u'].Value
        if ($firstLink -notmatch '^https?://') {
            $base = [System.Uri]$url
            $firstLink = ([System.Uri]::new($base, $firstLink)).AbsoluteUri
        }

        Write-Host ""
        Write-Host ("Downloading: " + $firstLink) -ForegroundColor Cyan
        $fileName = [System.IO.Path]::GetFileName(([System.Uri]$firstLink).LocalPath)

        Invoke-WebRequest -Uri $firstLink -OutFile $outFile -TimeoutSec 300 `
            -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" `
            -ErrorAction Stop

        $size = (Get-Item $outFile).Length
        Write-Host ("Downloaded: " + $outFile) -ForegroundColor Green
        Write-Host ("Size: " + [Math]::Round($size/1MB, 2) + " MB")
    } else {
        Write-Host "No direct .xml/.csv/.zip links found." -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "Interesting links on page:" -ForegroundColor Yellow
        $anyRe = [regex]'href="(?<u>[^"]+)"[^>]*>(?<t>[^<]{3,100})</a>'
        foreach ($m in $anyRe.Matches($resp.Content)) {
            $t = $m.Groups['t'].Value.Trim()
            if ($t -match '(?i)(скачать|download|xml|csv|zip|структур|набор|файл|реестр)') {
                Write-Host ("  " + $t + "  ->  " + $m.Groups['u'].Value)
            }
        }
    }
} catch {
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
}

Write-Host ""
Write-Host ("Output dir: " + $outDir)
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
