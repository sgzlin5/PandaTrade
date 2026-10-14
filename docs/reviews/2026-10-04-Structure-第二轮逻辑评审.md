# TradFi_Structure 第二轮逻辑评审（`v1.50-s58`）

- 评审对象：`Indictor/TradFi_Structure.mq5`
- 基线：`v1.50-s58`，5988 行，355627 字节，
  SHA-256 `A7043CD60BFA03BA151C061AF178654F073FC136CDBEE935278A38042778E33D`，
  工作区 = `git a5d8cf3`（无未提交改动）
- 评审日期：2026-10-04
- 与前一轮的关系：上一轮（`docs/reviews/2026-09-30-...-缺陷评审.md`）按**函数逐个判**，
  已修 13 项（`v1.50-s57` → `v1.50-s58`）。本轮**刻意换角度**，按跨函数不变式、
  状态污染、路径可达性与平台语义来查，并明确排除上一轮已修/已判定的项，避免重复。

## 评审方法

五个域并行独立审查，各自「先读代码再下结论」，每条发现必须给出
**行号 + 代码原文 + 可达性触发条件 + 严重度 + 最小修法**：

| 域 | 范围 |
|---|---|
| A | 数组方向 / 索引 / 窗口边界 / 输入解析 |
| B | 结构状态机与参考位追踪（bias / 节点 / protected / MSS-BOS 转换） |
| C | 事件语义 / 去重 / 置信闸门（8 类事件与可见性门控） |
| D | 快路径 / 缓存 / `needDraw` 指纹 / 场景集 / 对象生命周期 |
| E | 平台语义与生命周期（历史预加载 / `prev_calculated` / 多实例 / 图表状态还原） |

---

## 结论摘要

**共发现 27 条真缺陷，全部处置完毕：23 条修复 + 1 条加对账日志待实测定案 + 1 条仅文档警示 + 2 条经复核判定为非缺陷未采纳。**

其中 **3 条是我自己前几轮改动引入的**（s58 误删 `ArraySetAsSeries(open, true)`；s59 扩写早退块时留下重复的死检查；
s59 只复位了一半 HTF 缓存），另有 **1 条是我在本轮修复过程中引入、又被审查者抓回的严重回归**（见文末"我引入的错误"）。

**最重的一条是 C1**：默认档 `NODEFLIP_RETRACE` 因 helper 方向接反而**完全失效**，
所有逆势节点破位都被标成 CHoCH —— 这正是文件注释里记录的用户症状"加载 s55 后仍是 CHoCH"的同一根因。

### 按你裁定的处置（本轮第二批）

| 项 | 你的决定 | 落地 |
|---|---|---|
| 同图双实例互删 | 暂不加实例后缀，只写文档警示 | 文件头加了明文的"多实例限制"段（含"跨图表多实例是安全的"），CSV 自描述头加 `instance-note:` 行使归档可归属 |
| 右侧留白槽宽 | 先加对账日志、用实测定案 | `HtfLogSlot` 扩为 6 参：新增 `marginBars` / `rowPx`（整排像素宽）/ `edgePx`（整排右端映射到屏幕的 x）/ `chartW`，并直接输出 `fits` / `OVERFLOW: row exceeds chart width` / `PIXEL-PATH-UNAVAILABLE` 三态结论。**判据**：放置端把最右那根画在 `tBase + ps + n*slot`，故整排宽 = `ps + n*slot` = `pxPerBar + n*slotPx`，可用宽 = `marginPx` |
| CLOSURE 未收盘判定 | 改成只用已收盘 bar | 守卫 `b < 1` → `b < 3`（C1..C4 全为已收盘）。代价：最新 1 个节点的 closure 延后一根 bar 出现 |

另外本轮还修掉了两条此前列为"待裁定"的：**C7 同 bar 双破的落选侧**（两侧现在都会把对方标为已消耗，
杜绝了 `bar` 指向后一根的虚假时序 MSS）与 **B4 `ref.touched` 生命周期收口**（`AddNodeFiltered`
的同类型替换 `:2402`/`:2420` 现在会清闩锁——这是此前唯一漏掉的写点）。

上一轮（s58）修的是"单函数内看得见的错"；本轮真正有收成的是**跨函数/跨帧的状态与语义**：

