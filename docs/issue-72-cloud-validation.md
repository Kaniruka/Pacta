# Issue 72 隔离云服务验收

本记录只承载隔离 Supabase 与真实 AppShell 的服务证据；原生生命周期、进程重启和流程期间提醒见 [Issue 72 总验收](issue-72-validation.md)。不向共享 Pacta 项目写入业务数据。

## 设施与边界

`scripts/issue72_cloud_choice_acceptance.py` 复用 Issue 71 的 Management API 目标名称保护、迁移、RLS/CAS 探针、临时身份与服务清理。目标项目名称固定为 `Pacta issue72 disposable validation`；本轮独立创建 Nano 项目。state 位于被忽略的 `.scratch/issue72/isolated-state.json`，公开记录不含管理凭据、Auth 会话或运行时控制令牌。

运行时协议沿用 Issue 71，Flutter 配置 `.dart_tool/issue72-cloud-control.json` 仍使用 `ISSUE71_RUNTIME_CONTROL`，服务实际端口为 **30348**。该配置仅包含随机 loopback 控制能力，服务端凭据不传入 Flutter。Android 使用 `adb reverse tcp:30348 tcp:30348`；Windows 可从宿主 loopback 访问 WSL 服务。`scripts/issue72_run_cloud_acceptance.py` 负责执行与结构化结果：Android 临时锁定竖屏浅色并在 finally 恢复此前旋转/夜间模式，收到测试 marker 后由宿主发送真实 ADB `KEYCODE_BACK`；测试确认弹层消失、未写忽略标记且下次检查重新提示。

`integration_test/issue_72_cloud_choice_test.dart` 在每端运行真实 AppShell、真实本地 Drift 及真实 Supabase Auth/PostgREST。为缩短节流等待，注入可控检查时钟并调用测试生命周期回调；这些回调不作为原生前后台证据。点击由 Flutter tester 注入，Windows 使用 mouse，Android 使用 touch；不声称人工 OS 点击。场景涵盖：

- 首次发现2001年业务时间的快照也提示；旧云数据以稳定 token 判断版本。
- 取消后再次满足前台检查条件会提示；忽略后同版本不再自动提示且手动入口仍可打开预览。
- 独立同用户认证客户端通过公开上传 RPC 产生 revision 2、第二设备名，保持旧业务时间；旧记录内容修改产生新 token；两者均重新提示。
- 检查、取消和忽略保持本机业务指纹、行数与同步成功记录不变，AppShell 客户端无写快照 RPC；异用户无法读取该用户快照或旧数据。

## 已执行

2026-10-25：

```text
python3 scripts/issue72_cloud_choice_acceptance.py create-project
python3 scripts/issue72_cloud_choice_acceptance.py prepare
python3 -m py_compile scripts/issue72_cloud_choice_acceptance.py
cmd.exe /c dart format integration_test/issue_72_cloud_choice_test.dart
cmd.exe /c dart analyze integration_test/issue_72_cloud_choice_test.dart
```

单文件 Dart analyze 通过（No issues found）。创建独立项目成功。全部当前迁移应用成功；RLS/CAS 回滚 SQL、真实 owner read、跨用户隔离、旧数据读取、只读前后云摘要一致、revision 变化、旧 token 变化及临时探针身份/快照清理通过。结构化记录见 [服务准备证据](evidence/issue-72/cloud-service-prepare.json)。

两端真实服务均 **1 passed**，每次测试包含 snapshot 和 legacy 两个场景：

| 平台 | 实际命令 | 结果与证据 |
| --- | --- | --- |
| Android 15 | `python3 scripts/issue72_run_cloud_acceptance.py android` | 44 秒，snapshot/legacy 均通过；真实 ADB 系统返回关闭但未忽略，前台重提示；portrait 浅色、touch 输入；[结构化结果](evidence/issue-72/cloud-android.json) |
| Windows 11 | `python3 scripts/issue72_run_cloud_acceptance.py windows` | 43 秒，snapshot/legacy 均通过；mouse 输入、暗色限宽对话框；[结构化结果](evidence/issue-72/cloud-windows.json) |

主代理核对两端日志中的两条 `ISSUE72_REAL_CLOUD_PASS` 和最终成功行，并独立目视 Android 浅色、Windows 暗色截图。Android截图：[首次旧时间快照](evidence/issue-72/android-cloud-device-first-choice.png)、[第二客户端上传后新版](evidence/issue-72/android-cloud-device-new-version-choice.png)、[旧云数据首次](evidence/issue-72/android-cloud-legacy-first-choice.png)、[旧 token 变化](evidence/issue-72/android-cloud-legacy-new-version-choice.png)。Windows对应截图：[首次](evidence/issue-72/windows-cloud-device-first-choice.png)、[新版](evidence/issue-72/windows-cloud-device-new-version-choice.png)、[旧数据首次](evidence/issue-72/windows-cloud-legacy-first-choice.png)、[旧数据变化](evidence/issue-72/windows-cloud-legacy-new-version-choice.png)。

Android初始两次 host launcher 因 Windows 子进程 PATHEXT 继承仅含 `.CPL` 而无法运行 `WHERE`/Git，未进入业务测试；修复 runner 为显式使用 Windows Machine+User 的 PATH/PATHEXT 后按原入口通过。失败日志保留在被忽略目录。所有设备阶段都带 `--no-uninstall`；runner 的异常路径先定向终止自己启动的进程树，再逐项尝试恢复设置并落盘。Android 旋转与 night 设置实际恢复到原值（`1` / `0` / `yes`），主代理另用 ADB 独立复核。

## 清理与普通产物恢复

每批 runtime 结束已清理临时 Auth 用户、快照、旧 Goal 和控制文件。主代理再次执行 `cleanup-stale` 确认 `users=0 snapshots=0 legacy_goals=0` 后删除独立项目；直接调用 Management API 独立确认目标项目 GET 为 **404**，项目列表仅剩共享 `Pacta`，本地 project state 和控制文件不存在。详见 [清理证据](evidence/issue-72/cloud-cleanup.json)。

`flutter build apk --debug -t lib/main.dart` 与 `flutter build windows --debug -t lib/main.dart` 均成功，只传临时 JSON 中的 `SUPABASE_URL` 和 `SUPABASE_PUBLISHABLE_KEY` 两个公开字段，临时配置已删除。首次 Android `install -r` 因测试运行时断开而失败；恢复阶段启动已有 `PactaT24Secondary` AVD（不擦除数据，端口5556，型号 `sdk_gphone64_x86_64`、Android15），随后 `install -r` 输出 **Success**。这次恢复设备与此前消失的测试 runtime 身份不同，不把新 AVD 安装记录扩展为原生或云验收证据；验收均在断开前完成。未启动真实账号、未清除用户数据。[普通产物记录](evidence/issue-72/normal-artifacts-restored.json)保留首次失败和重试成功。
