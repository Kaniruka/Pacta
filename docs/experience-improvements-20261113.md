# 2026-11-13 体验问题复现与验收

来源：用户在聊天中提供的 11 项体验问题截图及后续确认。基线为 `134cef306a7edad6cca32495e87278a967e2a198`，开始时工作树干净。以下“通过”只描述已实际执行的检查，不代表未执行的平台或真实云服务。

## 已确认规则

- 精锐、普通共用一个专注标志，链记录仍独立。当前测试版不新增旧用户迁移或旧值选择流程；未清设备数据。
- 单精锐任务默认精锐，单普通任务默认普通，双分类沿用上次成功模式（首次普通），仍可显式切换。预约交接保持实际选择的模式。
- 云同步突出从云更新本机，保留次级上传。只有本设备成功下载并应用云端内容，或成功上传覆盖云端使两端一致，才更新本机成功同步时间。检查、发现更新、取消、忽略、失败不更新。
- 预计时长允许选择小时或分钟；内部仍以分钟保存，切换单位保持时长。

## 逐项复现

| 项 | 修改前实际证据 | 处理与验证边界 |
| --- | --- | --- |
| 1 共享专注标志 | 实际控件分别保存精锐/普通，原独立编辑测试 3 项通过 | 共用编辑入口与值；预约信号和链记录保持独立 |
| 2 完成后只加次数不加时长 | 前台直接完成及预约交接完成均得到 1500 秒、连续 1 次；尚未复现用户症状 | 不盲改计时算法；补测后台恢复、暂停后提前完成、已有非零累计，并向用户询问原场景 |
| 3 精锐新任务默认普通 | 看板实际设置弹窗未预选精锐，目标行为测试失败 | 与旧统一上次模式规则有关，按新规则调整 |
| 4 看板任务启动默认普通 | 看板/任务选择实际点击入口均复现 | 共用默认规则，保留显式选择与已有流程恢复 |
| 5 预约后进入普通 | 预约建立时为普通，交接继续普通 | 交接本身保留模式；修正启动默认值，不改结算 |
| 6 国策强化无编辑入口 | 卡片库有入口，详情正文没有管理操作 | 详情接入现有强化管理页，返回刷新要求 |
| 7 目标收起按钮不齐 | 同一 widget 样例中心偏低 4dp，图标间距 12/24dp；Windows 运行截图亦可见 | 固定相同控制区并对齐，标题整体折叠保留 |
| 8 任务空信息留白 | 空信息行仍高 88dp，标题下空白 52dp | 空信息行收缩至 56dp，标题居中 |
| 9 云同步主操作与时间摘要 | 下载为次要按钮、上传为强调按钮，标题要求选择同步方式；正常成功时间原本正确 | 从云更新为主要操作，保留覆盖保护；补充时间语义回归 |
| 10 冗余改名入口 | 详情同时有编辑卡片/修改名称，编辑页已含名称 | 详情仅保留编辑卡片，改名功能仍可用 |
| 11 预计时长单位 | 实际编辑框仅分钟，90 保存显示 90 分钟 | 增加小时/分钟选择，验证换算、清空和非法输入 |

## 主代理独立检查

- `flutter test test/ui/experience_repro_test.dart --timeout 60s --reporter expanded`：修改前 5 项基线探针通过，捕捉上述 6/7/8/10/11 现象。
- `flutter test test/focus/experience_repro_test.dart --plain-name '看板单精锐任务默认精锐链' --timeout 60s --reporter expanded`：修改前退出 1，真实设置弹窗预选不符合新规则。
- `flutter test test/focus/experience_repro_test.dart --plain-name '看板启动专注完成后看板时长与专注链次数同时增加' --timeout 60s --reporter expanded`：退出 0，25 分钟与 1 次均增加。
- `flutter test test/sync/cloud_sync_experience_test.dart --plain-name '主操作层级' --reporter expanded`：修改前退出 1，实际出现“选择同步方式”。
- 标志卡片、信号仓储、设置页面与快照仓储四组相关测试：修改后 54 项通过。
- 同步体验、同步卡片、App 同步及云检查四组相关测试：修改后 39 项通过。

