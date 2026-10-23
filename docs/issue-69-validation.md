# Issue #69 实施与验收

日期：2026-10-23–24（Asia/Shanghai）。票据：[T06: 简洁同步卡片与可持久的安全同步结果](https://github.com/Kaniruka/Pacta/issues/69)。比较基点：`413c02ea73223db08b44ce7dbf029afcc8634daf`，当前分支 `master`；开始时工作区干净。

## 实施及已确认边界

- 常驻卡片只保留入口和状态摘要；正常右侧显示本机当前用户成功时间，无记录显示“尚未同步”，工作、失败、已知云版本待处理优先。自动发现和忽略由后续票交付。
- Android 使用底部弹窗，Windows 使用最大560逻辑像素居中对话框；查看、明确选择方向、二次确认覆盖。双方时间、来源、整份丢弃后果保留。未知本地基线明确提示无法确认；指纹变化时提示尚未同步修改。未结束预约／专注允许上传、禁止下载，过期预览要求重新检查。
- 成功时间、实际上传／恢复的本地指纹、云 revision／legacy token 保存于安装本机的按用户偏好，不进入业务快照。下载恢复后的指纹在替换事务中计算。检查、取消及传输／事务失败不更新成功记录。
- 传输成功后偏好落盘失败单独返回完成结果，下载仍刷新页面；明确提示数据已传输但本机记录未保存，不能把已提交替换描述成目的端未变化的失败。
- 测试沿用专题规格 Testing Decisions：真实 AppShell、真实仓储／Drift，替换认证与远端；下层仅补指纹／版本过期、事务回滚、用户隔离及持久化失败。ADR0007/0008 范围适用，既有200%文字测试保留，没有新增读屏、大字号或专门键盘验收要求。

## 原生设备证据

入口 `integration_test/issue_69_sync_result_device_test.dart` 使用独立文件库和身份 `issue69-native-native20261023a`，真实 AppShell／本地仓储，外部云替身。未打开或删除普通业务数据库。write 阶段通过弹层返回、确认取消、上传，保存成功时间；verify 为独立新进程，读取同一文件和偏好并断言成功时间完全相同，再只检查、取消，确认时间仍相同。

| 平台 | write | 新进程 verify |
| --- | --- | --- |
| Windows 11 `10.0.22631.2506` | 1 passed，PID18460 | 1 passed，PID29688 |
| Android15 / API35，`PactaT24Peer`、`emulator-5554` | 1 passed，PID17702 | 1 passed，PID17823 |

命令：`cmd.exe /c flutter test integration_test/issue_69_sync_result_device_test.dart -d <windows或emulator-5554> --dart-define=ISSUE69_PHASE=<write或verify> --dart-define=ISSUE69_RUN=native20261023a`；Android另加`--no-uninstall`，阶段间执行`adb shell am force-stop com.pacta.pacta`。没有清数据或擦除模拟器。设备驱动为Flutter原生tester自动鼠标／触摸语义，并非人工操作。

截图保存于各平台应用支持目录的`issue69-{choice,confirmation,write,verify}.png`；主代理目视核验Android底部选择层、Windows居中选择层及两端恢复后的时间卡片。截图使用正常字号，Android浅色、Windows深色。已保留[Android选择层](evidence/issue69-android-choice.png)、[Android重启时间](evidence/issue69-android-restored-time.png)和[Windows选择层](evidence/issue69-windows-choice.png)截图。选择层截图的背景卡片来自修正右对齐前的首轮原生运行；重启截图已显示修正后的右对齐。窗口360dp两主题状态矩阵由App级回归覆盖。Windows Computer Use两次初始化均因`sandboxCwd is not a local file URI`失败，未声称完成该工具的桌面点击验收。

## 自动化与真实服务

Windows Flutter 3.47.2 / Dart3.13.2，经`cmd.exe /c`：

| 命令 | 结果 |
| --- | --- |
| `dart format`（所有修改Dart文件） | 通过 |
| `flutter analyze` | No issues found |
| `flutter test test/sync/cloud_snapshot_repository_test.dart` | 21 passed |
| `flutter test test/sync/manual_cloud_sync_app_test.dart test/sync/cloud_sync_card_test.dart` | 8 passed |
| `flutter test --reporter compact`（最终稳定版本） | **300 passed** |
| `flutter test integration_test/manual_cloud_sync_device_test.dart -d windows` | 1 passed |
| 同一入口 `-d emulator-5554 --no-uninstall` | 1 passed |
| `git diff --check` | 通过 |

首次完整测试与P2修复中的测试／代码编辑重叠，Windows深色失败注入断言失败；定向7项通过后，新增退出登录异步提示回归使定向共8项；最终稳定版全量300项通过。没有将失败轮次记为通过。原生完整流程在两端分别通过明确上传、修改本地、下载及业务恢复。Android构建输出flutter_timezone的Kotlin Gradle未来兼容警告，未影响结果。

2026-10-24凌晨在独立项目`ekjxqxafmwbyipdrprcz`（`Pacta issue69 disposable validation`）实测。创建前核验组织免费计划及仅有一个共享项目，使用nano实例，无套餐升级或共享业务写入。旧令牌HTTP401、首次替换令牌组织403后，由用户提供组织范围令牌恢复；令牌未提交或编译进客户端。

- 26份迁移全部应用；`supabase/tests/cloud_business_snapshots.sql` rollback RLS/CAS探针通过。额外真实SQL验证停用用户不能读取快照、上传SQLSTATE42501、原目的端版本／payload保持，事务回滚并删除临时权限用户。
- 复用现有`manual_cloud_sync_real_service_test.dart`和回环运行时服务；控制文件`.dart_tool/issue69-cloud-control.json`由Windows当前用户ACL保护，测试定义只传运行时控制令牌，服务端密钥及测试会话由运行时提供。ADB reverse30347仅用于测试。
- 实际命令：`flutter test integration_test/manual_cloud_sync_real_service_test.dart -d <平台> --dart-define=MANUAL_SYNC_REAL_CLOUD_PHASE=<阶段> --dart-define-from-file=.dart_tool/issue69-cloud-control.json`，从WSL经`cmd.exe /c`执行；Android加`--no-uninstall`。

| 平台／阶段 | 结果 |
| --- | --- |
| Windows / windows-conflict | 1 passed、1 intentional skip；本地预览后修改，上传和下载均拒绝，local fingerprint／cloud revision／成功时间不变；真实RPC并发HTTP409；传输替身离线恢复；旧v1兼容；非法下载拒绝且本地不部分覆盖。 |
| Android15 `emulator-5554` / android-upload | 1 passed、1 intentional skip；明确确认后上传revision1，成功结果版本及本地基线一致。 |
| Windows11 / windows-roundtrip | 1 passed、1 intentional skip；明确下载Android快照，新增Windows记录后明确上传revision2，描述及成功结果正确。 |
| Android15 `emulator-5556` / android-download | 1 passed、1 intentional skip；明确下载revision2，Android和Windows记录／描述、专注与国策记录保留，成功版本及实际恢复基线正确。 |

首轮windows-conflict通过后补入真实本地预览过期场景，重跑同样通过。最后Android阶段因ADB getprop停滞中断，重启ADB后原`PactaT24Peer`进入Windows终止僵持状态；保留其磁盘，使用已有`PactaT24Secondary`（5556、Android15）完成下载。没有清数据、擦除或卸载，两台都是本任务测试AVD。停滞轮次不记为通过；传输替身断网不声称为真实网络断开。

完成后停止运行时、删除两个会话用户；真实SQL核验`auth.users=0`、快照0、注册资格0。删除独立项目并重新查询项目列表，只有原共享Pacta；控制／状态文件已删除，5556 reverse为空。安全汇总见[云验收结果与清理](evidence/issue69-cloud-results.json)。原始命令日志位于本机被忽略的`.scratch/issue69/`，正文只记录实际结果。

## Standards

独立规范审查最终0项未解决。未使用的外部待处理参数已删除，当前已知状态来自实际检查；Speculative Generality建议已处理。

## Spec

独立需求审查最终0项实施问题。Standards与Spec由独立子代理对同一基点并行审查，两轴均指出“数据传输成功但本机记录落盘失败被误报为同步失败，下载跳过刷新”的P2；实现已按独立完成结果修复，并补公开边界失败注入测试。收尾还发现登录页沿用根ScaffoldMessenger时，旧异步传输可能显示上一用户提示；已在既有App边界补失败测试，按操作身份检查反馈并保留同用户下载刷新提示。父代理复核身份检查发生在传输和偏好读取的每个异步边界后，提示显示在同用户下载刷新之前；最终Standards与Spec均0项未解决，最终全量300项通过。

## 设计评审

设计依据：apple-design本地`modality.md › Best practices`的短任务、明确退出，以及`alerts.md › Buttons`的动作命名和取消；转译为Material3平台弹层，复用主题与状态文字。没有套用Apple菜单／键盘惯例，也不新增已退出范围要求。


## 普通构建与环境收尾

普通APK使用只含`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`的临时公开配置重新`flutter build apk --debug`，并对健康的`emulator-5556`执行`adb install -r`，返回Success；安装前force-stop，安装后未启动真实账号。`TEST_*`、管理员凭据、服务端密钥及控制令牌均未传入普通构建。Windows普通`flutter build windows --debug`同样使用上述公开配置构建成功，未启动真实账号。临时公开构建配置已删除。

原5554的宿主进程终止僵持尚未恢复，未擦除其磁盘或改写原业务数据库；它无法在本轮重新安装普通APK。最终真实下载及普通安装使用5556，此设备限制不冒充已修复。宿主恢复后可对5554执行`adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`恢复普通测试产物。
