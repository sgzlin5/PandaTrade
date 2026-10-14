# TTrades 结构口径调研（MSS / CHoCH / BOS）

> 调研日期：2026-09-23
> 方法：以 ttrades.com 一手文章为主体（逐篇抓取正文原话）；辅以其官方 YouTube（@ttrades_edu）视频标题/描述/章节；对其全站 110 篇文章做过 WordPress REST 全量检索 + 全文正则 grep，用于确认术语是否存在。第三方内容仅作交叉核对，不用于任何定义。
> 一手来源：ttrades.com 文章 20+ 篇（作者署名 TTrades）、其 YouTube 视频描述与章节、其官网 Indicator 功能说明
> 未决问题：5 项（见 §9）
>
> **⚠️ 注**：写入前该路径已存在一份同名并行调研稿（标题为「MSS / CISD / relevant swing」）。本文件按任务给定的结构重写并替换，内容以本次独立核实的证据为准。

## 0. 结论速览

- **Q1（最重要）：TTrades 完全不使用 "Change of Character" / "CHoCH" 这个词。** 他既不区分 MSS 与 CHoCH，也不把它们当同义词——CHoCH 不在他的术语体系里。他真正做对比的一对是 **MSS vs CISD（Change in the State of Delivery）**。若指标要"对齐 TTrades 口径"，不应保留 CHoCH 分支，而应改为 MSS / CISD 双概念。
- MSS 的一句话定义：*"It happens when price displaces and closes above or below a swing high or swing low."*（**位移 + 收盘**越过摆动点）。另有 *"MSS : A clear break and close beyond a key swing point, signaling intent."*
- **流动性扫荡不是 MSS 的硬前置**：*"The close through that series of candles is what confirms the shift. **The sweep itself is not the confirmation.**"* 但高周期偏置是硬前置：*"The higher timeframe provides the bias and the lower timeframe provides the structure confirmation."*
- **位移是 MSS 的必要确认**：*"The key confirmation is displacement (strong price movement with momentum) that breaks prior structure."*
- **必须收盘越过，不是影线**：*"If the candle cannot close through the level you need, the reversal is not confirmed."*
- 参考摆动点有可机械化的一条：高周期**回看 3 根 K 线**（含当前）取极值；并有 failure swing vs relevant swing 的过滤规则。但"哪一级摆动被破算 MSS"**没有**明确规则（§9）。

## 1. MSS vs CHoCH（核心问题）

**结论：CHoCH 在 TTrades 的一手材料中不存在。** 这是"存在性否定"，不是"没查到"。

可复核的验证方式：
- `https://ttrades.com/wp-json/wp/v2/posts` 拉取全部 110 篇文章正文做正则：`change of character` 命中 **0**，`\bchoch\b` 命中 **0**。同语料对照：`CISD` 命中 5、`displacement` 命中 20（证明检索有效）。
- YouTube 频道 `@ttrades_edu` 站内搜索 `choch` / `change of character`：**无任何视频标题命中**。
- 官方 Telegram `t.me/s/learnfromttrades`：可见帖文中零命中。
- 反例警告：ttrades.com 的 `?s=` 站点搜索**不是**服务端过滤（任何关键词都返回同样的 110 条），**不能**用作证据；REST/grep 才是。

### 1.1 MSS 的定义（TTrades 原话）

来源：<https://ttrades.com/market-structure-shifts-vs-change-in-the-state-of-delivery-a-clear-comparison/>（2025-07-01，视频 <https://youtu.be/E89d1HArbgM>）

> "A market structure shift occurs when the market transitions from bullish to bearish or bearish to bullish.
> • It happens when price **displaces and closes** above or below a swing high or swing low.
> • Example: Price creates a swing low, **sweeps liquidity**, then breaks and closes below that low, signaling a bearish shift in structure."

> "Essentially, MSS marks a trend change **confirmed by displacement**."

更简练的一句（他的亲笔措辞，但描述的是他所讲解的 MMXM Trader 模型，非其自有模型）：

来源：<https://ttrades.com/the-mmxm-traders-twitter-model-explained/>（2025-07-17，视频 <https://youtu.be/WwmS47Gb3M0>）
> "MSS : A clear break and **close** beyond a key swing point, signaling intent."

趋势视角的基础版定义（<https://ttrades.com/understanding-basic-market-structure-in-trading/>，视频 <https://youtu.be/sgAnVR6RSDg>）：
> "A market structure shift occurs when the prevailing trend reverses: From bearish to bullish: price stops making lower lows and begins forming higher highs."

### 1.2 他真正做对比的对象：CISD，不是 CHoCH

同一篇"对比"文章里，对照物是 **Change in the State of Delivery**：

> "The change in the state of delivery (CISD) looks at order flow differently. • Instead of focusing on swing highs or lows, it focuses on **the opening price in the series of up-close or down-close candles**. When price displaces and closes beyond that open, it validates the level as an order block."

> "Timing: **CISD often appears earlier than MSS**... Validation: MSS confirms broader trend changes, while CISD validates specific order blocks. Practical Use: CISD can give earlier entries but sometimes too early, leading to false signals, MSS is slower but often more conservative."

CISD 的独立定义（<https://ttrades.com/understanding-the-change-in-state-of-delivery-cisd/>，视频 <https://youtu.be/CHIK5oBRKiw>）：
> "Bullish to Bearish: Price forms a series of up-close candles, then closes below the opening price of those candles."

他给出的标准次序：*"1. Inversion or CISD shows early order flow weakness. 2. MSS confirms the structural shift. 3. Price retraces into a premium or discount zone, giving the best entry."*

**⚠️ 对指标的直接影响（推断，非原话）**：在他的体系里，"位移并收盘破坏摆动点" = MSS，"收盘穿过一串 opposing candles 的开盘价" = CISD。一个只有 MSS/CHoCH 两态的 state machine 与他的一手口径不一一对应——**CHoCH 那一态在他的语汇里没有对应物**。

### 1.3 TTrades 的 MSS 与 ICT/SMC 的 CHoCH 有何区别

**⚠️ 证据等级声明**：本节的 TTrades 一侧全部来自 §1.1 / §1.2 的逐字引文（一手）。
**ICT/SMC 一侧，本项目未能取到 ICT 本人的一手文本** —— 检索只返回第三方
（ATAS / 3commas 博客、各家 TradingView 脚本、券商教育页）。按本项目标准（同 D11 对 BOS 的处理），
**不采信二手转述去定义 CHoCH**。因此下面把 CHoCH 一侧明确标为
「**社区通行读法，未经一手核实**」，而把差异的论证建立在**他的原文**上。

**差异一：参照物不同（一手可证）**

| | 社区通行的 CHoCH | TTrades 的 MSS |
|---|---|---|
| 参照物 | 趋势中最近的一个**反向摆动点**（价格极值） | 同样破摆动点，**但必须带位移** |

**差异二：是否要求位移 —— 这是最大的区别（一手可证）**

他：*"Essentially, MSS marks a trend change **confirmed by displacement**."*
*"It happens when price **displaces and closes** above or below a swing high or swing low."*

→ CHoCH 类实现通常只要求"破了最近的反向摆动点"，**没有位移门槛**；
他的 MSS 把位移写成**定义的一部分**（本实现即三条门槛：实体 ≥1.0×ATR、穿越深度 ≥0.3×ATR、时效窗口）。

**差异三：承担"早期反转信号"角色的不是 CHoCH，是 CISD（一手可证）**

这是对指标影响最大的一条。在同一篇**专门做对比**的文章里，他拿来与 MSS 对照的是 **CISD**，
而不是 CHoCH；并且他明说了分工：

> *"Timing: **CISD often appears earlier than MSS**. … CISD can give earlier entries but sometimes
> too early, leading to false signals, **MSS is slower but often more conservative**."*
> 标准次序：*"1. Inversion or **CISD** shows early order flow weakness. 2. **MSS** confirms
> the structural shift. 3. Price retraces into a premium or discount zone."*

