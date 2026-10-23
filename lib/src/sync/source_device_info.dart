import 'dart:io';

import 'package:flutter/services.dart';

/// Hardware metadata used to identify the source of a cloud snapshot.
///
/// [deviceName] keeps the existing host name and platform label. Hardware values are
/// optional because some platforms and virtual machines do not expose them.
class SourceDeviceInfo {
  const SourceDeviceInfo({
    required this.deviceName,
    this.manufacturer,
    this.model,
  });

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.pacta/source_device_info',
  );

  final String deviceName;
  final String? manufacturer;
  final String? model;

  /// Reads platform hardware metadata, preserving the host name on failure.
  static Future<SourceDeviceInfo> load() async {
    final deviceName = Platform.isAndroid || Platform.isWindows
        ? '${Platform.localHostname} (${Platform.isAndroid ? 'Android' : 'Windows'})'
        : Platform.localHostname;
    if (!Platform.isAndroid && !Platform.isWindows) {
      return SourceDeviceInfo(deviceName: deviceName);
    }

    try {
      final values = await _defaultChannel.invokeMapMethod<String, dynamic>(
        'readHardwareMetadata',
      );
      return SourceDeviceInfo(
        deviceName: deviceName,
        manufacturer: _nonEmptyString(values?['manufacturer']),
        model: _nonEmptyString(values?['model']),
      );
    } on PlatformException catch (_) {
      return SourceDeviceInfo(deviceName: deviceName);
    } on MissingPluginException catch (_) {
      return SourceDeviceInfo(deviceName: deviceName);
    } on Exception catch (_) {
      return SourceDeviceInfo(deviceName: deviceName);
    }
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'unknown') return null;
    return trimmed;
  }
}
