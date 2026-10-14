# TradFi_Structure 第三轮逻辑评审（`v1.50-s59`）

- 评审对象：`Indictor/TradFi_Structure.mq5`
- 基线：`v1.50-s59`，6177 行 / 371789 字节，
  SHA-256 `4EE1C70BD6D362B3D0DF7DCB33D343F6F8AF919740DB656A5EBCA2B6AC46752A`
  （与二轮评审"部署核验"里记的 `repo=4EE1C70BD6D3` 一致），
  工作区 = `git 36bd48e`，`Indictor/TradFi_Structure.mq5` **无未提交改动**
- 评审日期：2026-10-09
- 与前一轮的关系：本轮**把"上轮那批修复是否真的落地"当成独立命题来验**，不把
  "已修"当既成事实。理由写在二轮评审自己的文末：那批改动由批量脚本用**锚点正则**插入，
  9 处写错里有 3 处（⑥⑦ 等）**编译不报、靠逐行读回落位才抓到**。s59 正是那批脚本的产物，
  所以"文件里出现了这段代码"与"这段代码会执行"必须分开验。顺带在未覆盖域做新缺陷搜索。

## 评审方法

**只读评审，未编译、未真机**（评审环境无 MetaEditor）。所有结论来自逐行读码与锚点核对，
每条发现给出**行号 + 代码原文 + 可达性 + 最小修法**。

逐段精读范围：事件写入器（`Add*Result` / `AddNodeFiltered`）、`ComputeClosures` / `EvalC4Half`、
`CheckFvg` / `AddObFromRun`、`CalcATRSeries`、位移判据（`DisplacedBeyond` / `MSSDisplaced`）、
CISD 链（`CisdOriginBar` / `CisdSetLevel` / `CheckCisd` / `SetProtectedFromCisd`）、
状态机（`ApplyMssTransition` / `CheckBreakAgainstRefs`）、节点级层（`NodeFlipUp/Dn` / `ComputeChoch`）、
`ClassifyNodeTiers` / `ComputeSweeps` / `BiasAtTime` / `ComputePrevDay` / `IsLiquidityTaken` /
`ComputeErlIrl` / `ComputeTargets` / `ComputeCisdFvgFollow` / `ComputeStructure`、
渲染层（`needDraw` 指纹与缓存同步 / 回收段 / 实时腿 / MSS·BOS·CHoCH·CISD·closure·FVG·OB·ERL·IRL·TGT·FIB
标注 / `LevelMarkedByBreak` / `LineEnd` / `Upsert*` / `HtfRightSlotSec` / `HtfLogSlot`）、
快路径（`UpdateLiveLeg` / `UpdateEarlyCisdFast` / `UpdateHtfLastFast`）、
生命周期（`OnInit` / `OnDeinit` / `OnChartEvent` / `OnCalculate`）与 `DbgReport` / `DumpRectObjects`。

**未逐行覆盖**（本轮盲区，见文末）：输入枚举块 `:188-620`、`DumpEvents` 主体 `:1080-1330`、
场景哈希表内部 `:4188-4252`、`DrawHtfCandles` 与 `RenderScene` 中段的部分纯几何代码。

---

## 结论摘要

**共 4 条**：其中 **3 条是 s59 那批修复自身的缺口**——两条新校验根本没执行、一条把非默认档判据接反。

| 编号 | 缺陷 | 域 | 严重度 | 性质 |
|---|---|---|---|---|
| **R1** | `OnInit` 的两条新校验被写进 `if(InpATRPeriod < 2){…}` 的 `return` **之后** ⇒ 死代码 | E | 中高 | **s59 修复未生效** |
| **R2** | 节点级 `NodeFlip` 的 helper 配对：修好默认档的同时把 `EXTREME` / `LEG` 两档判据**接反** | C | 中高 | **s59 修复引入** |
| R3 | 同类型节点替换同步 ref 时清 `touched` 却**不清 `broken`** ⇒ 新位继承"已消耗" | B | 中低 | s59 修复不完整 |
| R4 | 早退路径清了 A3 列出的派生全局，**漏 `g_curATR`** | E | 低 | s59 修复不完整 |

**一句话**：本轮没有推翻二轮的任何一条**判定**，但推翻了两条"已修"的**结论** ——
R1 说明 `A8`（`InpAnalysisWindow` 1/2 静默全灭）与 `A10`（`InpBiasLookback` 负值静默关偏置）
**在 s59 里仍然是活的**；R2 说明 `C1` 那次修复**换了一档正确、换掉了两档正确**。

---

# R1 — `OnInit` 的两条 s59 新校验是死代码（`A8` / `A10` 实际未修）

**严重度：中高**（触发条件是用户改输入项；一旦触发，后果是"整个指标静默归零"或"偏置链静默关闭"，
而文件自己把这两条列为**已修**）

