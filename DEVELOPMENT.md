# Measurement Device Manager — 开发指南

本文档面向 AI agent 和开发者，说明项目架构、命名约定、编码规范以及如何扩展系统。

## 项目概览

Measurement Device Manager 是一套 MATLAB 仪器控制与数据采集系统，采用三层架构：

```
┌──────────────────────────────────────────────────────────────────┐
│ UI 层 (MeasurementManagerApp)                                    │
│   程序化 App Designer │ 多仪器 tiledlayout │ Lamp 状态灯          │
│   仪器表格 │ 参数面板 │ 4 按钮分离 │ 合并保存 │ ELOG+Note │ 日志  │
├──────────────────────────────────────────────────────────────────┤
│ 管理层 (Station + ParameterDef + InstrumentRegistry)             │
│   仪器注册与生命周期 │ 采集队列调度(优先级) │ 状态快照 │ 参数元数据 │
├──────────────────────────────────────────────────────────────────┤
│ 导出层 (DataExporter)                                            │
│   MAT/CSV/PNG 导出 │ ELOG HTTP 上传 │ 元数据表 │ 绘图辅助        │
├──────────────────────────────────────────────────────────────────┤
│ 驱动层 (VisaInstrument 子类)                                      │
│   ESA │ OSA │ VNA │ Scope                                        │
└──────────────────────────────────────────────────────────────────┘
```

**技术栈**：MATLAB (uifigure + uigridlayout), Instrument Control Toolbox, NI-VISA, visadev API

## 目录结构

```
matlab_unified/
├── MeasurementManagerApp.m          # 主 App 类（程序化 App Designer，~1850 行）
├── DEVELOPMENT.md                   # 本文档
├── README.md                        # 用户文档
├── app_config.mat                   # 持久化配置（文件夹、ELOG 设置）
├── examples/                        # 各仪器独立示例脚本
│   ├── example_esa_keysight_n9020a.m
│   ├── example_osa_ceyear_6362d.m
│   ├── example_vna_keysight_e5080b.m
│   ├── example_scope_keysight_mso9404a.m
│   ├── example_scope_rigol_instant.m
│   ├── example_scope_rigol_timed.m
│   └── setup_example_environment.m
├── output/                          # 默认数据输出目录
└── +labdevices/                     # MATLAB 包命名空间
    └── +core/
        ├── VisaInstrument.m         # 仪器基类 < handle（SCPI 通信基础设施）
        ├── InstrumentRegistry.m     # 静态类：仪器注册表（IP、类型、VISA 资源名）
        ├── DataExporter.m           # 静态类：数据导出 + ELOG 上传
        ├── Station.m                # 仪器容器 + 采集调度中心 + 工厂方法
        ├── ParameterDef.m           # 仪器参数元数据定义（含采集参数）
        └── resetVisaConnections.m   # 清理残留 VISA 连接
    ├── +esa/
    │   └── KeysightN9020A.m         # ESA: configure + acquire(traceNumbers)
    ├── +osa/
    │   └── CeyearOSA6362D.m         # OSA: configure + acquire(traceNames) 双单元
    ├── +vna/
    │   └── KeysightE5080B.m         # VNA: configure + acquire(channels)
    └── +scope/
        ├── KeysightMSO9404A.m       # Scope: configure + acquire(channels)
        └── RigolDHO4204.m           # Scope: configure + acquire(channels) + 深存储
```

## UI 布局架构

```
Figure "Measurement Device Manager" (居中，85% 屏幕)
│
├── MainGrid [3×3]
│   RowHeight: {'1x', '1x', 30}         ← Row 3 固定 30px 给状态栏
│   ColumnWidth: {'1.1x', '1.5x', '0.4x'}  ← 左 37% / 中 50% / 右 13%
│
│   ├── (1,1): leftWrapper [2×1]        ← 仪器 + 参数上下分栏，无 TabGroup
│   │   ├── Instruments Panel (55%): [表格 + Lamp] + [Connect All | Disconnect All | Acquire All]
│   │   └── Parameters Panel (45%): 动态参数控件 + [Apply | Acquire | Apply+Acquire | Reset]
│   │
│   ├── (1,2): "Live Data View" Panel
│   │   ├── LayoutDropdown + tiledlayout('flow')  ← 多仪器动态子图，布局可切换
│   │   └── AcquisitionTable (Device/Type/Timestamp/Traces/Status)
│   │
│   ├── (1,3): Data Table + ELOG Panel (Collapsible)
│   │
│   ├── (2,1): Storage Panel + [Save All | Save Session | Save Selected | Clear]
│   ├── (2,2): Status Log (uitextarea)
│   ├── (2,3): ELOG Content (collapsible with toggle button)
│   │
│   └── (3,1:3): StatusLabel            ← 固定在 Grid 底部，不会漂移
```

