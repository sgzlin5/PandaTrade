# TradFi_Structure v1.48 性能优化说明（订正版）

> 对象：`Indictor/Structure.mq5`
> 状态：**已用 MetaEditor64 编译通过（0 errors / 0 warnings）并在 MT5 实盘图表上运行验证**。
> 初版本文写于"未能编译验证"的阶段，其中有 5 项改动后来被实测证明有害并已回滚，
> 另有 2 项致命 bug 是后来才定位到的。先把订正摆在这里，再讲现在真实的形态。

---

## 0. 订正记录（**请先读这一段**）

| 初版的论断 | 实际情况 |
|---|---|
| ①「`ObjectGet*`/`ObjectSet*` 是到终端的**跨进程调用**，是性能瓶颈所在」 | **前提错误**。MQL5 文档：在当前图表上这些调用是**直接访问**，不走同步队列。见 §5。整篇初版的代价模型建立在这个错误前提上。 |
| ②「对象属性影像缓存 `GfxMirror` 是主要收益」 | **已整体回滚**。它引入的槽位分配/压缩逻辑反而出 bug —— 实测镜像被压成 1 格，**除第一个外的结构线全部建不出来**。见 §6。 |
| ③「`changed = changed \|\| Upsert*()` 比 `\|=` 语义更明确」 | **这是最严重的一处错误**。MQL5 的 `\|\|` **会短路**：`changed` 一旦为真，右侧的 `Upsert*` 根本不被求值 → 同样"除第一个对象外全不创建"。已全部改成 `if(Upsert*()) changed = true;`。见 §7.1。 |
| ④「回收段仍每帧都跑（不能门控）」（§4）| 与本文 §6 ⑪ 自相矛盾；**最终实现是门控的**。见 §4。 |
| ⑤「§8 请这样验证：确认与 v1.47 **外观完全一致**」 | **做不到，也不该这样验**。v1.47 的数组方向假设是错的，v1.48 修掉后画面本来就该变（分析区间从"最老的一段历史"回到"最近 `InpAnalysisWindow` 根"）。见 §7.2。 |
| ⑥「创建路径去掉冗余 `ObjectFind`，省一次 IPC」（§4 ⑦）| **已回滚**。`ObjectFind` 在当前图表上是直接访问，省不下 IPC；去掉它反而让"对象是否已存在"的判断失去依据。现实现保留 `ObjectFind`。 |
| ⑦「`g_forceRedraw` + `GfxPrune()` 镜像压缩」（§4 ⑨、§6 ⑫） | **随镜像一起删除**。镜像不存在了，这两个补丁也就没有依附对象。 |

**教训（写进代码头注释了）**：本项目的两次"画面上什么都没有"都不是算法错，
而是**求值顺序**与**数组方向**这类"不报错的错误"。这两类问题的共同点是
编译通过、日志正常、对象坐标全对，唯一异常就是"看不见"。

---

## 1. 现在真实的代价模型

| 路径 | 调用频率 | 真实成本 |
|---|---|---|
| `ComputeStructure` | 每新 bar 一次 | 纯计算，无对象接触 |
| `RenderScene` 指纹判定 | 每新 bar 一次 | 8 次比较 + O(nNodes) + O(nBox)，**纯内存** |
| `RenderScene` 调和 | 仅 `needDraw` 帧 | 每对象若干次 `ObjectGet*`（直接访问）+ 变化项 `ObjectSet*` |
| `RenderScene` 回收 | 仅 `needDraw` 帧 | O(total) 哈希探测，**非** O(total × kept) |
| `UpdateLiveLeg` | **每 tick** | 门控命中时 = 3 次比较 + return |

当前图表上的 `ObjectsTotal` / `ObjectName` / `ObjectGet*` / `ObjectSet*` 都是
**直接访问**（MQL5 文档明确说明，见 §5）。所以优化的目标不是"减少 IPC 次数"
（那是个不存在的成本），而是**减少进入对象循环的帧数**与**脚本侧内存工作**。

按这个正确的模型，最终路线是**门控路线**：靠"少进循环"而不是"缓存对象"。

---

## 2. 保留下来的优化（①②③④⑤ 对应初版编号）

### ① 整段绘制门控 `needDraw`（收益最大的一项，纯内存）

八项指纹全部未变 → 整段绘制与注册跳过：

