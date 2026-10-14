# SMC 工具箱指标 · 术语通行定义核实报告

> 目的：为 MT5「SMC 工具箱指标」确定每个术语的**可机械化判定规则**与**默认参数**。
> 方法：优先一手来源（LuxAlgo 官方 Library/官方文档、TradingView Pine 源码、开源 Pine 实现原文、ICT 教学体系整理站）。
> 重要前提：本报告对每条都区分「**有权威/流行实现依据**」与「**无权威口径，属行业约定**」。第二节之后凡标 ⚠️ 的即为后者。

---

## 结论速览表

| # | 条目 | 权威性判定 | 一句话结论 |
|---|---|---|---|
| 1 | Strong/Weak High/Low | ❌ **无权威口径** | 两套互相冲突的事业主流口径；LuxAlgo 与 ICT 术语表**都不收录**该术语 |
| 2 | EQH/EQL 容差 | ⚠️ 部分 | 无官方默认值；实现普遍用 ATR 比例（实测 0.1 / 0.25 ATR），不是固定点数 |
| 3 | OB 区间基准 | ❌ **无统一** | Full high-low 与 body 两种都在一线实现里活跃；LuxAlgo 明文承认"genuinely differ" |
| 4 | OB 缓解/失效 | ✅ 有 | Mitigation=触及；Invalidation=**收盘穿过远端**；两者是两个状态，非同一件事 |
| 5 | BOS/CHoCH | ✅ 有 | 方向状态机；CHoCH 仅在方向反转的**首次**突破；同 bar 冲突是公开实现的**真实分歧+bite 级 bug** |
| 6 | Inducement | ⚠️ 分类学分歧 | "目标区之前最近的内部回撤摆动点"；不是新算法，是**角色标签** |
| 7 | IFVG | ✅ 有（一致） | **实体收盘穿越整个缺口**（非 CE、非影线）；两家独立来源完全一致 |
| 8 | Premium/Discount | ✅ 公式有，端点无 | 公式统一：`pos=(P−low)/(high−low)`；**端点取法各家不一致** |
| 9 | Killzone | ⚠️ 两套 | 以 NY 时间为锚；LuxAlgo 与 ICTKillzone 的 Asia/NY 段**冲突 1 小时/1 小时** |
| 10 | Pivot 窗口 | ✅ 有 | LuxAlgo 50/5、Black Tie 10、Quantum 15/5；确认延迟=右窗口，你的理解正确 |

---

## 1. Strong High / Weak High（强高点/弱高点）与 Strong Low / Weak Low

> **这是你标注"最不确定"的一条，结论就是：它确实没有权威口径。**

### 一句话定义

**不存在单一定义。** "强/弱"不是 ICT 的原始术语，而是 SMC 社区对摆动点的**一个附加标注**，且社区内部用法互相矛盾。

### 依据来源（关键证据）

**证据 A — LuxAlgo 官方不收录该术语。**
LuxAlgo 官方 Library 的 SMC/ICT 分类下有 **54 个概念**（含 Buy-side Liquidity、Liquidity Sweep、Liquidity Pool、Inducement、Internal vs External Range Liquidity、Inversion FVG、Killzones、Premium & Discount、Equal Highs/lows、Order Block Anatomy 等），**名录中没有 Strong/Weak High 或 Strong/Weak Low**。
→ https://www.luxalgo.com/library/family/smc-ict/ ｜ https://www.luxalgo.com/library/concept/buy-side-liquidity/

**证据 B — 独立 ICT 术语权威站也不收录该术语。**
ICTKillzone.com（115 条 ICT 术语表，明确对齐 Huddleston 的 2022/2024 mentorship 内容）用的是 **STH/ITH/LTH 与 STL/ITL/LTL** 三档递归分级，**没有"强/弱"分级**。
- STH = 三根 K 线摆动（左右各一根更低的高点）
- ITH = 两侧都是更低 STH 的 STH（递归晋升）
- LTH = 两侧都是更低 ITH 的 ITH
- **明确声明：分级是递归的，不是按时间周期定义的**（不是"5–15M 的算 STH"），"tier = pool size = break weight"
→ https://www.ictkillzone.com/ict-swing-point-hierarchy ｜ https://www.ictkillzone.com/ict-concepts

**证据 C — 社区两套对立口径（这就是分歧的全部）。**

