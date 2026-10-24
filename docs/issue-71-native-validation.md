# Issue #71 原生生命周期验收记录

日期：2026-10-25（Asia/Shanghai）。本记录只覆盖 Android 15 / Windows 11 的进程、前后台和系统网络证据；隔离 Supabase 读路径见 [云端验收记录](issue-71-cloud-validation.md)。业务 AppShell、Drift 与 CloudVersionCheck 回归结果见[总验收记录](issue-71-validation.md)。

## 入口与控制

入口：[issue_71_lifecycle_device_test.dart](../integration_test/issue_71_lifecycle_device_test.dart)。每个平台使用唯一 run ID，在应用支持目录创建独立 SQLite 文件和控制 JSON；文件不删除。`exercise` 初始化一份本地目标、任务和成功同步基线，打开真实 `AppShell`，再等待外部原生生命周期事件。`cold-verify` 和 `network-verify` 用同一 run ID 在新进程打开原文件，比较本地业务 fingerprint、成功时间与云版本检查前后的业务传输数。

测试进程仅在 `127.0.0.1:30349` 暴露控制端点，请求头 `X-Issue71-Control` 使用本次运行的本地 fixture token；不使用 Supabase 凭据。`GET /status` 返回 runner PID、lifecycle 状态、检查／传输计数和 Connectivity 状态。`POST /control` 可推进注入时钟、设置受控 remote 错误／版本，或在真实网络恢复后发送验收同步标记。Android 的后台前台由 ADB 完成；Windows 由测试入口的 Win32 `ShowWindow` / `SetForegroundWindow` 驱动，并通过 `GetWindowThreadProcessId` 核对窗口属于当前 runner。

## Windows 11

原生 runner 首轮构建成功。经修正本地国策仓储首次初始化和初始 `resumed` 计数后，运行 `win20261024c` 的 exercise 观察到 PID `23132`、启动检查 `inspectCount=1`、业务传输 `1`。三轮实际窗口最小化／恢复均完成，测试端确认每轮先进入后台态再回到 `resumed`：

| 轮次 | 控制状态 | 检查结果 | 本地业务／成功时间 |
| --- | --- | --- | --- |
| 1 | 时钟 +299 秒，remote 失败开启 | 检查受 5 分钟节流；次数仍为 1 | fingerprint 与成功时间不变，传输仍为 1 |
| 2 | 再 +1 秒，remote 失败开启 | 检查次数到 2，卡片显示可重试错误 | fingerprint 与成功时间不变，传输仍为 1 |
| 3 | 再 +300 秒，remote 恢复、revision 变为 3 | 检查次数到 3，卡片显示待处理更新 | fingerprint 与成功时间不变，传输仍为 1 |

这三轮的断言均通过。exercise 随后等待真实 Wi-Fi 重连同步点。宿主检查曾观察到 Connectivity 从 `[wifi, other]` 变为 `[other]`，随后恢复 `[wifi, other]`；期间 runner 计数仍为 `inspectCount=3`、`businessTransfers=1`。Windows `netsh wlan disconnect` 返回非零，但主代理观测到 Connectivity 状态变化；`finally` 路径尝试用已有 WLAN profile 恢复。测试进程在发送重连同步标记前退出，因此该次 exercise **不记为整体通过**。2026-10-25 只读系统复查显示无线适配器 `Up`、连接 profile 数为 1、IPv4 connectivity 为 `Internet`，网络已恢复。

2026-10-25 的新进程 `cold-verify` 已通过：PID `40656`（不同于 exercise PID `23132`）打开同一独立库；启动检查使 inspect 次数从 3 增至 4，业务传输保持 1；本地 fingerprint `-213de28231d32763` 与上次成功时间 `2026-10-24T07:44:55.230707Z` 均与持久基线一致。

2026-10-25 `network-verify` 已通过：runner PID `19596` 用新进程打开同一独立库，冷启动检查满足测试的“检查次数比进程启动前增加 1”断言，最终 inspectCount 为 6，传输仍为 1；本地 fingerprint 和成功时间保持不变。测试入口内的 `GetWindowThreadProcessId` guard 确认窗口属于当前 PID；原生状态为 `hidden → inactive → resumed`，resumeCount 到 1，inspectCount 仍为 6。

随后 host Connectivity 实际观察到 Wi-Fi 从 `[wifi, other]` 变为 `[other]` 并恢复 `[wifi, other]`。恢复使用原 WLAN profile 的 `try/finally` 调用；断开期间 runtime loopback 仍可用。测试收到 network reconnect marker，断言恢复没有增加 inspection 或业务传输；Windows `network-verify` 最终 `1 passed`。

