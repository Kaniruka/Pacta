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

/// 通知渠道健康度：渠道被降级或静音时，弹窗与锁屏提醒会被系统静默抑制。
///
/// 与 [DevicePermissionGateway] 分开声明：既有的假实现不必为一个新能力补
/// 方法，页面按需注入；桌面端恒为"健康"。
class NotificationChannelHealth {
  const NotificationChannelHealth({
    required this.healthy,
    this.degradedChannelIds = const [],
  });

  const NotificationChannelHealth.healthy()
    : this(healthy: true, degradedChannelIds: const []);

  /// 五个 `*_v2` 渠道都没有被降级、阻断或设为隐藏锁屏内容。
  final bool healthy;

  /// 需要用户去系统设置里修好的渠道 id，顺序稳定（事件渠道在最前）。
  final List<String> degradedChannelIds;
}

/// 读取与打开单个通知渠道的系统设置页。
abstract interface class NotificationChannelHealthGateway {
  /// 只读探测：不写任何系统设置，未创建的渠道按健康处理。
  Future<NotificationChannelHealth> inspectChannelHealth();

  /// 直达该渠道的系统设置页；不可用时回退到应用通知设置。
  Future<void> openChannelSettings(String channelId);
}

DevicePermissionGateway createDevicePermissionGateway() => Platform.isAndroid
    ? const MethodChannelDevicePermissionGateway()
    : const UnsupportedDevicePermissionGateway();

/// 后台运行能力：Android 走同一个 MethodChannel，桌面端恒为"无需放行"。
BatteryOptimizationGateway createBatteryOptimizationGateway() =>
    Platform.isAndroid
    ? const MethodChannelDevicePermissionGateway()
    : const UnsupportedDevicePermissionGateway();

/// 通知渠道健康度：Android 走设备权限通道，桌面端没有渠道概念。
NotificationChannelHealthGateway createNotificationChannelHealthGateway() =>
    Platform.isAndroid
    ? const MethodChannelDevicePermissionGateway()
    : const UnsupportedDevicePermissionGateway();

class MethodChannelDevicePermissionGateway
    implements
        DevicePermissionGateway,
        BatteryOptimizationGateway,
        NotificationChannelHealthGateway {
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

  @override
  Future<NotificationChannelHealth> inspectChannelHealth() async {
    try {
      final reply = await channel.invokeMapMethod<String, Object?>(
        'getNotificationChannelHealth',
      );
      if (reply == null) return const NotificationChannelHealth.healthy();
      final degraded = reply['degradedChannels'];
      return NotificationChannelHealth(
        // 只有原生侧明确说"不健康"才算不健康：读不到就按健康处理，
        // 避免首次启动或旧宿主把用户引向并不存在的降级问题。
        healthy: reply['healthy'] != false,
        degradedChannelIds: [
          if (degraded is List)
            for (final id in degraded)
              if (id is String && id.isNotEmpty) id,
        ],
      );
    } catch (_) {
      return const NotificationChannelHealth.healthy();
    }
  }

  @override
  Future<void> openChannelSettings(String channelId) async {
    try {
      await channel.invokeMethod<void>('openNotificationChannelSettings', {
        'channelId': channelId,
      });
    } catch (_) {
      // 渠道级设置页不是所有机型都有；调用方保留整页通知设置入口。
    }
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
    implements
        DevicePermissionGateway,
        BatteryOptimizationGateway,
        NotificationChannelHealthGateway {
  const UnsupportedDevicePermissionGateway();

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<NotificationChannelHealth> inspectChannelHealth() async =>
      const NotificationChannelHealth.healthy();

  @override
  Future<void> openChannelSettings(String channelId) async {}
}
