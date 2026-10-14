# Truth-table harness for the node-level "character change" criterion (stage 70 / v1.50-s60).
#
# WHY THIS EXISTS
#   The criterion lives in ONE function in Structure.mq5:
#       NodeFlipChanged(i, isUpBreak, legLvl, legExt, lvl, prev, hasPrev, close)
#   Before s60 it was two helpers (NodeFlipUp / NodeFlipDn) and the CALL SITE picked the
#   helper by the side being broken. That cannot be right, because the three modes mirror
#   in DIFFERENT directions:
#       EXTREME / LEG  compare the side being broken itself   (HH / close past leg origin)
#       RETRACE        measures give-back from the OPPOSITE extreme of the leg
#   Both historical pairings were therefore half-wrong:
#       s58  break-high -> Up helper : EXTREME/LEG right, RETRACE degenerate (always flip)
#       s59  break-high -> Dn helper : RETRACE right, EXTREME inverted and LEG degenerate
#   This script re-implements all three pairings side by side on hand-picked tuples and
#   checks the s60 pairing against the INPUT DOCUMENTATION, so a regression fails loudly.
#
#   It is a DIRECTIONAL comparison tool, NOT evidence about MT5 behaviour: the MT5-side
#   evidence is the CSV + the terminal. (Same caveat as kernel_sim_choch.ps1.)
#
# USAGE
#   pwsh -NoProfile -File kernel_sim_nodeflip.ps1      # exit code 1 = at least one FAIL
#
# NOTE: pure ASCII only (PS 5.1 reads BOM-less .ps1 as ANSI).

$script:RETR_PCT = 50.0
$script:FAILS    = 0
# Per-pairing violation counters, accumulated by Show-Case. Kept script-scoped (not returned)
# because a function's pipeline output would otherwise also capture the report lines and they
# would never reach the console.
$script:V = @{ s58 = 0; s59 = 0; s60 = 0 }

# mode    : ANY | EXTREME | LEG | RETRACE   (= InpNodeFlipMode)
# pairing : s58 | s59 | s60                 (= which helper the call site picked;
#                                             s60 = per-criterion, i.e. the fixed kernel)
function Test-Flip([string]$pairing, [string]$mode, [bool]$isUpBreak,
                   [double]$legLvl, [double]$legExt,
                   [double]$lvl, [double]$prev, [bool]$hasPrev, [double]$c)
{
    # Which historical helper would the call site have used for this side?
    $useUpHelper = $false
    if ($pairing -eq 's58') { $useUpHelper = $isUpBreak }
    if ($pairing -eq 's59') { $useUpHelper = (-not $isUpBreak) }

    # The two comparisons that EXTREME / LEG may use, computed once.
    $extremeUp = ((-not $hasPrev) -or ($lvl -gt $prev))
    $extremeDn = ((-not $hasPrev) -or ($lvl -lt $prev))
    $legUp     = (($legLvl -le 0.0) -or ($c -gt $legLvl))
    $legDn     = (($legLvl -le 0.0) -or ($c -lt $legLvl))

    switch ($mode)
    {
        'ANY' { return $true }
        'EXTREME' {
            if ($pairing -eq 's60') {
                if ($isUpBreak) { return $extremeUp }
                return $extremeDn
            }
            if ($useUpHelper) { return $extremeUp }
            return $extremeDn
        }
        'LEG' {
            if ($pairing -eq 's60') {
                if ($isUpBreak) { return $legUp }
                return $legDn
            }
            if ($useUpHelper) { return $legUp }
            return $legDn
        }
        'RETRACE' {
            # Break-high must measure give-back from the leg LOW  -> "Dn" formula.
            # Break-low  must measure give-back from the leg HIGH -> "Up" formula.
            $useDnFormula = $false
            if ($pairing -eq 's58') { $useDnFormula = (-not $isUpBreak) }
            elseif ($pairing -eq 's59') { $useDnFormula = $isUpBreak }
            else { $useDnFormula = $isUpBreak }

            if ($useDnFormula) {
                $progress = 0.0
                if ($legLvl -gt 0.0 -and $legLvl -gt $legExt) { $progress = $legLvl - $legExt }
                if ($progress -le 0.0) { return $true }        # cannot measure the leg -> no gate
                return (($c - $legExt) -ge ($progress * $script:RETR_PCT / 100.0))
            }
            $progress2 = 0.0
            if ($legLvl -gt 0.0 -and $legExt -gt $legLvl) { $progress2 = $legExt - $legLvl }
            if ($progress2 -le 0.0) { return $true }
            return (($legExt - $c) -ge ($progress2 * $script:RETR_PCT / 100.0))
        }
    }
    return $false
}

