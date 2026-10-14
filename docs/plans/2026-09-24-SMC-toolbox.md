# TradFi_SMC_Toolbox 实施计划

> 新建**独立**指标 `Indictor/SMC_Toolbox.mq5`（SMC = Smart Money Concepts 工具箱）。
> 与既有 `Indictor/Structure.mq5`（TTrades/ICT 口径，v1.50）**并存不合并**：
> 两者的结构定义不同源（见下「口径分歧」），合并会让两套口径互相污染。

## 1. 为什么是独立指标而不是扩展 TradFi_Structure

| 维度 | TradFi_Structure | TradFi_SMC_Toolbox |
|---|---|---|
| 口径来源 | TTrades 一手文章（有逐字引文） | SMC 行业通行读法（**多数无一手权威**） |
| 结构层数 | 单层（short / intermediate 是**质量分级**，不是两层结构） | **双层**：swing 层 + internal 层，各自独立跑状态机 |
| 反转术语 | MSS（TTrades 用语，全站零命中 CHoCH） | CHoCH（SMC 通行术语） |
| 枢轴检测 | 三点分形（len 固定 = 1） | 参数化对称窗口（swing=50 / internal=5） |
| OB 定义 | 由 CISD 造势序列派生（TTrades） | BOS/CHoCH 前最后一根反向 K 线（SMC 通行） |
| 对象前缀 | `Structure_` | `SMCToolbox_`（**必须不同**，否则两者互相回收对象） |

结论：**新建文件**。可复用的是**工程骨架**（五层分层 / 调和式场景同步 / needDraw 门控 / CSV 自描述头 / 硬约定），**不是**结构语义。

## 2. 模块清单（用户全选，10 项）

按依赖顺序编号，便于定位问题：

| # | 模块 | 依赖 | 说明 |
|---|---|---|---|
| M1 | 摆动点检测（双层枢轴） | — | 对称窗口枢轴，延迟 `len` 根确认 |
| M2 | 市场结构 BOS / CHoCH | M1 | swing 层 + internal 层各自独立状态机 |
| M3 | 摆动点标签 HH/HL/LH/LL | M1, M2 | 纯渲染，按当前趋势给枢轴贴标签 |
| M4 | 订单块 OB（缓解 / 失效） | M2 | 每个结构事件派生一个 OB |
| M5 | FVG（含 IFVG 反转） | — | 三根 K 线缺口；后验算回补与反转 |
| M6 | EQH / EQL（流动性池） | M1 | 同类型枢轴聚类 |
| M7 | 流动性扫荡 / 诱导（Sweep / IDM） | M1, M2, M6 | 扫荡 = 影线越位收盘收回；IDM = 事件前的反向内部枢轴 |
| M8 | Premium / Discount + EQ | M1 | 最近波段枢轴高/低构成区间 |
| M9 | 强/弱高低点 | M1, M2 | 两种口径（见 §4.3）可选 |
| M10 | Killzone 时段（亚洲/伦敦/纽约） | — | 按纽约时间切段，服务器时间换算 |
| M11 | 多周期结构叠加 | M1, M2 | 高周期跑同一套分析，映射回本图时间轴 |

## 3. 架构（沿用仓库既有五层）

```
OnCalculate
 ├─ ArraySetAsSeries(显式锁定 0 = 最新)
 ├─ 快路径：同 bar tick 且 InpReuseResultOnTick → 直接 return
 └─ 全量路径
     ├─ 分析层 ComputeSMC()     纯输入 K 线 + 参数 → SMCResult
     │    ├─ CalcATRSeries()
     │    ├─ AnalyzeStructure()   ← 同一函数被本图与高周期各调一次
     │    ├─ ComputeZones()       OB + FVG（含后验缓解/回补/反转）
     │    ├─ ComputeEqLevels()
     │    ├─ ComputeSweepsIdm()
     │    ├─ ComputePremiumDiscount()
     │    ├─ ComputeStrongWeak()
     │    └─ ComputeKillzones()
     ├─ 场景层 RenderScene()     调和式同步 + needDraw 门控 + 未注册即回收
     └─ 导出层 DumpEvents()      CSV 自描述头（InpDumpEvents）
```

