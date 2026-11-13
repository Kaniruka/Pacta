import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'avatar_image.dart';

/// One account profile as stored by the account profile service.
class RemoteProfile {
  const RemoteProfile({
    required this.displayName,
    required this.avatar,
    required this.updatedAt,
  });

  final String displayName;
  final ProfileAvatar? avatar;
  final DateTime updatedAt;
}

/// Account profile storage. It is not part of the business snapshot.
abstract interface class ProfileRemote {
  /// False when no account store is configured, so local saves stay local
  /// instead of reporting a failure the person cannot act on.
  bool get isAvailable;

  Future<RemoteProfile?> fetch({required String userId});

  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  });
}

class UnavailableProfileRemote implements ProfileRemote {
  const UnavailableProfileRemote();

  @override
  bool get isAvailable => false;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async =>
      throw StateError('尚未配置 Supabase，资料只保存在本机。');

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  }) async => throw StateError('尚未配置 Supabase，资料只保存在本机。');
}

/// Reads and writes the signed-in user's own profile through owner-scoped
/// RPCs; the table grants no direct client access.
class SupabaseProfileRemote implements ProfileRemote {
  SupabaseProfileRemote(this.client);

  final SupabaseClient client;

  @override
  bool get isAvailable => true;

  void _assertCurrentUser(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('当前登录用户已变化，请重新打开资料页面。');
    }
  }

  @override
  Future<RemoteProfile?> fetch({required String userId}) async {
    _assertCurrentUser(userId);
    final Object? response;
    try {
      response = await client.rpc('read_profile_account');
    } on PostgrestException catch (error) {
      throw StateError('云端资料暂不可用：${error.message}');
    }
    return remoteProfileFromJson(response);
  }

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  }) async {
    _assertCurrentUser(userId);
    final Object? response;
    try {
      response = await client.rpc(
        'save_profile_account',
        params: {
          'p_display_name': displayName,
          'p_avatar_base64': avatar == null ? null : base64Encode(avatar.bytes),
          'p_clear_avatar': avatar == null,
        },
      );
    } on PostgrestException catch (error) {
      throw StateError('保存失败：${error.message}');
    }
    final profile = remoteProfileFromJson(response);
    if (profile == null) {
      throw StateError('保存失败：云端没有返回资料。');
    }
    return profile;
  }
}

/// Decodes the owner-scoped RPC payload. Null means the account has no stored
/// profile yet, so the caller keeps the local cache instead of clearing it.
RemoteProfile? remoteProfileFromJson(Object? response) {
  if (response is! Map) return null;
  final json = Map<String, dynamic>.from(response);
  final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
  if (updatedAt == null) return null;
  final avatarBase64 = json['avatarBase64'];
  final avatar = avatarBase64 is String && avatarBase64.isNotEmpty
      ? ProfileAvatar(
          bytes: _decodeBase64Avatar(avatarBase64),
          mimeType: json['avatarMimeType'] as String? ?? 'image/png',
        )
      : null;
  return RemoteProfile(
    displayName: json['displayName'] as String? ?? '',
    avatar: avatar,
    updatedAt: updatedAt.toUtc(),
  );
}

/// ASCII whitespace that base64 payloads are allowed to carry.
const _base64Whitespace = <int>{0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20};

/// PostgreSQL's `encode(bytea, 'base64')` wraps its output every 76
/// characters with a line feed, and `base64Decode` rejects whitespace that
/// follows the padding. Only those whitespace bytes are dropped; every other
/// character still has to be valid base64 or decoding throws [FormatException].
Uint8List _decodeBase64Avatar(String value) {
  final normalized = value.codeUnits.any(_base64Whitespace.contains)
      ? String.fromCharCodes(
          value.codeUnits.where((unit) => !_base64Whitespace.contains(unit)),
        )
      : value;
  return base64Decode(normalized);
}