| 编号 | 缺陷 | 域 | 严重度 | 状态 |
|---|---|---|---|---|
| A1 | `ref.touched` 闩锁吞掉**强** MSS → 引擎层与节点层结论打架 | B | 高 | **已修** |
| A2 | 图表底色不在 `needDraw` 指纹 → 换主题后 FVG/HTF 混色**永久不刷新** | D+E 双方独立命中 | 中高 | **已修** |
| A3 | `ComputeStructure` 早退不清派生全局 → 本帧拿旧价调和、日志自相矛盾 | E | 中 | **已修** |
| A4 | 快路径 HTF 缓存只复位一半，注释高估了 `moved` 的作用 | D | 中 | **已修** |
| A5 | `DumpRectObjects` 的 `static` 跨 `OnInit` 存活 → 改参数后诊断永久沉默 | E | 中低 | **已修** |
| A6 | `Shift+D` 无条件绕过 `InpDumpEvents` → 误按一下**覆盖**你的归档 | E | 中低 | **已修** |
| B1 | 右侧留白槽宽：像素路径与兜底公式对"多出的一个 `ps`"扣减约定相反 | D | 中 | **已加对账日志**（待你实测后定案） |
| B2 | 同图表两实例互相删对象 + 共用全局（跨图表多实例是安全的） | D+E 双方独立命中 | 中 | **已文档警示**（按裁定不加强制） |
| B3 | 同 bar 双破时被丢弃那一侧造成当根零事件 | B | 中低 | **同根因已修**（重复事件已消除；"当根零事件"本身未单独验证） |
| B4 | `ref.touched` 不在参考位生命周期写点上复位 | B | 低 | **已修**（与 A1 同族） |
| A7 | **`open[]` 未锁时序方向**（s58 我误删） | A | 中 | **已修** |
| A8 | `InpAnalysisWindow` 设 1/2 ⇒ 结构检测**静默全灭** | A | 中 | **已修** |
| A9 | `OnInit` 不复位指纹 ⇒ 改颜色/线型要等下一根 bar | A | 中 | **已修** |
| A10 | `InpBiasLookback` 负值 ⇒ 偏置链静默关闭 | A | 低 | **已修** |
| A11 | `nValid < 3` 检查被 s59 复制成两份，第二份死代码（**我引入**） | A | 低 | **已修** |
| A12 | `time[b]` 求值在显示开关**之前**（关掉显示仍索引） | A | 低 | **已修** |
| A13 | `DbgReport` 无条件读 `time[1]`（靠两步间接保证安全） | A | 低 | **已修** |
| C1 | **默认档 `NODEFLIP_RETRACE` 是空操作 ⇒ 所有逆势破位都成 CHoCH** | C | **最高** | **已修** |
| C2 | 最新那段内包盒永远不入列 ⇒ 画出的是上一段 | C | 中 | **已修** |
| C3 | `nSWEEP`/`nClosure` 不在集中复位块 ⇒ 假不变量警报 + CSV 自相矛盾 | C | 中 | **已修** |
| C4 | `CalcATRSeries` 种子只写最旧一根 ⇒ 该区段 ATR 门槛系统偏松 | C | 低 | **已修** |
| C5 | CLOSURE 对未收盘 bar 下判（单 tick 判决） | C | 中低 | **已修**（按裁定：只用已收盘 bar） |
| C7 | 同 bar 双破"落选侧"不被消耗 ⇒ 虚假时序 MSS（= B3 同根因） | C | 中 | **已修** |

> **C1 是本轮最重的一条**，也是唯一一条会让你**当前屏幕上的标签整体变化**的修复：
> 一批原本显示 CHoCH 的位置会变成 BOS / 内部 BOS。这不是回归 —— 是默认档**第一次真正生效**
> （`InpNodeFlipRetracePct` 在此之前是完全无效的哑输入）。修完建议重新导一份 CSV 基线。

## 数据方向 / 输入校验域（域 A）的补充修复

### A7 — `open[]` 未锁时序方向（**我 s58 误删的**）

`OnCalculate` 里只锁了 4 个价格数组，`open` 漏了；而 `open[]` 全程按时序索引，
且**总是与 `close[]` 成对**出现在同一表达式里：

```c
// :2737-2738   CisdOriginBar 的实体方向判定
bool dirOk = isHigh ? (close[extremeBar] > open[extremeBar]) : (close[extremeBar] < open[extremeBar]);
// :2593 / :2594    BREAK_BODY 的实体两端判定
MathMin(open[i], close[i]) > level   /   MathMax(open[i], close[i]) < level
// :3371-3372   BiasAtTime
open[i] <= lvl   /   open[i] >= lvl
```

若方向错位，`CisdOriginBar` 的 `dirOk` 为假 → 返回 −1 → `CisdSetLevel` 直接放弃该侧 CISD 位
⇒ 该极值上**不再有 CISD、不再派生 OB、不再建立 protected swing**，而图上/CSV/日志**一处错都不报**，
只是"少了一批事件"——最难发现的那类失败。

**为什么必须修**：不是因为我证明了今天就是错的（`open` 与 `high/low/close` 出自同一次
timeseries 访问，MQL5 很可能共享 series 标志，即今天**恰好**是对的），而是因为
**仓库自己的纪律不允许这种依赖** —— 文件头 `:41` 明写
"【致命】OnCalculate 入口显式 `ArraySetAsSeries(x,true)` / 凡涉及数组方向的代码，一律显式
`ArraySetAsSeries`，不要依赖默认值"，而 s58 那次提交在写下这条纪律的**同时**删掉了 `open` 的调用
（提交信息："删除死调用 `ArraySetAsSeries(open, true)`"）。`ComputeRelevance` 的局部数组确实有
"方向无关"的显式豁免注释，`open` **没有**。补回是零成本的。

### A8 — `InpAnalysisWindow` 完全没有校验

```c
if(InpAnalysisWindow > 0 && InpAnalysisWindow < rates_total)
   analysisStart = InpAnalysisWindow - 1;      // 设 1 ⇒ 0；设 2 ⇒ 1
```
`analysisStart = 0` 时 `for(int i = analysisStart - 1; i >= 0; i--)` **一次都不执行**
⇒ `nValid` 恒为 1 ⇒ 命中 `nValid < 3` 早退 ⇒ **零 MSS/BOS/CISD/FVG/OB/SWEEP/CHoCH/CLOSURE**，
图上什么都不画，且**不报任何错**。默认 500 下不可达，但 `0`（全量）与负数在 `OnInit` 里都是合法值，
而 `1`/`2` 恰恰是唯一会炸掉一切的两个值 —— 文件里其它同类参数（`InpWindow >= 2`、`InpATRPeriod >= 2`、
`InpCandleCount`、`InpIcLatePercent`）都有下界校验，唯独漏了这个**直接决定"分析几根 bar"**的量。

### A9 — `OnInit` 不复位 `needDraw` 指纹

`needDraw` 是"**变化**检测器"而非"有效性检测器"，而它比较的指纹全局**跨 `OnDeinit`/`OnInit` 存活**，
`OnInit` 原本只清了 `g_lastRates`。于是：改 `InpColorMSS` 之类的**标量**输入 → `OnInit` →
首个全量帧（`g_lastRates=0` ⇒ `firstRun`）跑了 `ComputeStructure`，但事件集合没变
⇒ 整条 `||` 链为假 ⇒ **绘制块被跳过 ⇒ 图上仍是旧颜色**，要等到下一根 bar 才纠正。