### 设计要点

- **无 TabGroup**：仪器列表和参数面板上下排列在同一面板内，一键切换仪器时参数面板即时显示（通过 show/hide 缓存而非重建）
- **ParamControlCache**：每种仪器类型的参数控件仅创建一次，切换时通过 `Visible` 属性 show/hide，避免反复 delete+rebuild 的闪烁和性能开销
- **设计令牌系统**：所有颜色/字体/间距通过 `COLOR_*`、`FONT_*`、`SPACE_*` 常量集中管理，共 30 个令牌，替换了全文件约 250 处硬编码值
- **键盘快捷键**：Ctrl+Enter(采集) / Ctrl+S(全部保存) / Ctrl+D(Session保存) / Ctrl+C(连接所有) / Ctrl+L(清空) / Ctrl+E(ELOG上传)
- **可折叠 ELOG 面板**：通过 `ElogToggleButton` 切换显隐，默认折叠节省空间，`ElogContentGrid` 承载全部字段
- **HTML 按钮**：仪器表格内 Connect/Acquire 按钮用 HTML `<a>` 标签渲染在 uitable 单元格中，可随表同步滚动
- **Lamp 状态指示灯**：仪器表格右侧 uilamp 列，绿色=已连接，灰色=未连接，黄色=采集中。首行留空补偿表头高度
- **tiledlayout 多子图**：每个仪器 key 映射一个 tile，数据自动更新到对应 tile。用 `uipanel` 包裹 `tiledlayout` 保证兼容性
- **安全回退**：`visadev` 不可用时给出清晰提示而非崩溃
- **动态窗口**：Figure 尺寸取屏幕 85%，居中显示，适配不同分辨率

## 核心概念

### 仪器生命周期

```
创建 → 连接 → 配置 → 采集 → 保存 → 断开
  │      │      │      │      │       │
  │   connect configure acquire saveData disconnect
  │   (visadev) (SCPI)  (SCPI)  (DataExporter) (delete visadev)
```

### Station（仪器容器）

Station 是一站式仪器管理中心：
- 使用 `containers.Map` 存储 key → instrument 映射
- 提供 `getSnapshot()` 返回所有已连接仪器的状态快照（用于 ELOG 和调试）
- `acquireAll(priorityOrder, acquireParamsMap)` 按优先级顺序批量采集，支持传入每仪器采集参数
- `createInstrument(key)` 静态工厂方法集中管理仪器类型映射；未实现驱动返回 `[]` 并 warning（不抛异常）
- `defaultAcquireArgs(instrType)` 提供各仪器类型默认采集参数（OSA→TRD, Scope→[1], ESA→[1], VNA→[1]）

### ParameterDef（参数元数据）

定义每种仪器类型的参数。UI 层读取后动态创建输入控件。参数类型：
- `numeric` → NumericEditField
- `logical` → CheckBox
- `choice` → DropDown（支持多选值如 "1,2,3"）

**新增采集参数**（Phase 2）：

| 仪器 | 参数名 | 类型 | 默认值 | 说明 |
|------|--------|------|--------|------|
| OSA | `Trace` | choice | TRD | 采集 trace 槽位 (TRD/TRA/TRB/TRC) |
| Scope | `Channels` | choice | 1 | 采集通道 (1/2/3/4/组合) |
| ESA | `TraceNumbers` | choice | 1 | 采集 trace 编号 (1/2/3/组合) |
| VNA | `Channels` | choice | 1 | 采集通道 (1/2/3/4/组合) |

### 参数分流机制

所有仪器参数分为两类处理：

