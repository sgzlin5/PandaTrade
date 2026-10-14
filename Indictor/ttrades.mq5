//+------------------------------------------------------------------+
//|  ttrades.mq5                                                     |
//|  TTFM° — TTrades Fractal Model（主图叠加）                        |
//+------------------------------------------------------------------+
//|  移植来源：ttrades/pinescript                                      |
//|    simon-ru/ttrades @48cfa89，Pine v6，2015 行                     |
//|    头部署名 © mindyourbuisness / "Based on HTF Candles by Fadi"   |
//|  口径依据：docs/research/2026-09-23-TTFM-rules-report.md            |
//|  移植说明：docs/plans/2026-10-13-ttrades-mq5-port.md                |
//|            （§1 逐条对照 / §2 与原 Pine 的行为差异 / §3 待实测点）  |
//+------------------------------------------------------------------+
//|  与原 Pine 的行为差异（与"口径"分栏读）：                          |
//|   1. HTF 蜡烛：Pine 用"图上 bar 聚合 + time(HTF) 边界"构造，且只在   |
//|      最后 1000 根 bar 内构建；本实现直接 CopyRates(HTF)，无该限制。  |
//|   2. HTF 起始竖线：Pine 用 line.new(y1=0, y2=1, extend.both)。那个   |
//|      y=0 锚点会把纵轴拉到 0（克隆平台实测已复现）——改用 OBJ_VLINE。 |
//|   3. 信息表：MT5 没有 table 对象的文字排版，改为 4 行 OBJ_LABEL 面板。 |
//|   4. T-Spot 的判定式逐条照抄 Pine（行号见各分支注释）；Silver 的时段  |
//|      条件在 Pine 里本就是自定口径（一手资料只有 kill zone 叙述）。   |
//|   5. "反向 T-Spot 删除/隐藏"只保留了隐藏（改色），未移植删除逻辑。   |
//+------------------------------------------------------------------+
#property copyright "PandaTrade"
#property version   "1.00"
#property indicator_chart_window          // 主图叠加（对应 Pine overlay = true）
#property indicator_buffers 1
#property indicator_plots   1
// 一条隐藏线：只为让指标在数据窗口有一行；值恒为 EMPTY_VALUE，不参与定标。
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrNONE
#property indicator_label1  "TTFM scale"

#define OBJ_PREFIX     "TTFM_"
// 构建指纹：本仓库硬约定 4 —— 日志只打印它，不写版本字面量
#define BUILD_TAG      "v1.03-s1"   // v1.03：面板默认左下角（空白角）；四角通用 ANCHOR+行序
#define CHART_LOOKBACK 600     // 图上回看 bar 数（pivot/CISD 序列/ATR200 都在此窗口内）
#define MAX_HTF_SETS   6

//--- 枚举 ---
enum ENUM_HTF_MODE   { HTF_AUTO = 0, HTF_CUSTOM = 1 };
enum ENUM_TSPOT_BIAS { BIAS_NONE = 0, BIAS_BULLISH = 1, BIAS_BEARISH = 2 };
enum ENUM_RISK_TYPE  { RISK_PERCENT = 0, RISK_AMOUNT = 1 };
enum ENUM_TS_STYLE   { TS_SOLID = 0, TS_DASHED = 1, TS_DOTTED = 2 };

//--- 输入参数 ---
input group "== 高周期 HTF =="
input ENUM_HTF_MODE   InpHtfMode        = HTF_AUTO;      // HTF 模式
input ENUM_TIMEFRAMES InpHtfCustom      = PERIOD_W1;     // 自定义 HTF（Mode=Custom 生效）
input ENUM_TSPOT_BIAS InpTspotBias      = BIAS_NONE;     // T-Spot 方向过滤
input bool            InpShowHtf        = true;          // 显示 HTF 蜡烛
input int             InpHtfMaxDisplay  = 4;             // 显示最近 N 根（1..6）
input int             InpHtfOffsetBars  = 20;            // 距最后一根 K 线的偏移（图 bar）
input int             InpHtfBodyBars    = 2;             // 实体宽度（图 bar）
input int             InpHtfBufferBars  = 1;             // 蜡烛间距（图 bar）
input int             InpHtfGapBars     = 7;             // HTF 组间距（图 bar）
input color           InpBullBody       = C'138,191,145';// 阳线实体
input color           InpBearBody       = C'224,140,137';// 阴线实体
input color           InpBullWick       = C'138,191,145';// 阳线影线/边框
input color           InpBearWick       = C'224,140,137';// 阴线影线/边框
input bool            InpHtfLabelShow   = true;          // HTF 名称标签
input color           InpHtfLabelColor  = clrBlack;      // HTF 标签颜色
input bool            InpHtfTimerShow   = true;          // HTF 剩余时间
input color           InpHtfTimerColor  = clrBlack;      // 剩余时间颜色
input bool            InpHtfLineShow    = true;          // HTF 起始竖线
input color           InpHtfLineColor   = clrBlack;      // 起始竖线颜色
input ENUM_LINE_STYLE InpHtfLineStyle   = STYLE_DOT;     // 起始竖线线型
input int             InpHtfLineWidth   = 1;             // 起始竖线宽度

input group "== T-Spot =="
input bool           InpShowTspot       = true;          // 显示 T-Spot
input bool           InpShowOnlyLatest  = true;          // 只保留最新 T-Spot
input bool           InpExtendLatest    = true;          // 最新 T-Spot 延伸到当前 bar
input bool           InpShowChartSweeps = true;          // 扫破位水平短线
input int            InpBodyFillPercent = 30;            // T-Spot 填充强度 %（相对图表底色）
input ENUM_TS_STYLE  InpTspotLineStyle  = TS_DOTTED;     // 中线/收盘线线型
input int            InpMidlineWidth    = 1;             // 中线宽度
input bool           InpShowCloseLine   = true;          // 显示 T-Spot 收盘线
input bool           InpShowSilver      = true;          // Silver T-Spot
input bool           InpShowTtfmLabels  = true;          // C2/C3/C4 标签
input bool           InpHideAgainst     = true;          // 逆向 T-Spot 隐藏（改色）
input bool           InpShowSweeps      = true;          // T-Spot Sweep 确认
input bool           InpShowConfLines   = true;          // 确认线
input bool           InpShowConfLabels  = true;          // 确认标签
input bool           InpUseBodyPivots   = false;         // 用实体（open/close）判 pivot

input group "== CISD / 投影 =="
input bool   InpShowCisd   = true;                       // 显示 CISD 线
input color  InpColorCisd  = C'66,133,244';              // CISD 颜色
input int    InpCisdWidth  = 2;                          // CISD 宽度
input bool   InpShowProj   = true;                       // 显示目标投影
input color  InpColorProj  = C'255,152,0';               // 投影颜色
input string InpProjLevels = "1,0,-1,-2,-2.5,-4";        // 投影水平（逗号分隔）
input bool   InpExtendProj = true;                       // 投影延伸到当前 bar

input group "== 仓位提示 =="
input bool           InpShowPosSize    = true;           // 显示仓位建议
input double         InpAccountBalance = 10000.0;        // 账户余额
input ENUM_RISK_TYPE InpRiskType       = RISK_PERCENT;   // 风险类型
input double         InpRiskAmount     = 1.0;            // 风险值（% 或 金额）
input bool           InpAbbrevPos      = false;          // 面板缩写（Sz/En/St）

input group "== 面板 =="
input bool             InpShowPanel     = true;          // 显示信息面板
input ENUM_BASE_CORNER InpPanelCorner   = CORNER_LEFT_LOWER;  // 面板位置（默认左下：左上/右上常被其他 EA 的面板、按钮、时间轴占住）
input int              InpPanelFontSize = 9;             // 字号
input color            InpPanelColor    = clrBlack;      // 文字颜色

input group "== 告警 / 调试 =="
input bool InpAlertPopup = true;                         // 弹窗告警 Alert()
input bool InpAlertPush  = false;                        // 手机推送 SendNotification()
input bool InpDebugShow  = false;                        // 专家日志：每全量帧一行摘要

//--- 隐藏缓冲区 ---
double g_scale[];

