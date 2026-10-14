# TradFi MT5 Trading Context

MT5 自定义指标与 EA 脚本库的领域语言，与 库内指标 交易看板保持统一的视觉风格与交易逻辑。当前聚焦于市场结构（Market Structure）与 ICT 概念的可视化。

> **口径来源**：`TradFi_Structure` 的结构与事件口径**对齐 TTrades**。他的原文引用与配图见
> `docs/research/2026-09-23-TTrades-structure.md` 与 `docs/research/img/`；
> 对齐过程、逐阶段验收与被测量推翻过的假设见 `docs/plans/2026-09-23-TTrades-alignment.md`。
> **凡涉及数组方向的约定，一律以显式 `ArraySetAsSeries` 为准，不要依赖终端默认值。**

## Language

**冲动移动 (Impulsive Move)**:
一段强劲的单边趋势动作。边界完全由状态机事件界定：从上一个确认事件（MSS 或 BOS）之后开始，到下一次有效回撤（MSS）为止，该段内价格最高/最低的那根蜡烛即极值蜡烛。不做幅度过滤——任何打破极值蜡烛高/低点的动作都算有效回撤。若中间只夹着内部孕线而未发生有效回撤，则整个动作视为单腿冲动（Single Leg）。
_Avoid_: 趋势段（太宽泛）、拉升

**摆动点 / Swing (Swing Point)**:
结构线的折线极值点。**三点分形，左右两侧都严格**：swing high 为 `high[i]>high[prev] && high[i]>high[next]`，swing low 为 `low[i]<low[prev] && low[i]<low[next]`。结构线 = 连接全部确认 swing 点的锯齿折线。
_Avoid_: 顶点蜡烛、最值蜡烛（旧口径：段内动态极值蜡烛）
> 变更（v1.48）：旧版右侧用 `>=`／`<=`（左严格右非严格）。TTrades 的定义是"左右各一个**更低**的高"，
> 故两侧皆严格。实测该收紧本身影响很小（`fractal` 计数 −4%），真正的量变来自 failure swing 剔除。

**failure swing 剔除 (Failure Swing Filter)**:
与**上一个同类型** swing 的价格距离 < `InpMinSeparationATR × ATR` 的摆动点不予确认。他：*"forms too close to a prior high or low and lacks proper range separation"*。
_Avoid_: 相邻点去重（那是 bar 距离，不是价格距离）
> ⚠️ 他**明确说 separation 没有数值公式**（*"There is no strict numerical formula… If it is too close, expect it to be taken."*），配图 `Valid-Seperation.png` 也只给"小 vs 大"的定性对照。**门槛是本指标自定的近似**，默认 0.5。

**摆动分级 (Swing Tier)**:
`short` / `intermediate`。**intermediate = 一个 short-term 点，且比左右最近的同类型点都更极端**。节点数组强制高低交替，故"最近的同类型点"即 `nodes[n±2]`；任一侧越界则保持 `short`。
_Avoid_: 主/内部结构（那是 `isMain` 幅度分级，与此无关）
> 依据：`ITM.png` 中 `STH(2)` 左右各有 short-term high 却标 `STH` 而非 `ITH` —— 否证了字面读法
> （"左右各有一个 short-term 点即 intermediate"）。**必须在主循环之后整表计算**（右侧邻居需后验）。
> 用途：`SWEEP` 的扫荡位只取 intermediate；`long-term` 依赖 HTF 反应，尚未实现。

**受保护结构位 (Protected Swing / RefPoint)**:
当前趋势下受保护的两个结构位：`ST_UP` 时 `refHigh`=HH、`refLow`=HL；`ST_DOWN` 对称。`broken` 标记保证同一结构位只触发一次事件。
_Avoid_: 支撑阻力（无状态语义）
> ✅ **已按他的定义实现（v1.49-s11）。** 定义（三篇一手文章一致）：
> *"A protected swing forms when price reaches an important level and then **closes through
> the series of candles** into that level."*；*"…created when price **closes through the series
> of opposing candles** that led into a high or low."*；序列为
> *"Bearish movement → important level → **bullish change in the state of delivery** →
> protected swing → expansion higher"*，且 *"This is the **same change in the state of delivery**
> used to confirm swing formations."*
>
> → **CISD 触发的那一刻就是 protected swing 成立的那一刻**，锚点 = 造势序列的极值。
> 唯一写入点是 `SetProtectedFromCisd()`，由 `CheckCisd()` 在触发时调用。
>
> ⚠️ 他的定义里**没有**两样东西，我们此前都有：
> 1. **没有层级门槛** —— short/intermediate/long-term 是**质量分级**
>    （*"Intermediate-term highs/lows confirm **stronger** pivots"*），不是成立条件；
> 2. **没有幅度门槛** —— 旧的 `IsMainSwing`（腿长 ≥1.0×ATR 或 ≥0.382×前段）**无任何一手依据**，
>    已随 `InpUseMainFilter` / `InpMainFilterATR` / `InpMainFilterRatio` 一并删除。
>
> ⚠️ 他的序列里**有**一样我们没做：*"Price **sweeps liquidity** beneath a low"* ——
> 扫荡是**前置背景**（他同时说 *"The sweep itself is **not** the confirmation"*），
> 不是成立条件。这与 **D13**（OB 的前置扫荡）同源，仍未实现。

**位移判据 (Displacement)**:
**逐路径生效**，且原第②条「收盘穿越深度」**已整体删除**：
- **MSS**：① 实体 ≥ `InpMinDisplaceBodyATR × ATR`；③ 首次影线穿越落在 `[i, i+InpDisplaceMaxBars-1]`（时效）。
- **CISD / OB**：① + ③，**另加**「**触发 bar 起 N 根内出现同向 FVG**」（`InpCisdFvgLookahead`，默认 5）**替代**原②。

他：*"The key confirmation is displacement (strong price movement with momentum) that breaks prior structure."*、*"The best setups form within one to three candles"*、*"When displacement occurs …, **leaving behind a fair value gap**"*。
_Avoid_: 突破强度（太含糊）
> 时效条件用**无状态**实现：「首次穿越落在 `[i, i+N-1]`」等价于「`(i+N .. anchorBar-1)` 区间内无穿越」，
> 故不需要额外的状态字段。所有阈值均**无一手数值依据**，全部写入 CSV 头以便归档自描述。
> **`pen` 仍然计算并写入 CSV 的 `pen=` 列** —— 删掉的是**判据**，不是**度量**。
>
> ⚠️ **CISD 的 FVG 条件必须放在后验层**（`ComputeCisdFvgFollow`）：FVG 是主循环里随遍历
> 逐 bar 产生的，某次 CISD 触发时它**之后**的 bar 尚未被遍历 —— 在主循环内判定既是错的、
> 也构成未来函数。后验改写 `weak` 是安全的，因为 **CISD 的 `weak` 不参与任何判定**
> （趋势状态机只看 MSS），只影响配色与 CSV。
>
> ⚠️ **两处已知副作用，验收时须盯住**：
> 1. 原本第②条在默认 `BREAK_WICK` 下是"必须真的收在位外"的**唯一把关**（MSS 路径）。
>    它被删除后，**影线刺穿、实体够大、却收盘收回位内的 K 线也能判 strong** ——
>    即阶段 2-① 消除掉的"假破位"会回归，并会翻转趋势、消耗该位。
>    缓解：把 `InpBreakConfirm` 换成 `BREAK_CLOSE`（不引入 ATR 深度阈值即恢复"必须收盘越位"）。
> 2. CISD 的新条件**只能把事件判得更弱，不能判得更强** —— ①③ 仍是必要条件。
>    故 `strong` 的集合是原集合的**子集**：CISD 的 `OK` 数量只可能减少。