→ 在 SMC 语汇里 CHoCH 常承担"早期反转提示"；**在他这里这个角色由 CISD 承担**，
而 CISD 的参照物完全不是摆动点，而是**"一串同向收盘 K 线中最旧一根的开盘价"**
（配图 `CISD-2026-01.png` 把这层差异画得很清楚：CISD 线明显远离极值）。

**差异四：他把"扫荡"与"确认"明确拆开（一手可证）**

> *"The close through that series of candles is what confirms the shift.
> **The sweep itself is not the confirmation.**"*

→ SMC/CHoCH 教学中常把"扫荡流动性 + 结构破坏"当作一个组合信号；他明确拆成两件事。

**不是差异的地方（低置信度，待核实）**：ICT 教学里同样使用
**short / intermediate / long-term highs and lows** 这套分级（研究 §4），
即"层级"很可能不是他与 ICT 的分野，**真正的分野在"位移是不是定义的一部分"与"CISD 的存在"**。
⚠️ 本条**未取到 ICT 一手文本**，标注为待核实。

**一句话回答用户的问题**：
**不是"同一个东西的两种叫法"，而是两个学派的不同构件** ——
CHoCH 是 SMC 语汇里"破最近反向摆动点"的反转提示；他的 MSS 是"**位移确认**的趋势改变"，
且他在自己体系里**用 CISD（而非 CHoCH）担任更早的那一环**。
他全部一手语料中 CHoCH **零命中**（§1 的可复核验证）。


## 2. 前置条件（流动性扫荡 / 高周期偏置）

**2.1 流动性扫荡：不是硬前置。** 他专门做过视频把两者拆开：<https://youtu.be/5rbFskdmEmU> "Structure Shift vs Liquidity Grab"、<https://youtu.be/ynFA6E3qHj0> "Market Structure Shift vs Liquidity Grab - ICT Concepts"。最直接的一句原话：

来源：<https://ttrades.com/let-the-wick-form-trade-the-body-stop-getting-stopped-out/>（2026-08-29，视频 <https://youtu.be/RX8vtP3PLYk>）
> "The close through that series of candles is what confirms the shift. **The sweep itself is not the confirmation.**"

扫荡出现在"典型序列"里，但被写成样例而非必要条件——§1.1 引文里的 "Example:" 就是这个性质。另有序列表述（mmxm 篇）：
> "As long as you respect the same sequence — **raid, FVG, MSS/SMT** — the model remains valid."

注意该序列中 FVG 在 MSS **之前**，而非由 MSS 制造（见 §3.3）。

CISD 侧则把扫荡写成前置**观察项**（<https://ttrades.com/understanding-the-change-in-state-of-delivery-cisd/>）：
> "A liquidity sweep has likely taken place above a high or below a low."
> 工作流："1. **Watch for liquidity sweeps at obvious highs or lows.** 2. Wait for a close against the previous direction to confirm CISD."

同时明确"扫荡本身不构成有效摆动点"（<https://ttrades.com/how-change-in-the-state-of-delivery-cisd-confirms-swing-points/>，视频 <https://youtu.be/vn1RYjhJUnQ>）：
> "A swing point is not valid simply because liquidity is swept."

**2.2 高周期偏置 / draw on liquidity：在其模型内是硬前置。**
> "The higher timeframe provides the bias and the lower timeframe provides the structure confirmation." / "Structure tells you what price is doing, but the higher timeframe tells you why you should be looking for that direction in the first place." / "Without that higher timeframe reason, you are just blindly trading breakouts."
> （<https://ttrades.com/how-to-trade-breakouts-failure-to-manipulate/>，视频 <https://youtu.be/8yt3jn8L6O4>）

> "CISD on its own means nothing to me unless it is paired with a higher time frame candle closure... **If CISD is missing, I ignore the setup completely.**"（CISD Confirms Swing Points）
> "Never drop to the hourly until you have a one-sided daily bias."（<https://ttrades.com/fractal-model-playbook-aligning-daily-hourly-and-5-minute-charts/>，视频 <https://youtu.be/TNybDCtwBnc>）

Draw on liquidity 用前日高低点具体化（<https://ttrades.com/the-easiest-draw-on-liquidity/>，视频 <https://youtu.be/FXJBFbZQbck>）：
> "In a bullish trend, price repeatedly takes previous day highs. In a bearish trend, price repeatedly takes previous day lows."

**推断（非原话）**：其模型固定为"偏置 → 结构确认 → 入场"，MSS 本身不承担方向判断职责；方向由高周期给。

## 3. 位移（displacement）与 FVG

**3.1 定义（他唯一的一句显式定义）**——<https://ttrades.com/understanding-basic-market-structure-in-trading/>：
> "The key confirmation is displacement (**strong price movement with momentum**) that breaks prior structure."

另有专讲位移的视频：<https://youtu.be/1oco9lesido> "What is Displacement? - ICT Concepts"，描述为 *"This video should help you understand displacement during a Market Structure Shift."*；章节标记见 <https://youtu.be/PePk1V0Q4QQ>（"1:50 Displacement"）。

**3.2 位移是 MSS 的确认条件 → 是。**
> "Essentially, MSS marks a trend change confirmed by displacement."（MSS-vs-CISD 篇）

质量判据（定性，无数值）：
> "High-quality CISD usually shows: • A clean V-shaped reversal or **strong displacement** • A **decisive close through structure** • **Minimal sideways consolidation** before the close. If price chops for a large portion of the candle and barely closes through structure, it is usually consolidation rather than a true shift in delivery."（CISD Confirms Swing Points）

速度门槛：
> "The best setups form **within one to three candles** and show immediate displacement."（<https://ttrades.com/why-your-continuations-fail-order-blocks-cisd-explained/>，视频 <https://youtu.be/PQiRV0JMhIQ>）

反向用法（位移失败 = 反向信号）：
> "Failure to displace above previous day high suggests a bearish bias toward previous day low."（<https://ttrades.com/the-easiest-draw-on-liquidity/>）

**3.3 是否必须留下 FVG 才算结构破坏？→ 未找到一手来源（§9）。**
他反复把 FVG 与位移并列，但每次都是"叠加/加分"而非"必需"。例：<https://ttrades.com/breaker-blocks-simplified/>（视频 <https://youtu.be/75S4vwD4P1U>）
> "When displacement occurs through the breaker block, leaving behind a fair value gap, the probability of price reacting to that zone increases."

## 4. 被突破的参考摆动点如何界定

他有整套自查术语，**没有**单一答案，给的是梯度：

来源：<https://ttrades.com/advanced-market-structure-simplified-from-short-term-to-long-term-trends/>（2025-07-11，视频 <https://youtu.be/umyCqr_0NsI>）
> "A **short-term low** forms when a swing low has a higher low on each side of it."
> "An **intermediate-term low** forms when a short-term low has another short-term low to its left and right."
> "A **long-term low** is confirmed when price reacts from a higher timeframe level, then forms a short-term low on each side."
> "Market structure shifts (MSS) and breaks of structure (BOS) are clearer once you know the hierarchy"
> "Look for short-term highs/lows to confirm shifts. Use intermediate-term sweeps as confirmation of continuation or reversal."

**swing 点本身的定义 / failure swing vs relevant swing**（<https://ttrades.com/relevant-swings-which-swing-highs-and-lows-matter-in-trading/>，2026-03-21，视频 <https://youtu.be/HbOeD_JVens>）：
> "A bullish swing point forms when a candle prints a low and there is a higher low to its left and a higher low to its right."
> "A failure swing is a swing point that does not represent a meaningful extreme. It usually forms **too close to a prior high or low** and **lacks proper range separation**... Liquidity is still resting beyond it, which means price is likely to trade through it before forming a true reversal."
> "A **relevant swing** is different. It is **the extreme of the move within the current context**... It stands apart from prior structure."

separation 无数值公式（他本人明确否认）：*"There is no strict numerical formula for separation. It comes from experience and structural awareness. The key idea is simple. If it is too close, expect it to be taken. If it stands alone, respect it."*

**可机械化的高周期回看窗口（对指标最有用的一条）**：
> "focus on the current higher timeframe and **look back three higher timeframe candles including the current one**. The highs and lows within that window are your relevant levels. On the daily chart, this often means looking back three monthly candles. On the hourly chart, it may mean looking back three daily candles."

