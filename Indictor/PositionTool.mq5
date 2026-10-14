//+------------------------------------------------------------------+
//|  PositionTool.mq5                                         |
//|  TradingView 风格的多头/空头仓位工具（Long / Short Position）      |
//+------------------------------------------------------------------+
//|  为什么要有这个文件：                                             |
//|    TradingView 的 Long/Short Position 工具在图上摆三根线（入场/    |
//|    止损/止盈），盈利区绿色、亏损区红色，并实时给出点数、金额、百分比 |
//|    与盈亏比。MT5 原生没有对应物（只有开仓后的止损止盈虚线）。      |
//|    本指标把这套交互搬到 MT5 图表上，并按当前品种自动换算账户货币    |
//|    金额与建议手数。                                               |
//|                                                                  |
//|  ── 定仓三档，以及为什么默认是「以损定仓」──                       |
//|   ① 以损定仓（固定 R）：R 是**金额**，手数完全由止损距离反推：      |
//|      手数 = R / (止损距离 x 每手每价格单位金额)。                   |
//|      止损拖远 → 手数自动变小，被打到就是亏掉 R。                    |
//|      它把 R 与账户规模**解耦**，复盘时"这一笔亏 1R"才可比；         |
//|      按 % 定仓则账户一变，同一个 1R 的含金量就跟着变了。            |
//|   ② 按账户风险 %：R = 账户规模 x %，随账户浮动。                    |
//|   ③ 固定手数。                                                    |
//|    成本：另行给出**开仓占用保证金**。优先用 OrderCalcMargin 走经纪商 |
//|    自己的公式；取不到时退到两级估算，并在面板上标 ≈。               |
//|                                                                  |
//|  ── 三个必须绕过的 MT5 技术坑（决定了本文件的画法）──              |
//|   ① 图表对象**没有 alpha 通道**，做不出 TradingView 的半透明色块。  |
//|      → 矩形用 OBJPROP_FILL + OBJPROP_BACK（画在 K 线之下），颜色   |
//|        按 InpZoneMix 与图表底色混合，得到视觉上接近半透明的暗色。   |
//|   ② 拖拽事件（CHARTEVENT_OBJECT_DRAG）只在**鼠标松开后**报一次，    |
//|        且 OBJ_TREND 拖中点与拖端点都只给出一份新几何。              |
//|      → 统一以 modifier 0 的 time/price 为真值来源，拖完立刻把另    |
//|        一端归一化（水平线强制 price0==price1），线不会被拖斜。      |
//|      → 不要在本文件里重置 OBJPROP_SELECTED：MT5 必须先选中对象才能  |
//|        拖动，每次重画都清选中会让线变得"拖不动"。                   |
//|   ③ 换周期/改参数会 OnDeinit + OnInit，但图表对象还在。            |
//|      → OnInit 不做"清空重画"，而是从既有对象里 **Rebuild** 出状态， |
//|        否则每次切周期用户的仓位工具都会消失。                       |
//|   ④ 【已实测踩过】OBJPROP_HIDDEN=true 会让对象**鼠标命中不到** ——   |
//|        不只是"从 Ctrl+B 列表里藏起来"：连悬停光标都不变、点也点不中、 |
//|        拖动事件根本不触发。第一版给所有对象都设了它，结果就是         |
//|        "加出来的工具怎么拖都不动"。→ 可交互对象一律 HIDDEN=false。   |
//|        （同一次修复里还加了 OBJPROP_SELECTED 预选中作为第二道保障，  |
//|          但逻辑上它救不了命中不到的对象，故**不是**本次的真正原因。） |
//|   ⑤ 【已实测踩过，v1.12-s1】抓手**不能画在别的线的端点上**：        |
//|        时间宽度抓手原本是画在**入场线两个端点**上的小圆点            |
//|        （OBJ_ARROW 159，与 OBJ_TREND 端点坐标完全重合）→ MT5 把鼠标  |
//|        命中判给了**线**，用户拖到的是入场线（工具被整体平移，宽度   |
//|        纹丝不动）。日志实证：48 次加载、26 次拖动事件全是            |
//|        `_ENTRY/_SL/_TP`，`_HL/_HR` **一次都没有**（见 plan 70.1）。  |
//|        → 抓手移到**工具外侧**（离三根线都有距离），并换成 OBJ_TEXT   |
//|          字形（命中框 = 文字外框，比 8px 圆点大得多、字号可调）；     |
//|          另外在面板上补一组「宽度 −N / +N」按钮作为兜底通道。        |
//|                                                                  |
//|  ── 一处与原工具的**有意偏离** ──                                 |
//|    TradingView 的绿/红是**按角色**（目标=绿、止损=红）固定的；      |
//|    本指标按**结果**着色：把止盈拖到入场另一侧时，那块区域是亏损，   |
//|    就显示红色并给出负数。即"亏损必红、盈利必绿"，不会被角色骗。     |
//+------------------------------------------------------------------+
#property copyright "PandaTrade"
#property version   "1.10"
#property description "TradingView 风格的多头/空头仓位工具：拖拽入场/止损/止盈线，盈利区绿、亏损区红，"
#property description "实时显示点数、金额、百分比、盈亏比；支持以损定仓（固定 R）反推手数与开仓占用成本。"
#property description "时间宽度：拖工具外侧的菱形抓手，或用面板上的 宽度 -/+ 按钮。"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// 构建指纹：本仓库的规矩 —— 日志里只打印它，不写版本字面量
#define BUILD_TAG   "v1.12-s1"
// 图表对象统一前缀（Rebuild / ObjectsDeleteAll 都靠它）
#define OBJ_PREFIX  "PT_"
// 同时存在的仓位工具上限（状态是固定数组，不用动态数组）
#define MAX_TOOLS   32
// 面板最多几行
#define PANEL_MAX   14
// 折叠按钮的两种文字 —— **文字本身就是状态**（见 LoadUiState），不额外造状态对象
#define FOLD_TEXT_COLLAPSE "收起面板"
#define FOLD_TEXT_EXPAND   "展开面板"
// 与 EA 的接口对象名。⚠️ **跨文件契约**，改这里必须同步改 EA/PositionTrader.mq5
#define INTENT_OBJ  "PT_ORD"
// 面板几何（DrawPanel 与 DrawLotControls 都要用，故提到这里，避免两处各写一份字面量）
#define PANEL_X     10
#define PANEL_Y     52
#define PANEL_W     460
// 手数控件（贴在"手数"那一行右边）
#define EDIT_LOT      "PT_EDIT_LOT"
#define BTN_LOTMINUS  "PT_BTN_LOTMINUS"
#define BTN_LOTPLUS   "PT_BTN_LOTPLUS"
// 时间宽度控件（v1.12-s1）。存在理由 = 抓手在 MT5 里的鼠标命中不是 100% 可靠，
//   这是"无论如何都能改宽度"的兜底通道（见文件头坑⑤）。
#define BTN_WMINUS    "PT_BTN_WMINUS"
#define BTN_WPLUS     "PT_BTN_WPLUS"
// 抓手字形的字号加量：命中框 = 文字外框，故要明显大于正文字号才够好点
#define HANDLE_FONT_ADD 5
// 用户偏好（手动手数）的存放对象。
// ⚠️ 刻意**不**用 OBJ_PREFIX 开头：那样"清空全部"会把用户的偏好一起清掉。
//    代价是 OnDeinit 必须显式删它，否则会漏在图上。
#define UISTATE_OBJ "PT_Prefs"

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
{
   LOT_RISK_PERCENT = 0,   // 按账户风险% 反推手数
   LOT_FIXED        = 1,   // 固定手数
   LOT_FIXED_R      = 2    // 以损定仓：按固定 R 金额反推手数
};

input group "== 仓位与风控 =="
input ENUM_LOT_MODE InpLotMode     = LOT_FIXED_R;      // 手数模式
input double        InpRiskMoney   = 100.0;            // 以损定仓的 R（账户货币固定金额）
input double        InpRiskPercent = 1.0;              // 单笔风险（占账户 %；LOT_RISK_PERCENT 用）
input double        InpFixedLot    = 0.10;             // 固定手数（LOT_FIXED 用）
input double        InpAccountSize = 0.0;              // 账户规模（0 = 用账户余额）

input group "== 新建工具的默认值 =="
input double InpDefaultStopPips = 0.0;   // 默认止损距离（点；0 = 1.5 x ATR14）
input double InpDefaultRR       = 2.0;   // 默认盈亏比（止盈 = 止损 x 该值）
input double InpPipSize         = 0.0;   // 1 点的价格（0 = 自动；3/5 位小数按 10 个最小变动算 1 点）

input group "== 外观 =="
input color InpColorProfit = C'38,166,65';    // 盈利色（绿，涨绿 #26a641）
input color InpColorLoss   = C'248,81,73';    // 亏损色（红，跌红 #f85149）
input color InpColorEntry  = C'88,166,255';   // 入场线色（主蓝 #58a6ff）
input color InpColorHandle = clrWhite;        // 宽度抓手色（画在工具外侧，要显眼）
input int   InpWidthStepBars = 5;             // 宽度按钮每次增减几根 K 线
input color InpColorWarn   = C'240,136,62';   // 警示色（信号橙 #f0883e）
input bool  InpFillZones   = true;            // 是否填充盈亏区域
input int   InpZoneMix     = 25;              // 色块浓淡 %（与图表底色混色；越小越淡，0=纯底色）
input int   InpFontSize    = 9;               // 字号
input color InpPanelBg     = C'13,17,23';     // 面板底色（深背景 #0d1117）
input bool  InpShowPanel   = true;            // 显示信息面板与按钮
input bool  InpKeepOnRemove= false;           // 卸载指标时保留画图（便于重新挂载后恢复）