**结果层**：`SMCResult` 持有分类型数组（枢轴 / 结构事件 / 区间 / 相等位 / 扫荡 / 诱导 / killzone 段），一条记录一个 struct，不用平行数组。

## 4. 关键口径决策（**含"无一手依据"的显式标注**）

### 4.1 枢轴：对称窗口 + 延迟确认

`p` 是枢轴高 ⟺ `high[p]` 严格大于 `[p-len, p+len]` 内其余每一根的 high。
确认时刻 = bar `p-len`（右窗口走完）。**因此不可能有未来函数**，且**首根突破不可能发生在确认当根**
（因为 `high[p]` 是该窗口最大值，`close[p-len] ≤ high[p-len] ≤ high[p]`）。

> 自检等式（可离线验算）：`pivotConfirmBar == pivotBar - len`。
> 若某枢轴的确认 bar 不等于 `pivotBar - len`，说明窗口边界写错了。

**warm-up**：分析窗口最旧的 `len` 根不产生枢轴（右窗口不完整），**不用窗口外的数据去补**。
代价是窗口最旧端少一段结构；收益是不引入"窗口滑动改变历史事件"的重绘。

### 4.2 首次突破的标签 = BOS（**不是** CHoCH）

`trend == 0`（尚无方向）时出现首次突破，标为 **BOS**。
理由：CHoCH 的字面含义是"性格发生**改变**"，而此处没有"前一种性格"可改变。
标成 CHoCH 等于声称了一次无法验证的反转。**如实标注优先于对称美观。**
（多数 SMC 指标在此处标 CHoCH —— 这是本实现与它们的一处**有意差异**，写进 CSV 头。）

### 4.3 强/弱高低点：**该术语没有权威口径**，只实现两套有出处的读法

独立调研（`docs/research/2026-09-24-SMC-terms-research.md` §1）的实证结论：

- LuxAlgo 官方 Library 的 **54 个 SMC/ICT 概念**里**没有** Strong/Weak High/Low；
- ICTKillzone 的 **115 条 ICT 术语表**也**不收录**该术语，它用的是 STH/ITH/LTH 递归三档；
- 调阅的三份可读实现（Quantum、Black Tie、LuxAlgo Python 移植）**没有一份输出强/弱标签**。

社区里存在两套**结论相反**的读法，且无人裁决：

| 模式 | 判定轴 | 含义 |
|---|---|---|
| `SMC_SW_SWEPT_IS_WEAK`（**默认**） | 该枢轴**是否已被价格越过** | 已越过 = 流动性已耗 = 不再是要取的目标 = **弱** |
| `SMC_SW_DISPLACED_IS_STRONG` | 该枢轴之后是否出现**过位移门槛的反向破位** | 有 = 它保护住了趋势 = **强** |

选默认的理由：C-2 有可机械判定的真值条件，不依赖趋势状态，不会自己漂移。
C-1 复用本工具**同一条**位移门槛（`InpMinDisplaceBodyATR`），保证与结构事件的"强/弱"口径一致。

> ⚠️ **初版曾有一个 `SMC_SW_TREND_RELATIVE`（"顺趋势那侧为弱"）—— 已删除。**
> 那是从 ICT 口头措辞凭印象推的，**调研查不到任何出处**，属于"把自己的取舍伪装成标准"。
> 这是本文件唯一一次自我否决的设计，留在这里作为记录。

### 4.4 同 bar 双破（外包 K 线）

一根 bar 同时越过高点与低点时的先后顺序**无法从 OHLC 判定**（MQL5 无 tick 顺序）。
沿用仓库既有近似：**阳线（close ≥ open）→ 低先高后 → 终态取向上突破；阴线反之。**

⚠️ 调研（§5）指出这是**主流实现的共同缺口**：它们靠"收盘价不可能同时高于 A 又低于 B"
这个**几何巧合**隐式保证互斥，而非显式优先级；一旦高/低位倒挂，两个分支会同时执行、
趋势被后写覆盖。本实现做两件事：

1. **显式倒挂守卫**：`hiPrice <= loPrice` 时判定为畸形态，丢弃该状态重建，不做破位判定，
   并计入 `g_dbgInverted`（诊断日志可见）；
