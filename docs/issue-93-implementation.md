# #93 今日确认后自动上传 — 实施记录

状态：实施完成，本地客户端验证通过；真实云与两端设备验收由主 Agent 执行。
分支：`impl/pacta93-auto-upload`（基线 `1fb1851`，来自 `feat/sync-profile-cards-20261113`，已含 #91/#92）。
依据：[票据](tickets-sync-profile-cards-20261113/03.md)、[规格](spec-sync-profile-cards-20261113.md)、
[需求确认](requirements-sync-profile-cards-20261113.md)、[ADR 0005 补充](adr/0005-manual-whole-data-cloud-sync.md)、
[#92 实施记录](issue-92-implementation.md)中的上传请求幂等契约。

## 范围与决策

- 开关：本机当前用户偏好，默认关闭（SharedPreferences，键 `pacta.device.cloud_auto_upload.enabled.<userId>`）。
  只出现在同步操作面板；卡片常驻摘要仍只显示上次成功同步时间。
- 触发：仅“今日确认成功”。单点确认立即排一次；批量（含逐项例外）在整批结束时只排一次；
  部分成功（例外面板被关闭、批处理中途报错）也为已成功变更排一次；点亮、熄灭、普通编辑不触发。
- 队列：每用户只保留一条合并意图，加上至多一条“已发出但结果未知”的请求。
  意图不保存载荷副本，执行时才捕获最新本机快照（不排队陈旧副本）。
- 请求身份：真正发送前先把 requestId、期望 revision、载荷指纹与**冻结载荷**落盘。
  重试先用同一 requestId + 同一载荷向服务端确认原始结果（#92 台账返回该请求原本写入的 revision），
  确认后才为更新的意图生成新 requestId；同一 requestId 绝不复用于不同载荷。响应丢失重试不重复落档。
  冻结载荷是本票对 #92 唯一的上传接口扩展（`uploadLocal(captured:)`），因为要重发“完全相同的内容”
  才能保住请求身份。
- 版本边界：只有 `cloud.revision == 上次成功同步基线的 revision` 才允许自动上传。
  首次遇到既有云快照、其他设备写入新版本、恢复旧版本之后都不自动覆盖；忽略提示不构成授权。
  上传成功后用**返回值**的 revision 更新基线并清掉本机待提示版本；不加设备来源比对（
  来源仍是本设备也不等于本机已处理最新版本）。不做自动下载。
- 恢复边界：
  - 云端历史恢复沿用 #92 语义：基线写入“被恢复的 revision”，因此最新云版本仍显示为待处理，自动上传停止。
  - 本机恢复点找回会把本机换成更早的内容，原来的“已处理版本 + 指纹”基线不再能证明当前本机数据与云端一致，
    因此在替换前清除基线（清除失败则不替换）。之后任何新确认都会先要求用户核对云端。
  - 两个恢复入口（云端历史、本机恢复点）都在替换前取消自动上传队列，菜单/卡片下载前同样取消，
    避免恢复结果被静默自动上传回云端。
- 取消：关闭开关、恢复备份、手动上传/下载、切换账号都会取消旧请求。切换账号由 AppShell 监听当前用户变化，
  清除上一用户的持久队列；协调器在每次 await 后比较取消代次，命中即停止后续步骤，不写回新状态。
- 生命周期/登录：只在上传前用与云版本检查相同的 `canAccess`/`isAccessible` 判定（当前用户 + 停用状态），
  不可访问时保留队列不上传；联网、回到前台、登录或停用解除后重试最新本机快照。
- 存储：复用 SharedPreferences（#92 已用于同步结果与忽略状态），**不新增 Drift 表或迁移**；
  服务端复用 #92 的 `p_request_id` 台账，无需新迁移（后续服务端变更如需迁移使用 `202611130003` 前缀）。
- 历史页（同文件既有缺口）：云端备份与本机恢复点改为独立加载、独立错误与独立重试；
  云端离线时仍可查看并找回已有本机恢复点，找回仍会先取消自动上传队列。

## 变更清单

| 变更 | 文件 |
| --- | --- |
| 开关偏好（默认关闭、按用户） | [cloud_auto_upload_preference.dart](../lib/src/sync/cloud_auto_upload_preference.dart) |
| 持久队列、请求身份与冻结载荷 | [cloud_auto_upload_queue.dart](../lib/src/sync/cloud_auto_upload_queue.dart) |
| 自动上传协调器（触发、合并、重试、冲突、取消） | [cloud_auto_upload.dart](../lib/src/sync/cloud_auto_upload.dart) |
| 分类上传错误 + 冻结快照重试 + 载荷指纹 | [cloud_snapshot_repository.dart](../lib/src/sync/cloud_snapshot_repository.dart) |
| 基线清除（本机恢复点找回） | [cloud_sync_result.dart](../lib/src/sync/cloud_sync_result.dart) |
| 操作层开关、取消钩子、停止提示 | [cloud_sync_card.dart](../lib/src/sync/cloud_sync_card.dart) |
| 云端/本机恢复点独立加载与错误 | [cloud_snapshot_history_page.dart](../lib/src/sync/cloud_snapshot_history_page.dart) |
| 今日确认回调（单点/批量/部分成功） | [national_focus_tree_page.dart](../lib/src/national_focus/national_focus_tree_page.dart) |
| AppShell 认证/网络/生命周期接线、账号切换清理 | [main.dart](../lib/main.dart) |

## 对后续实现的最小契约

1. `CloudAutoUploadCoordinator`（每用户一个，随 Provider 生命周期 dispose）：
   - `enqueue()`：今日确认成功后排一次（关闭时什么都不做）；`trigger()`：联网/前台/登录/生命周期恢复后重试；
   - `setEnabled(bool)`：写入本机偏好，关闭时取消队列；`cancelPending()`：恢复与手动同步前调用；
   - `blockedReason`：非空表示已停止自动上传，需要用户核对云端（未处理版本、PT422、PT425）。
2. `CloudSnapshotRepository.uploadLocal(expectedRevision:, expectedFingerprint:, requestId:, captured:)`
   —— `captured` 是发起请求时保存的快照；指纹不一致仍然拒绝。
3. `fingerprintOfPayload(payload)` 与 `CloudSnapshotLocalState.fingerprint` 同口径，用于校验冻结载荷。
4. 上传错误类型：`CloudUploadRequestConflict`（PT422）、`CloudUploadRequestEvicted`（PT425）、
   `CloudUploadRevisionChanged`（PT409），都是 `StateError` 子类，保留原有文案。
5. `CloudSyncResultStore.clear(userId)`：清除“已处理云版本”基线。
6. `CloudSnapshotHistoryPage.onCancelPendingUpload`：恢复前取消队列。

## 实际执行的命令与结果

环境：Windows 11；DSH 工具 shell 为 MSYS bash；Flutter 3.47.2 / Dart 3.13.2。

```text
dart format <改动文件>                                   -> 完成
flutter analyze                                          -> No issues found!
flutter test test/sync/cloud_auto_upload_queue_test.dart -> +5  All tests passed!
flutter test test/sync/cloud_snapshot_frozen_retry_test.dart -> +4 All tests passed!
flutter test test/sync/cloud_auto_upload_test.dart       -> +15 All tests passed!
flutter test test/national_focus/national_focus_auto_upload_trigger_test.dart -> +5 All tests passed!
flutter test test/sync/cloud_snapshot_history_page_test.dart -> +7 All tests passed!
flutter test test/sync/cloud_auto_upload_card_test.dart  -> +3  All tests passed!
flutter test test/sync/cloud_auto_upload_app_test.dart   -> +4  All tests passed!
flutter test                                             -> +486 All tests passed!
git diff --check                                         -> 通过
```

## 新增测试覆盖

- 队列与开关（`cloud_auto_upload_queue_test.dart`）：默认关闭、按用户保存、意图与请求跨实例保留、
  合并只保留一条、阻塞原因保留、损坏内容按空队列处理、清空后不保留键。
- 冻结快照重试（`cloud_snapshot_frozen_retry_test.dart`）：同身份重发原载荷只落一份历史、
  同身份换载荷被判为冲突且不写入、指纹不一致仍拒绝、载荷指纹与捕获状态同口径。
- 协调器（`cloud_auto_upload_test.dart`）：默认关闭不排队；单次确认上传一次且内容未变不重复备份；
  在途多次确认合并；在途本机变化不会把新内容标成已同步；未处理云版本停止并保留意图；
  首次遇到既有云快照/忽略提示都不授权覆盖；离线失败→原身份重试+新意图新请求；
  响应丢失重试只落一份；PT422/PT425 停止且不改写；关闭开关取消在途与排队；
  停用/不可访问不上传、恢复后上传最新快照；恢复旧云版本后不因来源是自己而视为已处理；
  找回本机恢复点后不沿用旧基线；取消后不再上传历史内容。
- 今日确认回调（`national_focus_auto_upload_trigger_test.dart`）：批量只回调一次；单点一次；
  点亮不触发；普通+例外混合整批一次；部分成功后关闭例外面板仍一次；熄灭不触发。
- 卡片与历史页（`cloud_auto_upload_card_test.dart`、`cloud_snapshot_history_page_test.dart`）：
  开关默认关闭/开启后按用户保存；手动下载前取消待传请求；停止原因在卡片提示与面板展示；
  云历史离线时本机恢复点仍可查看与找回、两个错误独立呈现与重试、恢复前取消队列。
- App 级（`cloud_auto_upload_app_test.dart`）：默认关闭时批量确认不上传；开启后整批一次、
  普通编辑不触发；未处理云版本停止覆盖且队列保留；离线确认后前台恢复重试同一请求只落一份；
  切换账号清除上一账号队列且不代为上传。

## 未完成的验收（交主 Agent）

- 真实隔离 Supabase 项目：`p_request_id` 台账的端到端重试（响应丢失、PT422、PT425）、
  跨设备自动上传与版本阻塞、旧客户端兼容。本 worktree **未**连接真实项目或凭据。
- 两端设备：Android 与 Windows 运行同步面板开关、国策批量确认（含例外）、离线确认后重启、
  恢复（云端/本机）后不再自动上传；亮暗主题与窄宽窗口；截图证据需与命令输出同源保存。
- Windows 完全退出后的重试时机未验证（只验证前台恢复/联网触发）。

## 已知限制与说明

- “已发出但未确认”的请求把整份业务快照暂存在本机偏好里，以便同身份重发完全相同的内容；
  成功、取消或关闭后立即清除。它是本机数据，与被上传内容等价。
- 队列每用户只保留一条合并意图，不记录每次确认的来源；这是“整批只上传一次”的直接结果。
- 自动上传不会修改“上次成功同步时间”以外的界面状态；停止原因只在同步卡片提示与面板中显示。
