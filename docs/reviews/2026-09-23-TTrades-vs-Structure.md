# TTrades 结构口径 vs `Structure.mq5` 差异清单

> 日期：2026-09-23（v2，依据调研升级后的证据修订）
> 现状代码：`Indictor/Structure.mq5`（v1.48，1813 行）
> TTrades 口径：`docs/research/2026-09-23-TTrades-structure.md`
> 　　（该调研对全站 110 篇文章做过 WordPress REST 全文正则，属**语料级**证据；
> 　　　YouTube 口语逐字稿无法获取，PDF 讲义为纯图片，两处限制已在其 §9 记录）
> **本文只做差异分析，未改任何代码。**
>
> v2 相对 v1 的实质修订：**D5 结论反转**（扫荡不是前置条件）、**D8 升级为"硬门禁"**、
> D6/D11 补充语料级证据、新增 D13（摆动点分级）。

---

## 0. 一句话结论

**指标里那个"逆势破位"事件，在 TTrades 的框架里既不是 MSS、也不是 CISD —— 它最接近 ICT 的
CHoCH，而 TTrades 本人根本不用 CHoCH 这个词。**

CHoCH 的缺位现在是**语料级否定**，不是"我没搜到"：全站 110 篇文章正文正则，
`change of character` 命中 **0**、`\bchoch\b` 命中 **0**；同语料对照 `CISD` 命中 5、
`displacement` 命中 20（证明检索有效）。他的对照对是 **MSS vs CISD**。

而且缺的不止命名：

- 他的 **MSS** 要求 *"displaces and closes above or below a swing high or swing low"* ——
  现有事件**默认连收盘都不要求**（影线触及即算）；
- 他真正用来确认的是 **CISD**（收盘穿越"造势那一串 K 线的开盘价"）—— 指标里**完全没有**；
- 更要紧的是：**他的模型有一道高周期门禁**（见 D8），指标是完全单周期的。

---

## 1. 现状：指标实际在算什么（已核实）

### 1.1 两个参考点（RefPoint）

| 字段 | ST_UP 时含义 | ST_DOWN 时含义 |
|---|---|---|
| `refHigh` | 趋势内最高高点（HH；仅在更高或已破时更新） | 最近反弹高点（LH） |
| `refLow` | 最近回落低点（HL） | 趋势内最低低点（LL；仅在更低或已破时更新） |

即「当前趋势下受保护的两个摆动位」——**这正是他说的 protected swing 的语义**（用词不同）。
`broken` 标志防同一位重复触发；`UpdateRefsFromSwing()` 在新主结构 swing 确认时重置 `broken`。

### 1.2 唯一触发源：每根 bar 的 `CheckBreakAgainstRefs()`

```mql5
ST_UP   : 上破 refHigh → AddBOSResult(dir=UP)      // 顺势
          下破 refLow  → AddMSSResult(dir=DOWN)    // 逆势 + 立即切向
ST_DOWN : 下破 refLow  → AddBOSResult(dir=DOWN)    // 顺势
          上破 refHigh → AddMSSResult(dir=UP)      // 逆势 + 立即切向
```

**关键结论**：事件类型**完全由"突破方向 vs 当前趋势方向"决定** —— 顺势 → `BOS`，
逆势 → `MSS`。这是"延续 vs 反转"的区分，不是"MSS vs CHoCH"的区分。
真实运行日志验证（`bind=OK` 表示 ref 绑定正确）：

```
MSS event: type=MSS dir=DOWN breakBar=188 refBar=190 refPrice=1.06638 trend=UP    ← 逆势
BOS event: type=BOS dir=DOWN breakBar=179 refBar=185 refPrice=1.06293 trend=DOWN  ← 顺势
MSS event: type=MSS dir=UP   breakBar=159 refBar=161 refPrice=1.06444 trend=DOWN  ← 逆势
BOS event: type=BOS dir=UP   breakBar=136 refBar=159 refPrice=1.06532 trend=UP    ← 顺势
MSS event: type=MSS dir=DOWN breakBar=127 refBar=130 refPrice=1.06494 trend=UP    ← 逆势
BOS event: type=BOS dir=DOWN breakBar=124 refBar=127 refPrice=1.06466 trend=DOWN  ← 顺势
```

（`CONTEXT.md` L27-28 与 `BOSMSS_FIX_SPEC.md` §三/§八 的表述与代码一致：
"逆势打破前一个 swing 极值 → 结构反转"、"BOS/MSS 命名一律按当前趋势状态判断"。）

### 1.3 逆势破位（现 `MSS`）发生后的立即动作

