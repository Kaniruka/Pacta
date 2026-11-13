import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';

/// 1x1 transparent PNG used as an independent known-good sample.
final Uint8List _onePixelPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

final Uint8List _jpegHeader = Uint8List.fromList(const [
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
]);

Future<Uint8List> _largePng(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF3355AA),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  test('按文件头识别允许的 PNG 和 JPEG 格式', () {
    expect(detectAvatarFormat(_onePixelPng), AvatarImageFormat.png);
    expect(detectAvatarFormat(_jpegHeader), AvatarImageFormat.jpeg);
  });

  test('空内容、超限大小和未知格式给出可读原因', () {
    expect(
      () => validateAvatarSelection(Uint8List(0)),
      throwsA(
        isA<AvatarValidationException>().having(
          (error) => error.message,
          'message',
          contains('图片'),
        ),
      ),
    );
    expect(
      () => validateAvatarSelection(
        Uint8List(maxAvatarSourceBytes + 1)..setRange(0, 4, _onePixelPng),
      ),
      throwsA(
        isA<AvatarValidationException>().having(
          (error) => error.message,
          'message',
          contains('5 MB'),
        ),
      ),
    );
    expect(
      () => validateAvatarSelection(Uint8List.fromList(const [1, 2, 3, 4, 5])),
      throwsA(
        isA<AvatarValidationException>().having(
          (error) => error.message,
          'message',
          contains('PNG'),
        ),
      ),
    );
  });

  test('归一化后保存为受限大小的 PNG 头像', () async {
    final avatar = await prepareAvatarForUpload(_onePixelPng);
    expect(avatar.mimeType, 'image/png');
    expect(avatar.bytes.length, lessThanOrEqualTo(maxAvatarStoredBytes));
    expect(detectAvatarFormat(avatar.bytes), AvatarImageFormat.png);
  });

  test('大图按最长边缩小，存储字节不超过上限', () async {
    final source = await _largePng(1024);
    final avatar = await prepareAvatarForUpload(source);
    expect(avatar.bytes.length, lessThanOrEqualTo(maxAvatarStoredBytes));
    final codec = await ui.instantiateImageCodec(avatar.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, lessThanOrEqualTo(maxAvatarEdgePixels));
    expect(frame.image.height, lessThanOrEqualTo(maxAvatarEdgePixels));
    frame.image.dispose();
  });

  test('昵称按去空白后的长度受限', () {
    expect(normalizeDisplayName('  小林  '), '小林');
    expect(normalizeDisplayName('   '), '');
    expect(
      () => validateDisplayName('名' * (maxDisplayNameLength + 1)),
      throwsA(isA<AvatarValidationException>()),
    );
    expect(validateDisplayName('  ' * 3), '');
  });
}
