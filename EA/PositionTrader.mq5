//+------------------------------------------------------------------+
//|  PositionTrader.mq5                                       |
//|  把 PositionTool 画出来的仓位工具**真正挂成挂单**          |
//+------------------------------------------------------------------+
//|  为什么必须拆成 EA：                                               |
//|    MQL5 的**指标不能下单** —— OrderSend / CTrade 在指标里不可用。  |
//|    所以"画"留在指标里，"发单"只能另起一个 EA，两者靠图表对象通讯： |
//|      指标每次重画，把**当前选中工具**的挂单意图写进固定对象；       |
//|      EA 点击时读它 → 校验 → 发单。                                |
//|                                                                  |
//|  ── 为什么用"一行字符串"当接口，而不是直接去读那三根线 ──           |
//|    几何（入场/止损/止盈）EA 确实能从对象里读出来，但**手数读不到**： |
//|    它是 R / 风险% / 最小手数一起算出来的结论。若让 EA 自己再算一遍， |
//|    就等于把同一套定仓公式维护两份 —— "两个真相源"迟早对不上。       |
//|    故指标发布**结论**，EA 只消费、不重算。                          |
//|                                                                  |
//|  接口（对象名与字段顺序是**跨文件契约**，改一端必须同步改另一端）：  |
//|    对象名 ： PT_ORD                                          |
//|    存放位置： 该对象的 **OBJPROP_TOOLTIP**（不是 TEXT）             |
//|    载荷格式： TVPT1|NONE                                           |
//|              TVPT1|<L|S>|<entry>|<sl>|<tp>|<lots>|<R>|<noTrade>|<id>|
//|    ⚠️ 用 TOOLTIP 而不是 TEXT，是为了让这个对象可以是一个**空文字    |
//|       标签**：视觉上完全不存在，连"藏对象藏出可见垃圾"的风险都没有。 |
//|                                                                  |
//|  ── 四个刻意的取舍 ──                                              |
//|   ① 按钮由 EA 自己创建（前缀 TVPTX_），**不共用指标的按钮**：       |
//|      共用就得依赖"指标建的对象、点击事件会不会送到 EA"这一层。      |
//|      能送到，但没必要赌 —— EA 自持 UI 则失败面只剩"位置偏一点"。    |
//|      位置自适应地贴在指标按钮行右端（找不到指标则退回左上角）。      |
//|   ② **两步确认**：第一次点只是"上膛"，ARM_SECONDS 秒内再点一次才发单。|
//|      这是真金白银，不能一次误点就出去一张单。                       |
//|   ③ **一次一张单**，只处理当前选中的那个工具。                      |
//|      "一次点出好几张单"比"多点一次"危险得多，故批量挂单不做。        |
//|   ④ **绝不自己算手数、绝不自己改工具的止损止盈**：EA 只做"把指标     |
//|      算出来的东西原样送去券商"，任何偏差都拒绝并说明原因。            |
//+------------------------------------------------------------------+
#property copyright "PandaTrade"
#property version   "1.11"
#property description "读取 PositionTool 的挂单意图，把仓位工具挂成真实的挂单（Buy/Sell Limit 或 Stop）。"
#property description "指标不可用时自动切到手动模式：市价 BUY/SELL + 平仓，可在策略测试器里当手动回测面板。"

#include <Trade\Trade.mqh>

// 构建指纹：本仓库的规矩 —— 日志里只打印它，不写版本字面量。
// 顺带一个好处：Indictor/mq5debug.ps1 抓 init 行就是按「文件名 + build=」匹配的，
// 这里带上 build= 才能被同一套工具读到。
// ⚠️ 每改一次行为都要升它 —— 否则日志里分不出用户挂的是哪一版（吃过这个亏）。
#define BUILD_TAG    "v1.11-s1"
// 与指标的接口对象名 —— 跨文件契约，不要单独改
#define INTENT_OBJ   "PT_ORD"
// EA 自己的对象前缀（刻意与指标的 PT_ 不同，避免互相误删）
#define TVPTX_PFX    "TVPTX_"
#define BTN_PLACE    "TVPTX_BTN_PLACE"
#define BTN_CANCEL   "TVPTX_BTN_CANCEL"
#define BTN_BUY      "TVPTX_BTN_BUY"
#define BTN_SELL     "TVPTX_BTN_SELL"
#define BTN_CLOSEALL "TVPTX_BTN_CLOSEALL"
#define MSG_MAIN     "TVPTX_MSG_MAIN"
#define MSG_SUB      "TVPTX_MSG_SUB"
// 二次确认窗口（秒）与提示自动消失时间（秒）
#define ARM_SECONDS  6
#define MSG_SECONDS  15
// 上膛的是哪一下（0=没上膛）。开仓类要二次确认；**平仓/撤单不要** —— 见 OnChartEvent 里的说明。
#define ARM_NONE     0
#define ARM_TOOL     1
#define ARM_BUY      2
#define ARM_SELL     3

input group "== 挂单 =="
input long InpMagic       = 20260928;  // 本 EA 的 Magic（撤单/平仓只碰自己的单）
input int  InpSlippagePts = 30;        // 允许滑点（点，仅市价单用）
input bool InpAllowMarket = false;     // 入场价离市价太近时，允许改成市价单进场

