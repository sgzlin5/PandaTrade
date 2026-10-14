# PandaTrade

MT5 自定义指标与 EA 脚本库，保持统一的视觉风格与交易逻辑。

---

## 目录结构

```
sturdy-giggle/
├── Indictor/          # 自定义指标（.mq5）
│   ├── MACD.mq5
│   ├── ZigZag.mq5
│   ├── Structure.mq5
│   ├── PositionTool.mq5
│   ├── SMC_Toolbox.mq5
│   └── ttrades.mq5             # TTFM°（TTrades Fractal Model）主图叠加
├── EA/                # 智能交易系统（.mq5）
│   └── PositionTrader.mq5
├── ttrades/           # TTFM° 的多平台源文件
│   ├── ttrades.pine            # TradingView 原版（Pine v6，已修正）
│   └── ttrades.mine            # Mine Script（TradingVue）移植版
├── TradingVue/        # Mine Script 移植笔记
├── docs/
│   ├── adr/           # 架构决策记录
│   ├── indicators/    # 各指标详细口径与参数（自 README 拆分）
│   ├── ea/            # 各 EA 详细说明（自 README 拆分）
│   ├── plans/         # 实施计划与验收记录
│   ├── research/      # 一手资料调研（含 TTrades 配图、SMC 术语核实）
│   ├── reviews/       # 代码审查
│   └── baselines/     # 事件基线（逐版本归档，可 diff）
└── README.md
```

---

## 安装方法

1. 打开 MetaTrader 5，点击菜单 **文件 → 打开数据文件夹**
2. 将对应文件复制到 MQL5 目录下：
   - 指标：将 `Indictor/` 下的 `.mq5` 文件复制到 `MQL5/Indicators/`
   - EA：将 `EA/` 下的 `.mq5` 文件复制到 `MQL5/Experts/`
3. 在 MetaEditor（F4）中打开对应文件，按 **F7** 编译
4. 回到 MT5：
   - 指标：在「导航」面板 → 指标 → 自定义 中找到对应指标，拖拽到图表
   - EA：在「导航」面板 → 智能交易系统 中找到对应 EA，拖拽到图表（需开启「允许算法交易」）

> **注意**：MT5 目录下的 `.mq5` 与仓库里的源文件是**两份**。若在 MetaEditor 里打开的是 MT5 目录那份并编译，会覆盖部署产物。仓库的 `Indictor/mq5debug.ps1` 会把两份一起同步并校验哈希，避免这种静默覆盖。

---


## 指标列表

> 每个指标的**详细口径与参数**在 `docs/indicators/`（内容与原先本文件里的章节逐字一致，只是搬家）。
> ⚠️ 标记的含义只有一处权威来源：全文里的 ⚠️ 表示"与 TTrades 一手口径的差异 / 自定读法 / 已知边界"，引用前必读。

| 指标 | 源文件 | 一句话 | 详细口径 |
|---|---|---|---|
| `MACD` | `Indictor/MACD.mq5` | MACD（能量强弱分色），独立副图 | [docs/indicators/MACD.md](docs/indicators/MACD.md) |
| `ZigZag` | `Indictor/ZigZag.mq5` | ZigZag 折线：Depth / Deviation / Backstep 三参数识别转折点，主图 | [docs/indicators/ZigZag.md](docs/indicators/ZigZag.md) |
| `Structure` | `Indictor/Structure.mq5` | 市场结构：结构折线 + 四类事件标注，口径对齐 TTrades（**本仓库最大的一份**）| [docs/indicators/Structure.md](docs/indicators/Structure.md) |
| `SMC_Toolbox` | `Indictor/SMC_Toolbox.mq5` | SMC 工具箱：模块化、逐项开关，主图，对象前缀 `SMCToolbox_` | [docs/indicators/SMC_Toolbox.md](docs/indicators/SMC_Toolbox.md) |
| `ttrades` | `Indictor/ttrades.mq5` | TTFM°（TTrades Fractal Model）主图叠加，移植自社区 Pine v6 脚本；另有 `.pine` / `.mine` 两平台版本 | [docs/indicators/ttrades.md](docs/indicators/ttrades.md) |
| `PositionTool` | `Indictor/PositionTool.mq5` | 对齐 TV 的 Long/Short Position：入场/止损/止盈三线 + 盈亏、RR、建议手数 | [docs/indicators/PositionTool.md](docs/indicators/PositionTool.md) |

