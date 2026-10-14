# audit_state.ps1 -- mechanical audit for the bug class that actually bit us in v1.50-s18.
#
# THE BUG (docs/plans section 35.2): ComputeClosures appended to g_result.closure[] once
# per full recompute but never reset g_result.nClosure, and the central reset block in
# ComputeStructure did not list nClosure either. The count therefore accumulated every
# frame: first frame nodes=59/closure=59, next frame nodes=58/closure=117.
#
# NOTHING mechanical caught it: it compiled 0 errors / 0 warnings, and a hand-written
# "proof" of the invariant closure <= nodes was scoped to a SINGLE call, so it missed the
# cross-call case. What caught it was runtime data (the invariant + the CSV header).
#
# This script turns that lesson into a repeatable static check.
#
# WHAT IT CHECKS
#   A. Every `int n<X>;` count field in `struct StructureResult` has >=1 reset
#      (`g_result.n<X> = 0;`).
#   B. For each count field: the function holding the reset must actually DRIVE the
#      increments -- i.e. it must call one of the Add* helpers that does `g_result.n<X>++`.
#      A reset that lives only in ComputeStructure's central block is reported as OK*
#      (weaker: it does not protect against a pass that early-returns before its loop).
#   C. A curated list of per-frame globals each has at least one plain assignment, so a
#      frame cannot leave a stale value behind.
#   D. Every global READ in RenderScene that is absent from the needDraw fingerprint must
#      either be added to the fingerprint or listed in the JUSTIFIED table WITH a reason.
#      An unlisted one is a FAIL -- hard convention 3: a visual element missing from the
#      fingerprint leaves the chart stale ("wait for the next bar").
#      This check began as informational; a list people learn to ignore is worthless, so
#      every exception now has to be written down with its reason.
#
# WHAT IT DOES NOT CHECK
#   * Reachability of an assignment on every path (early returns, guards).
#   * Whether the assigned VALUE is right.
#   * Anything about the fast path (same-bar tick) beyond presence of the code.
#   * Assignments made THROUGH BY-REFERENCE OUT-PARAMETERS. Concretely:
#     `EvalEarlyCisd(close, g_icValid, g_icLevel, g_icRefBar)` writes those three
#     globals, but the only TEXTUAL assignment the checker can see is the one inside
#     UpdateEarlyCisdFast. So for that pattern the reported location is misleading --
#     verify by hand that such a function declares its out-params with '&'
#     (MQL5 passes simple types by value without it, and the call would silently
#     leave the caller's variable untouched while still compiling).
#   It is a tripwire for one bug class, not a verifier.
#
# NOTE ON THE CHECKER ITSELF: the first version of this script tracked "current function"
# with a loose regex and produced FALSE FAILs (it blamed FindBrokenNodeBar for nMSS/nCISD
# and reported nSWEEP/nClosure as "not reset anywhere" when both do reset). A checker that
# cries wolf is as harmful as one that stays silent, so function attribution here is done
# by scanning backwards to the nearest column-0 function definition -- and every result is
# reported with the enclosing function NAME so a wrong attribution is visible on sight.
#
# ASCII ONLY. Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so non-ASCII source
# would be mangled into syntax errors (CONTEXT.md hard convention #6).
#
# Usage:  powershell -File audit_state.ps1
#         powershell -File audit_state.ps1 -Src <path to .mq5>

param(
    [string]$Src = (Join-Path $PSScriptRoot 'Structure.mq5')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Src)) { Write-Output "FATAL: source not found: $Src"; exit 2 }

$lines = Get-Content $Src -Encoding UTF8
$total = $lines.Count
Write-Output "audit_state: $Src  ($total lines)"

$problems = 0

# A function definition starts at column 0 and looks like `type name(`.
$fnDefRe = '^(void|int|bool|double|long|string|datetime|color|uint)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('

# Map every line index -> enclosing function name (nearest preceding column-0 definition).
$owner = New-Object string[] $total
$cur = '<top-level>'
for ($i = 0; $i -lt $total; $i++) {
    if ($lines[$i] -match $fnDefRe) { $cur = $Matches[2] }
    $owner[$i] = $cur
}
$fnCount = ($owner | Sort-Object -Unique).Count
Write-Output "  functions/top-level units detected: $fnCount"