**结构反转 (MSS, Market Structure Shift)**:
**逆势**跌破/升破受保护结构位，**且满足 MSS 的位移判据**（① 实体 + ③ 时效；② 已移除）。上涨趋势中跌破 HL；下跌趋势中升破 LH。
_Avoid_: CHoCH（**TTrades 完全不用这个词** —— 全站 110 篇语料级零命中，他的对照对是 MSS / CISD）
> 依据：`ChangeInTrend-Bearish.png` 把他的"趋势变化"画成**落在 HL 位上、向右延伸的橙线**，与本实现一致。
> ⚠️ 本实现**默认实体突破确认**（`InpBreakConfirm=BREAK_BODY`），这是必需条件之一；
> 见「破位确认」条目 —— 注意该项**比他的字面口径（收盘）更严**。

**结构延续 (BOS, Break of Structure)**:
**顺势**突破受保护结构位（上涨中突破 HH；下跌中跌破 LL），结构线继续延伸。
_Avoid_: 顺势突破（描述性用语）
> ⚠️ **TTrades 没有给出 BOS 的一手定义** —— 全站 110 篇中 `break of structure` 仅出现 1 次且为并列提及；
> `BullishTrend-Structure.png` 与 `BasicUptrend.png` 都只标 HH/HL 序列、**无任何 BOS 标记**。
> 故此处的"顺势破位"是**行业通行读法，无法声称与他一致**。他唯一相关的一句是
> *"Not every break of structure is a full reversal."*

**CISD (Change in the State of Delivery)**:
以「造势那一串**同向收盘** K 线」中**最旧那根的开盘价**为位，价格**收盘穿越**该位即触发。**不看 swing、与趋势状态无关**。他：*"focuses on the opening price in the series of up-close or down-close candles. When price displaces and closes beyond that open, it validates the level as an order block."*
_Avoid_: 与 MSS 混用（两者是并列事件，不是别名）
> 依据：`CISD-2026-01.png` 显示 CISD 线**明显远离极值、贴近整段造势的起点** —— 证实取"最旧那根"，
> 否证"紧邻极值那根"。取数纪律：*"Always use the series of candles."*（故非单根）。
> ⚠️ CISD **不做位移的 WEAK 分级**（他定位它是 *"earlier but riskier"* 的早期信号，用 MSS 的位移门槛筛它会把 78% 判弱）。
> ⚠️ 它"早于 MSS"的角色需要**低周期 CISD × 高周期 MSS**；本指标是单图表，同周期下不必然更早。

**IC-CISD / Early CISD（收盘前的临时 CISD）**:
触发条件与 **CISD 完全相同**，唯一差别是判定用的"当前价"：正式 CISD 用已收盘 bar 的 `close[i]`，
IC-CISD 用未收盘 bar 的 `close[0]`。他：*"Automatically plots CISD **before candle closure**"*（"Early Trend Shift"）、
*"you are not predicting the wick, you are waiting for confirmation that it has already formed"*。
**纯渲染** —— 不置 `cisdHighFired`、不派生 OB、不建立 protected swing。
_Avoid_: 提前的 MSS（MSS 仍需收盘，两者不是同一层的东西）
> 依据：`docs/research/2026-09-23-TTFM-rules-report.md` §3。
> ⚠️ **为什么不写状态**：他本人承认 *"CISD can give earlier entries but sometimes too early,
> leading to false signals"*。把未收盘的猜测写进趋势状态机，正是那句警告描述的错误。
> 故预览的**唯一权威状态**由全量帧给出（`g_ic*`），快路径只负责让它跟手，且不写场景集。
> **生命周期**：只活在当前未收盘 bar 内 —— 依据是 `st.cisdLowValid && !st.cisdLowFired`
> 这个快照条件：收盘一旦真触发，`*Fired` 置真 → 预览自动失效，不需要额外清理逻辑。

**HTF 蜡烛叠加 (Higher Timeframe Candles)**:
在入场周期上直接绘制高周期蜡烛（实体矩形 + 上下影线），画在 K 线之下。
他：*"View HTF candles on your entry timeframe"*；根数**默认 4**（他的指标默认值）。
_Avoid_: 多周期图（那是看另一个图表，不是叠加）
> ⚠️ **性能约定（新增可视化元素时同样适用）**：正在形成的那根 HTF 蜡烛**每 tick 都在变**，
> 故它的 OHLC **不得进 `needDraw` 指纹** —— 进去就等于每 tick 触发整段调和，
> 正是 v1.48 专门消除的性能陷阱。指纹只含"集合级"信息：最新 HTF bar 开盘时间
> `g_htfT0` + **已收盘**蜡烛的 OHLC 签名 `g_htfSig`；正在形成的那根由快路径
> `UpdateHtfLastFast()` 单独刷新（缓存比对 + `0.1×ATR` 死区，未变即零对象调用）。
> ⚠️ 实体"透明度"同样受 `OBJ_RECTANGLE` 无 alpha 的约束，沿用 `PdFill(轮廓色, 底色)` 混色。
> ⚠️ HTF 蜡烛的对象名用**时间戳**做键，而非事件对象那种语义锚定 —— 这是固定根数的
> 实时叠加层，新 bar 到来时各对象只是换坐标，不存在"过期对象需回收"的情形。

**Candle 2 / Candle 3 收盘确认 (Valid Closure)**:
swing 点上的**收盘确认**类型。编号：C1 = swing 点**之前**；**C2 = swing 高/低本身**；C3 = C2 之后。
三种子类型：`C2-REV`（扫破前根极值后**收回** —— 他："A Candle 2 closure is **always** a reversal closure."）、
`C3`（C2 未给确认，C3 **收在 C2 实体之外**且未扫破 C2 极值）、
`C2-CONT`（扫破前根极值且**收在其外** —— 延续收盘，**不是**有效反转确认）。
_Avoid_: 吞没形态（那是两根实体关系，与"扫破+收回"不是一回事）、把 `C2-CONT` 也叫"确认"
> 依据：`docs/research/2026-09-23-TTFM-rules-report.md` §2。
> ⚠️ **现为 18a：只记录，不参与任何判定。** 他的门禁版是 *"A swing is only valid when it has
> both: a point of interest and a valid closure. **If either is missing, the swing point is
> ignored.**"* —— 那会改变全部下游结构（protected swing / BOS·MSS 归属 / 结构段划分），
> 性质同 v1.49-s11 的 protected swing 换定义，故拆为 18a / 18b 两步。
> ⚠️ **C3 的判据取"C3 未扫破 C2 极值 + C3 收在 C2 实体之外"，不是"C2 未扫破 C1"。**
> 后者在严格三点分形下**恒假**（swing low 必然 `low[b] < low[b+1]`），写成那样会是**死代码**。
> ⚠️ **三处自定口径**：C3 取实体版（"and range" 的更严版本未实现）；"engulfs it" 的字面
> 未作为必要条件；C1/C3 取物理相邻 K 线。全部写进 CSV 头部 `# closure` 行。
> ⚠️ **判断该功能是否真在跑要看子类型分布，不是条数** —— 若 `C3`/`C2-CONT` 恒为 0，
> 首个怀疑对象是分支又成了死代码（v1.49-s15 的死门控就是这么来的）。

**流动性目标 (Auto Targets)**:
偏置方向上、现价之外、**尚未被取走**的摆动位，按**价格距离**取最近 N 个；另追加 PDH/PDL。
他：*"Bullish → previous **untouched** highs; bearish → previous **untouched** lows …
**A level already taken out is invalid.**"*，且明确把它列为 *"separate, and primary"* 的目标来源。
_Avoid_: 支撑阻力（丢失"未被取走才是有效流动性"这层）
> ⚠️ **与 ERL 的关系**：ERL 给"最近的**一个**"，本项给"最近的 **N 个**"；
> 两者的"未被取走"判定**共用** `IsLiquidityTaken()` —— 同一概念一份实现（同 `CisdOriginBar` 的规矩）。
> ⚠️ 上限必须用 `InpTargetCount`（`want`），**不是**数组容量 `MAX_TARGETS`；
> 混用过的后果是"设成 2 也照样画 4 个"，且**不报任何错**。

