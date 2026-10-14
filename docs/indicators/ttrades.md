# ttrades

> 源文件：`Indictor/ttrades.mq5` ｜ 详细口径与参数（自 README 拆分） ｜ [返回 README](../../README.md)


> `Indictor/ttrades.mq5`

**TTFM°（TTrades Fractal Model）主图叠加指标**，移植自一份 Pine v6 脚本（`ttrades/pinescript`，社区版 TTFM°，
© mindyourbuisness / "Based on HTF Candles by Fadi"）。它做三件事：

1. 把**高周期蜡烛画在主图右侧**（`InpHtfMaxDisplay` 根，含实体/影线/名称/倒计时/起始竖线）；
2. 按 TTFM 规则标注 **T-Spot 区域**（六个分支：普通 / 扩张 / 顺势中点 × 看涨看跌，另有 Silver 变体）；
3. **T-Spot 扫破确认**时画确认线 + 标签 + 告警 + 按风险反推的仓位建议。

#### 口径分栏（引用前必读）

- **口径依据**：`docs/research/2026-09-23-TTFM-rules-report.md`（一手资料调研）。
- **T-Spot 六个判定式**逐条照抄 Pine，代码注释里带**行号**（Pine 行 1205 / 1274 / 1331 / 1377 / 1424 / 1459）。
- ⚠️ **Silver 的时段条件**（`candleOfDay==5` 或 `==4 且 NY 时 ≥13`）在 Pine 源里就是**自定口径**
  —— 一手资料只有 "kill zone 不重要、setup 才重要" 的叙述，没有任何时钟锚定的机械规则。
  本实现**原样保留**并在代码里标为自定口径，**不得当作他的口径引用**。
- ⚠️ **投影水平** `1,0,-1,-2,-2.5,-4` 为调研方推断（第二篇原文的水平列表被截断），中介置信度。
- 移植差异 / 待实测点 / 参数对照：`docs/plans/2026-10-13-ttrades-mq5-port.md`。

#### 输入参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `InpHtfMode` | `HTF_AUTO` | HTF 自动映射（1m→15m、5m→1h、15m→4h、1h→1d、4h→1w、1d→1mo；其余→1w）|
| `InpHtfCustom` | `PERIOD_W1` | `HTF_CUSTOM` 时生效 |
| `InpTspotBias` | `BIAS_NONE` | T-Spot 方向过滤（None = 两个方向都画）|
| `InpShowHtf` / `InpHtfMaxDisplay` | `true` / `4` | HTF 叠加开关 / 显示最近 N 根（1..6）|
| `InpHtfOffsetBars` / `InpHtfBodyBars` / `InpHtfBufferBars` / `InpHtfGapBars` | `20` / `2` / `1` / `7` | 右侧偏移 / 实体宽 / 烛间距（单位都是图 bar）|
| `InpBullBody` / `InpBearBody` / `InpBullWick` / `InpBearWick` | 绿 / 红 | 实体与影线颜色 |
| `InpHtfLabelShow` / `InpHtfTimerShow` | `true` / `true` | HTF 名称 / 剩余时间 |
| `InpHtfLineShow` / `InpHtfLineColor` / `InpHtfLineStyle` | `true` / 黑 / `DOT` | HTF 起始竖线（`OBJ_VLINE`，不占价格刻度）|
| `InpShowTspot` / `InpShowOnlyLatest` / `InpExtendLatest` | `true` / `true` / `true` | T-Spot 开关 / 只留最新 / 右端跟随当前 bar |
| `InpShowChartSweeps` | `true` | 扫破位水平短线 |
| `InpBodyFillPercent` | `30` | T-Spot 填充强度 %（**相对图表底色**混色；0 = 空心框）|
| `InpTspotLineStyle` / `InpMidlineWidth` / `InpShowCloseLine` | `DOT` / `1` / `true` | 中线与收盘线 |
| `InpShowSilver` / `InpShowTtfmLabels` / `InpHideAgainst` | `true` / `true` / `true` | Silver 标签 / C2-C3-C4 标签 / 逆向 T-Spot 隐藏（改色）|
| `InpShowSweeps` / `InpShowConfLines` / `InpShowConfLabels` / `InpUseBodyPivots` | `true` / `true` / `true` / `false` | 扫破确认 / 确认线 / 确认标签 / 用实体判 pivot |
| `InpShowCisd` / `InpColorCisd` / `InpCisdWidth` | `true` / 蓝 / `2` | CISD 线 |
| `InpShowProj` / `InpColorProj` / `InpProjLevels` / `InpExtendProj` | `true` / 橙 / `"1,0,-1,-2,-2.5,-4"` / `true` | 目标投影 |
| `InpShowPosSize` / `InpAccountBalance` / `InpRiskType` / `InpRiskAmount` | `true` / `10000` / `PERCENT` / `1.0` | 仓位建议（手数 = 风险额 ÷ (止损距离 ÷ tickSize × tickValue)）|
| `InpShowPanel` / `InpPanelCorner` / `InpPanelFontSize` / `InpPanelColor` | `true` / 右上 / `9` / 黑 | 信息面板（标题 / 倒计时 / 偏置 / 仓位）|
| `InpAlertPopup` / `InpAlertPush` | `true` / `false` | `Alert()` / `SendNotification()`（同一图 bar 不重复告警）|
| `InpDebugShow` | `false` | 日志：每根新 bar 一行 `TTFM_RENDER`，每次 T-Spot 一行 `TTFM_TSPOT` |

#### 验收

- 日志应有 `ttrades/TTFM 已初始化 | build=v1.00-s1 | chart=… htf=… | …`（所有观感开关都在这一行里，便于回答"装的是哪一版/开了哪些"）
- `InpDebugShow=true`：每根新 bar 一行 `TTFM_RENDER bar=… newHtf=… nHtfBars=… tspots=… touched=… bias=…`；
  出现 T-Spot 时另有 `TTFM_TSPOT key=… dir=… variant=1..6 …`
- **HTF 蜡烛不显示**：先看 `nHtfBars` 是否 ≥ 4（取不到 HTF 数据），再看图表右侧是否有空白（蜡烛画在未来时间，需要 Chart Shift）
- **T-Spot 不出**：`InpTspotBias` 是否挡住了方向；HTF 数据是否少于 4 根
- ⚠️ `0 errors / 0 warnings` **不能证明语义正确**（仓库既有教训）→ 必须与 TradingView 上同段行情的 Pine 图逐根比对
