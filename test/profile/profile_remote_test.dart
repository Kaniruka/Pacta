import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/profile_remote.dart';

void main() {
  final pngBytes = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);

  test('云端资料负载解码昵称、头像和更新时间', () {
    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'avatarMimeType': 'image/png',
      'avatarBase64': base64Encode(pngBytes),
      'updatedAt': '2026-11-13T09:00:00.123456+00:00',
    });
    expect(profile, isNotNull);
    expect(profile!.displayName, '小林');
    expect(profile.avatar?.mimeType, 'image/png');
    expect(profile.avatar?.bytes, pngBytes);
    expect(profile.updatedAt, DateTime.utc(2026, 11, 13, 9, 0, 0, 123, 456));
  });

  test('没有资料的账号返回 null，不构造空资料覆盖缓存', () {
    expect(remoteProfileFromJson(null), isNull);
    expect(remoteProfileFromJson(const <String, dynamic>{}), isNull);
  });

  test('头像为空时只保留昵称', () {
    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'avatarMimeType': null,
      'avatarBase64': null,
      'updatedAt': '2026-11-13T09:00:00+00:00',
    });
    expect(profile?.displayName, '小林');
    expect(profile?.avatar, isNull);
  });

  test('PostgreSQL 76 列换行的头像 base64 仍能往返解码', () {
    final onePixelPng = Uint8List.fromList(const [
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
    final wrapped = _postgresBase64Lines(base64Encode(onePixelPng));
    expect(wrapped, contains('\n'));
    expect(wrapped.length, base64Encode(onePixelPng).length + 1);

    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'avatarMimeType': 'image/png',
      'avatarBase64': wrapped,
      'updatedAt': '2026-11-13T09:00:00+00:00',
    });

    expect(profile?.avatar?.bytes, onePixelPng);
    expect(profile?.avatar?.mimeType, 'image/png');
  });

  test('头像 base64 允许的 ASCII 空白都被忽略', () {
    final encoded = base64Encode(pngBytes);
    final spaced =
        ' \t'
        '${encoded.substring(0, 4)}\r\n\v\f'
        '${encoded.substring(4).split('').join(' ')}';
    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'avatarBase64': spaced,
      'updatedAt': '2026-11-13T09:00:00+00:00',
    });
    expect(profile?.avatar?.bytes, pngBytes);
  });

  test('头像 base64 含非法字符时继续拒绝', () {
    final broken = '${base64Encode(pngBytes)}!!';
    expect(
      () => remoteProfileFromJson({
        'displayName': '小林',
        'avatarBase64': broken,
        'updatedAt': '2026-11-13T09:00:00+00:00',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}

/// Mirrors PostgreSQL `encode(bytea, 'base64')`: 76 characters per line and a
/// single line feed between lines.
String _postgresBase64Lines(String encoded) {
  final buffer = StringBuffer();
  for (var start = 0; start < encoded.length; start += 76) {
    final end = start + 76 < encoded.length ? start + 76 : encoded.length;
    buffer.write(encoded.substring(start, end));
    if (end < encoded.length) buffer.write('\n');
  }
  return buffer.toString();
}
