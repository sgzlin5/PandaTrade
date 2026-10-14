//+------------------------------------------------------------------+
//|  SMC_Toolbox.mq5                                          |
//|  SMC（Smart Money Concepts）工具箱指标 — 模块化 / 可开关           |
//+------------------------------------------------------------------+
//|  定位：这是**独立于** Structure.mq5 的另一套东西，不是它的升级版。        |
//|        Structure 的口径来自 TTrades 一手文章（MSS/CISD/protected swing），|
//|        本文件的口径来自 SMC 行业通行读法（BOS/CHoCH/OB/EQH-EQL）。              |
//|        两者对"结构"的定义不同源，合并会让两套语义互相污染 → 刻意分成两个文件。   |
//|        见 docs/plans/2026-09-24-SMC-toolbox.md §1。                              |
//+------------------------------------------------------------------+
//|  ⚠️ 关于"依据"的分级（本文件严格遵守，不许含糊）：                                |
//|    · 有 ICT/TradingView 明确依据的：Killzone 时段、Premium/Discount 概念、       |
//|      枢轴对称窗口（ta.pivothigh 左右等宽）。                                     |
//|    · **无一手权威、各家实现互相冲突**的：OB 区间基准、强/弱高低点、诱导（IDM）    |
//|      的机械化判定。凡此类，代码注释与 CSV 头部都显式标注"属行业约定"。            |
//|    规则：**不得把自己的取舍写成"标准如此"**。                                     |
//+------------------------------------------------------------------+
//|  架构（五层，沿用仓库既有接缝）：                                                 |
//|    ① 分析层  ComputeSMC(...) → SMCResult                                        |
//|               纯输入原始 K 线 + 参数，输出语义记录（枢轴/事件/区间/相等位/扫荡）  |
//|               其中 AnalyzeStructure() 是**唯一**的结构状态机实现，              |
//|               本图与高周期各调一次（同一份代码，口径不可能漂移）。                |
//|    ② 结果层  SMCResult：一条记录一个 struct，消灭 bar/dir 平行数组              |
//|    ③ 场景层  RenderScene(result)：语义锚定对象 ID + 调和式同步                  |
//|               （存在才更新、缺失才创建、过期才回收），仅场景变化才 ChartRedraw   |
//|    ④ 导出层  DumpEvents(...)：CSV 自描述头 + 全类型归并，供逐行 diff            |
//|    ⑤ 性能层  InpReuseResultOnTick：同 bar tick 复用分析结果；                   |
//|               needDraw 指纹未变时整段跳过调和。                                  |
//+------------------------------------------------------------------+
//|  仓库硬约定（逐条落实，勿删注释 —— 每条都对应一次真实事故）：                      |
//|    1. OnCalculate 入口**显式** ArraySetAsSeries(x,true)。                        |
//|       教训：本终端交给指标的数组**不是**时序（实测 index 0 = 最旧）。            |
//|       后果不是报错，而是"分析的是最老那段历史、坐标全对却落在可视区外"。          |
//|    2. **禁止把有副作用的调用写在 || / && 右侧**。MQL5 的 || 会短路；             |
//|       曾因 `changed = changed || Upsert*()` 导致 2367 个对象只建出 1 个，        |
//|       且不报任何错。一律写 `if(Upsert*()) changed = true;`。                     |
//|    3. **新增可视化元素必须同步两处**：needDraw 指纹 + AddSceneName 注册。        |
//|       漏指纹 → 新元素要等下一根 bar 才出现；漏注册 → 被回收段当过期对象删掉。     |
//|    4. **每次改动递增 BUILD_TAG**；日志里的版本号只打印 BUILD_TAG，不写字面量。    |
//|       （事故：OnDeinit 曾硬编码 v1.48 而 BUILD_TAG 已到 v1.49-s14b，            |
//|        于是最能证明"加载了哪一版"的那行日志反而一直在报错版本。）                 |
//|    5. **门控必须验证条件真的可达**。事故：某门控含 `time[lastBar]==time[0]`，    |
//|       而该合取项永不成立 → 成了死代码，注释却写着"连扫描都不做"。                |
//|    6. **诊断输出不得落在每 tick 路径上**。                                        |
//+------------------------------------------------------------------+
//|  模块与依赖（M 编号见 plan §2）：                                                |
//|    M1  双层枢轴检测            — 对称窗口 + 延迟 len 根确认                       |
//|    M2  BOS / CHoCH             — 依赖 M1，两层各跑一个独立状态机                  |
//|    M3  HH/HL/LH/LL 标签        — 依赖 M1/M2，纯渲染                              |
//|    M4  订单块 OB（缓解/失效）  — 依赖 M2，每个结构事件派生一个                     |
//|    M5  FVG / IFVG              — 三根 K 线缺口 + 后验回补与反转                    |
//|    M6  EQH / EQL               — 依赖 M1，同类型枢轴聚类                          |
//|    M7  流动性扫荡 / 诱导        — 依赖 M1/M2/M6                                    |
//|    M8  Premium / Discount + EQ — 依赖 M1                                          |
//|    M9  强/弱高低点             — 依赖 M1/M2，两种口径可切换                        |
//|    M10 Killzone 时段           — 纽约时间切段 + 跳空守卫                          |
//|    M11 多周期结构叠加          — 复用 AnalyzeStructure，**纯渲染不参与判定**      |
//+------------------------------------------------------------------+

#property copyright   "PandaTrade"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// 构建指纹：每次改动递增。出现在 INIT 日志与事件 CSV 头部。
// 用途：确认 MT5 实际加载的是哪一版编译产物（文件时间戳不可靠）。
#define BUILD_TAG    "v1.00-s1"

// ⚠️ 对象前缀必须与 Structure 的 "Structure_" 不同。
//    两者的回收段都是"凡带本前缀却不在场景集里的一律删除"——
//    前缀相同会让先跑的指标把后跑的指标的对象全部删掉。
#define OBJ_PREFIX   "SMCToolbox_"

// 方向常量
#define DIR_UP       1
#define DIR_DOWN    -1

// 结构层级（M2 双层）
#define TIER_SWING     0    // 波段层：驱动主要趋势状态
#define TIER_INTERNAL  1    // 内部层：独立状态机，互不干扰

// 区间种类（M4/M5 共用 SMCZone）
#define ZONE_OB        0
#define ZONE_FVG       1

// 强/弱高低点的种别
#define SW_STRONG_HIGH 0
#define SW_WEAK_HIGH   1
#define SW_STRONG_LOW  2
#define SW_WEAK_LOW    3

//+------------------------------------------------------------------+
//|  枚举                                                            |
//+------------------------------------------------------------------+
enum ENUM_SMC_BREAK
{
   SMC_BREAK_CLOSE,   // 收盘越过（SMC 通行口径）—— 默认
   SMC_BREAK_WICK     // 影线触及（最宽松）
};

enum ENUM_SMC_OB_BASIS
{
   SMC_OB_HYBRID,     // 影线全幅 + 实体 50% 中线（LuxAlgo 点名的 "common hybrid"）—— 默认
   SMC_OB_WICK,       // 整根 high-low（LuxAlgo 词条的建议默认）
   SMC_OB_BODY        // 开盘到收盘（对齐仓库 TTrades 的"实体优先"口径）
};

enum ENUM_SMC_SWEEP_SRC
{
   SMC_SWEEP_SWING,     // 只扫波段层枢轴
   SMC_SWEEP_BOTH,      // 波段层 + 内部层 —— 默认
   SMC_SWEEP_INTERNAL   // 只扫内部层枢轴
};

// EQH/EQL 挂在哪一层。
// ⚠️ **必须可配**，因为实测（tools/smc_logic_sim.py）表明：
//    波段层枢轴的相邻同类间距中位数 =130 根，远超任何合理的"相等"窗口，
//    故挂在波段层上时 EQ 几乎恒为 0（实测 500 根窗口 0 个）；
//    内部层间距中位数 13~15 根，能正常成池。
//    → 默认挂内部层。挂波段层只在用极小 swingLen 时才有意义。
enum ENUM_SMC_EQ_TIER
{
   SMC_EQ_INTERNAL,   // 内部层枢轴 —— 默认
   SMC_EQ_SWING,      // 波段层枢轴
   SMC_EQ_BOTH        // 两层各算一次
};

// 强/弱高低点的判据。
// ⚠️⚠️ **本术语没有任何权威口径。** 实证：LuxAlgo 官方 Library 的 54 个 SMC/ICT 概念
//     与 ICTKillzone 的 115 条 ICT 术语表**都不收录** Strong/Weak High/Low；
//     它只存在于社区口语层面，且社区内部有两套**结论相反**的读法：
//       · C-1 位移质量派：制造了强反向位移/有结构支撑 = strong（会守住）
//       · C-2 流动性状态派：已被越过 = 流动性已耗 = 不再是要取的目标；未越过 = strong
//     本实现只提供这两套**有出处**的读法，不发明第三种。
//     （初版曾有个 `SMC_SW_TREND_RELATIVE`「顺趋势那侧为弱」——那是从
//      ICT 口头措辞里凭印象推的，**查不到出处，已删除**。）
enum ENUM_SMC_SW_MODE
{
   SMC_SW_SWEPT_IS_WEAK,      // C-2：已被越过 = 弱（可机械判定）—— 默认
   SMC_SW_DISPLACED_IS_STRONG // C-1：破位 K 实体过位移门槛 = 强
};

//+------------------------------------------------------------------+
//|  输入参数                                                        |
//+------------------------------------------------------------------+
input group "== 模块开关（M1~M11）=="
input bool InpShowStructure   = true;   // M2 波段层 BOS/CHoCH
input bool InpShowInternal    = true;   // M2 内部层 BOS/CHoCH（浅色细线）
input bool InpShowSwingLabels = true;   // M3 摆动点 HH/HL/LH/LL 标签
input bool InpShowOB          = true;   // M4 订单块（含缓解/失效）
input bool InpShowFVG         = true;   // M5 公允价值缺口
input bool InpShowIFVG        = true;   // M5 反转缺口（被收盘穿越后的反向用法）
input bool InpShowEQHL        = true;   // M6 等高等低（流动性池）
input bool InpShowSweep       = true;   // M7 流动性扫荡
input bool InpShowIDM         = true;   // M7 诱导（Inducement）
input bool InpShowPremDisc    = true;   // M8 Premium / Discount 区间 + EQ
input bool InpShowStrongWeak  = false;  // M9 强/弱高低点（默认关：图上标记较密）
input bool InpShowKillzone    = true;   // M10 交易时段
input bool InpShowMTF         = false;  // M11 多周期结构叠加（默认关）

input group "== M1/M2 结构检测 =="
// 默认 15 / 5（Quantum Algo 的取值），**不是** LuxAlgo SMC 的 50 / 5。
// 依据是实测而非偏好：pivot 的确认延迟 = 半窗长度，故 swingLen=50 意味着
// 枢轴要等 50 根 K 线才成立。仿真（tools/smc_logic_sim.py）测得在 500 根分析窗口内：
//   swingLen=50 → 4 个枢轴 / 1 个结构事件（图上几乎没东西）
//   swingLen=15 → 17 个枢轴 / 9 个结构事件（BOS 7 + CHoCH 2）← 可用
// 可考实现的取值范围是 3~50，全部合法；50 只适合看超大级别。
input int InpSwingLen         = 15;     // 波段层枢轴半窗（根）
input int InpInternalLen      = 5;      // 内部层枢轴半窗（根）
// 破位确认：SMC 有明确依据 —— CHoCH/BOS 用**实体收盘**，影线穿越属 sweep 不算。
// 故默认 CLOSE；WICK 档保留，但它不是 SMC 口径（是仓库另一指标 Structure 的口径）。
input ENUM_SMC_BREAK InpBreakConfirm = SMC_BREAK_CLOSE;  // 破位确认方式
// 位移门槛：破位 K 实体 ≥ 该值 × ATR 才记 strong。
// ⚠️ 与 Structure **不同**：那边位移是 MSS 的**构成条件**（不足则不翻转趋势）；
//    这里位移只影响渲染与强/弱标注，BOS/CHoCH 一律照常成立 ——
//    SMC 把 BOS 当"结构事件"而非"确认信号"，用位移去否决它会让结构线断裂。
input double InpMinDisplaceBodyATR = 0.5;   // 破位 K 实体 / ATR（0=关闭）
input int InpATRPeriod        = 14;     // ATR 周期

input group "== M4 订单块 =="
// ⚠️ **无统一口径**。LuxAlgo「Order Block Anatomy」官方原文：
//    "exactly which prices bound the zone (the full range including wicks, or bodies only)
//     … conventions genuinely differ here." / "None of this is standardized."
//    一线实现三种都活跃：全幅（Quantum）、实体（部分产品）、混合（Black Tie / ICTKillzone 教学）。
//    混合 = 实体划入场、影线极值作失效位 —— LuxAlgo 点名为 "common hybrid"。
input ENUM_SMC_OB_BASIS InpOBBasis = SMC_OB_HYBRID;  // OB 区间基准
input int  InpOBLookback      = 20;     // OB 回溯上限（根，找最后一根反向 K 线）
input int  InpOBCluster       = 3;      // 连续反向 K 线合并上限（1=只取最近一根）
input bool InpObHideInvalidated = false;// 已失效的 OB 不再绘制（默认保留，改标 Breaker）
input bool InpObHideMitigated   = false;// 已缓解的 OB 不再绘制（默认保留，仅降级配色）

input group "== M5 FVG / IFVG =="
input double InpFvgMinATR     = 0.0;    // 缺口最小高度（×ATR，0=不过滤）
// ⚠️ 默认 **false**，依据是实测：把 fillPct 定义为"形成以来最大的影线穿透深度"后，
//    仿真测得 **85% 的缺口最终都会被完全穿透**（1913/2263）。若默认隐藏，
//    等于出厂就把六分之五的检出量抹掉 —— 与仓库在 Structure 上
//    踩过的同一个坑（那边实测 85% 被默认隐藏，只剩 ~7.6% 可见）。
input bool InpFvgHideFilled   = false;  // 已被完全回补的 FVG 不再绘制
// 注：IFVG 的判定**已按权威口径写死，不设开关** ——
//     LuxAlgo 与 ICTKillzone 两家逐字一致：「实体收盘穿越整个缺口」才反转；
//     影线穿过永不算（"a wick-through alone is usually read as a probe"）；
//     CE 是**成立后的入场位**，不是判定条件。故不做"穿 CE 即反转"的宽松档。

input group "== M6 等高等低 =="
input ENUM_SMC_EQ_TIER InpEqTier = SMC_EQ_INTERNAL;  // 挂在哪一层（见枚举处实测依据）
// 容差：可考实现无官方默认值，实测范围 0.10（Black Tie）~ 0.25（Quantum）。
// 取中间偏严的 0.15，减少假 EQH/EQL。
input double InpEqToleranceATR = 0.15;  // 相等容差（×ATR；0 = 改用下面的点数）
input int    InpEqTolerancePts = 20;    // 相等容差（点数；仅当 InpEqToleranceATR=0）
input int    InpEqMaxBars      = 60;    // 两个枢轴的最大间隔（根）
input int    InpEqMinCount     = 2;     // 至少几个枢轴才算流动性池
input bool   InpEqDrawBand     = true;  // 画成容差带（LuxAlgo 明确建议 band 而非线）

input group "== M7 扫荡 / 诱导 =="
input ENUM_SMC_SWEEP_SRC InpSweepSrc = SMC_SWEEP_BOTH;  // 扫荡取位来源
input int InpMaxSweep         = 8;      // 最多显示最近 N 条扫荡（0=全部）

input group "== M8 Premium / Discount =="
input bool InpPdShowZones     = true;   // 画区间上下半底色 + PREMIUM/DISCOUNT 标签
input bool InpPdShowEQ        = true;   // 画均衡位 EQ（区间 50%）
input int  InpPdMaxBars       = 200;    // 区间延伸的最多根数

input group "== M9 强/弱高低点 =="
// ⚠️ 本术语**无权威口径**（LuxAlgo 54 概念 + ICTKillzone 115 术语都不收录）。
//    两套有出处的读法见枚举处注释。切模式会显著改变标记，diff 前先核对 CSV 头。
input ENUM_SMC_SW_MODE InpSWMode = SMC_SW_SWEPT_IS_WEAK;  // 强弱判据
input int  InpMaxSW           = 6;      // 每类最多显示 N 个（0=全部）

