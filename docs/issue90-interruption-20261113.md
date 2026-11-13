# 本轮中止点（2026-11-13）

用户通过物理 Escape 停止 Computer Use；停止继续GUI操作，收拢本轮验收进程。整体实施尚未完成，不得将PR #96标记ready或宣称验收通过。

## 主检出

- 路径仍使用 `F:/Workspace/Release/Flutter/Pacta`；聊天当前cwd可能已自动切到profile worktree，后续所有命令必须显式指定工作目录。
- 分支 `feat/sync-profile-cards-20261113`，最近已合入 #91响应式收尾与#95提醒（3886c7e）。草稿PR #96，父规格#90，子票#91–#95。
- 主检出有未提交的 `integration_test/issue_95_daily_reminder_device_test.dart` 验收增强：通知权限允许/拒绝探针、独立SharedPreferences前缀、可选真实时钟提前分钟数及事件文件、列表滚动定位。不要丢弃。

## 未合入代码与复核

- #94：worktree `C:/Users/Stray/.codex/worktrees/pacta-profile-stats/Pacta`，分支 `impl/pacta94-profile-stats`，最近交付a7a2be7（含53cdf8c Base64 ASCII空白修复、与#95原生通道合并）。worker `pacta94_base64_finalize`（session-858952ec-8805-4972-925c-b700b342f1a7）已关闭。继续前检查实际HEAD/status；536项全量测试和两端构建为worker证据，主Agent尚未独立复跑最终版。
- #93：worktree `C:/Users/Stray/.codex/worktrees/pacta-auto-upload/Pacta`，分支 `impl/pacta93-auto-upload`；worker `pacta93_auto`（session-39b9885b-2d48-465d-99fe-4d2033636823）在审查返工阶段被关闭，须检查已提交及未提交状态再恢复。待核实：取消后的晚应答不得覆盖恢复基线；意图序号防捕获期间新确认丢失；错误回调须受代次保护；不能吞其他设备云提示；purge receipt清理偏好中的冻结载荷（含仅队列残留UUID）；旧服务不支持幂等时明确停止。真实服务auto fixture也已派给此worker，状态需核对。
- #91/#92/#95实施分支保留；不要重做已经合入的内化公式。
- DSH完成后的followup曾仅入队pending而未启动；确认未写入后关闭旧worker、用同一DSH通道新建worker可恢复。勿重复启动会并发写同一worktree的任务。

## 实测证据

- #92迁移+RLS/保留15份/幂等/purge：隔离项目最终probe通过并已应用；证据 `.scratch/issue90/history-probe-20261113-175430.json`。
- #94资料SQL：主Agent最终probe通过并已应用隔离项目；证据 `.scratch/issue90/profile-probe-20261113-185023.json`。Postgres Base64第77字符换行已真实验证，客户端修复已在#94分支，仍待真实资料两端往返。
- 真实历史恢复测试 Android与Windows均通过：`integration_test/snapshot_history_real_service_test.dart`，日志在 `build/ui-layout-evidence/issue90/history-real-{android,windows}-20261113-*`。Windows实际下载Android上传的数据；15份保留、重复请求、恢复不覆盖云、跨用户HTTP隔离均通过。
- #91最终窄屏视觉收尾Android320深色已通过并目视，证据已复制到主检出 `build/ui-layout-evidence/issue90/20261113-184359-cards-polished-android-dark320`。其他基线/光暗截图见实施进度文档。
- #95主Agent `flutter test test/notifications test/calendar`：77通过。Android系统拒绝通知后核心UI可用且不重复请求探针通过：`permission-denied-android-20261113-1903`。
- Android系统已观察到真实2205提醒，但首轮错过点击窗口，整体native tap测试失败，不能宣称通过。后续2分钟提前/5分钟观察的验收运行被用户停止Computer Use打断，尚未完成。
- Windows `flutter test`启动的Pacta窗口在Computer Use中黑屏、无法激活；File Explorer窗口可正常激活，桌面不是整体不可交互。尝试以sky可见方式启动同一测试exe时，用户按Escape停止Computer Use。原生通知实际点击未验证。

## 重要验收工具纠正

本机Flutter源码确认 `flutter drive` 默认停止时会卸载测试包。前期截图运行触发了该默认收尾；实体设备从未操作，模拟器旧包名com.pacta.pacta仍在，但缺少测试前com.rukani.pacta本地数据清单，不能断言其先前无数据。已向用户如实说明。后续必须 `--keep-app-running` 并仅停止测试进程，Android `flutter test`使用`--no-uninstall`。检查 `.scratch/issue90/run_ui.py` 等runner确实含保护旗标，再继续；不要用清数据、卸载或重置AVD补验收。

## 环境与后续

- Android模拟器 emulator-5556 / PactaFocusPilot20261112；真实设备b9680744未操作。曾为窄屏设置density540，各次finally恢复420。
- 临时云项目 `Pacta issue90 disposable validation`，状态 `.scratch/issue90/isolated-state.json`；共享Pacta项目未部署。隔离项目保留供继续验收。
- loopback测试会话服务原PTY session32316，已发送Ctrl-C请求清理并停止；后续需检查确实结束以及临时账号/控制文件清理，再使用 `.scratch/issue90/serve.py` 重建。凭据只在受保护.env与内存，禁止编译.env；测试控制文件只在.dart_tool。
- 剩余：恢复#93返工、合入#94/#93，独立完整测试与真实资料/自动上传、原生通知/照片选择/日历权限验收，Standards+Spec双轴及设计评审、修复、PR转ready、清理worker/worktree/临时云资源。未授权直接合并master或部署共享云。