| 指纹 | 含义 |
|---|---|
| `nodesTotal` / `curLastBar` | 节点集合是否变了 |
| `beginNode` | 第一个落在绘制窗口内的节点下标（窗口横移会改它） |
| `boxIdx` | 最新内包盒下标 |
| `nMSS` / `nBOS` | 事件条数 |
| `mssFrom` / `bosFrom` | `InpMaxEvents` 裁剪起点 |

### ② `ChartRedraw()` 门控

`g_gfxDirty`（帧内任何创建/修改/删除置位）+ `changed` 共同门控，每帧开头复位。
结构没变化的 bar 不再重绘，消除闪烁。

### ③ `UpdateLiveLeg`：门控前置 + 同 bar 早退 + 位移阈值

```
门控前置（3 次比较）：
  同一 bar 且 该腿的极值窗口落在当前未收盘 bar 上
  且 |low[0] - 上次端点| < eps 且 |high[0] - 上次端点| < eps
  → 直接 return（连扫描都不做）
扫描后二次门控：
  端点 bar 未变 且 |新端点 - 上次端点| < eps  → return
eps = 0.1 × ATR（ATR 不可用时退回 10 × _Point）
```

前置门控是**保守**判断 —— 可能漏掉"当前 bar 越过了阈值但最终极值仍是旧端点"，
那只会多走一次扫描，不影响正确性；二次门控负责最终正确性。

### ④ 减少无效分配 + 删死代码

- `validBars`：`rates_total` → `analysisStart + 1`；
- **删除 `boxRef` 平行数组**（被写入但从未被读取的纯死代码）；
- `atrArr`：`rates_total` → `analysisStart + 1`，顺带修掉上一次代码审查指出的
  "尾部槽位从未赋值"隐患（原来 `analysisStart` 以上恒为 0，若将来有人读该区间
  会让 ATR 过滤**静默失效**）。

### ⑤ 场景成员判定改哈希集合 + 回收段门控

`InScene()` 从线性查表改为开放寻址哈希集合（`g_setKey[]` + FNV-1a + 线性探测）：

- 成员判定 O(1)，回收段整段由 O(total × kept) 降为 **O(total)**；
- 容量取 2 的幂用掩码寻址，负载因子 ≥ 0.5 自动翻倍重建；
- 只在 `needDraw` 时重建（期望集合只在重画帧才变），容量按上一帧规模自适应；
- 空串作空槽位哨兵 —— 对象名恒非空（都有 `Structure_` 前缀），安全；
- 回收循环加 `needDraw` 门控：`needDraw == false` 意味着期望集合与上一帧完全一致，
  此时回收必然是空操作。

### ⑥ `ChartGetDouble` 惰性求值（2 次查询 → 常态 0 次）

`dashStep` 只在 `g_curATR <= 0.0` 时作为标签偏移兜底，原来无条件每帧取两次：

```mql5
if(g_curATR <= 0.0)
{
   double dashStep = (ChartGetDouble(0, CHART_PRICE_MAX) - ChartGetDouble(0, CHART_PRICE_MIN)) * 0.01;
   if(dashStep <= 0.0) dashStep = _Point * 50.0;
   labelPrice = (dir == DIR_UP) ? base + dashStep : base - dashStep;
}
```

> MQL5 **没有短路求值**，所以必须用 `if` 包住，不能写成
> `g_curATR <= 0.0 ? ChartGetDouble(...) : 0` —— 那样两次调用照样发生。
> 同一件事在 §7.1 反着踩了一次坑：把**有副作用**的调用放到 `||` 右侧。

---

## 3. 预期收益（机制层面的确定性变化）

| 场景 | 优化前 | 现在 |
|---|---|---|
| 新 bar、结构无变化 | 遍历全部节点/事件做内存比较 | 8 次比较后**整段跳过** + 不重绘 |
| 新 bar、结构有变化 | 全量调和 + 重绘 | 仅变化项写入 + 重绘 |
| 每 tick（同 bar，端点未越阈） | 扫 `InpAnalysisWindow` 根 + 全图重绘 | 3 次比较 |
| `ComputeStructure` 额外分配 | 2 × rates_total 清零 | 2 × (窗口+1) |
| 每帧的 `ChartGetDouble` | 恒定 2 次 | 仅 ATR 兜底时 |
| 回收段成员判定 | O(total × kept) 字符串比较 | O(total) 哈希探测 |

