import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../focus/focus_time_zones.dart';
import '../schedules/schedule_migration.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repeat.dart';
import '../tasks/task_database.dart';
import '../tasks/task_models.dart';
import 'legacy_cloud_snapshot.dart';
import 'cloud_recovery_point.dart';
import 'cloud_snapshot_history.dart';
import 'cloud_sync_result.dart';

/// 业务整份快照的载荷版本。
///
/// 版本 3 在完整 core 2（自有日程表 + 每场预约显式准备时长）之上加入重复日程：
/// `local_schedule_recurrences` 规则表，以及每条实例的规则归属、稳定系列身份、
/// 原始本地日期、规则时区与开始分钟、例外与墓碑标记。
///
/// 读取侧保留版本 1 与**完整**版本 2，用下方逐字段显式转换补默认值，而不是
/// 依赖"未知字段容错"：
/// * v1 → 现有安全转换（旧日历块提升为自有副本 + 预约边界），再补 v2/v3 列；
/// * v2 → 空规则表 + 每条日程的重复列取空/非重复默认值，已存值一律保留；
/// * v3 → 严格当前形状，缺表缺列整体拒绝。
///
/// 残缺的 pre-merge v2（缺日程表或任一预约缺 preparation_seconds）无论哪个
/// 版本都整体拒绝，绝不静默合并另一个领域的数据。客户端只写当前版本，服务端
/// 写入口同样只接受完整当前版本。
const int cloudSnapshotSchemaVersion = 3;

/// 完整第 2 版：日程表 + 每场预约准备时长的并集。
const int _version2SnapshotSchemaVersion = 2;

/// 同一上传请求被用于不同内容（服务端 PT422）。自动上传必须停止并检查，
/// 不能把它改写成新请求。
class CloudUploadRequestConflict extends StateError {
  CloudUploadRequestConflict() : super('该上传请求已用于不同的数据内容，请重新检查后再上传。');
}

/// 请求已被服务端处理，但它产生的备份不在最近 15 份内（PT425）。
class CloudUploadRequestEvicted extends StateError {
  CloudUploadRequestEvicted() : super('该上传请求已处理，但对应备份已不在最近 15 份内；请重新查看云端数据。');
}

/// 服务端不支持上传请求去重（旧 RPC 没有 p_request_id）。这是能力缺失，
/// 不是网络故障：自动上传必须停止并提示升级服务，不能反复静默重试。
class CloudUploadRequestIdUnsupported extends StateError {
  CloudUploadRequestIdUnsupported() : super('云端服务尚未支持上传请求去重，请升级服务后再重试自动上传。');
}

/// 并发版本校验失败（PT409）：云端已被推进，本次请求没有写入。
class CloudUploadRevisionChanged extends StateError {
  CloudUploadRevisionChanged() : super('云端数据在确认期间发生变化，请重新查看并选择覆盖方向。');
}

/// 服务端只接受当前载荷版本（PT426）：本次上传完全没有写入。
///
/// 冻结的旧版本请求因此可以安全丢弃并按最新本机快照重发；同一 requestId
/// 绝不能被改写内容重试。
class CloudSnapshotSchemaOutdated extends StateError {
  CloudSnapshotSchemaOutdated()
    : super('该上传请求使用旧版云端载荷格式，本次没有写入；请更新 Pacta 后重新同步。');
}

/// 上传在真正发出前被取消（关闭开关、切换账号、恢复备份）。
///
/// 与“请求已发出但应答丢失”不同：这次请求没有到达服务端，因此不产生新的
/// 请求身份，也不写成功基线。
class CloudUploadCancelled implements Exception {
  const CloudUploadCancelled();
}

/// A whole-account business-data snapshot. Device identity, local preferences,
/// lifecycle state, and the legacy per-entity upload queue are intentionally
/// kept outside this payload.
class CloudSnapshotMetadata {
  const CloudSnapshotMetadata({
    required this.revision,
    required this.deviceId,
    required this.deviceName,
    required this.dataUpdatedAt,
    required this.uploadedAt,
    required this.rowCount,
    this.isLegacy = false,
    this.legacyToken,
    this.payload,
    this.deviceManufacturer,
    this.deviceModel,
  });

  final int revision;
  final String deviceId;
  final String deviceName;
  final DateTime dataUpdatedAt;
  final DateTime uploadedAt;
  final int rowCount;
  final bool isLegacy;
  final String? legacyToken;
  final Map<String, dynamic>? payload;
  final String? deviceManufacturer;
  final String? deviceModel;
}

abstract interface class CloudSnapshotRemote {
  Future<CloudSnapshotMetadata?> inspect({required String userId});

  /// [requestId] 是上传请求的身份：服务端对同一用户同一 requestId 只写入
  /// 一次历史版本，重试返回已写入的结果而不产生新版本。
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  });

  Future<CloudSnapshotMetadata> download({required String userId});

  /// 已成功写入的云端备份，最新在前，最多 [cloudSnapshotHistoryLimit] 份。
  Future<List<CloudSnapshotHistoryEntry>> history({required String userId});

  /// 读取指定版本整份载荷；不存在的版本必须以 StateError 失败。
  Future<CloudSnapshotMetadata> downloadRevision({
    required String userId,
    required int revision,
  });
}

class SupabaseCloudSnapshotRemote implements CloudSnapshotRemote {
  SupabaseCloudSnapshotRemote(this.client);

  final SupabaseClient client;
  final Map<String, String> _legacyTokensByUser = {};