input group "== M10 Killzone（一律用纽约时间表达）=="
input bool   InpKzShowBoxes   = true;   // 画时段矩形
input string InpKzAsia        = "20:00-00:00";  // 亚洲时段（纽约时间）
input string InpKzLondon      = "02:00-05:00";  // 伦敦时段（纽约时间）
input string InpKzNewYork     = "07:00-10:00";  // 纽约时段（纽约时间）
// 时区换算。**不要用固定偏移** —— broker 多数走欧洲 DST、纽约走美国 DST，
// 两者切换日期每年相差约 3 周，固定偏移在那几周里必错 1 小时。
// 自动模式：用 TimeGMT() 反推服务器相对 GMT 的偏移，再按美国 DST 规则
// （3 月第 2 个周日 ~ 11 月第 1 个周日 = EDT = UTC−4，否则 EST = UTC−5）算纽约时间。
input bool   InpKzAutoTZ      = true;   // 自动推算时区（TimeGMT + 美国 DST 规则）
input int    InpKzManualShift = 7;      // 手动换算：纽约 = 服务器 − 该小时数（自动关闭时生效）
input int    InpKzMaxGapMin   = 120;    // 相邻 bar 时间差超过该值即切段（防周末并段）
input int    InpKzMaxBoxes    = 30;     // 最多绘制 N 个时段矩形
input bool   InpKzShowLabels  = true;   // 时段名标签

input group "== M11 多周期结构 =="
input ENUM_TIMEFRAMES InpMtfPeriod = PERIOD_H4;  // 高周期
input int InpMtfBars          = 300;    // 高周期取用根数
input int InpMtfSwingLen      = 20;     // 高周期枢轴半窗

input group "== 绘制 =="
// 实测依据（tools/smc_logic_sim.py）：分析窗口 500 根时 swingLen=15 出 9 个结构事件；
// 2000 根时出 40 个。窗口太短会让结构模块看起来"没在跑"。
input int InpWindow           = 500;    // 绘制窗口（根 K 线）
input int InpMaxEvents        = 6;      // 每类最多显示最近 N 条（0=全部）
input int InpLabelFontSize    = 8;      // 标签字号

input group "== 颜色 =="
input color InpColorBull      = C'38,166,65';   // 看涨结构（涨绿）
input color InpColorBear      = C'248,81,73';   // 看跌结构（跌红）
input color InpColorInternal  = C'139,148,158'; // 内部层结构（灰）
input color InpColorWeak      = C'110,110,130'; // 位移不足的弱事件（暗灰）
input color InpColorOB        = C'100,140,255'; // 订单块（蓝）
input color InpColorFVG       = C'0,200,180';   // FVG（青绿）
input color InpColorIFVG      = C'255,152,0';   // IFVG（橙）
input color InpColorEQ        = C'224,224,224'; // EQH/EQL（近白）
input color InpColorSweep     = C'255,213,79';  // 扫荡（黄）
input color InpColorIDM       = C'186,104,200'; // 诱导（紫）
input color InpColorEQLine    = C'255,213,79';  // 均衡位 EQ（黄）
input color InpColorKzAsia    = C'88,166,255';  // 亚洲时段
input color InpColorKzLondon  = C'240,136,62';  // 伦敦时段
input color InpColorKzNY      = C'38,166,65';   // 纽约时段
input int   InpFillPercent    = 30;             // 区间填充强度 %（0=空心框）

input group "== 性能 =="
input int  InpAnalysisWindow  = 2000;   // 分析窗口（根，0=全量）
input bool InpReuseResultOnTick = true; // 同 bar tick 复用分析结果

input group "== 调试验收（默认全关，常态零成本）=="
input bool InpDebugShowRef    = false;  // 专家日志：方向自检 + 枢轴自检等式 + 计数分布
input bool InpDumpEvents      = false;  // 导出全部事件 CSV（离线 diff 用）

//+------------------------------------------------------------------+
//|  数据结构（结果层）                                              |
//+------------------------------------------------------------------+
struct SMCPivot
{
   int      bar;     // series 下标（0 = 最新）
   datetime t;       // 该 bar 时间（多周期映射用，渲染不再反查数组）
   double   price;
   bool     isHigh;
   int      tier;    // TIER_SWING / TIER_INTERNAL
   int      seq;     // 同层级内的确认序号（自检等式用）
};

struct SMCStructEvent
{
   int      bar;      // 破位 bar
   datetime tBreak;
   int      refBar;   // 被突破的枢轴 bar
   datetime tRef;
   double   level;    // 被突破的枢轴价格
   int      dir;      // DIR_UP / DIR_DOWN
   bool     isChoch;  // true = CHoCH（趋势翻转）/ false = BOS（顺势延续）
   int      tier;
   bool     strong;   // 破位 K 实体是否过位移门槛
   double   bodyATR;  // 实体 / ATR（度量，始终写入 CSV）
   bool     outside;  // 该 bar 是否"同 bar 双破"（外包 K 线）
   bool     conflict; // 同 bar 双破时，两个方向**同时**成立（正常几何下不该发生，见 ComputeSMC）
   bool   isEqRef;    // 被突破的位是否同时是一个 EQH/EQL 流动性池（后验回填）
};

struct SMCZone
{
   int      kind;        // ZONE_OB / ZONE_FVG
   int      dir;         // DIR_UP / DIR_DOWN
   int      bar;         // 形成 bar（FVG = 第三根 C；OB = 破位 bar）
   datetime tBar;
   int      refBar;      // 锚点 bar（FVG = 第一根 A；OB = OB 那根 K 线）
   datetime tRef;
   double   lo, hi, ce;
   bool     mitigated;   // 被触及（价格进入区间）
   int      mitBar;
   bool     invalidated; // 被收盘穿越（失效）
   int      invBar;
   bool     inverted;    // FVG 专用：已成为 IFVG
   int      invertBar;
   double   fillPct;     // FVG 专用：最大回补比例 0..1
   bool     strong;      // OB 专用：关联事件的位移是否达标
   bool     showMT;      // 是否画均值门槛线（仅 HYBRID 基准：实体并集的 50%）
   int      tier;        // 关联事件层级（FVG 恒 -1）
};

struct SMCEqLevel
{
   double   price;
   bool     isHigh;
   int      tier;            // 该池挂在哪一层（EQ 必须标明层级，否则 0.15ATR 的容差无意义）
   double   tol;             // 成池时的容差（band 半宽；渲染与 CSV 都要，便于事后核对）
   int      bar1, bar2;      // 该组最旧 / 最新枢轴 bar
   datetime t1, t2;
   int      count;           // 组内枢轴个数
   bool     taken;           // 已被越过（流动性被取走）
   int      takenBar;
   bool     swept;           // 曾被"影线越过 + 收盘收回"
   int      sweepBar;
};

struct SMCSweep
{
   int      bar;
   datetime t;
   int      refBar;
   datetime tRef;
   double   level;
   int      dir;       // DIR_UP = 上方被扫 / DIR_DOWN = 下方被扫
   int      tier;
   bool     isEq;      // 扫的是 EQH/EQL 而非普通枢轴
};

struct SMCSegment       // Killzone 连续段
{
   int      sBar, eBar;
   datetime t1, t2;
   double   hi, lo;
   int      kz;         // 0=亚洲 1=伦敦 2=纽约
};

struct SMCStrongWeak
{
   int      bar;
   datetime t;
   double   price;
   int      kind;       // SW_STRONG_HIGH / SW_WEAK_HIGH / SW_STRONG_LOW / SW_WEAK_LOW
};

struct SMCResult
{
   SMCPivot        pivSwing[];   int nPivSwing;
   SMCPivot        pivInt[];     int nPivInt;
   SMCStructEvent  evtSwing[];   int nEvtSwing;
   SMCStructEvent  evtInt[];     int nEvtInt;
   SMCStructEvent  evtMtf[];     int nEvtMtf;
   // 多周期分析的枢轴**只用于让 AnalyzeStructure 有地方写**，不参与渲染、
   // 也绝不与本图 pivSwing 混用 —— 分开的容器本身就是一道防线。
   SMCPivot        pivMtfScratch[]; int nMtfScratch;
   SMCZone         zones[];      int nZones;
   SMCEqLevel      eqs[];        int nEq;
   SMCSweep        sweeps[];     int nSweep;
   SMCPivot        idm[];        int nIdm;
   SMCSegment      kz[];         int nKz;
   SMCStrongWeak   sw[];         int nSW;
   // ── 逐帧派生量：Premium / Discount ──
   double   pdHi, pdLo, pdEq;
   int      pdHiBar, pdLoBar;
   datetime pdHiT, pdLoT;
   bool     pdValid;
};

//+------------------------------------------------------------------+
//|  全局状态                                                        |
//+------------------------------------------------------------------+
SMCResult g_result;
double    g_curATR   = 0.0;      // 最新 bar 的 ATR（标签偏移用）
color     g_bg       = C'0,0,0'; // 图表底色（填充混色用，仅在 needDraw 帧读一次）

//── needDraw 指纹：硬约定 3 —— 每个可视化类别都必须有一项。──
//   取"集合级"信息（条数 + 最新一条的锚点），O(1) 内存可得。
//   ⚠️ 不含"最后一根正在形成的 bar 的 OHLC" —— 那会让每 tick 触发整段调和。
//   新 bar 由 time[0] 这一项覆盖（它必须存在，否则右端对象不会延长）。
datetime g_lastT0      = 0;
int  g_lastNPivSwing   = -1, g_lastNPivInt   = -1;
int  g_lastNEvtSwing   = -1, g_lastNEvtInt   = -1, g_lastNEvtMtf = -1;
int  g_lastNZones      = -1, g_lastNEq       = -1;
int  g_lastNSweep      = -1, g_lastNIdm      = -1;
int  g_lastNKz         = -1, g_lastNSW       = -1;
bool g_lastPdValid     = false;
double g_lastPdHi = 0.0, g_lastPdLo = 0.0;
int  g_lastPdHiBar = -1, g_lastPdLoBar = -1;

//── 场景成员哈希集合（回收段 O(1) 判定；照搬仓库已验证实现）──
string g_setKey[];
int    g_setMask   = 0;
int    g_setUsed   = 0;
bool   g_setReady  = false;
int    g_setNextCap = 128;

//── Killzone 解析结果（OnInit 时解析一次；解析失败则该时段禁用）──
int g_kzStart[3];
int g_kzEnd[3];
bool g_kzOk[3];

//── 自检计数（仅 InpDebugShowRef）──
int g_dbgPivotFound = 0;   // 检出枢轴总数（两层合计）
int g_dbgPivotBad   = 0;   // 独立复核不符的次数（**必须恒为 0**）
int g_dbgInverted   = 0;   // 高/低位倒挂被拦截的次数（正常应极少；持续增长说明枢轴次序有问题）

//+------------------------------------------------------------------+
//|  工具                                                             |
//+------------------------------------------------------------------+
color ClrMake(const int r, const int g, const int b)
{
   return (color)((r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16));
}

// 按**图表实际底色**把轮廓色弱化为填充色：
//     fill = 底色 + (轮廓色 − 底色) × pct/100
// ⚠️ 必须混向"实际底色"，不能假设黑底。
//    事故：原实现写死 `fill = 轮廓色 × α`，那只是黑底下的特例；白底上"往黑混"
//    会把颜色越压越暗，结果几乎看不见（用户实测反馈）。
color PdFill(const color base)
{
   int br = (int)(g_bg & 0xFF);
   int bg = (int)((g_bg >> 8) & 0xFF);
   int bb = (int)((g_bg >> 16) & 0xFF);
   int sr = (int)(base & 0xFF);
   int sg = (int)((base >> 8) & 0xFF);
   int sb = (int)((base >> 16) & 0xFF);
   double p = (double)InpFillPercent / 100.0;
   int r = (int)MathRound(br + (sr - br) * p);
   int g = (int)MathRound(bg + (sg - bg) * p);
   int b = (int)MathRound(bb + (sb - bb) * p);
   r = (int)MathMax(0, MathMin(255, r));
   g = (int)MathMax(0, MathMin(255, g));
   b = (int)MathMax(0, MathMin(255, b));
   return ClrMake(r, g, b);
}

// 解析 "HH:MM-HH:MM" → 起止分钟数（0..1439）。返回 false 表示格式非法。
bool ParseHHMM(const string spec, int &startMin, int &endMin)
{
   startMin = -1; endMin = -1;
   string parts[];
   if(StringSplit(spec, '-', parts) != 2) return false;
   for(int k = 0; k < 2; k++)
   {
      string hm[];
      if(StringSplit(parts[k], ':', hm) != 2) return false;
      int h = (int)StringToInteger(hm[0]);
      int m = (int)StringToInteger(hm[1]);
      if(h < 0 || h > 23 || m < 0 || m > 59) return false;
      if(k == 0) startMin = h * 60 + m;
      else       endMin   = h * 60 + m;
   }
   return true;
}

//── 时区换算（M10）──
// ⚠️ **不要用固定 GMT 偏移**。broker 多数跟随**欧洲** DST、纽约跟随**美国** DST，
//    两者的切换日期每年相差约 3 周 —— 固定偏移在那几周里必然错 1 小时，
//    且错得"看不出来"（Killzone 框整体平移一格）。
//
// 服务器相对 GMT 的偏移：用 TimeGMT() 反推，不假设 GMT+2/+3。
// ⚠️ 已知限制：TimeGMT() 依赖**本机时钟与时区设置**，在策略测试器里可能不准。
//    若发现框整体偏移，请关掉 InpKzAutoTZ 改用手动偏移。
double ServerGmtOffsetHours()
{
   datetime srv = TimeTradeServer();
   datetime gmt = TimeGMT();
   if(srv <= 0 || gmt <= 0) return 0.0;
   return (double)((long)srv - (long)gmt) / 3600.0;
}

// 某年某月的第 n 个星期日（n 从 1 计）
int NthSundayOfMonth(const int year, const int month, const int n)
{
   MqlDateTime d;
   d.year = year; d.mon = month; d.day = 1;
   d.hour = 0; d.min = 0; d.sec = 0;
   MqlDateTime d2;
   TimeToStruct(StructToTime(d), d2);
   int dow = d2.day_of_week;                 // 0 = 星期日
   int firstSunday = 1 + ((7 - dow) % 7);
   return firstSunday + (n - 1) * 7;
}

// 美国 DST：3 月第 2 个周日 ~ 11 月第 1 个周日。
// 只判到**日**粒度（不判 02:00 本地那一刻）—— 一年最多两次、各 2 小时的边界误差，
// 对时段框的用途可以接受；若要精确到分钟需引入完整时区库，MT5 不提供。
bool IsUsDst(const datetime gmtTime)
{
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   if(dt.mon < 3 || dt.mon > 11) return false;
   if(dt.mon > 3 && dt.mon < 11) return true;
   if(dt.mon == 3)  return (dt.day > NthSundayOfMonth(dt.year, 3, 2));
   return (dt.day < NthSundayOfMonth(dt.year, 11, 1));
}

// 服务器时间 → 纽约时间 的小时位移（正数表示纽约比服务器晚这么多小时）。
// 记录进全局，供 CSV 头部自描述（否则归档无法判断框是按哪个换算画的）。
double g_nyShiftHours = 7.0;

double ComputeNyShiftHours()
{
   if(!InpKzAutoTZ) return (double)InpKzManualShift;
   double srvOff = ServerGmtOffsetHours();
   long   gmtApprox = (long)TimeTradeServer() - (long)MathRound(srvOff * 3600.0);
   int    nyOff = IsUsDst((datetime)gmtApprox) ? -4 : -5;
   return srvOff - (double)nyOff;
}

// 纽约时间的"当日分钟数"（0..1439）
int NyMinuteOfDay(const datetime t)
{
   long shiftSec = (long)MathRound(g_nyShiftHours * 3600.0);
   long shifted  = (long)t - shiftSec;
   long mod      = shifted % 86400;
   if(mod < 0) mod += 86400;
   return (int)(mod / 60);
}

// 分钟数是否落在 [start, end) 内（支持跨午夜：end <= start 时视为绕回）
bool InKzWindow(const int minOfDay, const int startMin, const int endMin)
{
   if(startMin == endMin) return false;          // 零长度 → 禁用
   if(startMin < endMin)  return (minOfDay >= startMin && minOfDay < endMin);
   return (minOfDay >= startMin || minOfDay < endMin);  // 跨午夜
}