```mql5
AddMSSResult(i, DIR_DOWN, st.refLow, st.state);
st.refLow.broken = true;
st.state         = ST_DOWN;      // ← 立刻切向
st.refHigh.valid = false;        // ← 立刻作废对侧参考点
```

**一次逆势破位 = 趋势已反转**，没有中间态、没有二次确认、没有等待。

### 1.4 确认口径

```mql5
bool CloseConfirm() { return (InpCloseConfirm || InpMode == MODE_STRICT_ICT); }
```

默认 `InpMode = MODE_SHORT_TERM`、`InpCloseConfirm = false` → **影线/触及即确认**；
比较符是 `>` / `<`（**不是** `>=`）；除该开关外**没有任何强度判据**。

### 1.5 参考摆动点如何取得

- 只在**主结构** swing 上更新 ref：`isMainSwing` = 腿长 ≥ `InpMainFilterATR`(=1.0)×ATR
  **或** ≥ `InpMainFilterRatio`(=0.382)×前一段幅度；
- swing 三点判定（L985-986）：`high[i] > high[prevBar] && high[i] >= high[nextBar]`
  （**左严格、右非严格**）；
- 另有 `InpMinBarsBetweenSwings`、`InpMinRetracePoints`/`ATR`/`Ratio`、`InpMinSwingAmplitude`。
- **摆动点无分级**：全部 swing 一视同仁，只有 `isMain` 一个布尔区分。

### 1.6 分析/绘制窗口

`InpAnalysisWindow`(默认 500)：参与状态机的 bar 数，**同周期**计数；
`InpWindow`(默认 200)：绘制窗口，**同周期**计数。**两者都与"高周期"无关。**

### 1.7 同时双破（外包 bar）的裁决

按该 bar 阴阳决定保留哪个事件（`close[i] >= open[i]` 保留上破）。自创规则。

### 1.8 内包 K 线被整体排除在突破检测之外

`validBars` 构建时（L921）内包 bar 被 `continue` 跳过，**不进入 `CheckBreakAgainstRefs`**。

### 1.9 `InpNeedRetestToShow` 的真实作用（易误解）

它**只在渲染层**决定标注画不画：在事件之后（bar 从 `b-1` 往回 50 根）找有无重新穿越。
**不改状态机、不改事件记录、不参与切向**，方向是"事后回踩"而非"事前确认"。

### 1.10 不向外发布任何数据

`indicator_buffers 0`、无 `GlobalVariableSet` / `EventChartCustom` / `SetIndexBuffer` /
`iCustom` 输出，只有 `IndicatorSetString(INDICATOR_SHORTNAME, ...)`。
**唯一的对外可观察接口是图上对象名**（且对象 `OBJPROP_HIDDEN=true`）。

---

## 2. TTrades 口径要点（引原文，完整出处见调研文档）

| 概念 | 他的定义（原文要点） |
|---|---|
| **Swing point** | "a candle prints a low and there is a **higher low to its left and a higher low to its right**"（高点对称）—— **左右两侧都严格** |
| **摆动点分级** | short-term（两侧各一个更高低/更低高）→ intermediate-term（由短周期点构成）→ long-term（高周期反应后两侧形成短周期点）；*"MSS and BOS are clearer once you know the hierarchy"* |
| **relevant vs failure swing** | failure swing = "forms **too close to a prior high or low** and **lacks proper range separation**" → 忽略；relevant = "**the extreme of the move within the current context**" |
| **relevance 窗口** | "look back **three higher timeframe candles including the current one**"（日线看三月线、小时看三日线） |
| **MSS** | "happens when price **displaces and closes** above or below a swing high or swing low"；"marks a trend change **confirmed by displacement**" |
| **CISD** | "focuses on **the opening price in the series of up-close or down-close candles**. When price displaces and **closes beyond that open**, it validates the level as an order block"；"Price forms a series of up-close candles, then **closes below the opening price of those candles**" |
| **CISD 的取数纪律** | "**Always use the series of candles.** Only use the single candle if there are no other opposing candles." |
| **MSS vs CISD 时序** | "CISD often appears **earlier** than MSS"；次序 "1. Inversion or CISD shows early order flow weakness. 2. **MSS confirms the structural shift**. 3. Price retraces into a premium or discount zone" |
| **displacement** | "**strong price movement with momentum** that breaks prior structure"；质量："clean V-shaped reversal" / "decisive close through structure" / "minimal sideways consolidation"；速度："The best setups form **within one to three candles** and show immediate displacement" |
| **位移失败 = 反向信号** | "Failure to displace above previous day high suggests a bearish bias toward previous day low" |
| **FVG 是否必需** | **不必需**。他只把 FVG 写成叠加加分项："When displacement occurs… **leaving behind a fair value gap**, the probability of price reacting to that zone **increases**" |
| **扫荡是否前置** | **不是硬前置**。"The close through that series of candles is what confirms the shift. **The sweep itself is not the confirmation.**" 他另有专视频把 MSS 与 liquidity grab 拆开。CISD 工作流里扫荡仅为第 1 步**观察项**："A liquidity sweep has likely taken place above a high or below a low." |
| **高周期偏置** | **硬门禁**。"The higher timeframe provides the bias and the lower timeframe provides the structure confirmation." / "Without that higher timeframe reason, you are just blindly trading breakouts." / "If there is no candle 2 or candle 3 closure on the higher time frame, **it is ignored**." |
| **protected swing** | "forms when price reaches an important level and then **closes through the series of candles into that level**" |
| **确认** | 一律 **closure**："If the candle cannot close through the level you need, the reversal is not confirmed."；"Without it, price has not been confirmed." |
| **跨周期** | 三层职责：HTF(bias) / ITF(structure) / Entry；配对 Weekly→4H、Daily→1H、4H→15M、1H→5M；"**Only trade when all timeframes point in the same direction**" |
| **CHoCH** | **语料级零命中**（110 篇全文正则） |
| **BOS** | `break of structure` 全站**仅出现 1 次**且为并列提及；无定义专文。相关句："**Not every break of structure is a full reversal.**" |

