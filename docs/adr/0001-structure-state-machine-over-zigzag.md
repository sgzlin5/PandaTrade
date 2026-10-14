# 结构指标用独立状态机，不复用现有 ZigZag

新结构指标（TradFi_Structure）不复用 `ZigZag.mq5` 的摆动点检测，而是实现独立的"冲动移动 → 有效回撤(MSS) → BOS"状态机。原因：用户定义的 MSS/BOS 事件以"极值蜡烛"为基准（打破极值蜡烛的高/低点），而 ZigZag 用 Depth/Deviation/Backstep 三参数找摆动点——两套基准会产生错位（极值蜡烛已确认反转但 ZigZag 尚未确认），导致标注与结构线不一致。经盘问确认（方案 B），摆动点完全由状态机产生，ZigZag 保持独立、两者可叠加使用但互不依赖。
