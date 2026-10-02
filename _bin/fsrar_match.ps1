# fsrar_match.ps1 - match our 298 companies with FSRAR 1.67M records
# Finds neighbors by address, saves L keys
# SAVE AS UTF-8 WITH BOM (Russian in code)



# Автоподключение всех путей проекта
. "$PSScriptRoot\paths.ps1"

if (-not (Test-Path $fsrarCsv)) {
    Write-Host "ERROR: $fsrarCsv not found. Run RUN_FSRAR_PARSE.bat first." -ForegroundColor Red
    if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}; exit 1
}

$raw = Get-Content $rawFile -Raw -Encoding UTF8 | ConvertFrom-Json

# --- Address extraction ---
function Extract-AddressKey {
    param([string]$addr)
    if (-not $addr) { return "" }
    $a = $addr.ToLower() -replace 'ё', 'е'
    $a = $a -replace 'г\.', ' г ' -replace 'ул\.', ' ул ' -replace 'д\.', ' д '
    $a = $a -replace '[^а-я0-9]+', ' '
    $tokens = $a -split '\s+' | Where-Object { $_ -ne '' }
    
    $city = ""; $street = ""; $house = ""
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -eq 'г' -and $i + 1 -lt $tokens.Count) { $city = $tokens[$i + 1]; $i++; continue }
        if ($t -eq 'ул' -and $i + 1 -lt $tokens.Count) { $street = $tokens[$i + 1]; $i++; continue }
        if ($t -eq 'д' -and $i + 1 -lt $tokens.Count) { $house = $tokens[$i + 1]; $i++; continue }
    }
    if ($city -and $street) {
        return "$city|$street|$house"
    }
    return ""
}

# --- Build our sets ---
$ourInns = New-Object System.Collections.Generic.HashSet[string]
$ourAddrKeys = New-Object System.Collections.Generic.HashSet[string]

foreach ($c in $raw) {
    if ($c.inn) { [void]$ourInns.Add("$($c.inn)".Trim()) }
    if ($c.address -and $c.address.value) {
        $k = Extract-AddressKey $c.address.value
        if ($k) { [void]$ourAddrKeys.Add($k) }
    }
}

Write-Host ("Our INNs:        " + $ourInns.Count)
Write-Host ("Our addr keys:   " + $ourAddrKeys.Count)
Write-Host ""

# --- Pass 1: find our companies + their branches ---
Write-Host "Pass 1: locating our companies in FSRAR..." -ForegroundColor Cyan

$ourBranchKeys = New-Object System.Collections.Generic.HashSet[string]
$ourFoundInFsrar = 0
$reader = [System.IO.StreamReader]::new($fsrarCsv, [System.Text.Encoding]::UTF8)
$null = $reader.ReadLine()  # skip header
$lineNum = 0

while (($line = $reader.ReadLine()) -ne $null) {
    $lineNum++
    $p = $line -split ';', 7
    if ($p.Count -lt 7) { continue }
    $inn = $p[0].Trim()
    if ($inn -and $ourInns.Contains($inn)) {
        $ourFoundInFsrar++
        $k1 = Extract-AddressKey $p[3]
        $k2 = Extract-AddressKey $p[4]
        if ($k1) { [void]$ourBranchKeys.Add($k1) }
        if ($k2) { [void]$ourBranchKeys.Add($k2) }
    }
    if ($lineNum % 300000 -eq 0) {
        Write-Host ("  read $lineNum lines, our records: $ourFoundInFsrar, branch keys: $($ourBranchKeys.Count)")
    }
}
$reader.Close()

Write-Host ""
Write-Host ("Our companies found in FSRAR: " + $ourFoundInFsrar + " records") -ForegroundColor Green
Write-Host ("Branch address keys: " + $ourBranchKeys.Count)

# Combine all "interesting" addresses
$allInteresting = New-Object System.Collections.Generic.HashSet[string]
foreach ($k in $ourAddrKeys) { [void]$allInteresting.Add($k) }
foreach ($k in $ourBranchKeys) { [void]$allInteresting.Add($k) }
Write-Host ("Total interesting keys: " + $allInteresting.Count)

# --- Pass 2: find neighbors ---
Write-Host ""
Write-Host "Pass 2: finding neighbors..." -ForegroundColor Cyan

$neighbors = @{}
$reader = [System.IO.StreamReader]::new($fsrarCsv, [System.Text.Encoding]::UTF8)
$null = $reader.ReadLine()
$lineNum = 0

while (($line = $reader.ReadLine()) -ne $null) {
    $lineNum++
    $p = $line -split ';', 7
    if ($p.Count -lt 7) { continue }
    $inn = $p[0].Trim()
    if (-not $inn) { continue }
    if ($ourInns.Contains($inn)) { continue }

    $status = $p[6]
    if ($status -notmatch 'действ') { continue }

    $k1 = Extract-AddressKey $p[3]
    $k2 = Extract-AddressKey $p[4]

    $matched = ""
    if ($k1 -and $allInteresting.Contains($k1)) { $matched = $k1 }
    elseif ($k2 -and $allInteresting.Contains($k2)) { $matched = $k2 }

    if ($matched -and -not $neighbors.ContainsKey($inn)) {
        $neighbors[$inn] = [PSCustomObject]@{
            INN = $inn
            Name = $p[2]
            LegalAddr = $p[3]
            BranchAddr = $p[4]
            Activity = $p[5]
            Status = $p[6]
            Matched = $matched
        }
    }

    if ($lineNum % 300000 -eq 0) {
        Write-Host ("  read $lineNum lines, neighbors: $($neighbors.Count)")
    }
}
$reader.Close()

Write-Host ""
Write-Host ("Neighbors found: " + $neighbors.Count) -ForegroundColor Green

# --- Save L keys ---
$lines = @()
foreach ($kv in $neighbors.GetEnumerator()) {
    $n = $kv.Value
    $cleanName = $n.Name
    if ($cleanName -match '^(.+?)\s+Сокращенно:') { $cleanName = $matches[1].Trim() }
    $cleanName = $cleanName -replace '[«»"]', '' -replace '\s+', ' '
    $cleanName = $cleanName.Trim()
    
    if ($cleanName.Length -ge 3) {
        $lines += ("L," + $cleanName)
    }
    $lines += ("L," + $kv.Key)
}
[System.IO.File]::WriteAllLines($outKw, $lines, (New-Object System.Text.UTF8Encoding $true))

# --- Debug CSV ---
$rows = @("inn;name;legal_addr;branch_addr;activity;status;matched_key")
foreach ($kv in $neighbors.GetEnumerator()) {
    $n = $kv.Value
    $cn = $n.Name -replace ';', ',' -replace '\r?\n', ' '
    $la = $n.LegalAddr -replace ';', ','
    $ba = $n.BranchAddr -replace ';', ','
    $ac = $n.Activity -replace ';', ','
    $rows += "$($n.INN);$cn;$la;$ba;$ac;$($n.Status);$($n.Matched)"
}
[System.IO.File]::WriteAllLines($debugFile, $rows, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host ("  Neighbors (unique INNs):  " + $neighbors.Count)
Write-Host ("  Keywords (L) written:     " + $lines.Count)
Write-Host ("  Our records in FSRAR:     " + $ourFoundInFsrar)
Write-Host ""
Write-Host ("  L keys:  " + $outKw)
Write-Host ("  Debug:   " + $debugFile)
Write-Host "===========================================" -ForegroundColor Green
if (-not $env:PARSER_NO_PAUSE) {
    Read-Host "Press Enter to exit"
}