  void _assertCurrentUser(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('当前登录用户已变化，请重新打开同步页面。');
    }
  }

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    _assertCurrentUser(userId);
    final row = await _inspectSnapshotRow(userId);
    if (row != null) {
      _legacyTokensByUser.remove(userId);
      return _metadataFromJson(row);
    }
    return _readLegacySnapshot(userId);
  }

  Future<Map<String, dynamic>?> _inspectSnapshotRow(String userId) async {
    try {
      return await client
          .from('cloud_business_snapshots')
          .select(
            'revision,device_id,device_name,data_updated_at,uploaded_at,'
            'row_count,device_manufacturer,device_model',
          )
          .eq('user_id', userId)
          .maybeSingle();
    } on PostgrestException catch (error) {
      if (!_isMissingHardwareMetadataColumn(error)) rethrow;
      // Older projects may not have applied the nullable metadata migration
      // yet. Keep those snapshots inspectable using their original columns.
      _assertCurrentUser(userId);
      return await client
          .from('cloud_business_snapshots')
          .select(
            'revision,device_id,device_name,data_updated_at,uploaded_at,row_count',
          )
          .eq('user_id', userId)
          .maybeSingle();
    }
  }

  bool _isMissingHardwareMetadataColumn(PostgrestException error) {
    var code = error.code;
    var message = error.message;
    // PostgREST's maybeSingle error path can wrap a structured error body as
    // the message while replacing its code with the HTTP status.
    if (code == '400') {
      try {
        final body = jsonDecode(message);
        if (body is Map) {
          code = body['code']?.toString() ?? code;
          message = body['message']?.toString() ?? message;
        }
      } on FormatException {
        // Leave non-JSON errors untouched; they must still propagate.
      }
    }
    if (code != '42703' && code != 'PGRST204') return false;
    message = message.toLowerCase();
    return message.contains('cloud_business_snapshots') &&
        (message.contains('device_manufacturer') ||
            message.contains('device_model'));
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    _assertCurrentUser(userId);
    final row = await client
        .from('cloud_business_snapshots')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row != null) {
      _legacyTokensByUser.remove(userId);
      return _metadataFromJson(row);
    }
    final legacy = await _readLegacySnapshot(userId);
    if (legacy == null) throw StateError('Cloud snapshot does not exist.');
    return legacy;
  }

  @override
  Future<List<CloudSnapshotHistoryEntry>> history({
    required String userId,
  }) async {
    _assertCurrentUser(userId);
    final rows = await client
        .from('cloud_business_snapshot_history')
        .select(
          'revision,device_name,data_updated_at,uploaded_at,row_count,'
          'device_manufacturer,device_model',
        )
        .eq('user_id', userId)
        .order('revision', ascending: false)
        .limit(cloudSnapshotHistoryLimit);
    return [
      for (final row in rows)
        CloudSnapshotHistoryEntry(
          revision: row['revision'] as int,
          deviceName: row['device_name'] as String,
          rowCount: row['row_count'] as int,
          dataUpdatedAt: DateTime.parse(row['data_updated_at'] as String)
              .toUtc(),
          uploadedAt: DateTime.parse(row['uploaded_at'] as String).toUtc(),
          deviceManufacturer: _normalizeDeviceMetadata(
            row['device_manufacturer'] as String?,
          ),
          deviceModel: _normalizeDeviceMetadata(row['device_model'] as String?),
        ),
    ];
  }

  @override
  Future<CloudSnapshotMetadata> downloadRevision({
    required String userId,
    required int revision,
  }) async {
    _assertCurrentUser(userId);
    final row = await client
        .from('cloud_business_snapshot_history')
        .select()
        .eq('user_id', userId)
        .eq('revision', revision)
        .maybeSingle();
    if (row == null) {
      throw StateError('该云端备份已不在最近 $cloudSnapshotHistoryLimit 份之内。');
    }
    return _metadataFromJson(row);
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  }) async {
    _assertCurrentUser(userId);
    final String? expectedLegacyToken;
    final int remoteRevision;
    if (expectedRevision < 0) {
      expectedLegacyToken = _legacyTokensByUser[userId];
      if (expectedLegacyToken == null) {
        throw StateError('请重新检查旧版云数据后再上传，避免覆盖期间变化的数据。');
      }
      if (_legacyRevision(expectedLegacyToken) != expectedRevision) {
        throw StateError('旧版云数据预览已变化，请重新检查后再上传。');
      }
      remoteRevision = 0;
    } else {
      expectedLegacyToken = null;
      remoteRevision = expectedRevision;
    }
    final parameters = <String, dynamic>{
      'p_expected_revision': remoteRevision,
      'p_payload': payload,
      'p_device_id': deviceId,
      'p_device_name': deviceName,
      'p_data_updated_at': dataUpdatedAt.toUtc().toIso8601String(),
      'p_row_count': rowCount,
      'p_expected_legacy_token': expectedLegacyToken,
      'p_device_manufacturer': _normalizeDeviceMetadata(deviceManufacturer),
      'p_device_model': _normalizeDeviceMetadata(deviceModel),
      'p_request_id': _normalizeDeviceMetadata(requestId),
    };
    Object? result;
    try {
      try {
        result = await client.rpc(
          'save_cloud_business_snapshot',
          params: parameters,
        );
      } on PostgrestException catch (error) {
        final fallback = _olderSnapshotSignature(error, parameters);
        if (fallback == null) rethrow;
        // 幂等上传依赖 p_request_id：旧服务没有该参数时不能静默降级成
        // 会重复落档的上传，必须让调用方先升级服务端。
        if (requestId != null && !fallback.containsKey('p_request_id')) {
          throw CloudUploadRequestIdUnsupported();
        }
        // PGRST202 means no function ran. Retry only the confirmed older
        // signature, preserving the same payload and concurrency guards.
        _assertCurrentUser(userId);
        result = await client.rpc(
          'save_cloud_business_snapshot',
          params: fallback,
        );
      }
    } on PostgrestException catch (error) {
      if (error.code == 'PT409') throw CloudUploadRevisionChanged();
      if (error.code == 'PT422') throw CloudUploadRequestConflict();
      if (error.code == 'PT425') throw CloudUploadRequestEvicted();
      if (error.code == 'PT426') throw CloudSnapshotSchemaOutdated();
      if (error.code == '42501') {
        throw StateError('当前用户无法同步，请检查登录或停用状态。');
      }
      rethrow;
    }
    final Map<String, dynamic> row;
    if (result is List && result.length == 1 && result.single is Map) {
      row = Map<String, dynamic>.from(result.single as Map);
    } else if (result is Map) {
      row = Map<String, dynamic>.from(result);
    } else {
      throw StateError('Cloud snapshot RPC returned an invalid result.');
    }
    final saved = _metadataFromJson(row);
    _legacyTokensByUser.remove(userId);
    return saved;
  }

  /// 旧项目可能缺少后加的可选参数（设备元数据、上传请求标识）。
  /// 只有在服务端明确列出更旧的同名函数签名时，才用该签名重试一次；
  /// 其他缺失函数或权限错误按原错误处理，避免重试掩盖真实故障。
  Map<String, dynamic>? _olderSnapshotSignature(
    PostgrestException error,
    Map<String, dynamic> attempted,
  ) {
    if (error.code != 'PGRST202') return null;
    if (!error.message.contains('Could not find the function')) return null;
    final attemptedSignature = _rpcSignature(error.message);
    if (attemptedSignature == null ||
        !_sameSignature(attemptedSignature, attempted.keys.toSet())) {
      return null;
    }
    final existing = _rpcSignature(error.hint ?? '');
    if (existing == null) return null;
    for (final dropped in const [
      {'p_request_id'},
      {'p_request_id', 'p_device_manufacturer', 'p_device_model'},
    ]) {
      final candidate = Map<String, dynamic>.from(attempted);
      for (final key in dropped) {
        candidate.remove(key);
      }
      if (candidate.length == attempted.length) continue;
      if (_sameSignature(existing, candidate.keys.toSet())) return candidate;
    }
    return null;
  }

  Set<String>? _rpcSignature(String text) {
    final match = RegExp(r'public\.save_cloud_business_snapshot\(([^()]*)\)')
        .firstMatch(text);
    if (match == null) return null;
    final group = match.group(1)!.trim();
    if (group.isEmpty) return <String>{};
    return group.split(',').map((value) => value.trim()).toSet();
  }

  bool _sameSignature(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  Future<CloudSnapshotMetadata?> _readLegacySnapshot(String userId) async {
    _assertCurrentUser(userId);
    final response = await client.rpc('read_legacy_business_records');
    if (response == null) {
      _legacyTokensByUser.remove(userId);
      return null;
    }
    if (response is! Map) {
      throw StateError('Legacy cloud records returned an invalid result.');
    }
    final result = Map<String, dynamic>.from(response);
    final records = result['records'];
    final token = result['token'];
    if (records is! Map ||
        token is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      throw StateError(
        'Legacy cloud records are missing their revision token.',
      );
    }
    final local = await LegacyCloudSnapshotConverter().convert(
      userId: userId,
      records: Map<String, dynamic>.from(records),
    );
    if (local == null) {
      _legacyTokensByUser.remove(userId);
      return null;
    }
    _legacyTokensByUser[userId] = token;
    return CloudSnapshotMetadata(
      revision: _legacyRevision(token),
      deviceId: 'legacy',
      deviceName: '旧版云数据（来源设备未记录）',
      dataUpdatedAt: local.dataUpdatedAt,
      uploadedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      rowCount: local.rowCount,
      isLegacy: true,
      legacyToken: token,
      payload: local.payload,
    );
  }

  int _legacyRevision(String token) =>
      -(int.parse(token.substring(0, 15), radix: 16) + 1);

  CloudSnapshotMetadata _metadataFromJson(Map<String, dynamic> row) =>
      CloudSnapshotMetadata(
        revision: row['revision'] as int,
        deviceId: row['device_id'] as String,
        deviceName: row['device_name'] as String,
        dataUpdatedAt: DateTime.parse(row['data_updated_at'] as String).toUtc(),
        uploadedAt: DateTime.parse(row['uploaded_at'] as String).toUtc(),
        rowCount: row['row_count'] as int,
        isLegacy: false,
        payload: row['payload'] == null
            ? null
            : Map<String, dynamic>.from(row['payload'] as Map),
        deviceManufacturer: _normalizeDeviceMetadata(
          row['device_manufacturer'] as String?,
        ),
        deviceModel: _normalizeDeviceMetadata(row['device_model'] as String?),
      );
}

class UnavailableCloudSnapshotRemote implements CloudSnapshotRemote {
  const UnavailableCloudSnapshotRemote();

  StateError _error() => StateError('当前未配置云端整份同步。');

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async =>
      throw _error();

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async =>
      throw _error();

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  }) async => throw _error();

  @override
  Future<List<CloudSnapshotHistoryEntry>> history({
    required String userId,
  }) async => throw _error();

  @override
  Future<CloudSnapshotMetadata> downloadRevision({
    required String userId,
    required int revision,
  }) async => throw _error();
}

/// In-memory cloud implementation for application and repository tests.
class InMemoryCloudSnapshotRemote implements CloudSnapshotRemote {
  final Map<String, CloudSnapshotMetadata> _snapshots = {};
  final Map<String, CloudSnapshotMetadata> _legacySnapshots = {};
  final Map<String, String> _observedLegacyTokens = {};
  final Map<String, List<CloudSnapshotMetadata>> _history = {};

  /// 请求台账：request id → (version, payload 指纹)。与真实服务一样不含业务载荷，
  /// 也不随 15 份历史淘汰，因此重试不会重复落档。
  final Map<String, Map<String, ({int revision, String fingerprint})>>
  _requestLedger = {};
  bool available = true;
  bool suspended = false;