//+------------------------------------------------------------------+
//|  ATR（Wilder 平滑，单遍 O(n)）                                    |
//+------------------------------------------------------------------+
// maxBars：分析窗口上限（0 = 全量）。**参数化**是因为高周期分析要用自己的根数，
// 不能读全局 InpAnalysisWindow —— 否则多周期模块会去分析本图的窗口长度。
void CalcATRSeries(const double &high[], const double &low[], const double &close[],
                   const int rates_total, const int maxBars, double &atr[])
{
   ArrayResize(atr, rates_total);
   ArrayInitialize(atr, 0.0);

   int period = MathMax(2, InpATRPeriod);
   // 需要 i+1 可用 → 最旧只能到 rates_total-2
   int oldest = (maxBars > 0) ? (maxBars - 1) : (rates_total - 1);
   oldest = MathMin(oldest, rates_total - 2);
   if(oldest < 1) return;

   double sum     = 0.0;
   int    cnt     = 0;
   double prevATR = 0.0;

   for(int i = oldest; i >= 1; i--)   // 旧 → 新
   {
      double tr = high[i] - low[i];
      double a  = MathAbs(high[i] - close[i + 1]);
      double b  = MathAbs(low[i]  - close[i + 1]);
      if(a > tr) tr = a;
      if(b > tr) tr = b;

      cnt++;
      if(cnt <= period)
      {
         sum += tr;
         atr[i] = sum / (double)cnt;     // 预热期用running mean，避免出现 0
      }
      else
      {
         if(prevATR <= 0.0) prevATR = sum / (double)period;
         prevATR = (prevATR * (period - 1) + tr) / (double)period;
         atr[i] = prevATR;
      }
   }
   // bar 0（未收盘）用 bar 1 的值兜底 —— 不引入"正在形成的 bar 每 tick 变化"的量
   if(rates_total > 1) atr[0] = atr[1];
}

//+------------------------------------------------------------------+
//|  M1 枢轴检测                                                     |
//+------------------------------------------------------------------+
// 对称窗口：p 是枢轴高 ⟺ high[p] **严格大于** [p-len, p+len] 内其余每一根。
// 确认时刻 = bar (p - len)（右窗口走完）。故**不可能有未来函数**。
// ⚠️ 自检等式：调用方必须满足 confirmBar == p - len。见 AnalyzeStructure 内注释。
bool IsPivotHigh(const double &high[], const int rates_total, const int p, const int len)
{
   if(len < 1) return false;
   if(p - len < 0) return false;                 // 右侧（更新侧）窗口不完整
   if(p + len > rates_total - 1) return false;   // 左侧（更旧侧）数据不足
   for(int k = p - len; k <= p + len; k++)
   {
      if(k == p) continue;
      if(high[k] >= high[p]) return false;
   }
   return true;
}

bool IsPivotLow(const double &low[], const int rates_total, const int p, const int len)
{
   if(len < 1) return false;
   if(p - len < 0) return false;
   if(p + len > rates_total - 1) return false;
   for(int k = p - len; k <= p + len; k++)
   {
      if(k == p) continue;
      if(low[k] <= low[p]) return false;
   }
   return true;
}

//── 独立复核（仅诊断用，不参与任何判定）──
// 与上面"逐个否决"的写法**不同构**：这里先取窗口极值再比较。
// 两者在"窗口边界写错"时必然分叉，故可用来证伪边界错误。
// 注意二者**不等价**是正常的：出现并列极值时 IsPivot* 因严格性返回 false，
// 而这里返回 true —— 故只在 "IsPivot* 为真但复核为假" 时计入违规。
bool VerifyPivotHigh(const double &high[], const int rates_total, const int p, const int len)
{
   if(p - len < 0 || p + len > rates_total - 1) return false;
   double mx = -DBL_MAX;
   for(int k = p - len; k <= p + len; k++) if(high[k] > mx) mx = high[k];
   return (high[p] >= mx);
}

bool VerifyPivotLow(const double &low[], const int rates_total, const int p, const int len)
{
   if(p - len < 0 || p + len > rates_total - 1) return false;
   double mn = DBL_MAX;
   for(int k = p - len; k <= p + len; k++) if(low[k] < mn) mn = low[k];
   return (low[p] <= mn);
}

//+------------------------------------------------------------------+
//|  M2 结构状态机（**唯一**实现；本图与高周期共用）                  |
//+------------------------------------------------------------------+
struct SMCState
{
   int    trend;        // 0 未定 / DIR_UP / DIR_DOWN
   int    hiBar;  double hiPrice; bool hiValid; bool hiSwept;
   int    loBar;  double loPrice; bool loValid; bool loSwept;
};

void AddStructEvent(SMCStructEvent &arr[], int &n,
                    const int bar, const datetime tBreak,
                    const int refBar, const datetime tRef,
                    const double level, const int dir, const bool isChoch,
                    const int tier, const bool strong, const double bodyATR,
                    const bool outside, const bool conflict)
{
   ArrayResize(arr, n + 1);
   arr[n].bar      = bar;
   arr[n].tBreak   = tBreak;
   arr[n].refBar   = refBar;
   arr[n].tRef     = tRef;
   arr[n].level    = level;
   arr[n].dir      = dir;
   arr[n].isChoch  = isChoch;
   arr[n].tier     = tier;
   arr[n].strong   = strong;
   arr[n].bodyATR  = bodyATR;
   arr[n].outside  = outside;
   arr[n].conflict = conflict;
   arr[n].isEqRef  = false;   // 后验回填（ComputeEqLevels 之后由 MarkEqRefs 填）
   n++;
}

void AddPivot(SMCPivot &arr[], int &n, const int bar, const datetime t,
              const double price, const bool isHigh, const int tier)
{
   ArrayResize(arr, n + 1);
   arr[n].bar    = bar;
   arr[n].t      = t;
   arr[n].price  = price;
   arr[n].isHigh = isHigh;
   arr[n].tier   = tier;
   arr[n].seq    = n;
   n++;
}

// 破位判据（BOS / CHoCH 共用）
bool BrokeUp(const int i, const double level, const double &high[], const double &close[])
{
   if(InpBreakConfirm == SMC_BREAK_WICK) return (high[i] > level);
   return (close[i] > level);
}
bool BrokeDown(const int i, const double level, const double &low[], const double &close[])
{
   if(InpBreakConfirm == SMC_BREAK_WICK) return (low[i] < level);
   return (close[i] < level);
}

// 结构状态机主循环。
//   len       — 枢轴半窗
//   tier      — TIER_SWING / TIER_INTERNAL
//   oldest    — 分析窗口最旧下标（series：数值越大越旧）
//   evts/pivs — 输出（追加式，调用方负责初始化为空）
// fillPd：是否把"最近波段枢轴高/低"写成全图的 Premium/Discount 区间。
//   ⚠️ 必须由调用方显式指定：多周期分析也走本函数，若不加这个开关，
//      高周期的区间会**覆盖**本图的区间（后调用者胜），图上显示的就是另一张图的区间。
void AnalyzeStructure(const int rates_total,
                      const datetime &time[], const double &open[],
                      const double &high[], const double &low[], const double &close[],
                      const double &atr[], const int len, const int tier,
                      const int oldest, const bool fillPd,
                      SMCStructEvent &evts[], int &nEvts,
                      SMCPivot &pivs[], int &nPivs)
{
   if(len < 1 || oldest < 2) return;

   SMCState st;
   st.trend   = 0;
   st.hiValid = false; st.hiSwept = false;
   st.loValid = false; st.loSwept = false;
   st.hiBar   = -1; st.loBar = -1;

   for(int i = oldest; i >= 1; i--)      // 旧 → 新
   {
      //───────────────────────────────────────────────────────────
      //  ① 枢轴确认：bar i 上"新到达"的确认，对应枢轴 bar p = i + len
      //     等式来源：p 的右窗口 [p-len, p-1] 全部走完 ⟺ 已处理到 bar p-len。
      //     故在 i 处确认为真的枢轴 p 必然满足 p == i + len。
      //     ⚠️ 这条等式是本模块最重要的正确性不变量，InpDebugShowRef 时会断言。
      //───────────────────────────────────────────────────────────
      int p = i + len;
      if(p <= oldest)                    // 只用窗口内的枢轴（warm-up 损失见 plan §4.1）
      {
         if(IsPivotHigh(high, rates_total, p, len))
         {
            AddPivot(pivs, nPivs, p, time[p], high[p], true, tier);
            st.hiBar = p; st.hiPrice = high[p];
            st.hiValid = true; st.hiSwept = false;
            g_dbgPivotFound++;
            // 独立复核：用**另一种写法**（取窗口极值再比较）重算一次。
            // 与 IsPivotHigh 的"逐个否决"不同构，故只有窗口边界写错时两者才会不一致。
            // ⚠️ 不要写成 `i != p - len` —— 那是恒假的同义反复（p 就是 i+len 定义的），
            //    属仓库硬约定 5 明令禁止的"永不成立的门控"。
            if(!VerifyPivotHigh(high, rates_total, p, len)) g_dbgPivotBad++;
         }
         if(IsPivotLow(low, rates_total, p, len))
         {
            AddPivot(pivs, nPivs, p, time[p], low[p], false, tier);
            st.loBar = p; st.loPrice = low[p];
            st.loValid = true; st.loSwept = false;
            g_dbgPivotFound++;
            if(!VerifyPivotLow(low, rates_total, p, len)) g_dbgPivotBad++;
         }
      }

      //───────────────────────────────────────────────────────────
      //  ② 扫荡检测（在破位**之前**）：影线越位但收盘收回 → 记一次扫荡，
      //     **不消耗该位**（后续真正的突破照样能出 BOS/CHoCH）。
      //     这是纪律不是选择：若扫荡也消耗该位，一次扫影线就永久吃掉一个结构位。
      //───────────────────────────────────────────────────────────
      if(InpShowSweep || InpShowIDM)
      {
         if(st.hiValid && !st.hiSwept && high[i] > st.hiPrice && close[i] < st.hiPrice)
         {
            ArrayResize(g_result.sweeps, g_result.nSweep + 1);
            g_result.sweeps[g_result.nSweep].bar    = i;
            g_result.sweeps[g_result.nSweep].t      = time[i];
            g_result.sweeps[g_result.nSweep].refBar = st.hiBar;
            g_result.sweeps[g_result.nSweep].tRef   = time[st.hiBar];
            g_result.sweeps[g_result.nSweep].level  = st.hiPrice;
            g_result.sweeps[g_result.nSweep].dir    = DIR_UP;
            g_result.sweeps[g_result.nSweep].tier   = tier;
            g_result.sweeps[g_result.nSweep].isEq   = false;
            g_result.nSweep++;
            st.hiSwept = true;
         }
         if(st.loValid && !st.loSwept && low[i] < st.loPrice && close[i] > st.loPrice)
         {
            ArrayResize(g_result.sweeps, g_result.nSweep + 1);
            g_result.sweeps[g_result.nSweep].bar    = i;
            g_result.sweeps[g_result.nSweep].t      = time[i];
            g_result.sweeps[g_result.nSweep].refBar = st.loBar;
            g_result.sweeps[g_result.nSweep].tRef   = time[st.loBar];
            g_result.sweeps[g_result.nSweep].level  = st.loPrice;
            g_result.sweeps[g_result.nSweep].dir    = DIR_DOWN;
            g_result.sweeps[g_result.nSweep].tier   = tier;
            g_result.sweeps[g_result.nSweep].isEq   = false;
            g_result.nSweep++;
            st.loSwept = true;
         }
      }

      //───────────────────────────────────────────────────────────
      //  ③ 破位检测
      //───────────────────────────────────────────────────────────
      // ⚠️ 倒挂守卫：`hiPrice` 是最近一个枢轴高、`loPrice` 是最近一个枢轴低，
      //    两者**并不保证**高低有序（两次枢轴高之间可以没有枢轴低 —— 何况跳空/重算）。
      //    一旦倒挂，`close > hiPrice` 与 `close < loPrice` 可能同时成立，
      //    趋势会被后写分支覆盖 —— 这正是主流 Pine 实现靠"几何巧合"隐式互斥、
      //    因而在异常输入下静默出错的那个缺口（独立调研指出，无权威口径）。
      //    这里显式拦掉：倒挂时本 bar 不做任何破位判定，并计数供诊断。
      if(st.hiValid && st.loValid && st.hiPrice <= st.loPrice)
      {
         g_dbgInverted++;
         st.hiValid = false;      // 倒挂状态不可用 → 丢弃两个位，等下一个枢轴重建
         st.loValid = false;
         continue;
      }

      bool upBreak = (st.hiValid && BrokeUp(i, st.hiPrice, high, close));
      bool dnBreak = (st.loValid && BrokeDown(i, st.loPrice, low, close));

      bool bothBroke = (upBreak && dnBreak);   // 同 bar 双破（外包 K 线）
      bool outside   = bothBroke;
      bool conflict  = bothBroke;              // 记进 CSV，不隐藏"这里其实有歧义"
      if(bothBroke)
      {
         // 同 bar 双破且两个位都有效（≠倒挂）→ 几何上可能，但先后顺序无法从 OHLC 判定
         // （MQL5 无 tick 顺序）。沿用仓库既有近似：阳线 → 低先高后（终态向上）；阴线反之。
         if(close[i] >= open[i]) dnBreak = false;
         else                    upBreak = false;
      }

      double body = MathAbs(close[i] - open[i]);
      bool strong = (InpMinDisplaceBodyATR <= 0.0);
      double bodyATR = 0.0;
      if(atr[i] > 0.0)
      {
         bodyATR = body / atr[i];
         if(InpMinDisplaceBodyATR > 0.0) strong = (bodyATR >= InpMinDisplaceBodyATR);
      }

      if(upBreak)
      {
         // 首次突破（trend == 0）标 BOS 而非 CHoCH —— 见文件头/plan §4.2：
         // CHoCH 断言了"前一种性格"，而此处没有可改变的前状态。
         bool isChoch = (st.trend == DIR_DOWN);
         AddStructEvent(evts, nEvts, i, time[i], st.hiBar, time[st.hiBar],
                        st.hiPrice, DIR_UP, isChoch, tier, strong, bodyATR, outside, conflict);
         st.trend   = DIR_UP;
         st.hiValid = false;             // 该高点已被取走
         st.hiSwept = false;
      }
      else if(dnBreak)
      {
         bool isChoch = (st.trend == DIR_UP);
         AddStructEvent(evts, nEvts, i, time[i], st.loBar, time[st.loBar],
                        st.loPrice, DIR_DOWN, isChoch, tier, strong, bodyATR, outside, conflict);
         st.trend   = DIR_DOWN;
         st.loValid = false;
         st.loSwept = false;
      }
   }

   // 收尾：把状态机最后持有的两个位导出为"当前 Premium/Discount 区间"
   // 仅当：波段层 + 调用方明确要求（见 fillPd 注释）
   if(tier == TIER_SWING && fillPd)
   {
      // 区间端点取**结构层当前活跃（未被突破）的 swing high / swing low**。
      // 依据（调研 §8）：dealing range 的**端点取法是本条唯一无权威口径处** ——
      //   LuxAlgo 教学层要求"有意义的 leg"并明确警告 "Minor swings produce random midpoints"；
      //   Black Tie / Quantum 则机械取"最近 pivot"。各家不一致，故这里选一个**内部自洽**的：
      //   与结构层共用同一对活跃位 → 区间不会与结构线互相矛盾。
      //   重锚规则因此也是继承来的：收盘突破任一端 → 该位被消耗 → 新区间由下一对枢轴给出。
      double rHi = 0.0, rLo = 0.0;
      int    hiBar = -1, loBar = -1;

      if(st.hiValid) { rHi = st.hiPrice; hiBar = st.hiBar; }
      if(st.loValid) { rLo = st.loPrice; loBar = st.loBar; }

      // 某一侧已被突破（valid=false）时，用该侧**最近一个枢轴**兜底 ——
      // 否则区间会只剩单边，整个模块在趋势推进中反复消失。
      for(int k = nPivs - 1; k >= 0 && (hiBar < 0 || loBar < 0); k--)
      {
         if(pivs[k].isHigh && hiBar < 0) { hiBar = pivs[k].bar; rHi = pivs[k].price; }
         if(!pivs[k].isHigh && loBar < 0) { loBar = pivs[k].bar; rLo = pivs[k].price; }
      }

      if(hiBar >= 0 && loBar >= 0 && rHi > rLo)
      {
         g_result.pdHi = rHi; g_result.pdLo = rLo;
         g_result.pdEq = (rHi + rLo) / 2.0;
         g_result.pdHiBar = hiBar; g_result.pdLoBar = loBar;
         g_result.pdHiT = time[hiBar]; g_result.pdLoT = time[loBar];
         g_result.pdValid = true;
      }
   }
}

