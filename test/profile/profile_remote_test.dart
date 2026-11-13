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
}
