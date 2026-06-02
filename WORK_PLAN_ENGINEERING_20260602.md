# Measurement Device Manager 工程化工作计划

更新日期：2026-06-02
项目目录：Z:\Measurement_Device_Manager\matlab_unified
主线入口：MeasurementManagerApp.m
适用范围：统一 MATLAB 仪器控制 APP 的 GUI、仪器接口、采集模式、数据保存、ELOG、版本管理。

## 0. 项目目标

构建一套可长期维护的 MATLAB 仪器控制 APP，用于统一管理 OSA、ESA、OSC、VNA 等实验室仪器，实现安全连接、参数读取与设置、数据采集、数据保存、ELOG 上传和版本可追踪。

核心目标：
- 不误触发仪器。
- 默认优先读取当前显示数据。
- GUI 在常用窗口尺寸下可完整操作。
- 每次大版本改动都有 Git 版本记录。
- 每项功能完成后有复盘、测试记录和计划勾选。

## 1. 工作原则

### 1.1 仪器安全原则

- 没有用户明确授权，不连接真实仪器。
- 没有用户明确授权，不执行扫描、digitize、触发、重扫、长时采集。
- 默认采集语义为只读当前显示数据。
- 主动采集模式必须在 GUI 上明确标识，并由用户显式选择。
- 所有设备调试先做静态检查，再做最小链路，再做完整采集。

### 1.2 工程实现原则

- 主入口文件名和类名保持稳定：MeasurementManagerApp.m / MeasurementManagerApp。
- 版本号通过 Git tag 管理，不长期维护 MeasurementManagerAppV2/V3 这类分叉入口。
- 大改动前先记录旧版本，大改动后提交新版本。
- 不把工具临时文件提交到 Git，例如 .claude/、.codegraph/daemon.pid。
- 单次提交只包含同一主题的变动。

### 1.3 GUI 设计原则

- GUI 是实验工具，不做展示型界面；优先紧凑、可扫视、可重复操作。
- 核心按钮必须在常用窗口尺寸下可见：Connect、Acquire、Save、ELOG Upload。
- 配置项过多时使用折叠或滚动，不允许裁切到不可操作。
- 重要操作需要状态反馈：连接状态、保存结果、ELOG 上传结果、错误日志。

## 2. 当前基线状态

当前主线 GUI：MeasurementManagerApp.m
当前 Git 分支：master
当前远端：origin / https://github.com/OUTERI/Measurement-Device-Manager-matlab-unified.git
当前远端推送状态：本地可提交，远端 push 受本机代理 127.0.0.1:7897 影响暂不可用。

当前需注意的问题：
- Git 工作区仍存在工具文件状态：.codegraph/daemon.pid 删除、.claude/ 未跟踪。
- 这些文件不属于功能改动，后续提交时应继续排除。
- MATLAB 静态检查上一次被中断，后续功能提交前需要重新运行。

## 3. 里程碑拆分

### M0：版本管理与开发流程基线

目标：让后续开发有稳定流程。

任务：
- [x] 读取 Git 仓库状态和远端地址。
- [x] 建立正式工作计划文档。
- [x] 建立版本历史表。
- [ ] 配置本仓库 Git 作者为 QZF。
- [ ] 处理 GitHub push 的代理问题。
- [ ] 给当前稳定版本打本地 tag。
- [ ] 远端恢复后推送 commit 和 tag。

验收标准：
- 本地 Git 可正常 commit。
- VERSION_HISTORY.md 能查到历史版本。
- 大版本更新流程明确。

### M1：GUI 可用性与布局稳定

目标：先解决界面可操作性，为后续功能开发提供稳定载体。

任务：
- [x] Data Storage 面板固定高度，避免被 ELOG 详细字段挤压。
- [x] Save All / Save Session / Save Selected / Clear 按钮保留在固定 Storage 区域。
- [x] ELOG Upload 按钮放在 ELOG 标题栏，默认始终可见。
- [x] ELOG 详细配置默认折叠，可通过标题栏按钮展开。
- [x] Status Log 维持右侧窄列，不占用左下保存/ELOG 操作区。
- [ ] 小窗口下主要控件无裁切。
- [x] MATLAB checkcode 已运行，无语法中断；现有 21 条为旧代码分析提示。
- [x] MATLAB GUI 构造/销毁测试通过，不连接仪器。

