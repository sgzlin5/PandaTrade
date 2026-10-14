//+------------------------------------------------------------------+
//|  MACD.mq5                                                 |
//|  风格与 库内其他指标一致                                       |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   3

// ── MACD 线（蓝色 #58a6ff）
#property indicator_label1  "MACD"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'88,166,255'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

// ── 信号线（橙色 #f0883e）
#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'240,136,62'
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// ── 能量柱（4 色：涨强/跌强/涨弱/跌弱）
// 强色：原色
//   涨强 #26a641 → C'38,166,65'
//   跌强 #f85149 → C'248,81,73'
// 弱色：原色与深背景 #0d1117 (C'13,17,23') 各 50% 混合，模拟 50% alpha
//   涨弱 → C'26,92,44'
//   跌弱 → C'131,49,48'
#property indicator_label3  "Histogram"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  C'38,166,65',C'248,81,73',C'26,92,44',C'131,49,48'
#property indicator_width3  4

// 颜色索引含义
#define COLOR_UP_STRONG   0   // 涨 + 能量增强
#define COLOR_DOWN_STRONG 1   // 跌 + 能量增强
#define COLOR_UP_FADE     2   // 涨 + 能量减弱
#define COLOR_DOWN_FADE   3   // 跌 + 能量减弱

input int InpFastEMA   = 12;
input int InpSlowEMA   = 26;
input int InpSignalEMA = 9;
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;

double bufMACD[];
double bufSignal[];
double bufHist[];
double bufHistColor[];

int handleFast, handleSlow;

int OnInit()
{
   SetIndexBuffer(0, bufMACD,      INDICATOR_DATA);
   SetIndexBuffer(1, bufSignal,    INDICATOR_DATA);
   SetIndexBuffer(2, bufHist,      INDICATOR_DATA);
   SetIndexBuffer(3, bufHistColor, INDICATOR_COLOR_INDEX);

   // 启用 4 个颜色索引
   PlotIndexSetInteger(2, PLOT_COLOR_INDEXES, 4);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpSlowEMA + InpSignalEMA - 1);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpSlowEMA - 1);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpSlowEMA + InpSignalEMA - 1);

   handleFast = iMA(_Symbol, PERIOD_CURRENT, InpFastEMA, 0, MODE_EMA, InpPrice);
   handleSlow = iMA(_Symbol, PERIOD_CURRENT, InpSlowEMA, 0, MODE_EMA, InpPrice);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 1);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("MACD(%d,%d,%d)", InpFastEMA, InpSlowEMA, InpSignalEMA));
   return INIT_SUCCEEDED;
}

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
   if (rates_total < InpSlowEMA + InpSignalEMA) return 0;

   double emaFast[], emaSlow[];
   if (CopyBuffer(handleFast, 0, 0, rates_total, emaFast) <= 0) return 0;
   if (CopyBuffer(handleSlow, 0, 0, rates_total, emaSlow) <= 0) return 0;

   // ── 计算 MACD 线 ─────────────────────────────────────────────
   for (int i = 0; i < rates_total; i++)
      bufMACD[i] = emaFast[i] - emaSlow[i];

   // ── 计算 Signal（EMA of MACD）────────────────────────────────
   double k     = 2.0 / (InpSignalEMA + 1);
   int    start = InpSlowEMA - 1 + InpSignalEMA - 1;
   if (start >= rates_total) return 0;

   // 用前 InpSignalEMA 根 MACD 的简单均值作为种子
   double sum = 0;
   for (int i = InpSlowEMA - 1; i <= start; i++) sum += bufMACD[i];
   bufSignal[start] = sum / InpSignalEMA;

   for (int i = start + 1; i < rates_total; i++)
      bufSignal[i] = bufMACD[i] * k + bufSignal[i - 1] * (1.0 - k);

   // ── 计算柱高度 + 颜色索引 ────────────────────────────────────
   for (int i = 0; i < rates_total; i++)
   {
      bufHist[i]      = EMPTY_VALUE;
      bufHistColor[i] = COLOR_UP_STRONG;   // 默认值，对 EMPTY_VALUE 行无影响

      if (i < start || bufSignal[i] == EMPTY_VALUE) continue;

      double h     = bufMACD[i] - bufSignal[i];
      double hPrev = (i > start) ? (bufMACD[i-1] - bufSignal[i-1]) : h;

      bufHist[i] = h;

      // 能量减弱：当前柱绝对值 < 前一柱绝对值
      bool isUp   = (h >= 0);
      bool isFade = (i > start) && (MathAbs(h) < MathAbs(hPrev));

      if      ( isUp && !isFade) bufHistColor[i] = COLOR_UP_STRONG;
      else if ( isUp &&  isFade) bufHistColor[i] = COLOR_UP_FADE;
      else if (!isUp && !isFade) bufHistColor[i] = COLOR_DOWN_STRONG;
      else                       bufHistColor[i] = COLOR_DOWN_FADE;
   }

   return rates_total;
}