这与 s59 刚给指纹加的 `bgNow != g_lastBgClr` 是**完全同类**的理由：
底色"不触发 `OnInit` 却不在指纹里"，而输入本身恰恰是"触发 `OnInit` 却不在指纹里"。
修法：`OnInit` 里 `g_lastT0 = 0`（`time[0]` 恒 > 0，使首个全量帧指纹必真）＋ `g_lastBgClr = -1`。

### A10–A13 — 三条低危与一条我自己的死代码

| 项 | 说明 |
|---|---|
| A10 `InpBiasLookback` 未校验 | 负值 ⇒ `BiasAtTime` 循环体不执行 ⇒ **恒返回 0** ⇒ ERL/IRL/AutoTargets/Fib 投影与事件弱化分级**全部静默消失**（`biasC != 0` 恒假）。已加 `>= 1` 校验 |
| A11 `nValid < 3` 两份（**我 s59 引入**） | 我扩写早退块后没删原单行版 ⇒ 第二份**恒不可达**的死代码，会让下一个读代码的人以为这里还有一条独立早退通路。已删 |
| A12 `time[b]` 在开关之前求值 | `if(time[b] < tStart \|\| !InpShowMSS)`（MSS/BOS 两处）⇒ 关掉显示**不会**变便宜，照样索引。今天不越界（`b` 恒在窗口内），但它是全文件唯一一处"把数组索引放在开关之前"的地方。已换序 |
| A13 `DbgReport` 无条件读 `time[1]` | 守卫是 `nN > 0`，而安全靠**两步间接**：`nN > 0` ⟹ 越过 `nValid < 3` ⟹ 至少 3 根有效 bar ⟹ `rates_total >= 4`。把那个下界从 3 改成 1、或新增一个调用点，立刻变成越界读。已改为 `rates_total > 1 ? … : ""` |

另有 4 条低危/文档级与 3 条 UNPROVEN，列在末尾。

---

## 已修复（`v1.50-s59`）

### A1 — `ref.touched` 一次性闩锁吞掉强 MSS

```c
// 修复前（s58 及以前），:2863
if(!strong && ref.touched) return 0;          // 已记录过弱触发 → 静默，等强触发
AddMSSResult(i, dir, ref, st.state, strong);
if(!strong) { ref.touched = true; return 0; }
```

一句话概括两条语义，于是"弱触发不许重复记录"把"**强触发必须记录**"也一起吞了。

**可证性**：写 `touched=true` 的那根 bar 必然落在 `DisplacedBeyond`（`:2658-2667`）的时效窗口
`[i+N, anchorBar-1]` 内 —— 若它落在窗口外，同一个条件会让 `strong=true`。故闩锁置位后，
**只要仍有影线在窗口里穿越**，该位每根 bar 都恒 `strong=false`。清除点只有
`SetProtectedFromCisd`（需对侧出现新极值节点）。

**⚠️ 我下调了子代理给的严重度**：它报 FATAL 并称"永久吞掉"。实际一旦跨越 bar 的影线退出时效窗口，
强触发仍能记录，所以不是永久，而是"闩锁后的 `InpDisplaceMaxBars` 根内失效"。
但**真实后果仍然严重**：节点层 `ComputeChoch` 不读 `ref`（自带口径），同一位上照旧显示节点级 BOS
⇒ 引擎层与节点层对同一根 bar 给出相反结论；叠加 `InpHideWeakBreaks` 默认 `true`，用户屏幕上
既看不到弱线、也等不到引擎级 MSS。

**修法**：按注释自己的意图（"弱触发只记**首次**，不消耗该位"）拆开两条语义 —— 强触发无条件记录，
只有弱触发受闩锁约束。

### A2 — 图表底色未进 `needDraw` 指纹

所有 PD/HTF 填充色都由**图表实际底色**混出：`PdFill(InpColorFVG, bgClr, …)`（`:5085+`）。
而底色既不是输入项、也不在指纹（`:4993-5029`）里 ⇒ 改主题/换模板**不触发 `OnInit`** ⇒ 指纹全等
⇒ 本帧 `needDraw=false`，整块重画被跳过，色块继续用旧底色混色，直到下一根 bar 或一次缩放。
`OnChartEvent` 的 `CHART_CHANGE` 分支（`:1836`）又要求 `InpShowHTFCandles && HTF_PLACE_RIGHT` 才处理，
绝大多数配置下直接返回，使自愈更不可靠。**M15 图上最多 15 分钟、D1 图上约一天才纠正。**

**这条是域 D 与域 E 两个互不通气的审查者从不同入口独立命中的**，可信度高。
修法：每帧无条件读一次底色，纳入指纹并在指纹同步块更新缓存。

> 附注：`audit_state.ps1` 结构上抓不到这一类 —— 它只用正则扫 `RenderScene` 函数体文本里的
> `g_*`；而底色是"检查前捕获进局部变量的 `ChartGetInteger` 调用"，且 `DrawHtfCandleGeom` 内的那次
> 在**被调用函数**里。这是该工具的第 5 个盲区（前 4 个是已豁免项）。

### A3 — 早退后 `RenderScene` 仍用陈旧全局

`ComputeStructure` 在 `nValid < 3` 时早退（`:3826`），但 `OnCalculate` 仍**无条件**调用 `RenderScene`。
于是 `g_relValid/g_erlValid/g_irlValid/g_pdValid/g_tgtCount/g_fibValid/g_curBias` 全是上一帧的值，
本帧用旧价位调和出的对象紧接着被同帧回收段删掉，而 `TradFi_RENDER`/`TradFi_DBG` 会打出
`nodes=0` 却 `tgtCount>0`、`fibValid=1` —— **恰好毁掉你们用来判定"功能是否在跑"的那两行**。
触发很常见：图表刚加载、`rates_total` 刚过 4 时 `nValid` 必然 <3。
修法：早退前把这些派生全局一并清零。

### A4 — 快路径 HTF 缓存只复位一半

