import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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

  test('云端负载带回账号时区修订号与冲突标记', () {
    final profile = remoteProfileFromJson({
      'displayName': '小林',
      'updatedAt': '2026-11-13T09:00:00+00:00',
      'timeZoneId': 'Asia/Tokyo',
      'timeZoneRevision': 4,
      'timeZoneConflict': true,
    });
    expect(profile?.displayTimeZoneId, 'Asia/Tokyo');
    expect(profile?.timeZoneRevision, 4);
    expect(profile?.timeZoneConflict, isTrue);

    // PostgreSQL 的 bigint 也可能以文本形式到达；缺失或非法值按 0 处理，下一次
    // 明确修改会先冲突并采用账号值，而不是静默接受。
    final textual = remoteProfileFromJson({
      'displayName': '小林',
      'updatedAt': '2026-11-13T09:00:00+00:00',
      'timeZoneId': 'Asia/Tokyo',
      'timeZoneRevision': '7',
    });
    expect(textual?.timeZoneRevision, 7);
    expect(textual?.timeZoneConflict, isFalse);
    expect(
      remoteProfileFromJson({
        'displayName': '小林',
        'updatedAt': '2026-11-13T09:00:00+00:00',
      })?.timeZoneRevision,
      0,
    );
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

  group('save_profile_account 参数与旧库回退', () {
    test('没有时区可写时只发送 3 个参数', () async {
      final calls = <Map<String, dynamic>>[];
      final profile = await saveAccountProfile(
        (function, params) async {
          expect(function, 'save_profile_account');
          calls.add(params);
          return _savedProfileJson(
            displayName: params['p_display_name'] as String,
          );
        },
        displayName: '小林',
        avatar: null,
        displayTimeZoneId: null,
        timeZoneRevision: null,
      );

      expect(calls, hasLength(1), reason: '不该多发一次 5 参请求');
      expect(
        calls.single.keys,
        unorderedEquals([
          'p_display_name',
          'p_avatar_base64',
          'p_clear_avatar',
        ]),
        reason: '旧库只注册了 3 参函数，带上时区键会整体失败',
      );
      expect(profile.displayName, '小林');
    });

    test('选择了账号时区时发送含修订号的 5 个参数', () async {
      final calls = <Map<String, dynamic>>[];
      final profile = await saveAccountProfile(
        (function, params) async {
          calls.add(params);
          return _savedProfileJson(
            displayName: params['p_display_name'] as String,
            timeZoneId: params['p_time_zone_id'] as String?,
            timeZoneRevision: params['p_time_zone_revision'] as int? ?? 0,
          );
        },
        displayName: '小林',
        avatar: ProfileAvatar(bytes: pngBytes, mimeType: 'image/png'),
        displayTimeZoneId: 'Asia/Tokyo',
        timeZoneRevision: 2,
      );

      expect(calls, hasLength(1));
      expect(calls.single['p_time_zone_id'], 'Asia/Tokyo');
      expect(calls.single['p_time_zone_revision'], 2);
      expect(calls.single['p_avatar_base64'], base64Encode(pngBytes));
      expect(profile.displayTimeZoneId, 'Asia/Tokyo');
    });

    test('云端缺少含时区的接口时给出中文提示，昵称与头像仍按 3 参数保底保存', () async {
      final calls = <Map<String, dynamic>>[];
      Object? thrown;
      try {
        await saveAccountProfile(
          (function, params) async {
            calls.add(params);
            if (params.containsKey('p_time_zone_id')) {
              throw const PostgrestException(
                code: 'PGRST202',
                message:
                    'Could not find the function '
                    'public.save_profile_account(p_avatar_base64, '
                    'p_clear_avatar, p_display_name, p_time_zone_id, '
                    'p_time_zone_revision) in the schema cache',
              );
            }
            return _savedProfileJson(
              displayName: params['p_display_name'] as String,
            );
          },
          displayName: '小林',
          avatar: null,
          displayTimeZoneId: 'Asia/Tokyo',
          timeZoneRevision: 1,
        );
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<StateError>());
      final message = (thrown! as StateError).message;
      expect(message, contains('云端尚未部署'));
      expect(message, contains('时区'));
      expect(message, contains('昵称与头像'));
      expect(message, isNot(contains('Could not find the function')));
      expect(message, isNot(contains('schema cache')));
      expect(message, isNot(contains('PGRST202')));

      expect(calls, hasLength(2), reason: '先试 5 参，再按 3 参保底保存');
      expect(calls.first.containsKey('p_time_zone_id'), isTrue);
      expect(
        calls.last.keys,
        unorderedEquals([
          'p_display_name',
          'p_avatar_base64',
          'p_clear_avatar',
        ]),
      );
    });

    test('Postgres 权限错误换成中文提示，不外露英文 SQL', () async {
      Object? thrown;
      try {
        await saveAccountProfile(
          (function, params) async => throw const PostgrestException(
            code: '42501',
            message: 'permission denied for function save_profile_account',
          ),
          displayName: '小林',
          avatar: null,
          displayTimeZoneId: null,
          timeZoneRevision: null,
        );
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isA<StateError>());
      final message = (thrown! as StateError).message;
      expect(message, startsWith('保存失败：'));
      expect(message, contains('权限'));
      expect(message, isNot(contains('permission denied')));
      expect(message, isNot(contains('42501')));
      expect(message, isNot(contains('PostgrestException')));
    });

    test('其它 Postgrest 错误仍按保存失败返回且不泄露内部报错', () async {
      Object? thrown;
      try {
        await saveAccountProfile(
          (function, params) async => throw const PostgrestException(
            code: 'PGRST500',
            message:
                'Internal server error: relation "profiles" does not exist',
          ),
          displayName: '小林',
          avatar: null,
          displayTimeZoneId: null,
          timeZoneRevision: null,
        );
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isA<StateError>());
      final message = (thrown! as StateError).message;
      expect(message, startsWith('保存失败：'));
      expect(message, contains('云端服务'));
      expect(message, isNot(contains('relation')));
      expect(message, isNot(contains('profiles')));
    });
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

/// 账号资料 RPC 的返回负载，字段名与 remoteProfileFromJson 的输入一致。
Map<String, dynamic> _savedProfileJson({
  required String displayName,
  String? timeZoneId,
  int timeZoneRevision = 0,
}) => {
  'displayName': displayName,
  'updatedAt': '2026-11-13T09:00:00+00:00',
  'timeZoneId': timeZoneId,
  'timeZoneRevision': timeZoneRevision,
};

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
