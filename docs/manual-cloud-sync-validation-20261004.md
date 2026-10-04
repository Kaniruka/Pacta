# 手动整份云同步验证 — 2026-10-04

决策依据：[ADR 0005](adr/0005-manual-whole-data-cloud-sync.md)。术语已更新到 `CONTEXT.md`；核心规格、产品设计及验收矩阵已更新。

## 已完成的行为

- “我的”提供手动查看、上传覆盖云端和下载覆盖本地；显示双方数据更新时间、云端来源与上传时间，整份替换需要明确确认。
- 启动、恢复前台、联网恢复和日常业务编辑不再通过旧接口同步业务数据。身份状态查询、本地计时、检查点结算与通知维护继续运行。
- 下载事务先验证用户归属、表列类型和主要引用，再复核本机变化与未结束流程；确认期间云端版本变化会要求重查。失败回滚，不替换本机身份、设备设置或管理员状态。
- 国策按本机时间和固定北京 04:00 检查点结算，不生成新的时间核对；旧时钟待核对解除，旧分支冲突证据保留。
- 新快照尚不存在时，旧云记录在隔离临时数据库中转换成可选择的整份数据，不合并进本机；无法确定的来源/上传时间明确标为未知。旧数据内容 token 参与首次上传校验。创建新版快照后旧客户端逐记录写入被拒绝。

## 实际运行的验证

在 Windows 主机 SDK Flutter 3.47.2 / Dart 3.13.2 下，从仓库执行：

- `dart format`：对本任务改动的 Dart 文件完成格式化。
- `flutter analyze`：无问题。
- `flutter test --reporter expanded`：首轮 207 项通过；真实平台发现下载订阅问题后新增完整 AppShell 回归，最终 208 项全部通过。
- `flutter test test/sync --reporter expanded`：同步相关 18 项通过，覆盖取消、较旧云端覆盖较新本地、320 dp / 200% 字体、旧记录转换、1001 条数据完整性、账号隔离、过期预览及事务中段失败回滚。
- 对本任务涉及的文件执行 `git diff --check`：通过；未用仓库其他已有未提交改动的结果替代本任务结果。

使用临时目录的 PGlite 隔离 PostgreSQL 环境，模拟 Supabase Auth 角色、身份函数和旧业务表，实际执行了：

- `supabase/migrations/202610040001_cloud_business_snapshots.sql`。
- `supabase/tests/cloud_business_snapshots.sql`，完整 rollback-only 测试通过。
- 额外 SQL 探针：版本 0→1→2、初次非零/过期版本拒绝、缺失必填字段拒绝、跨用户 RLS、客户端直接写表拒绝、停用上传拒绝、旧数据 token 缺失/过期拒绝、正式快照后旧写入拒绝、快照和旧数据清除。

## 2026-10-04 真实服务与平台补充验收

- 已通过 Management API 在已连接的开发项目中应用 `202610040001`、`202610040002`，并记录到服务端迁移历史。现有用户业务记录未用于覆盖测试；使用独立临时身份隔离验收数据。
- 真实 REST/SQL 检查覆盖：匿名与跨用户读取拒绝、客户端直接写表拒绝、跨用户 payload 拒绝、停用用户读写拒绝、初次/过期版本与旧数据 token 拒绝、旧接口禁写和用户恢复。仓库 rollback-only SQL 测试也以临时身份执行并回滚。
- 两个实际 PostgreSQL 后端连接同时竞争首次上传，只有一个成功，持久版本为 1；另一连接得到明确版本冲突。
- 新快照和旧表记录的真实服务清除通过：快照与旧 Goal 均为 0，清除回执标记业务数据已清除。
- Android 15 / API 35 / x86_64 模拟器 `emulator-5554` 上传真实快照，Windows 11 实际客户端下载并新增 Goal 后上传，Android 再从 Windows 来源下载。三阶段实际客户端、真实 Supabase SDK、持久 Drift 数据库均通过；取消保留本机草稿，选择下载丢弃本机独有草稿，重复下载没有重复专注节点。
- Windows 实际 SDK 的过期预览立即拒绝，并保留本机记录；控制传输层断网后记录保留，恢复真实服务传输后可重新手动上传。
- Android T20/T21 日历 Provider、授权/撤权和缓存恢复；T22 通知拒绝、允许、预约交接、专注结束及点击去重；T23 国策提醒均通过。模拟器初始没有可见日历源，首次 T20 失败；建立唯一标记的临时日历/活动后重跑通过，之后只删除测试记录。
- Windows T22 托盘状态与原生通知通道、T23 国策提醒与偏好恢复测试通过；原有偏好文件在验收后恢复。