//+------------------------------------------------------------------+
//|  M4 订单块：结构事件 → 反向 K 线 → 区间                           |
//+------------------------------------------------------------------+
// 找"破位 bar 之前（更旧）的反向收盘 K 线簇"。
//   看涨事件（dir=+1）→ 阴线簇（close < open）
//   看跌事件（dir=-1）→ 阳线簇（close >= open）
// 从最靠近破位的那一根起，向更旧方向**连续**扩展到至多 maxRun 根。
// ⚠️ 为什么合并整簇而不是只取一根：调研指出 LuxAlgo 给出两种合法做法，
//    合并整簇更稳（不易因单根选择不同而漏掉实际被回测的区域）。
// 返回簇内根数（0 = 未找到）；runNewest 最靠近破位、runOldest 最旧。
int FindObRun(const int breakBar, const int dir, const int oldest, const int maxRun,
              const double &open[], const double &close[],
              int &runOldest, int &runNewest)
{
   runOldest = -1; runNewest = -1;
   int lim = breakBar + InpOBLookback;
   if(lim > oldest) lim = oldest;
   if(lim <= breakBar) return 0;

   int n = 0;
   for(int k = breakBar + 1; k <= lim; k++)   // 越旧下标越大
   {
      bool bear = (close[k] < open[k]);
      bool want = (dir == DIR_UP) ? bear : !bear;
      if(!want) break;                        // 簇必须连续
      if(n == 0) runNewest = k;
      runOldest = k;
      n++;
      if(maxRun > 0 && n >= maxRun) break;
   }
   return n;
}

void AddZone(SMCZone &arr[], int &n, const int kind, const int dir,
             const int bar, const datetime tBar, const int refBar, const datetime tRef,
             const double lo, const double hi, const bool strong, const int tier)
{
   ArrayResize(arr, n + 1);
   arr[n].kind        = kind;
   arr[n].dir         = dir;
   arr[n].bar         = bar;
   arr[n].tBar        = tBar;
   arr[n].refBar      = refBar;
   arr[n].tRef        = tRef;
   arr[n].lo          = lo;
   arr[n].hi          = hi;
   arr[n].ce          = (lo + hi) / 2.0;
   arr[n].mitigated   = false;
   arr[n].mitBar      = -1;
   arr[n].invalidated = false;
   arr[n].invBar      = -1;
   arr[n].inverted    = false;
   arr[n].invertBar   = -1;
   arr[n].fillPct     = 0.0;
   arr[n].strong      = strong;
   arr[n].tier        = tier;
   arr[n].showMT      = false;
   n++;
}

// 后验：扫"形成之后（更新侧）"的 bars，算缓解 / 失效 / 回补 / 反转。
// **必须后验**：形成当刻之后的 bar 尚未被主循环遍历到。
// 写成终态（不是"到目前为止"）→ CSV 可复现，且 diff 稳定。
void ComputeZoneStates(const int oldest,
                       const double &open[], const double &high[],
                       const double &low[], const double &close[])
{
   for(int z = 0; z < g_result.nZones; z++)
   {
      int    dir  = g_result.zones[z].dir;
      double lo   = g_result.zones[z].lo;
      double hi   = g_result.zones[z].hi;
      double ce   = g_result.zones[z].ce;
      int    from = g_result.zones[z].bar - 1;   // 更新侧
      if(from > oldest) from = oldest;

      double bestPen = 0.0;
      double span    = hi - lo;
      if(span <= 0.0) span = _Point;

      for(int j = from; j >= 1; j--)
      {
         //── 缓解：价格**进入**区间（影线触及即算）──
         if(dir == DIR_UP)
         {
            if(!g_result.zones[z].mitigated && low[j] <= hi)
            { g_result.zones[z].mitigated = true; g_result.zones[z].mitBar = j; }
         }
         else
         {
            if(!g_result.zones[z].mitigated && high[j] >= lo)
            { g_result.zones[z].mitigated = true; g_result.zones[z].mitBar = j; }
         }

         //── 失效：**收盘**穿越远端 ──
         if(dir == DIR_UP)
         {
            if(!g_result.zones[z].invalidated && close[j] < lo)
            { g_result.zones[z].invalidated = true; g_result.zones[z].invBar = j; }
         }
         else
         {
            if(!g_result.zones[z].invalidated && close[j] > hi)
            { g_result.zones[z].invalidated = true; g_result.zones[z].invBar = j; }
         }

         //── FVG 专用：回补比例（最大穿透深度）+ IFVG 反转 ──
         if(g_result.zones[z].kind == ZONE_FVG)
         {
            double pen = 0.0;
            if(dir == DIR_UP)   // 缺口在下方，价格下跌回补
            {
               if(low[j] < hi) pen = (hi - low[j]) / span;
            }
            else                // 缺口在上方，价格上涨回补
            {
               if(high[j] > lo) pen = (high[j] - lo) / span;
            }
            if(pen > bestPen) bestPen = pen;

            if(!g_result.zones[z].inverted)
            {
               // IFVG 判定：**实体收盘穿越整个缺口**（越过远端）。
               // ⚠️ 此处**不设开关** —— LuxAlgo 与 ICTKillzone 两家逐字一致：
               //    "The common requirement is a candle body closing beyond the far side of
               //     the gap; a wick-through alone is usually read as a probe."
               //    "影线完全穿过但收盘回内侧 → FVG 守住"。
               //    CE 是**成立之后的入场位**，不是判定条件 —— 所以不存在
               //    "收盘穿 CE 即反转"的宽松档（那是少数实现的做法，调研明确不推荐）。
               //    `close` 即实体边界，故用 close 与远端比较即为"实体收盘穿越"。
               bool through = (dir == DIR_UP) ? (close[j] < lo) : (close[j] > hi);
               if(through)
               {
                  g_result.zones[z].inverted  = true;
                  g_result.zones[z].invertBar = j;
               }
            }
         }
      }

      if(bestPen > 1.0) bestPen = 1.0;
      if(bestPen < 0.0) bestPen = 0.0;
      g_result.zones[z].fillPct = bestPen;
   }
}

//+------------------------------------------------------------------+
//|  M5 FVG 检测（在主循环内逐 bar 完成，与 OB 分开）                 |
//+------------------------------------------------------------------+
void DetectFvgs(const int rates_total, const datetime &time[],
                const double &high[], const double &low[], const double &close[],
                const double &atr[], const int oldest)
{
   if(!InpShowFVG && !InpShowIFVG) return;

   for(int i = oldest; i >= 2; i--)      // i = 三根里最新那根 C
   {
      int a = i + 2;                     // 三根里最旧那根 A
      if(a > oldest) continue;

      double minSize = 0.0;
      if(InpFvgMinATR > 0.0 && atr[i] > 0.0) minSize = InpFvgMinATR * atr[i];

      // 看涨 FVG（BISI，缺口向上）：A.high < C.low → 区间 [A.high, C.low]
      if(high[a] < low[i])
      {
         double zlo = high[a], zhi = low[i];
         if(zhi - zlo >= minSize)
            AddZone(g_result.zones, g_result.nZones, ZONE_FVG, DIR_UP,
                    i, time[i], a, time[a], zlo, zhi, false, -1);
      }
      // 看跌 FVG（SIBI，缺口向下）：A.low > C.high → 区间 [C.high, A.low]
      else if(low[a] > high[i])
      {
         double zlo = high[i], zhi = low[a];
         if(zhi - zlo >= minSize)
            AddZone(g_result.zones, g_result.nZones, ZONE_FVG, DIR_DOWN,
                    i, time[i], a, time[a], zlo, zhi, false, -1);
      }
   }
}

//+------------------------------------------------------------------+
//|  M6 等高等低（EQH / EQL）                                        |
//+------------------------------------------------------------------+
double EqTolerance(const double &atr[], const int bar)
{
   if(InpEqToleranceATR > 0.0 && atr[bar] > 0.0)
      return InpEqToleranceATR * atr[bar];
   return InpEqTolerancePts * _Point;
}