function Show-Case([string]$title, [bool]$isUpBreak,
                   [double]$legLvl, [double]$legExt,
                   [double]$lvl, [double]$prev, [bool]$hasPrev, [double]$c,
                   [hashtable]$expect)
{
    Write-Output ("== " + $title + " ==")
    Write-Output ("   isUpBreak={0}  legLvl={1}  legExt={2}  lvl={3}  prev={4}  hasPrev={5}  close={6}" -f `
                  $isUpBreak, $legLvl, $legExt, $lvl, $prev, $hasPrev, $c)

    $pairings = @('s58', 's59', 's60')
    Write-Output ("   {0,-8} {1,-7} {2,-7} {3,-7} {4,-9} {5}" -f 'mode', 's58', 's59', 's60', 'expected', 'verdict')

    $viol = @{ s58 = 0; s59 = 0; s60 = 0 }
    foreach ($m in @('ANY', 'EXTREME', 'LEG', 'RETRACE'))
    {
        $exp = 'no'
        if ($expect[$m]) { $exp = 'flip' }
        $cells = @()
        foreach ($p in $pairings)
        {
            $f = Test-Flip -pairing $p -mode $m -isUpBreak $isUpBreak -legLvl $legLvl `
                           -legExt $legExt -lvl $lvl -prev $prev -hasPrev $hasPrev -c $c
            $t = 'no'
            if ($f) { $t = 'flip' }
            $cells += $t
            if ($t -ne $exp) { $viol[$p] = $viol[$p] + 1 }
        }
        $verdict = 'FAIL'
        if ($cells[2] -eq $exp) { $verdict = 'PASS' }
        if ($verdict -eq 'FAIL') { $script:FAILS = $script:FAILS + 1 }
        Write-Output ("   {0,-8} {1,-7} {2,-7} {3,-7} {4,-9} {5}" -f `
                      $m, $cells[0], $cells[1], $cells[2], $exp, $verdict)
    }
    Write-Output ("   violations vs the documentation:  s58={0}  s59={1}  s60={2}" -f `
                  $viol['s58'], $viol['s59'], $viol['s60'])
    Write-Output ""
    $script:V['s58'] = $script:V['s58'] + $viol['s58']
    $script:V['s59'] = $script:V['s59'] + $viol['s59']
    $script:V['s60'] = $script:V['s60'] + $viol['s60']
}

# Run one case in BOTH orientations. Mirroring x -> (legLvl + legExt) - x swaps the roles of
# leg start / leg extreme and of high/low, so the expectations are identical by construction:
# if a pairing is wrong on the up-break side it must be wrong on the mirrored down-break side.
function Show-MirroredCase([string]$title, [double]$legLvl, [double]$legExt,
                           [double]$lvl, [double]$prev, [bool]$hasPrev, [double]$c,
                           [hashtable]$expect)
{
    Show-Case ("$title  [up-break / down-leg]") $true $legLvl $legExt $lvl $prev $hasPrev $c $expect
    $M = $legLvl + $legExt
    Show-Case ("$title  [dn-break / up-leg, mirrored]") $false ($M - $legLvl) ($M - $legExt) `
              ($M - $lvl) ($M - $prev) $hasPrev ($M - $c) $expect
}

Write-Output "Structure -- NodeFlipChanged truth table (retrace pct = $($script:RETR_PCT))"
Write-Output "expected column = what the INPUT DOCUMENTATION says the mode means"
Write-Output ""

# Case A: the user's M1 symptom. A deep down-leg, price breaks a LOWER high (LH) with only a
# small give-back off the leg low, and the close is still well below the leg origin (the high
# that started the leg). Nothing about the character of the trend has changed -> BOS(internal).
$expA = @{ ANY = $true; EXTREME = $false; LEG = $false; RETRACE = $false }
Show-MirroredCase "A: deep leg, LH below prev, give-back 3.5 of 12.0 (29%)" `
                  100.0 88.0 91.0 93.0 $true 91.5 $expA

# Case B: a genuine reversal. Price breaks a HIGHER high, closes past the leg origin and has
# given back more than half the leg -> every mode must say "character changed".
$expB = @{ ANY = $true; EXTREME = $true; LEG = $true; RETRACE = $true }
Show-MirroredCase "B: HH above prev, close past leg origin, give-back 13.0 of 12.0" `
                  100.0 88.0 100.0 93.0 $true 101.0 $expB

# Case C: only one node of this type in the window -> hasPrev=false. Documented behaviour:
# EXTREME cannot compare, so it ALLOWS the flip; LEG/RETRACE still say no.
$expC = @{ ANY = $true; EXTREME = $true; LEG = $false; RETRACE = $false }
Show-MirroredCase "C: hasPrev=false (only node of this type in window)" `
                  100.0 88.0 91.0 0.0 $false 91.5 $expC

Write-Output "======================================================================"
Write-Output ("violations per pairing   s58={0}   s59={1}   s60={2}" -f `
              $script:V['s58'], $script:V['s59'], $script:V['s60'])
Write-Output ""
Write-Output "Interpretation:"
Write-Output "  s58 must violate RETRACE only (its progress term is always 0 on the break-high"
Write-Output "      side, so RETRACE == ANY there) -- that is defect C1 of the 2nd review round."
Write-Output "  s59 must violate EXTREME and LEG (their comparisons come from the wrong helper,"
Write-Output "      so EXTREME is inverted and LEG is trivially true inside the leg) -- defect R2."
Write-Output "  s60 (this build) must violate nothing: NodeFlipChanged picks the side per mode."
Write-Output ""

$metaBad = 0
if ($script:V['s58'] -lt 1) { $metaBad++ ; Write-Output "META FAIL: s58 column does not reproduce defect C1" }
if ($script:V['s59'] -lt 1) { $metaBad++ ; Write-Output "META FAIL: s59 column does not reproduce defect R2" }
$s60bad = $script:V['s60']
if ($s60bad -ne 0) { $metaBad++ ; Write-Output "META FAIL: s60 column violates the documentation" }

if ($script:FAILS -gt 0) { Write-Output ("RESULT: FAIL ({0} s60 verdict mismatch(es))" -f $script:FAILS); exit 1 }
if ($metaBad -gt 0)      { Write-Output "RESULT: FAIL (meta assertions)"; exit 1 }
Write-Output "RESULT: PASS (s60 matches the documentation on every case; s58/s59 reproduce C1/R2)"
exit 0