| 口径 | 判定轴 | 结论 | 来源 |
|---|---|---|---|
| **C-1 位移/拒绝口径** | 该摆动点是否制造了**强反向位移**；它是否"保护"了当前趋势 | 制造了强反向位移、结构在其下方/上方成立 → **Strong**；没制造出足够反向反应 → **Weak**（弱位会被回头取流动性） | [FX.co Trader Journal](https://www.fx.co/pl/trader-journals/18964648)、[writofinance](https://www.writofinance.com/strong-and-weak-high-trading/) |
| **C-2 扫荡/流动性口径** | 该高点**是否已被价格突破/扫荡** | 已被破/已被扫 → 流动性已消耗 → **Weak（不再是目标）**；尚未被触及 → 流动性仍在 → 待被取 | [TradingView "Strong Weak Highs Lows" 指标说明](https://www.htx.com.hk/vi-vi/feed/community/20715979/?comment=1) |

⚠️ **同一份 TradingView 指标说明本身就自相矛盾**：它在正文写 "Strong High … is more likely to hold / acts as potential resistance"（C-1 口径），又同时写 "Weak High … Often becomes a future liquidity target / Higher probability of being broken"（隐含 C-1），但**同一个页面又把两种直觉混用**，且没有任何机械化触发条件——这正是"该术语只在社区口语层面约定、没有可实现定义"的直接证据。

**证据 D — 公开的 SMC 指标源码里，主流做法是根本不标注强弱。**
我读到的三份实现（Quantum Algo Pine v6、Black Tie SMC、LuxAlgo Python 移植版）都**只输出 BOS/CHoCH、OB、FVG、EQH/EQL、Premium/Discount**，没有任何一份输出 strong/weak 标签。

### 判定规则（若必须实现）

既然无权威口径，只能**选定一套并明示为约定**。两套的伪代码：

```
# 口径 C-1：位移/拒绝（推荐，更可测）
strongHigh = 存在 FVG 或 BOS 由该高点向下的位移腿产生
          OR 该高点之后的反向位移幅度 >= k * ATR   # k 建议 1.0~1.5
weakHigh   = not strongHigh

# 口径 C-2：扫荡/流动性
weakHigh   = (该高点的价格已被 high 穿过)            # 流动性已取
strongHigh = (该高点的价格从未被 high 穿过)          # 流动性仍存（注意：与 C-1 完全相反）
```

⚠️ **两套口径会把同一个高点标成相反结果。** 实现上**不要二选一后掩盖**，建议输出两个独立布尔量（`swept` / `displaced`），由用户在指标参数里选"强弱语义映射"。

### 置信度

| 子问题 | 置信度 |
|---|---|
| 「LuxAlgo / 主流实现不定义该术语」 | **高** |
| 「行业存在两套对立口径且无权威仲裁」 | **高** |
| 「某一套口径是通行答案」 | **不存在** |

### 分歧点在哪里（直接回答你的提问）

你问"是**是否已被价格突破**决定，还是**是否已被扫荡/是否还有流动性**决定"——**这是两个不同的问题，而社区把它们的答案都叫"强弱"**：

- **"已被突破"** 属于 C-2 轴：突破 = 流动性被消耗 → 该摆动点**失去作为目标的资格**（此时它通常被叫作 weak high）。
- **"是否还有流动性"** 是同一个轴的另一面：**还有未被触及的流动性 = 它仍是 draw on liquidity**（通常被叫 weak high / target）。
- **C-1 轴与流动性完全无关**，只看"反向位移质量"。

所以：**"已被突破"和"已被扫荡"其实是同一轴的两种表述（不冲突）；真正冲突的是 C-1（位移质量）与 C-2（流动性状态）。** 二者不可兼得，且 LuxAlgo/ICT 官方都不裁决。

---

## 2. EQH / EQL（Equal Highs / Equal Lows）

### 一句话定义

两个或以上摆动高（低）点停在几乎相同的价格 → 该处堆积止损与突破单，构成**买方（卖方）流动性池**，是被瞄准的**目标**，不是"墙"。

### 判定规则

```
EQH: |pH[i] - pH[j]| <= tol  且  i,j 之间有有意义的回撤（不是同一次顶部）
EQL: |pL[i] - pL[j]| <= tol  且  i,j 之间有有意义的反弹

tol 的三种取法（任选，必须参数化）：
  tol = k * ATR(P)          # k 默认 0.1 ~ 0.25，ATR 周期 14
  tol = fixedPips           # 外汇 5~10 pips
  tol = pct * price         # 指数 0.1%
```

### 主流实现的默认值（实测）

| 实现 | 容差参数 | 默认值 |
|---|---|---|
| Quantum Algo Pine v6 | `Equal Level Tolerance (ATR Ratio)` | **0.25 ATR** |
| Black Tie SMC | `Equal H/L Threshold (ATR)` | **0.1 ATR**（范围 0.01–1.0） |
| LuxAlgo 官方文档（Price Action Concepts） | **未公开容差**；只公开"更长周期 EQH/EQL 的数值输入" | **3（默认）**——是**连续摆动确认数**，不是容差 |
| ICTKillzone 术语表 | 固定值 | 外汇 **5–10 pips**；指数 **0.1%** |
| LuxAlgo Library 词条 | 定性 | "a few ticks 或 ATR 的一小部分"；并强调"**画成带（band）而不是线**"、"略微上倾的 equal lows 也算" |

来源：[Black Tie SMC 源码](https://raw.githubusercontent.com/blacktiereport/black-tie-free-indicators/main/indicators/black-tie-smc.pine) ｜ [Quantum Algo 源码](https://raw.githubusercontent.com/quantumalgo-official/smart-money-concepts-indicator/main/smart-money-concepts.pine) ｜ [LuxAlgo 官方文档 Liquidity Concepts](https://docs.luxalgo.com/platform/algos/price-action-concepts/liquidity) ｜ [LuxAlgo Library: Equal Highs/lows As Liquidity](https://www.luxalgo.com/library/concept/equal-highs-lows-as-liquidity/) ｜ [ICTKillzone 术语表](https://www.ictkillzone.com/ict-concepts)

### 在体系里的作用

**流动性池 / 目标 / 扫荡对象**。三家口径一致：

- LuxAlgo：「相对等高的高点标记**待成交的买方流动性**……该水平不是支撑或阻力，而是**流动性池**」「作为目标：等高点上方未被触及的池是做多的天然止盈位」
- LuxAlgo 官方文档：「Equal high's & low's 可能预示反转，以及即将到来的 CHoCH 或 BOS」
- ICTKillzone：「零售看到双顶并预期阻力；ICT 交易者看到上方聚集的止损，算法会在反转前瞄准它」

**重要的实现细节（延迟）**：LuxAlgo 官方文档明确写「Equal high's & low's 要求检测到的 swing points 已确认，这需要与数值输入相等的 bar 数。因此必须理解**它们是回溯显示的**」。

### 置信度与分歧点

- 「EQH/EQL = 流动性池/目标」：**高**（三家一致）
- 「容差取 ATR 比例」：**中**（多家实现确实都用 ATR 比例，但**没有官方默认值**）
- 「具体数值」：**低**——⚠️ **无权威口径，属行业约定**。0.1 与 0.25 差 2.5 倍，会显著改变信号数量。
- 分歧点：固定点数 vs ATR 比例 vs 百分比；以及 LuxAlgo 官方**只暴露了"连续摆动数"而完全没暴露容差**，说明它内部容差是硬编码且未公开——**无法从官方文档得到"官方默认值"**。

---

## 3. Order Block 的区间基准：body 还是 high-low？

### 一句话定义

Order Block = **引发位移之前的最后一根反向 K 线**（多头 OB = 上涨冲量前最后一根阴线；空头 OB = 下跌冲量前最后一根阳线），读作机构建仓的足迹（旧称 "institutional candle"）。

### 判定规则

```
// 触发：一次位移腿（break of structure / 留下 FVG）
// 基数定义
bullOB: idx = 最近一根 close[idx] < open[idx]   (在 lookback 内)
bearOB: idx = 最近一根 close[idx] > open[idx]

// ★ 区间基准三选一
A) Full range : top = high[idx],  bottom = low[idx]        ← 最宽
B) Body only  : top = max(open,close)[idx], bottom = min(open,close)[idx]   ← 最紧
C) Hybrid     : 入场用 body，失效/止损用 full range 的 wick 极值
```

### LuxAlgo 的具体实现用哪个？（你点名要的答案）

⚠️ **LuxAlgo 官方没有给出唯一答案——它明文承认这属于"约定分歧"。** 三条一手证据：

1. **LuxAlgo 官方 Library「Order Block Anatomy & Refinement」词条**原文：
   > "**Anatomy and refinement is the rules layer** on top of the base definition: exactly which prices bound the zone (**the full range including wicks, or bodies only**)… **conventions genuinely differ here.**"
   >
   > 并且把三种做法都列为合法：「**wick-to-wick 是最宽的诚实区间；bodies-only 更紧但会漏掉更多触及；一种常见的混合做法是用 body 规划入场、同时保留 wick 极值作为失效位**，并把 50% 线标为 mean threshold。」
   >
   > 明确结论：「**None of this is standardized: treat the rules as filters to test, not laws.**」
   → https://www.luxalgo.com/library/concept/order-block-anatomy-and-refinement/

2. **LuxAlgo 官方 Library「Bullish/bearish Order Block」词条**给的默认标记建议是：
   > 「Draw the candle's **full high-to-low range**（or refine to the body or its 50% mean threshold），and treat a decisive close through the entire zone as invalidation.」
   → https://www.luxalgo.com/library/concept/bullish-bearish-order-block/

3. **LuxAlgo 官方文档事实上使用 "body" 一类的口径**——在其 Price Action Concepts® 的 **Liquidity Grabs** 功能里，官方说明是：
   > "Bullish liquidity grabs … borders ranging from **the price low to candle body minimum**"
   > "Bearish liquidity grabs … borders ranging from **the price high to candle body maximum**"
   → https://docs.luxalgo.com/docs/algos/price-action-concepts/liquidity

> ⚠️ 重要限定：LuxAlgo 的 **Smart Money Concepts [LuxAlgo]** TradingView 脚本是 **closed-source（受保护源码）**，无法获取其 OB 区间的逐行实现。因此上面第 3 条是**同一厂商的另一款产品**（Price Action Concepts®）的证据，**不能直接等同于 SMC 脚本**。请勿把它当作"SMC 脚本用 body"的定论。

**其他一线实现的实际做法（可读源码）**：

| 实现 | OB 区间 | 源码依据 |
|---|---|---|
| Quantum Algo SMC Engine | **Full high-low**：`obT = high[idx]; obB = low[idx]` | [源码](https://raw.githubusercontent.com/quantumalgo-official/smart-money-concepts-indicator/main/smart-money-concepts.pine) |
| Black Tie SMC | **Hybrid**：多头 `obTop = max(open,close)[idx], obBot = low[idx]`；空头镜像（**实体一侧 + 全幅一侧**） | [源码](https://raw.githubusercontent.com/blacktiereport/black-tie-free-indicators/main/indicators/black-tie-smc.pine) |
| ICTKillzone（教学口径） | **Body 为入场区，wick 为止损外沿**："Mark the zone from candle **BODY only — wicks excluded**"；「Mean threshold = **50% of the candle body**, not the full range」 | [ict-order-block](https://www.ictkillzone.com/ict-order-block) |

### 置信度与分歧点

- 「OB = 位移前最后一根反向 K 线」：**高**（三家一致）
- 「主流用 body 还是 high-low」：⚠️ **无统一答案**——**结论：两种都是主流通行做法，且混合派是第三股主流**。置信度**高**（关于"不统一"这件事本身）；**不存在**"通行的唯一基准"。
- 分歧点：① 区间宽度（full vs body）；② **多根连续反向 K 线时取哪一根**（LuxAlgo 说明"取最靠近位移起点的那根，或把整簇合并成一个区间——选一种并保持一致"）；③ mean threshold 取 body 的 50% 还是 full range 的 50%（这两者不同！）。

---

## 4. Order Block 的"缓解"与"失效"：触及即缓解，还是收盘穿越即失效？

### 一句话定义（✅ 这条有清晰答案）

**这是两个不同的生命周期状态，主流实现是"两个都实现"，不是二选一。**

| 状态 | 触发 | 语义 |
|---|---|---|
| **Mitigation（缓解）** | 价格**返回并触及**区间（`low <= OB_top` 多头 / `high >= OB_bot` 空头） | 该 OB **被使用过一次** → 降级（fresh → tested），不再是最优质 |
| **Invalidation（失效）** | 价格**收盘穿过远端**（`close < OB_bottom` 多头） | 该 OB **作废** → 多数实现改标为 **Breaker Block**（反手角色） |

### 权威依据

**LuxAlgo 官方 Library 明确把两者定义为并存的两个状态：**
> "A block is commonly called **mitigated** once price has returned and traded into it (used once, and **downgraded on later visits**), and **invalidated** once price **closes through its far side**, at which point many traders **re-label it a breaker block** rather than deleting it."

→ https://www.luxalgo.com/library/concept/order-block-anatomy-and-refinement/

**Black Tie SMC 源码**：OB 的"mitigation"是一个**可选模式**（`Close` 默认 / `Wick`），注意它的实现里 **mitigation 就等于删除**（没有 tested 中间态）：
```pine
obMitigation = input.string("Close", "OB Mitigation", options=["Close","Wick"])
bool mitigated = obMitigation == "Close" ? close < ob.bottom : low < ob.bottom
```
→ [源码](https://raw.githubusercontent.com/blacktiereport/black-tie-free-indicators/main/indicators/black-tie-smc.pine)

**Quantum Algo SMC Engine 源码**：完整三段式 `obState: 0 fresh / 1 tested / 2 mitigated`；**触及**置 1（只降级不删除），**收盘穿越**才删除（killed）：
```pine
if od == 1
    if close < box.get_bottom(ob)      // 失效：实体收盘穿过远端
        killed := true
    else if st == 0 and low <= box.get_top(ob)   // 缓解：触及
        obState.set(i, 1)
```
→ [源码](https://raw.githubusercontent.com/quantumalgo-official/smart-money-concepts-indicator/main/smart-money-concepts-indicator/../smart-money-concepts.pine)

**ICTKillzone**：同一逻辑——「wick 进入 OB 区**不算** mitigation；只有**实体收盘越过区间边界**才构成 full mitigation」「**Full body candle close through the OB** → 失效；wick 不算」。并额外给出"被测试两次后耗尽"的经验失效条件。

### 置信度与分歧点

- 「Invalidation = 实体收盘穿过远端」：**高**（三家一致，无分歧）
- 「Mitigation = 触及」：**高**
- ⚠️ **名称与语义的分歧点**：
  1. **Black Tie 把"mitigation"用作"删除"（触及即删，Wick 模式下影线也算）**，而 LuxAlgo/Quantum 把 mitigation 当"降级"。**同名不同义。**
  2. **期权的第三态命名混乱**：失效后的 OB 有人叫 **Breaker Block**（LuxAlgo/ICTKillzone），有人直接删除（Quantum）。
  3. **"两次测试即耗尽"** 是 ICTKillzone 的经验规则，**其他两家都不实现** → ⚠️ 属约定。

---

## 5. BOS 与 CHoCH 的判定、优先级与状态机

### 一句话定义

- **BOS** = 价格朝**趋势同向**突破摆动点（延续确认）。牛市中突破 swing high = BOS。
- **CHoCH** = 价格朝**趋势反向**突破摆动点（反转的**首个**警告）。牛市中跌破 swing low = CHoCH。
- 唯一判定测试：**突破方向相对当前趋势是同向还是反向**。

**权威依据**：ICTKillzone 原文「given any break of a swing point, you can determine whether it is a BOS or CHoCH by a single test: is the break in the same direction as the current trend, or against it?」并且明确 **CHoCH 用实体收盘，影线不算**（影线穿越 = liquidity sweep / Judas）。
→ https://www.ictkillzone.com/ict-choch ｜ https://www.ictkillzone.com/ict-concepts

### 主流实现的状态机（伪代码级别）

三个公开实现在**结构上完全一致**——维护一个方向状态变量，突破时用它判定：

```python
# 状态：trend ∈ {-1, 0, +1}；每个活跃摆动点有 broken 标志防止重复触发
on_bar_close():                       # ★ 只在收盘判定 → 不重绘
    if swingHigh exists and not swingHighBroken and close > swingHigh:
        isCHoCH = (trend == -1)                    # 反向 → CHoCH
        emit("CHoCH ↑" if isCHoCH else "BoS ↑")
        trend = +1
        swingHighBroken = True
        createOrderBlock(bullish=True)

    if swingLow exists and not swingLowBroken and close < swingLow:
        isCHoCH = (trend == +1)
        emit("CHoCH ↓" if isCHoCH else "BoS ↓")
        trend = -1
        swingLowBroken = True
        createOrderBlock(bullish=False)
```

等价实现（Black Tie）用 `activeHigh/activeLow + highActive/lowActive`：
```pine
bool brokeHigh = highActive and close > activeHigh and close[1] <= activeHigh and barstate.isconfirmed
bool isCHoCH = trend == BEARISH      // 空头趋势中破高点 → CHoCH
```

### 「CHoCH 是否只在首次反转时出现、之后同向突破都算 BOS？」

**是的，这是所有实现的共同语义。** 因为 `isCHoCH` 直接由 `trend` 反号判定，而 `trend` 在每次触发时被重写——所以：

- 方向从 −1 翻到 +1 的那一次 → **CHoCH**
- trend 已是 +1 时后续每次破高 → **BOS**

⚠️ **但有一个重要的边界情况必须说明**：`trend == 0`（初始未定方向）时，第一次突破在 Black Tie 里被特殊处理（`shouldDraw = ... or trend == 0`，且 `isCHoCH` 为 false）→ **首次突破被标为 BOS**。这是个**未文档化的实现选择**，不同实现可能不同。

**ICTKillzone 的额外口径（教学层，非实现层）**：CHoCH 之后**必须**等到反向的**确认 BOS** 才是入场信号（"CHoCH is a warning, not an entry"），且 CHoCH 后面常有一个 failed continuation（= inducement）。这属于**交易流程**而非指标判定规则。

### 同一个 bar 上同时满足 BOS 与 CHoCH —— 这是真正的坑

**这里是本报告最有价值的发现之一：公开实现存在真实分歧，且其中一个有个 bite 级缺口。**

**Black Tie 的实现用两个独立的 `if`（不是 `if/else`）：**
```pine
if brokeHigh
    trend := BULLISH
    highActive := false
if brokeLow                 // ★ 不是 else if
    trend := BEARISH
    lowActive := false
```
`brokeHigh` 需要 `close > activeHigh`，`brokeLow` 需要 `close < activeLow`。**同一根 K 线无法同时满足这两个条件**（除非 `activeHigh < activeLow`，即摆动点次序被破坏的畸形状态）。所以实际上**正常输入下同 bar 冲突不会发生**——但这个安全性是**隐式的、未被代码显式保证的**。

**Quantum Algo 用 `swingHighBroken` / `swingLowBroken` 双标志**，机制上同样互斥，但额外有一个"同一 bar 既破实体又算 sweep"的防护：sweep 条件写成
```pine
high > swingHigh and close < swingHigh      // 影线穿越但实体收回
```
即 **实体突破与影线扫荡在定义上互斥**，这是正确的处理。

**结论：** 主流实现靠"收盘价不可能同时高于 A 且低于 B（当 A > B）"这一**几何事实**来避免同 bar 冲突，而不是靠显式优先级。这是**隐式的、危险的**：一旦你允许 `activeHigh`/`activeLow` 因算法缺陷倒挂（例如 pivot 检测异常、跳空、或重算历史），两个分支会同时执行，`trend` 会被**后写覆盖**。

**建议（实现层）**：不要依赖隐式几何保证。**显式加 `elif` 并定义优先级**：

```python
if brokeHigh and not brokeLow:      # 明确优先级
    ...
elif brokeLow and not brokeHigh:
    ...
elif brokeHigh and brokeLow:        # 显式处理畸形/跳空：本 bar 判为"结构冲突"，不翻转趋势
    emit("STRUCTURE_CONFLICT");  return
```

- 「BOS/CHoCH 判定规则」：**高**
- 「同一 bar 的优先级」：⚠️ **无权威口径，属约定**；且**主流实现并未显式定义**，靠几何巧合。**这是你必须在自己的实现里显式决策的地方。**
- 分歧点：① `trend==0` 首次突破标 BOS 还是 CHoCH；② 是否用 `if/else`；③ 是否要求"位移"（displacement）才算 BOS（LuxAlgo 要求位移；纯 Pine 实现不要求）。

---

## 6. Inducement（IDM，诱导）

### 一句话定义

**流动性作为诱饵**：在价格与真正的目标区（OB/FVG）之间，那个**最近的、小幅的内部回撤摆动点**。交易者会在这个浅回撤处入场并把止损放在它后面 → 该处成为一个小型流动性池 → 框架预期价格在前往真正目标区的路上**先把它取掉**。别名 **engineered liquidity**。

### 判定规则

```
1. 标出目标区 Z（f_z 的 OB 或 FVG）
2. 从当前价格到 Z 之间，找第一个反向的内部回撤摆动点：
     做空方向：impulse_leg 内、价格之上的第一个 minor 内部 swing high
     做多方向：impulse_leg 内、价格之下的第一个 minor 内部 swing low
   → 该点 = 候选 IDM
3. 被"取掉"的判定（与 liquidity sweep 同一机械规则）：
     做空：high > IDM 且 close < IDM      （影线穿越+实体收回）
     做多：low  < IDM 且 close > IDM
4. 严格模型中，Z 只有在 IDM 被取掉之后才视为"有效/可交易"
```

### 与普通 internal swing 的区别

**关键结论：IDM 不是一种新的检测算法，而是一个角色标签。**

- **internal swing（内部摆动点）** = 纯几何检测产物（pivot 窗口的局部极值）。它**没有方向性角色，也没有前置条件**。
- **IDM** = 同样是那个 pivot，但被赋予"诱饵"角色。**升格条件是两个关系**：
  1. **位置关系**：它必须位于**当前价格**与**已标出的目标区 Z** 之间。
  2. **功能关系**：它必须是"最显眼的最早入场位置"——即它的后方（外侧）是自然止损聚集处。

**LuxAlgo 官方词条原文明说这是**分类学层面的分歧**：
> "Definitions vary between teaching styles… In **strict structure-mapping models**, the IDM is specific (**the most recent internal pullback before a swing extreme**), and a zone behind it, such as an order block, **isn't treated as valid until that pullback has been run**. In **looser usage**, inducement covers **any engineered trap**: a minor liquidity sweep that recruits traders in one direction before the move goes the other way."
→ https://www.luxalgo.com/library/concept/inducement/

**ICTKillzone 的对应条目**（术语表内）：「Engineered liquidity placed intentionally between current price and a real point of interest — a minor swing that tempts early entries」。

### 置信度与分歧点

- 「IDM = 目标区之前的内部回撤 = 诱饵流动性」：**高**（两家一致）
- 「IDM 与 internal swing 的关系（角色 vs 检测）」：**高**
- 「最严格口径：Z 必须先等 IDM 被取才算有效」：**中**（LuxAlgo 明说是"strict models"的做法，**不是普适规则**）⚠️
- 分歧点：**严格口径（必须是"swing extreme 之前最近的内部回撤"）vs 宽松口径（任何诱导性小扫荡）**。二者在自动化实现里会产出**不同数量**的 IDM。

---

## 7. FVG 的 IFVG（Inversion FVG）

### 一句话定义

IFVG = **一个失败的 FVG**：多头 FVG 本应作支撑，若价格**收盘穿越整个缺口**，则该区间角色翻转为阻力；空头 FVG 被穿越则翻转为支撑。**同一个区间、同样的价格，只是角色反转。**

### 判定条件：收盘穿越整个缺口，还是穿越 CE？

**✅ 明确答案：实体收盘穿越「整个缺口」（far side / 远端），不是 CE。**

两个独立来源完全一致：

**LuxAlgo 官方 Library**：
> "if price instead **closes through the entire gap**, the level inverts… The common requirement is a candle **body closing beyond the far side of the gap**; **a wick-through alone is usually read as a probe into the gap rather than a genuine inversion.**"
→ https://www.luxalgo.com/library/concept/inversion-fvg/

**ICTKillzone（含逐案判定表）**：

| 价格行为 | 结果 |
|---|---|
| 影线进入缺口后反转 | FVG 守住，仍是普通 FVG |
| **影线完全穿过**但收盘回到内侧 | FVG 守住，仍是普通 FVG |
| **实体收盘越过远端边缘** | **反转，成为 IFVG** |
| 收盘穿过后又收盘穿回 | 争夺状态，视为不可靠，跳过 |

→ https://www.ictkillzone.com/ict-fvg-vs-ifvg

⚠️ **CE（50% 中点）的真实作用**：**不是反转判定条件，而是 IFVG 成立之后的入场位**。两家都写「enter at the **consequent encroachment** of the inverted gap — the exact 50% midpoint」。

### 成为 IFVG 之后如何使用

1. **作反转确认**：与 liquidity sweep + MSS 组成"扫荡 → 位移 → 反转"链条，IFVG 是"交割状态已改变"的独立证据。
2. **首次回测入场**：在翻转后的区间 **CE** 处入场，**止损放在缺口远端之外**；若实体重新收盘穿越回来，则标记为失效（contested）。
3. **可证伪的前置要求（ICTKillzone 强调）**：应在**扫荡之前**就标出那个 FVG，而不是事后从若干已反转的缺口里挑一个——「Mark it first and you are on record」。
4. **品质过滤**：若缺口在两个方向上接连被反转又收回 → 说明失衡判读双向失效 → 空仓观望。

### 实现（来自 Quantum Algo 源码，与上述定义一致）

```pine
// st == 0 且方向为多头，实体收盘跌破缺口底沿
if st == 0 and fd == 1 and close < box.get_bottom(fb)
    fvgDir.set(i, -1)      // 方向翻转
    fvgState.set(i, 1)     // → 状态 1 = 已反转
// 反转后若再次被实体穿越回来 → killed
else if st == 1 and fd == -1 and close > box.get_top(fb)
    killed := true
```

### 置信度与分歧点

- 「判定 = 实体收盘穿越整个缺口」：**高**（两家独立来源逐字一致）
- 「CE 是入场位而非判定条件」：**高**
- ⚠️ 小分歧：LuxAlgo 说"conventions differ on strictness"，即**是否容忍"仅在极短周期上收盘穿越"**存在差异；另有实现用**收盘穿越 CE** 作为宽松版 IFVG（属少数派，**不推荐**）。置信度：**中**。

---

## 8. Premium / Discount / Equilibrium

### 一句话定义

把 dealing range（一段有意义的 leg：swing low ↔ swing high）在 **50%** 处切开：**中点 = Equilibrium**，上方 = **Premium**，下方 = **Discount**。多头只在 discount 找入场，空头只在 premium。

### 判定规则（✅ 公式统一，无分歧）

LuxAlgo 官方给出的公式：
```
R_high = 区间高点 (参考 swing high)
R_low  = 区间低点 (参考 swing low)
EQ     = (R_high + R_low) / 2
Level(f) = R_low + f * (R_high - R_low)
pos_t  = (P_t - R_low) / (R_high - R_low)

Premium   : pos_t > 0.5
Discount  : pos_t < 0.5
Equilibrium: pos_t = 0.5
```
→ https://www.luxalgo.com/library/concept/premium-and-discount/

（Quantum Algo 源码逐字一致：`pdPos := (close - swingLow) / (swingHigh - swingLow)`）

### dealing range 的两端取什么？

**这是本条唯一的分歧所在：端点取法各家不一致。**

| 实现 | 端点取法 | EQ 带 |
|---|---|---|
| LuxAlgo（语言层） | 「the swing low and high of **the most recent leg that did something meaningful**, such as **sweeping a prior low or breaking structure**」；**明确警告 "Minor swings produce random midpoints"** | 50% 精确中点；另建议保留 62–79%（OTE）带 |
| LuxAlgo（公式层） | 只写"the reference swing high/low"，**未规定如何选** | 50% |
| Black Tie SMC 源码 | `lastPivotHigh` / `lastPivotLow`（**最近一次检测到的 pivot**，未做"有意义 leg"过滤） | **EQ 带 = [0.45, 0.55]**（即 `rangeLow + 0.45Δ` ~ `0.55Δ`） |
| Quantum Algo 源码 | 当前活跃的 `swingHigh` / `swingLow`（**与结构层共用同一对摆动点**） | 50% 精确中点 + **25% / 75% 四分位带** |

→ [LuxAlgo](https://www.luxalgo.com/library/concept/premium-and-discount/) ｜ [Black Tie 源码](https://raw.githubusercontent.com/blacktiereport/black-tie-free-indicators/main/indicators/black-tie-smc.pine) ｜ [Quantum Algo 源码](https://raw.githubusercontent.com/quantumalgo-official/smart-money-concepts-indicator/main/smart-money-concepts.pine)

**是"最近一个 swing high/low"还是"高周期区间"？**
→ **两者都在用，且不是互斥的。** LuxAlgo 的教学层要求"有意义的 leg（扫过流动性或破过结构）"——这**隐含高周期**；但它在公式层把端点留作自由变量。LuxAlgo 同时说明 intraday 时 **ICT session ranges** 起同样作用（即用 Asia/London 区间的高点与低点）。Black Tie/Quantum 则机械地取"最近 pivot"。

**区间何时重锚（三家一致的精神）**：LuxAlgo 明确「a close beyond either extreme, or a new leg through major liquidity, retires it; redraw from the new swings」。

### 置信度与分歧点

- 「50% 平分、pos 公式、premium/discount 语义」：**高**（公式层面无分歧）
- 「dealing range 端点取法」：⚠️ **无权威口径，属行业约定**。置信度**低**——这是本条**唯一**的真正分歧点，且直接决定指标画出来的区间是否稳定（用 `lastPivot` 会导致区间频繁跳动）。
- 分歧点：① 端点来源（最近 pivot vs 有意义 leg vs session range）；② **EQ 是"一条线"还是"一条带"**（0.45–0.55 vs 精确 50%）；③ 是否画 62–79% OTE 带。

---

## 9. Killzone 时段

### 一句话定义

ICT 框架中预期的**机构参与高峰、可交易位移集中**的时间窗。以 **New York 时间（America/New_York，随美国 DST 切换 EST/EDT）** 为锚。

### 两套主流时段表（⚠️ 存在冲突）

**口径 A — LuxAlgo 官方 Library「Killzones」词条**（并明确声明边界差异）：

| 窗口 | NY 时间 |
|---|---|
| Asian killzone | **20:00 – 00:00** |
| London open | 02:00 – 05:00 |
| New York AM | 07:00 – **10:00**（**指数期货变体：08:30 – 11:00**） |
| London close | 10:00 – 12:00 |
| New York PM | 13:30 – 16:00 |
| Silver Bullet（三个 1 小时窗） | 03:00–04:00 / 10:00–11:00 / 14:00–15:00 |
| ICT Macros（约 20 分钟） | 例：09:50–10:10 |

并且 LuxAlgo 明说：**"Window boundaries differ by 30 to 90 minutes across ICT sources and platforms; the times above are the most widely cited set."**
→ https://www.luxalgo.com/library/concept/killzones/

**口径 B — ICTKillzone.com（对齐 2022/2024 mentorship）**：

| 窗口 | NY 时间 | 备注 |
|---|---|---|
| Asian Kill Zone | **19:00 – 22:00** | 该站另一处又把 Asian Range 写作 **20:00–00:00**（**自身也不一致**） |
| London Open | 02:00 – 05:00 | 最佳子窗 02:00–04:00 |
| New York Open ★ | **07:00 – 09:00** | 高概率首选 |
| Silver Bullet | 10:00 – 11:00 | |
| London Close | 10:00 – 12:00 | |

该站还给出了 **UTC 换算表**：

| Kill Zone | NY Time | UTC（冬/EST） | UTC（夏/EDT） |
|---|---|---|---|
| Asian | 19:00–22:00 | 00:00–03:00 | 23:00–02:00 |
| London Open | 02:00–05:00 | 07:00–10:00 | 06:00–09:00 |
| New York Open | 07:00–09:00 | 13:30–16:00 | 12:30–15:00 |
| London Close | 10:00–12:00 | 15:00–17:00 | 14:00–16:00 |

并且强调：**"Kill zone times are always expressed in New York time (EST/EDT). The times never change — what changes is how they convert to your local timezone."**
→ https://www.ictkillzone.com/ict-kill-zones ｜ https://www.ictkillzone.com/ict-concepts ｜ https://liquidityhunters.cl/en/glossary/killzone/

**口径 C — 第三方 MT5 实现**（Asia 00:00–08:00 GMT / London 07:00–16:00 GMT / NY 12:00–21:00 GMT）：这是**大session**定义，不是 killzone，且**与 ICT 的 killzone 不是一回事**，仅作对照。
→ https://tradersentiments.com/indicators/mt5/sessions/session-boxes-indicator

### 换算到 MT5 服务器时间（实现要点）

⚠️ **不要用固定的 GMT 偏移。** MT5 服务器时间常见为 **GMT+2（冬）/ GMT+3（夏）**，但**各家 broker 不同**，且切换日期与**美国 DST 不同步**（欧洲 DST 在 3 月最后一个周日/10 月最后一个周日；美国在 3 月第二个周日/11 月第一个周日）→ **每年有约 3 周的时间，NY 与 broker 的时差会偏移 1 小时**。

**稳健做法（伪代码）**：
```cpp
// MT5 侧
datetime gmt   = TimeGMT();            // 与 broker 偏移无关
int      srvOff= (int)((TimeCurrent() - gmt) / 3600);   // 服务器相对 GMT 的小时偏移（东正）

// 纽约偏移（含美国 DST 规则）：
//   3 月第二个周日 02:00 本地 → 11 月第一个周日 02:00 本地 之间 = EDT = UTC-4
//   其余 = EST = UTC-5
int nyOff  = isUSDST(TimeGMT()) ? -4 : -5;    // UTC 偏移
int delta  = srvOff - nyOff;                  // 服务器时间 - 纽约时间（小时）
// 例：srvOff=+3, nyOff=-4(夏) → delta=+7  → 服务器 07:00 才是 NY 00:00
```
**永远以 NY 时钟为准，不要以服务器时钟为准**；所有窗口边界参数化，便于用户按自己的 broker 微调。

### 置信度与分歧点

- 「以 NY 时间为锚、London 02:00–05:00、London Close 10:00–12:00」：**高**（LuxAlgo 与 ICTKillzone 一致）
- 「Asian killzone」：**低** ⚠️ —— LuxAlgo=20:00–00:00，ICTKillzone=19:00–22:00，**LuxAlgo 自己的 Pages 之间也把 Asian range 写成 8 PM–12 AM**。分歧 1–2 小时。
- 「New York killzone 终点」：**低** ⚠️ —— LuxAlgo=07:00–**10:00**，ICTKillzone=07:00–**09:00**。分歧 1 小时。
- 权威仲裁：**无**。LuxAlgo 自己声明"in sources and platforms 相差 30–90 分钟"。
- 另有 **Silver Bullet**（03:00–04:00 / 10:00–11:00 / 14:00–15:00 NY）与 **ICT Macros**（~20 分钟窗）两个更细粒度集，本次未逐条来自 ICT 一手视频，均为 LuxAlgo/ICTKillzone 二级整理 ⚠️。

---

## 10. Swing / Pivot 检测的窗口口径

### 一句话定义

主流 SMC 指标用**固定左右窗口的 fractal pivot**：`ta.pivothigh(src, left, right)` / `ta.pivotlow(...)`，`left = right = 窗口长度`。

### 各实现的默认值（实测源码/文档）

| 实现 | Swing 层 | Internal 层 | 依据 |
|---|---|---|---|
| **LuxAlgo Smart Money Concepts** | **50** | **5** | LuxAlgo 官方文档（见下） |
| **LuxAlgo Price Action Concepts（EQH/EQL）** | 官方"数值输入（默认 **3**）"——注意**该 3 既是窗口也是确认延迟** | — | [官方文档](https://docs.luxalgo.com/docs/algos/price-action-concepts/liquidity) |
| **Black Tie SMC** | **10**（`swingLength`，minval 3 / maxval 50） | 无独立 internal 层（只有一层结构） | [源码](https://raw.githubusercontent.com/blacktiereport/black-tie-free-indicators/main/indicators/black-tie-smc.pine) |
| **Quantum Algo SMC Engine** | **15**（`Swing Structure Length`） | **5**（`Internal Structure Length`） | [源码](https://raw.githubusercontent.com/quantumalgo-official/smart-money-concepts-indicator/main/smart-money-concepts.pine) |

**LuxAlgo 官方文档对 EQH/EQL 的原文（一手）**：
> "Equal high's & low's requires the detected swing points to be **confirmed**, which takes **an amount of bars equal to the value set in the numerical input**. As such it is important to understand these are **displayed retrospectively**."
> 以及 "Users can display longer term equal high's/low's by increasing the numerical input **at the right of the toggle (3 by default)**."
→ https://docs.luxalgo.com/docs/algos/price-action-concepts/liquidity

（⚠️ 限定：这段出自 **Price Action Concepts®** 文档，是 LuxAlgo 的另一款付费产品，**不等于 Smart Money Concepts 脚本**。SMC 脚本本身 closed-source。）

### 「ta.pivothigh 左右窗口相等，确认延迟等于右窗口长度」——这个理解对吗？

**✅ 正确。**

Pine 参考中的函数签名与语义：`ta.pivothigh(source, leftbars, rightbars)` / `ta.pivotlow(source, leftbars, rightbars)` 返回**枢轴所在 bar 的价格**（第 `rightbars` 根之前那根），当且仅当该点为左右窗口内的极值，否则返回 `na`。

**因此：**
- **确认延迟 = rightbars 根K线**。枢轴发生在 `bar_index - rightbars`，但只有在当前 bar 收盘、右侧 `rightbars` 根全部走完后才被返回。
- 源码里的写法印证：`swingHighBar := bar_index - sLen`（Quantum）、`lastPivotHighBar := bar_index - swingLength`（Black Tie）——**两者都用 `右窗口` 回推定位枢轴 bar**。
- **`left == right`**：三份实现全部如此（`ta.pivothigh(high, sLen, sLen)`、`ta.pivothigh(swingLength, swingLength)`）。⚠️ 这**不是 Pine 的强制要求**，而是 SMC 指标的**约定**（对称窗口 → 无前视偏好）。
- 关于**重绘**：因为返回值只在右窗口走完后出现，**历史 bar 上的枢轴一旦确认就固定**（向后不重绘）；但**实时最后一根 bar 上尚未确认**，所以判断必须放在 `barstate.isconfirmed`（Quantum 与 Black Tie 都这么做）。**这一点对你的 MT5 实现直接适用**：MT5 的 pivot 检测应基于**已收盘 bar**，相同的延迟特性。

### 与 STH/ITH/LTH 递归分级的关系（重要的概念澄清）

⚠️ **pivot 窗口 ≠ ICT 的强弱分级。** ICTKillzone 明确警告：
> "**Confusing tiers with timeframes.** The 1H chart is not 'the ITH chart' — every timeframe carries its own full ladder."
> "Beware **indicators that claim to mark 'major structure' directly — most use lookback windows rather than the recursive rule, and they disagree with the hierarchy exactly where it matters.**"
→ https://www.ictkillzone.com/ict-swing-point-hierarchy

也就是说：`swingLength=50` 是**一个窗口启发式**，不是 ICT 的 STH/ITH/LTH 定义。**如果你要做真正的 ICT 结构分级，必须实现"三根 K 线 → STH，两侧更低 STH → ITH，两侧更低 ITH → LTH"的递归晋升**，而不是放大 pivot 窗口。这是一个**高价值的实现区分点**。

### 置信度与分歧点

- 「确认延迟 = 右窗口长度；左右窗口相等」：**高**
- 「主流默认值」：⚠️ **无权威口径，属行业约定**。实测范围 **3 ~ 50**，跨度 16 倍。LuxAlgo SMC 的 50/5 是目前最可考的"流行实现默认值"，但同样**无法从官方得到源码级确认**。

---

## 11. 给实现者的建议默认值

> 原则：**能参数化的全部参数化**；对"无权威口径"的项，默认值取**最保守/最不易产生歧义**的一侧，并在 UI tooltip 里注明它是约定而非标准。

| # | 参数 | 建议默认 | 理由 |
|---|---|---|---|
| **1** | 强弱语义 | **输出两个独立布尔量** `swept` / `displaced`；UI 上提供 `strong/weak 映射` 选择，**默认 = C-2 扫荡口径**（未扫=仍为目标） | 无权威口径，两套对立。C-2 至少有**可机械判定的真值条件**（`high > level`），而 C-1 需要主观定义"强位移"。输出原始布尔量可让用户自己重映射，避免把约定伪装成标准。 |
| **2** | EQH/EQL 容差 | **`tol = 0.15 * ATR(14)`**，UI 范围 0.05–0.50，允许切换"pips/百分比"模式 | 实测 0.1（Black Tie）与 0.25（Quantum）之间；0.15 取偏严一侧，减少假 EQH。**必须有 tooltip：无官方默认值。** |
| **2b** | EQH/EQL 聚类 | 与**上一个已确认 pivot** 比较（而非窗口内聚类），画成 **band（`max/min ± tol`）而非线**；池状态 `active → swept(影线穿+实体收) / spent(实体收盘穿越)` | 与 Black Tie/Quantum 一致；band 是 LuxAlgo 明确的建议（"Draw a band, not a line"）。 |
| **3** | OB 区间 | **Hybrid（推荐）**：`entry zone = body`，`stop/invalidation = full range wick extreme`，并在图上**同时画 body 框与 wick 极值线**；提供 `Full` / `Body` 模式开关 | 三种做法都主流（LuxAlgo 明文"conventions genuinely differ"）。Hybrid 被 LuxAlgo 点名为"common hybrid"、被 ICTKillzone 当教学口径，且**信息量最大**（入场与止损不混淆）。**不要让"用哪个"成为隐藏假设。** |
| **3b** | mean threshold | **取 body 的 50%**（默认），提供 `body 50%` / `full-range 50%` 切换 | LuxAlgo 与 ICTKillzone 都指向 body 50%；但 Quantum 用 full range 50%。二者数值不同，必须显式化。 |
| **3c** | 连续反向 K 线 | **合并整簇为一个区间**（`top = max(high[i..j]), bottom = min(low[i..j])`），并在簇内标出"最靠近位移起点"的那根作为主 entry | LuxAlgo 给的两种合法做法之一，合并更稳健、不易漏触及。 |
| **4** | OB 生命周期 | **三段式状态机**：`FRESH(0) → TESTED(1) → INVALID(2)`。**触及 → TESTED（只降级，不删除）**；**实体收盘穿过远端 → INVALID，改标 Breaker**；额外可选 "测试 2 次后 EXPIRED" | 与 LuxAlgo/Quantum 一致；Black Tie 的"触及即删"会丢失 fresh/tested 的区分，信息更少。失效一律用**实体收盘**（三家一致，无分歧）。 |
| **5** | BOS/CHoCH | **方向状态机 + 显式 `elif`**：`trend ∈ {-1,0,+1}`；`close` 突破活跃摆动点 → `isCHoCH = (trend == -trendDir)`；**同一 bar 双向突破 → 判为 STRUCTURE_CONFLICT，不翻转 trend** | ✅ 判定规则有权威依据。但同 bar 优先级**无权威口径**，主流实现靠几何巧合——**必须显式写成 `elif` 并处理冲突分支**，这是本次调研中最容易踩的实现雷。 |
| **5b** | 首次突破（`trend==0`） | 标为 **BOS**（与 Black Tie 一致），但在 UI 上提供"首次标 CHoCH"开关 | 这是**未文档化的实现选择**，无权威口径。默认跟随最流行实现，但暴露开关。 |
| **5c** | 非重绘 | 所有结构判定放在**已收盘 bar**；pivot 确认延迟 = 右窗口长度 | Quantum/Black Tie 都用 `barstate.isconfirmed`；MT5 侧同理。 |
| **6** | IDM | **严格口径为默认**：`IDM = 当前价格与目标区 Z 之间最近的内部 pivot`；提供 `Z 需等 IDM 被取才有效` 开关（**默认关**）；被取判定同 liquidity sweep（影线穿+实体收） | 严格口径更可机械判定（有明确的位置关系）；"Z 必须先等 IDM 被取"LuxAlgo 明说是 strict models 的做法，不宜作为普适默认。 |
| **7** | IFVG 判定 | **实体收盘穿越远端**（`bull FVG: close < gap.bottom`）；**影线穿越永不算**；反转后 `direction` 翻转，**CE = 入场位**，失效 = 实体再次收盘穿回 | ✅ 两家独立来源逐字一致，**可直接照搬，无需开关**。另有"收盘穿越后又收回 = contested → 跳过"这条建议值得实现。 |
| **8** | Dealing range 端点 | **默认：与 swing 结构层共用同一对"当前活跃 swing high/low"**（即 Quantum 做法）；另提供 `Session range` 模式（Asia/London 区间）与 `Require meaningful leg` 过滤开关。**区间在收盘突破任一端时立即重锚** | 端点是本条**唯一**无权威口径处。与结构层共用端点可保证内部一致性、避免两套区间互相矛盾。Range 频繁跳动是 `lastPivot` 做法的固有缺点，重锚规则必须明确。 |
| **8b** | Premium/Discount 分区 | **`EQ = 精确 50%`**；`Premium: pos>0.5`；`Discount: pos<0.5`；**另画 0.25 / 0.75 四分位带**；可选显示 **62% / 70.5% / 79% OTE 带**，**OTE 锚点 = 扫荡 wick 极值 → 位移极值** | 公式无分歧（LuxAlgo 给了完整公式）。25/75 带与 OTE 带是 Quantum LuxAlgo 的常见增强；OTE 的 wick-to-wick 锚定规则来自 ICTKillzone 的明确强调（**body-to-body 会导致区间偏移**）。 |
| **9** | Killzone 集合 | **默认采用 LuxAlgo 集合**：`Asia 20:00–00:00`、`London 02:00–05:00`、`NY AM 07:00–10:00`、`London Close 10:00–12:00`、`NY PM 13:30–16:00`（NY 时间）。**全部边界可编辑**，并提供 `ICTKillzone 集合` 预设（`Asia 19:00–22:00`、`NY AM 07:00–09:00`）。另提供 `Silver Bullet`（03–04 / 10–11 / 14–15）与 `NY 指数期货变体`（08:30–11:00）预设 | LuxAlgo 自认是"most widely cited set"，且其边界差异声明让它成为最诚实的默认。**但 Asia 与 NY 终点存在 1–2 小时分歧 → 必须可编辑**。 |
| **9b** | 时区换算 | **锚定 America/New_York**，内部实现美国 DST 规则（3 月第 2 周日 ~ 11 月第 1 周日 = EDT=UTC−4，否则 EST=UTC−5）。用 `TimeGMT()` 推算服务器偏移，**不要假设服务器是 GMT+2/+3**；提供手动偏移覆盖 | broker 服务器偏移（含欧洲 DST）与美国 DST 有约 3 周的不同步窗口 → 固定偏移每年会错 1 小时。 |
| **10** | Pivot 窗口 | **Swing 层 = 15，Internal 层 = 5**（默认）；UI 范围 Swing 5–50 / Internal 2–20 | 取 Quantum 的 15/5 而非 LuxAlgo 的 50/5：**50 的确认延迟为 50 根 K 线，对日内工具箱过慢**；15 是"可考实现 + 实用延迟"的折中。**tooltip 注明：无权威默认值，3~50 均为常见。** |
| **10b** | 结构分级（可选高级功能） | 若要做**真正的 ICT 分级**，实现**递归晋升**而非放大窗口：`STH = fractal(1,1)`；`ITH = STH 且两侧存在更低的 STH`；`LTH = ITH 且两侧存在更低的 ITH`。**不要用 `swingLength` 冒充强弱分级** | ICTKillzone 明确警告"声称直接标注 major structure 的指标，多数用 lookback 窗口而非递归规则，且恰好在关键处与分级不一致"。这是让工具箱区别于普通 SMC 指标的关键能力。 |

---

## 附录：来源清单（按引用频次）

### 一手 / 官方
- LuxAlgo 官方 Library（SMC/ICT 54 概念）— https://www.luxalgo.com/library/family/smc-ict/
- LuxAlgo Library: Smart Money Concepts — https://www.luxalgo.com/library/concept/smart-money-concepts/
- LuxAlgo Library: Order Block Anatomy & Refinement — https://www.luxalgo.com/library/concept/order-block-anatomy-and-refinement/
- LuxAlgo Library: Bullish/bearish Order Block — https://www.luxalgo.com/library/concept/bullish-bearish-order-block/
- LuxAlgo Library: Equal Highs/lows As Liquidity — https://www.luxalgo.com/library/concept/equal-highs-lows-as-liquidity/
- LuxAlgo Library: Inducement — https://www.luxalgo.com/library/concept/inducement/
- LuxAlgo Library: Inversion FVG — https://www.luxalgo.com/library/concept/inversion-fvg/
- LuxAlgo Library: Killzones — https://www.luxalgo.com/library/concept/killzones/
- LuxAlgo Library: Premium & Discount — https://www.luxalgo.com/library/concept/premium-and-discount/
- LuxAlgo Library: Internal vs External Range Liquidity — https://www.luxalgo.com/library/concept/internal-vs-external-range-liquidity/
- LuxAlgo Library: Liquidity Sweep / Liquidity Pool / Buy-side Liquidity
- **LuxAlgo 官方文档（产品手册）: Liquidity Concepts** — https://docs.luxalgo.com/docs/algos/price-action-concepts/liquidity

### 开源源码（可直接读的 Pine / 移植实现）
- Quantum Algo「Smart Money Concepts Engine」Pine v6 — https://raw.githubusercontent.com/quantumalgo-official/smart-money-concepts-indicator/main/smart-money-concepts.pine
- Black Tie Report「Black Tie SMC」Pine v5 — https://raw.githubusercontent.com/blacktiereport/black-tie-free-indicators/main/indicators/black-tie-smc.pine

### ICT 教学体系整理（二级，但系统性强）
- ICTKillzone: Swing Point Hierarchy — https://www.ictkillzone.com/ict-swing-point-hierarchy
- ICTKillzone: CHoCH — https://www.ictkillzone.com/ict-choch
- ICTKillzone: Liquidity — https://www.ictkillzone.com/ict-liquidity
- ICTKillzone: Kill Zones — https://www.ictkillzone.com/ict-kill-zones
- ICTKillzone: Order Block — https://www.ictkillzone.com/ict-order-block
- ICTKillzone: FVG vs IFVG — https://www.ictkillzone.com/ict-fvg-vs-ifvg
- ICTKillzone: OTE — https://www.ictkillzone.com/ict-ote
- ICTKillzone: 115 条术语表 — https://www.ictkillzone.com/ict-concepts
- Liquidity Hunters 术语表: Killzones — https://liquidityhunters.cl/en/glossary/killzone/

### 社区口径（用于证明"无权威口径"）
- TradingView「Strong Weak Highs Lows」说明（自相矛盾）— https://www.htx.com.hk/vi-vi/feed/community/20715979/?comment=1
- FX.co Trader Journal: Strong vs Weak Highs And Lows — https://www.fx.co/pl/trader-journals/18964648
- writofinance: Mastering Strong and Weak High — https://www.writofinance.com/strong-and-weak-high-trading/
- TradingFinder: Advanced Market Structure STH/ITH/LTH — https://tradingfinder.com/education/forex/ict-advance-market-structure-sth-ith-lth-stl-itl-ltl/

### 未能获取（限制说明）
- LuxAlgo「Smart Money Concepts [LuxAlgo]」TradingView 脚本为 **closed-source**，无法取得逐行实现。
- TradingView 页面直连抓取失败（bot 拦截）；`ta.pivothigh` 语义依据 Pine 参考签名（https://www.tradingview.com/pine-script-reference/v6/#fun_ta.pivothigh ）与两份开源实现的用法交叉验证。
- Stack Overflow / ForexFactory 抓取被 403 拦截。