---

## 3. 差异清单

按影响从大到小排列。**「现状」列是代码事实，「他」列是他原文。**

### D1 — 术语与语义双重错位（严重）

| | |
|---|---|
| 现状 | 逆势破位 → 标注 `MSS`（图上现已改为 `ChoCh`） |
| 他 | **MSS** = 位移 + **收盘** 越过 swing 位；**CISD** 才是提前的订单流信号；**CHoCH 无此词**（语料级 0 命中） |
| 差异 | 现状事件**既非**他的 MSS（缺收盘+位移），**也非** CISD（不看向向收盘 K 线开盘价） |
| 后果 | 图上一个"逆势破位"标注，在他那套读法里没有明确对应物 |

### D2 — 缺"收盘"确认（严重，但**现成可对齐**）

| | |
|---|---|
| 现状 | 默认 `InpCloseConfirm=false` → 影线/触及即确认 |
| 他 | 一律 closure："**If the candle cannot close through the level you need, the reversal is not confirmed.**" |
| 影响 | 现有默认口径下，**相当一部分"破位"按他的标准根本不成立** |
| 备注 | 指标已内置开关：`InpCloseConfirm=true` 或 `InpMode=MODE_STRICT_ICT`。**这是唯一一项不需要写新算法的对齐点** |

### D3 — 位移（displacement）判据缺失（严重）

| | |
|---|---|
| 现状 | 全文件 `displac`/`FVG`/`imbalance` **零命中** |
| 他 | "strong price movement with momentum that breaks prior structure"；"confirmed by displacement"；且**有时效**："The best setups form within one to three candles" |
| 影响 | 无法区分"小实体勉强收在结构外"与"大实体位移破位" —— 而这是他判断真假的核心 |
| 备注 | **FVG 不是必要条件**（他仅作加分项），所以不必为实现位移去引入 FVG 检测；数据上 `atrArr[]` + `open/close` 已够 |

### D4 — 缺 CISD 这一类事件（严重，属功能缺口）

| | |
|---|---|
| 现状 | 无 CISD |
| 他 | 实操模型里**确认动作由 CISD 承担**："If CISD is missing, I ignore the setup completely"；且有专文专视频讲它 |
| 影响 | 若目标是"按他的模型"，**CISD 比 MSS 更该先有** —— 他的入场链是 `CISD → 回调到 POI → 进场` |
| 关键规则 | 取数纪律："**Always use the series of candles.** Only use the single candle if there are no other opposing candles." |
| ✅ 歧义已由配图解决 | "closes below the **opening price of those candles**"（复数）未写死取哪一根。配图 `docs/research/img/CISD-2026-01.png` 显示 CISD 线画在**造势序列最旧那根的开盘价**（明显远离极值、贴近造势起点），**否证**"取紧邻极值那根"的读法。实现取最旧那根，与图一致 |

### D5 — 流动性扫荡**不是**前置条件（**v1 结论已推翻**）