relevance 会迁移（等价于承认事后更清晰）：
> "As price evolves, relevant swings will shift. **If a relevant high fails to produce a reversal, the next extreme becomes the new relevant high.**"

**protected swing（他定义风险用的那个点）**——<https://ttrades.com/let-the-wick-form-trade-the-body-stop-getting-stopped-out/>：
> "A protected swing forms when price reaches an important level and then **closes through the series of candles into that level**. That important level can be a high, low, or fair value gap."

另见 <https://ttrades.com/using-order-blocks-for-continuations/>（视频 <https://youtu.be/IJcfC6wAPZU>）：
> "Continuation OBs formed from a fair value gap or from sweeping a low are Protected Swings."

**⚠️** "MSS 必须破哪一级（最近对侧短周期摆动 / major swing / 最近保护高低点）"——他**没有**给出这种二分规则；只能确认他按 short/intermediate/long-term 分级讨论，且 intermediate-term 的扫荡被当作"延续或反转的确认"。此项列为未决（§9）。

### 4.1 关键澄清：三档是**摆动点的标签**，不是**多条结构线**

**他没有"短期结构线 / 中期结构线"这种画法。** 证据是他本人的三张配图（`docs/research/img/`）：

| 配图 | 内容 | 画了什么线 |
|---|---|---|
| `Short-term.png`（"Short Term High & Low"） | 一个 `STH`、一个 `STL` | **无线**，只有点标注 |
| `ITM.png`（"Intermediate Term High & Low"） | 四个 `STH`、一个 `ITH` | **无线**，只有点标注 |
| `ITM-FVG.png`（同上标题，另一种类型） | 一个 `ITH` + 几段短横线 | 短横线是 **FVG 的边界**，不是结构线 |
| `LT.png`（"Long Term High & Low"） | `STL` / `ITL` / `LTL` | 唯一一条线是左下角标注 **"HTF Level"** 的高周期锚定位 |

→ 三档是**同一个折线结构上的点被贴上不同层级的标签**，不存在"每个层级各画一条结构线"。
"层级"承担的是**用途分工**（同文「Identifying Market Shifts」逐字）：
> "Short-term highs/lows show **local price reactions**."
> "Intermediate-term highs/lows **confirm stronger pivots and sweeps (protected swings)**."
> "Long-term highs/lows set the **broader framework** for where price is likely heading."

### 4.2 新发现一手细节：intermediate 有**两种**类型

同文「Intermediate-Term Highs and Lows」逐字：
> "Intermediate-term highs and lows are simply multiple short term highs and lows that create stronger pivot points"
> "**There are two types**:
>  · **Basic** intermediate-term structures (built off short-term swings).  → 配图 `ITM.png`
>  · **Rebalanced** intermediate-term structures (formed when price **rebalances a fair value gap** and trades away). → 配图 `ITM-FVG.png`"

⚠️ 本条此前**未记录**于本报告，也未在本指标中实现。
意义：他的 intermediate 层级有一条**不依赖"左右各一个同类摆动"**的识别路径 ——
**价格回补了一个 FVG 并离开**。而我们已经有 FVG 检测（阶段 9），
故这条在实现上是**可机械化的**，且能把 1-D 的 tier 判定从"纯几何"扩展到"含 PD Array"。

## 5. BOS 的定义与区别

**未找到一手来源（对他自己的 BOS 定义而言）。**

事实是这个术语在其材料中几乎不出现：全部 110 篇文章正文中 `break of structure` 仅出现 **1 次**（即 §4 的 hierarchy 引文）；无 BOS 专文、无 BOS 视频标题、无定义句。第三方站点（howtotrade、equiti 等）有大量 MSS/BOS 对照内容，但**不属于 TTrades**，本报告不采信。

可确证的相关原话：
- "Market structure shifts (MSS) and breaks of structure (BOS) are clearer once you know the hierarchy"（advanced-market-structure）——**并列**提及，未做区分。
- "**Not every break of structure is a full reversal.**"（<https://ttrades.com/understanding-basic-market-structure-in-trading/>）
- 视频标题 <https://youtu.be/yq4Z7q4E6nU> "Trading without a Structure Shift / Break - ICT Concepts"；视频 <https://youtu.be/5rbFskdmEmU> 描述：*"Displacement vs Lack of displacement. **Break of structure vs Liquidity Grab**."*

**推断（标注为推断）**：在他的用法里 BOS 更像"任意越过结构位"的中性描述（因此才有 "not every break of structure is a full reversal"），而 MSS 是"被位移确认的、趋势级别的"破坏。但这句区分是从上述两句推出的，**不是他的原话**。

## 6. 确认方式（收盘确认 or 影线）

**必须收盘确认；影线刺穿不算。**

- "It happens when price displaces and **closes** above or below a swing high or swing low."（MSS 定义句）
- "MSS : A clear break and **close** beyond a key swing point, signaling intent."（mmxm 篇）
- "If price takes a level, do not assume the reversal has formed. **Wait for the candle closure.**" / "If you are looking for a reversal and **the candle cannot close through the level you need, the reversal is not confirmed.**"（<https://ttrades.com/how-to-trade-breakouts-failure-to-manipulate/>）
- "That closure is what matters. **Without it, price has not been confirmed.**"（CISD Confirms Swing Points）
- 模型级：*"Waiting for **closure** (CISD) confirmation prevents false reversals."*（Playbook）
- 收盘要穿过"造成该高低点的那一串 K 线"，而不仅是穿过那个价位本身：
  > "💡 Pro Tip: **Always use the series of candles.** Only use the single candle if there are no other opposing candles."（Using Order Blocks for Continuations）
- 影线在他的体系里承担**另一件事**（判断 C2 反转 / wick 是否成形），不承担结构确认：视频 <https://youtu.be/U1NJUh1RqMw> "Why You Need a Small Wick to Confirm a C2 Reversal"、<https://youtu.be/LKNQDAdId4s> "Master Candlestick Wicks - The Key To Catching Reversals"。

## 7. 实时性 vs 事后性

**他给的是实时规则（收盘即可判定），并且把"提前量"产品化了。**

- 实时规则：上节所有 "wait for the candle closure" 引文本身即可在收盘那一刻判定。
- 官方 Indicator 明确宣称能在收盘前给出（<https://ttrades.com/fractal-model-indicator/> 功能条目）：
  > "Auto CISD to show the shifting of trend" / "**Automatically plots CISD before candle closure**" / "**Early Trend Shift**" / "Trend Shift"
  另有专文 <https://ttrades.com/intracandle-cisd-ic-cisd-improve-your-entries/>（"Intracandle CISD (IC-CISD)"）。
  → 即：**CISD 可提前，MSS 仍需收盘**（这也是他产品里 Trend Shift 与 Early Trend Shift 分成两个开关的原因）。
- 他明确承认提前确认会带来假信号：*"CISD can give earlier entries but sometimes too early, leading to false signals"*（MSS-vs-CISD 篇）。
- 他承认参考摆动点会随行情演进而被改写（等价于承认事后看更清楚）：
  > "As price evolves, relevant swings will shift."（relevant-swings，该文有一节标题即 "Tracking Relevant Swings in Real Time"）
- 迟到一根 K 线的机械规则（Candle 2 / Candle 3 closure，<https://ttrades.com/candle-3-closure-a-complete-guide-to-identifying-continuations-and-reversals/>，视频 <https://youtu.be/MsuEQQl7L6s>）：
  > "This **delayed confirmation** still signals a reversal or continuation depending on context."
- 抗噪措施：*"Waiting one additional candle is one of the simplest and most effective filters you can use."*（why-your-continuations-fail）

**明确"结构破坏只能事后识别"这类正面自述 → 未找到一手来源（§9）。**

## 8. 跨周期的分形应用

**是，同一套结构逻辑递归适用于所有周期；权威在更高周期。**

