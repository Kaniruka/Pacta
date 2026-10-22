# Issue #62：Android 上传与桌面 Codex 的真实服务演示

2026-10-22，使用仓库当前实现、Android 15/API35、Windows 11 与实际 Codex CLI `0.163.0-alpha.10.2`。较早模型运行使用共享开发项目内随机身份；最终两平台完整原生测试使用独立临时 Free 项目。两类证据分开，不混用临时身份与版本。

## 可重复入口

- `scripts/issue62_cross_device_demo.py` 在内存取得服务端管理凭据、创建独立随机测试用户与 OAuth client，并启动仅监听本机的受随机控制码保护的运行时桥接。`.env` 必须来自受保护环境，不能粘贴到对话。测试用户在结束、中断和已捕获异常后清理；清理失败单独报告并使进程失败。
- Android 新测试 `integration_test/national_focus_ai_real_cross_device_test.dart` 只用独立临时 SQLite，不读取或覆盖普通用户业务库。公开配置及测试会话从运行时桥接取得，不把登录密码、refresh token 或服务密钥编译进 App。
- 桥接生成的 `.dart_tool/issue62-demo-control.json` 只含本次本机控制码和端口；结束删除。需先等待 `READY`，再执行下述 Flutter 命令。测试不是普通用户安装入口。

```bash
python3 scripts/issue62_cross_device_demo.py
# 另一终端；实际设备序列号应先用 adb devices -l 核对。
'/mnt/c/Users/Stray/AppData/Local/Android/sdk/platform-tools/adb.exe' -s emulator-5556 reverse tcp:30348 tcp:30348
cmd.exe /c flutter test integration_test/national_focus_ai_real_cross_device_test.dart -d emulator-5556 --no-uninstall --dart-define-from-file=.dart_tool/issue62-demo-control.json
```

可用 `--config <保护配置路径>` 显式选择目标项目；配置含公开 URL/key 与管理 token，不能提交或输出。Windows 使用同一测试的 `-d windows`，本机需能访问 WSL 桥接端口。`--evidence` 和 `--analysis-output` 可分别保存每轮结果。`--skip-analysis` 只跳过模型，仍执行真实 Codex app-server 工具；证据显式标记跳过，不算新模型分析通过。Android 桥接增加 `--android-device <实际序列号>` 可执行 Wi-Fi/移动数据中断，读取原状态、恢复后验证没有自动上传，异常清理也恢复原设置。

桥接的 `--codex` 参数可指定已安装 CLI 路径；使用原有受保护 Codex 登录状态，模型执行只配置本次只读 MCP。必要 skill 与合同文本直接传入模型上下文，实际业务证据仍经远端 MCP 读取。

## 演示边界

Android 上通过生产领域仓储建立卡片、点亮、主动熄灭和国策结算生成真实失败及冻结树；这些维护动作由设备测试调用，**不是手工逐项点击卡片编辑 UI**。手动上传、覆盖确认、请求码核对、明确同意与撤销均驱动真实 App UI，使用真实 Supabase 仓储与 Auth。

OAuth DCR、授权请求及 PKCE 交换由演示协调脚本发起，App UI 批准后把只读委托交给实际 Codex app-server 和 Codex 模型。此结果验证协议与 App 明确同意，但**不证明普通用户的 `codex mcp login` 浏览器回调流程已实测**。模型分析与显式 app-server 工具断言分开记录。

独立项目 Android 回放实际执行原生断网/恢复；未上传编辑不可见与断网恢复是两个独立断言。不声称平板兼容性。

## 执行结果

- Windows 独立项目：1 passed，44秒；[完整真实工具及 native flow 证据](evidence/issue62-windows-native-flow.json)。
- Android 独立项目：1 passed，47秒；实际设备序列号为重启 AVD 后的 `emulator-5554`，额外执行断网错误提示、恢复和 snapshot digest 不变；[证据](evidence/issue62-android-native-flow.json)。
- 两端均完成 UI 手动上传与覆盖确认→App 明确同意→Codex 读当前/冻结失败→本机未上传编辑不可见→再次上传后读取 revision2/旧 revision 拒绝→App 撤销→六工具和 initialize/tools/list 拒绝。状态滚动/fixture 时钟/传参等验收工具缺陷修复后才记录最终 native pass；早期失败不冒充通过。
- 较早两轮实际模型输出已由主 agent 阅读，五个工具成功读取记录保留；后续模型额度耗尽，最终 native 回放显式使用 `--skip-analysis`。原始报告遗失和保留证据的范围见 [模型复核摘要](evidence/issue62-codex-analysis-review.md)。
- JSON中的旧检查键 `actual_codex_read_android_snapshot_and_frozen_failure` 是当时脚本命名，Windows 的实际 `source_device` 为 Windows；新版脚本已改成 native，不据旧键声称 Windows 是 Android。
- 临时 Free 项目两平台结束后已删除，GET404；全部保护配置/数据库口令文件删除，原开发项目和数据保留。[部署及清理证据](issue-62-service-validation.md)。
