# #94 个人资料与名片统计 — 实施记录

状态：实施完成并已提交分支；真实云隔离与两端设备目视验收由主 Agent 协调，未在本文件预先声明通过。

分支 `impl/pacta94-profile-stats`，基线 `b11f426`（本地 integration ref `feat/sync-profile-cards-20261113`）。规格 `docs/spec-sync-profile-cards-20261113.md`、本票 `docs/tickets-sync-profile-cards-20261113/04.md`。

## 关键决定

- 账号资料独立存储：新增 `public.profile_accounts`（昵称 + 一张受限头像二进制）与两个 owner-scoped RPC；不做公共头像 URL、不引入对象存储桶，避免公共读泄漏。RLS 已启用且表不授予 `authenticated` 直接权限。
- 头像限制：客户端按系统选择器单图读取，识别 PNG/JPEG 文件头，重编码为 PNG 并把最长边压到 384 px，存储上限 256 KB；服务端再次校验 base64、大小（≤262144 字节）与文件头，尺寸/格式错误直接拒绝。
- 生命周期清除沿用 Auth 身份删除的 `on delete cascade`：**不替换** `admin_delete_user_business_data()`，避免覆盖 #92 迁移对历史备份与上传请求台账的清理；#92 的函数扩展与资料删除可组合。客户端 `purgeUserDataForReceipt` 同步删除本机资料缓存与头像字节。
- 业务快照隔离：资料缓存使用独立 Drift 表 `local_profile_accounts`，不在 `CloudSnapshotRepository._businessTables` 中；`test/profile/profile_snapshot_isolation_test.dart` 断言快照负载不含该表、恢复后资料不变。
- 统计口径复用现有投影：点亮=树中未删除且 `lit`；已内化=所有未删除卡片 `isInternalized`（复用 `successfulDays >= 180`，不改公式、不改历史成功日）；完成次数=已接受 `completed`；累计有效时间复用 `focusStatisticsByMode`（含已接受失败记录的有效区间，不含暂停/排除/待核对区间）。
- 界面复用现有 `pactaTheme`、Material 3 组件与 MiSans，未新建主题或颜色；统计组为可点击区域（最小 64 dp 高，语义按钮标签），进入二级明细页。
- 主题函数由 `_pactaTheme` 改为公开的 `pactaTheme`，仅供离线布局 fixture 使用同一主题，未改变视觉。

## 变更文件

新增：`lib/src/profile/`（`avatar_image.dart`、`avatar_picker.dart`、`profile_models.dart`、`profile_remote.dart`、`profile_repository.dart`、`profile_statistics.dart`、`profile_overview.dart`、`profile_format.dart`、`profile_card.dart`、`profile_edit_page.dart`、`profile_statistics_pages.dart`）、`supabase/migrations/202611130002_profile_account.sql`、`supabase/tests/profile_accounts.sql`、`integration_test/profile_card_device_test.dart`、`test/profile/*`。

修改：`lib/src/tasks/task_database.dart`（新增缓存表、schema 26、迁移与本地清除）、`lib/main.dart`（资料 provider、名片接线、主题公开）、`android/.../MainActivity.kt` 与 `windows/runner/flutter_window.{h,cpp}`（系统单图选择通道 `com.pacta/profile_avatar`）、`docs/agents/ui.md`、`supabase/README.md`。

## 已验证的命令与结果

（本节只记录实际执行结果；未执行项见下方"未完成验收"。）

### 分析与测试

| 命令 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found（合入 integration tip 后复跑） |
| `flutter test test/profile` | 34 项通过 |
| `flutter test`（合入后完整） | 481 项通过 |
| `dart run build_runner build` | 生成 schema 27 的 `task_database.g.dart`（含 `local_profile_accounts` 与 `local_cloud_recovery_points`） |

覆盖边界：179/180/365 天与已内化封顶、显示四舍五入不提前计为已内化（复用现有模型断言）、树/库/已删除卡片区分、待确认不算点亮、已完成 vs 失败记录的次数与有效时间区分、待核对/排除区间排除、空记录全 0、离线缓存与跨设备采用、账号写入失败重试、清除回执删除本机资料、业务快照恢复不改资料。

