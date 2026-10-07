# 专注链界面离线 Android 验证

入口：`integration_test/focus_chain_design_device_test.dart`。使用真实 `PactaApp`、假认证、内存数据库及独立动作设置；不读取账号凭据，不创建真实用户，不写入云端数据。

样例含两项任务、三条承诺动作；精锐和普通各含一次失败专注（有效10分钟）和三次成功专注（每次25分钟）。因此每链连续3次、累计1小时25分钟、平均21分15秒，失败时间在时长中保留。

## 常规运行

```powershell
flutter drive --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/focus_chain_design_device_test.dart -d emulator-5554
```

截图由现有 driver 保存到 `build/ui-layout-evidence/focus-chain-*.png`：首屏、记录、动作编辑、2倍字体深色、预约链记录、开始设置、进行中专注、预约准备。截图为本地验证产物，不纳入版本库。

## WSL 调用 Windows SDK 的连接替代步骤

2026-10-07 本机 Flutter drive 自动连接 VM 停滞，但显式 Dart driver 连接正常。可使用相同 Windows SDK 的 `dart.exe` 执行 `flutter_tools.snapshot build apk --debug --target=integration_test/focus_chain_design_device_test.dart`，设置 `PATHEXT` 和 `SYSTEMROOT`；snapshot 路径应为 Windows 路径。

然后用 Windows `adb.exe` 安装生成的 debug APK，以 `shell am start -n com.pacta.pacta/.MainActivity --ez start-paused true` 启动。读取本次 logcat 输出的 Dart VM service 端口与路径，通过 `adb forward tcp:7283 tcp:<设备VM端口>` 转发。把 `VM_SERVICE_URL` 设置为 `http://127.0.0.1:7283/<本次VM路径>/`，传入 Windows 环境（WSL 中在 `WSLENV` 追加 `VM_SERVICE_URL`），直接执行 `dart.exe test_driver/ui_layout_acceptance_test.dart`。不要复用旧进程的 VM 路径。

## 2026-10-07 验证证据

- Android AVD：PactaT24Peer，emulator-5554，Android 15 / API 35，截图1080×2340。
- Debug APK构建和安装成功。
- 显式 driver 运行结束：`All tests passed.`，退出码0。
- 编辑普通链动作并读取仓库确认保存；立即启动专注、启动15分钟预约准备均创建对应记录。
- 2倍字体与深色外观下记录页面无布局异常，动作可换行、时长在窄空间变为上下排列。
- 此证据仅覆盖模拟器界面和离线行为，不是通知权限、真实账号或真实云端同步验收。