验收标准：
- 打开 APP 后，不需要拖大窗口也能看到保存按钮和 ELOG 上传入口。
- 展开 ELOG 后，所有 ELOG 字段可访问。
- 折叠 ELOG 后，Upload 和状态反馈仍可见。

测试方式：
- 静态检查：checkcode('MeasurementManagerApp.m','-id')。
- GUI 人工检查：默认窗口尺寸、小窗口尺寸。
- 不连接仪器。

### M1 复盘：2026-06-02

完成功能：
- 调整主网格行列比例，给左下 Storage/ELOG 操作区更多稳定空间。
- Storage 区固定高度，保存按钮不再依赖 ELOG 剩余高度。
- ELOG 默认折叠，Upload 按钮、状态文本和展开按钮保留在标题栏。
- ELOG 可执行文件默认路径修正为 E:\Program Files (x86)\ELOG\elog.exe。

修改文件：
- MeasurementManagerApp.m
- WORK_PLAN_ENGINEERING_20260602.md

是否连接真实仪器：
- 否。

测试方式：
- MATLAB R2024b checkcode('MeasurementManagerApp.m','-id')。
- MATLAB R2024b 构造/销毁测试：app = MeasurementManagerApp(); delete(app)。

测试结果：
- checkcode 可运行，无语法中断；现有 21 条为旧代码分析提示。
- APP_CONSTRUCT_OK。

已知风险：
- 小窗口下完全无裁切仍需要用户在实际屏幕上肉眼确认。
- GitHub 远端 push 仍受本机代理 127.0.0.1:7897 影响，当前只能本地提交。

Git 提交号：
- 待提交。

是否已打 tag：
- 待提交后处理。

### M2：参数读取与 Set 功能

目标：连接设备后读取当前仪器参数，显示到 GUI，并支持用户修改后写回。

依赖：M1 完成。

任务：
- [ ] 梳理 ParameterDef 当前已有参数定义。
- [ ] 为 OSA 定义读取参数接口：波长范围、分辨率、采样间隔、能级。
- [ ] 为 ESA 定义读取参数接口：频率范围。
- [ ] 为 OSC 定义读取参数接口：垂直量程、时间窗口、通道数、采样率。
- [ ] GUI 参数面板区分 read current 和 Set。
- [ ] 未连接时 Set 按钮提示错误，不崩溃。
- [ ] 已连接时读取当前值填入编辑框。
- [ ] Set 只修改用户提交的参数。

验收标准：
- 每类仪器参数能显示当前值。
- 修改参数后 Set 能写回对应设备。
- 不同仪器只显示适用参数。

测试方式：
- 第一阶段：mock / 静态测试，不连仪器。
- 第二阶段：用户授权后逐台设备最小链路测试。

### M3：采集模式系统化

目标：把“只读当前数据”和“主动采集”明确分开。

依赖：M1 完成；部分依赖 M2。

任务：
- [ ] 为 OSA 添加模式：读取当前暂停数据、单次扫描、重复扫描。
- [ ] 为 ESA 添加模式：读取当前暂停数据、单次扫描、重复扫描。
- [ ] 为 OSC 添加模式：读取当前数据、数据采集器模式。
- [ ] GUI 中模式选择与仪器类型绑定。
- [ ] 默认模式为只读当前显示数据。
- [ ] 重复扫描支持间隔设置和停止。
- [ ] OSC 数据采集器模式支持采集时间、采样率和通道选择。

验收标准：
- 默认不会主动触发新扫描。
- 主动模式有清晰 UI 标识。
- 每种模式保存的数据结构一致，便于导出和 ELOG。

测试方式：
- mock 参数构造测试。
- 无设备静态检查。
- 授权后真机最小模式测试。