//--- 图上 bar 的本地副本（series 方向：索引 0 = 最新）---
double   g_o[], g_h[], g_l[], g_c[];
datetime g_t[];
int      g_n = 0;

//--- HTF 数据副本 ---
double   g_ho[], g_hh[], g_hl[], g_hc[];
datetime g_ht[];

//--- 运行态 ---
int      g_win = 0;
string   g_tfName = "";       // 当前 HTF 的显示名（1H/4H/1D…）
ENUM_TIMEFRAMES g_htf = PERIOD_H1;
datetime g_lastHtfT0 = 0;      // 已处理的 HTF 当前 bar 开盘时间
datetime g_lastSweepT = 0;    // 上次扫破确认告警所在图 bar（防同 bar 重复告警）
datetime g_lastChartT0 = 0;    // 已处理的图 bar 开盘时间
bool     g_tspotCreated = false;
// 最新 T-Spot 的几何与方向（触碰/确认用）
string   g_tsKey = "";
int      g_tsDir = 0;          // +1 看涨 / -1 看跌
double   g_tsMid = 0.0, g_tsHi = 0.0, g_tsLo = 0.0;
// 触碰状态
bool     g_touched = false;
string   g_touchKey = "";  // 触碰状态所属的 T-Spot key（换了就复位）
double   g_touchLevel = 0.0;
datetime g_touchT = 0;
// pivot（图 bar，series 索引 2 处确认）
double   g_pivHigh = 0.0, g_pivLow = 0.0;
datetime g_pivHighT = 0, g_pivLowT = 0;
// 最近信号（面板）
bool   g_hasSig = false;
string g_sigDir = "";
double g_sigEntry = 0.0, g_sigStop = 0.0, g_sigLots = 0.0;


//+------------------------------------------------------------------+
//| 颜色工具（与 Structure 同构：MQL5 color = 0x00BBGGRR）      |
//+------------------------------------------------------------------+
uint ClrR(const color c){ return (((uint)c)     ) & 0xFF; }
uint ClrG(const color c){ return (((uint)c) >> 8 ) & 0xFF; }
uint ClrB(const color c){ return (((uint)c) >> 16) & 0xFF; }
color ClrMake(const uint r, const uint g, const uint b){ return (color)(r | (g << 8) | (b << 16)); }

//| 按图表底色混色：fill = bg + (base − bg) × pct / 100
//|  ⚠️ 必须混向实际底色（CONTEXT v1.49 硬约定 7：不许假设黑底）
color MixFill(const color base, const color bg, const int pct)
{
   if(pct <= 0 || pct >= 100) return base;
   double a = pct / 100.0;
   uint r = (uint)MathRound((1.0 - a) * (double)ClrR(bg) + a * (double)ClrR(base));
   uint g = (uint)MathRound((1.0 - a) * (double)ClrG(bg) + a * (double)ClrG(base));
   uint b = (uint)MathRound((1.0 - a) * (double)ClrB(bg) + a * (double)ClrB(base));
   return ClrMake(r, g, b);
}

//+------------------------------------------------------------------+
//| 对象层。全部返回 bool（"是否本次新建"），调用点一律显式赋值        |
//|  ⚠️ 硬约定 2：有副作用的调用禁止写在 || / && 右侧                  |
//+------------------------------------------------------------------+
bool UpsertRect(const string name, const datetime t1, const double p1,
                const datetime t2, const double p2, const color clr, const bool fill)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, g_win, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetInteger(0, name, OBJPROP_FILL,       fill);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      return true;
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL,  fill);
   return false;
}

bool UpsertTrend(const string name, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr,
                 const int width, const ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, g_win, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      return true;
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   return false;
}

bool UpsertVLine(const string name, const datetime t, const color clr,
                 const int width, const ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_VLINE, g_win, t, 0.0);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      return true;
   }
   ObjectMove(0, name, 0, t, 0.0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   return false;
}

bool UpsertText(const string name, const datetime t, const double p, const string txt,
                const color clr, const int fontsize, const ENUM_ANCHOR_POINT anchor)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, g_win, t, p);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontsize);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
      ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetString (0, name, OBJPROP_TEXT,       txt);
      return true;
   }
   ObjectMove(0, name, 0, t, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString (0, name, OBJPROP_TEXT,  txt);
   return false;
}

//| 面板行（角标对象，窗口 0）
bool UpsertPanelLine(const string name, const int row, const string txt, const int fontsize)
{
   bool rightCorner = (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER);
   bool lowerCorner = (InpPanelCorner == CORNER_LEFT_LOWER  || InpPanelCorner == CORNER_RIGHT_LOWER);
   int x = 10;
   // 下角时 Y 从底边往上量 ⇒ 行序取反，读起来仍是 PN_0 在最上（自上而下 0/1/2/3）
   int y = 16 + (lowerCorner ? (3 - row) : row) * (fontsize + 4);
   // 锚点必须跟着角走：四角各用自己的锚点，文字才朝图内延伸。
   // 之前没设 OBJPROP_ANCHOR —— 默认锚点在右上角会把整行推到图上边缘之外（4 行全看不见）。
   ENUM_ANCHOR_POINT anc;
   if(rightCorner) anc = lowerCorner ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER;
   else            anc = lowerCorner ? ANCHOR_LEFT_LOWER  : ANCHOR_LEFT_UPPER;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     InpPanelCorner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anc);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontsize);
      ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      InpPanelColor);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
      ObjectSetString (0, name, OBJPROP_TEXT,       txt);
      return true;
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,    InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anc);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     InpPanelColor);
   ObjectSetString (0, name, OBJPROP_TEXT,      txt);
   return false;
}

//+------------------------------------------------------------------+
//| 对象回收                                                          |
//+------------------------------------------------------------------+
void DeletePrefix(const string prefix)
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, prefix) == 0) ObjectDelete(0, nm);
   }
}

//| 删除一个 T-Spot key 的全部附属对象
//|  key = 该 T-Spot 所在 HTF 蜡烛的开盘时间（字符串化），见 ProcessTspot
void DeleteKey(const string key)
{
   string groups[7] = {"TS_", "TSM_", "TSC_", "SW_", "C2_", "C3_", "SV_"};
   for(int g = 0; g < 7; g++)
   {
      string nm = OBJ_PREFIX + groups[g] + key;
      if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   }
   string tails[3] = {"_PJ_" + key, "_PL_" + key, "_CISD_" + key};
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string nm2 = ObjectName(0, i, -1, -1);
      if(StringFind(nm2, OBJ_PREFIX) != 0) continue;
      for(int t = 0; t < 3; t++)
         if(StringFind(nm2, tails[t]) >= 0) { ObjectDelete(0, nm2); break; }
   }
}

//| 统计 T-Spot 组数，并返回最旧一组的 key（key 为时间戳，可直接比大小）
string OldestTspotKey(int &count)
{
   count = 0;
   string best = "";
   long   bestV = 0;
   int    total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, OBJ_PREFIX + "TS_") != 0) continue;
      string key = StringSubstr(nm, StringLen(OBJ_PREFIX) + 3);
      long v = (long)StringToInteger(key);
      count++;
      if(best == "" || v < bestV) { best = key; bestV = v; }
   }
   return best;
}


//+------------------------------------------------------------------+
//| 数据层：图 bar 与 HTF bar 的本地副本（series 方向：0 = 最新）      |
//+------------------------------------------------------------------+
bool CopyChart(const int want)
{
   int n = MathMin(want, Bars(_Symbol, _Period));
   if(n < 30) return false;
   ArrayResize(g_o, n); ArrayResize(g_h, n); ArrayResize(g_l, n);
   ArrayResize(g_c, n); ArrayResize(g_t, n);
   ArraySetAsSeries(g_o, true); ArraySetAsSeries(g_h, true); ArraySetAsSeries(g_l, true);
   ArraySetAsSeries(g_c, true); ArraySetAsSeries(g_t, true);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, _Period, 0, n, r);
   if(got < 30) return false;
   g_n = got;
   for(int i = 0; i < got; i++)
   {
      g_o[i] = r[i].open;  g_h[i] = r[i].high;  g_l[i] = r[i].low;
      g_c[i] = r[i].close; g_t[i] = r[i].time;
   }
   return true;
}

