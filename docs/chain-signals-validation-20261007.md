# 链动作与时长验证（2026-10-07）

跟踪：[Issue #52](https://github.com/Kaniruka/Pacta/issues/52)。确认规则见核心规格的 Chain signals and duration 补充。

## 决策与实现

预约链设置触发信号，精锐/普通链分别设置专注标志。三种动作都是神圣座位的具体表达；仍采用原三条链的连续/最佳计数，改动作不重置记录，不新增动作执行计数。自动/提前预约交接保持原有行为。空动作不阻断启动。

动作文本存入用户隔离的本地业务表，schema 23 升至 24 仅新增表，保留记录。手动整份快照包含该表；旧快照缺表按空动作恢复，服务器既有 schemaVersion 1 保持兼容。没有新增远端逐记录表或自动上传。

精锐、普通分别按任务进度同口径统计有效时长：已接受完成及失败记录，排除暂停、重复、未核对区间。平均分母包含零时长的已接受已结算会话，空记录显示零。

## 界面判断

目的为在开始前明确现实承诺动作，并保留跨任务链记录。沿用 Material 3 语义色和字号；动作编辑独立、字段有持续标签，启动设置显示当前模式对应动作。新内容使用纵向分组、可滚动对话框，支持窄屏文字换行；本项目为 Android/Windows，Apple 原则用于可访问性和布局，不套用 Apple 导航约定。

依据已读取 apple-design 本地参考：text-fields.md › Best practices “include a separate label”；layout.md 的适应可用空间原则；color.md › System colors “Avoid hard-coding system color values”。这是对现有界面的增补，不新增视觉 token 或动画。

## 验证

使用 Windows Flutter SDK，从 WSL 调用 dart.exe 的 flutter_tools.snapshot；补充 PATHEXT 和 SYSTEMROOT 环境变量，以避免工具查找失败。

- `dart format`：改动 Dart 源码与测试已格式化；Drift 使用 `dart run build_runner build --delete-conflicting-outputs` 生成。
- `flutter analyze`：无问题。
- 存储/快照/旧快照专项测试：20 项通过；补充跨用户快照断言后快照专项 12 项通过。
- 时长统计专项：4 项通过。
- 初次完整 `flutter test`：233 项通过；新增界面测试清理 Drift 监听计时器后，最终完整测试 238 项全部通过。
- 界面专项：5 项通过，覆盖保存/取消/清空、320 宽度两倍字号、模式切换提示。
- `git -c core.whitespace=cr-at-eol diff --check`：通过（生成文件保留原 CRLF）。
- code-review 双轴：Standards 无硬性违规，发现文案作为字段标识的低优先级问题，已改枚举；Spec 无阻断问题，布局说明已与实际两张卡对齐。

未执行 Android 真机、Windows 原生应用人工交互或真实云端传输/RLS 复验；本次无需服务器迁移，自动化快照测试不代替真实服务证据。
