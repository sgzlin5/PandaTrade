//+------------------------------------------------------------------+
//|  Structure.mq5                                            |
//|  结构标记指标 — 冲动移动 / 有效回撤(MSS) / BOS 状态机              |
//|  主图对象绘制：结构线(OBJ_TREND) + MSS/BOS 标注(横向虚线)       |
//+------------------------------------------------------------------+
//|  ⚠️ 多实例限制（v1.50-s59 明文记录，未在代码里强制）              |
//|  · 一张图挂**两份**本指标 = 不支持。对象名不带实例身份（只有 bar  |
//|    下标），且两份共用同一批模块全局（g_lastRates/g_lastT0/…）：  |
//|    各自的全量帧会把对方的对象判为"未注册"删掉，OnDeinit 的        |
//|    ObjectsDeleteAll(0, OBJ_PREFIX) 也会连对方一起清空；CSV 同名   |
//|    文件互相覆盖（文件名只由 符号+周期 决定）。                    |
//|  · **跨图表**多实例（不同周期各挂一张图）是安全的 —— 图表各有独立 |
//|    对象命名空间与独立模块实例，结构上不可能互相影响。            |
//|  · 要同图对比两套参数：请开两个图表窗口，各自挂一份。            |
//+------------------------------------------------------------------+
//|  架构（三层，按 /improve-codebase-architecture 审查加深）：         |
//|    ① 分析层  ComputeStructure(series, params) → StructureResult   |
//|              纯输入原始 K 线与参数，输出语义事件（节点/MSS/BOS/盒）|
//|              状态机运行态封装在 struct SState，不再引用参数穿透    |
//|    ② 结果层  StructureResult：一条事件一条记录（struct），         |
//|              消灭 bar/dir/ref 平行数组，locality 提升              |
//|    ③ 场景层  RenderScene(result)：语义锚定 ID（Seg_<bar1>_<bar2>、|
//|              MSS_<refBar>_<eventBar>、BOS_<refBar>_<eventBar>、    |
//|              Box_<motherBar>），                                        |
//|              调和式同步：存在才更新、缺失才创建、过期才回收，      |
//|              仅在场景实际变化时 ChartRedraw → 消除每 tick 闪烁     |
//|    性能层    InpReuseResultOnTick：同 bar tick 复用分析结果，       |
//|              仅新 bar 到达才全量重算（swing 确认会回溯性改变尾部， |
//|              因此不做天真增量，只做整段复用 + 新 bar 全量重算）     |
//|              InpAnalysisWindow：限制分析窗口范围（默认 500），       |
//|              配合 Wilder 平滑 ATR（O(n) 单遍扫描），               |
//|              v1.47 性能优化的两大支柱                                |
//|              v1.48 性能优化（"门控"路线，不做对象属性缓存）：        |
//|               ① 整段绘制门控 needDraw：节点/窗口/盒/事件八项指纹    |
//|                  全部未变时整段跳过调和 → ObjectGet* 只发生在结构    |
//|                  真的变化的帧上                                      |
//|               ② ChartRedraw 门控：仅场景真的变化才重绘             |
//|               ③ UpdateLiveLeg 门控前置 + 同 bar 早退 + 0.1×ATR      |
//|                  位移阈值（原实现每 tick 白扫窗口且必重绘）          |
//|               ④ ChartGetDouble 惰性求值：dashStep 只在 ATR 兜底时     |
//|                  才查图表价格范围（原无条件每帧 2 次）               |
//|               ⑤ validBars 按分析窗口分配（原按 rates_total），      |
//|                  删除死代码 boxRef；atrArr 只分配 [0,analysisStart]  |
//|               ⑥ 场景成员判定改哈希集合（SceneHas）：回收段从            |
//|                  O(total × kept) 降为 O(total)                      |
//|               ⑦ 【致命】changed = changed || Upsert*() 全部改成      |
//|                  if(Upsert*()) changed = true;                      |
//|                  MQL5 的 || 会短路：一旦 changed 为真，右侧的       |
//|                  Upsert* 根本不被求值 → 除第一个对象外全部不创建。   |
//|                  代价是"画面上只有 1 个对象"，且不报任何错。        |
//|               ⑧ 【致命】OnCalculate 入口显式 ArraySetAsSeries(x,true) |
//|                  锁定时序方向，并把 analysisStart 从                 |
//|                  rates_total-InpAnalysisWindow 改为 InpAnalysisWindow-1|
//|  教训：本终端交给 OnCalculate 的数组**不是**时序（实测 index 0 = 最旧），|
//|  而全文件按 index 0 = 最新编写。后果不是报错，而是"分析的是最老的一段  |
//|  历史、对象坐标全对却整体落在可视区之外"——看起来就是"什么都没画"。   |
//|  凡涉及数组方向的代码，一律显式 ArraySetAsSeries，不要依赖默认值。    |
//|                                                                     |
//|  【教训】v1.48 曾尝试"对象属性镜像缓存"来避免 ObjectGet*，但：        |
//|    · 该前提不成立 —— ObjectsTotal/ObjectName/ObjectGet* 在当前图表上  |
//|      是**直接访问**（MQL5 文档），并非跨进程 IPC，省不下什么；        |
//|    · 镜像引入的槽位分配/压缩逻辑反而出 bug（镜像被压成 1 格 →        |
//|      除第一个外的结构线全部建不出来）。                              |
//|  故已整体移除，改为上面的门控路线。性能靠"少进循环"，不靠"缓存对象"。 |
//+------------------------------------------------------------------+
//|  算法（状态机，全量计算 + 窗口截断绘制）：                         |
//|    注意：MQL5 时序列索引 0 = 最新、rates_total-1 = 最旧           |
//|    折线极值点 = 相邻摆动点(fractal swing)：                        |
//      swing high: high[i]>high[prev] && high[i]>high[next]   （严格不等：相邻等高不算 swing）
//      swing low : low[i]<low[prev]  && low[i]<low[next]
//|    MSS/BOS 基于折线极值点突破确认：                                |
//|      UP 中突破前高(HH) → BOS(结构延续)；跌破前低(HL) → MSS(反转)  |
//|      DOWN中跌破前低(LL) → BOS(结构延续)；升破前高(LH) → MSS(反转) |
//|    StructureMode 三种结构模式（InpMode）：                         |
//|      FractalSwing：保留原始纯 fractal swing 逻辑                   |
//|      ShortTerm（默认）：有效回撤过滤 + 内包盒 + 外包 + 实时腿      |
//|      StrictICT：BOS/MSS 仅在收盘突破结构位后确认                   |
//|    最小 swing 幅度过滤：结构点腿长须达最小点数，可叠加 ATR/比例   |
//|    MSS 只突破"有效 HL/LH"：HL/LH 基准仅由通过幅度过滤的 swing 更新|
//|    破位确认切换：InpBreakConfirm（实体/收盘/影线），StrictICT 下限为收盘 |
//|    内包盒/外包 K 线单独处理（各自过幅度过滤），不并入 swing 判定   |
//|    MSS/BOS 虚线画在"被突破的结构位"（ref），且 ref 恒为已确认节点  |
//|    HH/HL/LL/LH 极值价格（每个标记可反查结构节点，级别不混）        |
//|    MSS 方向切换时重置反向基准 → 切换及时、ref 不被提前更新/覆盖   |
//|    主/内部结构分层：主结构驱动 MSS/BOS；内部结构浅色虚线单绘       |
//|    LH/HL 基准仅在"实际成为节点"时更新 → ref 严格对应折线极值      |
//|    水平线从"被突破极值节点 bar"起、至突破 bar，画在 refPrice（标准）  |
//|    线=结构位、字=突破事件；标签方向感知（UP 上/DOWN 下，ATR×0.15）|
//|    相邻 swing 最小间隔过滤（InpMinBarsBetweenSwings，滤高频折返）  |
//|    InpDebugShowRef：标签显示 refBar/refPrice 便于反查绑定           |
//|    虚线终点：首次回踩/反抽（触及 ref）或固定 N 根或下一节点       |
//+------------------------------------------------------------------+

#property copyright   "PandaTrade"
#property version     "1.50"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- 结构模式枚举 ---
enum ENUM_STRUCTURE_MODE
{
   MODE_FRACTAL_SWING,   // Fractal Swing（原始逻辑）
   MODE_SHORT_TERM,      // 短线画法（内包/外包/有效回撤/实时腿）
   MODE_STRICT_ICT       // 严格 ICT（BOS/MSS 收盘确认）
};

enum ENUM_LINE_END
{
   LINE_END_BREAK,          // 标准（默认）：被突破结构极值 → 突破K线，价格穿越位线即停
   LINE_END_HIT_ZIGZAG,     // 从折线极值点向右，碰到结构折线再停（后续回踩/反抽点）
   LINE_END_FIRST_RETEST,   // 首次回踩/反抽（触及 ref 即停，向右延伸）
   LINE_END_FIXED_BARS,     // 固定 N 根（向右延伸）
   LINE_END_NEXT_NODE       // 下一个结构节点（向右延伸）
};

// 阶段 21：PD Array（FVG / OB）区域矩形的**右端**策略。
//
// 【为什么需要它 —— 实测，不是观感】
//   在 XAUUSD.ct M5 的一次真实加载里（2026-09-24 15:06，v1.50-s27），
//   `STRUCT_OBJDUMP` 报出 14 个填充矩形；用它们的时间跨度 × 价格高度去铺
//   可视窗口（210 个 5 分钟格 × 108 个 0.25 价格格）做并集，得到：
//
//     一律画到当前 bar（原行为）        → 覆盖 **46.1%** 的图表面积
//     右端收到 起点 + 30 分钟           → 18.8%
//     右端收到 起点 + 60 分钟           → 21.9%
//     右端收到 起点 + 120 分钟          → 26.4%
//
//   其中**单块 `OB_183_176` 就占 49.2%**（跨 975 分钟 × 11.44 点）——
//   即"一块 OB 盖掉半个图"。而同一份数据里"把弱化的块改为不填充"只省 2.7%
//   （弱化块大多压在正常块上），故**这一项的收益远大于调整弱化配色**。
//
// ⚠️ 默认仍是 `PD_END_NOW`（原行为）—— 因为 plan §19.6-D20 记录过：
//   他的配图里 OB 就是向右延伸到现价区域，画到当前 bar **符合他的画法**。
//   所以这是一个**可选**的降噪开关，不是改正一个错误。
enum ENUM_PD_END
{
   PD_END_NOW,      // 到当前 bar（默认，= 他的画法；代价：失效的位也一路画到底）
   PD_END_RETEST,   // 到**首次被回踩**（价格首次回到区间内）那根 bar
   PD_END_FIXED     // 到起点 + InpPDRightBars 根
};

// 阶段 25：HTF 蜡烛**画在哪**。
//
//  动机（实测）：主图填充覆盖率从 44.2% 降到 10.8% 之后，HTF 实体成了**残余噪声里最大的一块**
//  （4 根 H4 实体自占可视区 8.5%，占整体 10.8% 的 79%）。用户要求把它挪出价格区。
//
//  ⚠️ MT5 **没有**"把副图放到右侧"的能力（副图只能纵向堆在主图下方），
//     故"右边"只能这么做：用 Chart Shift 在主图右端预留一块**未来留白**，
//     把整排蜡烛画在 `time[0]` **之后**的时段里。
//     代价：蜡烛落在**尚未发生的时间**上（时间语义变怪）。
//     收益：**保留价格对齐** —— 这正是它优于副图的地方（副图有自己的刻度）。
//
//  ⚠️ 对象名一律用**蜡烛真实的开盘时间**做键，**不用画出来的坐标** ——
//     右侧模式下一缩放坐标就变，若拿它当键，所有对象会被判为"过期"而全量重建。
enum ENUM_HTF_PLACE
{
   HTF_PLACE_OVERLAY,   // 叠加在真实时间位置（= 他的画法；会与主图 K 线重叠）
   HTF_PLACE_RIGHT      // 挪到右侧留白区（默认；自动开 Chart Shift，卸载时还原）
};

// 阶段 44（用户要求）：HTF 蜡烛周期**是否自动推导**。
//  自动规则（用户给定）：专用映射 1M→5M、5M→30M、30M→4H；表外按"**≥4 倍**"原则。
//  ⚠️ 实现上**不写死那张表** —— 在"标准阶梯"上取**第一个 ≥ 4×图表周期**的档位，
//     即可**逐行复现**用户给的三条（这就是它们不是巧合的证据）：
//       1M(60s)   ×4=240   → 阶梯首个 ≥240   = M5(300)    ✓ 与表一致
//       5M(300s)  ×4=1200  → M15(900)<1200   → M30(1800)  ✓ 与表一致
//       30M(1800s)×4=7200  → H1(3600)<7200   → H4(14400)  ✓ 与表一致
//  ⚠️ 阶梯只收**券商实际提供的经典档位**（M1/M5/M15/M30/H1/H4/D1/W1/MN1）——
//     这正是"1M 得到 M5 而不是 M4"的原因：M4 不在阶梯上。若把 M2/M3/M4/M6/M10/M12
//     之类也放进候选，1M 会推出 M4，就与用户给的表冲突了。
enum ENUM_HTF_TF_MODE
{
   HTF_TF_MANUAL,   // 手动：用 InpCandleTF 指定的周期
   HTF_TF_AUTO      // 自动：按"≥4 倍"原则从图表周期推导（1M→5M / 5M→30M / 30M→4H …）
};

// 破位确认方式（MSS / BOS 共用同一判据）。
//  TTrades 的原文是 "closes above or below a swing high or swing low" → BREAK_CLOSE；
//  本项默认 BREAK_BODY（实体完全越过），比他的字面口径更严。
enum ENUM_BREAK_CONFIRM
{
   BREAK_BODY,    // 实体完全越过（实体两端均在结构位之外）—— 默认
   BREAK_CLOSE,   // 收盘越过（= 他的字面口径 "closes above or below"）
   BREAK_WICK     // 影线触及即确认（最宽松）
};

//--- 输入参数 ---
input group "== 结构模式 =="
input ENUM_STRUCTURE_MODE InpMode = MODE_SHORT_TERM;   // 结构模式

input group "== 结构标记设置 =="
input int   InpWindow          = 200;            // 时间窗口（根K线，仅绘制窗口内结构）
input bool  InpShowMSS         = true;           // 显示 MSS 标注
input bool  InpShowBOS         = true;           // 显示 BOS 标注

input group "== 有效回撤过滤 =="
input bool   InpEnableRetraceFilter = true;      // 启用有效回撤过滤（滤除碎结构点）
input int    InpMinRetracePoints    = 100;       // 最小回撤点数（Points）
input double InpMinRetraceATR       = 0.5;       // 最小回撤 ATR 倍数
input double InpMinRetraceRatio     = 0.236;     // 最小回撤占前一段幅度比例
input int    InpATRPeriod           = 14;        // ATR 周期
input int    InpMinSwingAmplitude   = 0;         // 最小 swing 幅度（点数，0=关闭）
input int    InpMinBarsBetweenSwings = 2;         // 相邻 swing 最小间隔（根数，滤高频小折返）
// 阶段 1-B：failure swing 剔除门槛。
// 他的原话是 failure swing "forms too close to a prior high or low and lacks proper
// range separation" → 忽略，但又明确说"没有严格数值公式"（"If it is too close, expect
// it to be taken."）→ 故本阈值是自定近似。
// 判据：swing 与「上一个同类型 swing」的价格距离 < 门槛 × ATR → failure swing，不确认。
// 与既有过滤的区别：InpMinSwingAmplitude / IsValidRetrace 作用于「腿长」，
// 本项作用于「同类型相邻 swing 之间」，是新维度，二者不重叠。
// 0 = 关闭（此时可单独观察 1-A 严格化带来的变化，便于归因）。
input double InpMinSeparationATR  = 0.5;          // failure swing 剔除（×ATR，0=关闭）

input group "== 内包/外包处理（ShortTerm / StrictICT 模式生效）=="
input bool InpUseInsideBarBox    = true;         // 记录内包盒区间并处理突破
input bool InpDrawInsideBox      = true;         // 绘制内包盒矩形
// ⚠️ 原 `InpUseOutsideBarLogic`（"外包 K 线单独处理"）已于 v1.49-s15 删除：
//    独立评审机械核实它是**哑输入**（全文仅声明处出现 1 次，从未被引用）。
//    外包 K 线实际由 CheckBreakAgainstRefs 的同 bar 双破分支处理，与该开关无关。

// ⚠️ 【阶段 11 起整组「主/内部结构」输入已删除，共 5 项】
//  1) `InpUseMainFilter` / `InpMainFilterATR` / `InpMainFilterRatio`
//     用"腿长门槛"挑选驱动 refHigh/refLow 的 swing。**该门槛不是 TTrades 的定义**
//     ——他的 protected swing 由"收盘穿过进入该位的那一串反向 K 线"定义（即 CISD 触发），
//     故 ref 改由 SetProtectedFromCisd() 在 CISD 触发时建立，门槛整体删除。
//  2) `InpDrawSubStructure` / `InpColorSubStructure`
//     两项从未被任何代码引用（哑输入），且"主/内部结构"**不是他的概念**
//     （他的层级是 short/intermediate/long-term，且是"摆动点上的标签"而非多条结构线）。
//     故一并删除；若日后要做 tier 分级显示，应新增一个语义正确的输入，见 plan §19.7-B。

input group "== 突破确认 =="
// 破位判据（MSS / BOS 共用）。用户要求：**放宽为影线扫过即算** → 默认 BREAK_WICK。
// ⚠️ 严格度全序：BODY ⊂ CLOSE ⊂ WICK。WICK 最宽松 —— 影线一碰就命中。
//    他在这件事上的原话是 "price displaces and **closes** above or below a swing high
//    or swing low"（= BREAK_CLOSE）。故当前默认**比他的字面口径更宽**。
//    "影线扫过不算确认"也是他自己的话（"The sweep itself is not the confirmation."）——
//    这条由**位移判据**承担：影线触发但位移不足时只记为弱事件、不翻转趋势，
//    且**不消耗该位**（见 RefPoint.touched），后续真正的突破仍能出信号。
input ENUM_BREAK_CONFIRM InpBreakConfirm = BREAK_WICK;  // 破位确认方式（影线/收盘/实体）

// +-----------------------------------------------------------------+
// | 阶段 69/70（节点级口径，用户 2026-09-30 两轮裁定）               |
// |                                                                  |
// | 症状：M1 上涨段里"肉眼明显的高点破位"被标成 CHoCH，用户框出两处；  |
// |   第二轮（加载了 s55 之后仍在）用户说「应该都是**内部的 BOS**」。  |
// | 成因（两层）：                                                    |
// |   ① 破位口径：节点层直接复用 BrokeLevel()，而 InpBreakConfirm 默认  |
// |      BREAK_WICK ⇒ **影线一扫即破位、即翻转**。引擎本有"位移不足只记 |
// |      弱事件、不翻转趋势"的闸门（引他的话 "The sweep itself is not   |
// |      the confirmation."），节点层漏了 ⇒ 口径不一致。                |
// |   ② 翻转判据：s55 用"被破节点是不是新的同侧极值"，但 **M1 回撤几乎 |
// |      总能做出一个略低的低点**（LL）⇒ 判据通过 ⇒ 方向被打回空 ⇒ 其后 |
// |      的上破又成了 CHoCH。用户要的是**内部/外部之分**：回调破的是   |
// |      "内部"结构，不该改外部性格。                                  |
// | ⇒ ① 节点层自带口径，默认 **BREAK_CLOSE**（被扫的位仍由 SWEEP 层标）。|
// | ⇒ ② 新增 `InpNodeFlipMode`（4 档，见枚举注释）决定"什么叫改性格"；  |
// |      默认 **NODEFLIP_RETRACE**：逆势破位只有在**已从趋势极值回吐   |
// |      ≥ InpNodeFlipRetracePct% 的整段腿**（默认 50% = 贴现区的 EQ）  |
// |      时才叫 CHoCH；其余逆势破位 = **内部破位 ⇒ 标 BOS**。           |
// |   ⚠️ 标签规则从此与"翻转"绑定：**翻转 ⇒ CHoCH；不翻转 ⇒ BOS**。     |
// |   ⚠️ 被否掉的替代方案：用 intermediate(tier-1) 当闸门。tier-1 = **两侧 |
// |     都比它低/高**的局部顶底（`ClassifyNodeTiers`），单边下跌里只有    |
// |     **最低点**满足 ⇒ 整段下跌"一直没翻转"，反而把问题从上涨搬到下跌。 |
// |     记录于 plan §69.4，**不得再当作等价方案**。                       |
// +-----------------------------------------------------------------+
enum ENUM_NODE_FLIP
{
   NODEFLIP_RETRACE = 0,   // 回吐整段腿的 N% 才算改性格（默认，N=InpNodeFlipRetracePct）
   NODEFLIP_LEG     = 1,   // 收盘越过"当前腿起点"才算改性格
   NODEFLIP_EXTREME = 2,   // 被破节点本身是新同侧极值才算（v1.50-s55 的行为）
   NODEFLIP_ANY     = 3    // 任何逆向破位都翻转（s45–s54 的旧行为）
};
input ENUM_BREAK_CONFIRM InpNodeBreakConfirm = BREAK_CLOSE; // 节点级破位确认（影线扫过不算破结构）
input ENUM_NODE_FLIP     InpNodeFlipMode = NODEFLIP_RETRACE; // 节点级「改性格(CHoCH)」判据
input double InpNodeFlipRetracePct = 50.0; // NODEFLIP_RETRACE：回吐整段腿的百分之多少才算改性格

input group "== HTF relevance（对齐 TTrades：回看含当前共 3 根高周期 K 线）=="
// 他的原文："look back three higher timeframe candles including the current one.
// The highs and lows within that window are your relevant levels."
// 本轮按 C1 决策只做「标记」：把窗口内的最高/最低画成 relevant high/low，**不过滤任何 swing**
// —— 用窗口去删结构点会让结构线断裂，与既有"折线连续"设计冲突。
// 降级：HTF 数据未就绪时不画，也不影响其余逻辑（InpDebugShowRef=true 时会在日志留痕）。
input ENUM_TIMEFRAMES InpHTFPeriod      = PERIOD_D1;         // 高周期（当前 H1 时回看 3 根 D1）
input bool            InpDrawRelevance  = true;              // 绘制 relevant high/low 水平线
input color           InpColorRelevance = C'130,180,255';    // relevant 位颜色（浅蓝）
input group "== HTF 蜡烛叠加（对齐 TTrades「Higher Timeframe Candles」）=="
// 他的指标条目："View HTF candles on your entry timeframe"；研究报告 §9 给出默认值：
//   count 默认 **4**，另有 Size / Offset / 时间标签等参数。
// 【性能要害】正在形成的那根高周期 K 线**每 tick 都在变**。若把它的 OHLC 放进
//   needDraw 指纹，就会每 tick 触发整段调和 —— 正是 v1.48 专门消除的性能陷阱。
//   故指纹只含「集合级」信息（最新 HTF bar 开盘时间 + **已收盘**蜡烛的 OHLC 签名），
//   正在形成的那根由快路径 UpdateHtfLastFast() 单独刷新（缓存比对，未变即零对象调用）。
// 【绘制】每根 3 个对象：实体 OBJ_RECTANGLE + 上下影线各一条 OBJ_TREND。
//   ⚠️ OBJ_RECTANGLE 没有透明度（v1.49-s14 已用编译证实 error 256），
//   故实体填充沿用既有解法 PdFill(轮廓色, 图表底色) 按百分比混色。
input bool            InpShowHTFCandles = true;              // 在入场周期上叠加高周期蜡烛
// 阶段 44（用户要求）：蜡烛周期**默认自动**推导（映射表见 ENUM_HTF_TF_MODE 的注释）。
//  自动模式下 `InpCandleTF` 被忽略；要看"手改过的固定周期"就把它设成 HTF_TF_MANUAL。
input ENUM_HTF_TF_MODE  InpHtfTFMode     = HTF_TF_AUTO;       // 蜡烛周期模式（自动推导 / 手动指定）
input ENUM_TIMEFRAMES InpCandleTF       = PERIOD_H4;         // **手动模式**下的叠加周期（应 ≥ 图表周期）
input int             InpCandleCount    = 4;                 // 叠加根数（他的指标默认 4）
input int             InpCandleWidthPct = 70;                // 实体宽度占时间跨度的百分比
input int             InpHtfBodyFill    = 25;                // 实体填充强度 %（按底色混色；0=空心）
input color           InpColorHtfUp     = C'38,166,65';      // 高周期阳线颜色（涨绿）
input color           InpColorHtfDn     = C'248,81,73';      // 高周期阴线颜色（跌红）
// 他的指标另有 **Offset** 与**时间标签**两项（research §9："count default 4, **Size, Offset**,
// colors, **time labels**"）。§38.2 的保真度矩阵把这两项标为"未实现"，故此处补齐。
input int             InpHtfShift       = 0;                 // 整体左移 N 根高周期 K 线（0=贴最新）
input bool            InpHtfTimeLabels  = true;              // 每根下方标出开盘时间
input ENUM_HTF_PLACE  InpHtfPlacement   = HTF_PLACE_RIGHT;  // HTF 蜡烛画在哪（叠加 / 右侧留白区）
input group "== Dealing Range（区间 + 均衡位）=="
// 依据：`Relevant.png`（docs/research/img/）显示他把 relevant high/low **连成一个区间**
//   —— 即 dealing range；他序列第三步："Price retraces into a premium or discount zone"，
//   而 premium / discount 就是该区间的上/下半，分界是 50% 均衡位（EQ）。
// 区间取 1-C 的 3 根高周期 K 线极值（`g_relHigh` / `g_relLow`）。
// 【纯可视化】不参与任何判定。
input bool  InpDrawDealingRange = true;               // 绘制区间矩形 + PREMIUM/DISCOUNT 分区
input color InpColorRange       = C'130,180,255';     // 区间边框与分区标签颜色（浅蓝）
input color InpColorEQ          = C'255,213,79';      // 均衡位 EQ 颜色（黄）
// EQ（50% 均衡位）默认**关**：它是 dealing range 的派生元素，不是他明确给出的标记，
// 且与 PREMIUM/DISCOUNT 标签表达同一件事（上下半的分界），图上多一条线只是噪音。
// 需要时单独打开，不影响区间矩形与分区标签。
input bool  InpShowEQ           = false;               // 显示均衡位 EQ（默认不显示）
input group "== 前日高/低（PDH / PDL，对齐 TTrades 的 draw on liquidity）=="
// 他的一手依据：
//  · "Failure to displace above **previous day high** suggests a bearish bias
//     toward **previous day low**." — <https://ttrades.com/the-easiest-draw-on-liquidity/>
//  · 偏置规则："If price closes below the **previous day's low** – Expect continuation lower."
//  ⚠️ 本注释曾引 "Price takes out yesterday's high but closes back inside the range" ——
//     独立核验**未能溯源**该句，已删除。可溯源的同义句见 SWEEP 组的注释。
//  → 前日高/低在他的体系里是**流动性目标**（draw on liquidity），不是普通参考线。
//  ⚠️ 取"最近一根**已收盘**的 K 线"，且按**日期**判定而非写死 shift=1 —— 理由见 ComputePrevDay。
input bool  InpShowPDHL   = true;             // 显示前日高/低（PDH / PDL）
input ENUM_TIMEFRAMES InpPDPeriod = PERIOD_D1; // 周期（用户指定 1D；可改周/月）
input color InpColorPDHL  = C'224,224,224';   // PDH/PDL 颜色（近白，与既有配色均不相近）

input group "== 位移判据（对齐 TTrades MSS）=="
// 他的原话："The key confirmation is displacement (strong price movement with momentum)
// that breaks prior structure."；"clean V-shaped reversal or strong displacement"；
// "The best setups form within one to three candles and show immediate displacement."
// 他**未给出任何数值**，故以下三条阈值是本指标自定的近似（0 = 关闭该条）。
input double InpMinDisplaceBodyATR = 1.0;   // 破位 K 实体 ≥ 该值 ×ATR（MSS/CISD 共用）
// 原「② 收盘穿越深度 `InpMinDisplacePenATR × ATR`」**已整体删除**：
//   · v1.49-s12c：用户要求 MSS 去掉它；
//   · v1.49-s12d：用户要求 CISD 也把它**换成**「后续 N 根内出现同向 FVG」
//     （见 CISD 组的 `InpCisdFvgLookahead`）。
// 故该项已无任何消费者。`pen` 度量**仍然计算**并写入 CSV 的 `pen=` 列，供事后对照。
input int    InpDisplaceMaxBars    = 3;     // 首次影线穿越后 N 根 K 内确认（0=不限），MSS/CISD 共用
input color  InpColorWeakBreak     = C'110,110,130';   // 未过位移门槛的弱化线颜色（灰）
input group "== CISD（TTrades 的早期确认工具）=="
// 他的原话："The change in the state of delivery (CISD) looks at order flow differently.
// Instead of focusing on swing highs or lows, it focuses on the opening price in the series
// of up-close or down-close candles. When price displaces and closes beyond that open, it
// validates the level as an order block."
//   "Bullish to Bearish: Price forms a series of up-close candles, then closes below the
//    opening price of those candles."
// 取数纪律："Always use the series of candles. Only use the single candle if there are no
// other opposing candles."
// ⚠️ 存疑：他未写死取序列里【哪一根】的开盘价。本实现取「最旧那根」（整段造势的起点），
//    依据 "closes below the candles that created the high" 指向整段序列。需人工核实一次。
// 与 MSS 的关系：他明确 CISD 更早（"CISD often appears earlier than MSS"），
//    故两者并行存在、互不替代。
input bool  InpShowCISD  = true;              // 显示 CISD 事件
// 用户要求（v1.49-s12d）：把 CISD 的位移第②条（收盘穿越深度）**换成**
//   「**后续 N 根 K 线内出现同向 FVG**」。
// 【为什么放在后验层】FVG 是在主循环里、随遍历到各 bar 才产生的；
//   某次 CISD 触发时，它**之后**的 N 根 bar 还没被遍历到，FVG 尚不存在。
//   故这条判定必须放到主循环之后（见 ComputeCisdFvgFollow）——
//   这也是它不能像①③那样在主循环内直接算的原因。
// 【窗口定义】`[触发bar − N, 触发bar]`，即**触发 bar 本身 + 其后 N 根**（共 N+1 根）。
//   含触发 bar 是必要的：他的原话是位移 **leaving behind** a fair value gap ——
//   缺口通常正是由这根位移 K 线自己留下的。若只要"其后 N 根不含触发 bar"，
//   把函数里的下界改成 `b - N + 1` 即可。
// 【方向】要求**同向**（看涨 CISD ↔ 看涨 FVG）。理由：位移在方向上留下失衡；
//   若允许反向缺口来"确认"，语义上讲不通。若要放宽为"任意 FVG 即可"，
//   删掉 `ComputeCisdFvgFollow` 里的 `dir` 判断一行即可。
// 【0 = 关闭该条件】。
input int   InpCisdFvgLookahead = 5;   // CISD：后续 N 根内出现同向 FVG（0=关闭）
input color InpColorCISD     = C'186,104,200';   // CISD 标注颜色（紫）
input color InpColorCISDWeak = C'120,90,130';    // CISD 弱位移颜色（暗紫）
input group "== Early CISD / IC-CISD（收盘前确认，对齐 TTrades「Early Trend Shift」）=="
// 他的指标条目："Early Trend Shift" / "Automatically plots CISD **before candle closure**"。
// 一手依据：research/2026-09-23-TTFM-rules-report.md §3（IC-CISD 专文）。
// 【性质】**纯渲染**。触发条件与 CheckCisd 完全相同，只把判定用的"当前价"从
//   已收盘的 close[i] 换成未收盘 bar 的 close[0]。**一律不写任何状态字段** ——
//   不置 cisdHighFired、不派生 OB、不建立 protected swing。
//   理由：他本人承认提前确认会出假信号（"CISD can give earlier entries but sometimes
//   too early, leading to false signals"），把未收盘的猜测写进趋势状态机正是那个错。
// 【生命周期】预览只活在当前未收盘 bar 内：收盘时若真的触发，由正式 CISD 线接替；
//   否则预览消失、不产生任何 CISD 事件行。
input bool  InpShowEarlyCISD  = true;              // 显示 IC-CISD 预览（收盘前临时 CISD）
input color InpColorEarlyCISD = C'255,138,216';    // IC-CISD 颜色（亮紫，区别于收盘 CISD 的紫）
// 他的 IC-CISD 专文明确区分早晚：*"IC-CISD **early in a candle** tends to be the most powerful …
// When it happens **late**: most of the candle range is already used … better to wait for the
// next candle."* 故 IC-CISD 若发生在**高周期 K 线的后段**，应能被一眼看出来。
// ⚠️ 阈值**他未给数值** → 本项是自定近似（%）：已走过的高周期 K 线时间比例 ≥ 该值即标为 late。
// 0 = 关闭早/迟**分级**（预览线与标签照画，标签恒为 "IC-CISD"）—— 不是"关闭该标注"。
input int   InpIcLatePercent  = 60;               // IC-CISD 判"迟"的时间比例 %（0=关闭标注）
input group "== SWEEP（流动性扫荡，纯上下文标注）=="
// 他的一手文字：
//   "price **sweeps the previous candle's high or low** and then closes back inside that range"
//     — <https://ttrades.com/how-change-in-the-state-of-delivery-cisd-confirms-swing-points/>
//   ⚠️ 另有旧注释写过的 "Price takes out yesterday's high but closes back inside the range"
//      **无法溯源**（独立核验未在任何一手文章中找到；与上面那句措辞不同，不能当同一句）→
//      本注释已改用上面那句可溯源的表述。
//   "Use intermediate-term sweeps as confirmation of continuation or reversal."
// 定义：某根 K 线的**影线**越过位、但【收盘收回位内】→ 该位被扫荡。
//   ⚠️ 阶段 72 收紧（用户 2026-09-30：「我框出来的这里都实体突破了，不算 sweep 了吧」）：
//      ① **实体两端都不得越界**（开在位外、收在位内的"跨位 K 线"不算 sweep）；
//      ② 该位一旦**被收盘接受**（close 越界）就**停止扫描** —— 之后再刺破并收回是
//         "破位后的回抽"，不是 sweep。
//      两条都只**减少**事件，不会新增（严格度单调收紧）。
// 扫荡位取自 intermediate（tier-1）节点 —— 依据他 "intermediate-term sweeps" 的措辞。
//   ⚠️ 更新（v1.49-s13）：前日高/低**已单独标记**（PDH/PDL，见 ComputePrevDay），
//   但仍**不作为 SWEEP 的取位来源** —— SWEEP 只扫本图 intermediate 节点。
//   即"前日高低点已经画出来了，但扫荡判定不看它们"。
// 【定位】纯可视化，不参与任何判定 —— 他明确 "The sweep itself is not the confirmation."
// 每个位只记一次（首次被扫荡）。
input bool  InpShowSweep  = true;             // 显示 SWEEP 标注
input color InpColorSweep = C'255,152,0';     // SWEEP 颜色（橙）
input group "== PD Array（FVG / OB，对齐 TTrades）=="
// 【定义来源】docs/research/2026-09-23-TTrades-structure.md「PD Array」节，
//  逐字引文与配图（FVG-3candle / FVG-CE / OB-reversal-pattern / OB-confirmation）。
// FVG：他的原文 "the high/low of the candle(1) does not overlap the low/high of
//  candle(3)" → 三根 K 线、**影线对影线**（非实体）。区间 = [c1 与 c3 之间的空隙]，
//  CE（consequent encroachment）= 区间中点，图上另标 IOFED / FVG Fill 两个位。
// OB：他的原文 "the series of up close candles responsible for the move. When price
//  closes back below those candles, that area becomes a validated order block."
//  → **实体区间**（"Bodies matter more than wicks"）+ 关键价位 = 该序列最旧一根的
//  开盘价（"the opening price of the candle is often the most important reference"）。
//  该动作与我们阶段 4 的 CISD 是**同一个触发**，故 OB 直接由 CISD 运行态派生。
input bool  InpShowFVG       = true;              // 显示 FVG（三根K线缺口）
input bool  InpFvgHideFilled = true;              // 已被完全回补的 FVG 不再绘制
input double InpFvgMinWidthATR = 0.10;            // FVG 最小高度（×ATR；0=不限）——挡 tick 级假缺口
input color InpColorFVG      = C'0,200,180';      // FVG 颜色（**轮廓**；填充由底色+百分比派生）
input bool  InpShowOB        = true;              // 显示 OB（造势序列实体区间）
// 阶段 41（用户要求）：**做多 / 做空的 OB 用不同颜色**。
//  做多 OB（需求区）= 由**被扫的低点**派生（`dir == DIR_UP`）→ 绿；
//  做空 OB（供给区）= 由**被扫的高点**派生（`dir == DIR_DOWN`）→ 红。
//  ⚠️ 这两个色值刻意复用本文件既有的**多空成对色**（与 `InpColorHtfUp/Dn` 同值），
//     不另造新色 —— 全图"绿=多、红=空"保持单一约定。
input color InpColorOBUp     = C'38,166,65';      // 做多 OB（需求区）颜色（绿，与 HTF 阳线同族）
input color InpColorOBDn     = C'248,81,73';      // 做空 OB（供给区）颜色（红，与 HTF 阴线同族）
// 阶段 21：PD Array 区域的**右端**策略（见 ENUM_PD_END 处的实测数据）。
//  这是**视觉降噪**开关：只改矩形画多长，不改任何判定，也不改 CSV 的任何行。
//
//  ⚠️ 默认值变更史（三处同步记录，勿只改一处）：
//     · s28 引入时默认 = `PD_END_NOW`（= 他的画法）
//     · s29 用户裁定改为 `PD_END_RETEST`
//     · **s31 用户裁定改为 `PD_END_FIXED`**（"看起来更清爽"）
//     三者都**偏离** `plan §19.6-D20` 记录的他原画法（他把 OB 画成向右延伸到现价区域），
//     是**用户知情下的取舍**：用降噪换可读性。
//     实测覆盖率（同 9 个 PD 矩形 / 200 根窗口）：NOW 44.2% ・ FIXED6 6.8% ・
//     **FIXED12 8.9%** ・ FIXED24 11.8% ・ FIXED60 20.5%；RETEST ∈ [8.9%, 44.2%]。
//     选 FIXED 的另一个理由：它的宽度是**确定值**（`N + (anchor−valid)` 根），
//     而 RETEST 的宽度依赖真实 bar 数据、常被最小宽度下限接管（实测下限恰为 FIXED12）。
input ENUM_PD_END InpPDEnd      = PD_END_FIXED;   // 区域右端：固定N根/首次回踩/到当前
input int         InpPDRightBars = 12;            // 固定模式=向右延伸根数（12 根 = M5 上 60 分钟）；回踩模式=最小宽度
// PD Array 区域填充强度（0..100，0 = 只画空心框）。
//
// 【为什么从"写死填充色"改成"百分比 + 自动派生"】
//   原先填充色被写死为 `轮廓色 × α`。那套换算**隐含"黑底"假设** ——
//   在浅色底图上，正确做法是往**白**混，而"×α"把颜色越压越黑，
//   结果就是**白底图表上几乎看不见**（用户实测反馈）。
//   现改为按**图表实际底色**混色：
//       fill = bg + (轮廓色 − bg) × 百分比
//   · 黑底（bg≈0）    → fill ≈ 轮廓色 × 百分比（与旧行为一致，无回归）
//   · 白底（bg≈255）  → fill ≈ 向白靠拢的浅色调（白底上才看得见）
//   于是同一个百分比在两种底色下**语义一致**："轮廓色以该不透明度叠在你的图表底色上"。
// 底色经 `ChartGetInteger(0, CHART_COLOR_BACKGROUND)` 读取，且只在 needDraw 帧读一次。
// 默认 30%（用户裁定，v1.49-s14b）：白底上 10% 太淡，30% 才是可辨的浅色调。
//   预期颜色（白底）：FVG ≈ C'179,239,233'、OB ≈ C'209,221,255'、弱化 ≈ C'212,212,218'
//   预期颜色（黑底）：FVG = C'0,60,54'、OB = C'30,42,77'、弱化 = C'33,33,39'
input int   InpPDFillPercent = 30;                // PD Array 填充强度 %（0=空心框）
input group "== Internal / External Liquidity（对齐 TTrades）=="
// 【定义来源】research §13，逐字：
//   "Internal liquidity is a fair value gap." / "External liquidity is a swing high or swing low."
//   "Internal liquidity provides the point of interest. External liquidity provides the target."
// 【配图判别】他的 IRL / ERL 表达方式（docs/research/img/ERLIRL-*.png）：
//   IRL = FVG **横向色带**（= 我们画 FVG 的方式，无需新元素）
//   ERL = 摆动高/低处一条**短点线** + 标签 —— 本组新增的只有这一条线
//   两张图**不画连接箭头**，只是两个元素同时在场、各贴一个标签（故本实现也不画箭头）
// 【前提】他："Start with the higher timeframe bias." → 无 HTF 偏置时不画
//   （偏置为 0 时两侧都可能是目标，画出来等于没结论）。
input bool  InpShowERLIRL = true;                 // 显示 IRL（FVG=POI）与 ERL（摆动位=目标）
input color InpColorERL   = C'233,30,99';         // ERL 目标位颜色（玫红）
input color InpColorIRL   = C'0,200,180';         // IRL 回撤区颜色（与 FVG 同族）
input group "== HTF 偏置（对齐 TTrades 的 fractal 门禁）=="
// 他的原文（Fractal Model Playbook）：
//   "If price closes below the previous day's low – Expect continuation lower.
//    If price fails to close below the previous day's low – Expect reversal higher.
//    Same logic applies for previous day's high, but inverted."
//   "Never drop to the hourly until you have a one-sided daily bias."
//   "Higher time frame closure first → Lower time frame CISD."
// 规则（可机械化）：取上一根【已收盘】的高周期 K 线，与它前一根的高低比较：
//   close > 前根 high → 看涨(+1)；close < 前根 low → 看跌(-1)；
//   落在区间内 → 无新信息，向前回溯取最近一次决定性收线（最多 InpBiasLookback 根）。
//   回溯不到 → 0（无偏置）。
// 【现已生效】门禁按偏置弱化事件（见 RenderScene 各事件块的 dim 分支）；
// InpShowBias 控制偏置标签是否显示。
// 前置提醒：本指标是单图表，HTF 数据经 iClose/iHigh/iLow + iBarShift 取得。
input ENUM_TIMEFRAMES InpBiasTF      = PERIOD_D1;   // 偏置周期（当前 H1 时默认看日线）
input int             InpBiasLookback = 20;         // 偏置回溯上限（根，判不出则视为无偏置）
input bool            InpShowBias     = true;       // 显示当前 HTF 偏置（门禁的输入值）
input color           InpColorBias    = C'0,188,212';  // 偏置标签颜色（青）
input group "== Candle 2 / Candle 3 收盘确认（对齐 TTrades「valid closure」）=="
// 他的一手口径（research/2026-09-23-TTFM-rules-report.md §2）：
//   Candle 编号：C1 = swing 点**之前**；C2 = swing 高/低**本身**；C3 = C2 之后；C4 = C3 之后。
//   · 延续收盘：扫破前根的高/低并**收在其外** → 趋势延续。
//   · 反转收盘：**扫破**前根高/低（影线越出）但**收回前根区间内** → 反转证据。
//     "A Candle 2 closure is always a reversal closure."
//   · C2 收盘（看涨）：扫破前根的 **low**，再收回该 low **之上**；看跌镜像。
//   · C3 收盘（C2 未给确认时）："price does **not** sweep the previous candle, yet candle 3
//     **closes over the body of candle 2 and engulfs it**"；且 "without sweeping the
//     candle 2 high or low"。
//
// 【⚠️ 本阶段是 18a：只检测 + 标注 + 进 CSV，**不参与任何判定**】
//   他另有一条**门禁级**规则（research §1）：
//     "A swing is only valid when it has both: a point of interest and a valid closure
//      (candle 2 or candle 3). **If either is missing, the swing point is ignored.**"
//   若实现它，会改变**全部下游结构**（protected swing / BOS·MSS 归属 / 结构段划分），
//   性质与 v1.49-s11 同级 —— 故按阶段 3-a 的既有先例分两步：
//   **18a 只记录**（本阶段），18b 门禁开关另开一轮、单独测、单独归档。
//
// 【⚠️ 自定口径（他未给的部分）】
//   ① C3 的要求他有两个措辞："closes over the **body** of candle 2"（两处）与
//      "closes beyond the opening price **and range** of candle 2"（一处）。
//      本实现取**实体**版（被重复两次的那句）；"连区间一起越过"的更严版本**未实现**。
//   ② "engulfs it" 的字面（C3 实体完全包住 C2 实体）**未**作为必要条件 ——
//      他两次都只说"收在 C2 实体之外"，判据取后者。
//   ③ 用**物理相邻** K 线判定 C1/C3（非"有效 bar 序列"）。理由：closure 是逐根 K 线的
//      收盘语义（"the previous candle"），与 FVG 的形态口径不同。
//
// 【✅ 阶段 18b 已裁定：**不做门禁**（用户，2026-09-24，「无需门禁」）】
//   即上面那条"缺 POI 或缺 valid closure 则忽略该 swing"**永久不做**。
//   本层终态 = **只检测、只标注、进 CSV**，对结构 / 偏置 / 目标**零影响**。
//   实测若实现：只要求 closure → 保留 46/58 = 79.3%；closure + POI → 只剩 26/58 = 44.8%，
//   而 POI 的机械判据他的文章里只有一张种类清单、必须由实现方发明（同样的说法下
//   存活率能从 31% 到 100%）。**在最没有依据的地方引入主导结果的发明，方向是反的。**
//   ⚠️ 不要再以"补全保真度"为由把它加回来 —— 这是**已裁定的取舍，不是遗漏**（plan §43.7）。
input bool  InpShowClosures = true;              // 标注 C2 / C3 收盘确认（只标注，不做门禁）
input color InpColorC2      = C'126,231,135';    // C2 收盘（反转确认）颜色（亮绿）
input color InpColorC3      = C'255,214,102';    // C3 收盘（迟到一根）颜色（琥珀）
// 他：C3 收盘后"mark the **full range of candle 3**"，看涨则预期 C4 **刺入 C3 的上半**。
// 故 C3 事件另画一条 C3 区间的 50% 均衡位线 —— 这是他明确给出的用法，不是自造。
input bool  InpShowC3Eq     = true;              // 绘制 C3 的均衡位（50%）辅助线

input group "== Auto Targets / 目标投影（对齐 TTrades）=="
// 依据：research/2026-09-23-TTFM-rules-report.md §7。
// ── (a) 流动性目标（**他列为"separate，and primary"**）──
//   逐字："Bullish → previous **untouched** highs; bearish → previous **untouched** lows;
//   prior HTF candle highs/lows, HTF dealing-range extreme, failure swings, equal highs/lows.
//   **A level already taken out is invalid.**"
//   前提同上（"Start with the higher timeframe bias."）→ 无偏置时不画。
//   【与 ERL 的关系】ERL 给的是"最近的**一个**"；本项给"最近的 N 个"。
//   两者的"未被取走"判定**共用** IsLiquidityTaken()（同一概念一份实现）。
input bool  InpShowAutoTargets = true;                 // 显示流动性目标（偏置方向上未取走的摆动位）
input int   InpTargetCount     = 3;                    // 显示最近 N 个（上限 4）
input color InpColorTarget     = C'233,30,99';         // 目标位颜色（玫红，与 ERL 同族）
// ── (b) 投影目标（操纵腿的倍数）──
//   他给的**锚定规则很明确**："Anchor a Fibonacci tool to the **manipulation leg** — the swing
//   that sweeps liquidity and occurs **immediately before the CISD** … Bearish projects
//   high→low; bullish low→high. **Start the construction from Candle 2, the reversal point.**"
//   ⚠️⚠️ **但方向约定本实现是"我们的读法"，不是逐字口径** ——
//   他的水平表是 `1, 0, −1, −2, −2.5, −4`（负向扩展）。若照 TradingView 的常规（负向 = 越过
//   起点 A），那么在看涨（A=低、B=高）时 −1/−2 会落在 **A 之下** —— 那是**止损方向**，不是目标。
//   **故本实现反号**：以**交易方向**为准，从 B 继续向外投影（看涨向上、看跌向下）。
//   这属于"比原文多做/改做"，必须在文档与 CSV 头部标注，**不得**声称与他的水平表一致。
//   ⚠️ 水平表本身的置信度也只有**中介**（§7 自述：第二篇原文的水平列表被截断）。
//   【A / B 的取法】A = 最近一条**与偏置同向**的 CISD 事件的极值 bar
//   （= 造势序列极值 = 操纵极值）；B = A 之后的**反向极值**。
input bool  InpShowFibTargets  = true;                 // 显示操纵腿投影目标
input color InpColorFib        = C'255,171,64';        // 投影位颜色（橙）
// 投影水平表：**操纵腿的倍数**（逗号分隔，最多 FIB_NLEGS_MAX 条）。
//   语义：`价位 = B + 腿长 × k`，故 **k > 0 = 沿交易方向外推**（目标），k = 0 = B 本身。
//   ⚠️⚠️ 他的原文表是 `1, 0, −1, −2, −2.5, −4`，而**符号约定与本项不同** ——
//   他的负向在 TradingView 约定下落在**起点 A 之外**（= 止损方向）。故：
//     · 想要"交易方向上的目标"（推荐）：填 `0,1,2,2.5,4`（当前默认）
//     · 想要**逐字复现他的表**：填 `1,0,-1,-2,-2.5,-4`（此时 3 条线会落在 A 之外）
//   把选择权交给用户，而不是由本实现替他定死 —— 这比硬编码更诚实。
input string InpFibLegs        = "0,1,2,2.5,4";        // 操纵腿倍数表（逗号分隔，最多 6 条）

input group "== BOS/MSS 绘制 =="
input bool           InpNeedRetestToShow = false;   // 需后续回踩/反弹确认才显示（默认关闭）
input bool           InpDrawLiveLeg      = true;    // 结构线延伸至当前未确认端点
input ENUM_LINE_END  InpLineEnd          = LINE_END_HIT_ZIGZAG;  // 虚线终点模式（默认：从被突破结构极值向右，碰到结构折线即停）
input int            InpLineEndBars      = 20;      // 固定终点长度（根数，仅 FixedBars 模式）
input int            InpMaxEvents        = 6;       // 每类各只显示最近 N 条（BOS 与 MSS 各 N 条，避免满屏历史线；0=全部）
input bool           InpShowChoch        = true;    // 显示**节点级** BOS/CHoCH（CHoCH 为**借用 ICT 术语**）
// 阶段 32（用户要求）：弱化的 BOS/MSS **完全不画** —— 连灰线也不画，对象根本不创建。
//  ⚠️ "弱" = `mss[].weak`（位移不足）**或**逆 HTF 偏置，两者都算（与阶段 6-b 的弱化口径一致）。
//  设为 false 即退回"灰线 + 无标签"（= v1.49 G1 观感），便于新旧对照。
input bool           InpHideWeakBreaks   = true;    // 弱化的 BOS/MSS 完全不画（false=退回"灰线无标签"）
input color          InpColorChoch       = C'123,31,162'; // CHoCH 标注颜色（深紫；⚠️ 原写成 C'186,104,200' 与 CISD **完全相同**，已改）
// 诊断/限流：限制结构线最多画多少段（0 = 不限，按可见节点全画）。
// 用途一：MT5 单图表对象数有上限，段数过多会被终端拒绝创建；
// 用途二：切成 50/200/500 观察何时开始画不出来，从而定位上限位置。
input int            InpMaxSeg           = 0;       // 结构线最多段数（0=不限）

input group "== 性能 =="
input int    InpAnalysisWindow  = 500;         // 分析窗口（根K线，0=全量；限制分析范围以提升性能）
input bool   InpReuseResultOnTick = true;      // 同 bar tick 复用分析结果（减少重算）

input group "== 颜色 =="
input color InpColorStructure  = C'57,197,207';  // 结构线颜色（ZigZag 青）
input color InpColorMSS        = C'255,213,79';  // MSS 标注颜色（黄）
input color InpColorBOS        = C'255,82,82';   // BOS 标注颜色（红）
input color InpColorBox        = C'110,110,130'; // 内包盒矩形颜色

input group "== 调试验收（默认全关，常态零成本）=="
input bool InpDebugShowRef = false;   // 专家日志：方向自检 + GEO/VIEW 坐标诊断 + 每条事件明细
input bool InpDumpEvents   = false;   // 导出全部事件 CSV（离线 diff 用）
input bool InpHotkeys      = true;    // 热键诊断：Shift+S 导出图表 PNG；Shift+D 导出事件 CSV
// InpDumpEvents：文件名固定为 MQL5\Files\Structure_events_<品种>_<周期>.csv（每次全量重算覆盖），
// 便于「改前导出一份 → 存档 → 改代码 → 再导出一份 → diff」。
// 见 docs/plans/2026-09-23-TTrades-alignment.md（阶段 0）

//--- 常量 ---
#define OBJ_PREFIX   "Structure_"
#define ST_UP        1
#define ST_DOWN     -1
#define DIR_UP       1
// 构建指纹：每次改动递增一位。它出现在 INIT 日志与事件 CSV 头部。
// 用途：确认 MT5 实际加载的是哪一版编译产物。
// 背景：本仓库存在「MT5\Indicators 下另有一份 .mq5 副本，被（编辑器/手动）编译后
// 覆盖掉部署的 .ex5」的情况 —— 此时靠比对文件时间戳会得出错误结论。
#define BUILD_TAG    "v1.50-s59"   // s59：二轮评审批量修复 -- 默认档 NodeFlip 方向接反（所有逆势破位误标 CHoCH）/
                                        //   ref.touched 吞强 MSS 与生命周期复位缺口 / 底色不入指纹 / 早退残留全局 /
                                        //   open 方向锁丢失 / 分析窗口未校验 / 内包盒漏记 / 计数器复位缺口 /
                                        //   HTF 缓存半复位 / 双破落选侧未消耗 / CLOSURE 未收盘判定 / 留白槽位对账日志 /
                                        //   同图双实例限制明文记录（未在代码强制）
#define RELEVANCE_BARS 3   // TTrades 固定为 3 根（含当前）；不开放为输入，以免偏离原口径
#define DIR_DOWN    -1
// 阶段 18：Candle 2 / Candle 3 收盘确认的子类型（StructureEvent.sub）
#define CLOSURE_C2_REV   0   // C2 收盘：扫破前根极值后**收回**→ 反转确认（"A Candle 2 closure is always a reversal closure."）
#define CLOSURE_C3       1   // C3 收盘：C2 未扫破，C3 收在 C2 实体之外 → 迟到一根的确认
#define CLOSURE_C2_CONT  2   // C2 延续收盘：扫破前根极值后**收在其外**→ 延续（不是反转）
// 阶段 30/35：节点级破位的两个子类型。⚠️ 复用 `StructureEvent.sub` 字段 ——
//  它是"子类型判别位"，CLOSURE 与 NODEBRK 各自写入、各自解释，**不得跨族读**。
#define NODEBRK_CHOCH    0   // 破位方向 ≠ 结构方向 → 逆势（**借用 ICT 术语**）
#define NODEBRK_BOS      1   // 破位方向 == 结构方向 → 顺势（他的术语）
// 阶段 70：逆向破位的**第三种**（用户 2026-09-30「这里应该都是**内部的 BOS** 才对」）。
//  逆向破位但**没有改性格**（翻转判据未通过）⇒ 它是"内部结构的一次破位"，
//  按用户口径**标 BOS**（不是 CHoCH）：CHoCH 的含义是"性格改变"，而这层没改变性格。
//  ⚠️ 渲染与 NODEBRK_BOS 完全一致（同色同字），区别只在 CSV 的 state 列
//     （`BOS(node-level,internal-break)`）—— 用户明确要看到"BOS"这个字样。
#define NODEBRK_BOS_INTERNAL 2
// 阶段 19：Auto Targets / 投影目标的容量与水平表
#define MAX_TARGETS 4        // 流动性目标最多显示几个（InpTargetCount 的上限）
#define FIB_NLEGS_MAX 6      // 操纵腿投影水平数的**容量**（实际条数由 InpFibLegs 解析得出）

//+------------------------------------------------------------------+
//| 数据结构（结果层）：一条事件一条记录                              |
//+------------------------------------------------------------------+
struct StructureNode
{
   int    bar;      // bar 索引
   double price;    // 极值价格
   bool   isHigh;   // true=高点 / false=低点
   bool   isMain;   // true=主结构点 / false=内部点（仅影响线型）
   int    tier;     // 阶段 1-D：0=short-term / 1=intermediate-term（定义由图 ITM.png 证实）
};

struct StructureEvent
{
   int    bar;      // 事件 bar 索引（突破发生的 K 线）
   int    dir;      // DIR_UP / DIR_DOWN
   double ref;      // 被突破的结构位价格（LH/HL/HH/LL/母线高/母线低）
   int    refBar;   // 被突破极值节点所在 bar（水平线起点锚定，创建时反查）
   bool   weak;     // 阶段 3：true = 未过位移门槛（G1 → 弱化样式、不给文字标签）
   // ── v1.50-s58：CISD/OB 的第②条（后续 N 根内出现同向 FVG）独立成字段 ──
   //  ⚠️ 不得把它再折进 `weak`：那会让"位移不足"与"缺后续 FVG"两种成因不可区分（本项缺陷的成因）。
   //  真值约定：**只有 CISD / OB 会写它**（由 ComputeCisdFvgFollow 逐帧双向赋值）；
   //  其余事件类型恒为 false，**不得**读作任何含义（与上面 `sub`/`c4` 同一纪律）。
   //  渲染对 CISD/OB 取 `weak || !fvgFollow`（保持"质量仅以颜色区分"的既定观感），
   //  而 CSV 同时导出两个字段，于是"这条为什么是弱的"可回溯。
   bool   fvgFollow;
   int    bias;     // 阶段 6：该事件发生时的高周期偏置（+1 看涨 / -1 看跌 / 0 无）
   double bodyATR;  // 阶段 3：破位 K 实体 / ATR
   double penATR;   // 阶段 3：收盘穿越结构位深度 / ATR
   // ── 阶段 9：PD Array（FVG / OB）专用字段 ──
   //  复用同一结构是为了让 CSV 归并、偏置回填、渲染遍历三处逻辑保持不变。
   double zoneLo;   // FVG：缺口下沿 / OB：造势序列实体区间下沿
   double zoneHi;   // FVG：缺口上沿 / OB：造势序列实体区间上沿
   double fillPct;  // FVG：形成后被回补的最大比例 0..1（1 = 完全回补）
   bool   ceBroken; // FVG：是否已出现收盘穿越 CE（TTrades：穿 CE 即视为失效）
   // ── 阶段 18：Candle 2 / Candle 3 收盘确认专用 ──
   //  ⚠️ 只有 CLOSURE 行会写它；其余事件类型恒为 0，**不得**读作任何含义
   //  （与 §v1.49 第 11 条"`weak` 只表示位移不足、不得复用"同一纪律）。
   int    sub;      // CLOSURE_C2_REV / CLOSURE_C3 / CLOSURE_C2_CONT
   // C3 专属：C4 是否守住 C3 的均衡位那一半。
   //  0 = C4 尚未出现（待定）/ 1 = 守住（看涨未跌破 EQ、看跌未升破 EQ）/ 2 = 已破。
   //  ⚠️ 同样只有 CLOSURE/C3 行有意义，其余恒为 0。
   int    c4;
};

struct BoxZone
{
   double hi;       // 母线 high
   double lo;       // 母线 low
   int    mother;   // 母线 bar 索引
   int    start;    // 内包开始 bar（最旧内包）
   int    end;      // 内包结束 bar（最新内包）
};

struct StructureResult
{
   StructureNode  nodes[];   // 主结构节点（旧→新，驱动状态机）
   int            nNodes;
   StructureEvent mss[];     // MSS 事件
   int            nMSS;
   StructureEvent cisd[];    // 阶段 4：CISD 事件
   int            nCISD;
   StructureEvent sweep[];   // 阶段 5：SWEEP（流动性扫荡）事件
   int            nSWEEP;
   StructureEvent bos[];     // BOS 事件
   int            nBOS;
   StructureEvent fvg[];     // 阶段 9：FVG（三根 K 线，影线对影线）
   int            nFVG;
   StructureEvent ob[];      // 阶段 9：OB（造势同向收盘序列的实体区间）
   int            nOB;
   StructureEvent closure[]; // 阶段 18：Candle 2 / Candle 3 收盘确认（他的 "valid closure"）
   int            nClosure;
   // ── 阶段 30：CHoCH（**借用 ICT 术语**；见 ComputeChoch 的说明）──
   //  ⚠️ 这一族**不是他的概念**（他的语料里 `change of character` = 0 次）。
   StructureEvent choch[];   // 逆内部趋势、破"最近一个结构节点"（不要求是 protected swing）
   int            nChoch;
   // 注：原 `subNodes[]` / `nSub` 已于 v1.49-s15 删除（AddSubNode 从未被调用）。
   BoxZone        box[];     // 内包盒
   int            nBox;
};

//+------------------------------------------------------------------+
//| 状态机运行态（分析层内部）                                       |
//+------------------------------------------------------------------+
struct RefPoint
{
   int    bar;     // 结构点所在 bar
   double price;   // 结构点价格（已确认 ZigZag 极值）
   bool   valid;   // 已确认
   bool   broken;  // 已被**确认**突破（强触发）→ 该位用完，不再触发
   // 阶段 12-b：**弱触发**标记。BREAK_WICK 下"影线扫一下"就会命中破位条件，
   // 但位移不足时它并不是他所说的 MSS（"The sweep itself is not the confirmation."）。
   // 若此时也把 broken 置真，该位就被一次"扫影线"永久消耗，
   // 后面真正的收盘/实体突破反而再也出不来 —— 那是丢信号。
   // 故弱触发只记录一次（touched=true），**不消耗**该位；强触发才置 broken。
   bool   touched; // 已记录过一次弱触发（防同一根位反复产生弱事件）
};

// 术语对齐（阶段 1-E / v1.49-s11）：下面两个 ref 就是 TTrades 所说的
// protected high / protected low，其定义（"收盘穿过进入该位的那一串反向 K 线"）
// 即 CISD，由 SetProtectedFromCisd() 在 CISD 触发时写入。
struct SState
{
   int      state;       // ST_UP / ST_DOWN / 0=未播种
   RefPoint refHigh;     // HH(UP) / LH(DOWN)
   RefPoint refLow;      // HL(UP) / LL(DOWN)
   bool     lastIsHigh;  // 最后节点是否高点
   bool     hasLast;
   double   lastLeg;     // 最后一条已确认腿幅度（比例过滤）
   // 阶段 4：CISD 运行态。位 = 「造势那一串同向收盘 K 线」中最旧那根的开盘价；
   // Bar 记录该极值所在的 bar（供位移的时效条件使用）。Fired 保证每个位只触发一次。
   double cisdHighLevel; bool cisdHighValid; bool cisdHighFired; int cisdHighBar;
   double cisdLowLevel;  bool cisdLowValid;  bool cisdLowFired;  int cisdLowBar;
   // 阶段 9：CISD 位的「造势序列最旧一根」bar。OB 的实体区间需要它 —— 有了它，
   //  OB 无需独立扫描：同一次 CISD 触发即同一次 OB 验证（TTrades 原文
   //  "closes back below those candles" 与我们 CISD 的收盘穿越是同一个动作）。
   int cisdHighRunBar; int cisdLowRunBar;
};

//--- 全局（结果 + 场景集合）---
StructureResult g_result;      // 分析结果：ComputeStructure 填充，RenderScene 消费
double          g_curATR = 0.0; // 最近一次分析 ATR（渲染标签垂直偏移用）

//--- v1.48 性能：对象属性影像缓存（消除每帧 ObjectGet* 跨进程读取）---
datetime  g_drawnFrom = 0;     // 上次渲染的窗口左边界（诊断用）

//--- v1.48 性能：实时腿"显著位移"阈值状态 ---
//  UpdateLiveLeg 跑在**每 tick** 上，原实现只要极值端点有一丁点变化
//  （哪怕远低于一个像素）就写对象 + ChartRedraw()。这是本指标最热的路径：
//  活跃品种每根 M1 可触发数百次 tick，等于把"避免每 tick 全场景调和"的
//  优化又原样还了回去。现按 0.1×ATR 量化，低于阈值的位移直接不动图表。
datetime  g_liveBarT   = 0;
double    g_liveEndP   = 0.0;
int       g_liveEndBar = -1;
bool      g_liveInit   = false;
// 【等价性自检（v1.49-s15b）】实时腿的 O(1) 增量更新 vs 全量重扫的**不一致计数**。
//  仅在 InpDebugShowRef=true 时累加（那份全量扫描只在调试模式下付代价），
//  由 DbgReport 的 `liveMiss=` 字段输出。**该值必须恒为 0**；
//  非 0 即说明增量推导有误（例如 bar 内极值并非单调）→ 应回退到慢路径。
int       g_dbgLiveMismatch = 0;

//--- v1.48 性能：整段绘制门控 ---
//  结构没变时整段跳过调和循环，因此 ObjectGet* 的调用次数被限制在
//  "结构真的变了"的帧上 —— 这是本版主要的性能手段。
//  判据（任一变化 → 需要重画）：节点集合 / 可见窗口左端 / 最新内包盒 /
//  两类事件的条数与起始下标。这些量全部是 O(1) 或 O(n) 内存可得的。
int  g_lastNodes      = -1;    // 上次绘制的节点数
int  g_lastNodeBar    = -1;    // 上次绘制的最后节点 bar
int  g_lastOldestVis  = -1;    // 上次绘制时第一个落在窗口内的节点下标
int  g_lastBoxIdx     = -1;    // 上次绘制的最新内包盒下标
int  g_lastNMSS       = -1;    // 上次绘制的 MSS 条数
int  g_lastNBOS       = -1;    // 上次绘制的 BOS 条数
int  g_lastMSSFrom    = -1;    // 上次的 MSS 起始下标（InpMaxEvents 裁剪点）
int  g_lastBOSFrom    = -1;    // 上次的 BOS 起始下标

//--- v1.48 性能：场景成员哈希集合 ---
//  回收段原来对每个图表对象调一次 InScene()，那是 O(kept) 线性查表，
//  整段因此是 O(total × kept)。改为开放寻址哈希集合后成员判定 O(1)，
//  整段降为 O(total)。
//  只在 needDraw 时重建（期望集合只在重画帧才变），因此摊还成本极低。
//  容量取 2 的幂，用掩码寻址；负载因子 < 0.5 保证探测链短。
string g_setKey[];             // 空串 = 空槽位（对象名恒非空，可安全作哨兵）
int    g_setMask  = 0;         // 容量 - 1
int    g_setUsed  = 0;         // 已占用槽位数（含墓碑不计，本实现不做删除）
bool   g_setReady = false;     // 本帧集合是否可用（未 Add 过则为 false）
int    g_setNextCap = 128;     // 下次重建的容量（按上一帧规模自适应）

//--- v1.48 诊断计数器（仅 InpDebugShowRef 时有意义）---
//  用于把"节点为 0"的原因定位到具体的过滤环节：
//    raw      = 通过 fractal 判定（高/低）的次数
//    afterGap = 通过相邻最小间隔过滤后
//    afterRet = 通过有效回撤过滤后
//    afterC   = 通过双 swing 互斥裁决后
int g_dbgRaw = 0, g_dbgGap = 0, g_dbgRet = 0, g_dbgC = 0;
int g_dbgSeed = 0, g_dbgAddHigh = 0, g_dbgAddLow = 0;
int g_dbgSep = 0;   // 阶段 1-B：被 failure swing 剔除的 swing 数（诊断）
// 阶段 3：最近一次位移判定的度量（由 MSSDisplaced() 写入，AddMSSResult() 读取）。
// 用全局传递是为了避免 4 处调用点各自重复计算；它们是纯粹的"上一次判定结果"。
double g_lastBodyATR = 0.0;
double g_lastPenATR  = 0.0;
double g_lastNCISD   = -1;   // stage 4: CISD count fingerprint
double g_lastNSWEEP   = -1;   // stage 5: SWEEP count fingerprint
double g_lastNFVG     = -1;   // stage 9: FVG count fingerprint
double g_lastNOB      = -1;   // stage 9: OB count fingerprint
double g_lastNClosure = -1;   // stage 18: CLOSURE count fingerprint
double g_lastNChoch   = -1;   // stage 30: 节点级破位条数指纹（BOS/CHoCH 同数组）
// stage 10：Internal / External Liquidity 的当前配对（纯可视化，见 ComputeErlIrl）。
//  逐帧派生量：依赖 close[0] 与 g_curBias，故必须在分析后段算出并进入 needDraw 指纹。
bool     g_erlValid = false;  // 是否找到有效的 ERL（偏置方向上最近的、尚未被取走的摆动位）
double   g_erlPrice = 0.0;
int      g_erlBar   = -1;
// 注：`g_erlIsHigh` 已于 v1.49-s15 删除（只写不读）。ERL 的方向由 `g_erlPrice`
//     与现价的相对位置体现，标签位置不需要额外字段。
bool     g_irlValid = false;  // 是否找到有效的 IRL（偏置方向上的回撤 FVG）
double   g_irlPrice = 0.0;    // 该 FVG 靠近现价的那条边
int      g_irlFvgIdx= -1;
double   g_lastErlPrice = 0.0; bool g_lastErlValid = false; int g_lastErlBar = -1;
double   g_lastIrlPrice = 0.0; bool g_lastIrlValid = false; int g_lastIrlIdx = -1;
// 前日高/低（PDH / PDL）。与 relevance 同理：跨周期取数，只在全量重算路径算一次。
double   g_pdh = 0.0, g_pdl = 0.0;
datetime g_pdT1 = 0;            // 该日 K 线的开盘时间（画线左端）
bool     g_pdValid = false;
double   g_lastPdh = 0.0, g_lastPdl = 0.0; datetime g_lastPdT1 = 0; bool g_lastPdValid = false;
int    g_curBias      = 0;    // stage 6: HTF bias as of the newest bar
int    g_lastCurBias  = -2;   // stage 6: bias fingerprint
// HTF relevance（阶段 1-C）：3 根高周期 K 线的极值。仅用于标记，不参与任何过滤决策。
double   g_relHigh = 0.0, g_relLow = 0.0;
datetime g_relT1   = 0,   g_relT2   = 0;    // 窗口起止时间（画线两端）
bool     g_relValid = false;
int      g_relBars  = 0;                    // 实际取到的 HTF K 线数（降级诊断）
double   g_lastRelHigh = 0.0, g_lastRelLow = 0.0;   // needDraw 指纹用
bool     g_lastRelValid = false;
// 【needDraw 指纹补充（v1.49-s15）】独立评审查出三处缺口：
//  (a) 约 11 组对象以 `time[0]` 为右端（RANGE/EQ、PREMIUM/DISCOUNT、FVG 框与 CE 线、
//      OB 框、PDH/PDL、ERL、IRL、BIAS）。原指纹不含"新 bar"项 —— 于是新 bar 到来时
//      若没有其它项变化，这些对象**不会延长到新 bar**（右端滞后约 1 根）。
//  (c) 事件数组只按**条数**取指纹 → "等量换血"（窗口滑动导致旧事件离开 + 新事件形成、
//      条数恰好不变）不可见，图上会留旧事件。
//  → 加 `time[0]` **同时覆盖 (a) 与 (c)**：事件数组只在全量重算路径重建，
//    而那条路径正是由新 bar 触发的；新 bar 上 time[0] 必变 ⇒ 必然重画一次。
//    （若 InpReuseResultOnTick=false，同 bar 内 tick 也会重算，但那时只有**条数**会变，
//      已被原有各项覆盖。）
//  (b) `g_relT1`/`g_relT2` 缺席：新 HTF bar 上若 3 根窗口的极值恰好没变，
//      RELH/RELL 与 RANGE 左端仍锚在旧窗口 → 故一并加入。
//  代价：每 bar 多一次调和（本就每 bar 都要延长右端，属必要成本）。
datetime g_lastT0      = 0;
datetime g_lastRelT1   = 0, g_lastRelT2 = 0;
//══════════════════════════════════════════════════════════════════
//  阶段 16：IC-CISD（Early CISD）运行态
//══════════════════════════════════════════════════════════════════
// 【为什么需要 g_armedCisd*】`st.cisdLowValid/cisdLowFired/...` 是 ComputeStructure
//   内部的**局部状态机**，渲染层与快路径都看不见。故在分析末尾把「武装中且**尚未触发**」
//   的位快照出来。一旦收盘触发，`cisdLowFired` 置真 → 快照的 valid 自动变假 →
//   预览自动失效，不需要任何额外的清理逻辑。
bool     g_armedCisdHighValid  = false;
double   g_armedCisdHighLevel  = 0.0;
int      g_armedCisdHighBar    = -1;
bool     g_armedCisdLowValid   = false;
double   g_armedCisdLowLevel   = 0.0;
int      g_armedCisdLowBar     = -1;
// 当前"应当显示的预览"参数（dir=0 表示无预览）。这是预览的**唯一权威状态**：
//   全量帧重新求值并写入；快路径只读它来同步对象，并在状态翻转时碰一次对象。
int      g_icValid   = 0;      // 0=无预览 / DIR_UP / DIR_DOWN
double   g_icLevel   = 0.0;
int      g_icRefBar  = -1;
// needDraw 指纹（硬约定 3：新增可视化元素必须同步指纹）
int      g_lastIcValid  = -2;
double   g_lastIcLevel  = 0.0;
int      g_lastIcRefBar = -2;
// 快路径的对象状态缓存：与指纹分离，避免"每 tick 写 g_ic*"污染全量帧的比较基准。
int      g_icFastValid  = -1;
double   g_icFastLevel  = 0.0;
int      g_icFastRefBar = -1;
bool     g_icLate       = false;   // 阶段 16 补：当前 IC-CISD 是否落在高周期 K 线后段
bool     g_icFastLate   = false;
// 阶段 16 补（可观测性）：IC-CISD 预览**累计触发次数**（自本次加载起，0→有效 的跃迁计一次）。
//  动机：IC-CISD 可能在同一根 bar 内**触发又消失**，而 STRUCT_RENDER 只在全量帧采样 ——
//  逐帧快照**天然会漏掉**这类瞬时状态，于是"功能是否真的在跑"变成靠运气。
//  有了累计计数，任何一帧的日志都能回答该问题，不必恰好撞上触发瞬间。
int      g_icHits       = 0;
bool     g_icCountValid = false;   // 计数用的上一状态（与刷新缓存分开，避免双重计数）
// 快路径已画出的预览对象名（用于状态翻转时显式删除；全量帧不依赖它 —— 那边靠场景集回收）
string   g_icName    = "";
string   g_icLblName = "";

//══════════════════════════════════════════════════════════════════
//  阶段 17：HTF 蜡烛叠加运行态
//══════════════════════════════════════════════════════════════════
// 指纹只含"集合级"信息 —— 见输入组注释里的性能说明。
datetime g_htfT0    = 0;       // 最新（正在形成的那根）HTF bar 的开盘时间
long     g_htfSig   = 0;       // **已收盘** HTF 蜡烛的 OHLC 签名
datetime g_lastHtfT0  = 0;
long     g_lastHtfSig = 0;
// 快路径缓存：正在形成的那根的 OHLC（未变则零对象调用）
double   g_htfC0O = 0.0, g_htfC0H = 0.0, g_htfC0L = 0.0, g_htfC0C = 0.0;
// v1.50-s58：快路径"新 bar"判据。必须是全局且在 OnInit 清零 —— 函数内 static 会跨品种/周期保留。
int      g_lastRates = 0;
// v1.50-s59：图表底色必须进 needDraw 指纹。所有 PD/HTF 填充色都由底色混出（PdFill），
//   而底色**不在任何输入的范畴内** ⇒ 用户改主题/换模板不会触发 OnInit，指纹全等 ⇒
//   本帧 needDraw=false，色块继续用旧底色混出的颜色，直到下一根 bar 或一次缩放才纠正。
int      g_lastBgClr   = -1;
// [v1.50-s59] HtfLogSlot 的节流缓存：原为函数内 static，跨 OnDeinit/OnInit 存活（同一实例），
//   改留白设置后不会再打日志 —— 与 DumpRectObjects 的 s_done、g_lastRates 是同一类陷阱。
long     g_htfLogSlot     = -1;
int      g_htfLogPxPerBar = -1;
int      g_htfLogRowEdgePx = -1;
// v1.50-s59：一次性诊断的"只报一次"必须能在 OnInit 复位（static 跨 OnDeinit/OnInit 存活）。
bool     g_objDumped   = false;
datetime g_htfC0T0 = 0, g_htfC0T1 = 0;
// 阶段 25：右侧留白模式下每根蜡烛占多少秒。它随**缩放**变化 ⇒ 必须进 needDraw 指纹，
//  否则缩放后整排蜡烛会停在旧坐标直到下一根 bar（硬约定 3）。
long     g_htfSlot     = 0;
long     g_lastHtfSlot = -1;
// 阶段 25 诊断：留白区的**像素实测**结果（marginPx = -1 表示走了条数公式兜底）。
//  没有这两个数，一旦蜡烛位置不对，我只能猜是"公式错"还是"Chart Shift 没开"。
int      g_htfMarginPx  = 0;
int      g_htfPxPerBar  = 0;
// Chart Shift 原值：右侧模式会自动开启，OnDeinit 时还原，避免留下副作用
bool     g_shiftSaved    = false;
bool     g_shiftOnOrig   = false;
double   g_shiftSizeOrig = 0.0;

//══════════════════════════════════════════════════════════════════
//  阶段 19：Auto Targets / 投影目标运行态
//══════════════════════════════════════════════════════════════════
// 逐帧派生量：依赖 g_curBias 与 close[0]，故与 ERL/IRL 同层（FillEventBias 之后）。
// 全部进 needDraw 指纹 —— 否则价位变了而指纹没变，图上会停在旧位置。
int      g_tgtCount = 0;
double   g_tgtPrice[MAX_TARGETS];
int      g_tgtBar[MAX_TARGETS];
int      g_lastTgtCount = -1;
double   g_lastTgtPrice[MAX_TARGETS];
int      g_lastTgtBar[MAX_TARGETS];
// 操纵腿：A = 与偏置同向的最近一条 CISD 的极值（= 操纵极值）；B = A 之后的反向极值。
bool     g_fibValid     = false;
double   g_fibA         = 0.0, g_fibB = 0.0;
int      g_fibRefBar    = -1;
int      g_fibDir       = 0;
bool     g_lastFibValid = false;
double   g_lastFibA     = 0.0, g_lastFibB = 0.0;
int      g_lastFibRefBar = -1;
int      g_lastFibDir    = 0;
// 投影水平表（操纵腿的倍数）。OnInit 里赋值。
//  ⚠️ 他的原文水平表是 `1, 0, −1, −2, −2.5, −4`；本实现取**正号**（见输入组注释：负号在
//     TradingView 约定下指向反方向，作为"目标"讲不通）。改这里即可对齐他的表。
double   g_fibLegs[FIB_NLEGS_MAX];
int      g_fibNLegs = 0;      // 实际条数（由 InpFibLegs 在 OnInit 解析得出）

int g_dbgNValid = 0, g_dbgRates = 0;   // 有效 bar 数 / rates_total（诊断用）
int g_dbgNeedDraw = 0;                  // 渲染层诊断：本帧是否走了调和路径

// 诊断输出：分析层各过滤环节的通过数 + 渲染层状态。
// 由 OnCalculate 调用（InpDebugShowRef=true 时）。time/rates_total 由调用方传入。
//+------------------------------------------------------------------+
//| 事件导出（阶段 0 验收工具）                                        |
//|  仅 InpDumpEvents=true 时写文件，默认关 → 常态零成本。             |
//|  文件名固定（同品种同周期）→ 每次全量重算覆盖，便于版本间 diff。    |
//|  列布局预留后续阶段：displacement（阶段3）/ tier（阶段1）/         |
//|  biasState（阶段6）。后续加列不破坏已存档文件的列对齐。            |
//+------------------------------------------------------------------+
// 颜色 → "R,G,B"（MQL5 的 color 是 Windows COLORREF 布局：0x00BBGGRR）
string ClrStr(const color c)
{
   return StringFormat("%d,%d,%d",
                       (int)(c & 0xFF), (int)((c >> 8) & 0xFF), (int)((c >> 16) & 0xFF));
}

void DumpEvents(const datetime &time[], const int rates_total, const bool force = false)
{
   if(!InpDumpEvents && !force) return;

   string fname = "Structure_events_" + _Symbol + "_" +
                  EnumToString((ENUM_TIMEFRAMES)_Period) + ".csv";
   int h = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
   {
      PrintFormat("STRUCT_DUMP 打开失败 name=%s err=%d", fname, GetLastError());
      return;
   }

   // 自描述头：参数一变，diff 时立刻能看出"是不是同一组参数下的对比"
   FileWrite(h, "# Structure event dump");
   // [v1.50-s59] 归档可归属：本文件只对应**一个**实例。同品种同周期若挂了多份，
   //   它们会写同一个文件名、后写者覆盖前者，故此行的 build/参数只能代表最后写者。
   FileWrite(h, "# instance-note: one file per symbol+period; two instances on the same "
                 "chart/symbol/period overwrite each other (not supported)");
   FileWrite(h, StringFormat("# version=1.50 build=%s symbol=%s period=%s rates=%d",
                             BUILD_TAG, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                             rates_total));
   FileWrite(h, StringFormat("# window=%d analysisWindow=%d mode=%s breakConfirm=%s nodeBreak=%s "
                             "maxEvents=%d maxSeg=%d nodes=%d mss=%d bos=%d "
                             "cisd=%d closure=%d",
                             InpWindow, InpAnalysisWindow, EnumToString(InpMode),
                             (EnumToString(EffectiveBreak())), (EnumToString(EffectiveNodeBreak())), InpMaxEvents,
                             InpMaxSeg, g_result.nNodes, g_result.nMSS, g_result.nBOS,
                             g_result.nCISD, g_result.nClosure));
   // 结构过滤参数必须记录：它们决定事件集合，缺了就无法判断两份归档是否同一口径可比。
   // 阶段 11：mainATR/mainRatio/mainFilter 三项已删除（protected swing 改由 CISD 定义），
   //          改为记录该口径本身，保证归档自描述。
   FileWrite(h, StringFormat("# filters sepATR=%.2f retracePoints=%d retraceATR=%.3f "
                             "retraceRatio=%.3f minBars=%d minAmp=%d "
                             "protectedFrom=CISD retraceFilter=%s atrPeriod=%d",
                             InpMinSeparationATR, InpMinRetracePoints, InpMinRetraceATR,
                             InpMinRetraceRatio, InpMinBarsBetweenSwings, InpMinSwingAmplitude,
                             (InpEnableRetraceFilter ? "true" : "false"), InpATRPeriod));
   // 阶段 12-c/d 后：② 收盘穿越深度已整体删除 → 头部改为记录**替代它的规则**，
   // 并声明 pen 降级为"仅供参考的度量"。
   FileWrite(h, StringFormat("# displacement dispBody=%.2f dispBars=%d "
                             "cisdFvgLookahead=%d pen=informational-only",
                             InpMinDisplaceBodyATR, InpDisplaceMaxBars,
                             InpCisdFvgLookahead));
   FileWrite(h, "# sweep levels=intermediate(tier-1) firstOnly=true");
   FileWrite(h, StringFormat("# bias tf=%s lookback=%d", EnumToString(InpBiasTF), InpBiasLookback));
   // 阶段 9：PD Array 口径必须记录 —— FVG 基于**物理相邻**三根（v1.50-s46 起；此前为有效 bar 序列），
   // OB 由 CISD 造势序列派生（实体并集）。否则两份归档无法判断是否同一口径。
   FileWrite(h, "# pdarray fvg=3candle(wick-to-wick,**physical:c3,c3+1,c3+2**;v1.50-s46) "
                "ce=mid minWidth=InpFvgMinWidthATR*ATR "
                "ob=bodyrun(from CISD run) obLevel=runOldestOpen "
                "obDraw=**horizontalline**@obLevel (zoneLo/zoneHi kept in data+CSV only; v1.50-s48)");
   // 阶段 16/17：两个**纯渲染**元素的开关也记进头部 —— 它们不产生任何事件行，
   // 但"这两份归档是不是同一套显示设置导出的"仍需可判。
   FileWrite(h, StringFormat("# render icCisd=%s latePct=%d (pure-visual,no state write) "
                             "htfCandles=%s place=%s tfMode=%s tf=%s count=%d shift=%d widthPct=%d fillPct=%d labels=%s",
                             (InpShowEarlyCISD ? "true" : "false"), InpIcLatePercent,
                             (InpShowHTFCandles ? "true" : "false"),
                             EnumToString(InpHtfTFMode),
                             EnumToString(InpHtfPlacement), EnumToString(EffCandleTF()), InpCandleCount, InpHtfShift,
                             InpCandleWidthPct, InpHtfBodyFill,
                             (InpHtfTimeLabels ? "true" : "false")));
   // 阶段 20（可观测性）：**所有开关**必须单独记一行。
   //  教训：`# render` 只记了 `icCisd` 与 `labels`，**没记 `InpShowClosures`** ——
   //  结果某次导出出现 `nodes=75 / closure=0`，差点被当成"闭包检测回归"，
   //  实际只是用户把该开关关了。
   //  **凡"关掉就会让某类数据全为 0"的开关都必须进头部** ——
   //  否则"功能没跑"与"开关没开"在数据上不可区分，而这两者的处置完全相反。
   FileWrite(h, StringFormat("# switches icCisd=%s closures=%s c3eq=%s "
                             "autoTargets=%s targetCount=%d fibTargets=%s "
                             "htfCandles=%s htfLabels=%s "
                             "fvg=%s fvgHideFilled=%s fvgMinW=%.2f ob=%s sweep=%s cisd=%s mss=%s bos=%s "
                             "erlirl=%s pdhl=%s relevance=%s range=%s bias=%s htfPlace=%s choch=%s hideWeak=%s nodeFlip=%s flipRetr=%.1f",
                             (InpShowEarlyCISD ? "true" : "false"),
                             (InpShowClosures ? "true" : "false"),
                             (InpShowC3Eq ? "true" : "false"),
                             (InpShowAutoTargets ? "true" : "false"), InpTargetCount,
                             (InpShowFibTargets ? "true" : "false"),
                             (InpShowHTFCandles ? "true" : "false"),
                             (InpHtfTimeLabels ? "true" : "false"),
                             (InpShowFVG ? "true" : "false"),
                             (InpFvgHideFilled ? "true" : "false"),
                             InpFvgMinWidthATR,
                             (InpShowOB ? "true" : "false"),
                             (InpShowSweep ? "true" : "false"),
                             (InpShowCISD ? "true" : "false"),
                             (InpShowMSS ? "true" : "false"),
                             (InpShowBOS ? "true" : "false"),
                             (InpShowERLIRL ? "true" : "false"),
                             (InpShowPDHL ? "true" : "false"),
                             (InpDrawRelevance ? "true" : "false"),
                             (InpDrawDealingRange ? "true" : "false"),
                             (InpShowBias ? "true" : "false"), EnumToString(InpHtfPlacement), (InpShowChoch ? "true" : "false"), (InpHideWeakBreaks ? "true" : "false"),
                             (InpNodeFlipMode == NODEFLIP_RETRACE ? "RETRACE" :
                              (InpNodeFlipMode == NODEFLIP_LEG ? "LEG" :
                               (InpNodeFlipMode == NODEFLIP_EXTREME ? "EXTREME" : "ANY"))),
                             InpNodeFlipRetracePct));
   // 阶段 21：区域右端策略也要记 —— 它改变"图上色带画多长"，
   //  而实测覆盖率可从 46.1% 变到 18.8%，两份归档若不同设置则观感不可比。
   FileWrite(h, StringFormat("# pdend mode=%s rightBars=%d", EnumToString(InpPDEnd), InpPDRightBars));
   // 阶段 10：IRL/ERL 是**逐帧派生**量（依赖 close[0] 与 HTF 偏置），不是事件，
   // 故不进表格，只在头部记录口径与当帧取到的值，供离线核对。
   FileWrite(h, StringFormat("# erlirl bias=%d erlValid=%s erlPrice=%s erlBar=%d "
                             "irlValid=%s irlPrice=%s irlFvgIdx=%d "
                             "basis=erl:nearest-untaken-node irl:nearest-unfilled-fvg gated=htfBias",
                             g_curBias,
                             (g_erlValid ? "true" : "false"),
                             (g_erlValid ? DoubleToString(g_erlPrice, _Digits) : ""),
                             g_erlBar,
                             (g_irlValid ? "true" : "false"),
                             (g_irlValid ? DoubleToString(g_irlPrice, _Digits) : ""),
                             g_irlFvgIdx));
   // 阶段 18：closure 口径必须记录 —— 它是"swing 有效性"的确认条件，
   // 而其中两处是本实现自定的（C3 取"实体"版而非"连区间"版；用物理相邻 K 线）。
   FileWrite(h, "# closure c2rev=sweepC1+closeBackInside c3=c3NotSweepC2+c3CloseBeyondC2Body "
                "c2cont=sweepC1+closeBeyond neighbors=physical(t-1,t+1) "
                "c3strictness=body-not-range gate=NONE(18a,no state impact;18b+POI-declined-by-user) "
                "dir=swingSide(low:UP high:DOWN;NOT-signalDir:C2-CONT-is-a-continuation) "
                 "label=subtype+(U+25B2=bull|U+25BC=bear) "
                 "c4=eqHalf(bull:low[C4]>=EQ(C3) bear:high[C4]<=EQ(C3)) recordOnly");
   // 阶段 19：目标口径。⚠️ 分部置信度必须写在头部 —— 流动性目标是他列为 primary 的规则，
   // 而投影的**符号约定是用户可选项**（`InpFibLegs`），水平表本身也只有中介置信度。
   //
   // ⚠️ 【v1.50-s22 修】这一行曾把水平表**写死**为字面量 `legs=1,2,2.5,4`。
   //     v1.50-s21 把水平表改成 `InpFibLegs` 输入后，头部就开始**谎报**实际用的水平 ——
   //     而"头部自描述"正是这个文件存在的唯一理由（两份归档要能判断是否同一口径）。
   //     凡"输入项决定内容"的头部字段，**必须来自输入项本身**，不得写死。
   FileWrite(h, StringFormat("# targets liquidity=untaken-node(bias-dir)+nearN+pdh/pdl "
                             "takenBasis=IsLiquidityTaken(shared with ERL) "
                             "projection=manipulationLeg(A=cisdRefBar-extreme,B=reverse-extreme-after-A) "
                             "legs=%s (k>0 = beyond B along trade direction; k=0 = B) "
                             "DIRECTION=USER-CONFIGURABLE(theirs is 1,0,-1,-2,-2.5,-4 with opposite sign) "
                             "conf=liquidity:high proj:medium "
                             "T1==ERL(same node; label merged as ERL/T1, target line skipped) "
                             "nodebreaks=nearest-node(bar-identity) dirRule=sameAsLastBreak?BOS:CHoCH "
                             "structDirInit=firstLeg(nodes[0] is low->UP) "
                             "dedupe=yield-if-engine-MSS/BOS@same-refBar(any,incl.weak) "
                             "CHoCH=**borrowed ICT term; 0 hits in his 110-article corpus** "
                             "note=type=BOS covers BOTH engine and node-level; see state column",
                             InpFibLegs));
   // 阶段 20（可观测性）：**颜色口径必须记录**。
   //  动机：被问"图上这个色块是什么"时，只凭色相无法归属 —— 因为
   //   ① 颜色是**输入项**，改了默认值就认不出；
   //   ② 填充色是 `PdFill(轮廓色, 图表底色)` 按百分比混出的**派生色**，不是原色。
   //  有了这一行，任何一份导出都能反推每种元素在图上究竟是什么颜色：
   //      填充色 = 底色 + (轮廓色 − 底色) × 百分比 / 100
   //  于是"色块归属"从靠眼力变成可计算。
   color bgNow = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   FileWrite(h, StringFormat("# colors bg=%s pdfillPct=%d htfBodyFillPct=%d | "
                             "fvg=%s obUp=%s obDn=%s weak=%s range=%s box=%s "
                             "htfUp=%s htfDn=%s c2=%s c3=%s cisd=%s erl=%s irl=%s tgt=%s fib=%s "
                             "| derivedFill fvg=%s weak=%s htfUp=%s htfDn=%s "
                             "| derivedFillDim fvg=%s fvgLine=%s obLineUp=%s obLineDn=%s (weak family tint; ob is a LINE, no fill, v1.50-s48/s51)",
                             ClrStr(bgNow), InpPDFillPercent, InpHtfBodyFill,
                             ClrStr(InpColorFVG), ClrStr(InpColorOBUp), ClrStr(InpColorOBDn), ClrStr(InpColorWeakBreak),
                             ClrStr(InpColorRange), ClrStr(InpColorBox),
                             ClrStr(InpColorHtfUp), ClrStr(InpColorHtfDn),
                             ClrStr(InpColorC2), ClrStr(InpColorC3), ClrStr(InpColorCISD),
                             ClrStr(InpColorERL), ClrStr(InpColorIRL),
                             ClrStr(InpColorTarget), ClrStr(InpColorFib),
                             ClrStr(PdFill(InpColorFVG, bgNow, InpPDFillPercent)),
                             ClrStr(PdFill(InpColorWeakBreak, bgNow, InpPDFillPercent)),
                             ClrStr(PdFill(InpColorHtfUp, bgNow, InpHtfBodyFill)), ClrStr(PdFill(InpColorHtfDn, bgNow, InpHtfBodyFill)),
                             ClrStr(PdFill(InpColorFVG, bgNow, InpPDFillPercent / 2)),
                             ClrStr(PdFill(InpColorFVG, bgNow, 50)),
                             ClrStr(PdFill(InpColorOBUp, bgNow, 50)), ClrStr(PdFill(InpColorOBDn, bgNow, 50))));
   FileWrite(h, "seq,type,dir,breakBar,refBar,refPrice,breakTime,refTime,"
                "displacement,tier,biasState,zoneLo,zoneHi,fillPct,fvgFollow,state");

   // 归并两个事件数组为单一时间序（旧→新）。
   // 依据：validBars 由「旧→新」构建，事件在时序循环里产生，
   //       故各数组内 bar 下标递减；bar 更大 = 更旧 = 更早 → 取大者先出。
   // ⚠️【平局口径，v1.50-s58 起显式写出】八路比较**全用严格 `>`** ⇒ 同一根 bar 上
   //   多类事件并列时，裁决权落在**最后一个** `bar == bestBar` 的判断上，即固定优先级
   //   `CHoCH > CLOSURE > OB > FVG > SWEEP > CISD > BOS > MSS`，**不是事件创建序**
   //   （同一 bar 上 CISD 会排在 MSS 之前）。该顺序**完全确定**（不随帧变化），
   //   故归档之间逐行 diff 是稳定的；写在这里是为了让"为什么 CISD 排在 MSS 前"可查，
   //   而不是让人误以为是创建序或随机序。
   int i = 0, j = 0, c = 0, w = 0, v = 0, o = 0, cl = 0, ch = 0, seq = 0;
   while(i < g_result.nMSS || j < g_result.nBOS || c < g_result.nCISD ||
         w < g_result.nSWEEP || v < g_result.nFVG || o < g_result.nOB ||
         cl < g_result.nClosure || ch < g_result.nChoch)
   {
      int pick = -1, bestBar = -1;
      if(i < g_result.nMSS  && g_result.mss[i].bar  > bestBar) { bestBar = g_result.mss[i].bar;  pick = 0; }
      if(j < g_result.nBOS  && g_result.bos[j].bar  > bestBar) { bestBar = g_result.bos[j].bar;  pick = 1; }
      if(c < g_result.nCISD && g_result.cisd[c].bar > bestBar) { bestBar = g_result.cisd[c].bar; pick = 2; }
      if(w < g_result.nSWEEP && g_result.sweep[w].bar > bestBar) { bestBar = g_result.sweep[w].bar; pick = 3; }
      if(v < g_result.nFVG && g_result.fvg[v].bar > bestBar) { bestBar = g_result.fvg[v].bar; pick = 4; }
      if(o < g_result.nOB  && g_result.ob[o].bar  > bestBar) { bestBar = g_result.ob[o].bar;  pick = 5; }
      if(cl < g_result.nClosure && g_result.closure[cl].bar > bestBar) { bestBar = g_result.closure[cl].bar; pick = 6; }
      if(ch < g_result.nChoch && g_result.choch[ch].bar > bestBar) { bestBar = g_result.choch[ch].bar; pick = 7; }

      int    bar, refBar, dir;
      bool   weakE = false;
      // v1.50-s58：CISD/OB 的第②条（后续 N 根内同向 FVG）单独成列。
      //  初值 true ⇒ 对其余事件类型该列输出 "n/a"（它没有这一条），不会与"不满足"混淆。
      bool   fvgFollowE = true;
      int    biasE = 0;
      double bodyE = 0.0, penE = 0.0;
      double zLo = 0.0, zHi = 0.0, fillE = 0.0;
      double ref;
      string type;
      string stateStr = "";
      if(pick == 0)
      {
         bar    = g_result.mss[i].bar;    refBar = g_result.mss[i].refBar;
         ref    = g_result.mss[i].ref;    dir    = g_result.mss[i].dir;
         weakE  = g_result.mss[i].weak;
         biasE  = g_result.mss[i].bias;
         bodyE  = g_result.mss[i].bodyATR;
         penE   = g_result.mss[i].penATR;
         stateStr = (weakE ? "WEAK" : "OK");
         type   = "MSS"; i++;
      }
      else if(pick == 1)
      {
         bar    = g_result.bos[j].bar;    refBar = g_result.bos[j].refBar;
         ref    = g_result.bos[j].ref;    dir    = g_result.bos[j].dir;
         biasE  = g_result.bos[j].bias;
         type   = "BOS"; j++;
      }
      else if(pick == 2)
      {
         bar    = g_result.cisd[c].bar;   refBar = g_result.cisd[c].refBar;
         ref    = g_result.cisd[c].ref;   dir    = g_result.cisd[c].dir;
         weakE  = g_result.cisd[c].weak;
         biasE  = g_result.cisd[c].bias;
         bodyE  = g_result.cisd[c].bodyATR;
         penE   = g_result.cisd[c].penATR;
         fvgFollowE = g_result.cisd[c].fvgFollow;   // v1.50-s58：第②条成因单独可查
         stateStr = ((weakE || !fvgFollowE) ? "WEAK" : "OK");
         type   = "CISD"; c++;
      }
      else if(pick == 3)
      {
         bar    = g_result.sweep[w].bar;  refBar = g_result.sweep[w].refBar;
         ref    = g_result.sweep[w].ref;  dir    = g_result.sweep[w].dir;
         biasE  = g_result.sweep[w].bias;
         type   = "SWEEP"; w++;
      }
      else if(pick == 4)
      {
         bar    = g_result.fvg[v].bar;    refBar = g_result.fvg[v].refBar;
         ref    = g_result.fvg[v].ref;    dir    = g_result.fvg[v].dir;
         biasE  = g_result.fvg[v].bias;
         zLo    = g_result.fvg[v].zoneLo; zHi = g_result.fvg[v].zoneHi;
         fillE  = g_result.fvg[v].fillPct;
         stateStr = (g_result.fvg[v].ceBroken ? "CE-BROKEN"
                                              : (fillE >= 1.0 ? "FILLED" : "OPEN"));
         type   = "FVG"; v++;
      }
      else if(pick == 6)
      {
         // 阶段 18：Candle 2 / Candle 3 收盘确认。
         //  `state` 列承载子类型（与 FVG/OB 用 state 表达状态是同一做法）。
         bar    = g_result.closure[cl].bar;  refBar = g_result.closure[cl].refBar;
         ref    = g_result.closure[cl].ref;  dir    = g_result.closure[cl].dir;
         biasE  = g_result.closure[cl].bias;
         int subC = g_result.closure[cl].sub;
         if(subC == CLOSURE_C3)
         {
            // C3 另带 C4 的均衡位结果（他："expect candle 4 to wick into the upper half"）
            int c4r = g_result.closure[cl].c4;
            stateStr = (c4r == 1) ? "C3+C4-OK" : ((c4r == 2) ? "C3-C4-BROKE" : "C3");
         }
         else stateStr = (subC == CLOSURE_C2_CONT) ? "C2-CONT" : "C2-REV";
         type   = "CLOSURE"; cl++;
      }
      else if(pick == 7)
      {
         // 阶段 30/35：**节点级**破位。顺势 → `type=BOS`（他的术语）；
         //  逆势 → `type=CHOCH`（**借用 ICT 术语**）。
         //  ⚠️ 两条都靠 `state` 列自带来源标注 —— 因为 `BOS` 这个 type 值
         //     同时被引擎 BOS 使用，只靠 type 无法区分"protected swing 破位"与"节点级破位"。
         bar    = g_result.choch[ch].bar;  refBar = g_result.choch[ch].refBar;
         ref    = g_result.choch[ch].ref;  dir    = g_result.choch[ch].dir;
         biasE  = g_result.choch[ch].bias;
         if(g_result.choch[ch].sub != NODEBRK_CHOCH)
         { type = "BOS";   stateStr = (g_result.choch[ch].sub == NODEBRK_BOS_INTERNAL ? "BOS(node-level,internal-break)" : "BOS(node-level,borrowed-ICT-frame)"); }
         else
         { type = "CHOCH"; stateStr = "CHoCH(borrowed-ICT-term)"; }
         ch++;
      }
      else
      {
         bar    = g_result.ob[o].bar;     refBar = g_result.ob[o].refBar;
         ref    = g_result.ob[o].ref;     dir    = g_result.ob[o].dir;
         biasE  = g_result.ob[o].bias;
         // D14：OB 现在携带位移度量（与 MSS/CISD 同列同格式）
         weakE  = g_result.ob[o].weak;
         fvgFollowE = g_result.ob[o].fvgFollow;     // v1.50-s58：同 CISD
         bodyE  = g_result.ob[o].bodyATR;
         penE   = g_result.ob[o].penATR;
         zLo    = g_result.ob[o].zoneLo;  zHi = g_result.ob[o].zoneHi;
         // D14 补完：原来无条件写 "VALID"，导致同一行同时出现
         // displacement="...WEAK" 与 state="VALID" —— 自相矛盾，且按 state 过滤的下游会误收。
         // 他要求 closure **和** displacement 两者都成立才算验证，故位移不足时不能叫 VALID。
         stateStr = ((weakE || !fvgFollowE) ? "WEAK" : "VALID");
         type   = "OB"; o++;
      }
      seq++;

      string tBreak = (bar    >= 0 && bar    < rates_total)
                      ? TimeToString(time[bar],    TIME_DATE | TIME_MINUTES) : "";
      string tRef   = (refBar >= 0 && refBar < rates_total)
                      ? TimeToString(time[refBar], TIME_DATE | TIME_MINUTES) : "";

      FileWrite(h, IntegerToString(seq), type,
                (dir == DIR_UP ? "UP" : "DOWN"),
                IntegerToString(bar), IntegerToString(refBar),
                DoubleToString(ref, _Digits),
                tBreak, tRef,
                ((type == "MSS" || type == "CISD" || type == "OB") ? StringFormat("body=%.2f pen=%.2f %s", bodyE, penE, (weakE ? "WEAK" : "OK")) : ""),
                ((type == "FVG" || type == "OB" || type == "CLOSURE") ? "n/a" : NodeTierStr(refBar)), BiasStr(biasE),
                ((type == "FVG" || type == "OB") ? DoubleToString(zLo, _Digits) : ""),
                ((type == "FVG" || type == "OB") ? DoubleToString(zHi, _Digits) : ""),
                (type == "FVG" ? StringFormat("%.2f", fillE) : ""),
                ((type == "CISD" || type == "OB") ? (fvgFollowE ? "yes" : "no") : "n/a"),
                stateStr);
   }
   FileClose(h);
   PrintFormat("STRUCT_DUMP 已导出 %d 条事件 -> MQL5\\Files\\%s", seq, fname);
}
//+------------------------------------------------------------------+
//| 阶段 20：把**所有矩形对象**逐条导出（每次加载只导出一次）           |
//|                                                                  |
//|  为什么必须由指标自己报：本指标的全部对象都设了                     |
//|    `OBJPROP_HIDDEN = true`（不出现在 Ctrl+B 对象列表里）           |
//|    `OBJPROP_SELECTABLE = false`（在图上点也点不中）                |
//|  ——这是刻意为之（避免几百个对象塞满列表、避免误拖），              |
//|  代价就是**外部无法逐条查看**。故只能从内部导出。                   |
//|                                                                  |
//|  只导出 `OBJ_RECTANGLE`：矩形是唯一可能被看成"彩色背景"的形状；     |
//|  线/文字无论多少条都不会造成那种观感。                              |
//|  `fill=Y/N` 直接区分"填充色块"与"空心边框"。                       |
//+------------------------------------------------------------------+
void DumpRectObjects()
{
   // v1.50-s59：原为函数内 static —— 它跨 OnDeinit/OnInit 保留（同一实例），而注释写的是
   //   "每次加载只报一次"。后果：改任一输入项/切周期后，用户按既定流程查 STRUCT_OBJDUMP
   //   会什么都看不到，与"对象没画出来"不可分辨。改为全局 + OnInit 清零（同 :914 的教训）。
   if(g_objDumped) return;
   g_objDumped = true;

   int n = 0;
   PrintFormat("STRUCT_OBJDUMP ---- 矩形对象逐条（本次加载只报一次）----");
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, OBJ_PREFIX) != 0) continue;
      if((ENUM_OBJECT)ObjectGetInteger(0, nm, OBJPROP_TYPE) != OBJ_RECTANGLE) continue;
      n++;
      color    c    = (color)ObjectGetInteger(0, nm, OBJPROP_COLOR);
      bool     fill = (bool) ObjectGetInteger(0, nm, OBJPROP_FILL);
      datetime t1   = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
      double   p1   = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
      datetime t2   = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
      double   p2   = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
      PrintFormat("STRUCT_OBJDUMP %-26s clr=%s fill=%s  %s %.2f -> %s %.2f",
                  StringSubstr(nm, StringLen(OBJ_PREFIX)), ClrStr(c), (fill ? "Y" : "N"),
                  TimeToString(t1, TIME_DATE | TIME_MINUTES), p1,
                  TimeToString(t2, TIME_DATE | TIME_MINUTES), p2);
   }
   PrintFormat("STRUCT_OBJDUMP ---- 合计 %d 个矩形（fill=Y 即填充色块）----", n);
}

void DbgReport(const datetime &time[], const int rates_total)
{
   //══════════════════════════════════════════════════════════════════
   //  ⚠️ 不变量检查**不受 InpDebugShowRef 控制** —— 刻意放在早退之前。
   //
   //  理由：`closure ≤ nodes` 是 v1.50-s18 那个跨帧累加 bug 的**唯一现场证据**
   //  （plan §35.2：首帧 59/59 → 次帧 58/117）。但当时它**只在 CSV 头部可见** ——
   //  而没人会每根 bar 去读 CSV 头部。一个"被破坏时无人看见"的不变量，
   //  等于没有不变量（这与 §36.3"永远沉默的检查与喊狼来了一样有害"是同一件事）。
   //
   //  故约定：**不变量正常时静默，被破坏时无条件发声**（不看任何开关）。
   //  调试开关只控制"正常时的详尽输出"，不控制"异常时的报警"。
   //══════════════════════════════════════════════════════════════════
   if(g_result.nClosure > g_result.nNodes)
      PrintFormat("STRUCT_INVARIANT VIOLATED: closure=%d > nodes=%d (build=%s) —— "
                  "后验扫描可能又漏了自复位，见 plan §35.2 与 Indictor/audit_state.ps1",
                  g_result.nClosure, g_result.nNodes, BUILD_TAG);

   if(!InpDebugShowRef) return;
   DumpRectObjects();   // 一次性：把全部矩形逐条报出来（对象被 HIDDEN，外部看不到）
   // 阶段 20：把**填充色块**的对象数也数出来 —— 截图问"这些色块是什么"时，
   //  数量是唯一能和图上肉眼点数对上、从而排除"某个类型没画出来"的判据。
   //  FVGo/OBo 是**矩形**数（= 真正的填充区域）；FVGc/OBc 是它们的 CE 中点线。
   int nObj = 0, nIc = 0, nHtf = 0, nTgt = 0, nFib = 0, nCloLbl = 0, nC3Eq = 0;
   int nFvgo = 0, nFvge = 0, nBoxo = 0, nRangeo = 0;
   // 阶段 21：PD Array 矩形的**实际宽度**统计（根）。
   //  用途：`InpPDEnd` 改变了"区域画多长"，而这是**唯一能把降噪效果量化**的钩子 ——
   //  否则只能靠肉眼看观感。它同时能抓出"降噪降过头"：若最小宽度是 1~2 根，
   //  说明矩形已退化成看不见的细缝（那等于把功能删了）。
   long   pdsBars = 0, pdnBars = 0, pdMin = -1, pdMax = -1;
   long   pdsSec = (long)PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   for(int k = ObjectsTotal(0) - 1; k >= 0; k--)
   {
      string nm = ObjectName(0, k);
      if(StringFind(nm, OBJ_PREFIX) != 0) continue;
      nObj++;
      string body = StringSubstr(nm, StringLen(OBJ_PREFIX));
      if(StringFind(body, "IC_") == 0 || StringFind(body, "ICLbl_") == 0) nIc++;
      else if(StringFind(body, "HTF_")   == 0) nHtf++;
      else if(StringFind(body, "TGT_")   == 0) nTgt++;
      else if(StringFind(body, "FIB_")   == 0) nFib++;
      else if(StringFind(body, "CloLbl_")== 0) nCloLbl++;
      else if(StringFind(body, "C3EQ_")  == 0) nC3Eq++;
      else if(StringFind(body, "FVGCE_") == 0) nFvge++;   // CE 中点线（"FVGCE_" 不以 "FVG_" 开头，故须单列）
      //  ⚠️ 阶段 38 起 OB **不再是矩形**（改成水平线段）⇒ 这里只统计 FVG 色块的宽度。
      //     原来的 `|| StringFind(body,"OB_")==0` 已成死条件（留着会误导读者以为 OB 还是色块），故删除。
      else if(StringFind(body, "FVG_")   == 0)
      {
         nFvgo++;
         if(pdsSec > 0 && (ENUM_OBJECT)ObjectGetInteger(0, nm, OBJPROP_TYPE) == OBJ_RECTANGLE)
         {
            datetime a = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
            datetime b2 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
            long w = (long)(b2 - a) / pdsSec;
            if(w < 0) w = -w;
            pdnBars++; pdsBars += w;
            if(pdMin < 0 || w < pdMin) pdMin = w;
            if(w > pdMax) pdMax = w;
         }
      }
      else if(StringFind(body, "Box_")   == 0) nBoxo++;
      else if(StringFind(body, "RANGE")  == 0) nRangeo++;
   }

   // 阶段 16/17/19：这三个元素此前**只能靠肉眼看图**，日志里没有任何痕迹。
   //  本行把它们变成可测量输出 —— 否则验收判据形同"请你自己看"。
   //  预期：HTF = InpCandleCount × (3 + 时间标签?1:0)（实体 + 上下影线 [+ 时间标签]）；
   //        TGT = 2 × 目标数（线 + 标签）；FIB = 2 × g_fibNLegs；
   //        IC = 0 或 2（线 + 标签，只在未收盘 bar 上）。
   PrintFormat("STRUCT_RENDER icValid=%d icLevel=%s icRefBar=%d icLate=%d icHits=%d | tgtCount=%d fibValid=%d "
               "fibA=%s fibB=%s | objs total=%d IC=%d HTF=%d TGT=%d FIB=%d CloLbl=%d C3EQ=%d "
               "| fills FVGo=%d(CE=%d) Boxo=%d RANGE=%d",
               g_icValid, DoubleToString(g_icLevel, _Digits), g_icRefBar, (g_icLate ? 1 : 0), g_icHits,
               g_tgtCount, (g_fibValid ? 1 : 0),
               (g_fibValid ? DoubleToString(g_fibA, _Digits) : "-"),
               (g_fibValid ? DoubleToString(g_fibB, _Digits) : "-"),
               nObj, nIc, nHtf, nTgt, nFib, nCloLbl, nC3Eq,
               nFvgo, nFvge, nBoxo, nRangeo);
   // 阶段 21：PD 矩形的宽度分布（根）。`pdwMin` 若为 1~2 根 ⇒ 矩形已退化成细缝。
   PrintFormat("STRUCT_PDW mode=%s rightBars=%d rects=%d widthBars min=%d avg=%.1f max=%d",
               EnumToString(InpPDEnd), InpPDRightBars, (int)pdnBars,
               (pdMin < 0 ? 0 : (int)pdMin),
               (pdnBars > 0 ? (double)pdsBars / (double)pdnBars : 0.0),
               (pdMax < 0 ? 0 : (int)pdMax));

   // 阶段 18a：closure 的**分布**必须单独打一行 ——
   //  ① 判断该功能是否真在跑靠的是**分布**而不是条数（若 C3 / C2-CONT 恒为 0，
   //     首个怀疑对象是分支成了死代码 —— v1.49-s15 的死门控就是这么漏过去的）；
   //  ② 它同时是**不变量 `closure ≤ nodes`** 的可观测锚：v1.50-s18 的"跨帧累加"bug
   //     正是被这个不变量 + CSV 头部的 `closure=` 计数抓到的（首帧 59/59 → 次帧 58/117）。
   int nC2r = 0, nC3 = 0, nCont = 0, nC4ok = 0, nC4bad = 0, nC4pend = 0;
   for(int k = 0; k < g_result.nClosure; k++)
   {
      int sb = g_result.closure[k].sub;
      if(sb == CLOSURE_C3)
      {
         nC3++;
         int c4r = g_result.closure[k].c4;
         if(c4r == 1)      nC4ok++;
         else if(c4r == 2) nC4bad++;
         else              nC4pend++;
      }
      else if(sb == CLOSURE_C2_CONT) nCont++;
      else                           nC2r++;
   }
   // C4 那一组只在 C3 上成立，故单列；`c4pend` 恒等于"C4 还没出现的 C3 条数"。
   PrintFormat("STRUCT_CLOSURE nodes=%d closure=%d c2rev=%d c3=%d c2cont=%d "
               "c4ok=%d c4broke=%d c4pending=%d invariant=%s",
               g_result.nNodes, g_result.nClosure, nC2r, nC3, nCont,
               nC4ok, nC4bad, nC4pend,
               (g_result.nClosure <= g_result.nNodes) ? "OK" : "VIOLATED");
   PrintFormat("STRUCT_DBG rates=%d nValid=%d | fractal=%d afterGap=%d "
               "afterRet=%d afterSep=%d afterC=%d seedHits=%d addHigh=%d addLow=%d | "
               "nodes=%d nBox=%d MSS=%d BOS=%d CISD=%d SWEEP=%d FVG=%d OB=%d lastBar=%d | "
               "lastNodes=%d oldestVis=%d set=%d chartObjs=%d | drawnFrom=%s nd=%d liveMiss=%d",
               g_dbgRates, g_dbgNValid,
               g_dbgRaw, g_dbgGap, g_dbgRet, g_dbgSep, g_dbgC, g_dbgSeed,
               g_dbgAddHigh, g_dbgAddLow,
               g_result.nNodes, g_result.nBox, g_result.nMSS, g_result.nBOS, g_result.nCISD, g_result.nSWEEP,
                g_result.nFVG, g_result.nOB,
               g_result.nNodes > 0 ? g_result.nodes[g_result.nNodes - 1].bar : -1,
               g_lastNodes, g_lastOldestVis, g_setUsed, nObj,
               TimeToString(g_drawnFrom, TIME_DATE | TIME_MINUTES),
               g_dbgNeedDraw, g_dbgLiveMismatch);

   //── 坐标诊断：结构线到底画在哪、图表可见范围是什么 ──
   int nN = g_result.nNodes;
   if(nN > 0)
   {
      int bFirst = g_result.nodes[0].bar;
      int bLast  = g_result.nodes[nN - 1].bar;
      PrintFormat("STRUCT_GEO n=%d  barFirst=%d barLast=%d  "
                  "time[barFirst]=%s time[barLast]=%s time[0]=%s time[1]=%s",
                  nN, bFirst, bLast,
                  TimeToString(time[bFirst]), TimeToString(time[bLast]),
                  TimeToString(time[0]), (rates_total > 1 ? TimeToString(time[1]) : ""));

      // 读回前 3 段与后 3 段对象的真实坐标
      for(int s = 0; s < 3 && s < nN - 1; s++)
      {
         int b1 = g_result.nodes[s].bar, b2 = g_result.nodes[s + 1].bar;
         string on = OBJ_PREFIX + "Seg_" + IntegerToString(b1) + "_" + IntegerToString(b2);
         if(ObjectFind(0, on) < 0) { PrintFormat("STRUCT_GEO  head[%d] %s  MISSING", s, on); continue; }
         PrintFormat("STRUCT_GEO  head[%d] %s  t1=%s p1=%.5f  t2=%s p2=%.5f  clr=%d w=%d",
                     s, on,
                     TimeToString((datetime)ObjectGetInteger(0, on, OBJPROP_TIME, 0)),
                     ObjectGetDouble(0, on, OBJPROP_PRICE, 0),
                     TimeToString((datetime)ObjectGetInteger(0, on, OBJPROP_TIME, 1)),
                     ObjectGetDouble(0, on, OBJPROP_PRICE, 1),
                     (int)ObjectGetInteger(0, on, OBJPROP_COLOR),
                     (int)ObjectGetInteger(0, on, OBJPROP_WIDTH));
      }
      for(int s = nN - 3; s < nN - 1; s++)
      {
         if(s < 0) continue;
         int b1 = g_result.nodes[s].bar, b2 = g_result.nodes[s + 1].bar;
         string on = OBJ_PREFIX + "Seg_" + IntegerToString(b1) + "_" + IntegerToString(b2);
         if(ObjectFind(0, on) < 0) { PrintFormat("STRUCT_GEO  tail[%d] %s  MISSING", s, on); continue; }
         PrintFormat("STRUCT_GEO  tail[%d] %s  t1=%s p1=%.5f  t2=%s p2=%.5f  clr=%d w=%d",
                     s, on,
                     TimeToString((datetime)ObjectGetInteger(0, on, OBJPROP_TIME, 0)),
                     ObjectGetDouble(0, on, OBJPROP_PRICE, 0),
                     TimeToString((datetime)ObjectGetInteger(0, on, OBJPROP_TIME, 1)),
                     ObjectGetDouble(0, on, OBJPROP_PRICE, 1),
                     (int)ObjectGetInteger(0, on, OBJPROP_COLOR),
                     (int)ObjectGetInteger(0, on, OBJPROP_WIDTH));
      }
   }
   //── 可见性诊断：当前图表可视 bar / 价格区间，以及有多少结构线落在视口内 ──
   //  这是"对象建出来了但看不见"这一症状的判定依据：
   //  若 inTimeView>0 却仍看不见 → 问题在重绘/图层，而非坐标。
   int    firstVis = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int    visBars  = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   int    visLast  = firstVis - visBars + 1;
   if(visLast  < 0)             visLast  = 0;
   if(firstVis > rates_total-1) firstVis = rates_total - 1;
   if(firstVis < 0)             firstVis = 0;
   double pMin = ChartGetDouble(0, CHART_PRICE_MIN);
   double pMax = ChartGetDouble(0, CHART_PRICE_MAX);
   PrintFormat("STRUCT_VIEW %s %s firstVis=%d visBars=%d -> bars[%d..%d] times[%s .. %s] "
               "price[%.5f..%.5f] scale=%d",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
               firstVis, visBars, visLast, firstVis,
               TimeToString(time[firstVis]), TimeToString(time[visLast]),
               pMin, pMax, (int)ChartGetInteger(0, CHART_SCALE));

   //  时序语义下：firstVis = 左边界 = 更旧；firstVis - visBars + 1 = 右边界 = 更新。
   //  （上一版这里写反了，导致 inTimeView 恒为 0 —— 是诊断自身的 bug。）
   datetime tVisOld = time[firstVis], tVisNew = time[visLast];
   int inView = 0, priceIn = 0, segTotal = 0;
   for(int k = ObjectsTotal(0) - 1; k >= 0; k--)
   {
      string on = ObjectName(0, k);
      if(StringFind(on, OBJ_PREFIX + "Seg_") != 0) continue;
      segTotal++;
      datetime a = (datetime)ObjectGetInteger(0, on, OBJPROP_TIME, 0);
      datetime b = (datetime)ObjectGetInteger(0, on, OBJPROP_TIME, 1);
      if(a > b) { datetime tt = a; a = b; b = tt; }
      if(b < tVisOld || a > tVisNew) continue;     // 时间上不在视口
      inView++;
      double pa = ObjectGetDouble(0, on, OBJPROP_PRICE, 0);
      double pb = ObjectGetDouble(0, on, OBJPROP_PRICE, 1);
      double lo = MathMin(pa, pb), hi = MathMax(pa, pb);
      if(hi >= pMin && lo <= pMax) priceIn++;      // 价格上也落在视口
   }
   PrintFormat("STRUCT_VIEW segTotal=%d inTimeView=%d inPriceView=%d",
               segTotal, inView, priceIn);

   PrintFormat("STRUCT_GEO win=%d rates=%d oldest_bar=%s newest_bar=%s",
               InpWindow, rates_total,
               TimeToString(time[rates_total - 1]), TimeToString(time[0]));
}

//+------------------------------------------------------------------+
//| 初始化                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpWindow < 2)
   {
      Print("Structure: InpWindow 必须 ≥ 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   // 阶段 17/19：新增元素的规模校验。
   //  理由不是"洁癖"，而是仓库记过的实况：**MT5 单图表对象数有上限，超了会被终端拒绝创建**
   //  （见 InpMaxSeg 的注释）。HTF 蜡烛是唯一"按输入线性放大对象数"的新元素
   //  —— 每根 3 个对象，`InpCandleCount = 200` 就是 600 个。
   //  其余三项都是**内部有界**的：目标 ≤ 2×MAX_TARGETS、投影 = 2×g_fibNLegs（≤ 2×FIB_NLEGS_MAX）、
   //  closure 标签受 InpMaxEvents 裁剪，故不在此处校验。
   if(InpCandleCount < 0 || InpCandleCount > 50)
   {
      PrintFormat("Structure: InpCandleCount 必须在 0..50（每根 3 个对象；收到 %d）",
                  InpCandleCount);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpHtfBodyFill < 0 || InpHtfBodyFill > 100)
   {
      PrintFormat("Structure: InpHtfBodyFill 必须在 0..100（收到 %d）", InpHtfBodyFill);
      return INIT_PARAMETERS_INCORRECT;
   }
   // 阶段 43（用户要求）：**蜡烛周期必须 ≥ 图表周期**。
   //  为什么这条重要：设低了**不会报错**，只会静默地画"低周期蜡烛" ——
   //  那已经不是 HTF（他的条目原文是 "View HTF candles on your entry timeframe"），
   //  而观感上很难一眼看出错在哪。用户实机核对时点出了这个静默失败。
   //  ⚠️ 与其余各项校验**一致：阻断初始化并打印原因**，而不是只警告 ——
   //     静默地画错比拒绝加载更糟。若确实想看低周期蜡烛，那是另一个需求，得另开开关。
   //  ⚠️ 但只在**蜡烛开着时**才校验：否则"关掉该功能"的人会因为一个
   //     根本用不到的输入项而完全加载不了指标（例如在 D1 图上用默认 `InpCandleTF=H4`：
   //     蜡烛开着时应当拒绝并提示改周期；关掉蜡烛后没有任何理由拦住整个指标）。
   if(InpShowHTFCandles &&
      PeriodSeconds(EffCandleTF()) < PeriodSeconds((ENUM_TIMEFRAMES)_Period))
   {
      PrintFormat("Structure: 蜡烛周期(%s) 必须 ≥ 图表周期(%s)（tfMode=%s）—— "
                  "否则画的不是高周期蜡烛，而是低周期蜡烛",
                  EnumToString(EffCandleTF()), EnumToString((ENUM_TIMEFRAMES)_Period),
                  EnumToString(InpHtfTFMode));
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTargetCount < 0 || InpTargetCount > MAX_TARGETS)
   {
      PrintFormat("Structure: InpTargetCount 必须在 0..%d（收到 %d）",
                  MAX_TARGETS, InpTargetCount);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpPDRightBars < 0)
   {
      PrintFormat("Structure: InpPDRightBars 不能为负（收到 %d）", InpPDRightBars);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpHtfShift < 0)
   {
      PrintFormat("Structure: InpHtfShift 不能为负（收到 %d）—— 那会指向未来的 K 线",
                  InpHtfShift);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpIcLatePercent < 0 || InpIcLatePercent > 100)
   {
      PrintFormat("Structure: InpIcLatePercent 必须在 0..100（收到 %d）",
                  InpIcLatePercent);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpATRPeriod < 2)
   {
      Print("Structure: InpATRPeriod 必须 ≥ 2");
      return INIT_PARAMETERS_INCORRECT;
   // v1.50-s59：InpAnalysisWindow 是唯一直接决定"分析几根 bar"的量，却从未被校验。
   //   设 1 或 2 会让 nValid 恒 < 3 ⇒ ComputeStructure 在算任何东西之前就早退 ⇒
   //   零 MSS/BOS/CISD/FVG/OB/SWEEP/CHoCH/CLOSURE，图上什么都不画，且不报任何错。
   //   0 仍放行（= 全量分析）。
   if(InpAnalysisWindow != 0 && InpAnalysisWindow < 3)
   {
      PrintFormat("Structure: InpAnalysisWindow 必须为 0（全量）或 >= 3（收到 %d）；"
                  "1/2 会让有效 bar 不足 3 根而使结构检测整体失效", InpAnalysisWindow);
      return INIT_PARAMETERS_INCORRECT;
   }
   // v1.50-s59：负值会让 BiasAtTime 的循环体一次都不执行 ⇒ 恒返回 0 ⇒
   //   ERL/IRL/AutoTargets/Fib 投影与事件弱化分级全部静默消失。
   if(InpBiasLookback < 1)
   {
      PrintFormat("Structure: InpBiasLookback 必须 >= 1（收到 %d）", InpBiasLookback);
      return INIT_PARAMETERS_INCORRECT;
   }
   }
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Structure(%d)", InpWindow));
   // 阶段 19：操纵腿投影的水平表（倍数）。
   //  ⚠️ 他的原文表是 `1, 0, −1, −2, −2.5, −4`（**负向**扩展）。本实现取正号 ——
   //     理由见输入组注释（TradingView 约定下负号指向起点之外 = 止损方向，作为目标讲不通）。
   //     要逐字对齐他的表，改这四行即可（负号会立刻改变图上的方向，A/B 导出会看到价位变化）。
   // 阶段 19：操纵腿投影的水平表。
   //  ⚠️ 语义是 `价位 = B + 腿长 × k`，故 **k > 0 = 沿交易方向外推**。
   //     他的原文表 `1, 0, −1, −2, −2.5, −4` 用的是相反符号约定（负向落在起点 A 之外），
   //     照填会得到"止损方向"的线 —— 该说明写在输入项注释与 CSV 头部，由用户选择。
   //     把选择权交出去，好过由本实现替他定死（§38.4 的"改做"因此降级为"可配置"）。
   g_fibNLegs = 0;
   string parts[];
   int np = StringSplit(InpFibLegs, ',', parts);
   for(int i = 0; i < np && g_fibNLegs < FIB_NLEGS_MAX; i++)
   {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      double v = StringToDouble(s);
      // 拒绝 NaN/空串解析结果：StringToDouble 对垃圾输入返回 0，无法区分，
      // 故用 StringLen 已排除空串，其余按数值接受（0 本身就是合法水平）。
      g_fibLegs[g_fibNLegs++] = v;
   }
   if(InpShowFibTargets && g_fibNLegs == 0)
   {
      PrintFormat("Structure: InpFibLegs 解析出 0 条水平（收到 \"%s\"）", InpFibLegs);
      return INIT_PARAMETERS_INCORRECT;
   }
   // 无条件打印：用于确认 MT5 加载的正是本文件编译出的 .ex5
   // （若「专家」里看不到这一行，说明图表上跑的不是这个文件）
      // 关键参数回显：这些参数决定事件集合，专家标签页里可见 → 改完输入项可自证是否生效，
   // 不必再依赖"文件时间戳/是否出现 reason=5"这类间接判据（本会话已证明它不可靠）。
   // 版本号只允许有一个来源 = BUILD_TAG（见 OnDeinit 的历史事故注释）
   PrintFormat("Structure 已初始化 | build=%s | "
               "window=%d analysisWindow=%d mode=%s breakConfirm=%s maxEvents=%d maxSeg=%d | "
               "filters sepATR=%.2f retracePoints=%d retraceATR=%.3f retraceRatio=%.3f "
               "minBars=%d minAmp=%d | protectedFrom=CISD "
               "retraceFilter=%s atrPeriod=%d | dispBody=%.2f dispBars=%d cisdFvgFollow=%d | InpDebugShowRef=%s",
               BUILD_TAG,
               InpWindow, InpAnalysisWindow, EnumToString(InpMode),
               (EnumToString(EffectiveBreak())), InpMaxEvents, InpMaxSeg,
               InpMinSeparationATR, InpMinRetracePoints, InpMinRetraceATR, InpMinRetraceRatio,
               InpMinBarsBetweenSwings, InpMinSwingAmplitude,
               (InpEnableRetraceFilter ? "true" : "false"), InpATRPeriod,
               InpMinDisplaceBodyATR, InpDisplaceMaxBars, InpCisdFvgLookahead,
               InpDebugShowRef ? "true" : "false");
   // 阶段 22：**新增开关**必须进 INIT 回显（本行无条件打印）。
   //  教训：`# switches` 只写进 CSV（要 InpDumpEvents），`STRUCT_PDW` 只走 DbgReport
   //  （要 InpDebugShowRef）。于是这两个开关都关着时，"参数是默认值"与"用户手改过"
   //  **在日志上完全不可区分** —— 被问"当前是不是 OB 首次回踩即停"时，
   //  我只能从代码默认值推断，拿不出这一次加载的实证。
   //  INIT 回显是**唯一无条件打印**的一行，故凡会改变图上观感的新开关都放这里。
   PrintFormat("STRUCT_SWITCH pdEnd=%s pdRightBars=%d | earlyCisd=%s icLatePct=%d | "
               "closures=%s c3eq=%s | autoTargets=%s targetCount=%d fibTargets=%s | "
               "htfCandles=%s tfMode=%s tf=%s htfPlace=%s htfLabels=%s htfShift=%d htfCount=%d | "
               "fvg=%s fvgHideFilled=%s fvgMinW=%.2f ob=%s pdFillPct=%d choch=%s hideWeak=%s nodeBreak=%s nodeFlip=%s flipRetr=%.1f",
               EnumToString(InpPDEnd), InpPDRightBars,
               (InpShowEarlyCISD ? "true" : "false"), InpIcLatePercent,
               (InpShowClosures ? "true" : "false"), (InpShowC3Eq ? "true" : "false"),
               (InpShowAutoTargets ? "true" : "false"), InpTargetCount,
               (InpShowFibTargets ? "true" : "false"),
               (InpShowHTFCandles ? "true" : "false"), EnumToString(InpHtfTFMode), EnumToString(EffCandleTF()),
                EnumToString(InpHtfPlacement),
                (InpHtfTimeLabels ? "true" : "false"),
               InpHtfShift, InpCandleCount,
               (InpShowFVG ? "true" : "false"), (InpFvgHideFilled ? "true" : "false"), InpFvgMinWidthATR,
               (InpShowOB ? "true" : "false"), InpPDFillPercent, (InpShowChoch ? "true" : "false"), (InpHideWeakBreaks ? "true" : "false"),
                EnumToString(EffectiveNodeBreak()),
                (InpNodeFlipMode == NODEFLIP_RETRACE ? "RETRACE" :
                 (InpNodeFlipMode == NODEFLIP_LEG ? "LEG" :
                  (InpNodeFlipMode == NODEFLIP_EXTREME ? "EXTREME" : "ANY"))),
                (InpNodeFlipRetracePct));

   // 阶段 25：右侧留白模式**必须**有 Chart Shift，否则留白区宽度为 0，蜡烛会全挤在价格右缘。
   //  自动开启（并记住原值，OnDeinit 还原 —— 不给用户留下副作用）。
   //  ⚠️ 副作用调用一律写成独立语句，不得放进 `&&` / `||` 右侧（仓库硬约定 2）。
   if(InpShowHTFCandles && InpHtfPlacement == HTF_PLACE_RIGHT)
   {
      g_shiftOnOrig   = (bool)ChartGetInteger(0, CHART_SHIFT);
      g_shiftSizeOrig = ChartGetDouble(0, CHART_SHIFT_SIZE);
      g_shiftSaved    = true;
      if(!g_shiftOnOrig) ChartSetInteger(0, CHART_SHIFT, true);
      if(g_shiftSizeOrig < 20.0) ChartSetDouble(0, CHART_SHIFT_SIZE, 25.0);
      PrintFormat("STRUCT_HTFPOS 右侧留白模式：Chart Shift 原值 on=%s size=%.1f ；已确保 on=true size>=20",
                  (g_shiftOnOrig ? "true" : "false"), g_shiftSizeOrig);
   }
   g_lastRates = 0;   // v1.50-s58：本次 OnInit 后首个 OnCalculate 必走全量帧（换品种/改参数同理）
   g_objDumped = false;   // v1.50-s59：本次加载重新允许报一次矩形清单
   // ⚠️【v1.50-s59】needDraw 是"**变化**检测器"而不是"有效性检测器"，而这些指纹全局跨
   //   OnDeinit/OnInit 存活。只清 g_lastRates 不够：改**标量**输入（颜色/线型/线宽等）后
   //   事件集合完全没变，于是 `time[0] != g_lastT0` 及其后整条 || 链全假 ⇒ 首个全量帧
   //   虽然跑了 ComputeStructure，绘制块却被跳过 ⇒ 图上仍是**旧颜色**，要等下一根 bar 才纠正。
   //   置 g_lastT0 = 0 使首个全量帧的指纹必真（time[0] 恒 > 0）；底色缓存同理置 -1。
   g_lastT0    = 0;
   g_lastBgClr = -1;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 退出：清理全部对象                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ⚠️ 只打印 BUILD_TAG，不再写版本字面量。
   //   历史事故：此处曾硬编码 "v1.48"，而 BUILD_TAG 已到 v1.49-s14b ——
   //   于是"最能证明加载了哪一版"的那行日志，反而一直在报错误的版本。
   //   凡版本号，只允许有一个来源 = BUILD_TAG。
   PrintFormat("Structure 已卸载 | build=%s | reason=%d | nodes=%d",
               BUILD_TAG, reason, g_result.nNodes);
   // 阶段 25：还原 Chart Shift（右侧留白模式可能改过它）—— 不留副作用
   if(g_shiftSaved)
   {
      ChartSetInteger(0, CHART_SHIFT, g_shiftOnOrig);
      ChartSetDouble(0, CHART_SHIFT_SIZE, g_shiftSizeOrig);
   }
   ObjectsDeleteAll(0, OBJ_PREFIX);
}

//+------------------------------------------------------------------+
//| 阶段 27：按 Shift+S 把**当前图表**导成 PNG，交给"看图的人"            |
//|                                                                  |
//|  为什么加它：我（AI）**看不到终端画面**。以往判断"画成什么样"全靠对象   |
//|  转储与计数 —— 那是**数据层**证据；而"观感对不对""字形是不是方框"     |
//|  属于**像素层**，没有图就只能猜。故让指标自己把图交出来。              |
//|                                                                  |
//|  ⚠️ 只写 `MQL5\Files`（终端自己的沙箱）——**不抓屏幕**、不含窗口外任何   |
//|     内容，也不依赖 MT5 窗口是否在最前。                              |
//|  ⚠️ 文件名不用 `TimeToString`：它产出 `2026.09.24 17:55:03`，其中的     |
//|     `:` 与空格在 Windows 上是非法文件名字符，写盘会直接失败。          |
//+------------------------------------------------------------------+
void SnapChart()
{
   // ⚠️ 尺寸上限不是猜的：`ChartScreenShot` 对宽高有上限，超限直接不生成文件。
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(w < 200) w = 200;
   if(w > 1920) w = 1920;
   if(h < 200) h = 200;
   if(h > 1200) h = 1200;

   string sym = _Symbol;                 // XAUUSD.ct 里的 '.' 也一并换掉，避免与扩展名混淆
   StringReplace(sym, ".", "_");
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   string fname = StringFormat("Structure_snap_%s_%04d%02d%02d_%02d%02d%02d.png",
                               sym, dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

   bool ok = ChartScreenShot(0, fname, w, h, ALIGN_RIGHT);
   // 把落盘目录一并打出来 —— "文件到底存哪"不靠猜（终端/测试器/便携模式路径不同）
   PrintFormat("STRUCT_SNAP ok=%s file=%s size=%dx%d path=%s",
               (ok ? "true" : "false"), fname, w, h,
               TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files");
}

//+------------------------------------------------------------------+
//| 阶段 28：按 Shift+D 立即导出一份事件 CSV（不改输入项、不重挂指标）    |
//|                                                                  |
//|  为什么需要它：回答"某处的事件有没有产生／为什么没被标注"必须看         |
//|  **事件级**数据（`type/dir/breakBar/refBar/refPrice/displacement    |
//|  (WEAK|OK)/biasState`），而那只有 `InpDumpEvents=true` 才有。        |
//|  挂到热键上 = 把取证成本从"改输入 → 重挂 → 等一次全量帧"降到"按一个键"。|
//|                                                                  |
//|  ⚠️ v1.50-s59 修正：原注释写"热键必须显式 force 绕过 InpDumpEvents"，
//|     但那会让 InpDumpEvents=false 的用户按一下 Shift+D 就落盘、并**覆盖**自己
//|     先前导出的归档（文件名固定）。现改为热键同样受 InpDumpEvents 门控，
//|     被挡住时打一行可分辨日志 —— 既保住"可取证"，又不产生意外文件。
void DumpEventsNow()
{
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(bars <= 0)
   {
      PrintFormat("STRUCT_DUMP 热键失败：Bars()=%d", bars);
      return;
   }
   datetime t[];
   ArraySetAsSeries(t, true);
   int copied = CopyTime(_Symbol, PERIOD_CURRENT, 0, bars, t);
   if(copied <= 0)
   {
      PrintFormat("STRUCT_DUMP 热键失败：CopyTime err=%d", GetLastError());
      return;
   }
   // ⚠️【v1.50-s59】不再无条件绕过 InpDumpEvents。
   //   原实现让 Shift+D（InpHotkeys 默认 true）在任何图表上都能落盘，而 :963 的注释承诺
   //   "仅 InpDumpEvents=true 时写文件，默认关 → 常态零成本"。更麻烦的是文件名固定（:964
   //   "同品种同周期 → 每次全量重算覆盖"），于是一次误按热键就会**覆盖掉**用户先前
   //   InpDumpEvents=true 导出的归档 —— 一次误操作毁掉一份对照基线。
   //   改为：热键只在显式开启导出时才写，否则打一行可分辨的日志说明被谁挡住。
   if(!InpDumpEvents)
   {
      PrintFormat("STRUCT_DUMP 热键导出已被挡住：InpDumpEvents=false（本次不写文件）");
      return;
   }
   DumpEvents(t, copied, true);   // force=true：绕过门控，但门控已在上方显式确认过
}

//+------------------------------------------------------------------+
//| 阶段 25：缩放/平移会改变右侧留白的宽度 ⇒ 整排 HTF 蜡烛必须重排     |
//|                                                                  |
//|  ⚠️ 为什么需要这条事件：`RenderScene` 只在**全量帧**（新 bar）跑，   |
//|     而缩放不产生新 bar。若只靠全量帧，缩放后整排蜡烛会停在旧坐标。  |
//|  ⚠️ 这里只换坐标、**不注册场景集** —— 对象名用的是蜡烛真实开盘时间， |
//|     与全量帧注册的名字一致，故不会被回收段误删。                    |
//|  ⚠️ 阶段 27 起本函数还接按键：**按键事件必须先于 CHART_CHANGE 早退**。|
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(!InpHotkeys) return;
      // ⚠️ 为什么用 Shift 修饰而不是裸字母：裸字母在 MT5 图表上有内建语义，
      //    且"我按了键但指标没收到"与"收到了但没识别"必须可分辨 ——
      //    故未命中的按键也回显（前 20 次），用来**实测**按键到底有没有送来。
      long shiftK = TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT);
      long ctrlK  = TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL);
      bool isS    = (lparam == 83 || lparam == 115);      // 'S' / 's'
      bool isD    = (lparam == 68 || lparam == 100);      // 'D' / 'd'
      // `!= 0` 对"按下返回 -1 / 1 / -128（实测位掩码）"各种约定都成立
      if(shiftK != 0)
      {
         if(isS) { SnapChart();     return; }            // Shift+S → 图表 PNG
         if(isD) { DumpEventsNow(); return; }            // Shift+D → 事件 CSV
      }
      static int s_keyEcho = 0;
      if(s_keyEcho < 20)
      {
         s_keyEcho++;
         PrintFormat("STRUCT_SNAP key=%d shiftRaw=%d ctrlRaw=%d (未命中，仅回显)",
                     (int)lparam, (int)shiftK, (int)ctrlK);
      }
      return;
   }
   if(id != CHARTEVENT_CHART_CHANGE) return;
   if(!InpShowHTFCandles || InpHtfPlacement != HTF_PLACE_RIGHT) return;
   datetime tBase = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(tBase == 0) return;
   g_htfSlot = HtfRightSlotSec();
   bool changed = false;
   DrawHtfCandles(tBase, false, changed);
   if(changed) ChartRedraw();
}

//══════════════════════════════════════════════════════════════════
//  分析层：结果记录助手
//══════════════════════════════════════════════════════════════════

void AddNodeResult(const int bar, const double price, const bool isHigh)
{
   ArrayResize(g_result.nodes, g_result.nNodes + 1);
   g_result.nodes[g_result.nNodes].bar    = bar;
   g_result.nodes[g_result.nNodes].price  = price;
   g_result.nodes[g_result.nNodes].isHigh = isHigh;
   g_result.nodes[g_result.nNodes].isMain = true;
   g_result.nNodes++;
}

//+------------------------------------------------------------------+
//| 反查"被突破极值节点"所在 bar（创建事件时调用，此刻节点仍在序列）   |
//| ref 恒为节点价格 → 方向匹配 + 价格容差必命中；取最新同价节点       |
//| 返回 -1 表示未命中（防御：渲染回退到事件 bar）                     |
//+------------------------------------------------------------------+
int FindBrokenNodeBar(const double ref, const int dir)
{
   bool wantHigh = (dir == DIR_UP);
   for(int n = g_result.nNodes - 1; n >= 0; n--)
   {
      if(g_result.nodes[n].isHigh != wantHigh) continue;
      if(MathAbs(g_result.nodes[n].price - ref) <= _Point * 0.5)
         return g_result.nodes[n].bar;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| 阶段 4：CISD 事件入列                                              |
//|  复用 StructureEvent：ref = CISD 位（造势序列最旧一根的开盘价）、  |
//|  refBar = 该极值所在 bar。dir = 收盘穿越的方向。                    |
//|  位移度量经 g_lastBodyATR / g_lastPenATR 传入（与 MSS 同一套判据）。|
//+------------------------------------------------------------------+
void AddCisdResult(const int breakBar, const int dir, const double level,
                   const int extremeBar, const bool strong)
{
   ArrayResize(g_result.cisd, g_result.nCISD + 1);
   g_result.cisd[g_result.nCISD].bar     = breakBar;
   g_result.cisd[g_result.nCISD].dir     = dir;
   g_result.cisd[g_result.nCISD].ref     = level;
   g_result.cisd[g_result.nCISD].refBar  = extremeBar;
   g_result.cisd[g_result.nCISD].weak    = !strong;
   g_result.cisd[g_result.nCISD].fvgFollow = true;   // 第②条由 ComputeCisdFvgFollow 逐帧覆写
   g_result.cisd[g_result.nCISD].bodyATR = g_lastBodyATR;
   g_result.cisd[g_result.nCISD].penATR  = g_lastPenATR;
   if(InpDebugShowRef)
      Print("CISD event: type=CISD dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " breakBar=", breakBar, " extremeBar=", extremeBar,
            " level=", DoubleToString(level, _Digits),
            " bodyATR=", DoubleToString(g_lastBodyATR, 2),
            " penATR=",  DoubleToString(g_lastPenATR, 2),
            " ", (strong ? "OK" : "WEAK"));
   g_result.nCISD++;
}

//+------------------------------------------------------------------+
//| 阶段 18：Candle 2 / Candle 3 收盘确认事件入列                      |
//+------------------------------------------------------------------+
void AddClosureResult(const int c2Bar, const int dir, const double level,
                      const int refBar, const int sub)
{
   ArrayResize(g_result.closure, g_result.nClosure + 1);
   g_result.closure[g_result.nClosure].bar    = c2Bar;
   g_result.closure[g_result.nClosure].dir    = dir;
   g_result.closure[g_result.nClosure].ref    = level;
   g_result.closure[g_result.nClosure].refBar = refBar;
   g_result.closure[g_result.nClosure].sub    = sub;
   g_result.closure[g_result.nClosure].c4     = 0;   // 由 ComputeClosures 在 C3 分支覆写
   // ⚠️ 恒为 false：closure **没有位移判据**。它的 `sub` 表达"哪种确认"，
   //    不是"信号质量降级" —— 复用 weak 会把两种语义混成一个字段
   //    （同 v1.49 第 11 条对 FVG 的处置）。
   g_result.closure[g_result.nClosure].weak   = false;
   g_result.closure[g_result.nClosure].fvgFollow = false;   // 非 CISD/OB：无含义
   if(InpDebugShowRef)
      Print("CLOSURE event: c2Bar=", c2Bar, " refBar=", refBar,
            " dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " sub=", (sub == CLOSURE_C3 ? "C3"
                      : (sub == CLOSURE_C2_CONT ? "C2-CONT" : "C2-REV")),
            " level=", DoubleToString(level, _Digits));
   g_result.nClosure++;
}

//+------------------------------------------------------------------+
//| 阶段 18a 补：C4 是否守住 C3 的均衡位那一半                          |
//|                                                                  |
//|  他（research §2）：*"For a C3 closure: mark the **full range of    |
//|  candle 3**; bullish expect candle 4 to **wick into the upper half  |
//|  of candle 3**; bearish into the lower half."*                     |
//|                                                                  |
//|  实现：C4（= C3 之后那根）的影线是否**停在预期的那一半内**：          |
//|    看涨 → `low[C4]  >= EQ(C3)`（未跌破上半的下沿）                  |
//|    看跌 → `high[C4] <= EQ(C3)`（未升破下半的上沿）                  |
//|  返回 0 = C4 尚未出现（待定）/ 1 = 守住 / 2 = 已破。                |
//|                                                                  |
//|  ⚠️ 【自定口径】他给的是一句期望（"expect … to wick into"），         |
//|     **没有说破掉之后算不算失效**。本实现把"破 EQ"记为 2，但**不据此     |
//|     删除或弱化任何东西** —— 它只如实记录，不参与判定（仍是 18a 性质）。 |
//+------------------------------------------------------------------+
int EvalC4Half(const double &high[], const double &low[],
               const int c3, const int dir)
{
   int c4 = c3 - 1;                       // 序列方向：index 更小 = 更新
   if(c3 < 0 || c4 < 0) return 0;         // C4 还没出现 → 待定
   if(high[c3] <= low[c3]) return 0;      // 退化 C3（零区间）→ 不判
   double eq = (high[c3] + low[c3]) * 0.5;
   if(dir == DIR_UP) return (low[c4]  >= eq) ? 1 : 2;
   return                    (high[c4] <= eq) ? 1 : 2;
}

//+------------------------------------------------------------------+
//| 阶段 18a：Candle 2 / Candle 3 收盘确认（后验层）                   |
//|                                                                  |
//|  对每个**已确认**的结构节点（= C2）判定它带的是哪一种 closure。      |
//|                                                                  |
//|  ⚠️ 必须跑在主循环之后：节点 bar 可能被后续更极端的 swing 替换，     |
//|     而 closure 要标注在**最终**的节点上。                          |
//|  ⚠️ **只写 g_result.closure**，不触碰 nodes / SState / 任何判定路径 |
//|     —— 18a 的全部意义就在这条（门禁见 18b，未实现）。               |
//|                                                                  |
//|  ── 为什么 C3 的条件**不是**"C2 未扫破 C1" ──                        |
//|    按严格三点分形，swing low at b 恒有 `low[b] < low[b+1]`（b+1 与    |
//|    b 不可能"平低"，且内包 K 线不参与 swing 判定，不会让 b+1 变成      |
//|    更低点）。故"C2 未扫破前根"会让 C3 分支**永不触发**，成为死代码。  |
//|    他更明确的那一句是："When this happens **without sweeping the      |
//|    candle 2 high or low**, it becomes a candle 3 closure." ——         |
//|    这里的"previous candle"相对 C3 而言就是 **C2**。故条件取：          |
//|      ① C3 **没有**扫破 C2 的极值（`low[b-1] >= low[b]`）；           |
//|      ② C3 收在 **C2 实体之外**。                                     |
//|    而"C2 未能给出确认"作为**前提**保留：已有 C2-REV 的节点不再判 C3   |
//|    （他的原文："A candle 3 closure occurs when candle 2 **fails** to  |
//|    give the required closure"）。                                   |
//+------------------------------------------------------------------+
void ComputeClosures(const double &open[], const double &high[],
                     const double &low[], const double &close[],
                     const int rates_total)
{
   // ⚠️ 自复位必须放在**早退之前** —— 后验扫描的约定是"自己清自己的计数"
   //    （同 ComputeSweeps 的 `nSWEEP = 0`）。
   //
   //    【v1.50-s18 的真实事故，必须留在代码里】本条初版漏了自复位，而 `g_result`
   //    的集中复位块也没有 `nClosure` ⇒ 每经过一次全量重算就**累加**一遍：
   //      首帧  nodes=59 / closure=59   ← 正确
   //      下一帧 nodes=58 / closure=117 ← ≈ 59+58，每帧多一份
   //    抓出它的是**不变量 `closure ≤ nodes`** 与 CSV 头部的 `closure=` 计数 ——
   //    不是编译（0 errors / 0 warnings），也不是事前的"构造性证明"：
   //    那条证明只覆盖**单次调用内**（三分支互斥 + continue），**漏掉了跨调用**。
   //    放在早退之前还保证 `InpShowClosures=false` 时不留上一帧的陈旧数据 ——
   //    否则 A/B 对照的前提（关掉开关 = 零 CLOSURE 行）本身就不成立。
   //  【阶段 18b 终态：不做门禁（用户 2026-09-24 裁定）】
   //  他有一条门禁级规则："A swing is only valid when it has both: a point of interest
   //  and a valid closure (candle 2 or candle 3). If either is missing, the swing point
   //  is ignored." —— **本轮起永久不实现**。
   //  ⚠️ 不要再按"补全保真度"的理由把它加回来：这是**已裁定的取舍，不是遗漏**。
   //     理由见 plan §43.7（POI 判据必须由实现方发明，且会改动全部下游结构）。
   g_result.nClosure = 0;
   if(!InpShowClosures) return;

   for(int n = 0; n < g_result.nNodes; n++)
   {
      int b = g_result.nodes[n].bar;                 // C2 = swing 点本身
      // [v1.50-s59] 原为 b < 1：b=1 时 c3=0（正在形成），b=2 时 c4=0（刚开盘一个 tick），
      //   而 EvalC4Half 会拿那个 tick 的 high/low 判 EQ，默认 InpReuseResultOnTick=true 又让
      //   它在整根 bar 内不再重算，故标签与 CSV 的 c4 列在一根 bar 内是"基于单一 tick"的判决。
      //   改为要求 C1..C4 全为已收盘 bar。代价：最新 1 个节点的 closure 延后一根 bar 出现。
      if(b < 3 || b > rates_total - 2) continue;
      int c1 = b + 1;                                // C1：C2 之前那根
      int c3 = b - 1;                                // C3：C2 之后那根
      bool isLow = !g_result.nodes[n].isHigh;

      if(isLow)
      {
         // ── 看涨：C2 是 swing low ──
         double sweptLvl = low[c1];
         bool   swept    = (low[b] < sweptLvl);
         bool   c2Rev    = (swept && close[b] > sweptLvl);   // 扫破后**收回** → 反转确认
         if(c2Rev)
         {
            AddClosureResult(b, DIR_UP, sweptLvl, c1, CLOSURE_C2_REV);
            continue;
         }
         double bodyHi = MathMax(open[b], close[b]);         // C2 实体上沿
         if(low[c3] >= low[b] && close[c3] > bodyHi)
         {
            AddClosureResult(b, DIR_UP, bodyHi, c3, CLOSURE_C3);
            // 他的 C3 均衡位用法：C4 应刺入 C3 上半（未跌破 EQ）
            g_result.closure[g_result.nClosure - 1].c4 =
               EvalC4Half(high, low, c3, DIR_UP);
            continue;
         }
         if(swept && close[b] < sweptLvl)   // 扫破且**收在其外** → 延续收盘（非有效反转确认）
            AddClosureResult(b, DIR_UP, sweptLvl, c1, CLOSURE_C2_CONT);
         // ⚠️ 收盘**恰好等于** sweptLvl 时两者都不成立 → 不产生任何 closure。
         //    它既没收回位内、也没收在位外，按他的两条定义都不成立，故不硬塞一个。
      }
      else
      {
         // ── 看跌：C2 是 swing high ──
         double sweptLvl = high[c1];
         bool   swept    = (high[b] > sweptLvl);
         bool   c2Rev    = (swept && close[b] < sweptLvl);
         if(c2Rev)
         {
            AddClosureResult(b, DIR_DOWN, sweptLvl, c1, CLOSURE_C2_REV);
            continue;
         }
         double bodyLo = MathMin(open[b], close[b]);         // C2 实体下沿
         if(high[c3] <= high[b] && close[c3] < bodyLo)
         {
            AddClosureResult(b, DIR_DOWN, bodyLo, c3, CLOSURE_C3);
            g_result.closure[g_result.nClosure - 1].c4 =
               EvalC4Half(high, low, c3, DIR_DOWN);
            continue;
         }
         if(swept && close[b] > sweptLvl)
            AddClosureResult(b, DIR_DOWN, sweptLvl, c1, CLOSURE_C2_CONT);
      }
   }
}

void AddMSSResult(const int breakBar, const int dir, const RefPoint &ref,
               const int trend, const bool strong)
{
   ArrayResize(g_result.mss, g_result.nMSS + 1);
   g_result.mss[g_result.nMSS].bar     = breakBar;
   g_result.mss[g_result.nMSS].dir     = dir;
   g_result.mss[g_result.nMSS].ref     = ref.price;
   g_result.mss[g_result.nMSS].refBar  = ref.bar;
   // 阶段 3：位移判据结果。weak = 未过门槛 → 渲染层按 G1 只画弱化线、不给文字标签。
   // 度量值取自 MSSDisplaced() 写入的两个全局（避免 4 处调用点重复计算）。
   g_result.mss[g_result.nMSS].weak    = !strong;
   g_result.mss[g_result.nMSS].fvgFollow = false;   // 非 CISD/OB：无含义
   g_result.mss[g_result.nMSS].bodyATR = g_lastBodyATR;
   g_result.mss[g_result.nMSS].penATR  = g_lastPenATR;
   if(InpDebugShowRef)
   {
      int fb = FindBrokenNodeBar(ref.price, dir);
      Print("MSS event: type=MSS dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " breakBar=", breakBar, " refBar=", ref.bar,
            " refPrice=", DoubleToString(ref.price, _Digits),
            " trend=", (trend == ST_UP ? "UP" : "DOWN"),
            " bind=", (fb == ref.bar ? "OK" : ("MISMATCH(found=" + IntegerToString(fb) + ")")));
   }
   g_result.nMSS++;
}

void AddBOSResult(const int breakBar, const int dir, const RefPoint &ref,
               const int trend)
{
   ArrayResize(g_result.bos, g_result.nBOS + 1);
   g_result.bos[g_result.nBOS].bar    = breakBar;
   g_result.bos[g_result.nBOS].dir    = dir;
   g_result.bos[g_result.nBOS].ref    = ref.price;
   g_result.bos[g_result.nBOS].refBar = ref.bar;
   if(InpDebugShowRef)
   {
      int fb = FindBrokenNodeBar(ref.price, dir);
      Print("BOS event: type=BOS dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " breakBar=", breakBar, " refBar=", ref.bar,
            " refPrice=", DoubleToString(ref.price, _Digits),
            " trend=", (trend == ST_UP ? "UP" : "DOWN"),
            " bind=", (fb == ref.bar ? "OK" : ("MISMATCH(found=" + IntegerToString(fb) + ")")));
   }
   g_result.nBOS++;
}

void AddBoxResult(const int mother, const int start, const int end,
                  const double hi, const double lo)
{
   ArrayResize(g_result.box, g_result.nBox + 1);
   g_result.box[g_result.nBox].mother = mother;
   g_result.box[g_result.nBox].start  = start;
   g_result.box[g_result.nBox].end    = end;
   g_result.box[g_result.nBox].hi     = hi;
   g_result.box[g_result.nBox].lo     = lo;
   g_result.nBox++;
}

//══════════════════════════════════════════════════════════════════
//  阶段 9：PD Array（FVG / OB）
//  定义来源 = docs/research/2026-09-23-TTrades-structure.md「PD Array」节。
//  两者都属于他所说的 "Point of Interest"，是**执行层**的参照区，不参与结构判定。
//══════════════════════════════════════════════════════════════════

//── OB：由 CISD 的造势序列派生 ──
//  他："my eyes go to the series of up close candles responsible for the move.
//       When price closes back below those candles, that area becomes a validated
//       order block." + "Bodies matter more than wicks."
//  → 区间 = 该序列**实体**的并集；关键价位 = 最旧一根的开盘价（= 同一个 CISD 位）。
//  ⚠️ 区间右端：渲染时延伸到**最新 bar**（`t2 = time[0]`），不是锚定在突破 bar。
//  依据配图 `OB-reversal-pattern.png` / `OB-confirmation.png` —— 他把 OB 画成一条
//  向右延伸至现价区域的水平线。早期注释曾写"锚定到验证 bar"，与代码不符，已更正。
//  代价：早已失效的 OB 也会一路画到最右（本指标未跟踪 OB 失效，`state` 只标是否够位移）。
//
//  D14 修复（v1.49-s9e）：`strong` 由 CheckCisd 的 DisplacedBeyond() 透传进来。
//  依据他 "**Closure and displacement** are what validate the level." ——
//  原先此处把 weak/bodyATR/penATR 写死为 false/0/0，导致"强位移验证的 OB"与
//  "仅收盘穿过（位移不足）的 OB"在渲染与导出上**完全无法区分**，等于丢掉了
//  他用来定义 OB 有效性的两个条件之一。
//  ⚠️ 注意本修复只做**如实记录与区分**，**不加门控** —— 弱 OB 仍然被记录/绘制，
//  只是标记为弱。是否要求"位移为必要条件"（等同于 D13 的性质）属另一次决策。
void AddObResult(const int breakBar, const int dir, const double level,
                 const int runOldest, const double bodyLo, const double bodyHi,
                 const bool strong)
{
   ArrayResize(g_result.ob, g_result.nOB + 1);
   int n = g_result.nOB;
   g_result.ob[n].bar      = breakBar;
   g_result.ob[n].dir      = dir;
   g_result.ob[n].ref      = level;
   g_result.ob[n].refBar   = runOldest;
   // weak / 度量与 MSS、CISD 同源：都是紧邻的那次 DisplacedBeyond() 写入的全局。
   g_result.ob[n].weak     = !strong;
   g_result.ob[n].fvgFollow = true;    // 第②条由 ComputeCisdFvgFollow 逐帧覆写
   g_result.ob[n].bias     = 0;
   g_result.ob[n].bodyATR  = g_lastBodyATR;
   g_result.ob[n].penATR   = g_lastPenATR;
   g_result.ob[n].zoneLo   = bodyLo;
   g_result.ob[n].zoneHi   = bodyHi;
   g_result.ob[n].fillPct  = 0.0;
   g_result.ob[n].ceBroken = false;
   if(InpDebugShowRef)
      Print("OB event: dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " breakBar=", breakBar, " runOldest=", runOldest,
            " level=", DoubleToString(level, _Digits),
            " bodyZone=", DoubleToString(bodyLo, _Digits), "..",
            DoubleToString(bodyHi, _Digits),
            " bodyATR=", DoubleToString(g_lastBodyATR, 2),
            " penATR=",  DoubleToString(g_lastPenATR, 2),
            " ", (strong ? "OK" : "WEAK"));
   g_result.nOB++;
}

// 求造势序列 [extremeBar, runOldest] 的实体并集（series 方向：runOldest 更大 = 更旧）。
void AddObFromRun(const int breakBar, const int dir, const double level,
                  const int runOldest, const int extremeBar, const bool strong,
                  const double &open[], const double &close[])
{
   if(runOldest < 0 || extremeBar < 0 || runOldest < extremeBar) return;
   double lo = MathMin(open[runOldest], close[runOldest]);
   double hi = MathMax(open[runOldest], close[runOldest]);
   for(int j = runOldest - 1; j >= extremeBar; j--)
   {
      double b1 = MathMin(open[j], close[j]);
      double b2 = MathMax(open[j], close[j]);
      if(b1 < lo) lo = b1;
      if(b2 > hi) hi = b2;
   }
   AddObResult(breakBar, dir, level, runOldest, lo, hi, strong);
}

//── FVG：三根 K 线，影线对影线 ──
void AddFvgResult(const int confirmBar, const int dir, const int c1Bar,
                  const double zLo, const double zHi, const double ce,
                  const double fill, const bool ceBroken)
{
   ArrayResize(g_result.fvg, g_result.nFVG + 1);
   int n = g_result.nFVG;
   g_result.fvg[n].bar      = confirmBar;
   g_result.fvg[n].dir      = dir;
   g_result.fvg[n].ref      = ce;          // CE = 缺口中点（他的 "0.5" 入场位）
   g_result.fvg[n].refBar   = c1Bar;       // 缺口第一根（矩形左端锚定）
   // ⚠️ FVG 的 weak **不表示**"位移不足"（那是 MSS/CISD/OB 的用法）。
   //    FVG 没有位移判据，它的"已失效"状态只存在 `ceBroken` / `fillPct`。
   //    初版曾把 weak 赋成 ceBroken，等于把"换个档位反向使用（IFVG）"混同为"信号质量降级"，
   //    并把这个混淆固化进数据模型。此处保持 false，语义单一。
   g_result.fvg[n].weak     = false;
   g_result.fvg[n].fvgFollow = false;   // 非 CISD/OB：无含义
   g_result.fvg[n].bias     = 0;
   g_result.fvg[n].bodyATR  = 0.0;
   g_result.fvg[n].penATR   = 0.0;
   g_result.fvg[n].zoneLo   = zLo;
   g_result.fvg[n].zoneHi   = zHi;
   g_result.fvg[n].fillPct  = fill;
   g_result.fvg[n].ceBroken = ceBroken;
   if(InpDebugShowRef)
      Print("FVG event: dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " c1Bar=", c1Bar, " confirmBar=", confirmBar,
            " zone=", DoubleToString(zLo, _Digits), "..", DoubleToString(zHi, _Digits),
            " ce=", DoubleToString(ce, _Digits),
            " fill=", DoubleToString(fill, 2),
            " ", (ceBroken ? "CE-BROKEN" : "OPEN"));
   g_result.nFVG++;
}

// FVG 检测（**物理相邻三根**，`v1.50-s46` 起）：
//  candle1 = c3+2（更旧）· candle2 = c3+1 · candle3 = c3（当前 bar）
//  他："the high/low of the candle(1) does not overlap the low/high of candle(3)"
//  看跌（SIBI）：low[c1]  > high[c3]  → 价格下跌留下缺口，区间 [high[c3], low[c1]]，悬在现价**上方**
//  看涨（BISI）：high[c1] < low[c3]   → 价格上涨留下缺口，区间 [high[c1], low[c3]]，落在现价**下方**
//  ⚠️【v1.50-s46 口径变更（用户实机裁定）】原实现取 `validBars[k-2]`（**有效 bar 序列**，内包 K 被剔除）。
//    实测 88 条 FVG 里 **24 条不是物理相邻**（`d=c3−c1` 为 −3…−7），用户框出的那条正是 `d=−3`
//    —— 即"由 4 根 K 组成、隔着一根被忽略的内包 K"。用户判断："这个不是 FVG 吧" ⇒ 现改为
//    **物理相邻三根**（他的字面读法）。代价：会新增一批 tick 级缺口，故**同时**加最小高度门槛。
//  ⚠️ dir 必须与「缺口相对现价的位置」一致（看跌=SIBI=DIR_DOWN），
//     否则下面的回补/CE 判据会套用反方向的规则，导致缺口在形成当刻就被判成已回补。
//     v1.49-s9a 修复：初版此处两个分支的 dir 写反，实测 80 个缺口全部 fill=1.0。
void CheckFvg(const int c3,
              const double &high[], const double &low[], const double &close[],
              const double &atrArr[])
{
   int c1 = c3 + 2;                                  // 物理相邻：candle1 = candle3 + 2
   if(c1 < 0 || c1 >= ArraySize(high)) return;       // 窗口最旧两根没有 c1

   int    dir = 0;
   double zLo = 0.0, zHi = 0.0;
   if(low[c1] > high[c3])       { dir = DIR_DOWN; zLo = high[c3]; zHi = low[c1]; }
   else if(high[c1] < low[c3])  { dir = DIR_UP;   zLo = high[c1]; zHi = low[c3]; }
   else return;
   if(zHi <= zLo) return;                       // 退化（零宽）缺口不记录

   // 阶段 36：**最小高度门槛**。只拒绝零宽挡不住 tick 级噪声 ——
   //  实测存在 0.04（4 个 tick）的"缺口"，物理相邻口径下这类会更多。
   //  门槛取 ATR 相对值（跨品种/周期自适应），0 = 不限。
   // v1.50-s58：**越界防护与门槛解耦**。原写法把两者塞进同一个 if，而 `c3 < ArraySize(atrArr)`
   //   在当前调用下恒真（atrArr 与 c3 同受 analysisStart 上界）⇒ 一旦有人放宽循环起点，
   //   该 if 整体为假、**最小宽度门槛被静默关闭**（正是上面要挡的 tick 级噪声会被全量记录）。
   //   现在：取不到 ATR 就记一条诊断并**跳过门槛**，绝不改变 if 自身的真假语义。
   if(InpFvgMinWidthATR > 0.0 && c3 >= 0)
   {
      if(c3 >= ArraySize(atrArr))
      {
         if(InpDebugShowRef)
            PrintFormat("STRUCT_FVG 越界：c3=%d 超出 atrArr=%d → 最小宽度门槛本轮不生效",
                        c3, ArraySize(atrArr));
      }
      else
      {
         double atrC = atrArr[c3];
         if(atrC > 0.0 && (zHi - zLo) < InpFvgMinWidthATR * atrC) return;
      }
   }

   //── 生命周期：向更新方向扫描，记录最大回补比例与是否收盘穿越 CE ──
   //  他："As long as price does not close beyond the consequent encroachment,
   //       the fair value gap is generally considered respected."
   //  故 ceBroken（收盘穿 CE）= 该 FVG 已失效（可能转为 IFVG 反向使用）。
   double ce       = (zLo + zHi) * 0.5;
   double span     = zHi - zLo;
   double fill     = 0.0;
   bool   ceBroken = false;
   for(int q = c3 - 1; q >= 0; q--)
   {
      if(dir == DIR_UP)
      {
         if(low[q] <= zLo) fill = 1.0;
         else if(low[q] < zHi)
         {
            double d = (zHi - low[q]) / span;
            if(d > fill) fill = d;
         }
         if(close[q] < ce) ceBroken = true;
      }
      else
      {
         if(high[q] >= zHi) fill = 1.0;
         else if(high[q] > zLo)
         {
            double d = (high[q] - zLo) / span;
            if(d > fill) fill = d;
         }
         if(close[q] > ce) ceBroken = true;
      }
      if(fill >= 1.0 && ceBroken) break;        // 两个状态都已定
   }
   AddFvgResult(c3, dir, c1, zLo, zHi, ce, fill, ceBroken);
}

//+------------------------------------------------------------------+
//| 交替过滤添加结构节点：强制高低交替（避免"高-高/低-低"相连）       |
//| 同类型连续出现时只保留更极端者（更高的 high / 更低的 low）        |
//| 同步维护 st.lastLeg（最后一条腿幅度，供比例过滤）                 |
//| 返回 true = 节点被添加/替换；false = 同类型且不更极端（未变更）   |
//| LH/HL 基准仅在返回 true 时更新 → ref 严格对应结构线节点（问题1）  |
//+------------------------------------------------------------------+
bool AddNodeFiltered(const int bar, const double price, const bool isHigh,
                     SState &st, const bool isMain = true)
{
   if(!st.hasLast)
   {
      AddNodeResult(bar, price, isHigh);
      g_result.nodes[g_result.nNodes - 1].isMain = isMain;
      st.lastIsHigh = isHigh;
      st.hasLast    = true;
      st.lastLeg    = 0.0;
      return true;
   }
   int last = g_result.nNodes - 1;
   if(st.lastIsHigh == isHigh)
   {
      bool replaced = false;
      if(isHigh)
      {
         if(price > g_result.nodes[last].price)
         {
            int oldBar = g_result.nodes[last].bar;   // 被替换节点的 K 线 bar
            g_result.nodes[last].bar    = bar;
            g_result.nodes[last].price  = price;
            g_result.nodes[last].isMain = isMain;
            // 同类型替换：只同步同类型 ref（high 替换 → 只同步 refHigh）
            if(st.refHigh.valid && oldBar == st.refHigh.bar)
            {
               st.refHigh.bar   = bar;
               st.refHigh.price = price;
               // [v1.50-s59] touched 是"弱事件已记录一次"的闩锁，必须在参考位的每个生命周期
               //   写点上复位。这里被换成了更新的极值（bar/price 都变了），旧闩锁属于旧那个位，
               //   留着会让新位继承一次它从未发生过的弱触发。
               st.refHigh.touched = false;
            }
            replaced = true;
         }
      }
      else
      {
         if(price < g_result.nodes[last].price)
         {
            int oldBar = g_result.nodes[last].bar;   // 被替换节点的 K 线 bar
            g_result.nodes[last].bar    = bar;
            g_result.nodes[last].price  = price;
            g_result.nodes[last].isMain = isMain;
            // 同类型替换：只同步同类型 ref（low 替换 → 只同步 refLow）
            if(st.refLow.valid && oldBar == st.refLow.bar)
            {
               st.refLow.bar   = bar;
               st.refLow.price = price;
               st.refLow.touched = false;   // [v1.50-s59] 同上：闩锁属于旧位，不随替换继承
            }
            replaced = true;
         }
      }
      if(replaced && g_result.nNodes >= 2)
         st.lastLeg = MathAbs(g_result.nodes[g_result.nNodes - 1].price -
                              g_result.nodes[g_result.nNodes - 2].price);
      return replaced;
   }
   // 不同类型：正常追加
   AddNodeResult(bar, price, isHigh);
   g_result.nodes[g_result.nNodes - 1].isMain = isMain;
   st.lastIsHigh = isHigh;
   if(g_result.nNodes >= 2)
      st.lastLeg = MathAbs(g_result.nodes[g_result.nNodes - 1].price -
                           g_result.nodes[g_result.nNodes - 2].price);
   return true;
}

//+------------------------------------------------------------------+
//| 【v1.49-s15 已删除】AddSubNode() / subNodes[] / nSub              |
//|  独立评审机械核实：AddSubNode **全文无任何调用点**（仅定义处出现 1 次），  |
//|  故 subNodes 恒空、nSub 恒 0。内包盒/外包逻辑并不需要"内部结构节点"      |
//|  （外包 K 线由 CheckBreakAgainstRefs 的同 bar 双破分支处理）。           |
//|  原 `InpUseOutsideBarLogic` 亦为哑输入（全文仅声明处出现），一并删除：   |
//|  它的说明是"外包 K 线单独处理"，但那件事一直由双破分支在做，与它无关。     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 【阶段 11 起已删除】IsMainSwing()                                  |
//|  它按"腿长 ≥1.0×ATR 或 ≥0.382×前段"判定主结构。删除理由同          |
//|  UpdateRefsFromSwing：该门槛无一手依据，且其唯一用途（驱动 ref）    |
//|  已被 CISD 驱动的 protected swing 取代。                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ATR 序列：Wilder 平滑递推（O(n)，v1.47 替换 O(n²) 简单均值）       |
//| 种子 = 分析窗口最旧 n 根 TR 简单均值；向新 bar 方向递推            |
//| v1.48：数组只分配 [0, analysisStart]，不再按 rates_total 分配 ——   |
//|        原来 analysisStart 以上的槽位从未赋值（恒为 0），是纯浪费，  |
//|        且一旦将来有人读该区间会拿到 0 而让 ATR 过滤静默失效。       |
//+------------------------------------------------------------------+
void CalcATRSeries(const double &high[], const double &low[],
                   const double &close[], const int rates_total,
                   const int analysisStart,
                   double &atrArr[])
{
   ArrayResize(atrArr, analysisStart + 1);    // 只覆盖被分析的下标区间
   int n = InpATRPeriod;
   if(n < 2) n = 2;

   // 第一遍：TR 存入 atrArr（仅分析窗口内）
   for(int i = analysisStart; i >= 0; i--)
   {
      double tr = high[i] - low[i];
      double pc = (i + 1 < rates_total) ? close[i + 1] : close[i];
      double hc = MathAbs(high[i] - pc);
      double lc = MathAbs(low[i]  - pc);
      if(hc > tr) tr = hc;
      if(lc > tr) tr = lc;
      atrArr[i] = tr;
   }

   // 种子：最旧 n 根 TR 简单均值
   int seedEnd = MathMax(0, analysisStart - n + 1);
   double sum = 0.0; int cnt = 0;
   for(int i = analysisStart; i >= seedEnd; i--) { sum += atrArr[i]; cnt++; }
   double prevATR = (cnt > 0) ? sum / cnt : 0.0;

   // Wilder 平滑递推（旧→新）：atrArr[i] = (prevATR * (n-1) + TR[i]) / n
   for(int i = seedEnd - 1; i >= 0; i--)
   {
      prevATR = (prevATR * (n - 1) + atrArr[i]) / n;
      atrArr[i] = prevATR;
   }
   // 最旧 bar 的 ATR = 种子均值
   // [v1.50-s59] 种子均值原来只写进最旧那一根，[seedEnd, analysisStart-1] 这 n-1 根
   //   仍停在单根 TR -- 该区段所有 ATR 门槛（位移 / FVG 最小宽度 / 分离度 / 回撤）
   //   用的是 TR 而非 ATR，方差大得多，导致系统性偏松。改为把种子均值铺满整个种子区间。
   const double seedATR = (cnt > 0) ? sum / cnt : 0.0;
   for(int ii = seedEnd; ii <= analysisStart; ii++) atrArr[ii] = seedATR;
}

//+------------------------------------------------------------------+
//| 结构点有效性判定（#2 最小 swing 幅度过滤 + 有效回撤过滤）          |
//| 依次校验，全部通过才算有效结构点：                                 |
//|   1) InpMinSwingAmplitude（点数）硬下限（0=关闭）                  |
//|   2) 有效回撤：最小点数 必须满足，且 (ATR 倍数 或 前段比例) 任一满足 ——
//|      放宽 AND 为 点数 AND (ATR OR Ratio)，避免过严滤除有效结构点    |
//| 用于 swing 结构点与内包盒/外包事件，保证 MSS 只突破"有效 HL/LH"    |
//+------------------------------------------------------------------+
bool IsValidRetrace(const double leg, const double atrValue,
                    const double prevLeg)
{
   bool needCheck = InpEnableRetraceFilter || InpMinSwingAmplitude > 0;
   if(!needCheck) return true;

   if(InpMinSwingAmplitude > 0 && leg < InpMinSwingAmplitude * _Point)
      return false;

   if(InpEnableRetraceFilter)
   {
      // 最小点数：必须满足
      if(InpMinRetracePoints > 0 && leg < InpMinRetracePoints * _Point) return false;
      // ATR / Ratio：任一满足即可（都有门槛时也取"或"）
      bool atrOk   = (InpMinRetraceATR   <= 0.0) || (atrValue <= 0.0) || (leg >= InpMinRetraceATR   * atrValue);
      bool ratioOk = (InpMinRetraceRatio <= 0.0) || (prevLeg  <= 0.0) || (leg >= InpMinRetraceRatio * prevLeg);
      bool hasT    = (InpMinRetraceATR   > 0.0 && atrValue > 0.0) ||
                     (InpMinRetraceRatio > 0.0 && prevLeg  > 0.0);
      if(hasT && !(atrOk || ratioOk))
         return false;                              // 点数已过，但 ATR/比例均未过 → 无效
   }
   return true;
}

//+------------------------------------------------------------------+
//| 破位确认（MSS / BOS 共用判据）                                     |
//|                                                                  |
//|  三种口径，由 InpBreakConfirm 选择：                                |
//|   · BREAK_BODY （默认）实体**完全越过**结构位 —— 向上 min(open,close) > level |
//|   · BREAK_CLOSE        收盘越过 —— 向上 close > level（他的字面口径）          |
//|   · BREAK_WICK         影线触及 —— 向上 high > level                          |
//|                                                                  |
//|  ⚠️ 三者的严格度是**全序**：BODY ⊂ CLOSE ⊂ WICK（能过前者的必然能过后两者，反之不然）。|
//|     故从 WICK 改到 BODY 只会**减少并推迟**事件，不会产生全新的事件。       |
//|  ⚠️ StrictICT 模式的语义是"至少收盘确认"，故它会把 WICK 提升为 CLOSE，     |
//|     但**不会**把 BODY 降级为 CLOSE（模式是下限，不是覆盖）。               |
//+------------------------------------------------------------------+
ENUM_BREAK_CONFIRM EffectiveBreak()
{
   if(InpMode == MODE_STRICT_ICT && InpBreakConfirm == BREAK_WICK)
      return BREAK_CLOSE;
   return InpBreakConfirm;
}

//+------------------------------------------------------------------+
//| 阶段 69：**节点级**破位确认（与引擎 MSS/BOS 分开，理由见输入处注释）|
//|  口径与 EffectiveBreak 同构：StrictICT 是**下限**（WICK→CLOSE），  |
//|  不会把 BODY 降级。默认 BREAK_CLOSE ≠ 引擎默认 BREAK_WICK，        |
//|  ⇒ 这是**有意的不一致**，不是漏改：引擎要接 sweeping，节点层只判  |
//|    "结构是否真的被破"。                                           |
//+------------------------------------------------------------------+
ENUM_BREAK_CONFIRM EffectiveNodeBreak()
{
   if(InpMode == MODE_STRICT_ICT && InpNodeBreakConfirm == BREAK_WICK)
      return BREAK_CLOSE;
   return InpNodeBreakConfirm;
}

//+------------------------------------------------------------------+
//| 阶段 44：按"≥4 倍"原则把图表周期映射到蜡烛周期（纯函数，便于逐行核对）|
//|                                                                  |
//|  ⚠️ 阶梯**只含券商实际提供的经典档位**，顺序由小到大。              |
//|  ⚠️ 找不到（图表已是最高档）→ 返回 MN1；此时蜡烛等于图表周期本身，   |
//|     属退化但无害，且能通过"蜡烛周期 ≥ 图表周期"的校验。             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES AutoCandleTF(const ENUM_TIMEFRAMES chartTF)
{
   ENUM_TIMEFRAMES ladder[9] =
   {
      PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
      PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1
   };
   int cs = PeriodSeconds(chartTF);
   if(cs <= 0) return PERIOD_H4;              // 拿不到图表周期 → 退回默认
   for(int i = 0; i < ArraySize(ladder); i++)
      if(PeriodSeconds(ladder[i]) >= cs * 4) return ladder[i];
   return PERIOD_MN1;
}

//+------------------------------------------------------------------+
//| 阶段 44：**生效的**蜡烛周期（全指标只从这里取，不再直接用输入项）    |
//|                                                                  |
//|  ⚠️ 纯函数、**无状态** ⇒ 既不需要复位、也不需要进 needDraw 指纹     |
//|     （这是刻意选择：换成全局缓存就得在两处维护它，多一类"会变陈旧"的坑）|
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES EffCandleTF()
{
   if(InpHtfTFMode == HTF_TF_AUTO) return AutoCandleTF((ENUM_TIMEFRAMES)_Period);
   return InpCandleTF;
}

// 阶段 69：把口径**参数化**，使引擎（EffectiveBreak）与节点级（EffectiveNodeBreak）
//   可以各用各的口径，而判据本体只有一份实现（避免两处 switch 漂移）。
bool BrokeLevelCal(const int i, const double level, const bool isUp,
                   const double &high[], const double &low[],
                   const double &open[], const double &close[],
                   const ENUM_BREAK_CONFIRM cal)
{
   switch(cal)
   {
      case BREAK_BODY:
         return isUp ? (MathMin(open[i], close[i]) > level)
                     : (MathMax(open[i], close[i]) < level);
      case BREAK_CLOSE:
         return isUp ? (close[i] > level) : (close[i] < level);
      default: // BREAK_WICK
         return isUp ? (high[i] > level) : (low[i] < level);
   }
}

bool BrokeLevel(const int i, const double level, const bool isUp,
                const double &high[], const double &low[],
                const double &open[], const double &close[])
{
   return BrokeLevelCal(i, level, isUp, high, low, open, close, EffectiveBreak());
}

//+------------------------------------------------------------------+
//| 计算本次 swing 相对上一个已确认相反类型结构点的腿长               |
//| 无参考节点（首节点）返回 DBL_MAX → 恒通过过滤                     |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 阶段 1-B：同类型相邻 swing 的价格间距（failure swing 剔除用）      |
//|  无同类型前驱（首个同类型点）→ 返回 DBL_MAX → 恒通过               |
//|  节点强制高低交替，故「上一个同类型 swing」通常是 nodes[n-2]。     |
//+------------------------------------------------------------------+
double SeparationFromLastSameType(const double price, const bool isHigh,
                                  const SState &st)
{
   int last = g_result.nNodes - 1;
   if(last < 0) return DBL_MAX;
   if(st.lastIsHigh == isHigh) return MathAbs(price - g_result.nodes[last].price);
   if(last >= 1)               return MathAbs(price - g_result.nodes[last - 1].price);
   return DBL_MAX;
}
double LegFromLastNode(const double price, const bool isHigh,
                       const SState &st)
{
   if(g_result.nNodes == 0) return DBL_MAX;
   double refPrice;
   if(isHigh != st.lastIsHigh)
      refPrice = g_result.nodes[g_result.nNodes - 1].price;
   else if(g_result.nNodes >= 2)
      refPrice = g_result.nodes[g_result.nNodes - 2].price;
   else
      refPrice = g_result.nodes[0].price;
   return isHigh ? (price - refPrice) : (refPrice - price);
}

//+------------------------------------------------------------------+
//| BOS/MSS 唯一触发源 = CheckBreakAgainstRefs（v1.37 起）             |
//| 内包盒/外包事件不再独立触发标记；盒区间仅用于矩形绘制（g_result.box）|
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 每根 bar 的通用结构突破检测（不依赖该 bar 是否确认成 swing）       |
//| ST_UP ：突破 refHigh → bullish BOS；跌破 refLow → bearish MSS     |
//| ST_DOWN：跌破 refLow → bearish BOS；突破 refHigh → bullish MSS    |
//| 触发后只标记 broken + 切向，不更新 ref（ref 由确认 swing 更新）    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 阶段 3：位移判据（对齐 TTrades 的 MSS 确认条件）                   |
//|  他的原话："The key confirmation is displacement (strong price     |
//|  movement with momentum) that breaks prior structure."；           |
//|  "The best setups form within one to three candles and show        |
//|  immediate displacement."                                          |
//|  他**未给任何数值** → 三条阈值（实体/穿越深度/时效）均为自定近似，  |
//|  全部做成输入项，写入 CSV 头以便归档自描述。                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 位移判据核心（阶段 3 建立；阶段 4 起 CISD/MSS 共用同一套判据）。    |
//|  给定「被穿越价位 + 锚点 bar」，判定两条门槛：                      |
//|    ① 实体 |close-open| ≥ InpMinDisplaceBodyATR × ATR               |
//|    ③ 时效：首次影线穿越落在 [i, i+N-1]，N = InpDisplaceMaxBars     |
//|  他只有定性描述、无数值 → 阈值均为自定近似（0 = 关闭该条）。         |
//|  锚点 bar 语义：MSS 传 ref.bar（被破结构位所在 bar）；             |
//|                CISD 传极值 bar（造势序列的终点）。                |
//|                                                                  |
//|  ⚠️ 原第②条「收盘穿越深度 `|close-level| ≥ InpMinDisplacePenATR×ATR`」|
//|  **已整体删除**（s12c 去 MSS、s12d 换 CISD），故函数不再有该参数。   |
//|  但 `pen` **仍然计算**并写入 g_lastPenATR → CSV 的 `pen=` 列 ——    |
//|  删掉的是**判据**，不是**度量**；留着度量才能事后评估这两个改动。     |
//|                                                                  |
//|  CISD 的第②条现由「后续 N 根内出现同向 FVG」替代，见 ComputeCisdFvgFollow。|
//+------------------------------------------------------------------+
bool DisplacedBeyond(const int i, const double level, const int anchorBar,
                     const bool isUp,
                     const double &high[], const double &low[],
                     const double &open[], const double &close[],
                     const double &atrArr[])
{
   g_lastBodyATR = 0.0;
   g_lastPenATR  = 0.0;

   double atr = (i >= 0 && i < ArraySize(atrArr)) ? atrArr[i] : 0.0;
   if(atr <= 0.0) return true;   // ATR 不可用 → 不阻断（避免过滤静默失效）

   double body = MathAbs(close[i] - open[i]);
   double pen  = isUp ? (close[i] - level) : (level - close[i]);
   g_lastBodyATR = body / atr;
   g_lastPenATR  = pen  / atr;                  // 仍计算：CSV 的 pen= 列需要

   if(InpMinDisplaceBodyATR > 0.0 && g_lastBodyATR < InpMinDisplaceBodyATR) return false;

   // 时效条件的无状态实现：收盘确认在 bar i 时 bar i 自身即一次影线穿越，
   // 故「首次穿越落在 [i, i+N-1]」等价于「(i+N .. anchorBar-1) 区间无穿越」。
   if(InpDisplaceMaxBars > 0)
   {
      int from = i + InpDisplaceMaxBars;
      int to   = anchorBar - 1;
      for(int j = from; j <= to; j++)
      {
         if(j < 0 || j >= ArraySize(high)) break;
         if(isUp ? (high[j] > level) : (low[j] < level)) return false;
      }
   }
   return true;
}

// MSS 路径的薄封装：沿用 RefPoint 形态，语义与阶段 3 完全一致。
bool MSSDisplaced(const int i, const RefPoint &ref, const bool isUp,
                  const double &high[], const double &low[],
                  const double &open[], const double &close[],
                  const double &atrArr[])
{
   // v1.49-s12d：② 已整体删除（MSS 在 s12c 去掉，CISD 在本版换成 FVG 条件）。
   return DisplacedBeyond(i, ref.price, ref.bar, isUp, high, low, open, close, atrArr);
}
//+------------------------------------------------------------------+
//| 阶段 4：CISD 位 = 「造势那一串同向收盘 K 线」中最旧一根的开盘价。  |
//|  实现：自极值 bar 起向【更旧】方向收集极大的同向收盘序列。         |
//|  ⚠️ series 方向注意：下标增大 = 更旧，故向更旧推进是 j++。         |
//|  极端 bar 自身必须与造势方向同向，否则该极值不是"一串同向收盘"造出来的 |
//|  （例如长影线单根反转）→ 不设位，保守跳过。                        |
//+------------------------------------------------------------------+
// 阶段 9 重构：把「找到最旧一根」与「取其开盘价」拆开 —— OB 的实体区间
// 需要前者，CISD 位需要后者。此前只有后者，导致 OB 只能另起一套扫描逻辑。
// 现在 CisdOriginOpen 退化为对本函数的取值，保证两者口径永远一致。
int CisdOriginBar(const int extremeBar, const bool isHigh,
                  const double &open[], const double &close[],
                  const int oldestBar, bool &ok)
{
   ok = false;
   if(extremeBar < 0) return -1;

   bool dirOk = isHigh ? (close[extremeBar] > open[extremeBar])
                       : (close[extremeBar] < open[extremeBar]);
   if(!dirOk) return -1;

   int j      = extremeBar;
   int oldest = extremeBar;
   while(j <= oldestBar && j < ArraySize(close))   // v1.50-s58：补数组上界（原只靠 oldestBar 兜底）
   {
      bool same = isHigh ? (close[j] > open[j]) : (close[j] < open[j]);
      if(!same) break;
      oldest = j;
      j++;                       // 推向更旧
   }
   ok = true;
   return oldest;
}

double CisdOriginOpen(const int extremeBar, const bool isHigh,
                      const double &open[], const double &close[],
                      const int oldestBar, bool &ok)
{
   int ob = CisdOriginBar(extremeBar, isHigh, open, close, oldestBar, ok);
   if(!ok) return 0.0;
   return open[ob];
}

// 在新的极值确认成节点时重设 CISD 位（同时复位 Fired，使每个位只触发一次）。
void CisdSetLevel(SState &st, const int extremeBar, const bool isHigh,
                  const double &open[], const double &close[], const int oldestBar)
{
   bool ok = false;
   int runOldest = CisdOriginBar(extremeBar, isHigh, open, close, oldestBar, ok);
   if(!ok) return;
   double lvl = open[runOldest];
   if(isHigh)
   {
      st.cisdHighLevel = lvl; st.cisdHighValid = true;
      st.cisdHighFired = false; st.cisdHighBar = extremeBar;
      st.cisdHighRunBar = runOldest;          // 阶段 9：供 OB 实体区间使用
   }
   else
   {
      st.cisdLowLevel  = lvl; st.cisdLowValid  = true;
      st.cisdLowFired  = false; st.cisdLowBar  = extremeBar;
      st.cisdLowRunBar  = runOldest;
   }
}

//+------------------------------------------------------------------+
//| 阶段 11：protected swing 的**唯一定义源**                          |
//|                                                                  |
//|  他的定义 —— 三篇一手文章完全一致：                                 |
//|   · "A protected swing forms when price reaches an important level |
//|      and then **closes through the series of candles** into that   |
//|      level. That important level can be a high, low, or fair value |
//|      gap."（let-the-wick-form…）                                    |
//|   · "A protected swing is created when price **closes through the  |
//|      series of opposing candles** that led into a high or low."    |
//|      （ideal-formation）                                           |
//|   · 序列逐字："Bearish movement → important level → **bullish       |
//|      change in the state of delivery** → protected swing →          |
//|      expansion higher"                                             |
//|   · "This is the **same change in the state of delivery** used to   |
//|      confirm swing formations."                                    |
//|                                                                  |
//|  → 结论：**CISD 触发的那一刻，就是 protected swing 成立的那一刻**，   |
//|    锚点 = 造势序列的极值（我们的 cisdHighBar / cisdLowBar）。        |
//|                                                                  |
//|  ⚠️ 两条**不存在**于他定义里的东西，本函数据此取代旧实现：             |
//|   1. **无层级门槛**。short/intermediate/long-term 是**质量分级**      |
//|      （"Intermediate-term highs/lows confirm **stronger** pivots"）， |
//|      不是成立条件。                                                |
//|   2. **无幅度门槛**。故本函数取代原先由 `isMainSwing`（腿长 ≥1.0×ATR |
//|      或 ≥0.382×前段）驱动的 `UpdateRefsFromSwing` —— 那个门槛既不是   |
//|      他的定义，也从未出现在他的任何一句话里。                        |
//+------------------------------------------------------------------+
void SetProtectedFromCisd(SState &st, const bool isHigh,
                          const double &high[], const double &low[],
                          const int extremeBar)
{
   if(extremeBar < 0) return;
   if(isHigh)
   {
      st.refHigh.bar    = extremeBar;
      st.refHigh.price  = high[extremeBar];
      st.refHigh.valid  = true;
      st.refHigh.broken = false;
      st.refHigh.touched= false;
   }
   else
   {
      st.refLow.bar    = extremeBar;
      st.refLow.price  = low[extremeBar];
      st.refLow.valid  = true;
      st.refLow.broken = false;
      st.refLow.touched= false;
   }
}

// 每根 bar 检查：收盘是否穿越 CISD 位（不看 swing，故与趋势状态无关）。
//  他："When price displaces and closes beyond that open, it validates the level as an
//  order block." → 位移判据与 MSS 共用同一套（DisplacedBeyond）。
void CheckCisd(const int i, SState &st,
               const double &high[], const double &low[],
               const double &open[], const double &close[],
               const double &atrArr[])
{
   if(st.cisdHighValid && !st.cisdHighFired && close[i] < st.cisdHighLevel)
   {
      st.cisdHighFired = true;
      bool strong = DisplacedBeyond(i, st.cisdHighLevel, st.cisdHighBar, false,
                                    high, low, open, close, atrArr);
      AddCisdResult(i, DIR_DOWN, st.cisdHighLevel, st.cisdHighBar, strong);
      // 阶段 9：同一次触发即 OB 验证 —— 他："When price closes back below those
      //  candles, that area becomes a validated order block."（见 AddObFromRun）
      AddObFromRun(i, DIR_DOWN, st.cisdHighLevel, st.cisdHighRunBar, st.cisdHighBar,
                   strong, open, close);
      // 阶段 11：这次触发同时建立 protected high（他的定义）
      SetProtectedFromCisd(st, true, high, low, st.cisdHighBar);
   }
   if(st.cisdLowValid && !st.cisdLowFired && close[i] > st.cisdLowLevel)
   {
      st.cisdLowFired = true;
      bool strong = DisplacedBeyond(i, st.cisdLowLevel, st.cisdLowBar, true,
                                    high, low, open, close, atrArr);
      AddCisdResult(i, DIR_UP, st.cisdLowLevel, st.cisdLowBar, strong);
      AddObFromRun(i, DIR_UP, st.cisdLowLevel, st.cisdLowRunBar, st.cisdLowBar,
                   strong, open, close);
      // 阶段 11：这次触发同时建立 protected low（他的定义）
      SetProtectedFromCisd(st, false, high, low, st.cisdLowBar);
   }
}
//+------------------------------------------------------------------+
//| MSS 的唯一入口（v1.49-s9g 建立，s12b 修正弱触发语义）              |
//|                                                                  |
//|  他的定义：*"MSS marks a trend change **confirmed by displacement**."* |
//|  s9g 之前：`strong` 只传给 AddMSSResult 记录，`st.state` 无条件翻转 —— |
//|  即位移不足的破位照样改变趋势，进而影响 protected ref 的重设、       |
//|  后续 BOS/MSS 的归属、以及结构段的划分（全部下游）。                |
//|                                                                  |
//|  当前语义（三档，由 strong / ref.touched 决定）：                   |
//|   ① strong        → 记录(OK) + broken=true + 翻转趋势 + 重置对侧 ref + 返回 1 |
//|   ② !strong 且未 touched → 记录(WEAK) + touched=true，**不消耗该位**、返回 0 |
//|   ③ !strong 且已 touched → 静默返回 0（同一根位至多一条弱事件）      |
//|                                                                  |
//|  ⚠️ ②与③的区别是 s12b 的关键修正：`BREAK_WICK` 下"影线扫一下"就命中破位， |
//|     若弱触发也把该位标记为已破，该位会被一次扫影线**永久消耗**，       |
//|     后面真正的收盘/实体突破**再也出不来** —— 那是丢信号。             |
//|     故「记录一次弱触发」(`touched`) 与「消耗该位」(`broken`) 必须分开。 |
//|                                                                  |
//|  ⚠️ 返回值当前**不被消费**（原用于 `mssBar` 门控，该门控已随 s11 失效）。 |
//+------------------------------------------------------------------+
int ApplyMssTransition(SState &st, const int dir, RefPoint &ref,
                       const bool isUp, const int i,
                       const double &high[], const double &low[],
                       const double &open[], const double &close[],
                       const double &atrArr[])
{
   // 注意顺序：MSSDisplaced 会把度量写入 g_lastBodyATR/g_lastPenATR，
   // AddMSSResult 随后读取它们 —— 与修复前的调用顺序一致。
   bool strong = MSSDisplaced(i, ref, isUp, high, low, open, close, atrArr);

   // 阶段 12-b：弱触发只在**首次**记录一次，且**不消耗**该位。
   // 理由（BREAK_WICK 下尤其重要）：影线扫一下即命中破位条件，但位移不足时
   // 那不是他所说的 MSS（"The sweep itself is not the confirmation."）。
   // 若弱触发也置 broken，该位会被一次"扫影线"永久消耗，后面真正的突破再也出不来。
   // ⚠️【v1.50-s59 缺陷修复】强触发**不得被闩锁挡**。
   //   原实现（s58 及以前）只用一句 `if(!strong && ref.touched) return 0;` 概括两条语义，
   //   于是"弱触发不许重复记录"把"强触发必须记录"一起吞了：
   //     弱触发那根 bar 必然落在 DisplacedBeyond 的时效窗口 [i+N, anchorBar-1] 内
   //     （若它落在窗口外，同一个条件会让 strong=true），故闩锁置位后的每一根 bar
   //     只要**仍有影线在窗口里穿越**就恒 strong=false —— 该位在最长 N 根内再出不了 MSS，
   //     而节点层 ComputeChoch 不读 ref（自带口径），同一位上照旧显示节点级 BOS，
   //     ⇒ 引擎层与节点层对同一根 bar 给出相反结论。
   //   与 :2859-2862 的既定意图"弱触发只在首次记录一次，且**不消耗**该位"对照：
   //   原文讲的是"只记一次"，并未授权"挡掉强触发"，故这里按意图拆开两条语义。
   if(strong)
   {
      AddMSSResult(i, dir, ref, st.state, true);   // 强触发：无条件记录
   }
   else
   {
      if(ref.touched) return 0;                    // 弱触发只记首次，位仍有效
      AddMSSResult(i, dir, ref, st.state, false);
      ref.touched = true;
      return 0;                                    // 未过位移门槛 → 趋势未改变
   }
   ref.broken = true;                            // 强触发：该位用完
   if(dir == DIR_DOWN)
   {
      st.state         = ST_DOWN;
      st.refHigh.valid = false;                   // bearish MSS 后重置对侧 HH
      st.refHigh.touched = false;                // [v1.50-s59] 失效即清闩锁：同一个 (bar,price) 不得带闩锁复活
   }
   else
   {
      st.state        = ST_UP;
      st.refLow.valid = false;                    // bullish MSS 后重置对侧 LL
      st.refLow.touched  = false;                // [v1.50-s59] 同上（B4）
   }
   return 1;
}

int CheckBreakAgainstRefs(const int i, SState &st,
                           const double &high[], const double &low[],
                           const double &close[], const double &open[],
                            const double &atrArr[])
{
   int evType = 0;   // 0=无事件，1=**发生了趋势翻转的** MSS（已过位移门槛），2=BOS
   if(st.state == ST_UP)
   {
      bool upBroken = st.refHigh.valid && !st.refHigh.broken &&
                      BrokeLevel(i, st.refHigh.price, true, high, low, open, close);
      bool dnBroken = st.refLow.valid && !st.refLow.broken &&
                      BrokeLevel(i, st.refLow.price, false, high, low, open, close);
      if(upBroken && dnBroken)
      {
         // 外包形态双破：UP 中 阳线(close>=open)→保留 BOS(上破)；阴线→保留 MSS(下破)
         if(close[i] >= open[i])
         {
            AddBOSResult(i, DIR_UP, st.refHigh, st.state);
            // [v1.50-s59 缺陷修复] 落选侧 refLow 在**同一根 bar 上也被破了**，必须一并标记已用；
            //   否则它仍是 valid && !broken，紧随任一根 bar 再刺一下就会补记一条
            //   bar 指向后一根的虚假 bearish MSS（真正发生下破的是本根）。
            st.refLow.broken = true;
            st.refHigh.broken = true;
            evType = 2;
         }
         else
         {
            evType = ApplyMssTransition(st, DIR_DOWN, st.refLow, false, i,
                                        high, low, open, close, atrArr);
         }
      }
      else if(upBroken)
      {
         AddBOSResult(i, DIR_UP, st.refHigh, st.state);
         st.refHigh.broken = true;
         evType = 2;
      }
      else if(dnBroken)
      {
         evType = ApplyMssTransition(st, DIR_DOWN, st.refLow, false, i,
                                     high, low, open, close, atrArr);
      }
   }
   else if(st.state == ST_DOWN)
   {
      bool upBroken = st.refHigh.valid && !st.refHigh.broken &&
                      BrokeLevel(i, st.refHigh.price, true, high, low, open, close);
      bool dnBroken = st.refLow.valid && !st.refLow.broken &&
                      BrokeLevel(i, st.refLow.price, false, high, low, open, close);
      if(upBroken && dnBroken)
      {
         // DOWN 中 阳线双破→保留 MSS(上破)；阴线→保留 BOS(下破)
         if(close[i] >= open[i])
         {
            evType = ApplyMssTransition(st, DIR_UP, st.refHigh, true, i,
                                        high, low, open, close, atrArr);
         }
         else
         {
            AddBOSResult(i, DIR_DOWN, st.refLow, st.state);
            st.refLow.broken = true;
            st.refHigh.broken = true;   // [v1.50-s59] 镜像：消耗落选的 refHigh
            evType = 2;
         }
      }
      else if(dnBroken)
      {
         AddBOSResult(i, DIR_DOWN, st.refLow, st.state);
         st.refLow.broken = true;
         evType = 2;
      }
      else if(upBroken)
      {
         evType = ApplyMssTransition(st, DIR_UP, st.refHigh, true, i,
                                     high, low, open, close, atrArr);
      }
   }
   return evType;
}

//+------------------------------------------------------------------+
//| 【阶段 11 起已删除】UpdateRefsFromSwing()                          |
//|                                                                  |
//|  它按"主结构腿长门槛"维护 refHigh/refLow。删除理由：                  |
//|   · 该门槛（≥1.0×ATR 或 ≥0.382×前段）**不是他的定义**，也无任何一手依据；|
//|   · 他的 protected swing 定义是"收盘穿过进入该位的那一串反向 K 线"    |
//|     —— 即 **CISD 触发**（见 SetProtectedFromCisd，三篇一手文章一致）。 |
//|   · 两者并存会导致 ref 被两个不同口径反复覆盖 → 语义含糊。            |
//+------------------------------------------------------------------+

//══════════════════════════════════════════════════════════════════
//  分析层：主计算（纯分析，不触碰任何图表对象）
//══════════════════════════════════════════════════════════════════
//+------------------------------------------------------------------+
//| 阶段 1-C：HTF relevance（对齐 TTrades「回看 3 根高周期 K 线」）    |
//|  只计算与标记，不参与任何过滤决策（C1：不过滤 swing）。            |
//|  降级：HTF 数据未就绪（Copy* 返回 <=0）时不画，debug 下留痕。      |
//+------------------------------------------------------------------+
void ComputeRelevance()
{
   g_relValid = false;
   g_relBars  = 0;
   g_relHigh  = 0.0; g_relLow = 0.0;
   g_relT1    = 0;   g_relT2  = 0;

   double   hi[], lo[];
   datetime tm[];
   int gh = CopyHigh(_Symbol, InpHTFPeriod, 0, RELEVANCE_BARS, hi);
   int gl = CopyLow (_Symbol, InpHTFPeriod, 0, RELEVANCE_BARS, lo);
   int gt = CopyTime(_Symbol, InpHTFPeriod, 0, RELEVANCE_BARS, tm);
   g_relBars = MathMin(gh, MathMin(gl, gt));

   if(gh <= 0 || gl <= 0 || gt <= 0)
   {
      if(InpDebugShowRef)
         PrintFormat("STRUCT_REL 降级：HTF 数据未就绪 tf=%s gotH=%d gotL=%d gotT=%d err=%d",
                     EnumToString(InpHTFPeriod), gh, gl, gt, GetLastError());
      return;
   }

   int n = MathMin(gh, MathMin(gl, gt));
   // 极值只取 max/min → 与数组方向无关，故不需要 ArraySetAsSeries。
   // 时间同样用 min/max 求，避免依赖 Copy* 的填充顺序。
   g_relHigh = hi[0];
   g_relLow  = lo[0];
   g_relT1   = tm[0];
   g_relT2   = tm[0];
   for(int k = 0; k < n; k++)
   {
      if(hi[k] > g_relHigh) g_relHigh = hi[k];
      if(lo[k] < g_relLow)  g_relLow  = lo[k];
      if(tm[k] < g_relT1)   g_relT1   = tm[k];
      if(tm[k] > g_relT2)   g_relT2   = tm[k];
   }
   g_relValid = true;

   if(InpDebugShowRef)
      PrintFormat("STRUCT_REL tf=%s bars=%d relHigh=%.5f relLow=%.5f t1=%s t2=%s",
                  EnumToString(InpHTFPeriod), n, g_relHigh, g_relLow,
                  TimeToString(g_relT1, TIME_DATE | TIME_MINUTES),
                  TimeToString(g_relT2, TIME_DATE | TIME_MINUTES));
}
//+------------------------------------------------------------------+
//| 阶段 1-D：节点分级（short-term / intermediate-term）              |
//|  定义由图 `docs/research/img/ITM.png` 证实（文字定义缺了关键词）：  |
//|    intermediate = 一个 short-term 点，且**比左右最近的同类型点都   |
//|    更极端**。图中 STH(2) 左右各有 short-term high 却标 STH 而非    |
//|    ITH → 字面读法（只看"左右有没有"）被否证。                      |
//|  节点数组强制高低交替，故"最近的同类型点"就是 n-2 与 n+2。         |
//|  任一侧越界 → 无法确认 → 保持 short-term。                        |
//|  必须在主循环【之后】整表计算：右侧邻居要等后续节点出现才可知。     |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 阶段 30/35：**节点级** BOS / CHoCH（方向决定叫哪个）                |
//|                                                                  |
//|  ⚠️⚠️ 术语来源必须写明：TTrades 全站语料 `change of character` = 0、   |
//|     `\bchoch\b` = 0（plan §1 决策 A 的语料级否定）。本项是**借用**，   |
//|     他的早期信号是 CISD。故代码 / README / CSV 头部三处都标"借用词"，  |
//|     不得当作他的口径引用。用户 2026-09-29 明确要求此标注。            |
//|                                                                  |
//|  为什么需要它（真实盲区）：他的 MSS 只认"被 CISD 保护过的 swing"      |
//|  （SetProtectedFromCisd 是唯一写 ref 的地方），而**每次 bearish MSS   |
//|  之后 `refHigh.valid` 会被清空**（ApplyMssTransition）。于是在"没有   |
//|  CISD 重建高点位"的窗口里，价格向上破掉一个肉眼明显的高点，引擎连     |
//|  可比的位都没有 ⇒ 图上什么都没有。CHoCH 层补的正是这个盲区。          |
//|                                                                  |
//|  ⚠️ 三条纪律：                                                      |
//|   1. **纯渲染层**：绝不写 st.state，不影响任何 BOS/MSS 归属与判定。   |
//|   2. 判据用**节点**（g_result.nodes）而非 refHigh/refLow —— ref 会被  |
//|      MSS 清空，节点不会。                                          |
//|   3. 与 ComputeClosures 同层次：基于**最终节点表**的后验扫描。        |
//|      代价：同一类型被更极端节点**替换**过的地方，这里看到的是替换后的  |
//|      节点（与 closure 层同一取舍，plan §54 记录）。                  |
//|                                                                  |
//|  ⚠️⚠️ 【v1.50-s45 修正：结构方向**不能**借引擎的 MSS 状态】           |
//|   初版用"强 MSS 翻转出的 st.state"当趋势，结果 2026-09-29 那段上涨里  |
//|   把**连续破新高**全标成了 CHoCH —— 因为 bearish MSS 清空 refHigh 后  |
//|   那个状态**结构性锁死在 DOWN**（上方破位产生不了事件 ⇒ 永远翻不上来）。|
//|   用户实机指出"这两处应该是 BOS"，**判断正确**。                      |
//|   ⇒ 改为**自带结构方向**：`structDir` = **上一次破位的方向**，初值取    |
//|     **第一段腿**的方向（`nodes[0]` 是低点 → 首段向上 → UP）。          |
//|     破位方向 == structDir → **BOS**（顺势）；否则 → **CHoCH**（逆势）  |
//|     并把 structDir 翻成该方向 ⇒ 判据成为一句**纯节点级规则**，与引擎   |
//|     状态机彻底解耦（不再引用 `g_result.mss`，故不会被它的锁死传染）。   |
//|                                                                  |
//|  判据（用户裁定"每次破 swing 都标"）：                               |
//|   由旧到新逐 bar 扫；对"最近一个高点节点 / 低点节点"判破位；同一个位只  |
//|   报一次（报过置 done），**新节点到来后重新武装**。                    |
//|                                                                  |
//|  ⚠️⚠️ 【v1.50-s55/s70 修正：口径 + 「什么叫改性格」】                   |
//|   s55 症状：M1 上涨段里两处"肉眼明显的高点破位"被标成 CHoCH。成因 =     |
//|     本函数直接复用 `BrokeLevel()` ⇒ 继承 `InpBreakConfirm=BREAK_WICK`   |
//|     ⇒ **影线一扫即破位、即翻转 structDir**。引擎那边本有闸门（见输入处  |
//|     :227-229，"The sweep itself is not the confirmation."），节点层漏了。|
//|     ⇒ ① 自带口径 `EffectiveNodeBreak()`，默认 **BREAK_CLOSE**。        |
//|   s70 症状：**加载了 s55 之后，那两处仍是 CHoCH**；用户说「应该都是     |
//|     **内部的 BOS** 才对」。⇒ s55 的"新同侧极值"闸门不够：**M1 回撤几乎 |
//|     总能做出一个略低的低点**（LL）⇒ 判据通过 ⇒ 方向被打回空 ⇒ 其后上破 |
//|     又成 CHoCH。                                                     |
//|   ⚠️⚠️【v1.50-s59 补记：s70 那次修正**实际从未生效**】                  |
//|     上面 ② 的判据本来是对的，但两个调用点把 helper **接反了** —— 破高点 |
//|     调了 `NodeFlipUp`（它量的是"自高点回落了多少"，而破高点必然发生在   |
//|     空头腿内，此时 legExt<=legLvl 恒成立）⇒ progress 恒为 0 ⇒ 恒 true   |
//|     ⇒ 任何逆势破位都判成"改性格"= CHoCH，`InpNodeFlipRetracePct` 完全   |
//|     是哑输入。NodeFlipDn 与破低点同病（镜像）。**编译 0 错 0 警**，所以  |
//|     从 s70 到 s59 前一直没人发现：症状被"修"了，代码没变。              |
//|     ⇒ 已在 s59 修正：按"破哪一侧"配对 helper（破高点→NodeFlipDn，       |
//|       破低点→NodeFlipUp）。**这条注释所记录的症状到此才真正消除。**     |
//|     ⇒ ② 新增 `InpNodeFlipMode`（默认 NODEFLIP_RETRACE：回吐整段腿的    |
//|        ≥N%（默认 50% = 贴现区 EQ）才算"改性格"）。                     |
//|     ⇒ ③ **标签规则与翻转绑定**：翻转 ⇒ `CHoCH`；不翻转 ⇒ `BOS`（逆势   |
//|        但未翻转者记 `NODEBRK_BOS_INTERNAL`，观感同 BOS，CSV 可区分）。  |
//|   ⚠️ 被否掉的替代方案：用 intermediate(tier-1) 当闸门（单边下跌里只有   |
//|     最低点满足 ⇒ 反而把问题从上涨搬到下跌）。记录于 plan §69.4。        |
//+------------------------------------------------------------------+
void AddChochResult(const int bar, const int dir, const double level,
                    const int refBar, const int sub)
{
   ArrayResize(g_result.choch, g_result.nChoch + 1);
   g_result.choch[g_result.nChoch].bar     = bar;
   g_result.choch[g_result.nChoch].dir     = dir;
   g_result.choch[g_result.nChoch].ref     = level;
   g_result.choch[g_result.nChoch].refBar  = refBar;
   // ⚠️ 恒 false：CHoCH **没有位移判据**。复用 weak 会把"哪种破位"与"信号质量"混成一谈
   //    （同 v1.49 第 11 条对 FVG 的处置）。
   g_result.choch[g_result.nChoch].weak    = false;
   g_result.choch[g_result.nChoch].fvgFollow = false;   // 非 CISD/OB：无含义
   g_result.choch[g_result.nChoch].bias    = 0;      // 由 FillEventBias 回填
   g_result.choch[g_result.nChoch].bodyATR = 0.0;
   g_result.choch[g_result.nChoch].penATR  = 0.0;
   g_result.choch[g_result.nChoch].sub     = sub;    // NODEBRK_BOS / NODEBRK_CHOCH
   g_result.choch[g_result.nChoch].c4      = 0;
   if(InpDebugShowRef)
      Print("NODEBRK event: type=", (sub == NODEBRK_BOS ? "BOS(same-dir)"
                                     : (sub == NODEBRK_BOS_INTERNAL ? "BOS(counter-dir,internal-break)"
                                                                    : "CHoCH(character-changed)")),
            " bar=", bar, " refBar=", refBar,
            " dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " level=", DoubleToString(level, _Digits),
            " (CHoCH = borrowed ICT term, NOT TTrades)");
   g_result.nChoch++;
}

bool NodeFlipUp(const int i, const double legLvl, const double legExt,
                const double lvl, const double prev, const bool hasPrev,
                const double &close[])
{
   switch(InpNodeFlipMode)
   {
      case NODEFLIP_ANY:     return true;
      case NODEFLIP_EXTREME: return (!hasPrev || lvl > prev);    // 破的是"更高的高点"
      case NODEFLIP_LEG:     return (legLvl <= 0.0 || close[i] > legLvl);
      default:               break;                              // NODEFLIP_RETRACE
   }
   // 回吐判据：这条腿已经走了 progress，若价格从腿极值回吐 ≥ N% 的 progress ⇒ 改性格
   const double progress = (legLvl > 0.0 && legExt > legLvl) ? (legExt - legLvl) : 0.0;
   if(progress <= 0.0) return true;                              // 量不出腿长 ⇒ 不设门槛
   return ((legExt - close[i]) >= progress * InpNodeFlipRetracePct / 100.0);
}

bool NodeFlipDn(const int i, const double legLvl, const double legExt,
                const double lvl, const double prev, const bool hasPrev,
                const double &close[])
{
   switch(InpNodeFlipMode)
   {
      case NODEFLIP_ANY:     return true;
      case NODEFLIP_EXTREME: return (!hasPrev || lvl < prev);    // 破的是"更低的低点"
      case NODEFLIP_LEG:     return (legLvl <= 0.0 || close[i] < legLvl);
      default:               break;
   }
   const double progress = (legLvl > 0.0 && legLvl > legExt) ? (legLvl - legExt) : 0.0;
   if(progress <= 0.0) return true;
   return ((close[i] - legExt) >= progress * InpNodeFlipRetracePct / 100.0);
}

void ComputeChoch(const double &high[], const double &low[],
                  const double &open[], const double &close[],
                  const int rates_total)
{
   // ⚠️ 自复位必须在早退之前 —— 否则关掉开关会留下上一帧的陈旧数据，
   //    A/B 对照的前提（关掉 = 零 CHOCH 行）就不成立（v1.50-s18 的教训）。
   g_result.nChoch = 0;
   if(!InpShowChoch) return;
   int n = g_result.nNodes;
   if(n <= 0 || rates_total <= 1) return;

   // 结构方向初值 = **第一段腿**的方向（nodes[] 旧→新、高低交替）：
   //  nodes[0] 是低点 → 首段向上 → UP；是高点 → 首段向下 → DOWN。
   //  ⚠️ 不用引擎的 MSS 状态（见抬头：它会被 bearish MSS 结构性锁死）。
   //  只有一个节点时无从判断 → 0，由第一次破位建立方向（那次算 BOS）。
   int structDir = (n >= 2) ? (g_result.nodes[0].isHigh ? DIR_DOWN : DIR_UP) : 0;

   // 只扫"有数据的那段"。⚠️ 起点必须取**最旧**的那一个（bar 下标最大）——
   //  若取更年轻的起点，`while(nodes[p].bar >= i)` 会在**同一根** bar 上把一批更旧的
   //  节点一次性消费掉，等于把这段的"最近 swing"提前变成了新节点，前面的破位会被漏掉。
   int iStart = g_result.nodes[0].bar;
   if(iStart > rates_total - 1) iStart = rates_total - 1;

   // 阶段 69：本层**自带**破位口径（默认 CLOSE），不再借用引擎的 InpBreakConfirm(WICK)。
   //  取一次即定（EffectiveNodeBreak 只读输入，无副作用）。
   ENUM_BREAK_CONFIRM nbc = EffectiveNodeBreak();

   int    p = 0;
   double hiLvl = 0.0, loLvl = 0.0;
   int    hiBar = -1,  loBar = -1;
   bool   hiDone = true, loDone = true;   // 尚无位 → 视为"已用掉"，免得误触发
   // 阶段 69：**上一个同类型节点**的价格（节点数组强制高低交替，故就是旧一轮的那个）。
   //  作用 = 翻转闸门：只有"被破的这个节点本身是新的同侧极值"才真的翻转结构方向。
   //  ⚠️ `hasPrev=false`（本类型在窗口内只有这一个节点）时无从比较 → 允许翻转，
   //     即退回改动前的行为（宁可多翻一次，也不要在窗口左缘把方向锁死）。
   double hiPrev = 0.0, loPrev = 0.0;
   bool   hiHasPrev = false, loHasPrev = false;

   // 阶段 70：当前**腿**的两个参考价（用于"改性格"判据）
   //   legLvl = 这条腿的**起点**价（趋势确立/翻转时反向的最近节点价；0 = 尚未建立）
   //   legExt = 腿内沿趋势方向的**极值**（多 = 最高价，空 = 最低价），逐 bar 刷新
   // ⚠️ 两者都随扫描"由旧到新"推进而更新，故对每个历史 bar 用的都是当时的腿，
   //    不是最终值（后验层最容易踩的坑就是拿最终状态去解释历史）。
   double legLvl = 0.0;
   double legExt = 0.0;
   if(structDir == DIR_UP && iStart >= 0 && iStart < rates_total)   legExt = high[iStart];
   if(structDir == DIR_DOWN && iStart >= 0 && iStart < rates_total) legExt = low[iStart];

   for(int i = iStart; i >= 0; i--)
   {
      // 0) 腿内极值随行情推进（必须在本 bar 判破位**之前**更新：破位用的是当根的收盘，
      //    极值也要包含当根 —— 否则"同一根既创新高又破位"会被算成回吐不足）。
      if(structDir == DIR_UP)        { if(high[i] > legExt) legExt = high[i]; }
      else if(structDir == DIR_DOWN) { if(low[i]  < legExt) legExt = low[i]; }

      // 1) 本 bar 上存在的结构节点 → 更新"最近一个 swing"（并重新武装该侧）
      while(p < n && g_result.nodes[p].bar >= i)
      {
         if(g_result.nodes[p].isHigh)
         {
            hiPrev = hiLvl; hiHasPrev = (hiBar >= 0);
            hiLvl = g_result.nodes[p].price; hiBar = g_result.nodes[p].bar; hiDone = false;
         }
         else
         {
            loPrev = loLvl; loHasPrev = (loBar >= 0);
            loLvl = g_result.nodes[p].price; loBar = g_result.nodes[p].bar; loDone = false;
         }
         p++;
      }

      // 2) 破位。**标签规则（v1.50-s70）**：改性格 ⇒ CHoCH；没改性格 ⇒ BOS。
      //    顺势破位天然不改性格（方向没变）⇒ BOS；逆势破位是否改性格由 InpNodeFlipMode 定。
      if(hiBar >= 0 && !hiDone && BrokeLevelCal(i, hiLvl, true, high, low, open, close, nbc))
      {
         bool isBosH = (structDir == DIR_UP || structDir == 0);
      // [v1.50-s59 缺陷修复] 这里原来调的是 NodeFlipUp -- 方向反了，导致默认档彻底失效：
      //   NodeFlipUp 的 progress 要求 legExt > legLvl，而"破高点"必然发生在空头腿（structDir==DOWN）
      //   之下，此时 legLvl=腿起点高点、legExt=腿内最低点，恒有 legExt <= legLvl，故 progress 恒为 0
      //   于是 NodeFlipUp 恒返回 true，任何逆势破位都被判成"改性格"=CHoCH，
      //   而 InpNodeFlipRetracePct（默认 50%）成为哑输入。NodeFlipDn 与破低点同病（镜像）。
      //   修法：按"破哪一侧"配对 -- 破高点用 NodeFlipDn（量自最低点的回补），破低点用 NodeFlipUp。
      bool flipH  = isBosH ? false : NodeFlipDn(i, legLvl, legExt, hiLvl, hiPrev, hiHasPrev, close);
         int  subH   = isBosH ? NODEBRK_BOS : (flipH ? NODEBRK_CHOCH : NODEBRK_BOS_INTERNAL);
         AddChochResult(i, DIR_UP, hiLvl, hiBar, subH);
         hiDone = true;
         if(flipH)
         {
            structDir = DIR_UP;
            legLvl    = (loBar >= 0 ? loLvl : 0.0);   // 这条多腿的起点 = 此刻最近的那个低点
            legExt    = high[i];
         }
      }
      else if(loBar >= 0 && !loDone && BrokeLevelCal(i, loLvl, false, high, low, open, close, nbc))
      {
         bool isBosL = (structDir == DIR_DOWN || structDir == 0);
      bool flipL  = isBosL ? false : NodeFlipUp(i, legLvl, legExt, loLvl, loPrev, loHasPrev, close);   // v1.50-s59：同 flipH，按破位侧配对
         int  subL   = isBosL ? NODEBRK_BOS : (flipL ? NODEBRK_CHOCH : NODEBRK_BOS_INTERNAL);
         AddChochResult(i, DIR_DOWN, loLvl, loBar, subL);
         loDone = true;
         if(flipL)
         {
            structDir = DIR_DOWN;
            legLvl    = (hiBar >= 0 ? hiLvl : 0.0);
            legExt    = low[i];
         }
      }
   }
}

void ClassifyNodeTiers()
{
   int n = g_result.nNodes;
   for(int k = 0; k < n; k++) g_result.nodes[k].tier = 0;
   for(int k = 2; k + 2 < n; k++)
   {
      bool   isHigh = g_result.nodes[k].isHigh;
      double p      = g_result.nodes[k].price;
      double left   = g_result.nodes[k - 2].price;
      double right  = g_result.nodes[k + 2].price;
      bool   ok     = isHigh ? (p > left && p > right) : (p < left && p < right);
      if(ok) g_result.nodes[k].tier = 1;
   }
}

// 按 bar 反查节点层级（供 CSV 的 tier 列使用；事件创建时层级尚未算出，故查询期求值）
string NodeTierStr(const int bar)
{
   for(int k = 0; k < g_result.nNodes; k++)
      if(g_result.nodes[k].bar == bar)
         return (g_result.nodes[k].tier == 1 ? "intermediate" : "short");
   return "";
}
//+------------------------------------------------------------------+
//| 阶段 5：SWEEP（流动性扫荡）—— 纯上下文标注，不参与任何判定        |
//|                                                                  |
//|  他的原话：                                                        |
//|   · "price sweeps the previous candle's high or low and then       |
//|      closes back inside that range"                                |
//|   · "Use intermediate-term sweeps as confirmation of continuation  |
//|      or reversal."                                                 |
//|  ⚠️ 旧注释另引过 "Price takes out yesterday's high but closes back  |
//|     inside the range" —— 独立核验**未能溯源**，已删除。             |
//|                                                                  |
//|  定义：某根 K 线的影线越过位、但**收盘收回位内** → 该位被扫荡。     |
//|  位取自 intermediate（tier-1）节点；前日高/低见 PDH/PDL（v1.49-s13），   |
//|  但**不作为本函数的取位来源**。                                        |
//|  每个位只记一次（首次被扫荡）。                                     |
//|                                                                  |
//|  关键：sweep 不参与判定，故可在主循环【之后】做后验扫描 ——          |
//|  不受"事件时刻拿不到 tier"这一约束（1-F 卡住的地方）。             |
//+------------------------------------------------------------------+
void AddSweepResult(const int bar, const int dir, const double lvl, const int srcBar)
{
   ArrayResize(g_result.sweep, g_result.nSWEEP + 1);
   g_result.sweep[g_result.nSWEEP].bar     = bar;
   g_result.sweep[g_result.nSWEEP].dir     = dir;
   g_result.sweep[g_result.nSWEEP].ref     = lvl;
   g_result.sweep[g_result.nSWEEP].refBar  = srcBar;
   g_result.sweep[g_result.nSWEEP].weak    = false;
   g_result.sweep[g_result.nSWEEP].fvgFollow = false;   // 非 CISD/OB：无含义
   g_result.sweep[g_result.nSWEEP].bodyATR = 0.0;
   g_result.sweep[g_result.nSWEEP].penATR  = 0.0;
   if(InpDebugShowRef)
      Print("SWEEP event: type=SWEEP dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " sweepBar=", bar, " srcBar=", srcBar,
            " level=", DoubleToString(lvl, _Digits));
   g_result.nSWEEP++;
}

void ComputeSweeps(const double &high[], const double &low[],
                   const double &open[], const double &close[])
{
   g_result.nSWEEP = 0;
   int n = g_result.nNodes;
   for(int k = 0; k < n; k++)
   {
      if(g_result.nodes[k].tier != 1) continue;    // 只用 intermediate 位
      bool   isHigh = g_result.nodes[k].isHigh;
      double lvl    = g_result.nodes[k].price;
      int    srcBar = g_result.nodes[k].bar;
      // series：下标减小 = 更新，故自该位之后向更新方向扫描
      for(int i = srcBar - 1; i >= 0; i--)
      {
         // 阶段 72（收紧，用户 2026-09-30：「我框出来的这里都实体突破了，不算 sweep 了吧」）：
         //   ① **只有影线越界**：实体两端都不得越界（扫高：close < lvl 且 open <= lvl）。
         //      旧判据只看收盘 ⇒ "开在位外、收在位内"的大阴/大阳（跨位 K 线）也会被记成 sweep，
         //      那正是用户说的"实体突破了"。
         //   ② **位被收盘接受后停止扫描**：一旦出现 close 越界，该位就不再是"未被扫的流动性"，
         //      之后再刺破并收回属于**破位后的回抽**，不是 sweep。
         //      ⚠️ 旧实现只在命中 swept 时 break ⇒ 会把破位之后的一次回抽标成 sweep。
         bool swept = isHigh ? (high[i] > lvl && close[i] < lvl && open[i] <= lvl)
                             : (low[i]  < lvl && close[i] > lvl && open[i] >= lvl);
         if(swept)
         {
            AddSweepResult(i, isHigh ? DIR_DOWN : DIR_UP, lvl, srcBar);
            break;                                  // 每个位只记首次
         }
         // ② 被收盘接受 ⇒ 这个位作废，不再找 sweep。
         //   ⚠️ 与 swept 互斥**只在"收盘"这一维**成立：swept 要求收盘在位内、accepted 要求位外，
         //      故先判 swept 才是对的（保证"先扫后破"的那一次仍被记下来）。
         const bool accepted = isHigh ? (close[i] > lvl) : (close[i] < lvl);
         if(accepted) break;
      }
   }
}
//+------------------------------------------------------------------+
//| 阶段 6：HTF 偏置（门禁的计算层）                                   |
//|                                                                  |
//|  他的原文："If price closes below the previous day's low – Expect  |
//|  continuation lower. … Same logic applies for previous day's high, |
//|  but inverted."  "Higher time frame closure first → Lower time     |
//|  frame CISD."                                                      |
//|                                                                  |
//|  实现：自时刻 t 起，取上一根【已收盘】的 HTF K 线（shift+1），与它  |
//|  前一根（shift+2）比较；落在区间内则向前回溯，取最近一次决定性收线。 |
//|  返回 +1 看涨 / -1 看跌 / 0 无偏置。                               |
//|  成本：仅对事件调用（几十次），且最多回溯 InpBiasLookback 根。      |
//+------------------------------------------------------------------+
int BiasAtTime(const datetime t)
{
   int base = iBarShift(_Symbol, InpBiasTF, t, false);
   if(base < 0) return 0;
   int last = base + 1;                       // 含 t 的那根的前一根 = 最后一根已收盘
   for(int s = last; s < last + InpBiasLookback; s++)
   {
      double c  = iClose(_Symbol, InpBiasTF, s);
      double ph = iHigh (_Symbol, InpBiasTF, s + 1);
      double pl = iLow  (_Symbol, InpBiasTF, s + 1);
      if(c <= 0.0 || ph <= 0.0 || pl <= 0.0) break;   // HTF 数据未就绪 → 无偏置
      if(c > ph) return  1;
      if(c < pl) return -1;
   }
   return 0;
}

string BiasStr(const int b)
{
   if(b > 0) return "bull";
   if(b < 0) return "bear";
   return "none";
}

//+------------------------------------------------------------------+
//| 阶段 6-a：把偏置写入每条事件（后验，因此无需改任何事件创建签名）    |
//|  放在 ClassifyNodeTiers / ComputeSweeps 之后。                    |
//+------------------------------------------------------------------+
void FillEventBias(const datetime &time[], const int rates_total)
{
   g_curBias = BiasAtTime(time[0]);

   for(int k = 0; k < g_result.nMSS; k++)
      g_result.mss[k].bias = (g_result.mss[k].bar >= 0 && g_result.mss[k].bar < rates_total)
                             ? BiasAtTime(time[g_result.mss[k].bar]) : 0;
   for(int k = 0; k < g_result.nBOS; k++)
      g_result.bos[k].bias = (g_result.bos[k].bar >= 0 && g_result.bos[k].bar < rates_total)
                             ? BiasAtTime(time[g_result.bos[k].bar]) : 0;
   for(int k = 0; k < g_result.nCISD; k++)
      g_result.cisd[k].bias = (g_result.cisd[k].bar >= 0 && g_result.cisd[k].bar < rates_total)
                              ? BiasAtTime(time[g_result.cisd[k].bar]) : 0;
   for(int k = 0; k < g_result.nSWEEP; k++)
      g_result.sweep[k].bias = (g_result.sweep[k].bar >= 0 && g_result.sweep[k].bar < rates_total)
                               ? BiasAtTime(time[g_result.sweep[k].bar]) : 0;
   // 阶段 9：PD Array 同样回填偏置 —— 渲染层据此把"与 HTF 偏置逆向"的 POI 弱化，
   // 与 MSS/BOS/CISD/SWEEP 的既有处理保持一致。
   for(int k = 0; k < g_result.nFVG; k++)
      g_result.fvg[k].bias = (g_result.fvg[k].bar >= 0 && g_result.fvg[k].bar < rates_total)
                             ? BiasAtTime(time[g_result.fvg[k].bar]) : 0;
   for(int k = 0; k < g_result.nOB; k++)
      g_result.ob[k].bias = (g_result.ob[k].bar >= 0 && g_result.ob[k].bar < rates_total)
                            ? BiasAtTime(time[g_result.ob[k].bar]) : 0;
   // 阶段 18：closure 同样回填偏置（渲染层据此弱化与 HTF 逆向的确认）。
   for(int k = 0; k < g_result.nClosure; k++)
      g_result.closure[k].bias = (g_result.closure[k].bar >= 0 && g_result.closure[k].bar < rates_total)
                                 ? BiasAtTime(time[g_result.closure[k].bar]) : 0;
   // 阶段 30：CHoCH 回填偏置。⚠️ 渲染层**不**用偏置弱化 CHoCH（它没有"确认"语义），
   //  但 CSV 仍要如实记录该事件发生时的 HTF 偏置，供离线分析。
   for(int k = 0; k < g_result.nChoch; k++)
      g_result.choch[k].bias = (g_result.choch[k].bar >= 0 && g_result.choch[k].bar < rates_total)
                               ? BiasAtTime(time[g_result.choch[k].bar]) : 0;
}

//+------------------------------------------------------------------+
//| 前日高/低（PDH / PDL）                                            |
//|                                                                  |
//|  取数：`InpPDPeriod`（默认 PERIOD_D1）上**最近一根已收盘**的 K 线。   |
//|                                                                  |
//|  ⚠️ 为什么不能写死 shift=1：                                       |
//|   服务器刚换日、当日 K 线尚未生成的那一小段时间里，shift=0 才是     |
//|   "最近一根已收盘"。写死 shift=1 会在那个窗口里取到**前天**。        |
//|   故改为按**日期**判定：取第一根 open 日期 **严格早于当前服务器日期** |
//|   的 K 线。                                                        |
//|  ⚠️ 周末/假日无 K 线时，得到的是"最近一个交易日"，这也是 ICT 语境下  |
//|   previous day high/low 的通行含义。                               |
//+------------------------------------------------------------------+
void ComputePrevDay()
{
   g_pdValid = false; g_pdh = 0.0; g_pdl = 0.0; g_pdT1 = 0;

   double   hi[], lo[];
   datetime tm[];
   ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true); ArraySetAsSeries(tm, true);
   int gh = CopyHigh(_Symbol, InpPDPeriod, 0, 4, hi);
   int gl = CopyLow (_Symbol, InpPDPeriod, 0, 4, lo);
   int gt = CopyTime(_Symbol, InpPDPeriod, 0, 4, tm);
   int n  = MathMin(gh, MathMin(gl, gt));
   if(n < 2)
   {
      if(InpDebugShowRef)
         PrintFormat("STRUCT_PD 降级：数据不足 tf=%s got=%d err=%d",
                     EnumToString(InpPDPeriod), n, GetLastError());
      return;
   }

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int todayKey = now.year * 10000 + now.mon * 100 + now.day;

   int idx = -1;
   for(int i = 0; i < n; i++)
   {
      MqlDateTime d;
      TimeToStruct(tm[i], d);
      int key = d.year * 10000 + d.mon * 100 + d.day;
      if(key < todayKey) { idx = i; break; }   // 第一根日期早于今天的 = 最近一根已收盘
   }
   if(idx < 0) return;                          // 窗口内全是今天 → 拿不到

   g_pdh = hi[idx]; g_pdl = lo[idx]; g_pdT1 = tm[idx]; g_pdValid = true;
   if(InpDebugShowRef)
      PrintFormat("STRUCT_PD tf=%s shift=%d open=%s H=%s L=%s",
                  EnumToString(InpPDPeriod), idx, TimeToString(g_pdT1, TIME_DATE),
                  DoubleToString(g_pdh, _Digits), DoubleToString(g_pdl, _Digits));
}

//+------------------------------------------------------------------+
//| 流动性位是否已被取走                                              |
//|  "尚未被取走" = 该节点之后**没有任何 bar 越过它**。                 |
//|  他体系里被取走的外部流动性不再算目标 —— 应看下一个。               |
//|                                                                  |
//|  ⚠️ 本函数由 ComputeErlIrl 里原有的内联循环**逐字提取**而来       |
//|  （v1.50-s19），供 Auto Targets 复用 —— 目的是**同一个概念只有一份  |
//|  实现**（同 CisdOriginBar 的规矩），而不是复制两份后各自漂移。      |
//|  抽取是行为保持的；可观测验收锚：CSV 头部 `# erlirl ... erlPrice=` |
//|  必须与 s18 逐字相同。                                            |
//+------------------------------------------------------------------+
bool IsLiquidityTaken(const double lvl, const int nodeBar, const bool isHigh,
                      const double &high[], const double &low[])
{
   for(int j = nodeBar - 1; j >= 0; j--)
      if((isHigh && high[j] > lvl) || (!isHigh && low[j] < lvl)) return true;
   return false;
}

//+------------------------------------------------------------------+
//| 阶段 10：Internal / External Liquidity（对齐 TTrades）             |
//|                                                                  |
//|  他（research §13）逐字：                                          |
//|   · "Internal liquidity is a fair value gap."                     |
//|   · "External liquidity is a swing high or swing low."            |
//|   · "Internal liquidity provides the point of interest.           |
//|      External liquidity provides the target."                     |
//|   · "Start with the higher timeframe bias."                       |
//|   · internal→external 顺势方向 easier；external→internal 需更强确认。|
//|                                                                  |
//|  【定位】纯可视化层：只派生两个"当前配对"的价位供渲染，**不参与任何判定**。|
//|  【为什么是后验】依赖 g_curBias（FillEventBias 才算出）与 close[0]，    |
//|   故必须排在 FillEventBias 之后。                                  |
//|                                                                  |
//|  【配对规则（本实现自定，他未给机械规则）】                          |
//|   ERL = 偏置方向上、现价之外、**尚未被取走**的最近摆动位。           |
//|         "尚未被取走" = 该节点之后没有任何 bar 越过它（否则流动性已消耗，|
//|         他体系里被取走的外部流动性不再是目标 —— 应看下一个）。        |
//|   IRL = 偏置方向上、现价之外的**未完全回补** FVG（回撤区 = POI）。     |
//|         看涨取现价下方的看涨缺口，看跌取现价上方的看跌缺口。           |
//|  ⚠️ 取"最近"是**本实现自定**：他未说明按价格距离还是按时间先后。      |
//+------------------------------------------------------------------+
void ComputeErlIrl(const double &high[], const double &low[], const double &close[])
{
   g_erlValid = false; g_erlPrice = 0.0; g_erlBar = -1;
   g_irlValid = false; g_irlPrice = 0.0; g_irlFvgIdx = -1;

   // 他："Start with the higher timeframe bias." → 无偏置则不画（两侧都可能是目标）。
   if(g_curBias == 0) return;
   double px = close[0];

   //── ERL：偏置方向上最近的、尚未被取走的摆动位 ──
   int n = g_result.nNodes;
   for(int k = 0; k < n; k++)
   {
      bool isHigh = g_result.nodes[k].isHigh;
      if(g_curBias > 0 && !isHigh) continue;      // 看涨 → 上方摆动高
      if(g_curBias < 0 &&  isHigh) continue;      // 看跌 → 下方摆动低
      int nb = g_result.nodes[k].bar;
      if(nb < 0) continue;
      double lvl = g_result.nodes[k].price;
      if(g_curBias > 0 && lvl <= px) continue;    // 必须在现价之上
      if(g_curBias < 0 && lvl >= px) continue;    // 必须在现价之下
      // 该位之后是否已被越过 → 已取走，跳过（实现见 IsLiquidityTaken）
      if(IsLiquidityTaken(lvl, nb, isHigh, high, low)) continue;
      // 取价格上最近的那个
      if(!g_erlValid || (g_curBias > 0 && lvl < g_erlPrice) ||
                        (g_curBias < 0 && lvl > g_erlPrice))
      {
         g_erlValid = true; g_erlPrice = lvl; g_erlBar = nb;
      }
   }

   //── IRL：偏置方向上的回撤 FVG（未完全回补）──
   for(int k = 0; k < g_result.nFVG; k++)
   {
      if(g_result.fvg[k].fillPct >= 1.0) continue;      // 已完全回补 → 不再是有效 POI
      int    fd = g_result.fvg[k].dir;
      double zLo = g_result.fvg[k].zoneLo, zHi = g_result.fvg[k].zoneHi;
      if(g_curBias > 0)
      {
         if(fd != DIR_UP) continue;                     // 看涨 → 需求缺口
         if(zHi >= px) continue;                        // 必须在现价之下（回撤才会到达）
         if(!g_irlValid || zHi > g_irlPrice)            // 取最靠近现价的
            { g_irlValid = true; g_irlPrice = zHi; g_irlFvgIdx = k; }
      }
      else
      {
         if(fd != DIR_DOWN) continue;                   // 看跌 → 供给缺口
         if(zLo <= px) continue;                        // 必须在现价之上
         if(!g_irlValid || zLo < g_irlPrice)
            { g_irlValid = true; g_irlPrice = zLo; g_irlFvgIdx = k; }
      }
   }
}
//+------------------------------------------------------------------+
//| 阶段 12-d：CISD 的位移第②条 —— 「后续 N 根内出现同向 FVG」         |
//|                                                                  |
//|  用户要求：把 CISD 原有第②条（收盘穿越深度 ≥0.3×ATR）**换成**这一条。 |
//|                                                                  |
//|  【为什么必须后验】FVG 是主循环里随遍历逐 bar 产生的。某次 CISD 在 bar i |
//|  触发时，它**之后**的 N 根 bar 尚未被遍历，FVG 还不存在 —— 在主循环内   |
//|  判定会读到不完整的数据（且构成未来函数）。故整条判定放在主循环之后。   |
//|                                                                  |
//|  【为什么后验是安全的】CISD 的 `weak` **不参与任何判定** ——            |
//|  它只影响渲染配色与 CSV 记录（趋势状态机只看 MSS）。故在此改写 `weak`   |
//|  不会引入未来函数式的决策偏差。                                       |
//|  同一次 CISD 派生的 OB（bar 相同、方向相同）沿用同一结论，一并改写。    |
//|                                                                  |
//|  【语义方向】该条件只能把事件**判得更弱，不能判得更强**：              |
//|  ①（实体）与③（时效）仍是必要条件，本函数只在"没找到后续缺口"时补一个   |
//|  weak=true。故 strong 的集合是原来集合的子集。                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 阶段 19：Auto Targets（流动性目标）与操纵腿投影                      |
//|                                                                  |
//|  【定位】纯可视化层：只派生价位供渲染，**不参与任何判定**。          |
//|  【为什么是后验】与 ERL/IRL 同理 —— 依赖 g_curBias（FillEventBias    |
//|   才算）与 close[0]，故必须排在 FillEventBias 之后。                |
//|                                                                  |
//|  ⚠️ 分部置信度（必须与他的原话分开读）：                            |
//|   (a) 流动性目标：**他列为 primary**，规则逐字可溯 → 置信度高。      |
//|   (b) 投影目标：**锚定规则**逐字可溯（操纵腿 / 从 Candle 2 起算），    |
//|       但**方向约定是本实现反号后的读法**（见输入组注释），水平表本身   |
//|       也只有中介置信度 → **这是整个复刻里最弱的一环**。              |
//+------------------------------------------------------------------+
void ComputeTargets(const double &high[], const double &low[], const double &close[],
                    const int rates_total)
{
   g_tgtCount = 0;
   g_fibValid = false; g_fibA = 0.0; g_fibB = 0.0; g_fibRefBar = -1; g_fibDir = 0;

   // 他："Start with the higher timeframe bias." → 无偏置则两侧都可能是目标，不画。
   if(g_curBias == 0) return;
   double px = close[0];

   //── (a) 流动性目标：偏置方向上、现价之外、**尚未被取走**的摆动位，取价格最近的 N 个 ──
   //  ⚠️ 上限一律用 `want`（= InpTargetCount），**不是** MAX_TARGETS ——
   //     后者只是数组容量。曾把这两者混用，后果是"设成 2 也照样画 4 个"。
   if(InpShowAutoTargets)
   {
      int want = InpTargetCount;
      if(want < 0) want = 0;
      if(want > MAX_TARGETS) want = MAX_TARGETS;
      // 用"插入排序取最近 N 个"而不是先收集再排序：节点数可达数百，O(n×N) 远小于 O(n log n)。
      for(int k = 0; k < g_result.nNodes && want > 0; k++)
      {
         bool isHigh = g_result.nodes[k].isHigh;
         if(g_curBias > 0 && !isHigh) continue;      // 看涨 → 上方的高点
         if(g_curBias < 0 &&  isHigh) continue;      // 看跌 → 下方的低点
         int    nb  = g_result.nodes[k].bar;
         if(nb < 0 || nb >= rates_total) continue;
         double lvl = g_result.nodes[k].price;
         if(g_curBias > 0 && lvl <= px) continue;
         if(g_curBias < 0 && lvl >= px) continue;
         if(IsLiquidityTaken(lvl, nb, isHigh, high, low)) continue;
         // 按价格距离升序插入（距离近的排前面）
         double dist = MathAbs(lvl - px);
         int pos = g_tgtCount;
         while(pos > 0)
         {
            double dPrev = MathAbs(g_tgtPrice[pos - 1] - px);
            if(dPrev <= dist) break;
            pos--;
         }
         if(pos >= want) continue;
         int last = (g_tgtCount < want) ? g_tgtCount : want - 1;
         for(int m = last; m > pos; m--)
         {
            g_tgtPrice[m] = g_tgtPrice[m - 1];
            g_tgtBar[m]   = g_tgtBar[m - 1];
         }
         g_tgtPrice[pos] = lvl;
         g_tgtBar[pos]   = nb;
         if(g_tgtCount < want) g_tgtCount++;
      }
      // 前日高/低同为流动性目标（他明列 "previous day high/low" 属 draw on liquidity）。
      if(g_pdValid && want > 0 && g_tgtCount < want)
      {
         double pd = (g_curBias > 0) ? g_pdh : g_pdl;
         bool   ok = (pd > 0.0) && ((g_curBias > 0) ? (pd > px) : (pd < px));
         if(ok)
         {
            g_tgtPrice[g_tgtCount] = pd;
            // ⚠️ -1（不是 0）= "该目标没有本图节点 bar"。PDH/PDL 的锚是**高周期 K 线**，
            //    不是本图 bar；若写 0，渲染层会取 time[0]，于是线的左右端点**同一时刻**
            //    → OBJ_TREND 退化、画不出来。渲染层对 -1 单独处理（锚到该日开盘时间）。
            g_tgtBar[g_tgtCount]   = -1;
            g_tgtCount++;
         }
      }
   }

   //── (b) 操纵腿投影：A = 与偏置同向的最近一条 CISD 的极值；B = A 之后的反向极值 ──
   if(InpShowFibTargets)
   {
      for(int k = g_result.nCISD - 1; k >= 0; k--)
      {
         if(g_result.cisd[k].dir != g_curBias) continue;   // 只取与偏置同向的
         int rb = g_result.cisd[k].refBar;                 // 造势序列极值 bar = 操纵极值
         if(rb < 0 || rb >= rates_total) continue;
         double A = (g_curBias > 0) ? low[rb] : high[rb];
         double B = (g_curBias > 0) ? -DBL_MAX : DBL_MAX;
         for(int i = rb - 1; i >= 0; i--)                  // rb 之后（更新的 bar）
         {
            if(g_curBias > 0) { if(high[i] > B) B = high[i]; }
            else              { if(low[i]  < B) B = low[i];  }
         }
         if(B == -DBL_MAX || B == DBL_MAX) continue;       // 还没走出反向极值 → 腿未成形
         if(B == A) continue;                              // 零长度腿 → 投影无意义
         g_fibValid = true; g_fibA = A; g_fibB = B;
         g_fibRefBar = rb;  g_fibDir = g_curBias;
         break;
      }
   }
}

void ComputeCisdFvgFollow()
{
   if(InpCisdFvgLookahead <= 0) return;          // 0 = 关闭该条件

   for(int k = 0; k < g_result.nCISD; k++)
   {
      int b   = g_result.cisd[k].bar;
      int dir = g_result.cisd[k].dir;
      if(b < 0) continue;

      bool found = false;
      for(int v = 0; v < g_result.nFVG; v++)
      {
         if(g_result.fvg[v].dir != dir) continue;              // 必须**同向**
         int fb = g_result.fvg[v].bar;                         // FVG 的确认 bar（c3）
         if(fb <= b && fb >= b - InpCisdFvgLookahead) { found = true; break; }
      }

      // 后续窗口内没有同向缺口 → 该次 CISD 不符合第②条。
      //
      // ⚠️【v1.50-s58 缺陷修复】这里**必须双向赋值**，不能只写 `if(found) continue;` + 置真。
      //   旧实现只在"没找到"时写 `weak = true`，找到时直接 continue ⇒ `weak` 是**单向棘轮**：
      //   而本函数在事件创建（AddCisdResult/AddObResult 写 `weak = !strong`）**之后**运行，
      //   是 `weak` 的最后写入者 ⇒ 一个**已通过位移门槛的强 CISD**，只要后续 N 根内没有同向
      //   FVG，就被永久打成 weak，且**事后无法从 CSV 区分**"位移不足"与"缺后续 FVG"两种成因。
      //   后果不止观感：`weak` 是 CISD/OB 的**唯一质量色**（:5342 / :5498 的着色依据，
      //   见 CISD 渲染段的既定决策"CISD 不做 WEAK 分级，质量改以颜色区分"）——
      //   颜色这个唯一信号会被污染成"曾经弱过"。
      //
      //   语义定为：**本帧重算**后，`weak` 仍只表示"位移不足"（创建时写入的 !strong），
      //   本条②的结论写进**独立字段** `fvgFollow`（本帧双向赋值 ⇒ 不会棘轮）。
      //   渲染对 CISD/OB 取 `weak || !fvgFollow` —— 观感与旧实现等价，
      //   而 CSV 同时导出 weak 与 fvgFollow 两列，"这条为什么是弱的"从此可回溯。
      g_result.cisd[k].fvgFollow = found;
      for(int o = 0; o < g_result.nOB; o++)
      {
         if(g_result.ob[o].bar == b && g_result.ob[o].dir == dir)
         {
            g_result.ob[o].fvgFollow = found;
            break;                                             // OB 与 CISD 一一对应
         }
      }
   }
}

void ComputeStructure(const int rates_total,
                      const datetime &time[],
                      const double   &open[],
                      const double   &high[],
                      const double   &low[],
                      const double   &close[])
{
   g_result.nNodes = 0;
   g_result.nMSS   = 0;
   g_result.nCISD  = 0;
   g_result.nBOS   = 0;
   g_result.nBox   = 0;
   g_result.nFVG   = 0;
   g_result.nOB    = 0;
   g_result.nChoch = 0;
   // [v1.50-s59] nSWEEP / nClosure 原来只在各自计算函数首行自复位，而那两个函数在
   //   "有效 bar 不足"的早退路径上**根本不会被调用** ⇒ 该帧这两个计数保留上一帧旧值，
   //   而其余 8 个已被清零。后果有三：
   //     1) DbgReport 的无条件不变量检查会打出 closure=59 > nodes=0 的**假警报**，
   //        而这条不变量正是本文件认定"跨帧累加 bug"的唯一现场证据，假阳性会污染它；
   //     2) DumpEvents 每帧落盘时写出上一帧的 SWEEP/CLOSURE 行，其余 7 类全 0 ⇒ CSV 自相矛盾；
   //     3) 同帧 RenderScene 用这批陈旧事件调和对象。
   //   自复位逻辑保留也无害（同值重复写），这里补齐只是为了早退路径也得到干净状态。
   g_result.nSWEEP   = 0;
   g_result.nClosure = 0;
   // [v1.50-s59] armed CISD 是**跨帧**数据：全量帧写（见 g_armedCisd* 赋值处），
   //   快路径 tick 读它算 IC-CISD 实时预览。早退帧不刷新它，就必须清掉 ——
   //   否则预览会拿上一帧那个已经失效的 armed 位继续显示，而 insp 已归零。
   g_armedCisdHighValid = false;  g_armedCisdHighLevel = 0.0;  g_armedCisdHighBar = -1;
   g_armedCisdLowValid  = false;  g_armedCisdLowLevel  = 0.0;  g_armedCisdLowBar  = -1;
   g_dbgRaw = 0; g_dbgGap = 0; g_dbgRet = 0; g_dbgC = 0;
   g_dbgSeed = 0; g_dbgAddHigh = 0; g_dbgAddLow = 0; g_dbgSep = 0;

   //── 分析窗口：仅分析最近 InpAnalysisWindow 根 K 线（0=全量）──
   //  时序方向下，index 0 = 最新、index 递增 = 越旧。故「最近 W 根」是
   //  下标 [0, W-1]，窗口最旧 bar 的下标就是 W-1；随后 validBars 从
   //  W-1 递减到 0，正好得到「旧 → 新」的序列（与下面注释一致）。
   int analysisStart;
   if(InpAnalysisWindow > 0 && InpAnalysisWindow < rates_total)
      analysisStart = InpAnalysisWindow - 1;
   else
      analysisStart = rates_total - 1;               // 全量分析（最旧 bar）

   //── 内包过滤：构建有效 bar 序列 + 内包盒记录（旧→新）──
   // v1.48：只分配分析窗口大小（原来按 rates_total 分配，每次新 bar 多付一次
   //        数千元素的清零；5 万根图表上这是纯浪费）。boxRef 平行数组已删除
   //        —— 它被写入但从未被读取，属死代码。
   int winBars = analysisStart + 1;          // 参与分析的 bar 数
   int validBars[];
   ArrayResize(validBars, winBars);
   int nValid = 0;

   int mamaBar  = analysisStart;   // 第一个母线 = 分析窗口最旧 bar
   int boxStart = -1, boxEnd = -1;
   validBars[0] = mamaBar;
   nValid = 1;
   for(int i = analysisStart - 1; i >= 0; i--)
   {
      // 被当前母线完全包含 → 内包，忽略（但记录盒区间）
      if(high[i] <= high[mamaBar] && low[i] >= low[mamaBar])
      {
         if(boxStart < 0) boxStart = i;   // 最旧内包
         boxEnd = i;                      // 最新内包
         continue;
      }
      // 打破母线最高/最低 → 成为新母线；若中间存在内包段则记录盒
      validBars[nValid] = i;
      if(boxStart >= 0)
         AddBoxResult(mamaBar, boxStart, boxEnd, high[mamaBar], low[mamaBar]);
      nValid++;
      mamaBar  = i;
      boxStart = -1;
      boxEnd   = -1;
   }
   // [v1.50-s59 缺陷修复] 循环退出时仍挂着的内包段必须补记。
   //   AddBoxResult 原来只在"遇到新母线"分支里调用，于是最新母线之后的整串内包
   //   （即当前这段盘整，右端常态）被静默丢弃，屏幕上的盒永远是上一段，nBox 恒少 1。
   if(boxStart >= 0)
      AddBoxResult(mamaBar, boxStart, boxEnd, high[mamaBar], low[mamaBar]);
   g_dbgRates = rates_total;
   g_dbgNValid = nValid;
   if(nValid < 3)
   {
      // ⚠️【v1.50-s59】早退前必须把"逐帧派生全局"清零。
      //   理由：RenderScene 在本函数返回后**无条件**执行（OnCalculate:6013），而它无条件读
      //   g_relValid/g_erlValid/g_irlValid/g_pdValid/g_tgtCount/g_fibValid/g_curBias ——
      //   这些字段本帧没被重算，于是本帧会拿**上一帧**的价位去调和对象：调和出来的对象
      //   紧接着被同帧回收段删掉，而 STRUCT_RENDER/STRUCT_DBG 会打出 nodes=0 却 tgtCount>0、
      //   fibValid=1 —— 日志自相矛盾，恰好毁掉"功能是否在跑"那两行判据。
      //   触发很常见：图表刚加载（rates_total 刚过 4）时 nValid 必然 <3。
      g_curBias   = 0;
      g_relValid  = false;
      g_erlValid  = false;   g_irlValid  = false;   g_pdValid = false;
      g_tgtCount  = 0;       g_fibValid  = false;
      g_irlFvgIdx = -1;
      g_fibA = 0.0; g_fibB = 0.0; g_fibRefBar = -1; g_fibDir = 0;
      DbgReport(time, rates_total);
      return;
   }

   double atrArr[];
   CalcATRSeries(high, low, close, rates_total, analysisStart, atrArr);   // 每 bar 自己的 ATR（Wilder 平滑）
   double atrValue = atrArr[0];                                    // 供渲染标签偏移用
   g_curATR = atrValue;

   SState st;
   st.state            = 0;
   st.refHigh.bar      = 0;
   st.refHigh.price    = 0.0;
   st.refHigh.valid    = false;
   st.refHigh.broken   = false;
   st.refHigh.touched  = false;
   st.refLow.bar       = 0;
   st.refLow.price     = 0.0;
   st.refLow.valid     = false;
   st.refLow.broken    = false;
   st.refLow.touched   = false;
   st.lastIsHigh       = false;
   st.hasLast          = false;
   st.lastLeg          = 0.0;
   st.cisdHighLevel    = 0.0; st.cisdHighValid = false; st.cisdHighFired = false; st.cisdHighBar = -1;
   st.cisdLowLevel     = 0.0; st.cisdLowValid  = false; st.cisdLowFired  = false; st.cisdLowBar  = -1;
   st.cisdHighRunBar   = -1; st.cisdLowRunBar  = -1;

   // 阶段 2-②：bar → validBars 位置映射（-1 = 内包 K 线，未进入有效序列）。
   // 突破检测改为遍历分析窗口内**每一根** bar（含内包 K 线）；swing 逻辑仍只跑有效 bar。
   // 本步只改遍历结构、**不动任何判定条件** —— 验收判据是事件集合与改前一致。
   int validPos[];
   ArrayResize(validPos, analysisStart + 1);
   for(int q = 0; q <= analysisStart; q++) validPos[q] = -1;
   for(int q = 0; q < nValid; q++) validPos[validBars[q]] = q;

   for(int i = analysisStart; i >= 0; i--)
   {
      int k = validPos[i];

      // ── A. 外包 / 内包盒：仅用于盒区间记录（g_result.box 已在
      //    有效 bar 构建阶段填充，渲染矩形用）；不再独立触发 BOS/MSS ──
      //    BOS/MSS 唯一触发源 = A2 CheckBreakAgainstRefs（v1.37）

      // ── A2. 通用结构突破检测（每根 bar，不依赖 swing 确认）──
      //    返回值（1=趋势翻转的 MSS / 2=BOS）阶段 11 起不再被消费：
      //    它原先只用于 `mssBar` 门控（防止 MSS 当根用 swing 重建反向 ref），
      //    而 ref 现在只由 CheckCisd → SetProtectedFromCisd 写入，该门控已无对象。
      //    函数仍保留返回值以备将来使用（例如按事件类型分流诊断）。
      CheckBreakAgainstRefs(i, st, high, low, close, open, atrArr);
      CheckCisd(i, st, high, low, open, close, atrArr);

      // ── A3. 阶段 9：FVG（**物理相邻三根**，`v1.50-s46` 起；与 swing 确认无关）──
      //    放在下面的 guard 之前：最新 bar 上刚形成的缺口也应记录。
      //    ⚠️ 现在**每根 bar** 都可作 candle3（不再要求它在有效序列里），
      //       因为口径已改为物理相邻（内包 K 不再被跳过）。
      CheckFvg(i, high, low, close, atrArr);

      // 阶段 2-②：内包 K 线（k<0）只做上面的突破检测；首个/最后一个有效 bar
      // 无 prev/next，同样不进入 swing 逻辑。prevBar 必须在 guard 之后求值。
      if(k < 1 || k >= nValid - 1) continue;

      int prevBar = validBars[k - 1];   // 有效序列中更旧的一根（即母线）
      // ── B. fractal swing 确认（最新一根无 next，跳过）──
      int nextBar = validBars[k + 1];   // 有效序列中更新的一根

      bool isSwingHigh = (high[i] > high[prevBar] && high[i] > high[nextBar]);
      bool isSwingLow  = (low[i]  <  low[prevBar] && low[i]  <  low[nextBar]);
      if(isSwingHigh || isSwingLow) g_dbgRaw++;

      // ── B2. 相邻 swing 最小间隔过滤（滤除震荡区高频小折返）──
      if(InpMinBarsBetweenSwings > 0 && g_result.nNodes > 0)
      {
         int lastNodeBar = g_result.nodes[g_result.nNodes - 1].bar;
         // MQL5 series：新 bar 索引小（0=最新）、旧节点索引大 → 取绝对间隔
         if(MathAbs(lastNodeBar - i) < InpMinBarsBetweenSwings)
         {
            isSwingHigh = false;
            isSwingLow  = false;
         }
      }
      if(isSwingHigh || isSwingLow) g_dbgGap++;

      // ── C. 双 swing 互斥裁决（兜底；外包场景已在上方单独处理）──
      if(isSwingHigh && isSwingLow)
      {
         bool highMSS = (st.state == ST_DOWN && st.refHigh.valid && !st.refHigh.broken && high[i] > st.refHigh.price);
         bool highBOS = (st.state == ST_UP   && st.refHigh.valid && !st.refHigh.broken && high[i] > st.refHigh.price);
         bool lowMSS  = (st.state == ST_UP   && st.refLow.valid  && !st.refLow.broken  && low[i]  < st.refLow.price);
         bool lowBOS  = (st.state == ST_DOWN && st.refLow.valid  && !st.refLow.broken  && low[i]  < st.refLow.price);

         bool takeHigh;
         if(highMSS || lowMSS)      takeHigh = highMSS;      // MSS（反转）优先
         else if(highBOS || lowBOS) takeHigh = highBOS;      // 其次 BOS（延续）
         else                       takeHigh = !st.lastIsHigh; // 无事件：保持交替
         if(takeHigh) isSwingLow = false;
         else         isSwingHigh = false;
      }
      if(isSwingHigh || isSwingLow) g_dbgC++;

      // ── D. 有效回撤 / 最小 swing 幅度过滤（减少碎结构点）──
      if((InpEnableRetraceFilter || InpMinSwingAmplitude > 0) && InpMode != MODE_FRACTAL_SWING)
      {
         if(isSwingHigh)
         {
            double leg = LegFromLastNode(high[i], true, st);
            if(!IsValidRetrace(leg, atrArr[i], st.lastLeg)) isSwingHigh = false;
         }
         if(isSwingLow)
         {
            double leg = LegFromLastNode(low[i], false, st);
            if(!IsValidRetrace(leg, atrArr[i], st.lastLeg)) isSwingLow = false;
         }
         if(!isSwingHigh && !isSwingLow) continue;
      }
      if(isSwingHigh || isSwingLow) g_dbgRet++;
      // ── D1b. failure swing 剔除（阶段 1-B / 差异 D6a）──
      //  他的原话：failure swing "forms too close to a prior high or low and lacks
      //  proper range separation" → 忽略；"If it is too close, expect it to be taken."
      //  门槛是自定近似（他明说无数值公式），参数可调、0 = 关闭。
      if(InpMinSeparationATR > 0.0 && InpMode != MODE_FRACTAL_SWING)
      {
         if(isSwingHigh && atrArr[i] > 0.0 &&
            SeparationFromLastSameType(high[i], true, st) < InpMinSeparationATR * atrArr[i])
         {
            isSwingHigh = false;
            g_dbgSep++;
         }
         if(isSwingLow && atrArr[i] > 0.0 &&
            SeparationFromLastSameType(low[i], false, st) < InpMinSeparationATR * atrArr[i])
         {
            isSwingLow = false;
            g_dbgSep++;
         }
         if(!isSwingHigh && !isSwingLow) continue;
      }

      // ── D2. 主/内部结构判定 —— 【阶段 11 起已停用】
      //    原先由 `isMainSwing`（腿长 ≥1.0×ATR 或 ≥0.382×前段）筛选驱动 ref 的 swing。
      //    该门槛**不是他的定义**，也无任何一手依据；protected swing 已改由
      //    CISD 触发时建立（见 SetProtectedFromCisd）。
      //    相关输入项（InpUseMainFilter / InpMainFilterATR / InpMainFilterRatio）已移除。
      //    `isMain` 字段仍保留但恒为 true —— 见 plan §19.6-D30 的待议项。

      // ── E. 播种：第一个 swing 确定初始方向 ──
      if(st.state == 0)
      {
         g_dbgSeed++;
         if(isSwingHigh)
         {
            st.state            = ST_UP;
            st.refHigh.bar      = i;
            st.refHigh.price    = high[i];
            st.refHigh.valid    = true;
            st.refHigh.broken   = false;
            st.refHigh.touched  = false;
            AddNodeFiltered(i, high[i], true, st);
         }
         else if(isSwingLow)
         {
            st.state           = ST_DOWN;
            st.refLow.bar      = i;
            st.refLow.price    = low[i];
            st.refLow.valid    = true;
            st.refLow.broken   = false;
            st.refLow.touched  = false;
            AddNodeFiltered(i, low[i], false, st);
         }
         continue;
      }

      // ── F. swing 确认：只添加结构节点（+ 重设 CISD 位）──
      //    BOS/MSS 已由 A2 完成；
      //    ⚠️ 阶段 11 起**此处不再写 ref** —— 他的 protected swing 由 CISD 触发建立。
      //    旧的 `mssBar` 门控（避免 MSS 当根用 swing 重建反向 ref）随之失效：
      //    它防范的是"swing 驱动 ref"，而现在 ref 只由 CheckCisd 写入。
      if(isSwingHigh)
      {
         if(AddNodeFiltered(i, high[i], true, st, true))
         {
            g_dbgAddHigh++;
            CisdSetLevel(st, i, true, open, close, analysisStart);
         }
      }
      if(isSwingLow)
      {
         if(AddNodeFiltered(i, low[i], false, st, true))
         {
            g_dbgAddLow++;
            CisdSetLevel(st, i, false, open, close, analysisStart);
         }
      }
   }

   ClassifyNodeTiers();
   ComputeClosures(open, high, low, close, rates_total);  // 阶段 18a：需节点已定案，故后验
   ComputeChoch(high, low, open, close, rates_total);     // 阶段 30：同层次后验（借用 ICT 术语）
   ComputeSweeps(high, low, open, close);
   FillEventBias(time, rates_total);
   ComputeErlIrl(high, low, close);     // 阶段 10：依赖 g_curBias，故必须排在其后
   ComputeTargets(high, low, close, rates_total);  // 阶段 19：同层（依赖 g_curBias 与 close[0]）
   ComputeCisdFvgFollow();              // 阶段 12-d：需全部 FVG 已产生，故必须最后

   //── 阶段 16：把「武装中且**尚未触发**」的 CISD 位快照给渲染层/快路径 ──
   //  `st` 是本函数的局部状态机，渲染层看不见它。只导出 valid && !fired：
   //  收盘一旦真的触发，`*Fired` 置真 → 这里的 valid 自动变假 → IC-CISD 预览自行失效，
   //  不需要任何额外的清理逻辑（这正是"预览不会活过收盘"的机制本身）。
   g_armedCisdHighValid = (st.cisdHighValid && !st.cisdHighFired);
   g_armedCisdHighLevel = st.cisdHighLevel;
   g_armedCisdHighBar   = st.cisdHighBar;
   g_armedCisdLowValid  = (st.cisdLowValid && !st.cisdLowFired);
   g_armedCisdLowLevel  = st.cisdLowLevel;
   g_armedCisdLowBar    = st.cisdLowBar;
}

//══════════════════════════════════════════════════════════════════
//  场景层：对象生命周期（稳定 ID + 调和式同步，消除闪烁）
//══════════════════════════════════════════════════════════════════

// 对象名哈希（FNV-1a 变体，按 4 字符一块取，避免逐字符开销）。
// 用无符号运算：FNV 的常数 2166136261 超出 int 可表示的正数范围，
// 写成 int 会触发 "truncation of constant value" 告警。uint 是它的正确类型。
// 返回值转为 int 供下标运算 —— 最高位被掩码吃掉，不影响寻址。
int SceneHash(const string s)
{
   uint h = 2166136261;
   int  n = StringLen(s);
   for(int i = 0; i < n; i += 4)
   {
      h = (h ^ (uint)StringGetCharacter(s, i)) * 16777619;
      if(i + 1 < n) h = (h ^ (uint)StringGetCharacter(s, i + 1)) * 16777619;
      if(i + 2 < n) h = (h ^ (uint)StringGetCharacter(s, i + 2)) * 16777619;
      if(i + 3 < n) h = (h ^ (uint)StringGetCharacter(s, i + 3)) * 16777619;
   }
   return (int)h;
}

// 插入（容量不足时翻倍重建；容量由调用方按上一帧规模预估）
void SceneSetAdd(const string name)
{
   if(g_setUsed * 2 >= g_setMask + 1)      // 负载因子 >= 0.5 → 扩容
   {
      int newCap = (g_setMask + 1) * 2;
      string old[];
      ArrayResize(old, g_setMask + 1);
      for(int i = 0; i <= g_setMask; i++) old[i] = g_setKey[i];
      ArrayResize(g_setKey, newCap);
      if(ArraySize(g_setKey) != newCap)
      {
         // v1.50-s58：扩容失败 ⇒ 不变式 ArraySize(g_setKey)==g_setMask+1 已被破坏。
         //   不能用 return 了事（集合会停在"数组已缩、掩码未变"的错位状态，后续探测越界）；
         //   直接重建为干净状态，本帧集合略小但一定自洽。
         SceneSetRebuild();
         return;
      }
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
      if(g_setKey[h] == name) return;      // 已存在
      h = (h + 1) & g_setMask;
   }
   g_setKey[h] = name;
   g_setUsed++;
}

// 成员判定：O(1)（对比原 InScene 的 O(kept) 线性查表）
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

// 按需重建集合：容量跟随上一帧规模，避免反复扩容。
// 注意：先 ArrayResize 再按下标赋值 —— 对长度为 0 的动态数组做 g_setKey[0]=""
// 会触发 "array out of range" 运行时错误。
void SceneSetRebuild()
{
   if(g_setNextCap < 8) g_setNextCap = 8;
   ArrayResize(g_setKey, g_setNextCap);
   for(int i = 0; i < g_setNextCap; i++) g_setKey[i] = "";
   g_setMask  = g_setNextCap - 1;
   g_setUsed  = 0;
   g_setReady = true;
}

void AddSceneName(const string name)
{
   SceneSetAdd(name);
}

// 注：原 `InScene()`（`SceneHas()` 的无调用点包装）已于 v1.49-s15 删除。

//══════════════════════════════════════════════════════════════════
//  v1.48 渲染层说明（重要）
//
//  这里**不使用**任何"对象属性镜像缓存"。原因：
//   1. MQL5 文档明确说明，在当前图表上 ObjectGet*/ObjectName/ObjectsTotal
//      都是**直接访问**（只有跨图表才走同步队列），因此"先用镜像避免
//      ObjectGet*"这个前提从一开始就不成立 —— 镜像省不下什么。
//   2. 镜像引入了一整套额外状态（槽位分配、活跃区、压缩），实测中镜像被
//      压成 1 个槽位，导致除第一个外的所有结构线都建不出来。复杂度换来的
//      是负收益。
//  性能改由**门控**承担：needDraw 为假时根本不进入调和循环，因此
//  ObjectGet* 的调用次数天然被限制在"结构真的变了"的帧上。
//══════════════════════════════════════════════════════════════════

//+------------------------------------------------------------------+
//| 调和式线段（OBJ_TREND）：属性不变则不写                            |
//| 返回 true 表示创建或修改过（需要重绘）                             |
//+------------------------------------------------------------------+
bool UpsertLine(const string name,
                const datetime t1, const double p1,
                const datetime t2, const double p2,
                const color clr, const ENUM_LINE_STYLE style,
                const int width, const bool rayRight)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return false;   // v1.50-s58：创建失败 ⇒ 不算"已变更"（否则每帧重试 + 每帧重绘）
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  rayRight);
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
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      changed = true;
   }
   if((ENUM_LINE_STYLE)ObjectGetInteger(0, name, OBJPROP_STYLE) != style)
   {
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      changed = true;
   }
   if((int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != width)
   {
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      changed = true;
   }
   if((bool)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != rayRight)
   {
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
      changed = true;
   }
   return changed;
}

//+------------------------------------------------------------------+
//| 调和式文本（OBJ_TEXT）                                            |
//+------------------------------------------------------------------+
// 文本调和。anchor 默认 ANCHOR_LOWER（下中锚点：文字从 anchor 点向上生长），
// 既有调用方行为不变；BOS/MSS 需要"文字**压在**线正中"，故传 ANCHOR_CENTER。
// ⚠️ anchor 必须纳入调和判断 —— 与 UpsertRect 的 fill 同理，
//    只检查"是否新建"会漏掉"对象已存在但锚点仍是旧值"的情况。
bool UpsertText(const string name, const datetime t, const double price,
                const string text, const color clr,
                const ENUM_ANCHOR_POINT anchor = ANCHOR_LOWER)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price)) return false;   // v1.50-s58：创建失败 ⇒ 不算"已变更"（否则每帧重试 + 每帧重绘）
      ObjectSetString (0, name, OBJPROP_TEXT,     text);
      ObjectSetString (0, name, OBJPROP_FONT,     "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
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
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      changed = true;
   }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      changed = true;
   }
   if((ENUM_ANCHOR_POINT)ObjectGetInteger(0, name, OBJPROP_ANCHOR) != anchor)
   {
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      changed = true;
   }
   return changed;
}

//+------------------------------------------------------------------+
//| 调和式矩形（OBJ_RECTANGLE，内包盒）                               |
//+------------------------------------------------------------------+
// 矩形调和。fill=true 时填充区域（阶段 9：PD Array 上色）。
// ⚠️ MT5 的 OBJ_RECTANGLE **没有透明度**，且填充与边框共用 OBJPROP_COLOR ——
//    所以"半透明"只能靠两件事合成：① 填充色取暗一档的色调；② 保持 BACK=true
//    让矩形画在 K 线**之下**，蜡烛绘制在其上。故 PD Array 的填充色是独立输入。
bool UpsertRect(const string name, const datetime t1, const double p1,
                const datetime t2, const double p2, const color clr,
                const bool fill = false)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return false;   // v1.50-s58：创建失败 ⇒ 不算"已变更"（否则每帧重试 + 每帧重绘）
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DOT);
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
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      changed = true;
   }
   // 填充开关也纳入调和：只读"是否新建"会漏掉"已存在但填充状态相反"的对象。
   if((bool)ObjectGetInteger(0, name, OBJPROP_FILL) != fill)
   {
      ObjectSetInteger(0, name, OBJPROP_FILL, fill);
      changed = true;
   }
   return changed;
}

//+------------------------------------------------------------------+
//| 虚线终点计算（#4 终点模式）：                                     |
//|   FIRST_RETEST：事件 bar 之后第一根重新触及 ref 的 bar            |
//|     UP 事件看 low<=ref（回踩）；DOWN 事件看 high>=ref（反抽）     |
//|     未回踩则回退固定 N 根                                         |
//|   FIXED_BARS ：事件 bar 起固定 N 根                               |
//|   NEXT_NODE  ：原行为，到下一个结构节点或最右                     |
//+------------------------------------------------------------------+
datetime LineEnd(const int b, const int dir, const double base,
                 const int refBar, const int nextNode, const datetime &time[],
                 const double &high[], const double &low[])
{
   if(InpLineEnd == LINE_END_BREAK)
      return time[b];   // 标准：线 = refBar → breakBar，画在 refPrice
   if(InpLineEnd == LINE_END_HIT_ZIGZAG)
   {
      // 从被突破结构极值点（refBar，左）向右延伸，直到碰到结构折线为止：
      //   扫描结构折线段（相邻节点连线）与水平线 y=base 的交点，要求交点
      //   发生在 breakBar（b）之后（不早于突破 bar），且比 refBar 更右（时间更大）；
      //   找不到交点时回退到 breakBar（time[b]），不默认拉到最右 time[0]。
      datetime t0 = (refBar >= 0) ? time[refBar] : time[b];   // 起点时间（refBar 时间）
      datetime tB = time[b];                                  // break bar 时间
      datetime best = 0;
      bool     found = false;
      for(int n = 0; n < g_result.nNodes - 1; n++)
      {
         int    ba = g_result.nodes[n].bar;        // 段左端（更旧）
         int    bb = g_result.nodes[n + 1].bar;    // 段右端（更新）
         if(bb < 0 || ba < 0) continue;
         double pa = g_result.nodes[n].price;
         double pb = g_result.nodes[n + 1].price;
         if(pa == pb) continue;
         // 该段与水平线 y=base 相交：两端分别在 base 两侧
         if((pa <= base && pb >= base) || (pa >= base && pb <= base))
         {
            double frac   = (base - pa) / (pb - pa);
            int    hitBar = (int)MathRound(ba + (bb - ba) * frac);
            if(hitBar < 0) hitBar = 0;
            datetime ht = time[hitBar];
            if(ht >= tB && ht > t0)                // 交点在 breakBar 之后 + 更右
            {
               best = ht; found = true;
               break;                               // 取第一个向后交点
            }
         }
      }
      if(found) return best;
      return tB;                                    // 未找到：回退 break bar（不拉最右）
   }
   if(InpLineEnd == LINE_END_FIXED_BARS)
   {
      int endBar = b - InpLineEndBars;
      if(endBar < 0) endBar = 0;
      return time[endBar];
   }
   if(InpLineEnd == LINE_END_FIRST_RETEST)
   {
      for(int j = b - 1; j >= 0; j--)
      {
         if((dir == DIR_UP  && low[j]  <= base) ||
            (dir == DIR_DOWN && high[j] >= base))
            return time[j];
      }
      // 未回踩：回退固定 N 根
      int endBar = b - InpLineEndBars;
      if(endBar < 0) endBar = 0;
      return time[endBar];
   }
   // LINE_END_NEXT_NODE
   return (nextNode >= 0) ? time[nextNode] : time[0];
}

//+------------------------------------------------------------------+
//| 场景渲染：声明期望对象集合 → 调和 → 回收过期 → 条件重绘          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| PD Array 填充色派生：把轮廓色按百分比混向**图表实际底色**。          |
//|   fill = bg + (base − bg) × pct/100                                |
//| 这是"半透明"在**不透明填充**下的正确等价物 —— 因为 MT5 的          |
//| OBJ_RECTANGLE 没有 alpha 属性（`OBJPROP_ALPHA` 编译不过，已验证），  |
//| 所以"看起来像 α 不透明度"只能靠**预先算好混色结果**来实现。          |
//| ⚠️ 关键点：必须混向**实际底色**，不能假设黑底 ——                     |
//|   浅色底图上"往黑混"会让色块越压越暗，反而看不见。                  |
//| MT5 的 color 是 0x00BBGGRR，故通道提取为 &0xFF / >>8 / >>16。        |
//+------------------------------------------------------------------+
uint ClrR(const color c) { return ((uint)c)        & 0xFF; }
uint ClrG(const color c) { return (((uint)c) >> 8)  & 0xFF; }
uint ClrB(const color c) { return (((uint)c) >> 16) & 0xFF; }
color ClrMake(const uint r, const uint g, const uint b)
{
   return (color)(r | (g << 8) | (b << 16));
}
// 阶段 23：**百分比改为显式参数**。
//  ⚠️ 原实现只收 (base, bg)，内部固定读 `InpPDFillPercent` —— 于是 HTF 蜡烛那句
//     `PdFill(base, bg)` 实际用的是 **PD Array 的百分比**，`InpHtfBodyFill` 的**数值
//     从来没被用过**（只当 `>0` 的开关）。
//  发现方式：**数字自相矛盾** —— 导出头部写着 `htfBodyFillPct=25`，
//     但实测派生色 `RGB(190,228,198)` 恰是 **30%** 的混色（25% 应为 `201,233,208`）。
//  两处百分比互不相干，故必须各自显式传入，不能靠一个全局量。
color PdFill(const color base, const color bg, const int pct)
{
   if(pct <= 0 || pct >= 100) return base;      // 0=不填充（由调用方决定）；100=本色
   double a = pct / 100.0;
   uint r = (uint)MathRound((1.0 - a) * (double)ClrR(bg) + a * (double)ClrR(base));
   uint g = (uint)MathRound((1.0 - a) * (double)ClrG(bg) + a * (double)ClrG(base));
   uint b = (uint)MathRound((1.0 - a) * (double)ClrB(bg) + a * (double)ClrB(base));
   return ClrMake(r, g, b);
}

//══════════════════════════════════════════════════════════════════
//  阶段 16：IC-CISD（Early CISD / 收盘前临时 CISD）
//
//  触发条件与 CheckCisd **完全相同**，唯一差别是"当前价"：
//      正式 CISD  → 已收盘 bar 的 close[i]
//      IC-CISD    → 未收盘 bar 0 的 close[0]（= 最新报价）
//
//  ⚠️ 本组函数**一律只读**，不写任何状态字段：不置 cisdHighFired、不派生 OB、
//     不建立 protected swing。理由见输入组注释（他本人承认提前确认会出假信号）。
//══════════════════════════════════════════════════════════════════

// 求值：当前是否应当显示预览。dir=0 表示不显示。
void EvalEarlyCisd(const double &close[], int &dir, double &level, int &refBar)
{
   dir = 0; level = 0.0; refBar = -1;
   if(!InpShowEarlyCISD)          return;
   if(ArraySize(close) < 1)       return;

   // 两侧条件互为反面，同时成立需 CISD 位被反向穿越，极罕见；按 low 侧（看涨）优先。
   if(g_armedCisdLowValid && close[0] > g_armedCisdLowLevel)
   {
      dir = DIR_UP; level = g_armedCisdLowLevel; refBar = g_armedCisdLowBar;
   }
   else if(g_armedCisdHighValid && close[0] < g_armedCisdHighLevel)
   {
      dir = DIR_DOWN; level = g_armedCisdHighLevel; refBar = g_armedCisdHighBar;
   }
}

//+------------------------------------------------------------------+
//| 阶段 16 补（可观测性）：记账 IC-CISD 预览的**累计触发次数**        |
//|                                                                  |
//|  两个调用方（全量帧的 RenderScene 与快路径）都必须经过这里，且只有  |
//|  一个共享的"上一状态"（`g_icCountValid`）—— 否则两处各自计数会把   |
//|  同一次触发算两遍。                                                |
//+------------------------------------------------------------------+
void NoteIcState(const int dir)
{
   if(dir != 0)
   {
      if(!g_icCountValid) { g_icHits++; g_icCountValid = true; }
   }
   else g_icCountValid = false;
}

//+------------------------------------------------------------------+
//| 阶段 16 补：IC-CISD 是否落在**高周期 K 线的后段**。                |
//|  他："IC-CISD **early in a candle** tends to be the most powerful … When it happens **late**:
//  most of the candle range is already used … better to wait for the next candle."
//  ⚠️ 阈值他未给数值 → `InpIcLatePercent` 是自定近似（0 = 关闭标注）。
//  单独抽成函数是为了让**快路径**能在比对缓存前就得到该值 —— 否则 bar 内"由早转迟"不会刷新。
bool EvalIcLate()
{
   if(InpIcLatePercent <= 0) return false;
   long dur = (long)PeriodSeconds(EffCandleTF());
   if(dur <= 0) return false;
   datetime htfOpen = iTime(_Symbol, EffCandleTF(), 0);
   if(htfOpen <= 0) return false;
   long elapsed = (long)(TimeCurrent() - htfOpen);
   if(elapsed < 0) elapsed = 0;
   return ((double)elapsed * 100.0 / (double)dur >= (double)InpIcLatePercent);
}

// 绘制/更新预览对象。
//  registerScene：全量帧传 true（写场景集，回收段就不会误删）；
//                 快路径传 false（场景集只在全量帧有效，快路径不得写它）。
void SyncEarlyCisdObject(const datetime &time[], const bool registerScene, bool &changed)
{
   if(g_icValid == 0) return;   // 失效的清理分别由调用方负责（见各自注释）

   int refBar = (g_icRefBar >= 0) ? g_icRefBar : 0;
   datetime tEnd = time[0];
   if(tEnd <= time[refBar]) tEnd = time[refBar] + 60;  // 防御：右端必须晚于左端

   string nm  = OBJ_PREFIX + "IC_"    + IntegerToString(refBar);
   string lbl = OBJ_PREFIX + "ICLbl_" + IntegerToString(refBar);
   if(registerScene) { AddSceneName(nm); AddSceneName(lbl); }

   // 与正式 CISD 的区分：**点线**（正式为虚线）+ 亮紫。
   // 语义 = "未收盘的临时判断"，视觉上必须一眼看得出弱于正式线。
   if(UpsertLine(nm, time[refBar], g_icLevel, tEnd, g_icLevel,
                 InpColorEarlyCISD, STYLE_DOT, 1, false)) changed = true;

   double labelPrice = (g_icValid == DIR_UP) ? g_icLevel + g_curATR * 0.15
                                             : g_icLevel - g_curATR * 0.15;
   if(g_curATR <= 0.0) labelPrice = g_icLevel;

   // 阶段 16 补：他区分 "early in a candle"（最强）与 "late"（应等下一根）。
   //  ⚠️ 这是**自定近似**：他用的是定性表述，未给数值阈值（见输入组注释）。
   g_icLate = EvalIcLate();
   color  lblClr = g_icLate ? InpColorWeakBreak : InpColorEarlyCISD;
   string tag    = g_icLate ? "IC-CISD (late)" : "IC-CISD";
   if(UpsertText(lbl, time[0], labelPrice, tag, lblClr)) changed = true;

   g_icName    = nm;
   g_icLblName = lbl;
}

// 显式删除预览对象（快路径用）。返回是否真的删掉了东西。
bool DeleteEarlyCisdObjects()
{
   bool any = false;
   if(g_icName != "" && ObjectFind(0, g_icName) >= 0)      { ObjectDelete(0, g_icName);    any = true; }
   if(g_icLblName != "" && ObjectFind(0, g_icLblName) >= 0){ ObjectDelete(0, g_icLblName); any = true; }
   g_icName = ""; g_icLblName = "";
   return any;
}

// 快路径（每 tick）：只在**状态真的翻转**时碰对象，其余 tick 零对象调用。
void UpdateEarlyCisdFast(const datetime &time[], const double &close[])
{
   int dir; double level; int refBar;
   EvalEarlyCisd(close, dir, level, refBar);
   NoteIcState(dir);   // 累计计数：必须在下面任何 early-return **之前**，否则会漏计

   // "早/迟"必须在比对缓存**之前**求值：bar 内"由早转迟"时 dir/level/refBar 都没变，
   // 若不含它，标签会一直停在 "IC-CISD" 而不切成 "(late)"。
   bool late = EvalIcLate();

   if(dir == g_icFastValid && level == g_icFastLevel && refBar == g_icFastRefBar &&
      late == g_icFastLate)
      return;                                  // 未变 → 一次对象调用都不做

   bool changed = DeleteEarlyCisdObjects();    // 换边/换位/失效都先清旧的
   g_icFastValid = dir; g_icFastLevel = level; g_icFastRefBar = refBar;
   g_icFastLate  = late;
   g_icValid = dir; g_icLevel = level; g_icRefBar = refBar;

   if(dir != 0) SyncEarlyCisdObject(time, false, changed);

   if(changed) ChartRedraw();
}

//══════════════════════════════════════════════════════════════════
//  阶段 17：HTF 蜡烛叠加
//══════════════════════════════════════════════════════════════════

// 指纹混合：h*31 + v（用它而不是乘法是为了让溢出行为可预期 —— 只是个指纹）
long HtfMix(long h, long v)
{
   return (h << 5) - h + v;
}

// 计算"集合级"指纹。⚠️ 刻意**不含**正在形成那根的 OHLC ——
//   它每 tick 都变，进指纹就会每 tick 触发整段调和（v1.48 专门消除的性能陷阱）。
void ComputeHtfFingerprint()
{
   g_htfT0  = 0;
   g_htfSig = 0;
   if(!InpShowHTFCandles || InpCandleCount <= 0) return;

   datetime t0 = iTime(_Symbol, EffCandleTF(), InpHtfShift);
   if(t0 == 0) return;                       // HTF 历史未就绪 → 降级为不叠加
   g_htfT0 = t0;

   long sig = 0;
   for(int k = 1; k < InpCandleCount; k++)
   {
      int idx = k + InpHtfShift;             // Offset 必须与 DrawHtfCandles 用同一套下标
      if(idx < 0) continue;
      datetime tk = iTime(_Symbol, EffCandleTF(), idx);
      if(tk == 0) break;
      sig = HtfMix(sig, (long)tk);
      sig = HtfMix(sig, (long)MathRound(iOpen (_Symbol, EffCandleTF(), idx) / _Point));
      sig = HtfMix(sig, (long)MathRound(iHigh (_Symbol, EffCandleTF(), idx) / _Point));
      sig = HtfMix(sig, (long)MathRound(iLow  (_Symbol, EffCandleTF(), idx) / _Point));
      sig = HtfMix(sig, (long)MathRound(iClose(_Symbol, EffCandleTF(), idx) / _Point));
   }
   g_htfSig = sig;
}

// 画一根高周期蜡烛（实体矩形 + 上下影线）。几何量全部由调用方给出，
// 以便全量帧（自己取数）与快路径（用缓存比对过的那组值）共用同一段绘制代码。
//| 阶段 25：右侧留白区 —— 每根蜡烛占多少秒（像素实测；条数公式兜底）    |
//|                                                                  |
//|  主口径 = **像素实测**（函数内①）：pxPerBar 由最新两根图 bar 的屏幕    |
//|  像素差得到；留白区 =「最新 bar 右缘」到「窗口右缘」，把              |
//|  InpCandleCount 根均分它 → 无论怎么缩放都恰好铺满、不越界。           |
//|  兜底 = 条数公式 `visBars × shift/(100−shift)`（②，图表未布局时）。    |
//|  ⚠️ 需要用户开启 Chart Shift（本指标在右侧模式下会自动开，见 OnInit）。 |
//+------------------------------------------------------------------+
long HtfRightSlotSec()
{
   int n = InpCandleCount; if(n < 1) n = 1;
   long ps = (long)PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   if(ps <= 0) ps = 60;

   // ① 像素实测：把"最新图 bar"和"上一根"映射到屏幕像素，得到每根 bar 占多少像素，
   //   则 x0 + pxPerBar = 最新 bar 的**右缘** = 留白区左界，w 是右界。
   //  ⚠️ 为什么不用 `visBars × shift/(100−shift)` 起手：那个公式依赖
   //    "CHART_VISIBLE_BARS 是否已含留白区"这一**未文档化**的语义，
   //    差一个常数就会让整排蜡烛整体偏出可见区，而且错法看起来"像画不出来"。
   //    像素是直接测量，不依赖任何语义假设。
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime tp = iTime(_Symbol, PERIOD_CURRENT, 1);
   double   c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(t0 > 0 && tp > 0 && c0 > 0.0 && w > 50)
   {
      int x0 = 0, y0 = 0, xp = 0, yp = 0;
      bool ok0 = ChartTimePriceToXY(0, 0, t0, c0, x0, y0);
      bool okp = ChartTimePriceToXY(0, 0, tp, c0, xp, yp);
      int pxPerBar = (ok0 && okp) ? (x0 - xp) : 0;
      if(pxPerBar > 0)
      {
         int marginPx = w - (x0 + pxPerBar);        // 跳过正在形成的那根
         if(marginPx > 0)
         {
            long slotPx = (long)(((double)marginPx / (double)n) / (double)pxPerBar * (double)ps);
            if(slotPx < ps) slotPx = ps;            // 至少一根图 bar 宽，免得退化成看不见的细缝
            g_htfPxPerBar = pxPerBar;
            g_htfMarginPx = marginPx;
            // 整排宽 = pxPerBar(正在形成那根) + n*slotPx；右缘 = 整排右端映射到屏幕的 x。
            long rowPx = (long)pxPerBar + (long)n * slotPx;
            int  edgePx = -1; int exTmp = 0, eyTmp = 0;
            datetime tEndRow = (datetime)((long)t0 + ps + (long)n * slotPx);   // 与放置端公式一致
            if(ChartTimePriceToXY(0, 0, tEndRow, c0, exTmp, eyTmp)) edgePx = exTmp;
            HtfLogSlot(slotPx, 1, (int)(marginPx / n),
                       (pxPerBar > 0 ? (double)marginPx / (double)pxPerBar : 0.0),
                       pxPerBar, (int)rowPx, edgePx);
            return slotPx;
         }
      }
   }

   // ② 兜底：像素法拿不到（图表尚未布局 / 无 Chart Shift）→ 退回条数公式
   int vis = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   double sh = ChartGetDouble(0, CHART_SHIFT_SIZE);   // ⚠️ double 属性，不是 integer
   if(vis < 10) vis = 10;
   if(sh  < 1.0)  sh  = 1.0;
   if(sh  > 50.0) sh  = 50.0;
   double marginBars = (double)vis * sh / (100.0 - sh) - 1.0;   // 同样跳过正在形成的那根
   if(marginBars < 1.0) marginBars = 1.0;
   long slot = (long)(marginBars * (double)ps / (double)n);
   if(slot < ps) slot = ps;
   g_htfPxPerBar = 0;
   g_htfMarginPx = -1;
   HtfLogSlot(slot, 2, 0, marginBars, 0, -1, -1);   // 像素路径不可用时右缘无从对账
   return slot;
}

// 留白区宽度变化时打一行 —— 这是"蜡烛没画出来"与"画到屏幕外"的唯一可分辨证据。
void HtfLogSlot(const long slot, const int src, const int slotPx,
                 const double marginBars, const int pxPerBar,
                 const int rowWidthPx, const int chartEdgePx)
{
   // 节流：槽宽 / 每 bar 像素 / 右缘 任一变化就重打一行。
   if(g_htfLogSlot == slot && g_htfLogPxPerBar == pxPerBar
      && g_htfLogRowEdgePx == chartEdgePx) return;
   g_htfLogSlot      = slot;
   g_htfLogPxPerBar  = pxPerBar;
   g_htfLogRowEdgePx = chartEdgePx;
   // [v1.50-s59] 对账：放置端把最右那根画在 tBase + ps + n*slot，故整排像素宽
   //   = ps + n*slot = pxPerBar + n*slotPx；可用宽 = marginPx。右缘超过图表宽即溢出。
   //   这一行就是"像素路径与兜底公式对多出的一个 ps 扣减约定相反"的定案证据。
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   PrintFormat("STRUCT_HTFPOS slot=%ds candles=%d src=%d pxPerBar=%d marginPx=%d slotPx=%d "
               "shiftOn=%s shiftSize=%.1f visBars=%d | marginBars=%.2f rowPx=%d chartW=%d "
               "edgePx=%d %s",
               (int)slot, InpCandleCount, src, g_htfPxPerBar, g_htfMarginPx, slotPx,
               (ChartGetInteger(0, CHART_SHIFT) ? "true" : "false"),
               ChartGetDouble(0, CHART_SHIFT_SIZE),
               (int)ChartGetInteger(0, CHART_VISIBLE_BARS),
               marginBars, rowWidthPx, chartW,
               chartEdgePx,
               (chartEdgePx < 0 ? "PIXEL-PATH-UNAVAILABLE"
                                : (chartEdgePx > chartW ? "OVERFLOW: row exceeds chart width"
                                                        : "fits")));
}

void DrawHtfCandleGeom(const datetime t1, const datetime t2,
                       const datetime keyTime,
                       const double o, const double h,
                       const double l, const double c,
                       const bool registerScene, bool &changed)
{
   if(h <= 0.0 || l <= 0.0 || t2 <= t1) return;

   // 实体左右各内缩 (100 − width)/2 %；影线宽度不内缩（贴在时间跨度正中）
   int wpct = InpCandleWidthPct;
   if(wpct < 1)   wpct = 1;
   if(wpct > 100) wpct = 100;
   long span = (long)t2 - (long)t1;
   long pad  = (long)((double)span * (100 - wpct) / 200.0);
   datetime tb1  = (datetime)((long)t1 + pad);
   datetime tb2  = (datetime)((long)t2 - pad);
   if(tb2 <= tb1) { tb1 = t1; tb2 = t2; }
   datetime tMid  = (datetime)(((long)t1 + (long)t2) / 2);
   datetime tMid2 = tMid + 1;   // OBJ_TREND 两点不能同时刻；差 1 秒在图上即竖线

   bool  up   = (c >= o);
   color base = up ? InpColorHtfUp : InpColorHtfDn;
   // ⚠️ OBJ_RECTANGLE 没有透明度（v1.49-s14 已编译证实）。实体"透明度"只能靠
   //    PdFill 按**图表实际底色**混出实色，并靠 OBJPROP_BACK 画在 K 线之下。
   //    影线用同一个混色，保证实体与影线的观感强度一致。
   color bg   = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   bool  doFill = (InpHtfBodyFill > 0);
   color drawClr = doFill ? PdFill(base, bg, InpHtfBodyFill) : base;

   // ⚠️ 对象名用**蜡烛真实的开盘时间**（keyTime）做键，**不是**画出来的 t1。
   //    右侧模式下一缩放 t1 就变；若拿 t1 当键，每次缩放都会让整排对象被判为"过期"
   //    而全量重建 —— 既抖动又白白多几百次对象操作。
   //    其余理由同前：这是固定根数的实时层，k 永远覆盖「最近 N 根」，
   //    新 bar 到来时各对象只是换坐标，不存在"过期对象需要回收"的情形。
   string key = IntegerToString((long)keyTime);
   string nmB = OBJ_PREFIX + "HTF_B_" + key;
   string nmU = OBJ_PREFIX + "HTF_U_" + key;
   string nmD = OBJ_PREFIX + "HTF_D_" + key;
   if(registerScene) { AddSceneName(nmB); AddSceneName(nmU); AddSceneName(nmD); }

   double bodyHi = MathMax(o, c);
   double bodyLo = MathMin(o, c);

   if(UpsertRect(nmB, tb1, bodyHi, tb2, bodyLo, drawClr, doFill)) changed = true;
   if(UpsertLine(nmU, tMid, h, tMid2, bodyHi, drawClr, STYLE_SOLID, 2, false)) changed = true;
   if(UpsertLine(nmD, tMid2, bodyLo, tMid, l, drawClr, STYLE_SOLID, 2, false)) changed = true;

   // 时间标签（他指标的一项：research §9 "time labels"）。
   //   放在蜡烛**下方**（ANCHOR_UPPER 使其挂在锚点之下），颜色与实体一致。
   if(InpHtfTimeLabels)
   {
      string nmT = OBJ_PREFIX + "HTF_T_" + key;
      if(registerScene) AddSceneName(nmT);
      double lblY = (g_curATR > 0.0) ? (l - g_curATR * 0.35) : (l - _Point * 30.0);
      if(UpsertText(nmT, tMid, lblY, TimeToString(keyTime, TIME_MINUTES),
                    drawClr, ANCHOR_UPPER)) changed = true;
   }
}

// 全量帧：画最近 InpCandleCount 根（含正在形成的那根）。
//  阶段 25：改为收 `tBase`（= 最新图表 bar 的时间）而非整个 time 数组 ——
//  这样**缩放事件**（OnChartEvent，手上没有 time 数组）也能复用同一段绘制。
void DrawHtfCandles(const datetime tBase, const bool registerScene, bool &changed)
{
   if(!InpShowHTFCandles || InpCandleCount <= 0) return;

   for(int k = 0; k < InpCandleCount; k++)
   {
      int idx = k + InpHtfShift;             // Offset：整体左移 N 根（与指纹同一套下标）
      if(idx < 0) continue;
      datetime tReal = iTime(_Symbol, EffCandleTF(), idx);
      if(tReal == 0) break;                  // 历史未就绪 → 不画、不报错
      double o = iOpen (_Symbol, EffCandleTF(), idx);
      double h = iHigh (_Symbol, EffCandleTF(), idx);
      double l = iLow  (_Symbol, EffCandleTF(), idx);
      double c = iClose(_Symbol, EffCandleTF(), idx);
      if(h <= 0.0 || l <= 0.0) break;

      datetime t1, t2;
      if(InpHtfPlacement == HTF_PLACE_RIGHT)
      {
         // 右侧留白区：均分留白宽度。**左→右 = 由旧到新**（与主图时间轴同向）：
         //  k=0 是正在形成的那根 → **最右槽**；最旧的 → 最左槽。
         //  ⚠️ 第一版曾反过来（最新贴价格、越旧越靠右），被用户一眼判为"顺序反了" ——
         //    因为时间标签会**从右往左递减**，而图上其它一切都从左往右递增。
         // 留白区从**最新图 bar 的右缘**开始（+1 根图 bar），避免压住正在形成的那根
         int n = InpCandleCount; if(n < 1) n = 1;
         long ps = (long)PeriodSeconds((ENUM_TIMEFRAMES)_Period);
         if(ps <= 0) ps = 60;
         t1 = (datetime)((long)tBase + ps + (long)(n - 1 - k) * g_htfSlot);
         t2 = (datetime)((long)t1 + g_htfSlot);
      }
      else
      {
         t1 = tReal;
         if(idx == 0)
         {
            t2 = tBase;                      // 正在形成的那根：右端到最新图表 bar
            if(t2 <= t1) t2 = t1 + PeriodSeconds(EffCandleTF()) / 2;
         }
         else
         {
            // idx>0：右端 = 更新那根的开盘时间（= 本根收盘时间）。
            // ⚠️ 不用 t1 + PeriodSeconds 硬推 —— D1 有周末缺口，会画出比实际更宽的蜡烛。
            t2 = iTime(_Symbol, EffCandleTF(), idx - 1);
            if(t2 <= t1) t2 = t1 + PeriodSeconds(EffCandleTF()) / 2;
         }
      }
      // keyTime 一律传**真实开盘时间**：对象名不能随缩放的坐标漂移
      DrawHtfCandleGeom(t1, t2, tReal, o, h, l, c, registerScene, changed);
   }
}

// 快路径：只刷新"正在形成的那根"。缓存比对，未变即零对象调用。
void UpdateHtfLastFast(const datetime &time[])
{
   if(!InpShowHTFCandles || InpCandleCount <= 0) return;
   // Offset > 0 时画的全是**已收盘**的高周期 K 线，bar 内不会变 → 快路径无事可做。
   if(InpHtfShift != 0) return;

   datetime tHtf = iTime(_Symbol, EffCandleTF(), 0);
   if(tHtf == 0) return;
   double o = iOpen (_Symbol, EffCandleTF(), 0);
   double h = iHigh (_Symbol, EffCandleTF(), 0);
   double l = iLow  (_Symbol, EffCandleTF(), 0);
   double c = iClose(_Symbol, EffCandleTF(), 0);

   datetime t1, t2;
   if(InpHtfPlacement == HTF_PLACE_RIGHT)
   {
      // 阶段 25：右侧留白模式下"正在形成的那根"占**最右槽位**（左→右 = 由旧到新）。
      //  槽位宽度由留白区宽度决定（g_htfSlot），而不是 HTF 周期长度。
      datetime tNow = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(tNow == 0) return;
      long ps = (long)PeriodSeconds((ENUM_TIMEFRAMES)_Period);
      if(ps <= 0) ps = 60;
      // ⚠️ 改参数会触发 OnDeinit→OnInit（同一实例，static 变量**保留**），
      //  于是本 tick 可能带着 placement=RIGHT 但 g_htfSlot 还是 0（全量帧尚未跑）。
      //  不补算的话 t2==t1 → 退化几何 → 直接被 DrawHtfCandleGeom 丢掉，
      //  用户会看到"切到右侧模式后一根蜡烛都没有，直到下一根新 bar"。
      if(g_htfSlot <= 0) g_htfSlot = HtfRightSlotSec();
      int n = InpCandleCount; if(n < 1) n = 1;
      t1 = (datetime)((long)tNow + ps + (long)(n - 1) * g_htfSlot);
      t2 = (datetime)((long)t1 + g_htfSlot);
   }
   else
   {
      t1 = tHtf;
      t2 = time[0];
      if(t2 <= t1) t2 = t1 + PeriodSeconds(EffCandleTF()) / 2;
   }

   // 死区（与 UpdateLiveLeg 同一思路）：收盘价位移小于 0.1×ATR 且高低点未变时不动图表，
   // 否则活跃行情下每 tick 都要付 3 次 Upsert 的对象属性比对。
   double band = (g_curATR > 0.0) ? g_curATR * 0.1 : 0.0;
   // v1.50-s58：**开盘价必须参与判据** —— 原实现只比 h/l/c，且把 o 写进了一个从无读取的缓存
   //   （g_htfC0O 曾是死存储）。新 HTF K 线开出时 h/l 常与上一根相等，于是"只变了 open"被静默吞掉，
   //   实体按上一根的 open 绘制（右侧留白模式下 t1/t2 不随换根变化，整条早退会成立）。
   bool   moved = (o != g_htfC0O) || (h != g_htfC0H) || (l != g_htfC0L) ||
                  (MathAbs(c - g_htfC0C) >= band);
   if(t1 == g_htfC0T0 && t2 == g_htfC0T1 && !moved) return;

   g_htfC0T0 = t1; g_htfC0T1 = t2;
   g_htfC0O = o; g_htfC0H = h; g_htfC0L = l; g_htfC0C = c;

   bool changed = false;
   DrawHtfCandleGeom(t1, t2, tHtf, o, h, l, c, false, changed);   // 快路径不写场景集
   if(changed) ChartRedraw();
}

//+------------------------------------------------------------------+
//| 阶段 21：算 PD Array（FVG / OB）区域矩形的**右端**时间              |
//|                                                                  |
//|  anchorBar = 矩形左端锚定的 bar（FVG 的 c1 / OB 的造势最旧 rb）      |
//|  validBar  = 该区域**成立**的 bar（FVG 的确认 bar / OB 的验证 bar）—— |
//|              回踩与固定长度都从它之后算起，否则会数到形成期自己的 K 线 |
//|                                                                  |
//|  ⚠️ 右端必须晚于左端：`OBJ_RECTANGLE` 两端同刻是退化矩形，画不出来。  |
//|  ⚠️ 本函数**只影响画多长**，不参与任何判定、也不改 CSV 的任何行。     |
//+------------------------------------------------------------------+
datetime PdRightEnd(const int anchorBar, const int validBar,
                    const double zLo, const double zHi,
                    const datetime &time[], const double &high[], const double &low[])
{
   int vb = validBar;
   if(vb < 0) vb = anchorBar;
   datetime t = time[0];

   if(InpPDEnd == PD_END_FIXED)
   {
      int n = InpPDRightBars;
      if(n < 0) n = 0;
      int back = vb - n;                 // 序列方向：index 更小 = 更新
      if(back < 0) back = 0;
      t = time[back];
   }
   else if(InpPDEnd == PD_END_RETEST)
   {
      // 首次"回到区间内"：该 bar 的高低区间与缺口区间相交即算触及
      int hit = -1;
      for(int i = vb - 1; i >= 0; i--)
      {
         if(low[i] <= zHi && high[i] >= zLo) { hit = i; break; }
      }
      if(hit < 0) return time[0];        // 从未被回踩 → 与 PD_END_NOW 同（它仍是有效 POI）
      // ⚠️ 必须给**最小宽度**：回踩完全可能就发生在下一根，那样矩形会退化成
      //    一条几乎看不见的细缝 —— 降噪降过头等于把功能删了。
      //    序列方向 index 越小越新，故"更宽"= 更小的 index；取两者中更宽的那个。
      int floorIdx = vb - InpPDRightBars;
      if(floorIdx < 0) floorIdx = 0;
      if(hit > floorIdx) hit = floorIdx;
      t = time[hit];
   }

   if(t <= time[anchorBar]) t = time[anchorBar] + 60;   // 防退化矩形
   return t;
}

//+------------------------------------------------------------------+
//| 墓碑：阶段 29 曾在此加入 `WeakTag()`（弱化的 BOS/MSS 也打标签，     |
//| 后缀 `(w)`/`(b)`/`(wb)`）。                                        |
//| ⚠️ 该功能已于**阶段 31（`v1.50-s41`）按用户要求整体删除**，恢复到     |
//|    v1.49 G1 的观感：**弱化 = 暗色点线 + 无标签**。                  |
//| 留这行墓碑是为了避免以后有人再以"补全观感"为由把它加回来 ——         |
//| 它被加过、也被删过；当时的实测数据与取舍见 plan §52 与 §55。          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 阶段 33：某结构位是否已被**会画出来**的 MSS/BOS 标注过              |
//|                                                                  |
//|  用途：CHoCH 与 MSS 完全可能落在**同一个 swing 位**上（甚至同一根   |
//|  bar）—— 两者都是"逆势破位"的相邻定义、判据不同，但 `ref` 可能来自   |
//|  同一个节点。真叠在一起时，两条同价位点线 + 两个标签（`MSS` 与      |
//|  `CHoCH`）互相压住，既读不出也难看。                               |
//|                                                                  |
//|  ⇒ 规则：**同一结构位若已有会显示的 MSS/BOS，CHoCH 让位**。          |
//|  ⚠️ "会显示"必须按**实际渲染筛选**判定（`InpShowMSS/BOS`、          |
//|     `mssFrom/bosFrom` 截断、`InpHideWeakBreaks`、窗口左界）。        |
//|     若只看"存在过的 MSS"，一个已被隐去的弱 MSS 会把 CHoCH 一起挡掉， |
//|     那个位就**什么都不剩** —— 正是 §53/§54 要补的盲区。              |
//|  ⚠️ 只影响**画不画**：CSV 里 CHOCH 行照旧导出（重叠事实仍可复盘）。   |
//+------------------------------------------------------------------+
bool LevelMarkedByBreak(const int refBar, const datetime &time[], const datetime tStart)
{
   if(refBar < 0) return false;
   // ⚠️【v1.50-s45 规则调整】判据从"**会显示**的 MSS/BOS"改为"**存在**的 MSS/BOS"
   //   （不再看 weak / InpHideWeakBreaks）。理由：阶段 32 已定"弱事件完全不画"，
   //   若节点级标记还在同一个位上顶上来，等于**把刚隐去的弱判断换个名字显示出来**。
   //   引擎的判断优先（他是逐字口径），同一结构位只留一个标记。
   //   仍保留的两道筛选：族开关（InpShowMSS/BOS）与**窗口左界** —— 后者不能去，
   //   否则一个画不出屏幕的引擎事件会把屏幕内的节点级标记也挡掉。
   if(InpShowMSS)
   {
      int fromM = (InpMaxEvents > 0 && g_result.nMSS > InpMaxEvents)
                  ? g_result.nMSS - InpMaxEvents : 0;
      for(int k = fromM; k < g_result.nMSS; k++)
      {
         if(g_result.mss[k].refBar != refBar) continue;
         if(time[g_result.mss[k].bar] < tStart) continue;
         return true;
      }
   }
   if(InpShowBOS)
   {
      int fromB = (InpMaxEvents > 0 && g_result.nBOS > InpMaxEvents)
                  ? g_result.nBOS - InpMaxEvents : 0;
      for(int k = fromB; k < g_result.nBOS; k++)
      {
         if(g_result.bos[k].refBar != refBar) continue;
         if(time[g_result.bos[k].bar] < tStart) continue;
         return true;
      }
   }
   return false;
}

void RenderScene(const int rates_total, const datetime &time[],
                 const double &high[], const double &low[], const double &close[])
{
   bool changed = false;
   // 注：曾有一个 `g_gfxDirty` 标志，注释称"帧内任何写操作会重新置位"。
   //     实测全文只有一处写入，且紧邻 `changed = true` —— 即 `changed || g_gfxDirty` ≡ `changed`。
   //     它是 v1.48 被否决的"对象属性镜像缓存"方案的残留，已删除（含那两处失实注释）。

   int winStart = InpWindow - 1;              // 窗口 = 最新 InpWindow 根
   if(winStart > rates_total - 1) winStart = rates_total - 1;
   datetime tStart = time[winStart];

   //── 阶段 16/17：两个新可视化元素的**期望状态**必须在这里算 —— 
   //   它们要进下面的 needDraw 指纹，故必须在比较之前写入全局。
   //   （硬约定 3：新增可视化元素必须同步指纹，否则"要等下一根 bar 才出现"。）
   EvalEarlyCisd(close, g_icValid, g_icLevel, g_icRefBar);
   NoteIcState(g_icValid);   // 与快路径共用同一份"上一状态"，避免同一次触发被计两遍
   ComputeHtfFingerprint();
   // 阶段 25：槽宽必须在指纹比较**之前**算好 —— 它进指纹（缩放时整排蜡烛要重排）
   g_htfSlot = (InpShowHTFCandles && InpHtfPlacement == HTF_PLACE_RIGHT) ? HtfRightSlotSec() : 0;

   //── v1.48 性能：窗口左边界横移检测 ──
   //  Upsert* 比镜像即可判断"属性未变"，但窗口横移会改变"哪些对象该存在"：
   //  左边界右移 → 旧段/旧盒该被回收（回收循环会处理，changed=true）；
   //  左边界左移（加载历史）→ 期间的对象从未创建过，但镜像里没有它们的槽位，
   //  Upsert* 的慢路径会因 isNew 而创建。故两种方向都不需要额外标记，
   //  这里仅记录边界用于诊断；横移本身由回收循环与慢路径自然覆盖。
   g_drawnFrom = tStart;

   // 文本标签垂直偏移（v1.48：改为惰性求值）。
   //  dashStep 只在 g_curATR <= 0 时作为兜底使用，而 ChartGetDouble 是到终端
   //  的跨进程调用。原实现无条件每帧取两次，绝大多数帧的结果被直接丢弃。
   //  注：MQL5 没有短路求值，所以必须用 if 包住，不能写成三元表达式。

   //══════════════════════════════════════════════════════════════════
   //  v1.48 绘制门控：先把"是否需要重画"算清楚（全部 O(1)/O(n) 内存比较），
   //  不需要就整段跳过 —— 连对象名的构造与属性比对都不做。
   //══════════════════════════════════════════════════════════════════
   int nodesTotal = g_result.nNodes;
   int curLastBar = (nodesTotal > 0) ? g_result.nodes[nodesTotal - 1].bar : -1;

   // 第一个落在绘制窗口内的节点下标（窗口左侧的节点不画）
   int beginNode = nodesTotal;
   for(int n = 0; n < nodesTotal; n++)
   {
      if(time[g_result.nodes[n].bar] >= tStart) { beginNode = n; break; }
   }

   // 最新一个落在窗口内的内包盒下标（盒渲染只取最新那个）
   int boxIdx = -1;
   for(int n = g_result.nBox - 1; n >= 0; n--)
   {
      int e = g_result.box[n].end;
      if(e >= 0 && time[e] >= tStart) { boxIdx = n; break; }
   }

   int mssFrom = (InpMaxEvents > 0 && g_result.nMSS > InpMaxEvents)
                 ? g_result.nMSS - InpMaxEvents : 0;
   int bosFrom = (InpMaxEvents > 0 && g_result.nBOS > InpMaxEvents)
                 ? g_result.nBOS - InpMaxEvents : 0;

   // 底色**每帧无条件读一次**：只在 needDraw 块内读的话，恰恰是"底色变了"这一帧读不到。
   const int bgNow = (int)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   bool needDraw = (time[0] != g_lastT0) ||                 // 新 bar：右端对象须延长；亦覆盖"等量换血"
                   (nodesTotal != g_lastNodes) || (curLastBar != g_lastNodeBar) ||
                   (beginNode != g_lastOldestVis) || (boxIdx != g_lastBoxIdx) ||
                   (g_result.nMSS != g_lastNMSS) || (g_result.nBOS != g_lastNBOS) ||
                   (g_result.nCISD != g_lastNCISD) ||
                   (g_result.nSWEEP != g_lastNSWEEP) ||
                    (g_result.nFVG != g_lastNFVG) ||
                    (g_result.nOB != g_lastNOB) ||
                    (g_erlValid != g_lastErlValid) || (g_erlPrice != g_lastErlPrice) ||
                    (g_erlBar != g_lastErlBar) ||
                    (g_irlValid != g_lastIrlValid) || (g_irlPrice != g_lastIrlPrice) ||
                    (g_irlFvgIdx != g_lastIrlIdx) ||
                    (g_pdValid != g_lastPdValid) ||
                    (g_pdh != g_lastPdh) || (g_pdl != g_lastPdl) ||
                    (g_pdT1 != g_lastPdT1) ||
                   (g_curBias != g_lastCurBias) ||
                   (mssFrom != g_lastMSSFrom) || (bosFrom != g_lastBOSFrom) ||
                   (g_relHigh != g_lastRelHigh) || (g_relLow != g_lastRelLow) ||
                   (g_relT1 != g_lastRelT1) || (g_relT2 != g_lastRelT2) ||
                   (g_relValid != g_lastRelValid) ||
                   // 阶段 16/17：IC-CISD 预览状态 + HTF 蜡烛"集合级"指纹
                   (g_icValid != g_lastIcValid) || (g_icLevel != g_lastIcLevel) ||
                   (g_icRefBar != g_lastIcRefBar) ||
                   (g_htfT0 != g_lastHtfT0) || (g_htfSig != g_lastHtfSig) ||
                   (g_htfSlot != g_lastHtfSlot) ||   // 阶段 25：缩放改变右侧槽宽
                   (g_result.nClosure != g_lastNClosure) ||   // 阶段 18：新事件类型必须进指纹
                    (g_result.nChoch != g_lastNChoch) ||       // 阶段 30：CHoCH 同理（硬约定 3）
                   // 阶段 19：两个逐帧派生量（价位变了而指纹不变 → 图上停在旧位置）
                   (g_tgtCount != g_lastTgtCount) ||
                   (g_tgtPrice[0] != g_lastTgtPrice[0]) || (g_tgtPrice[1] != g_lastTgtPrice[1]) ||
                   (g_tgtPrice[2] != g_lastTgtPrice[2]) || (g_tgtPrice[3] != g_lastTgtPrice[3]) ||
                   (g_tgtBar[0]   != g_lastTgtBar[0])   || (g_tgtBar[1]   != g_lastTgtBar[1])   ||
                   (g_tgtBar[2]   != g_lastTgtBar[2])   || (g_tgtBar[3]   != g_lastTgtBar[3])   ||
                   (g_fibValid != g_lastFibValid) || (g_fibA != g_lastFibA) ||
                    (g_fibB != g_lastFibB) || (g_fibRefBar != g_lastFibRefBar) ||
                    (g_fibDir != g_lastFibDir) ||
                    (bgNow != g_lastBgClr);   // v1.50-s59：改主题/换模板也要重画混色

   // 门控只覆盖"绘制 + 注册"；回收段另有一条独立守卫（见下方 needDraw 判断）。
   if(needDraw)
   {
      g_lastNodes     = nodesTotal;
      g_lastNodeBar   = curLastBar;
      g_lastOldestVis = beginNode;
      g_lastBoxIdx    = boxIdx;
      g_lastNMSS      = g_result.nMSS;
      g_lastNBOS      = g_result.nBOS;
      g_lastNCISD     = g_result.nCISD;
      g_lastNSWEEP    = g_result.nSWEEP;
      g_lastNFVG      = g_result.nFVG;
      g_lastNOB       = g_result.nOB;
      g_lastNClosure  = g_result.nClosure;
      g_lastNChoch    = g_result.nChoch;
      // 阶段 19
      g_lastTgtCount = g_tgtCount;
      for(int m = 0; m < MAX_TARGETS; m++)
      {
         g_lastTgtPrice[m] = g_tgtPrice[m];
         g_lastTgtBar[m]   = g_tgtBar[m];
      }
      g_lastFibValid  = g_fibValid;  g_lastFibA = g_fibA;  g_lastFibB = g_fibB;
      g_lastFibRefBar = g_fibRefBar; g_lastFibDir = g_fibDir;
      g_lastBgClr    = bgNow;   // v1.50-s59：与指纹同帧同步
      g_lastErlValid  = g_erlValid;  g_lastErlPrice = g_erlPrice;  g_lastErlBar = g_erlBar;
      g_lastIrlValid  = g_irlValid;  g_lastIrlPrice = g_irlPrice;  g_lastIrlIdx = g_irlFvgIdx;
      g_lastPdValid   = g_pdValid;   g_lastPdh = g_pdh; g_lastPdl = g_pdl; g_lastPdT1 = g_pdT1;
      g_lastCurBias   = g_curBias;
      g_lastMSSFrom   = mssFrom;
      g_lastBOSFrom   = bosFrom;
      g_lastRelHigh   = g_relHigh;
      g_lastRelLow    = g_relLow;
      g_lastRelValid  = g_relValid;
      g_lastT0        = time[0];
      g_lastRelT1     = g_relT1;   g_lastRelT2 = g_relT2;
      g_lastIcValid   = g_icValid; g_lastIcLevel = g_icLevel; g_lastIcRefBar = g_icRefBar;
      g_lastHtfT0     = g_htfT0;   g_lastHtfSig  = g_htfSig;
      g_lastHtfSlot   = g_htfSlot;
      // 全量帧算出的期望状态 = 预览的权威状态 → 同步给快路径的缓存，
      // 否则下一 tick 快路径会把它当成"变了"而做一次无谓的删+建。
      g_icFastValid   = g_icValid; g_icFastLevel = g_icLevel; g_icFastRefBar = g_icRefBar;
      // v1.50-s59：**整组**复位。原来只清 T0/T1，O/H/L/C 留着全量帧之前的旧值 ⇒ 全量帧后
      //   第一个 tick 上 `moved`（:4779）是用陈旧 O/H/L/C 算的，早退实际只由 T0/T1 那一句兜着。
      //   两处必须同生共死：下一个人若把 T0/T1 当冗余删掉，`moved` 立刻变成真判据而带着脏缓存。
      g_htfC0T0 = 0;  g_htfC0T1 = 0;
      g_htfC0O  = 0.0; g_htfC0H = 0.0; g_htfC0L = 0.0; g_htfC0C = 0.0;
      SceneSetRebuild();            // 重建期望集合（哈希，成员判定 O(1)）

      // PD Array 填充色：按图表**实际底色**派生一次，整帧共用。
      // 放在 needDraw 块内 —— 底色极少变，没必要每帧付一次 ChartGetInteger（跨进程）。
      color bgClr    = (color)bgNow;   // v1.50-s59：复用指纹处已读的值（原来这里又读一次）
      color fillFVG  = PdFill(InpColorFVG,       bgClr, InpPDFillPercent);
      // 阶段 37：**弱化（逆 HTF 偏置 / 已失效）的 FVG 与 OB 不再共用同一个灰**。
      //  为什么必须改：弱化 FVG / 弱化 OB / 内包盒原来塌成同一个 `fillWeak`（实测 #D4D4DA），
      //  几条带子连成一片，中间没被覆盖的价格空档（实测纯 #FFFFFF）看起来就像
      //  "FVG 中间有个白洞" —— 用户实机就此提问。
      //  规则：**色相永远表示族别，浓度表示确认度**。
      //    填充：正常 = 族色 × InpPDFillPercent；弱化 = 族色 × 一半（更淡）
      //    轮廓：正常 = 族色原色；        弱化 = 族色 × 50%（洗淡但仍认得出是哪一族）
      //  ⚠️ 阶段 38 起 **OB 不再填充**（改成水平线段，见 OB 渲染段）⇒ 只保留线色。
      int   halfPct  = InpPDFillPercent / 2;
      color fillFVGD = PdFill(InpColorFVG, bgClr, halfPct);
      color lineFVGD = PdFill(InpColorFVG, bgClr, 50);
      color lineOBUpD = PdFill(InpColorOBUp, bgClr, 50);
      color lineOBDnD = PdFill(InpColorOBDn, bgClr, 50);
      bool  doFill   = (InpPDFillPercent > 0);

      // ── 阶段 17：HTF 蜡烛叠加 ──
      //  画在最底层：实体矩形用 OBJPROP_BACK=true（UpsertRect 恒定如此），
      //  故它位于图表 K 线之下，不会遮住价格。
      DrawHtfCandles(time[0], true, changed);

      // ── 阶段 16：IC-CISD 预览（未收盘 bar 上的临时 CISD）──
      //  只有 g_icValid != 0 时才会注册进场景集；失效时不注册 → 回收段会删掉
      //  快路径可能留下的预览对象。清空快路径缓存名，避免它去删已不存在的对象。
      SyncEarlyCisdObject(time, true, changed);
      if(g_icValid == 0) { g_icName = ""; g_icLblName = ""; }
      // "早/迟"同步给快路径缓存。⚠️ 它**不进 needDraw 指纹** —— 该值会在 bar 内翻转，
      // 而指纹只在全量帧比较；bar 内的翻转由快路径负责（它已把 late 纳入缓存比对）。
      // 这与 UpdateLiveLeg 的分工一致：**bar 内会变的东西交给快路径**。
      g_icFastLate = g_icLate;
      // ── 阶段 1-C：HTF relevance 水平线（只标记，不过滤）──
      //   两条线的存在与否都必须与 SceneSet 一致：加进场景集才会被回收段保留。
      if(InpDrawRelevance && g_relValid)
      {
         string nmH = OBJ_PREFIX + "RELH";
         string nmL = OBJ_PREFIX + "RELL";
         AddSceneName(nmH);
         AddSceneName(nmL);
         if(UpsertLine(nmH, g_relT1, g_relHigh, g_relT2, g_relHigh,
                       InpColorRelevance, STYLE_DOT, 1, false)) changed = true;
         if(UpsertLine(nmL, g_relT1, g_relLow, g_relT2, g_relLow,
                       InpColorRelevance, STYLE_DOT, 1, false)) changed = true;
      }

      // ── 阶段 8：dealing range + EQ（premium / discount）──
      //  依据 `Relevant.png`：他把 relevant high/low 连成一个区间；premium/discount
      //  即该区间的上/下半，分界为 50% 均衡位。纯可视化，不参与判定。
      //  与 relevance 线同源（g_relHigh / g_relLow），故一并放在 g_relValid 分支内。
      if(InpDrawDealingRange && g_relValid && g_relHigh > g_relLow)
      {
         double   eq  = (g_relHigh + g_relLow) * 0.5;
         datetime tR  = time[0];                     // 右端收到最新 bar
         double   pad = (g_relHigh - g_relLow) * 0.08;

         string nmR = OBJ_PREFIX + "RANGE";
         string nmE = OBJ_PREFIX + "EQ";
         string lbP = OBJ_PREFIX + "PremLbl";
         string lbD = OBJ_PREFIX + "DiscLbl";
         AddSceneName(nmR);
         // EQ 是可选元素（默认关）。注册与绘制必须同在 InpShowEQ 内 ——
         // 只跳过 Upsert 而仍 AddSceneName，会让回收段保住一个陈旧的 EQ 对象。
         if(InpShowEQ) AddSceneName(nmE);
         AddSceneName(lbP); AddSceneName(lbD);

         if(UpsertRect(nmR, g_relT1, g_relHigh, tR, g_relLow,
                       InpColorRange)) changed = true;
         if(InpShowEQ)
         {
            if(UpsertLine(nmE, g_relT1, eq, tR, eq,
                          InpColorEQ, STYLE_DASH, 1, false)) changed = true;
         }
         if(UpsertText(lbP, tR, g_relHigh - pad, "PREMIUM",  InpColorRange)) changed = true;
         if(UpsertText(lbD, tR, g_relLow  + pad, "DISCOUNT", InpColorRange)) changed = true;
      }
      g_setNextCap    = 128;        // 本帧统计规模后于末尾自适应

   //── 内包盒矩形（母线 high/low 围成，跨母线→最后内包）──
   if(InpMode != MODE_FRACTAL_SWING && InpUseInsideBarBox && InpDrawInsideBox && boxIdx >= 0)
   {
      int mother = g_result.box[boxIdx].mother;
      int end    = g_result.box[boxIdx].end;
      string nm = OBJ_PREFIX + "Box_" + IntegerToString(mother);
      AddSceneName(nm);
      if(UpsertRect(nm, time[mother], g_result.box[boxIdx].hi,
                                 time[end],   g_result.box[boxIdx].lo,
                                 InpColorBox)) changed = true;
   }

   //−− 结构线：语义锚定 ID（节点 bar 对）；统一青色连续实线 −−
   //  InpMaxSeg > 0 时只画最近 N 段（超出的部分从左侧截断），
   //  用于绕开终端对象数上限、并用于定位上限位置。
   int segFirst = beginNode;
   if(InpMaxSeg > 0)
   {
      int segLast = nodesTotal - 2;              // 最后一段的左端下标
      if(segLast - InpMaxSeg + 1 > segFirst)
         segFirst = segLast - InpMaxSeg + 1;
   }
   for(int k = segFirst; k < nodesTotal - 1; k++)
   {
      int b1 = g_result.nodes[k].bar;       // 更旧（左端点）
      int b2 = g_result.nodes[k + 1].bar;   // 更新（右端点）

      // 内部 swing 同样加入结构线（保持连续、不消失）；统一青色实线
      string nm = OBJ_PREFIX + "Seg_" + IntegerToString(b1) + "_" + IntegerToString(b2);
      AddSceneName(nm);
      if(UpsertLine(nm, time[b1], g_result.nodes[k].price,
                                 time[b2], g_result.nodes[k + 1].price,
                                 InpColorStructure, STYLE_SOLID, 1, false)) changed = true;
   }

   //── 实时腿：起点固定 = 最后确认结构点；终点 = 之后的反向极值 ──
   if(InpDrawLiveLeg && InpMode != MODE_FRACTAL_SWING && nodesTotal > 0)
   {
      int    lastBar    = g_result.nodes[nodesTotal - 1].bar;
      double lastPrice  = g_result.nodes[nodesTotal - 1].price;
      bool   lastIsHigh = g_result.nodes[nodesTotal - 1].isHigh;
      if(time[lastBar] >= tStart)
      {
         // 起点固定 = 最后确认结构点；终点 = 之后的反向极值
         int    endBar   = -1;
         double endPrice;
         if(lastIsHigh)
         {
            endPrice = DBL_MAX;
            for(int j = lastBar - 1; j >= 0; j--)
               if(low[j] < endPrice) { endPrice = low[j]; endBar = j; }
         }
         else
         {
            endPrice = -DBL_MAX;
            for(int j = lastBar - 1; j >= 0; j--)
               if(high[j] > endPrice) { endPrice = high[j]; endBar = j; }
         }
         if(endBar >= 0)
         {
            string nm = OBJ_PREFIX + "Live";
            AddSceneName(nm);
            if(UpsertLine(nm, time[lastBar], lastPrice,
                                       time[endBar], endPrice,
                                       InpColorStructure, STYLE_DASH, 1, false)) changed = true;
         }
      }
   }

   //── MSS 标注：虚线画在被突破的结构位 ref，标签在虚线右端上方 ──
   for(int k = mssFrom; k < g_result.nMSS; k++)
   {
      int b = g_result.mss[k].bar;
      if(!InpShowMSS || time[b] < tStart) continue;   // v1.50-s59：开关先判，关掉时不再索引 time[b]

      int    dir  = g_result.mss[k].dir;
      double base = g_result.mss[k].ref;   // ★ 被突破的结构位

      // ★ 水平线从"被突破极值节点 bar"开始，画在 refPrice；
      int refBar = g_result.mss[k].refBar;
      if(refBar < 0) refBar = b;                    // 防御回退

      // 虚线终点：模式可选（首次回踩/反抽、固定 N 根、下一节点）
      int nextNode = -1;
      for(int n = 0; n < g_result.nNodes; n++)
      {
         if(g_result.nodes[n].bar < b) { nextNode = g_result.nodes[n].bar; break; }
      }
      datetime tEnd = LineEnd(b, dir, base, refBar, nextNode, time, high, low);

      // 穿透检查（仅 InpNeedRetestToShow=true 时要求后续重新穿越才显示）
      if(InpNeedRetestToShow)
      {
         bool penetrated = false;
         int jStop  = b - 1;
         int jLimit = b - 50;
         if(jLimit < 0) jLimit = 0;
         for(int j = jStop; j >= jLimit; j--)
         {
            if((dir == DIR_UP  && low[j]  <= base) ||
               (dir == DIR_DOWN && high[j] >= base))
               { penetrated = true; break; }
         }
         if(!penetrated) continue;
      }

      // 阶段 3-b（G1 决策）：未过位移门槛的事件只画弱化线、**不给文字标签**。
      // 理由：纯 TTrades 口径下"逆势破位但未位移"没有对应术语（他的早期信号是 CISD，
      // 不是"弱结构破位"），故不造标签。标签名不注册进场景集 → 回收段会删掉它（若曾存在）。
      // 命名收口：确认级（OK）的标签统一为 MSS（不再使用 ICT 的 CHoCH） —— 他的术语对是 MSS / CISD。
      // 阶段 6-b：位移不足【或】与 HTF 偏置逆向 → 一律弱化（无标签 + 暗色点线）。
      // 两者都表示"未获确认"，但语义不同：前者是位移不够，后者是 HTF 不支持。
      // 他："if there is no candle 2 or candle 3 closure on the higher time frame, it is ignored."
      int  biasM = g_result.mss[k].bias;
      bool weak  = g_result.mss[k].weak ||
                   (biasM != 0 && g_result.mss[k].dir != biasM);
      // 阶段 32（用户要求）：弱事件**完全不画** —— 不建对象、不注册场景名。
      //  因对象名按 (refBar,b) 唯一，未注册即被回收段删掉 ⇒ "从灰线变为不存在"是自动的，
      //  不需要另写删除逻辑（与阶段 29 那次"弱化无标签"同一套机制）。
      if(weak && InpHideWeakBreaks) continue;
      color            lineClr = weak ? InpColorWeakBreak : InpColorMSS;
      // 用户要求：BOS / MSS 一律用**密集点线**（原先确认级用 STYLE_DASH，观感偏疏）。
      // 弱化与否**只用颜色**区分（弱化者没有标签）。
      ENUM_LINE_STYLE  lineSty = STYLE_DOT;

      string nm  = OBJ_PREFIX + "MSS_"   + IntegerToString(refBar) + "_" + IntegerToString(b);
      string lbl = OBJ_PREFIX + "MSSLbl_" + IntegerToString(refBar) + "_" + IntegerToString(b);
      AddSceneName(nm);
      if(!weak) AddSceneName(lbl);
      if(UpsertLine(nm, time[refBar], base, tEnd, base,
                            lineClr, lineSty, 1, false)) changed = true;
      if(!weak)
      {
         // 用户要求：标注放在虚线的**正中** —— 水平取线两端时间的中点，
         // 垂直用 ANCHOR_CENTER 居中于该价位（故不再做 ±0.15×ATR 偏移，
         // 也不需要 g_curATR 的兜底分支）。
         datetime tMid = (datetime)(((long)time[refBar] + (long)tEnd) / 2);
         if(UpsertText(lbl, tMid, base, "MSS", InpColorMSS, ANCHOR_CENTER)) changed = true;
      }
   }

   //── BOS 标注 ──
   for(int k = bosFrom; k < g_result.nBOS; k++)
   {
      int b = g_result.bos[k].bar;
      if(!InpShowBOS || time[b] < tStart) continue;   // v1.50-s59：开关先判，关掉时不再索引 time[b]

      int    dir  = g_result.bos[k].dir;
      double base = g_result.bos[k].ref;   // ★ 被突破的结构位

      // ★ 水平线从"被突破极值节点 bar"开始，画在 refPrice；
      int refBar = g_result.bos[k].refBar;
      if(refBar < 0) refBar = b;                    // 防御回退

      int nextNode = -1;
      for(int n = 0; n < g_result.nNodes; n++)
      {
         if(g_result.nodes[n].bar < b) { nextNode = g_result.nodes[n].bar; break; }
      }
      datetime tEnd = LineEnd(b, dir, base, refBar, nextNode, time, high, low);

      if(InpNeedRetestToShow)
      {
         bool penetrated = false;
         int jStop  = b - 1;
         int jLimit = b - 50;
         if(jLimit < 0) jLimit = 0;
         for(int j = jStop; j >= jLimit; j--)
         {
            if((dir == DIR_UP  && low[j]  <= base) ||
               (dir == DIR_DOWN && high[j] >= base))
               { penetrated = true; break; }
         }
         if(!penetrated) continue;
      }

      // 阶段 6-b：与 HTF 偏置逆向 → 弱化（无标签 + 暗色点线）。
      int  biasB = g_result.bos[k].bias;
      bool dimB  = (biasB != 0 && g_result.bos[k].dir != biasB);
      // 阶段 32：同 MSS —— 逆偏置的 BOS 完全不画（`InpHideWeakBreaks=false` 可退回灰线）。
      if(dimB && InpHideWeakBreaks) continue;

      string nm  = OBJ_PREFIX + "BOS_"   + IntegerToString(refBar) + "_" + IntegerToString(b);
      string lbl = OBJ_PREFIX + "BOSLbl_" + IntegerToString(refBar) + "_" + IntegerToString(b);
      AddSceneName(nm);
      if(!dimB) AddSceneName(lbl);
      // 用户要求：与 MSS 一致 —— 密集点线；弱化只用颜色区分（阶段 31 起恢复：弱化无标签）。
      if(UpsertLine(nm, time[refBar], base, tEnd, base,
                            (dimB ? InpColorWeakBreak : InpColorBOS),
                            STYLE_DOT, 1, false)) changed = true;
      if(!dimB)
      {
         // 用户要求：标注放在虚线的正中（同 MSS，见上）
         datetime tMid = (datetime)(((long)time[refBar] + (long)tEnd) / 2);
         if(UpsertText(lbl, tMid, base, "BOS", InpColorBOS, ANCHOR_CENTER)) changed = true;
      }
   }

   //── 阶段 30/35：**节点级**破位（BOS / CHoCH，判据见 ComputeChoch）──
   //  画法与 MSS/BOS 一致：从被破节点向右的点线 + 正中标签。
   //  ⚠️ `CHoCH` 是**借用 ICT 术语**（他的语料 0 次）；`BOS` 是他的术语。
   //  ⚠️ **不做弱化分级**：本层没有位移判据、也不表示"确认"，
   //     它是一条节点级结构观察 ⇒ 恒用原色、恒带标签。
   if(InpShowChoch)
   {
      int chochFrom = (InpMaxEvents > 0 && g_result.nChoch > InpMaxEvents)
                      ? g_result.nChoch - InpMaxEvents : 0;
      int nChochHidden = 0;   // 阶段 33：因与引擎 MSS/BOS 同位而让位的条数（诊断用）
      for(int k = chochFrom; k < g_result.nChoch; k++)
      {
         int b = g_result.choch[k].bar;
         if(time[b] < tStart) continue;

         int    sub    = g_result.choch[k].sub;
         int    dir    = g_result.choch[k].dir;
         double base   = g_result.choch[k].ref;
         int    refBar = g_result.choch[k].refBar;
         if(refBar < 0) refBar = b;

         // 阶段 33：同位去重 —— 该位已有引擎 MSS/BOS ⇒ 节点级标记让位（否则两标签重叠）
         if(LevelMarkedByBreak(refBar, time, tStart)) { nChochHidden++; continue; }

         int nextNode = -1;
         for(int n = 0; n < g_result.nNodes; n++)
         {
            if(g_result.nodes[n].bar < b) { nextNode = g_result.nodes[n].bar; break; }
         }
         datetime tEnd = LineEnd(b, dir, base, refBar, nextNode, time, high, low);
         if(tEnd <= time[refBar]) tEnd = time[refBar] + 60;   // 防退化线（两端同刻画不出来）

         // ⚠️⚠️ 阶段 70（用户裁定）：**只有"改了性格"才画 CHoCH**；其余一律画 BOS。
         //    逆势但没改性格的破位记 `NODEBRK_BOS_INTERNAL`，观感与 BOS 完全一致
         //    （用户原话："这里应该都是**内部的 BOS** 才对"），只在 CSV 的 state 列区分。
         bool   isBos   = (sub != NODEBRK_CHOCH);
         string tag     = isBos ? "BOS" : "CHoCH";
         color  lineClr = isBos ? InpColorBOS : InpColorChoch;

         string nm  = OBJ_PREFIX + "Choch_"    + IntegerToString(refBar) + "_" + IntegerToString(b);
         string lbl = OBJ_PREFIX + "ChochLbl_" + IntegerToString(refBar) + "_" + IntegerToString(b);
         AddSceneName(nm);
         AddSceneName(lbl);
         if(UpsertLine(nm, time[refBar], base, tEnd, base,
                       lineClr, STYLE_DOT, 1, false)) changed = true;
         datetime tMid = (datetime)(((long)time[refBar] + (long)tEnd) / 2);
         if(UpsertText(lbl, tMid, base, tag, lineClr, ANCHOR_CENTER)) changed = true;
      }
      // 阶段 33：让位条数必须可见 —— 否则"节点级标记变少了"与"根本不触发"不可分辨
      if(InpDebugShowRef && nChochHidden > 0)
         PrintFormat("STRUCT_NODEBRK 同位让位=%d（该位已有引擎 MSS/BOS）", nChochHidden);
   }

   //── CISD 标注（阶段 4-b）──
   //  决策：CISD **不做 WEAK 分级**处理、全部带标签。
   //  理由：他明说 CISD 是 "earlier but riskier" 的早期信号（"CISD can give earlier
   //  entries but sometimes too early, leading to false signals"），而用 MSS 那套为
   //  「穿越 swing 结构位」设计的位移门槛去筛它，实测 18 条里 14 条被判 WEAK ——
   //  与它的定位矛盾。质量改以**颜色**区分（OK = InpColorCISD，WEAK = InpColorCISDWeak），
   //  度量仍逐条写入 CSV 的 displacement 列，供事后分析。
   if(InpShowCISD)
   {
      // cisdFrom 不进 needDraw 指纹：它由 nCISD 与常量 InpMaxEvents 派生，
      // 而 nCISD 已在指纹中，故指纹充分。
      int cisdFrom = (InpMaxEvents > 0 && g_result.nCISD > InpMaxEvents)
                     ? g_result.nCISD - InpMaxEvents : 0;
      for(int k = cisdFrom; k < g_result.nCISD; k++)
      {
         int b = g_result.cisd[k].bar;
         if(time[b] < tStart) continue;

         int    dir    = g_result.cisd[k].dir;
         double base   = g_result.cisd[k].ref;      // CISD 位 = 造势序列起点的开盘价
         int    refBar = g_result.cisd[k].refBar;   // 极值 bar（线左端锚定；见 AddCisdResult）

         int nextNode = -1;
         for(int n = 0; n < g_result.nNodes; n++)
         {
            if(g_result.nodes[n].bar < b) { nextNode = g_result.nodes[n].bar; break; }
         }
         datetime tEnd = LineEnd(b, dir, base, refBar, nextNode, time, high, low);

         // 阶段 6-b：与 HTF 偏置逆向 → 弱化（无标签 + 暗色点线）。
         // CISD 仍不做位移的 WEAK 分级（见 §11.3），但 HTF 逆向是他明确要求忽略的。
         int   biasC  = g_result.cisd[k].bias;
         bool  dimC   = (biasC != 0 && g_result.cisd[k].dir != biasC);
         // v1.50-s58：配色对"位移不足"与"缺后续同向 FVG"**取并集**，
         //   与旧实现（后者曾被错误地折进 weak）视觉等价，但两个成因从此各自可查。
         bool  weakC  = g_result.cisd[k].weak || !g_result.cisd[k].fvgFollow;
         color lineClr = dimC ? InpColorWeakBreak
                              : (weakC ? InpColorCISDWeak : InpColorCISD);

         string nm  = OBJ_PREFIX + "CISD_"   + IntegerToString(refBar) + "_" + IntegerToString(b);
         string lbl = OBJ_PREFIX + "CISDLbl_" + IntegerToString(refBar) + "_" + IntegerToString(b);
         AddSceneName(nm);
         if(!dimC) AddSceneName(lbl);
         if(UpsertLine(nm, time[refBar], base, tEnd, base,
                               lineClr, (dimC ? STYLE_DOT : STYLE_DASH), 1, false)) changed = true;

         if(!dimC)
         {
            double labelPrice = (dir == DIR_UP) ? base + g_curATR * 0.15
                                                : base - g_curATR * 0.15;
            if(g_curATR <= 0.0)
            {
               double dashStep = (ChartGetDouble(0, CHART_PRICE_MAX) - ChartGetDouble(0, CHART_PRICE_MIN)) * 0.01;
               if(dashStep <= 0.0) dashStep = _Point * 50.0;
               labelPrice = (dir == DIR_UP) ? base + dashStep : base - dashStep;
            }
            string tag = "CISD";
            if(UpsertText(lbl, time[b], labelPrice, tag, lineClr)) changed = true;
         }
      }
   }

   //── 阶段 18a：Candle 2 / Candle 3 收盘确认 ──
   //  定位：它是他"**swing 有效性**"的确认条件（POI + valid closure），不是独立的信号方向。
   //  ⚠️ 18a **不参与判定** —— 结构照旧推进，这里只把"这个 swing 带的是哪种 closure"标出来。
   //     门禁版（"缺 closure 即忽略该 swing"）属 18b，另开一轮。
   //  画法：标签画在 swing 极值外侧；C3 另画 C3 区间的 50% 线（他："mark the **full range
   //  of candle 3**"，看涨预期 C4 刺入 C3 **上半**）。
   if(InpShowClosures)
   {
      int cloFrom = (InpMaxEvents > 0 && g_result.nClosure > InpMaxEvents)
                    ? g_result.nClosure - InpMaxEvents : 0;
      for(int k = cloFrom; k < g_result.nClosure; k++)
      {
         int b = g_result.closure[k].bar;
         if(time[b] < tStart) continue;

         int   sub    = g_result.closure[k].sub;
         int   dir    = g_result.closure[k].dir;
         int   refBar = g_result.closure[k].refBar;
         int   biasK  = g_result.closure[k].bias;
         bool  dimK   = (biasK != 0 && dir != biasK);
         color clr    = dimK ? InpColorWeakBreak
                             : ((sub == CLOSURE_C3) ? InpColorC3 : InpColorC2);

         // 标签：C3 另带 C4 的均衡位结果（`+` = 守住预期那半，`-` = 已破，无后缀 = C4 未出现）
         string tag;
         if(sub == CLOSURE_C3)
         {
            int c4r = g_result.closure[k].c4;
            tag = (c4r == 1) ? "C3+" : ((c4r == 2) ? "C3-" : "C3");
         }
         else tag = (sub == CLOSURE_C2_CONT) ? "C2-CONT" : "C2";
         // 阶段 26：方向记号 —— 文字里必须能**直接读出多空**。
         //  在此之前方向只由**位置**（低点下方=多 / 高点上方=空）与**颜色**（顺/逆偏置）表达，
         //  而颜色分的是"顺不顺偏置"、**不是**多空 ⇒ 单看一个悬空的 `C2` 判断不出方向。
         //  ⚠️ 字形不是"看着像能显示"：本指标文字对象固定 `OBJPROP_FONT = "Arial"`
         //     （见 UpsertText），已用 WPF `GlyphTypeface.CharacterToGlyphMap` 实测
         //     Arial 含 U+25B2 / U+25BC（▲▼）—— 故直接用符号，不退回 ASCII 的 ^ / v。
         tag += (dir == DIR_UP) ? "▲" : "▼";

         string lbl = OBJ_PREFIX + "CloLbl_" + IntegerToString(b);
         AddSceneName(lbl);
         double off = (g_curATR > 0.0) ? g_curATR * 0.5 : _Point * 50.0;
         double lp  = (dir == DIR_UP) ? low[b] - off : high[b] + off;
         if(UpsertText(lbl, time[b], lp, tag, clr)) changed = true;

         if(sub == CLOSURE_C3 && InpShowC3Eq)
         {
            double c3Hi = high[refBar], c3Lo = low[refBar];
            if(c3Hi > c3Lo)
            {
               double   eq    = (c3Hi + c3Lo) * 0.5;
               datetime tEndE = time[b];
               if(tEndE <= time[refBar]) tEndE = time[refBar] + 60;
               string   nmEq  = OBJ_PREFIX + "C3EQ_" + IntegerToString(b);
               AddSceneName(nmEq);
               if(UpsertLine(nmEq, time[refBar], eq, tEndE, eq,
                             InpColorC3, STYLE_DOT, 1, false)) changed = true;
            }
         }
      }
   }

   //── 阶段 9：PD Array（FVG / OB）──
   //  定位：他所说的 "Point of Interest"＝执行层参照区，**不参与任何结构判定**
   //  （"A Point of Interest Doesn't Mean an Entry."）。故本段只读 g_result，不写回。
   //  对象命名带 (c1, c3) / (runOldest, breakBar) 双 bar → 与既有 ID 方案一致。
   //  ⚠️ 与事件（MSS/BOS/CISD/SWEEP）的差别：那里"弱化 = 暗色 + 去掉标签"，因为弱化
   //     的是**信号**；PD Array 是**地图**，去掉标签会让人看不出画的是什么。故此处
   //     CE 已穿 / 与 HTF 偏置逆向只改**颜色**，标签恒定保留。
   //     依据：实测 80 个 FVG 中 66 个（82.5%）CE 已被收盘穿越 —— 一个 82.5% 都命中的
   //     判据若再兼任"去掉标签"，等于让整个功能默认无标签。
   if(InpShowFVG)
   {
      int fvgFrom = (InpMaxEvents > 0 && g_result.nFVG > InpMaxEvents)
                    ? g_result.nFVG - InpMaxEvents : 0;
      for(int k = fvgFrom; k < g_result.nFVG; k++)
      {
         int b  = g_result.fvg[k].bar;      // candle3（缺口确认 bar）
         int c1 = g_result.fvg[k].refBar;   // candle1（矩形左端）
         if(b < 0 || c1 < 0) continue;
         if(time[b] < tStart) continue;
         // 完全回补 = 缺口已被走完，PD array 意义消失 → 默认不再绘制
         if(InpFvgHideFilled && g_result.fvg[k].fillPct >= 1.0) continue;

         double zLo = g_result.fvg[k].zoneLo;
         double zHi = g_result.fvg[k].zoneHi;
         double ce  = g_result.fvg[k].ref;          // CE = 0.5 中点
         int  biasF = g_result.fvg[k].bias;
         bool dimF  = (biasF != 0 && g_result.fvg[k].dir != biasF) ||
                      g_result.fvg[k].ceBroken;
         // 区域上色：填充色按底色派生；轮廓/标签色恒定用亮色。
         // ⚠️ 弱化时**恢复填充**（v1.49-s14）：s12e 曾因"弱化色比正常填充色更亮"而改为不填充，
         //    但那是旧"×α"换算的副作用。现在两者都按同一百分比混向底色，
         //    量级相当（黑底 ≈(11,11,13) vs (0,20,18)/(10,14,26)），反转问题不复存在。
         //    弱化改由**颜色**（灰）区分，而不是"有没有填充"。
         // 阶段 37：弱化不再用中性灰，而是**同一族色的淡版**（见上方 fillFVGD/lineFVGD 的说明）
         color clrF  = dimF ? fillFVGD : fillFVG;
         color clrFt = dimF ? lineFVGD : InpColorFVG;

         string nm  = OBJ_PREFIX + "FVG_"    + IntegerToString(c1) + "_" + IntegerToString(b);
         string nmc = OBJ_PREFIX + "FVGCE_"  + IntegerToString(c1) + "_" + IntegerToString(b);
         AddSceneName(nm); AddSceneName(nmc);

         // 未失效的缺口画到最右（仍是有效 POI）；CE 用点线单独标出
         // 阶段 21：右端由 InpPDEnd 决定（默认仍是"到当前 bar"= 他的画法）
         datetime t2 = PdRightEnd(c1, b, zLo, zHi, time, high, low);
         if(UpsertRect(nm, time[c1], zHi, t2, zLo, clrF, doFill)) changed = true;
         if(UpsertLine(nmc, time[c1], ce, t2, ce, clrFt, STYLE_DOT, 1, false)) changed = true;
         // 阶段 40（用户要求）：**FVG 不再打文字标签** —— 色带本身 + CE 点线的颜色已足够识别。
         //  ⚠️ 不再注册 `FVGLbl_*` ⇒ 图上残留的旧标签会因"未注册即回收"被自动删除，
         //     不需要另写清理逻辑（与阶段 29/31 同一套机制）。
      }
   }
   if(InpShowOB)
   {
      int obFrom = (InpMaxEvents > 0 && g_result.nOB > InpMaxEvents)
                   ? g_result.nOB - InpMaxEvents : 0;
      for(int k = obFrom; k < g_result.nOB; k++)
      {
         int b  = g_result.ob[k].bar;       // 验证 bar（收盘穿回造势序列）
         int rb = g_result.ob[k].refBar;    // 造势序列最旧一根
         if(b < 0 || rb < 0) continue;
         if(time[b] < tStart) continue;

         double zLo = g_result.ob[k].zoneLo;   // 实体区间下沿（**仅数据/CSV 用，不再绘制**）
         double zHi = g_result.ob[k].zoneHi;   // 实体区间上沿（同上）
         double lvl = g_result.ob[k].ref;      // ★ 关键价位 = 造势序列最旧一根的开盘价（= CISD 位）
         int  biasO = g_result.ob[k].bias;
         // D14：位移不足的 OB 与 MSS/CISD 一样弱化（暗色）。标签仍保留 ——
         // PD Array 是地图不是信号，见本段开头说明与 CONTEXT.md v1.49 硬约定第 4 条。
         bool dimO  = (biasO != 0 && g_result.ob[k].dir != biasO) ||
                      g_result.ob[k].weak || !g_result.ob[k].fvgFollow;   // v1.50-s58：同 CISD 取并集
         // 阶段 41（用户要求）：**做多/做空 OB 分色** —— 绿=需求（被扫低点派生）、红=供给（被扫高点派生）。
         bool   upSide = (g_result.ob[k].dir == DIR_UP);
         color  clrOt  = dimO ? (upSide ? lineOBUpD : lineOBDnD)
                              : (upSide ? InpColorOBUp : InpColorOBDn);

         string nm  = OBJ_PREFIX + "OBLine_" + IntegerToString(rb) + "_" + IntegerToString(b);
         string lbl = OBJ_PREFIX + "OBLbl_"  + IntegerToString(rb) + "_" + IntegerToString(b);
         AddSceneName(nm); AddSceneName(lbl);

         datetime t2 = PdRightEnd(rb, b, zLo, zHi, time, high, low);
         // 阶段 38（用户要求）：**改成与他一致的水平线段**。
         //  他图上 OB 是"一条水平线向右延伸"，线在**关键价位**上（= open[runOldest]），
         //  另一端另有 "Invalidation" 标记；原实现画的是**实体并集矩形**（属推断，见 plan §18.3-②）。
         //  ⇒ 现在只画线：起于造势序列最旧一根、向右延伸到 `InpPDEnd` 决定的位置。
         //  ⚠️ 对象名改用 `OBLine_` 前缀：对象**类型**由矩形变为线，沿用旧名会让
         //     "已存在的矩形"撞进线的调和逻辑；换前缀后旧矩形**未注册即回收**，自动清除。
         //  ⚠️ 实体并集区间**仍保留在数据与 CSV**（zoneLo/zoneHi）—— 他说的 Invalidation
         //     指的就是那个区间的另一端，故这份信息不能丢。
         if(UpsertLine(nm, time[rb], lvl, t2, lvl, clrOt, STYLE_SOLID, 1, false)) changed = true;
         // 阶段 39（用户要求）：标签放到线段**右端**，不再留在被破 bar 处。
         //  为什么原来偏中：锚点取的是 CISD 触发 bar（= OB 的 `bar`），而线段右端是
         //  `PdRightEnd` 算出的 `vb + InpPDRightBars` ⇒ 触发 bar 天然坐在线段中偏右的位置。
         //  ⚠️ 用 `ANCHOR_RIGHT_*`（锚点在文字**右缘**）⇒ 文字**完全落在线段内**；
         //     若换成左锚点，文字会伸出右端，在 `PD_END_NOW`（右端=当前 bar）时被图表右缘切掉。
         //  ⚠️ 上下锚点按方向选：**做空** OB（供给，红）的标签在线上方 → RIGHT_LOWER（文字在锚点之上）；
         //     **做多**（需求，绿）在下方 → RIGHT_UPPER（文字在锚点之下），否则文字会向上压住线。
         //  （`upSide` 已在上方按"是否做多"定义，此处不再重复声明）
         double lp = upSide ? lvl - g_curATR * 0.1 : lvl + g_curATR * 0.1;
         if(UpsertText(lbl, t2, lp, "OB", clrOt,
                       upSide ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER)) changed = true;
      }
   }

   //── 前日高/低（PDH / PDL）──
   //  画法沿用本文件既有惯例：自该日 K 线开盘时间向右延伸至最新 bar，
   //  点线 + 线中点标签（ANCHOR_CENTER），与 BOS/MSS/ERL/IRL 的标注约定一致。
   if(InpShowPDHL && g_pdValid)
   {
      datetime tR   = time[0];
      datetime tMid = (datetime)(((long)g_pdT1 + (long)tR) / 2);
      string nmH = OBJ_PREFIX + "PDH";
      string nmL = OBJ_PREFIX + "PDL";
      string lbH = OBJ_PREFIX + "PDHLbl";
      string lbL = OBJ_PREFIX + "PDLLbl";
      AddSceneName(nmH); AddSceneName(nmL);
      AddSceneName(lbH); AddSceneName(lbL);
      if(UpsertLine(nmH, g_pdT1, g_pdh, tR, g_pdh,
                    InpColorPDHL, STYLE_DOT, 1, false)) changed = true;
      if(UpsertLine(nmL, g_pdT1, g_pdl, tR, g_pdl,
                    InpColorPDHL, STYLE_DOT, 1, false)) changed = true;
      if(UpsertText(lbH, tMid, g_pdh, "PDH", InpColorPDHL, ANCHOR_CENTER)) changed = true;
      if(UpsertText(lbL, tMid, g_pdl, "PDL", InpColorPDHL, ANCHOR_CENTER)) changed = true;
   }

   //── 阶段 10：Internal / External Liquidity ──
   //  他的表达方式（配图 ERLIRL-*.png）：IRL = FVG 色带（已在上面画过），
   //  ERL = 摆动位处一条短点线。**两图都没有连接箭头**，故此处也不画。
   //  无 HTF 偏置时 ComputeErlIrl 直接返回 → 两个对象都不注册 → 被回收段清掉。
   if(InpShowERLIRL && g_erlValid)
   {
      string nmE = OBJ_PREFIX + "ERL";
      string lbE = OBJ_PREFIX + "ERLLbl";
      AddSceneName(nmE); AddSceneName(lbE);
      if(UpsertLine(nmE, time[g_erlBar], g_erlPrice, time[0], g_erlPrice,
                    InpColorERL, STYLE_DOT, 1, false)) changed = true;
      datetime tE = (datetime)(((long)time[g_erlBar] + (long)time[0]) / 2);
      // 阶段 34：ERL 与目标 T1 是**构造性同位** —— ComputeErlIrl 与 ComputeTargets(a)
      //  用的是同一套筛选（偏置方向 / 现价之外 / IsLiquidityTaken / 价格最近），
      //  故 tgtBar[0] == g_erlBar、tgtPrice[0] == g_erlPrice **恒成立**。
      //  两者连渲染几何都一样（同起止时间、同价位、同 ANCHOR_CENTER），且**颜色同值**
      //  （ERL 与 Target 都是 C'233,30,99'）⇒ 两个标签精确叠印成一团笔画（用户截图实证）。
      //  ⇒ 标签合并成 `ERL/T1`，目标侧那条不再单独画（见下面目标循环里的 continue）。
      string erlTag = "ERL";
      for(int kk = 0; kk < g_tgtCount; kk++)
         if(g_tgtBar[kk] >= 0 && g_tgtBar[kk] == g_erlBar)
            erlTag += StringFormat("/T%d", kk + 1);
      if(UpsertText(lbE, tE, g_erlPrice, erlTag, InpColorERL, ANCHOR_CENTER)) changed = true;
   }
   if(InpShowERLIRL && g_irlValid && g_irlFvgIdx >= 0 && g_irlFvgIdx < g_result.nFVG)
   {
      // 只画"IRL 那条边 + 标签"：区间本体由 FVG 块负责（可能因 InpMaxEvents / 
      // InpFvgHideFilled 而未画出，故 IRL 自带一条边线，保证自解释）。
      int c1 = g_result.fvg[g_irlFvgIdx].refBar;
      if(c1 >= 0)
      {
         string nmI = OBJ_PREFIX + "IRL";
         string lbI = OBJ_PREFIX + "IRLLbl";
         AddSceneName(nmI); AddSceneName(lbI);
         if(UpsertLine(nmI, time[c1], g_irlPrice, time[0], g_irlPrice,
                       InpColorIRL, STYLE_DOT, 1, false)) changed = true;
         datetime tI = (datetime)(((long)time[c1] + (long)time[0]) / 2);
         if(UpsertText(lbI, tI, g_irlPrice, "IRL", InpColorIRL, ANCHOR_CENTER)) changed = true;
      }
   }

   //── 阶段 19：Auto Targets（流动性目标）+ 操纵腿投影 ──
   //  定位：纯可视化。他明列目标为 *"External liquidity provides the target."*，
   //  故与 ERL 同族，但给的是"最近的 N 个"而不是一个。
   if(InpShowAutoTargets && g_tgtCount > 0)
   {
      for(int k = 0; k < g_tgtCount; k++)
      {
         double   lvl = g_tgtPrice[k];
         // 阶段 34：与 ERL **同节点**（构造性同位）→ 线与标签都交给 ERL，避免同色叠印。
         //  ⚠️ 必须在 AddSceneName 之前 continue —— 未注册即回收，状态变化时旧对象自动清掉。
         //  ⚠️ 用 bar（节点身份）比较而不是价格：价格可能被不同节点偶然撞上（同 §57 的理由）。
         if(InpShowERLIRL && g_erlValid && g_tgtBar[k] == g_erlBar) continue;
         // ⚠️ OBJ_TREND 的两端时间**不能相同**，否则是退化线（对象建得出来但画不出）。
         //    -1 = PDH/PDL：锚到该高周期 K 线的开盘时间；仍不合法则退回固定根数。
         datetime tL = time[0];
         if(g_tgtBar[k] >= 0 && g_tgtBar[k] < rates_total)
            tL = time[g_tgtBar[k]];
         else if(g_pdValid && g_pdT1 > 0 && g_pdT1 < time[0])
            tL = g_pdT1;
         if(tL >= time[0])
         {
            int back = (rates_total > 10) ? 10 : rates_total - 1;
            if(back < 0) back = 0;
            tL = time[back];
         }
         string nm = OBJ_PREFIX + "TGT_" + IntegerToString(k);
         string lb = nm + "Lbl";
         AddSceneName(nm); AddSceneName(lb);
         if(UpsertLine(nm, tL, lvl, time[0], lvl,
                       InpColorTarget, STYLE_DOT, 1, false)) changed = true;
         datetime tMid = (datetime)(((long)tL + (long)time[0]) / 2);
         if(UpsertText(lb, tMid, lvl, StringFormat("T%d", k + 1),
                       InpColorTarget, ANCHOR_CENTER)) changed = true;
      }
   }

   //  操纵腿投影：A→B 为操纵腿，水平 = B 沿**交易方向**继续外推 leg × 倍数。
   //  ⚠️ 方向约定是本实现反号后的读法（见输入组注释），不得声称与他的水平表一致。
   if(InpShowFibTargets && g_fibValid)
   {
      double   leg = g_fibB - g_fibA;
      datetime tA  = time[g_fibRefBar];            // 左端锚在操纵极值 bar
      // 同 TGT：退化线（两端同一时刻）画不出来。极值 bar 恰为 bar 0 时必须退让。
      if(tA >= time[0])
      {
         int backF = (rates_total > 10) ? 10 : rates_total - 1;
         if(backF < 0) backF = 0;
         tA = time[backF];
      }
      for(int j = 0; j < g_fibNLegs; j++)
      {
         double lvl = g_fibB + leg * g_fibLegs[j];
         string nm  = OBJ_PREFIX + "FIB_" + IntegerToString(j);
         string lb  = nm + "Lbl";
         AddSceneName(nm); AddSceneName(lb);
         if(UpsertLine(nm, tA, lvl, time[0], lvl,
                       InpColorFib, STYLE_DOT, 1, false)) changed = true;
         if(UpsertText(lb, time[0], lvl, StringFormat("%.1fx", g_fibLegs[j]),
                       InpColorFib)) changed = true;
      }
   }

   //── HTF 偏置显示（阶段 6-b）──
   //  他："Never drop to the hourly until you have a one-sided daily bias."
   //  没有这一行，用户无法判断门禁实际在用哪个偏置值。
   if(InpShowBias)
   {
      string nmBias = OBJ_PREFIX + "BIAS";
      AddSceneName(nmBias);
      double anchor = 0.0;
      if(g_relValid) anchor = (g_curBias >= 0) ? g_relHigh : g_relLow;
      else           anchor = (g_curBias >= 0) ? high[0]   : low[0];
      double py = anchor + ((g_curBias >= 0) ? 1.0 : -1.0) * g_curATR * 0.5;
      string btxt = StringFormat("HTF bias %s (%s)",
                                 (g_curBias > 0 ? "BULL" : (g_curBias < 0 ? "BEAR" : "NONE")),
                                 EnumToString(InpBiasTF));
      if(UpsertText(nmBias, time[0], py, btxt, InpColorBias)) changed = true;
   }
   //── SWEEP 标注（阶段 5）──
   //  纯上下文：不参与判定，只标"该 intermediate 位被扫荡过"。
   //  标签沿用精简后的风格（只有类型名，见 §11.5）。
   if(InpShowSweep)
   {
      int sweepFrom = (InpMaxEvents > 0 && g_result.nSWEEP > InpMaxEvents)
                      ? g_result.nSWEEP - InpMaxEvents : 0;
      for(int k = sweepFrom; k < g_result.nSWEEP; k++)
      {
         int b = g_result.sweep[k].bar;
         if(time[b] < tStart) continue;
         int      dir    = g_result.sweep[k].dir;
         double   base   = g_result.sweep[k].ref;
         int      refBar = g_result.sweep[k].refBar;

         // 阶段 6-b：与 HTF 偏置逆向 → 弱化（无标签 + 暗色点线）。
         int  biasS = g_result.sweep[k].bias;
         bool dimS  = (biasS != 0 && g_result.sweep[k].dir != biasS);

         string nm  = OBJ_PREFIX + "SWEEP_"   + IntegerToString(refBar) + "_" + IntegerToString(b);
         string lbl = OBJ_PREFIX + "SWEEPLbl_" + IntegerToString(refBar) + "_" + IntegerToString(b);
         AddSceneName(nm);
         if(!dimS) AddSceneName(lbl);
         if(UpsertLine(nm, time[refBar], base, time[b], base,
                               (dimS ? InpColorWeakBreak : InpColorSweep),
                               STYLE_DOT, 1, false)) changed = true;
         if(!dimS)
         {
            double labelPrice = (dir == DIR_UP) ? base + g_curATR * 0.15
                                                : base - g_curATR * 0.15;
            if(g_curATR <= 0.0)
            {
               double dashStep = (ChartGetDouble(0, CHART_PRICE_MAX) - ChartGetDouble(0, CHART_PRICE_MIN)) * 0.01;
               if(dashStep <= 0.0) dashStep = _Point * 50.0;
               labelPrice = (dir == DIR_UP) ? base + dashStep : base - dashStep;
            }
            if(UpsertText(lbl, time[b], labelPrice, "SWEEP", InpColorSweep)) changed = true;
         }
      }
   }
   }  // ← 结束 needDraw 门控块

   // 自适应下一帧的哈希容量：按本帧实际规模取 2 的幂（留 2× 余量）
   if(needDraw)
   {
      int want = 128;
      while(want < (g_setUsed + 1) * 4) want *= 2;
      g_setNextCap = want;
   }

   //── 回收过期对象 ──
   //  v1.48：只在 needDraw 时执行。理由：needDraw=false 意味着期望集合与
   //  上一帧**完全一致**，此时回收必然是空操作（没有任何对象"该消失"）。
   //  成员判定用 O(1) 哈希（SceneHas），整段由 O(total × kept) 降为 O(total)。
   //  注：ObjectGet*/ObjectName/ObjectsTotal 在当前图表上是直接访问（非 IPC），
   //  所以这段的真实成本是脚本侧字符串比较，量级很小。
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
      g_dbgNeedDraw = 1;
   }
   else g_dbgNeedDraw = 0;

   // 只在场景真的变化时才重绘
   if(changed) ChartRedraw();
}

//+------------------------------------------------------------------+
//| 轻量实时腿：仅同 bar tick 时更新 Live 虚线端点（不对全场景调和，    |
//| 避免每 tick 数百次终端对象调用拖死图表 → 新 K 线无法渲染）         |
//|                                                                  |
//| v1.48：① 门控前置；② 端点位移小于 0.1×ATR 时不动图表。              |
//|                                                                  |
//| ⚠️ v1.49-s15b 修正（独立评审查出）：                                |
//|   原实现的门控含合取项 `time[lastBar] == time[0]`，而**该条件永不成立** |
//|   —— 节点只在 `k >= 1 && k <= nValid-2` 的守卫之后才加入，故节点 bar    |
//|   必然 ≥ 1，而 time[0] 是 bar 0。于是：                              |
//|     · 该门控是**死代码**；                                           |
//|     · 每 tick 都要跑一遍完整的 O(lastBar) 极值扫描（最多 ~500 次比较）； |
//|     · 而注释却声称"连扫描都不做" —— 理由也写反了。                     |
//|   正确的判据是**节点是否变化**（不是"节点是否落在当前 bar"）：          |
//|     只要节点没变，bar 1..lastBar-1 就是**冻结**的，极值窗口只可能被      |
//|     bar 0 刷新；而 bar 0 的 low 在 bar 内**单调下降**、high **单调上升**，  |
//|     故可 **O(1) 增量更新**，且**严格等价**于全量重扫（平值不替换，       |
//|     与重扫循环的 `<` / `>` 语义一致）。                                |
//|   只有**节点变化**（窗口本身换了）或首帧才需要重扫。                    |
//+------------------------------------------------------------------+
void UpdateLiveLeg(const datetime &time[], const double &high[],
                   const double &low[])
{
   if(!InpDrawLiveLeg || InpMode == MODE_FRACTAL_SWING || g_result.nNodes <= 0)
      return;
   int    lastBar    = g_result.nodes[g_result.nNodes - 1].bar;
   double lastPrice  = g_result.nodes[g_result.nNodes - 1].price;
   bool   lastIsHigh = g_result.nodes[g_result.nNodes - 1].isHigh;

   // 防御：节点即当前 bar 时极值窗口为空（按上面的守卫推演，实际不会发生）
   if(lastBar < 1) return;

   int    endBar;
   double endPrice;

   if(g_liveInit && g_liveBarT == time[lastBar] && g_liveEndBar >= 0)
   {
      //── 快路径 O(1)：节点未变 ⇒ 只有 bar 0 能刷新极值 ──
      endBar   = g_liveEndBar;
      endPrice = g_liveEndP;
      if(lastIsHigh) { if(low[0]  < endPrice) { endPrice = low[0];  endBar = 0; } }
      else           { if(high[0] > endPrice) { endPrice = high[0]; endBar = 0; } }
   }
   else
   {
      //── 慢路径：节点变化/首帧 ⇒ 窗口换了，必须重扫 ──
      endBar = -1;
      if(lastIsHigh)
      {
         endPrice = DBL_MAX;
         for(int j = lastBar - 1; j >= 0; j--)
            if(low[j] < endPrice) { endPrice = low[j]; endBar = j; }
      }
      else
      {
         endPrice = -DBL_MAX;
         for(int j = lastBar - 1; j >= 0; j--)
            if(high[j] > endPrice) { endPrice = high[j]; endBar = j; }
      }
      if(endBar < 0) return;
   }

   //── 端点位移不显著 → 本 tick 不产生任何终端调用 ──
   if(g_liveInit && g_liveEndBar == endBar && g_liveBarT == time[lastBar])
   {
      double eps2 = (g_curATR > 0.0) ? g_curATR * 0.1 : _Point * 10.0;
      if(MathAbs(endPrice - g_liveEndP) < eps2)
         return;
   }

   //── 等价性自检：把上面的增量结果与全量重扫对照（仅调试模式付代价）──
   //  这一段是"能证伪"的关键：增量推导若错了（例如某周期上 bar 内极值不单调），
   //  此处会计数并被 DbgReport 打出 liveMiss>0，而不是悄悄画错线。
   if(InpDebugShowRef)
   {
      int    chkBar = -1;
      double chkPrice;
      if(lastIsHigh)
      {
         chkPrice = DBL_MAX;
         for(int j = lastBar - 1; j >= 0; j--)
            if(low[j] < chkPrice) { chkPrice = low[j]; chkBar = j; }
      }
      else
      {
         chkPrice = -DBL_MAX;
         for(int j = lastBar - 1; j >= 0; j--)
            if(high[j] > chkPrice) { chkPrice = high[j]; chkBar = j; }
      }
      if(chkBar != endBar || MathAbs(chkPrice - endPrice) > _Point * 0.5)
         g_dbgLiveMismatch++;
   }

   string nm = OBJ_PREFIX + "Live";
   bool changed = UpsertLine(nm, time[lastBar], lastPrice, time[endBar], endPrice,
                             InpColorStructure, STYLE_DASH, 1, false);
   g_liveBarT   = time[lastBar];
   g_liveEndP   = endPrice;
   g_liveEndBar = endBar;
   g_liveInit   = true;
   if(changed) ChartRedraw();
}

//+------------------------------------------------------------------+
//| 主入口：分析（必要时）→ 场景渲染                                  |
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

   //── 明确数组方向：全部按时序（index 0 = 最新 bar）──
   //  不能靠"猜"方向。MQL5 传进来的数组方向取决于终端与是否调用过
   //  ArraySetAsSeries；本指标的全部索引逻辑（time[b]、节点 bar 比较、
   //  窗口裁剪）都按「0 = 最新」编写，故在此显式锁定，消除歧义。
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);   // v1.50-s59：s58 误删。open[] 全程按时序索引（且总与 close[]
                                    //   成对出现在 MathMin(open[i],close[i]) 这类表达式里），而文件自己的
                                    //   纪律（:41 "一律显式 ArraySetAsSeries"）不允许依赖终端默认。

   // 注：`STRUCT_ORIENT` 方向自检已移到**快路径 return 之后**（每全量帧一次）。
   //     它原先在快路径之前，于是在 InpDebugShowRef=true 时**每 tick** 都要付
   //     两次 TimeToString + 一次日志写 —— 落在全程序最热的路径上。

   // 用 bar 计数判断"新 bar"，比 prev_calculated 更可靠
   // v1.50-s58：原为函数内 static —— 它跨 OnDeinit/OnInit 保留，且判据不含品种/周期身份，
   //   换品种后若 rates_total 恰好相等会误判"非新 bar"而走快路径（整帧复用上一品种的结构）。
   //   ⇒ 改为全局 g_lastRates，并在 OnInit 末尾清零。
   bool firstRun = (g_lastRates == 0);
   bool newBar   = (rates_total != g_lastRates);
   g_lastRates   = rates_total;

   // 同 bar tick 且启用复用：跳过全量分析与全场景调和（每 tick 对数百个图表
   // 对象做终端读写会拖死图表、导致新 K 线无法渲染），仅轻量更新实时腿
   if(InpReuseResultOnTick && !firstRun && !newBar)
   {
      UpdateLiveLeg(time, high, low);
      // 阶段 16/17：这两个元素必须在**同 bar tick** 上也跟手 —— 它们的存在意义就是
      //   实时（IC-CISD 是"收盘前"的临时判断；HTF 蜡烛正在形成的那根本身每 tick 在变）。
      //   两者内部都是"缓存比对、未变即零对象调用"，故不会把每 tick 变成全场景调和。
      //   注意：它们都**不写场景集** —— 场景集只在全量帧有效，权威状态也由全量帧给出。
      UpdateEarlyCisdFast(time, close);
      UpdateHtfLastFast(time);
      return(rates_total);
   }

   // 新 bar / 首次 / 复用关闭 → 全量分析 + 全场景渲染
   // Stage 1-C: HTF relevance. Computed only on the full-recompute path --
   // three cross-timeframe Copy* calls per tick would be wasted on the fast path.
   if(InpDebugShowRef)   // 方向自检：每全量帧一次即可（原在快路径前，属每 tick 浪费）
      PrintFormat("STRUCT_ORIENT time[0]=%s time[rates_total-1]=%s  -> %s",
                  TimeToString(time[0]), TimeToString(time[rates_total - 1]),
                  (time[0] >= time[rates_total - 1]) ? "SERIES(0=newest)" : "NON-SERIES(0=oldest)");
   ComputeRelevance();
   ComputePrevDay();                    // 前日高/低：同为跨周期取数，同样只在全量路径算
   ComputeStructure(rates_total, time, open, high, low, close);
   RenderScene(rates_total, time, high, low, close);
   //── 阶段 0 验收：事件导出（InpDumpEvents=true 时才写文件）──
   DumpEvents(time, rates_total);

   //── v1.48 诊断（InpDebugShowRef=true 时输出到「专家」标签页）──
   DbgReport(time, rates_total);

   return(rates_total);
}
//+------------------------------------------------------------------+
