# Issue #70 原生设备读取证据

日期：2026-10-24。此记录只覆盖本机设备信息读取，不覆盖云端往返验收。

## Windows 11

命令：

```bash
cmd.exe /c flutter test integration_test/issue_70_device_metadata_test.dart -d windows --reporter expanded
```

结果：构建及原生集成测试通过（1项）。运行时由 Windows BIOS 注册表读取 `SystemManufacturer` 和 `SystemProductName`。该次采集发生在恢复原有设备名格式之前，原生输出中的裸主机名是历史采集值；最终格式为“主机名（Windows）”，由后续真实云 fixture 验证。

```text
manufacturer=ASUSTeK COMPUTER INC.
model=ASUS TUF Gaming A15 FA507UV_FA507UV
```

仅读取并输出设备名、厂商和机型；未查询或输出序列号。

## Android

当时 `flutter devices` 将 `emulator-5554` 标记为 offline，未取得 Android 原生运行结果。需在 Android 15 设备恢复在线后运行同一 fixture，并记录 `Build.BRAND`（Dart `manufacturer` 字段）和 `Build.MODEL`；本条不构成 Android 验收通过。

## 最终真实云 fixture 的原生读取

入口 `integration_test/issue_70_cloud_metadata_test.dart` 在真实 PactaApp 组合入口调用同一个 `SourceDeviceInfo.load()`，不是注入合成设备名。最终读取与云端回读一致：

| 平台 | 保留的设备名 | 品牌／厂商 | 型号／机型 |
| --- | --- | --- | --- |
| Android15，emulator-5556 | `localhost (Android)` | `google` | `sdk_gphone64_x86_64` |
| Windows11 | `FA507UV (Windows)` | `ASUSTeK COMPUTER INC.` | `ASUS TUF Gaming A15 FA507UV_FA507UV` |

两端本轮实际均有可用型号；unknown 回退由既有 AppShell 主边界替换外部云 metadata 验证，旧表未知信息另有真实服务 fixture。完整往返、截图及清理结果见[最终验收](issue-70-validation.md)。