  void seedLegacySnapshot({
    required String userId,
    required String token,
    required CloudSnapshotLocalState state,
  }) {
    _legacySnapshots[userId] = CloudSnapshotMetadata(
      revision: -(int.parse(token.substring(0, 15), radix: 16) + 1),
      deviceId: 'legacy',
      deviceName: '旧版云数据（来源设备未记录）',
      dataUpdatedAt: state.dataUpdatedAt,
      uploadedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      rowCount: state.rowCount,
      isLegacy: true,
      legacyToken: token,
      payload: state.payload,
    );
  }

  void _checkAccess() {
    if (!available) throw StateError('Cloud snapshot service is offline.');
    if (suspended) throw StateError('Suspended users cannot sync snapshots.');
  }

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    _checkAccess();
    final snapshot = _snapshots[userId];
    if (snapshot != null) {
      _observedLegacyTokens.remove(userId);
      return snapshot;
    }
    final legacy = _legacySnapshots[userId];
    if (legacy != null) _observedLegacyTokens[userId] = legacy.legacyToken!;
    return legacy;
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    _checkAccess();
    final snapshot = _snapshots[userId] ?? _legacySnapshots[userId];
    if (snapshot == null) throw StateError('Cloud snapshot does not exist.');
    return snapshot;
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  }) async {
    _checkAccess();
    final requestFingerprint = jsonEncode(payload);
    if (requestId != null) {
      final handled = _requestLedger[userId]?[requestId];
      if (handled != null) {
        if (handled.fingerprint != requestFingerprint) {
          throw CloudUploadRequestConflict();
        }
        // 只返回该请求原本写入的版本：返回当前版本会把其他设备的数据
        // 标记成本机已处理。
        for (final entry
            in _history[userId] ?? const <CloudSnapshotMetadata>[]) {
          if (entry.revision == handled.revision) return entry;
        }
        throw CloudUploadRequestEvicted();
      }
    }
    final legacy = _legacySnapshots[userId];
    if (legacy != null && legacy.legacyToken != null) {
      if (_legacyRevision(legacy.legacyToken!) != legacy.revision) {
        throw StateError('Invalid in-memory legacy token.');
      }
    }
    if (expectedRevision < 0 &&
        _observedLegacyTokens[userId] != legacy?.legacyToken) {
      throw StateError('Legacy cloud snapshot changed; inspect it again.');
    }
    if (expectedRevision < 0 &&
        _legacyRevision(_observedLegacyTokens[userId]!) != expectedRevision) {
      throw StateError('Legacy cloud snapshot preview is stale.');
    }
    if (expectedRevision == 0 && legacy != null) {
      throw StateError('Legacy cloud snapshot exists; inspect it before sync.');
    }
    final currentRevision = _snapshots[userId]?.revision ?? 0;
    final targetRevision = expectedRevision < 0 ? 0 : expectedRevision;
    if (currentRevision != targetRevision) {
      throw CloudUploadRevisionChanged();
    }
    final snapshot = CloudSnapshotMetadata(
      revision: currentRevision + 1,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt.toUtc(),
      uploadedAt: DateTime.now().toUtc(),
      rowCount: rowCount,
      payload: jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
      deviceManufacturer: _normalizeDeviceMetadata(deviceManufacturer),
      deviceModel: _normalizeDeviceMetadata(deviceModel),
    );
    _snapshots[userId] = snapshot;
    final history = _history.putIfAbsent(userId, () => []);
    history.insert(0, snapshot);
    if (history.length > cloudSnapshotHistoryLimit) {
      history.removeRange(cloudSnapshotHistoryLimit, history.length);
    }
    if (requestId != null) {
      _requestLedger.putIfAbsent(userId, () => {})[requestId] = (
        revision: snapshot.revision,
        fingerprint: requestFingerprint,
      );
    }
    _legacySnapshots.remove(userId);
    _observedLegacyTokens.remove(userId);
    return snapshot;
  }

  @override
  Future<List<CloudSnapshotHistoryEntry>> history({
    required String userId,
  }) async {
    _checkAccess();
    return [
      for (final snapshot
          in _history[userId] ?? const <CloudSnapshotMetadata>[])
        CloudSnapshotHistoryEntry(
          revision: snapshot.revision,
          deviceName: snapshot.deviceName,
          rowCount: snapshot.rowCount,
          dataUpdatedAt: snapshot.dataUpdatedAt,
          uploadedAt: snapshot.uploadedAt,
          deviceManufacturer: snapshot.deviceManufacturer,
          deviceModel: snapshot.deviceModel,
        ),
    ];
  }

  @override
  Future<CloudSnapshotMetadata> downloadRevision({
    required String userId,
    required int revision,
  }) async {
    _checkAccess();
    for (final snapshot
        in _history[userId] ?? const <CloudSnapshotMetadata>[]) {
      if (snapshot.revision == revision) return snapshot;
    }
    throw StateError('该云端备份已不在最近 $cloudSnapshotHistoryLimit 份之内。');
  }

  int _legacyRevision(String token) =>
      -(int.parse(token.substring(0, 15), radix: 16) + 1);
}

/// 恢复替换事务内的边界，用于在确切时机观察状态变化（例如账号切换）。
///
/// 只在事务内触发，且不改变默认行为：未注入观察者时这些边界只是取消检查点。
enum CloudRestoreStage {
  /// 事务已开始、异步预检完成，尚未读取本机日历映射。
  beforeReplacement,

  /// 已读取本机日历映射，尚未删除任何业务行。
  afterCalendarLookup,

  /// 所有业务行已写入，尚未提交。
  afterReplacement,
}

class CloudSnapshotLocalState {
  const CloudSnapshotLocalState({
    required this.fingerprint,
    required this.payload,
    required this.rowCount,
    required this.dataUpdatedAt,
    required this.hasUnfinishedFlow,
  });

  final String fingerprint;
  final Map<String, dynamic> payload;
  final int rowCount;
  final DateTime dataUpdatedAt;
  final bool hasUnfinishedFlow;
}

