# Issue #72 实施与验收

日期：2026-10-25（Asia/Shanghai）。票据：[T09: 云版本选择提醒、忽略与专注期间延迟](https://github.com/Kaniruka/Pacta/issues/72)。开始工作区干净，当前分支 `master`；实现比较基点 `21d58f2d8a410068c48e6537eb080627d7408b14`。

## 范围与测试边界

沿用专题规格 Testing Decisions：真实 AppShell、真实本地仓储和 Drift，替换外部认证、时钟和云 remote；从可见提示、操作、业务内容及持久化状态验证。真实设备重启和隔离 Supabase 独立留证，不用 widget 重建代替进程重启。ADR 0007/0008 的已确认范围继续有效。

读取 GitHub Issue 正文、评论（无评论）及标签，初始标签 `ready-for-agent`；入向和出向 GitHub 阻塞关系均为空。WSL 无 `gh`，实际通过 Windows `cmd.exe /c gh` 获取。当前设备列表包含 Android 15/API35 的 `emulator-5556` 与 Windows 11，设备可见不代表验收完成。

## 实施进度

- 主代理负责范围、协调、复核及交付；产品实现与 App 级 TDD、原生持久化/流程验收、隔离 Supabase 验收分别推进。
- #71 已有按 revision/旧数据 token 的只读检查、成功同步基线和五分钟前台节流；#72 补充选择提醒、按本机用户持久化忽略，以及活动流程期间非阻断提示与结束后的最新版本提示。
- 产品实现、原生四阶段、双端隔离服务验收及最终全量检查均已完成；实际证据如下。
- 首条 App 测试先要求较旧云快照自动出现完整选择弹层，原代码失败、实现后通过。随后覆盖关闭、按用户忽略、下载保留设备标记、预约/专注/暂停延迟，以及用户切换时移除旧身份弹层。
- 主代理复核发现活动计时每秒保存的本机检查点导致上传预览指纹过期。仅将既有 Focus 云序列化已排除的两个本机计时检查点从指纹比较标准化，不删除 payload 字段，不放宽真实业务变更的重新预览保护；单独保留 red→green 证据。

## 自动化与评审

实现提交 `fd2e729`，评审修复提交 `4f5cdad`、`d8bdc7d`。相关命令 `flutter test test/sync/cloud_version_check_app_test.dart test/sync/cloud_snapshot_repository_test.dart test/sync/manual_cloud_sync_app_test.dart` 最后 **48 passed**：19 项 App 提醒、24 项快照、5 项手动同步。实际计时检查点变化仍允许活动上传，暂停后的实质变化仍拒绝过期预览；历史无 `v2:` 的本地指纹基线显示未知。

### Standards

独立子代理针对基点至 `fd2e729` 的差异审查，0 项确认规范违规或需要报告的可维护性问题。身份分区、资源释放、隔离项目保护及既定测试边界均已检查；没有重新引入已退出范围的验收条件。补审新增云验收 runner 时发现缺少 `--no-uninstall` 和异常子进程／设备设置恢复保护；已在实际业务验收前修复并独立复核，未解决项 0。

### Spec

另一独立子代理发现并推动修复 2 项 P2。第一项：手动预览打开期间流程结束，重新检查的新版因操作忙碌未显示，关闭旧预览后不会立即评估。已先以 App 测试真实复现，再于操作结束下一帧重新评估尚未展示的检查；测试同时验证新版弹层再次取消不会立即重弹。第二项：真实预约取消页面等待通知清理时，自动云弹层可能先出现，旧页面随后通用 `pop` 会误关新弹层；以可挂起外部通知的真实 UI 操作测试复现，再改为只退出捕获的预约页面 route。独立复核确认两项原问题均解决，无新增问题，未解决项 0。


## 设计评审

使用 ui-ux-pro-max Flutter 查询 `state async`，采用加载/失败状态清晰和共享状态管理指导，沿用现有 Material3 主题。apple-design 本地 `modality.md › Best practices` 要求有明确取消入口、仅在帮助用户选择时使用模态；`alerts.md › Buttons` 要求动作标题简短具体；`color.md › System colors` 指导使用语义颜色。转译为 Android 底部弹窗与 Windows 限宽对话框，不引入 Apple 专属控件或超出 ADR 0007/0008 的专项要求。

主代理已目视真实 Windows 宽窗口、640×720 外框窄窗口、Android 横屏及竖屏暗色截图：文字、来源、覆盖和未知基线说明完整，忽略/取消/上传/下载可见；进行中流程只有非阻断提示，结束提示明确为最新 revision 5。完整截图和实际进程证据见 [原生验收](issue-72-native-validation.md)。Android 浅色与真实系统返回由隔离云入口补充。


## 最终验证结果

Windows Flutter 3.47.2 / Dart 3.13.2，经 WSL `cmd.exe /c` 实际执行：

| 命令／边界 | 结果 |
| --- | --- |
| `dart format`（8个任务Dart文件） | 已执行；最后仅补齐7处 lint 要求的花括号，不改行为 |
| `flutter analyze` | **No issues found**，2.4秒 |
| `flutter test --reporter compact` | **327 passed**，38秒；日志 `.scratch/issue72/final-full-test.log` |
| `git diff --check` | 通过 |
| Android15 / Windows11 原生 `exercise` + `restart-verify` | 四阶段各 **1 passed**，真实新PID与生命周期，见[原生证据](issue-72-native-validation.md) |
| Android15 / Windows11 + 隔离Supabase | 两端各 **1 passed**，各含 snapshot/legacy；真实系统返回、第二认证客户端上传与旧 token，见[服务证据](issue-72-cloud-validation.md) |

第一轮最终 analyze 发现7处 curly-brace lint，修正后重新format、analyze通过，再运行上述一次完整测试。没有把 lint 或夹具失败轮次记为通过。隔离项目及临时身份已清理，主代理复核删除；普通平台构建成功，Android普通APK保留数据安装成功，恢复设备身份变更的限制已在服务记录注明。


## 远端收尾

2026-10-25 代码及验收材料已推送 `origin/master`，验收提交 `bc49a26`。GitHub #72 六条验收项均已勾选，状态为 `CLOSED / completed`，标签为空；原生入向和出向阻塞均为空，保留与规格 #63 的父子关系。对应本地票据及 publication 映射同步更新。