- "This approach keeps the concept fractal. You are not limiting it to one timeframe. **You are applying the same structural logic everywhere.**"（relevant-swings）
- "This model works on any time frame. Monthly pairs with daily, daily pairs with intraday, and intraday pairs with lower intraday time frames. **The rules stay the same:** Higher time frame closure first → Lower time frame change in the state of delivery → Only then do we look for continuation."（CISD Confirms Swing Points）
- 三层职责（<https://ttrades.com/timeframe-alignment-how-to-align-higher-and-lower-time-frames-for-precision-entries/>，视频 <https://youtu.be/ubCe509_JLY>）：
  > "1. **Higher Time Frame (Bias)** – Determines market direction. 2. **Intermediate Time Frame (Structure)** – Confirms alignment with bias through change in state of delivery (CISD) and market structure. 3. **Entry Time Frame (Entry)** – Provides the opportunity for executing the trades."
- 周期配对："Weekly → 4H / Daily → 1H / 4H → 15M / 1H → 5M / 30M → 3M / 15M → 1M"；且 "**Only trade when all timeframes point in the same direction.**"
- 首选组合："Start with the daily for bias, use the 4 hour to define the swing, and execute with precision on the 15 minute chart."（<https://ttrades.com/the-best-timeframes-for-ttrades-fractal-model-simple/>，视频 <https://youtu.be/FgP2lc9nneM>）
- 反例警告："A lower time frame 'trend shift' is just a pullback into a discount or premium area on a higher time frame."（basic-market-structure）
- Candle 编号系统（Playbook）：Candle 1 = swing 点之前；**Candle 2 = swing high/low 本身**；Candle 3 = Candle 2 之后；Candle 4 = Candle 3 之后。

**权威归属**：高周期定方向（bias），中周期定结构确认，低周期只做精度。低周期的结构信号若无高周期收盘支持则被忽略——"Even if you see a clean change in the state of delivery on a lower time frame, **if there is no candle 2 or candle 3 closure on the higher time frame, it is ignored.**"

## 9. 未能证实的部分

以下每一项都是 **未找到一手来源**，并列出实际检索动作：

1. **CHoCH 的定义（Q1 后半）** — 未找到一手来源。检索：ttrades.com 全站 110 篇 REST 全文 grep（`change of character` = 0，`choch` = 0）；YouTube `@ttrades_edu` 站内搜索 `choch` / `change of character`；web_search 多组 `TTrades "change of character"` / `site:ttrades.com "change of character"` / `ttrades_edu CHoCH`；Telegram `t.me/s/learnfromttrades`。全部零命中。这更像**术语缺位**而非"有但未找到"。
2. **是否要求位移必须留下 FVG 才算 MSS/结构破坏（Q3.3）** — 未找到一手来源。检索：`understanding-fair-value-gaps`、`breaker-blocks-simplified`、`using-order-blocks-for-continuations`、`the-mmxm-traders-twitter-model-explained`、MSS-vs-CISD 篇。他只把 FVG 写成叠加加分项，从未写成必要条件；且 mmxm 序列中 FVG 位于 MSS 之前。
3. **MSS 必须突破哪一级摆动（Q4）** — 未找到一手来源。检索：`advanced-market-structure-simplified`、`relevant-swings`、`understanding-basic-market-structure`、`let-the-wick-form`。有 short/intermediate/long-term 分级与 relevant/protected swing 概念，但没有任何一句把 MSS 绑定到某个特定层级（尤其无法与 CHoCH 做层级对照，因为 CHoCH 不存在）。
4. **BOS 的正式定义及其与 MSS 的区别（Q5）** — 未找到一手来源。检索：`site:ttrades.com "break of structure"` 与 `"BOS"`；REST 全文 grep 确认 `break of structure` 全站仅 1 次且为并列提及。无 BOS 专文/专视频。
5. **"结构破坏只能事后识别"的正面自述（Q7）** — 未找到一手来源。检索：`relevant-swings`（仅承认 relevant swing 会演进）、`candle-3-closure`（"delayed confirmation"）、`fractal-model-playbook`。有"迟到一根 K 线确认"的机械规则与"摆动点会改写"的承认，但没有一句直接说"结构破坏只有事后才认得出"。

**方法学限制（非问题项，但影响证据等级）**：

- **YouTube 口语逐字稿无法获取**：timedtext 端点对该频道所有视频返回 200 但 0 字节（POT token 限制）；InnerTube `player` / `get_transcript` 返回 400；多个 Invidious/Piped 实例 403/500/502；youtubetotranscript、glasp、tactiq、notegpt、savesubs、kome.ai 全部失败。故本报告**没有一句"他口播原话"**；YouTube 证据一律限于**标题、描述、章节名**（仍是其本人发布的一手文本）。
- **PDF 讲义无正文**：各文章配发的 slide PDF 经下载 + pypdf 提取确认为**纯图片幻灯片**，仅能读到目录页文字（如 MSS 一文目录为 "Market Structure Shift / Change In State Of Delivery / Comparison / Inversion"，无 CHoCH）。
- **账号确认**：`youtube.com/oembed` 对 `E89d1HArbgM` 返回 `author_name = "TTrades"`、`author_url = https://www.youtube.com/@TTrades_edu`；官网页脚 X/YouTube 均为 `ttrades_edu`。已排除同名账号。

## 10. 来源清单

**一手 · ttrades.com 文章（作者署名 TTrades，每篇均配发同主题 YouTube 视频）**

| URL | 贡献 |
|---|---|
| <https://ttrades.com/market-structure-shifts-vs-change-in-the-state-of-delivery-a-clear-comparison/> | **核心**：MSS 定义句（位移+收盘）、CISD 定义、MSS/CISD 对照、反转次序。视频 E89d1HArbgM |
| <https://ttrades.com/understanding-basic-market-structure-in-trading/> | 位移定义句、MSS 趋势式定义、HTF/LTF 规则、"not every break of structure is a full reversal" |
| <https://ttrades.com/advanced-market-structure-simplified-from-short-term-to-long-term-trends/> | short/intermediate/long-term 摆动分级；全站唯一一次 BOS 与 MSS 并列提及 |
| <https://ttrades.com/understanding-the-change-in-state-of-delivery-cisd/> | CISD 完整定义与工作流；扫荡作为前置观察项 |
| <https://ttrades.com/how-change-in-the-state-of-delivery-cisd-confirms-swing-points/> | 收盘=确认、高质量判据、"CISD without HTF closure means nothing"、"sweep 不等于有效"、分形规则 |
| <https://ttrades.com/relevant-swings-which-swing-highs-and-lows-matter-in-trading/> | swing 点定义、failure vs relevant swing、valid separation、**高周期 3 根 K 线回看窗口**、relevance 迁移 |
| <https://ttrades.com/let-the-wick-form-trade-the-body-stop-getting-stopped-out/> | protected swing 定义、**"The sweep itself is not the confirmation."** |
| <https://ttrades.com/using-order-blocks-for-continuations/> | purge→CISD 序列、"closure through the opposing candles"、"use the series of candles"、protected swing 归属 |
| <https://ttrades.com/how-to-trade-breakouts-failure-to-manipulate/> | 收盘才确认、HTF 偏置为必要理由、failure to manipulate 与结构的关系 |
| <https://ttrades.com/the-mmxm-traders-twitter-model-explained/> | "MSS : A clear break and close beyond a key swing point"；"raid, FVG, MSS/SMT" 序列；fractal 组合 |
| <https://ttrades.com/the-easiest-draw-on-liquidity/> | draw on liquidity 具体化（前日高低）、displacement vs failure to displace、3 日回看 |
| <https://ttrades.com/timeframe-alignment-how-to-align-higher-and-lower-time-frames-for-precision-entries/> | 三层周期职责、周期配对表、"only trade when all timeframes point in the same direction" |
| <https://ttrades.com/mastering-top-down-analysis-aligning-multiple-timeframes-for-expansion-trading/> | top-down 流程、CISD 作为结构确认、HTF/LTF 分工 |
| <https://ttrades.com/the-best-timeframes-for-ttrades-fractal-model-simple/> | 首选 daily→4H→15m 组合、candle 2/3 closure 与 wick |
| <https://ttrades.com/fractal-model-playbook-aligning-daily-hourly-and-5-minute-charts/> | candle 编号系统、daily bias 规则、跨周期流水线、"waiting for closure prevents false reversals" |
| <https://ttrades.com/candle-3-closure-a-complete-guide-to-identifying-continuations-and-reversals/> | candle 3 closure 的"延迟确认"机械规则；摆动点需 POI + 有效收盘 |
| <https://ttrades.com/why-your-continuations-fail-order-blocks-cisd-explained/> | 位移速度门槛（1–3 根 K 线）、多等一根 K 线的过滤器 |
| <https://ttrades.com/breaker-blocks-simplified/> | 位移穿越 + 留下 FVG 作为**概率加分项**（非必要条件） |
| <https://ttrades.com/understanding-fair-value-gaps/> | FVG 三 K 定义、失效与 inversion（用于确认 FVG 非 MSS 必要条件）；**§11.1 的 FVG / CE 全部定义** |
| <https://ttrades.com/the-only-points-of-interest-that-actually-matter-for-trading/> | **§11.4** POI 优先级框架（FVG → swing → CISD）、"A Point of Interest Doesn't Mean an Entry" |
| <https://ttrades.com/timeframe-alignment-how-to-align-higher-and-lower-time-frames-for-precision-entries/> | **§12(B)** 三层周期栈的**命名**：Higher TF (**Bias**) / **Intermediate TF (Structure)** / Entry TF (Entry)；周期配对表 Weekly→4H、Daily→1H、4H→15M、1H→5M、30M→3M、15M→1M |
| <https://ttrades.com/internal-external-liquidity-using-the-ttrades-fractal-model/> | **§13（新收录）**：**Internal liquidity = FVG / External liquidity = swing 点**；"Internal 提供 POI、External 提供目标"；external→internal 需更强确认 |
| <https://ttrades.com/advanced-market-structure-simplified-from-short-term-to-long-term-trends/> | §4 / §4.1 / §4.2：三档定义；**intermediate 有两种类型（Basic / Rebalanced-via-FVG）** |
| <https://ttrades.com/fractal-model-indicator/> | 官方 Indicator 功能条目："Automatically plots CISD before candle closure" / "Early Trend Shift"（实时性证据） |

