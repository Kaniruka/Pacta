# Issue #69 跨入口同步摘要修复验收

日期：2026-10-26。依据[父 Issue #63](https://github.com/Kaniruka/Pacta/issues/63)、[子 Issue #69](https://github.com/Kaniruka/Pacta/issues/69)；修复前 HEAD 为 `70e0fa20bd897d48205e46aceb5f22d307283842`。初次实施按用户要求仅修复、不提交或推送；验收后用户追加授权，将本次修复、永久测试和验收证据一并提交推送。

## 根因与范围

“我的”和国策 AI 手动同步页各有一个 `CloudSyncCard`；两者共用本机按用户保存的同步结果，但常驻卡未在共享版本通知时重读自己的结果缓存。之前取消的手动预览还可能保留旧云版本，在另一个入口成功上传后误显示待处理。异步历史读取晚于新结果返回时也可能覆盖新缓存。

修复仅涉及卡片状态：版本通知触发同步结果重读；已处理并清除的云元数据同时清理旧预览缓存；读取请求序号配合原有 mounted/仓储身份检查丢弃过期成功和失败结果。没有重新创建页面、重启刷新或自动传输。

## TDD 与自动化进度

沿用已确认边界：真实 `PactaApp` / AppShell、本地仓储和内存 Drift，仅替换外部认证、云端和可注入时间／磁盘延迟。通过页面入口、目标编辑、摘要和预览文案断言。

- 永久回归加入 `test/sync/manual_cloud_sync_app_test.dart`。修复前执行 `cmd.exe /c flutter test test/sync/manual_cloud_sync_app_test.dart --plain-name "AI manual sync refreshes the existing summary and local baseline"`，返回两次后“尚未同步”仍存在，目标断言失败。
- 最小通知修复后，第二次上传摘要被旧预览版本误标待处理；清理已处理元数据后，首次同步、已有时间从 10:00 更新为 11:30，以及后续预览使用新基线通过。
- 追加同一路径的慢磁盘历史结果用例，执行 `--plain-name "delayed initial result: true"`，在请求序号保护前因旧空结果覆盖新结果再次失败；加入保护后两种读取时序均通过（2 passed）。
- `cmd.exe /c dart format lib/src/sync/cloud_sync_card.dart test/sync/manual_cloud_sync_app_test.dart integration_test/issue_69_sync_result_device_test.dart` 完成。
- `cmd.exe /c flutter analyze`：No issues found。
- `cmd.exe /c flutter test test/sync`：63 passed，包含离线检查恢复、预览过期、目的端保留、用户切换及退出时晚到结果等已有用例。
- `cmd.exe /c flutter test`：329 passed（原327项加正常／慢磁盘两项跨入口回归）。最终永久用例补充了上传成功反馈断言；把生产卡片暂时还原为修复前 HEAD 再跑正常时序，仍在“尚未同步”断言处失败；随后恢复修复并重跑全量。
- `cmd.exe /c flutter analyze`：最终再次检查，无问题；`git diff --check` 通过。

原始命令输出暂存 `/tmp/pacta-sync-card-fix/`，仅含测试样例，无真实账号或服务端凭据。

## 平台与服务边界

扩充现有 `integration_test/issue_69_sync_result_device_test.dart` 的 `cross-entry` 阶段，使用新的 RUN 身份、真实文件 SQLite、本机 SharedPreferences、禁用通知、内存云端；保留已有 write/restart 阶段。设备与云替身结果不能视为真实 Supabase 或人工鼠标／触摸验收。现有历史证据仍仅代表各自日期。

本修复不修改快照仓储传输、SQL、RLS、权限或数据库 schema；本次未连接真实 Supabase、部署 SQL 或重跑 RLS，不能将本机／内存云测试视为真实服务重新验收。授权覆盖及隔离的既有 App／仓储回归纳入上述同步目录和全量执行，历史隔离云证据未改写。

## 本次原生平台实测

```bash
cmd.exe /c flutter test integration_test/issue_69_sync_result_device_test.dart -d windows --dart-define=ISSUE69_PHASE=cross-entry --dart-define=ISSUE69_RUN=fix20261026win5
cmd.exe /c flutter test integration_test/issue_69_sync_result_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE69_PHASE=cross-entry --dart-define=ISSUE69_RUN=fix20261026android2
```

Windows 11（10.0.22631.2506）和 Android 15 / API 35（PactaT24Peer，emulator-5554）在真实原生应用内执行用户入口操作；每端 1 个用例覆盖：首次10:00摘要、看板创建目标后明确未同步警告、AI入口第二次同步后11:30摘要、常驻卡预览一致基线、取消后摘要不变。没有以重启或重建页面刷新，第二次上传对应真实业务修改。

夹具首轮补充了当前可访问状态来源（真实本地生命周期仓储＋外部认证替身），并在回到列表后滚动到同步卡、等待滚动结束再点击；Android小屏上卡片可能已被列表回收，直接ensureVisible无法定位。修正均限测试夹具，最终成功命令使用新RUN身份，不清除正常用户数据。原有write/restart分支保留，本次没有运行它们，也不以历史重启验收替代本次路径验证。

本机文件分别为 `C:\Users\Stray\AppData\Roaming\com.pacta\pacta/issue69-fix20261026win5.sqlite` 和 `/data/user/0/com.pacta.pacta/files/issue69-fix20261026android2.sqlite`。Android使用`--no-uninstall`保留数据。自动点击／滚动由integration_test驱动；本次没有人工鼠标／触屏专项验收，也没有重验无改动的原生通知／日历权限。

主代理目视核对了两端第二次同步截图：正常字号下卡片文字和时间可读，Windows暗色／Android亮色仍沿用现有主题。首、次同步截图分别为 [Windows首次](evidence/issue69-cross-entry-fix/windows-first-summary.png)、[Windows第二次](evidence/issue69-cross-entry-fix/windows-second-summary.png)、[Android首次](evidence/issue69-cross-entry-fix/android-first-summary.png)、[Android第二次](evidence/issue69-cross-entry-fix/android-second-summary.png)。它们是原生Flutter画面捕获，不是系统桌面截图；状态时间为可注入的测试时间。

## 双轴与设计复核

固定基点为修复前 `70e0fa2`。用户明确不提交，因此 `git log 70e0fa2..HEAD --oneline` 为空，`git diff 70e0fa2...HEAD` 也为空；本次审查使用 `git diff 70e0fa2 -- lib/src/sync/cloud_sync_card.dart test/sync/manual_cloud_sync_app_test.dart integration_test/issue_69_sync_result_device_test.dart`，另直接阅读新增验收文档。规范和规格由两个独立子Agent审查，主代理复核关键代码与实际测试结果。

### Standards

0项可操作问题。请求序号保护成功及失败回写，原有mounted和仓储身份保护保留；测试从真实App边界观察结果，存储延迟只使用既有注入点。未发现需要修改的Fowler基线异味。

### Spec

0项未解决问题。对照#63/#69当前正文、评论、专题规格故事41–43、57和ADR0005，首次／后续摘要与最新基线要求已覆盖；上传／下载仍需明确确认，没有自动业务传输或页面重建刷新。

设计自查读取apple-design的`feedback.md › Best practices`（状态反馈就地呈现）、`modality.md`与`sheets.md`（清晰取消和单个操作任务），转译为Flutter Android／Windows原则；无新增布局或文案。ADR0007／0008取消的大字、读屏和专项键盘要求未被引入。

## 普通产物恢复

`cmd.exe /c flutter build apk --debug --dart-define-from-file=build/issue69-fix-public.env` 和 `cmd.exe /c flutter build windows --debug --dart-define-from-file=build/issue69-fix-public.env` 均成功，恢复默认`lib/main.dart`普通Debug入口；Android `adb -s emulator-5554 install -r .../app-debug.apk` 返回`Success`。安装后停止应用，未打开真实账号；Android验收SQLite仍存在（188416字节），正常用户数据未清理。Windows仅构建，没有启动普通应用。

临时编译配置仅从本机.env筛选`SUPABASE_URL`和`SUPABASE_PUBLISHABLE_KEY`，没有传TEST_*或服务端凭据；恢复构建后删除临时文件。Android构建提示flutter_timezone未来Kotlin插件兼容性及SDK XML工具版本警告，未影响测试或构建；本次未处理无关工具链升级。

[机器可读结果及截图SHA-256](evidence/issue69-cross-entry-fix/results.json)、[最终基点红测原始输出](evidence/issue69-cross-entry-fix/red-final.log)、[慢磁盘红测原始输出](evidence/issue69-cross-entry-fix/red-delayed.log)、[Windows原生原始输出](evidence/issue69-cross-entry-fix/windows-native.log)、[Android原生原始输出](evidence/issue69-cross-entry-fix/android-native.log)。

已保存的命令日志仅去除行尾空白，其他输出内容保留。

Standards 0项；Spec 0项。父 Issue #63 已按用户授权验收关闭，ready-for-agent 已移除；[验收评论](https://github.com/Kaniruka/Pacta/issues/63#issuecomment-6401098970)保留发布时尚未提交的事实，后续提交推送信息以追加评论记录。