bool CopyHtf(const int want)
{
   int n = MathMax(want, 4);
   ArrayResize(g_ho, n); ArrayResize(g_hh, n); ArrayResize(g_hl, n);
   ArrayResize(g_hc, n); ArrayResize(g_ht, n);
   ArraySetAsSeries(g_ho, true); ArraySetAsSeries(g_hh, true); ArraySetAsSeries(g_hl, true);
   ArraySetAsSeries(g_hc, true); ArraySetAsSeries(g_ht, true);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, g_htf, 0, n, r);
   if(got < 4) return false;
   for(int i = 0; i < got; i++)
   {
      g_ho[i] = r[i].open;  g_hh[i] = r[i].high;  g_hl[i] = r[i].low;
      g_hc[i] = r[i].close; g_ht[i] = r[i].time;
   }
   return true;
}

string PriceStr(const double v){ return DoubleToString(v, _Digits); }

ENUM_LINE_STYLE StyleOf(const ENUM_TS_STYLE s)
{
   if(s == TS_SOLID)  return STYLE_SOLID;
   if(s == TS_DASHED) return STYLE_DASH;
   return STYLE_DOT;
}

//| 高周期映射（照抄 Pine 行 203-221 的 Auto 表）
ENUM_TIMEFRAMES AutoHtf(const ENUM_TIMEFRAMES chartTf)
{
   switch(chartTf)
   {
      case PERIOD_M1:  return PERIOD_M15;
      case PERIOD_M3:  return PERIOD_M30;
      case PERIOD_M5:  return PERIOD_H1;
      case PERIOD_M15: return PERIOD_H4;
      case PERIOD_M30: return PERIOD_D1;
      case PERIOD_H1:  return PERIOD_D1;
      case PERIOD_H4:  return PERIOD_W1;
      case PERIOD_H8:  return PERIOD_W1;
      case PERIOD_D1:  return PERIOD_MN1;
   }
   return PERIOD_W1;   // Pine 的默认 fallback
}

//| HTF 蜡烛叠加画在最后一根 K 线右侧 → 未来时间
datetime FutureTime(const int bars)
{
   return (datetime)((long)g_t[0] + (long)bars * (long)PeriodSeconds(_Period));
}

//+------------------------------------------------------------------+
//| 数学层                                                            |
//+------------------------------------------------------------------+
//| Pine calculateLogMidpoint（行 958-976）：对数中点，实体/影线取大者那一侧的一半
double LogMidpoint(const double h, const double l, const double o, const double c)
{
   if(h <= 0.0 || l <= 0.0 || h <= l) return (h + l) / 2.0;
   double lh = MathLog(h), ll = MathLog(l), lo = MathLog(o), lc = MathLog(c);
   double body = MathAbs(lc - lo);
   double up   = lh - MathMax(lo, lc);
   double dn   = MathMin(lo, lc) - ll;
   if(MathMax(up, dn) > body) return (up > dn) ? MathExp(lh - up / 2.0) : MathExp(ll + dn / 2.0);
   return MathExp((lh + ll) / 2.0);
}

//| Pine ta.atr(period)（RMA）取最新值。种子用最旧一根的 TR（与 Wilder 首值口径略差，见移植说明 §2）
double AtrRma(const int period)
{
   if(period < 1 || g_n < period + 2) return 0.0;
   double val = 0.0;
   for(int i = period; i >= 0; i--)
   {
      double tr = MathMax(g_h[i] - g_l[i],
                  MathMax(MathAbs(g_h[i] - g_c[i + 1]), MathAbs(g_l[i] - g_c[i + 1])));
      if(i == period) val = tr;
      else            val = (val * (period - 1) + tr) / period;
   }
   return val;
}

//+------------------------------------------------------------------+
//| 会话/时区（Silver T-Spot 的时段过滤用）                            |
//|  ⚠️ Pine 用 hour(time, "America/New_York")；MQL5 无时区库，这里按  |
//|     "服务器时间 − UTC 偏移 + 美东 DST 规则" 近似。DST 规则已实现，  |
//|     但与交易所时区表仍有边界差异 → 属待实测点（移植说明 §3）。       |
//+------------------------------------------------------------------+
int NthSunday(const int year, const int mon, const int nth)
{
   MqlDateTime d;
   d.year = year; d.mon = mon; d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
   datetime t = StructToTime(d);
   MqlDateTime e;
   TimeToStruct(t, e);
   int delta = (7 - e.day_of_week) % 7;     // day_of_week: 0 = 周日
   return 1 + delta + (nth - 1) * 7;
}

bool IsUsDst(const datetime utc)
{
   MqlDateTime s;
   TimeToStruct(utc, s);
   int y = s.year;
   MqlDateTime a, b;
   a.year = y; a.mon = 3;  a.day = NthSunday(y, 3, 2);  a.hour = 7; a.min = 0; a.sec = 0;
   b.year = y; b.mon = 11; b.day = NthSunday(y, 11, 1); b.hour = 6; b.min = 0; b.sec = 0;
   datetime start = StructToTime(a), stop = StructToTime(b);
   return (utc >= start && utc < stop);
}

int ServerToNyHour(const datetime serverT)
{
   long off = (long)TimeTradeServer() - (long)TimeGMT();   // 服务器相对 UTC 的秒偏移
   datetime utc = (datetime)((long)serverT - off);
   int shift = IsUsDst(utc) ? -4 : -5;
   datetime ny = (datetime)((long)utc + (long)shift * 3600);
   MqlDateTime st;
   TimeToStruct(ny, st);
   return st.hour;
}

//| Pine candleOfDay = floor(hour(time)/4) + 1（行 1070-1073）
int CandleOfDay()
{
   MqlDateTime st;
   TimeToStruct(g_t[0], st);
   return st.hour / 4 + 1;
}

//| Silver 的时段条件（Pine 行 1225 / 1295 / 1341 / 1388 / 1440 / 1475）
bool SilverSession()
{
   int cod = CandleOfDay();
   if(cod == 5) return true;
   if(cod == 4 && ServerToNyHour(g_t[0]) >= 13) return true;
   return false;
}

//+------------------------------------------------------------------+
//| HTF 偏置（Pine GetHTFBias，行 787-830）                            |
//+------------------------------------------------------------------+
string HtfBias()
{
   if(g_hh[1] <= 0.0 || g_hh[2] <= 0.0) return "Neutral";
   double lo = g_ho[1], lc = g_hc[1], lh = g_hh[1], ll = g_hl[1];
   double ph = g_hh[2], pl = g_hl[2];
   bool sweptHigh = (lh > ph);
   bool sweptLow  = (ll < pl);
   if(lc > ph) return "Bullish";
   if(lc < pl) return "Bearish";
   if(sweptHigh && lc < ph) return "Bearish";
   if(sweptLow  && lc > pl) return "Bullish";
   if(!sweptHigh && !sweptLow) return "Neutral";
   if(sweptHigh && sweptLow)
   {
      double up = lh - MathMax(lo, lc);
      double dn = MathMin(lo, lc) - ll;
      if(dn > up) return "Bearish";
      if(up > dn) return "Bullish";
   }
   return "Neutral";
}

//| Pine findLevelBarIndex（行 369-377）：在图上 bar 找 high/low == 该价位的最近一根
int FindLevelBar(const double level, const int maxBars)
{
   int lim = MathMin(maxBars, g_n - 1);
   for(int i = 0; i <= lim; i++)
      if(g_h[i] == level || g_l[i] == level) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| 仓位建议：lots = 风险金额 / (止损距离 / tickSize × tickValue)        |
//|  取不到 tickValue 的品种返回 0（面板显示 n/a）—— 不猜              |
//+------------------------------------------------------------------+
double RiskMoney()
{
   if(InpRiskType == RISK_AMOUNT) return InpRiskAmount;
   return InpAccountBalance * InpRiskAmount / 100.0;
}

double CalcLots(const double entry, const double stop, const double riskMoney)
{
   double dist = MathAbs(entry - stop);
   if(dist <= 0.0 || riskMoney <= 0.0) return 0.0;
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ts <= 0.0 || tv <= 0.0) return 0.0;
   double perLot = dist / ts * tv;
   if(perLot <= 0.0) return 0.0;
   double lots = riskMoney / perLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step > 0.0) lots = MathFloor(lots / step) * step;
   if(vmin > 0.0 && lots < vmin) lots = vmin;
   return lots;
}

