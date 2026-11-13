import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'cloud_auto_upload_preference.dart';
import 'cloud_auto_upload_queue.dart';
import 'cloud_snapshot_repository.dart';
import 'cloud_version_check.dart';

/// 云端有本机尚未处理的版本时停止自动覆盖的原因文案。
const String cloudAutoUploadUnhandledCloudReason =
    '云端有本机尚未处理的版本，已停止自动覆盖；请在云同步中核对后再继续。';

/// 今日确认后的整份云上传协调器。
///
/// 职责边界：
/// - 只在开关开启、用户仍登录且可访问、云端没有未处理版本时上传；
/// - 排队意图只合并成一条，执行时才捕获最新本机快照（不排队陈旧副本）；
/// - 已发出但结果未知的请求保留身份与冻结载荷，重试先确认旧应答；
/// - 关闭开关、切换账号或恢复备份会取消旧请求；不做自动下载。
class CloudAutoUploadCoordinator extends ChangeNotifier {
  CloudAutoUploadCoordinator({
    required this.userId,
    required this.repository,
    required this.preference,
    required this.queueStore,
    required this.canAccess,
    required this.isAccessible,
    this.versionCheck,
    this.now = DateTime.now,
    String Function()? requestIdFactory,
  }) : _requestIdFactory = requestIdFactory ?? (() => const Uuid().v4());

  final String userId;
  final CloudSnapshotRepository repository;
  final CloudAutoUploadPreference preference;
  final CloudAutoUploadQueueStore queueStore;

  /// 认证与生命周期可写检查：切换账号或停用后不得传输。
  final Future<bool> Function() canAccess;

  /// 已缓存的访问状态；离线时不会误判为可上传。
  final Future<bool> Function() isAccessible;
  final CloudVersionCheck? versionCheck;
  final DateTime Function() now;
  final String Function() _requestIdFactory;

  bool _enabled = false;
  bool _loaded = false;
  bool _busy = false;
  bool _disposed = false;
  bool _rerun = false;
  int _generation = 0;
  CloudAutoUploadQueue _queue = CloudAutoUploadQueue.empty;
  String? _blockedReason;
  Future<void> _mutationLock = Future<void>.value();

  bool get enabled => _enabled;
  bool get busy => _busy;
  bool get hasPendingWork => _queue.hasWork;
  DateTime? get pendingSince => _queue.pending ? _queue.requestedAt : null;
  String? get blockedReason => _blockedReason ?? _queue.blockedReason;