input group "== 手动模式（指标不可用时，例如在策略测试器里）=="
input double InpManualLots     = 0.10;  // 手数
input int    InpManualSLPoints = 200;   // 止损（最小变动 SYMBOL_POINT 的个数；0 = 不设）
input int    InpManualTPPoints = 400;   // 止盈（同上；0 = 不设）

input group "== 外观 =="
input color InpColorBuy  = C'38,166,65';   // 成功 / 做多色
input color InpColorWarn = C'240,136,62';  // 提示 / 失败色
input int   InpFontSize  = 10;             // 提示字号
input int   InpMsgBottomPx = 46;           // 提示距图表底边像素（被时间轴遮住就调大）

input group "== 策略测试器（实验性）=="
input bool InpTesterSpawnIndicator = false;  // 测试器里由 EA 用 iCustom 拉起 PositionTool（**仅测试器生效**）

input group "== 调试 =="
input bool InpDebug = false;  // 专家日志：每次意图解析都打一行

//--- 全局
CTrade   g_trade;
int      g_armed    = ARM_NONE;  // 已"上膛"的是哪一下（等第二次点击）
datetime g_armedAt  = 0;
bool     g_msgShown = false;
datetime g_msgAt    = 0;
bool     g_lastToolMode = false; // 上一帧是不是"指标模式"，用于自动切换按钮组
int      g_indHandle    = INVALID_HANDLE;  // 测试器里拉起的指标句柄
bool     g_spawnChecked = false;           // 拉起后只自检一次
string   g_lastBtn      = "";              // 去重：同一个按钮 500ms 内只执行一次
uint     g_lastBtnMs    = 0;

//+------------------------------------------------------------------+
//| 挂单计划：把"意图"解析 + 全部校验做完后的**可执行结论**            |
//+------------------------------------------------------------------+
struct SPlan
{
   bool            ok;        // 校验是否全通过
   string          err;       // ok=false 的原因（要能直接给人看）
   string          desc;      // 人类可读摘要（按钮 tooltip / 日志用）
   bool            isLong;
   bool            useMarket; // true = 退化成市价单
   ENUM_ORDER_TYPE type;
   double          lots;
   double          entry;
   double          sl;
   double          tp;
   double          risk;
   int             id;
};

//+------------------------------------------------------------------+
//| 小工具                                                            |
//+------------------------------------------------------------------+
string TypeName(const ENUM_ORDER_TYPE t)
{
   switch(t)
   {
      case ORDER_TYPE_BUY_LIMIT:  return "Buy Limit";
      case ORDER_TYPE_BUY_STOP:   return "Buy Stop";
      case ORDER_TYPE_SELL_LIMIT: return "Sell Limit";
      case ORDER_TYPE_SELL_STOP:  return "Sell Stop";
      case ORDER_TYPE_BUY:        return "市价 Buy";
      case ORDER_TYPE_SELL:       return "市价 Sell";
   }
   return "?";
}

// 指标按钮行的右端（EA 的按钮贴在那里）。找不到指标就退回左上角。
int AnchorX()
{
   const string anchors[] = {"PT_BTN_TOGGLE", "PT_BTN_CLR", "PT_BTN_LONG"};
   for(int k = 0; k < ArraySize(anchors); k++)
   {
      if(ObjectFind(0, anchors[k]) < 0) continue;
      return (int)ObjectGetInteger(0, anchors[k], OBJPROP_XDISTANCE)
           + (int)ObjectGetInteger(0, anchors[k], OBJPROP_XSIZE) + 16;
   }
   return 12;
}

int AnchorY()
{
   const string anchors[] = {"PT_BTN_TOGGLE", "PT_BTN_CLR", "PT_BTN_LONG"};
   for(int k = 0; k < ArraySize(anchors); k++)
      if(ObjectFind(0, anchors[k]) >= 0)
         return (int)ObjectGetInteger(0, anchors[k], OBJPROP_YDISTANCE);
   return 22;
}

void KillIfExists(const string nm)
{
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
}

void MakeButton(const string nm, const string txt, const int x, const int y,
                const int w, const int h, const color fg, const color bg){
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
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
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, C'70,76,88');
   ObjectSetInteger(0, nm, OBJPROP_STATE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   // ⚠️ HIDDEN 一律 false：本仓库已实测过"隐藏对象鼠标命中不到"这颗地雷
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 60);
}

// 提示画在**左下角**：左上角是指标面板的地盘，不跟它抢。
// ⚠️ 但左下角有个坑：MT5 的**时间轴（日期刻度）就画在图表底边**，
//    距底边太近的标签会被它盖住（第一版贴 12px，副标题基本全在里面）。
//    故留出 InpMsgBottomPx 的余量，并按终端字号给够。
void MakeMsgLabel(const string nm, const int y, const color c)
{
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, nm, OBJPROP_FONT, "Microsoft YaHei");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 60);
}