**操纵腿投影 (Manipulation-Leg Projection)**:
把**操纵腿**沿交易方向外推得到的目标位。他：*"Anchor a Fibonacci tool to the **manipulation
leg** — the swing that sweeps liquidity and occurs **immediately before the CISD** … Bearish
projects high→low; bullish low→high. **Start the construction from Candle 2, the reversal point.**"*
本实现：A = 最近一条**与偏置同向**的 CISD 事件的 `refBar`（= 造势序列极值 = 操纵极值），
B = A 之后的反向极值，水平 = `B + (B − A) × k`。
_Avoid_: 斐波那契回撤（回撤画在 A–B **之间**，投影画在 B **之外**）
> ⚠️⚠️ **符号被本实现翻了过来 —— 这是"改做"而非"对齐"。** 他的水平表是
> `1, 0, −1, −2, −2.5, −4`（**负向**扩展）；但 TradingView 约定下负向是从**起点 A 之外**
> 延伸，看涨时 A = 被扫破的低点 → −1/−2 落在 **A 之下**，那是**止损方向**而非目标。
> 故本实现以**交易方向**为准从 B 外推，取 `1, 2, 2.5, 4`。该差异同时写在输入组注释、
> CSV 头部（`DIRECTION=OURS(...)`）与 README —— **任何地方都不得声称与他的水平表一致**。
> ⚠️ 水平表本身置信度只有**中介**（调研自述原文列表被截断）。**这是四个功能里最弱的一环。**

**SWEEP (流动性扫荡)**:
**intermediate** 位被某根 K 线的**影线越过、但收盘收回位内**。每个位只记**首次**被扫荡。他：*"sweeps the previous candle's high or low and then closes back inside that range"*、*"Use intermediate-term sweeps as confirmation of continuation or reversal."*
_Avoid_: 假突破（语义重叠但更宽）
> **纯上下文标注，不参与任何判定** —— 他明确 *"The sweep itself is not the confirmation."*
> 前日/前周高低温属 HTF 上下文，尚未纳入。

**relevant 位 (Relevant High/Low)**:
高周期**回看含当前共 3 根 K 线**的最高/最低，画为两条点线。他：*"look back three higher timeframe candles including the current one. The highs and lows within that window are your relevant levels."*
_Avoid_: 关键位（无窗口语义）
> 按 C1 决策**只标记、不过滤** —— 用窗口去删结构点会让结构线断裂。
> 极值只取 max/min，与数组方向无关，故无需 `ArraySetAsSeries`。

**dealing range / 均衡位 (Dealing Range & EQ)**:
relevant high/low 连成的区间即 dealing range；其 **50% 处为均衡位 EQ**，上方是 **premium**、下方是 **discount**。他序列第三步：*"Price retraces into a premium or discount zone, giving the best entry."*
_Avoid_: 箱体、区间震荡（那是价格形态，不是 HTF 参照区间）
> 依据：`Relevant.png` 显示他把 relevant high/low 两点**连成区间**（不只是画两条线）。
> 对象：`RANGE`（矩形）/ `EQ`（50% 虚线）/ `PremLbl` / `DiscLbl`。**纯可视化，不参与判定。**

**HTF 偏置 (Higher-Timeframe Bias)**:
取上一根**已收盘**的高周期 K 线，与它**前一根**的高低比较：`close > 前根 high → bull`、`close < 前根 low → bear`；落在区间内则向前回溯（上限 `InpBiasLookback`）取最近一次决定性收线；回溯不到 → 无偏置。他：*"If price closes below the previous day's low – Expect continuation lower."*
_Avoid_: 趋势方向（那是逐 bar 结构状态，与 HTF 偏置不是一回事）

**HTF 门禁 (HTF Gate)**:事件的**方向与 HTF 偏置逆向**时予以**弱化**：不注册标签对象、暗色点线。他：*"if there is no candle 2 or candle 3 closure on the higher time frame, **it is ignored**."*、*"A lower time frame 'trend shift' is just a pullback into a discount or premium area on a higher time frame."*
_Avoid_: 过滤（事件仍记录在 CSV，只是画面弱化）
> 实测门禁力度：50 条事件中 **22 条对齐 / 28 条逆向（44%）**；**CISD 仅 33% 对齐** ——
> 这是"L4 是 CISD 的前提"那条判断的量化证据。
> MSS 的弱化条件为 **位移不足 `OR` 逆向偏置**（两者都表示"未获确认"，合并为同一弱化处理）。

**有效回撤 (Valid Retracement)**:
一段强劲趋势（冲动移动）中出现的真正意义上的反向修正动作，标志价格短期停顿或反转，目的是获取流动性或进行调整——不是停留在某根大蜡烛内部的无意义震荡盘整。判定条件：(1) 后续蜡烛必须实质性地打破该段冲动移动中极值蜡烛的高点或低点；(2) 内部孕线（高低点被前一根大蜡烛完全包裹）不算有效回撤；(3) 与蜡烛颜色（阴阳）无关；(4) 实体收盘或影线扫过（Sweep）均有效。
_Avoid_: 回调、pullback（作同义词时过于宽泛）

**有效回撤过滤 (Retrace Filter)**:
结构点确认前的幅度门槛：回撤腿须满足 **`最小点数` AND (`ATR 倍数` OR `前一段幅度比例`)**，并可叠加 `InpMinSwingAmplitude` 点数硬下限。swing 与内包盒统一过此门槛，保证 MSS 只突破"有效 HL/LH"。仅 ShortTerm / StrictICT 模式生效。
_Avoid_: 最小腿长（语义偏窄）
> **更正**：本文档旧版写的是三者 AND 语义，与代码不符 —— 代码是 `点数 AND (ATR OR 比例)`，
> 且代码注释也如实写了"放宽 AND 为 点数 AND (ATR OR 比例)，避免过严滤除有效结构点"。**代码是对的，旧文档没跟着改。**
> 注：`InpMinRetraceATR = 0` 时该条被短路（`atrOk` 恒真），过滤退化为只剩点数门槛。

**内部孕线 (Inside Bar)**:
高低点完全被"母线 K 线"包裹的蜡烛（母线 = 其最高/最低尚未被后续打破的 K 线）。一根母线可连续包含任意数量的后续 K 线，直到出现打破母线最高或最低的 K 线——期间所有被完全包含的 K 线（high ≤ 母线 high 且 low ≥ 母线 low）都是内包，不参与 swing 检测；但 ShortTerm / StrictICT 模式下会记录为**内包盒**（母线 high/low + 起止 bar）。
_Avoid_: 内包线、十字孕线
> 变更（v1.48 / 阶段 2-②）：内包 K 线**仍不参与 swing 逻辑**，但**突破检测改为遍历每一根 bar**
> —— 因为收盘确认口径下，内包 K 线的**收盘**仍可能越位（影线口径下母体会先破，故此前无实害）。

**单腿冲动 (Single Leg)**:
只由一根大蜡烛构成、未发生有效回撤的冲动移动。
_Avoid_: 单根趋势

**结构段 (Structure Segment)**:
冲动移动 → 有效回撤（MSS）→ 再次顺趋势突破（BOS）构成结构线的"一节"；BOS 之后进入下一节，直到下一次 MSS 出现。
_Avoid_: 腿（leg，易与单腿冲动混淆）

**内包盒 (Inside Box / BoxZone)**:
母线被完全包含的 K 线组成的盒区间；记录母线 high/low、内包起止 bar。向上突破母线 high → 倾向确认上升结构，向下跌破母线 low → 倾向确认下降结构（BOS/MSS 画在母线高/低）。仅 ShortTerm / StrictICT 模式生效。
_Avoid_: 孕线簇（无方向语义）

**外包 K 线 (Outside Bar)**:
同时打破前一根有效 bar 最高与最低的 K 线。MQL5 无 tick 顺序，用开收盘近似：阳线（close≥open）→ 低先高后 → 方向 UP；阴线（close<open）→ 高先低后 → 方向 DOWN。与当前趋势一致 → BOS（延续），相反 → MSS（反转），不再简单二选一。仅 ShortTerm / StrictICT 模式生效。
_Avoid_: 吞没形态（不限定同一根）