input group "== 调试 =="
input bool InpDebug = false;  // 专家日志：每个事件一行摘要

//+------------------------------------------------------------------+
//| 状态                                                              |
//+------------------------------------------------------------------+
struct SPos
{
   long     id;        // 工具编号（名字里的一部分）
   bool     isLong;    // 多头 / 空头
   double   entry;     // 入场价
   double   sl;        // 止损价（<=0 = 未设）
   double   tp;        // 止盈价（<=0 = 未设）
   datetime t1;        // 区域左边界
   datetime t2;        // 区域右边界
};

// 由一次计算得出的、绘制与面板共用的度量
struct SMetrics
{
   double pip;        // 1 点的价格
   double slPips;     // 带符号（正 = 盈利方向）
   double tpPips;
   double lots;       // 建议手数（已按最小/步长/最大归一）
   double lotsRaw;    // 归一前的手数（用于提示"低于最小手数"）
   double pnlSL;      // 止损打到时的盈亏（账户货币，正 = 盈利）
   double pnlTP;      // 止盈打到时的盈亏
   double rr;         // 盈亏比（|pnlTP / pnlSL|）
   double acct;       // 用到的账户规模
   double mpp;        // 每手、每 1 个价格单位的账户货币金额
   double margin;     // 开仓占用保证金（账户货币）= 这笔交易的成本
   bool   marginEst;  // true = 保证金是兜底估算（显示时加 ≈）
   double riskMoney;  // 本次设定的计划风险 R（账户货币）
   double minLot;     // 品种最小手数
   bool   lotTooSmall;// true = 按设定算出的手数 < 最小手数 ⇒ **不建议开仓**
   double maxSlPips;  // 反解：最小手数 + R 不变时，止损最多能放到多少点
   bool   lotsManual; // true = 手数是用户手填的（覆盖全部自动口径）
   bool   manualAdj;  // true = 手填值被最小/步长/上限归一过（面板要说明）
   bool   moneyOk;    // 是否拿到了有效的 tick value（拿不到就只能显示点数）
};

SPos g_pos[MAX_TOOLS];
int  g_n      = 0;    // 有效工具数
long g_nextId = 1;    // 下一个可用编号
long g_selId  = -1;   // 当前选中的工具编号（面板显示它）
bool g_collapsed = false;  // 左上角说明面板是否已收起
double g_manualLot = 0.0;  // >0 = 用户手填的手数（覆盖全部自动口径）；0 = 用公式算
int    g_lotRow    = -1;   // "手数"那一行在面板里的行号（-1 = 当前没有这一行）
int    g_widthRow  = -1;   // "宽度"那一行在面板里的行号（-1 = 当前没有这一行）
//--- 测试器兜底（见 PollOwnButtons）
string g_lastBtn   = "";   // 去重：同一按钮 500ms 内只执行一次
uint   g_lastBtnMs = 0;
bool   g_timerSeen = false;  // OnTimer / OnCalculate 首次调用自证
bool   g_calcSeen  = false;
// 面板行缓冲
string g_plText[PANEL_MAX];
color  g_plClr[PANEL_MAX];
int    g_plN = 0;

//+------------------------------------------------------------------+
//| 颜色工具（与 Structure / HTFCandles(已删除) 同构）           |
//| MQL5 的 color 是 0x00BBGGRR —— 最低字节是**红**                    |
//+------------------------------------------------------------------+
uint ClrR(const color c) { return (((uint)c)      ) & 0xFF; }
uint ClrG(const color c) { return (((uint)c) >> 8 ) & 0xFF; }
uint ClrB(const color c) { return (((uint)c) >> 16) & 0xFF; }

color ClrMix(const color a, const color b, const int pct)
{
   int p = pct;
   if(p < 0)   p = 0;
   if(p > 100) p = 100;
   const uint w1 = (uint)(100 - p);
   const uint w2 = (uint)p;
   const uint r  = (ClrR(a) * w1 + ClrR(b) * w2) / 100;
   const uint g  = (ClrG(a) * w1 + ClrG(b) * w2) / 100;
   const uint bl = (ClrB(a) * w1 + ClrB(b) * w2) / 100;
   return (color)((r & 0xFF) | ((g & 0xFF) << 8) | ((bl & 0xFF) << 16));
}

// 带符号的定长数字：+1.23 / -1.23
string Sgn(const double v, const int d)
{
   return (v >= 0.0 ? "+" : "") + DoubleToString(v, d);
}

string AcctCcy()
{
   return AccountInfoString(ACCOUNT_CURRENCY);
}

int DG() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }

// MQL5 没有 TimeframeToString：EnumToString(PERIOD_H1) = "PERIOD_H1"，砍掉前缀即可
string TFName()
{
   const string s = EnumToString(_Period);
   if(StringSubstr(s, 0, 7) == "PERIOD_") return StringSubstr(s, 7);
   return s;
}

//+------------------------------------------------------------------+
//| 名字工具：PT_<id><L|S>_<part>                                |
//|   从名字里反解状态是 Rebuild 的基础（换周期后状态只能从对象里捞）    |
//+------------------------------------------------------------------+
string ObjNameOf(const long id, const bool isLong, const string part)
{
   return OBJ_PREFIX + IntegerToString(id) + (isLong ? "L" : "S") + part;
}

string ObjName(const int i, const string part)
{
   return ObjNameOf(g_pos[i].id, g_pos[i].isLong, part);
}

bool ParseObjName(const string nm, long &id, bool &isLong, string &part)
{
   const int pl = StringLen(OBJ_PREFIX);
   if(StringLen(nm) <= pl) return false;
   if(StringSubstr(nm, 0, pl) != OBJ_PREFIX) return false;

   const string rest = StringSubstr(nm, pl);
   const int    len  = StringLen(rest);
   int k = 0;
   while(k < len)
   {
      const ushort c = StringGetCharacter(rest, k);
      if(c < '0' || c > '9') break;
      k++;
   }
   if(k == 0 || k >= len) return false;

   id = StringToInteger(StringSubstr(rest, 0, k));
   const ushort d = StringGetCharacter(rest, k);
   if(d != 'L' && d != 'S') return false;
   isLong = (d == 'L');
   part   = StringSubstr(rest, k + 1);
   return true;
}

int FindPos(const long id)
{
   for(int i = 0; i < g_n; i++)
      if(g_pos[i].id == id) return i;
   return -1;
}

// 当前工具的时间宽度（根 K 线）。宽度 = 右边界 − 左边界，至少 1 根。
// ⚠️ 只用于**显示**与按钮步进；判定仍以 t1/t2 的绝对时间为准（免得"根数"这种派生量被当成真值）。
int WidthBars(const int i)
{
   const long ps = (long)PeriodSeconds();
   if(ps <= 0 || i < 0 || i >= g_n) return 0;
   long n = (long)(g_pos[i].t2 - g_pos[i].t1) / ps;
   if(n < 1) n = 1;
   return (int)n;
}

//+------------------------------------------------------------------+
//| 品种换算                                                          |
//+------------------------------------------------------------------+
// 1 "点"的价格：外汇 5/3 位小数时 1 点 = 10 个最小变动，其余按最小变动
double PipSize()
{
   if(InpPipSize > 0.0) return InpPipSize;
   const int    dg = DG();
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(dg == 3 || dg == 5) return pt * 10.0;
   return pt;
}

// 每手、每 1 个价格单位对应的账户货币金额
//   用 tick 口径反推，比 SYMBOL_TRADE_TICK_VALUE 直接乘点数更不容易错
double MoneyPerPricePerLot()
{
   const double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ts > 0.0 && tv > 0.0) return tv / ts;

   // 退化路径：tick 数据未就绪时（实测 XAUUSD 在 OnInit 里 tick_value=0）用合约面值兜底。
   // 仅当**盈利货币 == 账户货币**时，contract_size 才正好等于"每手每 1 个价格单位"的金额：
   //   XAUUSD（100oz，盈利货币 USD）：1.00 价格 = 100 USD/手
   //   EURUSD（100000，盈利货币 USD）：1.00000 价格 = 100000 USD/手
   // 账户货币与盈利货币不一致时（如欧元账户做黄金）这里**不猜汇率**，宁可显示"--"
   const string pcy = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   const string acy = AccountInfoString(ACCOUNT_CURRENCY);
   if(pcy == acy && pcy != "")
   {
      const double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(cs > 0.0) return cs;
   }
   return 0.0;
}

// 开仓占用保证金（= 这笔交易的成本）
//   首选 OrderCalcMargin：它按**本经纪商**的保证金公式算，别自己造公式。
//   ⚠️ 但它在本指标里是否可用**未经我验证**（有些终端对指标调用交易类函数有限制），
//      故 false / 0 时按两级兜底，并把结果标记为"估算"（面板上显示 ≈）。
double MarginOf(const double lots, const bool isLong, const double entry, bool &estimated)
{
   estimated = true;
   if(lots <= 0.0) return 0.0;

   double px = entry;
   if(px <= 0.0) px = SymbolInfoDouble(_Symbol, isLong ? SYMBOL_ASK : SYMBOL_BID);
   if(px <= 0.0) return 0.0;

   double m = 0.0;
   if(OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, px, m))
   {
      if(m > 0.0)
      {
         estimated = false;
         return m;
      }
   }

   // 兜底 1：品种声明的每手初始保证金（仅当保证金货币 == 账户货币，否则数字不是账户货币）
   const string mcy = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_MARGIN);
   const string acy = AccountInfoString(ACCOUNT_CURRENCY);
   if(mcy != "" && mcy == acy)
   {
      const double mi = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
      if(mi > 0.0) return mi * lots;
   }

   // 兜底 2：名义价值 / 杠杆（外汇式保证金；贵金属/指数多数也近似成立）
   const double cs  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   const long   lev = AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(cs > 0.0 && lev > 0)
   {
      const double notional = lots * cs * px;
      return notional / (double)lev;
   }

   return 0.0;
}

