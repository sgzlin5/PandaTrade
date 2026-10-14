//+------------------------------------------------------------------+
//|  ZigZag.mq5                                               |
//|  ZigZag 指标 — 对称窗口极值检测 + 标准状态机                        |
//|  MQL5 折线图正确模式参考                                          |
//+------------------------------------------------------------------+

// ╔══════════════════════════════════════════════════════════════════╗
// ║  MQL5 折线图绘制关键规则（通用）                                 ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ 1. indicator_type   → DRAW_LINE  (连续线) / DRAW_SECTION (分段)║
// ║ 2. PLOT_EMPTY_VALUE  → EMPTY_VALUE (≈1.79e308)，绝不能 = 0.0   ║
// ║ 3. 缓冲区初始化       → ArrayInitialize(buf, EMPTY_VALUE)       ║
// ║ 4. SetIndexBuffer 时 → INDICATOR_DATA (可见) / CALCULATIONS(隐藏)║
// ║ 5. PLOT_DRAW_BEGIN   → 跳过前 N 根无效 bar                      ║
// ║ 6. OnCalculate 必须  → return rates_total （全量算完）           ║
// ║ 7. indicator_chart_window → 主图 / indicator_separate_window     ║
// ╚══════════════════════════════════════════════════════════════════╝

// ── 指标属性：绑定到主图表窗口 ──
#property indicator_chart_window
#property indicator_buffers 3       // 3 个缓冲区
#property indicator_plots   1       // 1 个绘图序列

// ── 折线外观（青色 #39c5cf）──
#property indicator_label1  "ZigZag"
#property indicator_type1   DRAW_SECTION      // 分段连线：自动跳过 EMPTY_VALUE 并在相邻有效点间绘制
#property indicator_color1  C'57,197,207'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// ── 输入参数 ──
input int InpDepth     = 12;   // Depth  两侧搜索窗口
input int InpDeviation = 5;    // Deviation  最小点数偏差
input int InpBackstep  = 3;    // Backstep   最小 bar 间隔

// ── 缓冲区（3 个，仅第 0 号参与绘图）──
double bufZigZag[];    // [0] 主折线 — 仅在转折点存真实价格，其余 EMPTY_VALUE
double bufHighPeak[];  // [1] 辅助 — 候选局部高点的 high 值
double bufLowPeak[];   // [2] 辅助 — 候选局部低点的 low 值

//+------------------------------------------------------------------+
//| 工具：在 arr[index] 至 arr[index+count-1] 中找最大值索引          |
//+------------------------------------------------------------------+
int FindMax(const double &arr[], int index, int count)
{
   if(count <= 0) return -1;
   int    best = index;
   double val  = arr[index];
   for(int j = index + 1; j < index + count; j++)
      if(arr[j] > val) { val = arr[j]; best = j; }
   return best;
}

//+------------------------------------------------------------------+
//| 工具：在 arr[index] 至 arr[index+count-1] 中找最小值索引          |
//+------------------------------------------------------------------+
int FindMin(const double &arr[], int index, int count)
{
   if(count <= 0) return -1;
   int    best = index;
   double val  = arr[index];
   for(int j = index + 1; j < index + count; j++)
      if(arr[j] < val) { val = arr[j]; best = j; }
   return best;
}

//+------------------------------------------------------------------+
//| OnInit — 绑定缓冲区、设置空值、配置外观                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpDepth <= 0 || InpDeviation < 0 || InpBackstep <= 0)
   {
      PrintFormat("ZigZag: Invalid params (Depth=%d, Deviation=%d, Backstep=%d)",
                  InpDepth, InpDeviation, InpBackstep);
      return INIT_PARAMETERS_INCORRECT;
   }

   // 缓冲区绑定
   SetIndexBuffer(0, bufZigZag,   INDICATOR_DATA);         // 可见
   SetIndexBuffer(1, bufHighPeak, INDICATOR_CALCULATIONS);  // 隐藏
   SetIndexBuffer(2, bufLowPeak,  INDICATOR_CALCULATIONS);  // 隐藏

   // ═══════════════════════════════════════════════════════════
   // ★ 折线图核心设置
   // ═══════════════════════════════════════════════════════════
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);    // 空值标记 = DBL_MAX
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN,  0);              // 从第 0 根 bar 起可绘制

   // 短名称与小数位
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("ZigZag(%d,%d,%d)",
                                   InpDepth, InpDeviation, InpBackstep));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnCalculate — 主计算入口                                          |
