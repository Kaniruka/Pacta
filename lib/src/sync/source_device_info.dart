import 'dart:io';

import 'package:flutter/services.dart';

/// 运行平台，决定来源标签使用型号还是设备名。
enum SourceDevicePlatform { android, windows, other }

/// Hardware metadata used to identify the source of a cloud snapshot.
///
/// [deviceName] keeps the host name and is the Windows source name. Hardware
/// values are optional because some platforms and virtual machines do not
/// expose them.
class SourceDeviceInfo {
  const SourceDeviceInfo({
    required this.deviceName,
    this.manufacturer,
    this.model,
    this.platform = SourceDevicePlatform.other,
  });

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.pacta/source_device_info',
  );

  /// 本机设备名；Windows 作为来源名称，其他平台仅作回退显示。
  final String deviceName;
  final String? manufacturer;
  final String? model;
  final SourceDevicePlatform platform;

  /// 上传与历史列表使用的来源标签。
  ///
  /// Android 只显示型号，Windows 只显示设备名，各自附平台括注；缺少必需
  /// 值时显示对应平台的未知来源，不伪造名称，也不包含设备标识或厂商。
  String get sourceLabel =>
      labelFor(platform: platform, hostName: deviceName, model: model);

  static String labelFor({
    required SourceDevicePlatform platform,
    required String hostName,
    String? model,
  }) {
    switch (platform) {
      case SourceDevicePlatform.android:
        return '${_displayName(model) ?? '未知型号'}（Android）';
      case SourceDevicePlatform.windows:
        return '${_displayName(hostName) ?? '未知设备名'}（Windows）';
      case SourceDevicePlatform.other:
        return _displayName(hostName) ?? '未知来源';
    }
  }

  /// Reads platform hardware metadata, preserving the host name on failure.
  static Future<SourceDeviceInfo> load() async {
    final platform = Platform.isAndroid
        ? SourceDevicePlatform.android
        : Platform.isWindows
        ? SourceDevicePlatform.windows
        : SourceDevicePlatform.other;
    final deviceName = Platform.localHostname;
    if (platform == SourceDevicePlatform.other) {
      return SourceDeviceInfo(deviceName: deviceName, platform: platform);
    }

    try {
      final values = await _defaultChannel.invokeMapMethod<String, dynamic>(
        'readHardwareMetadata',
      );
      return SourceDeviceInfo(
        deviceName: deviceName,
        platform: platform,
        manufacturer: _displayName(values?['manufacturer'] as String?),
        model: _displayName(values?['model'] as String?),
      );
    } on PlatformException catch (_) {
      return SourceDeviceInfo(deviceName: deviceName, platform: platform);
    } on MissingPluginException catch (_) {
      return SourceDeviceInfo(deviceName: deviceName, platform: platform);
    } on Exception catch (_) {
      return SourceDeviceInfo(deviceName: deviceName, platform: platform);
    }
  }

  static String? _displayName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.toLowerCase() == 'unknown') return null;
    return trimmed;
  }
}
