# 只读工具：统计 MQL5 源的 {} 配平，并把注释、字符串、字符字面量排除在外。
# 用法: pwsh -File .bracecheck.ps1 Structure.mq5
param([string]$Path = 'Structure.mq5')

$src  = [System.IO.File]::ReadAllText($Path)
$line = 1
$depth = 0
$minDepth = 0
$inBlock = $false      # 是否在 /* */ 中
$bad = @()

for ($i = 0; $i -lt $src.Length; $i++) {
    $c = $src[$i]
    $n = if ($i + 1 -lt $src.Length) { $src[$i + 1] } else { [char]0 }

    if ($c -eq "`n") { $line++; continue }

    if ($inBlock) {
        if ($c -eq '*' -and $n -eq '/') { $inBlock = $false; $i++ }
        continue
    }
    # 行注释
    if ($c -eq '/' -and $n -eq '/') {
        while ($i -lt $src.Length -and $src[$i] -ne "`n") { $i++ }
        $line++
        continue
    }
    # 块注释
    if ($c -eq '/' -and $n -eq '*') { $inBlock = $true; $i++; continue }
    # 字符/字符串字面量
    if ($c -eq "'" -or $c -eq '"') {
        $q = $c
        $i++
        while ($i -lt $src.Length) {
            if ($src[$i] -eq '\') { $i += 2; continue }
            if ($src[$i] -eq $q) { break }
            if ($src[$i] -eq "`n") { $line++ }
            $i++
        }
        continue
    }

    if ($c -eq '{') { $depth++ }
    elseif ($c -eq '}') {
        $depth--
        if ($depth -lt $minDepth) {
            $minDepth = $depth
            $bad += "line ${line}: depth went to $depth"
        }
    }
}

"final depth = $depth"
"min depth   = $minDepth"
if ($depth -ne 0) { "*** UNBALANCED: $depth unclosed {" }
if ($minDepth -lt 0) { "*** NEGATIVE DEPTH (extra })"; $bad | Select-Object -First 10 }
if ($depth -eq 0 -and $minDepth -ge 0) { "OK: braces balanced" }
