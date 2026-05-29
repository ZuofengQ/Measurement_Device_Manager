# MATLAB 统一仪器接口说明

这个目录包含一套新的 MATLAB 仪器控制与数据采集接口，目前覆盖以下四类仪器：

- ESA
- OSA
- VNA
- 示波器

这套代码只保留统一测试系统所需的核心能力：

- 连接设备 `connect`
- 断开设备 `disconnect`
- 参数配置 `configure`
- 数据采集 `acquire`
- 数据保存 `saveData`

这里**不包含**一次性实验脚本、硬编码 sweep 流程、临时测试逻辑。仓库中其他旧 MATLAB / Python 代码保持不变，用于参考和迁移。

## 目录结构

- `+labdevices/+core`
  - 公共基类、VISA 通信、数据导出、仪器注册表
- `+labdevices/+esa`
  - ESA 类
- `+labdevices/+osa`
  - OSA 类
- `+labdevices/+vna`
  - VNA 类
- `+labdevices/+scope`
  - 示波器类
- `examples`
  - 示例脚本，只展示调用方式，不会自动运行

## 当前类

- `labdevices.esa.KeysightN9020A`
- `labdevices.osa.CeyearOSA6362D`
- `labdevices.vna.KeysightE5080B`
- `labdevices.scope.KeysightMSO9404A`
- `labdevices.scope.RigolDHO4204`

## 实验室仪器与默认资源名

实验室已确认的仪器 IP 和默认资源名统一登记在：

- `labdevices.core.InstrumentRegistry`

当前映射如下：

| 仪器 | 注册键名 | 默认资源名 |
| --- | --- | --- |
| Keysight N9020A | `keysight_n9020a_esa` | `TCPIP0::192.168.1.45::inst0::INSTR` |
| Ceyear 6362D（白色） | `ceyear_osa_6362d_white` | `TCPIP0::192.168.1.35::8000::SOCKET` |
| Ceyear 6362D（黑色） | `ceyear_osa_6362d_black` | `TCPIP0::192.168.1.36::8000::SOCKET` |
| Keysight E5080B | `keysight_e5080b_vna` | `TCPIP0::192.168.1.27::inst0::INSTR` |
| SIGLENT SNA5003X-E | `siglent_sna5003x_e_vna` | `TCPIP0::192.168.1.103::inst0::INSTR` |
| Keysight MSO9404A | `keysight_mso9404a_scope` | `TCPIP0::192.168.1.25::inst0::INSTR` |
| Rigol DHO4204 | `rigol_dho4204_scope` | `TCPIP::192.168.1.49::INSTR` |

## 通讯方式总表

目前统一接口主要采用 **SCPI + MATLAB `visadev` + NI-VISA**。

| 仪器 | 类名 | 通讯方式 | 说明 |
| --- | --- | --- | --- |
| Keysight N9020A | `labdevices.esa.KeysightN9020A` | VISA over TCP/IP (`INSTR`) | 网络仪器，适合 ESA trace 采集 |
| Ceyear 6362D（白/黑） | `labdevices.osa.CeyearOSA6362D` | VISA over TCP Socket (`SOCKET`) | 通过固定端口直接访问设备 |
| Keysight E5080B | `labdevices.vna.KeysightE5080B` | VISA over TCP/IP (`INSTR`) | 网络 VNA |
| SIGLENT SNA5003X-E | 预留 | VISA over TCP/IP (`INSTR`) | 已登记 IP，类暂未实现 |
| Keysight MSO9404A | `labdevices.scope.KeysightMSO9404A` | VISA over TCP/IP (`INSTR`) | 支持瞬时波形采集 |
| Rigol DHO4204 | `labdevices.scope.RigolDHO4204` | SCPI over VISA TCP/IP | 支持瞬时采集和长时段深存储采集 |

## 两台 Ceyear 6362D 的使用方式

实验室有两台 `6362D`，请不要混用 IP。

推荐显式使用别名创建对象：

- `labdevices.osa.CeyearOSA6362D("white")`
- `labdevices.osa.CeyearOSA6362D("black")`
- `labdevices.osa.CeyearOSA6362D.whiteUnit()`
- `labdevices.osa.CeyearOSA6362D.blackUnit()`

如果不传参数，当前默认使用 **黑色 6362D**。

## Rigol DHO4204 的两种采集模式

`RigolDHO4204` 目前支持两类采集：

1. 瞬时/屏幕波形采集
   - `acquire(..., 'Mode', 'NORM')`

2. 长时段/深存储采集
   - `configureLongCapture(...)`
   - `prepareCapture(...)`
   - `runCapture()`
   - `stopAndReadCapture(...)`
   - `acquireTimed(...)`

