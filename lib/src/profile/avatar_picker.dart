import 'package:flutter/services.dart';

/// Raised when the system picker cannot return an image.
class AvatarPickException implements Exception {
  const AvatarPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Asks the platform for exactly one image.
///
/// Android uses the system photo picker (or the document picker on older
/// releases) and Windows uses the native open dialog, so neither needs broad
/// media-library access.
abstract interface class AvatarPicker {
  /// Returns the selected image bytes, or null when the person cancelled.
  Future<Uint8List?> pickSingleImage();
}

class SystemAvatarPicker implements AvatarPicker {
  const SystemAvatarPicker({this.channel = _defaultChannel});

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.pacta/profile_avatar',
  );

  final MethodChannel channel;

  @override
  Future<Uint8List?> pickSingleImage() async {
    try {
      return await channel.invokeMethod<Uint8List>('pickImage');
    } on PlatformException catch (error) {
      throw AvatarPickException(error.message ?? '系统图片选择暂时不可用。');
    } on MissingPluginException catch (_) {
      throw const AvatarPickException('当前平台不支持系统图片选择。');
    }
  }
}