```
collectParameterValues() → splitAcquireParams()
  ├── configArgs → instrument.configure(name=value, ...)  ← Apply 按钮
  └── acquireArgs → buildAcquireArgs() → AcquireParamsMap  ← Acquire 按钮
```

- **configure 参数**：CenterFrequency, Span, ResolutionBandwidth 等 → 发送 SCPI 命令
- **acquire 参数**：Trace, Channels, TraceNumbers → 传递给 `acquire()` 的首参数

四个按钮行为：
| 按钮 | 颜色 | 功能 |
|------|------|------|
| Apply | Teal | 仅 configure()，存储采集参数 |
| Acquire | Green | 仅 acquire()，使用已存储参数 |
| Apply+Acquire | Blue | configure() + acquire() |
| Reset | Default | 清空参数面板 |

### 数据采集流

```
onAcquire(key)
  ├── 检查 IsBusy / isConnected
  ├── 从 AcquireParamsMap 获取参数；无则用 buildAcquireArgs(key, {}) 回退默认值
  ├── instrument.acquire(args{:})
  └── onAcquireDone(key, data)
       ├── AcquisitionStore{end+1} = {key, data}    ← key-value 对存储
       ├── AcquisitionTable 追加一行
       ├── plotAcquisitionData(key, data)            ← 多 trace 同图叠加
       ├── updateStatusBar()
       └── AutoSave → doSave(data, key)
```

### 保存按钮语义

| 按钮 | 行为 | 用途 |
|------|------|------|
| **Save All** | 保存内存中全部采集数据，每条独立文件 | 全部导出 |
| **Save Session** | 仅保存每台仪器**最新一次**采集，合并为单个 .mat | 实验归档 |
| **Save Selected** | 选中表格行后保存对应数据 | 自由选择 |
| **Clear** | 清空内存数据、表格、图表 | 新一轮测量 |

**Save Session 实现**：使用 `containers.Map` 从后向前遍历 `AcquisitionStore`，每台仪器（按 key）只取第一次遇到（即最新），合并为 struct 后用 `-struct` 存入 .mat。

### 合并保存 (Save Session)

`onSaveSession()` 从尾部遍历 AcquisitionStore，每台仪器仅取最新一条，合并为单个 struct：

```matlab
seen = containers.Map();
for i = N:-1:1
    if ~seen.isKey(key); seen(key) = true; combined.(field) = data; end
end
save(matPath, "-struct", "combined", "-v7.3");
```

### 采集队列

批量采集（Acquire All Connected）时按优先级顺序执行：OSA → ESA → VNA → Scope。同类型按注册顺序。采集过程串行执行，避免多仪器同时占用 VISA 总线。

Station.acquireAll() 对 map 中没有条目的 key 调用 `defaultAcquireArgs(type)` 获取默认参数，确保所有仪器都能正常采集。

### ELOG 上传

通过 ELOG 命令行工具上传测量记录。面板为紧凑布局（10行×4列，FontSize 11）：

1. Server : Port
2. Logbook（可编辑下拉，默认 EPIC）
3. Author（可编辑下拉，默认 Li_Yansong）
4. XOI/Design : Type（下拉，不可编辑）
5. Wafer : Chip / Field : Sample（文本字段）
6. Measurement（文本）
7. Comments（多行，含备注）
8. Attach snapshot + Auto-upload + Upload button + Status

**新增字段**（迁移自旧版 MainGui.m）：XOI/Design、Wafer、Field、Chip → 组合为样品标识 `design_wafer_field_chip_sample`；Type → 作为 `Measuretype` 属性。

**上传模式**：手动（App截图PNG + 仪器快照） / 自动（采集数据图PNG + 样品信息）

**关键细节**：ELOG body 分隔符须用字面量 `'\n'`（单引号），禁用 `sprintf('\\n')`（会生成真正换行符破坏命令行）。附件仅 PNG（`exportgraphics` 生成），保存到输出目录。

## 命名约定