# ---------------------------------------------------------------- struct parse
$sBegin = -1
for ($i = 0; $i -lt $total; $i++) {
    if ($lines[$i] -match '^\s*struct\s+StructureResult\b') { $sBegin = $i; break }
}
if ($sBegin -lt 0) { Write-Output "FATAL: struct StructureResult not found"; exit 2 }
$sEnd = -1
for ($i = $sBegin + 1; $i -lt $total; $i++) {
    if ($lines[$i] -match '^\s*\};') { $sEnd = $i; break }
}
if ($sEnd -lt 0) { Write-Output "FATAL: end of struct StructureResult not found"; exit 2 }

$countFields = New-Object System.Collections.ArrayList
for ($i = $sBegin; $i -le $sEnd; $i++) {
    if ($lines[$i] -match '^\s*int\s+(n[A-Za-z0-9_]*)\s*;') { [void]$countFields.Add($Matches[1]) }
}
if ($countFields.Count -eq 0) {
    Write-Output "FATAL: no count fields parsed -- struct layout changed, script is stale"
    exit 2
}

# Helpers: line indexes where a pattern occurs.
function Find-Lines($lines, $total, $pattern) {
    $out = @()
    for ($i = 0; $i -lt $total; $i++) {
        if ($lines[$i] -match $pattern) { $out += $i }
    }
    return , $out
}

Write-Output ""
Write-Output "== A. StructureResult count fields: does each have a reset? ($($countFields.Count) fields) =="
$resetOwner = @{}
foreach ($cf in $countFields) {
    $hits = Find-Lines $lines $total ("g_result\." + [regex]::Escape($cf) + "\s*=\s*0\s*;")
    if ($hits.Count -eq 0) {
        Write-Output ("  FAIL  {0,-12} no reset found" -f $cf)
        $problems++
    } else {
        $owners = ($hits | ForEach-Object { $owner[$_] }) | Sort-Object -Unique
        $resetOwner[$cf] = $owners
        Write-Output ("  ok    {0,-12} reset in [{1}] at line(s) {2}" -f $cf, ($owners -join ', '), (($hits | ForEach-Object { $_ + 1 }) -join ', '))
    }
}

# ------------------------------------------------- central reset block contents
$cLine = -1
for ($i = 0; $i -lt $total; $i++) {
    if ($lines[$i] -match '^\s*void\s+ComputeStructure\s*\(') { $cLine = $i; break }
}
$central = @()
if ($cLine -ge 0) {
    for ($i = $cLine; $i -lt [Math]::Min($cLine + 40, $total); $i++) {
        if ($lines[$i] -match 'g_result\.(n[A-Za-z0-9_]*)\s*=\s*0\s*;') { $central += $Matches[1] }
    }
}
$central = $central | Sort-Object -Unique

Write-Output ""
Write-Output "== B. does the reset function actually DRIVE the increments? =="
Write-Output ("  central block (ComputeStructure) resets: {0}" -f ($central -join ', '))

foreach ($cf in $countFields) {
    $incLines = Find-Lines $lines $total ("g_result\." + [regex]::Escape($cf) + "\+\+")
    if ($incLines.Count -eq 0) {
        Write-Output ("  --    {0,-12} never incremented (unused?)" -f $cf)
        continue
    }
    $incFns = ($incLines | ForEach-Object { $owner[$_] }) | Sort-Object -Unique

    if (-not $resetOwner.ContainsKey($cf)) { continue }
    $resFns = $resetOwner[$cf]

    # A reset function qualifies if it calls one of the increment helpers.
    $driver = $null
    foreach ($rf in $resFns) {
        $body = Find-Lines $lines $total (("^\s*(void|int|bool|double|long|string|datetime)\s+" + [regex]::Escape($rf) + "\s*\("))
        if ($body.Count -eq 0) { continue }
        $fStart = $body[0]
        # body ends where the next column-0 definition begins
        $fEnd = $total - 1
        for ($i = $fStart + 1; $i -lt $total; $i++) {
            if ($lines[$i] -match $fnDefRe) { $fEnd = $i - 1; break }
        }
        foreach ($inc in $incFns) {
            for ($i = $fStart; $i -le $fEnd; $i++) {
                if ($lines[$i] -match ("\b" + [regex]::Escape($inc) + "\s*\(")) { $driver = $rf; break }
            }
            if ($driver) { break }
        }
        if ($driver) { break }
    }

    if ($driver) {
        Write-Output ("  ok    {0,-12} inc in [{1}] / reset in [{2}] which calls it" -f $cf, ($incFns -join ', '), $driver)
    } elseif (($central -contains $cf)) {
        Write-Output ("  OK*   {0,-12} inc in [{1}] / reset only in CENTRAL block" -f $cf, ($incFns -join ', '))
        Write-Output  "        ^ weaker: does not protect a pass that early-returns before its loop."
    } else {
        Write-Output ("  FAIL  {0,-12} inc in [{1}] / reset in [{2}] which does NOT call the incrementer" -f $cf, ($incFns -join ', '), ($resFns -join ', '))
        $problems++
    }
}