| | |
|---|---|
| 现状 | 无 sweep 概念 |
| 他 | **明确分开**："The sweep itself is not the confirmation."；并有专视频《Structure Shift vs Liquidity Grab》《Market Structure Shift vs Liquidity Grab》 |
| 修正 | v1 本文把 sweep 写成"前置之一"是**过度解读**。扫荡出现在他的**典型序列**里（"As long as you respect the same sequence — **raid, FVG, MSS/SMT**"），但被写成样例而非必要条件；在 CISD 工作流里是第 1 步**观察项** |
| 影响 | **不应**把"先扫荡"做成 MSS 的硬门槛。sweep 标记的价值降为"可视化上下文"，不是判定条件 |
| 另一条 | 他同时说 "A swing point is **not valid simply because liquidity is swept**" |

### D6 — 参考 swing 的选取口径不同（中等）

| | |
|---|---|
| 现状 | 主结构过滤（腿长 ≥1.0×ATR 或 ≥0.382×前段）+ 同类型只保留更极端者；窗口 = `InpAnalysisWindow`(500 根**同周期**) |
| 他 | relevant swing = 当前语境极值 + valid separation；**failure swing 要剔除**（"too close to a prior high or low"、"lacks proper range separation"）；且 relevance 由**3 根高周期 K 线（含当前）**界定。**更关键**：驱动 protected swing 的不是幅度门槛而是**结构层级** —— *"Intermediate-term highs/lows confirm stronger pivots and sweeps (**protected swings**)."* |
| 差异 | ①"极端性"判据不同（ATR/比例 vs 结构分离度）；②窗口**维度**不同（同周期 bar 数 vs 高周期 K 线数） |
| 备注 | 他**明说 separation 无数值公式**（"There is no strict numerical formula… If it is too close, expect it to be taken."），故只能自定近似 |

### D7 — swing 三点判定不对称（轻微但具体）

| | |
|---|---|
| 现状 | `high[i] > high[prev] && high[i] >= high[next]` —— **左严格、右非严格** |
| 他 | 两侧都要"更低的高"—— **左右皆严格** |
| 差异 | 平台/等高点处，指标会确认一个他不认的 swing 点 |
| 备注 | 一字符级改动，但会改变节点数量与全部下游事件，属**行为变更** |

### D8 — 缺高周期门禁（**严重，v2 升级**）

| | |
|---|---|
| 现状 | 单周期、单层状态机；无 HTF 概念。`InpAnalysisWindow` 只是同周期 bar 数 |
| 他 | **硬门禁 + 权威归属**："The higher timeframe provides the bias and the lower timeframe provides the structure confirmation."；"Without that higher timeframe reason, you are just blindly trading breakouts."；"Even if you see a clean CISD on a lower time frame, **if there is no candle 2 or candle 3 closure on the higher time frame, it is ignored.**" |
| 关键推论 | "**A lower time frame 'trend shift' is just a pullback into a discount or premium area on a higher time frame.**" —— 即：**现指标单周期标出的"逆势破位"，在他的框架里大部分只是高周期的回调**，不是结构转换 |
| 影响 | 这是**保真度天花板**：缺 HTF 层时，无论结构基元做得多准，事件集合仍会明显多于他会交易的集合 |
| 可机械化内容 | 三层职责（HTF bias / ITF structure / Entry）、配对标（Daily→1H、4H→15M、1H→5M…）、"Only trade when all timeframes point in the same direction"、前日/前周高低温、candle 2/3 closure（"price sweeps the previous candle's high or low and then closes back inside that range"） |

### D9 — 内包 K 线上的突破不被检测（轻微，但与 D2 叠加后放大）

| | |
|---|---|
| 现状 | `validBars` 排除内包 bar（L921）→ 这些 bar 不进入突破检测。**影线口径下影响很小**（内包 bar 的 high/low 不超过母线，母体会先破）；但**内包 bar 的收盘仍可越位** |
| 他 | 无"内包"概念；任何**收盘**越位都算 |
| 差异 | **与 D2 叠加后才显现**：一旦改用收盘确认，这个排除会导致真实破位被漏掉 |

### D10 — 外包 bar 的阴阳裁决是自创规则（轻微）

现状按 `close>=open` 决定保留哪个事件；他处未找到对应说法。因它直接决定"标 BOS 还是 MSS"，
会污染事件统计。

### D11 — BOS 缺少对标口径（轻微，v2 补充证据）

| | |
|---|---|
| 现状 | 顺势破位 → 标注 `BOS` |
| 他 | `break of structure` 全站 110 篇**仅出现 1 次**，且是并列提及（"MSS and BOS are clearer once you know the hierarchy"）；无定义专文/专视频 |
| 相关线索 | "**Not every break of structure is a full reversal.**"（→ 他笔下 BOS 更像"任意越过结构位"的中性描述，而 MSS 是被位移确认的趋势级破坏。**此区分是推断，非原话**） |
| 差异 | `BOS` 这一支缺少可对标的一手定义，无法判断是否与他的理解一致 |