**一手 · YouTube（@ttrades_edu，经 oembed 确认作者为 "TTrades"）**

| URL | 贡献 |
|---|---|
| <https://youtu.be/E89d1HArbgM> | "Market Structure Shift vs Change In State Of Delivery - ICT"；描述："differences between market structure shifts (MSS) and the change in state of delivery (CISD)" |
| <https://youtu.be/CHIK5oBRKiw> | "Change In State Of Delivery [CISD] - Orderblock Formation - ICT Concepts" |
| <https://youtu.be/_94CPMjWi9E> | 标题 "Market Structure Shift - ICT Concepts" |
| <https://youtu.be/1oco9lesido> | 标题 "What is Displacement? - ICT Concepts"；描述："understand displacement during a Market Structure Shift" |
| <https://youtu.be/5rbFskdmEmU> | "Structure Shift vs Liquidity Grab"；描述："Displacement vs Lack of displacement. Break of structure vs Liquidity Grab." |
| <https://youtu.be/ynFA6E3qHj0> | "Market Structure Shift vs Liquidity Grab - ICT Concepts" |
| <https://youtu.be/yq4Z7q4E6nU> | "Trading without a Structure Shift / Break - ICT Concepts" |
| <https://youtu.be/PePk1V0Q4QQ> | 章节标记 "1:15 Market structure shift (MSS)"、"1:50 Displacement" |
| <https://youtu.be/LKNQDAdId4s> / <https://youtu.be/U1NJUh1RqMw> | 影线专题（说明影线用于 C2 反转确认，非结构确认） |
| <https://youtu.be/WwmS47Gb3M0>、<https://youtu.be/HbOeD_JVens>、<https://youtu.be/umyCqr_0NsI>、<https://youtu.be/TNybDCtwBnc>、<https://youtu.be/FgP2lc9nneM>、<https://youtu.be/ubCe509_JLY>、<https://youtu.be/vn1RYjhJUnQ>、<https://youtu.be/PQiRV0JMhIQ>、<https://youtu.be/8yt3jn8L6O4>、<https://youtu.be/MsuEQQl7L6s>、<https://youtu.be/RX8vtP3PLYk>、<https://youtu.be/IJcfC6wAPZU>、<https://youtu.be/FXJBFbZQbck>、<https://youtu.be/75S4vwD4P1U>、<https://youtu.be/ZVUDpCyvxfQ> | 各对应文章的配套视频，用于标题/描述层面的术语核对 |

**一手 · 用于证伪的检索端点**

| URL / 端点 | 贡献 |
|---|---|
| `https://ttrades.com/wp-json/wp/v2/posts`（全 110 篇正文）+ `/pages` + `/search` | 全量语料正则检索：CHoCH = 0，CISD = 5，displacement = 20，break of structure = 1 —— Q1 的否定证据 |
| <https://t.me/s/learnfromttrades> | 官方 Telegram，可见帖文中无 CHoCH / change of character |
| `https://www.youtube.com/@ttrades_edu/search?query=choch`（及 `change of character` 等 5 组） | 频道标题级检索，无命中 |
| 各文章配发的 PDF 讲义（Basic-Market-Structure-TTrades-PDF.pdf、CISD-vs-MSS-TTrades-PDF.pdf 等 5 份） | 下载后 pypdf 提取：纯图片幻灯片，无可提取正文 |
| <https://ttrades.com/?s=CHoCH> 等 | 站点搜索非服务端过滤（任何查询返回同样 110 条）→ **不可用作证据** |

**第三方（仅作交叉核对，未用于任何定义）**

| URL | 说明 |
|---|---|
| <https://summarize.ing/video-458962-Market-Structure-Shift-ICT-Concepts> | 对 _94CPMjWi9E 的 AI 生成摘要，称位移为 "aggressive moves with full-bodied candles"、并称 "A stop raid often precedes"。**AI 生成、非逐字、非一手**，本报告未采信 |
| <https://www.equiti-me.com/uae-en/news/trading-ideas/mss-vs-bos-the-ultimate-guide-to-mastering-market-structure/> | 券商教育页的通用 MSS/BOS 说法，与 TTrades 无关联，未采信 |
| <https://s3.amazonaws.com/kajabi-storefronts-production/sites/2147559353/themes/2149797900/downloads/cc8dqI2eR0GX1UakUkgT_TTF_SMC_SLIDES.pdf> | 标题疑似 TTF SMC 幻灯片，归属不明，未采信 |

---

## 11. PD Array（FVG / OB）—— 阶段 9 的一手定义

> 本节为「在指标上增加 PD Array（FVG、OB）」这一需求的取证结果，供 `Indictor/Structure.mq5` 阶段 9 实现使用。
> 配图存于 `docs/research/img/`（共 8 张，均从他的文章正文抓取）。

### 11.1 FVG（Fair Value Gap）

**定义（逐字）**——<https://ttrades.com/understanding-fair-value-gaps/>：

> "Fair value gaps (FVG) are a **three candlestick pattern** that forms when the **low of the first candle does not overlap with the high of the third candle**, or when the **high of the first candle does not overlap with the low of the third candle**."

配图 `img/FVG-3candle.png` 把三根 K 线标为 1 / 2 / 3，并在图上重复同一句：
> "the high/low of the candle(1) does not overlap the low/high of candle(3)"

**要点（决定了实现口径）**：

1. **三根 K 线**，只约束第 1 根与第 3 根；第 2 根只是"穿过"的那根，不参与边界。
2. 边界用**整根 K 线的高低（含影线）**，不是实体。配图上水平线正是画在第 1 根的低与第 3 根的高。
   → 这与 OB 的"实体优先"形成**明确对照**（见 11.2）。
3. 方向命名（他的用语）：**BISI**（Buy Side Imbalance Sell Side Inefficiency，看涨缺口）/ **SIBI**（看跌缺口）。配图 `img/FVG-SIBI.png`。
4. **不要与另外两件事混淆**（配图 `img/FVG-vs-VolumeImbalance-vs-Gap.png`）：
   - **volume imbalance**：相邻两根之间 close→open 的缺口；
   - **true gap**：根本没有成交留下的空白；
   - 二者都**不是** FVG。