二轮评审把 `A8`（`InpAnalysisWindow` 设 1/2 ⇒ `nValid` 恒 1 ⇒ 零事件、图上什么都不画、不报错）
与 `A10`（`InpBiasLookback` 为负 ⇒ `BiasAtTime` 恒返回 0 ⇒ ERL/IRL/AutoTargets/Fib 投影与
事件弱化分级全部静默消失）标为**已修**。实际落位如下（`:1648-1669`，逐字）：

```cpp
   if(InpATRPeriod < 2)
   {
      Print("TradFi_Structure: InpATRPeriod 必须 ≥ 2");
      return INIT_PARAMETERS_INCORRECT;
   // v1.50-s59：InpAnalysisWindow 是唯一直接决定"分析几根 bar"的量，却从未被校验。
   //   设 1 或 2 会让 nValid 恒 < 3 ⇒ ComputeStructure 在算任何东西之前就早退 ⇒
   //   零 MSS/BOS/CISD/FVG/OB/SWEEP/CHoCH/CLOSURE，图上什么都不画，且不报任何错。
   //   0 仍放行（= 全量分析）。
   if(InpAnalysisWindow != 0 && InpAnalysisWindow < 3)
   {
      PrintFormat("TradFi_Structure: InpAnalysisWindow 必须为 0（全量）或 >= 3（收到 %d）；"
                  "1/2 会让有效 bar 不足 3 根而使结构检测整体失效", InpAnalysisWindow);
      return INIT_PARAMETERS_INCORRECT;
   }
   // v1.50-s59：负值会让 BiasAtTime 的循环体一次都不执行 ⇒ 恒返回 0 ⇒
   //   ERL/IRL/AutoTargets/Fib 投影与事件弱化分级全部静默消失。
   if(InpBiasLookback < 1)
   {
      PrintFormat("TradFi_Structure: InpBiasLookback 必须 >= 1（收到 %d）", InpBiasLookback);
      return INIT_PARAMETERS_INCORRECT;
   }
   }        // ← :1669，这一行的 `}` 才是 `if(InpATRPeriod < 2)` 的闭合
```

**可证性（无需测量，括号归属唯一）**：`:1649` 的 `{` 打开 `InpATRPeriod` 块；
`:1651` 的 `return` 之后**没有任何 `}`**；`:1661` 与 `:1668` 分别闭合两个新校验自己的块；
`:1669` 的 `}` 闭合 `InpATRPeriod` 块。**故两条新校验整段位于一个"必定在它们之前 return"的块内**
⇒ 不可达代码 ⇒ 与 s59 之前**行为完全一致**。

**为什么编译和既有工具都拦不住**：

| 手段 | 为什么没抓到 |
|---|---|
| 编译器 | 复合语句里 `return` 之后的代码**不是语法错**；MQL5 不报"不可达代码"警告（本轮未编译，但 s59 记录的是 0 errors / 0 warnings） |
| `audit_state.ps1` | 它扫的是 `ComputeStructure` 的计数复位与 `RenderScene` 读的全局，**完全不覆盖 `OnInit`** |
| 二轮评审的逐行复核 | 它复核的是"注释+代码插入是否落对函数"，而这两段**确实在 `OnInit` 里**——只是落在了错的**块**里 |

这正是二轮文末自己总结的教训（"批量脚本用锚点正则定位，锚点在文件里不止一处或结构相邻，
于是插入点静默错位"）的**第 10 例**：锚点 `return INIT_PARAMETERS_INCORRECT;\n   }` 在
`OnInit` 里出现了**多次**，脚本把新块插到了**第一个**匹配之后，而不是 `InpATRPeriod` 块之后。

**最小修法**：把 `:1669` 那一行的 `}` 上移到 `:1651` 的 `return` 之后（即 `InpATRPeriod` 块恢复成
三行），两条新校验就与其余校验同级。零风险、不改任何判定。

**修完的验收**：把 `InpAnalysisWindow` 设成 `2` 重新挂载 —— 应当**拒绝加载并打印原因**；
设成 `0` / `500` 应正常加载。`InpBiasLookback = 0` 同理应当被拒（它是 ULP 合法值，故必须有这条闸门）。

---

# R2 — 节点级 `NodeFlip` 的 helper 配对：默认档修好了，`EXTREME` / `LEG` 被接反

**严重度：中高**（默认档不受影响；但**两个可选档的判据与其输入说明相反**，且 CSV 头部会
`nodeFlip=EXTREME|LEG` 地自描述，导出档与标签不符）

s59 按 C1 的结论把调用点从"同侧 helper"改成"**按破位侧**配对"（`:3339` / `:3353`）：

```cpp
// :3339  破高点
bool flipH  = isBosH ? false : NodeFlipDn(i, legLvl, legExt, hiLvl, hiPrev, hiHasPrev, close);
// :3353  破低点
bool flipL  = isBosL ? false : NodeFlipUp(i, legLvl, legExt, loLvl, loPrev, loHasPrev, close);
```

