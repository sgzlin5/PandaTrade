# TradFi_Structure —— Mine Script v6 移植说明与验证清单

> 源实现：`Indictor/TradFi_Structure.mq5`（v1.47，口径 v1.39）
> 移植产物：`TradingVue/TradFi_Structure.mine`
> 目标平台：TradingVue.com 的 Mine 编辑器（Mine Script v6）

**状态：未编译验证。** 本文档的目的就是明确区分「有官方文档背书」与「需在编辑器里实测」的部分，
请按第 3 节逐条过一遍再上图表。

---

## 1. 移植口径对照

| MQL5 概念 | Mine Script 实现 | 保真度 |
|---|---|---|
| `struct SState` 状态机 | 一组 `var` 变量（跨 bar 持久） | 等价 |
| `ComputeStructure` 全量重算 + 窗口截断 | 增量状态机（每 bar 收盘执行一次） | 语义等价，见下 |
| `struct StructureResult` 平行数组 | `array<int>/<float>/<bool>` 结果集合 | 等价 |
| `OBJ_TREND` 逐段结构线 | 单条 `polyline.new()` | 等价（一处折线 vs 多段） |
| `OBJ_RECTANGLE` 内包盒 | `box.new()` / `box.set_*` | 等价 |
| `OBJ_TEXT` MSS/BOS 标签 | `label.new()` | 近似（见 §3-7） |
| `CalcATRSeries` Wilder 递推 | `ta.atr(period)` | 等价 |
| 时序列 `0 = 最新` | `bar_index 0 = 最旧`（递增） | 语义等价，间隔比较统一用差值 |
| `InpMinBarsBetweenSwings` 用 `MathAbs(lastNodeBar - i)` | `math.abs(lastNodeBar - midBar)` | 等价 |
| 每 tick 全量重算 + 结果复用 | 逐 bar 增量（无 tick 级重算） | 设计差异，见 §2-1 |

### 完整保留的逻辑（逐条对应源码）

- **A2 突破检测**是 BOS/MSS 唯一触发源（v1.37），内包盒/外包不再独立触发标记。
- 同一根 K 同时上破+下破时**互斥裁决**：UP 中阳线保留 BOS、阴线保留 MSS；DOWN 中阳线保留 MSS、阴线保留 BOS。
- **MSS 后重置对侧 ref**（bearish MSS → `refHighValid=false`；bullish MSS → `refLowValid=false`）。
- **MSS 当 bar 不用本 bar 的 swing 回填反向 ref**（v1.37 第 4 条）。
- `UpdateRefsFromSwing` 的 HH/HL/LL/LH 语义：顺趋势侧「仅创新极值或已破才更新」，反趋势侧「每个 swing 都更新」。
- **只有 `isMain`（主结构）swing 才更新 ref 并复位 broken**；内部 swing 仍进结构线。
- `AddNodeFiltered` 交替过滤：同类型只留更极端者；替换节点时同步同类型 ref 的 bar/price。
- 相邻 swing 最小间隔过滤、有效回撤过滤（点数 AND (ATR OR 比例)）、最小 swing 幅度硬下限。
- 主结构判定（ATR 倍数 OR 前段比例）。
- 内包过滤：被母线完全包含的 K 线不参与 swing 检测，但记录内包盒。
- fractal swing 判定 `high[i]>high[prev] && high[i]>=high[next]`（低点对称）。
- `LineEnd` 的 3 种端点模式（标准/固定 N 根/首次回踩），标签方向感知偏移 `ATR×0.15`。
- 每类事件只显示最近 N 条。

---

## 2. 有意的行为差异

### 2-1. 历史事件落图延后 1 根 bar

MQL5 全量重算时，`validBars[k+1]` 已存在，所以 `validBars[k]` 的 swing 在**当根 bar** 就能确认。
Mine 是逐 bar 执行的因果系统，第 k 根的 swing 必须等第 k+1 根收盘才能确认。

**影响**：结构线与 BOS/MSS 的最终位置完全一致，但在历史回放中「出现时间」晚 1 根 bar。
这是逐 bar 事件驱动模型的固有代价，不是 bug。

### 2-2. 结构线不画窗口外节点

MQL5 用 `InpWindow` 截断绘制窗口但**全量分析**。Mine 的 `polyline` 上限 500 点，
脚本里取最近 500 个节点（覆盖默认 200 根窗口）。节点数组本身不截断。

### 2-3. `碰到折线` 端点模式已移除

MQL5 的 `LINE_END_HIT_ZIGZAG` 需要「扫描未来折线段求交点」。
逐 bar 因果模型下未来折线尚不存在，且 v1.39 已把默认端点改回 `LINE_END_BREAK`。
故下拉框只保留 `突破K线`（= v1.39 默认）/ `固定N根` / `首次回踩`。

### 2-4. 内包盒只维护最新一个

