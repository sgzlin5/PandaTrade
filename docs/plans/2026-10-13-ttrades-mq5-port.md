# ttrades.mq5 —— Pine（TTFM°）→ MT5 移植说明与验证清单

> **源**：`ttrades/pinescript`（`simon-ru/ttrades` @`48cfa89`，Pine v6，2015 行；
> 头部 `© mindyourbuisness` / "Based on HTF Candles by Fadi"）
> **产物**：`Indictor/ttrades.mq5`（`BUILD_TAG = v1.00-s1`，1393 行）
> **口径依据**：`docs/research/2026-09-23-TTFM-rules-report.md`（一手资料调研）
> **格式参照**：`TradingVue/MIGRATION_NOTES.md`（那一次是反方向：MQL5 → Mine Script）

**状态：编译 `0 errors / 0 warnings`；已部署到终端 `MQL5/Indicators` 且 mq5/ex5 双侧哈希一致。语义未上机验证（尚未挂图）。**
本文档的目的就是明确区分「有源码/文档背书」与「需在终端上实测」的部分。

---

## 1. 逐条对照（Pine 行号 → MQL5 落点）

| 功能 | Pine 行号 | MQL5 | 等价性 |
|---|---|---|---|
| HTF 蜡烛构造 | 1095-1174（图上 bar 聚合 + `time(HTF)` 边界，仅最后 1000 根 bar）| `CopyHtf()` + `DrawHtf()`（直接 `CopyRates(HTF)`）| **近似**（见 §2-1）|
| HTF 起始竖线 | 1137-1144 | `DrawHtfStarts()`（`OBJ_VLINE`）| 等价（**必须**换实现，见 §2-2）|
| HTF 名称/倒计时标签 | 920-938 | `DrawHtf()` 内两个 `OBJ_TEXT` | 近似（MT5 的 `OBJ_TEXT` 不支持换行 → 拆成两个对象）|
| HTF 蜡烛回收（只留 N 根）| 1141-1144 / 1169-1173 | `DrawHtf()` 按固定集合重画 + `DrawHtfStarts()` 的 key 清理 | 等价 |
| 对数中点 `calculateLogMidpoint` | 958-976 | `LogMidpoint()` | 等价 |
| T-Spot 分支 1（普通看跌）| 1205-1211 | `ProcessTspot()` variant 1 | 等价 |
| T-Spot 分支 2（普通看涨）| 1274-1280 | variant 2 | 等价 |
| T-Spot 分支 3（扩张看跌）| 1331-1333 | variant 3 | 等价 |
| T-Spot 分支 4（扩张看涨）| 1377-1380 | variant 4 | 等价 |
| T-Spot 分支 5（顺势中点看涨）| 1424-1426 | variant 5 | 等价 |
| T-Spot 分支 6（顺势中点看跌）| 1459-1461 | variant 6 | 等价 |
| 六分支互斥（每根 HTF 一根）| 1193-1199 `tspot_created` | `ProcessTspot()` 的 `dir == 0` 门控 | 等价 |
| Zone（box + midline + closeline）| 1212-1222 | `DrawTspot()` | 等价（填充口径见 §2-7）|
| Silver 判定 | 1225 / 1295 / 1341 / 1388 / 1440 / 1475 | `SilverSession()` + variant 内 | **近似**（时区近似，见 §2-10）|
| 扫破位水平短线 | 1207 / 1276 | `OBJ_TREND`（同 key 名 `SW_`）| 等价 |
| 最新 T-Spot 右端跟随 | 1095-1102 | `ExtendLatestTspot()` | 等价 |
| T-Spot 触碰 | 1629-1652 | `UpdateTouch()` | 等价 |
| pivot（三路 + 合成）| 1596-1613 | `UpdatePivots()` / `PivotHighOf()` / `PivotLowOf()` | **近似**（等号口径，见 §3-4）|
| T-Spot Sweep 确认 | 1660-1737 | `CheckSweepConfirm()` | 等价（+同 bar 去重，见 §2-6）|
| CISD 线 + 目标投影 | 602-700 | `DetectCisd()` | 等价 |
| C2 / C3 / C4 标签 | 1245-1264 / 1308-1321 / 1354-1367 / 1401-1414 | `ProcessTspot()` 内 | 等价（标签 ATR 偏移口径见 §4）|
| 逆向 T-Spot 隐藏 | 1740-1779 | `HideAgainstTspots()` | 等价（改色实现）|
| 逆向 T-Spot 删除 | 1782-1868 | — | **未移植**（§2-8）|
| 仓位建议 | 548-600 | `CalcLots()` / `RiskMoney()` / `FmtLots()` | **近似**（MT5 原生 tickValue 口径，见 §2-9）|
| 信息表 | 1940-2011 | `UpdatePanel()`（4 行角标）| 近似（见 §2-3）|
| 告警 `CAL.customAlert` | 1236…1724（8 处）| `FireAlert()`（`Alert()` + `SendNotification()`）| 近似（无自定义 JSON 模板）|
| HTF 偏置 | 787-830 | `HtfBias()` | 等价 |
| ATR | `ta.atr(200)` | `AtrRma(200)` | 近似（种子口径，见 §2-11）|