# ------------------------------------------------------- per-frame global state
Write-Output ""
Write-Output "== C. per-frame globals: is each assigned somewhere? =="
$globals = @(
    'g_armedCisdHighValid', 'g_armedCisdHighLevel', 'g_armedCisdHighBar',
    'g_armedCisdLowValid',  'g_armedCisdLowLevel',  'g_armedCisdLowBar',
    'g_curBias', 'g_curATR',
    'g_erlValid', 'g_erlPrice', 'g_erlBar',
    'g_irlValid', 'g_irlPrice', 'g_irlFvgIdx',
    'g_pdValid', 'g_pdh', 'g_pdl', 'g_pdT1',
    'g_relValid', 'g_relHigh', 'g_relLow',
    'g_tgtCount', 'g_fibValid', 'g_fibA', 'g_fibB', 'g_fibRefBar', 'g_fibDir',
    'g_htfT0', 'g_htfSig',
    'g_icValid', 'g_icLevel', 'g_icRefBar'
)
$miss = @()
foreach ($g in $globals) {
    # A declaration with an initializer (`double g_x = 0.0;`) is NOT a per-frame
    # assignment. The first version of this check accepted it and reported every global
    # as "ok (in <top-level>)" -- a false PASS, i.e. exactly the kind of hollow green
    # light this script exists to prevent. Declarations are now excluded.
    $ok = $false
    $at = -1
    for ($i = 0; $i -lt $total; $i++) {
        if ($lines[$i] -match '^\s*(double|int|bool|long|string|datetime|color|uint|float|short|char)\b') { continue }
        if ($lines[$i] -match '^\s*(input|extern|static)\b') { continue }
        if ($lines[$i] -match ("(^|[^=!<>+\-*/])\b" + [regex]::Escape($g) + "\s*=[^=]")) { $ok = $true; $at = $i + 1; break }
    }
    if ($ok) {
        Write-Output ("  ok    {0,-22} first non-declaration assign at line {1} (in {2})" -f $g, $at, $owner[$at - 1])
    } else {
        Write-Output ("  FAIL  {0,-22} no non-declaration assign -- stale-value risk" -f $g)
        $miss += $g
    }
}
$problems += $miss.Count

# ================================================================ check D
# Hard convention #3: a visual element that is not covered by the needDraw fingerprint
# leaves the chart stale ("you have to wait for the next bar"). Every exception must be
# written down with a reason -- see the JUSTIFIED table below.
#
# NOTE: there used to be a PRELIMINARY "RESULT:" line printed here, before check D ran.
# That meant a reader who stopped at the first RESULT saw PASS even when D failed --
# a false green light, i.e. exactly the failure mode this script exists to prevent.
# There is now exactly ONE RESULT line, at the very end.
Write-Output ""
Write-Output "== D. globals READ in RenderScene but ABSENT from the needDraw fingerprint =="

$rsBegin = -1
for ($i = 0; $i -lt $total; $i++) {
    if ($lines[$i] -match '^void\s+RenderScene\s*\(') { $rsBegin = $i; break }
}
$ndBegin = -1
for ($i = 0; $i -lt $total; $i++) {
    if ($lines[$i] -match '^\s*bool\s+needDraw\s*=') { $ndBegin = $i; break }
}

