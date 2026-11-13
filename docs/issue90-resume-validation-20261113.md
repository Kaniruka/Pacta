# #90 / PR #96 接续验收（2026-11-13）

本记录接续 `issue90-interruption-20261113.md` 顶部最新停点；旧实施记录中的“尚未合入”“真实云未运行”等均为当时状态，不代表当前状态。**2026-11-14 02:01，最后的 Windows 原生通知点击与窗口恢复验收通过，已达到 PR 转 ready 条件。** 未授权合并 master 或部署共享云。

## 最终收口（2026-11-14）

- 真实 Windows 验收：`build/ui-layout-evidence/issue90/reminder-native-windows-20261114-015938`，`run.rc=0`。用户手动最小化和点击系统提醒，Agent 无桌面输入。02:00:12 收到 hidden；02:01:01 收到 inactive、resumed 和真实通知回调；02:01:03 的 `ISSUE95_NATIVE_ROUTE index=0` 在注入之前；其后才执行既有路由注入检查、关闭清理和偏好恢复。manifest 已按事件顺序核实标记 `nativeTap=true`。
- 前一轮 `reminder-native-windows-20261114-015441` 也证明真实点击与注入前看板 index=0，但未记录 hidden/resumed，未计为完整通过；用户确认已最小化，因此修正探针观测后重测，没有降低断言。
- 测试探针提交 `4fbefdc`：记录 arm 前后生命周期；开始时读取真实当前状态，避免丢弃提前最小化；原生点击后最多等 5 秒，让真实平台恢复事件到达。原生点击、后台后恢复、注入前看板三项断言全部保留，不合成生命周期状态、不改变生产逻辑。
- `dart format integration_test/issue_95_daily_reminder_device_test.dart` 完成；`flutter analyze` 无问题（`.scratch/issue90/reminder-lifecycle-analyze.log`）；`flutter test test/notifications` 57 通过（`reminder-lifecycle-tests.log`）。生产代码仍对应此前 605 项完整测试，不因测试探针小改重复全量运行。
- 独立 Standards / Spec 对 `8c05f74...4fbefdc` 复核均无发现，报告 `.scratch/issue90/final-native-{standards,spec}-review.md`。同步视觉结论沿用四组已判读的新图；本轮无视觉或生产代码变更。
- 临时项目 `Pacta issue90 disposable validation` 已于 02:02 删除，管理 API 读回 404 确认不存在，项目状态与运行时控制文件已移除；证据 `.scratch/issue90/cleanup-final.json`。删除前按实时名称及共享配置 URL 双重核验，共享 Pacta 项目未改。
- 测试进程已退出，30390 无监听。当前聊天没有可归档的 managed-worktree 附件；旧同步工作树仍有未提交变更，因此保留所有旧工作树及证据，不强制移除、不丢弃改动。此保留不影响 PR 评审。

## 本轮代码与复核

- 基点 `d516d60`；同步分层提交 `aac19b7`。保留原工作树改动，标题改为“数据同步”，操作面板保留来源、下载、上传、自动上传及历史；元数据、旧版说明、覆盖后果和同步基线移到方向确认。
- 取消确认不传输、不取消已有自动队列。原仓储的 CAS、指纹、旧数据、活动流程与账号隔离保护、忽略语义继续保留。
- `dart format` 已执行；`flutter analyze` 无问题（`.scratch/issue90/disclosure-analyze-final.log`）；`flutter test test/sync` 162 通过（`disclosure-sync-green.log`）；主 Agent `flutter test` 605 通过（`resume-full-tests.log`）。
- 固定 `git diff d516d60...aac19b7` 的独立 Standards / Spec 审查均无发现，分别见 `.scratch/issue90/resume-standards.md`、`resume-spec.md`。主 Agent复核确认入口与仓储调用未绕过保护。
- C 盘曾仅剩约 15 MB，一次源码写入截断；原测试文件保留，差异备份到 F 盘，源文件依据已读差异重建，经分析、162 项同步及 605 项完整测试后提交，并复制回原 C 盘工作树。测试临时文件改用 F 盘。缓存删除被自动审批拒绝，未绕过；此后 C 盘可用空间由外部操作恢复。

## 已有证据复核

下列证据均已读取日志/结果文件，不重复执行已完成内化公式或真实云测试：

| 范围 | 证据与结果 |
| --- | --- |
| 历史备份 SQL / RLS | `.scratch/issue90/history-probe-20261113-175430.json`：passed / applied；真实历史恢复 Android、Windows 运行均通过 |
| 资料 SQL / RLS | `.scratch/issue90/profile-probe-20261113-185023.json`：passed / applied |
| 真实资料跨端 | `build/ui-layout-evidence/issue90/profile-real-{android,windows}-resume`：两端 run.rc=0 |
| 真实自动上传 | `auto-real-{android,windows}-resume`：两端 run.rc=0；丢应答重试去重、新意图与其他设备版本阻断 |
| Android 原生提醒 | `reminder-native-click-20261113-210638`：run.rc=0，manifest nativeTap=true；真实点击在注入之前验证看板与生命周期 |
| Android 原生图片 / 日历 | `avatar-native-android`、`calendar-{granted,denied}-native`：run.rc=0；日历权限已恢复初始拒绝状态 |
| Windows 原生图片 | `avatar-native-windows-20261113-retry2`：真实系统单图选择合成 PNG，`PICKER_SELECTED bytes=226 mime=image/png`，PASS，run.rc=0 |

Windows 图片首轮 `avatar-native-windows-20261113-resume` 选图与图片处理成功，但无障碍树读取触发 Flutter 测试结束时的 SemanticsHandle 检查失败；第二轮只用截图操作后完整通过，不把首轮算作通过。

