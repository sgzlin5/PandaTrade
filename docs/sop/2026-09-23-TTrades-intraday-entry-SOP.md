# TTrades 日内入场 SOP

> **版本**：v1（2026-09-23）· 对应指标 `Structure.mq5` `v1.49-s14b`
> **依据**：`docs/research/2026-09-23-TTrades-structure.md`（一手语料取证），
> 一手来源清单见本文件 §14。
>
> **编制与核验过程（如实记录，共三步）**：
> 1. 初稿里有一句 *"You can have the POI, you can have the reaction, but without displacement
>    and a valid Candle 2 or Candle 3 closure, it is not a trade."* —— **这句是我编的**，
>    任何一手材料里都不存在。已删除。**逐字引文宁可少，不可造。**
> 2. 机械自检把本文件所有英文引文与归档比对，发现 5 处**未回填到研究文档**（属归档不完整）。
>    已补录为研究文档 §15 —— ⚠️ **但 §15 是从本文件回填的，属"自证循环"，
>    不能用来证明本文件的引文可溯源。**
> 3. 遂交**独立子代理重新抓取原始 URL** 逐句核验全部 60 处引文（研究 §15.5）。结论：
>    **50+ 处逐字或实质可溯源**；另查出并已修正 ——
>    **1 处不可溯源**（*"Price takes out yesterday's high but closes back inside the range"*，
>    研究 §15.4）、**1 处把摘要升格为【原文】**（§6 的 POI 箭号行）、
>    **4 处引号内改写**（项目符号被换成箭号 ×2、列表符换成 `/`、截断未加省略号）、
>    **2 处 §13 空白高估**。
>
> ⚠️ **其中一处是实质错误，不只是措辞**：初稿称"仓位与风险他完全没有"，
> 但 Playbook 明文 *"Target **2R** minimum"* / *"Minimum target: **2R** to remain profitable
> with >34% win rate"* —— **他给了盈亏比目标，只是不给仓位大小**。已更正（§13 第 5 项）。

---

## 0. 先读这一节：这份 SOP 的性质与证据等级

### 0.1 他**没有**发布过编号式的 SOP

TTrades 的全部一手材料是**文章 + 配套视频 + 配图**，讲的是逐个概念与配合关系，
**不存在一份"第 1 步…第 N 步"的入场清单**。本文件是**组装**，不是摘录。

因此每一条都标了证据等级，**不要把整份文件当作他的背书**：

| 标记 | 含义 |
|---|---|
| **【原文】** | 有他的一手逐字表述（或他本人配图）支撑，引用附在行内 |
| **【机械化】** | 他只有定性描述，**具体阈值/判定方式是我们定的** |
| **【空白】** | 他**从未提及**，是本 SOP 为可执行性补的，属我方添加 |
| **【存疑】** | 一手材料内部有张力，或存在两种同样合理的读法 |

### 0.2 一句话概括他的模型

> **高周期收盘先行 → 低周期交割状态改变（CISD）→ 然后才找延续。**
>
> 【原文】（**照原文的项目符号引用，箭号是本 SOP 的概括、不在引号内**）：
> > "The rules stay the same:
> >  - Higher time frame closure first
> >  - Lower time frame change in the state of delivery
> >  - Only then do we look for continuation."

---

## 1. 一页执行清单

**盘前（每交易日一次）**

- [ ] **① 定高周期偏置**：取上一根已收盘的高周期 K 线（默认 D1），与前一根比高低 → `BULL` / `BEAR` / `NONE`
- [ ] **② 偏置为 `NONE` → 当日不做。** *"Never drop to the hourly until you have a one-sided daily bias."*【原文】
- [ ] **③ 标出前日高/低（PDH/PDL）** 作为当日**流动性目标**（draw on liquidity）

**盘中（只在偏置方向上找机会）**

