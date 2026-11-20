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
    this.timeZoneRevision = 0,
    this.timeZoneConflict = false,
  });

  final String displayName;
  final ProfileAvatar? avatar;
  final DateTime updatedAt;

  /// The account display time zone (IANA), or null when the account has none.
  final String? displayTimeZoneId;

  /// Server-owned, strictly increasing revision of [displayTimeZoneId].
  ///
  /// The account store is the only writer of this counter, so a client can
  /// order its edit by the revision it last observed instead of by a device
  /// clock. Zero means the account has never accepted a time zone.
  final int timeZoneRevision;

  /// True when this request carried a zone that the account store refused
  /// because a newer accepted revision already existed.
  ///
  /// The returned [displayTimeZoneId] and [timeZoneRevision] are then the
  /// canonical winner, and the caller adopts them instead of retrying.
  final bool timeZoneConflict;
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
  /// that only edits a nickname or avatar never clears it.
  ///
  /// A non-null zone is an explicit preference and must carry the
  /// [timeZoneRevision] this edit was based on. The account store applies it
  /// only when the stored revision still matches; otherwise the newer accepted
  /// value wins and is returned with [RemoteProfile.timeZoneConflict]. Ordering
  /// therefore never depends on a device clock.
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
    int? timeZoneRevision,
  });

  /// Writes [displayTimeZoneId] only when the account has no value yet.
  ///
  /// This is the first-migration step: two devices may both read "no value"
  /// before writing, so the account store decides a single winner atomically
  /// instead of the last unconditional save winning. When the account has no
  /// profile row at all, the account store inserts one with an empty display
  /// name — an unset nickname, not a fabricated name — so the time zone can be
  /// stored before the person chooses a nickname. Existing names and avatars
  /// are untouched, and only a still-empty account value is ever filled. It
  /// returns the account value after the attempt (with its revision), so a
  /// device that lost the race adopts the winner.
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
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
    int? timeZoneRevision,
  }) async => throw StateError('尚未配置 Supabase，资料只保存在本机。');

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
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
      throw StateError(postgrestFailureText(error, prefix: '云端资料暂不可用'));
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
    int? timeZoneRevision,
  }) async {
    _assertCurrentUser(userId);
    return saveAccountProfile(
      (function, params) => client.rpc(function, params: params),
      displayName: displayName,
      avatar: avatar,
      displayTimeZoneId: displayTimeZoneId,
      timeZoneRevision: timeZoneRevision,
    );
  }

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) async {
    _assertCurrentUser(userId);
    final Object? response;
    try {
      response = await client.rpc(
        'initialize_profile_time_zone',
        params: {'p_time_zone_id': displayTimeZoneId},
      );
    } on PostgrestException catch (error) {
      throw StateError(postgrestFailureText(error, prefix: '时区初始化失败'));
    }
    return remoteProfileFromJson(response);
  }
}

/// 账号资料写入的 RPC 调用面：生产是 [SupabaseClient.rpc]，测试可注入替身。
typedef ProfileAccountRpc = Future<Object?> Function(
  String function,
  Map<String, dynamic> params,
);

/// 云端还没有部署含账号时区的 save_profile_account 时给用户看的中文提示。
const accountTimeZoneRpcMissingMessage =
    '云端尚未部署含账号时区的最新接口，暂时无法保存时区修改；昵称与头像未受影响。';

/// 判断异常是否表示"服务端没有这个函数签名"（PostgREST 的 schema cache 未命中）。
///
/// 旧版数据库只注册了 3 参数的 save_profile_account，带 p_time_zone_id 的调用
/// 会得到 PGRST202 与 "Could not find the function ... in the schema cache"。
bool isMissingProfileAccountRpc(PostgrestException error) {
  final text = '${error.code ?? ''} ${error.message}'.toLowerCase();
  return text.contains('pgrst202') ||
      text.contains('could not find the function') ||
      text.contains('schema cache');
}