**CE（consequent encroachment）= 缺口中点**——同文：

> "The midpoint of a fair value gap is called the **consequent encroachment**."

配图 `img/FVG-CE.png`（标题 "Key Levels"）把 FVG 的用法拆成**三个入场位**：

| 图上标签 | 含义 | 对应价位 |
|---|---|---|
| **IOFED** | 缺口被反向收盘穿越后反转使用（= IFVG） | 缺口近端边界 |
| **Consequent Encroachment**（图上直接标 `Entry 0.5`） | 中点入场 | `(下沿 + 上沿) / 2` |
| **FVG Fill** | 完全回补后入场 | 缺口远端边界 |

**失效与反转**：

> "As long as price does not **close beyond the consequent encroachment**, the fair value gap is generally considered respected."
> FVG 失效 = "when price **closes through the consequent encroachment** or closes fully through the fair value gap."
> 失效后的缺口可能转为 **Inversion FVG（IFVG）**：*"a failed fair value gap that then acts as support or resistance"*，且**可能在很久之后**才发生（配图 `img/FVG-Inversion.png`）。

→ **可机械化的两条状态**：① `ceBroken` = 出现收盘穿越 CE；② `filled` = 价格走完整个区间。
他说"generally considered respected"用的是 **CE**，故实现以 `ceBroken` 作为"该 FVG 已失效"的主判据。

### 11.2 OB（Order Block）

**定义（逐字，看跌情形）**——<https://ttrades.com/using-order-blocks-for-continuations/>：

> "Price runs into an important level. A **short term high** is formed. Price **raids that high**. … my eyes go to **the series of up close candles** responsible for the move. When price **closes back below those candles**, that area becomes a **validated order block**."

看涨情形镜像（配图 `img/OB-reversal-pattern.png`，标题 "Favorite Reversal Pattern"，两侧面板分别是看跌/看涨）：
图上文字为 *"Price reaches Important Level / Creates swing high / Raids swing high / Reverses and closes below the OB / OB supports price lower"*，
且 **OB 在图上被画成一条水平线**（不是框），另有一个 **"Invalidation"** 标记指向区间的另一端。

**配图 `img/OB-confirmation.png`（标题 "Continuation OB"）** 把同一件事画得更清楚：OB 是一条蓝色水平线向右延伸，**"Invalidation"** 标在该线下方（区间的另一端）。

**四条要点（同文，逐字）**：

| 引文 | 对实现的约束 | 本指标是否满足 |
|---|---|---|
| "Order blocks **only matter after liquidity is taken**." | OB 必须有前置扫荡；无扫荡的区域不算 | ❌ **未实现**（见下方 ⚠️） |
| "**Closure and displacement** are what validate the level." | 验证 = **收盘** + 位移，不是影线触及 | ⚠️ 收盘✅；位移自 v1.49-s9e 起透传（此前被丢弃） |
| "**The opening price of the candle** is often the most important reference." | **关键价位 = 造势序列最旧一根的开盘价** | ✅ 已实现，且 18/18 精确落在实体区间边界上 |
| "**Bodies matter more than wicks.**" | **区间 = 实体**，与 FVG 的影线口径相反 | ✅ 已实现 |

> ⚠️ **不要把上表第一行读成"已遵守"。** 本表是**他的要求**清单，不是达标清单 ——
> 独立审计发现此处排版容易让人误以为"OB 必须有前置扫荡"已经做到（见 `docs/plans/...` §19.6-D23）。
> 实际状态：`CheckCisd` 在**主循环内**为每次 CISD 触发派生一个 OB，**没有任何扫荡前置**；
> 且因为 `ComputeSweeps` 跑在**主循环之后**，`g_result.sweep` 在结构上**不可能**被 OB 读取 ——
> 补这个前置条件属**架构改动**，不是加一个 `if`（详见 plan §19.4-D13 与 §19.6-D22）。

另有一条直接支持"一串"而非"单根"的原话（§6 已录）：
> "💡 Pro Tip: **Always use the series of candles.** Only use the single candle if there are no other opposing candles."

### 11.3 关键发现：OB 的验证动作 = CISD

把 11.2 的第三、四条与 §1.2 的 CISD 定义并排看：

- CISD 位 = 造势那一串同向收盘 K 线中**最旧一根的开盘价**；
- OB 关键价位 = 同一串 K 线的**最旧一根开盘价**；
- CISD 触发 = **收盘穿越该位**；OB 验证 = 价格 **"closes back below those candles"**。

→ **两者是同一个动作**。故 `Structure.mq5` 的 OB 不需要独立扫描逻辑，
直接由阶段 4 已算出的 CISD 运行态派生（实现见 `AddObFromRun()`）。
差别只在于：CISD 只输出**价位**，OB 额外输出**那一串 K 线的实体区间**。

### 11.4 POI（Point of Interest）优先级框架

来源：<https://ttrades.com/the-only-points-of-interest-that-actually-matter-for-trading/>（配图 `img/POI-3types.png`）。

- 从 **protected swing** 出发，向当前区间推进，取**遇到的第一个** POI；
- 顺序：**① FVG → ② swing high/low → ③ CISD**；
- 重要限定（决定了 PD Array 的定位）：
  > "**A Point of Interest Doesn't Mean an Entry.**"

→ 即 PD Array 属**执行层参照区**，**不参与任何结构判定**。
本指标把它实现为纯可视化层（只读 `StructureResult`，不写回判定），与 SWEEP / dealing range 同级。

### 11.5 未证实 / 需标注为自定的部分

1. **"第一个 POI"的判定粒度**（按时间先后？按距离？）他未给机械规则 → 指标**不实现优先级筛选**，只把三类都画出来。
2. **OB 区间到底用实体并集还是单根实体**：原文说 "the series of up close candles"（一串），
   配图 `OB-reversal-pattern.png` 里只画了一条线（未画框）。本实现取**整串实体的并集**，
   并同时保留"关键价位"这条线所对应的价位（写进 CSV 的 `refPrice`）——这是**推断**，非他原话。
3. **FVG 的失效阈值**：他给的是两条并列条件（收盘穿 CE **或** 完全穿越），未说明二者关系。
   本实现两条都算并分别导出（`fillPct` / `state=CE-BROKEN|FILLED|OPEN`），渲染以 `ceBroken` 为准。
4. **FVG 是否应基于物理相邻三根 K 线**：原文只说 "three candlestick pattern"。
   本指标的结构分析整体跑在**剔除内包 K 线后的有效 bar 序列**上，FVG 亦沿用该口径。
   ⚠️ **这是一处需要如实说明的语义改动，不只是"加了个过滤器"**（独立审计指出，复核成立）：
   原给的理由"否则会产出大量 1-tick 级假缺口"**只支持「在物理相邻三根上加一个最小尺寸阈值」**，
   不支持"重新定义哪三根构成形态"。
   实测偏离幅度：**61/79（77%）** 是真三 K 形态，**18/79（23%）** 的 c1–c3 相隔 **3–23 根**
   （最远 23 根→14.1 pip 区间）。对这 18 个，**CE（他明文标注的 `Entry 0.5`）不是他的 CE**。
   两种误差方向相反：母线夹内包 K 时**虚增**（用到 V0 而非物理 candle 1）；
   物理三根里第 2 根是内包 K 时**漏检**（validBars 里 X、Z 相邻 → `k=1` → 直接 return）。
   正确做法应为 `c1 = c3+2`、`c2 = c3+1`（物理相邻）+ 最小尺寸阈值。
   **是否切换属语义决策，已提交用户裁定。** CSV 头 `basis=validbars` 已记录当前口径。

---

## 12. 「intermediate」在他的体系里是**两个不同的东西**（术语消歧，重要）

用户在 2026-09-23 提出一个理解：*"HTF 的结构在 LTF 上看就是中期结构线"*。
核查后：**这个理解方向对，而且有直接文本支持 —— 但它对应的是他的另一个术语。**
他文档里 "intermediate" 出现在**两处互不相通**的语境，混用会直接带偏实现：