而两个 helper **各自同时承载三档判据**，且三档的"镜像方式"并不一致（`:3224-3255`）：

```cpp
bool NodeFlipUp(...)                       // :3228-3238
{
   case NODEFLIP_EXTREME: return (!hasPrev || lvl > prev);              // :3231
   case NODEFLIP_LEG:     return (legLvl <= 0.0 || close[i] > legLvl);  // :3232
   // RETRACE: progress = legExt - legLvl（要求 legExt > legLvl）
   return ((legExt - close[i]) >= progress * InpNodeFlipRetracePct / 100.0);   // :3238
}
bool NodeFlipDn(...)                       // :3245-3254
{
   case NODEFLIP_EXTREME: return (!hasPrev || lvl < prev);              // :3248
   case NODEFLIP_LEG:     return (legLvl <= 0.0 || close[i] < legLvl);  // :3249
   // RETRACE: progress = legLvl - legExt（要求 legLvl > legExt）
   return ((close[i] - legExt) >= progress * InpNodeFlipRetracePct / 100.0);   // :3254
}
```

**真值表（破位侧 × 档位）** —— 「应当」取自输入说明与二轮评审记录的口径
（`NODEFLIP_EXTREME` = "被破节点本身是新的同侧极值（LL/HH）"；`NODEFLIP_LEG` =
"收盘越过当前腿起点，最严：只有整条腿被作废才改性格"）：

| 破位侧 | 档 | 应当 | s59 配对下实际 | 结论 |
|---|---|---|---|---|
| 破**高**点（`:3339` → `NodeFlipDn`） | `EXTREME` | `hiLvl > hiPrev`（HH） | `hiLvl < hiPrev`（破了更**低**的高点） | **反向** |
| | `LEG` | `close > legLvl` | `close < legLvl` | 空头腿下 `legLvl` 是腿起点高点、恒在上方 ⇒ **恒真 ⇒ 退化成 `ANY`** |
| | `RETRACE`（默认） | `close − legExt ≥ progress×N%` | 同 | ✅ 正确（C1 修好的正是这档） |
| 破**低**点（`:3353` → `NodeFlipUp`） | `EXTREME` | `loLvl < loPrev`（LL） | `loLvl > loPrev`（HL） | **反向** |
| | `LEG` | `close < legLvl` | `close > legLvl` | 多头腿下 `legLvl` 是腿起点低点、恒在下方 ⇒ **恒真 ⇒ 退化成 `ANY`** |
| | `RETRACE`（默认） | `legExt − close ≥ progress×N%` | 同 | ✅ 正确 |

**根因不是脚本，是接口**：`RETRACE` 的 progress **必须从对侧极值量起**（破高点要看
"自腿内最低点回补了多少"），而 `EXTREME` / `LEG` 的比较 **必须按"破位侧"本侧**（HH / 越过腿起点）。
**同一个 helper 里这两套是互相镜像的** ⇒ 任选一个 helper 都无法三档全对。s58 选的是"本侧"
（EXTREME/LEG 对、RETRACE 死），s59 换成了"对侧"（RETRACE 对、EXTREME/LEG 死）——
**这不是修好了，是把错误从左口袋挪到右口袋**。

**最小修法（二选一，都不改默认档行为）**：

1. 让 helper **只保留 RETRACE**，把 `EXTREME` / `LEG` 的比较留在 `ComputeChoch` 的调用点
   （那里天然知道自己是"破高点"还是"破低点"）；
2. 或给 helper 传一个"破位侧"布尔，`EXTREME` / `LEG` 按该布尔选比较方向，`RETRACE` 固定用
   s59 之后的配对。

**验收**：`InpNodeFlipMode = EXTREME` 与 `LEG` 各导一份 CSV，对照 CSV 头部 `nodeFlip=` 与
`state` 列的 `CHoCH` / `BOS(node-level,…)` 分布 —— 两档的 CHoCH 条数应当**显著不同**
（`LEG` 最严 ⇒ CHoCH 最少）。现在两档的行为是"`EXTREME` 反向过滤 + `LEG` 恒真"，
若两者导出结果与前一轮的 `ANY` 档高度相似，即坐实本条。

---

# R3 — 同类型节点替换同步 ref 时，清 `touched` 却不清 `broken`

**严重度：中低**（只在"参考位已被消耗 + 同类型替换"同时成立时吞掉一条 BOS；需你裁定口径）

s59 的 B4 把 `touched` 的复位收口到全部 10 个生命周期写点，理由写得很清楚
（`:2420-2422`）："这里被换成了更新的极值（bar/price 都变了），**旧闩锁属于旧那个位**"。
但**同一个写点里 `broken` 没有跟着复位**：

