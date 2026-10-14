# Pine → Mine Script（TradingVue）移植笔记 — TTFM° 实战

> 起因：把 `ttrades/pinescript`（Pine v6）搬到 TradingVue 的 Mine Script，HTF 蜡烛一直不显示。
> 结论来自**逐轮实测定位**（每一条都先被某个假设骗过，最后靠"直接读指标内部真值"收口）。
> 与 `TradingVue/MIGRATION_NOTES.md`（反方向：MQL5 → Mine）配套读。

## 1. 这台引擎的硬约束（照做才能跑）

| # | 约束 | 现象 | 依据 |
|---|---|---|---|
| 1 | **链式方法调用只执行第一段** | `a.M1().M2().M3()` 里只有 `M1` 生效；`M2/M3` 静默不跑 | 实测：HTF 蜡烛停在创建坐标（`boxL=bar_index`），而 `Reorder()` 在 `Update()` 里、`Update()` 在链的第 2 段 ⇒ 拆成三条独立语句后**全部恢复正常** |
| 2 | `overlay = true` 的关键字写法**不生效**（落副图）| 指标挂在副图 | 改用**位置参数**：`indicator("t", "s", true, ...)`（第 3 位 = overlay）|
| 3 | **绘图对象计入价格自动缩放** | 任何锚在 `y=0/1` 的 line/box 会把纵轴拉到 0、K 线压成一条线 | 原脚本的 HTF 起始竖线 `line.new(y1=0, y2=1, extend.both)` 直接复现；改锚当前 bar 的 `low/high` 解决 |
| 4 | `indicator()` 的 `max_labels_count` 默认 **50**，超额**静默删最旧** | 早建的对象（HTF 名称/倒计时标签）先消失 | 显式设 `max_labels_count = 500` |
| 5 | `array.get()` 越界是**运行时错误**（不是返回 na） | 条件关闭时脚本直接报 `Index 0 is out of bounds` | 原脚本用 `htf_lines[0]` 推 HTF 起始 bar，而该数组只在开关打开时才填 |
| 6 | `import user/Lib/ver`（TradingView 社区库）**必然不存在** | `脚本库 XXX 不存在` + 所有调用点报错 | 用本地函数替身（本例 `customAlert()` = `str.replace_all` 填模板 + `alert()`）|

## 2. 排除过的假设（别重复走）
1. "未来坐标（`bar_index + N`）不渲染" ✗ —— 探针实测：索引/时间两种坐标、**直接建**与**建后再 `set_left/set_right` 搬**，全部正常。
2. "未来区映射退化/被压窄" ✗ —— 那是读图误判（不同坐标系的 bar 跨度量纲不同，宽度不能直接比）。
3. "`box.set_left/set_right` 忽略未来值" ✗ —— 5 框对照实验全部落位。
4. "句柄存在 UDT、UDT 又存数组 → 句柄失效" ✗ —— 孤立探针（UDT→数组→`array.get`→`set_*`）正常。
5. **"链式调用只跑第一段" ✓** —— 与"看得见的都在 `Monitor()`/无条件区、看不见的都在链的 2/3 段"这一规律完全吻合。

## 3. 教训（方法层面，适用于这台引擎的任何移植）
- **定位顺序**：先证明"平台能力"（合成探针），再证明"指标内部状态"（在真指标里加临时诊断标签打印 `size()` / 对象坐标 / 当前 `bar_index`）。第二类证据一次就能定案，前四轮纯靠合成探针猜了四回。
- **诊断要打印"可对账的数字"**：`boxL` 与 `bar_index` 的差值、对象坐标 vs 目标坐标 —— 一眼就能分清"没建 / 建了没搬 / 搬了没渲染"。
- 临时诊断对象用完即删；**该指标没有 deinit 清理**，重贴会留下旧对象（多张黄标签叠在一起就是这个原因）——每次重贴前先删掉图上的指标实例。
- `0 errors` 不代表跑得对：链式调用静默失效、绘图参与缩放都属于"不报错的错"。

## 4. 本轮实际改动清单（`ttrades/ttrades.mine`）
| 改动 | 目的 |
|---|---|
| `indicator(...)` 加 `max_labels_count = 500`；overlay 改位置参数 | 标签上限 + 主图叠加 |
| HTF 起始竖线锚点 `y1=0,y2=1` → `low/high`（±`syminfo.mintick`）| 修"纵轴被拉到 0" |
| `type CandleSet` 加 `int start_bar`；Monitor 里 `candleSet.start_bar := bar_index` | 去掉对 `htf_lines[0]` 的越界依赖 |
| `helper.LineStyle()` 的 `'----'`/`'····'` 字面量 → 常量自比较 | Trace 线型选择恢复 |
| HTF 构建窗口 `last_bar_index - 1000` → 按 HTF/图周期比例缩放（clamp 4000）| 大 HTF 在小周期图上画不出来 |
| `box.set_left/set_right` 事件的 `array.unshift` 托管 + 上限 200 | Silver/Sweep 标签不再被 50 上限静默裁掉 |
| `pivot_high/pivot_low` 三元表达式补括号 | Pine 的 `A or B and C` ≠ `(A or B) and C` |
| `import CustomAlertLib` → 本地 `customAlert()` | 第三方库不存在 |
| **6 处 `htfN.Monitor().Update(...).FindImbalance()` 拆成三条独立语句** | **本次根因**：链式调用只跑第一段 |

## 5. 编译器警告的处理结论（收口）