全量帧末尾只清 `g_htfC0T0/g_htfC0T1`（令快路径下一 tick 必刷），`g_htfC0O/H/L/C` 留着**全量帧之前**的旧值。
今天无害，但原因不是注释说的那条：早退实际只由 `T0/T1` 那一句兜着，而 s58 的注释把 `moved`
描述成"修好了'只变了 open 被静默吞掉'"的判据 —— 每个全量帧后的第一个 tick 上它是失效的。
言过其实的注释比没有注释更危险：下一个人会把 `T0/T1` 当冗余删掉，然后它**立刻变成真 bug**。
修法：整组 OHLC 一并复位。

### A5 — 一次性诊断的 `static` 跨 `OnInit` 存活

`DumpRectObjects` 用函数内 `static bool s_done`（原 `:1310`），注释写"每次加载只报一次"，
但 MQL5 的 `static` 在同一图表跨 `REASON_PARAMETERS`/`CHARTCHANGE`/`TEMPLATE` **保留**。
后果：改任一输入项/切周期后，用户按既定流程查 `TradFi_OBJDUMP` 什么都看不到 ——
与"对象没画出来"不可分辨。文件自己在 `:914` 刚记录过这条教训（s58 的 `s_lastRates`）。
修法：改全局 `g_objDumped` + `OnInit` 清零。

### A6 — 热键无条件绕过 `InpDumpEvents`

`DumpEventsNow` 原以 `force=true` 调用 `DumpEvents`，注释还明确写着"热键路径必须显式 force 绕过"。
但 `InpHotkeys` 默认 `true`，于是**任何**图表上误按一下 `Shift+D` 就落盘，
而文件名固定（`:964`"同品种同周期 → 每次覆盖"）⇒ **一次误按覆盖掉你先前 `InpDumpEvents=true` 的归档**。
而 `:963` 的注释承诺"仅 `InpDumpEvents=true` 时写文件，默认关 → 常态零成本"。
修法：热键同样受门控，被挡住时打一行可分辨日志（保住"可取证"，又不产生意外文件）。

---

## 曾列入待裁定 — 本轮已全部按你的裁定处置

### B1 — 右侧留白槽宽的两条路径扣减约定相反（**已加对账日志，待你实测后定案**）

同一函数的两条路径服务同一个量（"每个 HTF 槽多少秒"）：

| 路径 | 代码 | 扣减 |
|---|---|---|
| ① 像素实测（**主路径**） | `:4583` `marginPx = w - (x0 + pxPerBar)` | 扣 1 bar |
| ② 兜底公式 | `:4602` `marginBars = vis*sh/(100-sh) - 1.0` | 扣 1 bar |
| 放置端（两条都走） | `:4715` `t1 = tBase + ps + (n-1-k)*slot` | 又多出 `ps` |

放置端从 `tBase + ps` 起、跨 n 个槽，所以留白宽度里**必须**扣掉那一个 `ps`。
两条路径都"看起来"扣了 1 bar，但像素路径的 `marginPx` 自身已经减掉了 `pxPerBar`，
却仍被放置端再加一个 `ps` —— 两条路径对同一个量的约定**必有一条错**。

**但我不能证实哪条错、也证不出可见症状**：`ChartTimePriceToXY` 给回的 `x0` 是 bar 中心还是右缘，
是唯一无法从文本确定的量。故此项标 **方向已证、量级未证**，改它属于"可能修好也可能改坏"。

**已按你的裁定落地（对账日志）**：`HtfLogSlot` 从 3 参扩为 6 参，新增 `marginBars` / `rowWidthPx` /
`chartEdgePx` 三个入参，并直接输出结论串：

```
STRUCT_HTFPOS slot=…s candles=… src=… pxPerBar=… marginPx=… slotPx=…
             shiftOn=… shiftSize=… visBars=… | marginBars=… rowPx=… chartW=… edgePx=… <结论>
```

**判据（这是定案的根据，不是猜测）**：放置端把最右那根画在
`tBase + ps + (n-1-k)*slot + slot` ⇒ 整排右端 = `tBase + ps + n*slot`
⇒ **整排像素宽 = `ps + n*slot` = `pxPerBar + n*slotPx`**（因为 `slotPx = marginPx/n/pxPerBar*ps`
⇒ `n*slotPx = marginPx*ps/pxPerBar`）。可用宽是 `marginPx`。所以：
**`edgePx > chartW` ⇒ 像素路径多扣了那一个 `ps`（即 `marginPx` 不该再减 `pxPerBar`）；
`edgePx <= chartW` ⇒ 像素路径正确、错的是兜底公式。** 日志末列会直接给出
`fits` / `OVERFLOW: row exceeds chart width` / `PIXEL-PATH-UNAVAILABLE` 三态。

顺带修掉了这条路径上的一个同族隐患：`HtfLogSlot` 的节流缓存原是**函数内 `static`**
（跨 `OnDeinit`/`OnInit` 存活），改留白设置后不会再打日志 —— 与 `DumpRectObjects` 的 `s_done`、
`g_lastRates` 是同一类陷阱，已改为全局并在 `OnInit` 复位。

### B2 — 同图表两实例互相删对象 + 共用全局（**按裁定：仅文档警示**）

对象名只编码 bar 下标（`Seg_<b1>_<b2>`、`MSS_<refBar>_<bar>`…），**不含实例身份**；
回收段枚举**整图表**带前缀的对象、以本实例的场景集为判据（`:5799-5803`），
`OnDeinit` 又是 `ObjectsDeleteAll(0, OBJ_PREFIX)`（`:1730`）。⇒ 同图两实例会互删，摘掉一个会清掉另一个整幅图。
更隐蔽的一层：两实例**共用同一份模块全局**（`g_lastRates`/`g_lastT0`/`g_lastNodes`…），
"是否新 bar"在同一张图上只被判一次 —— s58 那处修复针对的是**换品种/参数**的身份，不是**同图双实例**。

**⚠️ 范围要说清**：**跨图表**多实例（同品种不同周期，你说的"多张图各挂一份"）是**安全**的 ——
图表各有独立对象命名空间与独立模块实例，结构上不可能互相影响。所以这条只在你**把指标挂两次到同一张图**时成立。