- [ ] **④ 定 dealing range**：从"你正在进行情的那个 swing" → "造出它的高周期 swing"，连成区间
- [ ] **⑤ 50% 对分**：上半 = premium，下半 = discount，中缝 = EQ
- [ ] **⑥ 位置过滤**：偏多看 discount / EQ 附近；偏空看 premium / EQ 附近
- [ ] **⑦ 找 POI（内部流动性）**：偏置方向上的 **FVG**（顺序：FVG → swing → CISD）
- [ ] **⑧ 等确认**：价格进 POI 后出现 **Candle 2 或 Candle 3 收盘** / **CISD**
- [ ] **⑨ 加分项**：该收盘**同时**造出 protected swing → **Ideal Formation**
- [ ] **⑩ 入场**：收盘入场 或 用延续 OB 接
- [ ] **⑪ 止损**：放在 **protected swing** 之外（它就是"必须守住"的那条边）
- [ ] **⑫ 目标**：**外部流动性（ERL）** = 对侧摆动位 / dealing range 对侧沿 / PDH-PDL
- [ ] **⑬ 剩余空间检查**：入场点到目标的距离**还够不够你的盈亏比**

**任一环节不成立 → 不做。** 尤其：**没有偏置、没有 POI、没有收盘确认，三者缺一即放弃。**

---

## 2. 周期栈：先确定你在哪三层

**【原文】** 他把分析分成三层并明确命名：

> "1. **Higher Time Frame (Bias)** – Determines market direction.
>  2. **Intermediate Time Frame (Structure)** – Confirms alignment with bias through
>  **change in state of delivery (CISD) and market structure**.
>  3. **Entry Time Frame (Entry)** – Provides the opportunity for executing the trades."
> — <https://ttrades.com/timeframe-alignment-how-to-align-higher-and-lower-time-frames-for-precision-entries/>

**【原文】** 他本人的周期配对表：

| 结构层 | 入场层 |
|---|---|
| Weekly | 4H |
| **Daily** | **1H** |
| 4H | 15M |
| **1H** | **5M** |
| 30M | 3M |
| 15M | 1M |

> *"For example, if I want a 5M entry, I align it with **1H structure** and **daily bias**."*

**【原文】** 首选组合：*"Start with the daily for bias, use the 4 hour to define the swing,
and execute with precision on the 15 minute chart."*

**【原文】** 硬性一致要求：*"**Only trade when all timeframes point in the same direction.**"*

**【原文】** 跨层否决权：
> "Even if you see a clean change in the state of delivery on a lower time frame,
> **if there is no candle 2 or candle 3 closure on the higher time frame, it is ignored.**"

**【机械化】** 本 SOP 默认 **D1（偏置）→ H1（结构）→ M5/M15（入场）**；
指标侧用 `InpBiasTF`（默认 `PERIOD_D1`）、`InpHTFPeriod`（默认 `PERIOD_D1`）承载。

> ⚠️ **【存疑】** "intermediate"在他材料里指**两个不同的东西**：
> (A) 同一张图上的 **intermediate-term 摆动层级**；
> (B) 多周期栈里的 **Intermediate Time Frame**（上面那张表的那一层）。
> 本节指的是 (B)。混用会直接带偏实现 —— 详见 research §12。

---

## 3. 第 ① 步：定高周期偏置（每天一次）

**【原文】** 他给的偏置规则是可机械化的：

> "If price **closes below the previous day's low** – Expect continuation lower.
>  If price **fails to close below the previous day's low** – Expect reversal higher.
>  **Same logic applies for previous day's high, but inverted.**"

→ 即：取上一根**已收盘**的高周期 K 线，与其**前一根**的高/低比较：

| 条件 | 偏置 |
|---|---|
| `close > 前根 high` | **BULL (+1)** |
| `close < 前根 low` | **BEAR (−1)** |
| 落在前根区间内 | 无新信息 → 继续向前回溯，取最近一次决定性收线 |

**【机械化】** 回溯上限 `InpBiasLookback`（默认 20 根）；回溯不到 → `NONE`。

**【原文】** 单边要求：*"Never drop to the hourly until you have a one-sided daily bias."*

