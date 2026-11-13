# #92 简洁同步与最近 15 份备份恢复 — 实施记录

状态：实施完成，本地 client/SQL 验证通过；真实云与两端设备验收由主 Agent 执行。
分支：`impl/pacta92-backup-history`（基线 `c76a59f`）。
依据：[票据](tickets-sync-profile-cards-20261113/02.md)、[规格](spec-sync-profile-cards-20261113.md)。

## 范围与决策

- 来源显示：Android 只显示型号，Windows 只显示设备名，各自附平台括注；不再显示设备标识、
  厂商或单独型号行。缺少必需值时显示「未知型号（Android）」/「未知设备名（Windows）」，
  不回退到主机名，也不伪造名称。上传写入的 `device_name` 同样是该标签。
- 云备份保留：新增 `cloud_business_snapshot_history`，含最新份在内保留最近 15 份成功写入。
  快照写入、历史落档与淘汰在同一事务内完成，先写入新版本再淘汰最旧版本。
- 旧客户端兼容：`save_cloud_business_snapshot` 仍是唯一写入入口，新增参数全部带默认值；
  7/9 参数旧调用同样落历史、同样受版本条件校验与保留上限约束，没有另开无保护接口。
- 恢复：先持久保存本机恢复点（Drift `local_cloud_recovery_points`，独立于可上传业务表），
  读回确认后才整体替换；保存失败、校验失败、未结束流程或取消钩子命中时都不替换本机数据。
  恢复只写本机，不触发上传，因此不会覆盖云端。
- 本机恢复点与云端 15 份分开保存，按用户隔离，每用户保留最近 5 份，参与账号清除。

## 变更清单

| 变更 | 文件 |
| --- | --- |
| 来源标签与平台枚举 | [source_device_info.dart](../lib/src/sync/source_device_info.dart) |
| 历史条目与恢复取消异常 | [cloud_snapshot_history.dart](../lib/src/sync/cloud_snapshot_history.dart) |
| 本机恢复点模型与 Drift 存储 | [cloud_recovery_point.dart](../lib/src/sync/cloud_recovery_point.dart) |
| 历史列表 / 指定版本恢复 / 恢复点找回 | [cloud_snapshot_repository.dart](../lib/src/sync/cloud_snapshot_repository.dart) |
| 同步卡片精简与历史入口 | [cloud_sync_card.dart](../lib/src/sync/cloud_sync_card.dart) |
| 历史备份页 | [cloud_snapshot_history_page.dart](../lib/src/sync/cloud_snapshot_history_page.dart) |
| 恢复点表与 schema 26 迁移 | [task_database.dart](../lib/src/tasks/task_database.dart)、生成文件 `task_database.g.dart` |
| App 接入为来源标签 | [main.dart](../lib/main.dart) |
| 云历史迁移 | [202611130001_cloud_snapshot_history.sql](../supabase/migrations/202611130001_cloud_snapshot_history.sql) |
| SQL 验证脚本 | [cloud_snapshot_history.sql](../supabase/tests/cloud_snapshot_history.sql) |
| 部署说明 | [supabase/README.md](../supabase/README.md) |

## 面向 #93 的最小 API（实施约定）

自动上传本身不在本票内；#93 直接复用下列接口，不要另建写入路径或历史表。

1. **上传请求幂等**：`CloudSnapshotRepository.uploadLocal(expectedRevision:, expectedFingerprint:, requestId:)`
   → `CloudSnapshotRemote.upload(..., requestId:)` → RPC 参数 `p_request_id`。
   - 服务端在用户事务锁内先查请求台账 `cloud_business_snapshot_upload_requests (user_id, request_id)`；
     台账只记录请求身份、它产生的 revision 与 payload 指纹，**不含业务载荷**，并且不受 15 份保留上限
     影响，因此历史淘汰后重试也不会重复落档。
   - 命中台账时按台账 revision 从历史表映射返回**该请求原本写入的版本**（含原设备与原始上传时间）。
     绝不返回当前快照：否则请求 A 成功后被另一台设备写入新版本，A 的重试会把别人的数据记成本机
     已处理版本。
   - 同一 request id 换了内容 → `PT422`（客户端提示「该上传请求已用于不同的数据内容」），不写入。
   - 台账命中原版本已被淘汰 → `PT425`（提示「已处理，但对应备份已不在最近 15 份内」），不写入，
     也不会当作新请求。
   - `requestId` 非空时客户端**禁止**回退到没有 `p_request_id` 的旧签名：PostgREST 报 `PGRST202` 且
     提示的旧签名缺该参数时，直接抛 `StateError('云端服务尚未支持上传请求去重…')`，一次请求都不写。
     `requestId` 为 null 的手动上传继续保留 9 参数 / 7 参数逐级回退兼容。
   - 因此 #93 只在服务端确认支持幂等（本迁移已应用）时才重试；否则必须先升级服务端。