string FmtLots(const double lots)
{
   if(lots <= 0.0) return "n/a";
   return DoubleToString(lots, 2) + (InpAbbrevPos ? " lt" : " lots");
}


//+------------------------------------------------------------------+
//| 告警（Pine 用 CAL.customAlert；MT5 用 Alert + SendNotification）    |
//+------------------------------------------------------------------+
void FireAlert(const string msg)
{
   if(InpAlertPopup) Alert("TTFM: " + msg);
   if(InpAlertPush)  SendNotification("TTFM: " + msg);
}

//| 告警去重：同一事件只报一次（key = 事件类型 + 事件唯一标识）
//|   为什么需要：CheckSweepConfirm 每 tick 都跑，而"收在 pivot 之上/开在其下"是整根 bar
//|   的固定属性 ⇒ 同一根 bar 上只要价格满足条件就会每个 tick 报一次（反复弹窗）。
#define ALERT_KEY_MAX 64
string g_alertKeys[ALERT_KEY_MAX];
int    g_alertHead = 0;

bool AlertOnce(const string key)
{
   for(int i = 0; i < ALERT_KEY_MAX; i++)
      if(g_alertKeys[i] == key) return false;      // 已报过
   g_alertKeys[g_alertHead] = key;                 // 记下并环形推进（满了淘汰最旧）
   g_alertHead = (g_alertHead + 1) % ALERT_KEY_MAX;
   return true;
}

//+------------------------------------------------------------------+
//| CISD + 目标投影（Pine detectCISDAndProjections，行 602-700）        |
//|  c2Idx    ：C2 在图 bar 上的 series 索引（0 = 最新）               |
//|  c2Extreme：C2 的受保护价位（看涨用低点，看跌用高点）                |
//|  endT     ：右端时间（= 当前 HTF 周期结束），与 Pine end_bar 同义   |
//+------------------------------------------------------------------+
void DetectCisd(const int c2Idx, const double c2Extreme, const bool isBull,
                const datetime endT, const string key)
{
   if(c2Idx <= 0 || c2Idx >= g_n) return;

   double seriesHigh, seriesLow;
   if(InpUseBodyPivots)
   {
      seriesHigh = MathMax(g_o[c2Idx], g_c[c2Idx]);
      seriesLow  = MathMin(g_o[c2Idx], g_c[c2Idx]);
   }
   else
   {
      seriesHigh = c2Extreme;      // Pine：不用实体时，序列从 C2 极值这个"点"起
      seriesLow  = c2Extreme;
   }
   int seriesCount = 1;
   for(int i = 1; i <= 20; i++)    // Pine：从 C2 往回最多 20 根
   {
      int k = c2Idx + i;
      if(k >= g_n) break;
      bool bullCandle = (g_c[k] > g_o[k]);
      bool want = isBull ? (!bullCandle) : (bullCandle);   // 看涨要阴线序列
      if(!want) break;
      double ch = InpUseBodyPivots ? MathMax(g_o[k], g_c[k]) : g_h[k];
      double cl = InpUseBodyPivots ? MathMin(g_o[k], g_c[k]) : g_l[k];
      seriesHigh = MathMax(seriesHigh, ch);
      seriesLow  = MathMin(seriesLow,  cl);
      seriesCount++;
   }

   bool broken = false;
   int  breakIdx = -1;
   for(int i = c2Idx; i >= 0; i--)    // 从 C2 向前找到收盘穿破序列的那一刻
   {
      if(isBull ? (g_c[i] > seriesHigh) : (g_c[i] < seriesLow))
      { broken = true; breakIdx = i; break; }
   }
   if(!broken) return;

   double seriesRange   = seriesHigh - seriesLow;
   double seriesExtreme = isBull ? seriesHigh : seriesLow;

   if(InpShowCisd)
   {
      int oldest = c2Idx + (seriesCount - 1);
      if(oldest >= g_n) oldest = g_n - 1;
      string nm = OBJ_PREFIX + "CISD_" + key;
      UpsertTrend(nm, g_t[oldest], seriesExtreme, g_t[breakIdx], seriesExtreme,
                  InpColorCisd, InpCisdWidth, STYLE_SOLID);
   }
   if(!InpShowProj) return;
   if(seriesRange <= 0.0) return;

   // ==== 投影锚点：TTrades 口径（与 ttrades.mine / pinescript 同步改）====
   // 操纵腿 = CISD 之前那次扫流动性的摆动：看涨 → 之前的最后一个低点（= c2Extreme，C2 扫破低点）
   //   看跌 → 之前的最后一个高点；腿另一端 = 造势序列极值（= 水平 0）；从 Candle 2 起量；看跌高→低、看涨低→高
   // 水平 "1,0,-1,-2,-2.5,-4"：0 = 腿末端，-N = 沿交易方向再走 N 倍腿长，+1 = 回到腿起点
   // 注释：水平列表出自 std-dev 文章（该文原文水平表被截断 → 中介置信度）；锚点几何为文档读法
   double legEnd = isBull ? seriesHigh : seriesLow;
   double legLen = isBull ? (seriesHigh - c2Extreme) : (c2Extreme - seriesLow);
   if(legLen <= 0.0) return;
   string parts[];
   int np = StringSplit(InpProjLevels, ',', parts);
   if(np <= 0) return;
   for(int p = 0; p < np; p++)
   {
      string s = parts[p];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "") continue;
      double lv = StringToDouble(s);
      double proj = isBull ? legEnd - lv * legLen : legEnd + lv * legLen;
      datetime x1 = g_t[0];
      datetime x2 = InpExtendProj ? g_t[0] : endT;
      if(x2 <= x1) x2 = (datetime)((long)x1 + PeriodSeconds(_Period));
      string nm2 = OBJ_PREFIX + "PJ_" + key + "_" + s;
      UpsertTrend(nm2, x1, proj, x2, proj, InpColorProj, 1, STYLE_DOT);
      string nl2 = OBJ_PREFIX + "PL_" + key + "_" + s;
      UpsertText(nl2, x2, proj, s, InpColorProj, 8, ANCHOR_LEFT);
   }
}

//+------------------------------------------------------------------+
//| 画一个 T-Spot 组（Pine 行 1212-1233：box + midline + closeline）     |
//|  key   ：当前 HTF 蜡烛开盘时间戳（字符串），一组对象的命名键          |
//|  dir   ：+1 看涨 / -1 看跌                                        |
//|  mid   ：Pine sweep_mid（last_closed 的对数中点）                  |
//|  lastC ：last_closed 的收盘价（Zone 的另一条边）                    |
//|  expansive / silver：决定是否额外画 Silver 标签与文案              |
//+------------------------------------------------------------------+
void DrawTspot(const string key, const int dir, const double mid, const double lastC,
               const bool expansive, const bool silver)
{
   datetime t1 = g_ht[0];
   datetime t2 = (datetime)((long)g_ht[0] + PeriodSeconds(g_htf));
   color bg   = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   color base = (dir > 0) ? InpBullBody : InpBearBody;
   color fill = MixFill(base, bg, InpBodyFillPercent);
   bool  doFill = (InpBodyFillPercent > 0);

   string nmBox = OBJ_PREFIX + "TS_" + key;
   UpsertRect(nmBox, t1, mid, t2, lastC, fill, doFill);

   string nmMid = OBJ_PREFIX + "TSM_" + key;
   UpsertTrend(nmMid, t1, mid, t2, mid, InpHtfLabelColor, InpMidlineWidth, StyleOf(InpTspotLineStyle));

   if(InpShowCloseLine)
   {
      string nmCls = OBJ_PREFIX + "TSC_" + key;
      UpsertTrend(nmCls, t1, lastC, t2, lastC, InpHtfLabelColor, InpMidlineWidth, StyleOf(InpTspotLineStyle));
   }

   // 触碰判定所需几何：方向 + 上下沿
   g_tsKey = key;
   g_tsDir = dir;
   g_tsMid = mid;
   g_tsHi  = MathMax(mid, lastC);
   g_tsLo  = MathMin(mid, lastC);

   if(silver)
   {
      string txt = expansive ? "Silver Expansive T-Spot" : "Silver T-Spot";
      string nmSv = OBJ_PREFIX + "SV_" + key;
      double y = (dir > 0) ? g_l[0] : g_h[0];
      UpsertText(nmSv, g_t[0], y, txt, (dir > 0) ? InpBullBody : InpBearBody, 8,
                 (dir > 0) ? ANCHOR_UPPER : ANCHOR_LOWER);
      if(AlertOnce("SV_" + key))
         FireAlert(txt + " on " + _Symbol + " (" + g_tfName + ")");
   }
}