```cpp
// :2411-2424  同类型替换（high 侧）；:2432-2442 是 low 侧的镜像
int oldBar = g_result.nodes[last].bar;
g_result.nodes[last].bar    = bar;
g_result.nodes[last].price  = price;
g_result.nodes[last].isMain = isMain;
if(st.refHigh.valid && oldBar == st.refHigh.bar)
{
   st.refHigh.bar   = bar;
   st.refHigh.price = price;
   st.refHigh.touched = false;   // ← 只有 touched
   // 没有 st.refHigh.broken = false;
}
```

对照其余三个写点（`SetProtectedFromCisd` `:2864-2873`、状态初始化 `:3964-3970`、
播种 `:4104-4115`）都是 **`broken` 与 `touched` 成对写**。**只有替换这一处是不对称的。**

**可达性**：`ref` 节点要同时满足"是最后一个节点"且 `broken=true`。
节点数组强制高低交替，故同类型替换只在**中间那根反向 swing 被过滤器剔掉**时发生
（`InpMinBarsBetweenSwings` / 回撤过滤 / failure swing 剔除），此时出现：

1. `ST_UP` 中 `refHigh` 被上破 ⇒ 记 BOS，`refHigh.broken = true`（`:3015`）；
2. 价格继续走高，中间那根低点被测序门槛剔掉；
3. 更新的 swing high（更极端）到来 ⇒ 走替换分支 ⇒ `ref` 的 `bar/price` 换成了**新位**，
   而 `broken` 仍是 `true`；
4. 此后价格再破这个**新位** ⇒ `CheckBreakAgainstRefs` 的 `!st.refHigh.broken` 为假 ⇒ **不记 BOS**。

**两种读法**，需你裁定（我倾向 ①）：

| 读法 | 含义 | 修法 |
|---|---|---|
| ① 替换 = 换了一个位 ⇒ 状态应随位重置 | 与 B4 的论证一致：`(bar,price)` 变了，`broken` 与 `touched` 同属旧位 | 在 `:2423` / `:2441` 旁补 `st.refHigh.broken = false;` / `st.refLow.broken = false;` |
| ② 替换 = 同一条腿里的极值刷新 ⇒ 保留"已消耗" | 可避免同一段延续里重复出 BOS | 保持现状，但**必须加注释说明这是有意为之** |

无论选哪个，**当前的"两个字段在同一行被区别对待、且无任何注释解释"**都是不可接受的：
下一个人读到这里，无法判断哪个是笔误。

---

# R4 — 早退路径漏清 `g_curATR`（A3 修复的不完整项）

**严重度：低**（只影响标签垂直偏移量；默认参数下几乎看不出）

A3 的修复（`:3935-3952`）把 `RenderScene` 会读到的派生全局在早退前清零：

```cpp
if(nValid < 3)
{
   g_curBias   = 0;
   g_relValid  = false;
   g_erlValid  = false;   g_irlValid  = false;   g_pdValid = false;
   g_tgtCount  = 0;       g_fibValid  = false;
   g_irlFvgIdx = -1;
   g_fibA = 0.0; g_fibB = 0.0; g_fibRefBar = -1; g_fibDir = 0;
   DbgReport(time, rates_total);
   return;                                   // :3951
}
double atrArr[];
CalcATRSeries(high, low, close, rates_total, analysisStart, atrArr);
double atrValue = atrArr[0];
g_curATR = atrValue;                          // :3957 —— 早退时到不了这里
```

`g_curATR`（声明 `:774`）**不在清零清单里**，而 `RenderScene` 大量用它做标签偏移：
`:4615-4617`（IC-CISD 标签）、`:5606-5613`（CISD 标签 ±0.15×ATR 与兜底分支）、`:5779`（OB 标签）、
`:5919`（bias 文案定位）、`:5953-5960`（SWEEP 标签）、`:4855`（HTF 时间标签）。
故早退帧会拿**上一帧**（换品种/周期时甚至是上一个品种）的 ATR 去算偏移量。

与本轮 R1 归为同一族：A3 的目标是"早退帧不许用陈旧派生量"，而清单是**人工枚举**的，
漏一项就等于漏洞还在。**最小修法**：把 `g_curATR = 0.0;` 加进 `:3944-3949` 的清零块。
（其余渲染读到的 ATR 分支都自带 `g_curATR <= 0.0` 兜底，故置 0 是安全方向。）

> 附注：`audit_state.ps1` 结构上抓不到这一类 —— 它的检查 ③/④只覆盖
> "逐帧全局是否有非声明式赋值 / 是否进指纹"，而 `g_curATR` **在非早退帧确实每帧被赋值**，
> 脚本看到的是"有赋值"，看不到"**存在一条到不了那行赋值的路径**"。这是该工具的第 6 个盲区。

---

## 已复核到位、确认真的生效的 s59 修复

以下逐条回到代码核对过位置**与可达性**（不是只看"文件里有这段注释"）：