**结构模式 (StructureMode)**:
指标的三档行为开关。FractalSwing = 不套用有效回撤/failure swing 等过滤器；ShortTerm（默认）= 有效回撤过滤 + 内包盒 + 外包 + 实时腿；StrictICT = BOS/MSS 在收盘突破结构位后确认。
_Avoid_: 周期切换
> 变更（v1.48）：swing 三点判定改为**左右皆严格**后，该收紧**在所有模式下生效**
> —— 因为它是 swing 定义本身。故 `FractalSwing` 现在的含义是"不再叠加额外过滤器"，而非"沿用旧分形规则"。

**实时腿 (Live Leg)**:
结构线最后一段的未确认延伸：最后节点是低点 → 虚线连到当前最高 high；是高点 → 连到当前最低 low。仅 ShortTerm / StrictICT 模式生效。
_Avoid_: 虚线预测（无确认语义）

**破位确认 (Break Confirm)**:
MSS / BOS 共用的破位判据（`InpBreakConfirm`），三档且**严格度为全序**：
`BREAK_BODY`（实体完全越过）⊂ `BREAK_CLOSE`（收盘越过）⊂ **`BREAK_WICK`（默认，影线触及）**。
StrictICT 模式是**下限**而非覆盖：它把 WICK 提升为 CLOSE，但不把 BODY 降级。
_Avoid_: 收盘确认（旧称，只剩两档且暗示收盘是唯一口径）
> ⚠️ **两句话都是他说的，方向相反，别只引一句**：
> · *"price displaces and **closes** above or below a swing high or swing low"* → 支持 `BREAK_CLOSE`；
> · *"**The sweep itself is not the confirmation.**"* → 反对把"扫影线"当确认。
> 当前默认 `BREAK_WICK` 是**用户裁定**（放宽），**比他两句里的任一句都宽**。
> 他"影线不算确认"那层意思由**位移判据**承担：影线触发但位移不足 → 只记弱事件、
> 不翻转趋势、**且不消耗该位**（`RefPoint.touched`）→ 后续真正的突破仍出得来。

**弱触发 / 强触发 (Touched / Broken)**:
`RefPoint` 的两种一次性标记。**强触发**（过了位移门槛）= 真正的 MSS → 置 `broken`，该位用完。
**弱触发**（破了位但位移不足）= 只记录一次（`touched`），**不消耗该位**。
_Avoid_: 假突破（弱触发仍是真实发生过的破位，只是未获位移确认）
> 为什么必须分开：`BREAK_WICK` 下"影线扫一下"就命中破位条件，若弱触发也置 `broken`，
> 该位会被一次扫影线**永久消耗**，后面真正的收盘/实体突破**再也出不来** —— 那是丢信号。
> 注意**只在 MSS 路径生效**：BOS 没有位移判据（D11：他从未定义 BOS），
> 故 BOS 在影线触及即成立并消耗该位。**这是 MSS 与 BOS 的一处不对称**，
> 在 `BREAK_WICK` 下最明显。
_Avoid_: 实体确认（含义重叠）
> 变更（v1.48 / 阶段 2-①）：**默认由 `false` 改为 `true`**。他：*"If the candle cannot close through
> the level you need, the reversal is not confirmed."* 实测影响：事件 29 → 24 条，其中 **7 条是
> "只是刺破、从未收在该位外"的假破位**被消除，另有 8 条时点后移（等收盘）。

**PD Array（FVG / OB）**:
TTrades 体系里执行层的参照区，统称 Point of Interest。**不参与任何结构判定**——
他本人限定 *"A Point of Interest Doesn't Mean an Entry."*
_Avoid_: 信号区（有入场语义）
> 定义全文见 `docs/research/2026-09-23-TTrades-structure.md` §11。
> 一句话区分：**FVG 看影线，OB 看实体** —— 这是他两篇文章里的明文，不是取舍。

**FVG（Fair Value Gap）**:
三根 K 线形态：`low[第1根] > high[第3根]`（看涨 BISI）或 `high[第1根] < low[第3根]`（看跌 SIBI）。
区间 = 两者之间的空隙，边界取**整根 K 线的高低（含影线）**。
_Avoid_: 成交量失衡（volume imbalance，是 close→open 的缺口，另一回事）
> 本指标口径：第 1/3 根取自**有效 bar 序列**（内包 K 线已剔除），非物理相邻三根。

**CE（Consequent Encroachment）**:
FVG 的中点（50%）。他的原话：*"As long as price does not close beyond the consequent
encroachment, the fair value gap is generally considered respected."*
失效判据 = **收盘穿越 CE**，或完全走完整个区间。
_Avoid_: 均衡位（EQ，那是 dealing range 的 50%，且**默认不显示**）
> 配图 `FVG-CE.png` 把 FVG 的用法拆成三个入场位：IOFED / CE（图上标 `0.5`）/ FVG Fill。

**OB（Order Block）**:
造势的那一串**同向收盘 K 线**。价格收盘穿回该串之后，其**实体区间**成为验证过的 OB；
关键价位 = 该串**最旧一根的开盘价**（*"The opening price of the candle is often the most
important reference."*）。
_Avoid_: 供需区（泛化，丢失"必须已被收盘穿回"的验证语义）
> **关键复用点**：他的验证动作 *"closes back below those candles"* 与本指标的 **CISD 触发
> 是同一个动作**，故 OB 由 CISD 运行态派生（`AddObFromRun`），不另起检测逻辑。
> 配图 `OB-reversal-pattern.png` / `OB-confirmation.png` 里 OB 都画成**一条线**——那条线就是 CISD 位。

**IRL / ERL（Internal / External Liquidity）**:
他的一对流动性概念：**IRL = FVG（内部流动性，提供 POI）**，
**ERL = 摆动高/低（外部流动性，提供目标）**。
_Avoid_: 支撑/阻力（丢失"内部 vs 外部"的层级含义）
> 逐字（research §13）：*"Internal liquidity is a fair value gap."* /
> *"External liquidity is a swing high or swing low."* /
> *"**Internal liquidity provides the point of interest. External liquidity provides the target.**"*
> **前提**：*"Start with the higher timeframe bias."* → 无 HTF 偏置时不成立（两侧都可能是目标）。
> **不对称**：internal→external 顺势方向 *"generally easier"*；
> external→internal *"generally requires stronger confirmation because the move is trading back into the range"*。
> **画法**（他配图 `ERLIRL-*.png`）：IRL = FVG **横向色带**；ERL = 摆动位处**一条短点线**；
> **两张图都没有连接箭头**，只是两个元素同时在场、各贴一个标签。

**Premium / Discount / EQ**:
dealing range 按 50% 对分后的上/下半区：**上半 = premium，下半 = discount，中缝 = EQ**。
_Avoid_: 超买超卖（丢掉"相对区间的相对位置"这层含义）
> 逐字（research §14.1）：*"Split the dealing range at 50%. The **upper half is premium**.
> The **lower half is discount**. **EQ sits in the middle.**"*
> 用法：*"For bullish setups, look for longs in **discount or around EQ**.
> For bearish setups, look for shorts in **premium or around EQ**."*
> **它是剩余空间的度量，不是过滤器**：*"The setup can still work from a poor location.
> The issue is **how much range is left** for the trade."*
> ⚠️ **本指标的 `RANGE` 矩形并非他的 dealing range**（见 D31 / research §14.4）：
> 他的 dealt range 两端是"你在行情的那个 swing"与"造出它的高周期 swing"，**且有方向**；
> 我们取的是 3 根 HTF K 线的极值、无方向。**分区算法对，被对分的区间不对。**