**另外**：同图两实例 + `InpDumpEvents=true` 时 CSV 也会互相覆盖（文件名只由 符号+周期 决定），归档不可归属。

**已按你的裁定落地（仅文档警示，不在代码里强制）**：
① 文件头加了明文的"⚠️ 多实例限制"段，写清"同图挂两份 = 不支持"及其三条机理，
并**明确指出跨图表多实例是安全的**；
② CSV 自描述头加 `# instance-note: one file per symbol+period; …` 一行，
使归档文件可归属（避免将来拿到一份 CSV 却不知道它代表哪个实例）。

**没有加实例后缀**的理由按你的判断执行：那会让所有对象改名，现有图表上的对象需重挂才干净，
而"同图挂两份"并不是正常用法 —— 风险与代价不成比例。

### B3 — 同 bar 双破时被丢弃那一侧造成当根零事件（**同根因已修**）

`:2896-2909` 外包 K 线收阴时只走 `ApplyMssTransition(DIR_DOWN, st.refLow, …)`；
它返回 0（未过位移门槛）时**什么都不记录**，而该 bar 的 `upBroken` 同样为真却被整支丢弃
⇒ 既无 `BOS(up)` 也无 `MSS(down)`。

本轮随 C7 一并处置了**同一个根因**：落选侧现在会被标记为已消耗（见 C7），
"重复/迟到的 MSS"这一条已消除。**但"当根零事件"本身（两条路径都不记录任何事件）没有单独改** ——
它需要"双破时该报哪个"的口径决定，而那会改事件集合。此处**如实标注为未单独验证**，
不声称已修完。

### B4 — `ref.touched` 不在参考位生命周期写点上复位（**已修**）

原状：`touched` 只在"参考位被**新建**"时复位，其余生命周期写点全都不写：
失效对侧（旧 `:2871-2880`）只写 `valid`，`AddNodeFiltered` 的同类型替换（旧 `:2344-2348`/`:2361-2365`）
只写 `bar`/`price`。⇒ 同一个 `(bar, price)` 可以带着闩锁"复活"，使 A1 那类问题无法靠"位被换掉"自愈。

**已收口到全部 10 个写点**（`grep ref(High|Low)\.touched = false` 可复核）：

| 类别 | 位置 |
|---|---|
| 同类型替换（**本轮新补**） | `:2423` / `:2441` |
| 强破后失效对侧（**本轮新补**） | `:2970` / `:2976` |
| 参考位新建 | `:2865` / `:2873`（`SetProtectedFromCisd`）、`:4096` / `:4106`（种子） |
| 状态初始化 | `:3956` / `:3961` |

即：**失效即清闩锁**——同一个 `(bar, price)` 不得带闩锁复活。

---

## 事件语义 / 去重 / 置信域（域 C）——本轮最重的一条在这里

### C1 — 默认档 `NODEFLIP_RETRACE` 是**空操作** ⇒ 所有逆势破位都成 CHoCH

这条比 A1 更严重：它不是"某个分支走错"，而是**用户当前看到的标签整体是错的**。

```c
// NodeFlipUp  :3184      回吐判据
const double progress = (legLvl > 0.0 && legExt > legLvl) ? (legExt - legLvl) : 0.0;
if(progress <= 0.0) return true;      // 量不出腿长 ⇒ 不设门槛
// NodeFlipDn  :3200      镜像
const double progress = (legLvl > 0.0 && legLvl > legExt) ? (legLvl - legExt) : 0.0;
// 调用点（修前）
bool flipH = isBosH ? false : NodeFlipUp(i, legLvl, legExt, hiLvl, …);   // 破高点
bool flipL = isBosL ? false : NodeFlipDn(i, legLvl, legExt, loLvl, …);   // 破低点
```

**两行闭合的证明**：`NodeFlipUp` 只在 `structDir == DIR_DOWN` 时被求值（`isBosH` 为真时直接 `false`）。
而 DOWN 腿下 `legLvl` 被写成**腿起点的高点**（`:3313` 翻转时 `legLvl = hiLvl`），`legExt` 被写成
`low[i]`（`:3314`）且之后每根只按多头腿方向**往更低**更新（`:3283`）⇒ 恒有 `legExt <= legLvl`
⇒ `progress ≡ 0` ⇒ `:3185` 恒 `return true`。

于是 **`NODEFLIP_RETRACE` 行为等价于 `NODEFLIP_ANY`**：任何逆势破位都被判"改性格"= CHoCH，
`InpNodeFlipRetracePct`（默认 50%）是**哑输入**，CSV 头部 `nodeFlip=RETRACE` 是对行为的失实标签。
`NODEFLIP_LEG`/`NODEFLIP_EXTREME` 两档是有效的，**只有默认档坏**。

这正是文件注释 `:3127-3133` 自己记录的用户症状——"加载了 s55 之后那两处仍是 CHoCH"——
**同一个根因，s55→s70 那次修正实际没生效**。

**修法**：按"破哪一侧"配对 helper（破高点用 `NodeFlipDn`，它量的是自最低点的回补；破低点用 `NodeFlipUp`）。
修完 `progress` 在两侧都成立，默认档恢复语义。

> ⚠️ **这条修完你图上的标签会变**（一批原显示 CHoCH 的会变成 BOS 或"内部 BOS"）。
> 这不是回归，是默认档**第一次真正生效**。建议重新导一份 CSV 基线。

### C2 — 最新那段内包盒永远不入列

`AddBoxResult` 只在"遇到新母线"分支里调用（`:3873`），而**循环退出时仍挂着的内包段**
（= 最新母线之后的整串内包，也就是**当前这段盘整**，右端常态）被静默丢弃
⇒ 屏幕上那条盒**永远是上一段**，`nBox` 恒少 1。修法：循环后补 flush（已加在 `:3883`）。

