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

TBD