## EA 列表

| EA | 源文件 | 一句话 | 详细说明 |
|---|---|---|---|
| `PositionTrader` | `EA/PositionTrader.mq5` | 把 PositionTool 画出的仓位真正挂成挂单（Buy/Sell Limit 或 Stop）| [docs/ea/PositionTrader.md](docs/ea/PositionTrader.md) |

---

## 开发规范

- 所有文件使用 **UTF-8** 编码
- 指标文件放入 `Indictor/` 目录，EA 文件放入 `EA/` 目录
- 颜色规范遵循统一色板：

  | 用途 | Hex | MQL5 |
  |---|---|---|
  | 主蓝 | `#58a6ff` | `C'88,166,255'` |
  | 信号橙 | `#f0883e` | `C'240,136,62'` |
  | 涨绿 | `#26a641` | `C'38,166,65'` |
  | 跌红 | `#f85149` | `C'248,81,73'` |
  | 深背景 | `#0d1117` | `C'13,17,23'` |
  | ZigZag 青 | `#39c5cf` | `C'57,197,207'` |

- **编译与部署**：`Indictor/mq5debug.ps1` 会编译仓库源、**同步 `.mq5` 与 `.ex5` 到 MT5**、校验两边哈希，并打印专家日志尾部；`-Verify` 只校验不编译。
  **EA 走同一个脚本，加 `-Sub Experts`**（默认 `-Sub Indicators`）：
  `mq5debug.ps1 -Name PositionTrader -Sub Experts`。
  脚本**必须保持纯 ASCII**（Windows PowerShell 5.1 把无 BOM 的 `.ps1` 按 ANSI 读，中文会破坏解析）。
- **状态自检**：`Indictor/audit_state.ps1` 是针对一类**真实踩过的 bug**的静态绊线 ——
  「后验扫描漏自复位导致跨帧累加」（见 `docs/plans/…-TTrades-alignment.md` §35.2 / §36）。
  - **A**：`StructureResult` 每个计数都有复位；
  - **B**：复位所在函数**确实驱动**了自增（只由集中复位块覆盖的标 **OK\***，属较弱保障）；
  - **C**：一张逐帧全局清单都有非声明式赋值；
  - **D**：`RenderScene` 里被读取但**不在 `needDraw` 指纹**内的全局（硬约定 3）。
    每个例外都必须在脚本内 `justified` 表里**写明理由**；**没有理由的候选直接判 FAIL**
    （早期版本把它做成"信息性"输出，那等于给了一张会被无视的清单）。
    带"空洞绿灯"防护 —— 收集器几乎没收到东西时判 FAIL 而非 PASS。
  **四项都是 pass-fail**（D 早期是"信息性"，现已升级为判 FAIL —— 一张会被无视的清单没有价值）。
  当前 **PASS**（78 个读取 / 73 个在指纹内，5 条例外均有书面理由）。
  ⚠️ 它**不**检查"赋值在每条路径上是否可达"、**不**检查值的正确性、
  也**看不到通过引用出参写入的赋值** —— 它是绊线，不是验证器。改动判定层后请先跑它。
  > **验证检查器本身的标准手法**（只跑一次"通过"不算验证过）：
  > *故意破坏被检查的属性 → 确认检查器会喊 → 还原 → 确认源码哈希回到原值。*
  > 已对 **A/B 段**（删掉 `nClosure` 复位 → 报 FAIL）与 **D 段**（从 `justified` 表删一项 → 报 FAIL）各做过一次。
  > **C 段尚未做** —— 如实标注。
- **验证纪律**：任何改动都先导出事件 CSV 再逐行 diff；MT5 的专家日志写入**有延迟**，缺失预期行时不要立即下结论。
- **改行为就升 `BUILD_TAG`**：日志按它区分构建。不升，`build=` 这个自证锚点就废了 ——
  本仓库已经踩过：EA 跨了三次功能改动都没升版本，结果日志里**分不出用户挂的是哪一版**。
- **验收 runbook**：`docs/sop/2026-09-24-Structure-acceptance-runbook.md` ——
  一页说清"怎么挂 → 图上先看什么 → 发哪两行日志 → 每个字段各证明什么 → A/B 对照怎么做 →
  哪些是**已知边界不必再报**"。阶段 16–19 的运行时验收照它走即可。

---

## License

MIT
