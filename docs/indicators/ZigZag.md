# ZigZag

> 源文件：`Indictor/ZigZag.mq5` ｜ 详细口径与参数（自 README 拆分） ｜ [返回 README](../../README.md)


> `Indictor/ZigZag.mq5`

ZigZag 折线指标，基于 Depth / Deviation / Backstep 三参数识别价格转折点并连线。在**主图表窗口**中显示。

#### 效果预览

| 元素 | 颜色 | 说明 |
|---|---|---|
| ZigZag 折线 | ![#39c5cf](https://placehold.co/12x12/39c5cf/39c5cf.png) `#39c5cf` 青色 | 分段连线（`DRAW_SECTION`），宽 2 |

#### 输入参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `InpDepth` | `12` | 两侧搜索窗口（局部极值检测范围） |
| `InpDeviation` | `5` | 转折确认的最小点数偏差 |
| `InpBackstep` | `3` | 相邻转折点间的最少 bar 间隔 |

#### 技术细节

- **窗口**：主图表窗口（`indicator_chart_window`）
- **缓冲区**：3 个（主折线 `INDICATOR_DATA` + 2 个隐藏极值标记 `INDICATOR_CALCULATIONS`）
- **绘图类型**：`DRAW_SECTION`，空值使用 `EMPTY_VALUE`（≈1.79e308），避免与价格 0.0 冲突；仅在确认的转折点写入真实价格，`DRAW_SECTION` 自动跳过空值连接相邻有效点
- **两阶段算法**：
  1. **Phase 1 — 对称窗口极值检测**：对每根 bar `i`，检查 `high[i]` 是否为 `[i-Depth, i+Depth]` 中心窗口的最大值、`low[i]` 是否为最小值，标记到辅助缓冲区
  2. **Phase 2 — 状态机确认转折点**：三态状态机（0=初始 / -1=等高确认 / +1=等低确认），同时满足方向反转、Deviation 偏差、Backstep 间隔才确认转折并写入主缓冲区
- **计算策略**：每次 tick 全量重算，无状态残留
- **参数校验**：`OnInit` 中对三参数做合法性检查，非法参数返回 `INIT_PARAMETERS_INCORRECT`