| 上轮编号 | 修复 | 落点 | 复核结论 |
|---|---|---|---|
| A1 | 强 MSS 不被 `touched` 闩锁挡 | `:2954-2978`（`if(strong) AddMSSResult(...) else { if(ref.touched) return 0; ... }`） | ✅ 两条语义已拆开；强触发无条件记录 |
| A2 | 图表底色进指纹 | `:5140`（每帧无条件读）→ `:5177`（进 `\|\|` 链）→ `:5203`（同帧同步缓存）→ `:5230`（块内复用同值） | ✅ 且比上轮更强：块内不再重复 `ChartGetInteger` |
| A3 | 早退清派生全局 | `:3944-3949` | ⚠️ 见 R4（漏 `g_curATR`） |
| A4 | HTF 快路径缓存整组复位 | `:5221-5225`（`T0/T1/O/H/L/C` 同生死） | ✅ |
| A5 | `DumpRectObjects` 的 `static` → 全局 | `:1342-1343` + `OnInit :1758`（`g_objDumped = false`） | ✅ |
| A6 | 热键受 `InpDumpEvents` 门控 | `:1859-1862`（否则打 `TradFi_DUMP 热键导出已被挡住`，`:1861`） | ✅ 可取证性也保住了 |
| A7 | `open[]` 显式锁时序方向 | `:6128` | ✅ 与 `:41` 的纪律一致 |
| A9 | `OnInit` 复位指纹 | `:1764-1765`（`g_lastT0 = 0` / `g_lastBgClr = -1`） | ✅ 改颜色/线型不再需要等下一根 bar |
| A11 | 删掉重复的 `nValid < 3` | 全文只剩 `:3935` 一处 | ✅ |
| A12 | 开关先于 `time[b]` | `:5380`（MSS）、`:5452`（BOS） | ✅ |
| A13 | `DbgReport` 的 `time[1]` 守卫 | `:1502`（`rates_total > 1 ? TimeToString(time[1]) : ""`） | ✅ 不再靠两步间接保证 |
| B4 | `touched` 收口到 10 个写点 | `:2423` `:2441` `:2865` `:2873` `:2970` `:2976` `:3965` `:3970` `:4105` `:4115` | ✅ 10 处齐（但替换那处的 `broken` 见 R3） |
| C1 | 默认档 `NODEFLIP_RETRACE` 生效 | `:3339` / `:3353` | ⚠️ 默认档 ✅，`EXTREME`/`LEG` 见 R2 |
| C2 | 最新内包盒补 flush（且在**循环外**） | `:3928-3932`（紧接 `for` 的 `}` 之后） | ✅ ⑥ 那次"插到循环体内"的错误已不在 |
| C3 | `nSWEEP`/`nClosure` 进集中复位块 + 清 armed CISD | `:3877-3883` | ✅ 且 armed 的清理理由（快路径 tick 会读）站得住 |
| C4 | ATR 种子铺满整个种子区间 | `:2521-2522`（`for(ii = seedEnd; ii <= analysisStart; ii++) atrArr[ii] = seedATR;`） | ✅ 递推起点 `seedEnd-1` 与之相接，无断层 |
| C5/C6 | CLOSURE 只用已收盘 bar | `:2081`（守卫 `b < 3 \|\| b > rates_total - 2`；`EvalC4Half` 的 `c4 = c3-1` 在 `:2018`） | ✅ 两者自洽（`c3 = b-1 >= 2` ⇒ `c4 >= 1`） |
| C7 | 同 bar 双破消耗落选侧 | `:3002-3003`（UP 记 BOS 时消耗 `refLow`）、`:3041-3042`（DOWN 镜像） | ✅ 两侧对称，注释与代码一致 |

**另：二轮自陈"修复过程中我引入的 9 处错误"，本轮在代码里一处都没有残留**
（①游离分号、②丢声明、③残留 `s_done = true`、④裸块吃掉强 MSS、⑤声明被注释挤走、
⑥flush 进循环、⑦复位块插错函数）—— 除 ⑦ 属"功能等价、无法从行为上判定"外，其余都能逐条核到。

---

## 上轮列为遗留/待裁定、本轮复核**仍开放**的项（不计入本轮新发现）

这些是二轮评审自己标注"未单独验证 / 待你裁定 / 仅文档警示"的，本轮核对后**状态未变**，
列出以免下一轮重复劳动：

