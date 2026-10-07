# 看板精简与验证 — 2026-10-07

## 设计依据

Pacta 的看板服务于“选择下一项任务并开始专注”。使用 Flutter/Material 3，面向 Android 与 Windows；Apple HIG 在此应用信息层级、可读性和布局原则，不套用 macOS 导航约定。

旧版将国策检查点和显示时区说明、活动时区设置、日历来源管理混入行动摘要，且三个摘要标题混用 titleLarge/titleMedium。依据 `design-principles.md › Simplicity` 的 “Include just what’s necessary” 和 `settings.md › General settings` 的 “Put general, infrequently changed settings in your custom settings area”，移除说明并将设置集中到“我的”。依据 `typography.md › Conveying hierarchy` 的 “Adjust font weight, size, and color as needed to emphasize important information”，统一摘要标题 titleMedium；沿用现有语义颜色和系统字体。引用来自 `.agents/skills/apple-design/references/hig/` 已读取的参考文件。

保留任务专注进度作为主要视觉强调，不增加装饰或动画。页面标题24、摘要标题16、中等字重；正文14、辅助文字12逻辑像素，均保持系统缩放。摘要卡16内边距、12间距。宽度至少960且字体倍率小于1.6时双栏，其他情况单栏。活动行窄于360或字体倍率大于1.3时，日期和时长换行，进度条独占下一行。

```text
紧凑 / 大字体          常规宽度
今天先做什么  新建目标   任务列               辅助列
目标 / 任务 / 进度      今天先做什么         国策状态
国策状态              目标 / 任务 / 进度    近期专注活动
近期专注活动                               今日日历
今日日历
```

近期专注活动仍保留最近七日活动和累计有效专注，移除时区名称及按钮；国策仍保留状态数量和进入国策树的操作。显示时区在“我的”保留跟随设备、搜索和手动选择；日历来源沿用“我的 → 日历块”。日历空态只断言没有已导入的安排。国策检查点、结算和确认规则不变，无新增领域概念或 ADR；规格更新在 product-design.md 和核心规格中，CONTEXT.md 的既有改动不属于本任务。

## 自动验证

- Windows SDK `dart format`：改动 Dart 文件格式通过。
- Windows SDK `flutter analyze`：No issues found。
- `flutter test test/board test/ui_layout_test.dart test/calendar/calendar_page_test.dart`：15项通过，含窄屏两倍字体和亮暗主题文本/主操作对比度至少4.5:1。
- `flutter test`：246项通过。
- WSL直接执行Windows Dart的首次测试因Winsock环境错误10106未加载测试；改为Windows cmd调用flutter.bat后通过。

## 代码复核

固定点为实施前 HEAD `97003fe294b66a7d08ad384e21a35fe265d1a58b`。使用 code-review 技能，两个子Agent分别复核 Standards 与 Spec。

- Standards：无阻断问题。设备时区读取逻辑重复是低优先级维护建议。
- Spec：发现日历空态表述过度、日历条目依赖dense默认字号、摘要内边距不一致，三项均已修复。

实际设备验证记录见 board-design-device-fixture.md。
