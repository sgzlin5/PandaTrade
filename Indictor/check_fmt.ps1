# check_fmt.ps1 -- format/argument count check for every StringFormat/PrintFormat call.
#
# WHY THIS EXISTS
#   MQL5's StringFormat/PrintFormat are variadic: a mismatch between the number of
#   `%` specifiers and the number of arguments is NOT a compile error and NOT a
#   warning. MQL5 does not warn, and the terminal prints whatever lines up.
#   Consequences observed in this repo:
#     * one EXTRA argument shifts every field after it (e.g. the CSV header printed
#       `ob=0.1` because a double was consumed by an earlier `%s`);
#     * one MISSING argument makes a field print garbage/empty.
#   Both are silent at build time and only show up in archived CSV headers.
#
#   This script caught a real one: a stray comma turned two adjacent format
#   literals into "format + extra argument", so `legs=%s` swallowed the wrong
#   argument and the `legs=` field showed another field's text (v1.50-s46).
#
# HOW IT PARSES
#   For each call it finds `StringFormat(` / `PrintFormat(`, then walks forward
#   tracking string state and parenthesis depth, splitting on TOP-LEVEL commas.
#   Piece 0 is the format; the remaining pieces are the arguments. Nested commas
#   inside EnumToString(...), ternaries, and commas inside string literals are
#   therefore not miscounted.
#
# USAGE
#   .\check_fmt.ps1                                   # checks Structure.mq5
#   .\check_fmt.ps1 -Path .\SomeOther.mq5
#   Exit code 0 = all OK, 1 = at least one mismatch (so it can gate a build).
#
# NOTE: ASCII only. Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so
#       non-ASCII source here would be mangled into syntax errors.

param(
    [string]$Path = (Join-Path $PSScriptRoot 'Structure.mq5')
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Path)) { Write-Output "check_fmt: file not found: $Path"; exit 1 }

$lines = [System.IO.File]::ReadAllLines($Path)
Write-Output ("check_fmt: {0}  ({1} lines)" -f (Resolve-Path $Path).Path, $lines.Count)

$bad   = 0
$total = 0

for ($n = 0; $n -lt $lines.Count; $n++) {
    if ($lines[$n] -notmatch '(StringFormat|PrintFormat)\(') { continue }

    # collect the whole statement (up to the first line ending in ");")
    $start = $n + 1
    $end   = $start
    while ($end -le $lines.Count -and $lines[$end - 1] -notmatch '\);\s*$') { $end++ }
    $call  = ($lines[($start - 1)..($end - 1)] -join "`n")

    $mi = [regex]::Match($call, '(StringFormat|PrintFormat)\(')
    if (-not $mi.Success) { continue }
    $i = $mi.Index + $mi.Length

    $depth = 0; $inStr = $false; $pieces = @(); $cur = ''
    for (; $i -lt $call.Length; $i++) {
        $ch = $call[$i]
        # MQL5 escapes a quote inside a literal as \" -- must not toggle the state
        if ($inStr -and $ch -eq '\') {
            $cur += $ch
            if ($i + 1 -lt $call.Length) { $i++; $cur += $call[$i] }
            continue
        }
        if ($ch -eq '"') { $inStr = -not $inStr; $cur += $ch; continue }
        if (-not $inStr) {
            if     ($ch -eq '(') { $depth++ }
            elseif ($ch -eq ')') { if ($depth -eq 0) { break } else { $depth-- } }
            elseif ($ch -eq ',' -and $depth -eq 0) { $pieces += $cur; $cur = ''; continue }
        }
        $cur += $ch
    }
    $pieces += $cur

    # piece 0 is the format only (args were split off), so stripping quote chars is safe
    # and (unlike a "..." regex) keeps the text after an escaped \" intact.
    $fmtTxt = $pieces[0] -replace '"', ''
    # specifier: flags + width + precision + conversion, e.g. %s %d %.2f %-26s %04d
    $spec   = ([regex]::Matches($fmtTxt, '%[-+ 0#]*\d*(\.\d+)?[sdifxeEgG]')).Count
    $args   = $pieces.Count - 1
    $total++

    $head = $fmtTxt.Trim()
    if ($head.Length -gt 42) { $head = $head.Substring(0, 42) }

    if ($spec -eq $args) {
        Write-Output ("  ok    L{0,-5} spec={1,-3} args={2,-3}  {3}" -f $start, $spec, $args, $head)
    } else {
        $bad++
        Write-Output ("  BAD   L{0,-5} spec={1,-3} args={2,-3}  {3}" -f $start, $spec, $args, $head)
        Write-Output ("        ^ MISMATCH: {0} specifier(s) vs {1} argument(s)" -f $spec, $args)
    }
}

Write-Output ("RESULT: {0} call(s) checked, {1} mismatch(es)" -f $total, $bad)
if ($bad -gt 0) { exit 1 }
exit 0