| 类别 | 约定 | 示例 |
|------|------|------|
| 类名 | PascalCase | `MeasurementManagerApp`, `VisaInstrument` |
| 方法 | camelCase | `connect()`, `saveData()`, `logMessage()` |
| UI 回调 | `on` + 动作名 | `onConnect`, `onAcquireAll`, `onUploadElog` |
| 属性 | PascalCase | `ResourceName`, `InstrumentKeys` |
| 常量 | UPPER_SNAKE_CASE | `PRIORITY_ORDER` |
| 包目录 | `+` 前缀，小写 | `+labdevices`, `+core` |
| 文件名 | 与类名一致 | `Station.m` 包含 `classdef Station` |
| 错误 ID | `labdevices:ErrorType` | `labdevices:NotConnected` |

## 编码规范

1. **方法单一职责** — 每个方法不超过 30 行；超过则拆分为子方法
2. **文档注释** — 所有 public 方法必须有文档注释（H1 行 + 说明块）
3. **错误处理** — 所有 `try/catch` 必须调用 `logMessage()` 记录错误；不吞异常
4. **层间隔离** — UI 层不直接执行 VISA 操作（通过 Station 代理）；驱动层不引用 UI 类
5. **属性访问** — 默认 `SetAccess = private`，除非有明确理由需要外部修改
6. **无隐式依赖** — 所有依赖通过构造函数注入或属性明确声明
7. **分区注释** — 类文件用 `%%` 代码块分隔不同功能区
8. **防御性类型转换** — `uidropdown` Items 必须是 string 数组或 char cell；从 ParameterDef.Choices 读取时做 `string()` 转换
9. **Grid Layout 显式定位** — 所有 uigridlayout 子组件必须设置 `Layout.Row`/`Layout.Column`
10. **字体大小规范** — 使用设计令牌 `FONT_*` 常量：面板标题 18pt，Section 标题 16pt，正文/按钮/表格 14pt，辅助文本 13pt，日志/状态栏/ELOG 12pt

## 设计令牌参考

所有 UI 元素必须使用以下常量，禁止硬编码颜色/字体/间距值。

### 色彩

| 令牌 | 值 | 用途 |
|------|-----|------|
| `COLOR_PRIMARY` | `[0.145 0.388 0.922]` | 主按钮 / 选中状态 |
| `COLOR_PRIMARY_LIGHT` | `[0.859 0.918 0.996]` | 选中行背景 |
| `COLOR_ACCENT` | `[0.008 0.518 0.780]` | 信息 / 次要强调 |
| `COLOR_SUCCESS` | `[0.086 0.639 0.290]` | 成功 / 采集 / 保存 |
| `COLOR_WARNING` | `[0.918 0.345 0.047]` | 警告 / 忙状态 |
| `COLOR_DANGER` | `[0.863 0.149 0.149]` | 删除 / 断开 / 清除 |
| `COLOR_BG` | `[0.973 0.980 0.988]` | Figure 全局背景 |
| `COLOR_SURFACE` | `[1.000 1.000 1.000]` | 面板 / 卡片背景 |
| `COLOR_SURFACE_ALT` | `[0.945 0.953 0.976]` | 表格交替行 |
| `COLOR_TEXT` | `[0.059 0.090 0.165]` | 正文 / 标签 |
| `COLOR_TEXT_SECONDARY` | `[0.278 0.333 0.412]` | 辅助文字 |
| `COLOR_TEXT_MUTED` | `[0.580 0.639 0.722]` | 占位符 / 禁用 |
| `COLOR_BORDER` | `[0.886 0.910 0.941]` | 面板边框 |
| `COLOR_BORDER_LIGHT` | `[0.945 0.953 0.976]` | 极淡分隔线 |
| `COLOR_LAMP_OFF` | `[0.796 0.835 0.882]` | 未连接灯 |
| `COLOR_LAMP_ON` | `[0.133 0.773 0.369]` | 已连接灯 |
| `COLOR_LAMP_BUSY` | `[0.961 0.620 0.043]` | 采集中灯 |
| `COLOR_BUTTON_BG` | `[0.940 0.940 0.940]` | 默认按钮背景 |
| `COLOR_TEAL` | `[0.000 0.650 0.650]` | Apply 按钮 |
| `COLOR_LOG_BG` | `[0.970 0.970 0.970]` | 日志区背景 |

### 排版