void ComputeEqLevels(const SMCPivot &pivs[], const int nPivs, const int tier,
                     const double &high[], const double &low[], const double &close[],
                     const double &atr[], const int oldest)
{
   if(nPivs < InpEqMinCount) return;

   bool used[];
   ArrayResize(used, nPivs);
   ArrayInitialize(used, false);

   for(int a = 0; a < nPivs; a++)
   {
      if(used[a]) continue;

      bool     isHigh = pivs[a].isHigh;
      double   price  = pivs[a].price;
      int      cnt    = 1;
      int      bar1   = pivs[a].bar, bar2 = pivs[a].bar;
      datetime t1     = pivs[a].t,   t2   = pivs[a].t;
      double   tolUse = EqTolerance(atr, pivs[a].bar);

      for(int b = a + 1; b < nPivs; b++)
      {
         if(pivs[b].isHigh != isHigh) continue;
         // pivs 是「旧 → 新」，故 a 的 bar 下标更大；距离 = pivs[a].bar - pivs[b].bar
         int dist = pivs[a].bar - pivs[b].bar;
         if(dist > InpEqMaxBars) break;      // 已超最大间隔，后面的只会更远
         if(used[b]) continue;
         if(MathAbs(pivs[b].price - price) <= EqTolerance(atr, pivs[b].bar))
         {
            used[b] = true;
            cnt++;
            bar2 = pivs[b].bar; t2 = pivs[b].t;
            price = pivs[b].price;           // 取**最新**那个枢轴的价格作位
            tolUse = EqTolerance(atr, pivs[b].bar);
         }
      }

      if(cnt >= InpEqMinCount)
      {
         used[a] = true;
         ArrayResize(g_result.eqs, g_result.nEq + 1);
         int e = g_result.nEq;
         g_result.eqs[e].price  = price;
         g_result.eqs[e].isHigh = isHigh;
         g_result.eqs[e].tier   = tier;
         g_result.eqs[e].tol    = tolUse;
         g_result.eqs[e].bar1   = bar1; g_result.eqs[e].t1 = t1;
         g_result.eqs[e].bar2   = bar2; g_result.eqs[e].t2 = t2;
         g_result.eqs[e].count  = cnt;
         g_result.eqs[e].taken  = false; g_result.eqs[e].takenBar = -1;
         g_result.eqs[e].swept  = false; g_result.eqs[e].sweepBar = -1;
         g_result.nEq++;

         // 后验：该池是否已被取走 / 是否被"影线扫过但收盘收回"
         int from = bar2 - 1;
         if(from > oldest) from = oldest;
         for(int j = from; j >= 1; j--)
         {
            if(isHigh)
            {
               if(!g_result.eqs[e].swept && high[j] > price && close[j] < price)
               { g_result.eqs[e].swept = true; g_result.eqs[e].sweepBar = j; }
               if(!g_result.eqs[e].taken && close[j] > price)
               { g_result.eqs[e].taken = true; g_result.eqs[e].takenBar = j; }
            }
            else
            {
               if(!g_result.eqs[e].swept && low[j] < price && close[j] > price)
               { g_result.eqs[e].swept = true; g_result.eqs[e].sweepBar = j; }
               if(!g_result.eqs[e].taken && close[j] < price)
               { g_result.eqs[e].taken = true; g_result.eqs[e].takenBar = j; }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|  M7 诱导（IDM）                                                  |
//+------------------------------------------------------------------+
// ⚠️ **无一手权威** —— 各家对"诱导"的机械化判定互相冲突。本实现采用的约定：
//    对于每个**波段层**结构事件 E（bar b，方向 d），
//    IDM = 在上一个波段层事件与 E 之间、方向与 d **相反**的**最后一个内部层枢轴**。
//    直觉：上涨中先做出一个小回调低点（诱导散户做多/接盘），随后价格扫掉它再真正破位。
//    要求"上一个波段层事件之后"是为了排除早已失效的陈旧枢轴。
// 该约定写进 CSV 头，diff 时先核对口径。
void ComputeIdm(const int oldest)
{
   if(!InpShowIDM) return;
   if(g_result.nEvtSwing <= 0 || g_result.nPivInt <= 0) return;

   for(int e = 0; e < g_result.nEvtSwing; e++)
   {
      int    b   = g_result.evtSwing[e].bar;
      int    dir = g_result.evtSwing[e].dir;
      int    prevBar = oldest;                        // 上一个事件（更旧 = 下标更大）
      if(e > 0) prevBar = g_result.evtSwing[e - 1].bar;

      int bestIdx = -1;
      int bestBar = -1;
      for(int k = 0; k < g_result.nPivInt; k++)
      {
         int pb = g_result.pivInt[k].bar;
         if(pb >= prevBar) continue;                  // 必须比上一个事件更**新**
         if(pb <= b)       continue;                  // 必须比本次事件更**旧**
         bool wantHigh = (dir == DIR_DOWN);           // 看跌事件 → 找上方的高点作诱导
         if(g_result.pivInt[k].isHigh != wantHigh) continue;
         if(bestBar < 0 || pb < bestBar) { bestBar = pb; bestIdx = k; }
      }

      if(bestIdx >= 0)
      {
         ArrayResize(g_result.idm, g_result.nIdm + 1);
         int m = g_result.nIdm;
         g_result.idm[m] = g_result.pivInt[bestIdx];
         g_result.idm[m].tier = TIER_INTERNAL;
         g_result.nIdm++;
      }
   }
}

//+------------------------------------------------------------------+
//|  M7 后验：把"被突破的位本身就是一个 EQH/EQL"回填到结构事件上      |
//+------------------------------------------------------------------+
void MarkEqRefs()
{
   for(int e = 0; e < g_result.nEvtSwing; e++)
   {
      for(int q = 0; q < g_result.nEq; q++)
      {
         if(MathAbs(g_result.evtSwing[e].level - g_result.eqs[q].price) <= _Point * 2)
         { g_result.evtSwing[e].isEqRef = true; break; }
      }
   }
}

//+------------------------------------------------------------------+
//|  M9 强/弱高低点                                                  |
//+------------------------------------------------------------------+
// ⚠️ **本术语无权威口径**（见枚举处注释与 docs/research 的调研报告）。
//    这里只实现两套**有出处**的读法，不发明第三种。
// 只需 close：判"是否已被越过"用收盘口径；high/low 不参与。
void ComputeStrongWeak(const double &close[])
{
   if(!InpShowStrongWeak) return;
   if(g_result.nPivSwing <= 0) return;

   for(int k = 0; k < g_result.nPivSwing; k++)
   {
      int    bar    = g_result.pivSwing[k].bar;
      double price  = g_result.pivSwing[k].price;
      bool   isHigh = g_result.pivSwing[k].isHigh;

      // 该枢轴是否已被后续价格**越过**（收盘口径）
      bool taken = false;
      for(int j = bar - 1; j >= 1; j--)
      {
         if(isHigh ? (close[j] > price) : (close[j] < price)) { taken = true; break; }
      }

      bool weak;
      if(InpSWMode == SMC_SW_SWEPT_IS_WEAK)
      {
         // C-2 流动性状态派：已被越过 = 流动性已耗 = 不再是要取的目标 = 弱
         weak = taken;
      }
      else
      {
         // C-1 位移质量派：该枢轴之后是否出现过"过位移门槛"的反向破位。
         // 有 → 它保护住了趋势 = 强；没有 → 弱。
         // 判据复用结构事件的 strong 标志（同一条位移门槛），保证全工具口径一致。
         bool protectedByDisplacement = false;
         for(int e = 0; e < g_result.nEvtSwing; e++)
         {
            if(g_result.evtSwing[e].bar >= bar)  continue;  // 事件必须发生在枢轴之后
            if(g_result.evtSwing[e].strong == false) continue;
            // 反向破位：高点要等一个看跌位移事件
            if(isHigh && g_result.evtSwing[e].dir == DIR_DOWN) { protectedByDisplacement = true; break; }
            if(!isHigh && g_result.evtSwing[e].dir == DIR_UP)  { protectedByDisplacement = true; break; }
         }
         weak = !protectedByDisplacement;
      }

      int kind;
      if(isHigh) kind = weak ? SW_WEAK_HIGH   : SW_STRONG_HIGH;
      else       kind = weak ? SW_WEAK_LOW    : SW_STRONG_LOW;

      ArrayResize(g_result.sw, g_result.nSW + 1);
      g_result.sw[g_result.nSW].bar   = bar;
      g_result.sw[g_result.nSW].t     = g_result.pivSwing[k].t;
      g_result.sw[g_result.nSW].price = price;
      g_result.sw[g_result.nSW].kind  = kind;
      g_result.nSW++;
   }
}

//+------------------------------------------------------------------+
//|  M10 Killzone 时段切段                                            |
//+------------------------------------------------------------------+
void ComputeKillzones(const datetime &time[], const double &high[], const double &low[],
                      const int oldest)
{
   if(!InpShowKillzone) return;
   if(oldest < 2) return;

   long maxGap = (long)InpKzMaxGapMin * 60;
   if(maxGap <= 0) maxGap = 1;   // 守卫恒有效（防止门控变成死代码）

   int  curKz    = -1;
   int  segStart = -1, segEnd = -1;
   double segHi = 0.0, segLo = 0.0;
   datetime segT1 = 0, segT2 = 0;

   for(int i = oldest; i >= 1; i--)     // 旧 → 新
   {
      int m = NyMinuteOfDay(time[i]);
      int kz = -1;
      for(int s = 0; s < 3; s++)
      {
         if(!g_kzOk[s]) continue;
         if(InKzWindow(m, g_kzStart[s], g_kzEnd[s])) { kz = s; break; }
      }

      // 段结束条件：换时段 / 时段结束 / 时间跳空过大（周末）
      bool gap = (i < oldest && (long)(time[i + 1] - time[i]) > maxGap);
      if(curKz >= 0 && (kz != curKz || gap))
      {
         if(segEnd >= 0 && segEnd < segStart)
         {
            ArrayResize(g_result.kz, g_result.nKz + 1);
            int z = g_result.nKz;
            g_result.kz[z].sBar = segStart; g_result.kz[z].eBar = segEnd;
            g_result.kz[z].t1   = segT1;    g_result.kz[z].t2   = segT2;
            g_result.kz[z].hi   = segHi;    g_result.kz[z].lo   = segLo;
            g_result.kz[z].kz   = curKz;
            g_result.nKz++;
         }
         curKz = -1; segStart = -1; segEnd = -1;
      }
      if(kz < 0) continue;

      if(curKz < 0)
      {
         curKz = kz; segStart = i; segEnd = i;
         segHi = high[i]; segLo = low[i];
         segT1 = time[i]; segT2 = time[i];
      }
      else
      {
         segEnd = i; segT2 = time[i];
         if(high[i] > segHi) segHi = high[i];
         if(low[i]  < segLo) segLo = low[i];
      }
   }

   // 收尾：最后一段
   if(curKz >= 0 && segEnd >= 0 && segEnd < segStart)
   {
      ArrayResize(g_result.kz, g_result.nKz + 1);
      int z = g_result.nKz;
      g_result.kz[z].sBar = segStart; g_result.kz[z].eBar = segEnd;
      g_result.kz[z].t1   = segT1;    g_result.kz[z].t2   = segT2;
      g_result.kz[z].hi   = segHi;    g_result.kz[z].lo   = segLo;
      g_result.kz[z].kz   = curKz;
      g_result.nKz++;
   }
}

//+------------------------------------------------------------------+
//|  M11 多周期结构（复用 AnalyzeStructure —— 口径不可能漂移）        |
//+------------------------------------------------------------------+
void ComputeMtf()
{
   if(!InpShowMTF) return;

   int need = MathMax(InpMtfSwingLen * 4 + 10, MathMin(InpMtfBars, 1000));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int got = CopyRates(_Symbol, InpMtfPeriod, 0, need, rates);
   if(got < InpMtfSwingLen * 2 + 4) return;

   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, got); ArrayResize(o, got); ArrayResize(h, got);
   ArrayResize(l, got); ArrayResize(c, got);
   ArraySetAsSeries(t, true); ArraySetAsSeries(o, true); ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);

   for(int k = 0; k < got; k++)
   {
      t[k] = rates[k].time;
      o[k] = rates[k].open;
      h[k] = rates[k].high;
      l[k] = rates[k].low;
      c[k] = rates[k].close;
   }

   double atr[];
   CalcATRSeries(h, l, c, got, got - 1, atr);

   int oldestMtf = got - 2;    // 需要 i+1 可用
   if(oldestMtf < 2) return;

   int nEvts = 0, nPivs = 0;
   g_result.nMtfScratch = 0;
   AnalyzeStructure(got, t, o, h, l, c, atr, InpMtfSwingLen, TIER_SWING,
                    oldestMtf, false,          // fillPd=false：不得覆盖本图的 Premium/Discount
                    g_result.evtMtf, nEvts,
                    g_result.pivMtfScratch, nPivs);
   g_result.nEvtMtf     = nEvts;
   g_result.nMtfScratch = nPivs;
}

//+------------------------------------------------------------------+
//|  分析层总入口                                                    |
//+------------------------------------------------------------------+
void ComputeSMC(const int rates_total,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
{
   // 清空结果（全局复用，必须显式归零，否则上一帧的数据会残留）
   ArrayResize(g_result.pivSwing, 0); g_result.nPivSwing = 0;
   ArrayResize(g_result.pivInt,   0); g_result.nPivInt   = 0;
   ArrayResize(g_result.evtSwing, 0); g_result.nEvtSwing = 0;
   ArrayResize(g_result.evtInt,   0); g_result.nEvtInt   = 0;
   ArrayResize(g_result.evtMtf,   0); g_result.nEvtMtf   = 0;
   ArrayResize(g_result.zones,    0); g_result.nZones    = 0;
   ArrayResize(g_result.eqs,      0); g_result.nEq       = 0;
   ArrayResize(g_result.sweeps,   0); g_result.nSweep    = 0;
   ArrayResize(g_result.idm,      0); g_result.nIdm      = 0;
   ArrayResize(g_result.kz,       0); g_result.nKz       = 0;
   ArrayResize(g_result.sw,       0); g_result.nSW       = 0;
   g_result.pdValid = false;

   g_dbgPivotFound = 0;
   g_dbgPivotBad   = 0;

   int oldest = (InpAnalysisWindow > 0) ? (InpAnalysisWindow - 1) : (rates_total - 1);
   oldest = MathMin(oldest, rates_total - 2);
   if(oldest < 4) return;

   double atr[];
   CalcATRSeries(high, low, close, rates_total, InpAnalysisWindow, atr);
   if(rates_total > 0) g_curATR = atr[0];

   //① 结构（波段层）—— 只有这一次调用会把结果写成全图 Premium/Discount 区间
   AnalyzeStructure(rates_total, time, open, high, low, close, atr,
                    InpSwingLen, TIER_SWING, oldest, true,
                    g_result.evtSwing, g_result.nEvtSwing,
                    g_result.pivSwing, g_result.nPivSwing);

   //② 结构（内部层）—— 独立状态机，与波段层互不干扰
   //   ⚠️ **无条件计算**，不挂在 InpShowInternal 上。理由：内部层枢轴有第二个消费者 ——
   //      EQH/EQL（默认就挂在内部层，见 InpEqTier）与诱导 IDM。
   //      若按显示开关跳过，就会出现"关掉内部结构显示 → EQH/EQL 整块消失"的隐性耦合，
   //      而用户完全看不出原因。成本很小（一次 O(窗口) 扫描）。
   AnalyzeStructure(rates_total, time, open, high, low, close, atr,
                    InpInternalLen, TIER_INTERNAL, oldest, false,
                    g_result.evtInt, g_result.nEvtInt,
                    g_result.pivInt, g_result.nPivInt);

   //③ M4 订单块：每个波段层结构事件派生一个
   if(InpShowOB)
   {
      for(int e = 0; e < g_result.nEvtSwing; e++)
      {
         int dir = g_result.evtSwing[e].dir;
         int b   = g_result.evtSwing[e].bar;
         int rNew = -1, rOld = -1;
         int cnt = FindObRun(b, dir, oldest, InpOBCluster, open, close, rOld, rNew);
         if(cnt <= 0) continue;

         // 簇内极值：影线全幅 与 实体并集 各算一套，按基准选用
         double wLo = low[rNew],  wHi = high[rNew];
         double bLo = MathMin(open[rNew], close[rNew]);
         double bHi = MathMax(open[rNew], close[rNew]);
         for(int k = rNew + 1; k <= rOld; k++)
         {
            if(low[k]  < wLo) wLo = low[k];
            if(high[k] > wHi) wHi = high[k];
            double bl = MathMin(open[k], close[k]);
            double bh = MathMax(open[k], close[k]);
            if(bl < bLo) bLo = bl;
            if(bh > bHi) bHi = bh;
         }

         double zlo, zhi, mt;
         bool   showMT = false;
         if(InpOBBasis == SMC_OB_BODY)
         {
            zlo = bLo; zhi = bHi; mt = (bLo + bHi) / 2.0;
         }
         else if(InpOBBasis == SMC_OB_WICK)
         {
            zlo = wLo; zhi = wHi; mt = (wLo + wHi) / 2.0;
         }
         else // SMC_OB_HYBRID：影线全幅作区间 + 实体并集的 50% 作均值门槛（LuxAlgo "common hybrid"）
         {
            zlo = wLo; zhi = wHi; mt = (bLo + bHi) / 2.0;
            showMT = true;
         }
         if(zhi <= zlo) continue;

         AddZone(g_result.zones, g_result.nZones, ZONE_OB, dir,
                 b, time[b], rNew, time[rNew], zlo, zhi,
                 g_result.evtSwing[e].strong, TIER_SWING);
         // 均值门槛写进 ce（AddZone 默认填区间中点，这里按口径覆盖）
         g_result.zones[g_result.nZones - 1].ce     = mt;
         g_result.zones[g_result.nZones - 1].showMT = showMT;
      }
   }

   //④ M5 FVG
   DetectFvgs(rates_total, time, high, low, close, atr, oldest);

   //⑤ M4/M5 共用的后验状态（缓解 / 失效 / 回补 / 反转）
   ComputeZoneStates(oldest, open, high, low, close);

   //⑥ M6 EQH / EQL（按 InpEqTier 决定挂在哪一层；见枚举处的实测依据）
   if(InpShowEQHL)
   {
      if(InpEqTier == SMC_EQ_INTERNAL || InpEqTier == SMC_EQ_BOTH)
         ComputeEqLevels(g_result.pivInt, g_result.nPivInt, TIER_INTERNAL,
                         high, low, close, atr, oldest);
      if(InpEqTier == SMC_EQ_SWING || InpEqTier == SMC_EQ_BOTH)
         ComputeEqLevels(g_result.pivSwing, g_result.nPivSwing, TIER_SWING,
                         high, low, close, atr, oldest);
   }

   //⑦ M7 诱导（依赖波段层事件 + 内部层枢轴）
   ComputeIdm(oldest);

   //⑧ 回填"被突破的位本身就是流动性池"
   MarkEqRefs();

   //⑨ M9 强/弱高低点
   ComputeStrongWeak(close);

   //⑩ M10 Killzone（先算纽约时间位移 —— 见 ComputeNyShiftHours 的 DST 说明）
   g_nyShiftHours = ComputeNyShiftHours();
   ComputeKillzones(time, high, low, oldest);

   //⑪ M11 多周期结构（纯渲染，不参与以上任何判定）
   ComputeMtf();
}

//+------------------------------------------------------------------+
//|  场景集合（哈希；回收段 O(1) 判定）                              |
//+------------------------------------------------------------------+
int SceneHash(const string s)
{
   uint h = 2166136261;
   int  n = StringLen(s);
   for(int i = 0; i < n; i++)
      h = (h ^ (uint)StringGetCharacter(s, i)) * 16777619;
   return (int)h;
}

void SceneSetAdd(const string name)
{
   if(g_setUsed * 2 >= g_setMask + 1)
   {
      int newCap = (g_setMask + 1) * 2;
      string old[];
      ArrayResize(old, g_setMask + 1);
      for(int i = 0; i <= g_setMask; i++) old[i] = g_setKey[i];
      ArrayResize(g_setKey, newCap);
      for(int i = 0; i < newCap; i++) g_setKey[i] = "";
      g_setMask = newCap - 1;
      g_setUsed = 0;
      for(int i = 0; i < newCap / 2; i++)
      {
         if(old[i] == "") continue;
         int j = SceneHash(old[i]) & g_setMask;
         while(g_setKey[j] != "") j = (j + 1) & g_setMask;
         g_setKey[j] = old[i];
         g_setUsed++;
      }
   }
   int h = SceneHash(name) & g_setMask;
   while(g_setKey[h] != "")
   {
      if(g_setKey[h] == name) return;
      h = (h + 1) & g_setMask;
   }
   g_setKey[h] = name;
   g_setUsed++;
}

bool SceneHas(const string name)
{
   if(!g_setReady) return false;
   int h = SceneHash(name) & g_setMask;
   while(g_setKey[h] != "")
   {
      if(g_setKey[h] == name) return true;
      h = (h + 1) & g_setMask;
   }
   return false;
}

void SceneSetRebuild()
{
   if(g_setNextCap < 8) g_setNextCap = 8;
   ArrayResize(g_setKey, g_setNextCap);
   for(int i = 0; i < g_setNextCap; i++) g_setKey[i] = "";
   g_setMask  = g_setNextCap - 1;
   g_setUsed  = 0;
   g_setReady = true;
}

void AddSceneName(const string name) { SceneSetAdd(name); }

//+------------------------------------------------------------------+
//|  调和式对象操作                                                   |
//+------------------------------------------------------------------+
// 注：本层**不使用**任何"对象属性镜像缓存"。MQL5 文档说明在当前图表上
//     ObjectGet*/ObjectName/ObjectsTotal 都是直接访问（非跨进程 IPC），
//     因此"用镜像避免 ObjectGet*"的前提不成立；镜像反而引入槽位分配 bug。
//     性能由 needDraw 门控承担：指纹未变时根本不进入本层。
bool UpsertLine(const string name,
                const datetime t1, const double p1,
                const datetime t2, const double p2,
                const color clr, const ENUM_LINE_STYLE style,
                const int width, const bool rayRight)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  rayRight);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      return true;
   }
   bool changed = false;
   if((datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0) != t1 ||
      (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1) != t2 ||
      ObjectGetDouble(0, name, OBJPROP_PRICE, 0) != p1 ||
      ObjectGetDouble(0, name, OBJPROP_PRICE, 1) != p2)
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
      changed = true;
   }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
   { ObjectSetInteger(0, name, OBJPROP_COLOR, clr); changed = true; }
   if((ENUM_LINE_STYLE)ObjectGetInteger(0, name, OBJPROP_STYLE) != style)
   { ObjectSetInteger(0, name, OBJPROP_STYLE, style); changed = true; }
   if((int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != width)
   { ObjectSetInteger(0, name, OBJPROP_WIDTH, width); changed = true; }
   if((bool)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != rayRight)
   { ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight); changed = true; }
   return changed;
}

// ⚠️ anchor 必须纳入调和判断 —— 与 UpsertRect 的 fill 同理：
//    只检查"是否新建"会漏掉"对象已存在但该属性仍是旧值"的情况。
bool UpsertText(const string name, const datetime t, const double price,
                const string text, const color clr,
                const ENUM_ANCHOR_POINT anchor = ANCHOR_LOWER)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetString (0, name, OBJPROP_TEXT,     text);
      ObjectSetString (0, name, OBJPROP_FONT,     "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelFontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR,    clr);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,   anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,   true);
      return true;
   }
   bool changed = false;
   if((datetime)ObjectGetInteger(0, name, OBJPROP_TIME) != t ||
      ObjectGetDouble(0, name, OBJPROP_PRICE) != price)
   {
      ObjectMove(0, name, 0, t, price);
      changed = true;
   }
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
   { ObjectSetString(0, name, OBJPROP_TEXT, text); changed = true; }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
   { ObjectSetInteger(0, name, OBJPROP_COLOR, clr); changed = true; }
   if((ENUM_ANCHOR_POINT)ObjectGetInteger(0, name, OBJPROP_ANCHOR) != anchor)
   { ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor); changed = true; }
   if((int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE) != InpLabelFontSize)
   { ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelFontSize); changed = true; }
   return changed;
}

// ⚠️ MT5 的 OBJ_RECTANGLE **没有透明度**（引用 OBJPROP_ALPHA 会编译报错 256），
//    且填充与边框共用 OBJPROP_COLOR。故"半透明"只能靠 PdFill() 预先算好的
//    不透明混色 + OBJPROP_BACK=true 让矩形画在 K 线之下。
bool UpsertRect(const string name, const datetime t1, const double p1,
                const datetime t2, const double p2, const color clr,
                const bool fill, const bool bordered)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      bordered ? STYLE_DOT : STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetInteger(0, name, OBJPROP_FILL,       fill);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      return true;
   }
   bool changed = false;
   if((datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0) != t1 ||
      (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1) != t2 ||
      ObjectGetDouble(0, name, OBJPROP_PRICE, 0) != p1 ||
      ObjectGetDouble(0, name, OBJPROP_PRICE, 1) != p2)
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
      changed = true;
   }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
   { ObjectSetInteger(0, name, OBJPROP_COLOR, clr); changed = true; }
   if((bool)ObjectGetInteger(0, name, OBJPROP_FILL) != fill)
   { ObjectSetInteger(0, name, OBJPROP_FILL, fill); changed = true; }
   ENUM_LINE_STYLE wantStyle = bordered ? STYLE_DOT : STYLE_SOLID;
   if((ENUM_LINE_STYLE)ObjectGetInteger(0, name, OBJPROP_STYLE) != wantStyle)
   { ObjectSetInteger(0, name, OBJPROP_STYLE, wantStyle); changed = true; }
   return changed;
}

