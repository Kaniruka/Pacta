import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Opens the system screen that controls this app's runtime permissions.
///
/// Android may stop presenting a permission dialog after repeated denials, so
/// the system screen stays the only way to grant a capability again. Failures
/// are swallowed: a missing settings screen must never block core features.
abstract interface class DevicePermissionGateway {
  Future<void> openNotificationSettings();
  Future<void> openAppSettings();
}

/// Android 后台运行（忽略电池优化）的状态与设置入口。
///
/// 与 [DevicePermissionGateway] 分开声明而不是塞进同一个接口：既有实现
/// （含测试替身）不必为一个新增能力补方法；生产实现
/// [MethodChannelDevicePermissionGateway] 同时实现两者，页面按需取用。
abstract interface class BatteryOptimizationGateway {
  /// 本应用当前是否在系统电池优化白名单内。
  ///
  /// 非 Android 平台没有这个概念，固定返回 true（不需要额外放行）。
  Future<bool> isIgnoringBatteryOptimizations();

  /// 打开系统的电池优化白名单列表；没有该屏幕时退到应用详情页。
  Future<void> openBatteryOptimizationSettings();
}

DevicePermissionGateway createDevicePermissionGateway() => Platform.isAndroid
    ? const MethodChannelDevicePermissionGateway()
    : const UnsupportedDevicePermissionGateway();

/// 后台运行能力：Android 走同一个 MethodChannel，桌面端恒为"无需放行"。
BatteryOptimizationGateway createBatteryOptimizationGateway() =>
    Platform.isAndroid
    ? const MethodChannelDevicePermissionGateway()
    : const UnsupportedDevicePermissionGateway();

class MethodChannelDevicePermissionGateway
    implements DevicePermissionGateway, BatteryOptimizationGateway {
  const MethodChannelDevicePermissionGateway({
    this.channel = const MethodChannel('com.pacta/device_permissions'),
  });

  final MethodChannel channel;

  @override
  Future<void> openNotificationSettings() async {
    await _invoke('openNotificationSettings');
  }

  @override
  Future<void> openAppSettings() async {
    await _invoke('openAppSettings');
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      // 读不到状态时按"未放行"处理：提示白名单入口是可重复的动作。
      return false;
    }
  }

  @override
  Future<void> openBatteryOptimizationSettings() async {
    await _invoke('openBatteryOptimizationSettings');
  }

  Future<void> _invoke(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } catch (_) {
      // The device may not expose the screen; the caller keeps working.
    }
  }
}

class UnsupportedDevicePermissionGateway
    implements DevicePermissionGateway, BatteryOptimizationGateway {
  const UnsupportedDevicePermissionGateway();

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<void> openBatteryOptimizationSettings() async {}
}
