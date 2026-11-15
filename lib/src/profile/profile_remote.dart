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
    this.displayTimeZoneId,
  });

  final String displayName;
  final ProfileAvatar? avatar;
  final DateTime updatedAt;

  /// The account display time zone (IANA), or null when the account has none.
  final String? displayTimeZoneId;
}

/// Account profile storage. It is not part of the business snapshot.
abstract interface class ProfileRemote {
  /// False when no account store is configured, so local saves stay local
  /// instead of reporting a failure the person cannot act on.
  bool get isAvailable;

  Future<RemoteProfile?> fetch({required String userId});

  /// Saves the display name and avatar.
  ///
  /// [displayTimeZoneId] null keeps the stored account time zone, so a client
  /// that only edits a nickname or avatar never clears it. A non-null value is
  /// an explicit preference and only wins when it is newer than the stored one,
  /// which keeps a late request from overwriting a newer choice.
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
  });

  /// Writes [displayTimeZoneId] only when the account has no value yet.
  ///
  /// This is the first-migration step: two devices may both read "no value"
  /// before writing, so the account store decides a single winner atomically
  /// instead of the last unconditional save winning. When the account has no
  /// profile row at all, the account store inserts one with an empty display
  /// name — an unset nickname, not a fabricated name — so the time zone can be
  /// stored before the person chooses a nickname. Existing names and avatars
  /// are untouched. Returns the account value after the attempt, so a device
  /// that lost the race adopts the winner.
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
    required DateTime requestedAt,
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
    String? displayTimeZoneId,
  }) async => throw StateError('尚未配置 Supabase，资料只保存在本机。');

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
    required DateTime requestedAt,
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
    String? displayTimeZoneId,
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
          'p_time_zone_id': displayTimeZoneId,
          'p_time_zone_requested_at': updatedAt.toUtc().toIso8601String(),
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

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
    required DateTime requestedAt,
  }) async {
    _assertCurrentUser(userId);
    final Object? response;
    try {
      response = await client.rpc(
        'initialize_profile_time_zone',
        params: {
          'p_time_zone_id': displayTimeZoneId,
          'p_time_zone_requested_at': requestedAt.toUtc().toIso8601String(),
        },
      );
    } on PostgrestException catch (error) {
      throw StateError('时区初始化失败：${error.message}');
    }
    return remoteProfileFromJson(response);
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
  final timeZoneId = json['timeZoneId'];
  return RemoteProfile(
    displayName: json['displayName'] as String? ?? '',
    avatar: avatar,
    updatedAt: updatedAt.toUtc(),
    displayTimeZoneId: timeZoneId is String && timeZoneId.isNotEmpty
        ? timeZoneId
        : null,
  );
}

/// Line breaks a base64 payload may legitimately carry.
///
/// PostgreSQL's `encode(bytea, 'base64')` wraps its output every 76
/// characters with a line feed and ends the value with one, while
/// `base64Decode` rejects those bytes. Only CR and LF are dropped; spaces,
/// tabs and every other character stay illegal, so a malformed payload still
/// throws [FormatException] instead of decoding into garbage.
Uint8List _decodeBase64Avatar(String value) {
  final normalized = value.contains('\n') || value.contains('\r')
      ? value.replaceAll('\r', '').replaceAll('\n', '')
      : value;
  return base64Decode(normalized);
}