//+------------------------------------------------------------------+
//|  渲染：结构事件（BOS / CHoCH）                                    |
//+------------------------------------------------------------------+
void RenderStructEvents(const SMCStructEvent &evts[], const int nEvts,
                        const int tier, const datetime tStart, bool &changed)
{
   if(nEvts <= 0) return;
   int from = 0;
   if(InpMaxEvents > 0 && nEvts > InpMaxEvents) from = nEvts - InpMaxEvents;

   string tag = (tier == TIER_SWING) ? "S" : "I";
   int    wdt = (tier == TIER_SWING) ? 1 : 1;

   for(int k = from; k < nEvts; k++)
   {
      if(evts[k].tBreak < tStart) continue;

      // 配色规则（三条互不重叠，按优先级）：
      //   ① 内部层恒为灰 —— 它是上下文，不是信号
      //   ② 位移不足 → 暗灰（**只改颜色，不减信息**：线照画、CSV 照记）
      //   ③ 否则按突破方向：向上绿 / 向下红
      bool isInt = (tier == TIER_INTERNAL);
      color base = (evts[k].dir == DIR_UP) ? InpColorBull : InpColorBear;
      if(isInt)              base = InpColorInternal;
      if(!evts[k].strong)    base = InpColorWeak;

      string nm  = OBJ_PREFIX + "EV_" + tag + "_" + IntegerToString(evts[k].refBar)
                   + "_" + IntegerToString(evts[k].bar);
      string lbl = OBJ_PREFIX + "EVL_" + tag + "_" + IntegerToString(evts[k].refBar)
                   + "_" + IntegerToString(evts[k].bar);
      AddSceneName(nm);
      AddSceneName(lbl);

      if(UpsertLine(nm, evts[k].tRef, evts[k].level, evts[k].tBreak, evts[k].level,
                    base, STYLE_DOT, wdt, false)) changed = true;

      string txt = evts[k].isChoch ? "CHoCH" : "BOS";
      if(isInt) txt = "i-" + txt;
      if(evts[k].isEqRef) txt = txt + "+EQ";
      datetime tMid = (datetime)(((long)evts[k].tRef + (long)evts[k].tBreak) / 2);
      if(UpsertText(lbl, tMid, evts[k].level, txt, base, ANCHOR_CENTER)) changed = true;
   }
}

//+------------------------------------------------------------------+
//|  渲染：摆动点 HH/HL/LH/LL 标签                                   |
//+------------------------------------------------------------------+
void RenderSwingLabels(const datetime tStart, bool &changed)
{
   if(!InpShowSwingLabels) return;

   // 标签依赖**前一个**同类型枢轴的价格来判定 HH/HL/LH/LL，
   // 故按类型各维护一个"上一个枢轴价"。
   double prevHigh = 0.0, prevLow = 0.0;
   bool   hasPrevHigh = false, hasPrevLow = false;
   double atr = (g_curATR > 0.0) ? g_curATR : _Point * 50.0;

   for(int k = 0; k < g_result.nPivSwing; k++)
   {
      int    bar    = g_result.pivSwing[k].bar;
      double price  = g_result.pivSwing[k].price;
      bool   isHigh = g_result.pivSwing[k].isHigh;

      string txt = "";
      if(isHigh)
      {
         if(hasPrevHigh) txt = (price > prevHigh) ? "HH" : "LH";
         else            txt = "H";
         prevHigh = price; hasPrevHigh = true;
      }
      else
      {
         if(hasPrevLow) txt = (price > prevLow) ? "HL" : "LL";
         else           txt = "L";
         prevLow = price; hasPrevLow = true;
      }

      if(g_result.pivSwing[k].t < tStart) continue;

      string nm = OBJ_PREFIX + "SW_" + IntegerToString(bar);
      AddSceneName(nm);
      double py = isHigh ? price + atr * 0.12 : price - atr * 0.12;
      color  cl = InpColorInternal;
      if(UpsertText(nm, g_result.pivSwing[k].t, py, txt, cl, ANCHOR_CENTER)) changed = true;
   }
}

//+------------------------------------------------------------------+
//|  渲染：区间（OB / FVG / IFVG）                                   |
//+------------------------------------------------------------------+
// tRightEnd：图表最右（最新 bar）时间。区间默认向右延伸到它 ——
//   OB/FVG 是"仍然有效的参照区"，画到当前时刻才有意义。
//   ⚠️ 原实现把右端写成"区间自己的形成 bar"，等于每个区间都只画成一条竖线，
//      属性全对、图上也"有对象"，但它不表达任何区间语义 —— 这类错误不报错，只能靠读图发现。
void RenderZones(const datetime tRightEnd, const datetime tStart, bool &changed)
{
   if(g_result.nZones <= 0) return;

   // ⚠️ 必须**按 kind 分别裁剪**：zones 数组是「先追加全部 OB、再追加全部 FVG」的顺序，
   //    用一个全局 from 从尾部裁，会让 FVG 把 OB 整类挤掉（图上"OB 全不见了"）。
   int nOB = 0;
   for(int k = 0; k < g_result.nZones; k++)
      if(g_result.zones[k].kind == ZONE_OB) nOB++;
   int nFVG  = g_result.nZones - nOB;
   int fromOb  = (InpMaxEvents > 0 && nOB  > InpMaxEvents) ? (nOB  - InpMaxEvents) : 0;
   int fromFvg = (InpMaxEvents > 0 && nFVG > InpMaxEvents) ? (nOB + nFVG - InpMaxEvents) : nOB;

   for(int k = 0; k < g_result.nZones; k++)
   {
      int    kind = g_result.zones[k].kind;
      if(kind == ZONE_OB) { if(k <  fromOb)  continue; }
      else                { if(k <  fromFvg) continue; }
      if(g_result.zones[k].tRef < tStart) continue;   // 窗口外的区间不画
      int    dir  = g_result.zones[k].dir;
      bool   inv  = g_result.zones[k].invalidated;
      bool   mit  = g_result.zones[k].mitigated;
      bool   ifvg = g_result.zones[k].inverted;

      if(kind == ZONE_OB)
      {
         if(InpObHideInvalidated && inv) continue;
         if(InpObHideMitigated && mit)   continue;
      }
      else
      {
         if(ifvg && !InpShowIFVG) continue;
         if(!ifvg && !InpShowFVG) continue;
         // "已被完全回补"只在它还没成为 IFVG 时才隐藏 ——
         // IFVG 的语义恰恰是"补掉了、现在反向用"，隐藏它就丢了这个模块。
         if(!ifvg && InpFvgHideFilled && g_result.zones[k].fillPct >= 1.0) continue;
      }

      color outline;
      if(kind == ZONE_OB)
         outline = g_result.zones[k].strong ? InpColorOB : InpColorWeak;
      else
         outline = ifvg ? InpColorIFVG : InpColorFVG;

      // ⚠️ OB 的对象名必须带上**事件 bar**：两个相邻的结构事件完全可能选中同一根
      //    反向 K 线作 OB（refBar 相同）。只用 refBar 做键会让后者覆盖前者 ——
      //    结果是"少画了一个 OB"，不报错、只能靠读图发现。
      string base = (kind == ZONE_OB
                     ? ("OB_" + IntegerToString(g_result.zones[k].refBar)
                              + "_" + IntegerToString(g_result.zones[k].bar))
                     : ((ifvg ? "IFVG_" : "FVG_") + IntegerToString(g_result.zones[k].refBar)));
      string nm   = OBJ_PREFIX + base;
      string lbl  = OBJ_PREFIX + base + "_L";
      AddSceneName(nm);
      AddSceneName(lbl);

      // 右端统一延伸到最新 bar：有效区间画到当前时刻才有意义；
      // 已失效的区间由上方开关决定隐藏或保留（保留时颜色已弱化，不需再截断）。
      datetime tEnd = tRightEnd;
      if(tEnd <= g_result.zones[k].tRef) tEnd = g_result.zones[k].tBar;
      if(tEnd <= g_result.zones[k].tRef) tEnd = g_result.zones[k].tRef + PeriodSeconds();

      if(UpsertRect(nm, g_result.zones[k].tRef, g_result.zones[k].hi,
                    tEnd, g_result.zones[k].lo,
                    PdFill(outline), (InpFillPercent > 0), true)) changed = true;

      string txt;
      if(kind == ZONE_OB) txt = (dir == DIR_UP ? "OB+" : "OB-");
      else                txt = ifvg ? "IFVG" : "FVG";
      // 标签锚在区间上沿的左侧
      if(UpsertText(lbl, g_result.zones[k].tRef, g_result.zones[k].hi, txt, outline)) changed = true;

      // HYBRID 基准：另画实体并集的 50% 中线（均值门槛）。
      // 依据（调研 §3b）：LuxAlgo 与 ICTKillzone 都指向 "body 的 50%"，而 Quantum 用全幅 50%
      // —— **数值不同**，所以必须显式画出来，不能让它成为隐藏假设。
      string mtName = OBJ_PREFIX + base + "_MT";
      if(g_result.zones[k].showMT)
      {
         AddSceneName(mtName);
         if(UpsertLine(mtName, g_result.zones[k].tRef, g_result.zones[k].ce,
                       tEnd, g_result.zones[k].ce, outline, STYLE_DASH, 1, false))
            changed = true;
      }
   }
}

//+------------------------------------------------------------------+
//|  渲染：EQH / EQL                                                 |
//+------------------------------------------------------------------+
void RenderEq(const datetime tStart, bool &changed)
{
   if(!InpShowEQHL || g_result.nEq <= 0) return;

   int from = 0;
   if(InpMaxEvents > 0 && g_result.nEq > InpMaxEvents) from = g_result.nEq - InpMaxEvents;

   for(int k = from; k < g_result.nEq; k++)
   {
      if(g_result.eqs[k].t2 < tStart) continue;

      // ⚠️ 对象名必须带 tier：同一个 bar2 可能在两层各成一个池
      //    （内部层与波段层都对同一根 K 线取枢轴），不带层级会互相覆盖。
      string tid = (g_result.eqs[k].tier == TIER_INTERNAL) ? "I" : "S";
      string nm  = OBJ_PREFIX + "EQ_"  + tid + "_" + IntegerToString(g_result.eqs[k].bar2);
      string lbl = OBJ_PREFIX + "EQL_" + tid + "_" + IntegerToString(g_result.eqs[k].bar2);
      string bnd = OBJ_PREFIX + "EQB_" + tid + "_" + IntegerToString(g_result.eqs[k].bar2);
      AddSceneName(nm);
      AddSceneName(lbl);

      color cl = g_result.eqs[k].taken ? InpColorWeak : InpColorEQ;

      // band：LuxAlgo 明确建议把 EQH/EQL 画成**容差带**而不是一条线 ——
      // 一条线会让人误以为"必须精确相等"，而它本质是"这一带都是同一池"。
      if(InpEqDrawBand && g_result.eqs[k].tol > 0.0)
      {
         AddSceneName(bnd);
         if(UpsertRect(bnd, g_result.eqs[k].t1, g_result.eqs[k].price + g_result.eqs[k].tol,
                       g_result.eqs[k].t2, g_result.eqs[k].price - g_result.eqs[k].tol,
                       PdFill(cl), (InpFillPercent > 0), true)) changed = true;
      }
      else
      {
         // 关掉 band 时显式回收带对象（否则它会留在图上，且回收段也可能还没轮到它）
         if(ObjectFind(0, bnd) >= 0) ObjectDelete(0, bnd);
      }

      if(UpsertLine(nm, g_result.eqs[k].t1, g_result.eqs[k].price,
                    g_result.eqs[k].t2, g_result.eqs[k].price,
                    cl, STYLE_SOLID, 2, false)) changed = true;

      string txt = (g_result.eqs[k].isHigh ? "EQH" : "EQL");
      if(g_result.eqs[k].count > 2) txt = txt + "x" + IntegerToString(g_result.eqs[k].count);
      datetime tMid = (datetime)(((long)g_result.eqs[k].t1 + (long)g_result.eqs[k].t2) / 2);
      double atr = (g_curATR > 0.0) ? g_curATR : _Point * 50.0;
      double py  = g_result.eqs[k].isHigh ? g_result.eqs[k].price + atr * 0.1
                                          : g_result.eqs[k].price - atr * 0.1;
      if(UpsertText(lbl, tMid, py, txt, cl)) changed = true;
   }
}

//+------------------------------------------------------------------+
//|  渲染：流动性扫荡 + 诱导                                         |
//+------------------------------------------------------------------+
void RenderSweeps(const datetime tStart, bool &changed)
{
   if(!InpShowSweep || g_result.nSweep <= 0) return;

   int from = 0;
   if(InpMaxSweep > 0 && g_result.nSweep > InpMaxSweep) from = g_result.nSweep - InpMaxSweep;

   for(int k = from; k < g_result.nSweep; k++)
   {
      if(g_result.sweeps[k].t < tStart) continue;

      // 取位来源过滤（M7 输入）
      bool isInt = (g_result.sweeps[k].tier == TIER_INTERNAL);
      if(InpSweepSrc == SMC_SWEEP_SWING    &&  isInt) continue;
      if(InpSweepSrc == SMC_SWEEP_INTERNAL && !isInt) continue;

      string nm  = OBJ_PREFIX + "SWP_" + IntegerToString(g_result.sweeps[k].refBar)
                   + "_" + IntegerToString(g_result.sweeps[k].bar);
      string lbl = OBJ_PREFIX + "SWPL_" + IntegerToString(g_result.sweeps[k].refBar)
                   + "_" + IntegerToString(g_result.sweeps[k].bar);
      AddSceneName(nm);
      AddSceneName(lbl);

      if(UpsertLine(nm, g_result.sweeps[k].tRef, g_result.sweeps[k].level,
                    g_result.sweeps[k].t,    g_result.sweeps[k].level,
                    InpColorSweep, STYLE_DOT, 1, false)) changed = true;

      double atr = (g_curATR > 0.0) ? g_curATR : _Point * 50.0;
      double py  = (g_result.sweeps[k].dir == DIR_UP)
                   ? g_result.sweeps[k].level + atr * 0.15
                   : g_result.sweeps[k].level - atr * 0.15;
      if(UpsertText(lbl, g_result.sweeps[k].t, py, "SWEEP", InpColorSweep)) changed = true;
   }

   if(InpShowIDM && g_result.nIdm > 0)
   {
      int f2 = 0;
      if(InpMaxEvents > 0 && g_result.nIdm > InpMaxEvents) f2 = g_result.nIdm - InpMaxEvents;
      for(int k = f2; k < g_result.nIdm; k++)
      {
         if(g_result.idm[k].t < tStart) continue;
         string nm = OBJ_PREFIX + "IDM_" + IntegerToString(g_result.idm[k].bar);
         AddSceneName(nm);
         double atr = (g_curATR > 0.0) ? g_curATR : _Point * 50.0;
         double py = g_result.idm[k].isHigh ? g_result.idm[k].price + atr * 0.25
                                            : g_result.idm[k].price - atr * 0.25;
         color cl = InpColorIDM;
         if(UpsertText(nm, g_result.idm[k].t, py, "IDM", cl, ANCHOR_CENTER)) changed = true;
      }
   }
}

//+------------------------------------------------------------------+
//|  渲染：Premium / Discount + EQ                                   |
//+------------------------------------------------------------------+
void RenderPremiumDiscount(const datetime &time[], const datetime tStart, bool &changed)
{
   if(!InpShowPremDisc || !g_result.pdValid) return;

   datetime tL = (g_result.pdHiT < g_result.pdLoT) ? g_result.pdHiT : g_result.pdLoT;
   if(tL < tStart) tL = tStart;
   datetime tR = time[0];

   double hi = g_result.pdHi, lo = g_result.pdLo;
   double eq = g_result.pdEq;
   if(hi <= lo) return;

   if(InpPdShowZones)
   {
      string nmHi = OBJ_PREFIX + "PD_PREM";
      string nmLo = OBJ_PREFIX + "PD_DISC";
      string lbHi = OBJ_PREFIX + "PD_PREML";
      string lbLo = OBJ_PREFIX + "PD_DISCL";
      AddSceneName(nmHi); AddSceneName(nmLo);
      AddSceneName(lbHi); AddSceneName(lbLo);

      if(UpsertRect(nmHi, tL, hi, tR, eq, PdFill(InpColorBear),
                    (InpFillPercent > 0), true)) changed = true;
      if(UpsertRect(nmLo, tL, eq, tR, lo, PdFill(InpColorBull),
                    (InpFillPercent > 0), true)) changed = true;

      datetime tMid = (datetime)(((long)tL + (long)tR) / 2);
      if(UpsertText(lbHi, tMid, (hi + eq) / 2.0, "PREMIUM", InpColorBear, ANCHOR_CENTER)) changed = true;
      if(UpsertText(lbLo, tMid, (eq + lo) / 2.0, "DISCOUNT", InpColorBull, ANCHOR_CENTER)) changed = true;
   }

   if(InpPdShowEQ)
   {
      string nmEq = OBJ_PREFIX + "PD_EQ";
      string lbEq = OBJ_PREFIX + "PD_EQL";
      AddSceneName(nmEq); AddSceneName(lbEq);
      if(UpsertLine(nmEq, tL, eq, tR, eq, InpColorEQLine, STYLE_DASH, 1, false)) changed = true;
      datetime tMid = (datetime)(((long)tL + (long)tR) / 2);
      if(UpsertText(lbEq, tMid, eq, "EQ", InpColorEQLine, ANCHOR_CENTER)) changed = true;
   }
}