String? _normalizeDeviceMetadata(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// Replaces only the explicitly listed business tables for [userId]. The user
/// must pass the fingerprint captured before showing a destructive choice.
class CloudSnapshotRepository {
  CloudSnapshotRepository({
    required this.database,
    required this.remote,
    required this.userId,
    this.deviceId,
    required this.deviceName,
    String? deviceManufacturer,
    String? deviceModel,
    this.syncResultStore = const CloudSyncResultStore(),
    CloudRecoveryPointStore? recoveryPointStore,
    this.onRestoreStage,
    this.deviceIdLoader,
    this.now = DateTime.now,
  }) : deviceManufacturer = _normalizeDeviceMetadata(deviceManufacturer),
       deviceModel = _normalizeDeviceMetadata(deviceModel),
       recoveryPointStore =
           recoveryPointStore ?? DriftCloudRecoveryPointStore(database) {
    if (userId.isEmpty ||
        (deviceId != null && deviceId!.isEmpty) ||
        deviceName.trim().isEmpty) {
      throw ArgumentError('User and device identity must be present.');
    }
  }

  final PactaDatabase database;
  final CloudSnapshotRemote remote;
  final String userId;
  final String? deviceId;
  final String deviceName;
  final String? deviceManufacturer;
  final String? deviceModel;
  final CloudSyncResultStore syncResultStore;
  final CloudRecoveryPointStore recoveryPointStore;

  /// 恢复替换事务内的边界观察者；组合层或测试可在此检查账号是否已切换。
  final Future<void> Function(CloudRestoreStage stage)? onRestoreStage;

  /// 设备标识来源。默认读取本机设备表；组合层或测试可注入，从而在“读取设备
  /// 标识”这一步控制完成时机（这一步也是上传前的异步准备之一）。
  final Future<String> Function()? deviceIdLoader;

  final DateTime Function() now;

  Future<CloudSyncResult?> loadSyncResult() => syncResultStore.load(userId);

  /// 基线写入串行化：恢复、手动同步与自动上传的应答彼此有序；取消后的
  /// 晚到应答即使在恢复之后到达，也不会覆盖恢复写入的基线。
  ///
  /// 用惰性链而不是预先创建的 Future.value()：它可能在本组件构造的 Zone 里
  /// 完成，之后的 then 回调就跑在测试的 fake-async 之外。
  Future<void>? _baselineChain;

  Future<T> _serializeBaseline<T>(Future<T> Function() action) {
    final previous = _baselineChain;
    final run = previous == null ? action() : previous.then((_) => action());
    _baselineChain = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _commitSyncResult(
    CloudSnapshotMetadata cloud,
    String fingerprint,
  ) => _serializeBaseline(() => _writeSyncResult(cloud, fingerprint));

  /// 清除基线同样串行化，避免与在途应答交错。
  Future<void> _clearSyncResult() =>
      _serializeBaseline(() => syncResultStore.clear(userId));

  Future<void> _saveSyncResult(
    CloudSnapshotMetadata cloud,
    String fingerprint,
  ) => _commitSyncResult(cloud, fingerprint);

  Future<void> _writeSyncResult(
    CloudSnapshotMetadata cloud,
    String fingerprint,
  ) async {
    final result = CloudSyncResult(
      succeededAt: now().toUtc(),
      localFingerprint: fingerprint,
      cloudRevision: cloud.revision,
      legacyToken: cloud.legacyToken,
    );
    try {
      await syncResultStore.save(userId, result);
    } catch (error) {
      throw CloudSyncResultPersistenceException(result: result, cause: error);
    }
  }

  /// Calendar source columns tied to one physical device are deliberately
  /// omitted. A download reuses this device's matching source mapping when one
  /// exists; otherwise the restored source remains unselected.
  static const _calendarSourceExcluded = {'local_calendar_id', 'is_selected'};

  /// Legacy envelope version still accepted on read.
  ///
  /// A version 1 payload (from an older client) is accepted only through an
  /// explicit, validated conversion: documented missing columns are filled from
  /// the stored values and its calendar blocks are promoted into owned schedule
  /// copies before anything local is touched. Current writes always use
  /// [cloudSnapshotSchemaVersion].
  static const _legacySnapshotSchemaVersion = 1;

  /// Complete core version 2 (owned schedules + preparation seconds).
  ///
  /// Still accepted on read through the explicit goal-pin conversion below.
  /// Any half-missing version 2 payload is rejected atomically instead.

  /// Keep this table list explicit. It excludes per-device preferences,
  /// lifecycle state, device identity, and the legacy upload queue.
  static const _businessTables = <String>[
    'local_goals',
    'local_tasks',
    'local_national_focus_cards',
    'local_national_focus_strengthening_levels',
    'local_national_focus_requirement_versions',
    'local_national_focus_maintenance',
    'local_national_focus_failures',
    'focus_precedent_rules',
    'focus_appointments',
    'focus_sessions',
    'focus_nodes',
    'focus_chain_records',
    'appointment_chain_records',
    'chain_signals',
    'focus_sync_sources',
    'local_calendar_sources',
    'local_calendar_blocks',
    'local_schedules',
    'local_schedule_recurrences',
  ];

  Future<CloudSnapshotMetadata?> inspectCloud() =>
      remote.inspect(userId: userId);

  Future<CloudSnapshotLocalState> captureLocalState() async {
    return database.transaction(_captureLocalState);
  }

  Future<CloudSnapshotLocalState> _captureLocalState() async {
    final payload = await _exportPayload();
    final rowCount = (payload['tables'] as Map<String, dynamic>).values
        .cast<List<dynamic>>()
        .fold<int>(0, (total, rows) => total + rows.length);
    final hasUnfinished = await _hasUnfinishedFlow();
    return CloudSnapshotLocalState(
      fingerprint: _fingerprint(payload),
      payload: payload,
      rowCount: rowCount,
      dataUpdatedAt: _latestDataTimestamp(payload) ?? DateTime.now().toUtc(),
      hasUnfinishedFlow: hasUnfinished,
    );
  }

  /// [requestId] 让同一次上传请求可以安全重试：服务端对同一用户同一
  /// requestId 只写入一份历史备份。未提供时至多上传一次，不重试。
  ///
  /// [captured] 是发起该请求时捕获并持久化的快照。响应丢失后重试必须重发
  /// 完全相同的载荷，否则服务端会把它当作“同一请求换了内容”（PT422）。
  /// 传入快照仍要满足 [expectedFingerprint]，不跳过任何校验。
  Future<CloudSnapshotMetadata> uploadLocal({
    required int expectedRevision,
    required String expectedFingerprint,
    String? requestId,
    CloudSnapshotLocalState? captured,
    bool Function()? isCancelled,
  }) async {
    final state = captured ?? await captureLocalState();
    if (state.fingerprint != expectedFingerprint) {
      throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
    }
    // 设备标识读取本身也要等一次异步；取消（关闭开关、切换账号、恢复备份）
    // 可能正好发生在这段等待里。发送前必须再查一次，否则会带着取消前的
    // 旧快照继续覆盖云端。
    final deviceId = await _resolveDeviceId();
    _throwIfUploadCancelled(isCancelled);
    final cloud = await remote.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: state.payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: state.dataUpdatedAt,
      rowCount: state.rowCount,
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      requestId: requestId,
    );
    // 取消（恢复、关闭开关、切换账号）之后到达的应答不得写基线：
    // 否则恢复后的“已处理版本”会被改回这次上传的 revision。
    await _commitSyncResultGuarded(cloud, state.fingerprint, isCancelled);
    return cloud;
  }

  Future<void> _commitSyncResultGuarded(
    CloudSnapshotMetadata cloud,
    String fingerprint,
    bool Function()? isCancelled,
  ) => _serializeBaseline(() async {
    if (isCancelled?.call() == true) return;
    await _writeSyncResult(cloud, fingerprint);
  });

  /// 载荷的变更指纹，与 [CloudSnapshotLocalState.fingerprint] 同口径。
  /// 用于校验持久化请求中的冻结载荷没有与指纹脱节。
  String fingerprintOfPayload(Map<String, dynamic> payload) =>
      _fingerprint(payload);

  Future<void> downloadCloud({
    required int expectedRevision,
    required String expectedFingerprint,
  }) async {
    final localBefore = await captureLocalState();
    if (localBefore.hasUnfinishedFlow) {
      throw StateError('预约或专注尚未结束，暂不能覆盖本机数据。');
    }
    if (localBefore.fingerprint != expectedFingerprint) {
      throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
    }
    final cloud = await remote.download(userId: userId);
    if (cloud.revision != expectedRevision) {
      throw StateError('云端快照已变化，请重新检查后再同步。');
    }
    final payload = cloud.payload;
    if (payload == null) throw StateError('Cloud snapshot has no payload.');
    final validatedRows = await _validatePayload(payload);
    final latestCloud = await remote.inspect(userId: userId);
    if (latestCloud?.revision != expectedRevision) {
      throw StateError('云端快照已变化，请重新检查后再同步。');
    }

    final restoredFingerprint = await _replaceLocalTables(
      validatedRows: validatedRows,
      expectedFingerprint: expectedFingerprint,
    );
    await _saveSyncResult(cloud, restoredFingerprint);
  }

  /// 已成功写入的云端备份，最新在前。
  Future<List<CloudSnapshotHistoryEntry>> listCloudHistory() =>
      remote.history(userId: userId);

  /// 本机恢复点，最新在前；与云端备份分开保存。
  Future<List<CloudRecoveryPointSummary>> listLocalRecoveryPoints() =>
      recoveryPointStore.list(userId);

  /// 恢复指定云端备份到本机：先持久保存本机恢复点，再整体替换。
  /// 全程不上传，因此不会自动覆盖云端。
  Future<void> restoreCloudVersion({
    required int revision,
    required String expectedFingerprint,
    bool Function()? isCancelled,
  }) async {
    _throwIfCancelled(isCancelled);
    final cloud = await remote.downloadRevision(
      userId: userId,
      revision: revision,
    );
    final payload = cloud.payload;
    if (payload == null) throw StateError('该云端备份缺少内容，无法恢复。');
    final validatedRows = await _validatePayload(payload);
    _throwIfCancelled(isCancelled);
    await _replaceWithRecoveryPoint(
      validatedRows: validatedRows,
      expectedFingerprint: expectedFingerprint,
      reason: CloudRecoveryReason.beforeCloudRestore,
      isCancelled: isCancelled,
    );
    await _saveSyncResult(cloud, await _currentFingerprint());
  }

  /// 从本机恢复点找回数据；同样先保存当前状态，避免找回本身不可撤销。
  ///
  /// 找回的是更早的本机内容，原来的“已处理云版本 + 指纹”基线不再能证明
  /// 当前本机数据与云端一致，因此在替换前清除；否则下一次今日确认会把旧
  /// 内容当成“与云端一致”的改动自动覆盖最新云版本。清除失败则不替换。
  Future<void> restoreLocalRecoveryPoint({
    required String pointId,
    required String expectedFingerprint,
    bool Function()? isCancelled,
  }) async {
    _throwIfCancelled(isCancelled);
    final point = await recoveryPointStore.load(userId, pointId);
    if (point == null) throw StateError('本机恢复点不存在，可能已被清理。');
    final validatedRows = await _validatePayload(point.payload);
    _throwIfCancelled(isCancelled);
    await _clearSyncResult();
    await _replaceWithRecoveryPoint(
      validatedRows: validatedRows,
      expectedFingerprint: expectedFingerprint,
      reason: CloudRecoveryReason.beforeRecoveryRestore,
      isCancelled: isCancelled,
    );
  }

  /// 恢复点必须先真正落盘并可读回，才允许替换本机数据。
  Future<void> _replaceWithRecoveryPoint({
    required Map<String, List<Map<String, Object?>>> validatedRows,
    required String expectedFingerprint,
    required CloudRecoveryReason reason,
    bool Function()? isCancelled,
  }) async {
    final localBefore = await captureLocalState();
    if (localBefore.hasUnfinishedFlow) {
      throw StateError('预约或专注尚未结束，暂不能覆盖本机数据。');
    }
    if (localBefore.fingerprint != expectedFingerprint) {
      throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
    }
    final point = CloudRecoveryPoint(
      id: const Uuid().v4(),
      userId: userId,
      createdAt: now().toUtc(),
      reason: reason,
      dataUpdatedAt: localBefore.dataUpdatedAt,
      rowCount: localBefore.rowCount,
      payload: localBefore.payload,
      sourceDeviceName: deviceName,
    );
    await recoveryPointStore.save(point);
    // 读回必须证明落盘的就是本次恢复点：同一用户、同一标识，且内容指纹与
    // 替换前的本机状态一致；任何不一致都说明保存不可信，不能继续替换。
    final persisted = await recoveryPointStore.load(userId, point.id);
    if (persisted == null ||
        persisted.userId != userId ||
        persisted.id != point.id ||
        _fingerprint(persisted.payload) != localBefore.fingerprint) {
      throw StateError('本机恢复点未正确保存，已取消恢复。');
    }
    _throwIfCancelled(isCancelled);
    await _replaceLocalTables(
      validatedRows: validatedRows,
      expectedFingerprint: expectedFingerprint,
      isCancelled: isCancelled,
    );
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) throw const CloudRestoreCancelled();
  }

  void _throwIfUploadCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) throw const CloudUploadCancelled();
  }

  Future<void> _notifyRestoreStage(CloudRestoreStage stage) async {
    final observer = onRestoreStage;
    if (observer != null) await observer(stage);
  }

  Future<String> _currentFingerprint() async =>
      (await captureLocalState()).fingerprint;

  /// Repeat both safety checks immediately before the transaction. Nothing is
  /// deleted until the entire schema and every row has passed validation.
  Future<String> _replaceLocalTables({
    required Map<String, List<Map<String, Object?>>> validatedRows,
    required String expectedFingerprint,
    bool Function()? isCancelled,
  }) async {
    late String restoredFingerprint;
    await database.transaction(() async {
      final localAtCommit = await _captureLocalState();
      await _notifyRestoreStage(CloudRestoreStage.beforeReplacement);
      // 事务内、删除前检查：预检与删除之间用户可能已经切换账号或发起取消，
      // 此时必须整体放弃替换。
      _throwIfCancelled(isCancelled);
      if (localAtCommit.hasUnfinishedFlow) {
        throw StateError('预约或专注尚未结束，暂不能覆盖本机数据。');
      }
      if (localAtCommit.fingerprint != expectedFingerprint) {
        throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
      }
      final calendarDeviceData = await _localCalendarDeviceData();
      await _notifyRestoreStage(CloudRestoreStage.afterCalendarLookup);
      // 读取本机日历映射又是一次异步等待，删除前必须再检查一次。
      _throwIfCancelled(isCancelled);
      for (final table in _businessTables.reversed) {
        await database.customStatement(
          'DELETE FROM "${_quoteIdentifier(table)}" WHERE user_id = ?',
          [userId],
        );
      }
      for (final table in _businessTables) {
        for (final row in validatedRows[table]!) {
          if (table == 'local_calendar_sources') {
            final sourceId = row['source_id'] as String;
            final local = calendarDeviceData[sourceId];
            row['local_calendar_id'] = local?.localCalendarId;
            row['is_selected'] = local?.isSelected == true ? 1 : 0;
          }
          final columns = row.keys.toList();
          final names = columns
              .map((column) => '"${_quoteIdentifier(column)}"')
              .join(',');
          final placeholders = List.filled(columns.length, '?').join(',');
          await database.customStatement(
            'INSERT INTO "${_quoteIdentifier(table)}" ($names) VALUES ($placeholders)',
            [for (final column in columns) row[column]],
          );
        }
      }
      await _notifyRestoreStage(CloudRestoreStage.afterReplacement);
      // 事务末尾：替换过程中的账号切换或取消必须让整个事务回滚，
      // 不能留下半份或错属主的数据。
      _throwIfCancelled(isCancelled);
      restoredFingerprint = (await _captureLocalState()).fingerprint;
    });
    database.notifyUpdates({
      for (final table in database.allTables)
        if (_businessTables.contains(table.actualTableName))
          drift.TableUpdate.onTable(table),
    });
    return restoredFingerprint;
  }

  Future<Map<String, LocalCalendarSource>> _localCalendarDeviceData() async {
    final rows = await (database.select(
      database.localCalendarSources,
    )..where((row) => row.userId.equals(userId))).get();
    return {for (final row in rows) row.sourceId: row};
  }

  Future<Map<String, dynamic>> _exportPayload() async {
    final registeredTables = database.allTables
        .map((table) => table.actualTableName)
        .toSet();
    for (final table in _businessTables) {
      if (!registeredTables.contains(table)) {
        throw StateError('Snapshot table is not registered in Drift: $table');
      }
    }
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _businessTables) {
      final allColumns = await _tableColumns(table);
      final columns = allColumns
          .where(
            (column) =>
                table != 'local_calendar_sources' ||
                !_calendarSourceExcluded.contains(column),
          )
          .toList();
      final orderBy = await _primaryKey(table, allColumns);
      final rows = await database
          .customSelect(
            'SELECT ${columns.map((column) => '"${_quoteIdentifier(column)}"').join(',')} '
            'FROM "${_quoteIdentifier(table)}" WHERE user_id = '
            '? ORDER BY $orderBy',
            variables: [drift.Variable<String>(userId)],
          )
          .get();
      tables[table] = [
        for (final row in rows)
          {for (final column in columns) column: _jsonValue(row.data[column])},
      ];
    }
    return {
      'schemaVersion': cloudSnapshotSchemaVersion,
      'userId': userId,
      'tables': tables,
    };
  }

  Future<Map<String, List<Map<String, Object?>>>> _validatePayload(
    Map<String, dynamic> payload,
  ) async {
    final schemaVersion = payload['schemaVersion'];
    final isLegacy = schemaVersion == _legacySnapshotSchemaVersion;
    final isVersion2 = schemaVersion == _version2SnapshotSchemaVersion;
    if (!isLegacy &&
        !isVersion2 &&
        schemaVersion != cloudSnapshotSchemaVersion) {
      throw StateError('云端快照版本不受支持：$schemaVersion。');
    }
    // 版本 1 与完整的版本 2 都要按显式转换补上重复日程领域；版本 3 必须是
    // 当前完整形状，任何缺失都由后面的严格列校验整体拒绝。
    final preRecurrence = isLegacy || isVersion2;
    if (payload['userId'] != userId) {
      throw StateError('Snapshot version or user identity is invalid.');
    }
    final sourceTables = payload['tables'];
    final rawTables = sourceTables is Map<String, dynamic>
        ? Map<String, dynamic>.from(sourceTables)
        : sourceTables;
    if (rawTables is! Map<String, dynamic>) {
      throw StateError('Snapshot table set is invalid.');
    }
    // Version 1 payloads predate the chain-signal table as well; the missing
    // table means "no signals yet", not a malformed snapshot.
    if (isLegacy) {
      rawTables.putIfAbsent('chain_signals', () => <dynamic>[]);
    }
    // 完整 core 2 是两个票据的并集，所以任何一半缺失的 v2 都是合并前生成的
    // 残缺载荷：整体拒绝（在任何本地行被读写之前），绝不静默丢弃另一方数据。
    // 版本 3 是它的超集，同样必须携带这两个领域。
    if (!isLegacy) {
      if (rawTables['local_schedules'] is! List) {
        throw StateError('版本 2 及以后快照缺少日程表，已整体拒绝；请先升级本机再上传。');
      }
      final appointmentRows = rawTables['focus_appointments'];
      if (appointmentRows is List) {
        for (final row in appointmentRows) {
          if (row is Map && !row.containsKey('preparation_seconds')) {
            throw StateError('版本 2 及以后快照缺少预约准备时长，已整体拒绝；请先升级本机再上传。');
          }
        }
      }
      // 完整核心 2 若已经带上后来的列（例如目标置顶），这些列属于已知列：
      // 迁移只补齐缺失的默认值，已存值原样保留，不整体拒绝（见集成契约）。
    }
    if (preRecurrence) {
      // v1/v2 没有规则表：显式转换成一个空集合，表示"这个账号还没有重复规则"，
      // 而不是把缺失当成非法载荷。
      rawTables.putIfAbsent('local_schedule_recurrences', () => <dynamic>[]);
    } else if (rawTables['local_schedule_recurrences'] is! List) {
      throw StateError('版本 3 快照缺少重复规则表，已整体拒绝；请先升级本机再上传。');
    }
    final expectedTables = isLegacy
        ? [
            for (final table in _businessTables)
              if (table != 'local_schedules') table,
          ]
        : _businessTables;
    if (rawTables.keys.length != expectedTables.length ||
        !expectedTables.every(rawTables.containsKey)) {
      throw StateError('Snapshot table set is invalid.');
    }
    final registeredTables = database.allTables
        .map((table) => table.actualTableName)
        .toSet();
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in expectedTables) {
      if (!registeredTables.contains(table)) {
        throw StateError('Snapshot table is not registered in Drift: $table');
      }
      final localColumns = await _tableColumns(table);
      final expectedColumns = localColumns
          .where(
            (column) =>
                table != 'local_calendar_sources' ||
                !_calendarSourceExcluded.contains(column),
          )
          .toSet();
      final columnInfo = await _tableColumnInfo(table);
      final rawRows = rawTables[table];
      if (rawRows is! List) throw StateError('Invalid rows for $table.');
      final rows = <Map<String, Object?>>[];
      for (final item in rawRows) {
        if (item is! Map<String, dynamic>) {
          throw StateError('Invalid columns or user ownership in $table.');
        }
        final sourceRow = preRecurrence
            ? _withOlderVersionDefaults(
                table,
                item,
                expectedColumns,
                isLegacy: isLegacy,
              )
            : item;
        if (sourceRow.keys.length != expectedColumns.length ||
            !expectedColumns.every(sourceRow.containsKey) ||
            sourceRow['user_id'] != userId) {
          throw StateError('Invalid columns or user ownership in $table.');
        }
        for (final column in expectedColumns) {
          if (!_isValidSqliteValue(sourceRow[column], columnInfo[column]!)) {
            throw StateError('Invalid value type in $table.$column.');
          }
        }
        final row = <String, Object?>{
          for (final column in expectedColumns)
            column: _sqliteValue(sourceRow[column]),
        };
        if (const {'local_goals', 'local_tasks'}.contains(table)) {
          try {
            row['description'] = normalizeDescription(
              row['description'] as String,
            );
          } on ArgumentError {
            throw StateError('Invalid value in $table.description.');
          }
        }
        rows.add(row);
      }
      result[table] = rows;
    }
    if (isLegacy) {
      // Explicit legacy read: promote the old calendar-block projection into
      // owned schedule copies inside a throwaway payload copy. The conversion
      // happens before any local row is touched, so a rejected payload leaves
      // the device exactly as it was.
      result['local_schedules'] = await _promotedScheduleRows(result);
    }
    await _validateReferences(result);
    return result;
  }

  /// 旧版本的载荷缺少后来新增的列；只补这里列出的默认值，
  /// 其余缺列、未知列、类型错误与用户归属仍按严格校验拒绝。
  ///
  /// 版本 1：日程表整体缺席（由旧日历副本提升），另缺描述与预约准备时长。
  /// 版本 2：完整核心 2，只缺目标置顶标记与排序位。
  static const _legacySnapshotColumnDefaults = <String, Map<String, Object?>>{
    'local_goals': {'description': '', 'is_pinned': 0, 'sort_order': null},
    'local_tasks': {'description': ''},
    'focus_appointments': {'preparation_seconds': null},
  };

  /// 重复领域在 v1/v2 中不存在时的显式默认值。
  ///
  /// 只补缺失键：已存值（包括人为写入的非空值）一律保留，随后仍要过完整的
  /// 类型与引用校验。v3 不走这条路径，缺列即拒绝。
  static const _recurrenceColumnDefaults = <String, Object?>{
    'recurrence_id': null,
    'recurrence_series_id': null,
    'recurrence_date': null,
    'recurrence_time_zone_id': null,
    'recurrence_start_minutes': null,
    'is_recurrence_exception': 0,
    'is_recurrence_cancelled': 0,
  };

  /// 07 的目标置顶与手动排序位同样晚于完整 core 2：v1/v2 缺列时补
  /// "未置顶、无排序位"，已存值原样保留。
  static const _goalPinColumnDefaults = <String, Object?>{
    'is_pinned': 0,
    'sort_order': null,
  };

  Map<String, dynamic> _withOlderVersionDefaults(
    String table,
    Map<String, dynamic> row,
    Set<String> expectedColumns, {
    required bool isLegacy,
  }) {
    final defaults = <String, Object?>{
      if (isLegacy) ...?_legacySnapshotColumnDefaults[table],
      // ticket 11：回顾字段晚于完整的 core 2。v1/v2 载荷缺这一列都表示未回顾，
      // 已写入的值原样保留（只补缺失键），随后仍要过完整类型校验。
      if (table == 'local_national_focus_failures') 'reviewed_at': null,
      // ticket 07：置顶与排序位同样晚于 core 2。
      if (table == 'local_goals') ..._goalPinColumnDefaults,
      if (table == 'local_schedules') ..._recurrenceColumnDefaults,
    };
    if (defaults.isEmpty) return row;
    final additions = <String, dynamic>{
      for (final entry in defaults.entries)
        if (expectedColumns.contains(entry.key) && !row.containsKey(entry.key))
          entry.key: entry.value,
    };
    if (additions.isEmpty) return row;
    return <String, dynamic>{...row, ...additions};
  }

  /// Converts the calendar blocks of a version 1 payload into owned schedule
  /// rows, keeping every source marker for later import deduplication.
  Future<List<Map<String, Object?>>> _promotedScheduleRows(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final sourceNames = {
      for (final row in tables['local_calendar_sources']!)
        if (row['source_id'] is String && row['display_name'] is String)
          row['source_id'] as String: row['display_name'] as String,
    };
    final blocks = <LegacyCalendarBlockProjection>[];
    DateTime? migratedAt;
    for (final row in tables['local_calendar_blocks']!) {
      final startsAt = _epochToDateTime(row['starts_at']);
      final endsAt = _epochToDateTime(row['ends_at']);
      final updatedAt = _epochToDateTime(row['updated_at']);
      if (startsAt == null || endsAt == null || updatedAt == null) {
        throw StateError('旧版日历块缺少有效时间，无法转换日程。');
      }
      blocks.add(
        LegacyCalendarBlockProjection(
          sourceId: row['source_id'] as String,
          sourceEventId: row['source_event_id'] as String,
          occurrenceId: row['occurrence_id'] as String,
          eventIdentity: row['event_identity'] as String,
          title: row['title'] as String,
          startsAt: startsAt,
          endsAt: endsAt,
          allDay: row['all_day'] == 1,
          allDayStartDate: row['all_day_start_date'] as String?,
          allDayEndDateExclusive: row['all_day_end_date_exclusive'] as String?,
        ),
      );
      if (migratedAt == null || updatedAt.isAfter(migratedAt)) {
        migratedAt = updatedAt;
      }
    }
    final promoted = projectLegacyCalendarBlocks(
      blocks,
      migratedAt: migratedAt ?? DateTime.utc(1970),
      sourceNames: sourceNames,
    );
    final columns = (await _tableColumns('local_schedules')).toSet();
    return [
      for (final schedule in promoted) _promotedScheduleRow(schedule, columns),
    ];
  }

  Map<String, Object?> _promotedScheduleRow(
    PromotedSchedule schedule,
    Set<String> columns,
  ) {
    final row = <String, Object?>{
      'user_id': userId,
      'id': schedule.id,
      'title': schedule.title,
      'notes': '',
      'starts_at': _epochSeconds(schedule.startsAt),
      'ends_at': _epochSeconds(schedule.endsAt),
      'all_day': schedule.allDay ? 1 : 0,
      'all_day_start_date': schedule.allDayStartDate,
      'all_day_end_date_exclusive': schedule.allDayEndDateExclusive,
      'is_completed': 0,
      'completed_at': null,
      'task_id': null,
      'reminder_minutes_before': null,
      'origin': ScheduleOrigin.legacyCalendarBlock.storageValue,
      'source_ids': jsonEncode(schedule.sourceIds),
      'source_names': jsonEncode(schedule.sourceNames),
      'source_event_id': schedule.sourceEventId,
      'occurrence_id': schedule.occurrenceId,
      'event_identity': schedule.eventIdentity,
      // 旧日历块提升出来的副本不是重复日程，也没有例外或墓碑。
      ..._recurrenceColumnDefaults,
      'created_at': _epochSeconds(schedule.createdAt),
      'updated_at': _epochSeconds(schedule.updatedAt),
    };
    if (row.keys.length != columns.length || !columns.every(row.containsKey)) {
      throw StateError('转换出的日程字段与本机日程表不一致。');
    }
    return row;
  }

  int _epochSeconds(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;

  DateTime? _epochToDateTime(Object? value) => value is int
      ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
      : null;

  Future<Map<String, Map<String, Object?>>> _tableColumnInfo(
    String table,
  ) async {
    final rows = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    return {
      for (final row in rows)
        row.read<String>('name'): {
          'type': row.read<String>('type').toUpperCase(),
          'notnull': row.read<int>('notnull') == 1,
          'pk': row.read<int>('pk') > 0,
        },
    };
  }

  bool _isValidSqliteValue(Object? value, Map<String, Object?> column) {
    if (value == null) return column['notnull'] != true && column['pk'] != true;
    final type = column['type'] as String;
    if (type.contains('INT')) return value is int;
    if (type.contains('CHAR') ||
        type.contains('CLOB') ||
        type.contains('TEXT')) {
      return value is String;
    }
    if (type.contains('REAL') ||
        type.contains('FLOA') ||
        type.contains('DOUB')) {
      return value is num;
    }
    if (type.contains('BLOB')) return value is String;
    return value is num || value is String;
  }

  Future<void> _validateReferences(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    Set<Object?> ids(String table) => {
      for (final row in tables[table]!) row['id'],
    };
    final goalIds = ids('local_goals');
    final taskIds = ids('local_tasks');
    final cardIds = ids('local_national_focus_cards');
    final sessionIds = ids('focus_sessions');
    final appointmentIds = ids('focus_appointments');
    final sourceIds = {
      for (final row in tables['local_calendar_sources']!) row['source_id'],
    };
    void requireReference(bool valid, String label) {
      if (!valid) throw StateError('Snapshot contains an unknown $label.');
    }

    for (final row in tables['local_tasks']!) {
      requireReference(goalIds.contains(row['goal_id']), 'Goal reference');
    }
    for (final table in const [
      'local_national_focus_strengthening_levels',
      'local_national_focus_requirement_versions',
      'local_national_focus_failures',
    ]) {
      for (final row in tables[table]!) {
        requireReference(
          cardIds.contains(row['card_id']),
          'National Focus card reference',
        );
      }
    }
    for (final row in tables['local_national_focus_cards']!) {
      final name = row['name'];
      requireReference(
        name is String && name.trim().isNotEmpty,
        'National Focus card name',
      );
      final parentId = row['parent_id'];
      if (parentId != null) {
        requireReference(cardIds.contains(parentId), 'parent card reference');
      }
    }
    for (final row in tables['focus_appointments']!) {
      requireReference(
        taskIds.contains(row['task_id']),
        'appointment Task reference',
      );
    }
    for (final row in tables['focus_sessions']!) {
      requireReference(
        taskIds.contains(row['task_id']),
        'Session Task reference',
      );
      final appointmentId = row['appointment_id'];
      if (appointmentId != null) {
        requireReference(
          appointmentIds.contains(appointmentId),
          'Appointment reference',
        );
      }
    }
    for (final row in tables['focus_nodes']!) {
      requireReference(
        sessionIds.contains(row['session_id']),
        'Focus Session reference',
      );
      requireReference(
        taskIds.contains(row['task_id']),
        'Focus Node Task reference',
      );
    }
    for (final row in tables['local_calendar_blocks']!) {
      requireReference(
        sourceIds.contains(row['source_id']),
        'calendar source reference',
      );
    }
    final recurrenceIds = <Object?>{
      for (final row in tables['local_schedule_recurrences']!) row['id'],
    };
    final ruleZones = <Object?, Object?>{
      for (final row in tables['local_schedule_recurrences']!)
        row['id']: row['time_zone_id'],
    };
    // 稳定身份（系列 + 原始发生日期）在一份载荷里必须唯一：同一期既是活实例
    // 又是墓碑会同时取消并展示它，恢复后无法解释。
    final occurrences = <String>{};
    for (final row in tables['local_schedule_recurrences']!) {
      final frequency = row['frequency'];
      final weekly = frequency == 'weekly';
      requireReference(
        frequency == 'daily' || weekly,
        'Schedule recurrence frequency',
      );
      final weekdays = _decodeWeekdays(row['weekdays']);
      requireReference(weekdays != null, 'Schedule recurrence weekdays');
      requireReference(
        weekly ? weekdays!.isNotEmpty : weekdays!.isEmpty,
        'Schedule recurrence weekday set',
      );
      final firstDate = row['first_date'];
      requireReference(
        _isCalendarDate(firstDate),
        'Schedule recurrence first date',
      );
      final endDate = row['end_date'];
      requireReference(
        endDate == null ||
            (_isCalendarDate(endDate) &&
                (endDate as String).compareTo(firstDate as String) >= 0),
        'Schedule recurrence end date',
      );
      final zone = row['time_zone_id'];
      // 只接受客户端真正能展开的 IANA 时区：Mars/Olympus 这类字符串会让
      // getRecurrenceRules 在恢复后直接抛错，必须在替换本机数据之前整体拒绝。
      requireReference(
        zone is String && _isSupportedTimeZone(zone),
        'Schedule recurrence time zone',
      );
      final shiftDays = row['shift_days'];
      requireReference(
        shiftDays is int && shiftDays.abs() <= maxRecurrenceShiftDays,
        'Schedule recurrence shift',
      );
      final ruleTitle = row['title'];
      requireReference(
        ruleTitle is String && ruleTitle.trim().isNotEmpty,
        'Schedule recurrence title',
      );
      requireReference(row['notes'] is String, 'Schedule recurrence notes');
      final ruleTaskId = row['task_id'];
      requireReference(
        ruleTaskId == null || taskIds.contains(ruleTaskId),
        'Schedule recurrence Task reference',
      );
      // 规则模板的提醒偏移与普通实例共用同一契约：null 或 0..10080 分钟。
      // 类型（小数/字符串）与缺键已由 SQLite 列类型和严格列集合提前拒绝；
      // 这里补上范围，避免越界值在恢复后随懒展开扩散到实例。
      final ruleReminder = row['reminder_minutes_before'];
      if (ruleReminder != null) {
        requireReference(
          ruleReminder is int &&
              ruleReminder >= 0 &&
              ruleReminder <= maxScheduleReminderMinutesBefore,
          'Schedule recurrence reminder offset',
        );
      }
      final allDay = row['all_day'];
      requireReference(
        allDay == 0 || allDay == 1,
        'Schedule recurrence all-day',
      );
      final startMinutes = row['start_minutes_of_day'];
      final duration = row['duration_minutes'];
      final daySpan = row['day_span'];
      if (allDay == 1) {
        requireReference(
          daySpan is int && daySpan >= 1,
          'Schedule recurrence day span',
        );
      } else {
        requireReference(
          startMinutes is int && startMinutes >= 0 && startMinutes < 24 * 60,
          'Schedule recurrence start minute',
        );
        requireReference(
          duration is int && duration >= 1,
          'Schedule recurrence duration',
        );
      }
    }
    for (final row in tables['local_schedules']!) {
      final taskId = row['task_id'];
      if (taskId != null) {
        requireReference(taskIds.contains(taskId), 'Schedule Task reference');
      }
      final title = row['title'];
      requireReference(
        title is String && title.trim().isNotEmpty,
        'Schedule title',
      );
      final startsAt = row['starts_at'];
      final endsAt = row['ends_at'];
      requireReference(
        startsAt is int && endsAt is int && endsAt > startsAt,
        'Schedule time range',
      );
      if (row['all_day'] == 1) {
        final startDate = row['all_day_start_date'];
        final endDate = row['all_day_end_date_exclusive'];
        requireReference(
          startDate is String &&
              endDate is String &&
              endDate.compareTo(startDate) > 0,
          'Schedule all-day range',
        );
      }
      final reminder = row['reminder_minutes_before'];
      if (reminder != null) {
        requireReference(
          reminder is int && reminder >= 0 && reminder <= 7 * 24 * 60,
          'Schedule reminder offset',
        );
      }
      final origin = row['origin'];
      requireReference(
        origin is String &&
            ScheduleOrigin.values.any((known) => known.storageValue == origin),
        'Schedule origin',
      );
      final recurrenceId = row['recurrence_id'];
      final exception = row['is_recurrence_exception'];
      final cancelled = row['is_recurrence_cancelled'];
      requireReference(
        (exception == 0 || exception == 1) &&
            (cancelled == 0 || cancelled == 1),
        'Schedule recurrence flags',
      );
      if (recurrenceId == null) {
        // 非重复日程不能带重复领域的一半字段：宁可整体拒绝，也不接受
        // 归属不明、无法安全展开的实例。
        requireReference(
          row['recurrence_series_id'] == null &&
              row['recurrence_date'] == null &&
              row['recurrence_time_zone_id'] == null &&
              row['recurrence_start_minutes'] == null &&
              exception == 0 &&
              cancelled == 0,
          'Schedule recurrence linkage',
        );
        continue;
      }
      requireReference(recurrenceIds.contains(recurrenceId), 'recurrence rule');
      requireReference(
        row['recurrence_series_id'] is String &&
            (row['recurrence_series_id'] as String).trim().isNotEmpty,
        'Schedule recurrence series identity',
      );
      requireReference(
        _isCalendarDate(row['recurrence_date']),
        'Schedule recurrence date',
      );
      final instanceZone = row['recurrence_time_zone_id'];
      requireReference(
        instanceZone is String &&
            _isSupportedTimeZone(instanceZone) &&
            instanceZone == ruleZones[recurrenceId],
        'Schedule recurrence instance zone',
      );
      // 结构性键必须逐字段读取：字符串插值里的 `$row[...]` 只会插入整张
      // Map，再拼上字面方括号，不同 id 的重复身份因此逃过校验。
      final seriesKey = row['recurrence_series_id'];
      final identityKey = row['recurrence_date'];
      requireReference(
        occurrences.add('$seriesKey@$identityKey'),
        'Schedule recurrence identity',
      );
      final startMinutes = row['recurrence_start_minutes'];
      requireReference(
        startMinutes == null ||
            (startMinutes is int &&
                startMinutes >= 0 &&
                startMinutes < 24 * 60),
        'Schedule recurrence instance start minute',
      );
    }
  }

  bool _isCalendarDate(Object? value) {
    if (value is! String) return false;
    try {
      parseRecurrenceDate(value, '日期');
      return true;
    } on ArgumentError {
      return false;
    }
  }

  bool _isSupportedTimeZone(Object? value) {
    if (value is! String || value.trim().isEmpty) return false;
    try {
      return FocusTimeZones.contains(value);
    } on Object {
      return false;
    }
  }

  /// 星期集合的存储形式：整数数组。非法内容返回 null，由调用方拒绝整份载荷。
  List<int>? _decodeWeekdays(Object? value) {
    if (value is! String) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    final weekdays = <int>[];
    for (final entry in decoded) {
      if (entry is! int || entry < DateTime.monday || entry > DateTime.sunday) {
        return null;
      }
      weekdays.add(entry);
    }
    return weekdays;
  }

  Future<List<String>> _tableColumns(String table) async {
    final result = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    final columns = result.map((row) => row.read<String>('name')).toList();
    if (!columns.contains('user_id')) {
      throw StateError('Snapshot table has no user ownership column: $table');
    }
    return columns;
  }

  Future<String> _primaryKey(String table, List<String> columns) async {
    final info = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    final primaryKeyColumns = [
      for (final row in info)
        if (row.read<int>('pk') > 0)
          (position: row.read<int>('pk'), name: row.read<String>('name')),
    ]..sort((left, right) => left.position.compareTo(right.position));
    if (primaryKeyColumns.isEmpty ||
        primaryKeyColumns.any((entry) => !columns.contains(entry.name))) {
      throw StateError('Snapshot table has no supported primary key: $table');
    }
    return primaryKeyColumns
        .map((entry) => '"${_quoteIdentifier(entry.name)}"')
        .join(',');
  }

  Future<bool> _hasUnfinishedFlow() async {
    final appointments = await database
        .customSelect(
          'SELECT 1 FROM focus_appointments WHERE user_id = ? AND status = ? LIMIT 1',
          variables: [
            drift.Variable<String>(userId),
            drift.Variable<String>('active'),
          ],
        )
        .get();
    if (appointments.isNotEmpty) return true;
    final sessions = await database
        .customSelect(
          'SELECT 1 FROM focus_sessions WHERE user_id = ? AND status IN (?, ?) LIMIT 1',
          variables: [
            drift.Variable<String>(userId),
            drift.Variable<String>('active'),
            drift.Variable<String>('paused'),
          ],
        )
        .get();
    return sessions.isNotEmpty;
  }

  Future<String> _resolveDeviceId() async {
    if (deviceIdLoader case final loader?) return loader();
    return _getDeviceId();
  }

  Future<String> _getDeviceId() async {
    if (deviceId case final provided?) return provided;
    final existing = await (database.select(
      database.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (existing != null) return existing.deviceId;
    final generated = const Uuid().v4();
    await database
        .into(database.focusSourceDevices)
        .insertOnConflictUpdate(
          FocusSourceDevicesCompanion.insert(
            userId: userId,
            deviceId: generated,
          ),
        );
    return generated;
  }

  DateTime? _latestDataTimestamp(Map<String, dynamic> payload) {
    const timestampKeys = {
      'updated_at',
      'occurred_at',
      'created_at',
      'started_at',
      'completed_at',
      'settled_at',
      'paused_at',
      'deleted_at',
      'review_disposition_updated_at',
      'effective_from',
      'checkpoint_at',
      'last_settled_checkpoint_at',
    };
    DateTime? latest;
    final tables = payload['tables'] as Map<String, dynamic>;
    for (final rows in tables.values.cast<List<dynamic>>()) {
      for (final raw in rows.cast<Map<String, dynamic>>()) {
        for (final key in raw.keys.where(timestampKeys.contains)) {
          final value = raw[key];
          if (value is int) {
            final timestamp = DateTime.fromMillisecondsSinceEpoch(
              value * 1000,
              isUtc: true,
            );
            if (latest == null || timestamp.isAfter(latest)) latest = timestamp;
          } else if (value is String) {
            final timestamp = DateTime.tryParse(value)?.toUtc();
            if (timestamp != null &&
                (latest == null || timestamp.isAfter(latest))) {
              latest = timestamp;
            }
          }
        }
      }
    }
    return latest;
  }

  Object? _jsonValue(Object? value) => switch (value) {
    DateTime dateTime => dateTime.toUtc().millisecondsSinceEpoch ~/ 1000,
    Uint8List bytes => base64Encode(bytes),
    _ => value,
  };

  Object? _sqliteValue(Object? value) => value;

  String _fingerprint(Map<String, dynamic> payload) {
    // Recovery checkpoints advance during an active focus flow without changing
    // the user's business choices. Keep them in the uploaded payload, but exclude
    // the same two device checkpoint fields as focus cloud serialization from
    // the preview change detector. Pauses, interval bounds and outcomes remain.
    final normalized = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    // 指纹也用于校验恢复点读回内容，因此对畸形载荷必须保持全函数：缺表或缺
    // 字段时只跳过归一化，不抛类型错误。
    final tables = normalized['tables'];
    final sessions = tables is Map<String, dynamic>
        ? tables['focus_sessions']
        : null;
    if (sessions is List) {
      for (final row in sessions) {
        if (row is! Map<String, dynamic>) continue;
        final encoded = row['effective_intervals'];
        if (encoded is! String) continue;
        final decoded = jsonDecode(encoded);
        if (decoded is! List) continue;
        for (final interval in decoded) {
          if (interval is! Map<String, dynamic>) continue;
          interval
            ..remove('monotonic_checkpoint_microseconds')
            ..remove('last_observed_wall_time');
        }
        row['effective_intervals'] = jsonEncode(decoded);
      }
    }
    final value = jsonEncode(normalized);
    // FNV-1a is only a local change detector, never an integrity boundary.
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return 'v2:${hash.toRadixString(16).padLeft(16, '0')}';
  }

  String _quoteIdentifier(String identifier) =>
      identifier.replaceAll('"', '""');
}
