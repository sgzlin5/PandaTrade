# Structure.mq5 代码审查（v1.47 通读 + v1.48 订正）

> 审查对象：`Indictor/Structure.mq5`（**v1.47 静态通读，1378 行**）
> 方法：静态通读 + 对照 `CONTEXT.md` / `BOSMSS_FIX_SPEC.md` 声明的口径
> **本文所有行号以 v1.47 为准**；v1.48 改动后行号已失效，需要时请按函数名检索。

---

## 0. 订正记录（v1.48 之后补，请先读这一段）

初版审查写于**未能编译验证**的阶段（当时沙箱拒绝执行脚本）。后来编译链路打通并
在实盘图表上跑通，暴露出初版的若干结论需要更正：

| 初版内容 | 订正 |
|---|---|
| 「**未能实际编译**，无法确认 `.ex5` 是否对应当前 `.mq5`」 | 已具备完整链路：`MetaEditor64.exe /compile:` + 部署到终端 `MQL5\Indicators\` + 读 `MQL5\logs\`。当前状态 **0 errors / 0 warnings**，已在 EURUSD.ct H1 上运行验证。 |
| 「轻微 1：`CalcATRSeries` 尾部未赋值」（建议 `ArrayResize(atrArr, analysisStart + 1)`） | **已在 v1.48 修掉**，就是按这个建议改的。`validBars` 同样改为按窗口分配。 |
| 「观察 1：分析窗口横移会让历史 swing 消失 …… 这是换取 O(n) 性能的**主动取舍**，不算 bug」 | **定性错误。**它根本不是"窗口横移的设计取舍"，而是**数组方向 bug** 的症状。详见 §0.1。 |
| 未提及 | v1.48 期间**引入并修复了两个致命 bug**，表现都是"结构线完全不显示"。详见 §0.1、§0.2。 |

### 0.1 v1.48 致命 bug ①：数组方向反了（初版观察 1 的真正成因）

初版观察 1 说 `analysisStart = rates_total - InpAnalysisWindow`，
并把它理解为"分析窗口在最老那一侧"的取舍。**真实情况是：代码假设
`index 0 = 最新`，而本终端交给 `OnCalculate` 的数组是 `index 0 = 最旧`。**

诊断铁证（修复前，`rates_total = 15317`）：

```
TradFi_GEO time[0]=2024.04.08 00:00   time[barLast=3]=2024.04.08 03:00
           time[barFirst=14815]=2026.08.25 09:00
