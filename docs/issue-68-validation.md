# Issue #68：国策树视图偏好跨进程恢复

日期：2026-10-23。实施基点 `4cd11b2b90c15e0252820a76d80c8d88e3806283`，当前分支 `master`；开始时工作区干净。

## 范围与实现

依据 Issue #68、改进专题规格 US35–37 /「设备视图偏好」及验收矩阵 R22-06。沿用已确认页面/App 级边界，替换认证、云端与设备存储失败来源；真实进程重启单独取证。ADR0007/0008 已排除的辅助技术、大字号和专门键盘专项不作为本票验收条件，现有测试随常规回归保留执行。

原页面只把 `_detailed` 存在 State。现在 AppShell 传入当前用户标识，以本机 SharedPreferences 按用户保存一个视图 bool；首次简洁，选择立即发起保存，重新读取恢复。独立于 Drift 的业务数据与云快照，不保存平移或缩放，不新增云表、权限或协议。

读取期间显示进度文字，视图菜单暂禁用，其他页面操作保留；读取失败显示「视图偏好读取失败，暂用简洁视图。」和「重试读取」。保存失败保留本次可见选择，同时明确显示「视图偏好未保存，请重试。」和「重试保存」，不显示保存成功。检查平台 setBool 的 false 返回值；加载时 reload，避免把 legacy SharedPreferences 失败写入后的内存缓存当作落盘成功。用户切换重置页面身份；异步结果只可更新发起时的页面请求。

## 自动化证据

Flutter/Dart 均经 WSL 的 `cmd.exe /c` 使用 Windows SDK。

- 首个偏好测试在新增 userId 接口前编译失败，加入持久化后恢复与隔离断言通过。测试夹具最初因 Drift 零时长 timer 遗留失败，按现有页面测试等待实际异步查询并卸载页面后消除。
- 读取失败测试在无错误提示时失败；添加回退文案及重试后通过。
- 保存失败测试在无处理时因写入失败抛错/无提示失败；添加错误处理及重试后通过。实际点击「重试保存」，成功后重建恢复；失败后重建仍读旧值。
- 云快照回归使用真实 CloudSnapshotRepository 与 InMemoryCloudSnapshotRemote：视图改变不改变业务 payload/fingerprint，上传不携带偏好，下载后当前设备选择保留。未连接真实 Supabase；本票未改变数据库、身份、同步或权限契约。
- 相关测试首轮发现无限进度动画使现有 App 级 pumpAndSettle 等待设备 IO 超时，改为静态进度文字；最终该组 27 项通过。

最终验证：

| 命令 | 结果 |
| --- | --- |
| `dart format lib/main.dart lib/src/national_focus/national_focus_tree_page.dart lib/src/national_focus/national_focus_view_preferences.dart test/national_focus/national_focus_view_preferences_test.dart integration_test/issue_68_view_memory_device_test.dart` | 完成，最终 0 文件需格式变更 |
| `flutter analyze` | No issues found，4.3 秒 |
| `flutter test test/national_focus/national_focus_view_preferences_test.dart test/national_focus/national_focus_tree_page_test.dart test/national_focus/national_focus_reference_canvas_test.dart test/sync/manual_cloud_sync_app_test.dart` | 27 passed，8 秒（新增第6项异步用户切换回归前） |
| `flutter test` | 291 passed，22 秒；最终完整测试运行一次 |
| `git diff --check` | 通过 |

最终完整测试包含 6 项新增偏好测试，覆盖读取失败的 375dp 正常字号暗色布局、宽屏亮色保存失败重试，以及旧用户延迟读取不会污染当前用户。完整测试与分析日志在本机 `/tmp/issue68-full-test.log`、`/tmp/issue68-analyze-final.log`。

## 平台证据

修复前真实进程结束重启已完成：Android15 PID `16475 → 16590`，Windows11 PID `29020 → 21652`，选择详细后重新启动均回简洁。两端均确认旧进程已退出，没有热重载、清除数据或卸载。

修复后两端各三阶段通过：Android PID `16759 / 16881 / 17030`，Windows PID `26860 / 26824 / 33336`。第二进程先断言详细恢复，再切回简洁；第三进程断言简洁恢复。每阶段均验证同文件内测试卡片保留，退出后确认无旧进程。命令、详细阶段、截图与限制见[设备验收记录](issue-68-device-validation.md)。

主代理目视复核六张原生截图：Android 412×892 窄屏亮色、Windows 1266×683 宽屏暗色，正常字号菜单与卡片可读、无明显溢出。seed 截图为详细；restored-detailed 截图拍于恢复详细并改回简洁之后，因此画面是简洁，详细恢复由切换前的断言和独立 PID 证明。restored-simple 为再次重启后的简洁。设备操作为集成测试驱动的触摸/点击，未声称人工鼠标/触屏验收。

## 评审与交付

独立设计自查与主代理截图复核已完成。依据 apple-design `feedback.md › Best practices` 的就地状态反馈原则（“Consider integrating status feedback into your interface.”）和 ui-ux-pro-max 的 Error Recovery 指导，错误状态与重试同区，复用现有 Material 语义错误色、默认按钮和响应式文字。没有新增模态提醒或成功弹窗。

设计自查提出一项低优先级文案建议：首次读取与保存可使用不同进度文字。现有「正在更新视图…」描述视图状态更新并同时覆盖两者，保留该短句；它不承诺保存成功。无阻断设计发现。

## Standards

独立评审：0 项已记录标准违规。变更符合本机按用户保存偏好、与云快照隔离、读取失败回退并提供重试等相关要求；未将 ADR0007/0008 已退出范围的专项要求列为缺陷。

一项低优先级判断建议（possible Duplicated Code）：`national_focus_view_preferences_test.dart` 的 `_FailFirstReloadPreferences` 与 `_FailFirstSetBoolPreferences` 重复部分委托样板，包括 `_delegate`、`reload`、`getBool`、`setBool`、`noSuchMethod`。可考虑合并为可配置替身；当前分开保留也让两个失败场景更清楚。主代理复核后保留：读取替身模拟首次读取失败，写入替身还模拟缓存先于磁盘更新，职责清晰；不为少量测试样板引入配置分支。

## Spec

独立评审：0 项发现。未发现缺失/部分实现、范围扩张或错误实现。符合 US35–37、Issue #68 与 R22-06：首次简洁、按本机用户保存、选择立即发起持久化、真实重启恢复，以及读取失败回退与读写重试。偏好独立于业务快照，未新增平移缩放保存。保存检查 setBool 失败返回值，读取 reload 避免失败缓存冒充持久状态，身份及请求序号阻止旧异步结果污染当前用户。

两轴结论：Standards 0 项标准违规、1 项低优先级判断建议（已复核保留）；Spec 0 项发现，无未解决阻断项。

## 交付

交付操作为提交并推送当前 `master`、勾选 Issue #68 验收清单、移除 `ready-for-agent` 标签并关闭票据；最终提交标识与远端状态记录在 Issue 完成评论。GitHub 原生 blocked_by / blocking 在开始时和设备验收后均为空，无需删除其他票据关系；父票 #63 保留。