**【机械化】** 指标里 `BIAS` 标签实时显示当前偏置值。
**偏置为 `NONE` 时，MSS / BOS / CISD 与 PD Array 的弱化规则照旧，但按本 SOP 应当日不做。**

### 3.1 为什么偏置是**第一位**的

**【原文】** 偏置还是**加分项的条件之一**：
> "The rules stay the same:
>  - Higher time frame closure first
>  - Lower time frame change in the state of delivery
>  - Only then do we look for continuation."

**【原文】** 反例警告：
> "A lower time frame 'trend shift' is just a pullback into a discount or premium area
> on a higher time frame."

→ 低周期上漂亮的"趋势反转"，在高周期上常常只是**一次回撤**。这是本 SOP 把偏置放在第①步的原因。

---

## 4. 第 ② 步：标出前日高/低（PDH / PDL）作为目标

**【原文】** 他把前日高低点当作**流动性目标**（draw on liquidity）：

> "Failure to **displace above previous day high** suggests a bearish bias toward
> **previous day low**." — <https://ttrades.com/the-easiest-draw-on-liquidity/>

> ⚠️ **本节曾引两句，均已撤回**：
> 1. *"Price takes out yesterday's high but closes back inside the range"* —— **不可溯源**
>    （独立抓取 `the-easiest-draw-on-liquidity` 全文无此句）。**已删除。**
> 2. *"price sweeps the previous candle's high or low and then closes back inside that range"* ——
>    这句**可溯源**，但它出自 CISD 篇、讲的是 **candle 2 closure 与扫荡**，
>    **不是前日高低点**。初稿把它放在本节属**错误归属**，已移出。
>    （该句的正当落点是 §7.3「扫荡不是确认」，那里已引用。）

**【机械化】** 指标 `PDH` / `PDL` 两条点线；取"最近一根**已收盘**"的 D1 K 线
（按**日期**判定，不写死 `shift=1` —— 服务器刚换日、当日 K 线未生成时 `shift=0` 才是最近一根）。

---

## 5. 第 ③ 步：定 dealing range，并用 premium / discount 做位置过滤

**【原文】** 构造法（本 SOP 认为这是他最容易被忽略的一条）：

> "A dealing range is the range between **the swing point you are trading away from**
>  and **the higher timeframe swing you are trading toward**."
> "For a **bullish** range, start with the **low you are trading away from**.
>  Find the **higher timeframe swing high that made that low** and mark the range."
> "For a **bearish** range, start with the high you are trading away from.
>  Find the higher timeframe swing low that made that high and mark the range."

**【原文】** 分区与用法：

> "**Split the dealing range at 50%.** The **upper half is premium**. The **lower half is discount**.
>  **EQ sits in the middle.**"
> "For bullish setups, look for longs in **discount or around EQ**.
>  For bearish setups, look for shorts in **premium or around EQ**."

**【原文】** 目的一半来自区间：*"The dealing range high is **the target** for a bullish range."*

**【原文】** 为什么在意位置：
> "If you are long from **discount**, you have **more range** between your entry and the
> dealing range high. If you are long from **premium**, you are already closer to the target."
> "The setup **can still work from a poor location**. The issue is **how much range is left
> for the trade**."

**【原文】** 区间可以叠加：*"Multiple dealing ranges **can overlap**."*
（低周期 setup 可以落在高周期区间的同一个分区里 → 位置更好）

> ⚠️ **【机械化】且这是本指标目前的已知偏差**：指标画的 `RANGE` 用的是
> "3 根高周期 K 线的极值"，**不是**上面那条构造法（"你在行情的 swing + 造出它的高周期 swing"）。
> 分区算法（50% 对分）与他一致，**被对分的那条区间不是他的 dealing range**。
> 详见 `docs/plans/2026-09-23-TTrades-alignment.md` §21（D31）。

**位置过滤的判定（本 SOP 操作化）**：§4 的 dealing range 画好后，
当前价位于哪一半是硬约束 ——
**偏多但在 premium → 位置差，要么等回撤到 discount/EQ，要么放弃。**

