# TradFi_Structure 验收 Runbook（阶段 16–19 + closure 修复）

> **这份文档只有一个用途**：把"重挂一次指标 → 我读日志/CSV → 逐条给结论"这条链路
> 压缩成**一页可执行清单**。此前验收步骤散落在
> `docs/plans/2026-09-23-TTrades-alignment.md` 的 §32.6 / §35.6 / §37.3 / §40.4，
> 一页看全反而做不到，于是每次重挂都可能漏掉某一条判据。

---

## 0. 为什么还需要验收

四个功能（IC-CISD、HTF 蜡烛、C2/C3 closure、目标投影）**已全部编码并编译部署**，
其中阶段 18a 已在 2026-09-24 的真机导出上验收过一轮，**并因此抓出一个真 bug**
（closure 跨帧累加，见 plan §35.2）。但：

| 功能 | 运行时证据 |
|---|---|
| ① IC-CISD | **无** —— 纯渲染，既不进 CSV 也不打日志（首轮导出的 build 是 s18，日志无痕迹） |
| ② HTF 蜡烛 | **无** —— 同上 |
| ③ C2/C3 closure | ✅ 设计已验证（三种子类型都真实出现）；**修复后的版本未经真机确认** |
| ④ 目标投影 | **无** —— 首轮导出跑的 s18 **不含**阶段 19 代码 |

另外 `closure` 累加那个 bug 在 MT5 上**仍在持续**（截至 14:12:35 已到 `closure=289`，
每根 M5 净增"当帧节点数"）。**重挂的首要理由是止血，其次才是验收。**

---

## 1. 怎么挂

- 构建：`v1.50-s23`（或当时最新；以日志里的 `build=` 为准）
- 品种/周期：**任选**（旧基线是 XAUUSD.ct M5 与 EURUSD.ct H1，沿用任一个便于对照）
- 必开开关：
  - `InpDebugShowRef = true`（否则拿不到 `TradFi_RENDER` / `TradFi_CLOSURE` 等自检行）
  - `InpDumpEvents = true`（否则不导出 CSV）
- 其余保持默认即可。

> ⚠️ `TradFi_INVARIANT VIOLATED` 那一行**不受 `InpDebugShowRef` 控制** ——
> 不变量被破坏时一定会出现（`v1.50-s21` 起）。若看到它，说明闭包又开始累加了。

---

## 2. 挂上后，先看图上三件事

| 看什么 | 期望 |
|---|---|
| **HTF 蜡烛** | 在 K 线**之下**叠着 4 根 H4 蜡烛（实体 + 上下影线 + 每根下方一个时间标签） |
| **IC-CISD** | 出现 CISD 条件时，**最右边那根未收盘 bar** 上出现亮紫 `IC-CISD` **点线**；若已走过高周期 K 线 60% 时间则显示 `IC-CISD (late)` 并转暗 |
| **C2 / C3 标签** | 在 swing 极值外侧；C3 可能带后缀 `C3+`（C4 守住 C3 的 EQ）/ `C3-`（已破）/ 无后缀（C4 未出现） |

**最容易判断"是不是死的"的一条**：`C2` / `C3` / `C2-CONT` 三种标签**都要出现过**。
只看到 `C2` 就说明 C3 分支成了死代码。

---

## 3. 要发我的两行日志

在 MT5 的「专家」标签页里找这两行（每根 bar 各打一次）：

```
TradFi_CLOSURE nodes=… closure=… c2rev=… c3=… c2cont=… c4ok=… c4broke=… c4pending=… invariant=OK
TradFi_RENDER  icValid=… icLevel=… icRefBar=… icLate=… icHits=… | tgtCount=… fibValid=… | objs total=… IC=… HTF=… TGT=… FIB=… CloLbl=… C3EQ=…
```

### 它们各自证明什么

