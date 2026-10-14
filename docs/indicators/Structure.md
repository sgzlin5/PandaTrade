# Structure

> 源文件：`Indictor/Structure.mq5` ｜ 详细口径与参数（自 README 拆分） ｜ [返回 README](../../README.md)


> `Indictor/Structure.mq5`

市场结构指标，在**主图表窗口**上绘制结构折线与四类事件标注。**结构与事件口径对齐 TTrades**：

- 对齐过程、逐阶段验收数据、以及被测量推翻过的设计假设 → `docs/plans/2026-09-23-TTrades-alignment.md`
- 他的一手原文引用与配图 → `docs/research/2026-09-23-TTrades-structure.md`、`docs/research/img/`
- 逐版本事件基线（可逐行 diff）→ `docs/baselines/`
- **验收 runbook（一页）** → `docs/sop/2026-09-24-Structure-acceptance-runbook.md`

> **运行时验收状态（2026-09-24 14:17，构建 `v1.50-s23`）**：
> 四个新增功能（IC-CISD / HTF 蜡烛 / C2·C3 收盘确认 / 目标投影）与 closure 累加修复
> **已在真机上通过全部判据**（详见 plan §42）：`invariant=OK`、`closure=58=nodes` 且**三帧同值**
> （修复前同一跨度上是 59→117→175）、`HTF=16`、`TGT=6`、`FIB=10`、三种 closure 子类型齐全。
> ⚠️ **唯一未获正面证据的是 IC-CISD 是否真的触发过** —— 逐帧采样会漏掉 bar 内触发又消失的情况，
> 故 `v1.50-s24` 加了累计计数 `icHits`（看 `TradFi_RENDER` 那一行）。

#### 效果预览