int LotDigits(const double step)
{
   if(step >= 1.0)   return 0;
   if(step >= 0.1)   return 1;
   if(step >= 0.01)  return 2;
   if(step >= 0.001) return 3;
   return 4;
}

double NormLotRaw(const double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   // +1e-8 是给"0.3 / 0.01 = 29.999999"这类浮点误差留的余量
   return NormalizeDouble(MathFloor(v / step + 1e-8) * step, LotDigits(step));
}

double ClampLot(const double v)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(mn <= 0.0) mn = 0.01;
   if(mx <= 0.0) mx = 100.0;
   double r = v;
   if(r < mn) r = mn;
   if(r > mx) r = mx;
   return r;
}

// 当前价（多头用 Ask、空头用 Bid；拿不到就退化成最后收盘）
double CurPrice(const bool isLong)
{
   double p = SymbolInfoDouble(_Symbol, isLong ? SYMBOL_ASK : SYMBOL_BID);
   if(p <= 0.0) p = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(p <= 0.0) p = iClose(_Symbol, _Period, 0);
   return p;
}

// ATR（手算，避免在 OnInit/OnChartEvent 里依赖指标句柄的就绪状态）
double AtrOf(const int period)
{
   if(Bars(_Symbol, _Period) < period + 1) return 0.0;
   double sum = 0.0;
   // iHigh/iLow/iClose 的 shift 语义天然是"0 = 当前 bar"，不涉及数组方向
   for(int k = 1; k <= period; k++)
   {
      const double pc = iClose(_Symbol, _Period, k);
      const double hi = iHigh(_Symbol, _Period, k);
      const double lo = iLow(_Symbol, _Period, k);
      sum += MathMax(hi, pc) - MathMin(lo, pc);
   }
   return sum / (double)period;
}

//+------------------------------------------------------------------+
//| 度量：点数 / 金额 / 盈亏比 / 建议手数                              |
//|   slPips、tpPips、pnl 全部**带符号**，正 = 盈利方向               |
//|   于是"止损被拖到入场上方"这类怪几何自然给出负数，不需要特判        |
//+------------------------------------------------------------------+
void CalcMetrics(const int i, SMetrics &m)
{
   m.pip     = PipSize();
   m.mpp     = MoneyPerPricePerLot();          // 先算：后面手数/金额/最大止损都要用它
   m.moneyOk = (m.mpp > 0.0);
   m.acct    = (InpAccountSize > 0.0 ? InpAccountSize : AccountInfoDouble(ACCOUNT_BALANCE));

   m.minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(m.minLot <= 0.0) m.minLot = 0.01;

   const int    dir   = (g_pos[i].isLong ? 1 : -1);
   const double entry = g_pos[i].entry;

   m.slPips = 0.0;
   m.tpPips = 0.0;
   if(g_pos[i].sl > 0.0) m.slPips = (g_pos[i].sl - entry) * dir / m.pip;
   if(g_pos[i].tp > 0.0) m.tpPips = (g_pos[i].tp - entry) * dir / m.pip;

   // --- 手数 ---
   m.lotsRaw     = 0.0;
   m.lots        = 0.0;
   m.riskMoney   = 0.0;
   m.lotTooSmall = false;
   m.maxSlPips   = 0.0;
   m.lotsManual  = false;
   m.manualAdj   = false;

   if(g_manualLot > 0.0)
   {
      // 用户手填的手数**优先于一切自动口径**（面板上那个 − / + 与输入框）。
      // ⚠️ 手填值**不参与"不建议开仓"判断**：那是显式指定，不是"算出来不够"；
      //    但被最小/步长/上限归一过就要说明（归一后的实际风险与用户预期不同）。
      m.lotsManual = true;
      m.lotsRaw    = g_manualLot;
      m.riskMoney  = (InpLotMode == LOT_RISK_PERCENT ? m.acct * InpRiskPercent / 100.0
                     : (InpLotMode == LOT_FIXED_R ? InpRiskMoney : 0.0));
      m.lots       = ClampLot(NormLotRaw(g_manualLot));
      m.manualAdj  = (MathAbs(m.lots - g_manualLot) > 1e-9);
   }
   else if(InpLotMode == LOT_FIXED)
   {
      m.lotsRaw = InpFixedLot;
      m.lots    = ClampLot(NormLotRaw(InpFixedLot));
   }
   else
   {
      const double slDist = MathAbs(g_pos[i].sl - entry);
      // 以损定仓：R 是**固定金额**，手数完全由止损距离反推
      //   手数 = R / (止损距离 x 每手每价格单位金额)
      // 按账户风险 %：同一个公式，只是 R 随账户规模浮动
      m.riskMoney = (InpLotMode == LOT_FIXED_R ? InpRiskMoney : m.acct * InpRiskPercent / 100.0);

      if(slDist > 0.0 && m.mpp > 0.0 && m.riskMoney > 0.0)
      {
         const double want = m.riskMoney / (slDist * m.mpp);
         m.lotsRaw = want;
         m.lots    = ClampLot(NormLotRaw(want));
         // 算出来的手数**连最小手数都不到** ⇒ 用最小手数交易会超风险 ⇒ 不建议开仓
         m.lotTooSmall = (want < m.minLot - 1e-9);
      }

      // 反解：手数 >= 最小手数 且风险 <= R 所允许的最大止损宽度
      //   手数 = R / (dist x mpp) >= minLot  ⇒  dist <= R / (minLot x mpp)
      if(m.mpp > 0.0 && m.pip > 0.0 && m.riskMoney > 0.0)
         m.maxSlPips = m.riskMoney / (m.minLot * m.mpp * m.pip);
   }

   // --- 金额 ---
   m.pnlSL = 0.0;
   m.pnlTP = 0.0;
   if(m.mpp > 0.0 && m.lots > 0.0)
   {
      if(g_pos[i].sl > 0.0) m.pnlSL = (g_pos[i].sl - entry) * dir * m.mpp * m.lots;
      if(g_pos[i].tp > 0.0) m.pnlTP = (g_pos[i].tp - entry) * dir * m.mpp * m.lots;
   }

   // --- 开仓占用（成本）---
   m.margin    = 0.0;
   m.marginEst = false;
   if(m.lots > 0.0) m.margin = MarginOf(m.lots, g_pos[i].isLong, entry, m.marginEst);

   // --- 盈亏比 ---
   m.rr = 0.0;
   if(m.pnlSL != 0.0) m.rr = MathAbs(m.pnlTP / m.pnlSL);
}

//+------------------------------------------------------------------+
//| 对象基础设施                                                      |
//+------------------------------------------------------------------+
void EnsureObj(const string nm, const ENUM_OBJECT type,
               const datetime t1, const double p1,
               const datetime t2, const double p2)
{
   if(ObjectFind(0, nm) >= 0)
   {
      if((ENUM_OBJECT)ObjectGetInteger(0, nm, OBJPROP_TYPE) == type) return;
      ObjectDelete(0, nm);   // 同名但类型不对（旧版本残留）→ 重建
   }
   ObjectCreate(0, nm, type, 0, t1, p1, t2, p2);
}

// 水平线（OBJ_TREND，不射线，两端同价）
void DrawHLine(const string nm, const datetime t1, const double p, const datetime t2,
               const color clr, const int width, const string tip, const bool sel)
{
   EnsureObj(nm, OBJ_TREND, t1, p, t2, p);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  0, t1);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, 0, p);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, 1, p);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, true);   // 可拖
   // ⚠️ 这里**不能**设 OBJPROP_HIDDEN=true：那会让对象从 Ctrl+B 对象列表里消失，
   //    等于把"拖不动时的最后一条手动通路"也断了（历史上正是它让画线看起来拖不动）
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   // 主动置为选中：MT5 里**已选中**的对象不必再"点一次"，直接按住就能拖。
   // 这是对"终端单击选中选项关闭 ⇒ 根本选不中 ⇒ 拖不动"的兜底。
   ObjectSetInteger(0, nm, OBJPROP_SELECTED, sel);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1);
   ObjectSetString (0, nm, OBJPROP_TOOLTIP, tip);
}

// 时间宽度抓手（v1.12-s1 重写，见文件头坑⑤）。
//  旧实现：OBJ_ARROW(159) 画在**入场线的两个端点上**，与 OBJ_TREND 端点坐标完全重合
//          ⇒ MT5 的鼠标命中判给了线，用户拖到的永远是入场线（工具整体平移、宽度不变）。
//          日志实证：48 次加载 / 26 次拖动事件，`_HL`/`_HR` **一次都没有**（plan 70.1）。
//  现在：① 位置由 DrawOne 挪到**工具外侧**（离三根线都有距离，见那里的 pH 计算）；
//        ② 换成 OBJ_TEXT：命中框 = 文字外框，比 8px 圆点大得多，且字号可调。
//  ⚠️ 仍然 HIDDEN=false + SELECTABLE=true —— 这两条是坑④的代价换来的，不许动。
void DrawHandle(const string nm, const datetime t, const double p, const color clr, const bool sel)
{
   EnsureObj(nm, OBJ_TEXT, t, p, 0, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  0, t);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, 0, p);
   ObjectSetString (0, nm, OBJPROP_TEXT, "◆");          // ◆ 在 Microsoft YaHei 里有字形
   ObjectSetString (0, nm, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpFontSize + HANDLE_FONT_ADD);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, true);   // 可拖
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);      // 见坑④：HIDDEN=true 会命中不到
   ObjectSetInteger(0, nm, OBJPROP_SELECTED, sel);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 60);         // 高于线(1)/区标签(2)/按钮(50)之下另论
   ObjectSetString (0, nm, OBJPROP_TOOLTIP,
                    "拖动这里 = 调整工具的时间宽度（也可用面板上的 宽度 -/+ 按钮）");
}