| 字段 | 判据 | 若不符说明什么 |
|---|---|---|
| `invariant=OK` | **必须**是 `OK` | `VIOLATED` ⇒ closure 又跨帧累加了（`closure > nodes`） |
| `closure ≤ nodes` | **必须**成立 | 同上；这是那个 bug 的硬不变量 |
| `c4ok + c4broke + c4pending == c3` | **必须**成立 | `EvalC4Half` 的计数逻辑有洞 |
| `c4pending` | 应为 **0 或 1** | 远大于 1 ⇒ `EvalC4Half` 的 C4 取根写错了 |
| `c3` / `c2cont` | **都不应为 0** | 任一恒为 0 ⇒ 该分支是死代码（v1.49-s15 的死门控就是这么漏的） |
| `HTF` | `= InpCandleCount × (3 + 时间标签?1:0)`，默认 **16** | 不符 ⇒ HTF 蜡烛没画出来或对象没注册 |
| `TGT` | `= 2 × tgtCount` | 不符 ⇒ 目标线或标签缺一个 |
| `FIB` | `= 2 × 水平条数`（默认 5 条 → **10**） | 不符 ⇒ `InpFibLegs` 解析或渲染有问题 |
| `IC` | **0 或 2** | 3+ ⇒ 预览对象泄漏；恒为 0 且图上也没有 ⇒ IC-CISD 没成立 |
| `icValid` | 0 / 1 / -1 | 非 0 时 `icLevel` 应等于某个在武装中的 CISD 位 |
| **`icHits`** | **> 0 即证明 IC-CISD 真的触发过** | 恒为 0 ⇒ 该功能从未走到（注意：`icValid` 逐帧采样**会漏掉** bar 内触发又消失的情况，故以 `icHits` 为准） |

---

## 4. 可选：A/B 对照（证明"纯渲染改动没碰判定层"）

同一构建、同一图表，只改开关，各重挂一次并各导出一次：

- **A**：`InpShowEarlyCISD` + `InpShowHTFCandles` + `InpShowClosures` **全开**
- **B**：三个**全关**

**判据：两份 CSV 从 `seq,` 行起全部数据行必须逐字相同**，只允许头部
`# render …` 那一行不同。只要 IC-CISD 或 closure 检测漏进了判定层，A 与 B 必然分叉。

> 这正是关闭开关的意义：**它把"有没有副作用"变成一个可以直接对比的量**。

---

## 5. CSV 怎么读

- 位置：`MQL5\Files\Structure_events_<品种>_<周期>.csv`（每次全量重算**覆盖**）
- 编码 **UTF-8 无 BOM** ⇒ PowerShell 读必须带 `-Encoding UTF8`（硬约定 6）
- `type` 列现有 7 种：`MSS` / `BOS` / `CISD` / `SWEEP` / `FVG` / `OB` / `CLOSURE`
- `CLOSURE` 行的 `state` 列：`C2-REV` / `C2-CONT` / `C3` / `C3+C4-OK` / `C3-C4-BROKE`
- 头部自带**构建指纹 + 全部参数 + 自定口径**，是判断"两份归档是否同一口径"的唯一依据

---

## 6. 已知的、**不需要**再报的边界

这些是**已记录的刻意选择**，不是缺陷（详见 plan §38 保真度矩阵）：

- C3 只做"实体"版，未做"连区间一起越过"的更严版
- "engulfs it" 的字面（C3 实体完全包住 C2 实体）未作为必要条件
- C1/C3 取**物理相邻** K 线，非"有效 bar 序列"
- 投影水平表的符号是**用户可配置**的（`InpFibLegs`），默认值与他的表**不一致**
- **closure + POI 门禁未实现**（18b）：它改变全部下游结构，性质同 v1.49-s11，
  **按仓库流程需要先由用户裁定**，不能擅自做。
  → **决策提案见 plan §43**：已用真实导出量化影响面（closure 门禁 −21%；
  closure+POI 门禁 −55%，且**实测**同样说得通的口径下存活率跨 31%~100%），
  并列了 A/B/C/D 四个选项与我的建议（先做 closure 那半边）。
- 按腿长的期望表、2R/执行层：前者阈值纯自定，后者已声明属执行层不做
