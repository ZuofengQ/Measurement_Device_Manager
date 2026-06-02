# Version History

更新日期：2026-06-02
仓库：Z:\Measurement_Device_Manager\matlab_unified
远端：origin / https://github.com/OUTERI/Measurement-Device-Manager-matlab-unified.git
主分支：master

## 版本管理原则

- MATLAB 主入口名称保持稳定，默认不通过改类名或文件名来保存版本。
- 大版本用 Git commit + tag 管理，不靠复制 `MeasurementManagerAppV2.m`、`V3.m` 等长期分叉来管理。
- 大版本定义：会明显影响功能实现、仪器控制行为、数据保存语义、GUI 主流程或 ELOG 上传流程的改动。
- 零碎小改动可累计到下一次有意义的提交，不必每改一行就上传。
- 工具临时文件不进入版本提交，例如 `.claude/`、`.codegraph/daemon.pid`。

## 当前正式版本

| 版本标识 | 日期 | Git 标识 | 类型 | 内容 | 备注 |
| --- | --- | --- | --- | --- | --- |
| v20260602-rollback-m1-layout | 2026-06-02 | tag | fix | 回退 M1 GUI 布局改动 | M1 布局导致原本可显示界面不完整，先恢复到 M1 前 GUI |
| v20260602-m1-gui-layout | 2026-06-02 | 45d134c | ui | 稳定 Data Storage 和 ELOG Upload 布局 | 本地 tag 已创建；远端 push 受代理影响暂未完成 |
| v20260602-version-control-baseline | 2026-06-02 | tag | docs | 建立正式工作计划和版本控制表 | 当前版本管理基线；tag 指向本文件所在提交 |

## 历史提交记录

| 日期 | Commit | 类型 | 内容 | 说明 |
| --- | --- | --- | --- | --- |
| 2026-05-30 | bfbdb59 | fix | revert 2 broken fixes, apply correct alternatives | 当前代码基线，HEAD/origin/master |
| 2026-05-30 | e5eb573 | fix | 9 code review issues | 修复 9 个评审问题 |
| 2026-05-30 | b760744 | fix | GridSize cannot be set on non-empty TiledChartLayout | 修复 tiledlayout 相关错误 |
| 2026-05-30 | 031d094 | fix | use uistyle/addStyle for status column instead of HTML | 修复状态列显示方式 |
| 2026-05-30 | 7d4fd14 | feat | replace lamp column with in-table status column | 用表格状态列替代独立 lamp 列 |
| 2026-05-29 | 8928719 | docs | update DEVELOPMENT.md for UI v4 | UI v4 开发说明 |
| 2026-05-29 | 74e6f02 | feat | UI v4 | design tokens、合并 tabs、键盘快捷键、可折叠 ELOG |
| 2026-05-29 | 7d61d2a | refactor | code review fixes | 可用性、性能、健壮性修复 |
| 2026-05-29 | 8b99dab | docs | update README with ELOG, save buttons, data formats | README 文档更新 |
| 2026-05-29 | cf3becc | docs | update DEVELOPMENT.md for ELOG v2 | ELOG v2、保存语义和常见坑 |
| 2026-05-29 | c0db866 | feat | ELOG v2 | legacy 字段迁移、紧凑布局、保存语义、关键 bugfix |
| 2026-05-29 | b79e45d | feat | UI layout v3 | 三列布局、放大绘图区、tile 配置、日志折叠 |
| 2026-05-28 | 75d3f29 | feat | MeasurementManagerApp v2 | 多仪器显示、通道选择、按钮分离、session save |

## 大版本更新流程

1. 开始前检查状态：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" status --short --branch
```

2. 如当前版本稳定，先给旧版本打 tag：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" tag -a vYYYYMMDD-before-<task> -m "Before <task>"
git -C "Z:\Measurement_Device_Manager\matlab_unified" push origin vYYYYMMDD-before-<task>
```

3. 完成大改后只添加相关文件：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" add <相关文件>
```

4. 提交并推送：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" commit -m "<type>: <summary>"
git -C "Z:\Measurement_Device_Manager\matlab_unified" push origin master
```

5. 给新版本打 tag：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" tag -a vYYYYMMDD-<task> -m "<task> completed"
git -C "Z:\Measurement_Device_Manager\matlab_unified" push origin vYYYYMMDD-<task>
```

## 回滚方式

查看旧版本文件：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" show <commit>:MeasurementManagerApp.m
```

只回滚某个文件：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" restore --source <commit-or-tag> -- MeasurementManagerApp.m
```

整仓回滚需要非常谨慎，默认不执行：
```powershell
git -C "Z:\Measurement_Device_Manager\matlab_unified" reset --hard <commit-or-tag>
```