## 真实环境发现并修复的问题

1. 整份下载后 provider 重建重复赋值 `late final` 通知订阅，触发 `LateInitializationError`。已改为可重新订阅的字段，并新增完整 AppShell 的快速红/绿回归测试。
2. 以 SQLSTATE `40001` 表示业务版本冲突会导致真实 PostgREST 长时间重试；隔离 PGlite 没有暴露这个服务行为。保留已应用的首个迁移，以单独后续迁移改为 `PT409` / `PT410`，真实 SDK 验证其立即返回。依据：[Supabase 官方说明](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b)。界面显示可操作的中文提示，不展示底层异常类型。

## 验证边界

- Android 平台证据来自正在运行的 Android 15 模拟器，Windows 来自当前 Windows 11 主机。
- 实际传输验证使用当前开发项目中的隔离临时身份；没有额外建立新的收费项目。PGlite 证据仍作为隔离 SQL 回归，真实授权与并发结果另有实际服务证据。
- Windows 原生通知测试证明实际托盘/通知通道处理与流程调度，不以虚构的截图声称所有系统通知显示策略均已验证。
- 签到触发同步仍不在当前范围内。

## 离线恢复与测试清理补充

- Android 实际 Wi-Fi / 移动数据关闭后观测到 `Connectivity.none`，本机任务与国策记录仍可写；恢复网络、HOME/前后台恢复后，云业务调用计数仍为 0。force-stop 后重开同一个应用支持目录的 Drift 文件，记录完整。此测试的远端是明确的 InMemory 替身，证明 OS 生命周期不触发业务同步；真实服务传输与失败恢复由独立实际 SDK 测试证明。
- 离线 seed 与 restart verify 的设备测试都输出 `All tests passed`。首轮 host wrapper 在设备测试通过后遇到一次 adb logcat 轮询错误；修复轮 Flutter drive 未进入测试 READY，已停止重复重试，不把这一轮算作通过。它没有进入断网阶段，Wi-Fi / 移动数据均已恢复。
- 已清理 4 个独立临时 Auth 身份、对应快照和旧业务数据、临时注册资格与清除回执；并删除只允许测试身份调用的临时并发探针函数。验证残留临时用户/快照数均为 0。
- 已停止本机运行时会话服务器，删除临时账号凭据与控制配置；Windows 原有偏好已验证还原；Android 已恢复非 root、原 Wi-Fi / 移动数据状态，唯一标记的日历与活动已删除。
- 非敏感真实服务检查、清除和清理结果见 [JSON 证据](evidence/manual-cloud-sync-20261004.json)。该证据不含账号、密钥或 token。

- Android 修复后的完整 InMemory-cloud AppShell 上传/下载流程通过 `flutter test integration_test/manual_cloud_sync_device_test.dart -d emulator-5554 --reporter expanded` 直接运行通过。此前两个失败运行保留在历史日志中，不作为成功证据。
- 平台白名单通过标记与历史失败标记见 [平台证据日志](evidence/manual-cloud-sync-platform-20261004.log)；完整真实跨端测试与回归代码保存在 `integration_test/manual_cloud_sync_real_service_test.dart`、`integration_test/manual_cloud_sync_device_test.dart` 和 `integration_test/manual_cloud_offline_recovery_device_test.dart`。