  /// 读取本机开关与队列；可重复调用，用于界面刷新。
  Future<void> load() async {
    _enabled = await preference.load(userId);
    _queue = await queueStore.load(userId);
    _blockedReason = _queue.blockedReason;
    _loaded = true;
    _notify();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  /// 开关按本机用户保存；关闭即取消待上传请求，如实控制传输。
  Future<void> setEnabled(bool value) async {
    await _ensureLoaded();
    if (_disposed) return;
    _enabled = value;
    await preference.save(userId, value);
    if (_disposed) return;
    if (!value) {
      await cancelPending();
      return;
    }
    _notify();
    await trigger();
  }

  /// 今日确认成功后调用；多次调用只合并成一条待传意图。
  Future<void> enqueue() async {
    await _ensureLoaded();
    if (_disposed || !_enabled) return;
    await _mutateQueue((queue) => queue.recordIntent(now().toUtc()));
    await trigger();
  }

  /// 取消旧请求：关闭开关、恢复备份、手动同步或账号切换时调用。
  Future<void> cancelPending() async {
    _generation++;
    _rerun = false;
    _blockedReason = null;
    await _mutateQueue((queue) => queue.reset());
    _notify();
  }

  /// 网络恢复、回到前台、登录或生命周期恢复后安全重试。
  Future<void> trigger() async {
    if (_disposed) return;
    await _ensureLoaded();
    if (_disposed || !_enabled) return;
    if (_busy) {
      _rerun = true;
      return;
    }
    _busy = true;
    final generation = _generation;
    _notify();
    try {
      var passes = 0;
      do {
        _rerun = false;
        await _drain(generation);
      } while (_rerun && _active(generation) && ++passes < 8);
    } catch (_) {
      // 意外错误不打断本机使用；下次触发继续。
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> _drain(int generation) async {
    var queue = await _readQueue();
    if (!queue.hasWork) return;
    if (queue.blockedReason != null) return;
    if (!await _accessAllowed(generation)) return;

    final attempt = queue.request;
    if (attempt != null) {
      if (!await _resolveAttempt(attempt, generation)) return;
      if (!_active(generation)) return;
      queue = await _readQueue();
    }
    if (!queue.pending) return;
    if (queue.blockedReason != null) return;
    await _uploadLatest(generation);
  }

  /// 先确认已发出请求的原始结果，再考虑新的待传意图。
  Future<bool> _resolveAttempt(
    CloudAutoUploadAttempt attempt,
    int generation,
  ) async {
    // 从未发出的请求没有服务端身份，直接按最新本机快照重新生成。
    if (!attempt.attempted || !_isReproducible(attempt)) {
      await _mutateQueue((queue) => queue.clearRequest());
      return true;
    }
    try {
      final saved = await repository.uploadLocal(
        expectedRevision: attempt.expectedRevision,
        expectedFingerprint: attempt.fingerprint,
        requestId: attempt.requestId,
        captured: _stateOf(attempt),
      );
      if (!_active(generation)) return false;
      await _finish(saved);
      return true;
    } on CloudUploadRequestConflict catch (error) {
      await _block(error.message);
      return false;
    } on CloudUploadRequestEvicted catch (error) {
      await _block(error.message);
      return false;
    } on CloudUploadRevisionChanged {
      // 服务端台账没有该请求，说明它没有被写入；云端已被其他设备推进。
      await _mutateQueue((queue) => queue.clearRequest());
      await _stopForUnhandledCloud();
      return false;
    } catch (_) {
      // 离线、超时或登录状态变化：保留身份，下次继续。
      return false;
    }
  }

  Future<void> _uploadLatest(int generation) async {
    final cloud = await repository.inspectCloud();
    if (!_active(generation)) return;
    final result = await repository.loadSyncResult();
    final cloudRevision = cloud?.revision ?? 0;
    if (cloud != null && result?.cloudRevision != cloud.revision) {
      await _stopForUnhandledCloud();
      return;
    }
    final snapshot = await repository.captureLocalState();
    if (!_active(generation)) return;
    if (result != null &&
        result.cloudRevision == cloudRevision &&
        result.localFingerprint == snapshot.fingerprint) {
      // 本机内容已经是上次成功同步的那一份，重复上传只会多出一份相同备份。
      await _mutateQueue((queue) => queue.clearPending());
      return;
    }
    final attempt = CloudAutoUploadAttempt(
      requestId: _requestIdFactory(),
      fingerprint: snapshot.fingerprint,
      expectedRevision: cloudRevision,
      startedAt: now().toUtc(),
      attempted: true,
      payload: snapshot.payload,
      rowCount: snapshot.rowCount,
      dataUpdatedAt: snapshot.dataUpdatedAt,
    );
    // 先落盘请求身份与冻结载荷，再发送：响应丢失后仍能重发同一请求。
    await _mutateQueue((queue) => queue.startRequest(attempt));
    if (!_active(generation)) return;
    try {
      final saved = await repository.uploadLocal(
        expectedRevision: attempt.expectedRevision,
        expectedFingerprint: attempt.fingerprint,
        requestId: attempt.requestId,
        captured: _stateOf(attempt),
      );
      if (!_active(generation)) return;
      await _finish(saved);
    } on CloudUploadRequestConflict catch (error) {
      await _block(error.message);
    } on CloudUploadRequestEvicted catch (error) {
      await _block(error.message);
    } on CloudUploadRevisionChanged {
      await _mutateQueue((queue) => queue.clearRequest());
      await _stopForUnhandledCloud();
    } catch (_) {
      // 失败保留请求与意图，联网或恢复访问后重试。
    }
  }

  Future<void> _finish(CloudSnapshotMetadata saved) async {
    await _mutateQueue((queue) => queue.clearRequest());
    _blockedReason = null;
    // 刚写入的版本就是最新，不必再提示自己的版本。
    versionCheck?.handled();
    _notify();
  }

  Future<void> _stopForUnhandledCloud() async {
    await _block(cloudAutoUploadUnhandledCloudReason);
    final check = versionCheck;
    if (check != null && !check.checking) {
      unawaited(check.check(force: true));
    }
  }

  Future<void> _block(String reason) async {
    await _mutateQueue((queue) => queue.block(reason));
    _blockedReason = reason;
    _notify();
  }

  Future<bool> _accessAllowed(int generation) async {
    if (!_active(generation)) return false;
    try {
      if (!await canAccess()) return false;
      if (!_active(generation)) return false;
      return await isAccessible();
    } catch (_) {
      return false;
    }
  }

  bool _active(int generation) => !_disposed && generation == _generation;

  bool _isReproducible(CloudAutoUploadAttempt attempt) =>
      repository.fingerprintOfPayload(attempt.payload) == attempt.fingerprint;

  CloudSnapshotLocalState _stateOf(CloudAutoUploadAttempt attempt) =>
      CloudSnapshotLocalState(
        fingerprint: attempt.fingerprint,
        payload: attempt.payload,
        rowCount: attempt.rowCount,
        dataUpdatedAt: attempt.dataUpdatedAt,
        hasUnfinishedFlow: false,
      );

  Future<CloudAutoUploadQueue> _readQueue() async {
    _queue = await queueStore.load(userId);
    _blockedReason = _queue.blockedReason;
    return _queue;
  }

  /// 队列的读改写串行化：并发意图不会覆盖已发出的请求身份。
  Future<void> _mutateQueue(
    CloudAutoUploadQueue Function(CloudAutoUploadQueue) transform,
  ) {
    final run = _mutationLock.then((_) async {
      final current = await queueStore.load(userId);
      final next = transform(current);
      await queueStore.save(userId, next);
      _queue = next;
      _blockedReason = next.blockedReason;
    });
    _mutationLock = run.catchError((Object _) {});
    return run;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