**不给"快 N 倍"的数字** —— 没有实测的倍数就是编的。倍数取决于 tick 频率、
图表 bar 数、结构稳定度。

---

## 4. 回收段门控的正确性说明

外部手动删除本指标对象的情况：删除后该对象名会重新出现在期望集合里 →
下次 `needDraw` 帧的 upsert 会重新创建它（`ObjectFind` 找不到 → `ObjectCreate`）。
所以回收段门控不会造成"删掉的对象永不恢复"。

---

## 5. `ObjectsTotal()` 全表扫描：初版判断是错的

MQL5 官方文档 `ObjectsTotal()` 页面明确写着：

> When this function is used on the current chart, **this chart is accessed directly**,
> while in order to receive the properties of an object on a *different* chart,
> a synchronous call is used.

即：**当前图表上 `ObjectsTotal()` / `ObjectName()` 是直接访问**。初版把它列为
"偏慢、建议不动"是基于错误前提。

正确的成本拆解：

| 部分 | 成本 |
|---|---|
| `ObjectsTotal(0)` | 直接访问，O(1) |
| `ObjectName(0, i)` × total | 直接访问，每次 O(1) |
| `StringFind` × total | 脚本侧字符串前缀比较 |
| `SceneHas(nm)` × total | 脚本侧 **O(1)** 哈希探测（原为 O(kept) 线性查表） |

**结论**：这段接近最优。而且它体现「以图表为唯一真相源」这一设计 ——
一旦改成脚本自维护对象名账本，就引入"账本与图表不一致时删不掉/重复建"的
新故障模式，不值得。

---

## 6. 被回滚的路线：对象属性镜像缓存（反面教材）

初版新增 `GfxMirror g_mirror[]` 镜像保存"上次写入"的属性值，期望把无变化帧的
对象接触降到 0。**实测结果：镜像被压成 1 格，除第一个外的结构线全部建不出来。**

失败原因是双重的：

1. **前提不成立** —— `ObjectGet*` 在当前图表上是直接访问，镜像本来就省不下什么；
2. **引入的复杂度换来了 bug** —— 槽位分配 + 活跃区 + 压缩（`GfxPrune`）
   三者互相耦合，任何一处水位线算错就表现为"对象静默消失"。

代码里保留了一段说明（`RenderScene` 上方的注释块），提醒后人不要再走这条路。
**性能靠"少进循环"，不靠"缓存对象"。**

---

## 7. 两个致命 bug（都不是性能问题，都是"不报错的错误"）

这两个 bug 的表现完全相同：**结构线与 BOS/MSS 标注完全不显示**，
但编译 0 error / 0 warning，日志正常，对象坐标、颜色、宽度读回来全对。

### 7.1 `changed = changed || Upsert*(...)`：`||` 短路吃掉所有绘制

7 处调和调用初版写成 `changed = changed || UpsertLine(...)`。MQL5 的 `||`
**短路求值** —— `changed` 一旦为真，后续所有 `Upsert*` 都不再执行。

于是**只有第一个对象被创建**。诊断日志给出了铁证：

```
TradFi_DBG ... drawn=2367 ... chartObjs=1 | up=0 cr=0
```

分析层完全正确（2367 节点 / 1463 盒 / 670 MSS / 765 BOS），
渲染层一个都没建。

**修法**：全部改为 `if(Upsert*()) changed = true;` —— 无条件求值，再合并布尔结果。

> 这正是初版 §2 ⑤「把 `|=` 改成 `||`」引入的。`|=` 语义脏但**不短路**，
> 所以原写法反而是对的。改成 `||` 是"为了语义干净"制造出来的致命回归。

### 7.2 数组方向：本终端交给 `OnCalculate` 的**不是**时序数组

代码第 46 行的注释写「MQL5 时序列索引 0 = 最新」，全文件（`analysisStart`、
`validBars` 构建、`nodes` 顺序、渲染窗口裁剪、实时腿扫描）都按这个写。
**但本终端实测相反**：`index 0 = 最旧`。

诊断铁证（修复前）：

```
TradFi_GEO time[0]=2024.04.08 00:00  time[barLast=3]=2024.04.08 03:00
           time[barFirst=14815]=2026.08.25 09:00   (rates_total=15317)
```

`time[0]` 是 2024 年、`time[rates_total-1]` 是 2026 年 → **非时序**。

两个致命后果：