**PDH / PDL（前日高/低）**:
`InpPDPeriod`（默认 `PERIOD_D1`）上**最近一根已收盘** K 线的最高/最低点。
_Avoid_: 昨日区间（他要的是两个**点**，不是区间的上下沿）
> 他的一手依据：*"Price takes out **yesterday's high** but closes back inside the range"*；
> *"Failure to displace above **previous day high** suggests a bearish bias toward
> **previous day low**."*；偏置规则 *"If price closes below the **previous day's low** –
> Expect continuation lower."*
> → 在他的体系里前日高/低是**流动性目标**（draw on liquidity），不是普通参考线。
> ⚠️ **取数必须按日期判定，不能写死 `shift=1`**：服务器刚换日、当日 K 线尚未生成的那段
> 时间里 `shift=0` 才是"最近一根已收盘"，写死 `shift=1` 会在该窗口取到**前天**。
> 实现取"第一根 open 日期**严格早于**当前服务器日期的 K 线"。
> 周末/假日无 K 线时得到的是"最近一个交易日"——这也是 ICT 语境下的通行含义。
> ⚠️ PDH/PDL **已画出，但不作为 SWEEP 的取位来源**（SWEEP 只扫本图 intermediate 节点）。

**虚线终点 (Line End)**:
MSS/BOS 虚线的右端止点模式（`InpLineEnd`）：首次回踩/反抽（事件后第一根触及 ref 的 bar）/ 固定 N 根 / 下一个结构节点 / 碰到结构折线即停。
_Avoid_: 无限延长（无终止语义）

## 架构（2026-08 审查加深；v1.48 对齐 TTrades 后扩充）

单一 .mq5 内分层接缝：

- **分析层** `ComputeStructure(...)` → 纯输入 K 线，输出 `StructureResult`；状态机运行态封装于 `struct SState`。
- **后验层**（主循环之后，顺序有意义）：`ClassifyNodeTiers()` → `ComputeSweeps(...)` → `FillEventBias(time, rates_total)`。
  摆动的右侧邻居要等后续节点出现才可知，故分级必须后验；sweep 与偏置不参与判定，故可后验且无需改事件创建签名。
- **结果层** `StructureResult` → `StructureNode`（含 `tier`）/ `StructureEvent`（含 `weak`/`bodyATR`/`penATR`/`bias`，v1.49 起另有 PD Array 用的 `zoneLo`/`zoneHi`/`fillPct`/`ceBroken`）/ `BoxZone`，一条事件一条记录，无平行数组。
- **场景层** `RenderScene(result)` → 语义锚定对象 ID + 调和式同步（未注册即回收），仅场景变化时 `ChartRedraw`。
- **导出层** `DumpEvents(...)`（`InpDumpEvents`）→ **6 路**时间归并写 CSV（MSS/BOS/CISD/SWEEP/FVG/OB），头部自描述（构建指纹 + 全部参数 + PD Array 口径）。
- **性能层** `InpReuseResultOnTick`（默认开）：同 bar tick 复用分析结果；`needDraw` 八项指纹未变时整段跳过调和。

### 版本演进中形成的硬约定

**v1.36 起**：`RefPoint{bar, price, valid, broken}` 取代"纯价格 + hasHigh/hasLow"；突破检测（每根 bar 独立检测）与 swing 更新彻底拆分；结构节点只由确认 swing 添加；`isMain` 只影响线型、不阻断结构推进。

**v1.37 起**：`CheckBreakAgainstRefs` 是 BOS/MSS 的**唯一触发源**（内包盒/外包不再独立触发标记）；同 bar 双破有互斥规则。

**v1.48 起（对齐 TTrades）**：

1. **数组方向必须显式声明**。`OnCalculate` 入口 `ArraySetAsSeries(time/open/high/low/close, true)`。
   **教训**：本终端交给指标的数组**不是**时序（实测 `index 0 = 最旧`），而全文件按 `index 0 = 最新` 编写。
   后果不是报错，而是"分析的是最老的一段历史、对象坐标全对却整体落在可视区之外"——看起来就是"什么都没画"。
2. **禁止把有副作用的调用写在 `||` / `&&` 右侧**。MQL5 的 `||` 短路；曾因
   `changed = changed || Upsert*(...)` 导致 2367 个结构线对象只建出 1 个。
   一律写 `if(Upsert*()) changed = true;`。
3. **新增事件类型必须同步 `needDraw` 指纹**，否则新事件不触发重绘（表现为"要等下一根 bar 才出现"）；
   同时必须 `AddSceneName` 注册，否则会被回收段当作过期对象删除。
4. **每次改动递增 `BUILD_TAG` 指纹**，它同时出现在 INIT 日志行与 CSV 头部 —— 用来回答"MT5 实际加载的是哪一版"。
5. **验证纪律**：改动前先导出事件 CSV，改完逐行 diff 归因；**MT5 专家日志写入有延迟**，
   缺少预期行时不要立即下结论，隔几十秒重读或用 CSV 头部（落盘即完整）。
6. **PS 5.1 把无 BOM 的 `.ps1` 按 ANSI 读**，脚本必须纯 ASCII，中文一律走独立片段文件。

**v1.49 起（阶段 9：PD Array）**：

1. **PD Array 是只读渲染层**。`CheckFvg()` / `AddObFromRun()` 只写 `g_result.fvg` / `g_result.ob`，
   渲染段只读；**不得**把 POI 引入任何判定路径（他的限定见上）。
2. **OB 与 CISD 必须同源**。`CisdOriginBar()` 是"造势序列最旧一根"的**唯一**实现，
   `CisdOriginOpen()` 只是取它的开盘价。任何"再扫一遍找 OB"的写法都会让两者口径漂移。
3. **FVG 的失效状态是后验的**。`fillPct` / `ceBroken` 在缺口确认的那一刻就向后扫完整段算出，
   因此 CSV 里是**终态**（可复现），而渲染层据此决定是否隐藏（`InpFvgHideFilled`）与弱化。
4. **PD Array 的标签恒定显示**。事件（MSS/BOS/CISD/SWEEP）的"弱化 = 暗色 + 去标签"针对的是
   **信号**；PD Array 是**地图**，去标签会让人看不出画的是什么。故 `ceBroken` 与逆向偏置
   只改颜色。依据：实测 80 个 FVG 中 66 个（82.5%）CE 已被收盘穿越 —— 让一个 82.5% 命中的
   判据兼任"去标签"，等于让整个功能默认无标签。
5. **FVG 的方向由分支决定，不靠测量**。`high[c1] < low[c3]` ⇒ `zHi = low[c3]` 而
   `close[c3] >= low[c3]` 恒成立 ⇒ 确认那刻价格必在区间上沿之上 ⇒ 只能是看涨 `DIR_UP`。
   反之 `low[c1] > high[c3]` ⇒ 必是看跌 `DIR_DOWN`。
   **教训**：v1.49-s9 初版把两个分支的 `dir` 写反，区间正确但方向反了，于是每个缺口都被
   套用反方向的回补判据 —— 而价格本来就在区间另一侧，判据立刻成立，**80/80 全部瞬间
   "已回补 + 已穿 CE"**。抓出它的是**分布**（80/80 太极端），不是等式（`CE == (zLo+zHi)/2`
   在方向反了时依然成立）。