第二类适合你提到的“定时采集一整段数据”，而不只是读当前屏幕上的瞬时波形。

## 使用环境要求

建议按下面环境配置使用：

- MATLAB 版本：`R2024b`
- 必要工具箱：`Instrument Control Toolbox`
- VISA 后端：`NI-VISA`

### 其他人使用前至少要确认

1. 已安装 MATLAB R2024b
2. 已安装 `Instrument Control Toolbox`
3. 已安装 `NI-VISA`
4. 电脑与仪器在同一网段
5. 本机可以 `ping` 通目标仪器 IP
6. Windows 防火墙没有阻止 MATLAB 或 VISA 网络访问
7. MATLAB 已加入本目录到路径中

例如：

```matlab
addpath(genpath('E:\project\TestDeviceManager\matlab_unified'));
```

## 缺少环境配置时可能出现的情况

### 1. 没装 Instrument Control Toolbox

可能出现：

- `Undefined function 'visadev'`
- 无法创建 `visadev` 对象

说明：

- MATLAB 本身能打开，但不能通过这套统一接口访问仪器。

### 2. 没装 NI-VISA

可能出现：

- `visadev` 创建失败
- 找不到 VISA 资源
- 明明 IP 正确，但连接时报底层驱动错误

说明：

- 这通常不是代码问题，而是 MATLAB 没有可用的 VISA 后端。

### 3. 仪器和电脑不在同一网段

可能出现：

- `connect` 超时
- `*IDN?` 查询无响应
- ping 不通仪器 IP

### 4. 资源名格式不匹配

可能出现：

- `Unable to connect to the device`
- `Invalid VISA resource name`

说明：

- `INSTR` 和 `SOCKET` 资源名不能混用。
- 例如 `6362D` 用的是 `SOCKET` 资源，不是 `inst0::INSTR`。

### 5. 终止符设置不匹配

可能出现：

- 查询命令发出后卡住
- 读取到空字符串
- 只在部分设备上可连，部分设备上不可连

说明：

- 不同设备的 `LF / CRLF` 终止符不同，已经在类里按当前设备做了默认配置。
- 如果后续某台仪器固件行为不同，需要按真机再微调。

### 6. 深存储/长时段采集时超时

可能出现：

- 波形读取中途超时
- `readbinblock` / `WAVeform:DATA?` 卡住
- 读取到的数据点数不完整

说明：

- 这类情况在示波器尤其是 `Rigol DHO4204` 上更常见。
- 一般需要根据真机表现调节超时、分块点数、采样率或存储深度。

## 数据保存格式

统一导出层支持以下格式，可按需组合：

- `.mat` — 完整数据结构
- `.csv` — 表格格式（元数据 + 每 trace 独立 CSV）
- `.png` — 数据图（200 DPI）

## ELOG 电子日志上传

已完整接入 ELOG 命令行工具（服务器 192.168.1.72:8080），支持：

- **手动上传**：ELOG 面板填写信息 → Upload → App 截图 PNG + 仪器快照 + 样品标识
- **自动上传**：勾选 Auto-upload on save → 保存数据时自动附加数据图 PNG
- **字段**：Server/Port、Logbook（EPIC）、Author、XOI/Design、Wafer/Field/Chip/Sample、Type

## 保存按钮

| 按钮 | 行为 |
|------|------|
| **Save All** | 保存内存中全部采集数据，每条独立文件 |
| **Save Session** | 仅保存每台仪器最新一次采集，合并为单个 .mat |
| **Save Selected** | 选中表格行后保存对应数据 |
| **Clear** | 清空内存数据、表格、图表 |

## 示例

示例脚本在：

- `examples/basic_capture_examples.m`

里面包含：

- OSA 示例
- 白色 6362D 示例
- ESA 示例
- VNA 示例
- Keysight 示波器示例
- Rigol DHO4204 瞬时采集示例
- Rigol DHO4204 长时段采集示例

## 当前范围说明

当前只实现了你指定的前四类核心设备：

- ESA
- OSA
- VNA
- 示波器

辅助设备如激光器、功率计、直流源、RF 源、pump 目前没有并入这套统一接口。

## 后续建议

下一步比较合理的是：

1. 给 `SIGLENT SNA5003X-E` 补一个和 `KeysightE5080B` 同风格的 VNA 类
2. 找一台真机逐个联调：
   - `*IDN?`
   - 基础 `acquire`
   - 保存 `.mat/.csv/.png`
3. 根据真机表现微调：
   - 终止符
   - 超时
   - 二进制块读取
   - 深存储采集分块参数
