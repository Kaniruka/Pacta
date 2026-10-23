# Issue #66 Windows 11 实际交互验收

日期：2026-10-23。Windows 11（10.0.22631），普通 Flutter Debug 应用进程，独立临时 SQLite、80 个任务、外部身份替身、云同步及通知禁用；不读取真实用户数据库。使用 [离线验收入口](../tool/issue_66_focus_navigation_demo.dart) 的 `ISSUE66_TEXT_SCALE=200` 固定 fixture 字号为两倍，没有修改 Windows 全局字号。

## 工具与运行

内置 REPL 因 WSL 路径元数据报 `sandboxCwd is not a local file URI`。沿用 #65 已验证的方法，通过标准 MCP 连接本机同一已安装 REPL，工作目录映射到 F 盘，所有 Windows 输入、窗口选择和截图仍使用官方 `@oai/sky`。用户明确批准了工具要求的“Allow Codex to use pacta?”，权限仅用于 Pacta 测试窗口；未修改全局配置。

运行命令（分别使用 none、appointment、paused）：

```bash
cmd.exe /c flutter run -d windows -t tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_TEXT_SCALE=200
cmd.exe /c flutter run -d windows -t tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_TEXT_SCALE=200 --dart-define=ISSUE66_FLOW=appointment
cmd.exe /c flutter run -d windows -t tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_TEXT_SCALE=200 --dart-define=ISSUE66_FLOW=paused
```

## 实际操作

- 宽窗口约 1267×714，在专注主页只显示 80 项计数和入口；鼠标打开任务选择。用系统菜单“大小”、方向键调整实际窗口至截图宽约 405px，列表与执行页均为 2 倍字号；未用 tester 的虚拟尺寸替代实际窗口。
- 鼠标切换精锐筛选，两者分类任务出现；Tab 可到 Back、全部、精锐、普通，焦点可见，Space/Enter 激活筛选。实际 Enter 切到普通后，普通及两者任务可见。见[窄窗口任务列表](evidence/issue66-windows-narrow-picker-200.jpg)、[键盘选择普通](evidence/issue66-windows-keyboard-regular.jpg)。
- 鼠标滚轮浏览到 I66-14-两者，点击任务打开设置，Esc 关闭设置；普通筛选及同一条目的屏幕位置保留。见[浏览位置](evidence/issue66-windows-scrolled-regular.jpg)、[取消后](evidence/issue66-windows-cancel-retains-scroll.jpg)。
- 再次选该任务，鼠标启动倒计时，执行页标题、任务及倒计时可读；点击 Back 直接回专注主页，原流程卡片保留。点击任务入口恢复原任务，倒计时由 24:59 继续至 24:27，未重新开始 25 分钟。见[启动](evidence/issue66-windows-direct-execution.jpg)、[返回主页](evidence/issue66-windows-running-home.jpg)、[再次恢复](evidence/issue66-windows-resumed-direct.jpg)。
- appointment fixture 预置预约并删除原任务。主页入口优先恢复该预约，标题保留“已删除”；真实窄窗口/两倍字号下，鼠标滚动到准备配置，任务下拉项可省略长标题、无横向溢出。Tab 聚焦 Back、Enter 回主页，原预约仍在，点击任务入口再次恢复原准备页，倒计时继续。见[已删除任务预约](evidence/issue66-windows-deleted-appointment-home.jpg)、[准备页](evidence/issue66-windows-deleted-appointment-preparation.jpg)、[窄窗口配置](evidence/issue66-windows-appointment-narrow-config.jpg)、[键盘返回](evidence/issue66-windows-appointment-return-home.jpg)、[再次恢复](evidence/issue66-windows-appointment-resumed.jpg)。

- paused fixture 预置暂停会话并删除原任务。鼠标点主页任务入口恢复原暂停页，标题标记已删除、计时维持 60:00，并显示暂停不计入投入。Tab 聚焦 Back、Space 返回主页，点击任务入口再进入仍是同一暂停状态。见[暂停主页](evidence/issue66-windows-deleted-paused-home.jpg)、[暂停执行](evidence/issue66-windows-deleted-paused-execution.jpg)、[键盘返回](evidence/issue66-windows-paused-keyboard-return.jpg)、[再次恢复](evidence/issue66-windows-paused-resumed.jpg)。

三次普通fixture均已关闭，窗口列表确认无Pacta测试窗口。预约的创建和文件数据库复开后的流程身份另由两端原生集成测试验证；此处区分普通应用真实系统输入与 tester 合成输入，不混称。