### M4：数据管理与绘图交互

目标：让采集结果易管理、易删除、易识别。

任务：
- [ ] Live Data View 表格支持右键删除单条数据。
- [ ] 删除只影响内存记录，不误删已保存文件。
- [ ] 不同仪器类型使用不同颜色标注。
- [ ] OSC 多通道曲线颜色不重合。
- [ ] 数据保存支持按仪器分类。
- [ ] 数据保存支持按使用人分类。
- [ ] 增加 FIG 保存选项。
- [ ] 示波器时间轴改成相对时间差，并自动调整单位。

验收标准：
- 表格删除操作可撤销或至少有明确日志。
- 保存路径规则清晰可验证。
- 绘图颜色稳定，不随刷新随机变化。

### M5：ELOG 完整化

目标：让 ELOG 上传可见、可点、可验证、可配置。

依赖：M1 完成。

当前暂缓：用户需要进一步确认实验室 ELOG 字段配置。

任务：
- [ ] ELOG Upload 按钮始终可见。
- [ ] 上传结果显示在 ELOG 状态栏。
- [ ] 上传结果写入本地 _elog_log。
- [ ] ELOG 主机默认 192.168.1.72。
- [ ] ELOG 可执行文件默认 E:\Program Files (x86)\ELOG\elog.exe。
- [ ] 后续按实验室配置更新 logbook、author、字段映射。

验收标准：
- 不连接仪器也能发起手动 ELOG 测试。
- 成功/失败状态清晰可见。
- 本地日志可用于验证上传行为。

## 4. 测试矩阵

| 测试类型 | 是否需要真实设备 | 何时执行 | 内容 |
| --- | --- | --- | --- |
| MATLAB checkcode | 否 | 每次代码提交前 | 语法、明显静态问题 |
| GUI 打开测试 | 否 | GUI 改动后 | 窗口是否可打开、按钮是否可见 |
| 数据结构 mock 测试 | 否 | 保存/绘图/ELOG 改动后 | 构造假数据验证保存和显示 |
| 最小连接测试 | 是 | 用户授权后 | connect + *IDN? |
| 当前显示数据读取 | 是 | 用户授权后 | Fresh=false 路径 |
| 主动采集测试 | 是 | 用户明确授权主动采集后 | Fresh=true / 单扫 / 重复扫 |
| ELOG 真实上传 | 可能不需要仪器，但需要 ELOG 网络 | 用户允许后 | 上传测试条目并查看 _elog_log |

## 5. Git 流程

### 大版本开始前

1. 检查状态：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" status --short --branch
```

2. 如当前状态稳定，打旧版本 tag：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" tag -a vYYYYMMDD-before-<task> -m "Before <task>"
```

3. 如网络可用，推送 tag：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" push origin vYYYYMMDD-before-<task>
```

### 大版本完成后

1. 检查变动：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" status --short
git -C "Z:\Measurement_Device_Manager\matlab_unified" diff --stat
```

2. 只添加相关文件：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" add <相关文件>
```

3. 提交：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" commit -m "ui: stabilize storage and ELOG layout"
```

4. 打新版本 tag：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" tag -a vYYYYMMDD-<task> -m "<task> completed"
```

5. 网络可用后推送：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" push origin master
git -C "Z:\Measurement_Device_Manager\matlab_unified" push origin vYYYYMMDD-<task>
```

## 6. 复盘模板

每完成一个功能，在计划文档或复盘文档中记录：

- 完成功能：
- 修改文件：
- 是否连接真实仪器：
- 测试方式：
- 测试结果：
- 已知风险：
- Git 提交号：
- 是否已打 tag：

## 7. 当前下一步

当前优先执行 M1：GUI 可用性与布局稳定。

本阶段完成条件：
- Storage/ELOG 不裁切。
- ELOG Upload 可见。
- MATLAB 静态检查通过。
- 更新本计划勾选状态。
- 本地 Git commit。
- 若网络恢复，push 到 origin 并打 tag。
