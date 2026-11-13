import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_recovery_point.dart';
import 'package:pacta/src/sync/cloud_snapshot_history.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late DriftCloudRecoveryPointStore recoveryPoints;

  CloudSnapshotRepository repositoryFor({
    String userId = 'user-a',
    String deviceName = 'Pixel 7（Android）',
    CloudRecoveryPointStore? store,
  }) => CloudSnapshotRepository(
    database: database,
    remote: remote,
    userId: userId,
    deviceId: 'device-a',
    deviceName: deviceName,
    recoveryPointStore: store ?? recoveryPoints,
    now: () => DateTime.utc(2026, 11, 13, 9),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    recoveryPoints = DriftCloudRecoveryPointStore(database);
  });

  tearDown(() => database.close());

  test('上传成功后历史包含最新版本，并提供时间、来源与记录数', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-a', title: 'Cloud');
    final state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );

    final history = await repository.listCloudHistory();

    expect(history, hasLength(1));
    expect(history.single.revision, 1);
    expect(history.single.deviceName, 'Pixel 7（Android）');
    expect(history.single.rowCount, 1);
    expect(history.single.uploadedAt.isUtc, isTrue);
    expect(history.single.dataUpdatedAt.isUtc, isTrue);
  });

  test('连续上传保留最近15份备份并淘汰最旧，最新份始终在列', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-a', title: 'Cloud');
    for (var revision = 0; revision < 17; revision++) {
      final state = await repository.captureLocalState();
      await repository.uploadLocal(
        expectedRevision: revision,
        expectedFingerprint: state.fingerprint,
      );
    }

    final history = await repository.listCloudHistory();

    expect(history, hasLength(cloudSnapshotHistoryLimit));
    expect(history.first.revision, 17);
    expect(history.last.revision, 3);
    expect(
      history.map((entry) => entry.revision),
      List<int>.generate(15, (index) => 17 - index),
    );
  });

  test('恢复指定旧版本替换本机数据且不写入云端', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await _addGoal(database, id: 'goal-2', title: 'Second');
    state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 1,
      expectedFingerprint: state.fingerprint,
    );
    expect(await _goalTitles(database), ['First', 'Second']);

    await repository.restoreCloudVersion(
      revision: 1,
      expectedFingerprint: (await repository.captureLocalState()).fingerprint,
    );

    expect(await _goalTitles(database), ['First']);
    expect((await remote.inspect(userId: 'user-a'))?.revision, 2);
  });

  test('恢复失败不部分替换本机数据', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'Keep');
    final state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );

    await expectLater(
      repository.restoreCloudVersion(
        revision: 9,
        expectedFingerprint: state.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await _goalTitles(database), ['Keep']);
  });

  test('恢复前保存本机恢复点，并可从恢复点找回', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await _addGoal(database, id: 'goal-2', title: 'Second');
    state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 1,
      expectedFingerprint: state.fingerprint,
    );

    await repository.restoreCloudVersion(
      revision: 1,
      expectedFingerprint: (await repository.captureLocalState()).fingerprint,
    );
    expect(await _goalTitles(database), ['First']);

    final points = await repository.listLocalRecoveryPoints();
    expect(points, hasLength(1));
    expect(points.single.reason, CloudRecoveryReason.beforeCloudRestore);
    expect(points.single.rowCount, 2);

    await repository.restoreLocalRecoveryPoint(
      pointId: points.single.id,
      expectedFingerprint: (await repository.captureLocalState()).fingerprint,
    );

    expect(await _goalTitles(database), ['First', 'Second']);
    expect(points.single.reason, CloudRecoveryReason.beforeCloudRestore);
  });

  test('恢复点保存失败时不替换本机数据', () async {
    final repository = repositoryFor(store: const _FailingRecoveryPointStore());
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await _addGoal(database, id: 'goal-2', title: 'Second');
    state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 1,
      expectedFingerprint: state.fingerprint,
    );

    await expectLater(
      repository.restoreCloudVersion(
        revision: 1,
        expectedFingerprint: state.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await _goalTitles(database), ['First', 'Second']);
  });

  test('未结束流程中禁止恢复历史版本', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await database
        .into(database.focusAppointments)
        .insert(
          FocusAppointmentsCompanion.insert(
            userId: 'user-a',
            id: 'appointment-a',
            taskId: 'task-a',
            mode: 'regular',
            durationSeconds: 1800,
            startedAt: DateTime.utc(2026, 11, 13, 8),
            endsAt: DateTime.utc(2026, 11, 13, 8, 30),
            status: 'active',
            updatedAt: DateTime.utc(2026, 11, 13, 8),
          ),
        );
    state = await repository.captureLocalState();

    await expectLater(
      repository.restoreCloudVersion(
        revision: 1,
        expectedFingerprint: state.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await _goalTitles(database), ['First']);
  });

  test('恢复点按用户隔离', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await _addGoal(database, id: 'goal-2', title: 'Second');
    state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 1,
      expectedFingerprint: state.fingerprint,
    );
    await repository.restoreCloudVersion(
      revision: 1,
      expectedFingerprint: (await repository.captureLocalState()).fingerprint,
    );

    final other = repositoryFor(userId: 'user-b');
    expect(await other.listLocalRecoveryPoints(), isEmpty);
  });
  test('同一上传请求标识重试只写入一份历史版本', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-a', title: 'Cloud');
    final state = await repository.captureLocalState();
    final first = await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
      requestId: 'request-1',
    );

    final retried = await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
      requestId: 'request-1',
    );

    expect(retried.revision, first.revision);
    expect(await repository.listCloudHistory(), hasLength(1));
    expect((await remote.inspect(userId: 'user-a'))?.revision, 1);
  });

  test('恢复取消钩子在替换前生效，本机与云端都不变', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await _addGoal(database, id: 'goal-2', title: 'Second');
    final fingerprint = (await repository.captureLocalState()).fingerprint;

    await expectLater(
      repository.restoreCloudVersion(
        revision: 1,
        expectedFingerprint: fingerprint,
        isCancelled: () => true,
      ),
      throwsA(isA<CloudRestoreCancelled>()),
    );

    expect(await _goalTitles(database), ['First', 'Second']);
    expect(await repository.listLocalRecoveryPoints(), isEmpty);
    // 只有首次上传写入云端；取消的恢复从未产生上传。
    expect((await remote.inspect(userId: 'user-a'))?.revision, 1);
  });

  test('取消发生在恢复点保存之后时仍不替换本机数据', () async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    var state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await _addGoal(database, id: 'goal-2', title: 'Second');
    state = await repository.captureLocalState();
    final fingerprint = state.fingerprint;
    var checks = 0;

    await expectLater(
      repository.restoreCloudVersion(
        revision: 1,
        expectedFingerprint: fingerprint,
        isCancelled: () => ++checks > 2,
      ),
      throwsA(isA<CloudRestoreCancelled>()),
    );

    expect(await _goalTitles(database), ['First', 'Second']);
    expect(await repository.listLocalRecoveryPoints(), hasLength(1));
  });
}

class _FailingRecoveryPointStore implements CloudRecoveryPointStore {
  const _FailingRecoveryPointStore();

  @override
  Future<void> save(CloudRecoveryPoint point) async =>
      throw StateError('恢复点保存失败');

  @override
  Future<List<CloudRecoveryPointSummary>> list(String userId) async => const [];

  @override
  Future<CloudRecoveryPoint?> load(String userId, String pointId) async => null;
}

Future<void> _addGoal(
  PactaDatabase database, {
  required String id,
  required String title,
}) async {
  final now = DateTime.utc(2026, 11, 13);
  await database
      .into(database.localGoals)
      .insertOnConflictUpdate(
        LocalGoalsCompanion.insert(
          userId: 'user-a',
          id: id,
          title: title,
          classification: 'regular',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<List<String>> _goalTitles(PactaDatabase database) async {
  final rows = await (database.select(
    database.localGoals,
  )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  return rows.map((row) => row.title).toList();
}