/// PostgREST 失败的中文提示：只说明业务后果与可执行动作。
///
/// 直接上抛 [PostgrestException.message] 会把英文 SQL / 函数签名（例如
/// "permission denied for function save_profile_account"）带到界面上：中文
/// 前缀会让共享的错误文案转换认不出技术异常而原样透出。这里按错误码与文案
/// 先分类，再用 [prefix]（读取/保存/时区）拼出完整、可操作的中文提示。
String postgrestFailureText(
  PostgrestException error, {
  required String prefix,
}) {
  final code = (error.code ?? '').trim().toUpperCase();
  final message = error.message.toLowerCase();
  if (code == '42501' || message.contains('permission denied')) {
    return '$prefix：当前登录账号没有该操作的权限，请确认登录状态后重试。';
  }
  if (isMissingProfileAccountRpc(error)) {
    return '$prefix：云端服务版本尚未同步最新接口，请稍后重试。';
  }
  if (code == 'PGRST301' || message.contains('jwt')) {
    return '$prefix：登录状态已失效，请重新登录后再试。';
  }
  return '$prefix：云端服务暂时不可用，请稍后重试。';
}

/// 账号资料保存的统一流程。
///
/// [displayTimeZoneId] 为空时只发送 3 个参数：没有时区要写就不该把时区键
/// 一起发出去，否则旧版数据库会直接找不到 5 参函数，昵称和头像也会一起失败。
///
/// 只有用户确实改了账号时区时才尝试 5 参数版本。服务端还没有该签名时，先按
/// 3 参数把昵称与头像写回去，再抛出一条明确的中文提示，不把函数签名原文露给
/// 用户；此时本机仍保留待上传意图，接口部署后可重试。
Future<RemoteProfile> saveAccountProfile(
  ProfileAccountRpc rpc, {
  required String displayName,
  required ProfileAvatar? avatar,
  required String? displayTimeZoneId,
  required int? timeZoneRevision,
}) async {
  final baseParams = <String, dynamic>{
    'p_display_name': displayName,
    'p_avatar_base64': avatar == null ? null : base64Encode(avatar.bytes),
    'p_clear_avatar': avatar == null,
  };
  final Object? response;
  if (displayTimeZoneId == null) {
    try {
      response = await rpc('save_profile_account', baseParams);
    } on PostgrestException catch (error) {
      throw StateError(postgrestFailureText(error, prefix: '保存失败'));
    }
  } else {
    try {
      response = await rpc('save_profile_account', {
        ...baseParams,
        'p_time_zone_id': displayTimeZoneId,
        'p_time_zone_revision': timeZoneRevision,
      });
    } on PostgrestException catch (error) {
      if (!isMissingProfileAccountRpc(error)) {
        throw StateError(postgrestFailureText(error, prefix: '保存失败'));
      }
      try {
        await rpc('save_profile_account', baseParams);
      } on Object {
        // 基础保存也不可用时时区同样没有提交，提示语义不变。
      }
      throw StateError(accountTimeZoneRpcMissingMessage);
    }
  }
  final profile = remoteProfileFromJson(response);
  if (profile == null) {
    throw StateError('保存失败：云端没有返回资料。');
  }
  return profile;
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
  final conflict = json['timeZoneConflict'];
  return RemoteProfile(
    displayName: json['displayName'] as String? ?? '',
    avatar: avatar,
    updatedAt: updatedAt.toUtc(),
    displayTimeZoneId: timeZoneId is String && timeZoneId.isNotEmpty
        ? timeZoneId
        : null,
    timeZoneRevision: _parseRevision(json['timeZoneRevision']),
    timeZoneConflict: conflict == true,
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

/// Reads the account revision from either JSON number or PostgreSQL's textual
/// bigint form. An absent or malformed value is treated as revision zero: the
/// next explicit edit then conflicts instead of silently overwriting.
int _parseRevision(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