```

`time[0]` 是 2024 年、`time[rates_total-1]` 是 2026 年 → 非时序。

后果有两层：

1. `analysisStart = rates_total - InpAnalysisWindow` 在非时序语义下取到 14817，
   随后 `for(i = analysisStart-1; i >= 0; i--)` 走向 index 0，
   **实际分析的是最老的那 14800 根**，最近 500 根被完全排除；
2. `nodes[0].bar = 14815`（2026.08.25）成了**最新结构点**，而图表右端是
   2026.09.14~09.23 —— 2369 个对象**坐标全对但整体在可视区左侧之外**。

所以"历史 swing 随窗口横移而变"这个观察的表象是对的，成因判错了：
它不是取舍，是方向反了导致分析区间落在错误的一端。

**修法**：`OnCalculate` 入口显式 `ArraySetAsSeries(time/open/high/low/close, true)`，
`analysisStart` 改为 `InpAnalysisWindow - 1`。修复后 `STRUCT_ORIENT` 输出
`SERIES(0=newest)`，`nodes=69 / MSS=21 / BOS=13` 且结构线正常显示。

> 这条同时也是对初版「附：已确认正确的关键机制」的警告：
> 那些机制的**内部逻辑**确实是对的，但它们全都建立在"数组是时序"这个
> **未经检验的前提**上。前提错了，机制再对也不显示。

### 0.2 v1.48 致命 bug ②：`changed = changed || Upsert*(...)` 短路

v1.48 的一轮"语义清理"把 7 处 `changed |= Upsert*(...)` 改成
`changed = changed || Upsert*(...)`。MQL5 的 `||` **短路求值**：
`changed` 一旦为真，右侧 `Upsert*` 不再执行 → **只有第一个对象被创建**。

```
TradFi_DBG ... drawn=2367 ... chartObjs=1 | up=0 cr=0
```

分析层完全正确（2367 节点 / 1463 盒 / 670 MSS / 765 BOS），渲染层一个都没建。

**修法**：全部改为 `if(Upsert*()) changed = true;`。

> 注意「轻微 2」（Wilder 播种区把原始 TR 当 ATR）与「不一致」（OR vs AND 语义）
> 两条结论**经 v1.48 复核仍然成立**，未受订正影响。

---

## 结论摘要

**分析层没有发现严重缺陷。** 结构状态机、突破检测、ref 绑定纪律都与文档声明一致，
`BOSMSS_FIX_SPEC.md` 里 v1.35→v1.37 的各项修复都能在代码中找到对应实现。

发现 2 个真实的轻微问题（ATR 尾部未初始化、Wilder 播种区口径）、
1 处代码与文档不一致、若干观察项。

> **更正记录**：初版审查曾把「对象回收失效 / 图表持续累积残留线」列为严重问题，
> 并据此判定 `InpMaxEvents` 从未生效。**该结论是错的**，已撤回，详见文末附录。

---

## 轻微 1：`CalcATRSeries` 只初始化窗口内数组，尾部未赋值 —— **v1.48 已修**

**位置**：v1.47 L439 + L443-453

```mql5
ArrayResize(atrArr, rates_total);          // 全长分配
for(int i = analysisStart; i >= 0; i--)    // 只填 [0, analysisStart]
```

`analysisStart + 1 .. rates_total - 1` 这些槽位**从未赋值**。
`ArrayResize` 对数值数组填充 0.0，所以不是未定义行为，但语义上是「无效」而非「ATR = 0」。

**当前无实害**（这点值得一提，因为初版审查在此处也判错了方向）：
`atrArr[i]` 的读取点只有三处，全部落在窗口内 ——

- L815 / L820：`i` 来自 `validBars[k]`，而 `validBars[]` 只由 `[0, analysisStart]` 区间构建；
- L833：同上；
- L744：读 `atrArr[0]`，`0 <= analysisStart`。

所以未被赋值的尾部**不会被读到**。

**但它是陷阱**：任何未来新增的「读某个 ref bar 的 ATR」逻辑会拿到 0，
而 L493 的 `atrOk = (... || atrValue <= 0.0 || ...)` 在 ATR 为 0 时**无条件放行**，
失效方向是「过滤悄悄失效」，不报错、不崩溃，最难排查。

**修法**：`ArrayResize(atrArr, analysisStart + 1)`。 → **v1.48 已照此修改。**
（`validBars` 也一并改为按窗口分配。）

---

## 轻微 2：Wilder 播种区把原始 TR 当 ATR 使用（**v1.48 复核仍成立**）

**位置**：L455-458（取种子）、L462-466（递推起点）、L468（回写）

种子 = 最旧 `n` 根 TR 的简单均值，覆盖下标 `[seedEnd, analysisStart]`；
递推从 `seedEnd - 1` 开始向新 bar 方向走。
于是下标 `seedEnd + 1 .. analysisStart` 这一段**始终保持 TR 原值**，从未被平滑，
而它们随后被 `IsValidRetrace(leg, atrArr[i], ...)` 当作 ATR 使用。

TR 通常大于 ATR，所以这一段的门槛被**高估 → 该区间内的 swing 更容易被误滤**。

**影响量级**：`n = InpATRPeriod = 14`，默认 `InpAnalysisWindow = 500` 时，
只有最旧约 12 根受影响，且这些 bar 离当前很远，基本无关紧要。

**但 `InpAnalysisWindow` 调小后会放大**：`InpAnalysisWindow = 20` 时
`seedEnd = max(0, 20-13) = 7`，受影响区间 8..20 **占了窗口的 62%**，
此时过滤行为会与默认参数下明显不一致。

> v1.48 补充：数组方向修正后，`analysisStart` 的含义变了
> （从"最老那段历史的起点"变成"最近 W 根里最旧那根的下标"＝ `W-1`），
> 但"播种区保持 TR 原值"这个缺陷本身**不受影响，依然存在**。

**判据**：同一段行情，`InpAnalysisWindow = 20` 与 `= 500` 对比结构点数量，
若短窗口下明显更少，即是此处。

---

## 不一致：`InpMinRetraceATR` / `InpMinRetraceRatio` 是 OR 语义，但 `CONTEXT.md` 写的是 AND

**位置**：L492-498

代码实现 `点数 AND (ATR OR Ratio)`，代码注释 L475-476 也如实写了
「放宽 AND 为 点数 AND (ATR OR Ratio)，避免过严滤除有效结构点」。

但 `CONTEXT.md` 的「有效回撤过滤」条目写的是：

> 回撤腿须**同时**满足 最小点数 / ATR 倍数 / 前一段幅度比例（AND 语义，任一未过即无效）

**代码是对的，文档没跟着 v1.35 改。** 风险在于后人按 CONTEXT.md 的 AND 去"修"这个 OR。

**修法**：改 `CONTEXT.md`。零风险，建议直接做。

---

## 观察（非缺陷，但使用者应知道）

### 1. 分析窗口横移会让历史 swing 消失，历史 BOS/MSS 随之重绘

> **【订正】本条的成因在初版里判错了。** `analysisStart = rates_total - InpAnalysisWindow`
> 不是"窗口横移的设计取舍"，而是**数组方向 bug** 的一部分（详见 §0.1）。
> v1.48 已修为 `InpAnalysisWindow - 1`。

订正后本条仍然保留一部分成立性：`ComputeStructure` 每次全量重算，
窗口横移后 `validBars[0]` 变成新的最旧 bar，其之前的节点不再存在，
**左侧历史结构线与历史 BOS/MSS 会随窗口横移而变化**。
这是换取 O(n) 性能的主动取舍，不是 bug，但"结构标记"类指标使用者通常默认
历史是稳定的。建议在 README 参数表里对 `InpAnalysisWindow` 加一句提示。

### 2. `prev_calculated` 声明了但从未使用

L1345-1346 的签名里有 `prev_calculated`，函数体内没有引用。
新 bar 判断走 L1359-1362 的 `static int s_lastRates`。

注释 L1358 写「用静态 bar 计数判断"新 bar"，比 prev_calculated 更可靠」——
这句站不住：两者都**不区分**「来了新 bar」与「向左滚动加载了更早的历史」
（后一种情况 `rates_total` 也会变大，会触发一次多余的全量重算）。

功能上无害（多算一次），但注释的论断不成立，建议改成如实描述：
「用 rates_total 变化近似新 bar；加载历史时会多触发一次全量重算」。

### 3. `CheckBreakAgainstRefs` 的返回值在 C 段之后已无消费者

L772 取 `evType`，实际只在 L868 用 `mssBar = (evType == 1)`。
接口可以简化为 `void` + 一个 `bool` 输出参数，或直接返回 `bool mssOnThisBar`。
当前写法不算错，只是 `int` 的 1/2 编码已经部分失去意义。

### 4. `atrValue == 0` 时标签偏移的两个兜底量纲不一致

L1232-1235：

```mql5
double labelPrice = (dir == DIR_UP) ? base + g_curATR * 0.15 : base - g_curATR * 0.15;
if(g_curATR <= 0.0) labelPrice = (dir == DIR_UP) ? base + dashStep : base - dashStep;
```

`ATR * 0.15` 与 `dashStep`（图表价格范围的 1%）量纲差别很大，
若 `g_curATR` 恰好为 0（窗口过短导致，见轻微 2），标签位置会跳一下。
有兜底不算错，但两个兜底值差一个量级，建议统一到 `dashStep` 量纲。

### 5. v1.48 新增：渲染层与数组方向相关的隐式契约

`RenderScene` / `UpdateLiveLeg` 里的每一个 `time[...]` 下标、
`nodes[].bar` 的大小比较、`beginNode` 的扫描方向，都依赖
「bar 下标越大 = 时间越旧」。这个契约此前只写在文件头注释里，没有任何强制。

v1.48 起改为在 `OnCalculate` 入口显式 `ArraySetAsSeries(..., true)`，
并在 `InpDebugShowRef=true` 时打印 `STRUCT_ORIENT` 自检行。
**这是本次事件最重要的遗产：凡涉及数组方向的假设，一律显式声明，不要依赖默认值。**

---

## 附：已确认正确的关键机制（供后人放心）

> **前提提醒**：以下机制的内部逻辑经复核正确，但它们都建立在
> 「数组是时序（`index 0 = 最新`）」这一前提上。v1.48 之前该前提**不成立**，
> 因此这些正确的机制当时也无法产生可见输出。详见 §0.1。

- **对象调和回收是「默认删除、注册才保留」**（L1112 `g_nScene=0` → L1148 `AddSceneName`
  → L1294-1304 删除未注册者）。窗口滑出（L1144 `continue`）与 `InpMaxEvents`
  过滤（L1191/L1245 `continue`）都会**跳过注册**，因而被正确回收。无泄漏。
- **`broken` 标记防重复触发**：触发即置 `broken=true`（L561/L576/L582/L610/L617/L623），
  且**不立即更新 ref**，等确认 swing 才经 `UpdateRefsFromSwing` 复位。
- **突破检测与 swing 更新彻底拆分**：A2 每根有效 bar 独立检测（L772），
  F 段仅在确认 swing 成为节点后更新 ref（L869-884）。
- **MSS 立即切向 + 重置对侧 ref**（L568-569、L582-584、L603-604、L624-625）。
- **同类型节点替换时同步 ref**（L344-366）：仅同步同类型 ref，且用 `oldBar` 比对，
  保证 ref 恒对应结构线节点。
- **`InpMinBarsBetweenSwings` 用 `MathAbs(lastNodeBar - i)`**（L786），
  v1.36 修正过的方向 bug 没有回退。

---

## 附录：初版审查的错误结论（撤回）

初版把以下两条列为「严重」，**均系误判**：

1. ~~「回收失效 → 图表持续累积残留线」~~
2. ~~「`InpMaxEvents` 实际效果与预期相反」~~

**误判原因**：我按「默认保留、标记才删除」的模型推演，便得出
「滑出窗口的对象既不注册也不删除 → 永久残留」。
实际 L1294 的回收循环是反过来的逻辑 —— `if(!InScene(nm)) ObjectDelete(...)`，
即**未注册 = 删除**。滑出窗口的对象在下一帧就被回收，`InpMaxEvents`
也严格生效。我在推演时把「不在期望集合」当成了「不处理」，
而代码里它恰恰是「删除」的**触发条件**。

**教训**：这类推导必须落到实际代码行上核对方向，不能停留在机制层的心智模型。
`CONTEXT.md` 里「调和式同步（缺失才创建、变化才更新、过期才回收）」这句
描述**强化了**误判 —— 它读起来像"过期才回收"，而实际实现是"未注册即回收"，
两者在窗口滑出场景下结论正好相反。建议把 `CONTEXT.md` 这句改为
「**默认回收、注册保留**：每帧重建期望集合，未注册的对象立即删除」。

以上两条撤回后，本文件正文的结论不受影响。

---

## 附录二：v1.48 的方法论教训

本次调试最大的收获不是修好了某个 bug，而是识别出一类**共同的失败模式**：

| 症状 | 编译 | 日志 | 对象坐标 | 真实原因 |
|---|---|---|---|---|
| 结构线完全不显示 | 0 error | 正常 | — | `\|\|` 短路，`Upsert*` 未被求值（§0.2） |
| 结构线完全不显示 | 0 error | 正常 | **全部正确** | 数组方向反了，对象落在可视区外（§0.1） |

两者都不报错。第一类只能靠**执行计数**发现（`chartObjs=1` vs `drawn=2367`），
第二类只能靠**把脚本的坐标系与图表的可视坐标系对齐**发现
（`TradFi_VIEW` 打印 `firstVis/visBars` 与 `inTimeView` 计数）。

**可复用的判据**：
- 分析层计数正确 + 渲染层对象计数为 0 → 怀疑求值顺序/短路；
- 渲染层对象计数正确 + 坐标读回正确 + 画面为空 → 怀疑坐标系/方向，
  必须比较"对象的坐标区间"与"图表可视区间"，而不是继续盯着对象本身。

`InpDebugShowRef=true` 下的 `TradFi_DBG` / `TradFi_GEO` / `TradFi_VIEW`
三行就是为这两类问题准备的固定诊断面，建议保留。