//+------------------------------------------------------------------+
//|  渲染：强/弱高低点                                               |
//+------------------------------------------------------------------+
void RenderStrongWeak(const datetime tStart, bool &changed)
{
   if(!InpShowStrongWeak || g_result.nSW <= 0) return;

   int from = 0;
   if(InpMaxSW > 0 && g_result.nSW > InpMaxSW * 2) from = g_result.nSW - InpMaxSW * 2;

   for(int k = from; k < g_result.nSW; k++)
   {
      if(g_result.sw[k].t < tStart) continue;
      string txt;
      color  cl;
      switch(g_result.sw[k].kind)
      {
         case SW_STRONG_HIGH: txt = "SH"; cl = InpColorEQ;       break;
         case SW_WEAK_HIGH:   txt = "WH"; cl = InpColorWeak;     break;
         case SW_STRONG_LOW:  txt = "SL"; cl = InpColorEQ;       break;
         default:             txt = "WL"; cl = InpColorWeak;     break;
      }
      string nm = OBJ_PREFIX + "SWK_" + IntegerToString(g_result.sw[k].bar);
      AddSceneName(nm);
      double atr = (g_curATR > 0.0) ? g_curATR : _Point * 50.0;
      bool isHigh = (g_result.sw[k].kind == SW_STRONG_HIGH || g_result.sw[k].kind == SW_WEAK_HIGH);
      double py = isHigh ? g_result.sw[k].price + atr * 0.35 : g_result.sw[k].price - atr * 0.35;
      if(UpsertText(nm, g_result.sw[k].t, py, txt, cl, ANCHOR_CENTER)) changed = true;
   }
}

//+------------------------------------------------------------------+
//|  渲染：Killzone 时段矩形                                         |
//+------------------------------------------------------------------+
void RenderKillzones(const datetime tStart, bool &changed)
{
   if(!InpShowKillzone || !InpKzShowBoxes || g_result.nKz <= 0) return;

   int from = 0;
   if(InpKzMaxBoxes > 0 && g_result.nKz > InpKzMaxBoxes) from = g_result.nKz - InpKzMaxBoxes;

   for(int k = from; k < g_result.nKz; k++)
   {
      if(g_result.kz[k].t2 < tStart) continue;
      int s = g_result.kz[k].kz;
      if(s < 0 || s > 2) continue;

      color cl = InpColorKzAsia;
      string kn = "ASIA";
      if(s == 1) { cl = InpColorKzLondon; kn = "LONDON"; }
      if(s == 2) { cl = InpColorKzNY;     kn = "NEWYORK"; }

      string nm = OBJ_PREFIX + "KZ_" + kn + "_" + IntegerToString((long)g_result.kz[k].t1);
      AddSceneName(nm);
      if(UpsertRect(nm, g_result.kz[k].t1, g_result.kz[k].hi,
                    g_result.kz[k].t2, g_result.kz[k].lo,
                    PdFill(cl), (InpFillPercent > 0), true)) changed = true;

      if(InpKzShowLabels)
      {
         string lb = OBJ_PREFIX + "KZL_" + kn + "_" + IntegerToString((long)g_result.kz[k].t1);
         AddSceneName(lb);
         datetime tMid = (datetime)(((long)g_result.kz[k].t1 + (long)g_result.kz[k].t2) / 2);
         if(UpsertText(lb, tMid, g_result.kz[k].hi, kn, cl)) changed = true;
      }
   }
}

//+------------------------------------------------------------------+
//|  渲染：多周期结构（纯叠加，不参与任何判定）                       |
//+------------------------------------------------------------------+
void RenderMtf(const datetime tStart, bool &changed)
{
   if(!InpShowMTF || g_result.nEvtMtf <= 0) return;

   int from = 0;
   if(InpMaxEvents > 0 && g_result.nEvtMtf > InpMaxEvents) from = g_result.nEvtMtf - InpMaxEvents;

   for(int k = from; k < g_result.nEvtMtf; k++)
   {
      if(g_result.evtMtf[k].tBreak < tStart) continue;
      color cl = (g_result.evtMtf[k].dir == DIR_UP) ? InpColorBull : InpColorBear;
      string nm  = OBJ_PREFIX + "MTF_" + IntegerToString(g_result.evtMtf[k].refBar)
                   + "_" + IntegerToString(g_result.evtMtf[k].bar);
      string lbl = OBJ_PREFIX + "MTFL_" + IntegerToString(g_result.evtMtf[k].refBar)
                   + "_" + IntegerToString(g_result.evtMtf[k].bar);
      AddSceneName(nm); AddSceneName(lbl);

      if(UpsertLine(nm, g_result.evtMtf[k].tRef, g_result.evtMtf[k].level,
                    g_result.evtMtf[k].tBreak, g_result.evtMtf[k].level,
                    cl, STYLE_DASH, 2, false)) changed = true;

      string txt = "MTF " + (g_result.evtMtf[k].isChoch ? "CHoCH" : "BOS");
      datetime tMid = (datetime)(((long)g_result.evtMtf[k].tRef + (long)g_result.evtMtf[k].tBreak) / 2);
      if(UpsertText(lbl, tMid, g_result.evtMtf[k].level, txt, cl, ANCHOR_CENTER)) changed = true;
   }
}

//+------------------------------------------------------------------+
//|  场景层                                                          |
//+------------------------------------------------------------------+
// 注：high/low/close 不传入 —— 渲染层**只读结果层**（g_result 与 time）。
//     把原始 K 线也递进来会诱使渲染函数顺手做判定，破坏"分析层 → 结果层 → 场景层"的单向依赖。
void RenderScene(const int rates_total, const datetime &time[])
{
   bool changed = false;

   int winStart = InpWindow - 1;
   if(winStart < 1) winStart = 1;
   if(winStart > rates_total - 1) winStart = rates_total - 1;
   datetime tStart = time[winStart];

   //───────────────────────────────────────────────────────────────
   //  needDraw 指纹（硬约定 3）：每个可视化类别一项。
   //  全部是 O(1) 可得的"集合级"量；不含任何"正在形成的 bar 的 OHLC"。
   //  `time[0]` 这一项不可省：约 10 组对象以最新 bar 为右端，
   //  缺它则新 bar 到来时右端不延长（滞后一根）。
   //───────────────────────────────────────────────────────────────
   bool needDraw = (time[0] != g_lastT0) ||
                   (g_result.nPivSwing != g_lastNPivSwing) ||
                   (g_result.nPivInt   != g_lastNPivInt)   ||
                   (g_result.nEvtSwing != g_lastNEvtSwing) ||
                   (g_result.nEvtInt   != g_lastNEvtInt)   ||
                   (g_result.nEvtMtf   != g_lastNEvtMtf)   ||
                   (g_result.nZones    != g_lastNZones)    ||
                   (g_result.nEq       != g_lastNEq)       ||
                   (g_result.nSweep    != g_lastNSweep)    ||
                   (g_result.nIdm      != g_lastNIdm)      ||
                   (g_result.nKz       != g_lastNKz)       ||
                   (g_result.nSW       != g_lastNSW)       ||
                   (g_result.pdValid   != g_lastPdValid)   ||
                   (g_result.pdHi      != g_lastPdHi)      ||
                   (g_result.pdLo      != g_lastPdLo)      ||
                   (g_result.pdHiBar   != g_lastPdHiBar)   ||
                   (g_result.pdLoBar   != g_lastPdLoBar);

   if(needDraw)
   {
      g_lastT0        = time[0];
      g_lastNPivSwing = g_result.nPivSwing;
      g_lastNPivInt   = g_result.nPivInt;
      g_lastNEvtSwing = g_result.nEvtSwing;
      g_lastNEvtInt   = g_result.nEvtInt;
      g_lastNEvtMtf   = g_result.nEvtMtf;
      g_lastNZones    = g_result.nZones;
      g_lastNEq       = g_result.nEq;
      g_lastNSweep    = g_result.nSweep;
      g_lastNIdm      = g_result.nIdm;
      g_lastNKz       = g_result.nKz;
      g_lastNSW       = g_result.nSW;
      g_lastPdValid   = g_result.pdValid;
      g_lastPdHi      = g_result.pdHi;
      g_lastPdLo      = g_result.pdLo;
      g_lastPdHiBar   = g_result.pdHiBar;
      g_lastPdLoBar   = g_result.pdLoBar;

      SceneSetRebuild();

      // 底色只在 needDraw 帧读一次（跨进程调用，没必要每帧付）
      g_bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

      //── Killzone 先画（最底层背景）──
      RenderKillzones(tStart, changed);
      //── 区间：Premium/Discount 底色 → OB/FVG ──
      RenderPremiumDiscount(time, tStart, changed);
      RenderZones(time[0], tStart, changed);
      //── 线类事件 ──
      if(InpShowStructure)
         RenderStructEvents(g_result.evtSwing, g_result.nEvtSwing, TIER_SWING, tStart, changed);
      if(InpShowInternal)
         RenderStructEvents(g_result.evtInt, g_result.nEvtInt, TIER_INTERNAL, tStart, changed);
      RenderMtf(tStart, changed);
      RenderEq(tStart, changed);
      RenderSweeps(tStart, changed);
      //── 文字类 ──
      RenderSwingLabels(tStart, changed);
      RenderStrongWeak(tStart, changed);

      // 自适应下一帧的哈希容量（按本帧规模取 2 的幂，留 4× 余量）
      int want = 128;
      while(want < (g_setUsed + 1) * 4) want *= 2;
      g_setNextCap = want;
   }

   //── 回收过期对象 ──
   //  needDraw=false 意味着期望集合与上一帧完全一致 → 回收必为空操作，故跳过。
   if(needDraw)
   {
      for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
      {
         string nm = ObjectName(0, i);
         if(StringFind(nm, OBJ_PREFIX) != 0) continue;
         if(!SceneHas(nm))
         {
            ObjectDelete(0, nm);
            changed = true;
         }
      }
   }

   if(changed) ChartRedraw();
}