//| T-Spot 回收：只保留最近 InpHtfMaxDisplay 组；ShowOnlyLatest 只留最新一组
void RecycleTspots()
{
   if(InpShowOnlyLatest)
   {
      int cnt = 0;
      string newest = "";
      long   newestV = 0;
      int total = ObjectsTotal(0, -1, -1);
      for(int i = 0; i < total; i++)
      {
         string nm = ObjectName(0, i, -1, -1);
         if(StringFind(nm, OBJ_PREFIX + "TS_") != 0) continue;
         string key = StringSubstr(nm, StringLen(OBJ_PREFIX) + 3);
         long v = (long)StringToInteger(key);
         if(newest == "" || v > newestV) { newest = key; newestV = v; }
         cnt++;
      }
      if(cnt > 1)
      {
         for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
         {
            string nm2 = ObjectName(0, i, -1, -1);
            if(StringFind(nm2, OBJ_PREFIX + "TS_") != 0) continue;
            string key2 = StringSubstr(nm2, StringLen(OBJ_PREFIX) + 3);
            if(key2 != newest) DeleteKey(key2);
         }
      }
      return;
   }
   int count = 0;
   string oldest = OldestTspotKey(count);
   while(count > InpHtfMaxDisplay && oldest != "")
   {
      DeleteKey(oldest);
      oldest = OldestTspotKey(count);
   }
}

//+------------------------------------------------------------------+
//| T-Spot 状态机：每出现一根新的 HTF 蜡烛执行一次                      |
//|  六个分支与 Pine 行号一一对应，先命中者胜（Pine: tspot_created）     |
//|  Pine 里该逻辑跑在每根图 bar 上，但条件只依赖 HTF 的 1/2/3 根 → 等价 |
//+------------------------------------------------------------------+
void ProcessTspot()
{
   if(!InpShowTspot) return;
   if(g_hh[1] <= 0.0 || g_hh[2] <= 0.0 || g_hh[3] <= 0.0) return;   // 至少 4 根 HTF

   // Pine 行 1177-1180：candles[1]=最后收盘，[2]=前一根，[3]=再前一根
   double lO = g_ho[1], lH = g_hh[1], lL = g_hl[1], lC = g_hc[1];
   double pO = g_ho[2], pH = g_hh[2], pL = g_hl[2], pC = g_hc[2];
   double qH = g_hh[3], qL = g_hl[3], qO = g_ho[3], qC = g_hc[3];

   string bias = "";
   if(InpTspotBias == BIAS_BULLISH) bias = "bull";
   else if(InpTspotBias == BIAS_BEARISH) bias = "bear";
   bool okBear = (InpTspotBias != BIAS_BULLISH);
   bool okBull = (InpTspotBias != BIAS_BEARISH);

   double midLevel = LogMidpoint(pH, pL, pO, pC);      // Pine 行 1202
   // Pine 的排除式：外包且收回内部 → 六个分支都不成立
   bool outsideExcluded = (lH > pH && lL < pL && lC > pL && lC < pH);
   bool okCommon = (!outsideExcluded);

   int    dir = 0;
   int    variant = 0;
   bool   expansive = false;
   double c2Level = 0.0;
   bool   c2IsBull = false;

   // ---- 分支 1：普通看跌（Pine 行 1205）----
   if(dir == 0 && okBear && okCommon && lH > pH && lC < pH)
   { dir = -1; variant = 1; c2Level = lH; c2IsBull = false; }
   // ---- 分支 2：普通看涨（Pine 行 1274）----
   if(dir == 0 && okBull && okCommon && lL < pL && lC > pL)
   { dir = +1; variant = 2; c2Level = lL; c2IsBull = true; }
   // ---- 分支 3：扩张看跌（Pine 行 1331）----
   if(dir == 0 && okBear && okCommon && pH > qH && lC < MathMax(pO, pC))
   {
      bool extra = (pC >= midLevel) || (pC >= qH) || (pH > qH && pL < qL && pC > qL && pC < qH);
      if(extra) { dir = -1; variant = 3; expansive = true; c2Level = pH; c2IsBull = false; }
   }
   // ---- 分支 4：扩张看涨（Pine 行 1377）----
   if(dir == 0 && okBull && okCommon && pL < qL && lC > MathMin(pO, pC))
   {
      bool extra = (pC <= midLevel) || (pC <= qL) || (pH > qH && pL < qL && pC > qL && pC < qH);
      if(extra) { dir = +1; variant = 4; expansive = true; c2Level = pL; c2IsBull = true; }
   }
   // ---- 分支 5：顺势看涨中点扫破（Pine 行 1424）----
   if(dir == 0 && okBull && okCommon && lL < midLevel && lL > pO && lC > pH)
   { dir = +1; variant = 5; }
   // ---- 分支 6：顺势看跌中点扫破（Pine 行 1459）----
   if(dir == 0 && okBear && okCommon && lH > midLevel && lH < pO && lC < pL)
   { dir = -1; variant = 6; }

   if(dir == 0) return;

   // Pine 行 1210/1332/1378/1425/1460：Zone 中点是 last_closed 的对数中点
   double sweepMid = LogMidpoint(lH, lL, lO, lC);
   // Pine 行 1211 / 1280 / 1333 / 1380 / 1426 / 1461：收盘必须在 Zone 的正确一侧
   if(dir < 0 && !(lC < sweepMid)) return;
   if(dir > 0 && !(lC > sweepMid)) return;

   string key = IntegerToString((long)g_ht[0]);

   // 扫破位水平短线（Pine 行 1207 / 1276）：从前一根 HTF 周期画到当前周期
   if(InpShowChartSweeps)
   {
      double lvl = (dir < 0) ? pH : pL;
      datetime a = g_ht[0];
      datetime b = (datetime)((long)g_ht[0] + PeriodSeconds(g_htf));
      string nmSw = OBJ_PREFIX + "SW_" + key;
      UpsertTrend(nmSw, a, lvl, b, lvl, clrGray, 1, STYLE_SOLID);
   }

   // Silver 条件（Pine 行 1225 / 1295 / 1341 / 1388 / 1440 / 1475）
   bool silver = false;
   if(InpShowSilver && SilverSession())
   {
      if(dir < 0) silver = (lC < qL && lC < pL);
      else        silver = (lC > qH && lC > pH);
   }

   DrawTspot(key, dir, sweepMid, lC, expansive, silver);

   // C2/C3/C4 标签 + CISD（Pine：分支 5/6 没有这一段）
   if(variant <= 4)
   {
      int c2Idx = FindLevelBar(c2Level, 100);
      datetime endT = (datetime)((long)g_ht[0] + PeriodSeconds(g_htf));
      if(c2Idx > 0) DetectCisd(c2Idx, c2Level, c2IsBull, endT, key);
      if(c2Idx > 0 && InpShowTtfmLabels)
      {
         double atr = AtrRma(200) / 2.0;
         string nmC2 = OBJ_PREFIX + "C2_" + key;
         UpsertText(nmC2, g_t[c2Idx], (dir > 0) ? c2Level - atr : c2Level + atr, "C2",
                    (dir > 0) ? InpBullBody : InpBearBody, 8, ANCHOR_UPPER);
         string nmC3 = OBJ_PREFIX + "C3_" + key;
         string tag = expansive ? "C4" : "C3";
         UpsertText(nmC3, g_t[0], (dir > 0) ? sweepMid - atr : sweepMid + atr, tag,
                    (dir > 0) ? InpBullBody : InpBearBody, 8, ANCHOR_UPPER);
      }
   }

   g_tspotCreated = true;
   RecycleTspots();

   if(InpDebugShow)
      PrintFormat("TTFM_TSPOT key=%s dir=%d variant=%d expansive=%s silver=%s mid=%s lastC=%s",
                  key, dir, variant, (expansive ? "true" : "false"), (silver ? "true" : "false"),
                  PriceStr(sweepMid), PriceStr(lC));
}