MQL5 渲染全部盒（受窗口过滤）。Mine 脚本只保留最新一个盒对象，
因为 Mine 侧 `drawnN` 计数与历史对象生命周期无法可靠对应。结果集合里全部盒仍在，
如需显示多个，可在渲染段改成循环 `box.new()`。

### 2-5. 性能策略

MQL5 靠 `InpReuseResultOnTick` 复用结果避免每 tick 重建数百个图表对象。
Mine 只在 `barstate.isconfirmed` 推进状态、只在 `barstate.islast` 重建绘图，
天然没有该问题，故未移植这两个开关。

---

## 3. 必须在 Mine 编辑器中实测的点

按风险从高到低排列。**建议先只保留前 40 行，逐段放开验证**。

| # | 风险点 | 说明 | 若报错怎么改 |
|---|---|---|---|
| 1 | `input.string(..., options = [...], group = ...)` | `group` / `options` 的确切参数名未从文档确认 | 去掉 `group`/`options`，退化为普通字符串输入 |
| 2 | `syminfo.mintick` | 字段名未确认 | 换成 `syminfo.mintick` 的等价写法，或直接硬编码 `0.00001` |
| 3 | `chart.point.from_index(idx, price)` | 构造器签名未确认 | 改用 `chart.point.new(time, idx, price)` |
| 4 | `polyline.new(pts, ...)` 位置参数顺序 | 文档给的是 `points, curved, closed, xloc, line_color, fill_color, line_style, line_width` | 按报错调整，或全用具名参数 |
| 5 | `label.new(bBar, price, txt, xloc=, style=, color=, textcolor=, size=)` | 标签页抓取失败，参数按 Pine v6 同形写 | 删掉 `textcolor`/`size` 逐个试 |
| 6 | `box.set_lefttop()` / `box.set_rightbottom()` | 文档提到这两个函数名，但未给签名 | 改用 `box.set_left/set_right/set_top/set_bottom` |
| 7 | `plotshape(..., style = shape.circle, location = location.top)` | 仅为满足「指标至少一个输出调用」的声明要求 | 换成 `barcolor(na)` 或删掉（若 `line.new` 已够） |
| 8 | `int(math.max(a, b))` | 用作 `line.new` 的 x 坐标需要 int | 已加 `int()` 转换，若类型报错改 `math.round` |
| 9 | `var` 声明的数组在 `if` 块内被 `array.push` | 文档「作用域」一节明确允许局部改写全局数组 | 若报错，把 push 提到全局作用域 |
| 10 | `barstate.isconfirmed` / `barstate.islast` | 文档明确存在 | — |

### 关于点数阈值

MQL5 的 `_Point` 与 Mine 的 `syminfo.mintick` 在多数品种上数值相同，
但**含义不同**：`_Point` 是报价最小单位，`mintick` 是最小价格变动。
`InpMinRetracePoints=100` 这类阈值在移植后单位按 `mintick` 解释，请按品种实际调整。

---

## 4. 参数默认值对照

| Mine 输入 | 默认 | 对应 MQL5 |
|---|---|---|
| 结构模式 | `ShortTerm` | `InpMode = MODE_SHORT_TERM` |
| 最小回撤点数 | `100` | `InpMinRetracePoints` |
| 最小回撤 ATR 倍数 | `0.5` | `InpMinRetraceATR` |
| 最小回撤占前段幅度比例 | `0.236` | `InpMinRetraceRatio` |
| ATR 周期 | `14` | `InpATRPeriod` |
| 最小 swing 幅度 | `0` | `InpMinSwingAmplitude` |
| 相邻 swing 最小间隔 | `2` | `InpMinBarsBetweenSwings` |
| 主结构腿长门槛 (ATR) | `1.0` | `InpMainFilterATR` |
| 主结构腿长占前段比例 | `0.382` | `InpMainFilterRatio` |
| 收盘突破确认 | `false` | `InpCloseConfirm` |
| 虚线终点模式 | `突破K线` | `InpLineEnd = LINE_END_BREAK`（v1.39 默认） |
| 每类各只显示最近 N 条 | `6` | `InpMaxEvents` |
| 结构线颜色 | `rgb(57,197,207)` | `InpColorStructure` |
| MSS 颜色 | `rgb(255,213,79)` | `InpColorMSS` |
| BOS 颜色 | `rgb(255,82,82)` | `InpColorBOS` |
| 内包盒颜色 | `rgb(110,110,130)` | `InpColorBox` |

**未移植**：`InpWindow`（改由 polyline 500 点上限覆盖）、`InpDashBars`（已废弃）、
`InpNeedRetestToShow`（默认关闭，可后补）、`InpDrawSubStructure` / `InpColorSubStructure`
（v1.38 起结构线不再区分主/内部线型，统一青色实线）、`InpAnalysisWindow`、
`InpReuseResultOnTick`、`InpDebugShowRef`（等价能力由 `debugRefInput` 提供标签显示）。

---

## 5. 算法流程图（与 MQL5 一致）