void ShowMsg(const string main, const color c, const string sub = "")
{
   // 副标题在下、正文在上；两者都从 InpMsgBottomPx 起算，避开时间轴
   const int yb = MathMax(0, InpMsgBottomPx);
   MakeMsgLabel(MSG_MAIN, yb + 20, c);
   ObjectSetString(0, MSG_MAIN, OBJPROP_TEXT, main);
   MakeMsgLabel(MSG_SUB, yb, ClrDim(c));
   ObjectSetString(0, MSG_SUB, OBJPROP_TEXT, sub);
   g_msgShown = true;
   g_msgAt    = TimeCurrent();
   ChartRedraw();
}

color ClrDim(const color c)
{
   // 副标题压暗一点，跟正文拉开层次（不引新输入，免得参数表越滚越长）
   const uint r = (((uint)c)      ) & 0xFF;
   const uint g = (((uint)c) >> 8 ) & 0xFF;
   const uint b = (((uint)c) >> 16) & 0xFF;
   return (color)(((r * 2 / 3) & 0xFF) | (((g * 2 / 3) & 0xFF) << 8) | (((b * 2 / 3) & 0xFF) << 16));
}

void ClearMsg()
{
   ObjectDelete(0, MSG_MAIN);
   ObjectDelete(0, MSG_SUB);
   g_msgShown = false;
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 两种模式共用的前置件                                               |
//+------------------------------------------------------------------+
// 交易环境检查。任何一条不满足都写进 p.err 并返回 false。
// 抽出来是因为**指标模式与手动模式必须过同一套闸门** ——
// 分两份写迟早会出现"一边拦一边不拦"。
bool CheckTradingEnv(SPlan &p, const bool isLong)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   { p.err = "终端未允许算法交易 —— 点一下工具栏那个「算法交易」按钮"; return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   { p.err = "本 EA 未允许交易 —— 在 EA 属性里勾选「允许算法交易」"; return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { p.err = "账户不允许交易"; return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   { p.err = "账户不允许 EA 交易"; return false; }

   const long tmode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_MODE_DISABLED)
   { p.err = "该品种禁止交易"; return false; }
   if(tmode == SYMBOL_TRADE_MODE_CLOSEONLY)
   { p.err = "该品种当前只能平仓"; return false; }
   if(isLong && tmode == SYMBOL_TRADE_MODE_SHORTONLY)
   { p.err = "该品种只允许做空，不接受做多"; return false; }
   if(!isLong && tmode == SYMBOL_TRADE_MODE_LONGONLY)
   { p.err = "该品种只允许做多，不接受做空"; return false; }
   return true;
}

// 手数按本品种的步长/上下限归一
double NormVolume(const double v, bool &adjusted)
{
   const double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol = v;
   if(vstep > 0.0) vol = MathFloor(vol / vstep + 1e-8) * vstep;
   vol = NormalizeDouble(vol, 2);
   if(vmin > 0.0 && vol < vmin) vol = vmin;
   if(vmax > 0.0 && vol > vmax) vol = vmax;
   adjusted = (MathAbs(vol - v) > 1e-9);
   return vol;
}

// 指标接口在不在。**只看接口对象存不存在**，不看当前这一单能不能挂 ——
// 否则"入场线离市价太近"这类临时校验失败会把按钮组整个切成手动模式，那是错的。
bool InToolMode()
{
   return (ObjectFind(0, INTENT_OBJ) >= 0);
}

void PrepareTrade()
{
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)MathMax(0, InpSlippagePts));
   g_trade.SetTypeFillingBySymbol(_Symbol);   // 别自己挑 FOK/IOC，交给品种声明
}