//+------------------------------------------------------------------+
//| Pivot 检测（Pine 行 1596-1613：ta.pivothigh/low(...,2,2) 三路 + 合成）|
//|  ⚠️ Pine 的 pivothigh 在"两侧严格更高"时才成立；本实现同口径。        |
//|  ⚠️ 合成式按修正后的括号版本：(open 或 close 有 pivot) 且 high 有 pivot |
//+------------------------------------------------------------------+
bool PivotHighOf(const double &src[], const int lb, const int rb, double &val)
{
   int c = rb;
   if(c + lb >= g_n) return false;
   val = src[c];
   for(int k = 1; k <= lb; k++) if(!(val > src[c + k])) return false;
   for(int k = 1; k <= rb; k++) if(!(val > src[c - k])) return false;
   return true;
}

bool PivotLowOf(const double &src[], const int lb, const int rb, double &val)
{
   int c = rb;
   if(c + lb >= g_n) return false;
   val = src[c];
   for(int k = 1; k <= lb; k++) if(!(val < src[c + k])) return false;
   for(int k = 1; k <= rb; k++) if(!(val < src[c - k])) return false;
   return true;
}

void UpdatePivots()
{
   if(g_n < 6) return;
   double op, cp, hp, ol, cl, ll;
   bool hasOp = PivotHighOf(g_o, 2, 2, op);
   bool hasCp = PivotHighOf(g_c, 2, 2, cp);
   bool hasHp = PivotHighOf(g_h, 2, 2, hp);
   bool hasOl = PivotLowOf(g_o, 2, 2, ol);
   bool hasCl = PivotLowOf(g_c, 2, 2, cl);
   bool hasLl = PivotLowOf(g_l, 2, 2, ll);

   bool hasPh = false;
   if(InpUseBodyPivots)
   {
      if((hasOp || hasCp) && hasHp) hasPh = true;
   }
   else if(hasHp) hasPh = true;

   bool hasPl = false;
   if(InpUseBodyPivots)
   {
      if((hasOl || hasCl) && hasLl) hasPl = true;
   }
   else if(hasLl) hasPl = true;

   if(hasPh)
   {
      g_pivHigh  = InpUseBodyPivots ? MathMax(g_o[2], g_c[2]) : hp;
      g_pivHighT = g_t[2];
   }
   if(hasPl)
   {
      g_pivLow   = InpUseBodyPivots ? MathMin(g_o[2], g_c[2]) : ll;
      g_pivLowT  = g_t[2];
   }
}

//+------------------------------------------------------------------+
//| T-Spot 触碰（Pine 行 1616-1652）：只在最新一组 T-Spot 上判定         |
//+------------------------------------------------------------------+
void UpdateTouch()
{
   if(g_tsKey == "") return;
   if(g_tsKey != g_touchKey)
   {
      g_touched  = false;
      g_touchKey = g_tsKey;
   }
   if(g_tsDir < 0)
   {
      double lvl = g_tsLo;      // Pine：看跌取 min(top,bottom)
      if((g_h[0] > lvl || g_o[0] > lvl) && g_c[0] < lvl)
      { g_touched = true; g_touchLevel = lvl; g_touchT = g_t[0]; }
   }
   else if(g_tsDir > 0)
   {
      double lvl = g_tsHi;      // Pine：看涨取 max(top,bottom)
      if((g_l[0] < lvl || g_o[0] < lvl) && g_c[0] > lvl)
      { g_touched = true; g_touchLevel = lvl; g_touchT = g_t[0]; }
   }
}

//| 两个时间之间隔了几根图 bar（周末缺口会让它偏大 → 一律再和 g_n-1 取小）
int BarsBetween(const datetime tOld, const datetime tNew)
{
   int secs = PeriodSeconds(_Period);
   if(secs <= 0) return 0;
   int n = (int)(((long)tNew - (long)tOld) / secs);
   if(n < 0) n = 0;
   return MathMin(n, g_n - 1);
}

//+------------------------------------------------------------------+
//| T-Spot Sweep 确认（Pine 行 1660-1737）                             |
//|  看涨：pivot high 在触碰之前形成、当前 bar 收在 pivot 之上（开在其下）、|
//|       且 pivot 高于触碰价位；止损 = 两者之间的最低低点；入场 = 收盘。  |
//+------------------------------------------------------------------+
void CheckSweepConfirm()
{
   if(!InpShowSweeps) return;
   if(!g_touched || g_tsKey == "") return;

   if(g_tsDir > 0 && g_pivHigh > 0.0 && g_pivHighT < g_touchT &&
      g_c[0] > g_pivHigh && g_o[0] < g_pivHigh && g_pivHigh > g_touchLevel)
   {
      double lowest = g_l[0];
      int lim = BarsBetween(g_pivHighT, g_t[0]);
      for(int i = 1; i <= lim; i++) lowest = MathMin(lowest, g_l[i]);

      if(InpShowConfLabels)
      {
         UpsertText(OBJ_PREFIX + "CFL", g_t[0], lowest - AtrRma(200), "T-Spot Sweep",
                    InpBullBody, 8, ANCHOR_LOWER);
      }
      string msg = "Bullish T-Spot Sweep Confirmed on " + _Symbol + " (" + g_tfName + ")";
      if(InpShowConfLines)
      {
         datetime x1 = g_pivHighT;
         datetime x2 = g_t[0];
         if(x2 <= x1) x2 = (datetime)((long)x1 + PeriodSeconds(_Period));
         UpsertTrend(OBJ_PREFIX + "CF", x1, g_pivHigh, x2, g_pivHigh,
                     InpBullBody, 1, STYLE_SOLID);
      }
      if(AlertOnce("SW_B_" + g_tsKey)) FireAlert(msg);
      g_lastSweepT = g_t[0];
      if(InpShowPosSize)
      {
         g_sigDir   = "bullish";
         g_sigEntry = g_c[0];
         g_sigStop  = lowest;
         g_sigLots  = CalcLots(g_sigEntry, g_sigStop, RiskMoney());
         g_hasSig   = true;
      }
      g_touched = false;
      return;
   }

   if(g_tsDir < 0 && g_pivLow > 0.0 && g_pivLowT < g_touchT &&
      g_c[0] < g_pivLow && g_o[0] > g_pivLow && g_pivLow < g_touchLevel)
   {
      double highest = g_h[0];
      int lim = BarsBetween(g_pivLowT, g_t[0]);
      for(int i = 1; i <= lim; i++) highest = MathMax(highest, g_h[i]);

      if(InpShowConfLabels)
      {
         UpsertText(OBJ_PREFIX + "CFL", g_t[0], highest + AtrRma(200), "T-Spot Sweep",
                    InpBearBody, 8, ANCHOR_UPPER);
      }
      string msg = "Bearish T-Spot Sweep Confirmed on " + _Symbol + " (" + g_tfName + ")";
      if(InpShowConfLines)
      {
         datetime x1 = g_pivLowT;
         datetime x2 = g_t[0];
         if(x2 <= x1) x2 = (datetime)((long)x1 + PeriodSeconds(_Period));
         UpsertTrend(OBJ_PREFIX + "CF", x1, g_pivLow, x2, g_pivLow,
                     InpBearBody, 1, STYLE_SOLID);
      }
      if(AlertOnce("SW_S_" + g_tsKey)) FireAlert(msg);
      g_lastSweepT = g_t[0];
      if(InpShowPosSize)
      {
         g_sigDir   = "bearish";
         g_sigEntry = g_c[0];
         g_sigStop  = highest;
         g_sigLots  = CalcLots(g_sigEntry, g_sigStop, RiskMoney());
         g_hasSig   = true;
      }
      g_touched = false;
   }
}