void DrawZone(const string nm, const datetime t1, const double pa,
              const datetime t2, const double pb, const color clr, const bool fill)
{
   EnsureObj(nm, OBJ_RECTANGLE, t1, pa, t2, pb);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  0, t1);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, 0, pa);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, 1, pb);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_FILL, fill);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);        // 画在 K 线之下（见文件头坑①）
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false); // 不让它抢鼠标（拖的是线，不是色块）
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 0);
}

void DrawText(const string nm, const datetime t, const double p, const string txt,
              const color clr, const ENUM_ANCHOR_POINT anchor)
{
   EnsureObj(nm, OBJ_TEXT, t, p, 0, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  0, t);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, 0, p);
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
   // ⚠️ 不能用 Consolas：它只有 453KB、**不含中日韩字形**，而区标签里有"点"。
   //    按本仓库的规矩（见 Structure：「字形不是'看着像能显示'」），
   //    只能用**已确认含 CJK** 的字体；msyh.ttc（Microsoft YaHei，19.7MB）即是。
   ObjectSetString (0, nm, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 2);
}

void KillIfExists(const string nm)
{
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
}

//+------------------------------------------------------------------+
//| 绘制一个工具                                                      |
//+------------------------------------------------------------------+
void DrawOne(const int i)
{
   const bool     isLong = g_pos[i].isLong;
   const double   entry  = g_pos[i].entry;
   const double   sl     = g_pos[i].sl;
   const double   tp     = g_pos[i].tp;
   const datetime t1     = g_pos[i].t1;
   const datetime t2     = g_pos[i].t2;
   const int      dir    = (isLong ? 1 : -1);
   const int      dg     = DG();

   SMetrics m;
   CalcMetrics(i, m);

   const bool  sel       = (g_pos[i].id == g_selId);
   const int   entryW    = (sel ? 3 : 2);
   const color cEntry    = InpColorEntry;
   const color cSL       = ((sl > 0.0 && (sl - entry) * dir > 0.0) ? InpColorProfit : InpColorLoss);
   const color cTP       = ((tp > 0.0 && (tp - entry) * dir > 0.0) ? InpColorProfit : InpColorLoss);

   // --- 入场线 ---
   DrawHLine(ObjName(i, "_ENTRY"), t1, entry, t2, cEntry, entryW,
              StringFormat("%s #%d 入场 %s\n拖动这根线 = 整体平移（左右+上下，止损止盈一起走）",
                          (isLong ? "多头" : "空头"), (int)g_pos[i].id,
                          DoubleToString(entry, dg)), sel);
   // 时间宽度抓手（v1.12-s1）：**挪到工具外侧**，离三根线都有距离 —— 否则会与入场线端点
   //   抢鼠标命中（坑⑤）。偏移量取"腿长（止损/止盈里更长的那个）的 1/4"，随工具自适应；
   //   两者都没设时退到 20 点，避免抓手贴着入场线。
   double span = 0.0;
   if(sl > 0.0) span = MathMax(span, MathAbs(entry - sl));
   if(tp > 0.0) span = MathMax(span, MathAbs(entry - tp));
   double hOff = span * 0.25;
   if(hOff <= 0.0) hOff = 20.0 * (m.pip > 0.0 ? m.pip : _Point);
   double pTop = entry;
   if(sl > 0.0) pTop = MathMax(pTop, sl);
   if(tp > 0.0) pTop = MathMax(pTop, tp);
   const double pH = NormalizeDouble(pTop + hOff, dg);
   DrawHandle(ObjName(i, "_HL"), t1, pH, InpColorHandle, sel);
   DrawHandle(ObjName(i, "_HR"), t2, pH, InpColorHandle, sel);

   // --- 止损：线 + 亏损/盈利区 ---
   if(sl > 0.0)
   {
      DrawHLine(ObjName(i, "_SL"), t1, sl, t2, cSL, 2,
                StringFormat("止损 %s   %s 点", DoubleToString(sl, dg), Sgn(m.slPips, 1)), sel);
      DrawZone(ObjName(i, "_ZSL"), t1, entry, t2, sl,
               ClrMix((color)ChartGetInteger(0, CHART_COLOR_BACKGROUND), cSL, InpZoneMix),
               InpFillZones);
      string slTxt = StringFormat("%s 点  (%s%%)\n%s %s", Sgn(m.slPips, 1),
                                  Sgn(m.slPips * m.pip / entry * 100.0, 2),
                                  (m.moneyOk && m.lots > 0.0 ? Sgn(m.pnlSL, 2) : "--"),
                                  AcctCcy());
      // 最小手数都撑不住 R 时，把"不建议开仓"**直接写在亏损区上**，而不是只藏在面板里
      if(m.lotTooSmall) slTxt += "\n⚠ 不建议开仓";
      DrawText(ObjName(i, "_TSL"), t2, (entry + sl) / 2.0, slTxt, cSL, ANCHOR_RIGHT);
   }
   else
   {
      KillIfExists(ObjName(i, "_SL"));
      KillIfExists(ObjName(i, "_ZSL"));
      KillIfExists(ObjName(i, "_TSL"));
   }

   // --- 止盈：线 + 盈利/亏损区 ---
   if(tp > 0.0)
   {
      DrawHLine(ObjName(i, "_TP"), t1, tp, t2, cTP, 2,
                StringFormat("止盈 %s   %s 点", DoubleToString(tp, dg), Sgn(m.tpPips, 1)), sel);
      DrawZone(ObjName(i, "_ZTP"), t1, entry, t2, tp,
               ClrMix((color)ChartGetInteger(0, CHART_COLOR_BACKGROUND), cTP, InpZoneMix),
               InpFillZones);
      DrawText(ObjName(i, "_TTP"), t2, (entry + tp) / 2.0,
               StringFormat("%s 点  (%s%%)\n%s %s", Sgn(m.tpPips, 1),
                            Sgn(m.tpPips * m.pip / entry * 100.0, 2),
                            (m.moneyOk && m.lots > 0.0 ? Sgn(m.pnlTP, 2) : "--"),
                            AcctCcy()),
               cTP, ANCHOR_RIGHT);
   }
   else
   {
      KillIfExists(ObjName(i, "_TP"));
      KillIfExists(ObjName(i, "_ZTP"));
      KillIfExists(ObjName(i, "_TTP"));
   }

   // --- 左端标签：方向 + 入场价（放在入场线上方，ANCHOR_LEFT_LOWER） ---
   DrawText(ObjName(i, "_TAG"), t1, entry,
            StringFormat("%s #%d  %s", (isLong ? "LONG" : "SHORT"), (int)g_pos[i].id,
                         DoubleToString(entry, dg)),
            cEntry, ANCHOR_LEFT_LOWER);

   if(InpDebug)
      PrintFormat("DBG %s draw #%d %s entry=%s sl=%s tp=%s lots=%.2f rr=%.2f risk=%.2f margin=%.2f est=%s mode=%d",
                  BUILD_TAG, (int)g_pos[i].id, (isLong ? "LONG" : "SHORT"),
                  DoubleToString(entry, dg), DoubleToString(sl, dg), DoubleToString(tp, dg),
                  m.lots, m.rr, m.riskMoney, m.margin, (m.marginEst ? "Y" : "N"), (int)InpLotMode);
}

//+------------------------------------------------------------------+
//| 面板                                                              |
//+------------------------------------------------------------------+
void PL(const string s, const color c)
{
   if(g_plN < PANEL_MAX)
   {
      g_plText[g_plN] = s;
      g_plClr[g_plN]  = c;
      g_plN++;
   }
}

void MakeButton(const string nm, const string txt, const int x, const int y,
                const int w, const int h, const color fg, const color bg)
{
   EnsureObj(nm, OBJ_BUTTON, 0, 0.0, 0, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
   ObjectSetString (0, nm, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, ClrMix(bg, clrWhite, 30));
   ObjectSetInteger(0, nm, OBJPROP_STATE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   // 按钮也必须 HIDDEN=false：本指标已经实测过"隐藏对象鼠标命中不到"这颗地雷，
   // 不再在同一个坑上赌第二次（代价只是对象列表里多 4 个条目）
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 50);
}

void MakePanelBg(const int x, const int y, const int w, const int h)
{
   const string nm = OBJ_PREFIX + "PANELBG";
   EnsureObj(nm, OBJ_RECTANGLE_LABEL, 0, 0.0, 0, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, InpPanelBg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, ClrMix(InpPanelBg, clrWhite, 25));
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 40);
}

