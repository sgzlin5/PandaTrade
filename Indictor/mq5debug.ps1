# Structure debug loop: compile -> deploy (mq5 + ex5) -> verify -> read runtime log
# Usage:  . mq5debug.ps1 -WaitSec 5 -Tail 3
#         . mq5debug.ps1 -Verify          # only check what MT5 currently has
# NOTE: ASCII only. Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI,
#       so non-ASCII source would be mangled into syntax errors.
param(
    [string]$Name = 'Structure',
    [string]$Sub = 'Indicators',
    [int]$WaitSec = 0,
    [switch]$All,
    [switch]$Verify,
    [int]$Tail = 3
)

$ErrorActionPreference = 'Continue'

# $Sub picks BOTH the repo source dir and the MT5 target dir, so that EAs get the
# same compile -> deploy -> hash-verify treatment as indicators:
#   -Sub Indicators  ->  ./Indictor/*.mq5  ->  MQL5/Indicators   (default, unchanged)
#   -Sub Experts     ->  ./EA/*.mq5        ->  MQL5/Experts
$dir     = if ($Sub -eq 'Experts') { 'D:\Crypto\code\sturdy-giggle\EA' } else { 'D:\Crypto\code\sturdy-giggle\Indictor' }
$src     = Join-Path $dir ($Name + '.mq5')
$ex5     = Join-Path $dir ($Name + '.ex5')
$log     = Join-Path $dir ('compile_' + $Name + '.log')
$mql5dir = 'C:\Users\LZJ\AppData\Roaming\MetaQuotes\Terminal\97C14A345F12BC3CEEC3269EA27B4E26\MQL5\' + $Sub
$explog  = 'C:\Users\LZJ\AppData\Roaming\MetaQuotes\Terminal\97C14A345F12BC3CEEC3269EA27B4E26\MQL5\logs'

# Compares what the repo built against what MT5 would actually load.
# Rationale: the MT5\Indicators folder has historically held a SECOND, stale copy of
# the .mq5. If anything compiles that copy, it silently overwrites the deployed .ex5
# and the terminal runs an old build while file timestamps still look correct.
function Show-Compare {
    $mb = Join-Path $mql5dir ($Name + '.mq5')
    $eb = Join-Path $mql5dir ($Name + '.ex5')
    $srcTag = (Select-String -Path $src -Pattern '^#define BUILD_TAG' |
               Select-Object -First 1).Line
    Write-Output "SRC  $srcTag"
    foreach ($pair in @(@($src, $mb, 'mq5'), @($ex5, $eb, 'ex5'))) {
        $a = $pair[0]; $b = $pair[1]; $kind = $pair[2]
        if (-not (Test-Path $a)) { Write-Output "VERIFY $kind : repo artifact MISSING ($a)"; continue }
        $ha = (Get-FileHash $a).Hash
        if (-not (Test-Path $b)) { Write-Output "VERIFY $kind : MT5 copy MISSING"; continue }
        $hb = (Get-FileHash $b).Hash
        $ok = ($ha -eq $hb)
        Write-Output ("VERIFY {0} repo={1} mt5={2} match={3}" -f $kind, $ha.Substring(0,12), $hb.Substring(0,12), $ok)
        if (-not $ok) { Write-Output ("!! $kind MISMATCH: MT5 copy is NOT what the repo built -- something recompiled the MT5-side file.") }
    }
}

if ($Verify) { Show-Compare; return }

# --- pick newest MetaEditor ---
$me = Get-ChildItem 'C:\Program Files\*\MetaEditor64.exe' -ErrorAction SilentlyContinue |
      Sort-Object { $_.VersionInfo.FileVersion } -Descending |
      Select-Object -First 1 -ExpandProperty FullName
if (-not $me) { Write-Output 'FATAL: MetaEditor64.exe not found'; return }
Write-Output "MetaEditor: $me"

# --- 1. compile (repo source) ---
Write-Output '--- compiling ---'
& $me /compile:"$src" /log:"$log" | Out-Null
Start-Sleep -Milliseconds 1500

$result = (Get-Content $log -Encoding Unicode -ErrorAction SilentlyContinue |
           Select-String -Pattern 'Result:').Line
Write-Output "COMPILE $result"

if ($result -notmatch '0 errors') {
    Write-Output '--- errors/warnings ---'
    Get-Content $log -Encoding Unicode |
        Select-String -Pattern 'error|warning' | ForEach-Object { $_.Line }
    Write-Output '!! compile failed - not deploying'
    return
}

# --- 2. deploy: BOTH the source and the binary ---
# Deploying the .mq5 keeps the MT5-side copy current, so that if anything there
# compiles it, the result is still the current build instead of a stale one.
Copy-Item $src (Join-Path $mql5dir ($Name + '.mq5')) -Force
Copy-Item $ex5 (Join-Path $mql5dir ($Name + '.ex5')) -Force
Write-Output "DEPLOYED mq5+ex5 -> $mql5dir"
Show-Compare

# --- 3. read runtime log ---
if ($WaitSec -gt 0) {
    Write-Output "--- waiting $WaitSec s (attach the indicator in MT5 now) ---"
    Start-Sleep -Seconds $WaitSec
}

$lfile = Get-ChildItem $explog -Filter *.log -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $lfile) { Write-Output 'no expert log found'; return }

Write-Output "--- expert log: $($lfile.Name) (mtime $($lfile.LastWriteTime)) ---"

# INIT line: match by file name + "build=" ONLY (ASCII-safe).
# The old pattern hardcoded a version literal, so it silently stopped matching
# once the INIT format changed -- a stale pattern that reports "nothing found"
# is indistinguishable from "the indicator never ran".
$init = Select-String -Path $lfile.FullName -Pattern $Name -Encoding UTF8 |
        Where-Object { $_.Line -match 'build=' } | Select-Object -Last 1
if ($init) { Write-Output ('INIT  ' + ($init.Line -replace '^\S+\s+\d+\s+\S+\s+', '')) }
else       { Write-Output "INIT  (no line for $Name with build= found)" }

$dbg = Select-String -Path $lfile.FullName -Pattern 'STRUCT_DBG' -Encoding UTF8
if (-not $dbg) {
    Write-Output 'DBG   (none) -- indicator has not run yet; drop it on a chart in MT5'
} elseif ($All) {
    $dbg | ForEach-Object { $_.Line }
} else {
    $dbg | Select-Object -Last $Tail | ForEach-Object { $_.Line -replace '^\S+\s+\d+\s+\S+\s+', '' }
}