//+------------------------------------------------------------------+
//| 逆向 T-Spot 隐藏（Pine 行 1740-1779；只做隐藏，不做删除）            |
//|  方向存在 OBJ_RECTANGLE 的 TEXT 属性里（矩形不显示文本，可当私有标记） |
//+------------------------------------------------------------------+
void HideAgainstTspots()
{
   if(!InpHideAgainst) return;
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, OBJ_PREFIX + "TS_") != 0) continue;
      string key = StringSubstr(nm, StringLen(OBJ_PREFIX) + 3);
      string dS  = ObjectGetString(0, nm, OBJPROP_TEXT);
      int dir = (int)StringToInteger(dS);
      if(dir == 0) continue;
      double mid = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
      if(mid <= 0.0) continue;
      bool against = (dir < 0) ? (g_c[0] > mid) : (g_c[0] < mid);
      bool fill = (InpBodyFillPercent > 0) && !against;
      color fillClr = against ? bg : MixFill((dir > 0) ? InpBullBody : InpBearBody, bg, InpBodyFillPercent);
      color lineClr = against ? bg : InpHtfLabelColor;
      ObjectSetInteger(0, nm, OBJPROP_COLOR, fillClr);
      ObjectSetInteger(0, nm, OBJPROP_FILL,  fill);
      string nmMid = OBJ_PREFIX + "TSM_" + key;
      if(ObjectFind(0, nmMid) >= 0) ObjectSetInteger(0, nmMid, OBJPROP_COLOR, lineClr);
      string nmCls = OBJ_PREFIX + "TSC_" + key;
      if(ObjectFind(0, nmCls) >= 0) ObjectSetInteger(0, nmCls, OBJPROP_COLOR, lineClr);
   }
}


//+------------------------------------------------------------------+
//| HTF 叠加层：蜡烛 + 名称/倒计时 + 起始竖线                          |
//|  ⚠️ 全部画在最后一根 K 线右侧（未来时间）—— 与 Pine 的"offset"同义   |
//+------------------------------------------------------------------+
string TfName(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "1M";
      case PERIOD_M5:  return "5M";
      case PERIOD_M15: return "15M";
      case PERIOD_M30: return "30M";
      case PERIOD_H1:  return "1H";
      case PERIOD_H4:  return "4H";
      case PERIOD_D1:  return "1D";
      case PERIOD_W1:  return "1W";
      case PERIOD_MN1: return "1Mth";
   }
   return "TF" + IntegerToString((int)tf);
}

//+------------------------------------------------------------------+
//| HTF 剩余时间（Pine RemainingTime，行 733-751）                      |
//+------------------------------------------------------------------+
string RemainingText()
{
   if(g_ht[0] <= 0) return "n/a";
   long endT = (long)g_ht[0] + (long)PeriodSeconds(g_htf);
   long left = endT - (long)TimeCurrent();
   if(left < 0) left = 0;
   long d = left / 86400;
   long h = (left % 86400) / 3600;
   long m = (left % 3600) / 60;
   long s = left % 60;
   string r = StringFormat("%02d:%02d", (int)m, (int)s);
   if(h > 0 || d > 0) r = StringFormat("%02d:", (int)h) + r;
   if(d > 0)          r = StringFormat("%dD ", (int)d) + r;
   return "(" + r + ")";
}

void DrawHtf()
{
   if(!InpShowHtf) return;
   int count = InpHtfMaxDisplay;
   if(count < 1) count = 1;
   if(count > MAX_HTF_SETS) count = MAX_HTF_SETS;
   int step = InpHtfBodyBars + InpHtfBufferBars;
   if(step < 1) step = 1;
   bool doFill = (InpBodyFillPercent > 0);

   for(int j = 0; j < count; j++)
   {
      if(g_hh[j] <= 0.0 || g_hl[j] <= 0.0) break;
      int base = InpHtfOffsetBars + (count - 1 - j) * step;
      datetime t1 = FutureTime(base);
      datetime t2 = FutureTime(base + InpHtfBodyBars);
      datetime tm = (datetime)(((long)t1 + (long)t2) / 2);
      datetime tm2 = (datetime)((long)tm + 1);
      string key = IntegerToString((long)g_ht[j]);

      bool up = (g_hc[j] >= g_ho[j]);
      color bodyClr = up ? InpBullBody : InpBearBody;
      color wickClr = up ? InpBullWick : InpBearWick;

      UpsertRect(OBJ_PREFIX + "HB_" + key, t1, MathMax(g_ho[j], g_hc[j]),
                 t2, MathMin(g_ho[j], g_hc[j]), bodyClr, doFill);
      UpsertTrend(OBJ_PREFIX + "HU_" + key, tm, g_hh[j], tm2,
                  MathMax(g_ho[j], g_hc[j]), wickClr, 1, STYLE_SOLID);
      UpsertTrend(OBJ_PREFIX + "HD_" + key, tm2, MathMin(g_ho[j], g_hc[j]), tm,
                  g_hl[j], wickClr, 1, STYLE_SOLID);

      if(InpHtfLabelShow)
      {
         UpsertText(OBJ_PREFIX + "HL_" + key, t1, g_hh[j], TfName(g_htf) + " Model",
                    InpHtfLabelColor, 8, ANCHOR_LEFT);
      }
      if(InpHtfTimerShow && j == 0)
      {
         UpsertText(OBJ_PREFIX + "HT_" + key, t2, g_hh[j], RemainingText(),
                    InpHtfTimerColor, 8, ANCHOR_RIGHT);
      }
   }
}

//| HTF 起始竖线（Pine 行 1137-1144 的 htf_lines）——用 OBJ_VLINE，不占价格刻度
void DrawHtfStarts()
{
   if(!InpHtfLineShow) return;
   int count = InpHtfMaxDisplay;
   if(count < 1) count = 1;
   for(int j = 0; j < count && j < MAX_HTF_SETS; j++)
   {
      if(g_ht[j] <= 0) break;
      string nm = OBJ_PREFIX + "VL_" + IntegerToString((long)g_ht[j]);
      UpsertVLine(nm, g_ht[j], InpHtfLineColor, InpHtfLineWidth, InpHtfLineStyle);
   }
   // 回收：key 不在当前集合内的竖线删掉
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string nm2 = ObjectName(0, i, -1, -1);
      if(StringFind(nm2, OBJ_PREFIX + "VL_") != 0) continue;
      string key = StringSubstr(nm2, StringLen(OBJ_PREFIX) + 3);
      bool keep = false;
      for(int j2 = 0; j2 < count && j2 < MAX_HTF_SETS; j2++)
         if(IntegerToString((long)g_ht[j2]) == key) { keep = true; break; }
      if(!keep) ObjectDelete(0, nm2);
   }
}

//| 最新 T-Spot 的右端跟随当前 bar（Pine 行 1095-1102）                 |
void ExtendLatestTspot()
{
   if(!InpExtendLatest || g_tsKey == "") return;
   string nm = OBJ_PREFIX + "TS_" + g_tsKey;
   if(ObjectFind(0, nm) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
   datetime nowT = g_t[0];
   if(nowT <= t1) return;
   datetime right = (nowT < t2) ? nowT : t2;
   ObjectSetInteger(0, nm, OBJPROP_TIME, 1, right);
   string nmMid = OBJ_PREFIX + "TSM_" + g_tsKey;
   if(ObjectFind(0, nmMid) >= 0) ObjectSetInteger(0, nmMid, OBJPROP_TIME, 1, right);
   string nmCls = OBJ_PREFIX + "TSC_" + g_tsKey;
   if(ObjectFind(0, nmCls) >= 0) ObjectSetInteger(0, nmCls, OBJPROP_TIME, 1, right);
}

//+------------------------------------------------------------------+
//| 信息面板（Pine table.* → 4 行角标）                                |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!InpShowPanel)
   {
      DeletePrefix(OBJ_PREFIX + "PN_");
      return;
   }
   int fs = InpPanelFontSize;
   if(fs < 6) fs = 6;
   if(fs > 16) fs = 16;
   UpsertPanelLine(OBJ_PREFIX + "PN_0", 0,
                   TfName(_Period) + "-" + TfName(g_htf) + " Model", fs);
   UpsertPanelLine(OBJ_PREFIX + "PN_1", 1, RemainingText(), fs);
   UpsertPanelLine(OBJ_PREFIX + "PN_2", 2, "Bias: " + HtfBias(), fs);
   if(InpShowPosSize && g_hasSig)
   {
      string txt = ((g_sigDir == "bullish") ? "BUY " : "SELL ") + FmtLots(g_sigLots)
                 + "  " + (InpAbbrevPos ? "En:" : "Entry:")
                 + PriceStr(g_sigEntry) + " " + (InpAbbrevPos ? "St:" : "Stop:")
                 + PriceStr(g_sigStop);
      UpsertPanelLine(OBJ_PREFIX + "PN_3", 3, txt, fs);
   }
   else
   {
      DeletePrefix(OBJ_PREFIX + "PN_3");
   }
}


