# Issue #70 实施与验收

日期：2026-10-24（Asia/Shanghai）。票据：[T07: 云端来源设备型号与旧元数据兼容](https://github.com/Kaniruka/Pacta/issues/70)。开始时工作区干净；当前分支 `master`，比较基点 `519646bcd27172255b08de251ddd438ea0bbb8bf`。

## 实施与测试边界

- 保留原有“主机名 (Android/Windows)”设备名，Android 读取 `Build.BRAND` / `Build.MODEL`，Windows 只读 BIOS 注册表 `SystemManufacturer` / `SystemProductName`。没有序列号读取路径。平台失败或空字段保持未知。
- 型号元数据经过 App 组合入口、快照仓储、remote、RPC、云表和读取预览；不加入业务 payload，不改变整份覆盖或本机偏好的归属。预览以“厂商 · 型号”展示可用值，缺型号显示“型号未知”，原设备名继续显示。
- 云表新增可空列，旧行不回填虚构型号；RPC 新参数有默认值，旧客户端仍可调用。新版检查遇到明确的新增列缺失才改读原字段，保留旧云表的快照查看与下载；其他错误照常报错。新型号上传要求部署新迁移。
- 旧业务表转换继续隔离进行，原设备和上传时间未记录的提示保留；不把内部旧数据时间哨兵显示成真实上传时间。不更改当前用户、RLS、生命周期、revision/fingerprint 复核或事务替换规则。
- 沿用已确认云 remote 边界及既有 AppShell/页面测试，覆盖元数据缺失和展示；真实原生读取及隔离服务另取证。遵循 ADR0007/0008，不新增读屏、大字号或专门键盘支持要求；保留已有测试。

## 自动化

`cmd.exe /c flutter test test/sync/cloud_sync_card_test.dart --reporter compact` 首先因缺“型号未知”而失败（2通过、1失败）；实现后与 `test/sync/manual_cloud_sync_app_test.dart` 合跑8项通过。初次 `flutter analyze` 发现3个集成测试上传替身未适配可选参数，已交由实施修改；最终检查结果将在下文记录，初次失败不计通过。

最终产品代码经 Windows Flutter（WSL 调用）检查：

| 命令 | 结果 |
| --- | --- |
| `dart format`（修改 Dart 文件） | 通过 |
| `flutter analyze` | No issues found |
| `flutter test test/sync/cloud_snapshot_repository_test.dart test/sync/cloud_snapshot_remote_test.dart` | 28 passed |
| `flutter test test/sync/cloud_sync_card_test.dart test/sync/manual_cloud_sync_app_test.dart` | 8 passed |
| `flutter test --reporter compact` | **307 passed** |
| `git diff --check` | 通过 |

HTTP 测试还复现并修正 SDK `maybeSingle` 将缺列结构化错误包成 HTTP400 消息的情况；只对新增型号列缺失回退，不把权限或其他错误当作旧表兼容。完整测试实际运行31秒。产品实现提交 `363cfb0`，评审补充 AppShell 回归提交 `598d1c3`（单文件5项通过），验收入口及证据单独补交。

## 原生和真实服务

独立 Windows 原生读取初步证据见[原生读取记录](issue-70-native-device-evidence.md)。独立免费 nano 项目创建前核验组织 free 计划及仅有一个共享 Pacta 项目；新项目中27份迁移（含型号迁移）应用成功，九参 RPC 存在，`supabase/tests/cloud_business_snapshots.sql` 回滚式 RLS/CAS 与旧 RPC 默认参数探针通过。共享项目未写入。环境切换后旧运行时停止，控制文件陈旧；尚未执行上传。恢复时复用同一独立项目，清理3个旧临时用户，再创建本轮会话，没有重复建项目。Android 首轮集成构建61.8秒、安装4.4秒成功，但测试 runtime 控制定义键名与控制文件不一致，服务返回403；此时没有平台上传发生。修正测试配置后增量重跑，首轮失败不记通过。Android 增量重跑上传通过：原生实际值 `localhost (Android)` / `google` / `sdk_gphone64_x86_64`，上传 revision1 与原生 metadata 一致；真实 AppShell 预览及主代理目视核验[Android上传预览](evidence/issue70-android-upload-preview.png)通过。Windows 同一测试运行2项全部通过：下载 Android revision1，新增 Windows 业务记录后上传 revision2，BIOS 原生值与云回读一致；第二用户不能读 owner 快照，真实旧版本预览下载被拒绝且本地指纹保持。旧 `goals` 表无快照时真实转换、显示未知来源／型号／原上传时间未记录并确认下载通过。主代理目视核验[Windows查看Android来源](evidence/issue70-windows-android-preview.png)、[Windows实际机型](evidence/issue70-windows-upload-preview.png)、[旧云表预览](evidence/issue70-windows-legacy-preview.png)均可读、未伪造旧时间。Android 回程下载通过，实际[Windows来源预览](evidence/issue70-android-windows-preview.png)可读且长机型完整；下载后两端创建的记录及描述均保留，成功记录指纹与实际恢复数据一致。主代理已目视全部5张预览截图。

## 设计评审

本次界面用途是让用户在明确覆盖前识别来源设备。沿用 Material3 主题文字与既有滚动内容，在来源名下补一行可换行的型号，无新控件、固定宽度或颜色。参考 apple-design 本地 `writing.md › Best practices` 的清晰、熟悉用语，`layout.md › Best practices` 的可调窗口适配，及 `labels.md › Best practices` 的系统字体和文字层级；仅转译通用原则到 Android/Windows。ui-ux-pro-max Flutter 查询确认按可用空间布局的建议，沿用现有弹层响应式行为。主代理已目视 Android 浅色底部预览及 Windows 暗色居中预览；设备名、长机型和未知文字完整可见，操作仍有明确取消／下载／上传入口。360dp 明暗主题回归由既有 AppShell 场景覆盖。原生鼠标／触摸由 Flutter 集成 tester 驱动，不声称执行人工桌面点击。

## Standards

独立规范审查针对 `519646b…` 到 `363cfb0` 提出1项P2：新增实际型号仅在下层断言，尚缺已确认 AppShell 主边界可重复回归。已沿用现有 AppShell 四平台／主题场景，增加实际厂商／型号经上传进入预览，以及其他旧设备型号未知的断言；单文件5项测试通过，追加提交 `598d1c3`；独立复核确认原P2消除，当前未解决0项。真实云 fixture 也按 AppShell 主边界核对通过。未发现其他强制规范违规。

## Spec

独立需求审查0项实施问题：型号贯通原生、上传、存储、下载与预览，缺列回退、旧数据未知、设备名及旧 RPC 调用兼容满足要求，未见削弱身份隔离或版本检查。真实设备与隔离服务结果已由主代理复核，五张预览截图已目视核验；最终未解决0项。


实际设备命令从 WSL 经 `cmd.exe /c` 调用：

```text
flutter test integration_test/issue_70_cloud_metadata_test.dart -d <平台> --dart-define=ISSUE70_PHASE=<阶段> --dart-define-from-file=.dart_tool/issue70-cloud-control.json
```

Android 另加 `--no-uninstall`，使用 `emulator-5556`、Android15/API35；Windows11 版本实查 `10.0.22631.0`。runtime 通过 ADB reverse30347 提供隔离会话；控制文件有 Windows 当前用户 ACL，测试定义只包含运行时控制令牌，服务端密钥与真实密码没有编译进客户端。

| 平台／阶段 | 实际结果 |
| --- | --- |
| Android15 / android-upload | 1 passed，另1个Windows专用用例跳过；真实品牌／型号上传revision1，预览可见。 |
| Windows11 / windows-roundtrip | 2 passed；Android下载→Windows上传revision2、RLS隔离、过期预览保留目的端、旧goals表未知元数据下载均通过。 |
| Android15 / android-download | 1 passed，另1个Windows专用用例跳过；预览Windows来源，确认恢复两端记录／描述及成功指纹。 |

最后 `flutter analyze`（包含新增集成入口）再次 No issues found。测试执行保留正常用户数据，使用临时独立文件数据库和隔离测试身份；未清数据、卸载应用或擦除 AVD。历史5554挂起设备未使用。

## 普通构建与清理

普通 debug APK仅使用临时公开配置中的 `SUPABASE_URL` 和 `SUPABASE_PUBLISHABLE_KEY`，`flutter build apk --debug --dart-define-from-file=.dart_tool/issue70-public-build.json` 通过（16.9秒）；5556执行 `adb install -r` 返回Success，保留数据且未登录真实账号。Windows 同样仅公开配置的 `flutter build windows --debug` 通过（11.6秒），没有启动真实账号；临时公开构建配置已删除。测试 runtime 正常退出，临时Auth用户、注册资格、快照和旧goals fixture均为0；独立免费 nano 项目删除成功，管理API复查仅保留原共享Pacta，项目状态和控制文件已删除，ADB reverse已移除。安全摘要见[云验收结果](evidence/issue70-cloud-results.json)。本轮只部署隔离项目；共享云库仍需按Supabase README应用型号迁移后才能接收新型号上传。
