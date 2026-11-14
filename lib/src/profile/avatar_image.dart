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

/// Reads metadata first and bounds decoded raster allocation.
Future<ui.Image> decodeAvatarForCrop(Uint8List bytes) async {
  validateAvatarSelection(bytes);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width > 32768 ||
        descriptor.height > 32768 ||
        descriptor.width * descriptor.height > 100000000) {
      throw const AvatarValidationException('图片尺寸过大，请选择较小的图片。');
    }
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final ratio = longest > 2048 ? 2048 / longest : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * ratio).round().clamp(1, 2048),
      targetHeight: (descriptor.height * ratio).round().clamp(1, 2048),
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<Uint8List> _encodePng(Uint8List bytes, int maxEdge) async {
  final image = await decodeAvatarForCrop(bytes);
  ui.Image? output;
  ui.Picture? picture;
  try {
    final longest = image.width > image.height ? image.width : image.height;
    final ratio = longest > maxEdge ? maxEdge / longest : 1.0;
    final width = (image.width * ratio).round().clamp(1, maxEdge);
    final height = (image.height * ratio).round().clamp(1, maxEdge);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    output = await picture.toImage(width, height);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const AvatarValidationException('这张图片无法转换，请换一张。');
    return data.buffer.asUint8List();
  } finally {
    output?.dispose();
    picture?.dispose();
    image.dispose();
  }
}

String normalizeDisplayName(String value) => value.trim();

String validateDisplayName(String value) {
  final trimmed = normalizeDisplayName(value);
  if (trimmed.characters.length > maxDisplayNameLength) {
    throw const AvatarValidationException('昵称最多 32 个字符。');
  }
  return trimmed;
}