---

## 6. 第 ④ 步：找 POI = 内部流动性（IRL）

**【原文】** 他的定义干净到几乎可编码：

> "**Internal liquidity is a fair value gap.**"
> "**External liquidity is a swing high or swing low.**"
> "**Internal liquidity provides the point of interest. External liquidity provides the target.**"
> — <https://ttrades.com/internal-external-liquidity-using-the-ttrades-fractal-model/>

**【摘要】** POI 优先级 —— ⚠️ **下面这句箭号行是本 SOP 的摘要，不是他的话**。
他的顺序写成**三句散句**，从没有过这样一行；初稿给摘要加了引号并标【原文】，已更正：

> **① FVG → ② swing high/low → ③ CISD**（本 SOP 摘要）

**【原文】** 他真正的三句原话（出处同下）：

> "The first point of interest to look for is a **Fair Value Gap**."
> "If there isn't a Fair Value Gap, the next point of interest becomes a **swing high or swing low**."
> "…the final point of interest becomes a **change in state of delivery (CISD)**."

**【原文】** 取哪一个 —— 他给的是**路径次序**（先 protected swing → 朝当前区间推进 → 取遇到的第一个）：

> "Start at the **protected swing**. Work toward the current range. Look for a Fair Value Gap first."
> "If a Fair Value Gap exists **between the protected swing and the current range**, it becomes
>  the point of interest."

> ⚠️ **他给的是路径次序，缺的是"距离度量口径"**（多远算"在路径上"）——
> 初稿 §13 曾写成"他未给规则"，属**高估空白**，已更正。
> — <https://ttrades.com/the-only-points-of-interest-that-actually-matter-for-trading/>

**【原文】** 但**POI 本身不是入场理由**，确认必须来自收盘反应：

> "**A Point of Interest Doesn't Mean an Entry.**"
> "Simply having a fair value gap **does not mean price has to return to it**. …
>  **What matters is the reaction when price gets there.**"
> "The goal is to identify both and then use the fractal model to determine
>  **when the relationship is actually tradable**."
> "**wait for a valid Candle 2 or Candle 3 closure**"
> "The reaction and candle closure are **what give the move context**."
> — <https://ttrades.com/internal-external-liquidity-using-the-ttrades-fractal-model/>
> — POI 优先级与 *"A Point of Interest Doesn't Mean an Entry."* 见
>   <https://ttrades.com/the-only-points-of-interest-that-actually-matter-for-trading/>

**【机械化】** 指标 `IRL` 标签 = 偏置方向上、现价之外、未完全回补的最近 FVG 的靠近边；
`FVG` 色块 = 全部检出缺口。

**【机械化】** "第一个 POI"的**粒度**他未给规则（按时间？按距离？）——
本 SOP 取"**偏置方向、现价之外、最近的那个 FVG**"，指标不做优先级筛选。

---

## 7. 第 ⑤ 步：等确认 —— Candle 2/3 收盘 / CISD

### 7.1 Candle 编号（先对齐术语）

**【原文】** 他的编号系统：**Candle 1 = swing 点之前；Candle 2 = swing high/low 本身；
Candle 3 = Candle 2 之后；Candle 4 = Candle 3 之后。**

**【原文】** 有效收盘的判据：
> "If price **closes beyond Candle 1's body** but fails to close through the opposing
> candle series, then the protected swing has not been confirmed."
> "**Waiting one additional candle is one of the simplest and most effective filters
> you can use.**"
> "This **delayed confirmation** still signals a reversal or continuation depending on context."

**【原文】** 硬性要求：*"wait for a valid **Candle 2 or Candle 3 closure**"*

### 7.2 CISD —— 他真正的早期确认工具

**【原文】** 定义：
> "Instead of focusing on swing highs or lows, it focuses on **the opening price in the
> series of up-close or down-close candles**. When price **displaces and closes beyond
> that open**, it validates the level as an order block."
> "Bullish to Bearish: Price forms a series of up-close candles, then **closes below the
> opening price of those candles**."