6. **新增 PD 类事件同样受硬约定 3 约束**（`needDraw` 指纹 + `AddSceneName` 注册）。
7. **MT5 的 `OBJ_RECTANGLE` 没有透明度**，且填充与边框共用 `OBJPROP_COLOR`。
   **这不是"没找到属性"，是属性不存在** —— 已用编译测试证实：
   引用 `OBJPROP_ALPHA` 报 `error 256: undeclared identifier`。
   所以"半透明"只能是**预先算好的不透明混色** + 保持 `OBJPROP_BACK=true`
   让矩形画在 K 线**之下**（蜡烛绘制在其上）。
   **正确换算式（v1.49-s14 起）**：
   ```
   fill = 图表底色 + (轮廓色 − 图表底色) × 百分比/100
   ```
   底色经 `ChartGetInteger(0, CHART_COLOR_BACKGROUND)` 读取（只在 needDraw 帧读一次）。
   ⚠️ **必须混向"实际底色"，不能假设黑底** —— 这是踩过的坑：
   原先写死 `fill = 轮廓色 × α`，那只是**黑底**下的特例；在**白底**图表上"往黑混"
   会把颜色越压越暗，结果**几乎看不见**（用户实测反馈）。
   现由单一输入 `InpPDFillPercent`（**默认 30**，0 = 空心框）驱动，两种底色下语义一致：
   *"轮廓色以该不透明度叠在你的图表底色上"*。
   · 黑底（bg≈0）  → `fill ≈ 轮廓色 × pct`（与旧行为一致，无回归）
   · 白底（bg≈255）→ `fill ≈ 向白靠拢的浅色调`
   ⚠️ **百分比是"相对底色"的量**：白底上 10% 本身就是极淡的浅色调（曾因此被用户判为"看不清"），
   默认值已定为 **30%**。这是量纲问题，不是显示故障。
   ⚠️ **弱化状态改由颜色区分，不再靠"有没有填充"**（v1.49-s14）：
   s12e 曾因"弱化色比正常填充色更亮"而让弱化不填充，但那是旧"×α"换算的副作用；
   现两者按同一百分比混色、量级相当，反转问题不复存在。
   **同类教训（必须一起记）**：`UpsertRect(..., fill)` 的 `fill` 与
   `UpsertText(..., anchor)` 的 `anchor` **都必须纳入调和判断** ——
   只检查"是否新建"会漏掉"对象已存在但该属性仍是旧值"的情况，
   表现为"改了输入项但图上没反应"。
8. **BOS / MSS 用密集点线（`STYLE_DOT`），文字标注取线正中**。
   "正中" = 水平取线两端时间的中点 `(time[refBar] + tEnd) / 2`，
   垂直用 `ANCHOR_CENTER` 居中于该价位（故**不做** ±0.15×ATR 偏移）。
   弱化与否只由**颜色**区分，不再用线型区分（用户要求统一为点线）。
9. **OB 必须与 CISD 携带同一套位移度量**。他定义 OB 有效性用的是
   *"**Closure and displacement** are what validate the level."* —— 与定义 CISD 的是**同一句**。
   故 `AddObFromRun`/`AddObResult` 必须接收并透传 `strong`，
   `weak`/`bodyATR`/`penATR` 与 MSS/CISD 同源（都取自紧邻那次 `DisplacedBeyond()` 写入的全局）。
   **教训（D14）**：初版把这三个字段写死为 `false`/`0`/`0`，
   等于悄悄丢掉了他的两个有效性条件之一，而渲染上与"已验证"完全无异 —— 不报错、不露痕迹。
   ⚠️ **透传必须一路做到底**：第二版漏了导出层的 `state` 列，于是同一行 CSV 同时写着
   `displacement="…WEAK"` 与 `state="VALID"` —— **自相矛盾且按 `state` 过滤的下游会误收**（D25）。
   凡是"某个字段决定质量"的改动，**计算 / 渲染 / 导出三层的落点要一起列出来核对**。
10. **CSV 的 `tier` 列对 FVG / OB 输出 `n/a`**。这两类的 `refBar` 是 `runOldest` / `c1`，
   **按构造就不是结构锚点**，`NodeTierStr()` 对它们返回空串是必然 ——
   绝不能读作"该锚点无分级"。判据（无需测量）：锚点是**极值**的行解析成功率高
   （CISD 15/18、SWEEP 8/8），锚点是**任意 bar** 的行成功率低（OB 5/18、FVG 20/79）。
11. **`StructureEvent.weak` 只表示"位移不足"，不得复用作别的含义**。
    FVG 没有位移判据，它的失效状态只存在于 `ceBroken` / `fillPct`；
    初版把 `fvg[].weak` 赋成 `ceBroken`，等于把"失效后可反向使用（IFVG）"这一**换档**
    混同成"信号质量降级"，并把错误语义固化进数据模型（D21）。现恒为 `false`。
12. **文档里"他的要求"与"我们是否做到"必须分栏，不能只列要求**。
    原 `research` §11.2 的表格只写了引文与"对实现的约束"，读起来像达标清单，
    实际其中一行（OB 的前置扫荡）**零实现**（D23）。凡"要求 → 是否满足"的表，
    必须显式给出满足状态与证据行号。

**v1.49-s9g 起（D12：位移判据进入状态机）**：

1. **MSS 的位移判据不只是一条渲染规则，它是趋势改变的构成条件**。
   他：*"MSS marks a trend change **confirmed by displacement**."*
   故 `ApplyMssTransition()` 是**唯一**的 MSS 入口，四处调用点都必须经由它。
2. **弱 MSS 的语义**：仍然**记录事件**（G1 弱化渲染）、仍然**标记该位已破**
   （否则同一个位会在后续每根 bar 反复触发），但**不翻转趋势、不重置对侧 ref**，
   且**返回 0** 给 `mssBar` 门控（该门控抑制"同 bar 重建反向 ref"，趋势没变时不该抑制）。
3. **位移只在破位那根 bar 判定，不做事后重评**。代价：弱破位会"消耗掉"该 ref。
   自愈路径：下一个主结构 swing 确认时会设出新的 ref（`broken=false`）。
   "后来才出现位移"的情形由 **CISD 层**覆盖 —— 他体系里 CISD 本就是更灵敏的收盘确认工具。
4. ⚠️ **这类改动会改变事件集合，属语义变更而非 bug patch**。
   凡触及状态机的修复，都必须**预先写出可证伪的验收预测**（见 plan §19.4-D12），
   并预期 `docs/baselines/` 全部基线失效、需重测重归档。

**v1.49-s10 起（IRL / ERL 流动性配对）**：

1. **IRL/ERL 是逐帧派生量，不是事件**。它们依赖 `close[0]` 与 `g_curBias`，
   故 `ComputeErlIrl()` 必须排在 `FillEventBias()` **之后**，
   且三个量（valid/price/bar|idx）**全部要进 `needDraw` 指纹** ——
   否则价位变了而指纹没变，图上会停在旧位置。
2. **ERL 必须排除"已被取走"的位**。某个摆动高一旦在它之后被任何 bar 越过，
   流动性就已消耗，按他的体系应看**下一个**。不做这个排除会指向一个已经无效的目标。
3. **不画连接箭头**。他的配图里只有 IRL 色带 + ERL 点线两个元素各自带标签。
   加箭头属于"比原文多做"，会引入他没有的语义。
4. **无 HTF 偏置时不画**（`g_curBias == 0` → 直接返回）。这是他的明确前提，
   不是保守起见：偏置为 0 时上下两侧都可能是目标，画出来等于给了个假结论。

**v1.49-s11 起（protected swing 改用他的定义）**：

1. **`SetProtectedFromCisd()` 是 `refHigh` / `refLow` 的唯一写入点**（除播种）。
   任何"从 swing 直接写 ref"的代码都是回归 —— 他的 protected swing 由 CISD 定义。
2. **`CheckBreakAgainstRefs` 在 `CheckCisd` 之前调用**，这个顺序有语义：
   同一根 bar 上，先判定"是否突破了已存在的 protected swing"，再建立"本 bar 新形成的
   protected swing"。反过来会让同一根 bar 自己破自己。
3. **不得再引入幅度/层级门槛**。他的定义里两者都没有；若要加，必须先有一手依据。
4. ⚠️ **本改动改变了全部结构事件的锚点** —— `docs/baselines/` 全部基线失效，
   且**不能**再用"旧事件逐字不变"作为验收判据（那正是本次要改的东西）。
   替代判据：`refBar` 必须恒等于某个 `cisdHighBar` / `cisdLowBar`。

**v1.49-s15 起（独立代码评审后的修正）**：

1. **`needDraw` 指纹必须含"新 bar"项**（现为 `time[0] != g_lastT0`）。
   背景：约 11 组对象以 `time[0]` 为右端；原指纹不含新 bar 项，于是新 bar 到来时
   若没有其它项变化，它们**不会延长**（右端滞后约 1 根）。
   附带的更大收益：它同时覆盖了"**等量换血**"—— 事件数组只按**条数**取指纹，
   窗口滑动导致"旧事件离开 + 新事件形成、条数恰好不变"时原本不可见。
   因为事件数组只在**全量重算路径**重建，而那条路径正是由新 bar 触发的。
   同理 `g_relT1` / `g_relT2` 也必须进指纹（新 HTF bar 上极值可能恰好没变，
   但 RELH/RELL 与 RANGE 的左端锚点变了）。