未移植（**Pine 源里也没有**，故不属于本次缺口）：SMT / PSP / Auto Bias 1-2 / Dealing Range / Previous EQ / L-H lines /
History / C2-C3-C4 显隐开关。这些只存在于 TTrades 的闭源指标条目与博文里（见 rules-report §4/§5/§8/§9）。

---

## 2. 与原 Pine 的行为差异（平台差异，不是 bug）

1. **HTF 蜡烛的数据源**：Pine 用"图上 bar 聚合"（并因此受 1000 根 bar 窗口限制 —— 大 HTF 在小周期图上画不出来）；
   MT5 直接 `CopyRates(HTF)`。**结果更准**，但两边的 HTF 边界口径从此不同源：比对时要按 HTF bar 对齐，不要按图 bar 对齐。
2. **HTF 起始竖线必须换实现**：Pine 用 `line.new(y1=0, y2=1, extend=extend.both)`。那个 `y=0` 锚点在任何
   "把绘图对象算进价格自动缩放"的渲染器上会把纵轴拉到 0（已在克隆平台实测复现）。MT5 用 `OBJ_VLINE`，天然不占价格刻度。
3. **信息表 → 4 行角标**：MT5 没有 `table` 对象的文字排版能力，`OBJ_LABEL` 也不支持换行；HTF 名称与倒计时因此拆成两个对象。
4. **HTF 组数**：Pine 源里 `settings.max_sets := 1` 硬编码、`htf2..6.show := false` 硬编码 —— 多 HTF 组在源里就是死代码。
   本实现只做单组（`InpHtfMaxDisplay` 根蜡烛），不移植那 5 段死代码。
5. **只画"当前及之后"的 T-Spot**：Pine 的历史遍历会把历史 T-Spot 也留在图上；MT5 在初始化时判定当前一根，
   之后每根新 HTF 蜡烛再判一次。**历史 T-Spot 不会补画**。
6. **同一根图 bar 不重复告警**：Pine 的触碰/确认每根 bar 都可能重新触发；本实现加了 `g_lastSweepT` 去重。
7. **T-Spot 填充强度是"相对底色"的量**：Pine 用 `color.new(c, 90)`（≈10% 不透明）；MT5 无 alpha，
   改按仓库 v1.49-s14 的约定 `fill = 底色 + (轮廓色 − 底色) × pct/100`，默认 **30%**。两种底色下语义一致。
8. **"逆向 T-Spot 删除"未移植**（Pine 1782-1868 的三数组锁步删除）。只保留隐藏（改色）。
9. **仓位公式换成 MT5 原生**：Pine 按 `syminfo.type` 分支（forex/futures/crypto…）与期货合约乘数表手算；
   MT5 用 `tickValue / tickSize`（取不到就显示 `n/a`，不猜）。
10. **Silver 的时区**：Pine 用 `hour(time, "America/New_York")`（平台时区库，含 DST）；
    MT5 无时区库 → 用"服务器时间 − (TimeTradeServer−TimeGMT) + 美东 DST 规则"近似。**DST 边界日可能差 1 小时**。