| 元素 | 颜色 | 说明 |
|---|---|---|
| 结构线 | ![#39c5cf](https://placehold.co/12x12/39c5cf/39c5cf.png) `#39c5cf` | 连接全部确认 swing 点的锯齿折线（`OBJ_TREND` 逐段），实线 1px |
| **MSS** | ![#ffd54f](https://placehold.co/12x12/ffd54f/ffd54f.png) `#ffd54f` | 逆势破位 **+ 破位确认（默认影线触及） + 位移确认**（位移是趋势改变的**构成条件**），横向**密集点线** + 线正中 `MSS` 文本 |
| **BOS** | ![#ff5252](https://placehold.co/12x12/ff5252/ff5252.png) `#ff5252` | 顺势突破受保护结构位（同一破位判据），横向**密集点线** + 线正中 `BOS` 文本 |
| **CISD** | ![#ba68c8](https://placehold.co/12x12/ba68c8/ba68c8.png) `#ba68c8` | 收盘穿越「造势序列最旧一根的开盘价」，横向虚线 + `CISD` 文本 |
| **SWEEP** | ![#ff9800](https://placehold.co/12x12/ff9800/ff9800.png) `#ff9800` | intermediate 位被**影线**越过、**收盘收回位内**，且**实体两端都不越界**（`v1.50-s57` 收紧），横向点线 + `SWEEP` 文本 |
| relevant 位 | ![#82b4ff](https://placehold.co/12x12/82b4ff/82b4ff.png) `#82b4ff` | 高周期回看 3 根 K 线的极值，两条点线 |
| **dealing range** | ![#82b4ff](https://placehold.co/12x12/82b4ff/82b4ff.png) `#82b4ff` | relevant high/low 连成的区间矩形，内含 `PREMIUM` / `DISCOUNT` 分区标签 |
| 均衡位 EQ | ![#ffd54f](https://placehold.co/12x12/ffd54f/ffd54f.png) `#ffd54f` | 区间 50% 处，即 premium / discount 的分界（**默认不显示**，`InpShowEQ` 打开） |
| 偏置标签 | ![#00bcd4](https://placehold.co/12x12/00bcd4/00bcd4.png) `#00bcd4` | `HTF bias BULL/BEAR/NONE (PERIOD_D1)` |
| **FVG** | ![#00c8b4](https://placehold.co/12x12/00c8b4/00c8b4.png) `#00c8b4` | 三根 K 线缺口（影线对影线）**着色区域** + 中点 CE 点线。**无文字标签**（`v1.50-s50` 起，用户要求）：色带 + CE 线的颜色已足够识别。⚠️ **弱化时用同族淡青**（不是中性灰，`v1.50-s47`）——色相表示族别，浓度表示确认度 |
| **OB** | ![#26a641](https://placehold.co/12x12/26a641/26a641.png) `#26a641` 做多 / ![#f85149](https://placehold.co/12x12/f85149/f85149.png) `#f85149` 做空 | 造势序列**实体区间**的关键价位上一条**水平线段** + `OB` 文本。**做多/做空分色**（`v1.50-s51`）：绿 = 需求区（由被扫的**低点**派生）、红 = 供给区（由被扫的**高点**派生）—— 复用 HTF 蜡烛那套多空色，全图"绿=多、红=空"单一约定。无收盘穿回则不成立，**位移不足/逆偏置则用同族淡色** |
| **IRL** | ![#00c8b4](https://placehold.co/12x12/00c8b4/00c8b4.png) `#00c8b4` | Internal liquidity = **FVG**（就是上面的 FVG 色带），偏置方向上的那条标 `IRL` |
| **ERL** | ![#e91e63](https://placehold.co/12x12/e91e63/e91e63.png) `#e91e63` | External liquidity = **摆动高/低**，偏置方向上最近的、**尚未被取走**者，点线 + `ERL`。⚠️ 它与 `T1` 是**同一个节点**（构造性同位）⇒ 同位时标签合并为 **`ERL/T1`**，目标侧那条不再单独画（`v1.50-s44`）。⚠️ `v1.50-s66` 起**默认关闭**（`InpShowERL=false`；开关已与 `InpShowIRL` 拆分）|
| **PDH / PDL** | ![#455a64](https://placehold.co/12x12/455a64/455a64.png) `#455a64` | **前日（最近一根已收盘 D1）的最高/最低点**，两条点线 + **线右端** `PDH`/`PDL` 标签（`v1.50-s64` 起；此前锚在**线中点**，周一/节后中点在视野左侧 2~3 屏外 ⇒ 文字看不到）。⚠️ `v1.50-s62` 起默认色由近白 `#e0e0e0` 改为深蓝灰 `#455a64`（白底图表上近白几乎不可见）|
| **前日 50%** | ![#78909c](https://placehold.co/12x12/78909c/78909c.png) `#78909c` | 前日**区间**的中点 `(PDH+PDL)/2`，**虚线** + 右端 `PD50` 文字（`v1.50-s65` 新增，默认显示；与 PDH/PDL 同族淡一档）|
| **HTF 蜡烛** | ![#26a641](https://placehold.co/12x12/26a641/26a641.png) `#26a641` / ![#f85149](https://placehold.co/12x12/f85149/f85149.png) `#f85149` | 高周期蜡烛（实体矩形 + 上下影线），默认 4 根 H4。**默认画在主图右侧的未来留白区**（`InpHtfPlacement = HTF_PLACE_RIGHT`），既不压住真实 K 线、又保住价格刻度对齐（留白区内**左→右 = 由旧到新**，与主图时间轴同向）；想看回他的画法（叠加在真实时间位置）改成 `HTF_PLACE_OVERLAY` |
| **IC-CISD** | ![#ff8ad8](https://placehold.co/12x12/ff8ad8/ff8ad8.png) `#ff8ad8` | **收盘前**的临时 CISD 预览：点线 + `IC-CISD` 标签。只活在未收盘 bar 内，**不写任何状态字段**（见下） |
| **C2 / C3 收盘确认** | ![#7ee787](https://placehold.co/12x12/7ee787/7ee787.png) `#7ee787` / ![#ffd666](https://placehold.co/12x12/ffd666/ffd666.png) `#ffd666` | swing 点上的**有效收盘确认**：`C2`（扫破前根后收回）/ `C3`（迟到一根，收在 C2 实体外）/ `C2-CONT`（延续收盘，**不是**有效反转确认）；C3 另画其区间 50% 均衡位 |
| **CHoCH** | ![#7b1fa2](https://placehold.co/12x12/7b1fa2/7b1fa2.png) `#7b1fa2` | **借用 ICT 术语**（非他的概念）：逆内部趋势破最近结构节点即标，不要求 protected swing；与 MSS/BOS 同位时让位。详见下文"CHoCH"条 |
| **Auto Targets** | ![#e91e63](https://placehold.co/12x12/e91e63/e91e63.png) `#e91e63` | 偏置方向上**尚未被取走**的流动性位，按价格距离取最近 N 个（`T1`/`T2`/…），并追加 PDH/PDL。（⚠️ `v1.50-s61` 起**默认关闭**）⚠️ `T1` 与 `ERL` 恒为同一个节点 ⇒ 同位时并入 `ERL/T1` 标签 |
| **投影目标** | ![#ffab40](https://placehold.co/12x12/ffab40/ffab40.png) `#ffab40` | 从**操纵腿**外推的水平（`1.0x`/`2.0x`/`2.5x`/`4.0x`）。（⚠️ `v1.50-s61` 起**默认关闭**）⚠️ **方向约定是本实现反号的读法**，见下 |
| 未获确认的事件 | `#6e6e82` 灰 | 位移不足**或**与 HTF 偏置逆向 → 暗色点线、**无文字标签**（仅适用于 MSS/BOS/CISD/SWEEP 这类**信号**） |
| PD Array 的暗色 | `#6e6e82` 灰 | FVG 的 CE 已被收盘穿越、OB 的位移不足、或与 HTF 偏置逆向 → **灰色轮廓 + 灰色调填充**，但**标签恒定保留**（它是地图不是信号；实测 82.5% 的 FVG 都会穿 CE，若据此去标签等于默认全部无标签） |

#### 核心概念

- **Swing（摆动点）**：**左右两侧都严格**的三点分形 —— `high[i] > high[prev] && high[i] > high[next]`（低点对称）。
- **failure swing 剔除**：与上一个**同类型** swing 的价格距离 < `InpMinSeparationATR × ATR` 的摆动点不予确认。
- **位移判据**：**逐路径生效，且原第②条「收盘穿越深度」已整体删除**。
  **MSS** = 实体 ≥ `InpMinDisplaceBodyATR×ATR` + 时效（首次影线穿越后 `InpDisplaceMaxBars` 根内收盘确认）；
  **CISD / OB** = 同样的①③，**另加**「**触发 bar 起 N 根内出现同向 FVG**」（`InpCisdFvgLookahead`，默认 5）**替代**原②。
  `pen` 仍逐条写入 CSV 的 `pen=` 列 —— 删掉的是**判据**不是**度量**，留着才能事后评估改动影响。
- **MSS（Market Structure Shift）**：逆势跌破/升破受保护结构位 **且** 满足三条位移判据。**位移是构成条件，不只是显示规则** —— 位移不足的破位会被记录但**不改变趋势状态**（*"MSS marks a trend change **confirmed by displacement**."*）。
  > **弱化 = 完全不画**（`v1.50-s42`，用户要求）：`weak`（位移不足）**或**逆 HTF 偏置的 MSS/BOS，**连灰线也不画**、对象根本不创建。`InpHideWeakBreaks=false` 可退回"灰线 + 无标签"（= v1.49 G1 观感）。⚠️ 只作用于渲染 —— 弱事件**仍照旧进 CSV**（`displacement` 列带 `WEAK`/`OK`），事后可复盘。⚠️ 因此**逆偏置的破位现在只能靠 CHoCH 层看到**（见下条）。
- **BOS（Break of Structure）**：顺势突破受保护结构位。⚠️ 逆 HTF 偏置的 BOS **完全不画**（见上条 MSS 的弱化口径）。
- **CHoCH / 节点级 BOS（`v1.50-s45` 起为同一层，`s55` 改口径）**：**逆/顺"结构方向"突破「最近一个结构节点」**——**不要求该节点是 protected swing**。同向 → 标 **`BOS`**（红色，他的术语）；反向 → 标 **`CHoCH`**（紫色，**借用 ICT 术语**）。开关 `InpShowChoch`。
  > ⚠️ **`s55` 起两条口径专治"上涨里处处 CHoCH"**（用户 2026-09-30 在 M1 上涨段框出两处 CHoCH 后裁定"两个都上"）：
  > ① **本层自带破位口径** `InpNodeBreakConfirm`，默认 **`BREAK_CLOSE`**（影线扫过**不算**破结构；被扫的位仍由 SWEEP 层标注，信息不丢）。起因：本层原来复用引擎口径 `BREAK_WICK` ⇒ **影线一扫即判破位、即翻转方向**；而引擎那边本来就有"位移不足只记弱事件、**不翻转趋势**"的闸门（引他的话 *"The sweep itself is not the confirmation."*）——**两层口径不一致是 bug，不是审美**。
  > ② **「改性格」判据** `InpNodeFlipMode`（`s55`→`s70` 两轮）：`CHoCH` 的含义是**性格改变**，所以现在**标签与翻转绑定** —— **翻转 ⇒ `CHoCH`；不翻转 ⇒ `BOS`**（逆势但没翻转的破位记 `NODEBRK_BOS_INTERNAL`，**图上就是 `BOS`**，只在 CSV 的 `state` 列写 `BOS(node-level,internal-break)`）。四档判据（默认 **`NODEFLIP_RETRACE`**）：
  > | 档 | 什么叫"改性格" | 备注 |
  > |---|---|---|
  > | `NODEFLIP_RETRACE` **（默认）** | 逆势破位**且已从腿极值回吐 ≥ `InpNodeFlipRetracePct`%（默认 **50%** = 贴现区的 EQ）** | 自尺度、无绝对点数；调低 → CHoCH 出现更早 |
  > | `NODEFLIP_LEG` | 逆势破位**且收盘越过「当前腿起点」**（趋势确立时反向的最近节点） | 最严：只有整条腿被作废才改性格 |
  > | `NODEFLIP_EXTREME` | 被破节点本身是**新的同侧极值**（LL/HH） | = `v1.50-s55` 的行为；**用户已确认它在 M1 上不够**（回撤几乎总能做出一个略低的低点） |
  > | `NODEFLIP_ANY` | 任何逆势破位都翻转 | = `s45–s54` 旧行为，留作 A/B 对照 |
  > 用户原话（2026-09-30 第二轮）：「怎么是两个 choch？两个应该都是**内部的 BOS** 才对」—— 即回调破的是**内部**结构，不该改**外部**性格。
  > ⚠️ 被否掉的替代方案：用 `intermediate`(tier-1) 当翻转闸门。tier-1 的定义是"**两侧都比它低/高**"的局部顶底，单边下跌里只有**最低点**满足 ⇒ 整段下跌"一直没翻转"、每个下破都标 CHoCH，等于把问题从上涨搬到下跌。记录于 plan §69.4，**不得再当等价方案**。
  > ⚠️ **离线核验**：`Indictor/kernel_sim_choch.ps1`（纯 ASCII）把本层内核**独立重写**一遍，用**同一条合成序列**跑 8 种组合（旧口径 / s55 / s70 四档），对比标签序列（`CHoCH*` = s55 口径下"未翻转但仍写 CHoCH"）。⚠️ 它是**方向性对照工具**，不是 MT5 行为的证据；MT5 侧的证据是 CSV + 实机。
  > ⚠️⚠️ **`CHoCH` 是借用 ICT 术语，不是他的概念。** TTrades 全站语料 `change of character` = **0**、`\bchoch\b` = **0**（同语料 `CISD` = 5、`displacement` = 20），plan §1 决策 A 正是据此**放弃**了这个词；本层是在他的口径**之外**另开一层，并在代码注释 / 本 README / CSV 的 `state` 列（`CHoCH(borrowed-ICT-term)`、`BOS(node-level,borrowed-ICT-frame)`）**三处标注**。引用时不得当作他的口径。
  > ⚠️ **CSV 里 `type=BOS` 现在有两种来源**：引擎（protected swing 破位 + 位移门槛）与**节点级**（本层，无位移门槛）。靠 `state` 列区分；头部有 `nodebreaks=…` 子句自描述。
  > **它补的是哪个盲区**：他的 MSS 只认"被 CISD 保护过的 swing"，且**每次 bearish MSS 之后高点参考位会被清空**（`ApplyMssTransition`）——于是在"没有 CISD 重建高点位"的窗口里，价格破掉一个肉眼明显的高点，引擎连可比的位都没有。本层用**节点**而不是 ref 判定，正好覆盖这段。
  > ⚠️ **结构方向是"上次破位方向"而不是引擎的 MSS 状态**（`v1.50-s45` 修正）：初版借了引擎状态，结果在 2026-09-29 那段上涨里把**连续破新高**全标成 CHoCH —— 因为 bearish MSS 清空高点位后，那个状态**结构性锁死在 DOWN**（plan §59.1 有完整机制）。`s55/s70` 起方向**只在通过「改性格」判据时**才改变（见上条 ②）；初值仍取第一段腿的方向。CSV 的 `state` 列还能区分两种 BOS：`borrowed-ICT-frame`（顺势延续）与 `internal-break`（逆势但没改性格）。
  > **与引擎同位时让位**（`v1.50-s43`，`s45` 收紧）：同一个结构节点若已有引擎 MSS/BOS（**含被隐去的弱事件**），本层不画 —— 否则要么两标签重叠难看，要么把刚隐去的弱判断换个名字显示出来。⚠️ 只影响画不画：CSV 行照旧导出；`InpDebugShowRef=true` 时会打印让位条数。
  > ⚠️ 它是**后验层**（与 closure 同层次，基于最终节点表）：同一类型被更极端节点**替换**过的地方，这里看到的是替换后的节点。
- **protected swing（受保护结构位）**：**由 CISD 定义** —— *"A protected swing is created when price **closes through the series of opposing candles** that led into a high or low."* 即 **CISD 触发的那一刻就是它成立的那一刻**，锚点 = 造势序列的极值。它同时是止损位（*"the protected swing becomes the low that should hold"*），被突破即失效。**他的定义里没有层级门槛、也没有幅度门槛**（v1.49-s11 起删除了旧的"腿长 ≥1.0×ATR 或 ≥0.382×前段"门槛，因为它无一手依据）。
- **CISD（Change in the State of Delivery）**：以「造势那一串同向收盘 K 线」**最旧那根的开盘价**为位，收盘穿越即触发；**不看 swing、与趋势状态无关**。
- **IC-CISD / Early CISD（收盘前的临时 CISD）**：触发条件与上面的 CISD **完全相同**，唯一差别是判定用的"当前价"——正式 CISD 用已收盘 bar 的 `close[i]`，IC-CISD 用未收盘 bar 的 `close[0]`（= 最新报价）。对齐他的指标条目 *"Automatically plots CISD **before candle closure**"*（"Early Trend Shift"）。**它是纯渲染**：不置 `cisdHighFired`、不派生 OB、不建立 protected swing —— 一切状态字段保持不动，收盘那一刻由既有的正式 CISD 路径照常触发。预览只活在当前未收盘 bar 内：收盘时若真触发则由正式 `CISD` 线接替，否则预览消失且**不产生任何 CISD 事件行**。他本人承认提前确认会出假信号（*"CISD can give earlier entries but sometimes too early, leading to false signals"*），把未收盘的猜测写进趋势状态机正是那个错，故本实现刻意不写。
- **C2 / C3 收盘确认（valid closure）**：他的编号是 C1 = swing 点**之前**、**C2 = swing 高/低本身**、C3 = C2 之后。**反转收盘** = 扫破前根高/低（影线越出）但收回前根区间内；**延续收盘** = 扫破并收在其外。他明说 *"A Candle 2 closure is **always** a reversal closure."* **C3 收盘**出现在 C2 未能给出确认时：*"candle 3 **closes over the body of candle 2 and engulfs it**"* 且 *"without sweeping the **candle 2** high or low"*。本实现据此产出三种标注 —— `C2`（反转确认）、`C3`（迟到一根）、`C2-CONT`（延续收盘，**不是**有效反转确认）。
  > ⚠️ **本项不参与任何判定**（阶段 18a），且这一步是**终态**。他另有一条**门禁级**规则：*"A swing is only valid when it has both: a point of interest and a valid closure (candle 2 or candle 3). **If either is missing, the swing point is ignored.**"* —— **用户已裁定不做**（2026-09-24，「无需门禁」）：实现它会改变**全部下游结构**（protected swing / BOS·MSS 归属 / 结构段划分），而 POI 的机械判据他文章里只有一张种类清单、必须由实现方发明（同一套说法下存活率 31%~100%）。故 closure **永久**只标注、不影响结构，CSV 头部标 `gate=NONE(18a,no state impact;18b+POI-declined-by-user)`。
  > ⚠️ **三处自定口径**（写进 CSV 头部 `# closure` 行）：① C3 取**实体**版（他有"closes over the body"两处 vs "closes beyond the opening price **and range**"一处，后者未实现）；② "engulfs it" 的字面（C3 实体完全包住 C2 实体）**未**作为必要条件；③ C1/C3 取**物理相邻** K 线，非"有效 bar 序列"。
  > ⚠️ **C3 的条件不是"C2 未扫破前根"** —— 按严格三点分形，swing low 恒有 `low[b] < low[b+1]`，那样写该分支会是死代码。取的是他更明确的那句 *"without sweeping the **candle 2** high or low"*（相对 C3 而言的"前一根"就是 C2）。判断该功能是否真在跑，**要看子类型分布**而非条数。
  > **C4 均衡位**（`v1.50-s22` 补）：他 *"mark the full range of candle 3; bullish expect candle 4 to **wick into the upper half of candle 3**"*。本实现判 C4 是否**守住** C3 的 50%：看涨 `low[C4] >= EQ(C3)`、看跌 `high[C4] <= EQ(C3)`。标签后缀 **`C3+`**（守住）/ **`C3-`**（已破）/ 无后缀（C4 未出现，待定）；CSV `state` 列为 `C3+C4-OK` / `C3-C4-BROKE` / `C3`。⚠️ 他只说"期望"，**没说破掉之后算不算失效** → 本项**只记录，不删不弱化**。
  > **怎么读多空**（`v1.50-s36` 起显式化）：标签文字带方向记号 —— **`▲` = 多头**（C2 是 swing low，收回前低之上）、**`▼` = 空头**（镜像），如 `C2▲` / `C2-CONT▼` / `C3+▲`。此前方向只能靠**位置**（低点下方=多 / 高点上方=空）与**颜色**推断，而颜色表达的是"顺/逆当前偏置"（逆向压暗）、**不是**多空，故标签本身判断不出方向。
  > ⚠️ **CSV 的 `dir` 列对 CLOSURE 行 ≠ 信号方向**：它是"**这个 swing 是哪一侧**"（low → `UP`，high → `DOWN`）。对 `C2-REV` / `C3` 它与反转方向一致；但 **`C2-CONT` 是延续收盘** —— 例如 `dir=UP` 那条实际是"扫破前低并继续收在下方"（**看跌延续**）。⇒ 要筛"干净的多头集合"，必须同时用 `state` 列排掉 `C2-CONT`（用户 2026-09-24 裁定：**保持 `dir` 语义不变**、以文档写明，不翻转以免历史归档不可比）。
- **HTF 蜡烛（Higher Timeframe Candles）**：在他的入场周期上直接看到高周期蜡烛（实体 + 上下影线），对齐落地页条目 *"View HTF candles on your entry timeframe"*；根数默认 4（他的指标默认值）。**周期默认自动推导**（`InpHtfTFMode = HTF_TF_AUTO`，`v1.50-s54`）：按"**≥4 倍**"原则在标准阶梯（M1/M5/M15/M30/H1/H4/D1/W1/MN1）上取第一个 ≥4× 图表周期的档位 —— 该规则**逐行复现**了用户给定的映射（1M→5M、5M→30M、30M→4H），故不写死映射表；要固定周期就切到 `HTF_TF_MANUAL` 并用 `InpCandleTF`。**默认位置 = 主图右侧未来留白区**（`InpHtfPlacement = HTF_PLACE_RIGHT`，`v1.50-s33`）：既不像叠加那样压住真实 K 线，也不像副图那样丢掉价格刻度对齐（代价是蜡烛的时间坐标落在 `time[0]` 之后）。实体"透明度"用 `PdFill` 按**图表实际底色**混色 —— 因为 `OBJ_RECTANGLE` 没有透明度（v1.49-s14 已编译证实）。**性能**：正在形成的那根每 tick 都在变，故它**不进 `needDraw` 指纹**（进去会每 tick 触发整段调和），而由快路径单独刷新（缓存比对 + `0.1×ATR` 死区，未变即零对象调用）；指纹含"最新 HTF bar 开盘时间 + **已收盘**蜡烛的 OHLC 签名 + **留白槽宽**（缩放会改它 → 不加就会等下一根 bar 才重排）"。
- **Auto Targets / 投影目标**：两半，**证据强度不同，必须分开看**。
  **(a) 流动性目标**——他列为 *"separate, and primary"*：*"Bullish → previous **untouched** highs; bearish → previous **untouched** lows … **A level already taken out is invalid.**"* 本实现取偏置方向上、现价之外、**未被取走**的摆动位，按价格距离取最近 N 个，并追加 PDH/PDL。
  **(b) 操纵腿投影**——锚定规则逐字可溯：*"Anchor a Fibonacci tool to the **manipulation leg** — the swing that sweeps liquidity and occurs **immediately before the CISD**."* 本实现取 A = 最近一条**与偏置同向**的 CISD 事件的极值 bar（= 造势序列极值），B = A 之后的反向极值，水平为 `B + (B−A)×k`。
  > ⚠️⚠️ **符号约定是「用户可选项」，不是本实现替他做的裁决**（`v1.50-s21` 起）。他的水平表是 `1, 0, −1, −2, −2.5, −4`（**负向**扩展）；但按 TradingView 常规，负向是从**起点 A 之外**延伸，看涨时 A = 被扫破的低点 → −1/−2 会落在 **A 之下**，那是**止损方向**而不是目标。故水平表由 `InpFibLegs` 输入：**默认** `0,1,2,2.5,4`（交易方向上的目标），**填他的原表即可逐字复现**。语义固定为 `价位 = B + 腿长 × k`（k>0 = 沿交易方向外推），所以两种读法都能表达。CSV 头部记的是**实际输入值**（`legs=…`，`v1.50-s22` 起不再写死），并标 `DIRECTION=USER-CONFIGURABLE`。⚠️ 仍**不得**声称本实现的默认值与他的水平表一致。
  > ⚠️ 水平表本身的置信度也只有**中介**（调研自述"第二篇原文的水平列表被截断"）—— 这是四个功能里**最弱的一环**。
  > ⚠️ (a) 与 ERL **共用** `IsLiquidityTaken()` 判定"是否已被取走"（同一概念一份实现）；(`g_curBias == 0` 时两者都不画，前提是 *"Start with the higher timeframe bias."*）。
  > ⚠️ **`T1` 与 `ERL` 是同一个节点**（两处筛选条件完全相同 ⇒ `tgtBar[0] == g_erlBar` 恒成立），且两条线起止时间、价位、锚点、**颜色**都一样 ⇒ 两个标签会精确叠印成一团（实机截图确认）。`v1.50-s44` 起：**同位时标签合并成 `ERL/T1`**，目标侧那条不再单独画；用**节点 bar** 判定同位（不用价格，价格可能被不同节点偶然撞上）。`v1.50-s66` 起 ERL / IRL **开关已拆分**：`InpShowERL`（默认 `false`）只关 ERL，`InpShowIRL`（默认 `true`）不受影响；旧输入项 `InpShowERLIRL` 不再被识别。`InpShowERL=false` 时 ERL 不画，此时 `T1` 正常保留。

- **SWEEP（流动性扫荡）**：intermediate 位被**影线**越过、但**收盘收回位内**；纯上下文标注，不参与判定。
  > ⚠️ `v1.50-s57` 收紧两条（用户 2026-09-30：「我框出来的这里都实体突破了，不算 sweep 了吧」）：
  > ① **实体两端都不得越界** —— 旧判据只看收盘，于是"开在位外、收在位内"的跨位大阴/大阳也被记成 sweep，那正是"实体突破了"；
  > ② **位被收盘接受后停止扫描** —— 一旦出现 close 越界，该位就不再是"未被扫的流动性"，之后再刺破并收回属于**破位后的回抽**，不是 sweep。
  > 两条都只**减少**事件（严格度单调收紧），且"先扫后破"的那一次仍会被记下来。
  > 核验：`Indictor/kernel_sim_sweep.ps1`（四例对照，见 plan §72.3）。

- **摆动分级（tier）**：`short` / `intermediate`；intermediate = 比左右**最近的同类型**摆动点都更极端。
- **HTF 偏置门禁**：取上一根已收盘高周期 K 线，与它前一根的高低比较决定 `bull`/`bear`；事件与偏置**逆向**即弱化。
- **dealing range / 均衡位（EQ）**：relevant high/low 连成的区间；其 50% 为 EQ，上方是 premium、下方是 discount —— 他序列第三步"回撤到 premium/discount 区"的落点。**EQ 那条线默认不画**（`InpShowEQ`，默认 `false`）：它与 PREMIUM/DISCOUNT 分区标签说的是同一件事，只是多一条线。⚠️ `v1.50-s63` 起**整个 dealing range 默认不画**（`InpDrawDealingRange=false`：区间矩形 + PREMIUM/DISCOUNT 文字）；relevant high/low 的两条水平线由 `InpDrawRelevance` 单独控制，仍默认显示。
- **FVG（Fair Value Gap）**：三根 K 线形态 `low[第1根] > high[第3根]`（看涨）或 `high[第1根] < low[第3根]`（看跌）；区间边界取**整根 K 线的高低（含影线）**，中点即 **CE**（*"As long as price does not close beyond the consequent encroachment, the fair value gap is generally considered respected."*）。
  > ⚠️ **`v1.50-s46` 口径变更（用户实机裁定）**：三根 K 现在是**物理相邻**（`c1 = c3+2`）。原实现取**有效 bar 序列**（内包 K 已剔除），实测 88 条 FVG 里 **24 条不是物理相邻**（`d=c3−c1` 为 −3…−7，即"由 4~6 根 K 组成、中间隔着被忽略的内包 K"）—— 用户框出其中一条（`d=−3`）指出"这个不是 FVG 吧"，判断正确。改口径后那 24 条会消失，同时会新增一批 tick 级缺口，故**同时**加了最小高度门槛 `InpFvgMinWidthATR`（默认 `0.10`×ATR；实测原口径下有 12 条宽度 <0.3，最窄 **0.04**）。
  > ⚠️ 该变更会改变 FVG 事件集 ⇒ **`v1.50-s45` 及更早的 CSV 归档与之后的 FVG 行不可直接对比**（头部 `# pdarray` 行已注明 `physical:c3,c3+1,c3+2` 与 `minWidth=`）。
- **OB（Order Block）**：造势那一串**同向收盘 K 线**；价格**收盘穿回该串**之后，该区域成为验证过的 OB（*"Bodies matter more than wicks."*），关键价位 = 该串**最旧一根的开盘价**。该验证动作与本指标的 CISD 触发是**同一个动作**，故 OB 直接由 CISD 运行态派生。
  > **画法（`v1.50-s48` 起）= 与他一致的一条水平线段**：画在**关键价位**上（= `open[runOldest]` = CISD 位），起于造势序列最旧一根、向右延伸。他图上的 OB 就是这样一条线（配图另有 "Invalidation" 指向区间另一端），**不是框**。实体并集区间（`zoneLo`/`zoneHi`）**仍保留在数据与 CSV**，只是不再绘制 —— 那份信息正是 "Invalidation" 的参照。
  > ⚠️ 对象名前缀由 `OB_` 改为 `OBLine_`（对象类型从矩形变为线；旧矩形因未注册而被回收段自动清除）。**标签放在线段右端**（`v1.50-s49`）：看跌 OB 在线上方、看涨在线下方，用右缘锚点（`ANCHOR_RIGHT_*`）保证文字不越出线段 —— 与 CISD 标签（在被破 bar 处、另一侧 0.15×ATR）分离。
- **PD Array 不参与判定**：FVG 与 OB 属执行层参照区（他的限定 *"A Point of Interest Doesn't Mean an Entry."*），实现为纯可视化层，与 SWEEP / dealing range 同级。
  > ⚠️ **区域右端的降噪**（`v1.50-s28` 引入开关 → `s29` 改 `RETEST` → **`s31` 改 `FIXED`**）：FVG/OB 的矩形**原行为是画到当前 bar**（符合他配图里向右延伸到现价区域的画法），代价是失效的位也一路铺到底。
  > 实测覆盖率（同一批 9 个 PD 矩形 / 200 根窗口）：**NOW 44.2%** ・ FIXED6 6.8% ・ **FIXED12 8.9%（现默认）** ・ FIXED24 11.8% ・ FIXED60 20.5%；`RETEST ∈ [8.9%, 44.2%]`。
  > **现默认 `PD_END_FIXED` + `InpPDRightBars = 12`**：每个区域从**成立那根**起只向右延伸 12 根（M5 上 60 分钟）。选它而非 `RETEST` 的理由：**宽度是确定值**（`N + (anchor−valid)` 根），而 `RETEST` 依赖真实 bar 数据、且实测常被最小宽度下限接管（下限恰为 FIXED12）。
  > ⚠️ 这**偏离他的画法**，是用户知情下的取舍。想看回原样就设 `InpPDEnd = PD_END_NOW`。
  > 降噪是否真生效，看日志 `STRUCT_PDW … widthBars min/avg/max`（**唯一能量化它的钩子**）。FIXED 模式下 `min` 应 ≥ 12，**除非**该区域成立于最近 12 根之内（右端被钳在最新 bar，画不到未来）。
- **IRL / ERL（Internal / External Liquidity）**：*"Internal liquidity is a fair value gap."* / *"External liquidity is a swing high or swing low."* / *"**Internal liquidity provides the point of interest. External liquidity provides the target.**"* —— 偏置方向上的 FVG 标为 `IRL`（回撤 POI），偏置方向上最近的、**尚未被取走**的摆动位标为 `ERL`（目标）。⚠️ `v1.50-s66` 起 `ERL` 默认不画（`InpShowERL=false`），`IRL` 仍默认画（`InpShowIRL=true`）—— 两者原共用一个开关，已拆分。前提是 *"Start with the higher timeframe bias."*，**无 HTF 偏置时不画**。
- **PDH / PDL（前日高/低）**：`InpPDPeriod`（默认 `PERIOD_D1`）上**最近一根已收盘** K 线的最高/最低点。他的依据：*"Price takes out **yesterday's high** but closes back inside the range"*、*"Failure to displace above **previous day high** suggests a bearish bias toward **previous day low**."* → 在他的体系里这是**流动性目标**（draw on liquidity）。⚠️ 取数按**日期**判定（取第一根 open 日期严格早于当前服务器日期的 K 线），**不写死 `shift=1`** —— 服务器刚换日、当日 K 线尚未生成时 `shift=0` 才是最近一根已收盘。**前日 50%**（`v1.50-s65`，`InpShowPD50` 默认开）：前日**区间**的中点 `(PDH+PDL)/2`，虚线 + 右端 `PD50` 文字，锚点与 PDH/PDL 同款（贴最新 bar）。⚠️ 他**未明列**此项 —— 这是**我们的读法**（沿用本文件 C3 EQ 的"区间 50%"口径），不是他的口径。

> ⚠️ **两处需要如实知道的边界**：
> 1. **BOS 没有 TTrades 的一手定义** —— 他全站 110 篇文章中 `break of structure` 仅出现 1 次且为并列提及，两张结构配图也只标 HH/HL 序列、无任何 BOS 标记。此处的"顺势破位"是行业通行读法。
> 2. **`InpMinSeparationATR` 与三条位移阈值是本指标自定的近似** —— 他的文字只有定性描述（*"too close to a prior high or low"*、*"strong price movement with momentum"*），配图也只给"小 vs 大"的定性对照，没有数值。全部阈值都写进了 CSV 头部以便归档自描述。
>
> ⚠️ **PD Array 另有四处自定口径**（同样写进 CSV 头部）：
> ① FVG 取**有效 bar 序列**上的三根（内包 K 线已剔除），**非物理相邻三根** —— 实测 **18/79（23%）** 的 c1–c3 相隔 3–23 根，对这些缺口 **CE 不是他的 CE**。这是**语义改动**（改了"哪三根构成形态"），不只是加过滤器；
> ② OB 区间取整串实体的**并集**（原文只说 "the series of up close candles"，配图只画了一条线）；
> ③ FVG 失效以「**收盘穿越 CE**」为准，他给的是「收盘穿 CE」**或**「完全穿越」两条并列条件；
> ④ **`InpFvgHideFilled` 默认 `true`** —— 实测 **67/79（85%）** 的 FVG 被默认隐藏，叠加 `InpMaxEvents=6` 后**出厂最多只显示检出量的约 7.6%**，且他无此依据（`FVG-Inversion.png` 说明失效缺口仍可作反向位）。
>
> ⚠️ **还有两条他的明文要求尚未实现**：OB 的**前置流动性扫荡**（*"Order blocks only matter after liquidity is taken."*）与 **IOFED / IFVG 反转位**。前者需**架构改动**（扫荡在后验层，OB 在主循环内创建）。
>
> ⚠️ **v1.50-s16 新增的两个元素都是纯渲染，不产生任何事件行**：IC-CISD（预览）与 HTF 蜡烛叠加。二者的验收判据因此是"**事件 CSV 的全部数据行逐字不变**，只有头部 `build=` 与新增的 `# render ...` 行不同"。据此可一眼分辨"是渲染改动"还是"漏进了判定层"。
>
> ⚠️ **本轮新增功能的取证分级必须分开读**（依据 `docs/research/2026-09-23-TTFM-rules-report.md`）：IC-CISD 有**一手专文**支撑（IC-CISD 篇），HTF 蜡烛只有**落地页功能条目 + 默认值**支撑（无机械规则可考，故本实现的"实体宽度百分比 / 填充强度"是自定口径）。第二批功能里，**目标投影的锚定规则（操纵腿）有专文**，但**其水平表 `1, 0, −1, −2, −2.5, −4` 属调研方推断**（第二篇原文的水平列表被截断），落地时必须标为中介置信度，不得当逐字口径引用。

#### 输入参数

按属性对话框的分组顺序：

| 分组 | 参数 | 默认值 | 说明 |
|---|---|---|---|
| 结构模式 | `InpMode` | `MODE_SHORT_TERM` | `FractalSwing` / `ShortTerm` / `StrictICT` |
| 结构标记设置 | `InpWindow` | `200` | 绘制窗口（根 K 线） |
| | `InpShowMSS` / `InpShowBOS` | `true` | 是否显示对应标注 |
| 有效回撤过滤 | `InpEnableRetraceFilter` | `true` | 启用有效回撤过滤 |
| | `InpMinRetracePoints` | `100` | 最小回撤点数 |
| | `InpMinRetraceATR` | `0.5` | 最小回撤 ATR 倍数（**0 = 关闭该条**） |
| | `InpMinRetraceRatio` | `0.236` | 最小回撤占前段幅度比例 |
| | `InpATRPeriod` | `14` | ATR 周期 |
| | `InpMinSwingAmplitude` | `0` | 最小 swing 幅度（点数，0=关闭） |
| | `InpMinBarsBetweenSwings` | `2` | 相邻 swing 最小间隔（根） |
| | `InpMinSeparationATR` | `0.5` | **failure swing 剔除门槛（×ATR，0=关闭）** |
| 内包/外包 | `InpUseInsideBarBox` | `true` | 记录内包盒区间 |
| | `InpDrawInsideBox` | `true` | 绘制内包盒矩形 |
| | `InpUseOutsideBarLogic` | `true` | 外包 K 线单独处理 |
| ~~主/内部结构~~ | — | — | **整组已删除（v1.49-s11）**：`InpUseMainFilter` / `InpMainFilterATR` / `InpMainFilterRatio` 的"腿长门槛"**无一手依据**（他的 protected swing 由 CISD 定义）；`InpDrawSubStructure` / `InpColorSubStructure` 从未被引用，且"主/内部结构"不是他的概念 |
| 突破确认 | `InpBreakConfirm` | **`BREAK_WICK`** | 破位判据三档：**`BREAK_WICK` 影线触及（默认）** / `BREAK_CLOSE` 收盘越过（= TTrades 字面口径）/ `BREAK_BODY` 实体完全越过。严格度为全序 BODY ⊂ CLOSE ⊂ WICK。⚠️ **只管引擎（MSS/BOS/CISD 系列）**；节点级见下两行 |
| | `InpNodeBreakConfirm` | **`BREAK_CLOSE`** | **仅节点级**（CHoCH/节点级 BOS 层）的破位口径（`v1.50-s55`）。默认比引擎的 `BREAK_WICK` **更严**，这是**有意的不一致**：引擎要接 sweeping，本层只判"结构是否真的被破" ⇒ M1 上"刺破即回"不再翻转方向 |
| | `InpNodeFlipMode` | **`NODEFLIP_RETRACE`** | 节点级「改性格(CHoCH)」判据（`v1.50-s70`）：`RETRACE`（默认，回吐整段腿的 N% 才算）/ `LEG`（收盘越过腿起点）/ `EXTREME`（被破节点是新同侧极值，= s55）/ `ANY`（任何逆势破位都翻，= s45–s54）。**翻转 ⇒ CHoCH；不翻转 ⇒ BOS** |
| | `InpNodeFlipRetracePct` | `50.0` | `NODEFLIP_RETRACE` 的门槛：回吐**整段腿**的百分之多少才算改性格（50 = 贴现区 EQ）。调低 → CHoCH 出现更早、更频繁 |
| HTF relevance | `InpHTFPeriod` | `PERIOD_D1` | relevance 回看的高周期（含当前共 3 根） |
| | `InpDrawRelevance` / `InpColorRelevance` | `true` / 浅蓝 | relevant high/low 水平线 |
| HTF 蜡烛 | `InpShowHTFCandles` | `true` | 显示高周期蜡烛（实体矩形 + 上下影线） |
| | `InpHtfTFMode` | **`HTF_TF_AUTO`** | 蜡烛周期模式（`v1.50-s54`）：**自动** = 从图表周期按"**≥4 倍**"原则推导（1M→5M、5M→30M、30M→4H；表外同理，如 15M→1H、1H→4H、4H→D1）；**手动** = 用下一行的 `InpCandleTF` |
| | `InpCandleTF` | `PERIOD_H4` | **仅手动模式**使用的叠加周期（**必须 ≥ 图表周期**，否则 `OnInit` 拒绝加载并打印原因；`v1.50-s53`）。自动模式下本项被忽略 |
| | `InpCandleCount` | `4` | 叠加根数（**他的指标默认 4**；允许 0..50 —— 每根 3 个对象，是唯一随输入线性放大对象数的元素） |
| | `InpCandleWidthPct` | `70` | 实体宽度占时间跨度的百分比 |
| | `InpHtfBodyFill` | `25` | 实体填充强度 %（按图表底色混色；0=空心框；允许 0..100）。⚠️ `v1.50-s32` 前**这个数值是假的**（`PdFill` 固定读 `InpPDFillPercent`，本项只当开关）；现已修，`0` 时轮廓/影线会变成**原色**而非淡色 |
| | `InpHtfShift` | `0` | 整体左移 N 根高周期 K 线（他的指标里的 **Offset**；不允许为负） |
| | `InpHtfTimeLabels` | `true` | 每根下方标出开盘时间（他的指标里的 **time labels**） |
| | `InpHtfPlacement` | **`HTF_PLACE_RIGHT`** | 蜡烛画在哪：`HTF_PLACE_RIGHT` **主图右侧未来留白区（现默认）** / `HTF_PLACE_OVERLAY` 叠加在真实时间位置（= 他的画法，会与主图 K 线重叠）。⚠️ 右侧模式会**自动打开 Chart Shift 并把 shift 提到 25%**（否则留白宽度为 0、蜡烛全在屏幕外），**卸载时还原原值**；槽宽由**像素实测**得出（`STRUCT_HTFPOS` 日志为证）；缩放由 `CHARTEVENT_CHART_CHANGE` 当帧重排；留白区内**左→右 = 由旧到新**（`v1.50-s34` 修正，见计划 §48）。⚠️ 代价：蜡烛的时间坐标落在 `time[0]` **之后**（未来时间），这是"不压 K 线"的必然代价 |
| | `InpColorHtfUp` / `InpColorHtfDn` | 涨绿 / 跌红 | 高周期阳线 / 阴线颜色 |
| Dealing Range | `InpDrawDealingRange` | `false` | 绘制区间矩形 + PREMIUM/DISCOUNT 分区。⚠️ `v1.50-s63` 起**默认关闭**（图上不画矩形与分区文字），面板勾选即恢复。⚠️ 它**只管** RANGE 矩形与两个分区标签；`InpDrawRelevance`（RELH/RELL 线）是独立开关、仍为 `true` |
| | `InpShowEQ` | `false` | 均衡位 EQ（区间 50%）—— **默认不显示**；与分区标签表达同一件事，多一条线只是噪音 |
| | `InpColorRange` / `InpColorEQ` | 浅蓝 / 黄 | 区间边框与分区标签 / 均衡位颜色 |
| 位移判据 | `InpMinDisplaceBodyATR` | `1.0` | 破位 K 实体 ≥ 该值 ×ATR |
| | ~~`InpMinDisplacePenATR`~~ | — | **已删除（v1.49-s12c/d）**：MSS 与 CISD 都不再用"收盘穿越深度"判弱；CISD 改用下一条。`pen` 仍写入 CSV 供对照 |
| | `InpDisplaceMaxBars` | `3` | 首次影线穿越后 N 根内确认（0=不限） |
| | `InpColorWeakBreak` | 灰 | 弱化线颜色 |
| CISD | `InpShowCISD` | `true` | 显示 CISD |
| | `InpCisdFvgLookahead` | `5` | CISD 需「触发 bar 起 N 根内出现**同向** FVG」（0=关闭）；替代原②深度判据 |
| | `InpColorCISD` / `InpColorCISDWeak` | 紫 / 暗紫 | 标注与弱位移颜色 |
| Early CISD | `InpShowEarlyCISD` | `true` | 显示 **IC-CISD 预览**（收盘前的临时 CISD，对齐他的 "Early Trend Shift"） |
| | `InpColorEarlyCISD` | 亮紫 | IC-CISD 颜色（与收盘 CISD 的紫区分） |
| | `InpIcLatePercent` | `60` | IC-CISD 判"迟"的高周期 K 线时间比例 %（0=关闭标注）。**阈值他未给数值 → 自定近似** |
| C2 / C3 收盘 | `InpShowClosures` | `true` | 标注 C2 / C3 收盘确认（他的 "valid closure"） |
| | `InpColorC2` / `InpColorC3` | 亮绿 / 琥珀 | C2 收盘（反转确认）/ C3 收盘（迟到一根）颜色 |
| | `InpShowC3Eq` | `true` | 绘制 C3 区间的 50% 均衡位（他：看涨预期 C4 刺入 C3 上半） |
| Auto Targets | `InpShowAutoTargets` | `false` | 显示流动性目标（偏置方向上未取走的摆动位）。⚠️ `v1.50-s61` 起**默认关闭**（图上不画 `T1`/`T2`/`T3`），面板勾选即恢复 |
| | `InpTargetCount` | `3` | 显示最近 N 个（**允许 0..4**，越界在 `OnInit` 被拒绝） |
| | `InpColorTarget` | 玫红 | 目标位颜色（与 ERL 同族） |
| 投影目标 | `InpShowFibTargets` | `false` | 显示操纵腿投影目标。⚠️ `v1.50-s61` 起**默认关闭**（图上不画 `1.0x`/`2.0x` 等投影线），面板勾选即恢复 |
| | `InpColorFib` | 橙 | 投影位颜色 |
| | `InpFibLegs` | `0,1,2,2.5,4` | **操纵腿倍数表**（逗号分隔，最多 6 条）。语义 `价位 = B + 腿长 × k`，故 **k>0 = 沿交易方向外推**。想逐字复现他的原表就填 `1,0,-1,-2,-2.5,-4`（⚠️ 符号约定与他不同，那 3 条会落在**起点 A 之外**＝止损方向） |
| SWEEP | `InpShowSweep` / `InpColorSweep` | `true` / 橙 | 扫荡标注。判据见上文"SWEEP"条（`v1.50-s57` 起：**只有影线越界**，且**位被收盘接受后不再记**） |
| PD Array | `InpShowFVG` / `InpColorFVG` | `true` / 青绿 | FVG 矩形 + CE 点线 |
| | `InpFvgHideFilled` | `true` | 已被完全回补的 FVG 不再绘制 |
| | `InpFvgMinWidthATR` | `0.10` | FVG **最小高度**（×ATR；`0`=不限）。`v1.50-s46` 随"物理相邻"口径一起引入 —— 只拒绝零宽挡不住 tick 级假缺口 |
| | `InpPDFillPercent` | `30` | PD Array 区域填充强度 %（**按图表实际底色混色**，0 = 只画空心框）。白底上 30% ≈ FVG `C'179,239,233'` / OB `C'209,221,255'` |
| | `InpShowOB` | `true` | 显示 OB（造势序列关键价位上的一条水平线段） |
| | `InpColorOBUp` / `InpColorOBDn` | 绿 / 红 | **做多 / 做空 OB 分色**（`v1.50-s51`）：做多 = 被扫低点派生（需求区）→ 绿；做空 = 被扫高点派生（供给区）→ 红。值与 HTF 蜡烛的多空色相同 |
| | `InpPDEnd` | **`PD_END_FIXED`** | **区域右端策略**：`固定 N 根`（**现默认**，用户裁定）/ `首次回踩即停` / `到当前 bar`（= 他的画法） |
| | `InpPDRightBars` | `12` | `固定 N 根` 模式 = **向右延伸根数**（12 根 = M5 上 60 分钟）；`首次回踩` 模式 = 最小宽度保证 |
| | `InpPDRightBars` | `12` | `固定 N 根` 模式 = 延伸根数；**`首次回踩` 模式 = 最小宽度保证**（防止矩形退化成看不见的细缝） |
| IRL | `InpShowIRL` | `true` | 显示 Internal（FVG = POI）流动性边线 + `IRL` 标签 |
| ERL | `InpShowERL` | `false` | 显示 External（摆动位 = 目标）：玫红点线 + `ERL` 标签。⚠️ `v1.50-s66` 起**默认关闭**；原与 IRL 共用 `InpShowERLIRL`，现已拆分（旧 `.set` / 模板里那一项不再被识别）|
| | `InpColorERL` / `InpColorIRL` | 玫红 / 青绿 | ERL 目标位 / IRL 回撤区颜色。⚠️ ERL 与 Target **同色**（`233,30,99`）是刻意的"同族"标记，也是同位时必须合并标签的原因之一 |
| 前日高/低 | `InpShowPDHL` | `true` | 标记前日（最近一根**已收盘** K 线）的最高/最低点 |
| | `InpPDPeriod` | `PERIOD_D1` | 周期（用户指定 1D；可改周/月） |
| | `InpColorPDHL` | 深蓝灰 `#455A64` | PDH/PDL 颜色（`v1.50-s62` 起；原近白 `#E0E0E0` 在白底图上不可见） |
| | `InpShowPD50` | `true` | 前日 **50%**（前日 D1 的**区间**中点 `(PDH+PDL)/2`）。⚠️ 口径为**本实现自定**：他未明列此项，不得声称是他的口径。独立于 `InpShowPDHL` |
| | `InpColorPD50` | 蓝灰 `#78909C` | 前日 50% 颜色（与 PDH/PDL 同族淡一档；虚线以示同族不同档）|
| HTF 偏置 | `InpBiasTF` | `PERIOD_D1` | 偏置周期 |
| | `InpBiasLookback` | `20` | 偏置回溯上限（根） |
| | `InpShowBias` / `InpColorBias` | `true` / 青 | 偏置标签 |
| BOS/MSS 绘制 | `InpNeedRetestToShow` | `false` | 需后续回踩确认才显示 |
| | `InpDrawLiveLeg` | `true` | 结构线延伸至未确认端点 |
| | `InpLineEnd` / `InpLineEndBars` | `LINE_END_HIT_ZIGZAG` / `20` | 虚线终点模式 |
| | `InpMaxEvents` | `6` | 每类各只显示最近 N 条（0=全部）。⚠️ **这是硬截断**，不是"标签密度"旋钮：第 N+1 旧的那条**连线都不会画** |
| | `InpShowChoch` / `InpColorChoch` | `true` / 紫 | **CHoCH 层**（`v1.50-s40`，**借用 ICT 术语**，非他的概念）：逆内部趋势破最近结构节点即标，不要求 protected swing。⚠️ `s55` 起破位口径独立（`InpNodeBreakConfirm`）；`s70` 起**标签与翻转绑定**（`InpNodeFlipMode`）—— 只有真改性格才画 `CHoCH`，其余画 `BOS`。见上文"CHoCH"条 |
| | `InpHideWeakBreaks` | `true` | 弱化的 BOS/MSS **完全不画**（`v1.50-s42`，用户要求）：`weak` 或逆 HTF 偏置 ⇒ 连灰线也不画。设 `false` 退回"灰线 + 无标签" |
| | `InpMaxSeg` | `0` | 结构线最多段数（0=不限） |
| 性能 | `InpAnalysisWindow` | `500` | 分析窗口（0=全量） |
| | `InpReuseResultOnTick` | `true` | 同 bar tick 复用分析结果 |
| 颜色 | `InpColorStructure` / `InpColorMSS` / `InpColorBOS` / `InpColorBox` | 见上表 | 基础配色 |
| 调试验收 | `InpDebugShowRef` | `false` | 专家日志：方向自检 + GEO/VIEW 坐标诊断 + 每条事件明细 |
| | `InpDumpEvents` | `false` | 导出全部事件到 `MQL5\Files\Structure_events_<品种>_<周期>.csv` |
| | `InpHotkeys` | `true` | 热键诊断（`v1.50-s38`）：**Shift+S** 导出图表 PNG、**Shift+D** 导出事件 CSV，见下"图表快照" |

#### 事件导出与自描述（离线 diff）

打开 `InpDumpEvents` 后，每次全量重算会把全部事件写成 CSV（**覆盖**同名文件，便于"改前导出一份 → 改代码 → 再导出一份 → 逐行 diff"）。文件头部自带：

```
# version=1.49 build=v1.49-s9 symbol=EURUSD.ct period=PERIOD_H1 rates=16855
# window=200 analysisWindow=500 mode=MODE_SHORT_TERM breakConfirm=BREAK_WICK maxEvents=6 maxSeg=0 nodes=49 mss=15 bos=9
# filters sepATR=0.50 retracePoints=100 retraceATR=0.500 retraceRatio=0.236 minBars=2 minAmp=0 mainATR=1.00 mainRatio=0.382 mainFilter=true retraceFilter=true atrPeriod=14
# displacement dispBody=1.00 dispBars=3 cisdFvgLookahead=5 pen=informational-only
# sweep levels=intermediate(tier-1) firstOnly=true
# bias tf=PERIOD_D1 lookback=20
# pdarray fvg=3candle(wick-to-wick,basis=validbars) ce=mid ob=bodyrun(from CISD run) obLevel=runOldestOpen
seq,type,dir,breakBar,refBar,refPrice,breakTime,refTime,displacement,tier,biasState,zoneLo,zoneHi,fillPct,state
```

`build=` 是**构建指纹**（`#define BUILD_TAG`，每次改动递增），同时出现在专家日志的 INIT 行 —— 用来确认 MT5 实际加载的是哪一版编译产物。`displacement` 列给出位移度量与 `OK`/`WEAK`（覆盖 **MSS / CISD / OB** 三类 —— 他用来定义 OB 有效性的正是 *"Closure and displacement"*，故 OB 必须与 CISD 同列同格式）；`tier` 是摆动分级（**FVG / OB 行为 `n/a`** —— 它们的锚点按构造不是结构点，读作分级无意义）；`biasState` 是 HTF 偏置。`zoneLo` / `zoneHi` / `fillPct` / `state` 四列仅 FVG 与 OB 有值（FVG 的 `state` = `OPEN` / `CE-BROKEN` / `FILLED`，OB 的 `state` = `VALID` / `WEAK`），其余类型留空。

#### 图表快照与热键取证（`InpHotkeys`，`v1.50-s37` / `s38`）

**图表聚焦时：`Shift+S` → 当前图表导成 PNG；`Shift+D` → 立即导出一份事件 CSV。**

- **存在的理由**：AI 协作者**看不到终端画面**。以往判断"画成什么样"只能靠对象转储与计数（那属于**数据层**证据），
  而"观感好不好""字形显示成三角还是方框"属于**像素层** —— 没有图就只能猜。
  有了这个快照，"改完自己复验一遍"才成为可能，不必每次都要人肉截图。
- **`Shift+D`（事件 CSV）为什么也要热键**：回答"某处的事件到底有没有产生／为什么没被标注"必须看**事件级**数据
  （`type/dir/refBar/refPrice/displacement(WEAK|OK)/biasState`），而那平时只在 `InpDumpEvents=true` 时才有。
  挂到热键上 = 把取证成本从"改输入 → 重挂 → 等一次全量帧"降到"按一个键"。
  ⚠️ 热键路径**显式 force 绕过** `InpDumpEvents` 门控 —— 否则"按了没反应"又是一个不可分辨的失败。
- ⚠️ 快照**不抓屏幕**：`ChartScreenShot()` 只渲染本图表、写入终端自己的 `MQL5\Files` 沙箱 ——
  不含窗口外的任何内容，也不要求 MT5 窗口在最前。
- ⚠️ 文件名**不用** `TimeToString()`：它产出 `2026.09.24 17:55:03`，其中的 `:` 与空格在 Windows 上是非法字符，
  写盘会直接失败（而不是报错）。
- ⚠️ 未命中的按键会**回显**（每次加载最多 20 条）：`STRUCT_SNAP key=… shiftRaw=… ctrlRaw=… (未命中，仅回显)`。
  这是为了把"按键根本没送到指标"与"送到了但没被识别"分开 —— 否则两者在现象上都是"按了没反应"。
- ⚠️ 需要 Shift 修饰而不是裸字母：裸字母在 MT5 图表上有内建语义。`shiftRaw != 0` 的判法对
  "按下返回 -1 / 1" 与实测到的**位掩码 -128** 各种约定都成立，故不依赖未验证的符号约定。
  （实测日志：`STRUCT_SNAP key=16 shiftRaw=-128` = 只按 Shift 自身；`key=83/115` 才是 S/s。）

#### 技术细节

- **窗口**：主图表窗口（`indicator_chart_window`），全部使用图表对象（无缓冲区）
- **对象前缀**：`Structure_`；当前有 `Seg_`（结构段）、`MSS_`/`MSSLbl_`、`BOS_`/`BOSLbl_`、`CISD_`/`CISDLbl_`、`SWEEP_`/`SWEEPLbl_`、`FVG_`/`FVGCE_`（FVG 色带 / CE 点线；`v1.50-s50` 起不再有文字标签）、`OBLine_`/`OBLbl_`（OB 水平线 / 标签，`v1.50-s48` 由 `OB_` 改名以避开矩形→线的类型冲突）、`ERL`/`ERLLbl` + `IRL`/`IRLLbl`（外部 / 内部流动性）、`PDH`/`PDL`/`PDHLbl`/`PDLLbl` + `PD50`/`PD50Lbl`（前日高/低 + 前日 50%）、`Box_`（内包盒）、`RELH`/`RELL`（relevant 位）、`RANGE`/`EQ`/`PremLbl`/`DiscLbl`（dealing range）、`BIAS`（偏置标签）、`Live`（实时腿）；`OnDeinit` 自动清理
- **调和式同步**：每帧重建"期望对象集合"，**未注册即回收**（缺失才创建、变化才更新、过期才删除），仅在场景变化时 `ChartRedraw`
- **算法分层**：
  - 主循环（旧→新遍历分析窗口内**每一根** bar）：每根 bar 做突破检测（含内包 K 线）+ CISD 检查（CISD 触发处同时派生 OB）+ FVG 检测；有效 bar 另做 swing 确认与结构推进
  - 后验遍历（主循环之后，按此顺序）：`ClassifyNodeTiers()`（摆动分级，需右侧邻居 → 必须后验）→ `ComputeSweeps()`（扫掠位后验扫描，不参与判定故无时序约束）→ `FillEventBias(time, rates_total)`（写 HTF 偏置，无需改事件创建签名）
- **数组方向**：`OnCalculate` 入口显式 `ArraySetAsSeries(..., true)` 锁定时序（**本终端默认交给指标的数组不是时序**）；`analysisStart` 为"最近 `InpAnalysisWindow` 根"的最旧下标 = `InpAnalysisWindow - 1`
- **确认时机**：**默认影线触及即确认**（`InpBreakConfirm=BREAK_WICK`；另有 `BREAK_CLOSE` 收盘口径 = 他的字面口径、`BREAK_BODY` 实体完全越过）。swing 需相邻有效 bar 确认；CISD / SWEEP 为收盘口径。**注意**：影线触发但位移不足时，MSS 只记为弱事件（**完全不画**，见上）且**不消耗该结构位**，后续真正的突破仍能出信号。
- **性能**：`needDraw` 八项指纹（节点/窗口/盒/事件条数/裁剪起点/relevance/偏置）全部未变时整段跳过调和；`needDraw=false` 帧的对象接触数为 0