2. **版本号只允许有一个来源 = `BUILD_TAG`**。
   历史事故：`OnDeinit` 曾硬编码 `"v1.48"`，而 `BUILD_TAG` 已到 `v1.49-s14b` ——
   于是**最能证明"加载了哪一版"的那行卸载日志，反而一直在报错的版本**。
   凡日志中的版本号，一律只打印 `BUILD_TAG`，不写版本字面量。
3. **不得引入"看起来在省事、实际永不生效"的门控**。
   历史事故：`UpdateLiveLeg` 的防扫描门控含条件 `time[lastBar] == time[0]`，
   而节点 bar 必然 ≥ 1（节点只在 `k >= 1` 之后加入），该合取项**永不成立** ——
   门控成了死代码，O(lastBar) 扫描每 tick 都跑，而注释还写着"连扫描都不做"。
   **新增门控必须验证其条件真的可达**（写一行诊断计数或推演边界）。
4. **冗余标志要删，不要留着**。`g_gfxDirty` 全文只有一处写入，且紧邻 `changed = true`
   ⇒ `changed || g_gfxDirty` ≡ `changed`。它是被否决方案的残留，两处注释也是假的。
5. **诊断输出不得落在每 tick 路径上**。`STRUCT_ORIENT` 原在快路径 `return` 之前，
   在 `InpDebugShowRef=true` 时每 tick 付两次 `TimeToString` + 一次日志写；
   已移到快路径之后（每全量帧一次）。
6. **`ObjectGet*` / `ObjectsTotal` 是否 IPC：去测，不要靠注释**。
   文件内两处注释对此**互相矛盾**（一处称"跨进程"、一处称"直接访问"），
   而所有"避免 ObjectGet*"的性能论证都以它为前提。**未证实前不要据此重构。**

**v1.50-s18 起（后验扫描的自复位约定；一次真实的漏复位事故）**：

1. **任何后验扫描函数必须自己复位自己的计数**，且**复位要放在早退之前**。
   约定先例是 `ComputeSweeps` 的 `nSWEEP = 0`。
   **事故**：`ComputeClosures` 漏了自复位，且 `ComputeStructure` 顶部的集中复位块
   （复位 `nNodes/nMSS/nCISD/nBOS/nBox/nFVG/nOB`）也没带上 `nClosure` ⇒
   **每经过一次全量重算就累加一遍**：首帧 `nodes=59/closure=59`（正确），
   下一帧 `nodes=58/closure=117`（≈59+58）。
   放在早退之前是**必要**的：否则 `InpShowClosures=false` 时会留下上一帧陈旧数据，
   而那正是 A/B 对照（"关掉开关 = 零该类事件行"）的前提。
2. **⚠️ 证明的辖域必须覆盖结论的辖域。**
   事故前我曾断言不变量 `closure ≤ nodes` **"构造性成立、无需测量"** ——
   那个证明本身没错，但它只量化在**单次调用内**，而 bug 在**跨调用**。
   抓出它的是**运行时数据**（不变量 + CSV 头部计数），
   **不是**编译（`0 errors / 0 warnings`）、**也不是**推理。
3. **在"指数随时间平移"的数据上，任何基于"锚点值重复"的判据都不可靠**。
   两种试过且**无效**的手段：① "同一 `c2` 是否重复" → 两帧指数整体 +1，
   天然不重复，返回"零重复"的假阴性；② "`c2` 与 `c2+1` 同时出现"（平移重叠）
   → 相邻 bar 本来就聚集（对照 FVG 也有 27/100），无区分力。
   **可用的是计数型不变量**，以及**把不变量做成日志自检**
   （已落地为 `TradFi_CLOSURE … invariant=OK|VIOLATED`，并带 C4 三项计数
`c4ok` / `c4broke` / `c4pending`）。
4. **纯渲染元素也必须留下可测量痕迹。**
   阶段 16/17/19 的三个元素原先既不进 CSV 也不打日志，
   于是验收判据退化成"请你自己看图"。现由 `TradFi_RENDER` 一行输出：
   `icValid/icLevel/icRefBar | tgtCount/fibValid/fibA/fibB | objs total/IC/HTF/TGT/FIB/CloLbl/C3EQ`。
   预期关系可直接当判据：`HTF = InpCandleCount × (3 + 时间标签?1:0)`、`TGT = 2 × 目标数`、
   `FIB = 2 × 目标条数`、`IC ∈ {0,2}`，另报 `icLate`（0/1）与 **`icHits`**（IC-CISD 累计触发次数）。
   ⚠️ **`icValid` 是逐帧快照，会漏掉 bar 内"触发又消失"的情况 —— 判断 IC-CISD 是否真的在跑，
   以 `icHits > 0` 为准**，不要看 `icValid`。纯渲染元素没有 CSV 痕迹，就必须自己造痕迹。
5. **改动判定层后先跑 `Indictor/audit_state.ps1`。** 它把第 1 条那个 bug 做成了机械绊线：
   ① 每个 `StructureResult` 计数都有复位；② 复位所在函数**确实驱动**自增
   （只由集中复位块覆盖者标 `OK*`，属较弱保障）；③ 逐帧全局清单都有非声明式赋值；
   ④ `RenderScene` 读到的全局若不在 `needDraw` 指纹里，必须在脚本的 `justified` 表里
   **写明理由**，否则判 FAIL（早期是"信息性"输出 —— 一张会被无视的清单没有价值）。
   ⚠️ 它**不**检查路径可达性、**不**检查值的正确性、也**看不到通过引用出参写入的赋值**
   （具体一处：`EvalEarlyCisd(close, g_icValid, g_icLevel, g_icRefBar)`，
   那类模式必须人工确认出参带 `&`——MQL5 简单类型不加 `&` 时按值传递，
   调用方变量**不会被改却照样编译通过**）。**它是绊线，不是验证器。**
6. **检查器本身也需要被验证，且结论必须带上"它凭什么这么说"。**
   历史事故：`audit_state.ps1` 初版①用松散正则追踪"当前函数"，把自增归属错到
   `FindBrokenNodeBar`，对两个**实际有复位**的计数误报 NOT reset（假 FAIL）；
   ②把"声明时带初始值"当成逐帧赋值，于是 31 个全局**全部假 PASS**、落点全是
   `<top-level>`，一眼看去全绿而实际什么都没验证。
   → 检查器输出的每条结论都必须带**函数名与行号**，归属错了要能一眼看出来。
   会喊狼来了的检查与永远沉默的检查**一样有害**。
7. **验证检查器的标准手法（只跑一次"通过"不算验证过检查器）**：
   *故意破坏被检查的属性 → 确认检查器会喊 → 还原 → 确认源码哈希回到原值。*
   已照此验证检查 D：删掉 `needDraw` 里的一项后它确实报出该全局，还原后 `mq5` 哈希
   与测试前逐字节一致。
8. **凡 .NET 静态 API 涉路径，一律给绝对路径。**
   `[System.IO.File]::ReadAllBytes('相对路径')` 用的是**进程 CWD**，`cd` / `Set-Location`
   对它无效 —— 本会话因此踩了两次 `FileNotFoundException`。
9. **不变量：正常时静默，被破坏时无条件发声；报警与调试开关解耦。**
   事故背景：`closure ≤ nodes` 是 v1.50-s18 跨帧累加 bug 的**唯一现场证据**，
   却**只在 CSV 头部可见** —— 没人会每根 bar 去读 CSV 头部。
   一个"被破坏时无人看见"的不变量，等于没有不变量。
   → 约定：`DbgReport()` 里不变量检查提到 `if(!InpDebugShowRef) return;` **之前**；
   正常时静默，被破坏时 `PrintFormat("TradFi_INVARIANT VIOLATED: …")` **不看任何开关**。
   **调试开关只控制"正常时的详尽程度"，不控制"异常时的报警"** ——
   否则用默认配置的人永远看不到异常。
   > 这是第 6 条（"永远沉默的检查与喊狼来了一样有害"）在**运行期**的对应物：
   > 第 6 条讲静态检查器，本条讲运行期断言。