if ($rsBegin -lt 0 -or $ndBegin -lt 0) {
    Write-Output "  (skipped: RenderScene or needDraw not found -- layout changed?)"
} else {
    $rsEnd = $total - 1
    for ($i = $rsBegin + 1; $i -lt $total; $i++) {
        if ($lines[$i] -match $fnDefRe) { $rsEnd = $i - 1; break }
    }
    # needDraw expression ends at the first line whose trailing ';' closes it
    $ndEnd = $ndBegin
    for ($i = $ndBegin; $i -lt $total; $i++) {
        if ($lines[$i] -match ';\s*$') { $ndEnd = $i; break }
    }

    $reads = @{}
    for ($i = $rsBegin; $i -le $rsEnd; $i++) {
        $code = $lines[$i]
        # drop line comments so prose does not produce hits
        $c = $code.IndexOf('//')
        if ($c -ge 0) { $code = $code.Substring(0, $c) }
        foreach ($m in [regex]::Matches($code, '\bg_[A-Za-z0-9_]+\b')) {
            $n = $m.Value
            # skip assignment targets on this line
            if ($code -match ("\b" + [regex]::Escape($n) + "\s*=[^=]")) { continue }
            $reads[$n] = $true
        }
    }
    $inFp = @{}
    for ($i = $ndBegin; $i -le $ndEnd; $i++) {
        $code = $lines[$i]
        $c = $code.IndexOf('//')
        if ($c -ge 0) { $code = $code.Substring(0, $c) }
        foreach ($m in [regex]::Matches($code, '\bg_[A-Za-z0-9_]+\b')) { $inFp[$m.Value] = $true }
    }

    # Justified exclusions. Every entry MUST carry a reason; a global that is read in
    # RenderScene and is neither in the fingerprint nor listed here is a FAIL, not a
    # note -- otherwise this section degenerates into a list people learn to ignore.
    # (The first version printed such candidates as informational "?" lines only.)
    $justified = @{
        'g_result'    = 'arrays; covered indirectly by the count-based fingerprint terms'
        'g_drawnFrom' = 'diagnostic only; never drawn'
        'g_curATR'    = 'label vertical offset only; may go stale on a same-bar full recompute when InpReuseResultOnTick=false -- known, accepted'
        'g_fibLegs'   = 'set once in OnInit; MT5 re-runs OnInit on any input change, so it cannot go stale'
        'g_fibNLegs'  = 'set once in OnInit; same reasoning as g_fibLegs'
        'g_icLate'    = 'flips inside a bar by design; handled by the FAST PATH cache (UpdateEarlyCisdFast compares it), same division of labour as UpdateLiveLeg'
    }
    $cands = @()
    $noted = @()
    foreach ($n in ($reads.Keys | Sort-Object)) {
        if ($inFp.ContainsKey($n)) { continue }
        if ($n -like 'g_last*') { continue }          # fingerprint storage itself
        if ($n -like 'g_dbg*')  { continue }          # diagnostics
        if ($n -like 'g_set*')  { continue }          # scene-set internals
        if ($n -like 'g_icName*' -or $n -like 'g_icLblName') { continue }  # object-name cache
        if ($justified.ContainsKey($n)) { $noted += $n; continue }
        $cands += $n
    }
    Write-Output ("  coverage: {0} distinct globals read in RenderScene; {1} of them appear in needDraw" -f $reads.Count, $inFp.Count)
    if ($reads.Count -lt 10) {
        Write-Output "  !!  FAIL  collector found almost nothing -- this check is vacuous, fix the script"
        $problems++
    }
    foreach ($n in $noted) {
        Write-Output ("  ok    {0,-22} exempt: {1}" -f $n, $justified[$n])
    }
    if ($cands.Count -eq 0) {
        Write-Output "  ok    no UNJUSTIFIED render-input global is missing from the fingerprint"
    } else {
        foreach ($n in $cands) {
            Write-Output ("  !!  FAIL  {0,-20} read in RenderScene, not in needDraw, and has no written reason" -f $n)
            Write-Output  "            -> add it to the fingerprint, OR add it to the justified list WITH a reason"
            $problems++
        }
    }
}

Write-Output ""
if ($problems -eq 0) {
    Write-Output "RESULT: PASS (0 problems). All four checks are pass-fail; scope: the bug classes in the header."
    exit 0
} else {
    Write-Output "RESULT: FAIL ($problems problem(s)). All four checks are pass-fail; scope: the bug classes in the header."
    exit 1
}
