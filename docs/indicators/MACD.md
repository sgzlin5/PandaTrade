# MACD

> 源文件：`Indictor/MACD.mq5` ｜ 详细口径与参数（自 README 拆分） ｜ [返回 README](../../README.md)


> `Indictor/MACD.mq5`

MACD 指标，包含能量强弱颜色区分。在**独立子窗口**中显示。

#### 效果预览

| 元素 | 颜色 | 说明 |
|---|---|---|
| MACD 线 | ![#58a6ff](https://placehold.co/12x12/58a6ff/58a6ff.png) `#58a6ff` 蓝色 | 快线 EMA − 慢线 EMA |
| 信号线 | ![#f0883e](https://placehold.co/12x12/f0883e/f0883e.png) `#f0883e` 橙色 | MACD 的 EMA |
| 能量柱（涨强） | ![#26a641](https://placehold.co/12x12/26a641/26a641.png) `#26a641` 鲜绿 | 正值且能量增强 |
| 能量柱（跌强） | ![#f85149](https://placehold.co/12x12/f85149/f85149.png) `#f85149` 鲜红 | 负值且能量增强 |
| 能量柱（涨弱） | ![#1a5c2c](https://placehold.co/12x12/1a5c2c/1a5c2c.png) `#1a5c2c` 暗绿 | 正值但能量减弱 |
| 能量柱（跌弱） | ![#833130](https://placehold.co/12x12/833130/833130.png) `#833130` 暗红 | 负值但能量减弱 |

> **能量减弱判断**：当前柱的绝对值 < 前一柱的绝对值时，颜色切换为弱色（原色与暗背景 `#0d1117` 各 50% 混合）。

#### 输入参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `InpFastEMA` | `12` | 快线 EMA 周期 |
| `InpSlowEMA` | `26` | 慢线 EMA 周期 |
| `InpSignalEMA` | `9` | 信号线 EMA 周期 |
| `InpPrice` | `PRICE_CLOSE` | 价格类型（`ENUM_APPLIED_PRICE`） |

#### 技术细节

- **窗口**：独立子窗口（`indicator_separate_window`）
- **缓冲区**：4 个（MACD 线、信号线、柱值、颜色索引）
- **绘图序列**：3 个（MACD 线 `DRAW_LINE`、信号线 `DRAW_LINE`、能量柱 `DRAW_COLOR_HISTOGRAM`）
- **颜色索引**：`DRAW_COLOR_HISTOGRAM` + 4 色索引，单一绘图通道实现强弱配色（0=涨强 / 1=跌强 / 2=涨弱 / 3=跌弱）
- **EMA 计算**：通过 `iMA` 句柄复制快/慢线；Signal 以前 `InpSignalEMA` 根 MACD 的简单均值作为 EMA 种子
- **小数位**：`INDICATOR_DIGITS = _Digits + 1`
