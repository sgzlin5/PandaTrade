# Kernel check for the node-level BOS/CHoCH layer (stages 69/70).
# Re-implements the decision kernel of ComputeChoch (no MT5 deps) so the candidate rules can be
# compared on ONE synthetic sequence. Purpose: prove the falsifiable claim that the new rules can
# only turn CHoCH into BOS (never invent a break the old rule did not report), and show which rule
# leaves the pullback-high breaks as BOS while still firing CHoCH on a real reversal.
# NOTE: pure ASCII only (PS 5.1 reads BOM-less .ps1 as ANSI).

# Nodes: old -> new, strictly alternating high/low.
$nodes = @(
  @{bar=1;  isHigh=$true;  p=100.0},
  @{bar=3;  isHigh=$false; p=95.0},
  @{bar=5;  isHigh=$true;  p=98.0},   # LH
  @{bar=7;  isHigh=$false; p=93.0},   # LL  -> legitimate flip to DOWN
  @{bar=9;  isHigh=$true;  p=96.0},   # LH
  @{bar=11; isHigh=$false; p=94.0},   # HL (higher than 93)
  @{bar=13; isHigh=$true;  p=97.5},   # HH (higher than 96)
  @{bar=15; isHigh=$false; p=95.5},   # HL
  @{bar=17; isHigh=$true;  p=99.0}    # HH
)

# Bars (high/low/close). Deliberate mix of wick-only sweeps and closing breaks:
#   bar 8  : wick takes 93 (low 92.8) but closes 93.4  -> WICK only
#   bar 10 : wick takes 96 (high 96.3) but closes 95.8 -> WICK only
#   bar 12 : closes above 96 (96.5)                    -> CLOSE break
#   bar 14 : closes above 97.5 (97.8)                  -> CLOSE break
#   bar 16 : wick takes 99 (high 99.2) but closes 95.9 -> WICK only
#   bar 18 : closes above 99 (99.6)                    -> CLOSE break
$bars = @{}
$bars[1]  = @{h=100.2; l=99.0;  c=99.5}
$bars[3]  = @{h=95.5;  l=94.8;  c=95.0}
$bars[5]  = @{h=98.2;  l=97.0;  c=97.5}
$bars[7]  = @{h=93.6;  l=92.7;  c=93.0}
$bars[8]  = @{h=93.9;  l=92.8;  c=93.4}
$bars[9]  = @{h=96.2;  l=93.5;  c=96.0}
$bars[10] = @{h=96.3;  l=95.2;  c=95.8}
$bars[11] = @{h=96.1;  l=94.0;  c=94.3}
$bars[12] = @{h=96.8;  l=94.2;  c=96.5}
$bars[13] = @{h=97.6;  l=96.4;  c=97.5}
$bars[14] = @{h=98.0;  l=97.3;  c=97.8}
$bars[15] = @{h=97.9;  l=95.4;  c=95.6}
$bars[16] = @{h=99.2;  l=95.5;  c=95.9}
$bars[17] = @{h=99.1;  l=95.8;  c=99.0}
$bars[18] = @{h=99.8;  l=99.0;  c=99.6}
for($i=0; $i -le 20; $i++){ if(-not $bars.ContainsKey($i)){ $bars[$i] = @{h=0.0; l=0.0; c=0.0} } }