2. **成功已处理版本基线**：`CloudSyncResult.cloudRevision` / `legacyToken`（`loadSyncResult()`），
   仅在真正成功写入或成功应用云端数据后更新；检查、忽略、失败、取消都不更新。
   恢复旧版本时写入被恢复的 revision，因此最新版仍显示为待处理。
3. **恢复取消钩子**：`restoreCloudVersion(..., isCancelled: bool Function()?)` 与
   `restoreLocalRecoveryPoint(..., isCancelled: ...)`。命中时抛 `CloudRestoreCancelled`，
   本机数据不替换；已保存的恢复点保留（可找回）。恢复点保存后、替换事务前各检查一次。

## 实际执行的命令与结果

环境：Windows 11；DSH 工具 shell 为 MSYS bash；Flutter 3.47.2 / Dart 3.13.2。

```text
flutter pub get --offline                      -> Got dependencies!
dart run build_runner build                    -> Built with build_runner/aot; 新表代码已生成
dart format <改动文件>                          -> 已格式化
flutter analyze                                -> No issues found!
flutter test                                   -> +426 All tests passed!
flutter test test/sync/cloud_snapshot_history_test.dart      -> +11 All tests passed!
flutter test test/sync/cloud_snapshot_history_page_test.dart -> +4  All tests passed!
flutter test test/sync/source_device_info_test.dart          -> +5  All tests passed!
```

`task_database.g.dart` 由 build_runner 生成后按仓库既有约定转回 CRLF；该文件的差异包含新表代码与
生成器版本的格式化变化，属于 `AGENTS.md` 要求的「检查生成差异」范围。

## 新增测试覆盖

- 来源标签：型号/设备名构造、缺值未知来源、其他平台不虚构括注。
- 历史与恢复（`test/sync/cloud_snapshot_history_test.dart`）：最新份在列、连续上传保留 15 份并淘汰最旧、
  恢复旧版本不写云端、恢复失败不部分替换、恢复前保存恢复点并可从恢复点找回、恢复点保存失败不替换、
  未结束流程禁止恢复、恢复点按用户隔离、同 request id 重试只落一份历史、取消钩子前后两次。
- 历史页与入口（`test/sync/cloud_snapshot_history_page_test.dart`）：时间/来源/记录数、两组列表分开、
  取消不替换、确认后恢复并生成可找回恢复点、卡片提供历史入口且不再显示设备标识。
- 既有同步用例按新要求更新：去掉厂商/型号行断言，remote 替身补齐 `requestId` 与历史接口；
  旧 RPC 回退新增「两层可选参数逐级退回」用例。

## 未完成的验收（交主 Agent）

- 真实隔离 Supabase 项目：应用 `202611130001_cloud_snapshot_history.sql` 后执行
  `supabase db query --linked -f supabase/tests/cloud_snapshot_history.sql`，核对 RLS、并发、
  保留上限、恢复与账号清除结果。本 worktree **未**连接任何真实项目或凭据，上述 SQL 未在此执行。
- 两端页面验收：Android 与 Windows 运行受影响页面（同步卡片、历史备份页、恢复确认、恢复后看板刷新），
  验证亮暗主题、窄宽窗口、触摸/鼠标；截图需基于 Pacta 实际主题与 MiSans，Android 用
  `binding.takeScreenshot` + host driver 回传。
- 真实服务端到端：跨设备上传/列表/恢复与「恢复不覆盖云端」的真实行为。单元测试使用内存 remote 与
  临时 Drift 库，不能替代真实云或设备证据。

## 审查修复（2026-11-13 第二轮）

