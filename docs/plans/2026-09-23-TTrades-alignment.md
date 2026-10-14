# 计划：把 `Structure.mq5` 与 TTrades 口径对齐

> 日期：2026-09-23（v2，依据调研升级后的证据修订）
> 依据：`docs/research/2026-09-23-TTrades-structure.md`（语料级一手证据）
> 　　　`docs/reviews/2026-09-23-TTrades-vs-Structure.md`（差异 D1–D13 + 保真度分层 L1–L6）
> 状态：**计划已列，代码未改。** §1 有一个新决策未定（HTF 门禁），影响阶段编排。

---

## 0. 对齐的目标形态

TTrades 的模型是一条**带门禁的漏斗**：

```
L4  HTF（日线）  一次性偏置：前日高/低 + swing 点处 reversal closure（candle 2 / candle 3）
      ↓           ← 硬门禁："if there is no candle 2 or candle 3 closure on the higher
      ↓              time frame, it is ignored."
L2  LTF          CISD 确认（收盘穿越"造势那一串同向 K 线的开盘价"）
      ↓           ← 位移是必要条件；收盘是必要条件；扫荡**不是**
L5  POI          回撤到 FVG / OB，落在前日区间上半/下半（premium / discount）
      ↓
L6  执行          止损放 protected swing，目标 HTF 流动性池 / 2R+
```

### 一个必须写明的天花板

他的文章把 **HTF 偏置写成硬门禁**，并且明确说：
*"A lower time frame 'trend shift' is just a pullback into a discount or premium area on a
higher time frame."*

**推论：本指标单周期标出的"逆势破位"，在他的框架里大部分只是高周期的回调。**

因此在**只做 L1–L3**（= 当前选的 B2）的前提下：

> 能把"指标算出来的东西"与他的定义对齐，
> **但无法对齐"他会看哪些信号"** —— 事件集合仍会明显多于他会交易的集合。

这个天花板要么接受并在文档/图上如实标注，要么把 L4 纳入范围。**这是 §1 决策 D。**

---

## 1. 动手前必须定的决策

### 决策 A（已定，**v3 修订**）：去掉 `ChoCh`，收口为纯 TTrades 命名

初版选的是 A1（保留 `ChoCh` + 新增 `MSS`）。在"CHoCH 缺位是**语料级否定**"这一更强的
证据下（全站 110 篇正文正则 `change of character` = 0、`\bchoch\b` = 0，而同语料
`CISD` = 5、`displacement` = 20），你已改选**纯 TTrades**：

> 只留 **CISD**（早期信号）+ **MSS**（位移确认的结构转换），**放弃 CHoCH 这个词**。

两条后果，在**阶段 3 收口**：

1. 我早先那次 `MSS → ChoCh` 的改名产物（L1599/L1601/L473/L297/L140/L145/L158/L113/L95）
   **要撤销并替换**；
2. 逆势破位但**未过位移门槛**时，他的一手语汇里**没有对应词**（他的早期信号是 CISD，
   不是"弱结构破位"）→ 该情形默认**不单独给文字标签**，只以弱化样式画线，
   以免再造一个他不存在的术语。**此点仍待你确认**（见 §6）。

### 决策 B（已定，但见决策 D）：范围 B2 = L1–L3

### 决策 C（已定）：加事件导出 CSV 作客观验收

### 决策 D（**新，未定**）：要不要把 L4（HTF 门禁）纳入？

| 选项 | 含义 | 改动量 | 后果 |
|---|---|---|---|
| **D1（推荐）** | 本轮做 L1–L3，**并在图上/文档标注"未过 HTF 门禁"** | 中 | 诚实、快；事件数会多于他会交易的数量，但每个事件的定义与他一致 |
| D2 | 本轮直接做 L1–L4 | 大 | 事件集合才真正接近"他会看的"；但需提前引入多周期取数层 |
| D3 | 先 L1–L3，L4 留作下一轮 | 中 | 与 D1 同效，只是不承诺何时补 L4 |

**我倾向 D1 或 D2。** 若你在意"标出来的信号就是他会看的信号"，必须选 D2 —— 因为
D8 的推论说明 L4 不是可选的润色，而是决定信号集合的门禁。

---

## 2. 分阶段计划

每阶段验收流程：`编译(0/0) → 部署 → 你重挂一次 → 我读日志 + 导出 events → 与上一版逐行 diff`。

### 阶段 0：基线 + 验收工具（不改判定逻辑）

| 项 | 内容 |
|---|---|
| 改动 | ① 新增 `InpDumpEvents`，把全部事件写成 CSV 到 `MQL5\Files\`（默认关）；② 固定基线参数，导出改前的一版 events 存档 |
| CSV 字段 | 预留扩展：`type, dir, breakBar, refBar, refPrice, breakTime, level, displacement, tier, biasState` —— 后续阶段加列不破坏旧档可比性 |
| 验收 | 同一图表/参数/数据下可重复生成且内容稳定 |
| 风险 | 无。`FileWrite` 到 `MQL5\Files`，不触碰绘制路径 |
| 量 | S |

### 阶段 1：结构基元对齐（地基，先做）

| 项 | 内容 |
|---|---|
| 差异项 | **D7** swing 对称性；**D6** relevant/failure swing + 3 根高周期 K 线窗口；**D13** 摆动点分级 |
| 改动 ①（D7） | `high[i] > high[prev] && high[i] >= high[next]` → **左右皆严格**。一字符级，但会改变所有下游事件 |
| 改动 ②（D6a） | 新增 **failure swing 剔除**：swing 若与更早的同向 swing 过于接近（缺 separation）则不算结构点。他**明说无数值标准** → 自定近似并做成参数，默认保守（尽量少剔） |
| 改动 ③（D6b） | 新增 **relevance 窗口**：`CopyHigh/CopyLow(symbol, InpHTFPeriod, 0, 3, arr)` 取"当前 HTF 的 3 根 K 线（含当前）"高低点。**与 `InpAnalysisWindow` 用途不同**：前者="哪些 swing 算数"，后者="算多少历史"（性能旋钮），不要混用 |
| 改动 ④（D13） | 新增摆动点**分级**（short / intermediate / long-term）。他的定义是递归可机械化的：short-term = 两侧各一个更高低/更低高；intermediate = 由短周期点构成；long-term = HTF 反应后两侧形成短周期点 |
| 改动 ⑤ | 术语对齐（不改行为）：把 `refHigh/refLow` 的注释与调试输出标注为 **protected high / protected low**（语义已一致，他正是这个用词） |
| 验收 | 节点数与事件数变化；抽查若干 swing 是否为"左右皆严格"；relevance 边界应落在 3 根 HTF K 线的高低点上；分级标签抽查 |
| 风险 | D7 会让事件数明显变化（预期**减少**）；③ 依赖 `CopyHigh/CopyLow`，需处理 HTF 数据未就绪（返回 0 行）的降级路径 |
| 量 | M |

### 阶段 2：确认口径对齐（收盘 + 内包 K 线）

| 项 | 内容 |
|---|---|
| 差异项 | **D2**；**D9** |
| 改动 ①（D2） | 默认改为收盘确认（`InpCloseConfirm` 默认 `true`，或默认模式改 `MODE_STRICT_ICT`）。**零算法** |
| 改动 ②（D9） | **热路径重构**：现在 `CheckBreakAgainstRefs` 跑在 `validBars` 循环里，内包 K 线被 `continue` 掉。改为**突破检测遍历分析窗口内每一根 bar**，swing 检测继续只跑 `validBars`。做法：预生成 `isValidBar[]`，单趟从旧到新遍历 `i`：每根查突破，`isValidBar[i]` 为真时再跑 swing 逻辑 |
| 执行纪律 | **② 先单独做，且不改任何判定条件** —— 跑一版确认事件集合与改前一致（除内包 K 线新增的）**之后**再做 ①。两者混在一起无法定位差异 |
| 验收 | 改前/改后 events diff 应只有"内包 K 线处新增的事件"；随后做 ①，事件时点整体后移 |
| 风险 | ② 是状态机热路径重构，必须保持 `BOSMSS_FIX_SPEC.md` §四"先判突破、后更新 swing"的既有次序 |
| 量 | M |

### 阶段 3：位移判据 → 真正的 `MSS`

| 项 | 内容 |
|---|---|
| 差异项 | **D3** |
| 改动 | 破位 K 线需满足一组门槛才升级为 `MSS`。他只有定性描述（"strong price movement with momentum" / "decisive close through structure" / "minimal sideways consolidation"），**无任何数值** → 阈值必须自定并标注为近似。建议三选二：<br>① 实体 `\|close-open\| ≥ k1×ATR`<br>② 穿越深度 `\|close-level\| ≥ k2×ATR`<br>③ 与前一 K 的区间重叠比 ≤ r（对应"minimal consolidation"） |
| 新增：时效条件 | 他给了唯一一条近似可量化的规则："The best setups form **within one to three candles** and show immediate displacement." → 可加"位移须在破位起 1–3 根 K 线内发生" |
| 明确不做 | **不引入 FVG 检测**。他明确 FVG 只是加分项（"leaving behind a fair value gap, the probability… increases"），不是必要条件 |
| 事件分级 | 逆势破位未过门槛 → 早期事件（落点由决策 A 定为 `ChoCh`）；过了 → `MSS` |
| 验收 | events 里看位移量分布与升级比例；`MSS` 应明显少于早期事件 |
| 风险 | k1/k2/r **无外部依据**，必须留成可调参数，并在文档写明"本指标的近似，不是他的数字"。默认保守（宁少不多） |
| 量 | S–M |

### 阶段 4：CISD（他的核心确认工具）—— 真正拉开差距的一步

| 项 | 内容 |
|---|---|
| 差异项 | **D4** |
| 算法 | 在极值点处回溯**造势的同向收盘 K 线序列**（连续 `close>open` 或 `close<open`），取其**开盘价**作为 CISD 位；价格**收盘**穿越该位 → 多头/空头 CISD |
| 取数纪律 | 用他的话定边界："**Always use the series of candles.** Only use the single candle if there are no other opposing candles." → 有反向 K 线时不得只用单根 |
| ⚠️ 残留歧义 | "closes below the **opening price of those candles**"（复数）**仍未写死是序列里哪一根**。首根/末根结果不同。**按"首根（最旧那根）"实现并标注存疑**；他确有专文（`understanding-the-change-in-state-of-delivery-cisd`）与专视频（`CHIK5oBRKiw`），建议你从视频里确认一次 |
| 新增对象 | 新前缀（如 `CISD_<refBar>_<bar>`）+ 独立配色 + 渲染分支 |
| 验收 | **他自己给了判据**："CISD often appears earlier than MSS" → 导出 events 里 CISD 必须早于同向 MSS 出现，可直接自动化校验 |
| ⚠️ **该判据已纠正（见 §11）** | 上面这条是**我自己发明的**，且是**范畴错误**：他的模型里 CISD 与 MSS **不同周期**（"Higher time frame closure first → Lower time frame CISD"）。同周期比较不是他的用法，实测也确实不成立。真正的验证需要 LTF CISD × HTF MSS，属被推迟的 L4。 |
| 风险 | 连续同向收盘序列的起止需防抖：一根反向 K 是否终止序列要确认 |
| 量 | M |

### 阶段 5：sweep 标记（**v2 降级为可选**）

| 项 | 内容 |
|---|---|
| 差异项 | **D5** —— v1 结论已推翻：扫荡**不是**前置条件（"The sweep itself is not the confirmation."），他另有专视频把 MSS 与 liquidity grab 分开 |
| 改动 | ① 定义"流动性位"：前日/前周高低温、relevant swing 高低温；② sweep = 越过该位后**收盘回到位内**；③ 标为 `SWEEP` |
| 定位 | **只作上下文可视化，不作判定门槛。** 他的典型序列 "raid, FVG, MSS/SMT" 里扫荡是样例，不是必要条件 |
| 优先级 | **最低**。若为控制改动量，本阶段可整段砍掉而不影响 L1–L3 的保真度 |
| 量 | M（若做） |

### 阶段 6：L4 高周期门禁（**仅在决策 D 选 D2 时做**）

| 项 | 内容 |
|---|---|
| 差异项 | **D8** —— 本轮升级为严重项 |
| 改动 | ① 画前日/前周高低温；② 判定 HTF **candle 2 / candle 3 closure**（可机械化："price sweeps the previous candle's high or low and then closes back inside that range"）；③ 输出**偏置状态**（one-sided bias 是否成立）；④ 三层职责：HTF(bias) / 当前周期(structure) / 低周期(entry)；⑤ "Only trade when all timeframes point in the same direction" 的对齐检查 |
| 门禁语义 | 未过 HTF 门禁的结构事件应被**标记为未确认**（而非删除），并明确区分视觉 |
| 验收 | 图上可见偏置状态；events 里能区分"过了门禁/未过门禁"两组；门禁翻转时点可导出 |
| 风险 | 工作量最大的一层：多周期取数（`CopyRates`/`iHigh`）、HTF K 线未收盘时的处理、数据对齐。建议单独一轮做 |
| 量 | L |

### 阶段 7：文档与 Mine 版同步

| 项 | 内容 |
|---|---|
| 改动 | ① `CONTEXT.md`(34 处)、`BOSMSS_FIX_SPEC.md`(33 处)、`README.md`(10 处) 更新，并新增 `CISD` / `displacement` / `relevant swing` / `protected swing` / `摆动点分级` 词条，**明确标注 `ChoCh` 属 ICT 术语而非 TTrades 用词**；② `TradingVue/TradFi_Structure.mine` + `MIGRATION_NOTES.md` 同步（它用 `bar_index` 差值 + 滚动状态机，**不会自动一致**）；③ `docs/reviews/*` 与 ADR 属历史记录，**保留原文**，仅在新增文档注明口径已变更 |
| 量 | M |

---

## 3. 贯穿全程的回归护栏（上次踩过的坑）

1. **禁止把有副作用的调用写在 `||` / `&&` 右侧。** MQL5 短路 —— 上一版
   `changed = changed || Upsert*(...)` 导致 2367 个结构线对象只建出 1 个。新增分支一律 `if(F()) x = true;`。
2. **数组方向必须显式声明。** `OnCalculate` 入口已有 `ArraySetAsSeries(..., true)`；
   新增按 bar 下标访问的代码不得依赖默认方向。
3. **新增事件类型必须同步 `needDraw` 的 8 项指纹。** 否则新事件不触发重绘，
   表现为"要等下一根 bar 才出现"。
4. **新增事件要同步场景回收**：`AddSceneName` 注册 + 纳入 `OBJ_PREFIX` 体系，
   否则回收段把它当过期对象删掉。
5. **每阶段必须能单独回退**（阶段 2 的 ②、阶段 6 尤其）。
6. **改判定条件前后必须做 events diff**，不接受"看起来变好了"。

---

## 4. 明确不做（及原因）

| 项 | 原因 |
|---|---|
| 下单、止损、目标位、仓位 | 属**执行**（L6）；指标 `indicator_buffers 0` 发布不了数据。正确形态是新增 EA 消费结构事件 |
| FVG 检测作为位移的必要条件 | 他明确 FVG 只是加分项，不是必要条件（D3 备注） |
| SMT 背离、T-Spot、Auto Bias | 他的付费指标功能，超出结构对齐范围；SMT 还需第二个标的数据 |
| 把扫荡做成硬门槛 | D5 已推翻：他明确"MSS 与 liquidity grab"是两件事 |
| 把 `InpAnalysisWindow` 改成 relevance 窗口 | 用途不同（性能 vs 语义），合并会同时毁掉两边 |

---

## 5. 建议的执行顺序

```
阶段 0（基线 + events 导出）      ← 决策 C 已通过
   ↓
阶段 1（结构基元：D7/D6/D13）     ← 地基
   ↓
阶段 2（② 重构不动条件 → 验证 → ① 改收盘默认）
   ↓
阶段 3（位移 → MSS + ChoCh 分级）
   ↓
阶段 4（CISD）                    ← 收益最大的一步
   ↓
阶段 6（HTF 门禁）                ← 决策 D 选 D2 才做
   ↓
阶段 5（sweep 可视化）            ← 可选，收益最低
   ↓
阶段 7（文档 + Mine 同步）
```

**建议先做 0 → 1 → 2**，验证"对齐方向对不对、验收链路顺不顺"；CISD（阶段 4）是真正
拉开差距的一步，但它依赖阶段 1 的结构基元先稳定。

> **进度**：阶段 0 的代码部分**已实施并编译通过（0 errors / 0 warnings）** ——
> 新增 `InpDumpEvents` 与 `DumpEvents()`，已部署。等你在指标属性里勾上
> `InpDumpEvents` 重挂一次，即可产出基线 events 存档。

---

## 6. 待确认项（阶段 3 收口前需要你定）

### 6.1 未过位移门槛的逆势破位，图上怎么标？

纯 TTrades 命名下这个情形**没有对应术语**（他的早期信号是 CISD，不是"弱结构破位"）。

| 方案 | 做法 | 取舍 |
|---|---|---|
| **G1（推荐）** | 不画文字标签，只画一条弱化样式的虚线（灰/细） | 保留信息、不造术语；但需要图例说明灰线含义 |
| G2 | 完全不画，只在状态机内部用于切向 | 最干净；但丢失"结构被破但未位移"这一视觉线索 |
| G3 | 标一个中性描述词（如 `weak break`） | 好读；但仍是自造术语，与 D1 同类问题 |

### 6.2 `BOS` 保留吗？

他在 110 篇里只提过 `break of structure` **一次**，且为并列提及、**无定义**。
现状 `BOS` 是顺势破位标注（500 根窗口里 13 条）。

- 保留 → 维持"延续"这一支的可读性，文档注明"他未给正式定义"；
- 去掉 → 命名更纯粹，但丢掉一半标注信息。

**建议保留** —— 他确实按 hierarchy 并列讨论 BOS/MSS，且 *"Not every break of structure
is a full reversal."* 暗示他承认 BOS 这个层次；同时在 `CONTEXT.md` 标注定义缺口。

### 6.3 CISD 取序列里哪一根的开盘价？

他原文是 *"closes below the **opening price of those candles**"*（复数），未写死。
阶段 4 默认按**首根（最旧那根）**实现并标注存疑；他确有专文
（`understanding-the-change-in-state-of-delivery-cisd`）与专视频（`CHIK5oBRKiw`）可核。

---

## 7. 阶段 1 详细规格（动手前定稿）

阶段 1 有三处**他本人未给数值/未给边界**，必须先钉死再改状态机，否则改完无法判断对错。

### 1-A　swing 三点判定改左右皆严格（D7）

| | |
|---|---|
| 现状 | `high[i] > high[prevBar] && high[i] >= high[nextBar]`（左严格、右非严格） |
| 改为 | `high[i] > high[prevBar] && high[i] > high[nextBar]`（**右侧也严格**；low 对称） |
| 依据 | "a candle prints a high and there is a **lower high to its left and a lower high to its right**" |
| 影响 | 等高点/平台处不再确认 swing → 节点数减少，全部下游事件随之变化。**这是行为变更，不是修正**，必须与基线 diff 对照 |
| 注意 | 右侧严格后，`k >= nValid-1` 跳过最后一根的既有处理不变（无 `nextBar` 无法判定） |

### 1-B　failure swing 剔除（D6a）—— **已定：默认 `InpMinSeparationATR` = 1.0**

他的原话：failure swing "forms **too close to a prior high or low** and **lacks proper range
separation**" → 忽略；并**明确否认有数值公式**（"There is no strict numerical formula…
If it is too close, expect it to be taken."）。

提案：

- 新增 `InpMinSeparationATR`（默认 **1.0**）：一个 swing 与**上一个同类型 swing** 的
  **价格距离** < `InpMinSeparationATR × atrArr[i]` → 判为 failure swing，不予确认。
- **用价格距离而非 bar 距离** —— 他讲的是 range separation。
- 这是**新维度**，与既有的两个过滤不重叠：
  - `InpMinSwingAmplitude`（点数）作用在**腿长**上；
  - `IsValidRetrace`（腿长 ≥ ATR/比例）也作用在**腿**上；
  - separation 作用在**同类型相邻 swing 之间**。
- 被剔除后是否允许后续更极端的 swing 取代：沿用 `AddNodeFiltered` 已有的同类型替换逻辑。

### 1-C　HTF relevance 窗口（D6b）—— **已定：采用 C1（标记极值，不过滤）**

原文："look back **three higher timeframe candles including the current one**. The highs and
lows within that window are your relevant levels."

- 新增 `InpHTFPeriod`（默认 `PERIOD_D1`）。当前图 H1 时，3 根 D1 ≈ 72 根 H1。
- 取数：`CopyHigh(_Symbol, InpHTFPeriod, 0, 3, hiArr)` / `CopyLow(...)`。

**语义二选一（这是需要你定的点）**：

| 方案 | 做法 | 我的判断 |
|---|---|---|
| **C1（推荐）** | 把窗口内的**最高点/最低点标记为 relevant level**（额外标注，不删结构点） | 更贴合原话"The highs and lows within that window **are your relevant levels**"；且不破坏结构线连续性 |
| C2 | 用窗口边界**过滤** swing：落在 [relLow, relHigh] 之外/之内的才认 | 会删结构点，导致结构线断裂，与"折线连续"的既有设计冲突 |

- **降级路径必须有**：`CopyHigh/CopyLow` 返回 < 1 行（HTF 数据未就绪）→ 跳过 relevance 判定，
  **不得**因 HTF 缺数据而让指标整体不画。降级发生时必须在日志里可见。

### 1-D　摆动点分级（D13）

**他的原文三级定义**（<https://ttrades.com/advanced-market-structure-simplified-from-short-term-to-long-term-trends/>）：

- **Short-term low**：*"a swing low has a **higher low on each side of it**"* —— 即 1-A 确认出来的
  点本身（相邻 bar 级分形）。
- **Intermediate-term low**：*"a short-term low has **another short-term low to its left and
  right**"*。
- **Long-term low**：*"price reacts from a higher timeframe level, then forms a short-term low on
  each side"* → **依赖 HTF，留到阶段 6**。

**✅ 歧义已由他的示意图解决（2026-09-23）**：原文确实没写清邻居是否要更极端，但配图
`ITM.png`（已下载至 `docs/research/img/`）给出了决定性反证。

图中标了 4 个 `STH` 与 1 个 `ITH`，高点价格依次为：

```
STH(1)  <  STH(2)  <  ITH(峰)  >  STH(3)  >  STH(4)
```

**关键**：`STH(2)` 左侧有 `STH(1)`、右侧有 `ITH` —— **左右都是 short-term high**。
若按字面读法（"左右各有一个 short-term high 即 intermediate"），它**也应被标成 ITH**，
但图上标的是 `STH`。→ **字面读法被直接否证。**

且整组只标出**一个** ITH，说明该层级有区分度（不是"任何内部点都算"）。

> **因此实现口径确定为**：intermediate = 一个 short-term 点，且**比左右最近的同类型
> short-term 点都更极端**。节点数组强制高低交替，故"最近的同类型点"就是 `nodes[n-2]`
> 与 `nodes[n+2]`。**不再是"解释"，而是有图示依据的定义。**

**另两张配图的结论**：

- `ITM-FVG.png`：展示 **Rebalanced**（*"formed when price rebalances a fair value gap and
  trades away"*）那一类 —— 图中 ITH 旁画了两条水平线（FVG 边界）。**需要 FVG 检测，
  超出 L1–L3 范围**，本轮只做 Basic 型，与 §7 原计划一致。
- `LT.png`：展示 long-term 的确需要 **HTF Level** 参照（图中画了 HTF 水平线，`LTL` 在其下方
  反应成形）→ 印证 long-term **必须留到阶段 6**。

另外他给了 intermediate 结构的**两种类型**：Basic（由 short-term 摆动构成，可实现）与
Rebalanced（*"formed when price rebalances a fair value gap and trades away"* → **需要 FVG 检测，
超出 L1–L3 范围**）。本轮只做 Basic。

实现：给 `StructureNode` 加 `tier` 字段（0=short, 1=intermediate），写入 CSV 的 `tier` 列。

### 1-F　protected swing 改由 intermediate 点驱动（**本阶段影响最大的一处**）

他的原文给出了 protected swing 的归属：

> *"Intermediate-term highs/lows confirm stronger pivots and sweeps (**protected swings**)."*

即：**protected swing = intermediate-term 结构点**。

现状：`refHigh/refLow`（= 他说的 protected high/low）由 `isMainSwing` 驱动，判据是
**腿长 ≥ 1.0×ATR 或 ≥ 0.382×前一段幅度**（`InpMainFilterATR` / `InpMainFilterRatio`）——
这是**幅度门槛**，与他的**结构层级**是两套不同的分类法。

提案：`refHigh/refLow` 改由 **tier-1（intermediate）点**驱动；`isMain` 的幅度门槛降级为
**线型/可见性**用途或直接废弃（待定）。

- **必须作为独立子步做**，因为它会让事件集合发生最大幅度的变化，
  要与 1-A/1-B/1-C 的 diff 分开归因；
- 若 1-D 的 tier 判定必须由你核实后才可信，则 **1-F 应当排在核实之后**。

### 1-E　术语对齐（不改行为）

`refHigh/refLow` 的注释与 `InpDebugShowRef` 输出标注为 **protected high / protected low**
（语义已与他的用词一致，只是名字不同）。

### 阶段 1 验收

1. 基线 CSV 与改后 CSV **逐行 diff**（这是阶段 0 存在的唯一理由）；
2. 预期方向：节点数 ↓（1-A 严格化 + 1-B 剔除）、事件数 ↓；
3. 抽查：随机取若干 swing，人工核对左右邻居是否都更低/更高；
4. relevance：日志打印本期 3 根 HTF K 线的高低与时间范围，人工核对是否落对位置；
5. 降级：用一个历史不足的 HTF 周期（如 `PERIOD_MN1`）验证降级路径不崩、且日志有降级提示。

---

## 8. 阶段 1 执行结果（1-A + 1-B + 1-E 已实施）

**构建指纹**：`BUILD_TAG = "v1.48-s1"`（出现在 INIT 日志与 CSV 头部）。
编译 0 errors / 0 warnings；MT5 侧 `.mq5` 与 `.ex5` 均已与仓库产物校验一致。

**测量条件**：EURUSD.ct H1，`rates=16854`，`window=200`，`analysisWindow=500`，
`mode=MODE_SHORT_TERM`，`closeConfirm=false`，`InpMinSeparationATR=1.0`。

### 8.1 量化对比

| 指标 | 基线（阶段 0） | 阶段 1 | 变化 |
|---|---|---|---|
| `nodes` | 68 | **34** | −50% |
| `afterSep`（1-B 剔除量） | — | **51** | 占 afterRet(96) 的 53% |
| `MSS` | 20 | **12** | −40% |
| `BOS` | 13 | **9** | −31% |
| 事件总数 | 33 | **21** | −36% |
| 相邻事件**方向翻转**次数（摆荡代理） | 20 | **12** | −40% |
| `fractal`（1-A 影响） | 124 | 119 | −4% |

**读数**：`fractal` 只降 4%，说明 **1-A（左右皆严格）本身影响很小**；
真正起作用的是 **1-B**（`afterSep=51`，剔掉了过半数候选）。
摆荡代理指标（方向翻转 20→12）同向改善，符合预期。

### 8.2 事件级 diff 的两个发现

1. **6 个 bar 上的事件类型发生翻转**（`MSS↔BOS`），例如 bar 233 `BOS→MSS`、
   bar 416 `BOS→MSS`、bar 23/95/161/258 `MSS→BOS`。
   原因：节点从 68 降到 34，**状态机在那些突破点的趋势状态本身变了** ——
   这是结构性变更的必然结果，不是 bug。
2. 17 个 break bar 不再触发事件，5 个新 break bar 开始触发。

### 8.3 待办

- **隔离 1-A**：把 `InpMinSeparationATR` 改成 **0**（属性对话框里改即可，触发
  `REASON_PARAMETERS` 重载，无需重挂）→ 即可得到"只有 1-A"的那组测量，
  用于判断 1-B 是否过严。
- 归档：`docs/baselines/2026-09-23-stage0_EURUSD-H1.csv`（33 条）与
  `docs/baselines/2026-09-23-stage1_EURUSD-H1.csv`（21 条）。
- 1-C（HTF relevance 标记）、1-D/1-F（分级与 protected swing 改由 intermediate 驱动）
  尚未实施；1-D 依赖对 `ITM.png` 的人工核实。

### 8.4 ⚠️ 测量环境不是默认值（CSV 头部机制抓到）

自描述头部上线后第一次运行就抓到两条：

1. **`retraceATR=0.000`，而默认是 0.5。** 其余参数（`retracePoints=100`、`minBars=2`、
   `minAmp=0`、`mainATR=1.00`、`mainRatio=0.382`、`atrPeriod=14`）均与默认一致，
   说明参数映射无误 —— 是图表上这个输入确实为 0。
   **影响**：`IsValidRetrace` 中 `atrOk = (InpMinRetraceATR <= 0.0) || ...` → `atrOk` 恒真，
   整个 ATR/比例门槛被短路，有效回撤过滤退化成「腿长 ≥ 100 points（10 点）」。
   这解释了 §8.1 里 `afterRet=96 / afterGap=110` 为何如此宽松。
2. **`sepATR` 仍是 1.00** —— 试图改成 0 的动作未生效（新开图表时输入回落默认值，
   而 `InpMinSeparationATR` 默认即 1.0）。

**处置**：归档文件的 `# PROVENANCE` 行已按**实测值**改写
（`retraceATR=0.000` 并标注 NON-DEFAULT），不再是我先前猜测的 0.500。

**待你决定**：`InpMinRetraceATR` 是本指标自有的过滤机制（不是 TTrades 的概念），
为了让测量可复现、且与文档默认值一致，建议**恢复 0.5**；但它会同时改变事件集合，
所以**不要与 `sepATR` 的测量混在一次改动里** —— 见 §8.3 的顺序。

### 8.5 环境切换：测量基准已回到文档默认值（**重要**）

`build=v1.48-s1.2` 加载后，INIT 参数回显显示 **`retraceATR=0.500`** —— 即重挂/重置把
§8.4 提到的非默认值恢复了。**这意味着 §8.1–8.3 的三组测量都是在
`retraceATR=0.000`（非默认）下做的，与当前环境不可直接比较。**

那条"1-A 几乎无影响、1-B 承担全部"的归因结论**只在非默认环境下成立**，
需要在默认环境下重测才能作为定论。

**→ 更正：实测表明环境差异可忽略，归因结论仍然成立。** 对照两组的过滤计数器：

| 计数器 | 默认环境 (sep=0.5, retraceATR=0.5) | 旧环境 (sep=1.0, retraceATR=0) |
|---|---|---|
| `fractal`（1-A 的原始影响，位于所有过滤之前） | **119** | **119** |
| `afterRet`（回撤过滤后） | **97** | **96** |
| `afterSep`（1-B 剔除量） | **32** | 51 |
| `nodes` | 48 | 34 |

`retraceATR` 由 0 → 0.5 只让 `afterRet` 从 96 变 97（≈1%），`fractal` 完全相同 ——
原因是 `InpMinRetracePoints`(100 points) 那道最小腿长门槛本来就起主导，
ATR 门很少成为决定因素。故**无需补测**，归因可直接采信：

- **1-A 微小**：`fractal` 在两种环境下均为 119（对基线 124 即 −4%）；
- **1-B 主导**：`afterSep` 在 0.5 档剔 32、1.0 档剔 51，单调且量级最大；
- **节点数随 sepATR 单调**：66（0）→ 48（0.5）→ 34（1.0）；用户选定 **0.5** 为默认。

已归档四点：

| 归档文件 | sepATR | retraceATR | 事件 | MSS | BOS | dirFlips |
|---|---|---|---|---|---|---|
| `2026-09-23-stage0_EURUSD-H1.csv` | n/a（1-B 未实现） | 0.000 ⚠️非默认 | 33 | 20 | 13 | 20 |
| `2026-09-23-stage1-sep0_EURUSD-H1.csv` | 0.00 | 0.000 ⚠️非默认 | 32 | 18 | 14 | 18 |
| `2026-09-23-stage1_EURUSD-H1.csv` | 1.00 | 0.000 ⚠️非默认 | 21 | 12 | 9 | 12 |
| `2026-09-23-stage1-default-env_EURUSD-H1.csv` | 0.50 | 0.500 ✅默认 | 29 | 16 | 13 | 16 |

**~~待补~~**：默认环境下 `sepATR=0.00` 与 `1.00` 两组 → **已由上面的计数器对照证明不必补测**（环境差异 ≈1%）。

**新增的可自证机制**：`InpMinSeparationATR` 默认值改为 **0.5**；
INIT 行现在回显 `build=` 与全部过滤参数，改完输入项可在「专家」标签页直接确认是否生效。

### 8.6 阶段 1-C 执行结果（HTF relevance 标记）

构建 `v1.48-s1.3`；编译 0 errors / 0 warnings。

| 部件 | 实现 |
|---|---|
| 输入 | 新分组 `== HTF relevance ==`：`InpHTFPeriod`(默认 `PERIOD_D1`)、`InpDrawRelevance`、`InpColorRelevance` |
| 取数 | `CopyHigh/CopyLow/CopyTime(_Symbol, InpHTFPeriod, 0, 3, …)` → 窗口极值 + 起止时间 |
| 常量 | `#define RELEVANCE_BARS 3`（做成 `#define` 而非输入，避免偏离他的原口径） |
| 绘制 | `STYLE_DOT` 水平线 `Structure_RELH` / `RELL`，已 `AddSceneName` 注册（否则被回收段删除） |
| 指纹 | `needDraw` 已加入 `g_relHigh/g_relLow/g_relValid` 三项（护栏 #3） |
| 降级 | `Copy*` ≤0 时不画 + debug 下打印 `STRUCT_REL 降级：… gotH/gotL/gotT/err` |
| 方向无关性 | 极值用 max/min、时间用 min/max → 与数组填充顺序无关，故**不需要** `ArraySetAsSeries`（已在注释说明，避免后人误判为漏写） |
| 刻意不做 | relevance **不进 CSV 头**：它不参与任何过滤，事件集合与之无关，故 CSV 在不同 `InpHTFPeriod` 下仍可比 |

**验证结果**：

1. CSV 头 `build=v1.48-s1.3` → 新构建确已加载；
2. CSV 头 `nodes=48 mss=16 bos=13` → **仍 29 条事件，与 1-C 之前完全一致** ——
   这是关键回归判据，证明 1-C 没有渗入分析层；
3. 人工确认图上出现两条浅蓝点线；
4. `STRUCT_REL` 调试行未出现（运行实例 `InpDebugShowRef=false`），HTF 窗口数值待
   打开该开关后核对。

**过程更正（重要，我先前判断错误）**：本次一度认为 `v1.48-s1.3` 的 INIT 行"未出现"，
并据此推测"改输入项不触发 `OnInit`"。**该推测是错的** —— 稍后重读同一日志，
**13:24:26（`sepATR` 改动的重载）与 13:43:49（s1.3 加载）的 INIT 行都在**，
且 `reason=5` 确有 1 条。

真实原因是 **MT5 的专家日志写入有延迟**：即时读取会漏掉刚发生的行。

> **实践约定**：验证日志时若预期行缺失，**不要立即下结论**，隔几十秒重读；
> 或改用 CSV 头部（它在文件落盘时即完整）。

两个指纹因此都是可靠的。保留两者仍值得：CSV 头是**归档物**，归档文件自带参数，
比日后翻日志方便；INIT 行则能在「专家」标签页被人工直接看到。

---

## 9. 阶段 2 执行结果（确认口径对齐）

### 9.1 2-② 遍历结构重构（**不改任何判定条件**）

构建 `v1.48-s2`。改动内容：

- 新增 `validPos[]`：bar 下标 → `validBars` 位置（-1 = 内包 K 线）；
- 突破检测从 `validBars` 循环中移出，改为 `for(int i = analysisStart; i >= 0; i--)`
  **遍历分析窗口内每一根 bar**（含内包 K 线）；swing 逻辑仍只跑有效 bar；
- guard `if(k < 1 || k >= nValid - 1) continue;` 置于 A2 之后、`prevBar` 求值之前
  —— 否则 `validBars[k-1]` 在 k=-1 时会越界（下标 -2）。

**验收结果：29 → 29 条事件，消失 0、新增 0 —— 零差异。**
过滤计数器（`fractal/afterGap/afterRet/afterSep`）也完全相同。
证明该重构在现有（影线）确认口径下**行为中性**，状态机未被扰动。

### 9.2 2-① 默认改为收盘确认

构建 `v1.48-s2.1`，`InpCloseConfirm` 默认由 `false` 改为 `true`
（CSV 头与 INIT 行均确认 `closeConfirm=true` 实际生效）。

| 指标 | 影线 (s2) | 收盘 (s2.1) |
|---|---|---|
| `nodes` | 48 | 48（结构节点与确认方式无关） |
| `mss` / `bos` | 16 / 13 | **14 / 10** |
| 事件总数 | 29 | **24**（−5，−17%） |
| 过滤计数器 | 119/106/97/32 | 完全相同（确认在所有过滤之后） |

**按「结构位价格」对齐的事件 diff（29 → 24）：**

| 类别 | 数量 | 解释 |
|---|---|---|
| 两边都有、完全不变 | 12 | 本就在收盘价外 |
| 两边都有、**仅时点后移** | **8** | 等收盘所致（后移 1～11 根）—— 这正是他的要求 |
| 两边都有、类型翻转 `BOS↔MSS` | 2 | 趋势状态因前面事件集合变化而不同 |
| **仅影线口径有** | **7** | 只是刺破、从未收在该位外 → 正是假破位 |
| 仅收盘口径有 | 2 | 状态机路径变化所致 |

那 7 条正是 D2 要消除的对象，对应他的原话：
*"If the candle cannot close through the level you need, the reversal is not confirmed."*

### 9.3 归档（`docs/baselines/`）

| 文件 | sepATR | retraceATR | closeConfirm | 事件 |
|---|---|---|---|---|
| `2026-09-23-stage0_EURUSD-H1.csv` | n/a | 0.000 ⚠️ | false | 33 |
| `2026-09-23-stage1-sep0_EURUSD-H1.csv` | 0.00 | 0.000 ⚠️ | false | 32 |
| `2026-09-23-stage1_EURUSD-H1.csv` | 1.00 | 0.000 ⚠️ | false | 21 |
| `2026-09-23-stage1-default-env_EURUSD-H1.csv` | 0.50 | 0.500 | false | 29 |
| `2026-09-23-stage2-refactor_EURUSD-H1.csv` | 0.50 | 0.500 | false | 29 |
| `2026-09-23-stage2-closeconfirm_EURUSD-H1.csv` | 0.50 | 0.500 | **true** | 24 |

### 9.4 下一步

阶段 3（位移判据 → 真正的 `MSS`）。注意他在 110 篇里只提过 `break of structure` **一次**，
故 `BOS` 一支仍无可对标定义（见差异清单 D11）—— 阶段 3 只影响"逆势破位"那一支。

---

## 10. 阶段 3-a 执行结果（位移判据：只计算、不改渲染）

构建 `v1.48-s3`（编译 0 errors / 0 warnings）。拆成 3-a / 3-b 两步是为了归因：
3-a 只把判据结果**记录**下来，3-b 才让它影响**画面**。

### 10.1 三条判据（全部做成输入项 —— 他未给任何数值）

| 判据 | 输入 | 默认 | 对应他的原话 |
|---|---|---|---|
| 实体强度 | `InpMinDisplaceBodyATR` | 1.0 | "The key confirmation is displacement (**strong** price movement with momentum)" |
| 收盘穿越深度 | `InpMinDisplacePenATR` | 0.3 | "a **decisive close** through structure" |
| 时效 | `InpDisplaceMaxBars` | 3 | "The best setups form **within one to three candles**" |

### 10.2 时效条件的**无状态**实现（关键设计）

收盘确认发生在 bar `i` 时，`bar i` 自身即一次影线穿越。于是：

> 「首次穿越落在 `[i, i+N-1]`」**等价于**「`(i+N .. ref.bar-1)` 区间内没有穿越」

因此**不需要新增 `pierceBar` 字段** —— 省掉了约 10 处 `RefPoint` 状态初始化点的漏改风险
（漏一处就会读到陈旧值，产生难以定位的错误判定）。比 `ref.bar` 更旧的 bar 不计入，
因为那些 bar 早于该 ref 形成，不属于"本次穿越"。

### 10.3 实现落点

- `StructureEvent` 增 `weak` / `bodyATR` / `penATR` → CSV 已预留的 `displacement` 列现在填
  `body=1.23 pen=0.45 OK|WEAK`；
- `AddMSSResult` 增 `strong` 参数；度量经 `g_lastBodyATR` / `g_lastPenATR` 传递，
  避免 4 处调用点各自重复计算；
- `CheckBreakAgainstRefs` 增 `atrArr` 参数（ATR 是 `ComputeStructure` 的局部数组）；
- 新增 `# displacement dispBody=… dispPen=… dispBars=…` 头行；INIT 行同样回显。

### 10.4 验收结果

**事件仍 24 条、`nodes` 仍 48、`mss=14 / bos=10` —— 与 s2.1 完全一致。**
即 3-a 是**纯增量**（只多记录度量，不改任何过滤决策），无回归。

MSS 的 WEAK/OK 分布（阈值 1.0 / 0.3 / 3）：

| 结果 | 条数 | 按失败原因拆分 |
|---|---|---|
| OK | 7 | — |
| WEAK | 7 | 实体不足 **3**；仅穿越深度不足 **1**；**仅时效不足 3** |

**结论：那条 "within one to three candles" 的时效条件不是装饰** —— 它单独贡献了 3/7 的 WEAK
（这 3 条 `body=1.41 pen=1.38`、`1.31/0.61`、`1.22/0.62` 的实体与深度都合格）。
若按备选的"砍掉时效条件"方案，它们会被判为 OK。

另有一例值得注意：`body=1.49 pen=0.03` —— 大实体但几乎没收在位外，正确地被判 WEAK。

### 10.5 阶段 3-b 执行结果（G1 渲染 + 命名收口）

构建 `v1.48-s3.3`（编译 0 errors / 0 warnings）。

| 分支 | 线 | 标签 |
|---|---|---|
| **OK**（过位移门槛） | `InpColorMSS` 黄 + `STYLE_DASH` | **`MSS`** |
| **WEAK**（未过门槛） | `InpColorWeakBreak` 灰 + `STYLE_DOT` | **无标签** |

实现要点：weak 事件**不把标签名注册进场景集**（`if(!weak) AddSceneName(lbl);`）——
回收段遵循"未注册即删除"，旧标签自动清除，无需另写删除逻辑。

**命名收口**：全文件 `ChoCh` 残留归零，用户可见文案（属性分组名、输入说明、枚举注释、
专家日志 `MSS event:` 与 `MSS=%d` 字段）与确认级标签统一为 `MSS`。
至此落地"纯 TTrades 命名：`MSS` / `CISD`，不用 CHoCH"这一决策。

**验证（含一处事前量化预测）**：

- INIT 行 `build=v1.48-s3.3`；
- 事件仍 **24 条**（`nodes=49 / mss=15 / bos=9` —— 期间新到了一根 bar，总数不变）；
- 人工确认画面出现灰点线与 `MSS` 标签；
- **`chartObjs` 由 50 降至 47（−3）**，与预测完全一致：`InpMaxEvents=6` 下最近 6 条 MSS 中
  有 3 条 WEAK，其标签对象不再创建。

### 10.6 阶段 3 对照差异清单的落地情况

| 差异项 | 状态 |
|---|---|
| **D1** 术语与语义错位 | ✅ 命名收口为 `MSS`；确认级语义由位移判据承载 |
| **D2** 缺收盘确认 | ✅ 默认 `closeConfirm=true`（阶段 2-①） |
| **D3** 缺位移判据 | ✅ 三条判据 + 度量入 CSV（阶段 3-a） |
| **D4** 缺 CISD | ❌ **仍是最大缺口** —— 他实操里真正承担"确认"职责的工具 |
| D5 扫荡非前置 | ✅ 已按更正后的结论处理（未做成门槛） |
| D6/D7/D13 | 部分（1-A/1-B 已做；1-D/1-F 待核实） |
| D8 HTF 门禁 | ❌ 按决策 D1 接受天花板，未实施 |

---

## 11. 阶段 4 执行结果（CISD）

### 11.1 4-a 检测（构建 `v1.48-s4`）

| 部件 | 实现 |
|---|---|
| **CISD 位** | 自极值 bar 起向**更旧**方向收集极大的同向收盘序列，取**最旧那根的开盘价** |
| ✅ **取哪一根已由配图证实** | 原文 *"closes below the opening price of **those candles**"*（复数）**未写死**。配图 `docs/research/img/CISD-2026-01.png` 给出答案：CISD 线画在**造势序列最旧那根的开盘价**上 —— 它**明显远离极值、贴近整段造势的起点**，从而**否证**了"取紧邻极值那根"的读法。故本实现（最旧那根）正确，存疑解除 |
| 方向陷阱 | series 下 `下标增大 = 更旧`，故向更旧推进是 `j++`（已注释标出，易写反） |
| 保守跳过 | 极值 bar 自身若与造势方向不同向（长影线单根反转）→ 不设位 |
| 触发 | 收盘穿越即触发，**与趋势状态无关**（他："Instead of focusing on swing highs or lows…"） |
| 判据复用 | 位移判据抽成通用核 `DisplacedBeyond(level, anchorBar, …)`，**MSS / CISD 共用同一套三条门槛**（原 `MSSDisplaced` 改为薄封装） |
| CSV | 改为 **3 路时间归并**（MSS/BOS/CISD 混排） |
| 指纹 | `needDraw` 已加入 `nCISD` |

**验收：MSS/BOS 仍 24 条、完全未变** ✓（CISD 是并行检查，只改 `cisd*Fired`，不碰 refs 与趋势状态）。
CISD 检出 **18 条**（OK 4 / WEAK 14）。

### 11.2 ⚠️ 我对验收判据的纠正（重要）

阶段 4 的计划里我写了验收判据"CISD 必须早于同向 MSS"。**这是我自己发明的，且是范畴错误。**

他的模型里 CISD 与 MSS **分属不同周期**：
*"Higher time frame closure first → Lower time frame change in the state of delivery."*
**同周期比较不是他的用法。**

实测同样印证该判据不成立：12/15 条 MSS 有同向前置 CISD，但**只有 5/15 的 lead ≤ 10 根**
（其中 4 条 ≤3 根、2 条与 MSS 同 bar），其余 lead 为 32–98 根（已是无关的旧 CISD）。

**机制解释**：他的 CISD 用在**扫荡后短促的造势序列**上（run 常 1–3 根），起点开盘价贴近极值、
触发很快；而本指标锚在**结构摆动极值**，其造势序列常达十几根连续同向收盘 K，起点很远
→ 必须回吐整段造势才穿越。**故"同周期下 CISD 不早于 MSS"是该场景的必然结果，不是 bug。**

→ 真正验证"CISD 早于 MSS"需要 **LTF CISD × HTF MSS** 的双层结构，即被推迟的 L4。

### 11.3 4-b 渲染（构建 `v1.48-s4.1`）

**决策：CISD 不做 WEAK 分级、全部带标签。** 理由：他明说 CISD 是 *"earlier but riskier"*
（*"CISD can give earlier entries but sometimes too early, leading to false signals"*），
而用 MSS 那套为"穿越 swing 结构位"设计的位移门槛去筛它，实测 18 条里 14 条被判 WEAK ——
与它的定位自相矛盾。质量改以**颜色**区分：OK = `InpColorCISD`（紫），WEAK = `InpColorCISDWeak`（暗紫）；
度量仍逐条写入 CSV。

`cisdFrom` **刻意不进** `needDraw` 指纹：它由 `nCISD` 与常量 `InpMaxEvents` 派生，
而 `nCISD` 已在指纹中，指纹充分。

**验收**：事件仍 **42 条不变**；`chartObjs` **47 → 59（+12）**，
正好 = 6 条 CISD ×（线 + 标签），与 `InpMaxEvents=6` 的预测完全一致；人工确认紫色标注。

### 11.4 落地情况更新

| 差异项 | 状态 |
|---|---|
| **D4 缺 CISD** | ✅ **已实现**（同周期口径；其"早于 MSS"的跨周期角色待 L4） |
| 其余 | 见 §10.6 |

**归档**：`docs/baselines/2026-09-23-stage4a-cisd_EURUSD-H1.csv`（42 条）、
`2026-09-23-stage4b-cisd-render_EURUSD-H1.csv`（42 条）。

### 11.5 标签精简（构建 `v1.48-s4.2`）

按你的要求，MSS / BOS / CISD 三种事件的标签**只留类型名**，移除 `#<refBar> <price>` 后缀；
**水平位线保留**。调试信息（`refBar` / `refPrice` / `bind`）改为**只写专家日志** ——
`InpDebugShowRef` 因此只控制日志、不再影响图层文案，该开关的语义反而更干净了。

验收：`chartObjs` 仍 **59**、事件仍 **42 条**（15 MSS + 9 BOS + 18 CISD），全部未变；
人工确认标签已精简。

---

## 12. 三方一致性核对（MSS / BOS / CISD vs TTrades）

> 方法：先引一手文字，再用**他的配图**做判别（图已下载至 `docs/research/img/`）。
> 目的：在开始 1-D/1-F 之前，确认已实现的三个事件本身是否与他对齐。

### 12.1 MSS —— ⚠️ **部分一致（本节结论已于 §19 收窄，勿单独引用）**

> **回收声明（§19.4-D12 之后补写）**：本节原判"✅ 一致"，那是**只看定义句与线的画法**得出的。
> §19.4 发现 **D12**：`strong`（位移）只用于记录，`CheckBreakAgainstRefs` 在
> `st.state = ST_DOWN` 处**无条件**翻转趋势状态 —— 即**位移不足的破位照样改变趋势**。
> 而他明文要求 *"MSS marks a trend change **confirmed by displacement**"*，
> 实测 15 条 MSS 中 7 条位移不足。
> 另 **D17**：ref 驱动源未对齐（本表最后一行已自认，且 §19.4-I 指出其**定义**亦不符）。
> 故本节的正确结论是 **⚠️ 部分一致**，未对齐项为 D12 与 D17。

**决定性证据**：`ChangeInTrend-Bearish.png`（"Change In Trend"）中，趋势变化的标注是一条**橙色短横线，画在 `HL` 位上并向右延伸** —— 即"上升趋势中跌破 HL"就是他所标的趋势变化。

| 核对项 | 他 | 本实现 | 结论 |
|---|---|---|---|
| 触发位置 | 跌破 HL（上升趋势中） | `ST_UP` 跌破 `refLow` → `MSS(DOWN)` | ✅ |
| 线的画法 | 从被破位向右延伸 | 从 `refBar` 起到 `tEnd` | ✅ |
| 确认口径 | *"displaces and **closes**"* | `closeConfirm=true`（默认） | ✅ |
| 位移 | *"confirmed by displacement"* | 实体/深度/时效三条门槛 | ❌ **只用于渲染，未用于状态机（D12）** |
| 扫荡前置 | *"The sweep itself is **not** the confirmation"* | 未做成门槛 | ✅ |

**⚠️ 唯一不一致处（正是 1-D/1-F 要修的）**：本实现用 **`isMainSwing`（腿长 ≥1.0×ATR 或 ≥0.382×前段）**
挑选驱动 `refHigh/refLow` 的 swing；而他的口径是按**层级**，并且用法有分工：

> *"Look for **short-term** highs/lows to confirm shifts."*
> *"Intermediate-term highs/lows confirm stronger pivots and sweeps (**protected swings**)."*

即：**"确认转换"用 short-term、"protected swing"用 intermediate**。本实现两者都没按层级来 →
**这是当前唯一的实质性偏离，1-F 正是修它。**

### 12.2 BOS —— ⚠️ **无法核实（无可对标定义）**

- 全站 110 篇中 `break of structure` **仅出现 1 次**，且为并列提及；
- `BullishTrend-Structure.png` 与 `BasicUptrend.png` 都**只标 HH/HL 序列，没有任何 BOS 标记**；
- 因此本实现的"顺势破位"是**行业通行的合理读法**，但**无法声称与他一致**。

→ 对应差异清单 **D11**，本轮**无法关闭**，只能如实标注"他未给出定义"。

### 12.3 CISD —— ✅ **一致**

| 核对项 | 他 | 本实现 | 结论 |
|---|---|---|---|
| 位的位置 | 同向收盘序列的**开盘价** | 同向收盘序列**最旧那根**的开盘价 | ✅ 配图证实 |
| 取哪一根 | 文字未写死 | 最旧那根 | ✅ `CISD-2026-01.png` 显示线**明显远离极值、贴近造势起点**，否证"紧邻极值那根" |
| 是否看 swing | *"Instead of focusing on swing highs or lows…"* | 触发与趋势状态无关 | ✅ |
| 位移 | *"displaces and closes beyond that open"* | 与 MSS 共用 `DisplacedBeyond` | ✅ |
| 序列纪律 | *"Always use the series of candles."* | 收集极大同向序列，非单根 | ✅ |

**⚠️ 一处可接受的近似**：本实现的锚点是**已确认的摆动节点**；他的锚点是"造出该高低点的那串 K 线"，
理论上可以是任何极值。该差异无法从配图判别，属可接受近似（已在代码注释标注）。

### 12.4 顺带：1-B 的 separation 度量得到配图支持

`Valid-Seperation.png` 用两个面板对照 `Invalid separation` / `Valid separation`，
并以**浅蓝矩形的高度**表示分离度 —— 即 separation 是**同类型摆动点之间的价格/区间距离**
（不是 bar 距离）。这与本实现的 `|price − prevSameType.price|` 度量一致 ✅。
**但图只给"小 vs 大"的定性对照，仍无数值** → `InpMinSeparationATR=1.0` 依旧是我们自定的近似。

### 12.5 结论

**MSS ✅ / CISD ✅ / BOS ⚠️（无可对标定义）。**
唯一需要修的是 §12.1 标注的那处：**ref 的驱动源应按层级而非幅度门槛** —— 这恰好就是 1-D/1-F。
**故可以开始 1-D/1-F。**

---

## 13. 1-D 结果与 1-F 的搁置

### 13.1 1-D 已完成（构建 `v1.48-s5a`）

- **定义**（由图 `ITM.png` 证实）：intermediate = 一个 short-term 点，且比左右**最近的同类型**点都更极端。
- **实现**：`ClassifyNodeTiers()` 在 **主循环之后整表计算** —— 右侧邻居 `n+2` 在节点 `k`
  确认时还不存在，分级必须后验；tier 写入 CSV 的 `tier` 列（**查询期按 `refBar` 反查**，
  因为事件创建时层级尚未算出）。
- **验收**：事件仍 **42 条**、`chartObjs` 仍 **59**，未变 ✓

### 13.2 tier 分布（EURUSD.ct H1，49 节点 / 42 事件）

| 事件 | 总数 | intermediate | short | **空** |
|---|---|---|---|---|
| **MSS** | 15 | **0** | 7 | **8** |
| BOS | 9 | 3 | 5 | 1 |
| CISD | 18 | 6 | 9 | 3 |

### 13.3 ⚠️ 1-F 被搁置 —— 其前提被测量推翻

原设计"**ref 只由 intermediate 点驱动**"不成立，两条独立障碍：

**① 语义上不成立**：MSS 锚点 **0/15** 是 intermediate，这是定义的必然结果 ——
intermediate = 同类型序列的**局部极值**，而完好的上升趋势里低点**单调抬高**
（某低点跌破前低，那本身就是 MSS）。故**趋势中不存在 intermediate 低点**，
它们只在转折附近出现。于是"ref 只由 intermediate 驱动"会导致
**趋势中 ref 几乎不更新 → MSS 只能在陈旧结构位上触发**，显然不是他的本意。

**② 工程上也不可行**：**8/15** 条 MSS 的 `refBar` 在最终节点表里**已被"同类型更极端者替换"**
（例如 `break=09.17 09:00, ref=09.17 03:00` 已不存在）。即便前提成立，
事件时刻也拿不到 tier —— 分级必须后验，而锚点可能已被替换。

**重读他的原句后判断：原先是我读错了。** 两句合起来看：

> *"Intermediate-term highs/lows confirm stronger pivots and sweeps (**protected swings**)."*
> *"Use **intermediate-term sweeps** as confirmation of continuation or reversal."*

intermediate 点更像是**被扫荡的流动性目标**，而 protected swing 是**扫荡之后形成**的那个点 ——
**不是"intermediate 点本身就是 protected swing"**。该机制属于 Stage 5（sweep）的范畴，
故 1-F 与 Stage 5 合并考虑更合适。

**决定**：**1-F 搁置**；保留 1-D 的 tier 信息（已入 CSV，可用于过滤/展示等其它用途）。
归档：`docs/baselines/2026-09-23-stage5a-tier_EURUSD-H1.csv`。

---

## 14. 阶段 5 执行结果（SWEEP）

### 14.1 实现（构建 `v1.48-s5`）

| 项 | 内容与依据 |
|---|---|
| **扫荡位** | 只取 **intermediate（tier-1）节点** —— 依据他 *"Use **intermediate-term** sweeps as confirmation of continuation or reversal."* 前日/前周高低温属 HTF 上下文（L4，已推迟），本轮不纳入 |
| **判据** | 某根 K 线**影线越过位、但收盘收回位内**（`high>lvl && close<lvl`，低点对称）—— 他的 *"sweeps … and then closes back inside that range"* |
| **时机** | **主循环之后的后验扫描**（`ClassifyNodeTiers()` → `ComputeSweeps()`）。sweep 不参与判定，故**不受"事件时刻拿不到 tier"这一约束**（1-F 卡住的地方） |
| **每位数** | 每个位只记**首次**被扫荡 |
| **定位** | 纯可视化：不改状态机、不作门槛 —— 他明确 *"The sweep itself is not the confirmation."* |
| 指纹 / CSV | `needDraw` 已同步 `nSWEEP`；CSV 扩为 **4 路时间归并**（MSS/BOS/CISD/SWEEP）；新增 `# sweep levels=intermediate(tier-1) firstOnly=true` 自描述头行 |

### 14.2 验收

- 事件 **50 条** = 15 MSS + 9 BOS + 18 CISD + **8 SWEEP**；
- **MSS / BOS / CISD 三条计数完全未变** ✓ —— 后验扫描不碰状态机；
- `chartObjs` **59 → 69（+10）**；
- 8 条 `SWEEP event` 日志 + 橙色点线标注，人工确认。

### 14.3 数据里出现了一个真实的流动性簇（正面印证）

8 条 SWEEP 中有 **两条水平位完全相同**：

```
UP sweep=2026.09.22 11:00  level=1.14543  位源=2026.09.17 00:00
UP sweep=2026.09.22 11:00  level=1.14543  位源=2026.09.18 15:00
```

即**两个 intermediate 低点处于同一价格（等低点）**，并在**同一根 K 线**上被一起扫掉 ——
正是他 relevant-swings 一文描述的形态：*"if price forms a low just above equal lows…
**Liquidity is still resting beyond it**"*。检测器自己找出了这个簇，是一次正面印证。

### 14.4 顺带为 §13.3 的判断提供了直接证据

**intermediate 位确实会被反复扫荡**（8 次），而 MSS 锚点 0/15 是 intermediate。
这从数据上支持了 §13.3 的重读：**intermediate 点是"被扫荡的流动性目标"，
而不是"protected swing 本身"** —— 即 1-F 原设计读错了他的句子。
（Stage 5 与 1-F 合并考虑的方向也由此确认。）

归档：`docs/baselines/2026-09-23-stage5-sweep_EURUSD-H1.csv`（50 条）。

---

## 15. 阶段 6 执行结果（HTF 门禁 / L4）

### 15.1 6-a 偏置计算（构建 `v1.48-s6a`）

**规则可机械化**（他 Playbook 原文）：*"If price closes below the previous day's low – Expect
continuation lower. … Same logic applies for previous day's high, but inverted."*

实现：取上一根**已收盘**的 HTF K 线，与它前一根的高低比较 ——
`close > 前根 high → bull`、`close < 前根 low → bear`；落在区间内则**向前回溯**
（上限 `InpBiasLookback=20`）取最近一次决定性收线；回溯不到 → 无偏置。

- `BiasAtTime(t)` 用 `iBarShift(_Symbol, InpBiasTF, t)` + `iClose/iHigh/iLow`；
- `FillEventBias()` **后验**给每条事件写入偏置 → **无需改任何事件创建函数的签名**；
- 验收：事件仍 **50 条**；**`none=0`** 说明 HTF 数据读取正常（不是取不到数据导致的误判）。

### 15.2 对齐率（门禁的过滤力度）

| 事件 | 总数 | 与偏置**对齐** | 逆向 |
|---|---|---|---|
| MSS | 15 | 7（47%） | 8 |
| BOS | 9 | 8（89%） | 1 |
| **CISD** | 18 | **6（33%）** | 12 |
| SWEEP | 8 | 0（0%）※ | 8 |
| **合计** | **50** | **22（44%）** | **28** |

※ SWEEP 的"对齐"概念本身勉强：扫荡是"失败的突破"，方向含义依情况可正可反，此行不宜过度解读。

**CISD 仅 33% 对齐**，直接量化印证他那句 *"if there is no candle 2 or candle 3 closure on
the higher time frame, **it is ignored**"* —— 单周期检出的 CISD 有 2/3 在 HTF 偏置下本该被忽略。
**这是"L4 是 CISD 的前提"那条判断的实测证据。**

**两个交叉筛选**：

- **逆向偏置 + 位移 WEAK（双重不利）= 15 条** —— 正是他说的
  *"A lower time frame 'trend shift' is just a pullback into a discount or premium area on a
  higher time frame."*
- **对齐偏置 + 位移 OK（双重有利）= 7 条**：`MSS DOWN 08.26 15:00`、`CISD DOWN 08.28 16:00`、
  `MSS DOWN 08.28 17:00`、`MSS DOWN 09.01 10:00`、`CISD UP 09.08 04:00`、`CISD DOWN 09.16 11:00`、
  `MSS DOWN 09.22 10:00`。

**50 → 7（14%）** —— 这就是"one-sided HTF bias + 位移确认"那条漏斗的实际收窄幅度。

### 15.3 6-b 门禁生效 + 偏置显示（构建 `v1.48-s6`）

- 四类事件统一 **`dim` = 与 HTF 偏置逆向**；MSS 另叠加原有的位移 `weak` ——
  两者都表示"未获确认"（语义不同：前者位移不够，后者 HTF 不支持），故合并为同一弱化处理；
- 弱化表现：**不注册标签对象**（回收段自动清除）+ `InpColorWeakBreak` 暗色 + `STYLE_DOT`；
- **新增 `Structure_BIAS` 标签**显示当前偏置（`HTF bias BEAR (PERIOD_D1)`），
  锚在 1-C 的 relevance 位之外 0.5×ATR —— 用 relevance 位而非图表可视顶部，
  是为了让 `needDraw` 指纹能覆盖它（`g_curBias` 已加入指纹）。

**验收**：事件仍 **50 条**不变；`chartObjs` **69 → 59（−10）**（灰化事件失去标签，
同时新增 1 个 BIAS 标签）；人工确认偏置标签与灰化效果。

### 15.4 落地情况

| 差异项 | 状态 |
|---|---|
| **D8 HTF 门禁** | ✅ **已实现**（偏置计算 + 门禁生效 + 偏置可视化） |
| 其余 | 见 §10.6 / §11.4 |

归档：`docs/baselines/2026-09-23-stage6-htfgate_EURUSD-H1.csv`（50 条）。

---

## 16. 再次核对：完整一致性矩阵（v1.48-s7）

> 文档收尾（Stage 7）后做的一次全量复核。**方法升级**：不再只靠文字推敲 ——
> 他文章里的配图可直接下载并用图像查看（见 `docs/research/img/`，现共 18 张），
> 歧义处一律优先用配图判别。**本轮核对新增了 5 张之前没看过的图。**

### 16.1 矩阵

| 特性 | 依据 | 类型 | 结论 |
|---|---|---|---|
| swing 三点判定（**左右皆严格**） | `Swing-Point.png`：编号 1-2-3 明确画出"蜡烛 2 的低点低于左右两根"（高点对称） | **配图** | ✅ **一致**（v1.48 的收紧方向被图示直接证实） |
| failure swing 剔除 | `Valid-Seperation.png`：浅蓝矩形高度 = 同类型摆动点间的**价格**距离 | **配图**+文字 | ⚠️ **度量一致；阈值自定**（他明说无数值公式） |
| 默认收盘确认 | *"If the candle cannot close through the level you need, the reversal is not confirmed."* | 文字 | ✅ 一致 |
| 位移三条判据 | *"confirmed by displacement"* / *"The best setups form within one to three candles"* | 文字（**仅定性**） | ⚠️ **口径一致；阈值自定**（配图无数值） |
| **MSS** | `ChangeInTrend-Bearish.png`：趋势变化＝画在 **HL 位上向右延伸的橙线** | **配图**+文字 | ✅ 一致 |
| **BOS** | —— 110 篇仅 1 次并列提及；`BullishTrend-Structure.png`/`BasicUptrend.png` **只标 HH/HL、无 BOS 标记** | **无** | ❌ **无可对标定义**（D11，无法关闭） |
| **CISD** | `CISD-2026-01.png`：线画在**造势序列最旧那根的开盘价**、明显远离极值 | **配图**+文字 | ✅ 一致 |
| **SWEEP** | `B-VS-M.png`：Manipulation 面板＝**影线越过位、收盘收回位内**后反向（同 bar 判定） | **配图**+文字 | ✅ **一致** |
| 摆动分级 tier | `ITM.png`：`STH(2)` 左右各有 short-term high 却标 `STH` → 否证字面读法 | **配图** | ✅ 一致 |
| 3 根 HTF 回看窗口 | `Lookback.png`：画出"当前 HTF K 线 + 前两根"＝3 根；底部给出**周期配对表** `H4/W1、H1/D1、M15/H4、M5/H1、M3/M30、M1/M15` | **配图**+文字 | ✅ 一致（并印证 `H1→PERIOD_D1` 默认正确） |
| HTF 偏置规则 | Playbook：*"closes below the previous day's low → continuation lower"* | 文字 | ✅ 一致 |
| **ref 驱动源** | *"Intermediate-term highs/lows confirm stronger pivots and sweeps (protected swings)."* | 文字 | ❌ **未对齐** —— 仍用 `isMainSwing` 幅度门槛（§13.3 说明为何原方案被推翻） |

### 16.2 本轮核对**新发现的一个缺口**

`Relevant.png` 不只标出 Relevant Swing High/Low 两个点，**还把两者连成一个区间** ——
即他的 **dealing range**。结合他序列的第三步 *"Price retraces into a **premium or discount zone**"*，
说明 **L5 尚未做完**：

- 现状：1-C 只画了 `RELH` / `RELL` **两条水平线**；
- 缺：**区间本身 + 均衡位（EQ，50%）+ premium / discount 分区标注**。

这属于纯可视化补充（不涉及判定），可在需要时按同样纪律补上（先算后画 + CSV 自证）。

### 16.3 核对结论

- **可直接对标且已一致**：swing 定义、收盘确认、MSS、CISD、SWEEP、tier、3 根 HTF 回看、HTF 偏置规则；
- **口径一致但数值自定**（他无一手数值）：failure swing 的 separation、位移三条阈值；
- **无法对标**：`BOS`（他无定义）；
- **明确未对齐**：`ref` 驱动源（幅度门槛 vs 他的层级）；
- **未实现**：dealing range / EQ / premium-discount 可视化。

**没有任何一项是"口径不一致却当作一致"** —— 上面每一处偏离都在代码注释、
CSV 头部与文档里显式标注。

---

## 17. 阶段 8：dealing range / EQ（补齐 §16.2 的缺口）

### 17.1 依据

`Relevant.png` 显示他把 relevant high/low **连成一个区间**（dealing range）；他序列第三步
*"Price retraces into a **premium or discount zone**, giving the best entry"* ——
premium / discount 即该区间的上 / 下半，分界是 50% 均衡位（EQ）。

### 17.2 实现（构建 `v1.48-s8`）

| 元素 | 对象 ID | 说明 |
|---|---|---|
| 区间矩形 | `Structure_RANGE` | 从 `g_relT1`（3 根 HTF K 线窗口起点）到最新 bar，高度 = `g_relHigh .. g_relLow` |
| 均衡位 | `Structure_EQ` | 区间 50%，黄色虚线 |
| 分区标签 | `PremLbl` / `DiscLbl` | 区间内上 / 下各 8% 处标 `PREMIUM` / `DISCOUNT` |

- 与 relevance 两条线**同源同分支**（都基于 `g_relHigh`/`g_relLow`、同在 `g_relValid` 内）
  → 不会出现"线在而区间不在"的半截状态；
- 全部 `AddSceneName` 注册；`needDraw` 指纹**无需新增项**（`g_relHigh`/`g_relLow` 本就在指纹中）；
- **纯可视化，不参与任何判定**。

### 17.3 验收

事件仍 **50 条**不变；`chartObjs` **59 → 63（+4）**，与事前预测一致；人工确认区间与 EQ 位置。

### 17.4 附：用 Trading Hub 3.0 核对 BOS 的尝试（**未成，已按用户决定搁置**）

用户曾提议改用 **Trading Hub 3.0** 的定义来核对 `BOS`。实际核查过程：

- Trading Hub 3.0 是 TradingView 上 `fx_juka` 发布的 **PROTECTED SOURCE（受保护源码）** 第三方指标，
  **并非 TTrades 的材料**；
- **TradingView 拒绝抓取**（多个地区域名均 `fetch failed`）；
- 以中 / 英 / 越三种表述检索（`BOS CHOCH 区别 定义 用法`、`IDM BOS CHoCH rules` 等），
  仅能得到它的**列表页**与他人**仿制脚本**，**没有任何一处给出其 BOS 判据**；
  唯一像说明文档的是一个越南语 PDF 翻页器，**正文取不到**。

→ **无法取得一手依据**。按本项目一贯的证据标准（§12 起的核对一律要求一手来源），
**不采用二手转述去核对 BOS**。

**用户决定：暂不核对，保留现状。** 故差异清单 **D11（BOS 无可对标定义）维持未关闭**，
`CONTEXT.md` / `README.md` 中"BOS 是行业通行读法、无法声称与 TTrades 一致"的标注继续有效。

归档：`docs/baselines/2026-09-23-stage8-dealingrange_EURUSD-H1.csv`（50 条）。

---

## 18. 阶段 9：PD Array（FVG + OB）

**用户需求**：「还需要在指标上增加 PD Array 即 FVG、OB。你查一下 TTrades 对它们的定义，然后实现到本指标。」

### 18.1 取证结果

完整的一手定义、逐字引文与配图索引写在
`docs/research/2026-09-23-TTrades-structure.md` **§11**（新增）。
决定性结论有三条：

1. **FVG 用影线，OB 用实体** —— 这不是取舍，是他两篇不同文章里的明文：
   FVG *"the high/low of the candle(1) does not overlap the low/high of candle(3)"*；
   OB *"Bodies matter more than wicks."*
   → 若两者都用实体或都用影线，必错一个。
2. **OB 的关键价位 = 造势序列最旧一根的开盘价**（*"The opening price of the candle is often
   the most important reference."*），**并且** OB 的验证动作（*"closes back below those candles"*）
   与我们阶段 4 的 **CISD 触发是同一个动作**。
   → **OB 不需要独立的检测逻辑**，直接由 CISD 运行态派生，只多输出一个「实体区间」。
   这也解释了他配图里 OB 为什么画成**一条线**（那条线就是 CISD 位）。
3. **PD Array 不参与判定** —— *"A Point of Interest Doesn't Mean an Entry."*
   → 实现为纯可视化层，与 SWEEP / dealing range 同级。

### 18.2 实现（构建 `v1.49-s9`）

| 元素 | 口径 | 对象 ID |
|---|---|---|
| **FVG** | 有效 bar 序列上取 `c1 = validBars[k-2]`、`c3 = 当前`；**看跌（SIBI）`low[c1] > high[c3]` → `[high[c3], low[c1]]`，看涨（BISI）`high[c1] < low[c3]` → `[high[c1], low[c3]]`**（**影线对影线**）。⚠️ 方向映射在 v1.49-s9a 修正过，此处为**修正后**版本，推导见 §18.5 | `FVG_{c1}_{c3}` 矩形 |
| **CE** | `(zoneLo + zoneHi) / 2`，点线 | `FVGCE_{c1}_{c3}` |
| **FVG 标签** | 仅类型名 `FVG`（遵循 §11.5「只标记、不标价格」的既定约定） | `FVGLbl_{c1}_{c3}` |
| **OB** | 复用 CISD 的造势序列：区间 = `[runOldest, extremeBar]` 各根 **实体**的并集 | `OB_{runOldest}_{breakBar}` 矩形 |
| **OB 标签** | 仅 `OB`；看跌放区间上沿之上，看涨放之下 | `OBLbl_{runOldest}_{breakBar}` |

**代码落点**（全部为增量，未改动任何既有判定）：

- `CisdOriginBar()` **新增**，`CisdOriginOpen()` 退化为对它的取值 —— 消除「找最旧一根」
  与「取其开盘价」的重复实现，保证 CISD 位与 OB 区间永远同源；
- `SState` 增 `cisdHighRunBar` / `cisdLowRunBar`，在 `CisdSetLevel()` 内写入；
- `CheckCisd()` 在原有 `AddCisdResult()` 后**追加** `AddObFromRun()`（同一次触发）；
- `CheckFvg()` 在主循环 `CheckCisd` 之后调用，位于 `if(k < 1 || k >= nValid-1) continue;`
  **之前**（最新有效 bar 上刚形成的缺口也应记录）；
- `FillEventBias()` 扩到 fvg/ob —— 与 HTF 偏置逆向的 POI 沿用既有的**弱化约定**
  （暗色 + 无标签）；
- `needDraw` 指纹增 `nFVG` / `nOB` 两项；
- CSV 新增 4 列 `zoneLo,zoneHi,fillPct,state`，并将 FVG / OB 并入同一归并循环。

### 18.3 本轮**自定**的口径（必须与他的原话区分）

他给出的都是**定性**描述，以下**六处**是本实现自己定的，`CONTEXT.md` 与 CSV 头均已标注：

| # | 自定点 | 取值 | 理由 / 如何改回 |
|---|---|---|---|
| 1 | FVG 基于**有效 bar 序列**而非物理相邻三根 | `basis=validbars` | ⚠️ **见下方「§18.3-a 关于第 1 条的重要更正」** —— 这不是"加了个过滤"，而是**改了哪三根构成形态**。<br>**用户裁定（2026-09-23）：保持现状。** |
| 2 | OB 区间取**整串实体的并集** | 见上表 | 他说 "the series of up close candles"（一串）但配图只画了一条线。区间是推断 |
| 3 | FVG 失效以 **`ceBroken`（收盘穿 CE）** 为准 | `state=CE-BROKEN` | 他给了「收盘穿 CE」**或**「完全穿越」两条并列条件且未说明关系；两条都算并分别导出，渲染以 CE 为准。⚠️ 副作用：`fillPct≥1.0 && !ceBroken` 的 2 条在关掉 `InpFvgHideFilled` 时会以**满亮**绘制，看上去"未失效" |
| 4 | 「第一个 POI」优先级（FVG → swing → CISD）**不实现** | — | 他未给机械判定规则（按时间？按距离？），只做展示。**真正的阻塞点是 §19.4-I：我们的 protected swing 定义与他的不符，即使他给出规则也实现不了** |
| 5 | `InpMaxEvents` 复用为 PD Array 显示条数上限 | 6 | 不新增输入项，避免输入面板膨胀 |
| 6 | **`InpFvgHideFilled` 默认 `true`（完全回补的缺口不画）** | `true` | ⚠️ **他无此依据，且与 `FVG-Inversion.png` 冲突**（失效缺口仍可作反向位 IFVG）。实测 **67/79（85%）** 的 FVG 被默认隐藏；叠加 `InpMaxEvents=6`，**出厂最多只显示检出量的约 7.6%**。这是本阶段影响观感最大的一处自定。**用户裁定（2026-09-23）：保持现状。** |

#### 18.3-a 关于第 1 条的重要更正（独立审计提出，经复核成立）

原表述把"改用有效 bar 序列"的理由写成"否则会产出大量 1-tick 级假缺口"。
**这个理由只支持「在物理相邻三根上加一个最小尺寸过滤」，不支持「重新定义哪三根构成形态」**——
实现做的是后者，语义改动严格大于所述理由。

实测偏离幅度（`refBar - breakBar` 即 c1 与 c3 相隔的物理根数）：

| | 数量 | 占总数 |
|---|---|---|
| c1–c3 物理相邻（真三 K 形态） | 61 | 77% |
| **c1–c3 相隔 3–23 根** | **18** | **23%** |

极端例：相隔 23 根→区间 14.1 pip，相隔 19 根→区间 16.4 pip。
对这 18 个缺口，**CE（他明文标注的 `Entry 0.5` 入场位）不是他的 CE**。

两种误差都存在，且方向相反：

- **虚增**：母线 V0、V1、V2（中间夹内包 K）时，在 V2 处 `c1 = validBars[k-2] = V0`，
  用的是 V0 而非物理上的 candle 1；
- **漏检**：物理三根 (X, Y, Z)，Y 是 X 的内包 K（已被剔除），Z 相对 X 跳空且 `high[X] < low[Z]`；
  此时 validBars 里 X、Z 相邻 → `k = 1` → `CheckFvg` 的 `k < 2` 直接返回 → **合法缺口消失**。

→ **正确做法应为**：`c1 = c3 + 2`、`c2 = c3 + 1`（物理相邻），再叠加一个最小缺口尺寸阈值
来滤掉 1-tick 噪声。是否切换属**语义决策**（会改变 FVG 集合），已提交用户裁定。


### 18.4 验收（已测）

归档：`docs/baselines/2026-09-23-stage9-pdarray_EURUSD-H1.csv`
（**147** 条 = 50 旧 + 79 FVG + 18 OB，`rates=16857`）。

> ⚠️ **归档与源码已脱钩（独立审计指出，成立）**：该 CSV 是 `build=v1.49-s9c` 导出的，
> 而源码此后又走过 s9d（EQ 默认关）/ s9e（D14）/ s9f（审计修复），其中 **s9e 与 s9f 会改动
> OB 行的 `displacement` / `state` / `tier` 列**。故下表与 §19 的验收数字**只对 s9c 成立**，
> 不能作为当前构建的证据。**待定稿后必须重导 + 重归档 + 重跑不变量。**

| 判据 | 结果 |
|---|---|
| 旧 50 条事件**逐字段不变** | ✅ `seq` 除外（新事件插入导致重编号）；`breakBar`/`refBar` 两列**恒 +1**（窗口平移一格，非差异）；**其余 8 列 0 差异** |
| 更强的一次：跨新 bar 的**时间戳集合**比对 | ✅ 0 增 0 删（期间长出一根新 H1，整个分析窗口平移一格，仍然全等） |
| OB 条数 == CISD 条数 | ✅ 18 == 18，一次触发恰好派生一个，无一被拒 |
| OB 关键价位落在实体边界上 | ✅ 18/18：`dir=DOWN` 时 `zoneLo == refPrice`，`dir=UP` 时 `zoneHi == refPrice` |
| FVG `CE == (zoneLo+zoneHi)/2` | ✅ 79/79（差值恒为 5e-6 = `_Digits` 五位的半个最小刻度，纯显示取整） |
| FVG `CE-BROKEN ⇒ fillPct ≥ 0.5` | ✅ 0 违例（收盘穿过中点必然使影线深入过半，这条是逻辑自洽的硬约束） |
| 渲染改动不影响计算 | ✅ s9b/s9c/s9d 三版只动渲染，CSV 始终一致 |

FVG 状态分布（当前为下跌窗口）：`DOWN` 37 CE-BROKEN / 2 FILLED / 12 OPEN，`UP` 28 CE-BROKEN。
**不对称是行情造成的**：前 20 个 FVG 的 CE 均值 1.16252 → 后 20 个 1.14669（跌 158 点），
BOS/DOWN=8 : BOS/UP=1。下跌中需求侧（UP）缺口被逐个回落填掉，供给侧（DOWN）悬在上方不被触碰。

### 18.5 ⚠️ 阶段 9 的 bug 复盘：方向写反，而**等式自检抓不到**

`v1.49-s9` 初版把 `CheckFvg` 两个分支的 `dir` 写反（区间 `zLo/zHi` 是对的）。后果不是报错，
而是每个缺口都被套用**反方向**的回补判据 —— 而价格本来就在区间另一侧，判据立刻成立，
于是 **80/80 全部瞬间"已回补 + 已穿 CE"**，80 个 FVG 变成 80 个废数据。

**为什么我的第一轮自检没抓到**：当时验证的是 `CE == (zLo+zoneHi)/2`。这个等式在方向反了时
**依然成立** —— 它只约束区间与中点的关系，不约束方向。

**抓到它的是分布**：80/80 这个数字本身不像真的。

**正确的依据根本不需要测量**（已写入 `CONTEXT.md` v1.49 硬约定第 5 条）：`c1` 更旧、`c3` 更新，故
- `high[c1] < low[c3]` ⇒ `zHi = low[c3]`，而 `close[c3] >= low[c3]` **恒成立**
  ⇒ 确认那一刻价格必在区间上沿之上 ⇒ 只能是**看涨** `DIR_UP`；
- `low[c1] > high[c3]` ⇒ `zLo = high[c3]`，而 `close[c3] <= high[c3]` **恒成立**
  ⇒ 只能是**看跌** `DIR_DOWN`。

**方法论**：不变量分两类 —— 约束**内部一致性**的等式（方向反了照样成立），与约束**取值分布**的
统计特征（方向反了会立刻暴露）。新功能验收时**两类都要过**，不能只验等式。

---

## 19. 第三次核对：v1.49-s9d 一致性矩阵（含 PD Array）

> 用户要求：「然后再核对下指标是否符合 TTrades 的定义」。
> 证据标准与 §12 / §16 一致：**只认一手文章逐字引文与他自己发布的配图**。

### 19.1 本轮新增的三种核对手段

前两轮核对靠"读文字 + 看图"，本轮补上可机械执行的三条，避免自我确认：

1. **不变量核对**：对 CSV 逐行验证**可推导的恒等式**（见 §18.4）。它们是代码之外的独立约束。
2. **输入项可达性扫描**：用正则扫出全部 `input` 声明，再统计每个名字在全文中的出现次数 ——
   **只出现 1 次（即只在声明处）就是哑输入**。本轮扫出 3 个（见 D16）。
3. **事件集合的时间戳比对**：跨新 bar（分析窗口整体平移一格）比较事件集合，比逐行 diff 更强 ——
   逐行 diff 会被 bar 下标平移干扰，时间戳不会。

### 19.2 PD Array 一致性（阶段 9 新增部分）

| 特性 | 依据 | 类型 | 结论 |
|---|---|---|---|
| FVG = 三根 K 线、**影线对影线** | *"the high/low of the candle(1) does not overlap the low/high of candle(3)"* + `FVG-3candle.png`（两条水平线正画在第 1 根的低与第 3 根的高） | 逐字 + **配图** | ✅ **一致** |
| CE = 缺口中点 | *"The midpoint of a fair value gap is called the consequent encroachment."* + `FVG-CE.png` 直接标 `Entry 0.5` | 逐字 + **配图** | ✅ **一致** |
| FVG 失效判据 | *"closes through the consequent encroachment **or** closes fully through the fair value gap"* | 逐字 | ⚠️ **单方面择一**（我们以 `ceBroken` 为准）。两条都算并分别导出，详见 §18.3 第 3 条 |
| OB = **实体**区间 | *"Bodies matter more than wicks."* | 逐字 | ✅ **一致**（区间取整串实体并集属推断，见 §18.3 第 2 条） |
| OB 关键价位 = 造势序列**最旧一根开盘价** | *"The opening price of the candle is often the most important reference."* | 逐字 | ✅ **一致，且有独立数值印证**：18/18 该价位精确落在实体区间边界上 |
| OB 验证动作 = 同一次 CISD 触发 | *"When price closes back below those candles, that area becomes a validated order block."* | 逐字 | ✅ **一致**：实测 OB 18 条与 CISD 18 条一一对应（`breakBar` 可 join，0 失配） |
| PD Array **不参与判定** | *"A Point of Interest Doesn't Mean an Entry."* | 逐字 | ✅ **一致**：50 条旧事件跨新 bar 完全不变（0 增 0 删） |
| OB 必须有前置**流动性扫荡** | *"Order blocks **only matter after liquidity is taken**."* | 逐字 | ❌ **未实现**（**D13**） |
| OB 由**位移**验证 | *"**Closure and displacement** are what validate the level."* | 逐字 | ❌ **未实现**（**D14**） |
| FVG 的 IOFED / Inversion（IFVG）用法 | `FVG-CE.png` 的 IOFED 面板、`FVG-Inversion.png`（失效后仍可反转使用） | **配图** | ⚠️ **部分**：失效后仍画（变暗），但未标反转位 |
| POI 优先级（FVG → swing → CISD） | `the-only-points-of-interest...` 一文 | 逐字 | ⚠️ **未实现**（他未给机械判定规则，只做展示，见 §18.3 第 4 条） |
| FVG 三根必须**物理相邻** | 原文只说 *"three candlestick pattern"*，未限定"相邻" | 逐字（**模糊**） | ⚠️ **自定近似**：我们取有效 bar 序列（内包 K 线已剔除），见 §18.3 第 1 条 |
| 完全回补后是否还画 | `FVG-Inversion.png` 说明失效缺口仍可作反向位 | **配图** | ⚠️ **有冲突**：`InpFvgHideFilled` 默认隐藏完全回补的缺口。他的体系里它仍有 IFVG 用途 |

### 19.3 旧元素回归核对（阶段 9 未触碰，逐条复核仍成立）

| 特性 | 结论 |
|---|---|
| swing 三点（左右皆严格） | ✅ 一致（`Swing-Point.png`） |
| 默认收盘确认 | ✅ 一致 |
| 位移三条判据 | ⚠️ 口径一致、**阈值自定**（他无数值） |
| MSS 定义 | ⚠️ **部分** —— 定义句一致，但**弱破位仍驱动状态机**（**D12**） |
| CISD 定义 | ✅ 一致（`CISD-2026-01.png`） |
| SWEEP 定义 | ✅ 一致（`B-VS-M.png`）；但**只覆盖 tier-1 位**，导致 D13 无法判定 |
| 摆动分级 tier | ✅ 一致（`ITM.png`） |
| 3 根 HTF 回看窗口 | ✅ 一致（`Lookback.png`） |
| **BOS** | ❌ **无可对标定义（D11，未关闭）** |
| ref 驱动源 | ❌ **未对齐**（D17） |

### 19.4 本轮新发现的差异（按严重度）

**D12（严重）· 位移不足的破位仍然翻转趋势状态机 —— ✅ 已修复（v1.49-s9g，用户裁定「就地修复」）**

他的定义：*"MSS marks a trend change **confirmed by displacement**."*
实测：15 条 MSS 中 **7 条为 WEAK**（未过位移门槛）。
但 `strong` 只被用于**记录** —— `CheckBreakAgainstRefs` 在 `st.state = ST_DOWN` 处**无条件**赋值，不看 `strong`。

**后果**：受保护摆动点（protected high/low）的重设、后续 BOS/MSS 的归属、结构段的划分，
全都建立在被他体系拒绝的破位之上。G1 决策只弱化了**渲染**，没有触及**状态机**。

**修复实现**：新增 `ApplyMssTransition()`，四处 MSS 调用点全部改为经由它。语义：

| 情形 | 记录事件 | 标记该位已破 | 翻转趋势 / 重置对侧 ref | 返回值 |
|---|---|---|---|---|
| 位移**达标** | ✅ | ✅ | ✅ | `1` |
| 位移**不足** | ✅（保留，按 G1 弱化渲染、不给标签，便于事后核对） | ✅（**必须**，否则同一个位会在后续每根 bar 反复触发） | ❌ **不翻转** | `0` |

返回值用于调用方的 `mssBar` 门控 —— 该门控抑制"同一根 bar 上用本 bar 的 swing 重建反向 ref"，
**趋势没变时不应抑制**，故弱 MSS 必须返回 0。

**三条设计后果（必须写明）**：

1. **弱破位会"消耗掉"该 ref**。位移只在**破位那根 bar**判定，不做事后重评；
   若该 bar 位移不足，这个位就再也不会触发 MSS。
   —— 这不是死路：`UpdateRefsFromSwing` 会在下一个主结构 swing 确认时设出**新的** ref
   （`broken=false`），机制自然自愈。
2. **"后来才出现位移"的情形由 CISD 层覆盖**。他体系里 CISD 本就是"更早/更灵敏的收盘确认工具"，
   与我们这条"MSS 只看破位那一刻的位移"形成分工，不构成漏检。
3. **本次改动会改变事件集合**（这是 D12 的性质决定的，不是回归）：
   弱 MSS 不再翻转状态 → 其后的 ref 重设、BOS/MSS 归属、结构段划分全部随之变化。
   **`docs/baselines/` 下全部基线就此失效**，必须重测重归档。

**验收预测**：MSS 条数**大概率下降**（弱 MSS 不再引入由它派生的后续结构），
且剩余 MSS 的 `displacement` 列应**全部为 `OK`**（弱的那 7 条要么消失、要么仍被记录但不再引发翻转）。
后者是本次修复**最直接的判据** —— 若仍有 `MSS/…WEAK` 存在但**其后的结构却表现出趋势已翻转**，
说明修复没生效。


**D13（严重）· OB 缺少「流动性已被取走」前置**

他的原文：*"Order blocks **only matter after liquidity is taken**."*
实测：18 个 OB 中仅 **3 个（17%）** 在其极值 bar 处存在 SWEEP。
**但**这个 17% 只是**下界**，不能据此断言"其余 15 个确实没有扫荡"——
因为 `ComputeSweeps` **只处理 tier-1（intermediate）节点**（源码 line 1687），
短周期节点的扫荡根本不记录。即：我们**既没有实现这个前置条件，也没有能力度量它**。

**D14（中）· OB 丢弃位移判据 —— ✅ 已修复（v1.49-s9e）**

他的原文：*"Closure and displacement are what validate the level."*
`AddObResult` 原先把 `weak` / `bodyATR` / `penATR` 写死为 `false` / `0` / `0`，
没有接收 `CheckCisd` 已经算出的 `strong`。所以"由强位移验证的 OB"与"由弱收盘验证的 OB"
在渲染与导出上完全无法区分 —— 等于丢掉了**他用来定义 OB 有效性的两个条件之一**。

**修复内容**（三处透传 + 两处体现）：

| 位置 | 改动 |
|---|---|
| `AddObFromRun(...)` | 新增 `const bool strong` 形参 |
| `AddObResult(...)` | 新增 `const bool strong`；写 `weak = !strong`、`bodyATR/penATR = g_lastBodyATR/g_lastPenATR` |
| `CheckCisd` 两处调用 | 传入紧邻 `DisplacedBeyond()` 得到的 `strong` |
| `DumpEvents` 归并分支 | OB 分支填 `weakE/bodyE/penE`；`displacement` 列的适用类型由 `MSS|CISD` 扩为 `MSS|CISD|OB` |
| `RenderScene` OB 块 | `dimO` 增 `|| g_result.ob[k].weak`（暗色，**标签保留**） |
| 调试输出 | OB 的 `Print` 增 `bodyATR/penATR/OK|WEAK` |

⚠️ **本修复只做「如实记录与区分」，不加门控** —— 位移不足的 OB 仍被记录与绘制，只是标记为弱。
是否把位移升级为 OB 的**必要条件**（性质同 D13），属另一次需要你定的决策。

**验收预测（可证伪）**：本修复不触碰任何判定路径，故
**只有 OB 那 18 行的 `displacement` 列会从空变为 `body=.. pen=.. OK/WEAK`，
其余 131 行（50 旧事件 + 79 FVG + 18 OB 的其它列）必须逐字不变。**
若旧事件有任何一列变化，即说明改动泄漏到了判定层。

**D15（中）· CISD / OB 的极值锚点可能是「事后被替换掉的 swing」—— ⚠️ 已按审计意见拆分更正**

**本条的初版把 PD 行也算进来了，那是错的**（独立审计指出，复核成立）：
OB 的 `refBar` 是 `runOldest`、FVG 的是 `c1`，**按构造就不是结构锚点**，
所以它们的 `tier` 为空是**必然**，与"节点被替换"无关。

不用测量的判据（审计给出的对照）：锚点**是极值**的行解析成功率高 ——
CISD 15/18、SWEEP 8/8；锚点**是极值以外任意 bar** 的行成功率低 —— OB 5/18、FVG 20/79。

> ✅ **已修复（v1.49-s9f）**：`DumpEvents` 对 FVG/OB 两类行直接输出 `tier = n/a`，
> 不再用一个语义为空的值冒充"无分级"。**`tier` 列现在对 PD 行明确不可读作分级。**

**拆分后仍然成立的子项（仅 MSS）**：15 条 MSS 中 **8 条**的 `refBar` 已不在 `g_result.nodes` 中 ——
MSS 的 ref **确实**是结构点，故这 8 条是".bar 事后被同类更极端的 swing 替换"的真实体现。
成因：`AddNodeFiltered` 替换上一个节点时会改写 `nodes[last].bar`，而 `ref.bar` 记录的仍是旧 bar。
这不是 bug（当时确实有效），但意味着导出的锚点**不是最终确认的结构点**，事后复核会找不到。

**D16（轻，非 TTrades 口径问题，但属对外不一致）· 哑输入与死代码**

输入项可达性扫描结果：**63 个输入中 3 个从未被引用**

| 哑输入 | 声明处的说明 | 实际情况 |
|---|---|---|
| `InpUseOutsideBarLogic` | 外包 K 线单独处理 | 从未实现 |
| `InpDrawSubStructure` | 绘制内部结构（浅色虚线） | 从未实现 |
| `InpColorSubStructure` | 内部结构线颜色 | 从未实现 |

配套死代码：`StructureNode.isMain` **只写不读**（注释称"仅影响线型"，实际无任何渲染分支用它）；
`AddSubNode()` **定义但从未被调用**，`subNodes` / `nSub` 因此恒为空。
`README.md` line 188 对外宣称 `InpDrawSubStructure` 会画"内部结构线" —— **该行为不存在**。

**D17（轻）· MSS 的 ref 从不落在 intermediate 层**

15 条 MSS 的 refBar：`short` 7 条、`<非节点>` 8 条、**`intermediate` 0 条**。
与他 *"Intermediate-term highs/lows confirm stronger pivots and sweeps (protected swings)."*
的说法未对齐（§13.3 已记录成因，此处补充数据）。

### 19.5 核对结论

**PD Array 部分：定义层面高度一致**，`FVG 影线口径 / CE=中点 / OB 实体口径 /
OB 关键价位=造势序列最旧开盘价 / OB 验证=同一次 CISD / POI 不参与判定` 六项全部有逐字或配图依据，
其中"关键价位精确落在实体边界"与"OB↔CISD 一一对应"是**配图之外的独立数值印证**。

**但有三处他的明文要求没有实现**：D13（OB 需前置扫荡）、D14（OB 需位移验证）、
以及「FVG 完全回补后仍可作 IFVG」与 `InpFvgHideFilled=true` 的冲突（D19）。

**旧元素方面本轮新发现 D12**：把"位移"只用在渲染上、没用在状态机上，
是本指标与他体系之间**最大的一处结构性偏差**，且它影响的不只是显示 ——
它影响所有下游结构（protected swing、BOS/MSS 归属、结构段划分）。

**未关闭的历史项**：D11（BOS 无可对标定义）、D17（ref 驱动源）。

### 19.6 独立对抗性审计的补充发现（v1.49-s9f）

> 本节由**独立子代理**（隔离上下文、只读、被要求专门挑我方自我合理化之处）产出，
> 原报告见会话记录。以下每条都经我复核；**审计自己也在过程中被数据否证过两次**
> （它一度推断最大 48.2 pip 的 FVG 是"母亲 bar 伪影"，被 `refBar-breakBar ≤ 4` 否证；
> 一度以为 18/18 的 OB `tier` 为空，实测为 13/18）。
> 把这两条留在文档里，是因为**它自我收窄结论这件事本身就是审计质量的证据**。

| # | 发现 | 严重度 | 处置 |
|---|---|---|---|
| **D18** | **FVG 基准偏离幅度被低估**：实测 **61/79（77%）** 才是真三 K 形态，**18/79（23%）** 的 c1–c3 相隔 **3–23 根**（最远 23 根→14.1 pip）。对这 18 个，**CE 不是他的 CE**。且原给的理由（"否则会产出大量 1-tick 假缺口"）**只支持加尺寸过滤，不支持重新定义哪三根构成形态** | **高** | 已重写 §18.3-a，含虚增/漏检的具体构造；**切换与否提交用户裁定** |
| **D19** | **`InpFvgHideFilled=true` 从未列入自定口径表**，且与 `FVG-Inversion.png`（失效缺口仍可作反向位）冲突。实测 **67/79（85%）** 默认被隐藏；叠加 `InpMaxEvents=6`，**出厂最多显示检出量的约 7.6%** | 中高 | 已补为 §18.3 第 6 条 |
| **D20** | **代码注释与代码矛盾**：`AddObResult` 注释称"区间右端锚定到验证 bar"，渲染实际用 `t2 = time[0]`。后果：早已失效的 OB 也一路画到最右，看起来永远生效 | 中 | ✅ **已修（s9f）**：更正注释，并说明右延伸到最右**恰恰符合** `OB-reversal-pattern.png` / `OB-confirmation.png`（他把 OB 画成向右延伸至现价区域的线）；代价是未跟踪 OB 失效 |
| **D21** | **IOFED / IFVG 不只是"少画一个位"，而是画反了档位**：`ceBroken → dimF` 复用了本库"弱/未确认信号"的颜色语义，而 IOFED 是**失效后反向可用的新位**，被呈现成了降级 | 中 | ✅ **部分已修（s9f）**：停止用 `fvg[].weak` 承载 `ceBroken`（该字段在 MSS/CISD/OB 里意为"位移不足"，混用会把错误的语义固化进数据模型）。**IFVG 位本身仍未实现**，保留为未关闭项 |
| **D22** | **D13 不是"少一个 `if`"，是需要架构改动**：`CheckCisd` 在**主循环内**创建 OB，而 `ComputeSweeps` 跑在**主循环之后**；`g_result.sweep` 在全文件中从未被 OB 读取，且**结构上不可能**被读取 | 中 | 已补进 D13 描述 |
| **D23** | **§11.2 的表格读起来像已遵守**：`docs/research/...md` §11.2 的"对实现的约束"栏写着强读法"OB 必须有前置扫荡；无扫荡的区域不算"，而代码零实现。冲突在**我方文档内部** | 中 | ✅ 已修：该栏改为标注**未实现** |
| **D24** | **`tier` 列对 PD 行语义为空**（见 D15 更正） | 中 | ✅ 已修（s9f）：PD 行输出 `n/a` |
| **D25** | **`state` 列与 D14 自相矛盾**：s9e 已让 OB 携带位移度量，但 `stateStr` 仍无条件写 `VALID`，同一行会同时出现 `displacement="…WEAK"` 与 `state="VALID"`，按 `state` 过滤的下游会误收 | 中 | ✅ **已修（s9f）**：`stateStr = weakE ? "WEAK" : "VALID"` |
| **D26** | **§12.1 的 "MSS ✅ 一致" 从未回收**，而同表最后一行却自认 ref 驱动是唯一不一致处 —— §12.1 是查 MSS 的第一落点 | 中 | ✅ 已修：§12.1 改判 **⚠️ 部分一致** 并加回收声明，指向 D12/D17 |
| **D27** | **最明确的一处过度乐观**：`CONTEXT.md` 断言我们的 `RefPoint` "就是 TTrades 所说的 protected high/low"。他的定义是 *"price reaches an important level and then **closes through the series of candles** into that level"*，且由 **FVG / sweep 形成**；我们的是幅度门槛从 ZigZag 支点里挑的。此前只承认**层级**未对齐，**定义不符**全文未提。这同时是 §18.3-4（POI 未实现）的**真正阻塞点** | 中 | ✅ 已修：`CONTEXT.md` 该词条重写，明确"同名异物"及其两个后果 |
| **D28** | 死字段补充：`fvg[].weak`、`sweep[].weak` 只写不读 | 轻 | `fvg[].weak` 已改为恒定 `false` 并加注释；`sweep[].weak` 恒为 `false`，无害 |
| **D29** | §18.4 数字错误：`50+79+18 = 147` 而非 149；"其余 10 列 0 差异"不成立（`breakBar`/`refBar` 恒 +1） | 轻 | ✅ 已修 |
| **D30** | **"主结构 / 内部结构"不是他的概念**。D16 只说了 `InpDrawSubStructure` / `InpColorSubStructure` 是哑输入、`StructureNode.isMain` 只写不读；但更深的问题是**这套二分法本身没有一手依据** —— 他的层级是 **short / intermediate / long-term**（研究 §4.1），而且那三档是**摆动点上的标签**，不是三条结构线。故此二项**不应"补实现"，而应删除或改造为 tier 分级显示** | 中 | 待裁定（见 §19.7） |

### 19.7 由 D30 引出的一个可选方向：把哑输入改造成 tier 分级显示

`InpDrawSubStructure` / `InpColorSubStructure` 目前什么都不做，且其名义语义（主/内部结构）
**不是 TTrades 的概念**。两条出路：

| 方案 | 内容 | 依据强度 |
|---|---|---|
| **A. 删除** | 移除这两个输入与 `isMain` 死字段，`StructureNode` 只保留 `tier` | —（纯清理） |
| **B. 改造** | 复用这两个输入显示 **tier 分级**：例如 intermediate 级节点用较重的点、short 级用较轻的点（对应 `Short-term.png` / `ITM.png` 的 `STH` / `ITH` 标注方式） | 它本人的配图就是"同一折线上按层级标注点"，**属于他的画法** |

另有一条**尚未实现但他明确给了识别路径**的规则（研究 §4.2）：
> intermediate 有**两种**类型 —— Basic（由 short-term swings 构成）
> 与 **Rebalanced（价格回补了一个 FVG 并离开）**。

我们已有 FVG 检测（阶段 9），故 "Rebalanced intermediate" 是**可机械化的**，
可作为 tier 判定的第二条路径补充进 `ClassifyNodeTiers()`。

---

## 20. 阶段 10：Internal / External Liquidity（IRL / ERL）

**用户选择**：在 §19.7 的三个可选方向里选 **A —— 实现 Internal → External  liquidity 配对**。

### 20.1 依据

研究 §13（来源 <https://ttrades.com/internal-external-liquidity-using-the-ttrades-fractal-model/>，2026-08-22）。
他的定义干净到几乎可直接编码（逐字）：

> "**Internal liquidity is a fair value gap.**" / "**External liquidity is a swing high or swing low.**"
> "**Internal liquidity provides the point of interest. External liquidity provides the target.**"
> "Start with the **higher timeframe bias**."

### 20.2 先做配图判别（本轮关键取舍）

六张配图已下载并逐张查看（研究 §13.1）。结论：他的表达方式**极简** ——
**IRL = FVG 横向色带**（与我们已有的画法完全一致），**ERL = 摆动位处一条短点线**，
**两张图都没有 IRL→ERL 的连接箭头**。

→ 所以阶段 10 **真正新增的只有 ERL 那一条点线**；IRL 就是已有的 FVG 色带。
反过来，若照"关系"二字的直觉去画一条箭头，就是**比原文多做**，会引入他没有的语义。

### 20.3 实现（构建 `v1.49-s10`）

| 元素 | 口径 | 对象 ID |
|---|---|---|
| **ERL** | 偏置方向上、现价之外、**尚未被取走**的**最近**摆动位；点线 + `ERL` 标签（标签置于线中点，`ANCHOR_CENTER`，与 §19 起 BOS/MSS 的约定一致） | `ERL` / `ERLLbl` |
| **IRL** | 偏置方向上、现价之外、**未完全回补**的 **FVG**，取最靠近现价者；只画**靠近现价的那条边** + `IRL` 标签 | `IRL` / `IRLLbl` |

- `ComputeErlIrl()` 排在 `FillEventBias()` **之后**（依赖 `g_curBias` 与 `close[0]`）；
- **纯可视化**：只派生两个价位供渲染，**不参与任何判定**；
- `needDraw` 指纹增 6 项（`erlValid/erlPrice/erlBar`、`irlValid/irlPrice/irlFvgIdx`）——
  价格变了而指纹没变会让图停在旧位置；
- CSV 头部增 `# erlirl ...` 一行，记录口径与当帧取到的值（IRL/ERL 是**逐帧派生量，不是事件**，故不进表格）。

### 20.4 本轮**自定**的口径（他未给机械规则）

| # | 自定点 | 取值 | 说明 |
|---|---|---|---|
| 1 | "最近"按**价格距离**，非时间先后 | — | 他未说明按哪个维度取"最近的流动性" |
| 2 | ERL 排除**已被取走**的位 | 该节点之后有任何 bar 越过它即跳过 | 他："price can **take out** that external liquidity" —— 被取走的不再是目标，应看下一个。**不做这个排除会指向一个已经无效的目标** |
| 3 | 无 HTF 偏置时**不画** | `g_curBias == 0` → 直接返回 | 他的明确前提："Start with the higher timeframe bias."；偏置为 0 时上下两侧都可能是目标 |
| 4 | IRL 要求 `fillPct < 1.0` | 已完全回补的缺口不再是有效 POI | 与阶段 9 的 `ceBroken` 口径**不同**：这里用"完全回补"而非"收盘穿 CE"，因为 POI 的意义是"价格还能回来"，穿 CE 不等于回补完 |
| 5 | **不画连接箭头** | — | 依据见 §20.2 |

### 20.5 验收

- **预期不改变任何事件**：本阶段只在分析后段追加一个只读派生函数，
  且未触碰任何判定路径 → 50/79/18/18 等事件条数与内容应**逐字不变**（除窗口平移的下标偏移）；
- `chartObjs` 应 **+2 或 +4**（有偏置且找到 IRL/ERL 时 +4，只找到其一则 +2，无偏置 +0）；
- CSV 头部出现 `# erlirl` 行，且 `bias=±1` 时 `erlValid=true`。

---

## 21. D31：PREMIUM / DISCOUNT 的分区算法对，但**被对分的那条区间不是他的 dealing range**

### 21.1 问题

用户在 2026-09-23 问「PREMIUM 是什么」。为此取到了他**专讲 dealing range 的一手文章**
（<https://ttrades.com/understanding-dealing-ranges-in-trading-get-better-risk-reward/>，2026-09-19），
此前本项目的来源清单里**没有这一篇**。定义全文见研究 §14。

**分区算法：我们与他一一致**

> "Split the dealing range at 50%. **The upper half is premium. The lower half is discount.
>  EQ sits in the middle.**" + 配图 `DR-premium-discount-eq.png`（上半粉、下半绿、中缝 EQ）

**但区间的两端：我们取错了来源**

> "A dealing range is the range between **the swing point you are trading away from**
>  and **the higher timeframe swing you are trading toward**."

| | 他的 dealing range | 本实现 `RANGE`（阶段 8） |
|---|---|---|
| 上沿 | "the higher timeframe swing high **that made that low**" | `g_relHigh` = 3 根 HTF K 线的最高价 |
| 下沿 | "the low you are **trading away from**" | `g_relLow` = 3 根 HTF K 线的最低价 |
| 方向性 | **有**（bullish / bearish 两套构造） | **无**（一个 min..max 矩形） |

阶段 8 的依据是 `Relevant.png` 把 relevant high/low 连成区间 —— 那**确实**是他的一个概念，
但**不是**这篇 2026-09 文章里定义的 dealing range。两者可能重合，但**不是同一个构造**。

### 21.2 为什么这条值得修

1. 他的用法**依赖方向**：*"For bullish setups, look for longs in discount or around EQ.
   For bearish setups, look for shorts in premium or around EQ."* —— 一个无方向的矩形
   无法表达"这是 bullish range 还是 bearish range"；
2. 他的目标也挂在区间上：*"The dealing range high is **the target** for a bullish range."*
   —— 现版本因此**给不出目标**；
3. 它是**可机械化的**：一端取本图"正在行情的那个 swing"（我们已有 `refHigh`/`refLow`），
   另一端取高周期上"造出它的那个 swing"（我们有 `InpHTFPeriod` 的数据访问与 `iBarShift`）。

### 21.3 另需注意的一条限定（不要把它做成过滤器）

> "The setup can still work from a poor location. The issue is **how much range is left** for the trade."

→ premium/discount 是**剩余空间的度量**，**不是**"只能在此区入场"的过滤器。
若将来做成门禁（像 HTF 偏置那样弱化事件），就**超出了他的原文**。

### 21.4 状态

**未修**。属语义改动（会改变 `RANGE`/`EQ`/`PREMIUM`/`DISCOUNT` 的位置与含义），
且与 §19.6-I（protected swing 定义不符）同源 —— "正在行情的那个 swing"该取哪个点，
又回到 protected swing / ref 的口径问题上。**建议与 I 一起定**，不要单独改。

### 21.5 新的可选方向

`DR-*.png` 与 `ERLIRL-*.png` 都已归档。若要动手，建议顺序：

1. 先定 §19.4-**I**（protected swing 的定义：是"重要位 + 收盘穿串 / 与 FVG、sweep 同源"，
   还是继续用现在的幅度门槛）—— 它同时卡住 D31、D13 与 POI 优先级；
2. 再按 §14.3 的构造法重画 dealing range（bullish/bearish 两套 + 方向性目标）；
3. ERL 是否改为对齐"高周期 swing"目标（§14.4 末段指出的取位差异）。

---

## 22. 阶段 11：protected swing 改用**他的定义**（用户裁定「用他的定义」）

### 22.1 取证（三篇一手文章，表述完全一致）

用户于 §21.5 的第 ① 项选择「用他的定义」。为此重取了他的原文，
发现定义**比我原先引用的那一句更完整**，且**不含任何门槛**：

| 来源 | 逐字 |
|---|---|
| `let-the-wick-form-trade-the-body…`（2026-08-29） | *"A protected swing forms when price reaches an important level and then **closes through the series of candles** into that level. That important level can be a high, low, or fair value gap. **The sweep itself is not the confirmation.**"* |
| 同上 | *"This is the **same change in the state of delivery** used to confirm swing formations."* |
| 同上 | 序列：*"Bearish movement → important level → **bullish change in the state of delivery** → protected swing → expansion higher"* |
| `ttrades-ideal-formation-high-probability-swing-points`（2026-06-27） | *"A protected swing is created when price **closes through the series of opposing candles** that led into a high or low."* |
| 同上 | *"For a bullish setup: Price **sweeps liquidity beneath a low**. Candle 2 or Candle 3 **closes bullish**. The closure **breaks through the series of down-close candles**. A **protected swing low** is established."* |
| `internal-external-liquidity…`（2026-08-22） | LTF 模型三件套：*"a change in the state of delivery, a valid Candle 2 or Candle 3 closure, and a **new protected swing**"* |

**结论**：*"closes through the series of opposing candles that led into a high or low"*
**就是我们的 CISD** —— `cisdLowLevel` 正是"那串阴线最旧一根的开盘价"，收盘穿越即触发，
极值就是 `cisdLowBar`。**CISD 触发的那一刻 = protected swing 成立的那一刻。**

### 22.2 他的定义里**没有**的两样东西（我们此前都有）

| | 归属 | 处置 |
|---|---|---|
| **层级门槛**（short / intermediate / long-term） | `isMainSwing` 无关，但 §13.3 曾计划"ref 改由 intermediate 驱动" | **不加**。"Intermediate-term highs/lows confirm **stronger** pivots" 是**质量分级**，不是成立条件 |
| **幅度门槛**（腿长 ≥1.0×ATR 或 ≥0.382×前段） | `IsMainSwing()` + `InpUseMainFilter` / `InpMainFilterATR` / `InpMainFilterRatio` | **删除**。该门槛**无任何一手依据** |

### 22.3 实现（构建 `v1.49-s11`）

| 改动 | 内容 |
|---|---|
| **新增** `SetProtectedFromCisd(st, isHigh, high, low, extremeBar)` | `refHigh`/`refLow` 的**唯一写入点**（除播种）：锚点 = 造势序列极值 `cisdHighBar`/`cisdLowBar`，价格取 `high[]`/`low[]` 在该 bar 的值，并复位 `broken` |
| `CheckCisd()` 两处触发分支 | 在 `AddCisdResult` / `AddObFromRun` 之后各追加一次调用 |
| **删除** `UpdateRefsFromSwing()` | 其唯一职责是"按幅度门槛维护 ref"，已被取代 |
| **删除** `IsMainSwing()` | 同上 |
| **删除** swing 确认块中的 ref 写入与 `mssBar` 门控 | `mssBar` 防范的是"swing 驱动 ref"；ref 现在只由 `CheckCisd` 写，门控失去对象 |
| `AddNodeFiltered(..., isMain)` 的实参改为常量 `true` | `isMain` 字段仍保留（见 D30 待议项） |
| **删除输入** `InpUseMainFilter` / `InpMainFilterATR` / `InpMainFilterRatio` | 门槛无依据 |
| **删除输入** `InpDrawSubStructure` / `InpColorSubStructure` | 哑输入（从未被引用），且"主/内部结构"不是他的概念（D16 / D30） |
| CSV 头 `mainATR=… mainRatio=… mainFilter=…` → `protectedFrom=CISD` | 归档自描述：口径变了，头部必须跟着变 |
| `CheckBreakAgainstRefs` 的返回值不再被消费 | 保留返回值以备将来使用，但不捕获 |

**顺序语义（必须保持）**：`CheckBreakAgainstRefs` 仍在 `CheckCisd` **之前**调用 ——
同一根 bar 上先判"是否突破了已存在的 protected swing"，再建立"本 bar 新形成的"。
反过来会让同一根 bar 自己破自己。

### 22.4 验收（本轮不能再用"旧事件不变"）

⚠️ 本阶段**就是**要改结构事件的锚点，故 `docs/baselines/` 全部基线失效，
"50 条逐字不变"**不再是有效判据**。替代判据：

| # | 判据 | 期望 |
|---|---|---|
| 1 | `refBar` 必须是**某个 protected swing 的锚点** | MSS/BOS 的 `refBar` 应恒等于某个 `cisdHighBar`/`cisdLowBar`（即 `refBar` 落在 CISD 事件集合内） |
| 2 | ref 更新频率下降 | 旧口径由 ~30 个主结构 swing 驱动；新口径由 18 个 CISD 触发驱动（每侧约 9 次） |
| 3 | 事件条数变化 | MSS/BOS 的条数与内容**预期改变**（这是本次的目的，不是回归） |
| 4 | 与 D12 的叠加 | 弱 MSS 不翻转趋势（s9g）与新 ref 口径叠加后，MSS 条数可能显著减少 |
| 5 | 不变量仍须成立 | OB 价位落在实体边界；OB↔CISD 一一对应；FVG 的 `CE == mid`；`CE-BROKEN ⇒ fillPct ≥ 0.5` |
| 6 | 无残留在日志/CSV 的旧字段 | 头部不应再出现 `mainFilter`；INIT 行应出现 `protectedFrom=CISD` |

---

## 23. 阶段 12：破位确认改为**实体突破**（用户要求）

**用户要求**：「MSS 与 BOS 由结构高点或者低点被 **K 线实体**突破确认」。

### 23.1 如实标注：这比他的字面口径**更严**

他在破位这件事上的原文是：

> *"It happens when price **displaces and closes** above or below a swing high or swing low."*（MSS 定义句）
> *"The key confirmation is displacement that **breaks prior structure**."*

→ **`BREAK_CLOSE`（收盘越过）才是他的字面口径**。用户要求的"实体突破"是其**真子集**。

实现为**三档枚举**而不是布尔量，正是为了让这个区别留在明面上、且可一键切回：

| 取值 | 判据（向上突破为例） | 与他的关系 |
|---|---|---|
| **`BREAK_BODY`**（默认） | `min(open, close) > level` —— 实体两端都在结构位之外 | **比他的原文更严** |
| `BREAK_CLOSE` | `close > level` | **= 他的字面口径** |
| `BREAK_WICK` | `high > level` | 最宽松（旧 `InpCloseConfirm=false`） |

**严格度是全序**：`BODY ⊂ CLOSE ⊂ WICK` —— 能过前者的必然能过后两者，反之不然。
故从 CLOSE 改到 BODY 只会**减少并推迟**事件，不会产生全新事件（这一点让归因变简单）。

### 23.2 实现（构建 `v1.49-s12`）

| 改动 | 内容 |
|---|---|
| 新增 `enum ENUM_BREAK_CONFIRM { BREAK_BODY, BREAK_CLOSE, BREAK_WICK }` | 三档，带输入对话框注释 |
| `input bool InpCloseConfirm` → `input ENUM_BREAK_CONFIRM InpBreakConfirm = BREAK_BODY` | 默认值按用户要求 |
| **删除** `CloseConfirm()`，新增 `EffectiveBreak()` + `BrokeLevel()` | `BrokeLevel()` 是 MSS/BOS **共用**的唯一破位判据 |
| `CheckBreakAgainstRefs` 的 4 处 `upBroken`/`dnBroken` | 全部改为调用 `BrokeLevel()` |
| `StrictICT` 语义澄清为**下限**而非覆盖 | 它把 WICK 提升为 CLOSE，但**不**把 BODY 降级 |
| CSV 头 `closeConfirm=%s` → `breakConfirm=%s`（`EnumToString`） | 三档值直接落进归档，可自描述 |

### 23.3 ⚠️ 一个必须记录的**副作用**：`InpMinDisplacePenATR` 在该档下变为冗余

`BREAK_BODY` 要求 `min(open,close) > level`，故向上突破时
**`close − level ≥ 实体大小`** 恒成立。
而位移判据里那条「收盘穿越深度 ≥ `InpMinDisplacePenATR × ATR`」（默认 0.3）
要求 `close − level ≥ 0.3 × ATR`。

→ 只要实体 ≥ `0.3 × ATR`，这条**自动满足**；而实体若 < `0.3 × ATR`，
另一条「实体 ≥ `InpMinDisplaceBodyATR × ATR`」（默认 1.0）**已经先失败**。
**故在 `BREAK_BODY` 下，`penATR` 这条判据对结果不再有任何影响。**

这不是 bug，但要写明：**该档下真正生效的位移门只是「实体 ≥ 1.0×ATR」+「时效窗口」两条**。
`penATR` 仍逐条写入 CSV 的 `displacement` 列，供对照。

### 23.4 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | CSV 头 | `breakConfirm=BREAK_BODY`；不再出现 `closeConfirm=` |
| 2 | 事件条数 | **减少**（实体越过 ⊂ 收盘越过），且**时点后移或不早于**收盘口径 |
| 3 | 严格度全序检验 | 用 `BREAK_CLOSE` 重导一次，其事件集合应是 `BREAK_BODY` 的**超集**（这是本次改动最强的自检） |
| 4 | 与阶段 11 叠加 | 本次与 §22 的 ref 口径改动同时生效，归因时须分开（按 `refBar` 是否落在 CISD 集合内判断 ref 口径是否生效） |

### 23.5 用户随后放宽：改为 `BREAK_WICK`（`v1.49-s12b`）

**用户要求**：「那放宽要求，影线扫过也算」。

→ 默认改为 `BREAK_WICK`。三档枚举因此完全保留（`BREAK_BODY` / `BREAK_CLOSE` / `BREAK_WICK`），
只是默认值落在最宽松的一档。

**⚠️ 但这一放宽触发了一个必须一起修的连锁问题** —— 否则会**丢信号**：

`BREAK_WICK` 下"影线扫一下"就命中破位条件。原实现（§22.3）在 MSS 路径上
**无条件** `ref.broken = true`。于是：

1. 影线扫过 → 触发 → 位移不足 → 记为弱事件（不翻转趋势）→ **但该位被置 broken**；
2. 价格随后真正收盘/实体突破 → **该位已 broken，不再触发** → **真正的 MSS 永久丢失**。

**修法**：把"记录一次弱触发"与"消耗该位"**拆成两个标记**（`RefPoint`）：

| 标记 | 触发条件 | 作用 |
|---|---|---|
| `touched` | 破了位但**位移不足**（弱触发） | 只允许记录**一次**弱事件，**不消耗该位** |
| `broken` | 破了位**且**位移达标（强触发 = 真正的 MSS） | 该位用完，且翻转趋势 |

`ApplyMssTransition` 相应改为：`!strong && touched → 直接返回 0（静默）`；
`!strong && !touched → 记录 + touched=true + 返回 0`；`strong → 记录 + broken=true + 翻转 + 返回 1`。

**这是对 §22.3 那条"弱破位必须消耗该位"的修正。** 当时的理由
（"否则同一个位会在后续每根 bar 反复触发"）在 `touched` 存在后已不成立 ——
`touched` 精确地防住了重复记录，而不必牺牲该位。

**一处需要知道的不对称**：`touched` **只在 MSS 路径生效**。BOS 没有位移判据
（D11：他从未定义 BOS），故 BOS 在影线触及即成立**并消耗该位**。
在 `BREAK_WICK` 下这最明显：一次扫影线就能产生 BOS 并吃掉一个 protected swing，
而同样的一次扫影线只会在 MSS 路径上留下一个弱事件。**若要对称化，须先有 BOS 的一手定义
（D11 未关闭）**，否则只是把我们的猜测塞进两个地方。

### 23.6 验收（`v1.49-s12b`）

| # | 判据 | 期望 |
|---|---|---|
| 1 | CSV 头 | `breakConfirm=BREAK_WICK` |
| 2 | 事件条数 | **增加**（WICK ⊃ CLOSE ⊃ BODY） |
| 3 | **弱事件不应"吃掉"后续强事件** | 同一 `refBar` 上**允许**出现两条 MSS：一条 `WEAK` + 一条 `OK`（后者才是翻转趋势的那条）。若只出现 WEAK 而后续没有 OK，说明 `touched` 逻辑没生效 |
| 4 | 弱事件不重复 | 同一个 `refBar` 的 `WEAK` MSS **至多一条** |
| 5 | 严格度全序复检 | `BREAK_BODY ⊆ BREAK_CLOSE ⊆ BREAK_WICK` 的事件集合包含关系成立 |

---

## 24. 阶段 12-c：**移除 MSS 的「收盘穿越深度」判据**（用户要求）

**用户要求**：「把 MSS 的这个条件去掉」——指位移判据第②条
（`|close − level| ≥ InpMinDisplacePenATR × ATR`，默认 0.3）。

### 24.1 实现要点

`DisplacedBeyond()` 是 **MSS 与 CISD 共用**的函数，故不能全局删除，改为**按路径开关**：

| 路径 | 新增参数 `usePenCheck` | 生效的判据 |
|---|---|---|
| **MSS**（经 `MSSDisplaced()`） | `false` | ① 实体 + ③ 时效 |
| **CISD**（`CheckCisd` 两处） | `true` | ① + ② + ③ |
| **OB**（由 CISD 派生） | 继承 CISD 的 `strong` | 同上 |

- 参数**不设默认值**，强制两处显式传参 —— 避免"忘了传就悄悄沿用旧行为"；
- **`g_lastPenATR` 仍然照常计算并写入 CSV 的 `pen=` 列**。
  用户要去掉的是**判据**，不是**度量** —— 度量留着才能事后判断"去掉它对结果影响多大"；
- 输入项说明改为「**仅 CISD/OB**」，但**不删除**该项（CISD 仍用它）。

### 24.2 ⚠️ 已知副作用（必须在验收时盯住）

在默认 `BREAK_WICK` 下，② 原本是 **MSS 路径上唯一"必须真的收在位外"的把关**
（见 §23.5 与代码内注释）。移除后：

- **一根影线刺穿结构位、实体够大（≥1.0×ATR）、却收盘收回位内的 K 线，也能判为 `strong`**；
- 而 `strong` 的后果是**翻转趋势 + 消耗该位**（§22.3 / §23.5）。

→ 即 **阶段 2-① 当初专门消除掉的那 7 条"只刺破、从未收在位外"的假破位，会重新出现**，
而且这一次它们不只是显示问题 —— 它们会改变趋势状态与全部下游结构。

**这不是 bug，是本次改动的直接推论。** 若实测发现假破位：
① 恢复 MSS 的②（把 `usePenCheck` 对 MSS 传 `true`），或
② 把 `InpBreakConfirm` 换成 `BREAK_CLOSE` —— 后者在**不引入 ATR 深度阈值**的前提下
恢复"必须收盘越位"，是更贴合他字面口径的折中。

### 24.3 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | MSS 条数 | **增加**（少了一道门槛），且新增的应是 `body` 达标但 `pen` 偏小/为负的那些 |
| 2 | 直接证据 | 新出现的 `MSS/OK` 行里，应能看到 **`pen` 很小甚至为负** 的记录 —— 这正是"判据已移除"的证据。若所有 `OK` 行的 `pen` 仍 ≥0.3，说明改动没生效 |
| 3 | CISD / OB 不受影响 | CISD 与 OB 的条数与 `WEAK/OK` 分布应**逐字不变**（② 对它们仍然生效） |
| 4 | CSV 头 | `dispPen=0.30` 仍在（该项未删除）；`build=v1.49-s12c` |

---

## 25. 阶段 12-d：CISD 的第②条**换成**「后续 N 根内出现同向 FVG」

**用户要求**：「CISD 的这个条件改成 后续 5 根 K 线有出现 FVG 即可」。

### 25.1 为什么必须放在**后验层**（本节的实现要害）

FVG 是在主循环里**随遍历逐 bar 产生**的。某次 CISD 在 bar `i` 触发时，
它**之后**的 N 根 bar 尚未被遍历到，那些 FVG 还不存在。

→ 在主循环内判定这条，**既会读到不完整的数据，也构成未来函数**。
故整条判定独立成后验函数 `ComputeCisdFvgFollow()`，排在 `ComputeStructure` 的最后
（必须在 `ComputeErlIrl` 之后，且此时全部 FVG 已产生）。

**为什么后验改写是安全的**：**CISD 的 `weak` 不参与任何判定** ——
趋势状态机只看 MSS；CISD 的 `weak` 只影响渲染配色与 CSV 记录。
故在此改写它不会引入决策层面的未来函数。
同一次 CISD 派生的 OB（`bar`、`dir` 均相同）沿用同一结论，一并改写。

### 25.2 实现（构建 `v1.49-s12d`）

| 改动 | 内容 |
|---|---|
| **新增** `InpCisdFvgLookahead = 5`（0=关闭） | CISD 需在窗口内出现同向 FVG |
| **新增** `ComputeCisdFvgFollow()` | 遍历 `g_result.cisd[]`，找 `g_result.fvg[]` 中**同向**且确认 bar `fb ∈ [b−N, b]` 者；找不到则 `cisd[].weak = true`，并同步同 `bar`+`dir` 的 `ob[].weak` |
| **删除** `InpMinDisplacePenATR` | MSS 在 s12c 已不用；CISD 在本次换成 FVG 条件 → **已无任何消费者**，留着就是哑输入（D16 教训） |
| **删除** `DisplacedBeyond` 的第②条与 `usePenCheck` 参数 | 两条路径都不再用它；留一个恒为 `false` 的参数等于死参数 |
| `pen` **仍然计算** | 写入 `g_lastPenATR` → CSV 的 `pen=` 列。**删掉的是判据，不是度量** |
| CSV 头 / INIT 行 | `dispPen=%.2f` → `cisdFvgLookahead=%d pen=informational-only` |

### 25.3 本轮**自定**的口径（他未给机械规则）

| # | 自定点 | 取值 | 说明 |
|---|---|---|---|
| 1 | 窗口含**触发 bar 本身** | `[b−N, b]`，N=5 → 共 6 根 | 他的原话是位移 **leaving behind** a fair value gap —— 缺口通常正是这根位移 K 线自己留下的，排除它会让条件几乎永不成立。若严格只要"其后 5 根"，把下界改成 `b-N+1` |
| 2 | 要求**同向** FVG | 看涨 CISD ↔ 看涨 FVG | 位移在方向上留下失衡；允许反向缺口来"确认"语义上讲不通 |
| 3 | 只判**存在**，不判缺口大小/是否已回补 | — | 用户措辞是"有出现 FVG 即可" |

### 25.4 语义方向：**只会更弱，不会更强**

① 实体 与 ③ 时效 **仍是必要条件**，本函数只在"窗口内没找到同向缺口"时补一个 `weak=true`。

→ **`strong` 的集合是原来集合的子集**：CISD 的 `OK` 条数**只可能减少**。
这一条是天然的验收判据（见下）。

### 25.5 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | CISD `OK` 条数 | **减少或持平**，绝不增加（子集性质） |
| 2 | `pen` 与结论解耦的直接证据 | 应能看到 **`pen` 很小甚至为负、但结论仍是 `OK`** 的行 —— 证明 ② 不再参与判定 |
| 3 | 新条件生效的证据 | 应能看到 **`pen` 达标（如 ≥0.3）却被判 `WEAK`** 的行 —— 只有在"窗口内无同向 FVG"时才可能，证明新条件在起作用 |
| 4 | OB 同步 | 每个 `WEAK` CISD 对应的 OB（同 `bar`）也应为 `WEAK`；反之 `OK` 的对应 `OK` |
| 5 | **MSS 完全不受影响** | MSS 条数与 `OK/WEAK` 分布相对 s12c 应**逐字不变**（本次只动 CISD 路径） |
| 6 | CSV 头 | 出现 `cisdFvgLookahead=5 pen=informational-only`；不再出现 `dispPen=` |

---

## 26. 阶段 13：前日高/低（PDH / PDL）

**用户要求**：「再增加一个要求，标记出昨天 1D K 线的最高点和最低点」。

### 26.1 依据（他有一手依据，不是外部概念）

| 来源 | 逐字 |
|---|---|
| `the-easiest-draw-on-liquidity` | *"Failure to displace above **previous day high** suggests a bearish bias toward **previous day low**."* |
| 同上 | *"Price takes out **yesterday's high** but closes back inside the range"* |
| HTF 偏置规则 | *"If price closes below the **previous day's low** – Expect continuation lower."* |

→ 在他的体系里前日高/低是**流动性目标**（draw on liquidity），因此本项与 **ERL** 同族
（都是"目标位"），但**取位来源不同**：ERL 取本图最近的未被取走的摆动位，PDH/PDL 取高周期的日线极值。

### 26.2 实现（构建 `v1.49-s13`）

| 元素 | 口径 | 对象 ID |
|---|---|---|
| **PDH / PDL** | `InpPDPeriod`（默认 `PERIOD_D1`）上**最近一根已收盘** K 线的 high / low | `PDH`/`PDHLbl`、`PDL`/`PDLLbl` |

- 新增 `ComputePrevDay()`，与 `ComputeRelevance()` **并列**挂在全量重算路径上
  （每 tick 三次跨周期 `Copy*` 是浪费 —— 与 relevance 同一理由）；
- 画法沿用既有惯例：自该日 K 线开盘时间向右延伸至最新 bar，点线 + **线中点标签**（`ANCHOR_CENTER`）；
- `needDraw` 指纹增 4 项（`pdValid` / `pdh` / `pdl` / `pdT1`）；
- 新增输入 `InpShowPDHL` / `InpPDPeriod` / `InpColorPDHL`。

### 26.3 ⚠️ 本轮唯一的技术要害：**不能写死 `shift=1`**

"昨天那根 D1"直觉上就是 `CopyHigh(_Symbol, PERIOD_D1, 1, 1, h)` —— 但那是错的：

> **服务器刚换日、当日 K 线尚未生成的那一小段时间里，`shift=0` 才是"最近一根已收盘"。**
> 写死 `shift=1` 会在该窗口里取到**前天**的高/低点。

故实现按**日期**判定：取第一根 open 日期**严格早于**当前服务器日期（`TimeCurrent()`）的 K 线。
副作用是**周末/假日无 K 线时得到"最近一个交易日"** —— 这也正是 ICT 语境下
previous day high/low 的通行含义，故不算偏差。

### 26.4 附带修正的一处陈旧注释

SWEEP 段落原写着「前日/前周高低温属 L4，本轮不纳入」。本阶段后该说法**只对一半**：
前日高低点已经画出来了，但**仍不作为 SWEEP 的取位来源**（SWEEP 只扫本图 intermediate 节点）。
两处注释已改为准确表述 —— 避免留下"文档说没做、其实做了"的不一致。

### 26.5 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | 图上 | 出现两条近白点线 + `PDH`/`PDL` 线中点标签 |
| 2 | **不改变任何事件** | 本阶段只新增跨周期取数与渲染，**事件集合应逐字不变**（MSS/BOS/CISD/SWEEP/FVG/OB 全部） |
| 3 | `chartObjs` | **+4**（两条线 + 两个标签） |
| 4 | 专家日志 | 开启 `InpDebugShowRef` 时出现 `STRUCT_PD tf=PERIOD_D1 shift=… open=… H=… L=…`，其中 `shift` 应通常为 **1**（当日 K 线已生成时） |
| 5 | 数值核对 | 把 `H`/`L` 与该 D1 K 线的实际高低手动比对一次（这是唯一能确认"取对了哪一根"的方式） |

---

## 28. 阶段 15：独立代码评审与修正

**用户要求**：「评审一下指标，哪里还可以优化」。做法：自己读热点路径 + **派独立子代理**
（隔离上下文）按四条轴评审：与自身文档化约定的一致性 / 性能 / 健壮性 / 死代码。

### 28.1 评审结论速览

| 轴 | 结论 |
|---|---|
| **与自身约定一致** | ✅ `\|\|`/`&&` 短路副作用 **零残留**（17 处 `Upsert*` 全部规范）；`ArraySetAsSeries` 齐全；`fill`/`anchor` 都在调和判断内；PD Array 确实只读。**但 `needDraw` 指纹有三处真缺口** |
| **性能** | 一处**必现的每-tick 浪费**（`UpdateLiveLeg` 的死门控）；两处只在全量窗口下可感的 O(n²) |
| **健壮性** | 越界/除零/`Copy*` 失败路径**都覆盖了**，未见可复现崩溃点 |
| **死代码** | 已知三项独立复核**全部成立**，另新查出 4 项。**哑输入只剩 1 个**（已删） |

### 28.2 已修正（构建 `v1.49-s15`）

| # | 问题 | 修正 | 风险 |
|---|---|---|---|
| **1** | **`OnDeinit` 硬编码 `"v1.48"`**，而 `BUILD_TAG` 已到 `v1.49-s14b` —— **最能证明"加载了哪一版"的那行日志一直在报错误版本** | 卸载行与初始化行**都只打印 `BUILD_TAG`**，删掉版本字面量 | 无 |
| **2** | **`g_gfxDirty` 可证冗余**：全文仅 4 处出现（声明 / 复位 / 在紧邻 `changed=true` 处置 true / 读取）⇒ `changed \|\| g_gfxDirty` ≡ `changed`。两处注释也是假的（称"帧内任何写操作会重新置位"，实际无任何 `Upsert*` 置它）。是被否决的"镜像缓存"方案残留 | 删除变量 + 那两处失实注释 | 无 |
| **3** | **`needDraw` 指纹三处缺口**：**(a)** 无"新 bar"项 → 约 11 组以 `time[0]` 为右端的对象在新 bar 上**不延长**（右端滞后约 1 根）；**(b)** `g_relT1`/`g_relT2` 缺席；**(c)** 事件数组**只按条数**取指纹 → "等量换血"不可见，图上留旧事件 | 指纹加 `time[0] != g_lastT0` —— **它同时覆盖 (a) 与 (c)**（事件数组只在全量路径重建，而那条路径由新 bar 触发）；另加 `g_relT1`/`g_relT2` | 低 |
| **4** | 死代码：`AddSubNode()`（**无调用点**）+ `subNodes`/`nSub` + `InpUseOutsideBarLogic`（**唯一哑输入**）+ `g_erlIsHigh` + `InScene()` | 全部删除，并留"为何删"的注释 | 低 |
| **5** | `drawn=%d` 诊断**喂的是 `g_lastNodes`**，而真正为此声明的 `g_drawnFrom` **从未被读取** | 格式改为 `lastNodes=%d … drawnFrom=%s`，`g_drawnFrom` 真正打印出来 | 无 |
| **6** | `STRUCT_ORIENT` 诊断在**快路径 `return` 之前** → `InpDebugShowRef=true` 时**每 tick** 付 2×`TimeToString` + 一次日志写 | 移到快路径之后（每全量帧一次） | 低 |
| **7** | `CONTEXT.md` 的 v1.49 约定列表**有两个 8 号** | 重编号为 8–12 | 无 |

### 28.3 尚未做（已评估，待决定）

| # | 项 | 收益 | 风险 | 说明 |
|---|---|---|---|---|
| **A** | `UpdateLiveLeg`：把 O(lastBar) 重扫改为 **O(1) 增量** | 每 tick 从最多 ~500 次比较降到常数 | **中**（影响 Live 虚线观感，需看图） | ✅ **已完成，见 §28.7** |
| **B** | `ComputeErlIrl` 的 taken 判定改**前缀极值** | 默认窗口可忽略；`InpAnalysisWindow=0` 时约 2.7×10⁷ 次 → 线性 | 低（纯等价） | `taken` 对高点等价于 `max(high[0..nb-1]) > lvl`；两指针按 `nb` 递减即可 O(1) |
| **C** | `ComputeCisdFvgFollow` 的 O(nCISD×nFVG) 改二分 | 仅全量窗口可感 | 低 | FVG 确认 bar 按方向排序后二分定位 `[b-N, b]` |
| **D** | 重初始化不复位运行态（`g_last*` / `g_live*` / `s_lastRates`） | 潜在"改输入后空图" | 低 | ⚠️ **未证实**：无法在本环境确认 MQL5 的 re-init 语义。建议作硬化做，但**不要描述为已确认的 bug** |

### 28.4 评审**拒绝**的两项"优化"（记录以免后人重复提议）

- **`RenderScene` 的 ~20 处 `AddSceneName` + `Upsert*` 样板**、**`DumpEvents` 的 6 路归并 if-链**：
  MQL5 无 lambda，任何抽象都会牺牲类型安全，而**对象命名/注册恰恰是本项目历次 bug 的高发区**。
  改为在 `RenderScene` 开头补一段"新增元素必须同时做哪几件事"的注释即可 —— 真正的成本在那里。
- **不建议**降低 `ComputeSweeps` 的 O(nNodes × window)：其谓词是**同一根 bar 上的合取**
  （`high[i] > lvl && close[i] < lvl`），**无法**降为前缀极值查询。只建议在文档里注明伸缩性。

### 28.5 一条需要"去测"而不是"去改"的前提

文件内两处注释对 **`ObjectGet*` / `ObjectsTotal` 是否 IPC** 的说法**互相矛盾**
（一处称"跨进程"、一处引 MQL5 文档称"直接访问"）。所有"避免 `ObjectGet*`"的性能论证
都以它为前提。**未证实前不应据此重构**。建议验证方式：两版之间对比
`InpReuseResultOnTick=false` 时的 tick 耗时。

### 28.6 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | 事件集合 | **逐字不变**（本批只改日志/指纹/死代码，未触碰判定路径） |
| 2 | `chartObjs` | 可能**连续多帧变化**（指纹修好后右端对象会在新 bar 上延长）—— 属预期修正，不是回归 |
| 3 | 卸载日志 | 重新挂载后出现 `已卸载 \| build=v1.49-s15`（**不再是 `v1.48`**） |
| 4 | 专家日志 | `TradFi_DBG` 行出现 `lastNodes=` 与 `drawnFrom=<时间>`；`STRUCT_ORIENT` 频率由"每 tick"降为"每全量帧" |
| 5 | 输入项数 | 由 **80** 降为 **79**（删了 `InpUseOutsideBarLogic`） |

### 28.7 阶段 15-b：`UpdateLiveLeg` 改为 O(1) 增量（选项 A，已完成）

**构建 `v1.49-s15b`**。这是全程序**唯一**的每-tick 工作量，故单列。

#### 原理（为什么增量是**精确**的，不是近似）

极值窗口 = `[0, lastBar-1]`。它由两部分组成：

1. `bar 1 .. lastBar-1` —— **冻结**（已收盘，不会再变）；
2. `bar 0` —— 当前未收盘 bar，其 **low 在 bar 内单调下降、high 单调上升**。

故只要**节点没变**，窗口极值只可能被 bar 0 刷新 ⇒ 一次比较即可增量更新，
且与全量重扫**严格等价**（重扫循环用的是严格 `<` / `>`，平值不替换；增量同样只在严格越界时替换）。

只有**节点变化**（窗口本身换了）或首帧才需要重扫。

#### 原实现错在哪

门控含合取项 `time[lastBar] == time[0]`，而**该条件永不成立**
（节点只在 `k >= 1 && k <= nValid-2` 的守卫之后加入 ⇒ 节点 bar 必然 ≥ 1）。后果：

- 门控是**死代码**；
- 每 tick 都跑完整 O(lastBar) 重扫（默认窗口最多 ~500 次比较）；
- 注释却写着"连扫描都不做"，**而且理由也写反了**（它称"窗口只在节点之后的 bar 落在当前 bar 上时才变"，
  实际相反：只要 `lastBar >= 1`，窗口**就包含**当前 bar）。

#### 能证伪的自检（本次改动最关键的部分）

"我推理它等价"不等于"它真的等价"。故加入**运行时等价性自检**：
在 `InpDebugShowRef=true` 时，把增量结果与**全量重扫**的结果逐次对照，
不一致则累加 `g_dbgLiveMismatch`，经 `DbgReport` 的 **`liveMiss=`** 字段输出。

> **判据：`liveMiss` 必须恒为 0。**
> 非 0 即说明增量推导有误（例如某品种/周期上 bar 内极值并非单调），
> 应立即回退到慢路径 —— 而不是悄悄画错线。

代价：自检只在调试模式下付（`InpDebugShowRef` 默认 `false`）。

#### 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | `liveMiss` | **恒为 0**（这是本次改动的核心判据） |
| 2 | 事件集合 | **逐字不变**（本次只改实时腿，未触碰判定路径） |
| 3 | 图上 Live 虚线 | 端点与改前一致；只是"每 tick 的计算量"从 O(n) 降到 O(1) |
| 4 | 每-tick 开销 | 在 M1 这类活跃周期上可感（此前每 tick 都要扫一遍窗口） |



---

## 27. 阶段 14：PD Array 填充色改为**按图表底色自动派生**

### 27.1 用户反馈暴露了我的换算模型错误

用户：「OB 改完在白色底的图表看就看不清了」。

**根因**：我在 s12f 把填充色写死为 `轮廓色 × α`。那套换算**隐含"黑底"假设** ——
它等价于"把轮廓色以 α 不透明度叠在**黑**底上"。
在**白底**图表上，正确做法是往**白**混；而"×α"把颜色越压越暗（`C'10,14,26'`），
结果在白底上反而几乎看不见。**方向反了。**

这是我的模型错误，不是 MT5 的问题 —— 但也确实受 MT5 限制：`OBJ_RECTANGLE` 没有 alpha，
"半透明"只能是**预先算好的不透明混色**，所以混色的方向必须与底色一致。

### 27.2 修法：单一百分比 + 按**实际底色**混色

```
fill = 图表底色 + (轮廓色 − 图表底色) × 百分比/100
```

底色经 `ChartGetInteger(0, CHART_COLOR_BACKGROUND)` 读取（**只在 needDraw 帧读一次**，
避免每帧付跨进程调用）。

| 底色 | 结果 | 与旧行为 |
|---|---|---|
| 黑（bg≈0） | `fill ≈ 轮廓色 × pct` | **完全一致，无回归** |
| 白（bg≈255） | `fill ≈ 向白靠拢的浅色调` | 修正方向 |

于是同一个百分比在两种底色下**语义一致**：*"轮廓色以该不透明度叠在你的图表底色上"*。

### 27.3 顺带撤销 s12e 的"弱化不填充"

s12e 之所以让弱化不填充，是因为旧"×α"换算下弱化色 `C'110,110,130'` 的填充
**比正常填充更亮**（均值 117 vs 56/71），与"弱化"语义相反。

现在两者按**同一百分比**混向同一底色，量级相当
（黑底：`(11,11,13)` vs `(0,20,18)`/`(10,14,26)`），**反转问题不复存在**。
故恢复填充，弱化改由**颜色**（灰）区分 —— 语义更干净。

### 27.4 输入项变化

| 删除 | 新增 |
|---|---|
| `InpFillPDArray`、`InpColorFVGFill`、`InpColorOBFill` | `InpPDFillPercent`（**默认 30**，0 = 空心框） |

净减 2 项。`InpColorFVG` / `InpColorOB` 的注释改为"**轮廓色**；填充自动派生"。

**默认值沿革**：10（s14，用户初次指定）→ **30（s14b，用户白底实测后上调）**。
10% 未被推翻为"错误"，只是**在白底上偏淡** —— 百分比是相对底色的量纲，
白底上 10% 的浅色调本就不易辨认。

### 27.5 ⚠️ 需要用户知道的一件事：白底上 10% 本身就极淡

百分比是**相对底色**的量。白底上"轮廓色叠 10%" = 极浅的浅色调
（FVG ≈ `C'230,250,248'`、OB ≈ `C'240,244,255'`）—— **它就该是淡的**。

若用户仍觉得看不清，那是**量纲问题而非故障**，应把 `InpPDFillPercent` 调大：

| 百分比 | 白底上的 FVG 填充 | 白底上的 OB 填充 |
|---|---|---|
| 10% | `C'230,250,248'` | `C'240,244,255'` |
| 25% | `C'191,241,236'` | `C'216,227,255'` |
| 35% | `C'166,236,229'` | `C'201,215,255'` |
| 50% | `C'128,228,218'` | `C'178,198,255'` |

建议白底图表用 **30–40%**。

### 27.6 验收

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | 0 errors（三个旧输入已无任何引用，已 grep 确认） |
| 2 | **不改变任何事件** | 纯渲染改动 → 事件集合逐字不变 |
| 3 | 白底可见性 | OB/FVG 色块从"几乎看不见"变为可辨的浅色调 |
| 4 | 黑底无回归 | 黑底图表上的观感应与 s12f 完全一致 |
| 5 | 弱化有填充 | 弱化 PD Array 恢复为"灰色轮廓 + 灰色调填充"，不再是空心框 |











**审计未能推翻的部分（即它独立复现并确认我方数据的部分）**：
旧 50 条排除 `seq` 与两个 bar 下标列后 0 差异、bar 下标恒 +1；
OB 价位落在实体边界 18/18；OB↔CISD 18↔18；`CE == 中点` 79/79；`CE-BROKEN ⇒ fillPct ≥ 0.5` 零违例；
`sweep` 对 OB 零读取。

---

## 29. 阶段 16：Early CISD / IC-CISD（收盘前的临时 CISD）

**背景（用户裁定）**：对齐付费指标落地页的功能条目
"Auto CISD" 与 "**Early Trend Shift**（Automatically plots CISD **before candle closure**）"。
新的一手依据由本轮调研补齐：`docs/research/2026-09-23-TTFM-rules-report.md` §3。

**他的口径（研究报告 §3 逐字）**：
> "Intra-candle CISD (IC-CISD) … applies the same CISD **inside a single HTF candle** …
> HTF candle opens, trades against the intended direction forming a wick, LTF structure
> trends that opposing way, then an **LTF CISD against that short-term move** marks the
> wick as done → trade the body."
> 指标的 "Early Trend Shift" 开关 = "**live/provisional** CISD evaluated on the unclosed
> candle, **confirmed at close**"。

⚠️ 他同时承认提前确认会出假信号：*"CISD can give earlier entries but sometimes too early,
leading to false signals"*（MSS-vs-CISD 篇，见 research §7）。

### 29.1 为什么这是**纯渲染**改动

IC-CISD 的触发条件与本指标既有的 `CheckCisd()` **完全相同**（`close` 穿越造势序列最旧一根
的开盘价），唯一的差别是**判定所用的"当前价"**：

| | 既有 CISD | IC-CISD（本阶段） |
|---|---|---|
| 判定 bar | 已收盘的 `i`（主循环逐 bar） | 正在形成的 `bar 0` |
| 用的价格 | `close[i]` | `close[0]`（= 最新报价） |
| 对状态机的影响 | **有**：置 `cisdHighFired`、派生 OB、建立 protected swing | **无**。一项都不写 |

> **这是本阶段最重要的一条纪律**：IC-CISD 若也去置 `cisdHighFired`，就等于把
> "未收盘的猜测"写进了趋势状态机 —— 那正是他所说的 "too early, leading to false signals"。
> 故预览**只画线**，一切状态字段保持不动；收盘那一刻由既有的 `CheckCisd()` 照常触发。

### 29.2 生命周期设计（要害）

预览对象必须**只活在当前未收盘 bar 内**，收盘即消失（若真触发，由正式 CISD 线接替）。

- **全量帧（`RenderScene`，每根 bar 一次）**：求值 → 写 `g_ic*` → 进 `needDraw` 指纹 →
  有效则 `AddSceneName` 注册并绘制（进场景集，回收段不会误删）。
- **快路径（每 tick）**：`UpdateEarlyCisdFast()` 只在**状态真的翻转**时碰对象
  （无效→有效 / 有效→无效 / 换边换位），其余 tick **零对象调用**。
  它**不写场景集** —— 下一个全量帧会按当时的真实状态重新注册或回收它。
  > 这不是"靠回收段兜底"的隐式耦合：预览的**唯一权威状态**是全量帧算出的 `g_ic*`，
  > 快路径只是让它在 bar 内实时跟手。

**必须写进 `needDraw` 指纹**：`g_icValid / g_icDir / g_icLevel / g_icRefBar`。
（硬约定 3：新增可视化元素必须同步指纹，否则"要等下一根 bar 才出现"。）

### 29.3 依赖的取数接缝

`st.cisdLowValid/cisdLowFired/cisdLowLevel/cisdLowBar` 是 `ComputeStructure` 内的
**局部状态机**，渲染层看不见。故在 `ComputeStructure` 末尾把
「**武装中且尚未触发**」的位快照到全局（`g_armedCisd*`）：
`g_armedCisdLowValid = st.cisdLowValid && !st.cisdLowFired`。
—— 一旦收盘触发，`cisdLowFired` 置真 → 预览自动失效 → 不必额外清理逻辑。

### 29.4 新增输入

| 参数 | 默认 | 说明 |
|---|---|---|
| `InpShowEarlyCISD` | `true` | 显示 IC-CISD 预览 |
| `InpColorEarlyCISD` | 亮紫 `C'255,138,216'` | 与收盘 CISD 的紫 `C'186,104,200'` 区分 |

### 29.5 验收预测（可证伪）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | **0 errors / 0 warnings** |
| 2 | **事件集合逐字不变** | IC-CISD 是纯渲染 → CSV 的**全部事件行**与 s15b 基线**逐字相同**；只有头部 `build=` 行变化 |
| 3 | 预览只活在未收盘 bar | 预览线的左端 = 造势序列极值 bar，右端 = `time[0]`；**不会**出现在任何已收盘 bar 上 |
| 4 | 收盘后预览消失 | 若真实触发 → 出现正式 `CISD` 标签且预览线消失；若未触发 → 预览线消失、**不产生** CISD 行 |
| 5 | 状态机未被污染 | `displacement` 列（MSS/CISD/OB）逐字不变；`nodes` 计数不变 |
| 6 | 关闭开关无残留 | `InpShowEarlyCISD=false` 时，预览对象被回收（`ObjectFind<0`） |

判据 2 与 5 是**同一件事的两个落点**（一个看 CSV 行、一个看状态字段），
刻意分开写：若预览真的漏进了状态机，通常先在其中一处显形。

---

## 30. 阶段 17：HTF 蜡烛叠加

**背景（用户裁定）**：落地页条目 "**Higher Timeframe Candles** —— View HTF candles on
your entry timeframe"。研究报告 §9 给出他的默认值：**count 默认 4**、另有 Size / Offset /
时间标签等参数。

### 30.1 实现要点

- 取数：`iTime/iOpen/iHigh/iLow/iClose(_Symbol, InpCandleTF, k)`，`k = 0` 为正在形成的那根。
- 时间跨度：`k > 0` 时 `[iTime(k), iTime(k-1))`；`k == 0` 时右端取 `time[0]`（最新图表 bar）。
  —— 不假设周期秒数（D1 有周末缺口，`PeriodSeconds` 会算出比实际更宽的跨度）。
- 每根画 **3 个对象**：实体 `OBJ_RECTANGLE`（左右各内缩 `(100 − width)/2 %`）+ 上下影线各一条
  `OBJ_TREND`。影线两端时间取 `tMid` 与 `tMid + 1s` —— MQL5 的 `OBJ_TREND` **两点不能同时刻**，
  差 1 秒在图上即为竖线。
- ⚠️ **`OBJ_RECTANGLE` 没有透明度**（v1.49-s14 已用编译证实）。故实体填充沿用既有解法：
  `PdFill(轮廓色, 图表底色)` 按 `InpHtfBodyFill` 百分比混色，并保持 `OBJPROP_BACK=true`
  让蜡烛画在 K 线之下。

### 30.2 每 tick 更新的取舍（要害）

正在形成的那根 HTF 蜡烛**每 tick 都在变**。若把它的 OHLC 放进 `needDraw` 指纹，
就会**每 tick 触发整段调和** —— 正是 v1.48 花大力气消除的那个性能陷阱。

故指纹**只含"集合级"信息**：最新 HTF bar 的开盘时间 `g_htfT0` +
**已收盘** HTF 蜡烛的 OHLC 签名 `g_htfSig`。
正在形成的那根由快路径 `UpdateHtfLastFast()` 单独刷新（**缓存比对，未变即零对象调用**）。

### 30.3 新增输入

| 参数 | 默认 | 说明 |
|---|---|---|
| `InpShowHTFCandles` | `true` | 叠加高周期蜡烛 |
| `InpCandleTF` | `PERIOD_H4` | 叠加周期（应 ≥ 图表周期） |
| `InpCandleCount` | `4` | 叠加根数（**他的指标默认 4**） |
| `InpCandleWidthPct` | `70` | 实体宽度占时间跨度的百分比 |
| `InpHtfBodyFill` | `25` | 实体填充强度 %（按底色混色；0 = 空心） |
| `InpColorHtfUp` / `InpColorHtfDn` | 涨绿 / 跌红 | 遵守 TradFi 主题色板 |

### 30.4 验收预测（可证伪）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | **0 errors / 0 warnings** |
| 2 | **事件集合逐字不变** | 纯渲染 → CSV 全部事件行不变 |
| 3 | 对象数 | = `InpCandleCount × 3`（默认 12），对象名前缀 `Structure_HTF_` |
| 4 | 无每 tick 开销 | 未变帧的对象接触数为 0（与既有 needDraw 纪律一致） |
| 5 | 关闭开关无残留 | `InpShowHTFCandles=false` → 全部 `HTF_*` 对象被回收 |
| 6 | 降级安全 | HTF 历史未就绪（`iTime==0`）时**不画**、不报错、不影响其余逻辑 |

---

## 31. 阶段 18 / 19：提前登记的待办（本轮未做）

用户本轮共选 4 项；16 / 17 见上，以下两项已定方案、留待后续轮次：

- **阶段 18 · Candle 2 / Candle 3 closure**：研究报告 §2 已给全机械定义
  （continuation vs reversal closure；C3 = 未扫破前根、收在 C2 实体之外并吞没它；
  C3 的 EQ 上半/下半用法）。
  ⚠️ 他还有一条**门禁级**规则：*"A swing is only valid when it has both: a point of interest
  and a valid closure (candle 2 or candle 3). **If either is missing, the swing point is ignored.**"*
  —— 那会改变**全部下游结构**（同 v1.49-s11 的性质）。故按阶段 3-a 的既有先例分两步：
  **18a 只检测 + 标注 + 进 CSV，不参与判定**；**18b 门禁开关**另开一轮、单独测、单独归档。
- **阶段 19 · Auto Targets / Fibonacci 投影**：研究报告 §7 给出**锚定规则**
  （锚在**操纵腿** = CISD 之前那次扫荡所在的摆动；看跌 high→low、看涨 low→high；
  从 Candle 2 起算；水平为负向扩展 `1, 0, −1, −2, −2.5, −4`）。
  ⚠️ 研究报告同时标注：这个水平表**是它自己的推断**（第二篇原文的水平列表被截断），
  故落地时须按仓库惯例写进 CSV 头部并标为**中介置信度**，不能当逐字口径引用。

---

## 32. 阶段 16 / 17 执行结果（构建 `v1.50-s16`）

**已完成**：编译 `0 errors / 0 warnings`，已部署，仓库与 MT5 副本哈希一致
（`mq5 = DADC6991818A`，`ex5` 见下）。

### 32.1 实现落点清单（按"计算 / 渲染 / 导出"三层列出，遵 D25 的教训）

| 层 | 落点 | 说明 |
|---|---|---|
| 计算 | `ComputeStructure()` 末尾 **新增** `g_armedCisd*` 快照 | 只**读** `st`，不写回。`valid && !fired` 是"预览不会活过收盘"的机制本身 |
| 计算 | `ComputeHtfFingerprint()` | 只读 `iTime/iOpen/iHigh/iLow/iClose`，无状态机接触 |
| 渲染 | `EvalEarlyCisd` / `SyncEarlyCisdObject` / `DeleteEarlyCisdObjects` / `UpdateEarlyCisdFast` | 预览的 4 个函数 |
| 渲染 | `HtfMix` / `ComputeHtfFingerprint` / `DrawHtfCandleGeom` / `DrawHtfCandles` / `UpdateHtfLastFast` | 叠加层的 5 个函数 |
| 渲染 | `RenderScene` 签名 +`close[]`；`needDraw` 指纹 +5 项；`needDraw` 块内 +2 段绘制 | — |
| 快路径 | `OnCalculate` 同 bar 分支 +2 次调用 | 两者都不写场景集 |
| 导出 | `DumpEvents` 头部 +1 行 `# render ...`；`version=` 改 1.50 | **不动任何数据行** |

### 32.2 验收状态

| # | 判据 | 状态 |
|---|---|---|
| 1 | 编译 0 errors / 0 warnings | ✅ **已测**：`0 errors, 0 warnings, 1815 ms` |
| 2 | 事件 CSV 全部数据行逐字不变 | ⏳ **待实测**（原判据的"改前基线"已不可得 —— 见 §32.5，改用**等价性对照**） |
| 3–6 | 预览生命周期 / 收盘消失 / 状态机未污染 / 对象数 / 降级安全 | ⏳ **待实测** |

### 32.3 本轮踩到并已记录的一件事：`.ex5` **不可逐字节复现**

同一份源码连续编译两次，`ex5` 哈希不同（`994E4FE09787` → `AEC4FFC7EEC2`），而 `.mq5` 哈希稳定
（`DADC6991818A` 两次相同）。**推论**：
- `mq5debug.ps1` 的 `VERIFY ex5 match` **只在"编译后紧接部署"的同一次运行内**有意义；
  跨运行拿历史 ex5 哈希做比对会误报"被别的编译器覆盖"。
- 判断"终端到底加载了哪一版"，**唯一可靠依据仍是日志/CSV 里的 `build=`**（这正是 `BUILD_TAG` 存在的理由）。

### 32.4 未做（已按计划留待后续轮次）

阶段 18（Candle 2 / Candle 3 closure，先 18a 只检测不判定）与阶段 19（Auto Targets / Fibonacci 投影）——
方案见 §31，均未开始。

### 32.5 ⚠️ 流程失误与替代验收方案（必须记录）

**失误**：本阶段**先改了代码、后去找改前基线**，违反了阶段 0 立下的纪律
（"改动前先导出事件 CSV，改完逐行 diff 归因"）。后果是硬性的：

1. MT5 里那份 `v1.49-s15b` 的 `.ex5` 已被本次部署**覆盖**，另两个终端目录下也没有副本，
   `Indictor/Structure.mq5` 在 git 里**从未被跟踪**（`??` 未跟踪态），故 s15b 的源码也已不可得。
   → **严格意义上的 s15b A/B 对照已经做不出来了**，这笔账要记在流程上，不是测量结论。
2. 唯一残留的旧导出是 `MQL5\Files\Structure_events_EURUSD.ct_PERIOD_H1.csv`，
   但它的头部是 `build=v1.49-s9c` —— 中间隔着 s11（protected swing 换定义，**全部事件锚点改变**）
   与 s12 系列（破位确认口径变更），**不能当 s15b 的基线**。
3. ⚠️ **后续所有阶段必须在动代码之前先导出基线**。这条本已在阶段 0 写明，本次是我没执行。

**替代验收方案（更强，且只用一个构建）**：把"与旧构建比"换成"**与自身在关闭开关时比**"。

> 同一构建、同一图表、同一组参数，只改这两个开关，各导出一次：
> - **A**：`InpShowEarlyCISD=true`、`InpShowHTFCandles=true`
> - **B**：`InpShowEarlyCISD=false`、`InpShowHTFCandles=false`
>
> **判据：两份 CSV 的 `seq,` 行起全部数据行必须逐字相同**，唯一允许的差异是头部
> `# render icCisd=... htfCandles=...` 那一行。

为什么这比原判据**更针对**本阶段的要害：本阶段唯一的风险就是
"IC-CISD 的预览漏进了状态机"（写 `cisdHighFired` / 派生 OB / 建 protected swing）。
只要发生这种泄漏，A 与 B 的事件集合**必然**不同（泄漏会让 A 多出 CISD/OB 行、并改变其后全部下游结构）。
反过来说，若 A 与 B 逐字相同，就等于**直接证否**了"预览写状态"。
它同时覆盖 HTF 蜡烛叠加（若叠加层意外影响了任何判定，A/B 也会分叉）。

代价：需要你重挂两次（每次改一下开关）。收益：不依赖任何已丢失的历史产物。

### 32.6 验收操作清单（给你的三件事）

1. 重挂 `Structure`（**任意图表**先用 A 组设置跑一次）——
   确认专家日志出现 `build=v1.50-s16`，且**无** `error` / `zero divide` / `array out of range`。
2. **看**：HTF 蜡烛是否按预期叠在 K 线之下（默认 4 根 H4）；出现 CISD 条件时是否出现亮紫
   `IC-CISD` **点线**，且它**只**出现在最右边那根未收盘的 bar 上。
3. **A/B 导出**：`InpDumpEvents=true`，分别在开关全开 / 全关下各重挂一次，
   把 `MQL5\Files\Structure_events_<品种>_<周期>.csv` 两份都留好 —— 我来逐行 diff。

---

## 33. 阶段 18a：Candle 2 / Candle 3 收盘确认（只检测，不判定）

**构建 `v1.50-s18`**。依据：`docs/research/2026-09-23-TTFM-rules-report.md` §2 与
[candle-3-closure 专文](https://ttrades.com/candle-3-closure-a-complete-guide-to-identifying-continuations-and-reversals/)。

> ⚠️ 本节的可证伪预测是**在实现之后、任何测量之前**写下的 —— 仍完全可证伪
> （尚无任何导出数据）。但"先写预测再动手"这条纪律本轮**没有**遵守，与 §32.5 记的是同一笔账。

### 33.1 他的口径（逐字）

- **Candle 编号**：C1 = swing 点**之前**；**C2 = swing 高/低本身**；C3 = C2 之后；C4 = C3 之后。
- **延续收盘**：扫破前根高/低并**收在其外**。
- **反转收盘**：**扫破**前根高/低但**收回前根区间内**。"A Candle 2 closure is **always** a reversal closure."
- **C2 收盘（看涨）**：扫破前根的 **low**，再收回该 low **之上**；看跌镜像。
- **C3 收盘**：*"A candle 3 closure occurs when candle 2 **fails** to give the required closure."*
  *"price does **not** sweep the previous candle, yet candle 3 **closes over the body of candle 2
  and engulfs it**"*；且 *"without sweeping the **candle 2** high or low"*。
- **C3 的均衡位用法**：*"mark the **full range of candle 3**"*，看涨预期 **C4 刺入 C3 上半**。

### 33.2 ⚠️ 一处必须写明的推理：C3 的条件**不能**取"C2 未扫破 C1"

若照字面把 C3 的条件写成"**C2 没有扫破前一根**"，本实现里该分支会是**死代码**：

> 严格三点分形下 swing low at `b` 恒有 `low[b] < low[b+1]`。因为 index 相邻的 bar 不可能"平低"，
> 而内包 K 线**不参与** swing 判定（不会让 `b+1` 变成更低点）。故 `swept` 恒为真
> ⇒ C3 分支永不进入。

他更明确的那一句解决了这个歧义：*"When this happens **without sweeping the candle 2 high or low**,
it becomes a candle 3 closure."* —— 这里的 "the previous candle" 相对 C3 而言就是 **C2**。
故条件取 ① C3 **没有**扫破 **C2 的极值**（`low[b-1] >= low[b]`）；② C3 收在 **C2 实体之外**。
而"C2 未能给出确认"作为**前提**保留（已有 C2-REV 的节点不再判 C3）。

**这样 C3 分支是活的**：当 C2 扫破前根低点、却**收在该低点之下**（延续式收盘，即 C2 未能给出反转确认），
随后 C3 没有扫破 C2 的低点、并收在 C2 实体之上 —— 这正是他描述的"迟到一根的确认"场景。

### 33.3 三种子类型

| `state` 列 | 含义 | 是否"valid closure" |
|---|---|---|
| `C2-REV` | C2 扫破 C1 极值后**收回** | ✅ 是（他：C2 收盘**永远**是反转收盘） |
| `C3` | C2 未给出确认，C3 收在 C2 实体之外且未扫破 C2 极值 | ✅ 是（迟到一根） |
| `C2-CONT` | C2 扫破 C1 极值且**收在其外** | ❌ **不是**反转确认（是延续收盘） |

⚠️ 收盘**恰好等于**被扫位时**不产生**任何 closure —— 它既没收回位内、也没收在位外，
按他的两条定义都不成立。本实现**不硬塞**一个（宁可漏一条，不造一个他没说过的类别）。

### 33.4 自定口径（必须与他的原话分栏）

| # | 自定处 | 说明 |
|---|---|---|
| ① | C3 的严格度 | 他有**两个措辞**：*"closes over the **body** of candle 2"*（两处）与 *"closes beyond the opening price **and range** of candle 2"*（一处）。本实现取**实体**版；"连区间一起越过"的更严版本**未实现** |
| ② | "engulfs it" 的字面 | C3 实体**完全包住** C2 实体 —— **未**作为必要条件。他两次都只说"收在 C2 实体之外"，判据取后者 |
| ③ | C1/C3 的取根方式 | 用**物理相邻** K 线（`b±1`），**非**"有效 bar 序列"。理由：closure 是逐根 K 线的收盘语义（"the previous candle"），与 FVG 的形态口径不同 |

全部写进 CSV 头部的 `# closure ...` 行（`gate=NONE(18a,no state impact)` 亦在其中）。

### 33.5 为什么拆 18a / 18b（**本阶段不判定**）

他另有一条**门禁级**规则（research §1 逐字）：

> "A swing is only valid when it has both: a point of interest and a valid closure
> (candle 2 or candle 3). **If either is missing, the swing point is ignored.**"

若实现它，会改变**全部下游结构**（protected swing 重设、BOS/MSS 归属、结构段划分），
性质与 v1.49-s11 同级。故按阶段 3-a 的既有先例分两步：**18a 只记录（本阶段）**，
**18b 门禁开关**另开一轮、单独测、单独归档。

### 33.6 实现落点（按"计算 / 渲染 / 导出"三层）

| 层 | 落点 |
|---|---|
| 结构 | `StructureEvent` 新增 `int sub`；`StructureResult` 新增 `closure[]` / `nClosure`；新增 3 个 `CLOSURE_*` 常量 |
| 计算 | `AddClosureResult()`；`ComputeClosures()` —— 后验层，**只写 `g_result.closure`**，不碰 nodes/SState/判定路径 |
| 计算 | `FillEventBias` 增加 closure 回填；`ComputeStructure` 在 `ClassifyNodeTiers()` 之后调用 |
| 渲染 | `RenderScene` 新增 CLOSURE 段（标签 + C3 的 EQ 线）；`needDraw` 指纹 +1 项 |
| 导出 | `DumpEvents` 6 路归并 → **7 路**；`tier` 列对 CLOSURE 输出 `n/a`；头部 +`# closure` 行、统计行 +`cisd=`/`closure=` |

### 33.7 验收预测（可证伪，全部未测）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测通过**：`0 errors, 0 warnings, 1582 ms` |
| 2 | **闭合性**：闭包数 ≤ 节点数 | `closure ≤ nodes` —— 每个节点**至多**一条 closure（三分支互斥 + `continue`） |
| 3 | 子类型分布非退化 | 若 `C2-REV` 占 100% 而 `C3` / `C2-CONT` 恒为 0，**优先怀疑 C3 分支又成了死代码**（见 §33.2） |
| 4 | `tier` 列 | CLOSURE 行全部为 `n/a`（其 `refBar` 是 C1/C3，非结构锚点） |
| 5 | **不改变既有事件**（开关对照） | `InpShowClosures=false` 与 `true` 两次导出：**非 CLOSURE 行必须逐字相同** |
| 6 | 渲染 | `C2`/`C3`/`C2-CONT` 标签出现在对应 swing 极值外侧；C3 另有区间 50% 点线 |

判据 3 是本次**最值得盯**的一条：它的失效模式是"功能看起来在跑、实际永不触发"
（v1.49-s15 的死代码门控就是这么来的），而**条数统计抓不到它** —— 只有看**分布**才抓得到。
判据 5 与阶段 16/17 的 A/B 是同一个动作：一次 `InpShowEarlyCISD + InpShowHTFCandles +
InpShowClosures` 全开 / 全关的对照，即可同时验收三个阶段。

---

## 34. 阶段 19：Auto Targets / 操纵腿投影（构建 `v1.50-s19`）

依据：`docs/research/2026-09-23-TTFM-rules-report.md` §7。

### 34.1 ⚠️ 先分部说清置信度 —— 这两半的证据强度**不一样**

| 分部 | 他的原文 | 置信度 |
|---|---|---|
| **(a) 流动性目标** | *"Bullish → previous **untouched** highs; bearish → previous **untouched** lows … **A level already taken out is invalid.**"* 且被列为 *"separate, and primary"* | **高**（规则逐字可溯） |
| **(b) 操纵腿投影** | 锚定规则逐字可溯：*"Anchor a Fibonacci tool to the **manipulation leg** — the swing that sweeps liquidity and occurs **immediately before the CISD**. Bearish projects high→low; bullish low→high. **Start the construction from Candle 2, the reversal point.**"* | 锚定**高**；**方向约定与水平表 = 中介** |

### 34.2 ⚠️ 我把投影的**符号翻了过来**，这件事必须写在最显眼处

他的水平表是 `1, 0, −1, −2, −2.5, −4`（**负向**扩展）。问题在于：

> 按 TradingView 的常规约定，"负向扩展"是从**起点 A 之外**继续延伸。看涨时 A = 被扫破的低点、
> B = 之后的高点，于是 −1/−2 **落在 A 之下** —— 那是**止损方向**，不是目标。

**故本实现反号**：以**交易方向**为准，从 B 继续向外投影（看涨向上、看跌向下），水平取 `1, 2, 2.5, 4`。

这是"**比原文改做**"，不是对齐。按仓库纪律，它必须同时出现在：输入组注释、
CSV 头部（`DIRECTION=OURS(theirs=1,0,-1,-2,-2.5,-4)`）、README、以及本节。
**不得**在任何地方声称本实现与他的水平表一致。

⚠️ 还须知道：水平表本身的置信度也只有**中介** —— §7 自述"第二篇原文的水平列表被截断"。
这是整个四功能复刻里**最弱的一环**，我把它如实标出来了，而不是让它混在"高置信度"里。

### 34.3 实现

| 项 | 做法 |
|---|---|
| (a) 目标取位 | 偏置方向上、现价之外、**未被取走**的摆动位；按**价格距离**取最近 N 个（N = `InpTargetCount`，上限 4） |
| (a) 追加 | PDH / PDL（他明列 previous day high/low 属 draw on liquidity） |
| (b) A | 最近一条**与偏置同向**的 CISD 事件的 `refBar`（= 造势序列极值 = 操纵极值） |
| (b) B | A 之后的**反向极值**（看涨取最高 high、看跌取最低 low）；腿未成形或零长度则**不画** |
| (b) 水平 | `B + (B − A) × k`，k ∈ {1, 2, 2.5, 4}（`OnInit` 里赋值，改四行即可对齐他的表） |
| 共同前提 | `g_curBias == 0` 时**一律不画** —— 他的前提 *"Start with the higher timeframe bias."* |

**一处顺带的重构（有可观测验收锚）**：`ComputeErlIrl` 里原有的"该位是否已被取走"内联循环
被**逐字提取**为 `IsLiquidityTaken()`，供 (a) 复用 —— 目的是同一个概念只有一份实现
（同 `CisdOriginBar` 的规矩），而不是复制两份后各自漂移。
抽取行为保持，且**可验证**：CSV 头部的 `# erlirl … erlPrice=` 必须与 s18 逐字相同。

### 34.4 自审抓到的两个问题（都发生在写完到编译之间）

1. **上限写错对象**：把 `InpTargetCount` 的上限判断写成了 `MAX_TARGETS`（数组容量）。
   后果是**设成 2 也照样画 4 个** —— 编译、运行、无告警，只有读代码才发现。
   现已统一为 `want`；并加了一条自审：`MAX_TARGETS` 只允许出现在声明与容量判断处。
2. **零值未短路**：`InpTargetCount = 0` 时原逻辑仍会收集满 4 个。现由 `want < 0 → 0` +
   循环条件 `want > 0` 短路。

> 这两处的共同点值得记：**都是"输入项没被真正尊重"，而都不会报错**。

3. **退化线（`OBJ_TREND` 两端同一时刻）画不出来** —— 第三处，在渲染层。
   - PDH/PDL 追加目标时我把锚 bar 记成了 `0`，于是左右端点都取 `time[0]`；
   - 投影线的左端锚是 CISD 极值 bar，若该 bar 恰为 `bar 0`（未收盘 bar），同样退让不了。
   两处都已加防护：PDH/PDL 的锚改记 `-1`（= 无本图节点 bar）并锚到该高周期 K 线的
   **开盘时间** `g_pdT1`；投影线左端在 `tA >= time[0]` 时退回固定根数。
   **共同点**：这类缺陷在**编译期、运行期都不报错**，对象甚至"建得出来"，只是**不显示** ——
   与 v1.48 那次"对象坐标全对却整体落在可视区外"属同一类"静默不可见"。

### 34.5 验收预测（可证伪，均未测）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测通过**：`0 errors, 0 warnings, 1668 ms` |
| 2 | **ERL/IRL 无回归** | CSV 头部 `# erlirl … erlPrice=` 与 s18 **逐字相同**（这是 `IsLiquidityTaken` 抽取的唯一验收锚） |
| 3 | 目标数尊重输入 | `InpTargetCount = 2` 时图上**恰好** 2 条 `TGT_*`（不是 4 条） |
| 4 | 无偏置不画 | `g_curBias = 0` 时 `TGT_*` / `FIB_*` 对象数为 **0** |
| 5 | 事件集合不变 | 纯可视化 → 除新增头部行外，**全部事件行逐字不变** |
| 6 | 投影不越界 | `FIB_*` 的 4 条水平全部落在 B 的**交易方向**一侧（看涨在 B 之上、看跌在 B 之下） |
| 7 | 投影腿成形才画 | 最近同向 CISD 之后尚未出现反向极值时，`FIB_*` 为 0（不画零长度腿） |

判据 6 是针对 §34.2 那个反号决定的**直接检验**：若符号搞反，4 条线会全部落在 B 的另一侧。

---

## 35. 真机验收结果（`v1.50-s18`，XAUUSD.ct M5）+ 一个被抓出来的真 bug

用户于 2026-09-24 13:55:45 把 `v1.50-s18` 挂在 **XAUUSD.ct M5** 上，
开 `InpDebugShowRef=true` + `InpDumpEvents=true`，导出 285 条事件。
原始归档：`docs/baselines/2026-09-24-v1.50-s18-BUGGY-closure-accumulation_XAUUSD-M5.csv`
（**文件名里的 BUGGY 是刻意留的** —— 见 §35.2，这份数据本身是坏的，但它是发现 bug 的证据）。

### 35.1 ✅ 阶段 18a 的设计被证实

| 判据 | 结果 |
|---|---|
| **三种子类型都真实出现**（§33.7 判据 3 —— 我最担心的一条） | ✅ `C2-REV` / `C2-CONT` / `C3` **全部出现**。首帧日志逐条可数：**59 条 = 39 C2-REV + 12 C2-CONT + 8 C3** |
| **C3 分支不是死代码** | ✅ 8 条 C3 事件。§33.2 那处推理（"按字面写 C3 永不触发"）与据此改取的条件**被数据支持** |
| `tier` 列 | ✅ 117/117 行全部为 `n/a`（判据 4） |
| 一个节点只出一种子类型 | ✅ 0 例外 |

> 首帧日志里 `nodes=59 / closure=59`，**恰好一一对应**。这说明在**单帧内**，
> §33.2 的"三分支互斥 + continue"设计完全按预期工作。

### 35.2 ❌ 但同一份数据暴露了一个真 bug：跨帧累加

CSV 头部：`nodes=58 … closure=117`。

**`ComputeClosures` 每次调用对每个节点至多加 1 条**，故 `closure ≤ nodes` 是硬不变量。
`117 > 58` ⇒ **数组没有被复位** ⇒ 跨帧累加。

**三点序列（后续又观测到第二个数据点，证据等级从"目录列表"升为"内容级"）**：

| 观测时刻 | `rates` | `nodes` | `closure` | 来源 |
|---|---|---|---|---|
| 13:55:45 | 100152 | 59 | 59 | 首帧，专家日志逐条可数（59 条 `CLOSURE event:` 行） |
| 13:57:35 | 100153 | 58 | **117** | CSV 头部（归档 `…-BUGGY-closure-accumulation_…csv`） |
| 14:02:35 | 100154 | 58 | **175** | CSV 头部（归档 `…-BUGGY-closure-accumulation-t2_…csv`） |
| 14:07:35 | 100155 | 57 | **232** | CSV 头部（`175 + 57 = 232`，**第四个点**，未另存归档以免堆重复文件） |
| 14:12:35 | 100156 | 57 | **289** | CSV 头部（`232 + 57 = 289`，**第五个点**；日志同时显示该帧导出 454 条事件） |

核对：`117 − 59 = 58`、`175 − 117 = 58` —— **每来一根 M5 就净增"当帧节点数"那么多条**，
即**无上限增长**。这不是一次性偏差，而是**持续泄漏**：
`ArrayResize` 每帧在变大的数组上再做一次搬移（摊还代价随时间上升）、
CSV 每小时多出约 `58 × 12 = 696` 行、`needDraw` 指纹里的 `nClosure` 每帧必变
⇒ **每根 bar 强制一次全场景调和**。

> ⚠️ 这条同时也是对 §35.3 的补强：**"无上限"这个性质是靠第三个数据点才确立的**
> —— 只有两个点时它还可能是"某次边界重复"。观测点越多，结论的强度越不一样。

**根因**：后验扫描的约定是"**自己清自己的计数**"（`ComputeSweeps` 就写了 `nSWEEP = 0`），
而我写的 `ComputeClosures` **漏了自复位**，同时 `ComputeStructure` 顶部的集中复位块
（复位 `nNodes/nMSS/nCISD/nBOS/nBox/nFVG/nOB`）**也没有 `nClosure`**。
两个口子同时漏 ⇒ 每经过一次全量重算就多一份。

**修复**（`v1.50-s19b`）：在 `ComputeClosures` 的**早退之前**加 `g_result.nClosure = 0;`
—— 放在早退前是必要的：否则 `InpShowClosures=false` 时会留下上一帧的陈旧数据，
而那正是 A/B 对照（"关掉开关 = 零 CLOSURE 行"）的前提。

### 35.3 ⚠️ 方法论教训：我的"构造性证明"证错了范围

§33.7 判据 2 我曾断言 `closure ≤ nodes` **"是构造性成立的，不需要测量"**。
那个证明本身没错 —— **但它只量化在"单次调用内"**，而 bug 发生在**跨调用**。
一句话：*证明的辖域比结论需要的辖域小*。

**抓出它的是**：`closure ≤ nodes` 这个**不变量** + CSV 头部的 `closure=` **计数**。
**不是**编译（`0 errors / 0 warnings`），**也不是**我的推理。
—— 这正是仓库"先测量、后归因"那条纪律存在的理由，本轮它又赢了一次。

### 35.4 ⚠️ 两个**失败**的检验手段（记下来免得后人重复）

我先后试了两个想抓"跨帧重复"的判据，**都无效**：

| 检验 | 为什么无效 |
|---|---|
| "同一 `c2` 是否重复出现" | 返回 **117 个唯一值、零重复** —— 看似"没有累加"，实则**bar 指数每来一根新 K 线就整体 +1**，两帧的同一节点落在不同指数上，天然不重复 |
| "`c2` 与 `c2+1` 是否同时出现"（平移重叠） | 得到 72/117，看似很高 —— 但**对照 FVG 也有 27/100**，说明相邻 bar 本来就聚集，这个判据没有区分力 |

**结论**：在"指数会随时间平移"的数据上，任何基于**锚点值重复**的判据都不可靠。
可用的是**计数型不变量**（`closure ≤ nodes`）与**头部自描述计数**。

### 35.5 仍未验收的部分（这一轮拿不到证据）

| 功能 | 状态 | 为什么拿不到 |
|---|---|---|
| 阶段 18a | ✅ 已验收（并修了一个 bug） | — |
| 阶段 16 IC-CISD | ⏳ **无证据** | 它是纯渲染 → 既不进 CSV 也不打日志。首轮导出的 build 是 s18，日志里没有任何 IC 痕迹 |
| 阶段 17 HTF 蜡烛 | ⏳ **无证据** | 同上（只有 `chartObjs=91` 这个总数，无法拆出哪 12 个是 HTF 蜡烛） |
| 阶段 19 目标投影 | ⏳ **未运行过** | 首轮导出跑的是 s18，**不含**阶段 19 代码 |

**已针对性补强（`v1.50-s19c`）**：`DbgReport` 新增一行 `TradFi_RENDER`，
把"只能靠肉眼看图"的三项变成可测量输出：

```
TradFi_RENDER icValid=… icLevel=… icRefBar=… | tgtCount=… fibValid=… fibA=… fibB=… |
              objs total=… IC=… HTF=… TGT=… FIB=… CloLbl=… C3EQ=…
```

预期关系（可直接当判据用）：`HTF = 3 × InpCandleCount`；`TGT = 2 × 目标数`；
`FIB = 2 × FIB_NLEGS`；`IC ∈ {0, 2}`（只在未收盘 bar 上出现）；
`C3EQ ≤ C3 条数`。

同时 `DbgReport` 还新增一行 `TradFi_CLOSURE nodes=… closure=… c2rev=… c3=… c2cont=… invariant=OK|VIOLATED`
—— **把 §35.2 那个不变量直接做成日志自检**，下次同类漏复位会当场喊 VIOLATED，
不必再靠人工读 CSV 头部。

### 35.6 下一步需要你做的（一次就够）

重挂 `v1.50-s19c`（**这版才同时含阶段 19 与上述自检**），保持 `InpDebugShowRef=true` +
`InpDumpEvents=true`，然后：

1. 日志里应出现 `build=v1.50-s19c` 与 `TradFi_CLOSURE … invariant=OK`；
   **若出现 `invariant=VIOLATED` 就是没修好**，请把那一行发我。
2. `TradFi_RENDER` 那一行直接发我 —— 它一次覆盖 16/17/19 三项的判据 3/6/7。
3. 想要 A/B 对照（判据 5：关掉开关事件集合不变），再各重挂一次即可。

---

## 36. 把 §35 那个 bug 变成一道可复跑的机械检查

**新增 `Indictor/audit_state.ps1`**（纯 ASCII，遵硬约定 6）。
动机：§35.2 那个"后验扫描漏自复位"的 bug **没有任何机械手段抓到** ——
编译 `0 errors / 0 warnings`、推理也证错了辖域。既然它是一类可静态识别的模式，
就不该只留一句教训，而应该留一道**检查**。

### 36.1 它检查什么

| 段 | 判据 |
|---|---|
| **A** | `struct StructureResult` 里每个 `int n<X>;` 计数，都必须存在 `g_result.n<X> = 0;` |
| **B** | 复位所在的那个函数，必须**真的驱动**这些自增 —— 即它调用了做 `g_result.n<X>++` 的那个 `Add*`。<br>只由集中于 `ComputeStructure` 的复位块覆盖者标为 **OK\***（较弱：挡不住"pass 在循环前早退"） |
| **C** | 一张逐帧全局变量清单，每个都必须有**至少一次非声明式赋值** |

当前结果：**PASS（0 problems）**，其中 `nSWEEP`/`nClosure`/`nBox` 为强通过（复位函数确实调用自增函数），
`nNodes`/`nMSS`/`nCISD`/`nBOS`/`nFVG`/`nOB` 为 **OK\***（由集中块覆盖）。

### 36.2 它**不**检查什么（必须一并写明，否则会给人虚假信心）

- 赋值在**每条路径上是否可达**（早退、门控）—— 这是关键缺口，无法静态判定；
- 赋的**值对不对**；
- 快路径（同 bar tick）的行为，只查代码存在；
- **通过引用出参写入的赋值**。具体一处：`EvalEarlyCisd(close, g_icValid, g_icLevel, g_icRefBar)`
  确实写这三个全局，但检查器能看到的唯一**文本**赋值在 `UpdateEarlyCisdFast` 里，
  故它报的位置对这一处是误导的。**这类模式必须人工确认出参带 `&`** ——
  MQL5 简单类型默认按值传递，不加 `&` 时调用方变量**不会被改**，而**照样编译通过**。
  （已核：`EvalEarlyCisd` 的三个出参都带 `&`，L3549 的写回有效。）

### 36.3 ⚠️ 检查器自己先后有两个 bug —— 这段比结论更值得留

**bug 1：函数归属用松散正则 → 假 FAIL。**
初版靠 `^[A-Za-z_].*\b(\w+)\s*\([^;]*\)\s*$` 追踪"当前函数"，结果把自增归给了
`FindBrokenNodeBar`，于是对 `nSWEEP`（实际在 `ComputeSweeps:2290` 复位）与
`nClosure`（实际在 `ComputeClosures:1290` 复位）**双双误报 "NOT reset anywhere"**
—— 而同一份输出的 A 段明明已列出这两个复位点。

**bug 2：把"声明时带初始值"当成逐帧赋值 → 假 PASS。**
C 段初版接受 `double g_x = 0.0;` 这类声明行，于是 31 个全局**全部**报 ok，
而且落点全显示为 `<top-level>` —— **一眼看去全绿，实际什么都没验证**。

**两个 bug 的修法**：函数归属改为**向前回溯到最近的列 0 函数定义**（不做括号计数，
避免字符串/注释里的花括号干扰）；C 段显式跳过声明行与 `input|extern|static` 行。

**由此得到的两条元规则**（已写进脚本头部注释）：

1. **检查器本身需要被验证。** 一份会喊狼来了的检查，和一份永远沉默的检查**一样有害** ——
   前者会让人去改本来正确的代码。
2. **凡检查器报出的结论，都要带上"它凭什么这么说"**（本脚本因此为每条结果打印
   **所在函数名**与**行号**）—— 归属错了要能**一眼看出来**，而不是只能靠信念接受。

> 这与 §35.3 是同一条教训的两次命中：**推理与工具都会错，唯一可靠的裁判是
> "结论能否被一个独立于推理过程的东西反驳"。**

### 36.4 新增检查 D：`needDraw` 指纹覆盖（硬约定 3）

硬约定 3（"新增可视化元素必须同步 `needDraw` 指纹，否则表现为要等下一根 bar 才出现"）
同样曾经真实咬过人，故也做成检查：

> 收集 `RenderScene` 里**被读取**的 `g_*` 全局（剔除赋值目标与注释），
> 再收集 `needDraw` 表达式里的全局，报出"读了但不在指纹里"的名单。

**它是信息性检查**（不判 FAIL）："在 RenderScene 里被读" ≠ "必须在指纹里"——
指纹自己的存储（`g_last*`）、诊断量（`g_dbg*`）、场景集内部量（`g_set*`）、
对象名缓存（`g_icName`）都会被读到，但都不需要指纹槽位。

**⚠️ 并为它加了"空洞绿灯"防护**：若收集器几乎什么都没收到（`reads < 10`），
判 **FAIL** 而不是 PASS —— 否则"全部覆盖"这个结论**可能是空转得出的**。

**反证测试（这一步不能省）**：故意把 `g_tgtCount != g_lastTgtCount` 这一项从指纹里删掉，
再跑检查 D —— 它**确实报出了** `? g_tgtCount read in RenderScene, not in needDraw`。
随后还原，源码 `mq5` 哈希与测试前**逐字节一致**（`410BE8D2F0FA`）。

> **由此定下验证检查器的标准手法**：*故意破坏被检查的属性 → 确认检查器会喊 →
> 还原 → 确认源码哈希回到原值。* 只跑一次"通过"不算验证过检查器。

当前结果：`76` 个读取 / `73` 个在指纹内，其余 3 个均属上述正当豁免 → **ok**。

### 36.5 记一个踩了两次的工具坑

`[System.IO.File]::ReadAllBytes('相对路径')` **用的是进程 CWD，不是 PowerShell 的位置** ——
`cd` / `Set-Location` 对它无效，于是它去工作区根目录找文件并报 `FileNotFoundException`。
本会话踩了两次（`audit_state.ps1` 自查、以及源码还原后的 BOM 校验）。
**凡 .NET 静态 API 涉路径，一律给绝对路径。**

---

## 37. 阶段 16–19 收尾：规模校验、检查 D、以及一个"观测点数量"的教训

构建 `v1.50-s19e`。本轮**没有新功能**，只有防御性收口 —— 因为四个功能都已编码完毕，
而运行时验收仍待重挂（见 §37.3）。

### 37.1 新增输入的规模校验（`v1.50-s19e`）

HTF 蜡烛是四个新元素里**唯一"按输入线性放大对象数"**的：每根 3 个对象，
`InpCandleCount = 200` 就是 600 个。仓库记过实况 —— *"MT5 单图表对象数有上限，
超了会被终端拒绝创建"*（见 `InpMaxSeg` 注释）。故在 `OnInit` 按既有风格
（与 `InpWindow` / `InpATRPeriod` 一致）拒绝越界：

| 输入 | 允许范围 | 理由 |
|---|---|---|
| `InpCandleCount` | `0..50` | 每根 3 个对象，唯一随输入线性放大的元素 |
| `InpHtfBodyFill` | `0..100` | 越界会让 `PdFill` 混色外推 |
| `InpTargetCount` | `0..MAX_TARGETS(4)` | 与内部 `want` 钳制保持一致（此前只静默钳制） |

**其余三项内部自有界**，故意不在此校验：目标 = `2×MAX_TARGETS`、投影 = `2×FIB_NLEGS`、
closure 标签受 `InpMaxEvents` 裁剪。

### 37.2 观测点数量决定结论强度（对 §35.2 的补强）

§35.2 那个累加 bug，我在第 3 轮只能给到**两个数据点**，且其中一份中间态已被覆盖，
故当时如实写成"只有目录列表级证据"。第 4 轮拿到**第三个点**后，结论性质变了：

| 点 | `rates` | `nodes` | `closure` |
|---|---|---|---|
| 1 | 100152 | 59 | 59（首帧，日志逐条可数） |
| 2 | 100153 | 58 | 117 |
| 3 | 100154 | 58 | **175** |

`117−59 = 58`、`175−117 = 58` —— 净增恒等于**当帧节点数**。

**两个点只能说明"有重复"；三个点才能说明"每帧净增一个 nodes，即无上限增长"。**
"无上限"这个性质（进而 `ArrayResize` 摊还代价随时间上升、CSV 每小时多约 696 行、
`needDraw` 每帧必变导致**每根 bar 强制全场景调和**）**是第三个点才确立的**。
→ **不要在两个观测点上宣布一个关于趋势的结论。**

### 37.3 运行时验收状态（**仍未重挂**）

截至本轮结束，MT5 上跑的仍是 `v1.50-s18`（日志无 `v1.50-s19*` 的 INIT 行，
也无 `TradFi_CLOSURE` / `TradFi_RENDER` 自检行）。即：

- **⚠️ 那个累加泄漏仍在持续**（第三点 175 就是 14:02:35 的实时数据）——
  重挂 `v1.50-s19e` 的首要理由是**止血**，其次才是验收；
- 阶段 16（IC-CISD）/ 17（HTF 蜡烛）/ 19（目标投影）**仍无任何运行时证据**；
- 阶段 18a 已验收（§35.1），其 bug 已在 `s19b` 修复，但**修复本身也尚未在真机确认**。

**我尝试过且失败的三条自动触发路径**（记录下来以免重复尝试）：
① 只复制新 `.ex5`；② 在 MT5 的 `MQL5\Indicators\` 里**就地编译**同源副本；
③ 前者 + 等待 60 秒。三条都未触发终端重载，日志里没有 `reason=2`（REASON_RECOMPILE）。
该终端数据目录确属 Decode Global（`origin.txt` 已核），故不是"编译器与终端不匹配"。
**结论：这个终端的重载只能由人手动触发。**

### 37.4 旁注：工作区里出现了另一套东西

本轮发现 `Indictor/SMC_Toolbox.mq5`（`v1.00-s1`，2631 行）与配套的
`docs/plans/2026-09-24-SMC-toolbox.md`。其文件头明确写着这是**独立于**
`Structure.mq5` 的另一套东西（口径来自 SMC 行业通行读法，刻意与 TTrades 一手口径分源）。
**本轮未改动它任何内容** —— 记在这里只为说明"工作区里的变化不都来自本次任务"。

---

## 38. 阶段 16–19 的保真度矩阵（硬约定 12：要求 → 是否满足 → 证据）

硬约定 12 要求：*"文档里'他的要求'与'我们是否做到'必须分栏，不能只列要求"*，
且必须**显式给出满足状态与证据行号**。前几轮我只写了要求与预测，**没写这张表** —— 补上。
行号对 `v1.50-s19e` 有效。

### 38.1 ① Early CISD / IC-CISD

| 他的要求（research §3） | 状态 | 证据 |
|---|---|---|
| CISD 三条件之一：**收盘穿回**造势那串 K 线 | ✅ | `EvalEarlyCisd` L3342 与 `CheckCisd` 同一条件 |
| "automatically plots CISD **before candle closure**"（live/provisional，收盘确认） | ✅ | `EvalEarlyCisd` L3342 / `SyncEarlyCisdObject` L3362 / 快路径 `UpdateEarlyCisdFast` L3399 |
| **纯渲染，不写状态** | ✅ | 静态审计零写入；权威状态由 `RenderScene` 给出，快路径不写场景集 |
| 预览不活过收盘 | ✅ | `g_armedCisd*` 快照取 `valid && !fired`，L2969 |
| **"Early-in-the-candle CISD 最强；late CISD 应跳过"** | ✅ **已补（`v1.50-s20`）** | `EvalIcLate()`；标签在迟于 `InpIcLatePercent`（默认 60%）时显示 `IC-CISD (late)` 并转暗色。⚠️ 阈值他未给数值 → **自定近似** |
| 三条件之一：价格**到达 POI** | ❌ **未实现**（属 CISD 通用条件，非本阶段引入） | 无 POI 门槛 |

### 38.2 ② HTF 蜡烛叠加

| 他的要求（research §9） | 状态 | 证据 |
|---|---|---|
| count 默认 **4** | ✅ | `InpCandleCount = 4` |
| Size（尺寸） | ✅ | `InpCandleWidthPct` |
| **Offset（偏移）** | ✅ **已补（`v1.50-s20`）** | `InpHtfShift`（整体左移 N 根；指纹与绘制共用同一套下标） |
| **时间标签** | ✅ **已补（`v1.50-s20`）** | `InpHtfTimeLabels`；每根下方 `TimeToString(t1, TIME_MINUTES)` |
| colors | ✅ | `InpColorHtfUp` / `InpColorHtfDn` |
| 画在 K 线之下 | ✅ | `UpsertRect` 恒定 `OBJPROP_BACK=true` |

### 38.3 ③ Candle 2 / Candle 3 收盘确认

| 他的要求（research §2） | 状态 | 证据 / 说明 |
|---|---|---|
| C1/C2/C3/C4 编号 | ✅ | `ComputeClosures` L1297：C2 = swing 点，C1 = `b+1`，C3 = `b-1` |
| 延续收盘（扫破前根并**收在其外**） | ✅ | `CLOSURE_C2_CONT` |
| 反转收盘（**扫破后收回**） | ✅ | `CLOSURE_C2_REV` |
| "A Candle 2 closure **always** a reversal closure" | ✅ | 三种子类型命名与语义一致 |
| C3 收盘：未扫破 C2 极值 + **收在 C2 实体之外** | ✅ | `CLOSURE_C3` |
| C3 *"closes beyond the opening price **and range** of candle 2"* | ⚠️ **只做实体版**，"连区间一起越过"未实现 | 自定口径①（§33.4） |
| `"engulfs it"` 的字面（C3 实体完全包住 C2 实体） | ⚠️ **未作为必要条件** | 自定口径② |
| C3 的均衡位用法（mark C3 full range） | ✅ 画了 C3 的 50% 线 | 渲染块 L4010；`InpShowC3Eq` |
| "看涨预期 **C4 刺入 C3 上半**" | ✅ **已补（`v1.50-s22`）** | `EvalC4Half()`：看涨判 `low[C4] >= EQ(C3)`、看跌判 `high[C4] <= EQ(C3)`；结果落在标签后缀（`C3+` / `C3-` / 无后缀=待定）与 CSV 的 `state` 列（`C3+C4-OK` / `C3-C4-BROKE` / `C3`）。⚠️ **只记录，不参与判定**（他未说破掉之后算不算失效） |
| C1/C3 取**物理相邻** K 线 | ⚠️ 自定口径③（他写 "candle" 字面，未说明是否剔除内包） | §33.4 |
| **门禁：*"缺 POI 或缺 valid closure 则忽略该 swing"*** | ⛔ **用户裁定不做（2026-09-24，「无需门禁」）** —— 从"未实现"改为"已裁定的终态" | §43.7 |
| C2 亦需 POI，否则忽略 | ⛔ 同上（随 18b 一并否决） | §43.7 |

### 38.4 ④ Auto Targets / 操纵腿投影

| 他的要求（research §7） | 状态 | 证据 / 说明 |
|---|---|---|
| 看涨→**未取走**的高点；看跌→未取走的低点 | ✅ | `ComputeTargets` L2584 |
| PDH/PDL 属流动性目标 | ✅ | 追加逻辑（锚 bar 记 `-1`，锚到该日开盘） |
| *"A level already taken out is invalid."* | ✅ | `IsLiquidityTaken` L2469（与 ERL **共用**同一实现） |
| 锚 = **操纵腿**（CISD 之前那次扫荡的极值） | ✅ | A = 与偏置同向的最近 CISD 的 `refBar` 极值 |
| 看跌 high→low，看涨 low→high | ✅ | 以交易方向外推 |
| *"Start the construction from Candle 2, the reversal point."* | ⚠️ **待核**：A 取自 CISD 极值（造势序列极值），与"Candle 2"在他文中的所指是否同一处，**未取得一手确认** | — |
| 水平 `1, 0, −1, −2, −2.5, −4` | ⚠️ **降级为"可配置"**（`v1.50-s21`）：水平表由 `InpFibLegs` 输入，**选择权交给用户**；默认 `0,1,2,2.5,4`（交易方向上的目标），**照填他的原表即可逐字复现**（但符号约定不同，见输入项注释） | §34.2 / `InpFibLegs` |
| 按腿长给期望（平均腿→−2~−2.5；扩张腿→−4；大操纵腿→降到 −1） | ❌ 未实现 | — |
| 最低 2R / runners 到 HTF draw on liquidity | ❌ 未实现 | 属**执行层**，见 §4「明确不做」 |

### 38.5 矩阵结论

四功能的**主干**（CISD 提前确认、HTF 蜡烛、C2/C3 三分类、流动性目标）都有逐字依据并已实现；
首次成表时**明面上的缺口有 9 处**，按性质分三类；其中 A 类三处已在 `v1.50-s20` 补掉：

| 类别 | 条目 | 处置 |
|---|---|---|
| **A. 可补且已有一手依据** | ~~HTF 的 **Offset** 与**时间标签**~~ ✅ 已补；~~IC-CISD 的 **"K 线内早/晚"**~~ ✅ 已补；~~投影的 **`0` 水平**~~ ✅ 已补 | **本轮（`v1.50-s20`）完成** |
| **B. 已如实标注的"改做/自定"** | C3 的实体版 vs 区间版、"engulfs" 字面、C1/C3 物理相邻、投影符号翻转、`InpIcLatePercent` 阈值 | 保持标注，不改（改了反而偏离他的原话） |
| **C. 刻意推迟或超范围** | closure+POI **门禁**（18b）；按腿长的期望表（平均腿→−2~−2.5 等）；2R/执行层 | 门禁**需要用户裁定**（改结构）；期望表阈值纯自定；2R 属执行层，**已在 §4 声明不做** |

**补完后仍开放的是 B 与 C 两类**：B 类是"我改的"，C 类是"我没做的"或"超范围的"，
两类都在上表可查 —— 没有一项是"没写进文档"的。

> ⚠️ **这张表本身就说明了"复刻完成"这句话该怎么说**：
> 主干已复刻且逐条可溯，但**"完成"不等于"逐字一致"**。
> 这也是硬约定 12 存在的意义：只列要求不列状态，读起来就像达标清单。

---

## 39. `v1.50-s21`：让不变量"被破坏时无法被忽视"

本轮**没有新功能**。唯一的代码改动针对一个已被证实的**观测性缺陷**：

### 39.1 问题：那个不变量当时"只在 CSV 头部可见"

`closure ≤ nodes` 是 v1.50-s18 跨帧累加 bug 的**唯一现场证据**（§35.2）。
但它只出现在 **CSV 头部**（`# window=… closure=…`）——
而**没人会每根 bar 去读 CSV 头部**。一个"被破坏时无人看见"的不变量，等于没有不变量。

这同时是 §36.3 那条元规则的又一次命中：*永远沉默的检查与喊狼来了一样有害*。

### 39.2 改法：报警与调试开关**解耦**

`DbgReport()` 原先在函数第一行就 `if(!InpDebugShowRef) return;`，于是**全部**诊断都在开关之后。
现在把不变量检查提到早退**之前**：

```
不变量正常      → 静默（不看任何开关）
不变量被破坏    → 无条件 PrintFormat("TradFi_INVARIANT VIOLATED: closure=%d > nodes=%d (build=%s) …")
InpDebugShowRef → 只控制"正常时的详尽输出"，**不控制"异常时的报警"**
```

**约定（已写进 CONTEXT）**：*不变量正常时静默，被破坏时无条件发声。*
调试开关管详尽程度，不管报警 —— 否则"默认配置下的用户"永远看不到异常。

### 39.3 顺带把审计工具的反证测试补全

前一轮只对**检查 D**（`needDraw` 指纹覆盖）做过反证测试。本轮补做**检查 A/B**：

| 步骤 | 结果 |
|---|---|
| 删掉 `g_result.nClosure = 0;` | `FAIL  nClosure  no reset found` → `RESULT: FAIL (1 problem)` ✅ 它确实会喊 |
| 还原 | `ok  nClosure  reset in [ComputeClosures] at line 1356` → `RESULT: PASS` |
| 校验哈希 | `mq5 = 9BB2731D6515`，**与破坏前逐字节一致** ✅ |

至此 `audit_state.ps1` 的 **A/B 段与 D 段都经过"故意破坏→确认会喊→还原→校验哈希"的验证**。
（C 段的失败模式是"某全局从未被赋值"，用同样的手法可测，尚未做 —— 如实标注。）

### 39.4 验收预测

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | 正常时静默 | 关闭 `InpDebugShowRef` 且不变量成立时，日志**不出现** `TradFi_INVARIANT` |
| 3 | 异常时发声 | 关闭 `InpDebugShowRef` 且 `closure > nodes` 时，**必定**出现 `TradFi_INVARIANT VIOLATED`（这正是 s18 缺的那条） |
| 4 | 事件集合不变 | 纯诊断改动 → CSV 全部数据行逐字不变 |

### 39.5 本轮另一处改动：把"改做"降级为"可配置"

§38.4 把投影水平表标为 **⚠️ 改做**（符号翻转 + 水平改为 `1, 2, 2.5, 4`）。
本轮把它变成**输入项** `InpFibLegs`（默认 `0,1,2,2.5,4`，最多 6 条）：

- 语义写死为 `价位 = B + 腿长 × k`，故 **k > 0 = 沿交易方向外推**；
- 想**逐字复现他的原表**就填 `1,0,-1,-2,-2.5,-4`（⚠️ 符号约定与他不同，那 3 条会落在起点 A 之外）；
- 解析失败/空表在 `OnInit` 被拒绝。

**为什么这比"我替他定死符号"更好**：符号之争是**他的表述与 TradingView 约定之间的冲突**，
不是我与他之间的分歧。把选择权交出去，等于**把一处自定口径换成了一个可配置项** ——
用户可以用他的表，也可以用作目标讲得通的那套，而**不再需要我替他裁决**。

### 39.6 顺带把审计的 D 段从"信息性"升级为判 FAIL

D 段原先只是**列出**"读了但不在指纹里"的全局，不判 FAIL。本轮发现它把两个**新引入**的
全局（`g_fibNLegs`、`g_icLate`）报了出来 —— 报得对，但"信息性"意味着**这份清单可以被无视**。

故改为**带理由的豁免表**：每个例外必须在脚本的 `justified` 表里写明理由；
**没有理由的候选直接判 FAIL**。两条新增理由：

| 全局 | 理由 |
|---|---|
| `g_fibNLegs` / `g_fibLegs` | `OnInit` 里设一次；MT5 在任何输入变更后都会重跑 `OnInit`，故不可能变陈旧 |
| `g_icLate` | **按设计**会在 bar 内翻转；由**快路径**缓存比对处理（与 `UpdateLiveLeg` 同一套分工） |

**反证测试**：从 `justified` 表里删掉 `g_icLate` → 报
`!! FAIL g_icLate read in RenderScene, not in needDraw, and has no written reason` → `RESULT: FAIL`；
还原后 PASS。**至此 A/B 段与 D 段都经过反证验证**（C 段尚未，已在 README 如实标注）。

> 这与 §36.3 是同一个判断的第二次应用：**例外必须被写下来，否则它就不是例外而是漏洞。**

---

## 40. `v1.50-s22`：补上 C4 均衡位检测；并修掉审计脚本自身的一处"假绿灯"

### 40.1 C4 均衡位（他给的最后一条 closure 用法）

他（research §2）：*"For a C3 closure: mark the **full range of candle 3**; bullish expect
candle 4 to **wick into the upper half** of candle 3; bearish into the lower half."*

实现 `EvalC4Half()`：C4（= C3 之后那根）的影线是否**停在预期那一半内** —
看涨判 `low[C4] >= EQ(C3)`、看跌判 `high[C4] <= EQ(C3)`。
返回 `0` = C4 尚未出现（待定）/ `1` = 守住 / `2` = 已破，写进 `StructureEvent.c4`。

呈现：标签后缀 `C3+` / `C3-` / 无后缀（待定）；CSV 的 `state` 列 `C3+C4-OK` / `C3-C4-BROKE` / `C3`。

⚠️ **自定口径**：他给的是一句**期望**（"expect … to wick into"），**没有说破掉 EQ 之后算不算失效**。
故本项**只记录、不删除也不弱化任何东西**，仍是 18a 性质（`# closure` 头部标注 `c4=… recordOnly`）。

### 40.2 顺带修掉审计脚本自己的一处"假绿灯"

做 C 段反证测试时发现：`audit_state.ps1` 在 **D 段之前**先打了一行 `RESULT:`。
后果是**只读第一行 RESULT 的人会看到 PASS，而 D 段其实可能失败** ——
正是本脚本存在的意义所要防的那个失效模式。

已删除该提前结论：**现在全文只有一行 `RESULT:`，在最末尾**，且 D 段的失败会正确传导为 `FAIL`。
（反证：把 `g_icLate` 从 `justified` 表改名 → 输出 `!! FAIL g_icLate …` 且 `RESULT: FAIL`。）

### 40.3 检查器的反证验证（至此四段齐备）

| 检查段 | 反证手法 | 结果 |
|---|---|---|
| **A/B** | 删掉 `g_result.nClosure = 0;` | `FAIL nClosure no reset found` ✅ |
| **C** | 把清单里的 `g_tgtCount` 改成不存在的名字 | `FAIL g_tgtCountXYZ no non-declaration assign` ✅ |
| **D** | 把 `g_icLate` 从 `justified` 表改名 | `FAIL g_icLate … has no written reason` ✅ |
| 空洞绿灯防护 | 收集器低于 10 个读取即判 FAIL | 已内置 |

**至此 `audit_state.ps1` 的四段检查全部经过"故意破坏 → 确认会喊 → 还原"的验证。**

### 40.4 验收预测（可证伪，均未测）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | C4 计数自洽 | `TradFi_CLOSURE` 里 `c4ok + c4broke + c4pending == c3` |
| 3 | 待定恒等于"最近的 C3" | `c4pending` 应为 0 或 1（只有最新那条 C3 的 C4 可能还没出现）—— **若远大于 1，说明 `EvalC4Half` 的边界判断写错了** |
| 4 | 事件集合不变 | 除新增的 `c4` 语义外，其余类型的行逐字不变 |
| 5 | 审计单结论 | `audit_state.ps1` 全文只输出**一行** `RESULT:` |

---

## 41. `v1.50-s23`：头部自描述里的一处**谎报**；以及一页验收 runbook

### 41.1 CSV 头部曾**谎报**实际使用的投影水平

`# targets` 行把水平表**写死**成字面量 `legs=1,2,2.5,4`。
而 `v1.50-s21` 已把水平表改成输入项 `InpFibLegs` —— 于是从那一刻起，
**头部就在报告一个与实际渲染不一致的水平表**。

这条为什么值得单列：**CSV 头部存在的唯一理由就是自描述**（两份归档要能判断是否同一口径）。
一个会谎报的头部，比没有头部更糟 —— 它会让两个不同口径的归档看起来可比。

修法：改为 `StringFormat(..., InpFibLegs)`，并顺带把 `DIRECTION=OURS(...)` 改成
`DIRECTION=USER-CONFIGURABLE(...)`（符号约定现在是用户选项，不是本实现的裁决）。

> **可推广的规则**：凡"输入项决定内容"的头部字段，**必须取自输入项本身**，不得写死。
> 已把该行其余字段逐一复核（`# filters` / `# displacement` / `# render` / `# bias` 均取自输入），
> 确认这是**唯一**一处。

### 41.2 新增一页验收 runbook

`docs/sop/2026-09-24-Structure-acceptance-runbook.md`。

动机：验收步骤此前散落在 §32.6 / §35.6 / §37.3 / §40.4 四节里，
**一页看全反而做不到**，于是每次重挂都可能漏掉某条判据。
runbook 把"怎么挂 → 图上先看什么 → 发哪两行日志 → 每条字段各证明什么 →
可选的 A/B 对照 → CSV 怎么读 → 哪些是**已知边界不必再报**"压成一页，
并给出各字段的**判据式期望值**（例如 `HTF = InpCandleCount × (3 + 时间标签?1:0)`）。

### 41.3 验收预测

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | 头部取自输入 | 改 `InpFibLegs` 后重新导出，`# targets … legs=` **随之改变**（不再恒定 `1,2,2.5,4`） |
| 3 | 事件行不变 | 纯头部改动 → `seq,` 起全部数据行逐字不变 |

---

## 42. ⭐ 首次完整真机验收：`v1.50-s23`（2026-09-24 14:17:34 / 14:17:35 / 14:22:35）

用户重挂后，两行自检**首次全部打出**。这是四个功能落地以来**第一份完整的运行时证据**。

### 42.1 判据逐条核对（全部通过）

| 判据 | 期望 | 实测 | |
|---|---|---|---|
| `invariant` | `OK` | **`OK`** | ✅ |
| `closure ≤ nodes` | 成立 | 58 ≤ 58 | ✅ |
| **跨帧不累加** | 各帧同值 | **三帧全为 58**（14:17:34 / 14:17:35 / 14:22:35） | ✅ |
| `c4ok+c4broke+c4pending == c3` | 等式成立 | 3+5+0 = 8 = `c3` | ✅ |
| `c4pending` | 0 或 1 | **0** | ✅ |
| `c3` / `c2cont` 非 0（非死代码） | 都不为 0 | 8 / 12 | ✅ |
| `HTF = 4×(3+1)` | 16 | **16** | ✅ |
| `TGT = 2×3` | 6 | **6** | ✅ |
| `FIB = 2×5` | 10 | **10** | ✅ |
| `IC ∈ {0,2}` | 0 或 2 | 0，且 `icValid=0` 自洽 | ✅ |
| `TradFi_INVARIANT` 报警 | 不出现 | 不出现（正常时静默） | ✅ |

**`closure` 跨帧不累加这一条是本次最关键的收获**：s18 在同一时间跨度上是
`59 → 117 → 175`（每帧净增 nodes），而 s23 三帧**全是 58**。
**§35.2 那个 bug 的修复，至此在真机上确认。**

CSV 头部同时自证：`build=v1.50-s23`、`closure=58`、`legs=0,1,2,2.5,4`（**取自输入项，不再写死**）、
`# closure … c4=eqHalf(…) recordOnly`。CLOSURE 行的 `state` 分布 =
`C2-REV 38 / C2-CONT 12 / C3+C4-OK 3 / C3-C4-BROKE 5`（38+12+3+5 = 58 ✅）。

### 42.2 s18 → s23 的事件差异：已定位为**分析窗口滑动**，不是回归

逐字段比对两份导出的**非 CLOSURE 行**（共 165 / 168 行）：

- **162 条共有事件在 9 个字段上逐字相同**（`ref`/`rt`/`disp`/`tier`/`bias`/`zlo`/`zhi`/`fill`/`state`）；
- 差异只有三处，且全部集中在**最旧的几条**：
  1. `FVG 09-22 14:00` 的 `ref`/`rt`/`zhi` 变了（取到了不同的前一根）；
  2. `OB/CISD 09-22 15:40` 的 `disp` 微变（`body 1.04→1.03`）；
  3. **`BOS 09-22 18:05` 变成 `MSS`**（同 bar、同 `ref=4337.98`）。

**第 3 处的算术解释（不是推测）**：消失的那条 `BOS 09-22 15:20` 的
`refBar = 498`；而 `InpAnalysisWindow = 500` ⇒ 分析窗口是 `[0, 499]`。
窗口滑 3 根后，同一根 bar 变成下标 **501 → 落在窗口之外，不再被分析** ⇒ 该事件**不可能再产生**。
它的消失改变了趋势状态，于是 18:05 那根**同价位**的突破从顺势(BOS)变成逆势(MSS)。
第 1、2 处同理（`refBar 497→499` 就在边界上；ATR 序列的起点随窗口移动而微变）。

**对照组**：同构建 s18、相隔 1 根 bar（100153→100154）的两份导出，
差异**只出现在 ATR 派生的 `disp` 列**，**没有类型改变**——说明 ATR 类差异是固有的。

⚠️ **如实说明的局限**：1 根 bar 的对照**不足以移动窗口边界上的那个锚点**，
故"类型改变"没有被对照直接复现。**我没有做隔离实验**（需要同一构建跑同一段 bar，本环境做不到）。
支撑结论的是两条独立证据：① 上述 `refBar=498` 越界的**算术必然性**；
② 静态审计已证明 closure / targets / HTF 三处新代码对
`g_result.{nodes,mss,bos,cisd,sweep,fvg,ob}` 的写入**零命中**。

### 42.3 ⚠️ 唯一未获正面证据的项：IC-CISD

三帧的 `icValid` 都是 **0** —— 当时没有"武装中且被穿越"的 CISD 位，
**IC-CISD 的代码路径一次都没走到**。`IC=0` 只证明"没有多余对象"，**不证明它能触发**。

**根因是采样方式**：`TradFi_RENDER` 每根 bar 采一次，而 IC-CISD 可能在同一根 bar 内
**触发又消失** ⇒ 逐帧快照**天然会漏掉**这类瞬时状态。

**`v1.50-s24` 的修法**：新增**累计触发计数** `g_icHits`（自加载起，0→有效 的跃迁计一次），
打印在 `TradFi_RENDER` 里。两个调用方（全量帧与快路径）**共用同一份"上一状态"**
（`g_icCountValid`），避免同一次触发被计两遍。

> 这条与前面几次是同一类教训的第四次应用：**可观测性不足时，"功能是否存在"
> 会被误当成"功能是否在跑"。** 纯渲染元素没有 CSV 痕迹，就必须自己造痕迹。

### 42.4 本轮改动（`v1.50-s24`）

| 改动 | 说明 |
|---|---|
| 新增 `NoteIcState()` + `g_icHits` | IC-CISD 累计触发计数，写入 `TradFi_RENDER`（=可观测性补强） |
| 头部 `legs=` 取自输入项 | §41.1 那处"谎报"已在导出中验证修好（实测打出 `legs=0,1,2,2.5,4`） |
| 文件编码 | ⚠️ 本次用 `Set-Content` 改 BUILD_TAG 时**引入了 UTF-8 BOM**（PS 5.1 的默认行为），已检测并剥离；随后核对了前 3 字节与中文注释无损。**改 `.mq5` 一律不要用 `Set-Content`** |

### 42.5 验收预测

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | `icHits` 会增长 | 指标运行足够久后 `icHits > 0`，即证明 IC-CISD 真的触发过 |
| 3 | 其余字段不变 | `closure` / `HTF` / `TGT` / `FIB` 应与 §42.1 的实测值同量级 |

---

## 44. 阶段 21：PD Array 区域**右端**的降噪开关（`v1.50-s28`）

**起因**：用户把 MT5 截图与对象覆盖图对照后反馈"还是有点乱"。
本节先把这个"乱"变成可测量的数字，再决定改哪里 —— 而**测量否掉了我自己的第一直觉**。

### 44.1 先把"乱"量化

数据源：`v1.50-s27` 在 XAUUSD.ct M5 的真实 `TradFi_OBJDUMP`（14 个填充矩形）。
用它们的时间跨度 × 价格高度对可视窗口（**210 个 5 分钟格 × 108 个 0.25 价格格 = 22,680 格**）
做并集：

| 指标 | 结果 |
|---|---|
| **被填充覆盖（含弱化块）** | **46.1%** 的图表面积 |
| 仅"正常"块覆盖 | 43.5% |
| "弱化"块**额外**多盖的 | **仅 2.7%** |
| 单块冠军 `OB_183_176` | 跨 975 分钟 × 11.44 点 = **11,154 格 = 全图 49.2%** |

### 44.2 ⚠️ 我的第一直觉被数据否掉了

我原本判断"**弱化（灰）填充是主要噪声源**"。实测：把它们全部改为不填充**只省 2.7 个百分点** ——
因为弱化块大多**压在正常块之上**，改它们等于在已经被盖住的地方省面积。

**真正的主导因素是"矩形右端一律画到当前 bar"**：一块 OB 就盖掉 49.2%。
这与 §35.4 / §40.2 是同一类教训的第 N 次：**先测，再改；直觉给的优先序往往是错的。**

### 44.3 收窄右端的量化收益（同一份数据）

| 右端策略 | 覆盖率 |
|---|---|
| 一律画到当前 bar（原行为） | 46.1% |
| 收到 起点 + 30 分钟 | **18.8%** |
| 收到 起点 + 60 分钟 | **21.9%** |
| 收到 起点 + 120 分钟 | 26.4% |
| 收到 起点 + 240 分钟 | 32.8% |

单一杠杆即可把覆盖率砍到不足一半。

### 44.4 实现

新增枚举 `ENUM_PD_END` 与两个输入：

| 输入 | 默认 | 含义 |
|---|---|---|
| `InpPDEnd` | `PD_END_NOW` | `到当前 bar`（**= 他的画法**）/ `首次回踩即停` / `固定 N 根` |
| `InpPDRightBars` | `12` | 固定模式下的根数（M5 上 = 60 分钟） |

取右端的唯一实现是 `PdRightEnd(anchorBar, validBar, zLo, zHi, time, high, low)`，
FVG 与 OB 共用（**同一概念一份实现**，同 `CisdOriginBar` / `IsLiquidityTaken` 的规矩）。

两个细节：

1. **`validBar` 与 `anchorBar` 分开传**：回踩扫描与固定长度都必须从区域**成立**的 bar
   （FVG 的确认 bar / OB 的验证 bar）之后算起，否则会数到形成期自己的 K 线。
2. **防退化矩形**：右端若 ≤ 左端，`OBJ_RECTANGLE` 两端同刻画不出来（§40.2 的同类问题），
   故 `PdRightEnd` 末尾强制 `t = time[anchorBar] + 60`。

### 44.5 ⚠️ 为什么默认**不改**

`plan §19.6-D20` 已记录：他的配图里 OB 就是**向右延伸到现价区域**的线，
故"画到当前 bar"**符合他的画法**。所以这是一个**可选的降噪开关**，
不是"改正一个错误" —— 默认保持原行为，用户自己决定要不要收窄。

### 44.6 验收预测（可证伪）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | **事件零影响** | 纯渲染 → CSV **全部数据行逐字不变**（只有新增的 `# pdend` 头部行不同） |
| 3 | 默认无回归 | `InpPDEnd=PD_END_NOW` 时，`TradFi_OBJDUMP` 的 t2 与 s27 逐个相同 |
| 4 | `PD_END_FIXED` 生效 | 右端 = 成立 bar − N 根；实测覆盖率应向 21.9%（N=12）靠拢 |
| 5 | `PD_END_RETEST` 生效 | 右端 = 首次与区间相交的 bar；**若某区域从未被回踩则与 NOW 相同** |
| 6 | 头部自描述 | CSV 新增 `# pdend mode=… rightBars=…` |

### 44.7 用户裁定：**默认改为 `PD_END_RETEST`**（`v1.50-s29`）

§44.5 原本刻意把默认留在 `PD_END_NOW`（因为 D20 记录他的画法就是画到现价区域）。
**用户裁定要改默认**，故 `InpPDEnd` 的默认值改为 **`PD_END_RETEST`**。

这是**知情下的偏离**：用"更贴合他画法"换"可读性"。该取舍如实记录在此，
且**在输入项注释、README、CSV 头部三处**都标明默认已非原行为——
避免日后有人拿"默认设置"当"他的画法"来对照。

#### 44.7.1 ⚠️ 补一个必要条件：**最小宽度下限**

`PD_END_RETEST` 单靠"首次回踩即停"有个退化风险：**回踩完全可能就发生在下一根**，
那样矩形只有 1 根宽 —— 肉眼几乎看不见，**等于把功能删了**（降噪降过头）。

故 `PdRightEnd` 在回踩模式下**强制最小宽度**：

```
hit      = 首次与区间相交的 bar（没找到 ⇒ 与 PD_END_NOW 同）
floorIdx = vb - InpPDRightBars          // 至少要铺到"成立 bar - N 根"
hit      = 更宽的那个（序列方向 index 越小越新，故取 min）
```

于是 `InpPDRightBars` 在两个模式下含义不同（**已写进输入项注释与 README**）：
`PD_END_FIXED` = 延伸根数；`PD_END_RETEST` = **最小宽度保证**。

#### 44.7.2 新增可量化钩子 `STRUCT_PDW`

改默认之后，"到底降下来没有"不能靠肉眼看。故新增一行：

```
STRUCT_PDW mode=PD_END_RETEST rightBars=12 rects=… widthBars min=… avg=… max=…
```

它是**唯一能把降噪效果量化**的钩子，并且能抓出反向故障：
**若 `min` 只有 1~2 根，说明矩形已退化成细缝**（那说明最小宽度没生效或阈值太小）。

#### 44.7.3 验收预测（可证伪）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | **事件零影响** | CSV 全部数据行逐字不变（只有新增的 `# pdend` 头部行不同） |
| 3 | 覆盖率下降 | 默认下填充覆盖率应从 46.1% 明显下降（30 分钟档实测 18.8%，回踩档应同量级或更低） |
| 4 | **未降过头** | `STRUCT_PDW` 的 `widthBars min` **必须 ≥ `InpPDRightBars`**（默认 12）—— 若为 1~2 说明最小宽度未生效 |
| 5 | 从未回踩的位 | 其矩形宽度应与 `PD_END_NOW` 相同（它们仍是有效 POI，不该被砍） |

判据 4 是本次**最该盯**的一条：它的失效模式是"降噪把功能删了"，而**覆盖率下降本身看不出来**——
覆盖率降得漂亮，可能只是因为矩形全都缩成细缝了。

### 44.8 用户再次裁定：默认改为 **`PD_END_FIXED`**（`v1.50-s31`）

看了三模式对比图（`docs/img/2026-09-24-pdend-compare.png`）后，用户裁定**默认改为 `PD_END_FIXED`**
（"看起来更清爽"），`InpPDRightBars = 12`。

**默认值变更史**（已同步写进输入项注释、README、CSV 头部，三处一致）：

| 构建 | 默认 | 依据 |
|---|---|---|
| `s28` | `PD_END_NOW` | 引入开关时保守取原行为（= 他的画法） |
| `s29` | `PD_END_RETEST` | 用户裁定 |
| **`s31`** | **`PD_END_FIXED`** | 用户裁定（看对比图后选"更清爽"的） |

**选 FIXED 而不是 RETEST 的工程理由**（不只是观感）：
`FIXED` 的宽度是**确定值** `N + (anchor − valid)` 根，可预测、可复算；
而 `RETEST` 的宽度依赖真实 bar 数据，且实测**常被最小宽度下限接管**（那个下限恰好就是 FIXED12）
—— 也就是说 RETEST 在多数情况下**本来就会退化成 FIXED**，却多了一层不确定性。

#### 44.8.1 三模式实测覆盖率（同 9 个 PD 矩形 / 200 根窗口）

| 模式 | 覆盖率 |
|---|---|
| `NOW`（到当前 bar） | **44.2%** |
| `FIXED 6` | 6.8% |
| **`FIXED 12`（现默认）** | **8.9%** |
| `FIXED 24` | 11.8% |
| `FIXED 60` | 20.5% |
| `RETEST` | ∈ [8.9%, 44.2%]（严格上下界，非估计） |

> ⚠️ 与 §44.1 的 **46.1%** 不是同一个量：那次是**时间轴且含 4 根 HTF 蜡烛**，
> 本表是**根数轴且剔除 HTF**（它们不随本开关变化，留着只会遮住差异）。
> 用根数轴是有意的 —— **MT5 图表压缩休市，柱数就等于屏幕宽度比例**。

#### 44.8.2 FIXED 模式下的不变量（可证伪）

`widthBars min` **应 ≥ `InpPDRightBars`**，**除非**该区域成立于最近 N 根之内
（右端被钳在最新 bar —— 画不到未来）。例：`FVG_2_0` 的成立 bar 是 0，
故它在 `FIXED 12` 下宽度只有 2 根，这是**正确行为**而非故障。

#### 44.8.3 一处工具坑（本轮踩到）

用 PowerShell 的 `[System.IO.File]::WriteAllLines()` 改 README 时，
它按**环境换行符**（CRLF）重写，于是把一份 **LF** 的 `.md` **整份转成了 CRLF**
（与本仓库其它 `.md` 不一致）。已检测并改回 LF。
**凡改文本文件，一律 `WriteAllText` + 显式 `"\n"`，不要用 `WriteAllLines`。**

---

## 45. 阶段 23：`InpHtfBodyFill` 的百分比**从来没生效过**（`v1.50-s32`）

### 45.1 发现方式：**两个数字对不上**

起因是用户要试 `InpHtfBodyFill = 0`（把 HTF 蜡烛改成空心以降噪）。查代码时发现：

```mql5
color PdFill(const color base, const color bg)
{
   int pct = InpPDFillPercent;      // ← 固定读 PD Array 的百分比
   ...
}
...
color drawClr = doFill ? PdFill(base, bg) : base;   // ← HTF 没传自己的百分比
```

**于是 `InpHtfBodyFill` 只当 `>0` 的开关用，它的数值（25 / 50 / 80）全被忽略**，
真正的混色强度来自 `InpPDFillPercent`。

**证据是数字自相矛盾**（用用户自己那份导出的 `# colors` 行）：

| | 25% 应为 | 30% 应为 | **实测导出** |
|---|---|---|---|
| `htfUp` `#26a641` | `201,233,208` | **`190,228,198`** | **`190,228,198`** |
| `htfDn` `#f85149` | `253,212,210` | **`253,203,200`** | **`253,203,200`** |

导出头部明明写着 `htfBodyFillPct=25`，实测色却与 **30%** 逐位吻合 ⇒ 用的是 `InpPDFillPercent`。

> 这与本会话反复出现的主题是同一条：**该核对的是数字之间是否自洽，而不是代码看起来对不对。**
> 编译 `0 errors`、运行无告警、颜色也"看着正常"——只有把"声称的百分比"与"算出来的色值"
> 放在一起比，矛盾才显形。

### 45.2 修法

`PdFill` 改为**显式收百分比**：`color PdFill(const color base, const color bg, const int pct)`，
全部 6 个调用点各自传入正确的量：

| 调用点 | 传的百分比 |
|---|---|
| `fillFVG` / `fillOB` / `fillWeak`（PD Array） | `InpPDFillPercent`（30） |
| HTF 实体的 `drawClr` | **`InpHtfBodyFill`（25）** ← 修复点 |
| `# colors` 头部的 `derivedFill` | 逐类各传各的 |

**对默认观感的影响**：HTF 实体从"30% 混色"变成"**25% 混色**"（略淡一点），
即**终于等于它的输入值**。PD 侧完全不变（同一条路径、同一个百分比）。

### 45.3 ⚠️ 对"改成空心"这个用法的一个必须提醒

`InpHtfBodyFill = 0` 时 `drawClr = base` —— 即轮廓/影线/时间标签会从**淡色**变成**原色**
（亮绿 `#26a641` / 亮红 `#f85149`）。所以：

- **填充面积**确实降下来（实测 10.8% → 8.9%，相对降 18%）
- 但**线条的抢眼程度反而上升**

**要真正"更轻"的淡色空心蜡烛**，两个设置要一起改（`fill=0` 时轮廓色就是用 `InpColorHtf*` 画的）：

```
InpHtfBodyFill = 0
InpColorHtfUp  = C'201,233,208'    // 25% 混色值
InpColorHtfDn  = C'253,212,210'
```

### 45.4 验收预测（可证伪）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：`0 errors / 0 warnings` |
| 2 | **头部不再自相矛盾** | 导出 `# colors` 的 `derivedFill htfUp=` 应变成 **`201,233,208`**（= 25%），而不再是 `190,228,198`（= 30%） |
| 3 | PD 侧无回归 | `derivedFill fvg=` 仍为 `179,239,233`（30%，逐字不变） |
| 4 | `InpHtfBodyFill` 真可调 | 设成 60 后重导出，`derivedFill htfUp=` 应向 `125,201,131` 靠拢（60% 混色） |
| 5 | 事件零影响 | 纯渲染 → CSV 全部数据行逐字不变 |

---

## 43. 阶段 18b 决策提案：closure + POI 门禁（**待你裁定，尚未实施**）

他的原文（research §1 逐字）：

> "A swing is only valid when it has both: a point of interest and a valid closure
> (candle 2 or candle 3). **If either is missing, the swing point is ignored.**"

现交付的是 **18a**：closure **只检测、只标注、进 CSV**，**不影响结构**。
本节的目的是让你**不必读代码就能决定**要不要做 18b。所有数字都来自 `v1.50-s23` 的真实导出
（XAUUSD.ct M5，58 个节点），**不是估算**。

### 43.1 先看影响面（实测）

| 门禁档位 | 存活节点 | 剔除 |
|---|---|---|
| 现状（18a，无门禁） | 58 / 58 | 0 |
| **18b-1：只要求 closure** | **46 / 58 (79.3%)** | 12 (20.7%) |
| 18b-2：closure **且** POI | **26 / 58 (44.8%)** | **32 (55.2%)** |

> ⚠️ 18b-2 那一行的 POI 判定**用的是我临时设的口径**（节点价格被某个 FVG/OB 区间覆盖，
> 且 bar 距离 ≤ 20）。**他只列了 POI 的"种类"**（FVG、前高前低、等高等低、流动性扫荡、
> premium/discount…），**没有给任何机械判据**。

**⚠️ 而这个口径的敏感度是实测的，不是猜测** —— 同一批 58 个节点，换几条**同样说得通**的口径：

| POI 口径 | 存活节点 | 存活率 |
|---|---|---|
| 价格落在区间**中间 50%** + bar 距 ≤ 20 | 23 / 58 | **39.7%** |
| 价格被区间覆盖 + bar 距 ≤ 5 | 18 / 58 | **31.0%** |
| 价格被区间覆盖 + bar 距 ≤ 20 | 35 / 58 | **60.3%** |
| 价格被区间覆盖 + bar 距 ≤ 50 | 41 / 58 | **70.7%** |
| **只看 bar 距 ≤ 20（不看价格）** | 58 / 58 | **100.0%** |

**存活率跨 31% ~ 100%（69 个百分点）。** 也就是说 18b-2 一旦实施，
**它的行为主要由一条我发明的容差决定**，而不是由他的规则决定 ——
这本身就是该档位最大的问题，比"剔除多少"更值得关注。

### 43.2 两档各自的"可信度"不一样

| | 18b-1（closure） | 18b-2（+POI） |
|---|---|---|
| 依据强度 | **强**：closure 的定义逐字可溯，且已实现、已真机验收（§42.1） | **弱**：POI 只有种类清单，机械判据得**我发明** |
| 影响面 | −21%，可接受 | **−55%，且实测随口径在 31%~100% 存活率之间漂移** |
| 是否引入新自定参数 | 否 | **是**（距离阈值 + 覆盖判据，且它主导结果） |

### 43.3 ⚠️ 一个必须先说的**架构障碍**：门禁不能在后验层做

现状的三层顺序是：主循环建节点（状态机驱动）→ 后验层算 closure（`ComputeClosures`）→ 渲染。

但门禁是"**节点是否成立**"的条件，而 closure 现在是**对最终节点表**算出来的 ——
若在后验层删节点，节点表变了，closure 也跟着变 ⇒ **是个不动点问题**，不是一次过滤。

**故 18b 必须把 closure 判定搬进主循环**（节点确认处）。好消息：节点确认需要"右侧邻居"，
那时 `b-1`（C3）已经存在，判定所需的数据是齐的。
坏消息：这是**架构改动**，而不是加一个 `if`。

### 43.4 无论选哪档，成本是一样的（与 v1.49-s11 同级）

1. **`docs/baselines/` 全部基线失效** —— 事件集合会变，必须重测重归档；
2. 不能用"旧事件逐字不变"作验收判据（那正是本次要改的东西）；
3. 应改用的替代判据：**节点数下降方向明确**（18b-1 预期 −15~25%；18b-2 预期 −45~65%），
   且**被保留的节点 100% 带有效 closure**（18b-1）/ **100% 同时带 closure 与 POI**（18b-2）。

### 43.5 我的建议

> **先做 18b-1，单独一轮，单独归档；POI 那半边暂缓。**

理由：closure 半边**有逐字依据、已实现、已验收**，加个开关就能测，且影响面（−21%）在可接受范围；
POI 半边会**逼我发明判据**，而实测显示**同样说得通的口径下存活率能从 31% 到 100%**——
在最没有依据的地方引入**主导结果**的发明，方向是反的。
若你先要 POI 那半边，我需要你给一条口径（或接受我把它标成**纯自定**）。

### 43.6 需要你回答的

| 选项 | 含义 |
|---|---|
| **A（推荐）** | 做 18b-1（closure 门禁），**默认关**，可开关；POI 暂缓 |
| **B** | 做 18b-2（closure + POI），并接受其中的 POI 判据为**自定口径** |
| **C** | 两档都做，各自独立开关 |
| **D** | 都不做，18a 的"只标注"就是终态（那 §38.3 那条门禁缺口将**永久保留**并如实标注） |

> 在你答复之前，**我不动这段代码** —— 仓库自己的决策流程要求这类变更先裁定再动。

### 43.7 裁定（2026-09-24）：**D —— 不做门禁**

**用户原话**：「无需门禁」。

| 项 | 结论 |
|---|---|
| 18b-1（closure 门禁） | **不做** |
| 18b-2（closure + POI 门禁） | **不做** |
| 终态 | 18a：closure **只检测、只标注、进 CSV**，对结构 / 偏置 / 目标**零影响** |
| §38.3 那一行缺口 | **永久保留**，并改标为"用户裁定不做"（不再是"未实现"） |

**理由（记录在案，避免将来被当成遗漏重新提案）：**
1. 这一条保真度**要在最没有依据的地方引入主导结果的发明** —— POI 他只有一张种类清单，
   而同一套说法下实测存活率能从 31% 到 100%（§43.3）。方向是反的。
2. 实现它会动**全部下游结构**（protected swing / BOS·MSS 归属 / 结构段划分），性质同 v1.49-s11 那次整组删除。
3. closure 半边虽有逐字依据，但单独做（−20.7%）同样会让**既有归档失去可比性**，
   收益只是"更贴他的口径"，代价是历史记录全部作废。

**已落地为不可逆标注（防止将来被重新提案）：**

| 位置 | 内容 |
|---|---|
| CSV 头部 | `gate=NONE(18a,no state impact;18b+POI-declined-by-user)`（`Structure.mq5:981`） |
| `ComputeClosures()` 顶部 | 「阶段 18b 终态：不做门禁……**不要再以补全保真度为理由加回来 —— 这是已裁定的取舍，不是遗漏**」（`:1731-1736`） |
| 输入项注释 | `InpShowClosures = true // 标注 C2 / C3 收盘确认（只标注，不做门禁）`（`:465`） |
| 构建 | `v1.50-s35`；`0 errors, 0 warnings`；`mq5=776800C7BF5F` / `ex5=226090F3C900` match=True；`audit_state.ps1` → `PASS (0 problems)` |

⚠️ 本轮**只改标注与注释，零行为变更**：closure 的判定路径、节点表、CSV 数据行一字未动
（`# closure` 头部的 `gate=` 字段描述的是**已裁定的终态**，不是新开关）。





---

## 46. 阶段 24：HTF 蜡烛拆分为**独立副图指标**（`TradFi_HTFCandles.mq5`，`v1.00-s1`）

**起因**：主图填充覆盖率从 46.1% 降到 10.8% 之后，用户看出 **HTF 蜡烛成了残余噪声里最大的一块**，
提议"不合并到主图，用一个小图"。而实测数据支持这个直觉 —— 但**只在新的基线下**：

| 基线 | 只剩 PD（HTF 移走） | PD + HTF（现状） | 移走净减少 |
|---|---|---|---|
| 旧行为 `NOW` | 44.2% | 44.4% | **仅 0.2 pp** |
| 现默认 `FIXED 12` | 8.9% | **10.8%** | **1.9 pp（相对降 18%）** |

> ⚠️ **同一个建议，在两个基线下结论相反**。旧基线下那块 183 根宽的 OB 盖住了一切，
> HTF 藏在它底下（0.2 pp）→ 会得出"不值得做"的错结论。**基线变了，评估就必须重做。**

### 46.1 必须写明的取舍

副图有**自己的价格刻度**，故**失去"H4 价位 vs 入场位"的直接对应** ——
而这正是该功能存在的理由（他的条目原文是 *"View HTF candles **on your entry timeframe**"*）。
故**主图叠加保留为可选项**（`InpStructure.InpShowHTFCandles`），两者并存、由用户选。

### 46.2 两个决定了画法的技术坑

1. **副图刻度由 buffer 驱动**：没有 plot 的副图刻度退化 → 对象落到窗外（表现就是"空副图"）。
   故保留两个 **`clrNONE` 隐藏 buffer**（逐图-bar 载 H/L，只为定标）。
   ⚠️ 并**额外用 `IndicatorSetDouble(INDICATOR_MINIMUM/MAXIMUM)` 显式兜底** ——
   因为"不可见的 plot 是否仍参与自动定标"**未在终端上验证过**。
   两者一致时互不干扰；前者失效时后者保证蜡烛可见。**"未验证的前提"必须配一条显式兜底，而不是赌它成立。**
2. **副图共享主图时间轴，而 buffer 是"每根 bar 一支烛"**：`DRAW_CANDLES` 把 H4 的 OHLC 铺到
   它覆盖的 48 根 M5 bar 上，得到的是 48 支同样细烛拼成的**实心色块**，不是蜡烛剪影。
   → 蜡烛必须用**对象**画。对象用 `ChartWindowFind()` 返回的**本副图**编号创建；
   若不指定窗口号，对象会建到主图上 —— **那就等于没拆**。

### 46.3 顺带把构建脚本参数化

`mq5debug.ps1` 原先把文件名写死成 `Structure`。现加 `-Name` 参数（默认仍是它，**原用法零改动**）：
`.\mq5debug.ps1 -Name TradFi_HTFCandles`。

同时修掉一处**陈旧断言**：原 INIT 行匹配用的是写死的版本字面量（`'TradFi_Structure v1\.48'`），
在 INIT 格式改版后**早已匹配不到** —— 而"匹配不到"与"指标没运行"在输出上不可区分。
现改为按**文件名 + `build=`** 匹配（且保持纯 ASCII，遵硬约定 6）。

### 46.4 验收预测（可证伪）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 编译 | ⚠️ **已测**：两个指标均 `0 errors / 0 warnings`，哈希一致 |
| 2 | 脚本回归 | 不带参数跑 `mq5debug.ps1` 仍编译 `Structure` 且 `-Verify` 通过 |
| 3 | **落在副图** | INIT 行 `subwindow=` **必须 ≥ 1**；若为 0 说明它被当主图指标加载 |
| 4 | 对象数 | `InpDebugShow=true` 时 `TradFi_HTFRENDER … objs=` 应等于 `expect = N × (3 + 标签?1:0)`（默认 6×4=24） |
| 5 | **刻度生效** | 副图应看到完整的 HTF 蜡烛（不是空白、也不是被压成一条线）—— 这是兜底那一项的检验点 |
| 6 | 主图无回归 | `Structure` 的事件 CSV 一行不变（副图是独立指标，不触碰主指标） |
| 7 | 卸载清理 | 移除副图指标后，`TradFiHTF_` 前缀对象应全部消失 |

⚠️ 判据 5 是**唯一我无法在本地验证**的一条（需要终端渲染）。
若副图空白，第一顺位怀疑对象就是 §46.2-①，其次是 `g_win` 是否拿到了正确的副图编号。

---

## 47. 阶段 25：HTF 蜡烛改画**主图右侧未来留白区**（`v1.50-s33`）

**用户原话**：「把 HTF 蜡烛画到主图右侧的未来留白区」（在"再拆一个副图指标"与"右侧留白区"之间选了后者）。

### 47.1 路线取舍（与 §46 的关系）

§46 已把 HTF 蜡烛拆成**独立副图指标** `TradFi_HTFCandles.mq5`（能跑、`0 errors`、已部署），
但副图**有自己的价格刻度**：H4 蜡烛的高低点与主图入场位的**水平对应关系被切断**，
而这恰恰是这条功能存在的理由（他的条目原文 *"View HTF candles **on your entry timeframe**"*）。
且 MT5 的副图**永远只能竖着堆在主图下方**（没有"把副图放到右边"的 API —— 那是 API 边界，不是实现问题）。

⇒ 本轮改走第三条路：蜡烛仍画在**主图窗口**、用主图价格刻度（保住 H/L 对齐），
但时间坐标落在 `time[0]` **之后**的未来留白区 —— 既不压住真实 K 线，也不需要副图。

⚠️ **代价（写在明面上）**：蜡烛落在**尚未发生的时间**上，时间轴/十字线会把这段标成未来时间。
本功能只画矩形与文本，不产生任何依赖"未来"语义的对象，故代价被限制在观感范围内。

### 47.2 三个坑（都不是猜的，各有证据）

**① `CHART_SHIFT_SIZE` 是 `double` 属性，不是 `integer`。**（编译实测，非文档转述）

第一版写成 `ChartGetInteger(0, CHART_SHIFT_SIZE)`，编译报：
```
Structure.mq5(1519,50) : error 262: cannot convert enum
Structure.mq5(1519,31) : error 199: wrong parameters count
```
`error 262` 说明这个常量**存在**、只是属于**另一个枚举**（不是"未声明"）。
为把"它到底属于哪个枚举"变成实测而不是推断，写了一个探针（`%TEMP%\mq5probe\probe.mq5`）：

```mql5
bool   b = (bool)ChartGetInteger(0, CHART_SHIFT);
double d = ChartGetDouble(0, CHART_SHIFT_SIZE);   // ← 关键行
ChartSetInteger(0, CHART_SHIFT, b);
ChartSetDouble(0, CHART_SHIFT_SIZE, d);
```
结果：`Result: 0 errors, 1 warnings`（唯一 warning 是"探针没有 plot"）。
⇒ 定论：`CHART_SHIFT_SIZE` 用 `ChartGetDouble` / `ChartSetDouble`，取值区间 2.0%..50.0%（步长 0.5%）。

**② 留白区宽度必须以"像素实测"为主口径，"根数公式"只能兜底。**

条数公式 `marginBars = visBars × shift/(100−shift)` 依赖一个**未文档化**的前提：
`CHART_VISIBLE_BARS` 返回的条数**是否已包含留白区**。两种语义下的结果差一个常数倍，
而错法的表现是"整排蜡烛被推到屏幕外"—— **看起来与"根本没画出来"一模一样**，无法从现象反推原因。

⇒ `HtfRightSlotSec()`（`Structure.mq5:3932`）主口径改为直接测量：
把最新两根图 bar 经 `ChartTimePriceToXY()` 映射到屏幕像素求出 `pxPerBar`，
留白区左界 = `x0 + pxPerBar`（最新 bar 的**右缘**）、右界 = `CHART_WIDTH_IN_PIXELS`，
两者之差除以根数、再按 `pxPerBar` 换算成秒。条数公式降为兜底（图表尚未布局时用）。
每次槽宽变化打一行 `STRUCT_HTFPOS`（`HtfLogSlot()`，`:3986`），**故意让"画到屏幕外"与"没画"可分辨**。

**②-bis 事后实测裁定（`v1.50-s33` 真实运行日志，XAUUSD.ct M1，17:35:26）：**
```
STRUCT_HTFPOS slot=276s candles=4 src=1 pxPerBar=16 marginPx=295 slotPx=73
              shiftOn=true shiftSize=20.0 visBars=79
```
- `src=1` ⇒ 走的是像素实测（不是兜底）；`slotPx=73 × 4 ≈ marginPx=295` 自洽；
  `slot = (295/4)/16 × 60s = 276.6 → 276s` 与日志一致（M5 图同理：`(295/4)/16 × 300 = 1382s`）。**公式无内部矛盾。**
- 用条数公式反推：`79 × 20/(100−20) = 19.75 根 ≈ 316 px`，与实测 `295 px` 同量级（差 7%，
  差在"跳过正在形成的那根"与半根偏移）；而"visibleBars 已含留白区"这一读法给的是
  `79 × 20/100 = 15.8 根 ≈ 253 px`，明显偏小。
  ⇒ **实测裁定：`CHART_VISIBLE_BARS` 不含留白区。** 这条以后可以直接用，不必再靠兜底猜。
- 两张图挂上时 `Chart Shift 原值 on=true size=20.0` —— 原值已达标，故本轮**没有实际改动**用户图表设置（副作用为零）。

**③ 自动开 Chart Shift 有副作用 ⇒ 必须还原。**
右侧模式下若 Chart Shift 关着，留白区宽度为 0 ⇒ 蜡烛全在屏幕外。
故 `OnInit`（`:1520`）记下 `CHART_SHIFT` / `CHART_SHIFT_SIZE` 原值、打开它、并把 shift 提到 25%，
`OnDeinit`（`:1545`）**原地还原**。"不给用户留下副作用"是这条自动化的前提。

### 47.3 缩放不产生新 bar ⇒ 必须挂 `CHARTEVENT_CHART_CHANGE`

`RenderScene` 只在**全量帧**（新 bar）跑，而缩放/平移**不产生新 bar**。
留白区宽度随缩放变化 ⇒ 不挂事件，整排蜡烛会**停在旧坐标直到下一根 bar**（硬约定 3 的同一类错误）。
故新增 `OnChartEvent`（`:1561`）：只换坐标、**不注册场景集**
（对象键用的是蜡烛**真实开盘时间**，与全量帧同名，故不会被回收段误删）。

### 47.4 要求 → 是否满足 → 证据（硬约定 12）

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5` 行号） |
|---|---|---|---|
| 1 | 蜡烛画在主图**未来留白区** | ✅ | `HtfRightSlotSec()` :3932；几何 `DrawHtfCandles()` :4061（`t1 = tBase + 1 图 bar + k×slot`） |
| 2 | 保住价格刻度对齐（不拆副图） | ✅ | 对象仍由主图窗口创建（`OBJ_PREFIX`，不传 sub_window） |
| 3 | 不压住最新真实 K 线 | ✅ | 起点 = `tBase` + 1 根图 bar（`DrawHtfCandles` :4061 与 `UpdateHtfLastFast` :4110 两处一致） |
| 4 | 缩放后**当帧**重排 | ✅ | `OnChartEvent` :1561；指纹含 `(g_htfSlot != g_lastHtfSlot)` :4295 |
| 5 | 不改变任何判定 / CSV 数据行 | ✅ | 纯渲染；仅 `# render` 头部新增 `place=` 字段（:914）与 `# switches` 末尾新增 `htfPlace=`（:930） |
| 6 | 卸载还原 Chart Shift | ✅ | `OnDeinit` :1545-1549 |
| 7 | 可回退到他的画法 | ✅ | `InpHtfPlacement` :246（默认 `HTF_PLACE_RIGHT`，改 `HTF_PLACE_OVERLAY` 即回原样） |
| 8 | 编译 0 错 0 警 + 部署哈希一致 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=8B3E1168BD2A` / `ex5=C7EDEF905681`（`-Verify` match=True） |
| 9 | 静态自检 4 项 | ⚠️ 已测 | `audit_state.ps1` → `RESULT: PASS (0 problems)` |

### 47.5 验收预测（可证伪）

| # | 判据 | 期望 | 若不符，第一顺位怀疑 |
|---|---|---|---|
| 1 | INIT 行出现 `STRUCT_HTFPOS` | `src=1`（像素实测） | 图表未布局 → 落到 `src=2` 兜底 |
| 2 | 留白区宽度 | `marginPx > 0` 且 `slotPx ≈ marginPx / candles` | Chart Shift 没开（同一行有 `shiftOn=`） |
| 3 | 槽宽 | `slot` ≥ 1 根图 bar 的秒数 | `marginPx` 太小（缩放过大） |
| 4 | **可见性**（我无法本地验证） | 4 根 H4 蜡烛**完整落在右侧空白区**、不压最后一根 K 线 | "最新 bar 右缘 = `x0 + pxPerBar`"这一假设 → 改为 `x0 + pxPerBar/2` |
| 5 | 缩放 | 拖动时间轴缩放后蜡烛**当帧重排**（不是等下一根 bar） | `OnChartEvent` 未被触发 |
| 6 | 移除指标 | Chart Shift 回到**原值** | `g_shiftSaved` 分支 |

⚠️ 判据 4 是**唯一需要终端渲染**的一条；`STRUCT_HTFPOS` 那行日志就是它的取证工具。

### 47.6 副图指标的去留

`TradFi_HTFCandles.mq5`（§46）**保留，但不再是默认路线**：它适用于"必须同时看两个周期的整体形状"的场合，
代价是失去价格刻度对齐。两个实现共享同一套输入语义（周期 / 根数 / 宽度 / 填充 / 时间标签），
故从主图切到副图不需要重新学一遍参数。

### 47.7 与 §43（closure + POI 门禁）的关系

本轮**没有**动判定层 —— 判据 5 的"事件 CSV 数据行逐字不变"就是它的证据。
§43 的 18b 决策**已裁定为 D（不做门禁）**，见 §43.7 —— 判据层因此**永久**保持现状。

---

## 48. 修正：留白区内蜡烛顺序**反了**（`v1.50-s34`）

**用户反馈**：「HTF 蜡烛的顺序是不是反了」。**是反的**，已修。

### 48.1 错在哪

第一版排法是"**离价格最近 = 最新**，越旧越靠右"，当时写的理由是"保持与价格的连续性"。
但主图时间轴、事件标签、以及图上**所有**其它元素都是**从左往右递增**，
而这条规则让**时间标签从右往左递减** —— 在一张到处"左旧右新"的图上，
这一条逆序会被一眼看成画错了。

⚠️ 教训：**"连续性"是我自造的理由，逆序是客观事实。**
自造理由不能用来覆盖一条全图通行的约定；当两者冲突时，先服从约定。

### 48.2 改法

改成 **左→右 = 由旧到新**（`k=0` 的"正在形成的那根" → **最右槽**）：

| 位置 | 改动 | 行号 |
|---|---|---|
| `DrawHtfCandles()` | 槽位下标 `k` → `(n − 1 − k)`（`n = InpCandleCount`） | :4085 |
| `UpdateHtfLastFast()` | 形成中的那根占 `(n − 1)` 号槽（最右） | :4138 |

若你要的就是"最新那根贴着价格"，把这两处换回 `k` / `0` 即可（各一行）。

### 48.3 证据

| # | 要求 | 是否满足 | 证据 |
|---|---|---|---|
| 1 | 左→右 = 由旧到新 | ✅ | `Structure.mq5:4085`、`:4138` |
| 2 | 时间标签随之递增 | ✅ | 标签文本 = 蜡烛**真实开盘时间**（`keyTime = tReal`，`:4103` 一带），不再随槽位变动 |
| 3 | 只有顺序变、槽宽/起点不变 | ✅ | `t1 = tBase + 1 图 bar + slotIdx × g_htfSlot`，`slotIdx ∈ [0, n−1]` 覆盖同一段留白 |
| 4 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=492FE7656B44` / `ex5=6108BC381EAE` match=True；`audit_state.ps1` → `PASS (0 problems)` |

⚠️ §47.5 判据 4（"蜡烛肉眼可见、完整落在右侧空白区"）**已由用户实机确认**（否则不会看到顺序问题）；
同时 `STRUCT_HTFPOS` 日志给出 `src=1 / marginPx=295 / slotPx=73 / shiftOn=true`，两边独立吻合。

### 48.4 运行确认（用户："好了，可以了"）

| 取证点 | 日志证据（XAUUSD.ct M1，`20260924.log`） |
|---|---|
| s34 已加载 | `17:38:01.456 … 已初始化 \| build=v1.50-s34` |
| 走像素实测 | `STRUCT_HTFPOS slot=276s candles=4 src=1 pxPerBar=16 marginPx=295 slotPx=73 shiftOn=true shiftSize=20.0 visBars=79` |
| **缩放当帧重排**（§47.5 判据 5） | 同一实例内槽宽随缩放变化并被重新记录：`17:36:19 slot=276s` → `17:36:35 slot=261s (marginPx=279)` → `17:37:48 slot=276s` ⇒ `OnChartEvent` 确实在缩放时重算了留白区 |
| 用户裁定 | 「好了，可以了」⇒ 顺序问题已解决 |

⇒ §47 与 §48 的**全部可本地验证项 + 唯一的终端渲染项均已取证闭合**。

### 48.5 仍未闭合的一项（与本轮无关）

`§43 阶段 18b`：closure + POI 门禁 —— **已裁定为 D（不做）**，并在代码 / CSV / 输入注释三处落地为不可逆标注（§43.7）。

---

## 49. 阶段 26：closure 的**多空方向**显式化（`v1.50-s36`）

**用户提问**：「当前的 closure 有标注是空头的还是多头的吗」——**有，但标签文字里没有**，只能从位置与颜色反推。

### 49.1 改动前的三个通道（都会，但都不直接）

| 通道 | 是否表达多空 | 证据 |
|---|---|---|
| CSV `dir` 列 | ✅ 显式 `UP`/`DOWN` | `Structure.mq5:1137`（与其它事件类型共用该列） |
| 图上**位置** | ✅ 隐式：`DIR_UP` → 标签在 swing **低点下方**；`DIR_DOWN` → **高点上方** | `:4731` |
| 图上**颜色** | ❌ 表达的是"**顺/逆当前偏置**"（逆向压暗为 `InpColorWeakBreak`），子类型靠 C2 绿 / C3 琥珀 | `:4707-4709` |
| Debug 日志 | ✅ `CLOSURE event: … dir=UP/DOWN`（需 `InpDebugShowRef`） | `:1659-1660` |

⇒ **缺口**：一个悬空的 `C2` 标签，若不去看它在低点还是高点、也不知道当前偏置，就判断不出多空。

### 49.2 用户裁定（2026-09-24）

| 问题 | 裁定 | 落地 |
|---|---|---|
| 图上是否显式标多空 | **标签加方向记号**，保留现有配色 | `tag += (dir == DIR_UP) ? "▲" : "▼";`（`:4726`） |
| `C2-CONT` 的 `dir` 语义 | **保持现状**（= swing 侧），以文档写清 | CSV 头部 `# closure`（`:982-983`）+ README |

新增标签形态：`C2▲` / `C2▼` / `C2-CONT▲` / `C2-CONT▼` / `C3▲` / `C3-▼` / `C3+▲`（后缀 `+`/`-` 仍是 C4 是否守住 C3 均衡位）。CSV 的 `state` 列**不变**、`dir` 列**不变**。

### 49.3 字形不是"看着像能显示"——两条独立证据

用户拒绝了 ASCII 兜底（`^`/`v`）的前提是我能证明符号真能显示。故做了两次实测：

| # | 检验 | 方法 | 结果 |
|---|---|---|---|
| 1 | 字体是否含该字形 | WPF `GlyphTypeface.CharacterToGlyphMap.ContainsKey(0x25B2/0x25BC)` | Arial / Tahoma / Segoe UI / Consolas **均 True**（另测：`U+25B4`/`U+25BE` 小三角在 Arial 为 **False**，故**不用**它） |
| 2 | 字形是否活着进了二进制 | 在 `TradFi_Structure.ex5` 里找 UTF-16LE 码位字节 | `B2 25` 与 `BC 25` **均命中** ⇒ 字面量没有被编译器丢弃或转义 |

⚠️ 而"指标到底用哪个字体"**不是猜的**：文字对象由 `UpsertText()` 固定 `OBJPROP_FONT = "Arial"`（`:3578`），故第 1 项直接对 Arial 的结论有效。
⚠️ 仍缺的第三条腿是**终端实际渲染**（我看不到屏幕）—— 若你看到的不是三角而是方框，说明 MT5 用了字体回退，那就退回 `^`/`v`。

### 49.4 `dir` 语义坑（本次新发现，已在文档固定）

CLOSURE 行的 `dir` 表示"**这个 swing 是哪一侧**"（low → `UP`），**不是**信号方向：

| 子类型 | `dir=UP` 的实际含义 | 与信号方向 |
|---|---|---|
| `C2-REV` | 扫破前低后收回 → 看涨反转确认 | ✅ 一致 |
| `C3` | C3 收在 C2 实体之上 → 看涨 | ✅ 一致 |
| **`C2-CONT`** | 扫破前低**并继续收在其下** → **看跌延续** | ❌ **相反** |

⇒ 按 `dir=UP` 单独筛"多头"会把 `C2-CONT` 一并捞进来，必须**配合 `state` 列排掉 `C2-CONT`**。
裁定：**不翻转 `dir`**（翻转会让历史归档与新归档在 `dir` 过滤下不可比），只在 CSV 头部与 README 写明。

### 49.5 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据 |
|---|---|---|---|
| 1 | 标签文字直接可读多空 | ✅ | `:4726`；`▲`=多（swing low 侧）、`▼`=空 |
| 2 | 保留原有"C2 绿 / C3 琥珀 / 逆偏置压暗"配色 | ✅ | 配色行未改（`:4707-4709`） |
| 3 | 字形可显示（非猜测） | ✅ 两条独立证据 | §49.3（Arial 字形表 + ex5 字节） |
| 4 | CSV `state` / `dir` 列**零变化** | ✅ | 只碰标签字符串；`:1110`、`:1137` 未改 |
| 5 | 判定层零影响 | ✅ | 改动全部在 `if(InpShowClosures)` 渲染块内 |
| 6 | `dir` 语义坑写进可自证的地方 | ✅ | CSV 头部 `:982`、README closure 条 |
| 7 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=E051877C9798` / `ex5=82C8AFD0873E` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 49.6 验收预测（可证伪）

| # | 判据 | 期望 | 若不符 |
|---|---|---|---|
| 1 | 图上标签 | 每个 closure 标签末尾出现 `▲` 或 `▼` | `▲`/`▼` 显示成方框 → 换 ASCII 兜底 |
| 2 | 方向与位置一致 | 低点下方的标签必带 `▲`、高点上方必带 `▼` | 渲染取值与 `dir` 不一致 → 查 `g_result.closure[k].dir` |
| 3 | 后缀共存 | `C3+▲` / `C3-▼` 等两段后缀同时出现，顺序固定为"子类型 → C4 结果 → 方向" | — |
| 4 | CSV 不变 | 同一窗口导出，**除头部 `build=` 与新 `# closure` 子句外**数据行逐字相同 | 说明改动漏进了判定层 |

---

## 50. 阶段 27：让"看图"成为可复验动作 —— `Shift+S` 图表快照（`v1.50-s37`）

**用户提问**：「你可以看到这个指标在 MT5 中画的图吗」

**答案是不能。** 我没有终端的视觉通道 —— 这不是谦虚的说法，它有一个**具体的技术后果**：

### 50.1 之前我到底靠什么在判断"画成什么样"

| 证据类型 | 具体形式 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| **数据层** | `TradFi_OBJDUMP`（逐条矩形：名字/颜色/填充/时间/价格）、`TradFi_RENDER`（每类对象计数）、`TradFi_CLOSURE`（子类型分布）、`STRUCT_PDW`（矩形宽度分布） | 对象**画没画**、颜色是多少、几何在哪 | "好不好看""挤不挤" |
| **算术层** | `PdFill(base,bg,pct)` 的混色结果我自己算 | 填充色的**精确值** | 屏幕上的实际观感 |
| **像素层** | ——（本次之前是**空白**） | | 字形、遮挡、密度、整体清爽度 |

⚠️ 所以 §49 那类"字形会不会显示成方框"的问题，我只能把"字体是否含该字形"（WPF 字形表）与"字面量是否进了二进制"（ex5 字节）两条腿摆出来 —— **第三条腿（终端渲染）始终悬空**。
⚠️ 更早的一次教训已经写进计划：我从一张**被缩小的截图**上"读出"的色相（洋红/奶油色）是错的，实测调色板全是 `RGB ≥ 179` 的粉彩。**像素层结论不能靠猜，只能靠原始图。**

### 50.2 做法：让指标自己把图交出来

| 项 | 决定 | 理由 |
|---|---|---|
| 触发 | **图表聚焦时按 `Shift+S`**（图表 PNG）/ **`Shift+D`**（事件 CSV） | 裸字母在 MT5 图表上有内建语义；`CHARTEVENT_KEYDOWN` 是 MT5 给指标的官方热键通道 |
| 输出 | `MQL5\Files\Structure_snap_<品种>_<YYYYMMDD_HHMMSS>.png` / `…\Structure_events_<品种>_<周期>.csv` | 只写终端自己的沙箱，**不抓屏幕**、不含窗口外内容、不要求 MT5 在最前 |
| 开关 | `InpHotkeys = true`（`v1.50-s38` 由 `InpSnapShiftS` 更名而来） | 纯诊断动作，默认开（不想要时关掉即可，无其它副作用） |
| 自证 | 打印 `STRUCT_SNAP ok=… file=… size=… path=…` | "文件到底存哪"不靠猜（终端/测试器/便携模式路径不同） |

### 50.3 三个"看着能行其实会静默失败"的坑

1. **文件名不能用 `TimeToString()`** —— 它产出 `2026.09.24 17:55:03`，`:` 与空格在 Windows 上非法，
   写盘会**直接失败而不报错**，现象是"按了没反应"。改为自己拼 `%04d%02d%02d_%02d%02d%02d`，
   并把品种名里的 `.`（`XAUUSD.ct`）换成 `_`（否则与扩展名混淆）。
2. **按键"没送到"与"送到了没识别"必须可分辨** —— 否则两者在现象上都是"按了没反应"。
   故未命中的按键也回显（每次加载最多 20 条）：`STRUCT_SNAP key=… shiftRaw=… ctrlRaw=… (未命中，仅回显)`。
   （这条是 §35 那条教训的同型：**把两种不同的失败折叠成同一个现象，等于放弃了诊断。**）
3. **不依赖未验证的符号约定** —— `TERMINAL_KEYSTATE_SHIFT` 按下时返回 `-1` 还是 `1` 我没有一手依据，
   故判据写 `shiftRaw != 0`，对两种约定都成立。

### 50.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据 |
|---|---|---|---|
| 1 | 一个按键即可导出当前图表 | ✅ | `OnChartEvent` 的 `CHARTEVENT_KEYDOWN` 分支（`Structure.mq5:1611`）→ `SnapChart()`（`:1576`） |
| 2 | **不抓屏幕**、不含窗口外内容 | ✅ | `ChartScreenShot(0, …)`（只渲染本图表）；落盘目录由 `TERMINAL_DATA_PATH` 打印 |
| 3 | 落盘路径可自证 | ✅ | `STRUCT_SNAP … path=…` 日志行 |
| 4 | 按键事件可诊断 | ✅ | 未命中回显（前 20 次） |
| 5 | 不干扰既有行为 | ✅ | `CHART_CHANGE` 分支未改语义；按键分支在未命中时直接 `return` |
| 6 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=76D44B18472D` / `ex5=9B3A2323A263` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 50.5 验收预测（可证伪）

| # | 判据 | 期望 | 若不符 |
|---|---|---|---|
| 1 | 热键送达 | 按 `Shift+S` 后日志出现 `STRUCT_SNAP ok=true` | 只剩"未命中回显"行 ⇒ 事件没送到（看 `key=` 的码值） |
| 2 | 文件落盘 | `MQL5\Files` 下出现 `Structure_snap_*.png`，时间戳 = 按键时刻 | `ok=false` ⇒ `ChartScreenShot` 被异步排队/拒绝（查尺寸上限） |
| 3 | **我能读到它** | 我用 `read_image` 打开该 PNG，看到 HTF 蜡烛在右侧留白区、closure 标签带 `▲`/`▼` | 尺寸被截到 1920×1200 上限 ⇒ 放宽或按比例裁 |
| 4 | 图能回答像素层问题 | 至少能判：`▲/▼` 是三角还是方框、蜡烛是否越界、整体是否清爽 | 若仍看不清 ⇒ 加大尺寸 / 只截留白区 |

⚠️ 判据 3 是本阶段**唯一的目的**：把"像素层"从空白变成可复验。在此之前，所有关于观感的结论都只能来自人肉截图，而人肉截图的可靠性我已经栽过一次（§50.1 的色相误读）。

### 50.6 运行实证（`v1.50-s37`，用户按下热键）

`20260929.log` 09:34:48-09:34:51（XAUUSD.ct M5）：

```
STRUCT_SNAP key=16  shiftRaw=-128 ctrlRaw=0 (未命中，仅回显)   ← 只按 Shift 自身
STRUCT_SNAP key=229 shiftRaw=-128 ctrlRaw=0 (未命中，仅回显)
STRUCT_SNAP ok=true file=Structure_snap_XAUUSD_ct_20260929_093451.png size=1559x649
            path=…\MQL5\Files
```

⇒ 热键链路**全部打通**（判据 1、2 闭合），且快照已被我读取。
⚠️ 一处**实测修正**：`TERMINAL_KEYSTATE_SHIFT` 按下时返回的是 **-128（位掩码）**，既不是 `-1` 也不是 `1` ——
`shiftRaw != 0` 的写法恰好对三种约定都成立（这就是当初不写 `== -1` / `== 1` 的理由）。
档案：`docs/img/2026-09-29-v1.50-s37-XAUUSD-M5-snapshot.png`、`docs/img/2026-09-29-snapshot-mid-2x.png`（中段 2.2× 放大）。

---

## 51. 阶段 28：MSS 为什么可能"没被标出来"（`v1.50-s38`）

**用户提问**（附 `v1.50-s37` 快照）：「中间 C2 的位置是一个 MSS，为什么没有标记出来」

### 51.1 我第一次有了"像素层"证据 —— 先看图上到底有什么

快照：`docs/img/2026-09-29-v1.50-s37-XAUUSD-M5-snapshot.png`（1559×649，XAUUSD.ct M5，28 Sep → 29 Sep 04:20）。
本次判读（与 §50 之前"只有数据层"的状态相比，这是第一次）：

| 观察 | 结论 |
|---|---|
| 图上**存在**橙色点线 + `MSS` 文字（中段偏右，约 4120 附近） | MSS 功能**在跑**，不是"没实现/没触发" |
| closure 标签可见 **6 个**：`C2▼ ×2`、`C2-CONT▼ ×1`、`C2-CONT▲ ×3` | 与 `InpMaxEvents = 6` **完全吻合** |
| 全部 closure 标签**都带 `▲`/`▼`**，无方框 | §49 的字形两条证据被像素层证实（第三条腿闭合） |
| HTF 蜡烛 4 根落在**右侧未来留白区**，未压真实 K 线 | §47/§48 的留白区方案按设计工作 |

### 51.2 一条 MSS "看不见"有**四条**路径，不是一条

`RenderScene` 的 MSS 段（`Structure.mq5:4601-4666`）：

| # | 抑制条件 | 后果 | 行号 |
|---|---|---|---|
| 1 | 事件早于窗口左界（`InpWindow = 200`）或 `InpShowMSS = false` | 完全不画 | `:4604` |
| 2 | **`InpMaxEvents = 6` 硬截断**：`mssFrom = nMSS − 6` | **比最新 6 条更旧的 MSS 完全不画**（连暗线都没有） | `:4379` → `:4601` |
| 3 | **`weak`**＝位移 < `InpMinDisplaceBodyATR`(1.00 ATR) **或** 方向与 HTF 偏置逆向 | **只画暗色点线（`InpColorWeakBreak`），不给文字标签** | `:4645-4647`、`:4660-4665` |
| 4 | `InpNeedRetestToShow = true` 且后续 50 根内未重新穿越 | 完全跳过 | `:4622-4634`（当前默认 `false`，**不适用**） |

⚠️ 第 2 条最容易被误判成"漏画"：`InpMaxEvents` **同时**截断 **MSS / BOS / CISD / CLOSURE / FVG / OB / SWEEP 七个家族的文字标注**
（`:4379`、`:4734`、`:4790`、`:4855`、`:4898`、`:5062`）—— 它不是"标签密度"旋钮，而是**硬截断**：
第 7 旧的那条，连一条暗线都不会留下。

### 51.3 初判：最可能是第 2 条（截断），而不是"忘了标"

| 观测 | 推断 |
|---|---|
| 快照上 closure 标签**恰好 6 个** | 与 `InpMaxEvents = 6` 吻合 |
| 早前 M1 实战帧：`closure = 58`、`nodes = 73` | 58 条 closure 只能画出 6 个 ⇒ **截断必然在起作用** |
| 同帧 `MSS = 9`（M1） | 9 > 6 ⇒ 那 3 条最旧的 MSS **根本没被画** |

⇒ 你指的中段那条 MSS，很可能是被 `InpMaxEvents = 6` 截掉的（它比最新 6 条更旧），**不是漏画**。

⚠️ **但这仍是推断，不是结论**：上面 `closure=58` / `MSS=9` 两个数字来自**另一张图（M1）**，
`InpDebugShowRef=false` 时本图（M5）连 `TradFi_DBG` 计数都没有。
⚠️ 另有两条同族证据在支持"截断在起作用"：本图可见 **`BOS` 文字只有 1 个、`CISD` 只有 1 个** ——
若截断不生效（事件数 ≤ 6），图上应该更多。

### 51.4 取证工具：`Shift+D`（`v1.50-s38` 新增）

事件 CSV 不再需要改输入项（`InpDumpEvents`）：图表聚焦按 **`Shift+D`** 即可，
且热键路径**显式 `force=true` 绕过 `InpDumpEvents` 门控**（否则"按了没反应"又成了一个不可分辨的失败）。

它给出回答本问题所需的**全部**字段：

| 要回答 | CSV 里的位置 |
|---|---|
| 这条 MSS 到底有没有产生 | `type=MSS` 行的 `breakTime` / `refTime` / `refPrice` |
| 是"没画"还是"画成弱化线" | `displacement` 列：`body=… pen=… OK\|WEAK` |
| 是否被 HTF 偏置压制 | `biasState` 列（与 `dir` 一比即知） |
| 一共几条 MSS（判断截断有没有吃掉它） | 头部 `# window=… mss=N` |

### 51.5 可证伪预测（拿到 CSV 即可判）

| # | 判据 | 若成立 | 若相反 |
|---|---|---|---|
| 1 | `# window=… mss=N`，且 `N > 6` | **截断在起作用**，中段那条属被裁掉的旧事件 | `N ≤ 6` ⇒ 51.3 的初判**错**，转查第 3 条（弱化） |
| 2 | 目标那条 MSS 的 `displacement` 含 `WEAK`，或 `biasState` 与 `dir` 逆向 | 是**设计意图**（G1：未过位移门槛／逆 HTF 偏置 ⇒ 只画暗线不给标签） | `OK` 且同向 ⇒ 两条都不成立，**我这边有 bug，要查渲染段** |
| 3 | CSV 的 `type=MSS` 行数 = 图上可见 MSS 线条数 + 被裁条数 | 自洽 | 不自洽 ⇒ 渲染段有 bug |

### 51.6 两个可能的处置（等你定，先不动代码）

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. 把 `InpMaxEvents` 调大或设 0** | 0 = 不截断；或按需调到 20~30 | 对象数上升（每条 MSS/BOS/CISD 各 1 线 + 1 标签），图上更密 |
| **B. 只放宽 MSS/BOS** | 给这两类单独的截断参数 | 逻辑更清楚，但多两个输入项 |
| **C. 保持现状** | 认知上把"图上没有"读成"不在最新 6 条内" | 零改动，但看历史结构时要靠 CSV 补 |

⚠️ 若最终是**第 3 条（弱化）**，那么"没有标签"是**设计意图**；
要给它加标签（如 `MSS?`）等于引入一个 TTrades 术语里**不存在**的标注，我不会擅自做。

---

## 52. 阶段 29：弱化的 BOS/MSS **也打标签**（用户裁定 B，`v1.50-s39`）

**用户裁定**：在 §51.6 的三案里选 **B —— 弱化也打标签**。

### 52.1 §51 的实证结论（这次改动的事实基础）

`Shift+D` 导出的真实事件 CSV（`build=v1.50-s38`，XAUUSD.ct M5，`nodes=56 mss=9 bos=9 cisd=22 closure=56`，
`maxEvents=6`）显示：**9 条 MSS 只有 1 条带标签**，其余 5 条只留灰线、3 条被截断。
而且主导原因**不是位移**，是 **HTF 偏置**：9 条的 `biasState` 全是 `bear`，
于是那段上涨里所有**向上**破位全被判"逆偏置" ⇒ 灰线无标签。BOS 同理（9 条里也只有 1 条带标签）。
⇒ 图上看起来"中段 MSS 漏画"，实际是这条规则在系统性压制。

### 52.2 改法：颜色表示"确认与否"，后缀表示"为什么没确认"

| 标记 | 含义 | 颜色 |
|---|---|---|
| `MSS` / `BOS` | 确认（位移达标 **且** 顺 HTF 偏置） | 琥珀 / 蓝（原色，**未变**） |
| `MSS(w)` | 位移不足 | 暗灰（与线段同色） |
| `MSS(b)` / `BOS(b)` | 逆 HTF 偏置 | 暗灰 |
| `MSS(wb)` | 两者同时 | 暗灰 |

- **BOS 只会出现 `(b)`**：它**没有位移判据**（CSV 的 `displacement` 列对 BOS 行为空）。
- 新增开关 `InpLabelWeakBreaks = true`（`false` 即退回"弱化 = 无线标签"的旧观感，便于新旧对照）。
- **一致性收益**：改后**所有事件族一律有标签**（CISD/FVG/OB/CLOSURE 本来就无条件打标签，只是弱化时变灰），
  规则归一为"**颜色 = 确认与否，文字 = 内容**"。

### 52.3 为什么后缀是 ASCII 而不是中文（实测，非审美）

| 检验 | 方法 | 结果 |
|---|---|---|
| Arial 是否含 CJK 字形 | WPF `GlyphTypeface.CharacterToGlyphMap` | 弱 `U+5F31` / 逆 `U+9006` / 位 `U+4F4D` / 移 `U+79FB` / 偏 `U+504F` / 置 `U+7F6E` **全部 False** |

⇒ 中文标签只能落到**字体回退**，能不能显示不受本指标控制 —— 与 §49 的 ▲/▼ 同一类判断，但这次结论是**不能用**。
（`U+00B7` 中点、`(`、`w`、`b` 均为 True，故 ASCII 方案安全。）

### 52.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据 |
|---|---|---|---|
| 1 | 弱化 MSS 也出标签 | ✅ | `Structure.mq5:4678`（`drawLbl`）、`:4689` |
| 2 | 弱化 BOS 也出标签 | ✅ | `:4737`、`:4748` |
| 3 | 能区分"为什么弱" | ✅ | `WeakTag()`（`:4336`）：`(w)`/`(b)`/`(wb)` |
| 4 | 确认级观感不变 | ✅ | 无后缀、原色；`InpColorMSS`/`InpColorBOS` 未改 |
| 5 | 可一键退回旧观感 | ✅ | `InpLabelWeakBreaks = false`（`:513`） |
| 6 | 字形可显示 | ✅ 已实测 | §52.3（Arial 无 CJK → 用 ASCII） |
| 7 | 开关进了 CSV 头部 | ✅ | `# switches … weakLabels=%s`（`:944`、`:963`） |
| 8 | 判定层零影响 | ✅ | 只改渲染段；`weak` 的**写入**路径未动（仍不消耗结构位） |
| 9 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=F105689D22B2` / `ex5=288429348D5D` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 52.5 可证伪预测

| # | 判据 | 期望 | 若不符 |
|---|---|---|---|
| 1 | 标签**对象**数 | MSS 标签 1 → **6**、BOS 标签 1 → **6**（= `InpMaxEvents` 上限，各自 3 条被截断） | 若仍是 1 个 ⇒ `drawLbl` 分支没生效 |
| 1b | 当前视野内**可见**标签数 | MSS：**2~3 个**（seq 185/201/202 —— 其中 185 的标签在线段中点、可能贴左缘）；BOS：**2 个**（`BOS(b)` 197、`BOS` 207）。其余标签对象落在视野左外侧（`refBar` 110~196，而视野约 bar 0~79） | 视野内 0 个 ⇒ 注册与创建不匹配 |
| 2 | MSS 后缀分布（全部 6 条） | `(wb)`×2（seq 135/141）、`(b)`×1（seq 157）、`(w)`×2（seq 185/201）、无后缀×1（seq 202） | 分布不符 ⇒ 两个标志位取值错了 |
| 3 | BOS 后缀 | 只有 `(b)`（seq 174/197），**不出现** `(w)` | 出现 `(w)` ⇒ BOS 走了位移判据（不该） |
| 4 | 中段那条 | 09.28 12:45（seq 128）**仍不出现** —— 它属被 `InpMaxEvents=6` 截断的第 3 旧 | 若出现 ⇒ 截断逻辑变了 |
| 5 | CSV 数据行 | 除头部 `weakLabels=` 外**逐字不变** | 说明改动漏进了判定层 |

⚠️ 判据 4 是**故意留的边界**：本次裁定只做 B，**没做 A**（`InpMaxEvents` 保持 6）。
要看被截断的那 3 条，仍需把 `InpMaxEvents` 设为 `0` 或调大 —— 那是另一个决定。

---

## 53. 第三类原因：**被破的 swing 不一定是"可破的结构位"**（protected swing 由 CISD 建立）

**用户反馈**（在图上手画一条红线）：「我画的这条红色的应该也是 MSS」。

### 53.1 先把红线对上号（含不确定性声明）

| 步骤 | 内容 |
|---|---|
| 红线像素位置 | 图上 y≈128/494，左端正好落在 `C2▼` 标签下方那个**峰**上 |
| 标定 | 用图上两条**已标注**的线做线性标定：灰 `BOS(b)`（= 4126.64）与 `MSS(w)`（= 4120.40） |
| 推出价格 | **≈ 4128.5 ~ 4129** |
| 对应事件 | 09.29 **02:30**（服务器时间）的 `C2▼`，即 CSV 的 `bar=28, refPrice=4128.94` |

⚠️ **这是推断，不是测量**：红线是画在截图上的，快照里没有价格轴。要坐实，需要用户给出价格，或把线画进 MT5 再 `Shift+S`（那样我能用价格轴精确读数）。

### 53.2 数据核对：bar 28 在整份 CSV 里只被引用**一次**

| 引用者 | 有没有 |
|---|---|
| `CLOSURE` | ✅ 有：`200,CLOSURE,DOWN,28,29,4128.94,2026.09.29 02:30,02:25,…,C2-REV` |
| `CISD` | ❌ **没有** |
| `MSS` | ❌ **没有** |
| `BOS` | ❌ **没有** |

而同期其它位**都有** CISD 指向：`bar 42 ← CISD 01:35 DOWN`、`bar 36 ← CISD 02:10 UP`、`bar 19 ← CISD 03:30 UP`。

### 53.3 机制：swing ≠ 可破的结构位（有逐字依据）

他的原话：

> *"When IC-CISD forms, a swing high or low **becomes protected**."*（IC-CISD 篇）
> *"A protected swing is created when price **closes through the series of opposing candles** that led into a high or low."*（Ideal Formation）

代码据此实现（阶段 11 起）：

| 位置 | 事实 | 行号 |
|---|---|---|
| `SetProtectedFromCisd()` | **唯一**写 `refHigh`/`refLow` 的地方 | `:2519-2540` |
| 调用点 | **只有** `CheckCisd()` 的两个分支（空头 CISD→保护高点 / 多头 CISD→保护低点） | `:2561`、`:2572` |
| swing 确认处 | **不再写 ref** —— 注释明写"阶段 11 起此处不再写 ref" | `:3461-3463` |
| 突破判定 | **只**测 `st.refHigh` / `st.refLow` 这两个活动位 | `CheckBreakAgainstRefs()` `:2630`、`:2638-2641` |
| ref 跟随 | 仅当它指向的节点被同类型更极端者**替换**时同步 | `AddNodeFiltered()` `:2147-2151` |

⇒ **一个 swing 即便被破，只要它从未被 CISD 建立成 protected swing，就不会产生 BOS/MSS。** 这不是漏画，也不是 §51/§52 的截断或弱化问题，而是**第三类原因**。

### 53.4 结论与待裁定

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. 保持** | 只有 protected swing 被破才算 BOS/MSS（**= 他的口径**，逐字可溯） | 手画的"肉眼明显被破的 swing"永远不会有标记，看图时会反复产生同一疑问 |
| **B. 另加一层"任意结构节点被破"标注** | 独立记号/颜色（例如淡色 `BRK`），**与 BOS/MSS 完全分开**、不影响判定 | 他的模型里**没有**这个层级，必须明确标为**自造口径**；且节点很多，容易糊屏 |

⚠️ 无论选哪个，都要先确认红线价格（§53.1 的不确定性）—— 否则"我画的这条"具体是哪条 swing 仍未坐实。

---

## 54. 阶段 30：CHoCH 层（**借用 ICT 术语**，`v1.50-s40`）

### 54.1 这条裁定**部分推翻**了 §1 决策 A —— 必须留痕

**用户原话**：「那我画的红线应该标记为 ChoCh」。

⚠️ §1 决策 A 的记录是：在**语料级否定**下（TTrades 全站 110 篇正文 `change of character` = **0**、`\bchoch\b` = **0**，而同语料 `CISD` = 5、`displacement` = 20），你已改选"**纯 TTrades 命名**：只留 CISD + MSS，**放弃 CHoCH 这个词**"；代码里也做了收口（`:4661` 一带"不再使用 ICT 的 CHoCH"，全文件 `ChoCh` 残留归零）。

**本次不是撤销那条决策，而是"在他的口径之外另开一层，并把它标出来"**：

| 处置 | 内容 |
|---|---|
| 词 | 按你的要求用 `CHoCH` |
| 三处标注"借用词" | ① 代码块注释（`ComputeChoch()` 抬头）② README ③ **CSV 的 `state` 列直接写 `CHoCH(borrowed-ICT-term)`** |
| 纪律 | 它**只标注、不判定**；不得当作他的口径引用（与 §33/§38 对"自定口径"的处置同级） |

**两个用户裁定**：范围 = **每次逆势破 swing 都标**（不是每段只标第一次）；命名 = `CHoCH` + 三处标注。

### 54.2 判据（精确到可复算）

> **由旧到新逐 bar 扫。`curState` = 内部趋势，翻转点由「强 MSS」推出（`weak` 的不翻转 —— 与 `ApplyMssTransition` 的三档语义一致）。`curState = DOWN` 时，价格**向上**破掉"最近一个**高点节点**" → 记 `CHoCH(UP)`；`curState = UP` 时镜像。同一个位只报一次，**新节点到来后重新武装**。**

| 设计点 | 取值 | 理由 |
|---|---|---|
| 用节点还是 ref | **节点**（`g_result.nodes`） | `refHigh/refLow` 会被 MSS **清空**（`:2617-2621`），那正是本层要补的盲区 |
| 是否要求 protected | **不要求** | 这正是它与他 MSS 的分界：他的 MSS 只认 CISD 建立过的位 |
| 是否写 `st.state` | **绝不** | 纯渲染层；否则会改变 BOS/MSS 归属与结构段划分 |
| 弱化分级 | **不做** | CHoCH 没有位移判据、也不表示"确认"，恒用原色 + 恒带标签 |
| 截断 | 同其它族，受 `InpMaxEvents` 限制 | 一致性 |
| 与 MSS 同 bar | **先判破位、再应用本 bar 的 MSS 翻转** | 否则同一根 bar 上"MSS 翻趋势"会把该 bar 自己的反向影线点成 CHoCH |

### 54.3 实现中自己抓到的一个错（值得留下）

第一版扫描起点写成"取更**年轻**的那个"（`min(nodes[0].bar, mss[0].bar)`），后果是：
`while(nodes[p].bar >= i)` 会在**同一根 bar** 上把一批更旧的节点一次性消费掉 ⇒
"最近 swing"被提前换成新节点 ⇒ **那段区间里的逆势破位全部漏掉**。
改为取**最旧**（`max`）后才正确。

⚠️ 这个错**编译器抓不到、`audit_state.ps1` 的四项也抓不到** —— 它只在"窗口最左端存在逆势破位"时才显形。
记在这里的理由：**后验扫描层的 off-by-one 不会报错，只会静默少画。**

### 54.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 逆势破 swing 出 CHoCH | ✅ | `ComputeChoch()` `:2852`；`AddChochResult()` `:2829`；调用点 `:3628` |
| 2 | **不要求** protected swing | ✅ | 判据只读 `g_result.nodes`，不碰 `refHigh/refLow` |
| 3 | 纯渲染、零判定影响 | ✅ | 不写 `st.state`；`nChoch` 不进任何判定路径 |
| 4 | 每次逆势破都标（同一位不重复） | ✅ | `hiDone/loDone` 报过即置位，新节点重新武装 |
| 5 | 可关 | ✅ | `InpShowChoch`（自复位在早退之前 ⇒ 关掉 = 零 CHOCH 行） |
| 6 | 进指纹（硬约定 3） | ✅ | `(g_result.nChoch != g_lastNChoch)` `:4576`；赋值 `:4601` |
| 7 | CSV 可辨且自标借用词 | ✅ | 归并 `pick == 7`；`state` 列 = `CHoCH(borrowed-ICT-term)` |
| 8 | 开关进头部 | ✅ | `# switches … weakLabels=%s choch=%s`；INIT `STRUCT_SWITCH … choch=%s` |
| 9 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=68E3DD20F74E` / `ex5=71170CB925A1` match=True；`audit_state.ps1` → `PASS`（且 `nChoch` 的复位被 tripwire 独立确认） |

### 54.5 可证伪预测（重挂后按 `Shift+D` 即可核对）

| # | 判据 | 期望 | 若不符 |
|---|---|---|---|
| 1 | 出现 `CHOCH` 行且 `nChoch ≥ 1` | 至少一条 | 0 条 ⇒ `g_chochSeedState` 没被写入，或 `InpShowChoch=false` |
| 2 | **你红线那条** | 有一条 CHOCH 落在 03:15（强 MSS DOWN）之后、**首次越过 4128.94** 的那根 bar 上，`refPrice≈4128.94` | 若落在别的位上 ⇒ 节点表里 bar 28 被替换过（§54.2 的取舍） |
| 3 | 只出现一次 | 同一个 `refBar` 上不应出现两条 CHOCH | 出现多条 ⇒ `done` 位没生效 |
| 4 | 判定层零影响 | **非 CHOCH 行逐字不变**（除头部 `build=` 与新增 `choch=` 子句） | 说明改动漏进了判定层 |
| 5 | 图上 | 紫色点线 + `CHoCH` 标签；**不作弱化**（不因逆 HTF 偏置变灰） | 变灰 ⇒ 误用了 MSS 的弱化逻辑 |

---

## 55. 阶段 31：**删除**阶段 29 的"弱化也打标签"（`v1.50-s41`）

**用户原话**：「同时删除之前加的弱化的MSS」。

### 55.1 删了什么

**整体删除**阶段 29（`v1.50-s39`）加的那一层 —— **MSS 与 BOS 一起**（该层当时是一个开关同时管两者）：

| 被删对象 | 位置 |
|---|---|
| 输入项 `InpLabelWeakBreaks` | 原 `:513`（现存项目里已无此项） |
| `WeakTag()` 函数与其说明块 | 原 `:4469-4487` |
| MSS 段的 `drawLbl` 分支与 `"MSS" + WeakTag(...)` | MSS 渲染段 |
| BOS 段的 `drawLblB` 分支与 `"BOS" + WeakTag(false, dimB)` | BOS 渲染段 |
| CSV `# switches` 的 `weakLabels=%s` 字段 | 头部 |

**恢复的观感**：`弱化 = 暗色点线 + 无标签`（= v1.49 G1 的原始行为），即 `if(!weak) AddSceneName(lbl);`。

⚠️ **判据层一字未动**：`weak` 的**写入**路径（`ApplyMssTransition` 的三档语义、"弱触发不消耗该位"）从来就不属于本层，本次也没碰。

### 55.2 留下一行墓碑（不是遗漏，是"删过"）

代码原位置保留一段注释，写明"该功能已按用户要求整体删除"，理由：
**避免以后有人（包括我）再以"补全观感 / 图上像漏画"为由把它加回来** —— 它被加过、也被删过，`§52` 里有当时的实测数据，`§55` 里有删除决定。

### 55.3 与 §52/§54 的关系

- **§52 被本阶段取代**（记录保留，作为"加过又删"的完整轨迹）。
- **§54（CHoCH 层）不受影响**：CHoCH 从一开始就是"恒带标签、不做弱化分级"的独立层，从未引用 `InpLabelWeakBreaks`。
  换句话说：**"弱化不打标签"与"CHoCH 一定打标签"现在同时成立**，两者不矛盾 —— 前者是"未获确认的结构破位不造标签"，后者是"另一类结构事件的观察记录"。

### 55.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 弱化的 MSS 不再有标签 | ✅ | MSS 段恢复 `if(!weak) AddSceneName(lbl);` + `if(!weak){ … "MSS" … }` |
| 2 | 弱化的 BOS 不再有标签 | ✅ | BOS 段恢复 `if(!dimB) …` |
| 3 | 开关与函数彻底消失 | ✅ | 全文 `InpLabelWeakBreaks` / `WeakTag(` / `drawLbl` **零命中**（仅墓碑注释提到旧名） |
| 4 | CSV 头部不再声称有该开关 | ✅ | `# switches … htfPlace=%s choch=%s`（`weakLabels=` 已删） |
| 5 | CHoCH 层不受影响 | ✅ | CHoCH 恒 `AddSceneName(lbl)` + `"CHoCH"` 文本，与弱化无关 |
| 6 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=1EEC2D6B9F49` / `ex5=ABD4C96BAF62` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 55.5 可证伪预测（重挂 + `Shift+D` 核对）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 弱化 MSS 的标签消失 | 图上不再出现 `MSS(w)` / `MSS(b)` / `MSS(wb)`；BOS 不再出现 `BOS(b)` |
| 2 | 确认级不受影响 | `MSS`（无后缀）与 `BOS` 仍在，位置/颜色不变 |
| 3 | 灰色弱化线仍在 | 弱化事件**仍画线**（只是没标签）—— 这是与"删除事件"的分界，务必如此 |
| 4 | CHoCH 不受影响 | `CHOCH` 行与紫色标签照旧 |
| 5 | CSV | 除头部 `build=` 与 `weakLabels=` 字段消失外，其余逐字不变 |

⚠️ 判据 3 是关键分界：本次删的是**标签层**，不是**事件层**。若你想连灰线一起去掉（= 弱事件完全不画），那是另一个决定 —— 说一声即可，它只影响渲染段的一行。

---

## 56. 阶段 32：弱化的 BOS/MSS **完全不画**（`v1.50-s42`）

**用户原话**：「弱事件完全不画」（承接 §55 末尾我标出的那个分界）。

### 56.1 改法与范围

| 项 | 取值 | 依据 |
|---|---|---|
| 影响的族 | **MSS 与 BOS**（保持对称，同 §55） | 两者共用"弱化"样式与同一段判据 |
| "弱"的定义 | `mss[].weak`（**位移不足**）**或** 方向**逆 HTF 偏置** —— 两者都算 | 与阶段 6-b 的弱化口径一致（"两者都表示未获确认，但语义不同"） |
| 做法 | 在渲染段 `continue`：**不建对象、不注册场景名** | 对象名按 `(refBar,b)` 唯一 ⇒ "未注册即回收"，从灰线变为不存在是**自动**的，无需另写删除逻辑（与阶段 29 同一套机制） |
| 可逆 | 输入 `InpHideWeakBreaks`（默认 `true` = 你要的行为；`false` 退回"灰线 + 无标签"= v1.49 G1 观感） | 避免又一次"加了再删"的往返；同时保留 A/B 对照能力 |

⚠️ **判据层仍是一字未动**：`weak` 的**写入**路径（三档语义、"弱触发不消耗该位"）与本次无关；改的只是"画不画"。
⚠️ 关掉开关即回到 s41/s38 的观感，因此**新旧归档仍可对照**（CSV 头部有 `hideWeak=`）。

### 56.2 三个必须说清的后果

1. **`InpMaxEvents` 数的是事件，不是画出来的条数。** `mssFrom = nMSS − 6` 先按**原始事件表**裁剪，再逐个判弱 ——
   所以最新 6 条里若有弱事件被隐去，图上出现的确证线会**少于 6 条**。这是预期行为，不是丢事件。
2. **反转会比以前更晚显形。** 逆 HTF 偏置的 MSS/BOS 现在完全不画；而 D1 偏置可以长时间不变
   （本图实测：9 条 MSS 的 `biasState` **全是 bear**）。⇒ 在那段里，**唯一**还会标出"反向结构事件"的就是 §54 的 CHoCH 层。
   两层现在是互补关系：**顺偏置的破位看 MSS/BOS，逆偏置的破位看 CHoCH**。
   ⚠️ 但两者**不是同一件事**：CHoCH 只认"逆**内部趋势**破**最近节点**"，与"逆 HTF 偏置的 protected swing 破位"判据不同。
   若出现"某处反转既没有 MSS 也没有 CHoCH"，先用 `Shift+D` 看 CSV，再决定要不要动判据 —— **不要凭观感下结论**。
3. **弱事件仍在 CSV 里。** 本改动只作用于渲染：`mss`/`bos` 行照旧导出（`displacement` 列仍带 `WEAK`/`OK`，`biasState` 仍在），
   ⇒ 事后仍可完整复盘"当时有哪些弱触发被隐去了"。

### 56.3 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 弱 MSS 完全不画 | ✅ | `:4810` `if(weak && InpHideWeakBreaks) continue;` |
| 2 | 逆偏置 BOS 完全不画 | ✅ | `:4871` `if(dimB && InpHideWeakBreaks) continue;` |
| 3 | 连对象都不创建（不是"画成透明"） | ✅ | `continue` 在 `AddSceneName` / `UpsertLine` **之前** ⇒ 未注册 ⇒ 回收段自动删除旧对象 |
| 4 | 可一键回到旧观感 | ✅ | `InpHideWeakBreaks = false`（`:517`） |
| 5 | 开关进头部（CSV + INIT） | ✅ | `# switches … choch=%s hideWeak=%s`（`:958`）；INIT `STRUCT_SWITCH … hideWeak=%s`（`:1541`） |
| 6 | 关掉开关 = 零影响（A/B 前提） | ✅ | 判据 `&& InpHideWeakBreaks`，为 `false` 时整条分支短路 ⇒ 与 s41 行为逐字一致 |
| 7 | 判定层零影响 | ✅ | 改动只在 `RenderScene` 的两个渲染段内 |
| 8 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=BE7A844013FB` / `ex5=7530091153A7` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 56.4 可证伪预测（重挂 + `Shift+D` / `Shift+S` 核对）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 灰色点线消失 | 图上不再有 `InpColorWeakBreak` 色的 MSS/BOS 点线（此前本图应有两三条） |
| 2 | 确证线仍在 | `MSS`（琥珀，4120.40 一带）与 `BOS`（红，4114.44 一带）照旧 |
| 3 | 紫色 CHoCH 仍在 | §54 的那条不受影响 |
| 4 | CSV 不变 | 除头部 `build=` 与新增 `hideWeak=` 外，**数据行逐字不变**（弱事件仍在表里）—— 这条是"只改渲染"的判据 |
| 5 | 对象数下降 | `InpDebugShowRef=true` 时 `TradFi_RENDER` 的 MSS/BOS 计数应等于"确证条数"，而非"裁剪后的 6 条" |

---

## 57. 阶段 33：CHoCH 与 MSS/BOS **同位时让位**（`v1.50-s43`）

**用户原话**：「ChoCh与MSS重叠时要处理下，不然不好看」。

### 57.1 为什么会重叠（不是巧合，是两条判据的必然交集）

| | MSS | CHoCH |
|---|---|---|
| 破什么 | **被 CISD 保护过的** swing 位（`refHigh/refLow`） | **最近一个结构节点**（`g_result.nodes`） |
| 要位移吗 | 要（≥1.00 ATR + 时效条件） | **不要** |
| 触发时内部趋势 | 翻转前可以是 DOWN（`dir=UP`） | **必须**是 DOWN（`dir=UP`） |

⇒ 当"被保护的那个高点"**恰好就是**"最近那个高点节点"、且位移达标时，
**同一根 bar 上会同时产出 `MSS(UP)` 与 `CHoCH(UP)`，且两者的 `ref` 是同一个价位、`refBar` 是同一个节点**。
渲染上就是：两条同价位点线叠在一起 + 两个标签画在**同一个线段中点**上 ⇒ 文字直接压住。

### 57.2 规则与实现

> **同一个结构位若已有"会显示"的 MSS/BOS，CHoCH 让位**（不画线、不画标签）。

⚠️ **"会显示"必须按实际渲染筛选判定** —— `InpShowMSS/BOS`、`mssFrom/bosFrom` 截断、`InpHideWeakBreaks`、窗口左界（`time[b] < tStart`）。
若只看"存在过的 MSS"，一个**已被隐去的弱 MSS** 会把 CHoCH 一起挡掉，那个位就**什么都不剩** —— 那正是 §53/§54 要补的盲区，等于绕回去了。

| 位置 | 内容 |
|---|---|
| `LevelMarkedByBreak(refBar, time, tStart)` | 新函数：遍历会被画出的 MSS/BOS，判断是否有同 `refBar` 者 |
| CHoCH 渲染段 | `if(LevelMarkedByBreak(...)) { nChochHidden++; continue; }` |
| 诊断 | `InpDebugShowRef=true` 时打印 `TradFi_CHOCH 同位让位=N` —— 否则"CHoCH 变少了"与"CHoCH 不触发了"不可分辨 |

⚠️ 为什么用 `refBar`（节点身份）而不是 `ref`（价格）：价格可能被不同节点偶然撞上；`refBar` 才是"同一个 swing"的唯一身份。

### 57.3 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 同位时 CHoCH 不画 | ✅ | `LevelMarkedByBreak()` `:4496`；调用点 `:4955` |
| 2 | 只让位、不误伤 | ✅ | 判定按**实际渲染筛选**（开关 / 截断 / `InpHideWeakBreaks` / 窗口） |
| 3 | 让位可观测 | ✅ | `TradFi_CHOCH 同位让位=%d`（`:4976`，需 `InpDebugShowRef`） |
| 4 | 不改判定层、不改 CSV | ✅ | 只加渲染段分支；`CHOCH` 行照旧导出（重叠事实仍可复盘） |
| 5 | MSS/BOS 侧零改动 | ✅ | 两个既有渲染段一字未动（让位是单向的：CHoCH 让 MSS/BOS，不反之） |
| 6 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=C01106C10722` / `ex5=EC52211BE516` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 57.4 可证伪预测

| # | 判据 | 期望 |
|---|---|---|
| 1 | 同价位不再出现两个标签 | 任一 `refBar` 上，`MSS`/`BOS` 与 `CHoCH` **不同时**出现在图上 |
| 2 | CHoCH 不会整体消失 | 至少保留**没有** MSS/BOS 的那些位（本图预计仍有 1~2 条，即 §53 那条盲区位） |
| 3 | 让位条数可查 | 开 `InpDebugShowRef` 后看到 `TradFi_CHOCH 同位让位=N`（`N ≥ 1` 才算规则真被触发） |
| 4 | CSV 不变 | 除头部 `build=` 外**逐字不变**；`CHOCH` 行数与让位前相同 |

⚠️ 判据 2 是这次改动的主要风险：**别把 CHoCH 全让没了**。若图上一条 CHoCH 都不剩，
说明 `LevelMarkedByBreak` 判宽了（很可能忘了窗口筛选那一条）—— 用判据 3 的日志立刻能区分。

---

## 58. 阶段 34：`ERL` 与 `T1` 是**构造性同位** ⇒ 合并标签（`v1.50-s44`）

**用户反馈**（附手绘红框截图）：「我红色框出来的位置，是什么标记重叠了？」

### 58.1 先回答"是什么重叠了"：`ERL` 与 `T1`，而且**必然**重叠

| | ERL | 目标 `T1` |
|---|---|---|
| 选法 | 偏置方向上、现价之外、**未被取走**、价格**最近**的摆动位 | 用**完全相同**的筛选取最近 N 个 → 第 1 个就是它 |
| 代码 | `ComputeErlIrl()` `:3168-3197` | `ComputeTargets()`(a) `:3262-3301` |
| 现价基准 | `px = close[0]`（`:3175`） | `px = close[0]`（`:3260`） |
| "已取走"判据 | `IsLiquidityTaken()` | **同一个函数** |

⇒ `g_tgtBar[0] == g_erlBar` 且 `g_tgtPrice[0] == g_erlPrice` **恒成立**。
CSV 头部自己就写着这件事：`# targets … takenBasis=IsLiquidityTaken(shared with ERL)`。

叠加的不只是位置 —— **四条全同**：

1. 两条线都从 `time[同一个 bar]` 到 `time[0]`、同一价位；
2. 两个标签都锚在**同一个中点**（`:5219` 与 `:5265` 由同一对时间算出）；
3. 都用 `ANCHOR_CENTER`；
4. **颜色同值** —— ERL 与 Target 都是 `C'233,30,99'`（`:410`、`:483`；CSV `# colors` 行 `erl=233,30,99 tgt=233,30,99`）。

⇒ 两个标签**精确叠印**，渲染出来只是一团笔画。用户的红框正是这一处。

### 58.2 改法（用户裁定：合并成 `ERL/T1`）

| 位置 | 内容 |
|---|---|
| ERL 渲染段（`:5227-5231`） | 标签文本 = `"ERL"` + 对每个**同节点**目标追加 `/Tk`（**全部**列出，不是只取第一个） |
| 目标循环（`:5261`） | `if(InpShowERLIRL && g_erlValid && g_tgtBar[k] == g_erlBar) continue;` —— 线与标签都交给 ERL |
| 判据 | 用**节点 bar** 而不是价格：价格可能被不同节点偶然撞上（同 §57 理由） |
| 顺序 | `continue` 在 `AddSceneName` **之前** ⇒ 未注册即回收，状态变化时旧对象自动清掉 |
| 反例保底 | `InpShowERLIRL=false` 时 ERL 不画 ⇒ 该分支不成立 ⇒ `T1` 照常单独画 |
| CSV | `# targets` 行追加 `T1==ERL(same node; label merged as ERL/T1, target line skipped)`（`:1014`） |

### 58.3 顺带修掉一个**我自己造的**同类错误

用户截图让我去查调色板时发现：我加 CHoCH 时"选了个紫色"，**没查既有色**：

```
InpColorCISD  = C'186,104,200'   // :315
InpColorChoch = C'186,104,200'   // :518  ← 与 CISD 完全相同
```

⇒ 已按用户裁定改为**深紫 `C'123,31,162'`**（`#7B1FA2`）：与 CISD 的淡紫同族但明显更深，白底可辨。
⚠️ 教训（与 §57 同源）：**新增可视化元素前，先跑一遍"与既有色的距离"**，不要凭印象挑颜色。

### 58.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 同位时不再有两个标签 | ✅ | ERL 标签合并（`:5227-5231`）+ 目标侧 `continue`（`:5261`） |
| 2 | 信息不丢（T1 的身份仍可见） | ✅ | 标签文本为 `ERL/T1`；且同节点目标**全部**列出 |
| 3 | 不同位时行为不变 | ✅ | 判据只在 `g_tgtBar[k] == g_erlBar` 成立时生效 |
| 4 | `InpShowERLIRL=false` 时 `T1` 不受影响 | ✅ | 分支带 `InpShowERLIRL &&` 前置条件 |
| 5 | CHoCH 不再与 CISD 同色 | ✅ | `InpColorChoch = C'123,31,162'`（`:518`） |
| 6 | 判定层零影响 | ✅ | 只改渲染 + CSV 头部一句注释 |
| 7 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=39DE14DE3DD4` / `ex5=EE7298397E74` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 58.5 可证伪预测（重挂后看截图 / `Shift+D`）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 那一处只剩一个标签 | 红框位置显示 `ERL/T1`（不再是两团叠印） |
| 2 | 目标侧无重复线 | 同位那条不再单独画（几何本就被 ERL 覆盖，视觉上无变化） |
| 3 | `T2`/`T3` 编号不变 | 仍是 `T2`、`T3`（**不重排**，避免"T2 变 T1"的语义漂移） |
| 4 | CHoCH 颜色与 CISD 可区分 | 图上 CHoCH 是深紫、CISD 是淡紫 |
| 5 | CSV | 除头部 `build=` 与 `# targets` 新子句外**逐字不变** |

---

## 59. 阶段 35：节点级破位**分 BOS / CHoCH** —— 结构方向不能再借引擎的 MSS 状态（`v1.50-s45`）

**用户反馈**（附全图 + 两个红框）：「我框出来的两个地方应该是BOS才对」。
放大核对：两框里都是紫色的 `CHoCH` 标签（深紫 = `s44` 已生效）。

### 59.1 根因：我借来的"趋势"被结构性锁死了

初版（`s40`）用**引擎的 MSS 状态**当趋势：`curState` 由**强 MSS** 翻转。
但引擎里：

```mql5
if(dir == DIR_DOWN) { st.state = ST_DOWN; st.refHigh.valid = false; }   // ApplyMssTransition :2617-2621
```

**每次 bearish MSS 之后高点参考位被清空** ⇒ 那之后：
- 上方所有破位**产生不了任何事件**（没有 `refHigh` 可比）；
- 没有事件 ⇒ `st.state` **永远翻不上来**（翻转需要"被保护的高点被破"，而槽位是空的，
  除非再来一条 bearish CISD 重新保护一个高点）。

于是 2026-09-29 03:15 那条 `MSS DOWN` 之后，整段上涨在我的层里"趋势"始终是 DOWN，
**连续破新高全被判成逆势 = CHoCH**。**用户的判断是对的。**

⚠️ 这是一次**定义借错**，不是编码手误：我把一个"会在单方向上锁死"的状态当成了"市场结构方向"。

### 59.2 改法（用户裁定 A）：本层自带结构方向

| 项 | 定义 |
|---|---|
| `structDir` | **上一次破位的方向**；初值 = **第一段腿**的方向（`nodes[0]` 是低点 → 首段向上 → UP）；只有一个节点时 = 0 |
| 破位方向 == `structDir` | 标 **`BOS`**（顺势，他的术语） |
| 破位方向 != `structDir` | 标 **`CHoCH`**（逆势，**借用 ICT 术语**），并把 `structDir` 翻成该方向 |
| 与引擎状态机的关系 | **完全解耦** —— 不再引用 `g_result.mss`（`g_chochSeedState` 已整个删除） |

⇒ 判据变成一句纯节点级规则：**同一方向的连续破位 = BOS；方向反转的那一次 = CHoCH，且它同时把方向翻过去。**
**每个方向变化恰好一个 CHoCH**，其余都是 BOS —— 这正是 ICT 的经典读法。

| 位置 | 改动 |
|---|---|
| `ComputeChoch()` | 重写：去掉 MSS 指针与 `curState`，改用 `structDir`；`AddChochResult()` 增加 `sub` 参数（`NODEBRK_BOS` / `NODEBRK_CHOCH`） |
| 渲染段 | `sub → tag/color`：顺势用 `BOS` + `InpColorBOS`；逆势用 `CHoCH` + `InpColorChoch` |
| CSV | 顺势 `type=BOS` + `state=BOS(node-level,borrowed-ICT-frame)`；逆势 `type=CHOCH` + `state=CHoCH(borrowed-ICT-term)`。**`type=BOS` 现在同时覆盖引擎与节点级两层，靠 `state` 列区分** |
| CSV 头部 | 新增 `nodebreaks=…` 子句，自描述判据、初值、让位规则与"借用词" |
| §57 让位规则 | **收紧**：从"会让位的（会显示的）MSS/BOS"改为"**存在**的 MSS/BOS"（含 weak）。理由：s42 已定"弱事件完全不画"，若节点级标记在同一位上顶上来，等于**把刚隐去的弱判断换个名字显示出来** |

### 59.3 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 顺势破位标 `BOS` | ✅ | `:2919`（`subH`）、渲染段 `tag = isBos ? "BOS" : "CHoCH"` |
| 2 | 逆势破位标 `CHoCH` 并翻转方向 | ✅ | `:2926`（`subL`）、`structDir = DIR_DOWN` |
| 3 | **不再依赖引擎 MSS** | ✅ | `ComputeChoch` 内零 `g_result.mss` 引用；`g_chochSeedState` 已删除（全文零命中） |
| 4 | 每方向变化恰好一个 CHoCH | ✅ | `structDir` 每次破位即等于破位方向 ⇒ 只有反方向那次是 CHoCH |
| 5 | 与引擎同位时让位 | ✅ | `LevelMarkedByBreak()`（含 weak，见 §59.2 收紧说明） |
| 6 | 术语来源三处标注 | ✅ | 代码抬头 / README / CSV `state` 列 + `# nodebreaks` 子句 |
| 7 | 判定层零影响 | ✅ | 本层不写 `st.state`；引擎 MSS/BOS 逐字未动 |
| 8 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=C5DF328B59BD` / `ex5=13711DDE7540` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 59.4 一个**尚未闭合**的语义分歧（需要用户用新图判定）

新规则下，**"反方向的第一破"必然是 CHoCH**（这正是 CHoCH 的教科书含义）。
所以两个红框里：

| 情形 | 期望 |
|---|---|
| 该破位是下跌结构之后的**第一次向上破位** | 仍是 **`CHoCH`** —— 这是定义使然，不是 bug |
| 该破位之前已经有过一次向上破位（方向已翻 UP） | 应为 **`BOS`** ✓ |

⇒ 右边的框（更晚的那次）应当变成 `BOS`；左边的框是否变，取决于它是不是"反转后的第一破"。
**若你要求"上涨途中破前面任何一个高点都算 BOS"**（即放任第一次反转破位也叫 BOS），
那就得把"结构方向"改成**按 HH/HL 序列**判定（而不是按上次破位方向）——
代价是 **CHoCH 会变得极罕见**（几乎只在"破更低低点"时才出现），等于把 CHoCH 这一层废掉一半。
**这个取舍我没有替你决定** —— 先看新图判定左框属于哪种情形，再定。

---

## 60. 阶段 36：FVG 口径改为**物理相邻三根** + 最小高度门槛（`v1.50-s46`）

**用户反馈**（附手绘红框 + 全图）：「这里我框出来的 FVG 是错误的吧，这个不是 FVG 吧」

### 60.1 先定到具体那一条（`Shift+D` 的真实 CSV）

`build=v1.50-s45`，14:08:38 导出，XAUUSD.ct M5：

```
seq=239  FVG  UP  c3=4  c1=7  d=-3  宽度=0.66  zLo=4135.52  zHi=4136.18
         fill=0.00  OPEN   c3时间=2026.09.29 08:50
```

`zLo/zHi` 与图上那条带子（≈4135.5–4136.2）吻合，**就是它**。关键只有一个数：

> bar 下标越大越旧，故 `d = c3 − c1 = −3` 表示 **c1 与 c3 相隔 3 根** —— 这个缺口用的是**隔了 4 根的 K**，
> 中间那根被当作**内包 K 剔除**、没进"有效 bar 序列"，因此没资格当 c2。

**这正是 §9 时代就写在代码里的口径偏差**（原 `CheckFvg` 注释：*"c1/c3 取自有效 bar 序列（内包 K 线已被剔除），而非物理上相邻的三根 K 线"*）。
⇒ **用户的直觉在"字面读法"上是对的**：这不是"三根连续 K 之间的缺口"。

### 60.2 量化：这不是孤例

同一份 CSV，**88 条 FVG**：

| `d = c3 − c1` | 条数 | 含义 |
|---|---|---|
| −2 | 64 | 物理相邻三根 ✓ |
| −3 | 16 | 中间隔 1 根内包 |
| −4 / −5 | 3 / 2 | 隔 2~3 根 |
| −6 / −7 | 1 / 2 | 隔 4~5 根 |

另有 **12 条宽度 < 0.3**（最窄 **0.04** = 4 个 tick）—— 原实现只拒绝**零宽**缺口（`zHi <= zLo`），没有最小高度门槛。

⚠️ 替原口径说一句公道话：被剔除的都是**内包 K**，按定义其范围被母线（c2）完全包住，
**不可能单独伸进缺口**；`fill=0.00 OPEN` 也表明形成后无人碰过该区间。
⇒ 它不是"假缺口"，而是"**由 4 根 K 组成的缺口**"。用户反对的是**形态**（不是汉字意义上的"三根之间"），不是区间的真实性。

### 60.3 改法（用户裁定 C：两条都做）

| 项 | 改动 |
|---|---|
| 三根 K | `CheckFvg()` 改为 `c1 = c3 + 2`（**物理相邻**）；不再接收 `validBars`/`k`，改为接收 `atrArr` |
| 最小高度 | 新增 `InpFvgMinWidthATR = 0.10`（×ATR，`0`=不限）；在 `zHi > zLo` 之后再挡一道 |
| 调用点 | `CheckFvg(i, high, low, close, atrArr)` —— **每根 bar 都可作 c3**（不再要求它在有效序列里） |
| CSV 头部 | `# pdarray` 行改注 `physical:c3,c3+1,c3+2` + `minWidth=InpFvgMinWidthATR*ATR`；`# switches` 增 `fvgMinW=%.2f`（INIT 回显同步） |

⚠️ **口径变更 ⇒ 归档可比性**：`v1.50-s45` 及更早的 CSV 与之后版本的 **FVG 行不可直接对比**（其余族不受影响）。
⚠️ **副带影响**：`IRL` 取"最近未完全回补的 FVG"（`ComputeErlIrl`），FVG 集合一变，`IRL` 的指向可能随之外移 —— 这是预期传导，不是新 bug。

### 60.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 三根物理相邻 | ✅ | `CheckFvg()` `:2106` `int c1 = c3 + 2;` + 越界守卫 `:2107` |
| 2 | 最小高度门槛可调、可关 | ✅ | `InpFvgMinWidthATR`（`:365`）；判定 `:2124-2128`；`0` = 不限 |
| 3 | 每根 bar 都可作 c3 | ✅ | 调用点 `:3531`（不再传 `validBars`/`k`） |
| 4 | 门槛用 ATR 相对值 | ✅ | `InpFvgMinWidthATR * atrArr[c3]` —— 跨品种/周期自适应，不用固定价格单位 |
| 5 | 头部自描述 + 开关入库 | ✅ | `# pdarray`（`:937-939`）、`# switches fvgMinW=`（`:959`）、INIT `STRUCT_SWITCH`（`:1556`） |
| 6 | 判定层零影响 | ✅ | 只改 FVG 的记录/绘制；结构与偏置路径未动 |
| 7 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=29704FDDF4A1` / `ex5=801389812D3A` match=True；`audit_state.ps1` → `PASS (0 problems)` |

⚠️ 过程中自己抓到一次**格式化参数错位**：给 `# switches` 的**参数表**插了 `InpFvgMinWidthATR`，却漏了在**格式串**里加对应的 `%` 说明符
⇒ 后面所有开关的值都会**整体错位一格**（`ob` 会打出 `0.1`）。编译器与静态自检**都抓不到**（`StringFormat` 是变参）。
已补齐并逐项核对两处（`# switches` 24/24、INIT 21/21 说明符与参数一一对应）。
**教训：给变参格式化加字段时，格式串与参数表必须成对改，且要人工点一遍个数。**

### 60.5 可证伪预测（重挂 → `Shift+D` 复核）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 你框的那条消失 | `zLo=4135.52 / zHi=4136.18 / c3时间=08:50` 那一行**不再出现**（`d=−3` 在新口径下不可能） |
| 2 | 相邻性 | 新 CSV 里 `type=FVG` 的行**全部** `d = −2` |
| 3 | 微缺口 | 新 CSV 里**不存在**宽度 < `0.10×ATR` 的 FVG（该图上 M5 约 <0.25） |
| 4 | 头部自证 | 新 CSV 头部含 `physical:c3,c3+1,c3+2` 与 `fvgMinW=0.10`（INIT 行同） |
| 5 | 其余族不动 | 非 FVG 行（MSS/BOS/CISD/CLOSURE/OB/SWEEP/CHOCH）应保持同量级；`IRL` 可能因 FVG 集合变化而移动（预期） |

---

## 61. 阶段 37：弱化的 FVG / OB **不再共用同一个灰**（`v1.50-s47`）

**用户提问**（附手绘红框）：「FVG 中间的白色是什么意思」

### 61.1 先量出来：那不是任何对象的颜色，是**背景**

像素扫描（原图 1615×672，白底），垂直扫 x=1000：

| 屏幕 y | 颜色 | 读数 |
|---|---|---|
| 291–334 | `#D4D4DA` | 一条**弱化矩形** |
| 335–342 | `#806E82` / `#8080B0` | 两条矩形边缘的反走样混色 |
| **343–368** | **`#FFFFFF`** | **背景 —— 这里没有任何对象** |
| 369–447 | `#D4D4DA` | 另一条弱化矩形 |

水平扫 y=353（白带所在行）：x 1000→1169 全是 `#FFFFFF`，只有 x 1170–1185 被右侧那块矩形覆盖。

⇒ **白带 = 上下两条矩形之间的价格空档**（高约 26px ≈ 1.3 点），不是"白色对象"，也不是 FVG 的区间。
（另证：FVG 的标签画在**区间下沿再往下 0.1×ATR**（`:5188-5190`），图上 `FVG` 字样正压在上面那条灰带的下边缘 ⇒ FVG 区间在白带**上方**。）

### 61.2 根因：弱化的 FVG / OB / 内包盒**塌成同一个颜色**

调色板自证（CSV `# colors` 行）：`fvg=0,200,180 ob=100,140,255 **weak=110,110,130** box=110,110,130`；
弱化元素填充 = `PdFill(InpColorWeakBreak, 白, 30%)` = **(212,212,218) = `#D4D4DA`**，与实测完全一致。

代码同源（改前）：FVG 段 `clrF = dimF ? fillWeak : fillFVG`（`:5174`）、OB 段 `clrO = dimO ? fillWeak : fillOB`（`:5211`）
—— **两个族、三种元素、一个灰**。于是几条带子连成一片，中间没覆盖的空档看起来就像"FVG 中间有个白洞"。

### 61.3 改法（用户裁定 A）：**色相表示族别，浓度表示确认度**

| | 填充 | 轮廓 |
|---|---|---|
| 正常 | 族色 × `InpPDFillPercent` | 族色原色 |
| **弱化** | **族色 × 一半**（更淡） | **族色 × 50%**（洗淡但仍认得出族别） |

白底 255,255,255、`InpPDFillPercent=30` 下的实际派生色（**已手算核对**）：

| 元素 | 正常填充 | 弱化填充 | 弱化轮廓 |
|---|---|---|---|
| FVG | (178,238,232) 淡青 | (217,247,244) | **(128,228,218) 青** |
| OB | (208,220,255) 淡蓝 | (232,238,255) | **(178,198,255) 蓝** |
| ~~旧弱化灰~~ | — | ~~(212,212,218)~~ | ~~(110,110,130)~~ |

⇒ 弱化后仍能一眼分辨"这是 FVG 还是 OB"，而"弱化"由**更淡**表达（不再是中性灰）。
⚠️ `fillWeak` 局部变量随之**变成死代码并已删除**（避免留一个"看起来还在用"的残骸）；
`InpColorWeakBreak` 本身仍被 MSS/BOS/CHoCH 的弱化线与标签使用，未动。

### 61.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 弱化 FVG 保留族色 | ✅ | 定义 `fillFVGD` `:4719` / `lineFVGD` `:4721`；应用 `:5189-5190` |
| 2 | 弱化 OB 保留族色 | ✅ | 定义 `fillOBD` `:4720` / `lineOBD` `:4722`；应用 `:5226-5227` |
| 3 | 色相 = 族别、浓度 = 确认度 | ✅ | 规则写在 `:4711-4718` 注释里；两者不再共用 `fillWeak` |
| 4 | 头部可反推颜色 | ✅ | `# colors` 增 `derivedFillDim fvg= ob= lineFvg= lineOb=`（`:1035`、`:1045`） |
| 5 | 其余元素不受影响 | ✅ | MSS/BOS/CHoCH/SWEEP/CISD 的弱化仍用 `InpColorWeakBreak`（未动） |
| 6 | 判定层零影响 | ✅ | 只改渲染取色 + CSV 头部一行 |
| 7 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=2FE57AFF389B` / `ex5=F41EFA5EB1A8` match=True；`audit_state.ps1` → `PASS (0 problems)` |

### 61.5 可证伪预测（重挂后看同一处）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 灰带不再是一个颜色 | 那一处应出现**淡青**与**淡蓝**两种带子（此前两条都是 `#D4D4DA`） |
| 2 | 白带仍在 | 两条带子之间那条白空档**依然存在**（它是背景，不是缺陷）—— 但两侧带子颜色不同后，它读作"这里没有位"而不是"FVG 的一部分" |
| 3 | 轮廓可辨族别 | 弱化 FVG 的边框偏青 (128,228,218)、弱化 OB 偏蓝 (178,198,255) |
| 4 | 头部自证 | 新 CSV 的 `# colors` 行含 `derivedFillDim fvg=217,247,244 ob=232,238,255 …` |
| 5 | 其余不变 | 非 FVG/OB 行的数、以及 MSS/BOS 的弱化灰线颜色，均不变 |

---

## 62. 阶段 38：OB 改成**水平线段**（与他一致）+ 抓到一个 CSV 头部的**静默错位**（`v1.50-s48`）

### 62.1 依据：他图上 OB 就是一条线，不是框

research §11.2（`docs/research/2026-09-23-TTrades-structure.md`）：

> 图注：*"…**OB 在图上被画成一条水平线**（不是框），另有一个 **"Invalidation"** 标记指向区间的另一端。"*（`:428`）
> *"配图 `OB-confirmation.png`（标题 "Continuation OB"）：OB 是一条蓝色水平线向右延伸，**"Invalidation"** 标在该线下方（区间的另一端）。"*（`:430`）

而"线画在哪个价位"由同节的逐字要求给出：*"**The opening price of the candle** is often the most important reference."*
⇒ **线 = 关键价位 = `open[runOldest]`（造势序列最旧一根的开盘价）**，也就是 CISD 那条线所在的价位。

**用户要求**：「OB改成和他一样的水平线段」。

### 62.2 改动

| 项 | 改动 |
|---|---|
| 绘制 | `UpsertRect(实体并集)` → **`UpsertLine(关键价位 → 向右)`**，实线宽 1（他的画法就是一条平实线） |
| 对象名 | `OB_` → **`OBLine_`**。⚠️ 对象**类型**从矩形变成线，沿用旧名会让"已存在的矩形"撞进线的调和逻辑；换前缀后旧矩形**未注册即回收**，自动清除 |
| 标签 | 贴线放：看跌 OB 在线上方 `+0.1×ATR`、看涨在下方 `−0.1×ATR`。⚠️ CISD 标签在**同一根 bar**、偏移 `0.15×ATR` 在**另一侧** ⇒ 两者不叠印（这是刚在 ERL/T1 上学到的教训） |
| 实体并集 | `zoneLo`/`zoneHi` **仍写进数据与 CSV**，只是不再绘制 —— 他的 "Invalidation" 指的就是那个区间的另一端，信息不能丢 |
| 死代码 | 随之失效的 `fillOB` / `fillOBD` 局部量已删除；`# colors` 头部把 `ob`（填充）换成 `obLine=`（弱化线色），并注明 "ob is a LINE, no fill" |
| 连带清理 | ① `OBJDUMP`/`RENDER` 的统计里 `nObo`（"OB 是填充矩形"的计数）**已删** —— OB 不再是矩形，留着它只会永远打 0 并误导读者；② 同一处的 `\|\| StringFind(body,"OB_")==0` 死条件一并删除 |
| 头部 | `# pdarray` 增 `obDraw=**horizontalline**@obLevel (zoneLo/zoneHi kept in data+CSV only; v1.50-s48)` |

### 62.3 顺带抓到一个**真 bug**（编译器与既有自检都抓不到）

`s46` 给 `# targets` 追加 `nodebreaks=…` 时，我在两段**格式字面量之间多写了一个逗号**：

```mql5
"… target line skipped)",          // ← 多余的逗号
"nodebreaks=nearest-node(…) …",
InpFibLegs));
```
⇒ 该调用变成 "**格式 + 2 个参数**"，而格式里只有 1 个说明符（`legs=%s`）。
**后果**：`legs=%s` 会**吃掉第一个参数**（那段 `nodebreaks` 文本），真正的 `InpFibLegs` 被忽略 ⇒
CSV 头部 `legs=` 字段**打印成另一段文字**。由于 `StringFormat` 是**变参**，MQL5 既不报错也不告警，**静默错位**。
已被下面这台新检查器抓到，已修（去掉逗号）并逐项复核。

⚠️ 这次事故与 §60.4 记的那次（给 `# switches` 加参数却漏加说明符）是**同一类**：
**变参格式化在 MQL5 里没有任何编译期保护**。所以不靠人眼，靠机器。

### 62.4 新增检查器 `Indictor/check_fmt.ps1`（**已做负测**）

遍历每个 `StringFormat` / `PrintFormat`：按**字符串状态 + 括号深度**切分**顶层逗号** ⇒ piece0 = 格式、其余 = 参数；
比较 `%` 说明符个数与参数个数。退出码 0 = 全对，1 = 有错位（可直接卡构建）。

| 测试 | 结果 |
|---|---|
| **正测**（真实源文件） | `60 call(s) checked, 0 mismatch(es)`，exit 0 |
| **负测 A**（故意多一个参数） | `BAD L984 spec=2 args=3` + exit 1 ✓ |
| **负测 B**（故意少一个参数） | `BAD L984 spec=2 args=1` + exit 1 ✓ |

三种易错形态都已覆盖并被验证：`\"` **转义引号**（初版误判为 0 specifier）、`%-26s` / `%04d` **带宽度**（初版不计数）、
`EnumToString(...)` 内的**嵌套括号**。脚本纯 ASCII（已核 0 个非 ASCII 字节），遵硬约定 6。

### 62.5 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | OB 画成水平线段 | ✅ | OB 渲染段 `UpsertLine(nm, time[rb], lvl, t2, lvl, clrOt, STYLE_SOLID, 1, false)` |
| 2 | 线在**关键价位**上 | ✅ | `lvl = g_result.ob[k].ref`（= `open[runOldest]`，由 `CisdSetLevel` `:2529` 写入） |
| 3 | 右端仍受 `InpPDEnd` 策略控制 | ✅ | `PdRightEnd(rb, b, zLo, zHi, …)`（未变） |
| 4 | 实体并集信息不丢 | ✅ | `zoneLo/zoneHi` 仍存于 `StructureEvent` 并进 CSV |
| 5 | 类型改名自动清理旧对象 | ✅ | 前缀 `OBLine_`；回收段"未注册即删除" |
| 6 | 标签不与 CISD 叠印 | ✅ | OB 标签 `lvl ± 0.1×ATR`；CISD 标签 `base ± 0.15×ATR`，同 bar 异侧 |
| 7 | 格式化错位不再复发 | ✅ | `check_fmt.ps1` 正测 0 mismatch（且负测两个方向都报警） |
| 8 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=00286372938A` / `ex5=6EB03E308E40` match=True；`audit_state.ps1` → `PASS`；`check_fmt.ps1` → `60 call(s), 0 mismatch` |

### 62.6 可证伪预测（重挂后看同一处）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 线上不再有色块 | 原先那几条 OB 灰带消失，换成**同价位的一条实线** |
| 2 | 线在哪 | 线应正好压在该 OB 的**关键价位**（此前实测 22/22 落在实体并集的边界上 ⇒ 线会与并集的下/上沿重合） |
| 3 | 旧矩形被清 | 不再有 `Structure_OB_*` 对象（回收段删除），只剩 `Structure_OBLine_*` |
| 4 | 头部自证 | 新 CSV 头部含 `obDraw=**horizontalline**@obLevel …`，且 `# colors` 里 `ob` 只以 `obLine=` 出现 |
| 5 | 其余族不动 | FVG 仍是色带；MSS/BOS/CHoCH/闭包标签与线的位置不变 |

---

## 63. 阶段 39：OB 标签移到**线段右端**（`v1.50-s49`）

**用户要求**：「OB的标记能否放到右边，而不是线段中心」。

### 63.1 为什么它原先"看起来在中间"

标签锚点取的是 **CISD 触发 bar**（= OB 的 `bar`），而线段右端由 `PdRightEnd()` 算出：

```mql5
int back = vb - n;            // PD_END_FIXED：n = InpPDRightBars（默认 12）
t = time[back];               // ⇒ 右端在触发 bar **之后 12 根**
```

⇒ 触发 bar 天然坐在 `[造势序列最旧一根 … 触发 bar+12]` 这段区间的**中偏右**位置 —— 不是设计成居中，而是"锚点选错了对象"。

### 63.2 改法与两个刻意的选择

| 项 | 取值 | 理由 |
|---|---|---|
| 锚点时间 | **`t2`**（线段右端） | 用户要求 |
| 水平锚 | **`ANCHOR_RIGHT_LOWER` / `ANCHOR_RIGHT_UPPER`**（锚点在文字**右缘**） | 文字**完全落在线段内**；若用左锚点，文字会伸出右端，在 `PD_END_NOW`（右端 = 当前 bar）时被图表右缘切掉 |
| 垂直锚 | 看跌 → `RIGHT_LOWER`（文字在锚点之上）；看涨 → `RIGHT_UPPER`（文字在锚点之下） | 否则文字的**生长方向**会把它推向线，把线压住 |
| 垂直偏移 | 仍为 `lvl ± 0.1×ATR`（未变） | 贴着线放 |

### 63.3 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 标签在线段右端 | ✅ | `UpsertText(lbl, t2, lp, "OB", clrOt, …)` `:5253`（锚点由 `time[b]` 改为 `t2`） |
| 2 | 文字不越出线段右端 | ✅ | `ANCHOR_RIGHT_LOWER/UPPER`（锚点在文字右缘） |
| 3 | 不压住线 | ✅ | 上下锚点按方向选；偏移量未变 |
| 4 | 线本身不动 | ✅ | `UpsertLine` 一行未改 |
| 5 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=4487774211BF` / `ex5=487ED8DD0C55` match=True；`audit_state.ps1` → `PASS`；`check_fmt.ps1` → `60 call(s), 0 mismatch` |

### 63.4 可证伪预测（重挂后看同一处）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 标签位置 | `OB` 字样出现在**线段的右端**（此前在被破 bar 处、视觉偏中） |
| 2 | 方向 | 看跌 OB 的 `OB` 在**线上方**、看涨在**线下方** |
| 3 | 不越界 | 文字不伸出线段右端；切到 `PD_END_NOW` 也不被图表右缘切掉 |
| 4 | 与 CISD 标签不叠 | `CISD` 仍在被破 bar 处、另一侧 0.15×ATR（未动）⇒ 两者分离 |
| 5 | 其余不动 | 线、FVG 色带、其它标签位置均不变 |

---

## 64. 阶段 40：**去掉 FVG 的文字标签**（`v1.50-s50`）

**用户要求**：「FVG不用加标签，标记颜色即可」。

### 64.1 改动

| 项 | 改动 |
|---|---|
| 标签 | 删除 `FVGLbl_*` 文本对象（含 `AddSceneName` 注册与 `UpsertText` 调用），以及只为它服务的 `lp` 偏移计算 |
| 保留 | **色带**（`FVG_*`，族色填充）+ **CE 点线**（`FVGCE_*`，族色点线）—— 这两者已足以按颜色识别 |
| 清理机制 | ⚠️ 不再注册 `FVGLbl_*` ⇒ 图上**残留的旧标签**会因"未注册即回收"被自动删除，不需另写清理逻辑（与阶段 29/31 同一套机制） |
| 未动 | 判据、`InpMaxEvents` 裁剪、`InpFvgHideFilled`、弱化配色规则（§61）全部不变 |

### 64.2 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 不再有 FVG 文字标签 | ✅ | FVG 渲染段只注册 `nm`(色带) 与 `nmc`(CE)，全文 `FVGLbl` 仅剩注释里的墓碑说明 |
| 2 | 色带与 CE 线仍在 | ✅ | `UpsertRect(nm, …)` / `UpsertLine(nmc, …)` 两行未动 |
| 3 | 旧标签自动清除 | ✅ | 名称不注册 ⇒ 回收段删除 |
| 4 | 不影响其它族 | ✅ | 只改 FVG 段；OB/MSS/BOS/CHoCH/闭包/CISD 未动 |
| 5 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=EE5492E99E5D` / `ex5=225EF56647FB` match=True；`audit_state.ps1` → `PASS`；`check_fmt.ps1` → `60 call(s), 0 mismatch` |

### 64.3 可证伪预测（重挂后看同一处）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 图上不再出现 `FVG` 字样 | 全部 `FVG` 文本消失（含此前那几条） |
| 2 | 色带与 CE 线保留 | 原位置的青色色带与中点虚线仍在，颜色不变（弱化的仍是淡青） |
| 3 | 旧对象被回收 | 不再有 `Structure_FVGLbl_*` 对象 |
| 4 | 其余族不动 | `OBLine_`/`CISD_`/`MSS`/`BOS`/`CHoCH` 的线与标签位置不变 |

---

## 65. 阶段 41：**做多 / 做空的 OB 分色**（`v1.50-s51`）

**用户要求**：「做多与做空的OB 颜色要区分开」。

### 65.1 改动

| 项 | 改动 |
|---|---|
| 输入项 | `InpColorOB`（单一蓝 `100,140,255`）→ **`InpColorOBUp` = `C'38,166,65'`（绿）/ `InpColorOBDn` = `C'248,81,73'`（红）** |
| 方向来源 | `g_result.ob[k].dir`：**`DIR_UP` = 做多 OB**（由被扫的**低点**派生，需求区）；**`DIR_DOWN` = 做空 OB**（由被扫的**高点**派生，供给区） |
| 弱化变体 | `lineOBD`（单一）→ `lineOBUpD` / `lineOBDnD`（各自 50% 淡版），弱化时仍能分辨多空 |
| 标签锚 | 顺带修正：`upSide` 的语义由"看跌"改为"**做多**"（`dir == DIR_UP`），上下锚点随之对调 —— 做多（绿）的标签在线下方、做空（红）的线上方 |
| 头部 | `# colors` 的 `ob=%s` → `obUp=%s obDn=%s`；`derivedFillDim` 的 `obLine=` → `obLineUp=` / `obLineDn=` |

**为什么用绿/红而不是另造新色**：本文件已有成对的**多空色**（`InpColorHtfUp = 38,166,65` / `InpColorHtfDn = 248,81,73`）。
复用它们 ⇒ 全图**只有一套"绿=多、红=空"约定**，不需要用户再记一套映射。
⚠️ 代价（如实记录）：`InpColorBOS = C'255,82,82'` 是亮红，与做空 OB 的红**相近**。
缓解：BOS 是**点线事件线 + 自带 `BOS` 标签**、OB 是**实线**；且两者通常不在同一价位。
若日后仍觉混，改 `InpColorOBDn` 一个输入即可，不动代码。

### 65.2 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 做多/做空 OB 不同色 | ✅ | `clrOt = dimO ? (upSide ? lineOBUpD : lineOBDnD) : (upSide ? InpColorOBUp : InpColorOBDn)` |
| 2 | 方向判据正确 | ✅ | `upSide = (g_result.ob[k].dir == DIR_UP)`；`DIR_UP` 由 `CheckCisd` 的 `cisdLowLevel` 分支（被扫低点）写入 `AddObFromRun(i, DIR_UP, …)` |
| 3 | 弱化后仍可分多空 | ✅ | 两个独立的 50% 淡版线色 |
| 4 | 头部自证 | ✅ | `# colors … obUp=38,166,65 obDn=248,81,73 … derivedFillDim … obLineUp=… obLineDn=…` |
| 5 | 旧的单一色输入彻底移除 | ✅ | 全文 `InpColorOB` / `lineOBD` 零命中 |
| 6 | 格式化参数不错位 | ✅ | `check_fmt.ps1` → `60 call(s), 0 mismatch` |
| 7 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=DDB702DB0092` / `ex5=72022A63712E` match=True；`audit_state.ps1` → `PASS` |

### 65.3 可证伪预测（重挂后看同一处）

| # | 判据 | 期望 |
|---|---|---|
| 1 | 分色 | 图上 OB 线段分成**绿/红两类**，不再全是蓝 |
| 2 | 方向正确 | **绿** OB 位于价格**下方**（需求区，由被扫低点派生）；**红** OB 位于价格**上方**（供给区） |
| 3 | 弱化仍可辨 | 逆偏置/位移不足的 OB 变**淡绿/淡红**，而不是灰 |
| 4 | 标签方向 | `OB` 字样：做多（绿）在线**下方**、做空（红）在线**上方** |
| 5 | 头部 | 新 CSV 的 `# colors` 行含 `obUp=38,166,65 obDn=248,81,73` |

---

## 66. 阶段 42：INIT 回显补上 HTF 蜡烛的**周期**（`v1.50-s52`）

**缘起**：用户问「假如我打开 5m 图，右边的 HTF 的蜡烛是什么周期的？」——
答案是 `InpCandleTF`（默认 `PERIOD_H4`），**且不随图表周期自动变**（源码里没有任何按 `_Period` 推导的分支）。
但核对时发现一个**可观测性缺口**：

| 位置 | 有没有 `tf=` |
|---|---|
| CSV 头部 `# render … tf=PERIOD_H4 …` | ✅ 有 |
| **专家日志 `STRUCT_SWITCH …`（唯一无条件打印的一行）** | ❌ **没有** |

⇒ 只翻专家日志的话**看不出这排蜡烛是哪个周期**；而 MT5 里**每个图表实例各自记住自己的输入值**，
同一指标挂在两张图上完全可能是两个不同的蜡烛周期 —— 这正是"参数是默认值"与"用户手改过"
在日志上不可区分的老问题（阶段 22 的同一教训）。

**改动**（一行）：`STRUCT_SWITCH` 的 `htfCandles=%s` 之后插入 `tf=%s`，参数位传 `EnumToString(InpCandleTF)`。
结果那行变成：

```
STRUCT_SWITCH … | htfCandles=true tf=PERIOD_H4 htfPlace=HTF_PLACE_RIGHT htfLabels=true htfShift=0 htfCount=4 | …
```

### 66.1 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | INIT 回显含蜡烛周期 | ✅ | `"htfCandles=%s tf=%s htfPlace=%s …"` `:1567`；参数 `EnumToString(InpCandleTF)` `:1574` |
| 2 | 变参不错位 | ✅ | `check_fmt.ps1`：`L1565 spec=22 args=22`，全局 0 mismatch |
| 3 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=07058E5F1A92` / `ex5=1222A6E8704A` match=True；`audit_state.ps1` → `PASS` |

### 66.2 用户明确**未采纳**的两项（记录在案，避免被当成遗漏）

问过"要不要把两个坑一起补"，用户只选了 A（INIT 回显），故以下**有意不做**：

| 项 | 现状 | 后果 |
|---|---|---|
| 「蜡烛周期 ≥ 图表周期」校验 | **不做**。`OnInit` 现有 8 项校验不含周期比较（`:1460-1540`） | 在 H1 图上把 `InpCandleTF` 设成 M5 不会报错，会照画 M5 蜡烛（那已不是 HTF）。注释里的"应 ≥ 图表周期"只是建议 |
| 低周期时"只警告不阻断" | **不做** | 同上 |

⚠️ 这是**已裁定的取舍**，不是漏项。

### 66.3 该取舍已于 §67 **被用户推翻并实施**（留痕）

上表的"不做"仅代表 `v1.50-s52` 当时的裁定。用户在下一轮明确要求：
「没有"蜡烛周期 ≥ 图表周期"的校验 这个问题也要改下」⇒ 见 §67。

---

## 67. 阶段 43：补上「**蜡烛周期 ≥ 图表周期**」校验（`v1.50-s53`）

**用户要求**：「没有"蜡烛周期 ≥ 图表周期"的校验 这个问题也要改下」——即 §66.2 里那份"已裁定不做"的清单，被**推翻**。

### 67.1 改动与被推翻的那一条

```mql5
if(InpShowHTFCandles &&
   PeriodSeconds(InpCandleTF) < PeriodSeconds((ENUM_TIMEFRAMES)_Period))
{
   PrintFormat("TradFi_Structure: InpCandleTF(%s) 必须 ≥ 图表周期(%s) —— "
               "否则画的不是高周期蜡烛，而是低周期蜡烛", …);
   return INIT_PARAMETERS_INCORRECT;
}
```

| 设计点 | 取值 | 理由 |
|---|---|---|
| 阻断 or 警告 | **阻断**（`INIT_PARAMETERS_INCORRECT`） | 与文件里其余 8 项输入校验**同一风格**；且"静默画错"比"拒绝加载"更糟 —— 这正是本条要治的病 |
| 是否看 `InpShowHTFCandles` | **看**（`&&`） | ⚠️ 若无条件校验：在 **D1 图**上用默认 `InpCandleTF = H4` 会**拒绝加载整个指标**（14400 < 86400）。而"关掉蜡烛"的人没有任何理由被一个用不到的输入项拦住。开着 → 该拦就拦；关了 → 放行 |
| 打印内容 | 同时给出**实际值**与**图表周期** | 否则用户只知道"被拒"，不知道要改成什么 |

⚠️ **副作用（如实记录）**：在周期高于 `InpCandleTF` 的图上（例如 D1 图 + 默认 H4 蜡烛），指标现在会**拒绝加载**并在专家日志打印原因。
这是一次**有意的行为收紧**：要么把 `InpCandleTF` 改成 ≥ 图表周期，要么把 `InpShowHTFCandles` 关掉。

### 67.2 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 存在"周期 ≥ 图表周期"的校验 | ✅ | `:1484-1499`（`PeriodSeconds(InpCandleTF) < PeriodSeconds(_Period)`） |
| 2 | 违例时给出可诊断的信息 | ✅ | 打印 `InpCandleTF(%s) 必须 ≥ 图表周期(%s)`（含两边的 `EnumToString`） |
| 3 | 与既有校验风格一致 | ✅ | 同为 `return INIT_PARAMETERS_INCORRECT`（该函数现共 10 处） |
| 4 | 关掉蜡烛时不误拦 | ✅ | 判据前置 `InpShowHTFCandles &&` |
| 5 | 变参不错位 | ✅ | `check_fmt.ps1`：新增那条 `spec=2 args=2`；全局 `61 call(s), 0 mismatch` |
| 6 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=CEDBB79568E2` / `ex5=7EDC50C7345F` match=True；`audit_state.ps1` → `PASS` |

### 67.3 可证伪预测（重挂后核对）

| # | 情形 | 期望 |
|---|---|---|
| 1 | M5 图 + 默认 `H4` 蜡烛 | **正常加载**（14400 ≥ 300），日志出现新增的 `tf=PERIOD_H4` |
| 2 | H1 图 + 默认 `H4` 蜡烛 | 正常加载（14400 ≥ 3600） |
| 3 | **D1 图 + 默认 `H4` 蜡烛** | **拒绝加载**，专家日志出现 `InpCandleTF(PERIOD_H4) 必须 ≥ 图表周期(PERIOD_D1)` |
| 4 | D1 图 + 关掉 `InpShowHTFCandles` | 正常加载（校验不生效） |
| 5 | H1 图 + 故意设 `M5` | 拒绝加载并打印原因（此前是静默画 M5 蜡烛） |

---

## 68. 阶段 44：HTF 蜡烛周期**自动推导**（`v1.50-s54`）

**用户要求**：「可以自动设置 HTF 蜡烛的周期吗？按照 4 倍及以上原则，按照我下面规定的映射：
1M→5M、5M→30M、30M→4H；不在上面映射表的按照 4 倍原则」

### 68.1 关键判断：**那张表不是新规则，而是"≥4 倍"在标准阶梯上的结果**

用户给了"表 + 表外按 4 倍"，看似需要"先查表、查不到再算"两套逻辑。
实测发现：在**标准阶梯**（券商实际提供的经典档位）上取"**第一个 ≥4×图表周期**"的档位，
**逐行复现**了用户给的三条 —— 于是规则只需要一条，不会出现"表与算法漂移"：

| 图表周期 | ×4 | 阶梯上第一个 ≥4× 的档位 | 用户表 | 一致？ |
|---|---|---|---|---|
| M1（60s） | 240s | M15? 否 → **M5(300)** | 5M | ✅ |
| M5（300s） | 1200s | M15(900) 否 → **M30(1800)** | 30M | ✅ |
| M30（1800s） | 7200s | H1(3600) 否 → **H4(14400)** | 4H | ✅ |

⚠️ **阶梯里刻意不收 M2/M3/M4/M6/M10/M12/M20/H2/H3/H6/H8/H12** ——
这正是"1M 得到 M5 而不是 M4"的原因（M4=240s 恰好等于 4×M1；若把 M4 放进候选，1M 会推出 M4，与用户的表冲突）。
⇒ "**只收经典档位**"这一条是**被用户给出的表反推出来的约束**，不是我随手选的。

表外各档（同一规则，已用脚本独立算过一遍）：

| 图表 | M15 | H1 | H4 | D1 | W1 | MN1 |
|---|---|---|---|---|---|---|
| 蜡烛 | **H1**（4×） | **H4**（4×） | **D1**（6×） | **W1**（7×） | **MN1**（4.29×） | **MN1**（无更高档，退化=图表周期） |

### 68.2 实现

| 项 | 做法 | 理由 |
|---|---|---|
| 新枚举 | `ENUM_HTF_TF_MODE { HTF_TF_MANUAL, HTF_TF_AUTO }`；输入 `InpHtfTFMode`，**默认 `HTF_TF_AUTO`** | 用户要的就是自动 |
| 纯函数 | `AutoCandleTF(chartTF)`：阶梯数组 + `PeriodSeconds(ladder[i]) >= cs*4` 首个命中；查不到 → `MN1` | 便于逐行核对（无状态、无副作用） |
| 统一取值口 | `EffCandleTF()`：AUTO → `AutoCandleTF(_Period)`，否则 `InpCandleTF` | 全指标**只从这里取**，数据路径不再直接读输入项（27 处已替换） |
| 为什么不用全局缓存 | **保持纯函数** | 换成全局就要"复位 + 进指纹"两处维护，多一类"会陈旧"的坑；纯函数两样都不需要（沿用 `EffectiveBreak()` 的先例） |
| 周期校验 | §67 那条改成校验 `EffCandleTF()` | 自动模式下推导值必然 ≥4× ⇒ 该校验自然通过；手动模式仍按原样拦 |
| 可观测性 | INIT 回显与 CSV `# render` 都增 `tfMode=`（并保留 `tf=`） | "这排蜡烛是 H4"这句话，从此能分辨是**自动推出来的**还是**用户手填的** |

### 68.3 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 可自动设置蜡烛周期 | ✅ | `InpHtfTFMode`（默认 AUTO）`:254`；`EffCandleTF()` `:2427` |
| 2 | 1M→5M / 5M→30M / 30M→4H | ✅ | `AutoCandleTF()` `:2407-2420`；**逐行核算见 §68.1**（脚本独立复算一致） |
| 3 | 表外按 ≥4 倍 | ✅ | 同函数；表外 6 档全部核对（§68.1 第二张表） |
| 4 | 不写死映射表 | ✅ | 规则只有"阶梯 + ≥4×"一条；三行映射是它的推论 |
| 5 | 与§67 的周期校验不冲突 | ✅ | 校验改用 `EffCandleTF()`；AUTO 必然通过 |
| 6 | 无新增状态/指纹负担 | ✅ | 纯函数；`audit_state.ps1` 的 D 检查无新条目 |
| 7 | 口径可自证 | ✅ | INIT `… htfCandles=true tfMode=HTF_TF_AUTO tf=PERIOD_M30 …`；CSV `# render … tfMode=… tf=…` |
| 8 | 变参不错位 | ✅ | `check_fmt.ps1`：`# render` 11/11、`STRUCT_SWITCH` 23/23、周期校验 3/3，全局 `61 calls, 0 mismatch` |
| 9 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=7364C7852094` / `ex5=C6687C99D0D4` match=True；`audit_state.ps1` → `PASS` |

### 68.4 可证伪预测（重挂后核对）

| # | 图表 | 期望 `tf=` | 备注 |
|---|---|---|---|
| 1 | **M5** | **`PERIOD_M30`** | ⚠️ **默认值变了**：此前固定 H4，现在自动给 M30（用户给的映射 5M→30M） |
| 2 | M1 | `PERIOD_M5` | 用户表原样 |
| 3 | M15 | `PERIOD_H1` | 表外，≥4× |
| 4 | M30 | `PERIOD_H4` | 用户表原样 |
| 5 | H1 | `PERIOD_H4` | 表外，4× |
| 6 | H4 | `PERIOD_D1` | 表外，6× |
| 7 | 切到 `HTF_TF_MANUAL` + `InpCandleTF=H4` | `PERIOD_H4`（任何图表上都一样，只要 ≥ 图表周期） | 回退路径 |
| 8 | 日志口径 | 新 INIT 行含 **`tfMode=HTF_TF_AUTO tf=PERIOD_M30`** | 能分清"自动推出"与"用户手填" |

---

## 69. 阶段 69：节点级破位的**口径**与**翻转闸门**（`v1.50-s55`）

**用户要求**：「我画的两个框应该也都是BOS才对吧」（2026-09-30，XAUUSD **M1** 04:18–05:30 上涨段，两处框选；
左框 ≈4122.4 上是紫色 `CHoCH`；右框内读到的是青色 CISD 线 + 下方 `OB` 标签，未见 `BOS/CHoCH/MSS` 字样）。
用户裁定：**选项 C = 两条都上**（口径 + 闸门各自独立、可分别关掉）。

### 69.1 症状与代码级成因

左框那个 `CHoCH` 的来源是**确定的**：`CHoCH` 只能由 `ComputeChoch` 的**逆向分支**产生
⇒ 那一刻 `structDir == DIR_DOWN`。所以问题不是"没标"，而是"**结构方向被判成了空**"。

成因是**两层口径不一致**（不是审美问题）：

| # | 机制 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|
| 1 | 节点层直接复用引擎的 `BrokeLevel()`，继承 `InpBreakConfirm = BREAK_WICK` ⇒ **影线一扫即判破位、即翻转 `structDir`** | 输入 `:230`；`BrokeLevel()` `:2437`；调用点原为 `:3063`/`:3070` |
| 2 | 引擎对"影线触发的破位"**本来有闸门**（位移不足只记弱事件、**不翻转趋势**、不消耗结构位），节点层 s30/35 后加，**这道闸门漏了** | `:227-229` 注释，引他的话 *"The sweep itself is not the confirmation."* |

M1 上"刺破即回"极多 ⇒ `structDir` 被反复打回 `DOWN` ⇒ 其后**每个上破高点**都被标成 CHoCH。
⚠️ 这与 `v1.50-s45` 修掉的"引擎状态结构性锁死"（§59.1）是**两个不同的 bug**：那次是状态锁死，这次是**口径过宽**。

### 69.2 两条改动

| 项 | 做法 | 理由 |
|---|---|---|
| ① 自带破位口径 | 新输入 `InpNodeBreakConfirm`（**默认 `BREAK_CLOSE`**）+ `EffectiveNodeBreak()`；判据本体参数化为 `BrokeLevelCal(..., cal)`，`BrokeLevel()` 退化成 `cal = EffectiveBreak()` 的薄壳 | 判据只有**一份实现**，避免两处 `switch` 漂移；引擎要接 sweeping，本层只判"结构是否真的被破" |
| ② 翻转闸门 | 新输入 `InpNodeFlipExtremeOnly`（**默认 true**）：逆向破位时 `flip = 顺势 ∥ 开关关 ∥ 无前驱 ∥ 新高>前高(或 新低<前低)` | 与 HH/HL 序列读法一致；无前驱时允许翻转 = 退回旧行为，不在窗口左缘锁死方向 |
| ③ 可观测 | 新增子类型 `NODEBRK_CHOCH_NOFLIP (=2)`：**图上仍画 CHoCH**，CSV `state` 列变 `CHoCH(borrowed-ICT-term;no-flip)` | 事后能复盘"这次逆势破位到底翻没翻" |
| ④ 回显 | CSV `# window … nodeBreak=%s`、`# switches … nodeFlipExtreme=%s`；INIT `STRUCT_SWITCH … nodeBreak=%s nodeFlipExtreme=%s` | 关掉开关后"图上没标签"与"功能没跑"必须可区分（§20 的教训） |

### 69.3 单调性：改动**只减不增**

两条都是收紧：`BREAK_CLOSE ⊂ BREAK_WICK`（能过收盘的必然能过影线），闸门只可能**减少** `structDir` 的翻转
⇒ 事件集合是旧集合的**子集**：**只可能把 CHoCH 变成 BOS，不可能凭空造出旧口径没有的破位**。
（与 §68 的"BODY ⊂ CLOSE ⊂ WICK 全序"同一原理。）这使"改坏了"的表现形态是可预测的：只会**变少**，不会多出陌生标记。

### 69.4 被否掉的方案：用 `intermediate`(tier-1) 当翻转闸门

选项 C 的原始写法是"只有 **tier-1 节点的逆向破位**才翻转"。核算后**否掉**：

- `tier-1` 的定义（`ClassifyNodeTiers`）是"**比左右最近的同类型点都更极端**"= **局部顶/底**。
- 在**单边下跌**里，`low` 序列逐级下移，只有**最后一个（最低）**满足"比左右都低"
  ⇒ **整段下跌期间没有任何低点算 tier-1** ⇒ 逆向破位永不翻转 ⇒ **每个下破都标 CHoCH**，等于把问题从上涨搬到下跌。
- 另有一条边界：循环条件 `k + 2 < n` ⇒ 最新两个节点**永远是 tier-0**，闸门天然滞后。
- ⇒ 改用"**相对上一个同类型节点是否创新极值**"（LL/HH）：单边里第二个低点即成立，无滞后、无边界问题。

**不得再把 tier-1 当作等价方案**（此为终态记录）。

### 69.5 离线核验（`Indictor/kernel_sim_choch.ps1`）

把本层**内核**（不含 MT5 依赖）独立重写，用同一条合成序列跑四种组合（`CHoCH*` = 逆向但**未**翻转）：

| 组合 | 事件数 | 标签序列 |
|---|---|---|
| 旧：WICK + 逆向必翻 | 8 | CHoCH×7, BOS×1 |
| 只加闸门：WICK + 新极值才翻 | 8 | CHoCH×5, `CHoCH*`×2, BOS×1 |
| 只改口径：CLOSE + 逆向必翻 | 4 | BOS, CHoCH, BOS, BOS |
| **本次：CLOSE + 新极值才翻** | 4 | BOS, `CHoCH*`, CHoCH, BOS |

- 读法：旧口径把 8 次破位里的 7 次标成 CHoCH；新口径只留 4 次（**影线扫过的 3 次不再算破位**），
  且上涨段里的上破最终落在 **BOS**；中间那次 `CHoCH` 是"破了更高的高点 ⇒ 合法改性格"。
- ⚠️ **负测试（证明该 sim 不是橡皮图章）**：第一版把 MT5 的**递减 bar 序**照抄成"递增 i + `nodes[p].bar >= i`"，
  结果只吐出 2 条荒谬事件（`bar 1 UP-break of 99`）。改成 `<=` 后才得到上表 ⇒ 该工具**会失败**，不是恒真。
- ⚠️ 它是**方向性对照工具**，不是 MT5 行为的证据；MT5 侧证据 = CSV + 实机观感。

### 69.6 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 影线扫过不再算破结构 | ✅ | `InpNodeBreakConfirm=BREAK_CLOSE` `:254`；`EffectiveNodeBreak()` `:2439`；调用 `:3107`/`:3117` |
| 2 | 逆向破位仅在**创新极值**时翻转方向 | ✅ | `InpNodeFlipExtremeOnly` `:255`；闸门 `:3110`/`:3120`；前驱跟踪 `:3093`/`:3098` |
| 3 | 两个开关可**分别**关掉（A/B 对照） | ✅ | 二者互相独立：口径 `:254`、闸门 `:255` |
| 4 | 未翻转的逆向破位仍可复盘 | ✅ | `NODEBRK_CHOCH_NOFLIP` `:617`；CSV `state` `:1213`；日志三分支 `:3039` |
| 5 | 不新增全局状态 / 指纹负担 | ✅ | 纯局部变量；`audit_state.ps1` → `PASS (0 problems)`，D 检查无新条目 |
| 6 | 变参不错位 | ✅ | `check_fmt.ps1` → `61 call(s) checked, 0 mismatch(es)`（含新加的 2 个 `%s`） |
| 7 | 借用词标注未被改动 | ✅ | CSV `state` 仍带 `borrowed-ICT-term`；README 三处标注未动 |
| 8 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=4A124C59E917` / `ex5=66BB3E8168BF` match=True；编码 `CRLF / bareLF=0 / 无 BOM` |

### 69.7 可证伪预测（重新挂载指标后核对）

| # | 观察点 | 期望 |
|---|---|---|
| 1 | INIT 行 | `build=v1.50-s55 … breakConfirm=BREAK_WICK … choch=true hideWeak=true nodeBreak=BREAK_CLOSE nodeFlipExtreme=true` |
| 2 | CSV `# window` 行 | 出现 `nodeBreak=BREAK_CLOSE` |
| 3 | CSV `# switches` 行 | 结尾出现 `nodeFlipExtreme=true` |
| 4 | M1 同类上涨段 | CHoCH **明显变少**，上破多为 `BOS`；若两处框的成因是"影线破位 / 破的是更高的低点"，它们应变成 BOS |
| 5 | CSV `state` 列 | 出现 `CHoCH(borrowed-ICT-term;no-flip)`（逆向但未翻转） |
| 6 | 把 `InpNodeBreakConfirm` 改回 `BREAK_WICK` | 事件数回升（可 A/B 对照，验证口径确在生效） |
| 7 | 关掉 `InpNodeFlipExtremeOnly` | CHoCH 变多、`;no-flip` 行消失 |
| 8 | **若两处仍是 CHoCH** | 说明方向是被一次**真正的收盘 LL** 翻下去的（结构确实转空）⇒ 要么接受，要么把 CISD(shift) 纳入方向判据 —— **需用户单独裁定**，且必须先排除 §59.1 的锁死风险 |

---

## 70. 阶段 70：`PositionTool` 的时间宽度抓手（`v1.12-s1`）

**用户报告**：「盈亏比工具的宽度无法调整」（2026-09-30）。

### 70.1 取证：先证明"用户拖了"，再证明"事件没落在抓手上"

该指标的 `CHARTEVENT_OBJECT_DRAG` 分支里有一行**无条件打印**的日志（`DBG … object-drag <对象名>`），
这是它当初为"拖不动"埋的自证锚点。于是终端日志本身就是取证工具 —— 统计 `MQL5\Logs\20260924~20260930.log`：

| 被拖动的对象 | 事件次数 |
|---|---|
| `PT_1S_ENTRY` | 10 |
| `PT_1S_TP` | 10 |
| `PT_1S_SL` | 6 |
| **`_HL` / `_HR`（宽度抓手）** | **0** |

两条结论同时成立：① 用户**确实在拖**（26 次事件）；② 事件**确实送达了指标**（不然日志里不会有线的事件）
—— 但**从来没有一次落在抓手上**。所以既不是"事件没来"（坑②那类），也不是"拖动代码没写"。

### 70.2 根因：抓手画在了入场线的**端点上**，命中被判给了线

抓手原名 `_HL/_HR`，实现是 `OBJ_ARROW(159)`（8px 实心圆），坐标 = `(t1, entry)` 与 `(t2, entry)`
—— 与 `OBJ_HLine`/`DrawHLine` 画出的 `OBJ_TREND`（`_ENTRY`）**两个端点完全重合**。
两个可选中对象命中区重叠时，MT5 把判定权给了**线**：用户"拖圆点"拖到的其实是入场线
⇒ 工具被**整体平移**，宽度一动不动 —— 正是他描述的现象。

> ⚠️ 注意这不是"没实现"：`OnDragObj` 里 `_HL`/`_HR` 两个分支一直存在且逻辑正确（左右边界各自受
> `t1 < t2` 约束）。**功能写了，但入口点不到** —— 与坑 ④（`OBJPROP_HIDDEN=true`）是同一类问题的两种表现：
> **能看见 ≠ 能点到**。

### 70.3 两条修法（互不依赖）

| # | 做法 | 为什么这样 |
|---|---|---|
| ① 把抓手**挪出线外** | `pH = max(entry, sl, tp) + 腿长×0.25`（腿长 = 止损/止盈里更长的那个；都没设时退 20 点），抓手画在 `(t1, pH)` 与 `(t2, pH)` | 与三根线**拉开坐标距离** ⇒ 命中不再有竞争者。偏移随工具自适应，不写死点数 |
| ② 抓手换 `OBJ_TEXT` 的 **◆** 字形 | `OBJPROP_FONTSIZE = InpFontSize + 5` | `OBJ_TEXT` 的命中框 = **文字外框**，比 8px 圆点大得多，且字号可调（`OBJ_ARROW` 的字形大小不可调） |
| ③ 面板加**兜底通道** | 新增一行 `宽度 N 根` + `−N / +N` 两个按钮（`DrawWidthControls()`，与"手数"行同一套做法）；新输入 `InpWidthStepBars`（默认 5）、`InpColorHandle` | **完全不依赖鼠标命中**：即便将来 MT5 的命中规则再变，宽度也能改 |
| ④ 两个入口同一语义 | 抓手拖右端与按钮 `+N` 都只改 `t2`（`t1` 固定），共用 `StepWidth()` 的钳位（至少 1 根） | 避免"两个入口各改一套"导致行为不一致 |

### 70.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/PositionTool.mq5`） |
|---|---|---|---|
| 1 | 宽度可调（鼠标） | ✅ | 抓手位置 `:666-668`；`DrawHandle()` 改为 `OBJ_TEXT` `:565-580` |
| 2 | 抓手不再与线抢命中 | ✅ | `pH` = 工具上沿 + `腿长×0.25` `:658-668`（与三根线均不相交） |
| 3 | 宽度可调（不依赖鼠标） | ✅ | `DrawWidthControls()` `:885-908`；`StepWidth()` `:911-931`；按钮处理 `:1501-1515`；轮询兜底已登记 `:1598` |
| 4 | 宽度有可读的量化显示 | ✅ | 面板 `宽度 N 根` `:1092-1093`；`WidthBars()` `:283` |
| 5 | 旧对象自动升级 | ✅ | `EnsureObj()` 见到同名异类型会**删除重建**（`:490` 附近）⇒ 已画的 `OBJ_ARROW` 抓手自动变成 `OBJ_TEXT`，无需手工清理 |
| 6 | 换周期/改参数不丢宽度 | ✅ | 宽度真值仍在 `t1/t2`，`Rebuild()` 从矩形读回（未改动） |
| 7 | 面板行数不超限 | ✅ | 新增 1 行；最坏分支计数 ≈ 11 行 < `PANEL_MAX=14` |
| 8 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=24D7C67DA39A` / `ex5=F46A4EB82FE3` match=True；`check_fmt.ps1 -Path PositionTool.mq5` → `48 call(s), 0 mismatch(es)` |

### 70.5 可证伪预测（重新挂载后核对）

| # | 操作 | 期望 |
|---|---|---|
| 1 | 重挂指标，看 INIT | `DBG v1.12-s1 init XAUUSD.ct <TF> tools=… ` |
| 2 | 看图上 | 每个工具**外侧**（三根线的上方）出现两个白色 **◆**；原有的圆点消失 |
| 3 | 拖右侧 ◆ | 宽度变化，面板 `宽度 N 根` 同步；日志出现 `DBG … object-drag <PT_<id><L|S>_HL>`（**这是关键预测**：`_HL` 要第一次出现在日志里） |
| 4 | 点面板 `宽度 +5` | 宽度 +5 根，日志（开 `InpDebug`）打 `DBG … width + -> N bar(s)` |
| 5 | 把宽度拖到 1 根以内 | 被钳位成 1 根，不会出现"线与矩形退化"的不可见对象 |
| 6 | 拖入场线 | 仍然是整体平移（宽度不变）—— 确认没有把两个手势搞混 |

---

## 71. 阶段 71：节点级「改性格」判据换成**腿回吐比例**，标签与翻转绑定（`v1.50-s56`）

**用户要求（第二轮）**：「怎么是两个choch？两个应该都是**内部的BOS**才对」（2026-09-30，XAUUSD M1）。
⚠️ 关键前提：这次截图时**用户已加载 s55**（日志 `build=v1.50-s55 … nodeBreak=BREAK_CLOSE nodeFlipExtreme=true`），
即 **s55 的两条修正没能解决他的问题** —— 记为"预测 #8 命中"，也说明 §69 的成因判断只对了一半。

### 71.1 为什么 s55 不够

s55 的闸门是"**被破节点本身是新的同侧极值**"。问题：**M1 的回撤几乎总能做出一个略低的低点**（LL）——
只要比上一个低点低一点点、且**收盘**在其下方，闸门就通过 ⇒ `structDir` 被打回 `DOWN` ⇒ 其后的上破又成 CHoCH。
即：闸门太容易通过，**"内部"与"外部"没有被区分开**。

用户的措辞给了正确口径：**回调破的是"内部"结构，不该改"外部"性格** ⇒

### 71.2 两条改动

| # | 改动 | 说明 |
|---|---|---|
| ① | **标签与翻转绑定** | `CHoCH` 的含义就是"性格改变" ⇒ **翻转 ⇒ CHoCH；不翻转 ⇒ BOS**。逆势但未翻转的破位记 `NODEBRK_BOS_INTERNAL(=2)`，**渲染与 BOS 完全一致**（用户要看到 "BOS" 字样），只在 CSV 的 `state` 列区分：`BOS(node-level,internal-break)` vs `BOS(node-level,borrowed-ICT-frame)` |
| ② | **新增 `InpNodeFlipMode`（4 档）** | `RETRACE`（**默认**：逆势破位**且已从腿极值回吐 ≥ `InpNodeFlipRetracePct`%（默认 50）整段腿**才算改性格）/ `LEG`（收盘越过腿起点）/ `EXTREME`（= s55）/ `ANY`（= s45–s54）。**默认档自尺度、无绝对点数**，且 50% 正是贴现区 EQ（用户熟悉的量） |
| ③ | **腿状态随扫描推进** | `legLvl` = 腿起点价（趋势确立/翻转时反向的最近节点）；`legExt` = 腿内沿趋势方向的极值（逐 bar 刷新）。⚠️ 两者都是**当时的**值，不是最终值 —— 后验层最容易的错误就是拿最终状态解释历史（§54 的教训） |

### 71.3 离线核验：`Indictor/kernel_sim_choch.ps1`（同一条合成序列跑 8 种组合）

| 档（caliber=CLOSE） | 标签序列 |
|---|---|
| `s45–s54`：WICK + 必翻 | CHoCH, CHoCH, CHoCH, CHoCH, CHoCH, BOS, CHoCH, CHoCH |
| `s55`（今天加载的）：CLOSE + 新极值闸门 | BOS, **CHoCH\***, **CHoCH**, BOS |
| `s70` `LEG` | BOS, **CHoCH**, **BOS**, BOS |
| `s70` **默认 `RETRACE` 50%** | BOS, **CHoCH**, **BOS**, BOS |
| `s70` `RETRACE` 25% | BOS, CHoCH, BOS, BOS |
| `s70` `ANY`（对照） | BOS, CHoCH, BOS, BOS |

（`CHoCH*` = s55 口径下"逆势但未翻转、却仍写 CHoCH"。前四行**逐字复现 §69.5 的表**，故旧表仍有效。）
读法：s55 那行里**第二个上破是 CHoCH**（正是用户看到的症状：连续两处 CHoCH）；s70 的 `RETRACE`/`LEG` 把它变成 **BOS** ✓，
而"真正改性格"的那一次仍保留 `CHoCH` ✓。⚠️ 该工具是**方向性对照**，不是 MT5 行为的证据；
且它**会失败**（§69.5 记过一次扫反 bar 序的负测试）。

### 71.4 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 内部破位显示为 `BOS` 而不是 `CHoCH` | ✅ | `NODEBRK_BOS_INTERNAL` `:629`；渲染 `isBos = (sub != NODEBRK_CHOCH)` `:5272` |
| 2 | `CHoCH` 只在真改性格时出现 | ✅ | `NodeFlipUp/NodeFlipDn()` `:3067`/`:3084`；调用 `:3176`/`:3190` |
| 3 | 四档口径可现场切换（不用重编译） | ✅ | `InpNodeFlipMode` `:265`；`InpNodeFlipRetracePct` `:266` |
| 4 | 判据用的是"当时的腿"，不是最终状态 | ✅ | `legLvl/legExt` 随扫描更新 `:3143-3144` 与 `ComputeChoch` 循环首 |
| 5 | CSV 能区分两种 BOS | ✅ | `state` 列 `:1225-1229` |
| 6 | 口径可自证（INIT + CSV 双回显） | ✅ | `nodeFlip=%s flipRetr=%.1f`（INIT `:1652`、CSV `# switches` `:1029`）；取值用 `:1050-1052` / `:1665-1667` 的三元链 |
| 7 | 变参不错位 | ✅ | `check_fmt.ps1` → `61 call(s), 0 mismatch(es)` |
| 8 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=DA7B8AE69CE5` / `ex5=FA34096BE961` match=True；`audit_state.ps1` → `PASS` |

### 71.5 可证伪预测（重新挂载后核对）

| # | 观察点 | 期望 |
|---|---|---|
| 1 | INIT 行 | `build=v1.50-s56 … nodeBreak=BREAK_CLOSE nodeFlip=RETRACE flipRetr=50.0` |
| 2 | 用户框的那两处 | **变成红色 `BOS`**（`RETRACE` 默认档下，那两处回撤不足以作废整条腿） |
| 3 | 05:14 那段大幅下跌 | 跌到**回吐整段上涨腿的 50%** 附近出现一次 `CHoCH`（不是一连串） |
| 4 | 把 `InpNodeFlipRetracePct` 调到 `15~20` | CHoCH 明显变多（可即时验证判据在生效） |
| 5 | 把 `InpNodeFlipMode` 换成 `LEG` | CHoCH 更少（只有整条腿被作废才翻） |
| 6 | 换成 `EXTREME` / `ANY` | 复现 s55 / s45–s54 的观感（A/B 对照） |
| 7 | CSV 的 `state` 列 | 出现 `BOS(node-level,internal-break)` |
| 8 | **若两处仍是 CHoCH** | 说明那条腿的起点就在附近（价格已回吐 ≥50%）⇒ 需要看 CSV 里的节点序列表：届时请按 `Shift+D` 导出 M1 的 CSV，我按 `refBar/refPrice/dir/tier` 逐行复盘 |

---

## 72. 阶段 72：SWEEP 判据收紧（实体不越界 + 被接受即停）（`v1.50-s57`）

**用户要求**：「我框出来的这里都实体突破了，不算 sweep 了吧」（2026-09-30，XAUUSD M1，含红框截图）。

### 72.1 取证：先把用户框的那个 SWEEP 定位到像素

对截图做**颜色定位**（`InpColorSweep = C(255,152,0)`，容差 ±12/±20/±40）而不是靠肉眼：

| 元素 | 像素坐标（截图 1615×672） |
|---|---|
| 橙色 SWEEP 点线所在行 | `y = 207`（实心像素 281 个） |
| 该点线的 x 跨度 | **x = 306 → 865**（左端 = 被扫节点，右端 = 扫荡那根 K 线） |
| `SWEEP` 文字 | x = 851–881，y = 206–213（就在点线右端 = 扫荡 bar 处，与渲染逻辑一致） |
| 用户红框 | y 197–217，右边界 ≈ **x 894** ⇒ **整条 SWEEP 标注都在框内** |

⇒ 用户指的就是这一条 SWEEP，而不是别的元素。

### 72.2 判据缺的两条（旧实现为什么错）

旧判据只有一句：`high[i] > lvl && close[i] < lvl`（扫高）。两个漏洞：

| # | 漏洞 | 用户看到的现象 |
|---|---|---|
| ① | **只看收盘**，不看开盘 ⇒ "开在位外、收在位内"的跨位大 K 线也算 sweep | 「**实体**突破了」 |
| ② | 只在**命中 swept** 时才 `break`；**收盘越界（被接受）不终止扫描** ⇒ 位被破之后的一次回抽（刺破+收回）仍会被记成 sweep | 框内明明已经突破过，却又标了一个 SWEEP |

### 72.3 改动（`ComputeSweeps`，两条都只**减少**事件）

```mql5
bool swept = isHigh ? (high[i] > lvl && close[i] < lvl && open[i] <= lvl)   // ①
                    : (low[i]  < lvl && close[i] > lvl && open[i] >= lvl);
if(swept) { AddSweepResult(...); break; }                                   // 每位的首次
const bool accepted = isHigh ? (close[i] > lvl) : (close[i] < lvl);         // ②
if(accepted) break;                                                         // 被接受 ⇒ 该位作废
```

⚠️ 顺序不可反：`swept`（收盘在位内）与 `accepted`（收盘在位外）在**收盘这一维互斥**，
先判 swept 才能保证"**先扫后破**"的那一次仍被记录下来。
⚠️ 函数签名新增 `open[]`（调用点 `:3938`），`check_fmt` 不受影响（没有格式串）。

### 72.4 离线核验：`Indictor/kernel_sim_sweep.ps1`（四例，位 = 100，扫高）

| 例 | 形态 | 旧 | 新 |
|---|---|---|---|
| A | 影线越界、开收都在位内 | SWEEP | **SWEEP** ✓（没有过度收紧） |
| B | **开盘在位外**、收盘收回位内（跨位 K 线） | SWEEP | **不算** ✓（①，正是用户说的"实体突破"） |
| C | **先收盘越界**（被接受），之后又刺破并收回 | SWEEP（标在第 2 根） | **不算** ✓（②，那是破位后的回抽） |
| D | 先影线扫过一次，**之后**才收盘越界 | SWEEP | **SWEEP** ✓（不删历史；先扫后破的那次保留） |

该核验脚本与 MQL5 判据是**同一套比较**，且**会失败**（B/C 两例在旧口径下确实输出 SWEEP）。

### 72.5 要求 → 是否满足 → 证据

| # | 要求 | 是否满足 | 证据（`Indictor/Structure.mq5`） |
|---|---|---|---|
| 1 | 实体越界的不算 sweep | ✅ | `open[i] <= lvl` / `open[i] >= lvl` `:3289-3290` |
| 2 | 已被突破过的位不再记 sweep | ✅ | `accepted` 早停 `:3299-3300` |
| 3 | 先扫后破的那次仍保留 | ✅ | 先判 `swept` 再判 `accepted` `:3291-3300` |
| 4 | 只减少、不新增事件 | ✅ | 两条都是合取项收紧；核验表 A/D 形状不变 |
| 5 | 口径写进文档（三处） | ✅ | 输入组注释 `:398-404`；README 颜色表 / SWEEP 条 / 输入表 |
| 6 | 离线可复核 | ✅ | `Indictor/kernel_sim_sweep.ps1`（纯 ASCII，四例对照） |
| 7 | 编译 / 部署 / 自检 | ⚠️ 已测 | `0 errors, 0 warnings`；`mq5=E5F941177C79` / `ex5=0743A0A9EB6D` match=True；`audit_state.ps1` PASS；`check_fmt.ps1` 61 calls / 0 mismatch |

### 72.6 可证伪预测（重新挂载后核对）

| # | 观察点 | 期望 |
|---|---|---|
| 1 | INIT 行 | `build=v1.50-s57 …` |
| 2 | 用户框的那一处 | **SWEEP 标注消失**（该位在框内已被收盘接受 ⇒ ② 生效） |
| 3 | CSV 头部 `SWEEP=n` | 同一窗口内**比 s56 少**（可 A/B 对照） |
| 4 | 找一根"开在位外、收在位内"的跨位 K 线 | 不再被标 SWEEP（① 生效） |
| 5 | 找一次真正的"扫后即收"（实体全在位内） | 仍然标 SWEEP，且**点线右端就在那根** |
| 6 | 若框内那处**仍在** | 说明该位的"被接受"发生在框**之后**（即那次 sweep 早于突破）⇒ 请按 `Shift+D` 导出 CSV，我按 `breakTime/refTime/refPrice` 逐行核 |