void MakePanelLine(const int idx, const int x, const int y,
                   const string txt, const color c)
{
   const string nm = OBJ_PREFIX + "PL" + IntegerToString(idx);
   EnsureObj(nm, OBJ_LABEL, 0, 0.0, 0, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
   ObjectSetString (0, nm, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 45);
}

// 折叠状态**不额外存**：折叠按钮的文字本身就是状态。
//   换周期 / 改参数 / 重编译时对象都还在，故读回按钮文字就能恢复 ——
//   不需要第二个存储位，也就不存在"两个存储位不一致"的可能。
// 手动手数就没这么幸运了（它是个数值，没有现成的宿主），
// 故借一个**空文字标签**的 TOOLTIP 存 —— TOOLTIP 不会被渲染，对象视觉上不存在。
void SaveUiState()
{
   const string nm = UISTATE_OBJ;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 0);
      ObjectSetString (0, nm, OBJPROP_TEXT, "");      // 空文字 = 什么都不画
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   }
   ObjectSetString(0, nm, OBJPROP_TOOLTIP,
                   StringFormat("manualLot=%s", DoubleToString(g_manualLot, 4)));
}

void LoadUiState()
{
   g_collapsed = false;   // 新挂载（按钮还不存在）= 默认展开
   const string nm = OBJ_PREFIX + "BTN_TOGGLE";
   if(ObjectFind(0, nm) >= 0)
      g_collapsed = (ObjectGetString(0, nm, OBJPROP_TEXT) == FOLD_TEXT_EXPAND);

   g_manualLot = 0.0;
   if(ObjectFind(0, UISTATE_OBJ) >= 0)
   {
      const string tp = ObjectGetString(0, UISTATE_OBJ, OBJPROP_TOOLTIP);
      const int p = StringFind(tp, "manualLot=");
      if(p >= 0) g_manualLot = StringToDouble(StringSubstr(tp, p + 10));
      if(g_manualLot < 0.0) g_manualLot = 0.0;
   }
   if(InpDebug) PrintFormat("DBG %s loadui collapsed=%s manualLot=%.2f",
                            BUILD_TAG, (g_collapsed ? "Y" : "N"), g_manualLot);
}

// 把说明区（面板底 + 全部文字行）清掉 —— "收起"与"关掉面板"共用
void HideInfoPanel()
{
   KillIfExists(OBJ_PREFIX + "PANELBG");
   for(int k = 0; k < PANEL_MAX; k++)
      KillIfExists(OBJ_PREFIX + "PL" + IntegerToString(k));
}

//+------------------------------------------------------------------+
//| 手数控件：贴在"手数"那一行的右边                                    |
//|   一个输入框 + 两个步进按钮。行不存在（没选中工具 / 面板收起 / 关掉）|
//|   就整组删掉 —— 不留孤儿对象。                                     |
//+------------------------------------------------------------------+
double StepOfLot()
{
   double s = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(s <= 0.0) s = 0.01;
   return s;
}

// OBJ_EDIT 是 MT5 里唯一能"直接在图上敲数"的对象（探针已验证常量存在）
void MakeEdit(const string nm, const string txt, const int x, const int y,
              const int w, const int h, const string tip)
{
   EnsureObj(nm, OBJ_EDIT, 0, 0.0, 0, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
   ObjectSetString (0, nm, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nm, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, nm, OBJPROP_READONLY, false);   // 可编辑
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, C'30,36,48');
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, ClrMix(InpPanelBg, clrWhite, 35));
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 55);
   ObjectSetString (0, nm, OBJPROP_TOOLTIP, tip);
}

void DrawWidthControls()
{
   const int si = FindPos(g_selId);
   if(!InpShowPanel || g_collapsed || g_widthRow < 0 || si < 0)
   {
      KillIfExists(BTN_WMINUS);
      KillIfExists(BTN_WPLUS);
      return;
   }

   const int lh = InpFontSize + 8;
   const int y  = PANEL_Y + 6 + g_widthRow * lh;
   const int h  = 16;
   const int bw = 46;
   const int x2 = PANEL_X + PANEL_W - 8 - bw;    // "放宽"
   const int x1 = x2 - 4 - bw;                   // "变窄"

   MakeButton(BTN_WMINUS, "-" + IntegerToString(InpWidthStepBars), x1, y, bw, h, clrWhite, C'52,58,70');
   MakeButton(BTN_WPLUS,  "+" + IntegerToString(InpWidthStepBars), x2, y, bw, h, clrWhite, C'52,58,70');
   ObjectSetString(0, BTN_WMINUS, OBJPROP_TOOLTIP,
                   StringFormat("时间宽度收窄 %d 根（等价于把右端抓手往左拖）", InpWidthStepBars));
   ObjectSetString(0, BTN_WPLUS,  OBJPROP_TOOLTIP,
                   StringFormat("时间宽度放宽 %d 根（等价于把右端抓手往右拖）", InpWidthStepBars));
}

// 时间宽度按"根数"增减。只动右边界（t1 固定）—— 与拖右端抓手同一语义，两个入口不打架。
void StepWidth(const int sign)
{
   const int si = FindPos(g_selId);
   if(si < 0) return;
   const long ps = (long)PeriodSeconds();
   if(ps <= 0) return;
   const long step = (long)InpWidthStepBars * ps;
   if(step <= 0) return;

   datetime t2 = g_pos[si].t2 + (datetime)(sign * step);
   // 至少留 1 根：右边界必须严格大于左边界（否则线与矩形都退化，MT5 会画出不可见对象）
   if(t2 <= g_pos[si].t1) t2 = g_pos[si].t1 + (datetime)ps;
   g_pos[si].t2 = t2;

   if(InpDebug)
      PrintFormat("DBG %s width %s -> %d bar(s)", BUILD_TAG, (sign > 0 ? "+" : "-"),
                  (int)((g_pos[si].t2 - g_pos[si].t1) / ps));
   DrawAll();
}

void DrawLotControls()
{
   const int si = FindPos(g_selId);
   if(!InpShowPanel || g_collapsed || g_lotRow < 0 || si < 0)
   {
      KillIfExists(EDIT_LOT);
      KillIfExists(BTN_LOTMINUS);
      KillIfExists(BTN_LOTPLUS);
      return;
   }

   SMetrics m;
   CalcMetrics(si, m);

   const int lh = InpFontSize + 8;
   const int y  = PANEL_Y + 6 + g_lotRow * lh;
   const int h  = 16;                                     // 行高 17 → 控件 16，不压下一行
   const int xe = PANEL_X + PANEL_W - 8 - 24 - 4 - 58;     // 输入框左边界

   const string stepTxt = DoubleToString(StepOfLot(), 2);
   MakeButton(BTN_LOTMINUS, "-", xe - 4 - 24, y, 24, h, clrWhite, C'52,58,70');
   MakeEdit  (EDIT_LOT, DoubleToString(m.lots, 2), xe, y, 58, h,
              StringFormat("%s直接输入手数后回车即改为手动；填 0 或清空 = 回到自动",
                           (m.lotsManual ? "当前是手动手数。\n" : "当前是按公式算的。\n")));
   MakeButton(BTN_LOTPLUS, "+", xe + 58 + 4, y, 24, h, clrWhite, C'52,58,70');

   ObjectSetString(0, BTN_LOTMINUS, OBJPROP_TOOLTIP, "手数减一个步长（" + stepTxt + "）");
   ObjectSetString(0, BTN_LOTPLUS,  OBJPROP_TOOLTIP, "手数加一个步长（" + stepTxt + "）");
}

// 步进：第一次按时以"当前生效手数"为基准，按一下就从自动切成手动
void StepLot(const int sign)
{
   const int si = FindPos(g_selId);
   if(si < 0) return;

   SMetrics m;
   CalcMetrics(si, m);

   const double step = StepOfLot();
   const double base = (g_manualLot > 0.0 ? g_manualLot : m.lots);
   double next = base + (double)sign * step;

   const double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(mn > 0.0 && next < mn) next = mn;
   if(next <= 0.0) next = step;

   g_manualLot = NormalizeDouble(next, LotDigits(step));
   SaveUiState();
   if(InpDebug) PrintFormat("DBG %s steplot sign=%d base=%.2f -> manual=%.2f",
                            BUILD_TAG, sign, base, g_manualLot);
   DrawAll();
}

// 输入框编辑完成（回车 / 点到别处）：0 或空 = 取消手动
void ApplyLotEdit()
{
   const string txt = ObjectGetString(0, EDIT_LOT, OBJPROP_TEXT);
   const double v   = StringToDouble(txt);
   g_manualLot = (v > 0.0 ? v : 0.0);
   SaveUiState();
   if(InpDebug) PrintFormat("DBG %s lotedit <%s> -> manual=%.2f", BUILD_TAG, txt, g_manualLot);
   DrawAll();
}

void DrawButtons()
{
   const int bx  = 10;
   const int byy = 22;
   const int bh  = 22;
   MakeButton(OBJ_PREFIX + "BTN_LONG",  "+ 做多",   bx,       byy, 84, bh, clrWhite, C'22,101,52');
   MakeButton(OBJ_PREFIX + "BTN_SHORT", "+ 做空",   bx + 90,  byy, 84, bh, clrWhite, C'150,44,44');
   MakeButton(OBJ_PREFIX + "BTN_DEL",   "删除选中", bx + 180, byy, 80, bh, clrWhite, C'52,58,70');
   MakeButton(OBJ_PREFIX + "BTN_CLR",   "清空全部", bx + 266, byy, 80, bh, clrWhite, C'52,58,70');

   if(!InpShowPanel)
   {
      // 面板被输入参数整个关掉时，折叠按钮没有意义 → 清掉
      KillIfExists(OBJ_PREFIX + "BTN_TOGGLE");
      return;
   }

   MakeButton(OBJ_PREFIX + "BTN_TOGGLE",
              (g_collapsed ? FOLD_TEXT_EXPAND : FOLD_TEXT_COLLAPSE),
              bx + 356, byy, 88, bh, clrWhite, (g_collapsed ? C'96,72,20' : C'52,58,70'));
   ObjectSetString(0, OBJ_PREFIX + "BTN_TOGGLE", OBJPROP_TOOLTIP,
                   (g_collapsed ? "面板已收起：手数 / 成本 / 盈亏比被隐藏，点此展开"
                                : "收起左上角说明面板，只留操作按钮（画线与工具不受影响）"));
}