**【原文】** 时序与定位：
> "Timing: **CISD often appears earlier than MSS** … CISD can give earlier entries but
> **sometimes too early, leading to false signals**. MSS is slower but often more conservative."

**【原文】** 标准次序：
> "1. Inversion or **CISD** shows early order flow weakness.
>  2. **MSS** confirms the structural shift.
>  3. Price retraces into a **premium or discount zone**, giving the best entry."

**【机械化】** 指标 `CISD` 事件：位 = 造势序列**最旧一根的开盘价**，**收盘穿越**即触发；
不做位移分级渲染之外的门槛（指标侧口径见 §8 的说明）。

### 7.3 ⚠️ 扫荡（sweep）不是确认

**【原文】** 这一条他反复强调，最直接的一句：
> "The close through that series of candles is what confirms the shift.
>  **The sweep itself is not the confirmation.**"
> — <https://ttrades.com/let-the-wick-form-trade-the-body-stop-getting-stopped-out/>

**【原文】** 扫荡在"典型序列"里出现，但是**样例**而非必要条件：
> "As long as you respect the same sequence — **raid, FVG, MSS/SMT** — the model remains valid."

→ **本 SOP 的立场：扫荡是背景，不是扳机。** 有扫荡更好，没有扫荡不构成否决。

---

## 8. 第 ⑥ 步：结构确认（MSS）—— 更慢但更保守

**【原文】** 定义：
> "It happens when price **displaces and closes** above or below a swing high or swing low."
> "Essentially, MSS marks a trend change **confirmed by displacement**."

**【机械化】** 本指标把"位移"实现为门槛（**他本人未给任何数值**）。
⚠️ **该处代码近期变动频繁，以下是 `v1.49-s14b` 的实际口径（已按代码核对，非照抄旧文档）**：

| 路径 | 生效条件 | 对应输入 |
|---|---|---|
| **MSS** | ① 破位 K 实体 ≥ `InpMinDisplaceBodyATR × ATR`；③ 首次影线穿越后 `InpDisplaceMaxBars` 根内完成收盘确认 | `InpMinDisplaceBodyATR`（默认 1.0）、`InpDisplaceMaxBars`（默认 3） |
| **CISD / OB** | ① + ③，**另加**「**触发 bar 起 N 根内出现同向 FVG**」 | 再加 `InpCisdFvgLookahead`（默认 5，0=关闭） |

⚠️ **原第②条「收盘穿越深度 ≥ `InpMinDisplacePenATR × ATR`」已被删除**，
`InpMinDisplacePenATR` **这个输入项已不存在**（该数值仍会写进 CSV 的 `pen=` 列供对照）。
删除过程：先在 MSS 路径去掉，随后 CISD 侧也换成上面的 FVG 条件。

⚠️ **破位确认方式另有一个输入** `InpBreakConfirm`（默认 `BREAK_WICK` = 影线触及即算破位；
另有 `BREAK_CLOSE` 收盘、`BREAK_BODY` 实体完全越过）。严格度为全序 `BODY ⊂ CLOSE ⊂ WICK`。
**注意**：`BREAK_WICK` 下"必须真的收在位外"这层把关**已不存在**，
故影线刺穿即可能触发（位移门槛仍需过）。

→ **CISD 与 MSS 的关系**：CISD 更早、更灵敏；MSS 更慢、更保守。
**两者并行存在、互不替代**【原文】。本 SOP 允许**只凭 CISD 入场**（更早），
但那句 *"sometimes too early, leading to false signals"* 是他的原话 —— 早入场要接受更多假信号。

---

## 9. 第 ⑦ 步：Ideal Formation（加分项，非必需）

**【原文】** 定义与价值：
> "An **Ideal Formation** occurs when a Candle 2 or Candle 3 closure **simultaneously creates
> a protected swing**."
> "A valid Candle 2 closure only becomes ideal when it **also creates a protected swing**."