### 平台编译与离线布局 fixture

| 命令 | 结果 |
| --- | --- |
| `flutter build apk --debug` | 成功（exit 0），验证 `MainActivity.kt` 的 `com.pacta/profile_avatar` 通道可编译 |
| `flutter build windows --debug` | 成功（exit 0），验证 `flutter_window.cpp` COM 选择器与 `ole32/uuid` 链接 |
| `flutter test -d windows integration_test/profile_card_device_test.dart --dart-define=PROFILE_PILOT_DIR=issue-94/windows-dark` | 通过，输出名片/国策明细/专注明细/编辑 4 张深色图 |
| 同上 `PROFILE_PILOT_LIGHT=true`、`DIR=issue-94/windows-light` | 通过，输出 4 张浅色图 |
| 合入 integration tip 后复跑深色 fixture（`issue-94/windows-dark-merged`） | 通过，确认合并后仍可构建与截图 |

截图目录 `build/ui-layout-evidence/issue-94/<run>/<name>.png`（构建产物目录，未纳入版本库）。Windows 首次构建时 CMake 经网络下载 sqlite3 源码极慢，用本机已有缓存 tarball 预置 `build/windows/x64/_deps/...` 后才完成；该预置只影响本机构建缓存，未提交任何构建产物。

Android 命令（由主 Agent 在模拟器执行）：`flutter drive --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/profile_card_device_test.dart`，驱动沿用现有 `test_driver/ui_layout_acceptance_test.dart`，截图名同上，不带后缀。

### 真实云隔离项目（事务回滚）

| 命令 | 结果 |
| --- | --- |
| `python F:/Workspace/Release/Flutter/Pacta/.scratch/issue90/probe_profile.py --source ...` | PASS；`applied=false`，事务回滚，临时 SQL 探针身份已清理；证据 `.scratch/issue90/profile-probe-20261113-182814.json`（不含凭据） |

该脚本在固定隔离项目（已部署 #92）上以事务方式应用本迁移与 `supabase/tests/profile_accounts.sql`，验证：空账号返回 null、昵称去空白、PNG 头识别与 base64 往返、>262144 字节与非图片拒绝、无头像参数保留旧头像、显式清除、`authenticated` 无直接表权限、跨用户读隔离与写入不串号、临时授权后 RLS 只暴露本人行、以及资料表到 `auth.users` 的 `on delete cascade` 接线。未删除隔离项目中供两端测试使用的 device/other/legacy 身份。

### 合并 integration tip

- 合并 `feat/sync-profile-cards-20261113`（含 #91/#92/#95 已合入内容）。冲突文件：`lib/src/tasks/task_database.dart`、`task_database.g.dart`、`supabase/README.md`。
- Drift：保留 #92 的 `local_cloud_recovery_points` 与本地清除、身份清单 UNION；资料缓存迁移改为 **schema 27**（`from < 26` 建恢复点表，`from < 27` 建资料表），g.dart 由 build_runner 重新生成，未整文件选边。
- README 同时保留 #92 的历史备份段与本票资料段，按 202611130001 → 202611130002 排序。
- 平台通道保持独立：`com.pacta/profile_avatar` 使用独立 channel 与独立成员（`profile_avatar_channel_` / `profileAvatarChannelName`），不与 #95 的提醒通道合并或改名。
- 迁移未替换 `admin_delete_user_business_data()`，因此 #92 对该函数的历史表/台账清理保持不变；资料清理由 FK cascade 承担。
## 未完成验收（交主 Agent）

- Android 模拟器/实机：运行 fixture 或真实 AppShell 取名片、明细、编辑四张图，验证窄宽、亮暗、触摸与系统图片选择器；本轮未在 Android 设备上运行。
- 真实云：资料跨设备一致、头像上传/清除、失败重试的端到端证据；本票只完成隔离项目的事务回滚探针。
- 独立复跑：主 Agent 应按本文件命令重跑 analyze/test、两端 fixture 与云探针后再判定验收。
- 未推送、未部署、未关闭 Issue。