11. **ATR 种子**：Wilder 的首值本该是前 N 根 TR 的均值；本实现用最旧一根 TR 播种（Pine 的 `ta.atr` 由平台实现）。
    影响只在前 200 根 bar，之后收敛。
12. **`g_gap / InpHtfGapBars`（组间距）在多组模式下才有意义** —— 本实现是单组，故该输入当前**不生效**（保留为多组扩展位）。
    ⚠️ 这属于"输入项与行为不一致"的仓库禁用形态：已在 README 表格里写明它是扩展位、当前不生效。

---

## 3. 必须在终端上实测的点（按风险从高到低）

| # | 风险点 | 现象判据 | 若不对怎么改 |
|---|---|---|---|
| 1 | **六个分支的命中分布** | `InpDebugShow=true` 时看 `TTFM_TSPOT … variant=N`。若只有 1/2 命中、3-6 从不命中，说明 HTF 索引映射错了 | 核 `g_ho[1]/[2]/[3]` = last/prev/prevprev 的映射 |
| 2 | **HTF 索引映射** | 用一段已知行情：看 T-Spot 覆盖的是"刚收盘那根 HTF"还是错位一根 | 改 `ProcessTspot()` 的 `l*/p*/q*` 索引 |
| 3 | **未来时间对象是否可见** | HTF 蜡烛画在 `time[0] + offset×P` 的未来时刻，需要图表右侧有空白（Chart Shift 打开、右移足够）| 调大 `InpHtfOffsetBars` 或在图表上右移 |
| 4 | **pivot 的等号口径** | 与 TradingView 同段比对 C2/C3 与扫破确认次数 | Pine 的 `ta.pivothigh` 对"相等"的处理未在一手源确认；本实现用**双侧严格** |
| 5 | **Silver 时段** | 换算出 T-Spot 生成时的图 bar 时刻是否落在 16:00-19:59（服务器时）或 12:00-15:59 且 NY≥13 | 改 `SilverSession()`；DST 边界日留意 |
| 6 | **告警频率** | 真实挂图 30 分钟，看 `Alert()` 是否只在扫破确认时出现 | 同上（同 bar 去重已加） |
| 7 | **面板倒计时** | 与 HTF 边界对齐（换 HTF bar 时归零）| 核 `RemainingText()` 的 `g_ht[0] + PeriodSeconds(g_htf)` |
| 8 | **投影水平的解析** | `InpProjLevels` 用逗号分隔，含负数与小数（`-2.5`）| `StringToDouble` 逐段解析；异常段跳过 |

### 与 TradingView 的逐根比对方法
同一品种、同一周期、同一段历史：切到 TradingView 挂 Pine 版 → 截图 → 在 MT5 上切到同一时段。
**对齐基准是 HTF bar 的开盘时间**（两边 HTF 数据源不同，按图 bar 对齐会错位）。

---

## 4. 参数默认值对照