## Windows 原生提醒验收历史（已于上方最终收口完成）

本轮 `reminder-native-windows-20261113-resume` 排程到本机 22:15，应用已最小化。到点后系统 `SHQueryUserNotificationState` 返回 2（BUSY），未观察到可点击通知。fixture 因真实点击超时失败，打印 `ISSUE95_PREFERENCES_RESTORED`。没有注入回调冒充点击，没有改系统通知/隐私设置。已请求用户桌面空闲时再补测。

22:53 用户要求继续后再测，目录 `reminder-native-windows-20261113-225334`。开跑前系统返回 5（ACCEPTS），22:54:18 进入真实点击等待，目标为 22:56。主 Agent 最小化测试窗口后，到点再查已变成 2（BUSY）；把已有普通资源管理器窗口置前仍返回 2，未观察到通知。22:58:19 fixture 超时失败（run.rc=1），确认 `ISSUE95_PREFERENCES_RESTORED`，测试进程已退出。此轮未改代码或系统设置，不能计作原生点击通过。后续需要桌面在排程、最小化及到点期间持续可接收通知；仅开跑时一次 ACCEPTS 不足以证明环境就绪。

23:00 再次接续，改用 `.scratch/issue90/run_windows_reminder.py` 每秒记录通知环境，目录 `reminder-native-windows-20261113-230051`。`notification-state.jsonl` 证明开跑、构建、Pacta 前台截图观察期间均为 5；23:01:54 工具点击最小化后立即变为 2，并持续到 23:03 提醒到点及测试结束。将普通资源管理器置前、重置 JavaScript 自动化会话均未使状态恢复。23:05:44 fixture 因没有真实点击失败（run.rc=1），偏好已恢复，测试进程退出。

这次明确了状态改变的时点，但尚不足以证明自动化输入层就是原因。[微软定义](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ne-shellapi-query_user_notification_state)中 BUSY 表示全屏应用或演示设置状态，不能仅从该返回值断言具体应用。下一轮改由用户手动最小化测试窗口、点击原生通知，Agent 只读监测，以排除自动化输入的影响；已向用户发出协助请求，未再次启动依赖人工操作的运行。业务代码、Windows 通知设置和共享云均未改；PR 仍 draft。

## 最终视觉验收

同一 `sync_profile_overview_device_test.dart` 覆盖名片、同步操作、上传与下载确认、历史、恢复确认及取消后的数据保持。命令使用 `.scratch/issue90/run_ui.py <device> integration_test/sync_profile_overview_device_test.dart <label>`；以下运行均记录 `exitCode=0`、`sourceUnchanged=true`：

| 平台与主题 | `build/ui-layout-evidence/issue90/` 下的运行目录 |
| --- | --- |
| Windows 深色宽窗口 | `20261113-221801-sync-final-windows-dark` |
| Windows 亮色宽窗口 | `20261113-222538-sync-final-windows-light` |
| Android 亮色 | `20261113-222227-sync-final-android-light-unpaused` |
| Android 深色 320 逻辑像素 | `20261113-222407-sync-final-android-dark320` |

Android 后两次增加 `--no-start-paused`；深色增加 `--dart-define=SYNC_PROFILE_DARK_THEME=true`，实际 density=540，finally 恢复 physical density=420。原生 `native-state.png`、`native-window.txt` 与窄屏 `native-density.txt` 补充系统侧证据。新图已交独立 apple-design 复核，最终报告见 `design-review-issue90-final.md`。

深色 320 运行的 `cloud-history.png` 抓到了关闭操作面板时的过渡残影和测试指针，不用作视觉通过依据；同次运行 `history-after-cancel.png` 是相同数据的稳定历史页面，已由主 Agent 与设计复核 Agent 目视检查。其余方向确认及原生上传确认无该遮罩。

### 启动 ANR 诊断边界

第一轮 `20261113-221709-sync-final-android-light` 和独立重跑 `20261113-222011-sync-final-android-light-recheck` 虽 Flutter 测试返回 0，但原生窗口有 ANR 弹窗，因此不作为最终视觉通过证据。保留第一轮 `native-state.png` 与 `.scratch/issue90/android-anr-dump.txt`；两次均是启动焦点事件超时，伴随高 CPU/内存压力，未发现指向应用初始化锁的明确栈。

Flutter 本机源码 `packages/flutter_tools/lib/src/commands/drive.dart` 的 `startPausedDefault=true`，运行日志也确认等待驱动时 isolate 暂停。仅增加 `--no-start-paused` 后亮色、深色窄屏均通过且原生画面正常，未改业务代码；这支持调试启动等待是诱因，但不声称穷尽所有资源压力原因。深色运行后的 `anr-index-after.txt` 最新 ANR 仍是设备 UTC 14:20:59，早于两次 unpaused 运行；`density-restored.txt` 确认恢复完成。未来验收仍须检查原生系统画面，Flutter 通过日志本身不足以排除遮罩。

## 2026-11-13 的保留与清理边界（后续清理见最终收口）

- 所有 Android 命令使用 emulator-5556，未操作实体设备；截图命令含 `--keep-app-running`，原生 test 含 `--no-uninstall`，未卸载或清应用数据。
- loopback 30390 检查无监听，本轮未启动真实云会话服务。隔离云项目及原工作树保留到验收收口；共享项目未部署。
- 已停止本轮 Windows 测试进程和 Android 测试应用，未卸载或删除数据；主检出曾显示的 issue69 fixture `M` 经字节/hash核对与 HEAD 一致，刷新索引后无源码差异。
- 当前阻塞不要求重新确认任何产品需求。