//+------------------------------------------------------------------+
//|  导出层：事件 CSV（自描述头 + 全类型归并）                        |
//+------------------------------------------------------------------+
void DumpEvents(const datetime &time[], const int rates_total)
{
   if(!InpDumpEvents) return;

   string fname = "SMCToolbox_events_" + _Symbol + "_" +
                  EnumToString((ENUM_TIMEFRAMES)_Period) + ".csv";
   int h = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
   {
      PrintFormat("SMCToolbox_DUMP 打开失败 name=%s err=%d", fname, GetLastError());
      return;
   }

   FileWrite(h, "# SMC_Toolbox event dump");
   FileWrite(h, StringFormat("# build=%s symbol=%s period=%s rates=%d",
                             BUILD_TAG, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period), rates_total));
   FileWrite(h, StringFormat("# structure swingLen=%d internalLen=%d break=%s dispBody=%.2f atrPeriod=%d",
                             InpSwingLen, InpInternalLen, EnumToString(InpBreakConfirm),
                             InpMinDisplaceBodyATR, InpATRPeriod));
   // 口径声明：本文件与 Structure 的口径差异必须留在归档里，
   // 否则日后无法判断两份 CSV 是否同一口径可比。
   FileWrite(h, "# pivot = symmetric-window(len), strict-both-sides, confirmDelay=len "
                "TIER-IS-WINDOW-BASED-NOT-ICT-RECURSIVE-HIERARCHY "
                "firstBreakLabel=BOS(not CHoCH) outsideBarByColor=true");
   FileWrite(h, StringFormat("# ob basis=%s lookback=%d cluster=%d hideInval=%s hideMit=%s "
                             "meanThreshold=body-union-50%% "
                             "NO-AUTHORITY(LuxAlgo: 'conventions genuinely differ')",
                             EnumToString(InpOBBasis), InpOBLookback, InpOBCluster,
                             (InpObHideInvalidated ? "true" : "false"),
                             (InpObHideMitigated ? "true" : "false")));
   FileWrite(h, StringFormat("# fvg minATR=%.2f hideFilled=%s "
                             "ifvg=BODY-CLOSE-THROUGH-FAR-SIDE(hardcoded,no switch) "
                             "ce=entry-not-criterion",
                             InpFvgMinATR, (InpFvgHideFilled ? "true" : "false")));
   FileWrite(h, StringFormat("# eqhl tier=%s tolATR=%.3f tolPts=%d maxBars=%d minCount=%d band=%s",
                             EnumToString(InpEqTier), InpEqToleranceATR,
                             InpEqTolerancePts, InpEqMaxBars, InpEqMinCount,
                             (InpEqDrawBand ? "true" : "false")));
   FileWrite(h, "# idm = last INTERNAL pivot of opposite dir between previous and current "
                "SWING event. STRICT-MODEL READING (LuxAlgo: strict vs loose is a taxonomy split)");
   FileWrite(h, StringFormat("# strongweak mode=%s "
                             "NO-AUTHORITY(not in LuxAlgo's 54 concepts nor ICTKillzone's 115 terms; "
                             "two conflicting community readings)",
                             EnumToString(InpSWMode)));
   FileWrite(h, StringFormat("# killzone autoTZ=%s nyShiftHours=%.1f serverGmtOffset=%.1f "
                             "gapGuardMin=%d asia=%s london=%s ny=%s",
                             (InpKzAutoTZ ? "true" : "false"),
                             g_nyShiftHours, ServerGmtOffsetHours(),
                             InpKzMaxGapMin, InpKzAsia, InpKzLondon, InpKzNewYork));
   FileWrite(h, StringFormat("# render premDisc=%s eq=%s swLabels=%s kz=%s mtf=%s(%s) "
                             "fillPct=%d maxEvents=%d window=%d windowStart=%s",
                             (InpShowPremDisc ? "true" : "false"),
                             (InpPdShowEQ ? "true" : "false"),
                             (InpShowSwingLabels ? "true" : "false"),
                             (InpShowKillzone ? "true" : "false"),
                             (InpShowMTF ? "true" : "false"),
                             EnumToString(InpMtfPeriod),
                             InpFillPercent, InpMaxEvents, InpWindow, TimeToString(time[0])));
   // 分类计数（别用 nZones 同时充当 ob 与 fvg 的数 —— 那会让归档自描述失真）
   int nOB = 0, nFVG = 0, nIFVG = 0;
   for(int k = 0; k < g_result.nZones; k++)
   {
      if(g_result.zones[k].kind == ZONE_OB) nOB++;
      else if(g_result.zones[k].inverted)   nIFVG++;
      else                                  nFVG++;
   }
   FileWrite(h, StringFormat("# counts pivSwing=%d pivInt=%d evtSwing=%d evtInt=%d evtMtf=%d "
                             "ob=%d fvg=%d ifvg=%d eq=%d sweep=%d idm=%d kz=%d sw=%d pdValid=%s",
                             g_result.nPivSwing, g_result.nPivInt,
                             g_result.nEvtSwing, g_result.nEvtInt, g_result.nEvtMtf,
                             nOB, nFVG, nIFVG, g_result.nEq,
                             g_result.nSweep, g_result.nIdm, g_result.nKz,
                             g_result.nSW, (g_result.pdValid ? "true" : "false")));
   FileWrite(h, "seq,type,tier,dir,bar,timeBar,refBar,timeRef,level,zoneLo,zoneHi,ce,"
                "state,strong,bodyATR,outside,extra");

   int seq = 0;

   // ① 波段层结构事件
   for(int k = 0; k < g_result.nEvtSwing; k++)
   {
      seq++;
      string xtra = "";
      if(g_result.evtSwing[k].isEqRef) xtra = "eqRef";
      if(g_result.evtSwing[k].conflict)
         xtra = (xtra == "" ? "" : xtra + "+") + "CONFLICT(bothSidesBroke)";
      FileWrite(h, StringFormat("%d,%s,%s,%s,%d,%s,%d,%s,%s,,,,%s,%s,%.3f,%s,%s",
                seq, (g_result.evtSwing[k].isChoch ? "CHOCH" : "BOS"),
                "SWING", (g_result.evtSwing[k].dir == DIR_UP ? "UP" : "DOWN"),
                g_result.evtSwing[k].bar, TimeToString(g_result.evtSwing[k].tBreak),
                g_result.evtSwing[k].refBar, TimeToString(g_result.evtSwing[k].tRef),
                DoubleToString(g_result.evtSwing[k].level, _Digits),
                "", (g_result.evtSwing[k].strong ? "OK" : "WEAK"),
                g_result.evtSwing[k].bodyATR,
                (g_result.evtSwing[k].outside ? "1" : "0"), xtra));
   }

   // ② 内部层结构事件
   for(int k = 0; k < g_result.nEvtInt; k++)
   {
      seq++;
      string xtra = g_result.evtInt[k].conflict ? "CONFLICT(bothSidesBroke)" : "";
      FileWrite(h, StringFormat("%d,%s,%s,%s,%d,%s,%d,%s,%s,,,,%s,%s,%.3f,%s,%s",
                seq, (g_result.evtInt[k].isChoch ? "CHOCH" : "BOS"),
                "INTERNAL", (g_result.evtInt[k].dir == DIR_UP ? "UP" : "DOWN"),
                g_result.evtInt[k].bar, TimeToString(g_result.evtInt[k].tBreak),
                g_result.evtInt[k].refBar, TimeToString(g_result.evtInt[k].tRef),
                DoubleToString(g_result.evtInt[k].level, _Digits),
                "", (g_result.evtInt[k].strong ? "OK" : "WEAK"),
                g_result.evtInt[k].bodyATR,
                (g_result.evtInt[k].outside ? "1" : "0"), xtra));
   }

   // ③ 区间（OB / FVG / IFVG）
   for(int k = 0; k < g_result.nZones; k++)
   {
      seq++;
      string ty = "OB";
      if(g_result.zones[k].kind == ZONE_FVG)
         ty = g_result.zones[k].inverted ? "IFVG" : "FVG";

      string st = "";
      if(g_result.zones[k].kind == ZONE_FVG)
         st = g_result.zones[k].inverted ? "INVERTED"
              : (g_result.zones[k].fillPct >= 1.0 ? "FILLED"
                 : (g_result.zones[k].fillPct > 0.0 ? "PARTIAL" : "OPEN"));
      else
         st = g_result.zones[k].invalidated ? "INVALID"
              : (g_result.zones[k].mitigated ? "MITIGATED" : "FRESH");

      // 数值列统一用 DoubleToString 预先转好再拼 —— 不用 printf 的 %.*f 宽度星号，
      // 它在 MQL5 上的行为不值得赌（拼错不会报错，只会写出垃圾 CSV）。
      // tier：FVG 的锚点是普通 K 线（按构造不是结构点），读作分级无意义 → 输出 n/a。
      // 与仓库既有纪律一致：不能让 n/a 被读成"该锚点无分级"。
      FileWrite(h, StringFormat("%d,%s,%s,%s,%d,%s,%d,%s,,%s,%s,%s,%s,%s,,%s,fill=%s",
                seq, ty,
                (g_result.zones[k].kind != ZONE_OB ? "n/a"
                 : (g_result.zones[k].tier == TIER_INTERNAL ? "INTERNAL" : "SWING")),
                (g_result.zones[k].dir == DIR_UP ? "UP" : "DOWN"),
                g_result.zones[k].bar, TimeToString(g_result.zones[k].tBar),
                g_result.zones[k].refBar, TimeToString(g_result.zones[k].tRef),
                // level 列对区间恒为空：区间用的三列是 zoneLo/zoneHi/ce，不是单点价位
                DoubleToString(g_result.zones[k].lo, _Digits),
                DoubleToString(g_result.zones[k].hi, _Digits),
                DoubleToString(g_result.zones[k].ce, _Digits),
                st, (g_result.zones[k].strong ? "OK" : "WEAK"), "",
                DoubleToString(g_result.zones[k].fillPct, 2)));
   }

   // ④ EQH / EQL
   for(int k = 0; k < g_result.nEq; k++)
   {
      seq++;
      string st = g_result.eqs[k].taken ? "TAKEN" : (g_result.eqs[k].swept ? "SWEPT" : "INTACT");
      FileWrite(h, StringFormat("%d,%s,%s,%s,%d,%s,%d,%s,%s,,,,%s,,,,count=%d;tol=%s",
                seq, (g_result.eqs[k].isHigh ? "EQH" : "EQL"),
                (g_result.eqs[k].tier == TIER_INTERNAL ? "INTERNAL" : "SWING"),
                (g_result.eqs[k].isHigh ? "UP" : "DOWN"),
                g_result.eqs[k].bar2, TimeToString(g_result.eqs[k].t2),
                g_result.eqs[k].bar1, TimeToString(g_result.eqs[k].t1),
                DoubleToString(g_result.eqs[k].price, _Digits), st,
                g_result.eqs[k].count,
                DoubleToString(g_result.eqs[k].tol, _Digits)));
   }

   // ⑤ 扫荡
   for(int k = 0; k < g_result.nSweep; k++)
   {
      seq++;
      FileWrite(h, StringFormat("%d,SWEEP,%s,%s,%d,%s,%d,%s,%s,,,,DONE,,,,",
                seq, (g_result.sweeps[k].tier == TIER_INTERNAL ? "INTERNAL" : "SWING"),
                (g_result.sweeps[k].dir == DIR_UP ? "UP" : "DOWN"),
                g_result.sweeps[k].bar, TimeToString(g_result.sweeps[k].t),
                g_result.sweeps[k].refBar, TimeToString(g_result.sweeps[k].tRef),
                DoubleToString(g_result.sweeps[k].level, _Digits)));
   }

   // ⑥ 诱导
   for(int k = 0; k < g_result.nIdm; k++)
   {
      seq++;
      FileWrite(h, StringFormat("%d,IDM,INTERNAL,%s,%d,%s,,,,,,,,,,,",
                seq, (g_result.idm[k].isHigh ? "UP" : "DOWN"),
                g_result.idm[k].bar, TimeToString(g_result.idm[k].t)));
   }

   // ⑦ 强弱高低点
   for(int k = 0; k < g_result.nSW; k++)
   {
      seq++;
      string ty;
      switch(g_result.sw[k].kind)
      {
         case SW_STRONG_HIGH: ty = "STRONG-HIGH"; break;
         case SW_WEAK_HIGH:   ty = "WEAK-HIGH";   break;
         case SW_STRONG_LOW:  ty = "STRONG-LOW";  break;
         default:             ty = "WEAK-LOW";    break;
      }
      FileWrite(h, StringFormat("%d,%s,SWING,%s,%d,%s,,,,,,,,,,,",
                seq, ty, (g_result.sw[k].kind == SW_STRONG_HIGH || g_result.sw[k].kind == SW_WEAK_HIGH) ? "UP" : "DOWN",
                g_result.sw[k].bar, TimeToString(g_result.sw[k].t)));
   }

   // ⑧ 多周期结构
   for(int k = 0; k < g_result.nEvtMtf; k++)
   {
      seq++;
      FileWrite(h, StringFormat("%d,%s,MTF,%s,%d,%s,%d,%s,%s,,,,%s,%s,%.3f,,",
                seq, (g_result.evtMtf[k].isChoch ? "CHOCH" : "BOS"),
                (g_result.evtMtf[k].dir == DIR_UP ? "UP" : "DOWN"),
                g_result.evtMtf[k].bar, TimeToString(g_result.evtMtf[k].tBreak),
                g_result.evtMtf[k].refBar, TimeToString(g_result.evtMtf[k].tRef),
                DoubleToString(g_result.evtMtf[k].level, _Digits),
                (g_result.evtMtf[k].strong ? "OK" : "WEAK"),
                g_result.evtMtf[k].bodyATR));
   }

   FileClose(h);
}

//+------------------------------------------------------------------+
//|  诊断（仅 InpDebugShowRef，且只在全量帧调用）                     |
//+------------------------------------------------------------------+
void DbgReport(const datetime &time[], const int rates_total)
{
   if(!InpDebugShowRef) return;

   // 数组方向自检：本文件全部索引逻辑按「0 = 最新」编写。
   PrintFormat("SMCToolbox_ORIENT time[0]=%s time[rates-1]=%s -> %s",
               TimeToString(time[0]), TimeToString(time[rates_total - 1]),
               (time[0] >= time[rates_total - 1]) ? "SERIES(0=newest)" : "NON-SERIES(0=oldest)");

   // 枢轴确认等式自检：g_dbgPivotBad **必须恒为 0**。
   // 非 0 即说明"确认延迟 = len"这条不变量被破坏了（右窗口边界写错）。
   PrintFormat("SMCToolbox_PIVOT found=%d invariantViolations=%d (must be 0) swingLen=%d internalLen=%d "
               "invertedLevelsRejected=%d",
               g_dbgPivotFound, g_dbgPivotBad, InpSwingLen, InpInternalLen, g_dbgInverted);

   // 分布自检（防"方向写反"这类静默错误 —— 仓库吃过这个亏）：
   //  FVG 两个方向都必须存在；若全为同一方向 → 判据写反。
   int fvgUp = 0, fvgDn = 0, fvgFull = 0, fvgPart = 0;
   for(int k = 0; k < g_result.nZones; k++)
   {
      if(g_result.zones[k].kind != ZONE_FVG) continue;
      if(g_result.zones[k].dir == DIR_UP) fvgUp++; else fvgDn++;
      if(g_result.zones[k].fillPct >= 1.0) fvgFull++;
      else if(g_result.zones[k].fillPct > 0.0) fvgPart++;
   }
   int obFresh = 0, obMit = 0, obInv = 0;
   for(int k = 0; k < g_result.nZones; k++)
   {
      if(g_result.zones[k].kind != ZONE_OB) continue;
      if(g_result.zones[k].invalidated) obInv++;
      else if(g_result.zones[k].mitigated) obMit++;
      else obFresh++;
   }
   int choch = 0, bos = 0;
   for(int k = 0; k < g_result.nEvtSwing; k++)
   {
      if(g_result.evtSwing[k].isChoch) choch++; else bos++;
   }

   PrintFormat("SMCToolbox_DIST fvg(up=%d dn=%d full=%d partial=%d) ob(fresh=%d mit=%d inval=%d) "
               "swingEvents(bos=%d choch=%d) eq=%d sweep=%d idm=%d kz=%d sw=%d mtf=%d",
               fvgUp, fvgDn, fvgFull, fvgPart, obFresh, obMit, obInv,
               bos, choch, g_result.nEq, g_result.nSweep, g_result.nIdm,
               g_result.nKz, g_result.nSW, g_result.nEvtMtf);

   if(fvgUp > 0 && fvgDn == 0)
      Print("SMCToolbox_WARN 所有 FVG 都是 UP 方向 —— 极可能是方向判据写反（见 plan §6 A3）");
   if(fvgDn > 0 && fvgUp == 0)
      Print("SMCToolbox_WARN 所有 FVG 都是 DOWN 方向 —— 极可能是方向判据写反（见 plan §6 A3）");
   if(choch == 0)
      Print("SMCToolbox_WARN CHoCH 恒为 0 —— 趋势翻转分支可能是死代码（见 plan §6 A3）");
   if(g_dbgPivotBad != 0)
      PrintFormat("SMCToolbox_WARN 枢轴确认等式被破坏 %d 次 —— 右窗口边界有误", g_dbgPivotBad);
   if(g_dbgInverted > 0)
      PrintFormat("SMCToolbox_NOTE 拦截了 %d 次高/低位倒挂（已丢弃该状态重建）—— "
                  "正常应极少；持续增长说明枢轴次序异常", g_dbgInverted);
}

//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpSwingLen < 1 || InpInternalLen < 1)
   {
      Print("SMCToolbox: 枢轴半窗必须 >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpATRPeriod < 2)
   {
      Print("SMCToolbox: InpATRPeriod 必须 >= 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpWindow < 2)
   {
      Print("SMCToolbox: InpWindow 必须 >= 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpInternalLen >= InpSwingLen)
   {
      // 不是致命错误（用户可以有意这么做），但几乎总是配置失误 → 明确提示。
      PrintFormat("SMCToolbox 警告: 内部层半窗(%d) >= 波段层半窗(%d)，两层结构将几乎重合",
                  InpInternalLen, InpSwingLen);
   }

   // 解析 Killzone 时段（解析失败 → 该时段禁用，不中断初始化）
   g_kzOk[0] = ParseHHMM(InpKzAsia,    g_kzStart[0], g_kzEnd[0]);
   g_kzOk[1] = ParseHHMM(InpKzLondon,  g_kzStart[1], g_kzEnd[1]);
   g_kzOk[2] = ParseHHMM(InpKzNewYork, g_kzStart[2], g_kzEnd[2]);
   if(!g_kzOk[0]) PrintFormat("SMCToolbox: 亚洲时段格式非法 '%s'（应为 HH:MM-HH:MM）→ 已禁用", InpKzAsia);
   if(!g_kzOk[1]) PrintFormat("SMCToolbox: 伦敦时段格式非法 '%s' → 已禁用", InpKzLondon);
   if(!g_kzOk[2]) PrintFormat("SMCToolbox: 纽约时段格式非法 '%s' → 已禁用", InpKzNewYork);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("SMC Toolbox(%d/%d)", InpSwingLen, InpInternalLen));

   // 无条件打印：确认 MT5 加载的正是本文件编译出的 .ex5。
   // 版本号只有一个来源 = BUILD_TAG。
   PrintFormat("SMC_Toolbox 已初始化 | build=%s | swingLen=%d internalLen=%d "
               "break=%s atr=%d | modules struct=%s int=%s swLbl=%s ob=%s fvg=%s ifvg=%s "
               "eqhl=%s sweep=%s idm=%s premDisc=%s sw=%s kz=%s mtf=%s | window=%d analysis=%d "
               "kzShift=%.1f",
               BUILD_TAG, InpSwingLen, InpInternalLen, EnumToString(InpBreakConfirm), InpATRPeriod,
               (InpShowStructure ? "y" : "n"), (InpShowInternal ? "y" : "n"),
               (InpShowSwingLabels ? "y" : "n"), (InpShowOB ? "y" : "n"),
               (InpShowFVG ? "y" : "n"), (InpShowIFVG ? "y" : "n"),
               (InpShowEQHL ? "y" : "n"), (InpShowSweep ? "y" : "n"),
               (InpShowIDM ? "y" : "n"), (InpShowPremDisc ? "y" : "n"),
               (InpShowStrongWeak ? "y" : "n"), (InpShowKillzone ? "y" : "n"),
               (InpShowMTF ? "y" : "n"), InpWindow, InpAnalysisWindow, g_nyShiftHours);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  OnDeinit：只清理本指标自己的对象（前缀隔离）                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("SMC_Toolbox 已卸载 | build=%s | reason=%d | evtSwing=%d zones=%d",
               BUILD_TAG, reason, g_result.nEvtSwing, g_result.nZones);
   ObjectsDeleteAll(0, OBJ_PREFIX);
}

//+------------------------------------------------------------------+
//|  OnCalculate                                                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < 4) return(rates_total);

   //── 显式锁定时序方向（硬约定 1）──
   //  不依赖终端默认值：本终端实测交给指标的数组 index 0 是**最旧**，
   //  而全文件按 index 0 = 最新编写。不显式声明 → 分析的是最老那段历史，
   //  对象坐标全对却整体落在可视区之外（看起来就是"什么都没画"）。
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   // 用静态 bar 计数判断"新 bar"，比 prev_calculated 更可靠
   static int s_lastRates = 0;
   bool firstRun = (s_lastRates == 0);
   bool newBar   = (rates_total != s_lastRates);
   s_lastRates   = rates_total;

   //── 快路径：同 bar tick 且启用复用 → 直接返回 ──
   //  本指标**没有**需要每 tick 跟手的元素（不像 Structure 有 IC-CISD 与
   //  HTF 蜡烛），故快路径什么都不做。这是有意为之：工具箱全部元素都是
   //  收盘确认口径的，未收盘 bar 上重算只会得到会反悔的结果。
   if(InpReuseResultOnTick && !firstRun && !newBar)
      return(rates_total);

   ComputeSMC(rates_total, time, open, high, low, close);
   RenderScene(rates_total, time);
   DumpEvents(time, rates_total);
   DbgReport(time, rates_total);   // 在快路径之后（硬约定 6）

   return(rates_total);
}
//+------------------------------------------------------------------+