| Pine 输入 | 默认 | MQL5 输入 | 默认 |
|---|---|---|---|
| `htf_mode` | `Auto` | `InpHtfMode` | `HTF_AUTO` |
| `custom_htf` | `1W` | `InpHtfCustom` | `PERIOD_W1` |
| `tspot_bias` | `None` | `InpTspotBias` | `BIAS_NONE` |
| `Show HTF` / `Max Display` | `true` / `4` | `InpShowHtf` / `InpHtfMaxDisplay` | `true` / `4` |
| `padding from current candles` | `20` | `InpHtfOffsetBars` | `20` |
| `space between candles` | `1` | `InpHtfBufferBars` | `1` |
| `Candle Width` | `1`（×2 后=2）| `InpHtfBodyBars` | `2` |
| `space between Higher Timeframes` | `5` | `InpHtfGapBars` | `7`（Pine 值 ×…… **自定**：单组模式下不生效）|
| 实体/边框/影线颜色 | `#8ABF91` / `#E08C89` | `InpBull*` / `InpBear*` | 同 |
| `Show T-Spot` / `Only Latest` / `Extend` | `true`×3 | `InpShowTspot` / `InpShowOnlyLatest` / `InpExtendLatest` | 同 |
| `Show Chart Sweeps` | `true` | `InpShowChartSweeps` | `true` |
| `tspot_transparency` | `90` | `InpBodyFillPercent` | `30`（**量纲不同**，见 §2-7）|
| `tspot_line_style` | `dotted` | `InpTspotLineStyle` | `TS_DOTTED` |
| `show_tspot_close_line` | `true` | `InpShowCloseLine` | `true` |
| `show_silver_tspot` | `true` | `InpShowSilver` | `true` |
| `show_ttfm_labels` | `true` | `InpShowTtfmLabels` | `true` |
| `hide_against_tspots` | `true` | `InpHideAgainst` | `true` |
| `show_tspot_sweeps` / `show_confirmation_lines` / `show_confirmation_labels` | `true`×3 | `InpShowSweeps` / `InpShowConfLines` / `InpShowConfLabels` | 同 |
| `usebody_for_confirmation` | `false` | `InpUseBodyPivots` | `false` |
| `show_cisd` / `cisd_width` | `true` / `2` | `InpShowCisd` / `InpCisdWidth` | 同 |
| `show_projections` / `projection_levels` / `extend_latest_projections` | `true` / 同 / `true` | `InpShowProj` / `InpProjLevels` / `InpExtendProj` | 同 |
| `showPositionSize` / `accountBalance` / `riskType` / `riskAmount` | `true` / `10000` / `Percentage` / `1` | `InpShowPosSize` / `InpAccountBalance` / `InpRiskType` / `InpRiskAmount` | 同 |
| `Show Info Table` / `Table Position` | `true` / `Top Right` | `InpShowPanel` / `InpPanelCorner` | `true` / `CORNER_RIGHT_UPPER` |
| （Pine 无）| — | `InpAlertPopup` / `InpAlertPush` / `InpDebugShow` | `true` / `false` / `false` |

---

## 5. 执行流程（与 Pine 的对照）

```
每次 OnCalculate：
 ├─ ArraySetAsSeries(time/open/high/low/close, true)   ← 硬约定 1
 ├─ 隐藏 buffer 全填 EMPTY_VALUE                        ← 绝不能留 0（会把纵轴拉到 0）
 ├─ CopyChart(600) / CopyHtf(N+4)                      ← 本地副本，后续全在数组上算
 ├─ 首帧：清对象 + 复位全部运行态
 ├─ 新 HTF bar？（g_ht[0] != g_lastHtfT0）
 │    └─ ProcessTspot()：六分支 → Zone + Silver + C2/C3/C4 + CISD/投影 → 回收
 ├─ 新图 bar？（g_t[0] != g_lastChartT0）
 │    ├─ UpdatePivots()         ← 三路 pivot（open/close/high 与 low 对称）
 │    ├─ DrawHtf() / DrawHtfStarts() / HideAgainstTspots()
 ├─ 每帧：UpdateTouch() → CheckSweepConfirm() → ExtendLatestTspot()
 └─ 面板：新 bar 或距上次 ≥1s 才刷（倒计时）
```

---

## 6. 验收与已知限制

**日志（唯一无条件打印的 INIT 行）**
```
ttrades/TTFM 已初始化 | build=v1.00-s1 | chart=M15 htf=H4 | bubble=Auto|bias=None | htfCandle=on n=4 off=20 body=2 buf=1 gap=7 …
```
`InpDebugShow=true` 时：
- 每根新 bar 一行 `TTFM_RENDER bar=… newHtf=… htf=… nHtfBars=… tspots=… tsDir=… touched=… bias=…`
- 每次新建 T-Spot 一行 `TTFM_TSPOT key=… dir=… variant=1..6 expansive=… silver=… mid=… lastC=…`

**对象命名**（全部 `TTFM_` 前缀，`key` = 该 T-Spot/蜡烛所在 HTF 蜡烛的开盘时间戳）

