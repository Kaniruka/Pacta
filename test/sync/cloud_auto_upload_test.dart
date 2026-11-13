import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_auto_upload.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_version_check.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'auto-upload-user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late PactaDatabase database;
  late _TrackingRemote remote;
  late CloudSnapshotRepository repository;
  late InMemoryCloudAutoUploadQueueStore store;
  var requestCounter = 0;

  Future<void> seedGoal(String title) async {
    final tasks = LocalTaskRepository(
      database: database,
      userId: _userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    await tasks.createGoal(
      GoalDraft(title: title, classification: TaskClassification.regular),
    );
    await tasks.dispose();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requestCounter = 0;
    database = PactaDatabase(NativeDatabase.memory());
    remote = _TrackingRemote();
    store = InMemoryCloudAutoUploadQueueStore();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
    );
    await seedGoal('默认目标');
  });

  tearDown(() async {
    await database.close();
  });

  CloudAutoUploadCoordinator coordinatorFor({
    bool Function()? accessible,
    CloudVersionCheck? versionCheck,
  }) => CloudAutoUploadCoordinator(
    userId: _userId,
    repository: repository,
    preference: const CloudAutoUploadPreference(),
    queueStore: store,
    canAccess: () async => accessible?.call() ?? true,
    isAccessible: () async => accessible?.call() ?? true,
    versionCheck: versionCheck,
    requestIdFactory: () => 'request-${++requestCounter}',
  );

  Future<void> publishOtherDevice(int expectedRevision) => remote.upload(
    userId: _userId,
    expectedRevision: expectedRevision,
    payload: const {'schemaVersion': 1, 'userId': _userId, 'tables': {}},
    deviceId: 'other',
    deviceName: '另一台设备（Windows）',
    dataUpdatedAt: DateTime.utc(2026, 11, 13),
    rowCount: 0,
  );

  test('开关默认关闭：确认只记录本机状态，不排队也不上传', () async {
    final coordinator = coordinatorFor();
    await coordinator.enqueue();
    expect(coordinator.enabled, isFalse);
    expect(remote.uploadCalls, 0);
    expect((await store.load(_userId)).hasWork, isFalse);
  });

  test('开启后单次确认上传一次，内容未变时不重复生成备份', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    expect(coordinator.enabled, isTrue);

    await coordinator.enqueue();
    expect(remote.uploadCalls, 1);
    expect(remote.requestIds, ['request-1']);
    final saved = await repository.loadSyncResult();
    expect(saved!.cloudRevision, 1);
    expect(
      saved.localFingerprint,
      (await repository.captureLocalState()).fingerprint,
    );
    expect((await store.load(_userId)).hasWork, isFalse);
    expect(await remote.history(userId: _userId), hasLength(1));

    await coordinator.enqueue();
    expect(remote.uploadCalls, 1);
    expect(await remote.history(userId: _userId), hasLength(1));
  });

  test('上传途中的再次确认合并到下一轮，不重复写入相同备份', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    remote.uploadGate = Completer<void>();
    final first = coordinator.enqueue();
    await remote.uploadStarted.future;
    await coordinator.enqueue();
    await coordinator.enqueue();
    remote.uploadGate!.complete();
    await first;

    expect(remote.uploadCalls, 1);
    expect(await remote.history(userId: _userId), hasLength(1));
    expect((await store.load(_userId)).hasWork, isFalse);
  });

  test('上传途中本机变化时，上一份备份不会把新内容标成已同步', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    remote.uploadGate = Completer<void>();
    final first = coordinator.enqueue();
    await remote.uploadStarted.future;
    await seedGoal('上传途中确认');
    remote.uploadGate!.complete();
    await first;

    final saved = await repository.loadSyncResult();
    final current = await repository.captureLocalState();
    expect(remote.uploadCalls, 1);
    expect(saved!.localFingerprint, isNot(current.fingerprint));
    expect((await store.load(_userId)).hasWork, isFalse);
  });

  test('未处理的云版本停止自动覆盖，排队意图保留', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    await coordinator.enqueue();
    await publishOtherDevice(1);
    final uploadsBefore = remote.uploadCalls;

    await coordinator.enqueue();
    expect(remote.uploadCalls, uploadsBefore);
    expect(coordinator.blockedReason, cloudAutoUploadUnhandledCloudReason);
    final queue = await store.load(_userId);
    expect(queue.pending, isTrue);
    expect(queue.blockedReason, cloudAutoUploadUnhandledCloudReason);
  });

  test('首次遇到既有云快照需要用户处理，忽略提示不等于授权覆盖', () async {
    await publishOtherDevice(0);
    final check = CloudVersionCheck(
      repository: repository,
      now: () => DateTime.utc(2026, 11, 13, 12),
      canAccess: () async => true,
      isAccessible: () async => true,
    );
    final coordinator = coordinatorFor(versionCheck: check);
    await coordinator.setEnabled(true);
    await check.check(force: true);
    expect(check.hasPendingVersion, isTrue);
    await check.ignore(check.metadata!);

    await coordinator.enqueue();
    expect(remote.uploadCalls, 1);
    expect(coordinator.blockedReason, cloudAutoUploadUnhandledCloudReason);
    expect((await store.load(_userId)).pending, isTrue);
    coordinator.dispose();
    check.dispose();
  });

  test('离线失败后重试原身份，并为新的确认生成新请求', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    remote.failUploads = true;
    await coordinator.enqueue();
    final failed = await store.load(_userId);
    expect(failed.request!.requestId, 'request-1');
    expect(failed.request!.attempted, isTrue);

    await seedGoal('离线期间确认');
    remote.failUploads = false;
    await coordinator.enqueue();

    expect(remote.requestIds, ['request-1', 'request-1', 'request-2']);
    expect(await remote.history(userId: _userId), hasLength(2));
    final saved = await repository.loadSyncResult();
    expect(saved!.cloudRevision, 2);
    expect(
      saved.localFingerprint,
      (await repository.captureLocalState()).fingerprint,
    );
    expect((await store.load(_userId)).hasWork, isFalse);
  });

  test('服务端已接收但响应丢失：重试同一身份只保留一份备份', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    remote.loseNextResponse = true;
    await coordinator.enqueue();
    expect(await remote.history(userId: _userId), hasLength(1));
    expect((await store.load(_userId)).request, isNotNull);

    await coordinator.trigger();
    expect(await remote.history(userId: _userId), hasLength(1));
    expect((await repository.loadSyncResult())!.cloudRevision, 1);
    expect((await store.load(_userId)).hasWork, isFalse);
  });

  test('同一请求身份换了内容会停止自动上传，不重写成新请求', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    await coordinator.enqueue();
    await seedGoal('请求之后的新内容');

    final current = await repository.captureLocalState();
    await store.save(
      _userId,
      CloudAutoUploadQueue(
        pending: true,
        requestedAt: DateTime.utc(2026, 11, 13, 13),
        request: CloudAutoUploadAttempt(
          requestId: 'request-1',
          fingerprint: current.fingerprint,
          expectedRevision: 1,
          startedAt: DateTime.utc(2026, 11, 13, 13),
          attempted: true,
          payload: current.payload,
          rowCount: current.rowCount,
          dataUpdatedAt: current.dataUpdatedAt,
        ),
      ),
    );
    await coordinator.trigger();

    expect(coordinator.blockedReason, '该上传请求已用于不同的数据内容，请重新检查后再上传。');
    final queue = await store.load(_userId);
    expect(queue.request!.requestId, 'request-1');
    expect(await remote.history(userId: _userId), hasLength(1));
    final uploadsBefore = remote.uploadCalls;
    await coordinator.enqueue();
    expect(remote.uploadCalls, uploadsBefore);
  });

  test('请求已处理但备份被淘汰时停止并提示重新查看', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    final captured = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: captured.fingerprint,
      requestId: 'request-1',
      captured: captured,
    );
    for (var index = 0; index < 15; index++) {
      final state = await repository.captureLocalState();
      await repository.uploadLocal(
        expectedRevision: index + 1,
        expectedFingerprint: state.fingerprint,
        requestId: 'filler-$index',
        captured: state,
      );
    }
    await store.save(
      _userId,
      CloudAutoUploadQueue(
        pending: true,
        requestedAt: DateTime.utc(2026, 11, 13, 13),
        request: CloudAutoUploadAttempt(
          requestId: 'request-1',
          fingerprint: captured.fingerprint,
          expectedRevision: 0,
          startedAt: DateTime.utc(2026, 11, 13, 13),
          attempted: true,
          payload: captured.payload,
          rowCount: captured.rowCount,
          dataUpdatedAt: captured.dataUpdatedAt,
        ),
      ),
    );
    await coordinator.trigger();
    expect(coordinator.blockedReason, contains('不在最近 15 份内'));
    expect((await store.load(_userId)).request!.requestId, 'request-1');
  });

  test('关闭开关取消排队与在途请求，之后确认不再排队', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    remote.uploadGate = Completer<void>();
    final first = coordinator.enqueue();
    await remote.uploadStarted.future;
    await coordinator.setEnabled(false);
    remote.uploadGate!.complete();
    await first;

    expect((await store.load(_userId)).hasWork, isFalse);
    expect(coordinator.blockedReason, isNull);
    await coordinator.enqueue();
    expect((await store.load(_userId)).hasWork, isFalse);
    expect(remote.uploadCalls, 1);
  });

  test('停用或不可访问时不上传，恢复后可重试最新本机快照', () async {
    var accessible = false;
    final coordinator = coordinatorFor(accessible: () => accessible);
    await coordinator.setEnabled(true);
    await coordinator.enqueue();
    expect(remote.uploadCalls, 0);
    expect((await store.load(_userId)).pending, isTrue);

    await seedGoal('停用期间确认');
    accessible = true;
    await coordinator.trigger();
    expect(remote.uploadCalls, 1);
    final payload = (await remote.download(userId: _userId)).payload!;
    expect(payload['tables']['local_goals'], hasLength(2));
  });

  test('恢复旧云版本后不因来源仍是本设备而把最新云端当成已处理', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    await coordinator.enqueue();
    await seedGoal('第二个云端版本');
    await coordinator.enqueue();
    final uploadsBefore = remote.uploadCalls;
    expect(await remote.history(userId: _userId), hasLength(2));

    final beforeRestore = await repository.captureLocalState();
    await repository.restoreCloudVersion(
      revision: 1,
      expectedFingerprint: beforeRestore.fingerprint,
    );
    expect((await repository.loadSyncResult())!.cloudRevision, 1);
    final latest = await remote.inspect(userId: _userId);
    // 最新云快照确实是本设备写的，但那不构成“本机已处理最新版本”。
    expect(latest!.deviceId, 'device-a');
    expect(latest.revision, 2);

    await seedGoal('恢复之后的今日确认');
    await coordinator.enqueue();
    expect(remote.uploadCalls, uploadsBefore);
    expect(coordinator.blockedReason, cloudAutoUploadUnhandledCloudReason);
    expect((await store.load(_userId)).pending, isTrue);
  });

  test('找回本机恢复点后不沿用旧基线自动覆盖最新云端', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    await coordinator.enqueue();
    await seedGoal('恢复点里的本机内容');

    // 用云端第 1 版恢复一次，制造包含“恢复点里的本机内容”的本机恢复点。
    final beforeCloudRestore = await repository.captureLocalState();
    await repository.restoreCloudVersion(
      revision: 1,
      expectedFingerprint: beforeCloudRestore.fingerprint,
    );
    expect((await repository.loadSyncResult())!.cloudRevision, 1);
    final point = (await repository.listLocalRecoveryPoints()).first;

    final beforePointRestore = await repository.captureLocalState();
    await repository.restoreLocalRecoveryPoint(
      pointId: point.id,
      expectedFingerprint: beforePointRestore.fingerprint,
    );
    // 找回的是更早的本机内容，原基线不再能证明与云端一致。
    expect(await repository.loadSyncResult(), isNull);

    await seedGoal('找回之后的今日确认');
    final uploadsBefore = remote.uploadCalls;
    await coordinator.enqueue();
    expect(remote.uploadCalls, uploadsBefore);
    expect(coordinator.blockedReason, cloudAutoUploadUnhandledCloudReason);
  });

  test('恢复备份前取消队列后不再自动上传历史内容', () async {
    final coordinator = coordinatorFor();
    await coordinator.setEnabled(true);
    await coordinator.enqueue();
    expect(remote.uploadCalls, 1);
    await seedGoal('恢复前确认');

    await coordinator.cancelPending();
    await coordinator.trigger();
    expect(remote.uploadCalls, 1);
    expect((await store.load(_userId)).hasWork, isFalse);
  });
}

class _TrackingRemote extends InMemoryCloudSnapshotRemote {
  final List<String?> requestIds = [];
  int uploadCalls = 0;
  bool failUploads = false;
  bool loseNextResponse = false;
  Completer<void>? uploadGate;
  final Completer<void> uploadStarted = Completer<void>();

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
    uploadCalls++;
    requestIds.add(requestId);
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    final gate = uploadGate;
    if (gate != null) await gate.future;
    if (failUploads) throw StateError('测试网络不可用');
    if (loseNextResponse) {
      loseNextResponse = false;
      await super.upload(
        userId: userId,
        expectedRevision: expectedRevision,
        payload: payload,
        deviceId: deviceId,
        deviceName: deviceName,
        dataUpdatedAt: dataUpdatedAt,
        rowCount: rowCount,
        deviceManufacturer: deviceManufacturer,
        deviceModel: deviceModel,
        requestId: requestId,
      );
      throw StateError('响应丢失');
    }
    return super.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt,
      rowCount: rowCount,
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      requestId: requestId,
    );
  }
}