| | **(A) intermediate-term 结构** | **(B) Intermediate Time Frame** |
|---|---|---|
| 出处 | `advanced-market-structure-simplified...` | `timeframe-alignment...` |
| 是什么 | **同一张图上**摆动点的**层级标签** | **多周期栈里的中间那张图** |
| 定义 | *"a short-term low has another short-term low to its left and right"*；另有 **Rebalanced** 变体（回补 FVG 后离开） | *"Intermediate Time Frame (**Structure**) – Confirms alignment with bias through CISD and market structure"* |
| 与 HTF 的关系 | 定义里**完全不涉及 HTF**，纯本图几何 | **它就是 HTF 与入场周期之间的那一层** |
| 是否画线 | 不画线，只在点上标 `ITH`/`ITL`（§4.1） | —（是图表选择，不是图形元素） |

**(B) 的逐字证据**——<https://ttrades.com/timeframe-alignment-how-to-align-higher-and-lower-time-frames-for-precision-entries/>：
> "My trading approach divides analysis into three key time frames:
>  1. **Higher Time Frame (Bias)** – Determines market direction.
>  2. **Intermediate Time Frame (Structure)** – Confirms alignment with bias through
>     **change in state of delivery (CISD) and market structure**.
>  3. **Entry Time Frame (Entry)** – Provides the opportunity for executing the trades."
>
> "For example, if I want a **5M entry**, I align it with **1H structure** and **daily bias**."

→ 所以"**HTF 的结构投射到 LTF 上，就是承担结构角色的那一层**"这个理解**成立**，
   他的原名叫 **Intermediate Time Frame**，且被明确指派了 **structure** 的职责。
   配图 `TFA-5.png` 给出周期配对表（Weekly→4H、Daily→1H、4H→15M、1H→5M、30M→3M、15M→1M）。

**但另一条同样明确**：在**单图 tier 词汇**里，锚定 HTF 的层级叫 **long-term**，不叫 intermediate——
> "A **long-term low** is confirmed when price **reacts from a higher timeframe level**,
>  then forms a short-term low on each side." / "Long-term structures are **anchored on higher time frame reactions**."

**结论（三句话）**：
1. 若指"多周期栈里承担结构职责的那一层" → 用户理解**成立**，他的名字是 **Intermediate Time Frame**；
2. 若指"单图上的 intermediate-term 摆动层级" → 他的定义**不含 HTF**，锚定 HTF 的是 **long-term**；
3. **不要把 (A)(B) 当成同一个概念**。（本指标的 `tier` 实现的是 (A)。）

## 13. 新一手来源：Internal / External Liquidity（此前未收录，且**高度可机械化**）

来源：<https://ttrades.com/internal-external-liquidity-using-the-ttrades-fractal-model/>（2026-08-22，视频 `vMq1l8Zzzjw`）

他的定义极为干净，几乎是直接可编码的：
> "**Internal liquidity is a fair value gap.**" / "That gap becomes internal liquidity."
> "**External liquidity is a swing high or swing low.**"
> "The relationship is straightforward: **Internal liquidity = fair value gaps / External liquidity = swing highs and lows**"
> "**Internal liquidity provides the point of interest. External liquidity provides the target.**
>  The fractal model provides the confirmation."

要点（逐字）：

- **只有反应才算数**：*"Simply having a fair value gap does not mean price has to return to it. … What matters is the reaction when price gets there."*
- **确认工具不变**：*"wait for a valid **Candle 2 or Candle 3 closure**"*
- **两个方向不对称**：internal→external 顺势方向"generally easier"；
  external→internal *"generally requires stronger confirmation because the move is trading back into the range"*。
- **LTF 模型的三件套**：*"a change in the state of delivery, a valid Candle 2 or Candle 3 closure, and a **new protected swing**"*
- **跨周期**：*"Internal and external liquidity are fractal concepts."*

⚠️ **本指标尚未实现**：我们已有 FVG（= internal）与 swing 点（= external），
但**没有把它们组织成 "internal → external" 的目标关系**。
配图（未下载）：`IRL.png`、`ERl.png`、`Relationshjip.png`、`wekk.png`、`Low-and-EQ-4.png`、`11-1D-_-1H-Fractal-Model.png`。

### 13.1 配图判别：他是怎么"画"这个关系的

六张配图已下载（`docs/research/img/ERLIRL-*.png`）。**表达方式极简**：

| 配图 | 图上有什么 |
|---|---|
| `ERLIRL-internal.png`（"What is IRL"） | 只有一条**淡黄色横向色带**从缺口处向右延伸 = IRL，**无标签无线** |
| `ERLIRL-external.png`（"What is ERL"） | 同一条色带 + **顶部一条短点线** = ERL |
| `ERLIRL-relationship.png`（"ERL & IRL Relationship"） | 色带 + 顶部短点线 + 一小段 L 形折线（标的是回撤/入场那根 K，**不是 IRL→ERL 的路径**） |
| `ERLIRL-low-and-eq.png`（视频封面） | 同上，另加两个黑框标签 **`ERL`** 与 **`IRL`** 分别指向短点线与色带 |

**关键**：**两张图都没有从 IRL 指向 ERL 的箭头**。所谓的"关系"是靠
**两个元素同时在场 + 各贴一个标签**表达的。故本指标也不画箭头（见 plan §20）。

另：**IRL 的画法与我们已有的 FVG 色带完全一致** —— 所以阶段 10 真正新增的
只有 **ERL 那一条点线**。

---

## 14. Dealing Range / Premium / Discount / EQ（一手定义）

来源：<https://ttrades.com/understanding-dealing-ranges-in-trading-get-better-risk-reward/>
（2026-09-19，视频 `yb3Te7tiGRk`，PDF `TTrades-Dealing-Ranges.pdf`）。
配图已下载：`docs/research/img/DR-*.png`（6 张）。

### 14.1 Premium / Discount / EQ —— 逐字定义

> "#### Premium, Discount, And EQ
>  **Split the dealing range at 50%.**
>  **The upper half is premium.**
>  **The lower half is discount.**
>  **EQ sits in the middle.**
>  For bullish setups, look for longs in **discount or around EQ**.
>  For bearish setups, look for shorts in **premium or around EQ**."

**配图判别**（`DR-premium-discount-eq.png`，标题 "Long in discount"）：
dealing range 被画成一个矩形，**上半区染粉红 = premium、下半区染绿 = discount**，
中间一条 50% 分界 = EQ；右侧给出 `TARGET` / `ENTRY` / `STOP` 标记 ——
该例的入场落在 **discount**，目标就是**区间上沿**。

另有一张 `DR-what-is-dealing-range.png` 是**工具设置图**：他用 TradingView 的
**Gann Box**（levels `0 / 0.382 / 0.5 / 0.618 / 1`）来画区间，
把 **0.5 以上染粉、以下染绿**（约 51% 不透明度）。即 premium/discount 是**视觉分区**，不是指标信号。

### 14.2 为什么在意位置（他的理由，逐字）

> "If you are long from **discount**, you have **more range** between your entry and the dealing range high."
> "If you are long from **premium**, you are already closer to the target."
> "The setup can still work from a poor location. The issue is **how much range is left** for the trade."

⚠️ 注意限定：**"The setup can still work from a poor location."** ——
所以 premium/discount **不是过滤器**，只是**剩余空间（风险报酬）的度量**。

### 14.3 dealing range 的**构造法**（本节最关键，且**与本实现不同**）

> "A dealing range is the range between **the swing point you are trading away from**
>  and **the higher timeframe swing you are trading toward**."
> "For a bullish range, start with the **low you are trading away from**.
>  Find the **higher timeframe swing high that made that low** and mark the range."
> "For a bearish range, start with the high you are trading away from.
>  Find the higher timeframe swing low that made that high and mark the range."
> "**Dealing ranges are fractal**… You can have a daily dealing range, an hourly dealing range,
>  and another dealing range on the 15 minute or 5 minute."
> "Multiple dealing ranges **can overlap**."

两个要点：

