import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:characters/characters.dart';

/// Largest accepted selection, before the avatar is scaled and re-encoded.
const int maxAvatarSourceBytes = 5 * 1024 * 1024;

/// Largest avatar binary kept in the account profile store.
const int maxAvatarStoredBytes = 256 * 1024;

/// Longest edge of the stored avatar image.
const int maxAvatarEdgePixels = 384;

/// Longest accepted display name, counted in user-perceived characters.
const int maxDisplayNameLength = 32;

enum AvatarImageFormat {
  png('image/png', 'PNG'),
  jpeg('image/jpeg', 'JPEG');

  const AvatarImageFormat(this.mimeType, this.label);

  final String mimeType;
  final String label;
}

/// A selected or stored avatar binary that already passed format validation.
class ProfileAvatar {
  const ProfileAvatar({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  bool get isEmpty => bytes.isEmpty;
}

/// Rejection carrying the sentence shown next to the failed action.
class AvatarValidationException implements Exception {
  const AvatarValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Detects PNG or JPEG by file signature without decoding the image.
///
/// Returns null when the bytes are empty or carry no supported signature, so
/// callers can reject the selection before any account write.
AvatarImageFormat? detectAvatarFormat(Uint8List bytes) {
  // 完整 PNG 签名是 8 字节，JPEG 只要 3 字节前缀。截断的文件必须按“未知格式”
  // 拒绝，不能先按前缀分支去读越界下标。
  if (_hasPngSignature(bytes)) return AvatarImageFormat.png;
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return AvatarImageFormat.jpeg;
  }
  return null;
}

bool _hasPngSignature(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0D &&
    bytes[5] == 0x0A &&
    bytes[6] == 0x1A &&
    bytes[7] == 0x0A;

AvatarImageFormat validateAvatarSelection(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const AvatarValidationException('没有读取到这张图片，请重新选择。');
  }
  if (bytes.length > maxAvatarSourceBytes) {
    throw const AvatarValidationException('图片超过 5 MB，请选择更小的图片。');
  }
  final format = detectAvatarFormat(bytes);
  if (format == null) {
    throw const AvatarValidationException('仅支持 PNG 或 JPEG 图片。');
  }
  return format;
}

/// Validates a system-picker selection and re-encodes it as a bounded PNG.
///
/// The stored avatar is always PNG so the account store needs one format
/// check, and the longest edge is reduced until the encoded binary fits
/// [maxAvatarStoredBytes].
Future<ProfileAvatar> prepareAvatarForUpload(Uint8List bytes) async {
  validateAvatarSelection(bytes);
  Object? lastError;
  for (final edge in const [maxAvatarEdgePixels, 192, 128]) {
    try {
      final encoded = await _encodePng(bytes, edge);
      if (encoded.length <= maxAvatarStoredBytes) {
        return ProfileAvatar(
          bytes: encoded,
          mimeType: AvatarImageFormat.png.mimeType,
        );
      }
    } catch (error) {
      lastError = error;
    }
  }
  throw AvatarValidationException(
    lastError == null ? '这张图片暂时无法保存，请换一张。' : '这张图片无法转换，请换一张。',
  );
}

Future<Uint8List> _encodePng(Uint8List bytes, int maxEdge) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final probeFrame = await probe.getNextFrame();
  final width = probeFrame.image.width;
  final height = probeFrame.image.height;
  probeFrame.image.dispose();

  var targetWidth = width;
  var targetHeight = height;
  final longest = width > height ? width : height;
  if (longest > maxEdge) {
    final scale = maxEdge / longest;
    targetWidth = (width * scale).round().clamp(1, maxEdge);
    targetHeight = (height * scale).round().clamp(1, maxEdge);
  }

  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  if (data == null) {
    throw const AvatarValidationException('这张图片无法转换，请换一张。');
  }
  return data.buffer.asUint8List();
}

String normalizeDisplayName(String value) => value.trim();

String validateDisplayName(String value) {
  final trimmed = normalizeDisplayName(value);
  if (trimmed.characters.length > maxDisplayNameLength) {
    throw const AvatarValidationException('昵称最多 32 个字符。');
  }
  return trimmed;
}
