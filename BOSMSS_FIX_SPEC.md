# BOS/MSS 绑定修复说明（v1.35 已执行，v1.36 审计重构）

> ## ⚠️ 历史文档 —— 已冻结，不反映当前口径
>
> 本文记录 **v1.31 – v1.39** 期间 BOS/MSS 绑定问题的修复过程与当时的约定，作为历史存档保留。
>
> **v1.48 起，事件口径已对齐 TTrades 并发生实质变更**，本文以下内容**不再是当前行为的描述**：
>
> | 本文的约定 | 现状（v1.48+） |
> |---|---|
> | 逆势破位即标 `MSS` | `MSS` 还须过**位移判据**（实体 / 穿越深度 / 时效三条） |
> | 默认影线/触及即确认 | **默认收盘确认**（`InpCloseConfirm=true`） |
> | 只有 BOS / MSS 两类事件 | 另有 **CISD**（造势序列起点的开盘价）与 **SWEEP**（扫荡）两类 |
> | 无层级概念 | 摆动点分 `short` / `intermediate`（见 `CONTEXT.md` 的「摆动分级」） |
> | 无 HTF 概念 | 有 **HTF 偏置门禁**：与偏置逆向的事件被弱化 |
>
> **当前口径的权威来源**：
> - 术语与架构约定 → `CONTEXT.md`
> - 与 TTrades 的逐条对齐、验收数据、被推翻的假设 → `docs/plans/2026-09-23-TTrades-alignment.md`
> - 他的一手原文与配图 → `docs/research/2026-09-23-TTrades-structure.md`、`docs/research/img/`
> - 逐版本事件基线（可 diff）→ `docs/baselines/`

> 目标：BOS/MSS 必须严格绑定"被突破的 ZigZag 已确认极值点"。以下每条后标注完成状态。

## 一、BOS/MSS 只基于 ZigZag 已确认极值点 ✅（v1.31–v1.35 已落实）
- 本指标的状态机基准 refHigh/refLow 即为 lastSwingHigh/lastSwingLow（随趋势互换）：
  - ST_UP ：refHigh = 已确认 HH（突破它 → BOS-up）；refLow = 已确认 HL（跌破它 → MSS-down）
  - ST_DOWN：refLow = 已确认 LL（跌破它 → BOS-down）；refHigh = 已确认 LH（升破它 → MSS-up）
- ref 更新纪律：LH/HL 仅在"实际成为结构节点"时更新；HH/LL 仅在确认突破后更新
  → ref 恒为 g_result.nodes[] 中真实存在的节点价格，绝不用 high[i]/low[i]/fractal。

## 二、水平线价格 = 被突破极值价格 ✅（v1.33–v1.34）
- 渲染：UpsertLine(time[refBar], refPrice, time[breakBar], refPrice)
- linePrice 恒取 ref（StructureEvent.ref），起点恒取 refBar（创建时 FindBrokenNodeBar 反查）。

## 三、状态机语义 + MSS 立即切向 ✅（v1.31）
- UP 中跌破 lastSwingLow → AddMSSResult(DIR_DOWN) + st.state=ST_DOWN
- DOWN 中升破 lastSwingHigh → AddMSSResult(DIR_UP) + st.state=ST_UP
- BOS/MSS 命名一律按当前趋势状态判断，不按突破方向直名。

## 四、先判突破、后更新 swing ✅（v1.32 重写保证）
- F 段顺序：AddMSSResult/AddBOSResult（用旧基准）→ 再 st.refHigh=... 更新 → 再 AddNodeFiltered。
- HandleBreakEvent 同序。

## 五、每个 BOS/MSS 只触发一次 ✅（等效实现）
- 触发即更新基准/切换状态（等价 broken=true），同一极值不会二次标注。
- 同 bar 互斥（section C / handled→continue）保证不重复。

## 六、线段起止点标准 ✅（v1.34 默认 LINE_END_BREAK）
- 起点 = 被突破 swing bar；终点 = 突破 bar；价格 = 被突破 swing 价。
- 延伸模式（FIRST_RETEST/FIXED_BARS/NEXT_NODE）保留为可选，价格恒不变。

## 七、标签可偏移、线不偏移 ✅（v1.34）
- 标签：time[breakBar]，UP → refPrice+ATR*0.15，DOWN → refPrice-ATR*0.15。
- 线严格在 refPrice。

## 八、大跌后 BOS 语义复核 ✅（已复核）
- UP 中跌破 HL → MSS-down（不是 BOS）；DOWN 中跌破 LL → BOS-down。
- box/outside 事件同样走状态机：ST_UP 破母线低 → 检查跌破 HL 才 MSS。

## 九、有效 swing 过滤 ✅（v1.35 补最小间隔；其余既有）
- 新增 InpMinBarsBetweenSwings=2：与上一 swing 节点间隔 >= N 根。
- 其余复用：InpMinSwingAmplitude（点数）、IsValidRetrace（Points+ATR+Ratio，AND）、
  主/内部结构门槛（InpMainFilterATR/InpMainFilterRatio）。