## Android 15 / API 35

设备为既有 AVD `PactaT24Secondary` / `emulator-5556`，保留数据。2026-10-25 exercise 进程 PID `8771`，唯一 run ID `android20261025a`；实际通过 ADB `KEYCODE_HOME` 送入后台，再以 `monkey -p com.pacta.pacta 1` 恢复三次。runtime lifecycle states 每轮均有 `hidden/paused → resumed`，resumeCount 到 3。三轮结果与 Windows 相同：4:59 节流、5 分钟处受控 remote failure 可重试、之后成功读取新 revision；inspectCount 最终为 3、businessTransfers 保持 1。

第四阶段通过 ADB 在 `try/finally` 中 `svc wifi/data disable` 后重新 enable。运行时 `Connectivity` 实测 `wifi → none → wifi`；恢复后 inspectCount 仍为 3、businessTransfers 仍为 1。fingerprint `4a4364ba3737276d` 与成功时间 `2026-10-24T19:13:07.410317Z` 前后相同。Android exercise 命令最终 **1 passed**。已取出 [Android 失败状态卡片](evidence/issue71-android-failed.png)和[Android 恢复状态卡片](evidence/issue71-android-recovered.png)截图。

随后执行 `adb shell am force-stop com.pacta.pacta`，未清数据或卸载；以相同 run ID、`--no-uninstall` 启动 cold-verify 的前三次尝试，Flutter 在断言前收到 `WebSocketChannelException: Connection closed before full header was received`。这些失败属于调试连接故障，不记作业务断言结果。

诊断保留原始 Logcat 后，手动启动同 APK 得到存活 PID `9622`；其真实 VM service 经 host `9351` → device `39875` 可成功读取 `getVM` / `getIsolate`，排除 Activity 启动失败和基础 ADB 转发故障。失败的 Flutter 日志在 Activity 启动后仅 **2 ms** 就拾取旧 VM 地址，目标端口随后 connection refused。唯一修复操作是 `adb -s emulator-5556 logcat -c`；保持默认 DDS、同一源码入口、原 run ID 与所有应用数据，再执行原 cold-verify 命令即 **1 passed / exit 0**。该结果支持旧 Logcat 缓冲中的 VM 地址被误拾取这一诊断；未修改产品代码或验收入口，也未停用 DDS。

成功命令（控制令牌通过本机 fixture 环境变量传入，不记录令牌值）：

```bat
flutter test -v integration_test/issue_71_lifecycle_device_test.dart -d emulator-5556 --no-uninstall --dart-define=ISSUE71_PHASE=cold-verify --dart-define=ISSUE71_RUN_ID=android20261025a --dart-define=ISSUE71_CONTROL_TOKEN=%ISSUE71_CONTROL_TOKEN%
```

成功的新进程 PID `9710` 不同于 exercise PID `8771`。Flutter 等待 **1556 ms** 后识别新 VM，host `1202` → device `42937` 完成连接。`ISSUE71_COLD_VERIFY_PASS` 和 `ISSUE71_NATIVE_PASS` 确认启动检查使 inspectCount 从 3 增至 **4**，businessTransfers 保持 **1**；fingerprint `4a4364ba3737276d` 和成功时间 `2026-10-24T19:13:07.410317Z` 与持久基线一致。独立 SQLite／控制 JSON 保留。可公开的 PID、端口、时序与断言摘要见 [Android 冷启动诊断结果](evidence/issue71-android-coldverify-summary.txt)；含调试认证地址的原始日志只保留于被忽略的 `.scratch/issue71/`。

## 未计为通过的初始化尝试

- `win20261024a` 在第一次 AppShell 挂载时新增国策 checkpoint 维护与 `focus_sync_sources` 初始化行，导致基线过早捕获；入口现于捕获前通过公开本地仓储 API 完成这项幂等初始化，并继续做完整 fingerprint 比较。
- `win20261024b` 把 runner 启动时初始 `resumed` 误当作一次前后台循环；入口现只累计观察到 `hidden` / `paused` 后再出现的 `resumed`。

上述初始化尝试均不代表产品回归失败，也未清除对应独立数据库。Android cold-verify 的旧 VM 地址问题已通过清理 Logcat 缓冲修复；最终验证保留了独立数据库和控制文件。
