# Issue #64 实施与验收

> 历史适用范围：以下设计、评审及验收记录适用于各节所载日期（2026-10-23 范围调整之前）。原始事实、测试和证据保留；其中无障碍要求及未完成项不再构成未来交付条件，现行范围见 [ADR 0007](adr/0007-accessibility-out-of-product-scope.md)。

票据：[T01: 描述贯通目标、任务与整份快照](https://github.com/Kaniruka/Pacta/issues/64)。
日期：2026-10-22。比较基点：`0ad61c97a3f2a3556b39f58ef820476e64585add`，分支 `master`。

## 结果

| 验收条件 | 结果与证据 |
| --- | --- |
| 目标/任务描述新增、编辑、清空；trim、换行转空格、200用户可见字符 | 通过 AppShell＋真实仓储 widget 测试及两平台原生测试。family emoji 按 grapheme 计数；空描述不渲染描述行。名称规则未修改。 |
| 看板单行省略、编辑全文、2×字号与窄屏 | 320×800逻辑像素、2×字号；目标浅色、任务深色 widget 测试通过。折叠后保留目标描述、隐藏任务描述；Android实际截图已检查。 |
| 模型/本地/整份快照贯通；升级与旧快照兼容，非法数据拒绝且不部分替换 | schema24→25迁移保留旧目标和任务；真实服务下载缺描述v1快照后描述为空、记录保留；额外列、跨用户行和超长描述拒绝，fingerprint不变。 |
| Android15/Windows11实际编辑、清空、重启保留；隔离Supabase双端往返 | 两平台分别write→新进程verify通过；Android上传→Windows下载/新增描述后上传→Android下载全部通过。 |

## 实施与已确认测试边界

- `Goal`、`Task` 和对应草稿新增默认空串 `description`。仓储共用规范化，去首尾空白、常见换行转空格，最多200 grapheme。
- Drift schema25为两表添加非空默认空串列，保留已有业务记录；生成代码同步更新。`characters`作为直接依赖。
- 复用既有表单及主题，共用描述输入控件；看板非空才显示单行描述，编辑框换行显示全文，弹窗内容可滚动。
- 快照仍为schemaVersion1；只允许目标/任务行缺失描述这一兼容情况，精确列集、类型、用户归属和引用校验继续执行。下载也执行描述规范化，超长值在替换前拒绝。
- 主边界为AppShell＋真实仓储/Drift，替换外部认证与远端；下层只补迁移和旧快照/严格校验风险。没有逐层重复描述CRUD测试。

## 自动化验证

Windows Flutter 3.47.2 / Dart3.13.2，通过 `cmd.exe /c` 执行：

| 命令 | 最终结果 |
| --- | --- |
| `dart format`（所有本票修改Dart文件；Drift生成文件也已生成/格式化） | 通过 |
| `dart run build_runner build --delete-conflicting-outputs` | 生成schema25代码，已检查差异 |
| `flutter analyze` | No issues found |
| `flutter test test/board` | 7 passed |
| `flutter test test/tasks/task_database_migration_test.dart` | 1 passed |
| `flutter test test/focus/chain_signals_repository_test.dart test/national_focus/national_focus_repository_test.dart` | 29 passed |
| `flutter test test/sync/cloud_snapshot_repository_test.dart` | 16 passed |
| `flutter test --reporter compact`（审查修复后最终运行） | **270 passed** |
| `python3 -m py_compile scripts/issue64_cloud_sync_acceptance.py` | 通过 |
| `git -c core.whitespace=cr-at-eol diff --check` | 通过（生成文件保持既有CRLF） |

迁移与旧快照风险按TDD执行。首轮完整测试暴露两处旧迁移夹具问题：使用当前schema建库后只回退版本号，及旧库缺任务表。已让夹具还原无描述的旧表，再跑相关29项及全量通过。新增折叠测试曾因按钮不在可点区域而失败，修正滚动定位后通过。

## 原生本地验证

入口 `integration_test/goal_task_description_device_test.dart` 使用应用支持目录中的独立文件数据库、外部认证替身、真实AppShell和仓储，不连接云，也不打开生产业务库。

分别执行（`...`为上述入口）：

- Android15，AVD `PactaT24Peer`，emulator-5554：`flutter test ... -d emulator-5554 --no-uninstall --dart-define=DESCRIPTION_PHASE=write`，1 passed；停止实际进程后，另一次 `DESCRIPTION_PHASE=verify`，1 passed。模拟器曾退出，重启后沿用同一数据，未擦除设备。
- Windows11 10.0.22631：`flutter test ... -d windows --dart-define=DESCRIPTION_PHASE=write`，1 passed；另一次新进程 `DESCRIPTION_PHASE=verify`，1 passed。

write阶段通过界面完成两类描述的新增、修改、清空和重新保存；verify读取同一文件并检查描述、折叠和编辑全文，随后删除独立fixture文件。不是widget重建或热重载代替重启。

[Android实际描述显示截图](evidence/issue64-android-descriptions.png)已由主代理与UI代理目视检查。原生测试使用Flutter tester点击/文字输入，不声称真人鼠标、软键盘或读屏审查。Windows Computer Use初始化两次均报WSL cwd不是本地URI，未取得Windows截图；Windows原生测试结果与截图限制分别记录。

## 隔离Supabase真实往返

项目 `qznxwgqnavqxdqfhkzdg`，名称 `Pacta issue64 disposable validation`，ap-southeast-1。创建前核验组织Free且只有一个活跃项目，在剩余免费配额使用nano实例，未升级套餐或添加付费资源。没有向共享开发项目写本轮业务数据。

`python3 scripts/issue64_cloud_sync_acceptance.py prepare` 应用26份仓库迁移并执行 `supabase/tests/cloud_business_snapshots.sql` rollback RLS/CAS 探针，通过用户隔离、权限和并发版本边界。Auth/资格均为临时fixture。

`serve`只监听回环地址127.0.0.1:30347，以随机控制令牌传递临时Auth会话。Windows当前SID ACL保护控制/状态文件。服务端密钥和Auth会话没有编译进客户端；测试编译定义只包含运行时控制令牌。Android使用ADB reverse到该回环端口。

原生入口 `integration_test/manual_cloud_sync_real_service_test.dart`，参数：

`flutter test <入口> -d <平台> --dart-define=MANUAL_SYNC_REAL_CLOUD_PHASE=<阶段> --dart-define-from-file=.dart_tool/issue64-cloud-control.json`（Android另加 `--no-uninstall`）。

| 平台/阶段 | 结果 |
| --- | --- |
| Windows / windows-conflict | 1 passed，1 intentional skip。真实RPC旧预览HTTP409；传输替身离线后恢复真实服务；真实RPC上传并下载缺描述v1快照，目标/任务标题保留、描述为空；非法表集下载拒绝，本地fingerprint不变。 |
| Android / android-upload | 1 passed，1 intentional skip。明确UI确认上传，真实快照保留目标/任务描述。 |
| Windows / windows-roundtrip | 1 passed，1 intentional skip。明确下载保留Android目标/任务描述；创建带描述的Windows目标并明确上传。 |
| Android / android-download | 1 passed，1 intentional skip。明确下载后Android目标/任务及Windows新增目标描述均保留。 |

没有将传输替身断网称为真实网络断开。首次Windows测试暴露无云快照的空值假设，改为revision0后重跑通过。会话恢复中断原runtime后重建会话；Set-Acl失败改为icacls当前SID并验证。失败轮次不算通过。

## Standards

独立规范审查无文档标准违反。发现的轻微输入框重复已通过共用 `_DescriptionField` 消除；复核后无待处理基线异味。标准来源：AGENTS、CLAUDE、UI代理规范、GLOSSARY及ADR0001/0003/0004/0005。主代理复核结论。

## Spec

UI/存储需求审查无遗漏。独立同步审查发现下载描述只检查字符串类型、可绕过领域约束（P2）；已补规范化、超长拒绝及失败fingerprint不变测试，定向与最终全量通过。主代理复核快照兼容仅限缺description，其他列/用户规则保留。最终无未解决Spec发现。

Standards最终0项；Spec最终0项（P2已修复）。

## 设计审查

本次描述切片无高严重度问题。依据apple-design本地参考：Accessibility › Vision（大字号）、Typography › Supporting Dynamic Type、Layout › Adaptability、Entering Data › Best practices（清晰标签/动态校验）、Cross-platform translation。翻译为Flutter TextScaler/Material3主题、滚动弹窗、字段标签、字符计数及编辑全文；没有套用Apple平台控件。暗色证据仅为widget主题测试，截图限制见上。

## 数据与资源清理

Android原应用私有文件在测试前完整归档。测试后停止进程、恢复归档，所有7个原始文件SHA-256均一致；仅多出一个本轮Flutter资源时间戳缓存，已删除。普通debug APK已仅用公开URL/publishable key重新构建并通过 `adb install -r`安装，未启动以避免改变恢复数据。Windows原支持目录为空，fixture已删；普通Windows debug应用也重新构建完成，原Release产物未改。

已停止runtime、删除临时Auth会话/控制文件，删除独立项目和本地含随机数据库口令的状态文件，移除ADB reverse及临时公开配置。再次真实查询独立项目HTTP404，项目列表仅剩原开发项目；见[清理证据](evidence/issue64-cloud-cleanup.json)。中断前可能残留在独立项目的fixture也随项目删除清除。

开始时已有用户修改的GLOSSARY、产品/规范/ADR/验收矩阵及新需求票据文档均保留，不纳入本票提交。根`.env`未修改。
