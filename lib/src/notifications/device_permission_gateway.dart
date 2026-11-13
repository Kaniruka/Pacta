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

DevicePermissionGateway createDevicePermissionGateway() => Platform.isAndroid
    ? const MethodChannelDevicePermissionGateway()
    : const UnsupportedDevicePermissionGateway();

class MethodChannelDevicePermissionGateway implements DevicePermissionGateway {
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

  Future<void> _invoke(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } catch (_) {
      // The device may not expose the screen; the caller keeps working.
    }
  }
}

class UnsupportedDevicePermissionGateway implements DevicePermissionGateway {
  const UnsupportedDevicePermissionGateway();

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openAppSettings() async {}
}
