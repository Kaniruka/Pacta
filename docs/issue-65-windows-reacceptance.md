# Issue #65 Windows 重新验收

> 历史适用范围：以下设计、评审及验收记录适用于各节所载日期（2026-10-23 范围调整之前）。原始事实、测试和证据保留；其中无障碍要求及未完成项不再构成未来交付条件，现行范围见 [ADR 0007](adr/0007-accessibility-out-of-product-scope.md)。

状态：实际鼠标/键盘、窄窗口与大字号验收完成；Windows无障碍由用户明确豁免。初始代码 `05babfe`，当时工作区干净。

## 环境错误复现与修复

内置 `node_repl.js` 在执行最小脚本前拒绝
`file:///mnt/f/Workspace/Release/Flutter/Pacta`，错误为
`codex/sandbox-state-meta: sandboxCwd is not a local file URI`。
`js_reset` 后同样失败。

按诊断优先检查：WSL路径被交给Windows REPL、运行时配置、桌面服务连接。
本机配置的REPL确为Windows `node_repl.exe`；Node与模块路径也都是Windows路径。
使用标准MCP连接已安装的同一REPL，工作目录映射为F盘，最小JS通过，
`@oai/sky`的`list_windows`也通过，定位到会话路径元数据传递。
临时连接不修改全局配置、不直接调用桌面原生helper，所有窗口操作仍走
现有REPL中的官方`@oai/sky`接口。

首次启动Pacta时服务要求应用访问授权：“Allow Codex to use pacta?”。
用户随后要求“请继续”，按本轮Pacta验收授权继续；仅使用离线内存fixture窗口，不操作登录和真实用户数据。

## 复验结果

构建并运行普通 WidgetsFlutterBinding 的内存fixture，Windows应用实际窗口，未用tester。
以 `BOARD_TEXT_SCALE_PERCENT=200` 强制该fixture的Flutter文字为2倍，未修改Windows系统字号。
默认宽窗口约1267×714；随后用系统菜单“大小”将实际窗口缩至约405×714。
405px是窗口捕获宽度，不将它声称为360逻辑像素或Windows全局缩放设置。

- 实际鼠标点击标题：折叠/展开，任务与任务描述消失/恢复，目标描述和状态保留。
- 实际Tab找到标题，Enter展开、Space折叠；焦点留在标题，下一Tab直接到编辑，再下一Tab到删除。
- 编辑目标独立打开，原始目标描述可见，取消后折叠状态不变；键盘打开删除确认，再Escape取消，无实际删除。
- 窄窗口2倍字号下重复非空目标折叠/展开和空目标折叠，无溢出或目标数量/状态裁剪。
- 两目标均折叠时，原生UIA树无任务、任务描述、空态和添加任务入口；保留标题、目标描述、数量、状态、编辑删除。
- UIA标题节点Value在“已展开／已折叠”之间切换，并带收起/展开任务提示；讲述人进程已实际启动。

[窄窗口折叠](evidence/issue65-windows-narrow-collapsed.jpg)、
[窄窗口展开](evidence/issue65-windows-narrow-expanded.jpg)、
[编辑目标](evidence/issue65-windows-narrow-edit.jpg)、
[删除确认](evidence/issue65-windows-narrow-delete.jpg)、
[两目标折叠](evidence/issue65-windows-both-collapsed.jpg)、
[原生UIA树](evidence/issue65-windows-ui-tree.json)。

Narrator键盘命令依据[微软官方命令表](https://support.microsoft.com/en-us/accessibility/windows/narrator/appendix-b-narrator-keyboard-commands-and-touch-gestures)：
Caps lock/Insert为Narrator键，Narrator+Enter为主操作。
实际Caps lock+Enter连续展开/折叠后保留标题焦点，截图见
[讲述人运行环境中的标题焦点](evidence/issue65-windows-narrator-header.jpg)。
专用组合键的效果还可能由App处理Enter，因此不单以这个现象证明TTS发声；
曾尝试本机短时系统输出与离线ASR补证，但未取得隔离的目标状态朗读证据，未计作通过，
临时录音已删除且没有录音提交。用户随后明确要求忽略电脑端无障碍，故停止这部分工作。
Windows无障碍是范围豁免，而非已通过的声音测试；其余键鼠和布局检查已完成。


## 清理

独立fixture的内存数据随窗口退出释放，没有打开真实用户数据库或云端业务服务。
退出测试窗口，停止本轮启动的讲述人，关闭临时REPL/MCP连接；全局工具配置未修改。
仅公开URL/publishable key用于重建普通Windows Debug入口；临时define已删除，
普通应用不启动，Release产物未改。临时录音、ASR日志、依赖和操作连接文件已清理。
