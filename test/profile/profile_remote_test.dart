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

  test('PostgreSQL 76 列换行的真实 PNG 字节仍能往返解码', () {
    final realPng = _onePixelPng();
    final encoded = base64Encode(realPng);
    expect(encoded.length, greaterThan(76), reason: '需要跨过 PG 的换行边界');

    final wrapped = _postgresBase64Lines(encoded);
    expect(wrapped.split('\n').length, greaterThan(2));
    expect(wrapped.endsWith('\n'), isTrue, reason: 'PG 每行（含末行）后都换行');
    expect(wrapped.length, encoded.length + wrapped.split('\n').length - 1);

    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'avatarMimeType': 'image/png',
      'avatarBase64': wrapped,
      'updatedAt': '2026-11-13T09:00:00+00:00',
    });

    expect(profile?.avatar?.bytes, realPng);
    expect(profile?.avatar?.mimeType, 'image/png');
  });

  test('CRLF 换行的 base64 变体同样可解码', () {
    final realPng = _onePixelPng();
    final crlf = _postgresBase64Lines(base64Encode(realPng))
        .replaceAll('\n', '\r\n');
    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'avatarBase64': crlf,
      'updatedAt': '2026-11-13T09:00:00+00:00',
    });
    expect(profile?.avatar?.bytes, realPng);
  });

  test('只忽略换行，空格与其它空白仍按非法输入拒绝', () {
    final encoded = base64Encode(pngBytes);
    final malformedInputs = <String>[
      encoded.replaceRange(0, 0, ' '),
      encoded.replaceRange(4, 4, ' '),
      encoded.replaceRange(0, 0, '\t'),
      encoded.replaceRange(4, 4, '\v'),
      encoded.replaceRange(4, 4, '\f'),
    ];
    for (final malformed in malformedInputs) {
      expect(
        () => remoteProfileFromJson({
          'displayName': '小林',
          'avatarBase64': malformed,
          'updatedAt': '2026-11-13T09:00:00+00:00',
        }),
        throwsA(isA<FormatException>()),
        reason: '非换行空白不得被静默接受',
      );
    }
  });

  test('头像 base64 含非法字符时继续拒绝', () {
    final encoded = base64Encode(pngBytes);
    final broken = encoded.replaceRange(encoded.length, encoded.length, '!!');
    expect(
      () => remoteProfileFromJson({
        'displayName': '小林',
        'avatarBase64': broken,
        'updatedAt': '2026-11-13T09:00:00+00:00',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => remoteProfileFromJson({
        'displayName': '小林',
        'avatarBase64': 'YQ==YQ==',
        'updatedAt': '2026-11-13T09:00:00+00:00',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}

/// A real 1x1 PNG. Its base64 form is longer than 76 characters, so the
/// PostgreSQL line wrapping is exercised instead of only a short value.
Uint8List _onePixelPng() => Uint8List.fromList(const [
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

/// Mirrors PostgreSQL `encode(bytea, 'base64')`: 76 characters per line,
/// each line terminated by a line feed, including the last one.
String _postgresBase64Lines(String encoded) {
  final buffer = StringBuffer();
  for (var start = 0; start < encoded.length; start += 76) {
    final end = start + 76 < encoded.length ? start + 76 : encoded.length;
    buffer.write(encoded.substring(start, end));
    buffer.write('\n');
  }
  return buffer.toString();
}