| 问题 | 修复 |
| --- | --- |
| 幂等分支返回当前快照，会把其他设备的新版本记成本机已处理 | 新增不含业务载荷的请求台账，命中时按台账 revision 从历史映射返回该请求**原版本**；同 request id 换内容报 `PT422`，原版本已淘汰报 `PT425`，都不会写入 |
| 恢复点读回只判非空 | 校验 `userId`、`id` 与载荷指纹都等于替换前的本机状态，任一不符即取消恢复 |
| 取消钩子只在事务外检查 | `_replaceLocalTables` 接收 `isCancelled`，在事务内设置三个检查点：异步预检后、读取本机日历映射后（首个 DELETE 前）、全部写入后（提交前）；任一命中都回滚整个替换 |
| 带 requestId 时静默降级旧签名会丢失去重 | requestId 非空禁止回退到无 `p_request_id` 的签名，直接报需升级服务；手动上传（null）保留兼容 |
| `_fingerprint` 对畸形载荷会抛类型错误 | 改为全函数：畸形载荷跳过归一化，供恢复点读回校验使用 |

取消检查点用 `CloudRestoreStage`（`beforeReplacement` / `afterCalendarLookup` / `afterReplacement`）
异步观察者验证，不再依赖调用计数：分别在三个边界模拟账号切换，断言本机数据未被替换，
并验证「写入完成后取消」会整体回滚（恢复目标已写入仍恢复为替换前记录）。

新增测试：原版本重试、request id 换内容被拒、淘汰后重试不写入、恢复点读回不一致不替换、
事务内取消仍不替换、requestId 非空不回退旧签名、`PT422`/`PT425` 错误映射。
SQL 增加版本 19/20 之后重试必须返回 19、`PT422`、`PT425` 及台账清除断言。

第三轮（真实隔离云诊断反馈）：SQL probe 的 purge 段原先仍在 `authenticated` 角色下读 `auth.users`，
在真实项目上以 `42501 permission denied` 失败。已改为身份选择、种子数据与结果断言都在 `reset role`
的可信会话里完成，`authenticated` 只用于 RLS 与 CAS 检查，`service_role` 只用于执行清除 RPC；
并移除「无空闲非管理员身份就跳过」的分支——缺少管理员或非管理员身份时直接报错，不再静默跳过 purge。
第四轮（真实 probe 再次 42501）：请求台账的事件计数断言当时仍在 authenticated 段，已移到 `reset role`
之后；`reset role` 也提前到全部可信断言之前。现约定：`authenticated` 段只访问授权表
（`cloud_business_snapshots`、`cloud_business_snapshot_history`）与授权 RPC，`auth.users`、`app_admins`、
请求台账、purge receipt、停用记录一律只在可信段读写；台账在 authenticated 段只保留一条「必须不可读」的
隐私反证。淘汰场景的填充上传改为先读 `cloud_business_snapshots` 的实际当前版本再逐次推进，否则会先撞
`PT409` 而测不到 `PT425`。结构自检：16 个 DO 块 dollar-quote 全部配对，单引号配平。
主 Agent 提供 admin + 非 admin 两个身份后该段会真实执行。

## 已知限制与其他说明

- 本 worktree 检出时工作区为 CRLF 而仓库 blob 为 LF，`git status` 曾把整棵树报为改动；
  已为本 worktree 单独设置 `core.autocrlf=input`（`config.worktree` 作用域，不影响其他 worktree），
  未改动任何文件内容。
- 本机恢复点每用户保留 5 份（含整份业务快照，需要上限）；规格未规定数量，此为实施默认值。
- 历史列表来自受 RLS 保护的表直读，客户端只取元数据列；整份载荷仅在恢复指定版本时读取。
## 合并与复核

```text
git merge --no-edit feat/sync-profile-cards-20261113   -> Merge made by the 'ort' strategy; 无冲突
                                                         （仅 ADR 0005 补充与本票基线文档）
flutter analyze                                        -> No issues found!
flutter test                                           -> +426 All tests passed!
```

合并后逐一核对 ADR 0005「Optional confirmation upload and retained backups — 2026-11-13」：
最近 15 份含最新份的原子创建与淘汰、显式历史恢复先持久保存用户隔离恢复点、保存失败不替换、
事务恢复不打断未结束流程、恢复不上传、迁移保留现存快照、旧写接口不能绕过保留与并发校验、
清除义务覆盖历史副本、来源单一标签且缺失元数据显式未知 —— 与本实现逐条对应。
自动上传与合并请求队列属于 #93，本票未实施。