---

# SMC 工具箱的领域语言（`TradFi_SMC_Toolbox.mq5`）

> ⚠️ **与上面的 TTrades 体系是两套口径，不要互相套用。**
> 上面那份（`TradFi_Structure`）的每个术语都有 TTrades 一手引文；
> 本节的术语来自 **SMC 行业通行读法**，其中**多数没有权威口径**，凡此类均已标注。
> 术语通行性核实见 `docs/research/2026-09-24-SMC-terms-research.md`；
> 口径决策与被实测推翻的假设见 `docs/plans/2026-09-24-SMC-toolbox.md`。

**枢轴 / Pivot (Symmetric Window Pivot)**:
`p` 是枢轴高 ⟺ `high[p]` **严格大于** `[p-len, p+len]` 内其余每一根。**确认延迟 = 右窗口长度 `len`**。
_Avoid_: 分形（那是 `len=1` 的特例）
> **两层结构 ≠ ICT 递归分级。** swing / internal 只是两个不同半窗的检测器。
> ICT 真正的分级是**递归晋升**（三点分形 → STH；两侧更低的 STH → ITH；两侧更低的 ITH → LTH），
> 本工具**不声称**实现它。调研引 ICTKillzone 的警告：
> *"most use lookback windows rather than the recursive rule, and they disagree with the
> hierarchy exactly where it matters."*

**BOS / CHoCH**:
BOS = 朝趋势**同向**突破（延续）；CHoCH = 朝趋势**反向**突破（首次反转警告）。
_Avoid_: MSS（那是 TTrades 用语，全站 110 篇零命中 CHoCH，两者不可互换）
> `trend==0`（尚无方向）的**首次**突破标 **BOS**。理由：CHoCH 的字面含义是"性格**改变**"，
> 此处没有"前一种性格"可改变，标 CHoCH 等于声称一次无法验证的反转。
> **主流 Pine 实现靠"收盘价不可能同时高于 A 又低于 B"的几何巧合隐式保证互斥**，
> 一旦高/低位倒挂就会两分支同时执行、趋势被后写覆盖 → 本实现加**显式倒挂守卫**。

**订单块 / OB (Order Block)**:
**引发位移之前的最后一根反向 K 线**（或连续反向 K 线簇）。
_Avoid_: 与 `TradFi_Structure` 的 OB 混用 —— 那边是由 CISD 造势序列派生的，**不是同一个东西**
> ⚠️ **区间基准无统一口径。** LuxAlgo「Order Block Anatomy」官方原文：
> *"exactly which prices bound the zone … **conventions genuinely differ here**"*、
> *"**None of this is standardized**"*。全幅（Quantum）/ 实体 / 混合（Black Tie）三种都属一线主流。
> 默认取**混合**：影线全幅作区间 + 实体并集的 50% 作**均值门槛线**（显式画出，
> 因为 body-50% 与 full-range-50% 是**不同数值**）。
> 两个**并存状态**：*缓解* = 价格触及（只降级配色）；*失效* = **实体收盘穿越远端**。

**公允价值缺口 / FVG，与 IFVG**:
三根 K 线缺口，边界取**整根高低（含影线）**。**IFVG = 实体收盘穿越整个缺口后换向使用**。
_Avoid_: 把 CE 当反转判据（CE 是成立**之后**的入场位）
> **IFVG 判定有逐字一致的权威依据**（LuxAlgo 与 ICTKillzone 两家）：
> 影线穿过**永不算**（*"a wick-through alone is usually read as a probe"*）。
> 故实现**写死**为 `close` 穿越远端，**不设开关**。
> ⚠️ 实测：**83%** 的缺口最终会被完全穿透 → `InpFvgHideFilled` 默认 **false**
> （默认隐藏等于出厂抹掉六分之五的检出量）。

**等高等低 / EQH / EQL**:
两个或以上同类型枢轴停在几乎相同价格 → 流动性池，是被**瞄准的目标**而非墙。
_Avoid_: 支撑阻力
> 容差无官方默认值，可考实现实测 0.10~0.25 × ATR → 取 **0.15**。
> ⚠️ **必须挂内部层**：实测波段层枢轴间距中位数 **130** 根，远超任何合理的"相等"窗口
> → 挂波段层时 EQ **恒为 0**；内部层间距中位数 13 根，正常成池。
> 画成**容差带**而非线（LuxAlgo 明确建议）。

**流动性扫荡 / SWEEP**:
影线越过结构位但**收盘收回位内**。**不消耗该位** —— 后续真正的收盘突破照样能出 BOS/CHoCH。
_Avoid_: 假突破
> 与 `TradFi_Structure` 的 SWEEP 同名同义，但取位来源不同（那边只取 intermediate 节点）。

**诱导 / IDM (Inducement)**:
位于当前价格与目标区之间、**最近的内部回撤摆动点** —— **它是角色标签，不是新检测算法**。
_Avoid_: 把 IDM 当成一种特殊枢轴
> 调研明确这是**分类学分歧**：*strict structure-mapping models* 里 IDM 特指"波动极值前最近的
> 内部回撤"，且"目标区要等它被取掉才算有效"；*looser usage* 里则泛指任何陷阱。
> 本实现取**严格口径**，且**不用它门禁目标区**（那是 strict models 专属做法）。

**Premium / Discount / EQ（dealing range）**:
按区间的 50% 对分：上半 = premium，下半 = discount，中缝 = EQ。公式无分歧。
_Avoid_: 超买超卖
> ⚠️ **端点取法是本条唯一无权威口径处。** LuxAlgo 教学层要求"有意义的 leg"并警告
> *"Minor swings produce random midpoints"*；Black Tie / Quantum 则机械取"最近 pivot"。
> 本实现取**结构层当前活跃（未被突破）的 swing 高/低** —— 选它是因为**内部自洽**：
> 与结构线共用同一对位，区间不会与结构线互相矛盾；重锚规则也随之继承
> （收盘突破任一端 → 该位被消耗 → 新区间由下一对枢轴给出）。

**强/弱高低点 / Strong-Weak High-Low**:
⚠️ **本术语没有任何权威口径。** LuxAlgo 官方 Library 的 **54 个** SMC/ICT 概念、
ICTKillzone 的 **115 条**术语表**都不收录**它；三份可读实现**无一输出该标签**。
_Avoid_: 把它当成标准概念引用
> 社区存在两套**结论相反**的读法，本实现只提供这两套（不发明第三种）：
> · `SMC_SW_SWEPT_IS_WEAK`（**默认**）：**已被越过** = 流动性已耗 = 不再是要取的目标 = 弱。
> · `SMC_SW_DISPLACED_IS_STRONG`：之后出现**过位移门槛的反向破位** = 它保护住了趋势 = 强。
> **默认取前者**：有可机械判定的真值条件，不依赖趋势状态、不会自己漂移。

**Killzone（亚洲 / 伦敦 / 纽约）**:
以**纽约时间**为锚的时段窗口。边界各家相差 30~90 分钟，故**全部可编辑**。
_Avoid_: 交易时段（那是交易所有无开盘，与此无关）
> ⚠️ 换算**不能用固定 GMT 偏移**：broker 多数跟随**欧洲** DST、纽约跟随**美国** DST，
> 两者切换日期每年相差约 3 周 —— 固定偏移在那几周里必错 1 小时，且错得看不出来。
> 实现用 `TimeGMT()` 反推服务器偏移 + 美国 DST 规则（3 月第 2 周日 ~ 11 月第 1 周日）。
> 已知限制：`TimeGMT()` 在策略测试器里可能不准；DST 只判到日粒度 → 提供手动覆盖。



