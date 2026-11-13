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
## 审查修复（2026-11-13 第二轮）

主 Agent 审查 `1937dbd` 提出四项修复，均已按 TDD 补测后修复。

1. **读取失败不再制造本机版本**：`syncProfile` 读取失败只记录错误状态（无缓存行时仅在内存返回，不写库；有行时只更新 `syncError`，不改 `updatedAt`/负载）。没有 `pendingSave` 意图时不再因时间戳比较上传，云端既有资料重试后被采用且不上传。回归：`首次读取失败不写本机版本…`、`读取失败不推进已有缓存的版本时间`。
2. **串行网络操作 + 本地编辑指纹条件提交**：新增 `local_profile_accounts.edit_sequence`（schema **28**，27→28 增加列）作为本地编辑版本；仓储内所有保存/同步经同一操作队列串行，网络结果（采用、上传成功、上传失败、读取失败）仅在 `edit_sequence` 未变时提交，晚到的旧响应被丢弃而不会覆盖较新编辑；远端不可用时的真实编辑保持 `pendingSave`，云端可用后由同步上传。回归：`后台读取等待时用户保存会排队…`、`另一入口的新编辑不被晚到的较新云端资料覆盖`、`晚到的上传失败不覆盖另一入口的新编辑`、`离线编辑在云端可用后由同步上传…`。
3. **`combineLatest2` 错误终止**：错误到来时先转发错误，再取消两路订阅并关闭输出（原实现先置 `closed` 导致 `finish` 立即返回、另一路泄漏且不关闭）。回归：`一路报错时取消两路订阅并关闭输出`（断言两路 `hasListener` 为 false 且输出 `onDone`）。
4. **keep-avatar 原子语义**：`save_profile_account` 不再先读旧头像；不带头像参数时由单条 `insert … on conflict do update` 的 `case when keep_avatar then profile_accounts.avatar_* else excluded…` 保留现有二进制，并发清空/换头像不会被昵称更新复活。RLS 与 owner 作用域不变。探针新增 `keep_after_clear` 断言（清除后仅改名不得恢复旧头像）。

### 修复后复验

| 命令 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test test/profile` | 40 项通过 |
| `dart run build_runner build` | 重新生成含 `edit_sequence` 的 g.dart（schema 28） |
| 隔离项目探针 | PASS，事务回滚，证据 `.scratch/issue90/profile-probe-20261113-183619.json` |

合并状态：integration tip `edde186` 已包含在分支中（上一轮合入的 `1937dbd`），本轮无新上游提交。
## 真实服务 fixture（仅准备，未运行）

新增 `integration_test/profile_real_service_test.dart`，由主 Agent 在 SQL 最终验证并部署到隔离项目后于两端执行。**本轮未运行，不记为通过。**

- 运行时协议沿用 #71/#92：`ISSUE71_RUNTIME_CONTROL` + `ISSUE90_RUNTIME_PORT`（默认 30390），从 loopback `/session?user=device|other` 取临时会话；客户端只持有运行时下发的 URL/publishable key/refresh token，不编译 `.env`、不含管理员密钥。
- Android phase：用真实 `save_profile_account` 保存合成 1x1 PNG 头像与昵称，随后用新的 remote 从云端读回，断言昵称、mime 与头像字节完全一致（base64 往返）。
- Windows phase：使用**独立内存缓存**（本机无资料），`syncProfile` 从云端采用 Android 保存的昵称与头像；随后改昵称并 `clearAvatar`，再从云端读回确认昵称更新、头像为空。重复运行 Windows 时会读到上一次 Windows 结果，测试按注释接受该幂等分支。
- 跨用户：以 `other` 身份调用 `read_profile_account` 不得读到 owner 昵称，直接 `select public.profile_accounts` 因无表权限被 `PostgrestException` 拒绝。
- 业务快照隔离：同一临时库内用真实 `CloudSnapshotRepository` 上传（带 `requestId`）后新增本机业务行再 `downloadCloud` 恢复，断言本机资料缓存与云端资料均未被快照恢复改写。
- 收尾：恢复该用户既有同步结果偏好键，关闭临时内存库与两个客户端；不触碰共享云、不删除隔离项目的临时身份。

建议执行命令（主 Agent 用现有 runner 传入 control 与端口；示例仅示意环境变量名）：

```
flutter test -d <android-device> integration_test/profile_real_service_test.dart \
  --dart-define=ISSUE71_RUNTIME_CONTROL=<runtime-control> \
  --dart-define=ISSUE90_RUNTIME_PORT=30390
flutter test -d windows integration_test/profile_real_service_test.dart \
  --dart-define=ISSUE71_RUNTIME_CONTROL=<runtime-control> \
  --dart-define=ISSUE90_RUNTIME_PORT=30390
```

运行顺序：先 Android 建立资料，再 Windows 采用与修改。

注意：为验证"业务快照上传/恢复不改资料"，fixture 会以 `device` 身份上传一次业务快照（revision 前进 1，历史保留 15 份），因此建议在 #92 的 snapshot history fixture 之后运行，或为该轮使用新的隔离会话；共享项目不得运行本 fixture。

## 主审修复（2026-11-13 第三轮）：PostgreSQL base64 行换行

事实链：PostgreSQL `encode(bytea, 'base64')` 每 76 个字符插入一个 LF（主 Agent 真实 SQL 已测）；Dart 3.13 的 `base64Decode('YQ==\n')` 抛 `FormatException`（padding 之后的空白不被接受）。`remoteProfileFromJson` 直接解码 RPC 返回的 `avatarBase64`，因此**任何超过一行的头像**（76 字符 ≈ 57 字节原始 PNG 以上）都会读取失败，而短头像恰好不换行掩盖了缺陷。

修复（`lib/src/profile/profile_remote.dart`）：

- 解码前只剔除 base64 允许的 ASCII 空白（HT 0x09、LF 0x0A、VT 0x0B、FF 0x0C、CR 0x0D、SP 0x20），其余字符原样交给 `base64Decode`；非法字符仍抛 `FormatException`，不静默丢弃。
- 无空白时跳过重写，保持原有开销；编码方向（`save` 的 `base64Encode`）不变，未改动已部署隔离项目的 SQL。

TDD（先红后绿，`test/profile/profile_remote_test.dart`）：

- `PostgreSQL 76 列换行的头像 base64 仍能往返解码`：67 字节有效 1x1 PNG（`\x89PNG...IEND`）编码为 92 字符、按 76 列插入 LF，断言字节与 mime 完全往返；红态报 `Invalid character (at character 77)`。
- `头像 base64 允许的 ASCII 空白都被忽略`：同一载荷穿插空格、TAB、CRLF、VT、FF 后仍解码出原字节。
- `头像 base64 含非法字符时继续拒绝`：合法 payload 追加 `!!` 后仍抛 `FormatException`。

验证：`flutter analyze` 无问题；`flutter test test/profile` 43 项通过。未改 SQL 与真实服务 fixture（仍为准备未执行）。
