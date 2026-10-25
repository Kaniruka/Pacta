# Issue 72 隔离云服务验收

本记录只承载隔离 Supabase 与真实 AppShell 的服务证据；原生生命周期、进程重启和流程期间提醒见 [Issue 72 总验收](issue-72-validation.md)。不向共享 Pacta 项目写入业务数据。

## 设施与边界

`scripts/issue72_cloud_choice_acceptance.py` 复用 Issue 71 的 Management API 目标名称保护、迁移、RLS/CAS 探针、临时身份与服务清理。目标项目名称固定为 `Pacta issue72 disposable validation`；本轮独立创建 Nano 项目。state 位于被忽略的 `.scratch/issue72/isolated-state.json`，公开记录不含管理凭据、Auth 会话或运行时控制令牌。

运行时协议沿用 Issue 71，Flutter 配置 `.dart_tool/issue72-cloud-control.json` 仍使用 `ISSUE71_RUNTIME_CONTROL`，服务实际端口为 **30348**。该配置仅包含随机 loopback 控制能力，服务端凭据不传入 Flutter。Android 使用 `adb reverse tcp:30348 tcp:30348`；Windows 可从宿主 loopback 访问 WSL 服务。

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

Android 15 / Windows 11 真实 AppShell 服务测试与最终清理结果待本轮实际运行后补记。
