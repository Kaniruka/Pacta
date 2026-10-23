import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Successful manual sync metadata belonging to this installation and user.
/// It is deliberately excluded from downloadable business snapshots.
class CloudSyncResult {
  const CloudSyncResult({
    required this.succeededAt,
    required this.localFingerprint,
    required this.cloudRevision,
    this.legacyToken,
  });

  final DateTime succeededAt;

  /// Null means the historical local baseline is unknown, never unchanged.
  final String? localFingerprint;
  final int cloudRevision;
  final String? legacyToken;
}

/// Business data has already transferred successfully. Retrying the transfer
/// cannot repair this installation's failed history write.
class CloudSyncResultPersistenceException implements Exception {
  const CloudSyncResultPersistenceException({
    required this.result,
    required this.cause,
  });

  final CloudSyncResult result;
  final Object cause;

  String get message => '同步已完成，但本机同步记录未保存，请重新检查数据。';

  @override
  String toString() => message;
}

class CloudSyncResultStore {
  const CloudSyncResultStore({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  String _key(String userId) => 'pacta.device.cloud_sync.result.$userId';

  Future<CloudSyncResult?> load(String userId) async {
    final preferences = await preferencesLoader();
    await preferences.reload();
    final encoded = preferences.getString(_key(userId));
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      return CloudSyncResult(
        succeededAt: DateTime.parse(value['succeededAt'] as String).toUtc(),
        localFingerprint: value['localFingerprint'] as String?,
        cloudRevision: value['cloudRevision'] as int,
        legacyToken: value['legacyToken'] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(String userId, CloudSyncResult result) async {
    final preferences = await preferencesLoader();
    final saved = await preferences.setString(
      _key(userId),
      jsonEncode({
        'succeededAt': result.succeededAt.toUtc().toIso8601String(),
        'localFingerprint': result.localFingerprint,
        'cloudRevision': result.cloudRevision,
        'legacyToken': result.legacyToken,
      }),
    );
    if (!saved) throw StateError('同步已完成，但本机同步记录未保存，请重新检查数据。');
  }
}