| 后缀 | 类型 | 含义 |
|---|---|---|
| `HB_/HU_/HD_` | rect/trend×2 | HTF 实体 / 上影 / 下影 |
| `HL_/HT_` | text | HTF 名称 / 剩余时间 |
| `VL_` | vline | HTF 起始竖线 |
| `TS_/TSM_/TSC_` | rect/trend×2 | T-Spot 区 / 中线 / 收盘线 |
| `SW_` | trend | 扫破位水平线 |
| `C2_/C3_` | text | C2 标签 / C3（扩张分支写作 C4）|
| `SV_` | text | Silver T-Spot 标签 |
| `CISD_/PJ_/PL_` | trend/trend×2/text | CISD 线 / 投影线 / 投影标签 |
| `CF/CFL` | trend/text | 扫破确认线 / 标签（全局唯一，只留最新）|
| `PN_0..3` | label | 信息面板 |

**已知限制**
1. 未移植：逆向 T-Spot 的**删除**逻辑、多 HTF 组（源里就是死代码）、`InpHtfGapBars`（单组下不生效）。
2. 历史 T-Spot 不补画（§2-5）；切周期/切品种会清空重来（`OnDeinit` 清 `TTFM_` 前缀对象）。
3. `0 errors / 0 warnings` 不代表语义正确 —— 验收必须走 §3 的终端实测。

## 7. 变更台账（BUILD_TAG）

| 版本 | 日期 | mq5 md5(前12) | ex5 md5(前12) | 编译 | 变更 |
|---|---|---|---|---|---|
| v1.00-s1 | 2026-10-13 | D63FBF43C9C4 | 0DA26F7E1AF1 | 0 errors / 0 warnings | 首次移植落地 |
| **v1.01-s1** | 2026-10-13 | **E0D5CBA49B5C** | **1B4F90E6FC7E** | 0 errors / 0 warnings | 投影锚点改 TTrades 口径：`破位价 ± 序列幅度×lv` → `操纵腿末端 ± lv×腿长`（`legEnd/legLen`，`legLen<=0` 提前退出）；与 `ttrades.mine` / `pinescript` 同步 |
| **v1.02-s1** | 2026-10-14 | **613C05FBC6E4** | **6F74A7B1CD28** | 0 errors / 0 warnings | ① 面板默认位置改**左上角**（右上角常被其他 EA 的按钮/面板占住）；② `UpsertPanelLine` **显式设 `OBJPROP_ANCHOR`**（右角→`ANCHOR_RIGHT_UPPER`、左角→`ANCHOR_LEFT_UPPER`）—— 原来没设锚点，右角会把 4 行全推到图外；③ 新增 `AlertOnce(key)` **按事件去重**（Silver `SV_<key>`、扫破 `SW_B_<key>` / `SW_S_<key>`）：修「告警每 tick 连发」—— 根因是 `CheckSweepConfirm()` 每 tick 都跑 + 触发条件是整根 bar 的固定属性，且 `g_lastSweepT` **只赋值、从未读取**（全文件 0 处读取）|
| **v1.03-s1** | 2026-10-14 | **B07638F3EBD8** | **4A2800FCCFD0** | 0 errors / 0 warnings | 面板默认位置改**左下角**（左上/右上都被其他 EA 的面板/按钮占用）；`UpsertPanelLine` 改为**四角通用**：下角时 Y 从底边往上量，行序取反（`3-row`）使 PN_0 仍排在最上；锚点按角选 `ANCHOR_{LEFT,RIGHT}_{UPPER,LOWER}` |

校验方式（每次部署都做）：
1. 编译日志 **`Result: 0 errors`** 行（不看 MetaEditor 退出码）；
2. 部署后 **mq5 双侧哈希一致**（repo `Indictor/ttrades.mq5` ≡ 终端 `MQL5/Indicators/ttrades.mq5`）；
3. ex5 哈希与上一版**必须不同**；
4. **不要**用"在 ex5 里搜 BUILD_TAG 字符串"当判据 —— .ex5 不保留明文串（连 `ttrades`/`TTFM_` 都搜不到），无效方法；运行时确认看 MT5「专家」日志里的 `build=` 值。