## 设备证据与限制

Windows 修改前运行：`python scripts/run_focus_pilot.py --target board --scenario default --view wide --theme light --snapshot-only --run-id experience-before-20261113`，退出 0。主代理已打开判读 `build/ui-layout-evidence/board-pilot/runs/experience-before-20261113-default-wide-light/board-default-wide-expanded.png`。

Android 15（emulator-5554）修改前试跑虽完成并生成图片，但并行修改导致 runner 判定源码漂移，manifest 为 `invalid`，不计正式验收。最终取证须等相关写入停止后重跑。

真实云服务验证入口需要隔离项目和运行时验收会话；本轮未发现默认 30347 端口的验收会话监听，尚未执行真实 Supabase 往返/RLS。不得把内存 remote 结果当成真实服务验证。本次未改数据库 schema、远端协议或 RLS。

## 最终自动化与代码复核

- 主代理 `flutter analyze`：退出 0，No issues found。
- 主代理 `flutter test --timeout 120s --reporter expanded`：最终 **377 项通过**，退出 0，日志 `.scratch/experience-20261113/full-test-final.log`。首轮两项失败来自旧模式规则的测试前提，已改为新规则：精锐任务仅断言精锐；双分类重启测试通过设置弹窗显式选择模式，筛选不再代替模式选择。修正后两个相关文件 18 项通过，再跑完整测试通过。
- `git diff --check`：通过。未提交、推送或部署。
- Standards 独立审查：发现核心规格仍要求“三个动作”的 P2 文档冲突，已改为共享 Focus Marker 与独立 Appointment Trigger Signal；复核后无未处理规范问题。
- Spec 独立审查：第 2 项保留未解决。审查提出的 `2^53-1` 上限经主代理核对属于浮点整数精度保护，不是产品时长配额；无依据的一年业务上限已在实施阶段撤回。未进行旧用户迁移符合本次明确决定。

## 设备操作与设计复核

| 运行 | 结果及证据目录（仓库相对路径） |
| --- | --- |
| Windows 11，修改后看板，同样例/视口/亮色 | runner 退出 0；`build/ui-layout-evidence/board-pilot/runs/experience-after-20261113-default-wide-light`；主代理已打开与修改前图对照 |
| Windows 11，亮色，任务编辑/精锐默认/共享标志/国策管理 | `experience_improvements_device_test.dart` 退出 0；`build/ui-layout-evidence/experience-20261113/windows-light-r3`，6 张截图 |
| Android 15 emulator-5554，暗色，同上交互 | 同一 fixture 退出 0；`build/ui-layout-evidence/experience-20261113/android-dark-r4`，6 张截图（表单取证前关闭输入法并滚动到时长字段） |
| Windows 11，云同步常驻摘要/弹层/活动流程禁下载 | `issue_69_sync_result_device_test.dart`，`ISSUE69_PHASE=ui79`，退出 0；`build/ui-layout-evidence/experience-20261113/windows-sync` |
| Android 15，同步摘要/弹层/活动流程禁下载 | 同一 ui79 fixture 退出 0；`build/ui-layout-evidence/experience-20261113/android-sync` |
| Windows 11 / Android 15，实际点击上传、修改本地、再下载还原 | `flutter test integration_test/manual_cloud_sync_device_test.dart -d windows` / `-d emulator-5554` 均退出 0；使用本机真实 Drift 和内存 cloud remote，不是远端 Supabase |
| Android 15，真实一分钟计时，中途切后台再返回 | `flutter test integration_test/focus_elapsed_device_test.dart -d emulator-5554 --reporter expanded` 最终退出 0，实际 `effectiveSeconds=59`、连续 1 次，看板与链卡累计均非零 |

每次目录独立，保留 `run.log`（stdout/stderr）与 `run.rc`，不覆盖早期失败记录。组合设备 fixture 的早期失败分别来自错误地要求弹层下看板文字不存在，以及懒加载列表未滚动到待断言内容；已修复 fixture，未为这些失败修改应用行为。截图为实际运行 App 的 Flutter 画面，不包含系统输入法或系统弹窗的完整画面；不以此声称完成独立 IME/原生权限验收。

