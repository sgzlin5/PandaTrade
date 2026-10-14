# SMC_Toolbox

> 源文件：`Indictor/SMC_Toolbox.mq5` ｜ 详细口径与参数（自 README 拆分） ｜ [返回 README](../../README.md)


> `Indictor/SMC_Toolbox.mq5`

**SMC（Smart Money Concepts）工具箱** —— 模块化、可逐项开关，主图表窗口，对象前缀 `SMCToolbox_`。

> **它与 `Structure` 是两套东西，不是升级关系。** 两者的"结构"定义**不同源**：
> 前者对齐 TTrades 一手文章（MSS / CISD / protected swing），后者是 SMC 行业通行读法
> （BOS / CHoCH / OB / EQH-EQL）。合并会让两套语义互相污染，故刻意分开。
> 对象前缀必须不同 —— 两者的回收段都是"凡带本前缀却不在场景集里的一律删除"。

- 实施计划与口径决策（含**被实测推翻的假设**）→ `docs/plans/2026-09-24-SMC-toolbox.md`
- 术语通行性核实（一手来源）→ `docs/research/2026-09-24-SMC-terms-research.md`

#### 模块清单（M1~M11）

| # | 模块 | 输入开关 | 说明 |
|---|---|---|---|
| M1 | 双层枢轴检测 | `InpSwingLen` / `InpInternalLen` | 对称窗口极值，**确认延迟 = 半窗长度** |
| M2 | 市场结构 BOS / CHoCH | `InpShowStructure` / `InpShowInternal` | 两层各跑一个**独立**状态机 |
| M3 | 摆动点 HH/HL/LH/LL 标签 | `InpShowSwingLabels` | 纯渲染 |
| M4 | 订单块 OB（缓解 / 失效） | `InpShowOB` | 每个波段层结构事件派生一个 |
| M5 | FVG / IFVG | `InpShowFVG` / `InpShowIFVG` | 三根 K 线缺口 + 后验回补与反转 |
| M6 | EQH / EQL（流动性池） | `InpShowEQHL` | 同类型枢轴聚类，画成**容差带** |
| M7 | 流动性扫荡 / 诱导 | `InpShowSweep` / `InpShowIDM` | 扫荡不消耗结构位；IDM 是角色标签 |
| M8 | Premium / Discount + EQ | `InpShowPremDisc` | 端点取结构层**当前活跃**的 swing 高/低 |
| M9 | 强/弱高低点 | `InpShowStrongWeak` | ⚠️ **该术语无权威口径**，见下 |
| M10 | Killzone（亚洲/伦敦/纽约） | `InpShowKillzone` | 纽约时间表达 + **自动美国 DST 换算** |
| M11 | 多周期结构叠加 | `InpShowMTF` | 复用同一份状态机代码，**纯渲染不参与判定** |

#### 效果预览