## 十、调试显示 ✅（v1.35 新增）
- InpDebugShowRef=true 时标签显示 "BOS #<refBar> <refPrice>" / "MSS #<refBar> <refPrice>"。
- 验收：每个 BOS/MSS 都能反查到一个已确认 ZigZag 极值点（refBar/ref 字段在 StructureEvent 中常存）。

## 验收标准对照
1. 水平线落在 ZigZag 极值价格 ✅  2. 线从极值点起到突破 K ✅  3. 标签偏移、线不偏移 ✅
4. UP 破低 = MSS ✅  5. DOWN 破高 = MSS ✅  6. MSS 后立即切向 ✅
7. 同点只触发一次 ✅  8. CheckBreak 先于 UpdateSwing ✅
---

## 十一、审查重构（v1.36，逐条落实）✅

> 依据外部审查 6 项最优先问题重构状态机；编译 0 errors / 0 warnings。

1. **修复 InpMinBarsBetweenSwings 方向 bug（真 bug，结构线消失直接根因）** ✅
   - 原 i - lastNodeBar：MQL5 新 bar 索引小、旧节点索引大 → 恒为负 → 种子后所有 swing 全被过滤 → 结构线只剩种子点（“结构线没了”）。
   - 改为 lastNodeBar - i（旧-新，符合遍历方向）。
2. **SState 重构为 RefPoint{bar, price, valid, broken}** ✅
   - 移除 refHigh/refLow 纯价格 + hasHigh/hasLow；ref 直接保存结构位 bar + 价格。
   - AddBOSResult/AddMSSResult 直接取 ref.bar，不再 FindBrokenNodeBar 反查（后者仅作 InpDebugShowRef 校验 Print）。
3. **HandleBreakEvent 不再制造主结构节点** ✅
   - 删除 AddNodeFiltered(i, high[i]/low[i])；结构节点只由确认 swing（F 段）添加。
   - 事件只负责：检测突破 ref → 标 BOS/MSS → 置 broken → MSS 立即切向。
4. **突破检测与 swing 更新彻底拆分** ✅
   - A2 CheckBreakAgainstRefs(i)：每根有效 bar 独立检测突破 refHigh/refLow（不依赖 swing 确认），不遗漏非 swing bar 上的突破。
   - F UpdateRefsFromSwing：仅在确认 swing 成为节点后更新 ref（HH/HL/LL/LH 语义保留）。
5. **broken 标记防重复触发** ✅
   - 突破后仅置 broken=true，**不立即把 ref 更新成当前 K 线极值**；等确认 swing 才更新 → BOS/MSS 恒绑定已确认折线极值点。
6. **实时腿起点固定** ✅
   - 起点 = 最后确认结构点（不再移动到未确认同向更极端点）；终点 = 之后的反向极值。

**连带调整**：主/内部结构不再阻断结构推进（内部 swing 也进结构线，isMain 仅影响线型：主段实线/含内部点段浅色虚线；subNodes 单独虚线绘制移除）；对象 ID 改 MSS_<refBar>_<eventBar> / BOS_<refBar>_<eventBar>；LineEnd 默认仍 LINE_END_BREAK。FindBrokenNodeBar 保留为 debug 校验。ATR 数组化（可选优化）本轮未做。TradFi_Structure.mq5 → v1.36，编译 0/0。

---

## 十二、v1.37 简化（BOS/MSS 单一触发源）✅

> 编译 0 errors / 0 warnings。

1. **CheckBreakAgainstRefs 为唯一 BOS/MSS 触发源** ✅
   - 内包盒/外包事件不再独立触发（HandleBreakEvent 整段删除）；盒区间仅用于矩形绘制（g_result.box 构建阶段已填充）。
2. **A2 互斥（同一根 K 只一个事件，MSS 优先）** ✅
   - 同时上破+下破（外包形态）时只取 MSS（反转优先），BOS 不标。
3. **MSS 后重置对侧 ref** ✅
   - bearish MSS（UP→DOWN）：st.refHigh.valid=false；bullish MSS（DOWN→UP）：st.refLow.valid=false。
   - 旧趋势 ref 不再参与新趋势判断。
4. **内部结构不驱动 BOS/MSS ref** ✅
   - isMainSwing=false 的 swing 仍进结构线（虚线），但只有 isMainSwing==true 才 UpdateRefsFromSwing。
5. **同类型节点替换同步 ref** ✅
   - AddNodeFiltered 替换时若被替换节点 bar == st.refHigh.bar / st.refLow.bar，同步更新 ref 的 bar/price。
6. **InpMinBarsBetweenSwings 用 MathAbs(lastNodeBar - i)** ✅
7. **对象 ID 保留 MSS_<refBar>_<eventBar> / BOS_<refBar>_<eventBar>** ✅（v1.36 已改）
8. **Debug 强制打印（InpDebugShowRef=true）** ✅
   - AddMSSResult/AddBOSResult 输出：type、dir、breakBar、refBar、refPrice、trend、bind（refBar 反查一致 → OK / MISMATCH）。

TradFi_Structure.mq5 → v1.37，编译 0/0。
