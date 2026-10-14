# Kernel check for ComputeSweeps after the stage-72 tightening.
# User report (2026-09-30): "the place I boxed has bodies breaking through -- that is not a sweep, right?"
# Mirrors the MQL5 predicate on four hand-made cases so the two new rules are demonstrably in effect.
# Sweeping a HIGH at level 100 (level = a tier-1 node's price), scanning forward from the node.
# NOTE: pure ASCII only (PS 5.1 reads BOM-less .ps1 as ANSI).

function Sweep-First([object[]]$bars, [double]$lvl, [bool]$bodyInside, [bool]$stopOnAccept)
{
   for($i = 0; $i -lt $bars.Count; $i++){
      $b = $bars[$i]
      # rule 1 (new): only the WICK may cross -- the body must stay inside (open <= lvl)
      $swept = if($bodyInside){ ($b.h -gt $lvl -and $b.c -lt $lvl -and $b.o -le $lvl) }
               else            { ($b.h -gt $lvl -and $b.c -lt $lvl) }
      if($swept){ return "SWEEP at bar $($i+1)" }
      # rule 2 (new): once a close goes beyond, the level is accepted -> stop scanning
      if($stopOnAccept -and $b.c -gt $lvl){ return "no sweep (level accepted at bar $($i+1))" }
   }
   return "no sweep"
}

$cases = @(
  @{ name = "A  wick above, close+open inside            "
     bars = @(@{o=99.4;h=100.3;l=99.2;c=99.6}, @{o=99.6;h=99.9;l=99.0;c=99.2}) },
  @{ name = "B  open ABOVE (body straddles), close inside"
     bars = @(@{o=100.4;h=100.9;l=99.3;c=99.5}) },
  @{ name = "C  close above first, later poke closes back"
     bars = @(@{o=99.8;h=100.4;l=99.7;c=100.2}, @{o=100.2;h=100.6;l=99.6;c=99.9}) },
  @{ name = "D  wick-only sweep, THEN a close above      "
     bars = @(@{o=99.5;h=100.4;l=99.3;c=99.7}, @{o=99.8;h=100.6;l=99.7;c=100.5}) }
)

foreach($c in $cases){
   $old = Sweep-First $c.bars 100.0 $false $false     # stage <72: close-based only, no early stop
   $new = Sweep-First $c.bars 100.0 $true  $true      # stage 72
   "{0}  OLD: {1,-34}  NEW: {2}" -f $c.name, $old, $new
}