//+------------------------------------------------------------------+
//| 生命周期                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpHtfMaxDisplay < 1 || InpHtfMaxDisplay > MAX_HTF_SETS)
   {
      PrintFormat("ttrades/TTFM: InpHtfMaxDisplay 必须在 1..%d（收到 %d）", MAX_HTF_SETS, InpHtfMaxDisplay);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBodyFillPercent < 0 || InpBodyFillPercent > 100)
   {
      PrintFormat("ttrades/TTFM: InpBodyFillPercent 必须在 0..100（收到 %d）", InpBodyFillPercent);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpHtfBodyBars < 1 || InpHtfOffsetBars < 0 || InpHtfBufferBars < 0)
   {
      Print("ttrades/TTFM: InpHtfBodyBars 必须 ≥ 1，InpHtfOffsetBars / InpHtfBufferBars 必须 ≥ 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   SetIndexBuffer(0, g_scale, INDICATOR_DATA);
   ArraySetAsSeries(g_scale, true);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_win = 0;                     // 主图窗口（#property indicator_chart_window）
   g_htf = (InpHtfMode == HTF_AUTO) ? AutoHtf(_Period) : InpHtfCustom;
   g_tfName = TfName(g_htf);
   IndicatorSetString(INDICATOR_SHORTNAME, "TTFM(" + TfName(_Period) + "-" + g_tfName + ")");

   DeletePrefix(OBJ_PREFIX);
   // 这一行是"唯一无条件打印"的 INIT 回显：所有观感开关都在这里可查
   PrintFormat("ttrades/TTFM 已初始化 | build=%s | chart=%s htf=%s | bubble=%s|bias=%s | htfCandle=%s n=%d off=%d body=%d buf=%d gap=%d lab=%s timer=%s vline=%s "
               "| tspot=%s onlyLatest=%s extend=%s fillPct=%d silver=%s ttfm=%s hideAgainst=%s | cisd=%s proj=%s levels=%s extendProj=%s "
               "| sweeps=%s confLine=%s confLabel=%s bodyPivot=%s | posSize=%s | panel=%s corner=%d | alertPopup=%s alertPush=%s",
               BUILD_TAG, TfName(_Period), g_tfName,
               (InpHtfMode == HTF_AUTO ? "Auto" : "Custom"),
               (InpTspotBias == BIAS_BULLISH ? "Bullish" : (InpTspotBias == BIAS_BEARISH ? "Bearish" : "None")),
               (InpShowHtf ? "on" : "off"), InpHtfMaxDisplay, InpHtfOffsetBars,
               InpHtfBodyBars, InpHtfBufferBars, InpHtfGapBars,
               (InpHtfLabelShow ? "on" : "off"), (InpHtfTimerShow ? "on" : "off"), (InpHtfLineShow ? "on" : "off"),
               (InpShowTspot ? "on" : "off"), (InpShowOnlyLatest ? "on" : "off"), (InpExtendLatest ? "on" : "off"),
               InpBodyFillPercent, (InpShowSilver ? "on" : "off"), (InpShowTtfmLabels ? "on" : "off"),
               (InpHideAgainst ? "on" : "off"),
               (InpShowCisd ? "on" : "off"), (InpShowProj ? "on" : "off"), InpProjLevels,
               (InpExtendProj ? "on" : "off"),
               (InpShowSweeps ? "on" : "off"), (InpShowConfLines ? "on" : "off"),
               (InpShowConfLabels ? "on" : "off"), (InpUseBodyPivots ? "on" : "off"),
               (InpShowPosSize ? "on" : "off"),
               (InpShowPanel ? "on" : "off"), (int)InpPanelCorner,
               (InpAlertPopup ? "on" : "off"), (InpAlertPush ? "on" : "off"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeletePrefix(OBJ_PREFIX + "PN_");
   if(reason != REASON_CHARTCHANGE)
   {
      int total = ObjectsTotal(0, -1, -1);
      for(int i = total - 1; i >= 0; i--)
      {
         string nm = ObjectName(0, i, -1, -1);
         if(StringFind(nm, OBJ_PREFIX) == 0) ObjectDelete(0, nm);
      }
   }
   ChartRedraw();
   PrintFormat("ttrades/TTFM 已卸载 | build=%s | reason=%d", BUILD_TAG, reason);
}

//+------------------------------------------------------------------+
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
   // 硬约定 1：本终端交给指标的数组不是时序，必须显式声明方向
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   // 隐藏 buffer 全填 EMPTY_VALUE：绝不能留 0，否则纵轴被拉到 0
   int upto = (prev_calculated <= 0) ? rates_total - 1 : (rates_total - prev_calculated);
   for(int i = upto; i >= 0; i--) g_scale[i] = EMPTY_VALUE;

   if(rates_total < 60) return(rates_total);

   g_htf = (InpHtfMode == HTF_AUTO) ? AutoHtf(_Period) : InpHtfCustom;
   g_tfName = TfName(g_htf);

   if(!CopyChart(CHART_LOOKBACK)) return(rates_total);
   if(!CopyHtf(InpHtfMaxDisplay + 4)) return(rates_total);

   bool firstFrame = (prev_calculated <= 0);
   if(firstFrame)
   {
      DeletePrefix(OBJ_PREFIX);
      g_lastHtfT0   = 0;
      g_lastChartT0 = 0;
      g_tsKey       = "";
      g_touchKey    = "";
      g_touched     = false;
      g_hasSig      = false;
      g_pivHigh = 0.0; g_pivLow = 0.0;
      g_pivHighT = 0;  g_pivLowT = 0;
      g_lastSweepT  = 0;
   }

   bool newChartBar = (g_t[0] != g_lastChartT0);
   bool newHtf      = (g_ht[0] != g_lastHtfT0);

   if(newHtf)
   {
      g_lastHtfT0 = g_ht[0];
      ProcessTspot();
   }
   if(newChartBar)
   {
      g_lastChartT0 = g_t[0];
      UpdatePivots();
      DrawHtf();
      DrawHtfStarts();
      HideAgainstTspots();
   }

   UpdateTouch();
   CheckSweepConfirm();
   ExtendLatestTspot();

   // 面板倒计时最多每秒刷一次（不把诊断/UI 刷新压在每 tick 路径上）
   static datetime s_lastPanel = 0;
   datetime nowSrv = TimeCurrent();
   if(newChartBar || (nowSrv - s_lastPanel) >= 1)
   {
      s_lastPanel = nowSrv;
      UpdatePanel();
   }

   if(InpDebugShow && newChartBar)
   {
      int nTs = 0;
      OldestTspotKey(nTs);
      PrintFormat("TTFM_RENDER bar=%s newHtf=%s htf=%s nHtfBars=%d tspots=%d tsDir=%d touched=%s bias=%s",
                  TimeToString(g_t[0], TIME_DATE|TIME_MINUTES),
                  (newHtf ? "true" : "false"), g_tfName,
                  ArraySize(g_hh), nTs, g_tsDir, (g_touched ? "true" : "false"), HtfBias());
   }

   if(newChartBar) ChartRedraw();
   return(rates_total);
}
//+------------------------------------------------------------------+