### D12 — 事件之后的"回调到折价区"没有体现（轻微）

现状 `InpLineEnd` 有 `LINE_END_FIRST_RETEST`（首次回踩即停），但那是**画线终点**；
他序列第三步是"Price retraces into a **premium or discount zone**, giving the best entry"。
属入场逻辑，可能本就不在指标职责内。

### D13 — 摆动点无分级（中等，v2 新增）

| | |
|---|---|
| 现状 | 全部 swing 一视同仁，只有 `isMain` 一个布尔 |
| 他 | 三级：**short-term**（两侧各一个更高低/更低高）→ **intermediate-term**（由短周期点构成）→ **long-term**（高周期反应后两侧形成短周期点）；并给出用法："Look for **short-term** highs/lows to confirm shifts. Use **intermediate-term** sweeps as confirmation of continuation or reversal." |
| 差异 | 指标缺"这一级是短/中/长"的标签，因而无法表达"用短周期确认转换、用中周期确认延续"，也无法按他的口径挑选 protected swing |
| ✅ 歧义已解决 | 文字定义未说邻居是否要更极端，但配图 `ITM.png` 给出反证：图中 `STH(2)` 左右各有 short-term high，却标 `STH` 而非 `ITH` → **字面读法被否证**。定义为：intermediate = 比左右**最近的同类型** short-term 点都更极端（节点强制交替，故即 `nodes[n±2]`） |
| 另注 | intermediate 结构分两类：Basic（由 short-term 摆动构成）与 Rebalanced（*"formed when price rebalances a fair value gap and trades away"* → **需要 FVG 检测**，超出 L1–L3 范围） |
| 备注 | 他的分级定义是**递归可机械化**的，实现代价不高 |

---

## 4. 影响面评估

| 维度 | 结论 |
|---|---|
| 下游程序消费者 | **无**。`indicator_buffers 0`、无全局变量/自定义事件/缓冲区，`EA/AutoSLTP.mq5` 与结构无关 |
| 对已保存图表设置 | 改**语义**不影响；只有改**输入参数名**才会让已存设置回落默认值 |
| 对 `TradingVue/TradFi_Structure.mine` | 用 `bar_index` 差值 + 滚动状态机，**不含** `analysisStart` 那套绝对下标；语义改动需**单独同步** |
| 对文档 | `CONTEXT.md`(34)、`BOSMSS_FIX_SPEC.md`(33)、`README.md`(10)、`docs/adr/0001-*` 都编码了"逆势=MSS"口径，需同步；`docs/reviews/*` 与 ADR 属历史记录，保留原文 |

---

## 5. 保真度分层（**这是本轮的决策核心**）

对齐有**天花板**，取决于做到哪一层。按他的门禁强度排：

| 层 | 内容 | 缺了它会怎样 |
|---|---|---|
| **L1 结构基元** | swing 左右皆严格、relevant vs failure、3 根高周期 K 线窗口、摆动点分级 | 结构点本身的定义就与他不一致 |
| **L2 确认口径** | 收盘确认、位移判据、（内包 K 线也参与检测） | 大量"破位"按他标准不成立 |
| **L3 事件补全** | CISD、MSS（位移确认后） | 他真正用的确认工具缺失 |
| **L4 高周期门禁** | HTF 偏置（前日/前周高低、candle 2/3 closure）、三层职责、"所有周期同向" | **事件集合仍会明显多于他会交易的集合**（D8 的推论） |
| **L5 上下文可视化** | dealing range / EQ、premium-discount、POI(FVG/OB) 画图、sweep 标记 | 只影响可读性，不影响判定 |
| **L6 执行** | 下单、止损放 protected swing、目标 2R+/流动性池 | 属 EA 职责，不属指标 |

**关键判断**：只做 L1–L3（= 你选的 B2）能把"指标算出来的东西"与他的定义对齐，
但**无法对齐"他会看哪些信号"** —— 因为 L4 是硬门禁。这一点必须明确记录，
不能对外宣称"已与 TTrades 对齐"。

> 如果他的一手文章确实把 HTF 写成硬门禁，那么"完全对齐"在指标形态下**不可达** ——
> 指标只能输出未经 HTF 过滤的候选信号。要么接受这个天花板并如实标注，
> 要么把 L4 纳入范围（改动量最大的一层）。
