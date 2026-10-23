# Issue #67：统一预约和直接专注的上次模式记忆

日期：2026-10-23。实施基点 `24ac7800f325c5263af4b90af37f24cb3f08ecad`，当前分支 `master`；开始时工作区干净。

## 范围与边界

以 Issue #67、专题规格 User Stories 32–34 及 Testing Decisions 为依据。主边界为真实 AppShell/页面＋本地仓储/Drift，替换外部认证、云端及设备读取；下层仅补充事务回滚与用户隔离等难以在页面稳定制造的风险。按 ADR0007/0008 保留正常字号、响应式、鼠标/触摸及 Android 系统返回验收。

成功预约和直接专注均记住模式；试选、取消、失败及恢复已有流程不写入另选模式。预约取消不撤回记忆，不改变历史归属。无需修改 Supabase 协议或真实服务数据。

## 实现

预约创建、同步队列与模式偏好在同一个本地事务提交；直接专注复用相同偏好保存方法。任何偏好写入失败均回滚业务启动。专注主页移除生命周期内的模式缓存，在打开任务选择时读取当前用户的最新持久偏好，避免看板启动后主页仍沿用旧值。原有活动流程优先恢复，不用另选模式覆盖原流程或偏好。

保留筛选预选与设置内切换、首次普通、预约取消不撤回模式的规则，不变更预约编辑、历史归属、链结算、计时或云端协议。

## 自动化验证

Windows Flutter/Dart 由 WSL 通过 `cmd.exe /c` 调用。

| 命令/边界 | 实际结果 |
| --- | --- |
| `dart format lib/main.dart lib/src/focus/focus_repository.dart test/focus/focus_repository_test.dart test/focus/focus_task_navigation_test.dart` | 完成 |
| `dart format integration_test/issue_67_mode_memory_device_test.dart` | 完成 |
| `flutter analyze` | No issues found |
| `flutter analyze integration_test/issue_67_mode_memory_device_test.dart` | 最终截图版 No issues found |
| `flutter test test/focus/focus_task_navigation_test.dart test/focus/focus_repository_test.dart` | 41 passed |
| `flutter test` | 285 passed，26秒 |
| `git -c core.whitespace=cr-at-eol diff --check` | 通过 |

两项 App 回归在修复前分别因「预约取消并重建后丢失精锐默认」和「从其他入口启动后主页仍预选普通」失败，修复后通过。主边界沿用真实页面操作：看板直接启动后回专注主页、预约取消后重建、试选普通并取消、成功直接普通后重建。已有恢复流程回归随完整测试执行。

下层四种失败场景以 SQLite 触发器拒绝首次 INSERT / 已有 UPDATE，分别验证预约和直接专注均不部分落盘、原偏好保留。独立文件数据库补充不同用户隔离及关闭重开后的记忆。Drift 多实例调试提示来自独立执行器的文件复开测试；测试无失败。

## 平台验收

Android 15 / API35 与 Windows 11 使用独立 SQLite 文件和离线外部替身，不触碰用户业务数据库，不进行 Supabase 写入。两端各运行三阶段原生测试：首次普通及取消不变→成功直接精锐；退出进程后恢复原专注→结束后成功预约普通；再次退出进程后恢复原预约→取消不回撤→两条路径写入失败回滚。精锐用户与另一个首次普通用户隔离。

Android 三阶段 PID 为 `15857 / 15993 / 16089`，Windows 为 `30340 / 10148 / 11168`，各阶段通过。通过分别启动原生应用进程和同一隔离文件取证，区别于单次运行内 widget 重建。命令与详细证据见[设备验收记录](issue-67-device-validation.md)。

主代理目视复核两端设置、预约恢复、错误状态共六张实际运行截图：Android 正常字号窄屏亮色、Windows 正常字号宽屏暗色，模式值和操作可见，无溢出。错误注入显示现有 SQLite 排错内容，取消与两种启动按钮仍可操作。截图位置及平台运行限制见设备记录。

设备操作由集成测试驱动，并非人工触摸/鼠标取证；两端实际应用进程、文件持久化和画面均已运行。普通 APK / Windows Debug 产物均已重新构建；Android `adb install -r` 成功，保留用户数据且未启动真实账号应用。仅传公开客户端配置，临时配置已删除。

设计自查依据 apple-design `entering-data.md › Best practices`（合理默认、提供选择）及 `pickers.md › Best practices`（值可预测），转译为 Flutter 既有模式下拉与启动确认；ui-ux-pro-max Flutter 表单指导用于确认提交前校验。保留现有 Material 3 主题和布局，无新增视觉组件。

## Standards

独立子代理审查：0 项发现。事务边界、偏好归属与 App/下层测试边界符合仓库规则；未发现有实质影响的代码异味。

## Spec

独立子代理审查：0 项实现错误、缺失行为或越界改动。US32–34、事务内成功写入、首次默认与跨入口最新偏好、筛选预选、原预约不变与取消不回撤均符合规格。平台验收由主代理另核对实际运行及截图，不将测试脚本当作通过证据。

两轴合计：Standards 0，Spec 0，无未解决发现。

## 票据关系

GitHub 原生 blocked_by / blocking 实施前均为空；无需删除其他票据关系，父票 #63 保留。交付操作为提交并推送当前 `master`、勾选验收清单、移除 `ready-for-agent` 标签并关闭 #67；提交标识与最终远端状态记录在 Issue 完成评论。