### C3–C6 — 计数复位缺口、ATR 种子、CLOSURE 口径

| 项 | 说明 |
|---|---|
| **C3** `nSWEEP`/`nClosure` 不在集中复位块 | 这两个只在各自计算函数首行自复位，而那两个函数在"有效 bar 不足"的早退路径上**根本不会被调用** ⇒ 该帧这两个计数保留上一帧旧值、其余 8 个已清零。后果：`DbgReport` 的无条件不变量检查打出 `closure=59 > nodes=0` 的**假警报**——而这条不变量正是本文件认定"跨帧累加 bug"的**唯一现场证据**，假阳性会污染它。已补进集中复位块（并连带清 `armed CISD`，它是跨帧数据、快路径 tick 会读） |
| **C4** `CalcATRSeries` 种子只写最旧一根 | 种子均值原来只写进 `atrArr[analysisStart]`，`[seedEnd, analysisStart-1]` 这 `n-1` 根仍停在**单根 TR** ⇒ 该区段所有 ATR 门槛（位移 / FVG 最小宽度 / 分离度 / 回撤）用的是 TR 而非 ATR，方差大得多、系统性偏松。影响面是最旧 ~2.6% 的窗口。已改为铺满种子区间 |
| **C5** `InpAnalysisWindow` 无校验 | 与 A8 同一条（域 A 与域 C 从不同角度各自命中），已修 |
| **C6** CLOSURE 对**未收盘** bar 下判（`F6`） | `b=2` 时 `c4=0`：`EvalC4Half` 拿"新 bar 第一个 tick"的 low/high 判 EQ，且默认 `InpReuseResultOnTick=true` 使其**整根 bar 内不再重算** ⇒ `C3+`/`C3-` 标签与 CSV `c4` 列在一根 bar 内是**基于单一 tick 的判决**。与注释 `:1962`"返回 0 = C4 尚未出现（待定）"的措辞不一致。**已按你裁定修改**：守卫 `b < 1` → `b < 3`（C1..C4 全为已收盘 bar），代价是最新 1 个节点的 closure 延后一根 bar 出现 |

### C7 — 同 bar 双破时"落选侧"不被消耗（**已修**）

`:2931-2945` 外包 bar 同时破两侧时，只把**被取的那一侧**置 `broken = true`，
落选侧仍 `valid && !broken`。默认 `BREAK_WICK` 下：ST_UP 中一根外包 bar 同时上破 refHigh、
下破 refLow 且收阳 ⇒ 记 BOS(UP)，refLow 未消耗；紧随任一根 bar 再刺一下 refLow，
就再记一条 **bearish MSS，其 `bar` 是后一根而非真正发生下破的那根**（`ref/refBar` 仍是同一个位）。
`DisplacedBeyond` 的窗口 `[i+N, anchorBar-1]`（N 默认 3）覆盖该情形 ⇒ 这条**虚假时序 MSS 通常是 OK 级、会真画出来**。

**已修**：两侧现在都会把对方标记为已消耗 —— ST_UP 收阳记 BOS(UP) 时置 `st.refLow.broken = true`（`:2979`），
ST_DOWN 收阴记 BOS(DOWN) 时置 `st.refHigh.broken = true`（`:3019`）。
落选侧那一根**确实在同一根 bar 上被破**，消耗它是符合事实的，因此不再有随后的虚假重复事件。

同族第二实例在 `ComputeChoch`：`if(high 侧){…} else if(low 侧){…}` 同 bar 双破时只处理高点侧，
低点破位要么延迟出、要么**丢失**，而 `loDone` 一直与事实不符。默认 `BREAK_CLOSE` 下不可达
（同一根 bar 收不到既高于高点又低于低点），`=BREAK_WICK` 时可达。**此处未改** ——
它需要"双破时该报哪个"的口径决定，属会改事件集合的语义取舍。

---

## 低危与文档级

| 项 | 域 | 说明 |
|---|---|---|
| `DisplacedBeyond` 在门槛判定**之前**写 `g_lastBodyATR`（`:2651` 早于 `:2654` 的门槛 return） | B | 弱因是"时效窗口"的行，CSV 里带着"已过实体门槛"的 `bodyATR` ⇒ 离线按 `bodyATR` 复核会误判该行"不该弱"。可修，但会改 CSV 数值口径，需你确认 |
| `FindBrokenNodeBar` 的 `bind=` 自检是**恒真断言**（`:2080`/`:2100` 拿 `ref.price` 反查同价 node，而 `ref.price` 本就来自 `nodes[]`） | B | 它永远发现不了它本要发现的那类错。属"检查器无效"而非行为错 |
| `InpMinSeparationATR` 在 `MODE_FRACTAL_SWING` 静默失效（`:3916` 带 `InpMode != MODE_FRACTAL_SWING` 条件），输入说明 `:203` 未标注 | B | 仅注释 |
| 顶层注释 `:44-47` 断言"实测 index 0 = 最旧"，与 `:5940-5943`/`:5975-5977` 按 series 处理矛盾 | E | `ArraySetAsSeries` 只改解释不改数据，两种说法效果等价；但作为"实测结论"会误导后续排查 |
| `LevelMarkedByBreak`（`:4868`）的同位去重口径不成立：节点级传**被破节点** bar、引擎传 **protected ref** bar，两者通常不同 ⇒ 让位机制基本不触发 | B（域外附带） | 作者自己的 `nChochHidden` 诊断（`:5370`）就是答案 |

## UNPROVEN（未证到可达，不列为缺陷）

1. **历史回放期每帧全量重算 + 每帧 `ChartRedraw`（O(N²)）**：`newBar` 只由 `rates_total` 变化判定，
   历史下载期 `rates_total` 逐次增长 ⇒ 每帧全量帧。**不是错状态**（计数全复位、场景集每帧重建、
   CSV 末次覆盖），代价是卡顿闪烁。批大小无法在无终端环境测定。
   定案：在 `OnCalculate` 打一行 `rates_total`，数首次加载一个新品种时的调用次数。