//+------------------------------------------------------------------+
int OnCalculate(const int       rates_total,
                const int       prev_calculated,
                const datetime  &time[],
                const double    &open[],
                const double    &high[],
                const double    &low[],
                const double    &close[],
                const long      &tick_volume[],
                const long      &volume[],
                const int       &spread[])
{
   if(rates_total < InpDepth + InpBackstep + 1) return 0;

   double priceDev = InpDeviation * _Point;

   // ── 全量初始化 ──
   ArrayInitialize(bufZigZag,   EMPTY_VALUE);
   ArrayInitialize(bufHighPeak, 0.0);
   ArrayInitialize(bufLowPeak,  0.0);

   // ═══════════════════════════════════════════════════════════════
   // Phase 1 — 对称窗口局部极值检测
   //
   // ★ 关键修复：旧版只检查 [i, i+Depth]（前向窗口），
   //    正确做法是检查 [i-Depth, i+Depth]（中心对称窗口）。
   //
   //    对 bar i：如果 high[i] 是 centeredWindow 中的最大值，
   //    则 bufHighPeak[i] = high[i]（候选高点）。
   // ═══════════════════════════════════════════════════════════════
   for(int i = 0; i < rates_total; i++)
   {
      int left  = MathMax(0,          i - InpDepth);
      int right = MathMin(rates_total - 1, i + InpDepth);
      int wSize = right - left + 1;

      // 检查 high[i] 是否为中心窗口最大值
      if(FindMax(high, left, wSize) == i)
         bufHighPeak[i] = high[i];

      // 检查 low[i] 是否为中心窗口最小值
      if(FindMin(low, left, wSize) == i)
         bufLowPeak[i] = low[i];
   }

   // ═══════════════════════════════════════════════════════════════
   // Phase 2 — 标准状态机确认转折点
   //
   //    状态   含义
   //    ────   ────
   //      0    初始：寻找第一个候选极值
   //     -1    已有确认高 → 正在寻找更低点来确认该高为转折
   //     +1    已有确认低 → 正在寻找更高点来确认该低为转折
   //
   //    确认条件（三者同时满足）：
   //      a) 方向反转 — 新极值类型与前一个相反
   //      b) Deviation — 价格跨度 ≥ InpDeviation 点
   //      c) Backstep  — bar 间隔 ≥ InpBackstep
   // ═══════════════════════════════════════════════════════════════
   int    state         = 0;       // 当前状态
   int    lastPivotPos  = -1;      // 上一确认转折的 bar 索引
   int    trackingPos   = -1;      // 当前追踪极值的 bar 索引
   double trackingVal   = 0.0;     // 当前追踪极值的价格
   double oppositeVal   = 0.0;     // 对向跟随价格

   for(int i = 0; i < rates_total; i++)
   {
      switch(state)
      {
         // ── 初始：找第一个候选极值 ──
         case 0:
         {
            if(bufHighPeak[i] != 0.0)
            {
               trackingPos = i;  trackingVal = bufHighPeak[i];
               oppositeVal = low[i];
               state       = -1;   // 已有高 → 等待低来确认
            }
            if(bufLowPeak[i] != 0.0)
            {
               if(state != 0)     // 高/低同时出现 → 以高优先
                  break;
               trackingPos = i;  trackingVal = bufLowPeak[i];
               oppositeVal = high[i];
               state       = 1;    // 已有低 → 等待高来确认
            }
            break;
         }

         // ── 有高，等低来确认 ──
         case -1:
         {
            // 贪心更新：出现更高高则替换跟踪锚
            if(bufHighPeak[i] != 0.0 && bufHighPeak[i] > trackingVal)
            {
               if(lastPivotPos < 0 || (i - lastPivotPos) >= InpBackstep)
               {
                  trackingPos = i;
                  trackingVal = bufHighPeak[i];
               }
            }

            // 低反：价格下跌超过偏差 → 确认 trackingPos 上的高为转折点
            if(bufLowPeak[i] != 0.0
               && (trackingVal - bufLowPeak[i]) > priceDev
               && (i - trackingPos) >= InpBackstep)
            {
               bufZigZag[trackingPos] = trackingVal;  // ★ 写入可见缓冲区
               lastPivotPos = trackingPos;

               trackingPos = i;
               trackingVal = bufLowPeak[i];
               oppositeVal = high[i];
               state       = 1;     // 转向：等新高来确认这个低
            }
            break;
         }

         // ── 有低，等高来确认 ──
         case 1:
         {
            // 贪心更新：出现更低低则替换跟踪锚
            if(bufLowPeak[i] != 0.0 && bufLowPeak[i] < trackingVal)
            {
               if(lastPivotPos < 0 || (i - lastPivotPos) >= InpBackstep)
               {
                  trackingPos = i;
                  trackingVal = bufLowPeak[i];
               }
            }

            // 高反：价格上涨超过偏差 → 确认 trackingPos 上的低为转折点
            if(bufHighPeak[i] != 0.0
               && (bufHighPeak[i] - trackingVal) > priceDev
               && (i - trackingPos) >= InpBackstep)
            {
               bufZigZag[trackingPos] = trackingVal;  // ★ 写入可见缓冲区
               lastPivotPos = trackingPos;

               trackingPos = i;
               trackingVal = bufHighPeak[i];
               oppositeVal = low[i];
               state       = -1;    // 转向：等新低来确认这个高
            }
            break;
         }
      }
   }

   // ── 收尾：写入最后一个未确认极值 ──
   //   （让最后一个不完整 swing 也可见）
   if(state != 0 && lastPivotPos >= 0 && trackingPos > lastPivotPos)
      bufZigZag[trackingPos] = trackingVal;

   return rates_total;
}
//+------------------------------------------------------------------+