| 令牌 | 大小 | 用途 |
|------|------|------|
| `FONT_XL` | 18pt | 面板标题（与正文明显区分） |
| `FONT_LG` | 16pt | Section 标题 |
| `FONT_MD` | 14pt | 正文 / 按钮 / 表格 |
| `FONT_SM` | 13pt | 辅助文本 / 下拉框 |
| `FONT_XS` | 12pt | 日志 / 状态栏 / ELOG 字段 |

### 间距

| 令牌 | 值 | 用途 |
|------|-----|------|
| `SPACE_XS` | 2px | 紧密元素间距 |
| `SPACE_SM` | 4px | 默认内边距 |
| `SPACE_MD` | 8px | 面板内边距 / 按钮间距 |
| `SPACE_LG` | 12px | Section 间距 |
| `SPACE_XL` | 16px | 大间距 |

## 如何扩展

### 添加新仪器类型

1. 在 `InstrumentRegistry.all()` 中注册新的 key/IP/资源名
2. 实现 `VisaInstrument` 子类（必须实现 `configure()` 和 `acquire()`）
3. 在 `Station.createInvestment()` 的 switch 中添加 key → class 映射
4. 在 `ParameterDef.forType()` 中添加该仪器类型的参数定义
5. 在 `getAcquireParamNames()` 中注册采集参数名

### 添加新的可配置参数

修改 `ParameterDef.make<Type>Defaults()`，在对应仪器类型的参数列表中添加新 `ParameterDef(...)` 条目。UI 自动生成控件。

### 添加新的存储格式

1. 在 `DataExporter` 中新增 `write<Format>File(data, folder, baseName)` 静态方法
2. 在 `saveAcquisition()` 的 `lowerFormats` 分支中添加对该格式的处理
3. 在 UI 的 Storage Panel 中添加对应 CheckBox

### 添加新的 UI 面板

1. 在 `MeasurementManagerApp` 中新增 `build<PanelName>(obj, parent)` 方法
2. 在 `createComponents()` 中调用该方法并指定 grid 位置
3. 添加对应的回调方法和属性

## 常见陷阱

| 陷阱 | 原因 | 解法 |
|------|------|------|
| `uidropdown` 'Items' 验证失败 | Items 必须是 string 数组或 cell of char，不能是 cell of string | `if iscell(items); items = string(items); end` |
| `containers.Map` key 类型 | key 必须是字符向量 | 使用 `char(key)` 转换 string |
| visadev 重复创建 | 同一资源被多个对象持有 | Station 集中管理，`connect()` 前检查 `isConnected()` |
| 连接后立即查询失败 | 仪器需要预热时间 | Ceyear OSA 在 `connect()` 中有额外初始化序列 |
| `configure()` 在断连后调用 | 参数只在连接后有效 | `ensureConnected()` 守卫 |
| ELOG 阻塞 UI | HTTP 超时过长 | 设置 30s 超时，非阻塞调用 |
| 批量采集时 VISA 冲突 | 多个 visadev 并发读写 | 采集队列串行执行 |
| `acquire()` 无参数调用失败 | 所有驱动的 acquire 首参数为必需参数 | `buildAcquireArgs(key, {})` 提供默认值回退 |
| tiledlayout 父容器不兼容 | 旧版 MATLAB 不支持 uigridlayout 作为父容器 | 用 uipanel('BorderType','none') 包裹 |
| StatusLabel 位置漂移 | 用绝对定位挂在 Figure 上 | 放入 MainGrid 固定行 |
| InstrumentTable 列数 vs Grid 列数不匹配 | 添加了控件但 Grid 列数未更新 | 始终检查 Grid [m,n] 与子组件 Layout.Column 的一致性 |
| Properties 类型约束报错 | 某些类在旧版 MATLAB 中未定义（如 TiledChartLayout） | 未知类型去掉类型约束，仅保留属性名 |
| `sprintf('\\n')` 产生真正换行符 | MATLAB 中 sprintf 解释 `\n` 为 char(10) | ELOG body 分隔符用字面量 `'\n'`（单引号） |
| `arguments` block 不兼容 struct 传参 | R2024a 中 `opts.Field` 语法需 name=value 调用 | 手动 isfield+默认值替代 arguments block |
| buildTraceTable x/y 维度不匹配 | OSA 两次独立查询可能返回不同长度 | 取 min 共同长度截断 |