# mode      : ANY | EXTREME | LEG | RETRACE      (= InpNodeFlipMode)
# useClose  : caliber. true = BREAK_CLOSE, false = BREAK_WICK  (= EffectiveNodeBreak)
# retrPct   : only for RETRACE (= InpNodeFlipRetracePct), percent of the leg to give back
# newLabel  : false = s55 labeling (counter-dir without flip still says CHoCH)
#             true  = s70 labeling (flip => CHoCH, otherwise => BOS(internal))
function Run-Kernel([string]$mode, [bool]$useClose, [double]$retrPct, [bool]$newLabel, [string]$title)
{
   $n = $nodes.Count
   $structDir = if($n -ge 2){ if($nodes[0].isHigh){ -1 } else { 1 } } else { 0 }
   $p = 0; $hiLvl = 0.0; $loLvl = 0.0; $hiBar = -1; $loBar = -1
   $hiDone = $true; $loDone = $true
   $hiPrev = 0.0; $loPrev = 0.0; $hiHasPrev = $false; $loHasPrev = $false
   $legLvl = 0.0; $legExt = 0.0
   if($structDir -eq 1){ $legExt = $bars[1].h } elseif($structDir -eq -1){ $legExt = $bars[1].l }
   $out = New-Object System.Collections.Generic.List[string]
   for($i = 1; $i -le 18; $i++){
      # leg extreme tracks the trend (must happen BEFORE the break test of this bar)
      if($structDir -eq 1  -and $bars[$i].h -gt $legExt){ $legExt = $bars[$i].h }
      if($structDir -eq -1 -and $bars[$i].l -lt $legExt){ $legExt = $bars[$i].l }

      while($p -lt $n -and $nodes[$p].bar -le $i){
         if($nodes[$p].isHigh){
            $hiPrev = $hiLvl; $hiHasPrev = ($hiBar -ge 0)
            $hiLvl = $nodes[$p].p; $hiBar = $nodes[$p].bar; $hiDone = $false
         } else {
            $loPrev = $loLvl; $loHasPrev = ($loBar -ge 0)
            $loLvl = $nodes[$p].p; $loBar = $nodes[$p].bar; $loDone = $false
         }
         $p++
      }

      $b = $bars[$i]
      $brokeHi = if($useClose){ $b.c -gt $hiLvl } else { $b.h -gt $hiLvl }
      $brokeLo = if($useClose){ $b.c -lt $loLvl } else { $b.l -lt $loLvl }

      if($hiBar -ge 0 -and -not $hiDone -and $brokeHi){
         $isBos = ($structDir -eq 1 -or $structDir -eq 0)
         $flip  = $false
         if(-not $isBos){
            switch($mode){
               "ANY"     { $flip = $true }
               "EXTREME" { $flip = ((-not $hiHasPrev) -or ($hiLvl -gt $hiPrev)) }
               "LEG"     { $flip = (($legLvl -le 0.0) -or ($b.c -gt $legLvl)) }
               default   {
                  $progress = if($legLvl -gt 0.0 -and $legExt -gt $legLvl){ $legExt - $legLvl } else { 0.0 }
                  $flip = if($progress -le 0.0){ $true } else { (($legExt - $b.c) -ge ($progress * $retrPct / 100.0)) }
               }
            }
         }
         if($isBos){ $sub = "BOS" } elseif($flip){ $sub = "CHoCH" } elseif($newLabel){ $sub = "BOS(int)" } else { $sub = "CHoCH*" }
         $d = if($structDir -eq 1){ "UP" } elseif($structDir -eq -1){ "DOWN" } else { "0" }
         $out.Add(("bar {0,2}  UP-break of {1,6}  structDir-before={2,-4} -> {3}" -f $i, $hiLvl, $d, $sub))
         $hiDone = $true
         if($flip){ $structDir = 1; $legLvl = if($loBar -ge 0){ $loLvl } else { 0.0 }; $legExt = $b.h }
      } elseif($loBar -ge 0 -and -not $loDone -and $brokeLo){
         $isBos = ($structDir -eq -1 -or $structDir -eq 0)
         $flip  = $false
         if(-not $isBos){
            switch($mode){
               "ANY"     { $flip = $true }
               "EXTREME" { $flip = ((-not $loHasPrev) -or ($loLvl -lt $loPrev)) }
               "LEG"     { $flip = (($legLvl -le 0.0) -or ($b.c -lt $legLvl)) }
               default   {
                  $progress = if($legLvl -gt 0.0 -and $legLvl -gt $legExt){ $legLvl - $legExt } else { 0.0 }
                  $flip = if($progress -le 0.0){ $true } else { (($b.c - $legExt) -ge ($progress * $retrPct / 100.0)) }
               }
            }
         }
         if($isBos){ $sub = "BOS" } elseif($flip){ $sub = "CHoCH" } elseif($newLabel){ $sub = "BOS(int)" } else { $sub = "CHoCH*" }
         $d = if($structDir -eq 1){ "UP" } elseif($structDir -eq -1){ "DOWN" } else { "0" }
         $out.Add(("bar {0,2}  DN-break of {1,6}  structDir-before={2,-4} -> {3}" -f $i, $loLvl, $d, $sub))
         $loDone = $true
         if($flip){ $structDir = -1; $legLvl = if($hiBar -ge 0){ $hiLvl } else { 0.0 }; $legExt = $b.l }
      }
   }
   Write-Output ("=== " + $title + " ===")
   foreach($line in $out){ Write-Output $line }
   Write-Output ""
}

# --- stage 69 table (kept verbatim so plan 69.5 stays valid) --------------------------------
Run-Kernel -mode ANY     -useClose $false -retrPct 50 -newLabel $false -title "s45-s54: WICK + always flip"
Run-Kernel -mode EXTREME -useClose $false -retrPct 50 -newLabel $false -title "s55 gate, WICK caliber"
Run-Kernel -mode ANY     -useClose $true  -retrPct 50 -newLabel $false -title "s55 caliber: CLOSE + always flip"
Run-Kernel -mode EXTREME -useClose $true  -retrPct 50 -newLabel $false -title "s55 as loaded today: CLOSE + new-extreme gate"
# --- stage 70 (this build) ------------------------------------------------------------------
Run-Kernel -mode LEG     -useClose $true  -retrPct 50 -newLabel $true  -title "s70 mode=LEG: flip only past the leg origin"
Run-Kernel -mode RETRACE -useClose $true  -retrPct 50 -newLabel $true  -title "s70 DEFAULT mode=RETRACE 50% of the leg"
Run-Kernel -mode RETRACE -useClose $true  -retrPct 25 -newLabel $true  -title "s70 mode=RETRACE 25% of the leg"
Run-Kernel -mode ANY     -useClose $true  -retrPct 50 -newLabel $true  -title "s70 mode=ANY (control: every counter-break flips)"