1. **是方向性的**（bullish range / bearish range 两套构造），不是"窗口极值连成矩形"；
2. **两端各有出处**：一端是**你正在进行情的那个 swing**，另一端是**造出它的那张高周期图上的 swing**。

### 14.4 ⚠️ 与本实现的差异（由此产生的 D31）

本指标阶段 8（plan §17）画了 `RANGE` / `EQ` / `PremiumLbl` / `DiscountLbl`，
但区间两端取的是 **`g_relHigh` / `g_relLow`** —— 即 §16 那条
「高周期回看 **3 根** K 线的极值」（来自 `relevant-swings` 一文）。

对照本节 14.3：

| | 他的 dealing range | 本实现的 `RANGE` |
|---|---|---|
| 上沿 | "the higher timeframe swing high that made that low" | 3 根 HTF K 线的最高价 |
| 下沿 | "the low you are trading away from" | 3 根 HTF K 线的最低价 |
| 方向性 | **有**（bullish / bearish 两套构造） | **无**（只是一个 min..max 矩形） |
| 用途 | 度量**剩余空间** + 目标（区间对侧沿） | 仅分区着色 |

→ 即：**PREMIUM / DISCOUNT 的分区算法（50% 对分）与他一致，但被对分的那条区间并非他的 dealing range。**
这是一处新差异，记为 **D31**（plan §21）。

另注：他的 **"The dealing range high is the target for a bullish range"** 与阶段 10 的 **ERL**
（external liquidity = 摆动高/低 = 目标）在语义上重合，但**取的位不同** ——
他的区间目标来自**高周期** swing，我们的 ERL 取的是**本图**最近的未被取走的摆动位。

---

## 15. SOP 归档补齐（2026-09-23 补录）

> ⚠️ **证据等级声明（独立核验提出，成立）**：本节是从
> `docs/sop/…-SOP.md` **回填**的 —— 当时的发现是"SOP 里有 5 处引文不在本报告中"。
> 因此**"本节包含这些引文"不能反过来证明 SOP 的引文可溯源**（自证循环）。
> 本节的作用只是**把本次会话抓到的原文记录下来**，其**独立核验见 §15.5**。

**为什么有这一节**：编写 `docs/sop/2026-09-23-TTrades-intraday-entry-SOP.md` 时做了一次
机械核验（把 SOP 里所有英文引文与本文档比对），发现**5 处引文不在本文档中** ——
它们来自本次会话新抓的文章，但当时只写进了 SOP、**没有回填到本报告**。
这是**归档不完整**，不是伪造；本节把它们补齐，使 SOP 可溯源。

### 15.1 `ttrades-ideal-formation-high-probability-swing-points`（2026-06-27，视频 `SF61vCsBl1A`）

> "An **Ideal Formation** occurs when a Candle 2 or Candle 3 closure **simultaneously creates
>  a protected swing**."
> "A protected swing is created when price **closes through the series of opposing candles**
>  that led into a high or low."
> "A valid Candle 2 closure **only becomes ideal when it also creates a protected swing**."
> "If price **closes beyond Candle 1's body but fails to close through the opposing candle
>  series**, then the protected swing has not been confirmed."
> "An Ideal Formation **should never be traded as a standalone pattern**."
> "The first is the **opening price of the opposing candle series** that created the protected
>  swing. The second is the **equilibrium (EQ) of the confirmation candle**."
> "Because both confirmations occur on the same candle, **Candle 3 often becomes the expansion
>  candle** traders look to participate in."

**形成后的两条关键位**（他明确说"要标在图上"）：① 造势反向 K 线序列的**开盘价**；
② **确认 K 线的 EQ**。第 ① 条与我们 CISD 位 / OB 关键价位同源。

**POI 清单**（他列的"重要位"枚举）：*"Fair Value Gaps (FVGs) / Liquidity sweeps /
Previous highs and lows / Premium and discount arrays / Higher timeframe points of interest"*。

### 15.2 `timeframe-alignment-…`（2026-07-30）中此前未归档的引文

> "For example, if I want a **5M entry**, I align it with **1H structure** and **daily bias**."
> "**Positional entries** are ideal if you are unsure if a retracement will occur and you
>  want to get onside"
> "With a **CISD** on the 5-minute chart and a **continuation OB**, **take entry on the close**."
> "Following the **phases of price** the expectation would be: **Expansion – Consolidation – Expansion**."
> "**Only trade when all timeframes point in the same direction.**"

⚠️ **归属更正（独立核验发现）**：*"Start with the daily for bias, use the 4 hour to define
the swing, and execute with precision on the 15 minute chart."* 此前被列在本节
（timeframe-alignment）标题下，**归属错误** —— 该句出自
<https://ttrades.com/the-best-timeframes-for-ttrades-fractal-model-simple/>（本报告 §8 的归属才对）。
独立抓取 timeframe-alignment 全文**无此句**。

止损的另一处口径（同文）：*"The stop must allow price to trade into the FVG below if its
going to form a continuation."* / *"stop below the **EQ of the 30 minute candle** as well as
below the **breaker low**"*。

### 15.3 `internal-external-liquidity-…`（2026-08-22）中此前未归档的引文

§13 已录其定义，此处补录**确认与操作层**的逐字句：

> "wait for a valid **Candle 2 or Candle 3 closure**"
> "The reaction and candle closure are **what give the move context**."
> "The goal is to identify both and then use the fractal model to determine
>  **when the relationship is actually tradable**."
> "A reversal at external liquidity needs to show that price is **actually changing direction**."
> "Once the first target is taken, **runners** can continue toward the dealing range target."

### 15.4 ✅ 已解决：那句不可溯源引文的处置

SWEEP 相关的一句 *"Price takes out yesterday's high but closes back inside the range"*
曾出现在**代码注释**（`Structure.mq5` 的 SWEEP 输入组）与 SOP 初稿中。

**独立核验（重新抓取 `the-easiest-draw-on-liquidity` 全文）确认：该句不可溯源。**
最接近的是 `how-change-in-the-state-of-delivery-cisd-confirms-swing-points` 中的
*"price **sweeps the previous candle's high or low** and then closes back inside that range"* ——
**措辞不同，不能当作同一句**（且那句讲的是 candle 2 closure 与扫荡，不是前日高低点）。

**处置（均已执行）**：
1. SOP §4 删除该句，并写明撤回理由；
2. 代码注释三处（PDH 输入组、SWEEP 输入组、SWEEP 函数头）改用**可溯源**的那句；
3. research §15.4 由"待核实"改为"已确认不可溯源"。

> **本节的方法论价值**：这是本项目第一次由**独立核验**抓出**伪造/误引**（而非靠自检）。
> 配套教训：**"在归档里找得到"不构成证据** —— 因为归档可能是从被检验对象回填的（自证循环）。

### 15.5 独立核验的其余结论（摘要）

由独立子代理**重新抓取原始 URL** 逐句比对 SOP 全部英文引文（共 60 处）：

- **50+ 处逐字或实质可溯源**；
- **1 处不可溯源**（§15.4，已处理）；
- **1 处"摘要升格为原文"**：SOP 曾把 research §11.4 的箭号式摘要
  `① FVG → ② swing high/low → ③ CISD` 加引号标为【原文】。他的顺序实为**三句散句**：
  *"The first point of interest to look for is a Fair Value Gap."* /
  *"If there isn't a Fair Value Gap, the next point of interest becomes a swing high or swing low."* /
  *"…the final point of interest becomes a change in state of delivery (CISD)."* → 已更正；
- **4 处引号内改写**（原文项目符号被换成箭号 ×2、列表符换成 `/`、截断未加省略号）→ 已照原文还原；
- **§13【空白】2 项被高估**（POI 粒度、风险/R:R）→ 已更正。**其中风险一项是实质错误**：
  Playbook 明文 *"Target **2R** minimum"* / *"Minimum target: **2R** to remain profitable
  with >34% win rate"*，**他给了盈亏比目标，只是不给仓位大小**；
- **新增来源**：`how-to-trade-london-using-ttrades-fractal-model`
  （其原文 *"The clock itself is not what makes the setup valid."* 支持"他不给时段硬规则"）。






