# 示例脚本说明

本目录下的示例按“仪器 + 采集场景”拆开，已写成 MATLAB 函数，直接在命令行调用函数名即可。

## 可直接运行的示例

- `example_scope_rigol_instant.m`
  - Rigol DHO4204 瞬时屏幕波形采集
- `example_scope_rigol_timed.m`
  - Rigol DHO4204 长时段采集
- `example_scope_keysight_mso9404a.m`
  - Keysight MSO9404A 瞬时波形采集
- `example_esa_keysight_n9020a.m`
  - Keysight N9020A 频谱采集
- `example_osa_ceyear_6362d.m`
  - Ceyear 6362D 光谱采集
- `example_vna_keysight_e5080b.m`
  - Keysight E5080B VNA 数据采集

调用方式示例：

```matlab
cd('E:\project\TestDeviceManager\matlab_unified\examples')
saved = example_scope_rigol_timed();
```

## 默认保存命名

如果不传 `BaseName`，保存文件名默认格式为：

`设备名_yyyy_MM_dd-HH_mm`

例如：

- `DHO4204_2026_05_26-14_35.mat`
- `N9020A_2026_05_26-14_36_metadata.csv`

如果同一分钟内重复保存，代码会自动在后面补后缀避免覆盖，例如：

- `DHO4204_2026_05_26-14_35_01.mat`

## 手动命名

每个示例脚本里都有：

- `useManualName`
- `manualBaseName`

把 `useManualName = true;` 就会使用你自己写的文件名。

## 输出目录

默认保存到：

- `matlab_unified/output`

## 初始化

每个示例都会先调用：

- `setup_example_environment.m`

这个函数会自动：

1. 把 `matlab_unified` 加到 MATLAB 路径
2. 创建默认输出目录

## 使用建议

- 先从单通道开始测试
- 先只保存 `mat` 或 `csv`，确认采集没问题后再加 `png`
- 如果示波器长时段采集超时，优先减小 `ChunkPoints` 或总采样点数
