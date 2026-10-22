# Issue #65 实施与验收

Issue：[T02: 标题区域折叠与看板分类呈现](https://github.com/Kaniruka/Pacta/issues/65)。
开始时 HEAD：`fece2f9da89c202551ea68c781a79fe57f11e99d`，分支 `master`。
并行工作随后将原有需求文档提交为 `7dcd449`；本票审查基点采用该提交。

## 范围与测试边界

沿用已确认的看板 App 级测试，通过可见内容、公开交互与 Semantics 验证。
描述功能 #64 已落地，本票完成组合复核：折叠保留目标描述、隐藏任务描述。
不改分类规则、历史归属或数据结构，不涉及云服务边界。

开始时已有 GLOSSARY、产品设计、核心规范、验收矩阵、ADR0005 的用户改动，
以及未跟踪需求整理/规格/票据文件；未替换或混入本票实现提交。

## 实施

- 标题区域是单一可聚焦折叠控件，方向箭头不构成第二个焦点；目标编辑/删除独立。
- 首次展开，各目标独立；空/非空目标折叠均卸载任务、内部添加入口及空态。
- 标题、目标描述、数量、完成状态和目标编辑删除保留；状态允许换行，避免大字号裁剪。
- 看板移除分类常驻标签；目标编辑保留“新任务默认分类”，任务编辑使用“适用专注链”。
- 普通/精锐/两者分类、专注进度和历史归属实现未改变。

## 自动化验证

所有 Flutter/Dart 命令均由 WSL 通过 `cmd.exe /c` 调用 Windows SDK。

| 命令 / 边界 | 结果 |
| --- | --- |
| `dart format` 四个改动 Dart 文件 | 完成 |
| `flutter analyze` | No issues found |
| `flutter test test/board` | 9 passed |
| `flutter test --reporter compact` | 272 passed |
| `flutter test integration_test/board_design_device_test.dart -d windows --reporter expanded` | 1 passed |
| 同一入口 `-d emulator-5554 --no-uninstall --reporter expanded` | 1 passed |
| `git diff --check` | 通过 |

TDD：先扩充现有标题点击测试，旧实现无法折叠；实现后通过。再逐片加入空目标、
Tab/Enter/Space、expanded 语义、编辑/删除隔离和分类编辑断言。
App 测试同时复核长标题、目标间独立性、描述组合及 both 分类保留。
进一步核验展开/折叠均提供 SemanticsAction.tap，并从公开 performSemanticsAction
分发点击成功折叠，状态与内容同步更新；保留该语义操作回归断言。
原生测试使用真实内存 Drift 和 fake auth，不访问用户数据库或云端业务数据。

Android 15 API35：现有 `PactaT24Peer` / emulator-5554。
Windows 11：10.0.22631。Windows 注入鼠标事件、Android 注入触摸事件，
两端均通过 Tab 寻找标题焦点并以 Enter/Space 切换；两端的 360 逻辑宽度、
两倍字号/暗色布局下，额外切换非空/空目标并验证目标描述保留及任务隐藏。
这些是原生进程中的 Flutter tester 事件，不声称是 Windows 系统鼠标/读屏操作。

新增原生断言首次因懒加载目标离开视口而不能 ensureVisible；改为 scrollUntilVisible
后，两端重跑通过。初次 Windows 测试的 SemanticsHandle 清理错误也已修正。
Android 手动读屏检查过程开启系统语义后，测试框架末尾的句柄数校验失败；
该检查轮次单独记录，未计入上面的通过结果。关闭读屏后无暂停自动化轮次通过。

## 设计与实际交互证据

采用 ui-ux-pro-max Flutter Semantics 指导；apple-design 的 Accessibility › Vision、
Mobility/Speech、Layout › Adaptability、Typography › Supporting Dynamic Type、
Buttons 和 Lists and tables 的反馈/层级原则转译为 Flutter Material 3；未套用 Apple 控件。
主代理目视检查 Android 暗色/两倍字号图像：标题、描述、数量、状态和编辑/删除可读，
空目标折叠后空态与添加入口消失。正常滚动可见其余内容；无新增颜色或字体体系。

- [实际 Android 空目标触摸折叠](evidence/issue65-android-empty-collapsed.png)。
- [启用 TalkBack 后滑动聚焦目标标题](evidence/issue65-android-talkback.png)。

Windows Computer Use 初始化失败：`sandboxCwd is not a local file URI:
file:///mnt/f/Workspace/Release/Flutter/Pacta`。无法通过该工具取得 Windows 桌面截图、
实际系统输入或可用读屏交互证据。原生 Semantics 断言不能代替这一验收项。Android TalkBack 15 已实际启用，
滑动可聚焦目标标题；未取得完整双击激活及朗读状态的有效证据，亦保留待验。
因此该票尚不能宣称全部验收完成，保留 Issue 打开并明确剩余检查。

## Standards

独立代理审查：0 项文档标准违反，0 项必须调整的 Fowler 异味。
依据 AGENTS、CLAUDE、UI 规范、GLOSSARY、产品设计、ADR0003/0004 及适用设计参考。
主代理复核：交互单焦点、48逻辑像素最小高度、现有主题及数据边界符合规则。

## Spec

独立代理审查：0 项功能错误、遗漏实现或范围膨胀；指出原生大字号阶段缺少切换，
已补充并在 Android/Windows 重跑通过。实际读屏验收限制保留，不以静态审查替代。
Standards 0 项；Spec 0 项实现问题，仍有上述平台验收缺口。

## 清理与远端状态

Android 私有数据已从本轮开始前的归档恢复，7个原文件 SHA-256 全部一致，
最终无额外文件。恢复过程中 Windows adb 的 stdin tar 提取被截断；改为将归档推送到
临时路径并就地提取后，逐文件校验通过，临时归档及新增资源时间戳已清理。
原有业务数据库、偏好和 Flutter 缓存均恢复；未卸载或清空应用数据。
TalkBack 临时启用设置已撤销，回到无启用服务的初始状态。

仅从 .env 提取公开 URL/publishable key 到被忽略的临时 define 文件，
`flutter build apk --debug` 和 `flutter build windows --debug` 均通过；
Android `adb install -r` 安装普通版本成功，未启动以避免改变恢复数据。
Windows 普通 Debug 产物已重建，Release 产物未改；原生测试仅用内存库。
临时 define 文件已删除，无凭据/真实用户内容进入提交。

本票实现与验收证据提交到当前 master 并推送 origin/master。
按用户要求移除 Issue 的 ready-for-agent 标签，核验 blocked_by/blocking 均为空；
保留原生父子关系。实际读屏缺口未标为完成，Issue 保持打开。
