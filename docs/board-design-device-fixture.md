# 看板重构 Android 设备验证

设备夹具：`integration_test/board_design_device_test.dart`。使用假认证、内存数据库和本地假日历，不登录真实账号，也不写入云端。

夹具包含一个目标与任务、13 分钟有效专注记录、一项已点亮国策和一条今日只读日历活动。验证看板保留任务、国策、近期活动和今日日历；检查点说明、时区说明和时区/日历来源入口不出现在看板。随后从“我的”选择并保存 `America/Los_Angeles`，打开日历来源页确认假来源可见。

夹具还将视口设为 360 dp、文字缩放设为 2 倍、平台亮度设为深色，并检查近期活动与日历内容可滚动访问且没有 Flutter 布局异常。

## 运行结果

在 Windows Android 模拟器 `emulator-5554`（Android 15 / API 35）运行：

```powershell
flutter test integration_test/board_design_device_test.dart -d emulator-5554
```

实际命令通过 Windows `cmd.exe` 调用 Flutter 3.47.2。结果：APK 构建并安装成功，`00:09 +1: All tests passed!`。常规项目完整测试由主任务验证。

设备截图保存在本地 `build/ui-layout-evidence/`，不纳入版本库：`board-redesign-overview.png` 展示看板首屏，`board-redesign-activity-and-calendar.png` 展示近期活动和今日日历。窄屏、2 倍文字和深色模式由设备测试覆盖；截图驱动在视口切换时未稳定返回，因此没有将错误页面截图作为窄屏证据。