void DrawPanel()
{
   const int bx = PANEL_X;      // 面板左
   const int by = PANEL_Y;      // 面板上
   const int bw = PANEL_W;      // 面板宽（"算式"与"不建议开仓"两行较长）
   const int lh = InpFontSize + 8;

   g_plN    = 0;
   g_lotRow = -1;
   g_widthRow = -1;

   // 按钮**始终**画：面板收起/关掉时它是唯一的建仓入口，跟着一起藏就等于没入口
   DrawButtons();

   // 收起 或 关掉面板：只把说明区拿掉，按钮不动（位置也不动，免得肌肉记忆失效）
   if(!InpShowPanel || g_collapsed)
   {
      HideInfoPanel();
      DrawLotControls();    // g_lotRow<0 ⇒ 会把手数控件一并删掉
      DrawWidthControls();  // g_widthRow<0 ⇒ 宽度按钮一并删掉
      return;
   }

   const int si = FindPos(g_selId);
   if(si < 0)
   {
      PL("Position Tool  " + BUILD_TAG, clrSilver);
      if(g_n == 0)
         PL("点【+ 做多 / + 做空】新建仓位工具", ClrMix(InpPanelBg, clrWhite, 85));
      else
         PL("点任意一根线选中工具（或按 + 新建）", ClrMix(InpPanelBg, clrWhite, 85));
      PL("拖入场线 = 整体平移；拖止损/止盈线 = 单独调整", ClrMix(InpPanelBg, clrWhite, 70));
      PL("拖工具外侧的 ◆ = 调整时间宽度；Delete = 删除选中", ClrMix(InpPanelBg, clrWhite, 70));
      if(g_n > 0)
         PL(StringFormat("图上共 %d 个工具，当前未选中", g_n), ClrMix(InpPanelBg, clrWhite, 70));
   }
   else
   {
      const int      dg      = DG();
      const int      dir     = (g_pos[si].isLong ? 1 : -1);
      const double   entry   = g_pos[si].entry;
      const color    cEntry  = InpColorEntry;
      const color    cSL     = ((g_pos[si].sl > 0.0 && (g_pos[si].sl - entry) * dir > 0.0) ? InpColorProfit : InpColorLoss);
      const color    cTP     = ((g_pos[si].tp > 0.0 && (g_pos[si].tp - entry) * dir > 0.0) ? InpColorProfit : InpColorLoss);

      SMetrics m;
      CalcMetrics(si, m);

      const string ccy = AcctCcy();

      PL(StringFormat("%s #%d   %s  %s", (g_pos[si].isLong ? "做多 LONG" : "做空 SHORT"),
                      (int)g_pos[si].id, _Symbol, TFName()), cEntry);
      PL(StringFormat("入场  %s", DoubleToString(entry, dg)), cEntry);

      if(g_pos[si].sl > 0.0)
         PL(StringFormat("止损  %s   %s 点   %s   (%s%%)",
                         DoubleToString(g_pos[si].sl, dg), Sgn(m.slPips, 1),
                         (m.moneyOk && m.lots > 0.0 ? Sgn(m.pnlSL, 2) + " " + ccy : "--"),
                         Sgn(m.slPips * m.pip / entry * 100.0, 2)), cSL);
      if(g_pos[si].tp > 0.0)
         PL(StringFormat("止盈  %s   %s 点   %s   (%s%%)",
                         DoubleToString(g_pos[si].tp, dg), Sgn(m.tpPips, 1),
                         (m.moneyOk && m.lots > 0.0 ? Sgn(m.pnlTP, 2) + " " + ccy : "--"),
                         Sgn(m.tpPips * m.pip / entry * 100.0, 2)), cTP);

      PL(StringFormat("盈亏比  %s   (1 点 = %s)",
                      (m.pnlSL != 0.0 ? "1 : " + DoubleToString(m.rr, 2) : "--"),
                      DoubleToString(m.pip, dg)), clrSilver);

      // 时间宽度那一行：右边贴「-N / +N」两个按钮（与"手数"行同一套做法）。
      //  存在理由：抓手的鼠标命中在 MT5 里不是 100% 可靠（见文件头坑⑤），这是兜底通道。
      g_widthRow = g_plN;
      PL(StringFormat("宽度  %d 根", WidthBars(si)), clrSilver);

      // --- 手数 / 成本（这几行刻意写成可手算复核的形式，而不是只丢一个数字）---
      const double perPoint = m.pip * m.mpp;   // 每点、每手的账户货币价值

      // 记下"手数"这一行的行号：− / + / 输入框要贴在这一行右边。
      // 三个分支都**以这一行开头**，故在这里记一次即可。
      g_lotRow = g_plN;

      if(m.lotsManual)
      {
         // 手动优先：手填值覆盖一切自动口径。控件就在这一行右边，不用再解释怎么改。
         PL(StringFormat("手数  %s（手动指定%s）",
                         DoubleToString(m.lots, 2),
                         (m.manualAdj ? "，已按最小/步长归一" : "")), clrSilver);
         if(m.manualAdj)
            PL(StringFormat("注意：手填 %s 被归一为 %s（本品种最小 %s / 步长 %s）",
                            DoubleToString(g_manualLot, 4), DoubleToString(m.lots, 2),
                            DoubleToString(m.minLot, 2), DoubleToString(StepOfLot(), 2)),
               InpColorLoss);
      }
      else if(m.lotTooSmall)
      {
         // 算出的手数连最小手数都不到 ⇒ 用最小手数下单**必然超风险** ⇒ 直接判"不建议开仓"。
         // ⚠️ 这里**不能**显示被 Clamp 上去的 0.01——那个数字会被当成"可以下"。
         PL("手数  --（⚠ 不建议开仓）", InpColorWarn);
         PL(StringFormat("⚠ 最小手数 %s 下亏损 %s %s（> 设定 R %s %s）",
                         DoubleToString(m.minLot, 2), DoubleToString(MathAbs(m.pnlSL), 2), ccy,
                         DoubleToString(m.riskMoney, 2), ccy), InpColorWarn);
         PL(StringFormat("  止损收到 ≤ %s 点（现 %s 点），或 R 提到 ≥ %s %s",
                         DoubleToString(m.maxSlPips, 1), DoubleToString(MathAbs(m.slPips), 1),
                         DoubleToString(MathAbs(m.pnlSL), 2), ccy), InpColorWarn);
      }
      else if(InpLotMode == LOT_FIXED)
      {
         PL(StringFormat("手数  %s（固定手数）", DoubleToString(m.lots, 2)), clrSilver);
         if(InpFixedLot < m.minLot - 1e-9)
            PL(StringFormat("注意：固定手数 %s 低于最小手数 %s，已取最小手数",
                            DoubleToString(InpFixedLot, 2), DoubleToString(m.minLot, 2)), InpColorLoss);
      }
      else
      {
         PL((InpLotMode == LOT_FIXED_R
             ? StringFormat("手数  %s（以损定仓  R = %s %s）",
                            DoubleToString(m.lots, 2), DoubleToString(InpRiskMoney, 2), ccy)
             // ⚠️ 这一行必须短：右边要留给 − / 输入框 / + 三个控件。
             //    账户规模与 R 的换算在下面"算式"那一行已经摊开了，这里不重复。
             : StringFormat("手数  %s（风险 %s%%）",
                            DoubleToString(m.lots, 2), DoubleToString(InpRiskPercent, 2))), clrSilver);
         // 算式一律摊开：三种模式的手数都是同一条公式，只是 R 的来源不同
         PL(StringFormat("算式  R %s / (止损 %s 点 x %s %s/点/手) = %s 手",
                         DoubleToString(m.riskMoney, 2), DoubleToString(MathAbs(m.slPips), 1),
                         DoubleToString(perPoint, 2), ccy, DoubleToString(m.lots, 2)),
            ClrMix(InpPanelBg, clrWhite, 75));
      }

      if(m.lots > 0.0 && m.margin > 0.0)
         PL(StringFormat("成本  %s%s %s 保证金（%s）",
                         (m.marginEst ? "≈" : ""), DoubleToString(m.margin, 2), ccy,
                         (m.marginEst ? "估算" : "经纪商公式")), clrSilver);

      if(!m.moneyOk)
         PL("注意：本品种取不到 tick value，只显示点数不显示金额", InpColorLoss);
   }

   // 面板底 + 每行一个 label（label 不支持换行，故一行一个对象）
   MakePanelBg(bx, by, bw, 10 + g_plN * lh);
   for(int k = 0; k < PANEL_MAX; k++)
   {
      if(k < g_plN) MakePanelLine(k, bx + 8, by + 6 + k * lh, g_plText[k], g_plClr[k]);
      else          MakePanelLine(k, bx + 8, by + 6 + k * lh, "", clrNONE);
   }

   // 手数控件贴在"手数"那一行右边（行号已在上面记好）；宽度按钮同理
   DrawLotControls();
   DrawWidthControls();
}

void DrawChrome()
{
   DrawPanel();
}