//+------------------------------------------------------------------+
//| 手动模式：指标不可用时，用手动参数在市价进场                        |
//|   这就是"在策略测试器里当手动回测面板"那条路 —— 见 README 的说明。 |
//|   ⚠️ 它只做市价单：没有指标就没有"入场线"，也就没有可挂的价位。     |
//+------------------------------------------------------------------+
bool BuildManualPlan(SPlan &p, const bool isLong)
{
   p.ok        = false;
   p.err       = "";
   p.desc      = "";
   p.isLong    = isLong;
   p.useMarket = true;
   p.type      = (isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   p.id        = 0;
   p.risk      = 0.0;

   if(!CheckTradingEnv(p, isLong)) return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   { p.err = "取不到最新报价"; return false; }

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const int    dg    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   p.entry = (isLong ? tick.ask : tick.bid);
   if(p.entry <= 0.0) { p.err = "报价为 0"; return false; }

   // 券商要求的最小"停价距离"：市价单的 SL/TP 相对当前价不能太近
   const int stopsPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int fzPts    = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const int minPts   = MathMax(stopsPts, fzPts);

   if(InpManualSLPoints > 0 && minPts > 0 && InpManualSLPoints < minPts)
   { p.err = StringFormat("止损设了 %d 点，小于券商要求的最小 %d 点 —— 把 InpManualSLPoints 调大",
                          InpManualSLPoints, minPts); return false; }
   if(InpManualTPPoints > 0 && minPts > 0 && InpManualTPPoints < minPts)
   { p.err = StringFormat("止盈设了 %d 点，小于券商要求的最小 %d 点 —— 把 InpManualTPPoints 调大",
                          InpManualTPPoints, minPts); return false; }

   const double slDist = (double)InpManualSLPoints * point;
   const double tpDist = (double)InpManualTPPoints * point;
   p.sl = (slDist > 0.0 ? NormalizeDouble(p.entry + (isLong ? -slDist : slDist), dg) : 0.0);
   p.tp = (tpDist > 0.0 ? NormalizeDouble(p.entry + (isLong ? tpDist : -tpDist), dg) : 0.0);

   bool adj = false;
   p.lots = NormVolume(InpManualLots, adj);
   if(p.lots <= 0.0) { p.err = "手数归一后为 0 —— 检查 InpManualLots"; return false; }

   p.desc = StringFormat("手动模式：市价 %s %.2f 手 @ %s | 止损 %s | 止盈 %s",
                         (isLong ? "BUY" : "SELL"), p.lots, DoubleToString(p.entry, dg),
                         (p.sl > 0.0 ? DoubleToString(p.sl, dg) : "不设"),
                         (p.tp > 0.0 ? DoubleToString(p.tp, dg) : "不设"));
   if(adj)
      p.desc += StringFormat("｜手数已按步长归一（输入的是 %.2f）", InpManualLots);

   p.ok = true;
   return true;
}

//+------------------------------------------------------------------+
//| 读取 + 校验 + 决定挂单类型：全部结论都在这里                       |
//|   任何一条不满足都**拒绝并给出人话原因**，绝不"猜着往下走"          |
//+------------------------------------------------------------------+
bool BuildPlan(SPlan &p)
{
   p.ok        = false;
   p.err       = "";
   p.desc      = "";
   p.useMarket = false;
   p.type      = ORDER_TYPE_BUY_LIMIT;

   //--- 1. 读意图 ---
   if(ObjectFind(0, INTENT_OBJ) < 0)
   {
      // 区分两种完全不同的原因 —— 一律说"没挂指标"会把人指向错误的排查方向：
      //   · 指标按钮在、接口对象不在 ⇒ 指标在跑，但是**没有挂单接口的旧版本**
      //   · 连指标按钮都没有        ⇒ 指标确实没挂
      if(ObjectFind(0, "PT_BTN_LONG") >= 0)
         p.err = "接口对象 " + INTENT_OBJ + " 不存在，但指标按钮在 ⇒ 这是**没有挂单接口的旧版本**，"
                 "把 PositionTool 重新挂载一次即可";
      else
         p.err = "图上没有 PositionTool 指标 —— 先把它挂上，能看见画线了再挂单";
      return false;
   }
   const string raw = ObjectGetString(0, INTENT_OBJ, OBJPROP_TOOLTIP);
   if(InpDebug) PrintFormat("DBG %s intent <%s>", BUILD_TAG, raw);

   string f[];
   const int n = StringSplit(raw, '|', f);
   if(n < 2 || f[0] != "TVPT1")
   {
      p.err = "意图格式不认识：" + raw;
      return false;
   }
   if(f[1] == "NONE")
   {
      p.err = "没有选中的仓位工具 —— 先在图上点一下某根线，面板标题出现「做多/做空 #N」再挂单";
      return false;
   }
   if(n < 9)
   {
      p.err = StringFormat("意图字段不足（%d/9）：%s", n, raw);
      return false;
   }

   p.isLong = (f[1] == "L");
   p.entry  = StringToDouble(f[2]);
   p.sl     = StringToDouble(f[3]);
   p.tp     = StringToDouble(f[4]);
   p.lots   = StringToDouble(f[5]);
   p.risk   = StringToDouble(f[6]);
   const int noTrade = (int)StringToInteger(f[7]);
   p.id              = (int)StringToInteger(f[8]);

   //--- 2. 意图自身的完备性 ---
   if(p.entry <= 0.0) { p.err = "入场价无效（" + f[2] + "）"; return false; }
   if(p.sl    <= 0.0) { p.err = "该工具没有止损线 —— 没有止损就不该挂单"; return false; }
   if(p.tp    <= 0.0) { p.err = "该工具没有止盈线"; return false; }
   if(noTrade == 1)   { p.err = "指标判定「不建议开仓」（最小手数下已超出设定的 R）—— 先收窄止损或调大 R"; return false; }
   if(p.lots  <= 0.0) { p.err = "手数为 0 —— 检查手数模式 / 止损是否有效"; return false; }

   //--- 3. 交易环境 ---
   if(!CheckTradingEnv(p, p.isLong)) return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   { p.err = "取不到最新报价"; return false; }

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const int    dg    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double ask   = tick.ask;
   const double bid   = tick.bid;

   // 券商要求的最小挂单距离：止损/止盈的"停价档"与"冻结档"取更严的那个
   const int stopsPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int fzPts    = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const int minPts   = MathMax(stopsPts, fzPts);
   const double minDist = (double)minPts * point;

   //--- 4. 挂单类型：入场在"更有利的一侧"= Limit；越过市价 = Stop ---
   if(p.isLong) p.type = (p.entry < ask) ? ORDER_TYPE_BUY_LIMIT  : ORDER_TYPE_BUY_STOP;
   else         p.type = (p.entry > bid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;

   const double ref  = (p.isLong ? ask : bid);
   const double dist = MathAbs(ref - p.entry);
   if(minDist > 0.0 && dist < minDist)
   {
      if(InpAllowMarket)
      {
         p.useMarket = true;
         p.type = (p.isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      }
      else
      {
         p.err = StringFormat("入场价距市价只有 %.0f 点，小于券商要求的最小 %.0f 点，挂不出去 —— "
                              "把入场线拖远一点；或打开 InpAllowMarket 允许改市价进场",
                              (point > 0.0 ? dist / point : 0.0), (double)minPts);
         return false;
      }
   }

   //--- 5. 止损止盈的方向与距离 ---
   if(p.isLong)
   {
      if(!(p.sl < p.entry)) { p.err = "做多工具却把止损放在了入场之上 —— 先把止损线拖到入场下方"; return false; }
      if(!(p.tp > p.entry)) { p.err = "做多工具却把止盈放在了入场之下 —— 先把止盈线拖到入场上方"; return false; }
   }
   else
   {
      if(!(p.sl > p.entry)) { p.err = "做空工具却把止损放在了入场之下 —— 先把止损线拖到入场上方"; return false; }
      if(!(p.tp < p.entry)) { p.err = "做空工具却把止盈放在了入场之上 —— 先把止盈线拖到入场下方"; return false; }
   }
   if(!p.useMarket && minDist > 0.0)
   {
      if(MathAbs(p.entry - p.sl) < minDist)
      { p.err = StringFormat("止损离入场只有 %.0f 点，小于最小 %d 点", MathAbs(p.entry - p.sl) / point, minPts); return false; }
      if(MathAbs(p.tp - p.entry) < minDist)
      { p.err = StringFormat("止盈离入场只有 %.0f 点，小于最小 %d 点", MathAbs(p.tp - p.entry) / point, minPts); return false; }
   }

   //--- 6. 手数按本品种的步长/上下限归一 ---
   bool adjusted = false;
   const double before = p.lots;
   p.lots = NormVolume(p.lots, adjusted);
   if(p.lots <= 0.0) { p.err = "归一后手数为 0"; return false; }

   //--- 7. 摘要（按钮 tooltip / 日志共用同一份描述，避免两处措辞不一致）---
   p.desc = StringFormat("%s %.2f 手 @ %s | 止损 %s | 止盈 %s | 计划亏 %s",
                         TypeName(p.type), p.lots,
                         DoubleToString(p.entry, dg),
                         DoubleToString(p.sl, dg),
                         DoubleToString(p.tp, dg),
                         DoubleToString(p.risk, 2));
   if(adjusted)
      p.desc += StringFormat("｜注意：手数已按本品种步长归一（指标算的是 %.2f）", before);

   p.ok = true;
   return true;
}

//+------------------------------------------------------------------+
//| 发单                                                              |
//+------------------------------------------------------------------+
bool PlacePlan(const SPlan &p)
{
   const int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double entry = NormalizeDouble(p.entry, dg);
   const double sl    = NormalizeDouble(p.sl, dg);
   const double tp    = NormalizeDouble(p.tp, dg);
   const string cmt   = StringFormat("TVPT#%d", p.id);

   PrepareTrade();

   bool ok = false;
   switch(p.type)
   {
      case ORDER_TYPE_BUY_LIMIT:  ok = g_trade.BuyLimit (p.lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt); break;
      case ORDER_TYPE_BUY_STOP:   ok = g_trade.BuyStop  (p.lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt); break;
      case ORDER_TYPE_SELL_LIMIT: ok = g_trade.SellLimit(p.lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt); break;
      case ORDER_TYPE_SELL_STOP:  ok = g_trade.SellStop (p.lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt); break;
      case ORDER_TYPE_BUY:        ok = g_trade.Buy      (p.lots, _Symbol, 0.0, sl, tp, cmt);                     break;
      case ORDER_TYPE_SELL:       ok = g_trade.Sell     (p.lots, _Symbol, 0.0, sl, tp, cmt);                     break;
      default:
         // p 是 const 引用（只读），这里不能往里写 err
         PrintFormat("[失败] 内部错误：未知挂单类型 (%d)", (int)p.type);
         ShowMsg("[失败] 内部错误：未知挂单类型", InpColorWarn, "把这条日志发给维护者");
         return false;
   }

   if(ok)
   {
      // 顺带把**精确**占用保证金打出来：OrderCalcMargin 在**指标里不可用**
      // （已实测 marginProbe=FAIL），但在 EA 里可用 —— 所以这里是用户能拿到的
      // 唯一精确口径，指标面板上那个只是"名义价值/杠杆"的估算。
      double mreq = 0.0;
      const bool mok = OrderCalcMargin((p.isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),
                                       _Symbol, p.lots, entry, mreq);
      PrintFormat("[成功] %s | %s | 票号=#%I64u | 成交=#%I64u | 占用保证金=%s",
                  _Symbol, p.desc, g_trade.ResultOrder(), g_trade.ResultDeal(),
                  (mok ? DoubleToString(mreq, 2) : "n/a"));
      const bool isPending = (p.type == ORDER_TYPE_BUY_LIMIT || p.type == ORDER_TYPE_SELL_LIMIT ||
                              p.type == ORDER_TYPE_BUY_STOP  || p.type == ORDER_TYPE_SELL_STOP);
      ShowMsg(StringFormat("[成功] %s #%I64u", (isPending ? "已挂单" : "已进场"), g_trade.ResultOrder()),
              InpColorBuy,
              p.desc + (mok ? StringFormat("｜占用保证金 %s", DoubleToString(mreq, 2)) : ""));
      return true;
   }

   PrintFormat("[失败] %s | %s | retcode=%d | %s",
               _Symbol, p.desc, (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   ShowMsg(StringFormat("[失败] retcode=%d", (int)g_trade.ResultRetcode()),
           InpColorWarn, g_trade.ResultRetcodeDescription() + "（完整请求见专家日志）");
   return false;
}

//+------------------------------------------------------------------+
//| 撤单：只撤**本 EA 的 Magic + 本品种**的挂单                        |
//|   ⚠️ 不碰已成持仓的单 —— 那已经不是"挂单"了，撤它等于平仓，        |
//|      那是另一件事，不能藏在"撤销挂单"这个按钮里。                   |
//+------------------------------------------------------------------+
void CancelOurOrders()
{
   int done = 0, bad = 0, foreign = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagic) { foreign++; continue; }
      if(g_trade.OrderDelete(tk)) done++;
      else
      {
         bad++;
         PrintFormat("[失败] 撤单 #%I64u | retcode=%d | %s",
                     tk, (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }

   const string sub = StringFormat("本品种共 %d 张挂单：撤掉 %d，失败 %d%s",
                                   done + bad, done, bad,
                                   (foreign > 0 ? StringFormat("（另有 %d 张是别的 Magic，没动）", foreign) : ""));
   if(bad > 0)         ShowMsg(StringFormat("[失败] 有 %d 张没撤掉", bad), InpColorWarn, sub);
   else if(done > 0)   ShowMsg(StringFormat("[成功] 已撤 %d 张挂单", done), InpColorBuy, sub);
   else                ShowMsg("[注意] 没有可撤的挂单", InpColorWarn, sub);
   PrintFormat("[撤单] %s", sub);
}

//+------------------------------------------------------------------+
//| 平仓：只平**本 EA 的 Magic + 本品种**的持仓                        |
//|   为什么手动模式必须有它：没有指标的图上没有止盈止损线可参考，      |
//|   一个"能进场但不能出场"的回测面板是没法用的。                     |
//|   ⚠️ 这个按钮**不要二次确认**，与开仓相反：平仓是降风险，           |
//|      而且"急着平却要点两下"本身就是风险。开仓才需要两步。          |
//+------------------------------------------------------------------+
void CloseOurPositions()
{
   PrepareTrade();

   int done = 0, bad = 0, foreign = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) { foreign++; continue; }
      if(g_trade.PositionClose(tk)) done++;
      else
      {
         bad++;
         PrintFormat("[失败] 平仓 #%I64u | retcode=%d | %s",
                     tk, (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }

   const string sub = StringFormat("本品种共 %d 个持仓：平掉 %d，失败 %d%s",
                                   done + bad, done, bad,
                                   (foreign > 0 ? StringFormat("（另有 %d 个是别的 Magic，没动）", foreign) : ""));
   if(bad > 0)         ShowMsg(StringFormat("[失败] 有 %d 个没平掉", bad), InpColorWarn, sub);
   else if(done > 0)   ShowMsg(StringFormat("[成功] 已平 %d 个持仓", done), InpColorBuy, sub);
   else                ShowMsg("[注意] 没有可平的持仓", InpColorWarn, sub);
   PrintFormat("[平仓] %s", sub);
}

//+------------------------------------------------------------------+
//| 按钮                                                              |
//+------------------------------------------------------------------+
void UpdateButtons()
{
   const int bx = AnchorX();
   const int by = AnchorY();

   ObjectSetString(0, BTN_CANCEL, OBJPROP_TOOLTIP,
                   StringFormat("撤掉本 EA（Magic=%d）在本品种上的全部挂单；已成持仓的不动",
                                (int)InpMagic));

   if(InToolMode())
   {
      // 指标模式：一次一张挂单，按工具的参数来
      MakeButton(BTN_PLACE, (g_armed == ARM_TOOL ? "确认挂单?" : "按工具挂单"),
                 bx, by, 104, 22, clrWhite, (g_armed == ARM_TOOL ? C'150,90,20' : C'28,60,110'));
      MakeButton(BTN_CANCEL, "撤销挂单", bx + 110, by, 92, 22, clrWhite, C'52,58,70');
      KillIfExists(BTN_BUY);
      KillIfExists(BTN_SELL);
      KillIfExists(BTN_CLOSEALL);
   }
   else
   {
      // 手动模式：市价 BUY / SELL / 平仓 / 撤单
      MakeButton(BTN_BUY,  (g_armed == ARM_BUY  ? "确认 BUY?"  : "BUY"),
                 bx, by, 84, 22, clrWhite, (g_armed == ARM_BUY  ? C'150,90,20' : C'22,101,52'));
      MakeButton(BTN_SELL, (g_armed == ARM_SELL ? "确认 SELL?" : "SELL"),
                 bx + 90, by, 84, 22, clrWhite, (g_armed == ARM_SELL ? C'150,90,20' : C'150,44,44'));
      MakeButton(BTN_CLOSEALL, "平掉本EA仓", bx + 180, by, 104, 22, clrWhite, C'96,72,20');
      MakeButton(BTN_CANCEL, "撤销挂单", bx + 290, by, 92, 22, clrWhite, C'52,58,70');
      KillIfExists(BTN_PLACE);
      ObjectSetString(0, BTN_CLOSEALL, OBJPROP_TOOLTIP,
                      "平掉本 EA 在本品种上的全部持仓（一次点击，**不**二次确认 —— 平仓是降风险）");
   }

   UpdateTooltips();
   ChartRedraw();
}

// 每秒刷新一次：悬停就能看到"现在这一下会下出什么单"
void UpdateTooltips()
{
   const string armPrefix = "点击后会先上膛，再点一次才执行。\n";
   const string armedPrefix = "已上膛 —— 再点一次立即执行：\n";

   if(InToolMode())
   {
      SPlan p;
      if(BuildPlan(p))
         ObjectSetString(0, BTN_PLACE, OBJPROP_TOOLTIP,
                         (g_armed == ARM_TOOL ? armedPrefix : armPrefix) + "将挂：" + p.desc);
      else
         ObjectSetString(0, BTN_PLACE, OBJPROP_TOOLTIP, "当前挂不出去：" + p.err);
      return;
   }

   // 手动模式（图上没有指标，例如在策略测试器里）—— 市价单，参数来自输入
   SPlan b, s;
   const bool okB = BuildManualPlan(b, true);
   const bool okS = BuildManualPlan(s, false);
   ObjectSetString(0, BTN_BUY, OBJPROP_TOOLTIP,
                   (okB ? ((g_armed == ARM_BUY ? armedPrefix : armPrefix) + b.desc)
                        : ("现在下不出去：" + b.err)));
   ObjectSetString(0, BTN_SELL, OBJPROP_TOOLTIP,
                   (okS ? ((g_armed == ARM_SELL ? armedPrefix : armPrefix) + s.desc)
                        : ("现在下不出去：" + s.err)));
}

//+------------------------------------------------------------------+
//| 生命周期                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpMagic <= 0)
   {
      Alert("PositionTrader: Magic 必须为正数（撤单/平仓靠它区分自己的单）。");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpManualSLPoints < 0 || InpManualTPPoints < 0)
   {
      Alert("PositionTrader: 手动模式的止损/止盈点数不能为负。");
      return INIT_PARAMETERS_INCORRECT;
   }

   PrepareTrade();

   // 测试器里把指标拉起来（**仅测试器**：实盘图上你已经有指标了，再拉一个会出现两套面板）。
   //   两个关键点：
   //    ① 只能由 EA 用 iCustom 创建 —— 策略测试器本身**不跑指标**；
   //    ② 测试器**默认把 iCustom 创建的指标藏起来**，必须 TesterHideIndicators(false)。
   if(InpTesterSpawnIndicator && MQLInfoInteger(MQL_TESTER))
   {
      TesterHideIndicators(false);
      g_indHandle = iCustom(_Symbol, _Period, "PositionTool");
      PrintFormat("[测试器] 拉起指标 PositionTool | handle=%d | err=%d",
                  g_indHandle, GetLastError());
   }

   EventSetTimer(1);
   g_lastToolMode = InToolMode();
   UpdateButtons();

   PrintFormat("PositionTrader build=%s 已启动 | %s %s | Magic=%d | 允许市价=%s | 模式=%s | 接口对象 %s",
               BUILD_TAG, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
               (int)InpMagic, (InpAllowMarket ? "true" : "false"),
               (g_lastToolMode ? "指标模式（按工具下单）" : "手动模式（市价 BUY/SELL）"),
               INTENT_OBJ);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0, BTN_PLACE);
   ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, BTN_BUY);
   ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_CLOSEALL);
   ObjectDelete(0, MSG_MAIN);
   ObjectDelete(0, MSG_SUB);
   ChartRedraw();
   if(InpDebug) PrintFormat("DBG %s deinit reason=%d", BUILD_TAG, reason);
}

// 本 EA 的交易全部由点击驱动，不看行情 —— 但这里要做两件事：
//   ① 测试器里 iCustom 拉起的指标要自检一次（对象到底有没有生成）
//   ② 轮询按钮状态（测试器里点击事件可能不来）
void OnTick()
{
   if(!g_spawnChecked && g_indHandle != INVALID_HANDLE)
   {
      g_spawnChecked = true;
      const bool panel = (ObjectFind(0, "PT_BTN_LONG") >= 0);
      const bool intr  = (ObjectFind(0, INTENT_OBJ) >= 0);
      PrintFormat("[测试器] 指标自检：面板对象=%s 接口对象=%s ⇒ %s",
                  (panel ? "在" : "缺失"), (intr ? "在" : "缺失"),
                  (panel ? "指标在测试器里跑起来了（但按钮能不能点，还要看点击事件/轮询）"
                         : "指标没产生任何对象 —— 这条路走不通，别在上面花时间了"));
   }
   PollButtons();
}

void OnTimer()
{
   // 上膛超时 → 自动解除（避免"手滑上膛、半小时后误点发单"）
   if(g_armed != ARM_NONE && (TimeCurrent() - g_armedAt) > ARM_SECONDS)
   {
      g_armed = ARM_NONE;
      UpdateButtons();
      ShowMsg("[注意] 确认已超时取消", InpColorWarn,
              StringFormat("二次确认窗口是 %d 秒，重来一次即可", ARM_SECONDS));
      return;
   }

   // 指标出现/消失时按钮组要跟着换（比如你在图上挂上或卸载了指标）。
   // 没有这一步，测试器里跑着的 EA 不会自动切到手动按钮组。
   const bool tm = InToolMode();
   if(tm != g_lastToolMode)
   {
      g_lastToolMode = tm;
      g_armed = ARM_NONE;
      UpdateButtons();
      PrintFormat("[模式] 切到%s", (tm ? "指标模式（按工具下单）" : "手动模式（市价 BUY/SELL）"));
      return;
   }

   if(g_msgShown && (TimeCurrent() - g_msgAt) > MSG_SECONDS) ClearMsg();
   UpdateTooltips();
}

//+------------------------------------------------------------------+
//| 开仓类动作的统一两步确认                                           |
//|   第一下只上膛（**上膛前先校验**：明知下不出去就别让他上膛），       |
//|   第二下才真发单，而且**重新构建一次计划** —— 这中间行情、画线、     |
//|   甚至手数都可能变过，拿第一下的旧结论去发单是错的。                 |
//+------------------------------------------------------------------+
void DoArmedAction(const int kind)
{
   const bool firstTime = (g_armed != kind);

   SPlan p;
   const bool okPlan = (kind == ARM_TOOL) ? BuildPlan(p) : BuildManualPlan(p, kind == ARM_BUY);
   if(!okPlan)
   {
      ShowMsg("[失败] 下不出去", InpColorWarn, p.err);
      PrintFormat("[失败] %s", p.err);
      return;
   }

   if(firstTime)
   {
      g_armed   = kind;
      g_armedAt = TimeCurrent();
      UpdateButtons();
      ShowMsg(StringFormat("[注意] 已上膛：%d 秒内再点一次确认", ARM_SECONDS), InpColorWarn, p.desc);
      return;
   }

   g_armed = ARM_NONE;
   UpdateButtons();
   PlacePlan(p);
}

//+------------------------------------------------------------------+
//| 按钮点击的统一入口（点击事件 + 轮询两条路都走这里）                 |
//|   同一按钮 500ms 内只执行一次：测试器里两条路可能都触发。           |
//|   用 GetTickCount()（墙钟毫秒）而不是 TimeCurrent() —— 测试器里    |
//|   服务器时间会随 tick 跳，用它做去重窗口是错的。                    |
//+------------------------------------------------------------------+
void HandleButton(const string nm)
{
   const uint now = GetTickCount();
   if(nm == g_lastBtn && (now - g_lastBtnMs) < 500) return;   // 去重
   g_lastBtn   = nm;
   g_lastBtnMs = now;

   // 开仓类：两步确认
   if(nm == BTN_PLACE) { DoArmedAction(ARM_TOOL); return; }
   if(nm == BTN_BUY)   { DoArmedAction(ARM_BUY);  return; }
   if(nm == BTN_SELL)  { DoArmedAction(ARM_SELL); return; }

   // 减风险类：一次点击直接执行
   if(nm == BTN_CLOSEALL)
   {
      g_armed = ARM_NONE;
      CloseOurPositions();
      return;
   }
   if(nm == BTN_CANCEL)
   {
      g_armed = ARM_NONE;
      CancelOurOrders();
      return;
   }
}

//+------------------------------------------------------------------+
//| 测试器兜底：轮询按钮的**按下状态**                                  |
//|   社区里"按钮在可视化测试器里点不动"是老问题（多个 MQL5 帖子在问）， |
//|   因为 CHARTEVENT_OBJECT_CLICK 不一定会送到 EA。但**按钮被点击后    |
//|   的 STATE 状态是会被正确设置的** —— 故在 OnTick 里轮询它。         |
//|   这条兜底在实盘上同样安全：事件路径已经把 STATE 清掉了，轮询看不到。|
//+------------------------------------------------------------------+
void PollButtons()
{
   const string btns[] = {BTN_PLACE, BTN_BUY, BTN_SELL, BTN_CLOSEALL, BTN_CANCEL};
   for(int i = 0; i < ArraySize(btns); i++)
   {
      if(ObjectFind(0, btns[i]) < 0) continue;
      if(!(bool)ObjectGetInteger(0, btns[i], OBJPROP_STATE)) continue;

      ObjectSetInteger(0, btns[i], OBJPROP_STATE, false);   // 消费掉这次按下
      if(InpDebug) PrintFormat("DBG %s poll-click <%s>", BUILD_TAG, btns[i]);
      HandleButton(btns[i]);
      return;   // 一次 tick 只处理一个，避免连锁
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // 诊断锚点：测试器里到底有没有点击事件，靠这一行判定（开 InpDebug 才有）
   if(InpDebug) PrintFormat("DBG %s object-click <%s>", BUILD_TAG, sparam);

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);   // 放开按钮的按下态
   ChartRedraw();
   HandleButton(sparam);
}
//+------------------------------------------------------------------+
