# fsrar_parse.ps1 - streaming parser for FSRAR XML (10 GB)
# Reads XML in 8 MB chunks, extracts rows into compact CSV
# SAVE AS UTF-8 WITH BOM (Russian tag names in code)


# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

$xmlFile = Get-ChildItem -Path $extractDir -Filter "*.xml" -Recurse -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1
if (-not $xmlFile) {
    Write-Host "ERROR: no .xml found in $extractDir" -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}; exit 1
}
$xmlPath = $xmlFile.FullName

Write-Host "Input:  $xmlPath"
Write-Host "Size:   $([Math]::Round((Get-Item $xmlPath).Length/1MB, 1)) MB"
Write-Host "Output: $outFile"
Write-Host ""
Write-Host "This will take 5-15 minutes. Do not close the window." -ForegroundColor Yellow
Write-Host ""

# Exact field tag names from the XML
$fInn  = 'ИНН_организации_сельскохозяйственного_товаропроизводителя_'
$fKpp  = 'КПП_организации_сельскохозяйственного_товаропроизводителя_'
$fName = 'Полное_и_сокращенное_наименование_организации_сельскохозяйственного_товаропроизводителя_с_указанием_ее_ОПФ'
$fAddr = 'Адрес__место_нахождения___организации_сельскохозяйственного_товаропроизводителя_'
$fBr   = 'Место_нахождения__адрес__обособленного_подразделения_организации__осуществляющего_лицензируемый_вид_деятельности'
$fAct  = 'Вид_лицензируемой_деятельности_организации'
$fStat = 'Сведения_о_действии_лицензии'

$reInn  = [regex]::new('<' + [regex]::Escape($fInn) + '>(?<v>[^<]*)</', 'IgnoreCase')
$reKpp  = [regex]::new('<' + [regex]::Escape($fKpp) + '>(?<v>[^<]*)</', 'IgnoreCase')
$reName = [regex]::new('<' + [regex]::Escape($fName) + '>(?<v>[^<]*)</', 'IgnoreCase')
$reAddr = [regex]::new('<' + [regex]::Escape($fAddr) + '>(?<v>[^<]*)</', 'IgnoreCase')
$reBr   = [regex]::new('<' + [regex]::Escape($fBr) + '>(?<v>[^<]*)</', 'IgnoreCase')
$reAct  = [regex]::new('<' + [regex]::Escape($fAct) + '>(?<v>[^<]*)</', 'IgnoreCase')
$reStat = [regex]::new('<' + [regex]::Escape($fStat) + '>(?<v>[^<]*)</', 'IgnoreCase')

function Get-Field($re, $body) {
    $m = $re.Match($body)
    if ($m.Success) { return $m.Groups['v'].Value.Trim() }
    return ''
}

$reader = [System.IO.StreamReader]::new($xmlPath, [System.Text.Encoding]::UTF8, $true, 1048576)
$writer = [System.IO.StreamWriter]::new($outFile, $false, [System.Text.UTF8Encoding]::new($true))
$writer.WriteLine('inn;kpp;name;legal_addr;branch_addr;activity;status')

$chunkSize = 8 * 1024 * 1024   # 8M chars
$buffer    = New-Object char[] $chunkSize
$pending   = ''
$rowsTotal = 0
$rowsKept  = 0
$startTime = Get-Date
$lastReport = $startTime

while (($read = $reader.Read($buffer, 0, $chunkSize)) -gt 0) {
    $chunk = $pending + [string]::new($buffer, 0, $read)
    $pending = ''

    $parts = $chunk -split '</row>'
    $pending = $parts[-1]

    if ($parts.Length -gt 1) {
        $complete = $parts[0..($parts.Length - 2)]
        foreach ($p in $complete) {
            $startIdx = $p.IndexOf('<row>')
            if ($startIdx -lt 0) { continue }
            $body = $p.Substring($startIdx + 5)
            $rowsTotal++

            $inn = Get-Field $reInn $body
            if (-not $inn) { continue }

            $kpp  = Get-Field $reKpp  $body
            $name = Get-Field $reName $body
            $la   = Get-Field $reAddr $body
            $ba   = Get-Field $reBr   $body
            $act  = Get-Field $reAct  $body
            $st   = Get-Field $reStat $body

            $writer.WriteLine("$inn;$kpp;$name;$la;$ba;$act;$st")
            $rowsKept++
        }
    }

    # Progress report every 15 seconds
    $now = Get-Date
    if (($now - $lastReport).TotalSeconds -ge 15) {
        $el = ($now - $startTime).TotalSeconds
        $percent = if ($xmlFile.Length -gt 0) { [Math]::Round(($reader.BaseStream.Position / $xmlFile.Length) * 100, 1) } else { 0 }
        Write-Host ("progress ~${percent}%  rows=$rowsTotal kept=$rowsKept  elapsed=$([Math]::Round($el))s")
        $lastReport = $now
    }
}

$reader.Close()
$writer.Close()

$el = ((Get-Date) - $startTime).TotalMinutes
Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  Rows total:  " + $rowsTotal)
Write-Host ("  Rows kept:   " + $rowsKept)
Write-Host ("  Elapsed:     " + [Math]::Round($el, 1) + " min")
Write-Host ("  Output:      " + $outFile)
Write-Host ("  CSV size:    " + [Math]::Round((Get-Item $outFile).Length/1MB, 1) + " MB")
Write-Host "===========================================" -ForegroundColor Green
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