1. `analysisStart = rates_total - InpAnalysisWindow` 在非时序语义下取到 14817，
   随后 `for(i = analysisStart-1; i >= 0; i--)` 一路走向 index 0，
   **实际分析的是"最老的那 14800 根"**，把最近 500 根完全排除；
2. 于是 `nodes[0].bar = 14815`（2026.08.25）就是**最新的结构点**，
   而图表右端显示的是 2026.09.14~09.23 ——
   **2369 个对象坐标全部正确，却整体落在可视区左侧之外**。

这就是"对象建出来了却看不见"的真正机制：不是没画，是画在了屏幕外。

**修法**：

```mql5
ArraySetAsSeries(time,  true);
ArraySetAsSeries(open,  true);
ArraySetAsSeries(high,  true);
ArraySetAsSeries(low,   true);
ArraySetAsSeries(close, true);
```

并在 `ComputeStructure` 里把窗口起点从 `rates_total - InpAnalysisWindow`
改为 `InpAnalysisWindow - 1` —— 时序语义下「最近 W 根」就是下标 `[0, W-1]`，
最旧 bar 的下标是 `W-1`，随后 `validBars` 从 `W-1` 递减到 0，正好得到"旧 → 新"。

**修复后实测**（`InpWindow=200`、`InpAnalysisWindow=500`）：

```
STRUCT_ORIENT time[0]=2026.09.23 06:00 time[rates_total-1]=2024.04.08 00:00 -> SERIES(0=newest)
TradFi_DBG  nValid=322 | nodes=69 nBox=51 MSS=21 BOS=13 lastBar=8
            | drawn=69 oldestVis=37 set=53 chartObjs=53 | nd=1
TradFi_GEO  n=69 barFirst=498 barLast=8 time[barFirst]=2026.08.25 12:00 time[barLast]=2026.09.22 22:00
TradFi_GEO  tail[67] Seg_11_8 t1=2026.09.22 19:00 p1=1.14286 t2=2026.09.22 22:00 p2=1.14545 clr=13616441
TradFi_VIEW EURUSD.ct PERIOD_H1 firstVis=82 visBars=83 -> bars[0..82]
            times[2026.09.17 20:00 .. 2026.09.23 06:00] price[1.14190..1.14980] scale=4
```

`oldestVis=37` = bar 199 之前的节点被 200 根绘制窗口正确裁掉；
`Seg_11_8` 落在可视区正中间。**图表上结构线与 BOS/MSS 标注正常显示（已确认）。**

**教训**：凡涉及数组方向的代码，一律显式 `ArraySetAsSeries`，不要依赖默认值。
"方向反了"不会报错，只会让结果整体错位。

---

## 8. 诊断开关

`InpDebugShowRef = true`（默认 `false`，关闭时零成本）时会输出：

| 前缀 | 内容 |
|---|---|
| `STRUCT_ORIENT` | 数组方向自检（`SERIES(0=newest)` / `NON-SERIES(0=oldest)`） |
| `TradFi_DBG` | 分析层各过滤环节通过数 + 渲染层状态（节点/盒/事件/窗口/对象数/`needDraw`） |
| `TradFi_GEO` | 首尾节点 bar 与时间、首尾 3 段对象的真实回读坐标 |
| `TradFi_VIEW` | 图表可视 bar 区间/时间区间/价格区间 + 落在视口内的结构线计数 |

`TradFi_VIEW` 的 `inTimeView` / `inPriceView` 是判定"对象建出来了但看不见"
这一症状的关键 —— 若 `inTimeView > 0` 却仍看不见，问题在重绘/图层而非坐标；
若 `= 0`，就是坐标整体落在视口外（本次 bug 即此类）。

---

## 9. 没做的事（及原因）

- **`ObjectMove` 合并**：更新一条线是两个锚点各一次 `ObjectMove`。
  换成 `ObjectSetInteger(OBJPROP_TIME, idx)` + `ObjectSetDouble(OBJPROP_PRICE, idx)`
  仍是两次调用，净收益 0；MQL5 没有"一次设时间+价格"的合并接口。
- **增量 swing 检测**：fractal swing 的确认会**回溯性改变**尾部节点，
  天真的"只算新增 bar"是错的。要正确做增量得维护可回滚的状态栈，
  复杂度远高于收益。
- **`InpMaxEvents` / `InpMaxSeg` 的绘制裁剪**：与性能无关，是显示策略。