2. **WICK 口径下 `broken` 与"真实收盘突破"不一致**：需 WICK/CLOSE 两份 CSV diff。
3. **`atr <= 0` 时 `DisplacedBeyond` 直接返回 `true`**（`:2647`）是否在真实数据上关掉位移门槛：
   查 CSV 是否存在 `bodyATR=0.00` 且 `state=OK` 的行。

---

## 验证与部署

```
编译        Result: 0 errors, 0 warnings
部署核验    VERIFY mq5  repo=4EE1C70BD6D3  mt5=4EE1C70BD6D3  match=True
            VERIFY ex5  repo=24537D5D0A8B  mt5=24537D5D0A8B  match=True
仓库审计    audit_state.ps1  RESULT: PASS (0 problems)   [覆盖率 81→82，多出的正是新进指纹的底色]
格式检查    check_fmt.ps1    65 call(s), 0 mismatch(es)
```

改动规模：`Indictor/TradFi_Structure.mq5`，`v1.50-s58` → **`v1.50-s59`**，
源码 SHA-256 `4EE1C70BD6D3…`，行数 5990 → **6177**（`+222 / −33`）。

### ⚠️ 修复过程中我引入的 9 处错误（完整披露）

这次批量改动用脚本做"注释+代码"插入，**有 9 处我自己写错了**，其中一处是**严重的语义回归**。
全部记录在案，因为它们的性质完全不同，教训也不同：

| # | 我写错的 | 怎么暴露的 | 性质 |
|---|---|---|---|
| ① | 指纹表达式尾部残留游离的 `(g_fibDir != g_lastFibDir);` | 编译 **17 errors** | 结构错，编译器抓 |
| ② | 注释替换误删 `void DumpEventsNow()` 声明行 | 编译 **17 errors** | 结构错，编译器抓 |
| ③ | `DumpRectObjects` 残留一行 `s_done = true;` | 编译 **17 errors** | 结构错，编译器抓 |
| ④ | **`ApplyMssTransition` 里旧的 `if(!strong){…}` 体没删干净，变成裸块 `{ ref.touched=true; return 0; }`** | **编译 0 errors / 0 warnings —— 是事件语义域的审查者逐行比对才抓到的** | **语义错，编译器完全不报** |
| ⑤ | 域 C 修复时，注释块**覆盖**了 `isBosH`/`isBosL` 的声明行（把声明挤到了使用之后） | 编译 **2 errors**（undeclared identifier） | 结构错，编译器抓 |
| ⑥ | 域 C 的盒 flush 插到了**循环体内**（那里 `boxStart` 刚被重置为 -1，flush 永不执行） | 编译器**不报** —— 是我逐行复核落位时发现的 | 语义错，编译器不报 |
| ⑦ | 域 C 的计数器复位块锚点匹配到了 `ComputeChoch` 的同名行，插错了函数 | 编译器**不报**（功能上等价）—— 同样靠复核落位发现 | 定位错，编译器不报 |
| ⑧ | 第二批：域 C 注释里写了全角 `）`，被 PowerShell 当成未闭合的括号 | **脚本自身抛 ParserError，文件未写入** | 无害（写入在末尾，失败即中止） |
| ⑨ | 第二批：用完 `[string].Join`（应为 `[string]::Join`） | 运行时报 MethodNotFound，**文件未写入** | 无害（同上） |

⑧⑨ 两条虽然也是我写错，但**没有造成任何污染**，原因值得记下：**所有批量脚本都把
`WriteAllText` 放在最后一步**，前面任何断言/语法失败都会在写盘前中止。这是这套脚本里
唯一一条真正救过命的约定 —— 否则 ⑧⑨ 会各写坏一次 6166 行的文件。

④⑥⑦ 三条的共性是：**批量脚本用"锚点正则"定位，而锚点在文件里不止一处或结构相邻**，
于是插入点静默错位。本次的教训是——**批量改完必须逐处读回落位，而不是只看编译通过**。
⑦ 尤其说明问题：它编译 0 错、运行时也"看起来对"，但语义上该复位属于 `ComputeStructure` 的集中块，
放错函数会在将来某次函数重排时变成真 bug。

④ 的后果：MQL5 里裸 `{}` 复合语句**总是执行**，于是**每一条强 MSS 也会 `return 0`**，
其后的 `ref.broken = true`、`st.state` 翻转、对侧参考位失效全部**不可达**。
从第一次下破开始，状态机冻结、同一参考位被反复重复报事件。**而它编译得干干净净。**

这一条值得单独记住：**"编译 0 错 0 警"对这类缺陷零保证**。
本轮的 17 条真缺陷里，绝大多数编译器都不会报（`ref.touched` 闩锁、底色不入指纹、
早退残留全局、缓存只复位一半、static 跨 OnInit、热键绕过门控、`open` 方向、输入未校验…），
而我自己新引入的那条最严重的，恰恰也是编译器不报的那一类。
所以"改完必须编译"只挡住了结构错；**语义错只能靠逐行读 + 域审查兜住**。

---

### 我判定为"非缺陷"、未采纳的一条

**域 A 报的 F-3（HTF 指纹从 `k=1` 起、绘制从 `k=0` 起，致 k=0 的时间标签不刷新）—— 我认为不成立。**

