# Issue #71 隔离 Supabase 与 AppShell 验收

日期：2026-10-24 至 2026-10-25（Asia/Shanghai）。本记录涵盖隔离 Supabase 服务边界和 Android/Windows AppShell 云检查；真实进程冷启动、后台/前台及断网重连证据见 [Issue #71 总验收记录](issue-71-validation.md) 与 [原生验收记录](issue-71-native-validation.md)。

## 隔离环境与数据库边界

- 创建前只读核对 Supabase 组织为 Free 方案，项目清单只有共享项目 `Pacta`。建立独立 nano 项目 `Pacta issue71 disposable validation`（ref `jgpuzfocircarvlykzqd`，`ap-southeast-1`）；迁移、Auth 身份、快照和旧 Goal fixture 都仅在这个项目中。共享项目未写入。
- Management token 从被 Git 忽略的根目录 `.env` 读取，只在脚本进程内使用。数据库初始化口令随机生成，不保存在仓库；Flutter 控制文件仅包含短期随机运行令牌并以当前 Windows SID ACL 保护。Auth 会话通过受控回环端口传递，账号密码和服务端密钥没有编入客户端。
- `scripts/issue71_cloud_discovery_acceptance.py prepare` 应用仓库中的 27 份迁移，并通过 `supabase/tests/cloud_business_snapshots.sql` rollback-only RLS/CAS 探针。
- 真实 Auth/REST 探针通过：owner 读到自己的 revision 1，第二用户读不到 owner 快照；旧数据 RPC 只向旧 Goal 所属用户返回数据。快照与旧 Goal 读取前后的业务摘要一致。将快照 revision 从 1 改为 2 后 owner 读到 revision 2；更新旧 Goal 内容后 stable token 改变，`data_updated_at` 保持不变。

## Android 与 Windows AppShell 实际服务阶段

入口：[issue_71_cloud_discovery_test.dart](../integration_test/issue_71_cloud_discovery_test.dart)。每个阶段都使用独立的 Supabase Auth session、真实 Supabase SDK、AppShell 和临时 Drift 文件库。先把实际 revision/token 写成设备已处理基线；冷启动检查对此版本保持安静。runtime 端点随后只改变快照 revision 或旧 Goal 内容，且不改变 `data_updated_at`；推进测试时钟并发送 `resumed` callback 后卡片显示待处理。两端 local business 都是 3 行，检查前后 fingerprint 相同。

测试 HTTP observer 验证实际服务请求：没有快照保存 RPC，也没有业务表写入；Android legacy 与两个 Windows 阶段还断言 `cloud_business_snapshots` GET 的 `select` 只请求 metadata 列，不是 `*`，不含 `payload`。legacy 检查只额外调用只读的 `read_legacy_business_records` RPC。跨用户探针验证第二用户只能读自己的快照，不能读首用户快照或旧 Goal。旧预览只打开后取消，没有下载或改写本地业务。

每次平台/阶段都重新启动 runtime，提供全新的 revision 1 / legacy token fixture；旧服务停止时清理临时 Auth 用户、快照、旧 Goal 和控制文件，再创建下一阶段 session。

| 平台 / 阶段 | 实际命令结果 | 只读证据 | 截图 |
| --- | --- | --- | --- |
| Android 15 / API 35 / `snapshot` | `cmd.exe /c flutter test integration_test/issue_71_cloud_discovery_test.dart -d emulator-5556 --no-uninstall --dart-define=ISSUE71_PHASE=snapshot --dart-define-from-file=.dart_tool/issue71-cloud-control.json`：1 passed；输出 `reads=3 legacyReads=0 localRows=3 localFingerprintUnchanged=true` | revision 1 静默；revision 2 后待处理；dataUpdatedAt 未变。selector 断言是在本阶段之后加入的，故不把该断言记作本阶段执行证据。 | [已处理版本](evidence/issue71-android-snapshot-handled.png)、[待处理卡片](evidence/issue71-android-snapshot-pending.png) |
| Android 15 / API 35 / `legacy` | `cmd.exe /c flutter test integration_test/issue_71_cloud_discovery_test.dart -d emulator-5556 --no-uninstall --dart-define=ISSUE71_PHASE=legacy --dart-define-from-file=.dart_tool/issue71-cloud-control.json`：1 passed；输出 `reads=4 legacyReads=4 localRows=3 localFingerprintUnchanged=true` | 旧 token 变化后待处理；dataUpdatedAt 未变；metadata-only GET、无下载和保存请求断言通过。 | [待处理卡片](evidence/issue71-android-legacy-pending.png)、[旧版云数据预览](evidence/issue71-android-legacy-preview.png) |
| Windows 11 / `snapshot` | `cmd.exe /c flutter test integration_test/issue_71_cloud_discovery_test.dart -d windows --dart-define=ISSUE71_PHASE=snapshot --dart-define-from-file=.dart_tool/issue71-cloud-control.json`：1 passed；输出 `reads=3 legacyReads=0 localRows=3 localFingerprintUnchanged=true` | revision 变化后待处理；dataUpdatedAt 未变；metadata-only GET、无下载和保存请求断言通过。 | [已处理版本](evidence/issue71-windows-snapshot-handled.png)、[待处理卡片](evidence/issue71-windows-snapshot-pending.png) |
| Windows 11 / `legacy` | `cmd.exe /c flutter test integration_test/issue_71_cloud_discovery_test.dart -d windows --dart-define=ISSUE71_PHASE=legacy --dart-define-from-file=.dart_tool/issue71-cloud-control.json`：1 passed；输出 `reads=4 legacyReads=4 localRows=3 localFingerprintUnchanged=true` | 旧 token 变化后待处理；dataUpdatedAt 未变；metadata-only GET、无下载和保存请求断言通过。 | [待处理卡片](evidence/issue71-windows-legacy-pending.png)、[旧版云数据预览](evidence/issue71-windows-legacy-preview.png) |

上表命令省略公共入口和配置尾参数。完整命令模板如下；Android 使用 `--no-uninstall` 保留模拟器数据：

```bash
flutter test integration_test/issue_71_cloud_discovery_test.dart -d <平台> [--no-uninstall] --dart-define=ISSUE71_PHASE=<snapshot|legacy> --dart-define-from-file=.dart_tool/issue71-cloud-control.json
```

`resumed` callback 用于稳定验证五分钟节流后的真实云读取，不作为真实 OS 前后台或进程冷启动证据；后者由独立原生入口记录。Android 测试使用既有 `PactaT24Secondary`（emulator-5556），不清除应用数据或擦除 AVD。旧版转换会创建隔离 Drift memory DB，Android 首次 legacy 阶段显示了 Drift 的多数据库 debug 提示，但测试通过且本机指纹不变；之后在集成入口启用了同仓库既有的预期提示抑制。

Android 首轮连接未通过的原因是 AVD UTC 比主机慢约 11 小时，Supabase TLS 报 `CERTIFICATE_VERIFY_FAILED: certificate is not yet valid`。将仅此测试 AVD 的时钟校准至主机当前 UTC 后重新创建 Auth session；没有绕过证书校验。校准重启 adbd 后清掉了一次 `adb reverse` 映射，重新建立 `tcp:30347` 转发后四阶段按表通过。初始草稿阶段的 snapshot session 名也曾不匹配；入口现把 `snapshot` phase 映射到 `device` session，后续实测通过。

## 清理与删除复核

所有 runtime service 停止后执行 `cleanup-stale`，聚合检查为 `users=0 snapshots=0 legacy_goals=0`，控制文件已移除；然后执行 `delete-project` 删除独立 nano 项目和本地 project state。Management API 复查目标项目返回 HTTP 404，项目列表只剩共享项目 `Pacta`。ADB reverse 已移除，AVD adbd 已退出 root 模式；AVD 未擦除，Android app 数据未卸载。最终结果另存于 [issue71-cloud-results.json](evidence/issue71-cloud-results.json)。