| 项 | 现状 |
|---|---|
| **B3** 同 bar 双破时"当根零事件" | `:2996-3003` 的 `close>=open` 分支仍只记 BOS、丢弃 MSS 候选；`:3032-3042` 镜像。C7 只治了"虚假时序 MSS"，**没治"当根什么都不记"** —— 需"双破该报哪个"的口径裁定 |
| **`LevelMarkedByBreak` 同位去重口径不成立** | `:5059` 比 `mss[k].refBar`、`:5070` 比 `bos[k].refBar`（= CISD 派生的 **protected ref** bar），而 CHoCH 传的是**被破节点** bar（`:5523`）。两者通常是不同的节点 ⇒ 让位机制基本不触发。作者自己的诊断 `nChochHidden`（`:5554`）就是答案 |
| `DisplacedBeyond` 在门槛判定**之前**写 `g_lastBodyATR` | `:2732`（写）早于 `:2735` 的实体门槛 `return false` ⇒ 弱因是"时效"的行，CSV 里带着"已过实体门槛"的 `bodyATR`。改它属改 CSV 数值口径，需你确认 |
| `InpMinSeparationATR` 在 `MODE_FRACTAL_SWING` 静默失效 | `:4070`（`InpMode != MODE_FRACTAL_SWING` 合取项），输入说明 `:203` 仍未标注 |
| `FindBrokenNodeBar` 的 `bind=` 自检是恒真断言 | `:1932-1947`：拿 `ref.price` 反查**同价** node，而 `ref.price` 本就来自 `nodes[]` ⇒ 它永远发现不了它要发现的那类错 |
| 顶层注释 `:44-47` 的"实测 index 0 = 最旧"与 `:6124-6130` 的 `ArraySetAsSeries(true)` 叙述矛盾 | 效果等价，但作为"实测结论"会误导后续排查 |
| 二轮的 3 条 UNPROVEN | ①历史回放期每帧全量重算（O(N²)）；②WICK 口径下 `broken` 与"真实收盘突破"不一致；③`atr <= 0` 时 `DisplacedBeyond` 直接返回 `true`（`:2728`）。三条都需真机/双基线 diff 才能定案 |

---

## 验证与部署

本轮**未编译、未真机**（评审环境无 MetaEditor；只用只读工具读码与定位行号），
故上面 4 条的证据级别是"**代码可证**"而非"运行时已证"：

| 项 | 证据级别 | 建议的定案动作 |
|---|---|---|
| R1 | **可证**（括号归属唯一，且两条新校验位于 `return` 之后） | 改完把 `InpAnalysisWindow=2` 挂一次，看是否被拒 |
| R2 | **可证**（三档判据在两个 helper 里逐字可读，真值表闭合） | `EXTREME` / `LEG` 各导一份 CSV，比对 `nodeFlip=` 下的 CHoCH 条数 |
| R3 | **可证可达**（4 步时序 + 过滤器前提），但"该怎么修"需你裁定 | 若选读法 ①，改后重导基线（事件集合会变） |
| R4 | **可证**（`g_curATR` 不在清零清单，且 `:3951` 提前 return） | 无可见症状，属防御性收口 |

建议的提交粒度：**R1 与 R4 可以各成一次零语义改动**（`v1.50-s60`？）；
**R2 会改变非默认档的标签/事件集合** ⇒ 与 C1 同性质，需按仓库既有纪律**预先写出可证伪的
验收预测**，并预期 `docs/baselines/` 中与 `nodeFlip` 相关的基线失效；
**R3 需先有你的口径裁定**再动代码。

---

## 本轮我自己的局限（先写下来，免得被当成"已验证")

1. **没有编译、没有真机**。所有"✅ 已生效"都是读码结论；本轮**没有**任何一条是靠运行证据得出的。
2. **未逐行覆盖**输入枚举块 `:188-620`、`DumpEvents` 主体 `:1080-1330`、场景哈希表内部
   `:4188-4252`。故"输入说明与行为不符"这一类（如 `InpMinSeparationATR` 那条）本轮**没有系统扫**，
   只是顺手核到两条（`InpNodeFlipMode` 的两档）。
3. **`needDraw` 指纹只核了"有没有漏项"**（逐项对 `RenderScene` 读到的全局），
   没有核"每一项的比较语义是否正确"（例：`g_htfSig` 的哈希碰撞性质、`double` 直接 `!=` 比较）。
4. **R2 的真值表是我按 helper 源码与输入说明推的**，没有真机对照；
   若你的实机记忆里 `EXTREME` 档曾经"看起来是对的"，那说明我对该档口径的读法与你的原意有偏差——
   请以输入说明为准复核一次。
5. 本轮的插入点/行号全部是**当前 `v1.50-s59` 文件**的实测行号；任何一次改动都会让它们漂移。

---

# 处置记录（追加于同日；以上正文为**评审原文，未改动**）

> 正文的基线是 `v1.50-s59`。本节记录处置结果，处置后源码为 **`v1.50-s60`**。
> 本节行号是**改后**的实测行号，与正文（改前）不同 —— 正文保留原状，便于对照。

## 改了什么

