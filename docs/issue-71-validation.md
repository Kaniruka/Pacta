# Issue #71 实施与验收

日期：2026-10-24–25（Asia/Shanghai）。票据：[T08: 冷启动与前台只读检查云版本](https://github.com/Kaniruka/Pacta/issues/71)。开始工作区干净，当前分支 `master`，比较基点 `4417fb5d1ad2cc6466bce3fce6ed9a53176647cd`。

## 范围和已确认测试边界

沿用专题规格 Testing Decisions：真实 AppShell、真实本地仓储和 Drift，替换外部认证、云 remote、时钟和设备读取。主边界验证冷启动、5分钟前台节流、失败重试、云版本变化、成功上传/下载已处理及用户切换；不测试私有字段或控件嵌套。旧版转换和新版仅元数据读取沿用已有 remote 契约，并以隔离 Supabase 复核。只读检查允许变更设备检查状态，不得改变业务内容或成功同步时间。

ADR 0007/0008 已确认范围继续有效：保留正常字号、亮暗主题、响应式布局、鼠标/触摸和 Android 系统返回；不新增读屏、大字号或专项键盘验收。自动选择提示、忽略和进行中流程延迟提醒属于 #72。

## 工作记录

- 已读取 #71 正文及评论（无评论），确认依赖 #69 已有成功版本/本地基线实现。GitHub 实际入向阻塞关系为空；出向为 #72，完成后清理。
- 实施与 AppShell 回归、隔离服务验收、真实进程生命周期入口并行推进；最终由主代理复核代码、测试输出和设备证据。
- 当前发现 Windows 11 与 Android 15/API35 设备，实际运行结果在完成后记录，工具可用不等于已验收。

2026-10-25 恢复：产品代码和 315 项全量通过记录保留；隔离项目仍存在，旧 runtime 已停止，残留临时身份由专用脚本清理后重新创建。Windows 前三轮真实生命周期断言已有证据，但整场 exercise 在网络确认阶段中断，不标为整体通过。补做独立网络与进程重启以及 Android／真实服务验收。

## 检查和验收结果

产品实现提交 `71951cd`。实现期间先写 AppShell 测试，首次因缺少 `cloudCheckClock` 注入而失败；修正测试中误用 `await void` 后，首批检查与手动同步回归通过。后补场景已包含在以下最终全量结果中。

Windows Flutter 3.47.2／Dart 3.13.2，经 WSL 的 `cmd.exe /c` 实际执行：

| 命令 | 结果 |
| --- | --- |
| `dart format`（改动 Dart 文件） | 已执行 |
| `flutter test test/sync/cloud_version_check_app_test.dart test/sync/manual_cloud_sync_app_test.dart --reporter compact` | **13 passed** |
| `flutter test --reporter compact` | **315 passed**，28 秒；日志在被忽略的 `.scratch/issue71-full-test.log` |
| `flutter analyze`（含两份新增平台入口） | **No issues found** |
| `git diff --check` | 通过 |

首轮静态检查发现平台验收入口的 6 处 lint；修正私有字段初始化参数调用名称等问题后，最后一轮静态检查通过。完整测试包含既有多数据库 debug 提示，但没有失败项。夹具初始化修正另提交 `d1bf7f6`。

Windows 原生首轮构建成功，runner PID 22060。真实最小化产生 inactive/hidden、恢复产生 resumed；首轮业务指纹比较失败。诊断定位为既有国策仓储首次 `settleDueCheckpoints()` 创建维护与 `focus_sync_sources` 初始化行，并非云端检查导入。夹具改为先通过公开仓储完成初始化再捕获基线，保留完整业务指纹比较；首轮不记通过。

隔离 Supabase 已应用全部迁移，回滚式 `cloud_business_snapshots.sql` RLS/CAS 探针通过；真实 Auth/REST 验证 owner 可读、跨用户拒读、新版快照／旧 goals 只读前后摘要一致、revision 1→2 及旧数据 token 变化。Android 15 与 Windows 11 的 AppShell＋真实服务 `snapshot`、`legacy` 共四阶段现均 **1 passed**。显式元数据 select（非 `*`、不含 payload）、相同处理版本静默、revision／旧 token 变化后待处理、时间不变以及本机业务指纹／行数不变均有对应证据；隔离用户拒读已验证。详见[隔离云端验收记录](issue-71-cloud-validation.md)及[结构化结果](evidence/issue71-cloud-results.json)。清理后临时用户／快照／旧 Goal 均为 0、隔离项目 GET 返回 404；主代理独立调用 Management API 复查项目清单仅剩共享 `Pacta`，本地项目状态和运行时控制文件均不存在。

## 原生生命周期与进程验证

详细命令与失败轮次见[原生验收记录](issue-71-native-validation.md)。Windows 的 PID23132 已逐轮通过三次真实最小化／恢复，4:59 节流、5:00 失败及后续恢复符合预期；PID40656 的新进程 `cold-verify` 已通过，同一独立数据库与成功同步时间保留，启动仅增加一次检查。

Android 15/API35 的 `exercise` PID8771 已整场 **1 passed**：三轮 ADB Home／恢复后检查次数为 3，业务传输仍为初始化基线的 1；实际系统 Connectivity `wifi → none → wifi`，恢复不增加检查，业务指纹和成功时间保持一致。Android `am force-stop` 后同库新进程 PID9710 的 `cold-verify` **1 passed**，检查从3增至4、传输仍1，原 fingerprint／成功时间保留。初次 Flutter VM 连接失败经日志确认是误拾取旧 Logcat 地址；保存日志后仅清日志缓冲，默认 DDS 原命令通过，未改产品或验收入口。Windows `network-verify` PID19596 **1 passed**：真实窗口后台／前台（运行时 PID guard 生效）与系统网络 `wifi,other → other → wifi,other`，检查维持6、传输维持1，原业务指纹与成功时间不变。完整结构化结果见[原生结果](evidence/issue71-native-results.json)。

## 设计评审

采用 ui-ux-pro-max 的 Flutter 查询 `loading error retry state`：加载、错误及完成状态有明确文字，共享检查状态通过 Riverpod 连接卡片。参考 apple-design 本地 `feedback.md › Best practices` 的就地状态反馈与按重要性选择中断程度、`labels.md › Best practices` 的系统字体／语义颜色、`layout.md › Visual hierarchy` 的层级原则，转译到 Material3。只读发现与失败显示在同步卡片，不打断当前任务；真正覆盖仍走原有预览与二次确认。

主代理已目视 Windows 11 暗色原生[失败卡片](evidence/issue71-windows-failed.png)及[恢复后待处理卡片](evidence/issue71-windows-recovered.png)：状态文字完整，失败有“点击重试”和刷新图标，原有导航和业务入口保持可用。两张截图来自真实 runner PID23132 的生命周期场景。Computer Use 初始化、重试及 reset 后均因 `sandboxCwd is not a local file URI` 失败；没有声称使用该工具进行桌面鼠标点击。平台控件由 Flutter 集成 tester 驱动，窗口最小化／恢复由仅测试入口的 Win32 instrumentation 驱动。

主代理另已目视 Android 浅色[新版待处理](evidence/issue71-android-snapshot-pending.png)、[旧数据预览](evidence/issue71-android-legacy-preview.png)，以及 Windows 暗色[新版待处理](evidence/issue71-windows-snapshot-pending.png)、[旧数据预览](evidence/issue71-windows-legacy-preview.png)。状态文案清楚；未知型号／来源和原上传时间未记录的说明保留，按钮及覆盖后果完整。设备控件操作由 Flutter 集成 tester 驱动。

主代理已目视原生 Android [失败卡片](evidence/issue71-android-failed.png)及[恢复卡片](evidence/issue71-android-recovered.png)，状态可读、导航和普通业务入口可用。

## Standards

独立子代理按 `4417fb5…71951cd` 审查，0 项可确认标准违规。资源释放、异步身份／世代保护及 AppShell＋Drift 测试边界符合仓库规范；没有将已退出范围的无障碍、大字号或键盘要求带回验收。追加补审发现的测试窗口 PID 限制、临时账号创建失败清理边界均已修复，独立复核为 0 项；Dart 私有初始化参数的误判已依实际 SDK 分析结果撤回。

## Spec

另一独立子代理按同一差异审查，0 项代码需求发现。前台检查、版本识别、成功版本抑制、用户切换隔离与手动覆盖边界符合 #71；实际设备和服务完成状态单独取证。主代理已复核最终补丁、结果 JSON 和设备截图；两轴最终未解决均为 0。

## 普通构建与清理

2026-10-25 普通构建仅传原开发配置中的 `SUPABASE_URL` 与 `SUPABASE_PUBLISHABLE_KEY`；临时 JSON 只有这两个公开字段，不包含运行时控制令牌、测试身份或服务端密钥。

- `flutter build apk --debug --no-pub -t lib/main.dart --dart-define-from-file=.dart_tool/issue71-public-build.json` 通过，Gradle 27.5 秒；保留既有 `flutter_timezone` KGP 未来兼容警告，不影响本次构建。
- `flutter build windows --debug --no-pub -t lib/main.dart --dart-define-from-file=.dart_tool/issue71-public-build.json` 通过，18.4 秒。
- 对 `emulator-5556` 执行 `am force-stop` 和 `adb install -r`，输出 `Success`，恢复普通主入口 APK；未清数据、卸载或启动真实账号。两端独立验收数据库保留。
- 临时公开构建配置已删除。云项目、测试身份和控制文件已清理；native 30349／30350 端口映射已不存在。主代理复查宿主 WLAN 为 Up／IPv4 Internet，AVD Wi-Fi 已恢复。

最终 `dart format` 检查 7 个任务 Dart 文件均无需变化；`flutter analyze` 为 No issues found。完整 315 项测试对应当前未再修改的产品代码；后续改动均为平台验收入口、证据及状态文档。
