import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 已发出、结果尚未确认的上传请求。
///
/// 同一 [requestId] 只对应这一份 [payload]：服务端按请求身份去重，重试必须
/// 重发完全相同的载荷；换了内容只能生成新请求（否则服务端报 PT422）。
class CloudAutoUploadAttempt {
  const CloudAutoUploadAttempt({
    required this.requestId,
    required this.fingerprint,
    required this.expectedRevision,
    required this.startedAt,
    required this.attempted,
    required this.payload,
    required this.rowCount,
    required this.dataUpdatedAt,
  });

  final String requestId;

  /// [payload] 的变更指纹，与 [CloudSnapshotLocalState.fingerprint] 同口径。
  final String fingerprint;
  final int expectedRevision;
  final DateTime startedAt;

  /// true 表示请求可能已到达服务端，必须用同一身份重试以取得原始结果。
  final bool attempted;
  final Map<String, dynamic> payload;
  final int rowCount;
  final DateTime dataUpdatedAt;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'fingerprint': fingerprint,
    'expectedRevision': expectedRevision,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'attempted': attempted,
    'rowCount': rowCount,
    'dataUpdatedAt': dataUpdatedAt.toUtc().toIso8601String(),
    'payload': payload,
  };

  static CloudAutoUploadAttempt? fromJson(Object? value) {
    if (value is! Map) return null;
    final requestId = value['requestId'];
    final fingerprint = value['fingerprint'];
    final expectedRevision = value['expectedRevision'];
    final startedAt = _time(value['startedAt']);
    final attempted = value['attempted'];
    final payload = value['payload'];
    final rowCount = value['rowCount'];
    final dataUpdatedAt = _time(value['dataUpdatedAt']);
    if (requestId is! String ||
        requestId.isEmpty ||
        fingerprint is! String ||
        fingerprint.isEmpty ||
        expectedRevision is! int ||
        startedAt == null ||
        attempted is! bool ||
        rowCount is! int ||
        dataUpdatedAt == null ||
        payload is! Map) {
      return null;
    }
    return CloudAutoUploadAttempt(
      requestId: requestId,
      fingerprint: fingerprint,
      expectedRevision: expectedRevision,
      startedAt: startedAt,
      attempted: attempted,
      payload: Map<String, dynamic>.from(payload),
      rowCount: rowCount,
      dataUpdatedAt: dataUpdatedAt,
    );
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

/// 跨重启保留的自动上传队列：一条合并后的待传意图，和至多一条已发出但
/// 未确认结果的请求。队列不保存“待上传副本”以外的业务状态。
class CloudAutoUploadQueue {
  const CloudAutoUploadQueue({
    this.pending = false,
    this.requestedAt,
    this.pendingSequence = 0,
    this.request,
    this.blockedReason,
  });

  final bool pending;
  final DateTime? requestedAt;

  /// 意图身份：每次新确认自增。开始请求时只消费“自己捕获之前”的意图，
  /// 不吞掉捕获之后到达的新确认。
  final int pendingSequence;
  final CloudAutoUploadAttempt? request;

  /// 需要用户核对云端数据后才能继续的原因（PT422/PT425/未处理云版本）。
  final String? blockedReason;

  bool get hasWork => pending || request != null;

  CloudAutoUploadQueue recordIntent(DateTime at) => CloudAutoUploadQueue(
    pending: true,
    requestedAt: pending ? requestedAt : at,
    pendingSequence: pendingSequence + 1,
    request: request,
    blockedReason: blockedReason,
  );

  /// 开始一个请求：[servedThrough] 是捕获载荷时已存在的意图序号。
  /// 之后到达的新确认仍是 pending，等待本轮结束后的新请求。
  CloudAutoUploadQueue startRequest(
    CloudAutoUploadAttempt attempt, {
    required int servedThrough,
  }) {
    final stillPending = pendingSequence > servedThrough;
    return CloudAutoUploadQueue(
      pending: pending && stillPending,
      requestedAt: stillPending ? requestedAt : null,
      pendingSequence: pendingSequence,
      request: attempt,
      blockedReason: blockedReason,
    );
  }

  CloudAutoUploadQueue clearRequest() => CloudAutoUploadQueue(
    pending: pending,
    requestedAt: requestedAt,
    pendingSequence: pendingSequence,
    blockedReason: blockedReason,
  );

  /// 只清掉自己负责的意图：更晚的确认（序号更大）保持待传。
  CloudAutoUploadQueue clearPending({required int through}) {
    final stillPending = pendingSequence > through;
    return CloudAutoUploadQueue(
      pending: pending && stillPending,
      requestedAt: stillPending ? requestedAt : null,
      pendingSequence: pendingSequence,
      request: request,
      blockedReason: blockedReason,
    );
  }

  CloudAutoUploadQueue block(String reason) => CloudAutoUploadQueue(
    pending: pending,
    requestedAt: requestedAt,
    pendingSequence: pendingSequence,
    request: request,
    blockedReason: reason,
  );

  CloudAutoUploadQueue reset() => const CloudAutoUploadQueue();

  Map<String, dynamic> toJson() => {
    'pending': pending,
    'requestedAt': requestedAt?.toUtc().toIso8601String(),
    'pendingSequence': pendingSequence,
    'request': request?.toJson(),
    'blockedReason': blockedReason,
  };

  static const empty = CloudAutoUploadQueue();

  static CloudAutoUploadQueue fromJson(Object? value) {
    if (value is! Map) return empty;
    final pending = value['pending'];
    final requestedAt = value['requestedAt'];
    final pendingSequence = value['pendingSequence'];
    final blockedReason = value['blockedReason'];
    return CloudAutoUploadQueue(
      pending: pending == true,
      requestedAt: requestedAt is String
          ? DateTime.tryParse(requestedAt)
          : null,
      pendingSequence: pendingSequence is int && pendingSequence > 0
          ? pendingSequence
          : 0,
      request: CloudAutoUploadAttempt.fromJson(value['request']),
      blockedReason: blockedReason is String && blockedReason.isNotEmpty
          ? blockedReason
          : null,
    );
  }
}

abstract interface class CloudAutoUploadQueueStore {
  Future<CloudAutoUploadQueue> load(String userId);

  Future<void> save(String userId, CloudAutoUploadQueue queue);

  Future<void> clear(String userId);

  /// 仍留有队列（含冻结业务载荷）的用户，供账号清除时枚举；
  /// 这些用户可能已经没有业务表行，必须能单独发现。
  Future<List<String>> userIds();
}

class SharedPreferencesCloudAutoUploadQueueStore
    implements CloudAutoUploadQueueStore {
  const SharedPreferencesCloudAutoUploadQueueStore({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  static const _prefix = 'pacta.device.cloud_auto_upload.queue.';

  String _key(String userId) => '$_prefix$userId';

  @override
  Future<CloudAutoUploadQueue> load(String userId) async {
    final preferences = await preferencesLoader();
    await preferences.reload();
    final encoded = preferences.getString(_key(userId));
    if (encoded == null) return CloudAutoUploadQueue.empty;
    try {
      return CloudAutoUploadQueue.fromJson(jsonDecode(encoded));
    } on FormatException {
      return CloudAutoUploadQueue.empty;
    }
  }

  @override
  Future<void> save(String userId, CloudAutoUploadQueue queue) async {
    final preferences = await preferencesLoader();
    if (!queue.hasWork && queue.blockedReason == null) {
      await clear(userId);
      return;
    }
    final saved = await preferences.setString(
      _key(userId),
      jsonEncode(queue.toJson()),
    );
    if (!saved) throw StateError('待上传请求未保存，请重试。');
  }

  @override
  Future<void> clear(String userId) async {
    final preferences = await preferencesLoader();
    final removed = await preferences.remove(_key(userId));
    if (!removed) throw StateError('待上传请求未清除，请重试。');
  }

  @override
  Future<List<String>> userIds() async {
    final preferences = await preferencesLoader();
    await preferences.reload();
    return [
      for (final key in preferences.getKeys())
        if (key.startsWith(_prefix) && key.length > _prefix.length)
          key.substring(_prefix.length),
    ];
  }
}

/// 测试用：与真实存储同样的读写语义，便于注入失败。
class InMemoryCloudAutoUploadQueueStore implements CloudAutoUploadQueueStore {
  final Map<String, CloudAutoUploadQueue> queues = {};
  Object? failure;

  @override
  Future<CloudAutoUploadQueue> load(String userId) async {
    _throwIfFailing();
    return queues[userId] ?? CloudAutoUploadQueue.empty;
  }

  @override
  Future<void> save(String userId, CloudAutoUploadQueue queue) async {
    _throwIfFailing();
    queues[userId] = queue;
  }

  @override
  Future<void> clear(String userId) async {
    _throwIfFailing();
    queues.remove(userId);
  }

  @override
  Future<List<String>> userIds() async {
    _throwIfFailing();
    return queues.keys.toList();
  }

  void _throwIfFailing() {
    final error = failure;
    if (error != null) throw error;
  }
}