子代理的事实陈述准确（`:4587` 指纹 `for(k=1…)`、`:4745` 绘制 `for(k=0…)`），但它自己的推导里已有答案：
右侧留白模式下 `t2 = t1 + g_htfSlot`（`:4774`），而标签文本是 `TimeToString(keyTime, TIME_MINUTES)`。
**在当前 HTF bar 内，`t1`/`t2` 都是常数**（由 `UpdateHtfLastFast` 的 `tNow + ps + (n-1)*slot` 决定，
bar 内不变），所以标签内容在整根 bar 内**本来就不该变** → "指纹不含 k=0"不产生可见缺陷。
`DrawHtfCandles` 在**每个全量帧**都从 `k=0` 画（含标签），而全量帧由新 bar 触发 —— 恰好在标签**该变**的时候重画。
唯一能让标签该变而不重画的是 `g_htfSlot` 变化（缩放/改留白），而 `g_htfSlot` **在指纹里**（`:4995` 附近）。
故 k=0 排除出指纹是**有意的性能分工**（`:909` 的 `g_htfSig` 注释写明"**已收盘** HTF 蜡烛的签名"），
且分工闭环。**不改** —— 子代理建议的"指纹改为从 k=0 起"会恢复每 tick 全场景调和，是明确的性能倒退。

---

## ⚠️ 域 A 残留在你 MT5 里的两个探针文件（需你处理）

域 A 为了把上面 A7（`open` 方向）从推测**升级为定案**，往你的 MT5 里放了两个一次性文件。
它无法在不打扰你正在运行的终端的前提下自动触发，所以**需要你跑一次或直接删掉**：

```
…\MQL5\Indicators\TradFi_OrientProbe.mq5 / .ex5      （只读探针，3.2 KB）
…\MQL5\Scripts\TradFi_OrientProbeRun.ex5
```

跑一次 `TradFi_OrientProbeRun`，日志会出现 `PROBE-BEFORE` / `PROBE-AFTER` 两行，其中
`o=S|N` 是 `open[]` 的实测方向，`OHLC-align mismatches=0/N` 是"`open` 是否与 `high/low` 同向"的**直接判据**
（`N > 0` 即证明方向确实错位、A7 是真 bug 而非防御性修复）。
**跑完请连同 `.mq5` 一起删掉这三个文件**（仓库侧它已清理干净，只留在 MT5 里）。

如果你不想跑：A7 的修复本身是零风险的（只是把方向显式锁定，与 `:41` 的纪律一致），
探针只影响"这条到底算真 bug 还是防御性加固"的定性，**不影响是否该修**。

---

## 附录：本轮独立复核且**判定为非缺陷**的项

这些是我在子代理之外自己追到结论的，列出以免下一轮重复劳动：

| 项 | 结论 |
|---|---|
| 8 个事件计数器的复位完备性 | `nMSS`/`nCISD`/`nBOS`/`nBox`/`nFVG`/`nOB`/`nChoch` 在集中复位块（`:3744-3751`）；`nSWEEP` 在 `:3313`、`nClosure` 在 `:2003` 于各自函数内复位。**全部有复位**。⚠️ 但后两者不在集中块，文件注释（`:1986-1989`）已声明知晓该风险，`audit_state.ps1` 会以 `OK*` 标注其弱性。 |
| `InpMaxEvents` 是否污染 CSV | **不污染。** 该输入只用于渲染裁剪（`mssFrom`/`bosFrom`/`cisdFrom`/… 全在 `RenderScene` 内计算），`DumpEvents` 用 8 个独立 while 循环取全量事件。设计正确。 |
| `oldestBar` 越界 | 实参即 `analysisStart`（`CisdSetLevel(st, i, …, analysisStart)`，`:3977`/`:3985`），恒 ≤ `rates_total-1`；`CisdOriginBar` 内 `j < ArraySize(close)` 是纯防御性、当前不可达。 |
| `DbgReport` 不变量检查是否被开关架空 | **未被架空。** 检查在 `:1349`，`if(!InpDebugShowRef) return;` 在 `:1354` 之后；且 `DbgReport` 在 `:5986` 由全量路径**无条件**调用。机制成立。⚠️ 但它成立完全依赖「检查排在早退之前」这一顺序，属脆弱安排（见发现清单）。 |
| `fvgFollow` 是否会让图停在旧色 | 不会。`fvgFollow` 由既有 FVG/CISD 的**固定 bar 下标**比较得出，不随当前 bar 漂移；新 FVG 产生时 `nFVG` 变化已进指纹。 |
| `EvalIcLate` 用 `TimeCurrent()` | 有意为之：IC-CISD 只在未收盘 bar 上做实时预览，快路径注释（`:5962-5965`）说明"bar 内由早转迟必须能刷新"；`audit_state.ps1` 已把 `g_icLate` 列为例外并写明理由。 |
| `UpdateLiveLeg` 的 O(1) 增量 | 正确。bar 0 的极值在 bar 内单调，故增量与全量重扫等价；换 bar 由 `g_liveBarT == time[lastBar]` 判据触发慢路径重扫；另有调试模式下与全量重扫的**等价性自检**（`:5887-5908`）会累加 `g_dbgLiveMismatch`。 |
| 场景集回收段 | 只删「带前缀 且 `!SceneHas`」的对象（`:5799-5808`），未注册对象不会被误删，也无泄漏。 |
| 指纹是否漏项（`nBox`） | `nBox` 未进指纹，但盒渲染只取最新那个且 `boxIdx` 已在指纹内；`time[0]` 变化即覆盖新 bar 场景。当前不构成 stale。 |
| HTF 指纹从 `k=1` 起（域 A 的 F-3） | **非缺陷**，理由见正文专节（bar 内 `t1/t2` 恒定 ⇒ 标签本来就不该变）。 |
| `SceneSetAdd` 扩容失败的自愈（域 D 的 F3） | **我判定比子代理报的轻**：`SceneSetRebuild()` 确实清空哈希表，但**回收段之后**的每一次 `AddSceneName` 都会把该对象重新注册，故不会"删掉本帧全部对象"；它只造成一次哈希扰动与些许对象抖动。子代理称"删光"未计入调用顺序。**仍建议加固**（失败时先翻倍重试），但不是缺陷。 |
| 域 D 其余排除项 | 已由该域逐条给出理由并复核：`changed` 汇总无 `\|\|` 短路、对象注册与绘制同分支、`SceneHash` 碰撞只多一次探测、`PD_END_RETEST`/`PD_END_NOW` 安全、`UpdateLiveLeg` 早退不可达。 |