**【原文】** 为什么它更好：
> "Because both confirmations occur on the same candle, **Candle 3 often becomes the expansion
> candle** traders look to participate in."

**【原文】** 形成后要标的两条关键位：
> "The first is the **opening price of the opposing candle series** that created the protected swing.
>  The second is the **equilibrium (EQ) of the confirmation candle**."

**【原文】** 但它**不能单独交易**：
> "An Ideal Formation **should never be traded as a standalone pattern**."
> 需要 POI（原文为列表）：
> > "Common examples include:
> >  - Fair Value Gaps (FVGs)
> >  - Liquidity sweeps
> >  - Previous highs and lows
> >  - Premium and discount arrays
> >  - Higher timeframe points of interest"

**【机械化】** 指标里对应：`CISD` 事件 + `OB` 色块（造势序列实体区间，其关键价位正是
"opposing candle series 的开盘价"）。

---

## 10. 第 ⑧–⑪ 步：入场、止损、目标

### 10.1 入场

**【原文】** 两种方式，他都提过：
> "**Positional entries** are ideal if you are unsure if a retracement will occur and you
> want to get onside."（不确定会不会回撤 → 收盘直接进）
> "With a CISD on the 5-minute chart and a **continuation OB, take entry on the close**."
> "**The entry does not always need to come directly from the higher timeframe.** …
>  The higher timeframe provides the expectation. The lower timeframe can provide the execution."

**【机械化】** 本 SOP 默认：**在确认收盘的那根入场**（收盘价成交）；
若价格已走远，等回撤到 **CE（FVG 中点）** 或 **OB 实体区间**再进。

### 10.2 止损 = protected swing

**【原文】** 定义与止损逻辑在**同一段**里：
> "A protected swing forms when price reaches an important level and then **closes through
> the series of candles** into that level."
> "If the expectation is bullish, the protected swing becomes **the low that should hold**.
>  If the expectation is bearish, the protected swing becomes **the high that should hold**."
> "**If price takes that protected swing, the assumption that the wick has formed is wrong,
>  and the trade is invalidated.**"

**【机械化】** 指标里 protected swing 的唯一写入点是 `SetProtectedFromCisd()` ——
**CISD 触发的那一刻就是 protected swing 成立的那一刻**。图上表现为 `CISD` 位所在结构线。

### 10.3 目标 = 外部流动性（ERL）

**【原文】** *"Internal liquidity provides the point of interest. **External liquidity provides the target.**"*

三个可用的目标，按优先级：

| 优先级 | 目标 | 依据 |
|---|---|---|
| 1 | **对侧摆动位（ERL）** | 偏置方向上最近的、**尚未被取走**的摆动高/低 |
| 2 | **dealing range 对侧沿** | *"The dealing range high is the target for a bullish range."* |
| 3 | **PDH / PDL** | *"Failure to displace above previous day high suggests a bearish bias toward previous day low."* |

**【原文】** 打过第一个目标之后：*"Once the first target is taken, **runners** can continue
toward the dealing range target."*

**【机械化】** 指标 `ERL` = 偏置方向上、现价之外、**尚未被取走**的最近摆动位
（"已被取走"的定义：该节点之后有任何 bar 越过它）。

### 10.4 剩余空间检查（这一条最容易漏）

**【原文】** *"The setup **can still work from a poor location**. The issue is
**how much range is left** for the trade."* / *"Enter with enough range between the entry
and the target to reach your risk reward."*

→ **本 SOP 的硬性收尾：入场前量一下"入场点 → 最近目标"还剩多少空间。
空间不足你的盈亏比 → 放弃，不管你多看好方向。**

---

## 11. 三张否决清单（满足任一即不做）

**A. 环境否决**
- 高周期偏置 = `NONE`（*"Never drop to the hourly until you have a one-sided daily bias."*）
- 三层周期方向不一致（*"Only trade when all timeframes point in the same direction."*）
- 高周期没有 Candle 2/3 收盘支持（*"…it is ignored."*）