2. 双破时把 `CONFLICT(bothSidesBroke)` 写进 CSV 的 `extra` 列 —— **不隐藏"这里其实有歧义"**。

### 4.5 OB 区间基准：默认 **HYBRID**（影线全幅 + 实体 50% 中线）

调研（§3）引 LuxAlgo「Order Block Anatomy」官方原文：
> "exactly which prices bound the zone (the full range including wicks, or bodies only)
> … **conventions genuinely differ here.**" / "**None of this is standardized.**"

三种都属一线主流：全幅（Quantum）、实体、混合（Black Tie / ICTKillzone 教学）。
LuxAlgo 点名 mixed/hybrid 为 "common hybrid"。故默认 HYBRID：**影线全幅作区间，实体并集的 50% 作均值门槛线**。

> 依据（调研 §3b）：LuxAlgo 与 ICTKillzone 都指向 "body 的 50%"，**而 Quantum 用全幅 50% —— 数值不同**。
> 所以这条线必须**显式画出来**，不能让它成为隐藏假设。

**连续反向 K 线合并**（`InpOBCluster`，默认 3）：调研指出 LuxAlgo 给出两种合法做法，
合并整簇更稳、不易漏掉实际被回测的区域。

⚠️ 与仓库既有的 TTrades 口径（`Structure` 的 CISD 派生 OB，实体并集）**不是同一个东西**：
那边是"造势序列"，这边是"破位前最后一根反向 K 线"。两者都提供，默认取 SMC 通行读法。

### 4.6 有效位（consumed）与扫荡的关系

- **扫荡（sweep）不消耗结构位** —— 影线越位但收盘收回，只记一次 `SWEEP`，**该位仍然有效**，
  后续真正的收盘突破照样能出 BOS/CHoCH。
- **只有收盘（或影线，按 `InpBreakConfirm`）越位才消耗该位。**
理由同仓库既有纪律：否则一次扫影线会永久吃掉一个结构位，后续真突破再也出不来（丢信号）。

### 4.7 Killzone 时区换算：**不用固定偏移**，用 `TimeGMT()` + 美国 DST 规则

输入用**纽约时间**表达（ICT 惯例）。换算默认走自动模式：

```
srvOff = (TimeTradeServer() − TimeGMT()) / 3600        // 反推，不假设 GMT+2/+3
nyOff  = IsUsDst(now) ? −4 : −5                        // 3月第2周日 ~ 11月第1周日 = EDT
shift  = srvOff − nyOff                                // 纽约 = 服务器 − shift
```

> ⚠️ 调研（§9b）指出：**broker 多数跟随欧洲 DST、纽约跟随美国 DST**，两者切换日期
> 每年相差约 3 周 —— **固定偏移在那几周里必然错 1 小时**，且错得看不出来（框整体平移一格）。
> 这是本项从初版的"固定 `InpKzNYShiftHours`"改成自动的**唯一原因**。
>
> **已知限制（如实声明）**：
> 1. `TimeGMT()` 依赖**本机时钟与时区设置**，在策略测试器里可能不准 → 提供 `InpKzAutoTZ=false` 手动覆盖；
> 2. DST 只判到**日**粒度（不判 02:00 本地那一刻）→ 一年两次、各 2 小时的边界误差。
>    要精确到分钟需完整时区库，MT5 不提供。
>
> **时段集合本身也无权威口径**：LuxAlgo 自认其集合"most widely cited"但明说
> "Window boundaries differ by 30 to 90 minutes across ICT sources"。故三个时段全部可编辑。

### 4.8 时间段的边界与跳空

连续同 session 的 bar 归为一段。**额外加时间间隔守卫**（`InpKzMaxGapMin`，默认 120 分钟）：
相邻 bar 时间差超过该值即强行切段。否则**周末跳空会把周五尾盘与周一开盘并成同一个矩形**。

> 单根 bar 的时段（`segEnd == segStart`）**不生成矩形** —— 零宽矩形画不出东西，
> 只会白占一个对象名额。

### 4.9 IFVG：**按权威口径写死，不设开关**