```
每根 bar 收盘：
  ├─ 1. 内包判定：high <= 母线high && low >= 母线low ?
  │     是 → 记录内包盒区间，跳过本 bar（不参与 swing）
  │     否 → 本 bar 是「有效 bar」，继续
  │        └─ 若中间有内包段 → 记录盒（母线 high/low + 内包起止）
  ├─ 2. A2 突破检测（BOS/MSS 唯一触发源）
  │     UP   : 破 refHigh → BOS-up    | 破 refLow → MSS-down（切 DOWN，清 refHigh）
  │     DOWN : 破 refLow  → BOS-down  | 破 refHigh → MSS-up  （切 UP，清 refLow）
  │     双破  : 按 close vs open 裁决（MSS 优先）
  │     触发即置 broken=true；不更新 ref
  ├─ 3. fractal swing 确认（old / mid / cur 三元组）
  │     swing high: midHigh > oldHigh && midHigh >= high
  │     swing low : midLow  < oldLow  && midLow  <= low
  │     → 最小间隔过滤 → 双 swing 互斥裁决 → 有效回撤过滤 → 主结构判定
  │     → 播种 or 加节点（交替过滤）+ 更新 ref（仅 isMain）
  └─ 4. 滚动推进 old ← mid ← cur ← 本 bar；本 bar 成为新母线

最后一根 bar：
  → 重建 polyline 结构线（节点变化时）
  → 更新实时腿（起点=最后确认节点，终点=之后反向极值）
  → 增量绘制 BOS/MSS 线+标签 → 更新内包盒
```

---

## 6. ⚠️ v1.48 对齐 TTrades 后产生的分歧（**本移植版尚未跟进**）

**状态**：本 `.mine` 版对应 MQL5 的 **v1.47 / 口径 v1.39**。MQL5 侧 v1.48 完成了一轮
"对齐 TTrades"的改造，**下列内容本移植版全部没有**
（关键词计数：`CISD` / `SWEEP` / `bias` / `displacement` / `tier` 在 `.mine` 里均为 **0**）。

| v1.48 的新增 / 变更 | 说明 | 本移植版 |
|---|---|---|
| swing 三点判定**左右皆严格** | `high[i]>high[prev] && high[i]>high[next]`（低点对称）；旧版右侧用 `>=` / `<=` | ❌ 仍是旧式（见 §5 流程图第 3 步） |
| failure swing 剔除 | 与上一**同类型** swing 距离 < `sepATR×ATR` 不予确认 | ❌ 无 |
| **默认收盘确认** | `InpCloseConfirm=true` | ⚠️ 需核对 `closeConfirm` 的默认值与作用范围 |
| **位移判据 → MSS** | 实体 / 穿越深度 / 时效三条门槛；未过则弱化 | ❌ 无（MSS 仅"逆势破位"） |
| **CISD** 事件 | 造势序列**最旧一根**的开盘价 + 收盘穿越 | ❌ 无 |
| **SWEEP** 事件 | intermediate 位被影线越过但**收盘收回位内** | ❌ 无 |
| 摆动分级 `tier` | short / intermediate（比左右最近同类型点都更极端） | ❌ 无 |
| HTF relevance 位 | 高周期回看 3 根 K 线的极值，两条点线 | ❌ 无 |
| **HTF 偏置门禁** | 与偏置逆向的事件弱化（无标签 + 暗色点线） | ❌ 无 |
| 内包 K 线**也参与突破检测** | 收盘口径下内包 bar 的收盘仍可越位 | ❌ 无（内包 bar 整体跳过） |
| 数组方向显式声明 | `ArraySetAsSeries(..., true)` | ✅ **天然无此问题** —— Mine 用 `bar_index` 递增 |
| 构建指纹 + 事件 CSV 导出 | `BUILD_TAG`、`InpDumpEvents`、自描述头部 | ❌ 无（Mine 侧可用 `log.info` 与表格替代） |

**为什么没在这一轮同步**：

1. 这是一次**实质性功能扩展**（两类新事件 + 摆动分级 + 一套门禁），不是文案同步 ——
   相当于把 v1.48 整个重做一遍；
2. Mine Script **没有可用的本地编译器**，改动无法验证。而 MQL5 侧这一轮最大的教训恰恰是
   **"不报错的错误"代价最高**（`||` 短路与数组方向都编译通过、却让整幅画面全空）——
   在无编译器的环境里盲改风险很高；
3. MQL5 侧口径**仍在演进**（`1-F` 已搁置、`ref` 的驱动源尚未对齐 TTrades），现在同步会跟着变。

**建议**：等 MQL5 侧口径稳定后再移植，且**按 v1.48 的分层顺序逐项跟进**
（结构基元 → 确认口径 → 事件 → 门禁），每步在 Mine 编辑器里实测一遍。
届时可直接复用 `docs/baselines/` 的事件基线做逐行比对的参照。

> 注：Mine 的 `bar_index` 递增语义天然规避了 MQL5 侧的"数组方向"陷阱，
> 但也意味着**两者的事件时点会差 1 根 bar**（见 §2-1），比对时要扣掉这个偏移。