设计复核适用 Android/Windows Flutter 原则，遵从 ADR 0007/0008 范围：

- `apple-design/references/hig/layout.md` 的 Visual hierarchy："Align elements to make them easier to scan"。目标图标按相同控制区对齐；空信息任务不再保留三行槽位。
- `entering-data.md` 的 Best practices："offer choices instead of requiring text entry"。小时/分钟可选，单位切换保持数值意义，非法输入有明确反馈。
- `buttons.md` 的 Style：主操作使用强调样式。同步弹层强调“从云端更新”，上传保留次级入口，覆盖后果仍可见。
- 已打开判读 Windows 与 Android 的看板、时长表单、精锐设置、共享标志、强化管理、详情刷新、同步正常及禁下载截图；沿用现有语义主题。窄屏长表单与强化管理使用滚动访问；Android 时长表单另取关闭输入法后的完整状态，不把未滚动到的内容误判为功能不存在。

## 尚未解决

持续跟踪：[Issue #88](https://github.com/Kaniruka/Pacta/issues/88)。本轮 PR 不关闭该问题。

用户后续确认：正常使用手机、Pacta 处于后台；专注链卡片次数增加，但**累计与平均时长**未增加，观察对象不是看板任务进度。用户明确要求：复现不了不影响其他 bug 修复与功能需求，不因此阻塞交付。因此本项改为**非阻塞待复现**，其余 10 项按已完成验证交付；本轮关闭不代表本项已修复。此前继续轮 3 的 blocked 状态只记录当时的信息缺口，现被本次用户决定替代。

第 2 项“完成专注后只加次数、不加时长”未复现。已验证前台直接完成、预约交接后完成、App 生命周期后台→前台结算、暂停后按规则提前完成，以及已有非零累计后再次完成；看板与链卡累计均正确。后续若继续定位，应优先覆盖真实手机后台运行时专注链卡片的连续次数、累计与平均三项，而不是继续泛测任务进度或默认锁屏场景。设备型号、原应用版本、会话时长和是否发生进程回收仍未知，但不作为本轮交付前置条件。未改计时算法，也未宣称该项已修复。

额外真实计时：无注入时钟，在 Android 看板实际启动 1 分钟，主机 ADB HOME 切后台、`am start` 将现有任务带回前台。第二轮后台时间为北京时间 03:07:50–03:08:46（约 55 秒），结果为 59 秒、1 次；看板与链卡均显示非零时长。第一轮在后台到期后返回，严格 60 秒断言得到实际 59 秒而失败，保留 `.scratch/experience-20261113/android-real-focus.log`；第二轮探针以 59–60 秒精度范围核对非零累计与记录/UI 一致，日志 `android-real-focus-r2.log` 和 `android-real-focus-host-r2.log`。这不能证明秒级精度没有差异，也不能替代真实锁屏、进程被杀或用户原始场景；本轮不据此修改生产计时算法。

继续轮补充（03:11–03:13）：复用同一真实时钟设备探针，在 `FOCUS_REAL_STARTED` 后通过 `KEYCODE_SLEEP` 熄屏，`dumpsys power` 确认 `mWakefulness=Dozing`；03:11:47 熄屏，03:12:43 唤醒并解除锁屏。测试退出 0，仍为 59 秒、连续 1 次，看板与链卡累计非零。日志为 `android-real-focus-lock.log` 和 `android-real-focus-lock-host.log`。这补充了当前 Android 15 模拟器锁屏证据，但不覆盖真机厂商杀后台或进程终止，仍未复现用户原始症状。没有新增生产代码改动。

## 流程复盘

- 复现测试的 `finally` 先卸载控件树，再关闭仓储/Drift；本轮修正了失败断言后仍挂载导致清理挂起的问题。新 fixture 已包含这个顺序。
- 先完成有界的相关测试，生产写入停止后再集中跑全套和设备截图。并行修改导致的无效取证与中止测试保留记录，不计通过。
- 仓库未发现 `.github/workflows` 或已跟踪的 pre-commit 自动检查入口；本轮手工执行的 analyze/test 未来可接入 CI。此为环境改进候选，本次未扩展部署/CI 配置。