**B. 位置否决**
- 偏多但价格在 **premium**（离目标太近）／偏空但在 **discount**
- 入场点到首个目标的剩余空间不足盈亏比

**C. 确认否决**
- 只有 POI、没有收盘确认（*"A Point of Interest Doesn't Mean an Entry."*）
- 只有扫荡、没有收盘穿越（*"The sweep itself is not the confirmation."*）
- 只有低周期结构变化、没有高周期收盘

---

## 12. 与本指标的对照表

| SOP 步骤 | 图上对象 | 备注 |
|---|---|---|
| **①** 高周期偏置 | `BIAS` 标签（`HTF bias BULL/BEAR/NONE`） | 偏置为 `NONE` 时应当日不做 |
| **②** 前日高/低 | `PDH` / `PDL` 两条点线 | 流动性目标 |
| **③** 高周期 relevant 位 | `RELH` / `RELL` | 3 根高周期 K 线窗口的极值 |
| **③** dealing range | `RANGE` 矩形 + `PremLbl` / `DiscLbl`（`EQ` 可选开） | ⚠️ **区间来源与他的构造法不符**（D31） |
| **④** POI | `FVG` 色块 + `IRL` 标签（偏置方向那条） | 内部流动性 |
| **⑤** 确认 | `CISD` 事件线 + `CISD` 标签 | 造势序列最旧一根开盘价被收盘穿越 |
| **⑥** 结构确认 | `MSS` 事件线 | 位移达标才翻转趋势；弱事件为暗色无标签 |
| **⑦** Ideal Formation | `CISD` + `OB` 色块 | OB 关键价位 = 造势序列最旧一根开盘价 |
| **⑧–⑩** 入场/止损 | （无专用对象） | 止损位 = protected swing（即 `CISD` 位所在结构线） |
| **⑫** 目标 | `ERL` 标签（玫红点线） | 外部流动性，已排除"已被取走"的位 |
| （全程） | `Seg_` 折线 | 趋势段划分，非某一步专用 |

**弱化（暗色 = 该元素未获确认）的三种原因**，读图时必须分清：
1. **位移不足**（MSS / CISD / OB）；
2. **与高周期偏置逆向**（MSS / BOS / CISD / SWEEP / FVG / OB）；
3. **FVG 的 CE 已被收盘穿越**（该缺口已失效）。

---

## 13. 【空白】他没说、因此本 SOP 只能自己定的部分

这一节请当作"**风险自负区**"—— 以下每一项都**没有**一手依据：

| # | 空白项 | 本 SOP / 指标的处置 |
|---|---|---|
| 1 | **位移的具体数值** | 我们定了阈值：**MSS** = 实体 1.0×ATR + 3 根时效；**CISD/OB** = 再加「后 5 根内出现同向 FVG」。他只有 *"strong price movement with momentum"*、*"within one to three candles"*（原「深度 0.3×ATR」一条**已从代码删除**） |
| 2 | **failure swing 的分离阈值** | 我们定了 `InpMinSeparationATR`。他明说 *"There is no strict numerical formula for separation."* |
| 3 | **"第一个 POI"的距离度量口径** | ⚠️ **已更正**：初稿写"他未给规则"属**高估空白**。他**给了路径次序**（*"Start at the protected swing. Work toward the current range. Look for a Fair Value Gap first."*），缺的只是"多远算在路径上"的度量口径。指标仍未实现优先级筛选，只把三类 POI 都画出来 |
| 4 | **时段规则**（做哪个交易时段） | **没有硬规则**。他有伦敦时段专文，但原文明确 *"the exact kill zone is not extremely important"*、*"**The clock itself is not what makes the setup valid.**"*、*"Do not force the entry because London is open."* |
| 5 | **仓位 与 止损距离公式** | ⚠️ **已更正**：初稿写"仓位与风险完全没有"对**风险**高估。他给了**硬性盈亏比目标** —— Playbook 明文 *"Target **2R** minimum"*、*"Minimum target: **2R** to remain profitable with >34% win rate"*（并附胜率区间 ~40–80%）。故：**仓位大小他没有；盈亏比目标他给了（2R 起）**。本 SOP 的 §10.4 剩余空间检查即据此 |
| 6 | **多空同时成立的冲突裁决** | 未定义 |
| 7 | **protected swing 的"重要位"层级** | 他说 *"can be a high, low, or fair value gap"*，但未限定必须哪一级 |
| 8 | **BOS 的定义** | 他全站 110 篇里 `break of structure` **仅 1 次**且为并列提及 —— 指标里的 BOS 是**行业通行读法**，不是他的 |