调研（§7）确认这是本工具箱里**少数有逐字一致权威依据**的项：

> LuxAlgo："The common requirement is a candle **body closing beyond the far side of the gap**;
> a **wick-through alone is usually read as a probe**."
> ICTKillzone：影线完整穿过但收盘回内侧 → **FVG 守住**；**实体收盘越过远端边缘** → 反转。

故实现为 `close` 与远端比较（`close` 即实体边界），**影线永不算**。
**CE 是成立之后的入场位，不是判定条件** —— 因此**不存在**"收盘穿 CE 即反转"的宽松档。

> ⚠️ 初版曾提供一个 `InpIFvgRequireCloseThrough` 开关（关掉即退化为穿 CE）。
> 既然调研给出了逐字一致的答案，**留一个"更宽松但没人这么用"的档只会制造歧义** → 已删除。

### 4.10 EQH/EQL 挂在哪一层：**默认内部层**（实测决定，不是偏好）

实测（`tools/smc_logic_sim.py`）同类型相邻枢轴的 bar 距离：

| 层级 | 距离最小值 | 中位数 | 最大值 |
|---|---|---|---|
| 波段层（len=50） | 60 | **130** | 303 |
| 内部层（len=5） | 6 | **13** | 57 |

波段层枢轴间距远超任何合理的"相等"窗口 → 挂波段层时 **EQ 几乎恒为 0**
（实测 500 根窗口 0 个、2000 根窗口 0~3 个）。内部层能正常成池（7~29 个）。

故 `InpEqTier` 默认 `SMC_EQ_INTERNAL`，并提供 `SWING` / `BOTH`。
**容差**取 `0.15 × ATR`（可考实现实测范围 0.10 Black Tie ~ 0.25 Quantum，取中间偏严）。
**画成容差带而非线** —— LuxAlgo 明确建议 band，因为一条线会让人误以为"必须精确相等"。

### 4.11 两层结构 ≠ ICT 的递归分级（必须如实声明）

本文件的 swing / internal 两层**只是两个不同半窗的枢轴检测器**。
调研（§10）引用 ICTKillzone 的明确警告：

> "Beware indicators that claim to mark 'major structure' directly — most use lookback windows
> rather than the recursive rule, and **they disagree with the hierarchy exactly where it matters**."

真正的 ICT 分级是**递归晋升**（三点分形 → STH；两侧更低的 STH → ITH；两侧更低的 ITH → LTH），
与"把窗口调大"不是一回事。**本工具不声称实现该分级**，CSV 头里写明
`TIER-IS-WINDOW-BASED-NOT-ICT-RECURSIVE-HIERARCHY`。要做递归分级需另开一轮（见 §9 未做项）。

### 4.12 Pivot 半窗默认 15（**不是** LuxAlgo 的 50）

依据是实测而非偏好。仿真（`tools/smc_logic_sim.py`，500 根分析窗口）：

| swingLen | 枢轴数 | 结构事件 | BOS | CHoCH |
|---|---|---|---|---|
| 50 | 4 | **1** | 1 | 0 |
| 20 | 10 | 5 | 3 | 2 |
| **15** | **17** | **9** | 7 | 2 |
| 10 | 32 | 16 | 11 | 5 |

`swingLen=50` 意味着枢轴要等 **50 根 K 线**才成立，在 500~2000 根窗口里几乎不出结构事件
（图上看起来就是"结构模块没在跑"）。可考实现的取值范围是 3~50，全部合法；
默认取 Quantum 的 **15/5** 是"有出处 + 确认延迟可接受"的折中。

## 5. 硬约定（继承仓库，逐条对应到本文件）

1. `OnCalculate` 入口显式 `ArraySetAsSeries(..., true)`。**不依赖终端默认方向。**
2. **禁止把有副作用的调用写在 `||` / `&&` 右侧**（MQL5 短路）。一律 `if(Upsert*()) changed = true;`
3. **新增可视化元素必须同时**：进 `needDraw` 指纹 + 调 `AddSceneName()`。
   漏前者 → 要等下一根 bar 才出现；漏后者 → 被回收段当过期对象删掉。