void DrawAll()
{
   for(int i = 0; i < g_n; i++) DrawOne(i);
   DrawChrome();
   PublishIntent();   // 把当前选中工具的挂单意图发布给 EA（指标自己不能下单）
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 与 EA 的接口：发布挂单意图                                         |
//+------------------------------------------------------------------+
//|  为什么必须有这一层：MQL5 的**指标不能下单**，故发单在 EA 里做。   |
//|  几何（入场/止损/止盈）EA 其实能从对象里读，但**手数读不到** ——    |
//|  它是 R / 风险% / 最小手数一起算出来的。若让 EA 再算一遍，就等于   |
//|  把同一套定仓公式维护两份，"两个真相源"迟早对不上。故指标发布      |
//|  **结论**，EA 只消费。                                           |
//|                                                                  |
//|  载荷存在对象名 = INTENT_OBJ 的 **OBJPROP_TOOLTIP** 里，而不是     |
//|  OBJPROP_TEXT：TOOLTIP 不会被渲染，故这个对象可以是"空文字标签"    |
//|  —— 视觉上完全不存在，也就没有"藏对象藏出可见垃圾"的风险。         |
//|                                                                  |
//|  格式（`|` 分隔，字段顺序是契约）：                                |
//|    TVPT1|NONE                                          无选中工具  |
//|    TVPT1|<L|S>|<entry>|<sl>|<tp>|<lots>|<R>|<noTrade>|<id>          |
//+------------------------------------------------------------------+
void PublishIntent()
{
   const string nm = INTENT_OBJ;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 0);
      ObjectSetString (0, nm, OBJPROP_TEXT, "");      // 空文字 = 不渲染任何东西
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false); // 留在 Ctrl+B 列表里，便于自查
   }

   const int si = FindPos(g_selId);
   string payload;
   if(si < 0)
   {
      payload = "TVPT1|NONE";
   }
   else
   {
      SMetrics m;
      CalcMetrics(si, m);
      payload = StringFormat("TVPT1|%s|%s|%s|%s|%s|%s|%d|%d",
                             (g_pos[si].isLong ? "L" : "S"),
                             DoubleToString(g_pos[si].entry, DG()),
                             DoubleToString(g_pos[si].sl, DG()),
                             DoubleToString(g_pos[si].tp, DG()),
                             DoubleToString(m.lots, 2),
                             DoubleToString(m.riskMoney, 2),
                             (m.lotTooSmall ? 1 : 0),
                             (int)g_pos[si].id);
   }
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, payload);
   if(InpDebug) PrintFormat("DBG %s publish <%s>", BUILD_TAG, payload);
}

//+------------------------------------------------------------------+
//| 工具增删                                                          |
//+------------------------------------------------------------------+
void CreateTool(const bool isLong)
{
   if(g_n >= MAX_TOOLS)
   {
      PrintFormat("DBG %s 已达工具上限 %d，未新建", BUILD_TAG, MAX_TOOLS);
      return;
   }

   const int    dg   = DG();
   const double pip  = PipSize();
   const double px   = CurPrice(isLong);

   double stopDist = InpDefaultStopPips * pip;
   if(stopDist <= 0.0)
   {
      const double atr = AtrOf(14);
      stopDist = (atr > 0.0 ? atr * 1.5 : 200.0 * pip);
   }
   const double rr = (InpDefaultRR > 0.0 ? InpDefaultRR : 2.0);

   const double entry = NormalizeDouble(px, dg);
   const double sl    = NormalizeDouble(isLong ? entry - stopDist : entry + stopDist, dg);
   const double tp    = NormalizeDouble(isLong ? entry + stopDist * rr : entry - stopDist * rr, dg);

   // 初始时间宽度：左边留 20 根、右边伸到未来 20 根（K 线不足时用服务器时间兜底）
   datetime t1 = iTime(_Symbol, _Period, MathMin(20, MathMax(0, Bars(_Symbol, _Period) - 1)));
   if(t1 <= 0) t1 = TimeCurrent() - (datetime)(20 * PeriodSeconds());
   const datetime t2 = (iTime(_Symbol, _Period, 0) > 0 ? iTime(_Symbol, _Period, 0) : TimeCurrent())
                       + (datetime)(20 * PeriodSeconds());

   g_pos[g_n].id     = g_nextId;
   g_pos[g_n].isLong = isLong;
   g_pos[g_n].entry  = entry;
   g_pos[g_n].sl     = sl;
   g_pos[g_n].tp     = tp;
   g_pos[g_n].t1     = t1;
   g_pos[g_n].t2     = t2;
   g_selId = g_nextId;
   g_nextId++;
   g_n++;

   if(InpDebug)
      PrintFormat("DBG %s create #%d %s entry=%s sl=%s tp=%s", BUILD_TAG, (int)g_selId,
                  (isLong ? "LONG" : "SHORT"), DoubleToString(entry, dg),
                  DoubleToString(sl, dg), DoubleToString(tp, dg));

   DrawAll();
}

void DeletePos(const int i)
{
   const string parts[] = {"_ENTRY", "_SL", "_TP", "_ZSL", "_ZTP",
                           "_TSL", "_TTP", "_TAG", "_HL", "_HR"};
   for(int k = 0; k < ArraySize(parts); k++)
      KillIfExists(ObjName(i, parts[k]));

   for(int k = i; k < g_n - 1; k++) g_pos[k] = g_pos[k + 1];
   g_n--;
   g_selId = -1;
}

void DeleteSelected()
{
   const int i = FindPos(g_selId);
   if(i < 0) return;
   if(InpDebug) PrintFormat("DBG %s delete #%d", BUILD_TAG, (int)g_selId);
   DeletePos(i);
   if(g_n > 0) g_selId = g_pos[g_n - 1].id;   // 自动选中下一个，面板不会空掉
   DrawAll();
}

void DeleteAllTools()
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
   g_n = 0;
   g_selId = -1;
   DrawAll();
}

//+------------------------------------------------------------------+
//| Rebuild：把状态从既有图表对象里捞回来                              |
//|   换周期 / 改参数 / 重新挂载都要靠它，否则画的东西会"消失"          |
//+------------------------------------------------------------------+
void Rebuild()
{
   g_n = 0;
   g_selId = -1;
   g_nextId = 1;

   // 第一趟：找所有 _ENTRY，建立 id/方向/入场价
   const int total = ObjectsTotal(0, 0, -1);
   for(int k = 0; k < total; k++)
   {
      const string nm = ObjectName(0, k, 0, -1);
      long   id   = 0;
      bool   isL  = false;
      string part = "";
      if(!ParseObjName(nm, id, isL, part)) continue;
      if(part != "_ENTRY") continue;
      if(FindPos(id) >= 0) continue;
      if(g_n >= MAX_TOOLS) continue;

      g_pos[g_n].id     = id;
      g_pos[g_n].isLong = isL;
      g_pos[g_n].entry  = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
      g_pos[g_n].sl     = 0.0;
      g_pos[g_n].tp     = 0.0;
      g_pos[g_n].t1     = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
      g_pos[g_n].t2     = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
      if(id >= g_nextId) g_nextId = id + 1;
      g_n++;
   }

   // 第二趟：补齐止损/止盈/时间宽度
   for(int i = 0; i < g_n; i++)
   {
      const string ns = ObjName(i, "_SL");
      const string nt = ObjName(i, "_TP");
      const string nz = ObjName(i, "_ZTP");
      const string nz2= ObjName(i, "_ZSL");

      if(ObjectFind(0, ns) >= 0) g_pos[i].sl = ObjectGetDouble(0, ns, OBJPROP_PRICE, 0);
      if(ObjectFind(0, nt) >= 0) g_pos[i].tp = ObjectGetDouble(0, nt, OBJPROP_PRICE, 0);

      // 时间宽度以矩形为准（线的时间端点会被拖拽归一化，矩形才是权威）
      const string nrect = (ObjectFind(0, nz) >= 0 ? nz : nz2);
      if(ObjectFind(0, nrect) >= 0)
      {
         g_pos[i].t1 = (datetime)ObjectGetInteger(0, nrect, OBJPROP_TIME, 0);
         g_pos[i].t2 = (datetime)ObjectGetInteger(0, nrect, OBJPROP_TIME, 1);
      }
      if(g_pos[i].t2 <= g_pos[i].t1)
         g_pos[i].t2 = g_pos[i].t1 + (datetime)(20 * PeriodSeconds());
   }

   if(g_n > 0) g_selId = g_pos[g_n - 1].id;
   if(InpDebug) PrintFormat("DBG %s rebuild -> %d tool(s)", BUILD_TAG, g_n);
}