> ⚠️ **一条给读者的方法论提醒**：不要把"他几乎从不给数值"当经验法则 —— 这个前提**本身不准确**。
> 他在多处给了具体数字，例如 *"look back **three** higher timeframe candles"*、
> *"I personally look back **three days**"*、*"within **one to three** candles"*、
> *"Target **2R** minimum"*、周期配对表（Weekly→4H … 15M→1M）。
> **正确做法是逐句回原文核对，而不是靠"有没有数字"来判断真伪。**

---

## 14. 来源清单（全部为一手）

| 主题 | 来源 |
|---|---|
| 三层周期栈 / 周期配对 | <https://ttrades.com/timeframe-alignment-how-to-align-higher-and-lower-time-frames-for-precision-entries/> |
| 高周期偏置规则 / 跨层否决权 | <https://ttrades.com/fractal-model-playbook-aligning-daily-hourly-and-5-minute-charts/>、<https://ttrades.com/how-change-in-the-state-of-delivery-cisd-confirms-swing-points/> |
| MSS 定义 / MSS vs CISD | <https://ttrades.com/market-structure-shifts-vs-change-in-the-state-of-delivery-a-clear-comparison/> |
| CISD 定义 | <https://ttrades.com/understanding-the-change-in-the-state-of-delivery-cisd/> |
| 位移 / 一根 K 线过滤器 | <https://ttrades.com/why-your-continuations-fail-order-blocks-cisd-explained/> |
| protected swing / 影线与实体 | <https://ttrades.com/let-the-wick-form-trade-the-body-stop-getting-stopped-out/> |
| Ideal Formation / Candle 2-3 | <https://ttrades.com/ttrades-ideal-formation-high-probability-swing-points/>、<https://ttrades.com/candle-3-closure-a-complete-guide-to-identifying-continuations-and-reversals/> |
| POI 优先级 | <https://ttrades.com/the-only-points-of-interest-that-actually-matter-for-trading/> |
| Internal / External Liquidity | <https://ttrades.com/internal-external-liquidity-using-the-ttrades-fractal-model/> |
| Dealing Range / premium-discount-EQ | <https://ttrades.com/understanding-dealing-ranges-in-trading-get-better-risk-reward/> |
| 前日高低点 / draw on liquidity | <https://ttrades.com/the-easiest-draw-on-liquidity/> |
| 时段（**无硬规则**的依据） | <https://ttrades.com/how-to-trade-london-using-ttrades-fractal-model/> |
| 首选周期组合 | <https://ttrades.com/the-best-timeframes-for-ttrades-fractal-model-simple/> |
| 盈亏比目标 2R / 胜率 | <https://ttrades.com/fractal-model-playbook-aligning-daily-hourly-and-5-minute-charts/> |
| 摆动分级 / relevant swing | <https://ttrades.com/advanced-market-structure-simplified-from-short-term-to-long-term-trends/>、<https://ttrades.com/relevant-swings-which-swing-highs-and-lows-matter-in-trading/> |

**证伪性说明**：他的全部一手语料中 **CHoCH 零命中**（`change of character` = 0、`choch` = 0，
110 篇文章正文正则）。故本 SOP **不使用 CHoCH**；MSS 承担"趋势改变"，
CISD 承担"更早的确认"。详见 research §1。