4. **每次改动递增 `BUILD_TAG`**，它只出现在 INIT 日志与 CSV 头部。
5. 日志里的版本号**只打印 `BUILD_TAG`**，不写版本字面量。
6. 对象前缀 `SMCToolbox_`，`OnDeinit` 用 `ObjectsDeleteAll(0, OBJ_PREFIX)` 清理。
7. **诊断输出不得落在每 tick 路径上。**
8. **新增门控必须验证条件真的可达**（不许出现永不成立的合取项）。

## 6. 验收判据（可证伪）

本指标**没有历史基线可比**（新文件），故第一次的验收是**建立基线**。已有两个可重复执行的检查器：

| 工具 | 作用 | 当前结果 |
|---|---|---|
| `MetaEditor64 /compile` | 语法与类型 | **0 errors, 0 warnings** |
| `tools/smc_logic_sim.py` | 核心算法**逐行移植**后跑分布判据 | **全部通过**（见下） |
| `tools/check_csv_columns.py` | CSV 每条行格式的字段数 = 表头字段数 | **8/8 一致（17 字段）** |

- **A1 编译**：`Result:` 行出现 `0 errors`。
- **A2 自检等式**：`InpDebugShowRef=true` 时日志必须打印 `invariantViolations=0`。
- **A3 分布合理性**（`smc_logic_sim.py` 的硬判据，防止"方向写反"这类静默错误）：
  - **FVG 方向侧检查**：缺口在确认那根时价格必须在**正确一侧**
    （看涨 → `close ≥ 上方沿`；看跌 → `close ≤ 下方沿`）。
    这是构造性恒等式，**必须恒为 0 次违反**。仓库历史上正是栽在这里
    （两个分支的 `dir` 写反 → 价格本就在另一侧 → 全部缺口瞬间"已回补"）。
    实测 `sideBad=0`。
  - 盘整行情下两个方向的缺口都必须出现（实测 up/dn 均 280~300）。
  - `fillPct` 必须是连续谱（实测 full/part/open = 5715/396/741）。
  - BOS 与 CHoCH 都必须存在（实测聚合 BOS=188 / CHoCH=160）。
  - 枢轴**独立复核**：用"取窗口极值再比较"的**不同构**写法重算，必须一致（实测 0 不符）。
- **A4 渲染改动隔离**：纯渲染开关翻转时，**事件 CSV 的全部数据行必须逐字不变**，
  只有头部 `# render` 行不同。
- **A5 事件 CSV 逐行 diff**：改动前后各导出一份，逐行比对并归因到具体模块。

### 已实测出的参数结论（写进默认值，不是偏好）

| 结论 | 证据 |
|---|---|
| `swingLen` 默认 **15** 而非 LuxAlgo 的 50 | 500 根窗口下 50 → 1 个事件；15 → 9 个（§4.12） |
| EQH/EQL 默认挂**内部层** | 波段层枢轴间距中位数 130 根 → EQ 恒为 0；内部层 13 根 → 正常成池（§4.10） |
| `InpFvgHideFilled` 默认 **false** | 实测 **83%** 的缺口最终会被完全穿透（5715/6852）→ 默认隐藏等于出厂抹掉六分之五 |
| `InpEqToleranceATR` 默认 **0.15** | 可考实现范围 0.10~0.25，取中间偏严 |
| `InpAnalysisWindow` 默认 **2000** | 500 根窗口下结构事件仅 9 个；2000 根出 33~41 个 |

## 7. 已知边界（如实声明，不假装做到）

1. **SMC 术语多数无一手权威** —— 除 IFVG 判定、OB 缓解/失效、BOS/CHoCH 状态机、
   killzone 以纽约时间为锚这四项外，**OB 区间基准、强/弱高低点、诱导判定、
   dealing range 端点、EQ 容差、pivot 默认值**在各家实现里**互相冲突**。
   本文件凡涉及处均标注，并写进 CSV 头。