| 编号 | 改动 | 落点（改后行号） |
|---|---|---|
| **R1** | 把 `if(InpATRPeriod < 2)` 块的闭合括号上移到它的 `return` 之后 ⇒ 原本被它包住的 `InpAnalysisWindow` / `InpBiasLookback` 两条校验**升到同级**、从此可达。附注释说明这一段的来历（s59 锚点错位）与"改完必须读回落位"的教训 | `:1658-1662`（块闭合）、`:1663-1672`（注释） |
| **R2** | 删除 `NodeFlipUp` / `NodeFlipDn` 两个 helper，改为**单一入口** `NodeFlipChanged(i, isUpBreak, legLvl, legExt, lvl, prev, hasPrev, close)`：`EXTREME`/`LEG` 按**破位侧本侧**比较，`RETRACE` 按**对侧极值**取回吐。两个调用点改为 `isUpBreak=true`（破高点）/ `false`（破低点） | 新函数 `:3262-3316`；调用点 `:3402` / `:3416` |
| **R3** | 同类型节点替换同步 ref 时补 `broken = false`（此前只清 `touched`），两个方向各一处 | `:2449`（refHigh）、`:2468`（refLow） |
| **R4** | 早退清零块补 `g_curATR = 0.0;` | `:4014` |
| — | `BUILD_TAG` → `v1.50-s60`，四项修复逐条写进它的注释（版本号仍只有这一个来源） | `:628-641` |

改动规模：`Indictor/TradFi_Structure.mq5` **+111 / −34**（`git diff --stat`）。
另新增 `Indictor/kernel_sim_nodeflip.ps1`；并在 `Indictor/kernel_sim_choch.ps1` 头部加了一条
**更正抬头**（该文件内核编码的是 s58 配对，故其 `RETRACE` 各臂与 `ANY` 逐字相同 —— 它的臂
按"plan §69.5 记录保持有效"的要求**未改动**，只加说明）。

## R3 的口径裁定（正文把它列为"需你裁定"，此处按读法 ① 落地）

采用**读法 ①：替换 = 换了一个位 ⇒ 状态随位重置**。理由：

1. 与 s59（B4）自己写下的论证一致 —— `bar/price` 都变了，"旧状态属于旧那个位"；
2. 其余三个 ref 写点（`SetProtectedFromCisd` `:2858-2873`、状态初始化、播种）都是 `broken` 与
   `touched` **成对写**，只有替换这一处不对称 ⇒ 更像漏写而不是有意设计；
3. 保留 `broken=true` 会让引擎**拿新位的价位去比、却永不开火**（`CheckBreakAgainstRefs` 的
   `!st.refHigh.broken` 恒假），即"量的是 A、判的是 B"。

⚠️ **这是本次唯一的语义变更**：它会让**一部分此前被静默吞掉的 BOS 重新出现**。按仓库纪律
先给出**可证伪的预测**：

> **预测**：在 `docs/baselines/` 的新旧 diff 上，变化**只能表现为 `type=BOS` 的行数增加或位置
> 变化**（含 `state` 列），**不应**出现 MSS 行数变化，也不应出现 `nodes` / `closure` / `mss`
> 计数变化。若对照里出现 `nodes` 或 `mss` 的变化，说明我对该写点可达性的判断有误，
> 应回退到读法 ②（保留 `broken`）重新分析。

## 验证（**本轮无 MT5**，故证据分三层，逐层说清它能证明什么）

| 层 | 手段 | 结果 | 能证明 / 不能证明什么 |
|---|---|---|---|
| **编译** | `Indictor/mq5debug.ps1`（MetaEditor64 → 编译 → 部署 mq5+ex5 → 哈希核对） | **`COMPILE Result: 0 errors, 0 warnings, 2276 ms elapsed`**；`VERIFY mq5 repo=F9CF004749A5 mt5=F9CF004749A5 match=True`、`VERIFY ex5 repo=CFA547492DE0 mt5=CFA547492DE0 match=True` | **`v1.50-s60` 能编译**，且仓库与 MT5 目录两份一致（不会被"另一份陈旧 .mq5"静默覆盖）。⚠️ 0/0 只挡住结构错：三轮评审 R1 正是"编译 0/0 却语义全错"的那一类，故它**不能**替代下面三层 |
| 结构 | `.bracecheck.ps1`（已排除注释与字符串） | `final depth = 0 / min depth = 0 / OK: braces balanced` | 只证明 `{}` 配平，**不证明语义** |
| 静态 | `check_fmt.ps1` | `65 call(s) checked, 0 mismatch(es)` | 格式化串与实参个数未被我改坏 |
| 静态 | `audit_state.ps1` | `RESULT: PASS (0 problems)` | 四类旧缺陷（计数复位 / 逐帧全局 / 指纹覆盖）仍全绿。⚠️ 它的检查 D 里 `g_curATR` **本来就是 exempt 项**（理由写的是"同一 bar 全量重算时可能陈旧 —— 已知、接受"）—— 这正是 R4 的盲区：豁免的是"没进指纹"，而漏掉的是"早退路径压根不赋值"，两者在报告里长得一样 |
| **行为** | **`Indictor/kernel_sim_nodeflip.ps1`（本轮新增）** | **`RESULT: PASS`**；`s58=4 处违反 / s59=10 处违反 / s60=0 处违反` | **唯一能真跑**的行为证据：三档判据 × 三种配对并行重算，拿**输入文档**当期望值。s58 列复现 C1（违反全在 `RETRACE`）、s59 列复现 R2（违反全在 `EXTREME`/`LEG`）、s60 列零违反。**它证明"判据真值表与文档一致"，不证明"MT5 会这样跑"** |