TradingVue 编译器给出 13 条同句警告「为确保计算一致性，应在每次运算时调用函数'X'。建议将其调用移出当前作用域。」
含义：**这些函数有内部状态**（要读上一根 bar 的值，或用变量偏移访问历史），引擎要求它们**每根 bar 都被调用**，
放进 `if`/`else` 后某些 bar 会跳过 → 历史段与实时段可能算出不同结果。是**警告不是错误**（脚本照常编译运行）。

| 类别 | 对象（原行号）| 处置 |
|---|---|---|
| 有状态内置函数 | `ta.change`（1117，`isNewHTFCandle` 的 `else` 分支）| ✅ **已修**：`htfChanged = ta.change(HTFBarTime) != 0` 提到 `if` 之前**无条件求值**，`else` 分支改用 `htfChanged`。语义完全一致，且更正确。`ttrades.mine` 与 `pinescript` 都改 |
| 事件驱动调用 | `findLevelBarIndex`（1278/1335/1381/1428）、`detectCISDAndProjections`（1282/1339/1385/1432）、`htfN.Monitor`（1928…1983）| ⛔ **判定可忽略**：它们本就只在 T-Spot 成立 / HTF 门控内跑；要消掉必须改成"每根 bar 无条件调用、只把绘制留在条件里"，属结构性改动且偏离 Pine 原版。TradingView 对同一份代码给同类警告 |

> 教训：**警告要按"是否真的有状态断点"分类**，不能一律去消 —— 只有第 1 类是真实的（状态函数被条件分支割断），
> 其余 12 条是"事件驱动调用"的通用提示。

## 6. 口径改动：目标投影（Projection）改为 TTrades 读法

原脚本（作者自定口径）：`proj = 破位价 ± 造势序列幅度 × level`，默认水平 `"0.5,1.0,1.5,2.0"` —— 与 TTrades 无关。

改为 TTrades 读法（依据 `docs/research/2026-09-23-TTFM-rules-report.md` §7）：

| 要素 | TTrades 口径 | 代码实现 |
|---|---|---|
| 锚点（操纵腿）| CISD 之前那次**扫流动性**的摆动：看涨 = 之前的最后一个低点、看跌 = 之前的最后一个高点 | `c2_extreme_level`（C2 的扫破价位，本就是该函数入参）|
| 腿的另一端 | 造势序列极值 = **水平 0** | `leg_end = is_bullish ? series_high : series_low` |
| 腿长 | 从 Candle 2（反转点）量到腿末端 | `leg_len = is_bullish ? series_high - c2_extreme_level : c2_extreme_level - series_low` |
| 方向 | 看跌 **高→低**、看涨 **低→高** | `proj = is_bullish ? leg_end - level*leg_len : leg_end + level*leg_len` |
| 水平 | `1, 0, −1, −2, −2.5, −4`（0 = 腿末端，−N = 沿交易方向 N 倍腿长，+1 = 腿起点）| 输入项默认值改为该列表 |

预期（同一份文档）：平均腿 → 到 **−2 / −2.5** 有反应；扩张腿 → **−4 / −4.5**；腿过大 → 缩小到 **−1**。

⚠️ 标注：**水平列表**出自 std-dev 文章、且该文原文水平表被截断（中介置信度）；**锚点/起量点的精确几何**是本文档读法，非逐字口径 —— 对外引用时按此标注，不要说成"他的原话水平位"。

## 7. 浅色底图的配色坑（用户底图是白色）

| 对象 | 原默认 | 问题 | 现默认 |
|---|---|---|---|
| Sweep 确认标签 `tspot_sweep_label_color` | `color.white` | **白底上白字 = 隐形**（用户实际看不到）| `color.black` |
| Trace 价签 `settings.label_color` | `#eaeaea`（近白）| 同上（Trace 默认关闭）| `color.black` |

规则：**默认色必须按"用户实际底图"选**（对应仓库 CONTEXT 硬约定 7「不许假设黑底」）。改动只碰默认值，输入项仍可改。
`color.new(color.white, 100)` 这类**全透明背景**不算问题（它是"无背景"的写法，不是白色标签）。

## 8. 平台适配：面板的 HTF 倒计时算错

**现象**（同一时刻、同一品种，1M 图 / 15M HTF）：TradingView 面板显示 `01:49`，Mine 版显示 `12:30`；两台平台**自带的 1M 秒级倒计时几乎一致**（47s vs 42s ⇒ 墙钟相同）。

**原式**（`Helper.RemainingTime`）：`timeRemaining = (time_close(HTF) - timenow)/1000`

**反推**：TV 的 01:49 ⇒ 15M 蜡烛收盘在 01:00 ✓（00:45–01:00）；12:30 ⇒ 收盘在 ~01:10:48、或 `timenow` 停在 ~00:47:30 —— 都不是 15M 边界 ⇒
**这台引擎的 `timenow` / `time_close(HTF)` 有一个不可靠**（差 ~10m41s）。

**处置**：`ttrades.mine` 改为只用 bar 开盘时间的纯算术式（绕开这两个平台调用）：
`timeRemaining = timeframe.in_seconds(HTF) - (time - time(HTF))/1000`
代价：粒度随 1M bar 更新（不秒跳）。原式在 TradingView 上正确，`pinescript` **不动**，注释保留备查。
定案工具：`ttrades/probe_htf_timer.mine`（把 `1M bar open / timenow / time(15) / time_close(15) / in_seconds` 与两个公式结果一起打在图上）。

> 教训：**凡是依赖 `timenow` / `time_close(htf)` 的"现在几点"计算，移植到非 TradingView 引擎都要重新验**；
> 优先用"只用 bar 开盘时间"的纯算术式（可观测、无平台隐式状态）。