2. **多周期结构只做映射，不做门禁** —— 高周期结构线只是画在本图时间轴上，**不参与**本图任何判定。
3. **两层结构不是 ICT 递归分级**（见 §4.11）。
4. **不做回测/胜率统计** —— 本指标是可视化工具箱，不含信号统计。
5. **warm-up 损失**：分析窗口最旧 `len` 根无枢轴（见 §4.1）。
6. **`TimeGMT()` 在策略测试器里可能不准**（见 §4.7）。
7. **OB 的 Breaker 改标未实现** —— 调研指出多数实现把"被实体收盘穿透的 OB"改标为
   Breaker Block。本实现只标 `state=INVALID`，不画 Breaker（见 §9）。
8. **ICT 的 OTE 带（62%~79%）未实现**（见 §9）。

## 8. 独立调研结论的采纳清单

调研报告：`docs/research/2026-09-24-SMC-terms-research.md`（一手来源优先，
LuxAlgo 官方 Library/文档 + 两份可读 Pine 源码 + ICTKillzone 术语表）。

| # | 调研结论 | 采纳动作 |
|---|---|---|
| 1 | 强/弱高低点**无任何权威口径**（LuxAlgo 54 概念、ICTKillzone 115 术语均不收录） | 删除自造的第三种读法，只留两套**有出处**的；默认机械可判定的 C-2 |
| 2 | EQH/EQL 容差无官方默认；实测 0.10~0.25 ATR | 默认 **0.15**；并**实测发现必须挂内部层**（§4.10） |
| 2b | LuxAlgo 建议画成 **band** 而非线 | 采纳 `InpEqDrawBand` 默认开 |
| 3 | OB 区间"**conventions genuinely differ**"，hybrid 是常见做法 | 默认 **HYBRID**（影线全幅 + 实体 50% 中线） |
| 3b | 均值门槛 body-50% vs full-range-50% **数值不同** | 显式画出该线（`_MT` 对象），不让它成为隐藏假设 |
| 3c | 连续反向 K 线合并是合法做法之一 | 采纳 `InpOBCluster` 默认 3 |
| 4 | OB 缓解=触及、失效=实体收盘穿远端，**两个并存状态** | 已是此实现；默认**不隐藏**已缓解/已失效（只改配色与 state） |
| 5 | 同 bar BOS+CHoCH 优先级**无权威口径**，主流靠几何巧合 | 加**显式倒挂守卫** + CSV 记 `CONFLICT`（§4.4） |
| 5b | `trend==0` 首次突破标什么无权威口径 | 保持 **BOS** 并写进 CSV 头 |
| 6 | IDM 是**角色标签**，严格/宽松是分类学分歧 | 保持严格口径（事件前最后一个反向内部枢轴），声明不门禁 Z |
| 7 | IFVG = **实体收盘穿越整个缺口**，两家逐字一致 | **写死，删除宽松开关**（§4.9） |
| 9 | Killzone 边界各家差 30~90 分钟；**须按美国 DST 换算** | 三个时段全可编辑；换算改自动 DST（§4.7） |
| 10 | pivot 确认延迟=右窗口；实测默认值 3~50 | 取 **15/5**（实测 50 在可用窗口内几乎不出事件，§4.12） |
| 10b | 用窗口冒充"major structure"是常见误导 | **明确声明不实现 ICT 递归分级**（§4.11） |

## 9. 明确未做（不假装做到）

1. **ICT 递归分级（STH / ITH / LTH）** —— 调研（§10b）称这是"让工具箱区别于普通 SMC 指标的关键能力"，
   但它是**独立算法**（递归晋升），不是把 pivot 窗口调大。工作量大且会改变全部结构语义，
   需单开一轮并按仓库纪律重测基线。
2. **OB → Breaker Block 改标** —— 需在 `SMCZone` 上加 `breaker` 状态与一套新渲染。
3. **OTE 带（0.62 / 0.705 / 0.79）** —— 调研给出锚定规则（扫荡 wick 极值 → 位移极值），
   未实现。
4. **Premium/Discount 的 0.25 / 0.75 四分位带** —— LuxAlgo 建议，未实现。
5. **Liquidity void / 未被回补的失衡区** 等 LuxAlgo 54 概念中的其余条目。
6. **策略测试器实证** —— 本机无 MT5 历史回放环境，全部验收止于
   「编译 0 错 0 警告 + 逐行移植仿真 + 静态列数检查」。**真机读图验收需要用户完成。**