> **检查器自身的验证**（按仓库"只跑一次通过不算验证过检查器"的规矩）：新脚本的"故意破坏"
> 就是它自己的 **s58 / s59 两列** —— 它们必须是"违反 > 0"，若哪天变成 0，脚本会打
> `META FAIL: … does not reproduce defect …` 并 `exit 1`。本条已实测：第一版把布尔与字符串
> 混比，四列同时报 24 处违反、脚本立刻 FAIL 退出；改对后为 `4 / 10 / 0`。

**未能验证的（如实列出）**：编译与部署已验（见上表第 1 行），但 **`v1.50-s60` 还没有在终端里
跑过** —— 部署时读到的最后一行 INIT 仍是 `build=v1.50-s59 ... (XAUUSD.ct,M5)`，即**这个终端
当前加载的还是 s59**。故以下三项仍需你实机确认：

1. **R1**：把 `InpAnalysisWindow` 设成 `2` 重新挂载 —— 应当**被拒绝加载并打印原因**（改前是静默全灭）；
   再设回 `0`/`500` 应正常加载。这一条**顺带就是**"s60 真的被加载了"的判据（INIT 行会打 `build=v1.50-s60`）。
2. **R2**：`InpNodeFlipMode = EXTREME` 与 `LEG` 各导一份 CSV，两档的 CHoCH 条数应当**显著不同**
   （LEG 最严 ⇒ 最少）；默认档 `RETRACE` 的 CSV 应与 s59 逐字一致（行为刻意保持不变）。
3. **R3**：按上面的**可证伪预测**做一次新旧 CSV diff —— 只应多出/移动 `type=BOS` 的行。

## 本轮**没有**处置的项（附原因）

正文"上轮列为遗留/待裁定"那一节的 7 项**全部未动**：

- **B3（同 bar 双破的"当根零事件"）**、**`DisplacedBeyond` 在门槛前写 `g_lastBodyATR`**：
  都要先定"双破该报哪个" / "CSV 数值口径能否改"，属**改事件集合或改归档口径**的取舍；
- **`LevelMarkedByBreak` 同位去重口径不成立**：要选"按位比还是按节点比"，同样是口径决定；
- **`InpMinSeparationATR` 在 `MODE_FRACTAL_SWING` 静默失效**：只需补输入说明，但会改输入项文案；
- **`FindBrokenNodeBar` 的恒真 `bind=` 自检**、**顶层注释 `:44-47` 的方向叙述**：不影响行为；
- **3 条 UNPROVEN**（历史回放 O(N²)、WICK 下的 `broken` 语义、`atr <= 0` 绕过位移门槛）：
  都需要真机或双基线 diff 才能定案。

需要哪一条就说一声；其中 B3 与 `LevelMarkedByBreak` 建议**先定口径再动代码**。

## 本次修复过程中我自己的两处错误（完整披露，按仓库惯例）

| # | 我写错的 | 怎么暴露的 | 性质 |
|---|---|---|---|
| ① | 新脚本第一版的违反计数把**布尔期望值**与**字符串结果**相比（`'flip' -ne $true` 恒真）⇒ 四列同时报"24 处违反"，即**s60 列也会报错** | **脚本自己的断言**：末行打出 `META FAIL: s60 column violates the documentation` 并 `exit 1` | 逻辑错，**被检查器抓住** —— 这正是"检查器必须有区分力、且被验证过"那条纪律的价值：如果它只会说 PASS，这个 bug 会一直躺在"全绿"的假象里 |
| ② | 往 `Indictor/kernel_sim_choch.ps1` 的更正抬头里写了一个 `⚠️`（U+26A0 U+FE0F），而**该文件头部第一句就写着** `NOTE: pure ASCII only (PS 5.1 reads BOM-less .ps1 as ANSI)` | 逐字节扫描（`ReadAllBytes` 统计 `>127` 的字节）⇒ 6 个非 ASCII 字节 | 违反仓库**明文硬约定**；同族的 `kernel_sim_sweep.ps1` 历史上已经因为这条被回改过一次（见 git log `2549c04`）。已改回 `!!` |

> 两条都不是"编译/工具能兜住"的错：①是**自证式**的（检查器喊了才看见），②只有**按仓库自己的约定去扫**才发现。
> 记下来的用处是：下一个改这些文件的人应当先跑一次字节扫描，再跑一遍两个 sim。