| 元素 | 颜色 | 说明 |
|---|---|---|
| **BOS / CHoCH** | ![#26a641](https://placehold.co/12x12/26a641/26a641.png) `#26a641` / ![#f85149](https://placehold.co/12x12/f85149/f85149.png) `#f85149` | 按突破方向着色；水平点线从被突破的枢轴画到破位 bar，线正中写标签 |
| 内部层结构 | ![#8b949e](https://placehold.co/12x12/8b949e/8b949e.png) `#8b949e` | 前缀 `i-`，灰（它是上下文，不是信号） |
| 位移不足 | ![#6e6e82](https://placehold.co/12x12/6e6e82/6e6e82.png) `#6e6e82` | **只改颜色，不减信息**：线照画、CSV 照记 |
| **OB** | ![#648cff](https://placehold.co/12x12/648cff/648cff.png) `#648cff` | 区间矩形 + 均值门槛虚线（HYBRID 基准）+ `OB+`/`OB-` 标签 |
| **FVG** | ![#00c8b4](https://placehold.co/12x12/00c8b4/00c8b4.png) `#00c8b4` | 三根 K 线缺口（影线对影线）着色彩带 |
| **IFVG** | ![#ff9800](https://placehold.co/12x12/ff9800/ff9800.png) `#ff9800` | 实体收盘穿越整个缺口后**换向**使用 |
| **EQH / EQL** | ![#e0e0e0](https://placehold.co/12x12/e0e0e0/e0e0e0.png) `#e0e0e0` | 横向粗线 + **容差带**，被取走后转灰 |
| **SWEEP** | ![#ffd54f](https://placehold.co/12x12/ffd54f/ffd54f.png) `#ffd54f` | 影线越位、收盘收回位内 |
| **IDM** | ![#ba68c8](https://placehold.co/12x12/ba68c8/ba68c8.png) `#ba68c8` | 诱导位（角色标签） |
| Premium / Discount | 红/绿底 + `PREMIUM` / `DISCOUNT` / `EQ` | 区间按 50% 对分 |
| 强/弱高低点 | `SH`/`WH`/`SL`/`WL` | **默认关闭**（标记较密） |
| Killzone | 蓝 / 橙 / 绿 | 亚洲 / 伦敦 / 纽约时段矩形 |
| 多周期结构 | 按方向着色 + `MTF BOS` 标签 | **默认关闭** |

#### 核心概念（与 TradFi_Structure 的差异处）

- **枢轴（pivot）**：对称窗口 —— `p` 是枢轴高 ⟺ `high[p]` **严格大于** `[p-len, p+len]` 内其余每一根。
  **确认延迟 = 右窗口长度 `len`**，故不可能有未来函数。实测自检等式恒成立（0 次违反）。
- **BOS vs CHoCH**：BOS = 朝趋势**同向**突破（延续）；CHoCH = 朝趋势**反向**突破（首次反转警告）。
  `trend==0` 的**首次**突破标 **BOS** 而非 CHoCH —— CHoCH 的字面含义是"性格**改变**"，
  此处没有可改变的前状态，标 CHoCH 等于声称一次无法验证的反转。
- **两层结构 ≠ ICT 递归分级**：swing / internal 只是两个不同半窗的检测器。
  ICT 真正的分级是**递归晋升**（STH → ITH → LTH），本工具**不声称**实现它。
- **扫荡不消耗结构位**：影线越位但收盘收回只记一次 `SWEEP`，该位**仍然有效**，
  后续真正的收盘突破照样能出 BOS/CHoCH。否则一次扫影线会永久吃掉一个结构位（丢信号）。
- **IFVG 判定写死**：**实体收盘穿越整个缺口**（越过远端）。影线永不算；CE 是成立**之后**的入场位，
  不是判定条件 —— 故**没有**"收盘穿 CE 即反转"的宽松档。
- **OB 两个并存状态**：*缓解* = 价格触及（降级配色）；*失效* = **实体收盘穿越远端**。
  默认**都不隐藏**（只改配色与 CSV 的 `state`），因为"隐藏"等于丢信息。
- **同 bar 双破（外包 K 线）**：MQL5 无 tick 顺序，按阳/阴线近似决定终态方向，
  并在 CSV 的 `extra` 列标 `CONFLICT(bothSidesBroke)` —— 不隐藏"这里其实有歧义"。
  另有**显式倒挂守卫**：高/低位倒挂时丢弃该状态重建（主流实现靠几何巧合隐式互斥，异常输入下会静默出错）。

#### 输入参数（主要项）

| 分组 | 参数 | 默认值 | 说明 |
|---|---|---|---|
| 模块开关 | `InpShow*` ×13 | 见上表 | M9 / M11 默认关 |
| 结构检测 | `InpSwingLen` | **`15`** | 波段层半窗。**不是** LuxAlgo 的 50，理由见下 |
| | `InpInternalLen` | `5` | 内部层半窗 |
| | `InpBreakConfirm` | `SMC_BREAK_CLOSE` | 收盘越过（SMC 口径）/ 影线触及 |
| | `InpMinDisplaceBodyATR` | `0.5` | 破位 K 实体 / ATR；不足只弱化配色，**不否决事件** |
| 订单块 | `InpOBBasis` | `SMC_OB_HYBRID` | 影线全幅 + 实体 50% 中线 |
| | `InpOBCluster` | `3` | 连续反向 K 线合并上限 |
| FVG | `InpFvgHideFilled` | **`false`** | 实测 **83%** 的缺口最终会被完全穿透，默认隐藏等于抹掉六分之五 |
| 等高等低 | `InpEqTier` | `SMC_EQ_INTERNAL` | ⚠️ **必须挂内部层**，见下 |
| | `InpEqToleranceATR` | `0.15` | 可考实现实测范围 0.10~0.25 |
| | `InpEqDrawBand` | `true` | 画成容差带而非线 |
| Killzone | `InpKzAsia/London/NewYork` | `20:00-00:00` / `02:00-05:00` / `07:00-10:00` | **纽约时间**，均可编辑 |
| | `InpKzAutoTZ` | `true` | `TimeGMT()` 反推服务器偏移 + 美国 DST 规则 |
| 性能 | `InpAnalysisWindow` | `2000` | 分析窗口（500 根下结构事件仅 9 个） |
| | `InpWindow` | `500` | 绘制窗口 |

#### 验收与验证工具

| 工具 | 作用 | 当前结果 |
|---|---|---|
| `MetaEditor64 /compile` | 语法与类型 | **0 errors, 0 warnings** |
| `tools/smc_logic_sim.py` | 核心算法**逐行移植**后跑分布判据 | 全部通过 |
| `tools/check_csv_columns.py` | CSV 每条行格式字段数 = 表头字段数 | 8/8 一致（17 字段） |

`smc_logic_sim.py` 的硬判据里最关键的一条是 **FVG 方向侧检查**：
缺口在确认那根时价格必须在**正确一侧**。这是构造性恒等式，必须恒为 0 次违反 ——
仓库历史上正是栽在这里（两个分支的 `dir` 写反 → 价格本就在另一侧 → 全部缺口瞬间"已回补"）。
实测 `sideBad=0`。

#### ⚠️ 口径边界（如实声明）

1. **强/弱高低点没有权威口径** —— LuxAlgo 官方 Library 的 **54 个** SMC/ICT 概念、
   ICTKillzone 的 **115 条**术语表**都不收录**该术语，三份可读实现**无一输出它**。
   本实现只提供两套**有出处**的读法（默认：已被越过 = 弱）。
2. **OB 区间基准无统一口径** —— LuxAlgo 官方原文 *"conventions genuinely differ here"*。
   全幅 / 实体 / 混合三种都属一线主流；默认取混合，并**把均值门槛线显式画出来**，
   不让它成为隐藏假设（body-50% 与 full-range-50% 是**不同数值**）。
3. **Killzone 时段边界各家差 30~90 分钟**，全部可编辑。
4. **`TimeGMT()` 在策略测试器里可能不准**；DST 只判到日粒度 → 可关自动模式手动覆盖。
5. **多周期结构只做映射，不做门禁**；**不做回测/胜率统计**。
6. **未实现**：ICT 递归分级、OB→Breaker 改标、OTE 带、Premium 四分位带。
7. **本机无 MT5 回放环境** —— 验收止于「编译 + 逐行移植仿真 + 静态列数检查」，
   **真机读图验收需由使用者完成**。

#### 实测决定的默认值（不是偏好）

| 默认值 | 证据 |
|---|---|
| `InpSwingLen = 15`（而非 50） | 500 根窗口下：50 → **1** 个结构事件；15 → **9** 个（BOS 7 + CHoCH 2） |
| EQ 挂**内部层** | 波段层枢轴间距中位数 **130** 根 → EQ 恒为 0；内部层 **13** 根 → 正常成池 |
| `InpFvgHideFilled = false` | 实测 **83%**（5715/6852）的缺口最终被完全穿透 |
| `InpAnalysisWindow = 2000` | 2000 根下结构事件 33~41 个，500 根下仅 9 个 |