//+------------------------------------------------------------------+
//| 事件                                                              |
//+------------------------------------------------------------------+
void OnDragObj(const string nm)
{
   long   id   = 0;
   bool   isL  = false;
   string part = "";
   if(!ParseObjName(nm, id, isL, part)) return;

   const int i = FindPos(id);
   if(i < 0) return;

   const int      dg = DG();
   const double   p0 = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
   const datetime t0 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);

   if(part == "_ENTRY")
   {
      // 拖入场线 = 整体平移（TradingView 同款手感）
      if(g_pos[i].entry <= 0.0) return;
      const double delta = p0 - g_pos[i].entry;
      g_pos[i].entry = NormalizeDouble(g_pos[i].entry + delta, dg);
      if(g_pos[i].sl > 0.0) g_pos[i].sl = NormalizeDouble(g_pos[i].sl + delta, dg);
      if(g_pos[i].tp > 0.0) g_pos[i].tp = NormalizeDouble(g_pos[i].tp + delta, dg);

      // 时间轴也一起平移。
      // ⚠️ 少了这一步，横向拖动会被 DrawHLine 的归一化原样抹掉 ——
      //    用户看到的现象就是"这条线怎么拖都不动"。
      if(t0 > 0 && g_pos[i].t1 > 0)
      {
         const long dt = (long)t0 - (long)g_pos[i].t1;
         if(dt != 0)
         {
            g_pos[i].t1 += (datetime)dt;
            g_pos[i].t2 += (datetime)dt;
         }
      }
   }
   else if(part == "_SL")
   {
      g_pos[i].sl = NormalizeDouble(p0, dg);
   }
   else if(part == "_TP")
   {
      g_pos[i].tp = NormalizeDouble(p0, dg);
   }
   else if(part == "_HL")
   {
      if(t0 < g_pos[i].t2) g_pos[i].t1 = t0;
      else                 g_pos[i].t1 = g_pos[i].t2 - (datetime)PeriodSeconds();
   }
   else if(part == "_HR")
   {
      if(t0 > g_pos[i].t1) g_pos[i].t2 = t0;
      else                 g_pos[i].t2 = g_pos[i].t1 + (datetime)PeriodSeconds();
   }
   else return;

   g_selId = id;
   if(InpDebug)
      PrintFormat("DBG %s drag %s -> entry=%s sl=%s tp=%s", BUILD_TAG, nm,
                  DoubleToString(g_pos[i].entry, dg), DoubleToString(g_pos[i].sl, dg),
                  DoubleToString(g_pos[i].tp, dg));

   DrawAll();
}

void OnClickObj(const string nm)
{
   if(nm == OBJ_PREFIX + "BTN_LONG")
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      CreateTool(true);
      return;
   }
   if(nm == OBJ_PREFIX + "BTN_SHORT")
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      CreateTool(false);
      return;
   }
   if(nm == OBJ_PREFIX + "BTN_DEL")
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      DeleteSelected();
      return;
   }
   if(nm == OBJ_PREFIX + "BTN_CLR")
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      DeleteAllTools();
      return;
   }
   if(nm == OBJ_PREFIX + "BTN_TOGGLE")
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      g_collapsed = !g_collapsed;   // DrawButtons 会把新状态写进按钮文字 ⇒ 状态就地持久化
      DrawAll();
      return;
   }
   if(nm == BTN_LOTMINUS)
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      StepLot(-1);
      return;
   }
   if(nm == BTN_LOTPLUS)
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      StepLot(+1);
      return;
   }
   if(nm == BTN_WMINUS)
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      StepWidth(-1);
      return;
   }
   if(nm == BTN_WPLUS)
   {
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ChartRedraw();
      StepWidth(+1);
      return;
   }

   // 点任意一根线 → 选中该工具（面板切换显示对象）
   long   id   = 0;
   bool   isL  = false;
   string part = "";
   if(!ParseObjName(nm, id, isL, part)) return;
   if(FindPos(id) < 0) return;
   if(g_selId != id)
   {
      g_selId = id;
      DrawAll();
   }
}

//+------------------------------------------------------------------+
//| 生命周期                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Position Tool " + BUILD_TAG);
   IndicatorSetInteger(INDICATOR_DIGITS, DG());

   Rebuild();          // 不清空重画：换周期/改参数/重挂载都从对象里恢复（见文件头坑③）
   LoadUiState();      // 折叠状态从折叠按钮的文字里读回（同一套"状态在对象里"的思路）
   DrawAll();

   // 一次性探针：确认 OrderCalcMargin 在本指标里能不能调（这是"成本"一栏是否精确的前提）。
   // 打这行日志是为了让"能不能用"由日志自证，而不是靠我猜文档。
   double probeM   = 0.0;
   double probeLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(probeLot <= 0.0) probeLot = 0.01;
   const bool probeOk = OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, probeLot, CurPrice(true), probeM);

   PrintFormat("DBG %s init %s %s tools=%d pip=%s mpp=%.5f | marginProbe=%s %.2f (lot=%.2f)",
               BUILD_TAG, _Symbol, TFName(), g_n,
               DoubleToString(PipSize(), DG()), MoneyPerPricePerLot(),
               (probeOk ? "OK" : "FAIL"), probeM, probeLot);

   // 测试器兜底用的定时器：**只在测试器里装**（实盘点击事件是通的，不需要多一个每秒唤醒）
   if(MQLInfoInteger(MQL_TESTER))
   {
      EventSetTimer(1);
      PrintFormat("DBG %s 测试器模式：已装 1 秒定时器做按钮轮询兜底", BUILD_TAG);
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // 只有"真的被卸载"才清图；换周期/改参数/重编译要留着，等 OnInit 里的 Rebuild 接手
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_PROGRAM)
   {
      if(!InpKeepOnRemove)
      {
         ObjectsDeleteAll(0, OBJ_PREFIX);
         // UISTATE_OBJ 刻意不在 OBJ_PREFIX 之下（免得"清空全部"清掉用户偏好），
         // 所以这里必须**单独**删，否则它会漏在图上。
         KillIfExists(UISTATE_OBJ);
      }
   }
   ChartRedraw();
   if(InpDebug) PrintFormat("DBG %s deinit reason=%d (keep=%s)", BUILD_TAG, reason,
                            (InpKeepOnRemove ? "true" : "false"));
}

//+------------------------------------------------------------------+
//| 测试器兜底：轮询自己的按钮状态                                      |
//|   策略测试器**不一定会把 CHARTEVENT_OBJECT_CLICK 送给指标**          |
//|   （社区已知老问题），表现就是"指标按钮在回测里点了没反应"。          |
//|   但**按钮被点击后的 STATE 状态是被正确设置的** —— 故改读状态。      |
//|   只在测试器里启用：实盘的点击事件是通的，不需要多一个每秒唤醒。      |
//|   去重用 GetTickCount()（墙钟）而不是 TimeCurrent() ——               |
//|   测试器里服务器时间会随 tick 跳，拿它做时间窗是错的。                |
//+------------------------------------------------------------------+
void PollOwnButtons()
{
   // ⚠️ 刻意**不**把 EDIT_LOT 放进来：它不是按钮，没有 STATE 语义。
   //    测试器里输入框的"编辑完成"事件多半也来不了 —— 但 − / + 两个按钮是按钮，
   //    走轮询是通的，所以手数在测试器里靠点 − / + 调，不靠打字。
   const string btns[] = {OBJ_PREFIX + "BTN_LONG",  OBJ_PREFIX + "BTN_SHORT",
                          OBJ_PREFIX + "BTN_DEL",   OBJ_PREFIX + "BTN_CLR",
                          OBJ_PREFIX + "BTN_TOGGLE",
                          BTN_LOTMINUS, BTN_LOTPLUS, BTN_WMINUS, BTN_WPLUS};
   for(int k = 0; k < ArraySize(btns); k++)
   {
      if(ObjectFind(0, btns[k]) < 0) continue;
      if(!(bool)ObjectGetInteger(0, btns[k], OBJPROP_STATE)) continue;

      // 去重：同一个按钮 500ms 内只执行一次（事件路径可能同时也到达）
      const uint now = GetTickCount();
      if(btns[k] == g_lastBtn && (now - g_lastBtnMs) < 500)
      {
         ObjectSetInteger(0, btns[k], OBJPROP_STATE, false);
         return;
      }
      g_lastBtn   = btns[k];
      g_lastBtnMs = now;

      ObjectSetInteger(0, btns[k], OBJPROP_STATE, false);   // 消费掉这次按下
      PrintFormat("DBG %s poll-click <%s>", BUILD_TAG, btns[k]);
      OnClickObj(btns[k]);
      return;   // 一次只处理一个，避免连锁
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      // 这一行是"拖不动"的诊断锚点：拖完**必须**在专家日志里看到它。
      // 看不到 ⇒ 事件根本没来，问题在 MT5 的选中/拖动机制，不在这份代码里。
      PrintFormat("DBG %s object-drag <%s>", BUILD_TAG, sparam);
      OnDragObj(sparam);
   }
   else if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(InpDebug) PrintFormat("DBG %s object-click <%s>", BUILD_TAG, sparam);
      g_lastBtn   = sparam;                 // 记下，免得轮询再执行一次
      g_lastBtnMs = GetTickCount();
      OnClickObj(sparam);
   }
   else if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      // 手数输入框编辑完成（回车 / 焦点移走）。
      // 探针已验证：这个事件**不需要** ChartSetInteger 开关，是自动产生的。
      if(InpDebug) PrintFormat("DBG %s object-endedit <%s>", BUILD_TAG, sparam);
      if(sparam == EDIT_LOT) ApplyLotEdit();
   }
   else if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 46)   // Delete
      {
         DeleteSelected();
      }
   }
}

// 指标侧的定时器：**只在测试器里**跑，给轮询兜底一个不依赖行情的节拍。
// ⚠️ "测试器里指标能不能用 OnTimer"我不确定（探针验证过的只有 EA 那边能用），
//    所以这里打一行首次调用日志，让"到底哪个钩子活着"由日志自证。
void OnTimer()
{
   if(!g_timerSeen)
   {
      g_timerSeen = true;
      PrintFormat("DBG %s hook OnTimer 首次被调用（指标在测试器里能用定时器）", BUILD_TAG);
   }
   PollOwnButtons();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // 本指标不产生 buffer：一切都靠对象画。
   // 唯一要做的是**测试器里的按钮轮询兜底**（见 PollOwnButtons 的说明）。
   if(MQLInfoInteger(MQL_TESTER))
   {
      if(!g_calcSeen)
      {
         g_calcSeen = true;
         PrintFormat("DBG %s hook OnCalculate 首次被调用（测试器里指标确实在被计算）", BUILD_TAG);
      }
      PollOwnButtons();
   }
   return rates_total;
}
//+------------------------------------------------------------------+
