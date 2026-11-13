import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_recovery_point.dart';
import 'package:pacta/src/sync/cloud_snapshot_history.dart';
import 'package:pacta/src/sync/cloud_snapshot_history_page.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_card.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;

  CloudSnapshotRepository repositoryFor({
    String deviceName = 'Pixel 7（Android）',
    CloudRecoveryPointStore? recoveryPointStore,
  }) => CloudSnapshotRepository(
    database: database,
    remote: remote,
    userId: 'user-a',
    deviceId: 'device-a',
    deviceName: deviceName,
    recoveryPointStore: recoveryPointStore,
    now: () => DateTime.utc(2026, 11, 13, 9, 30),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
  });

  tearDown(() => database.close());

  testWidgets('历史列表显示时间、来源与记录数，并分开本机恢复点', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(home: CloudSnapshotHistoryPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('云端备份'), findsOneWidget);
    expect(find.text('本机恢复点'), findsOneWidget);
    expect(find.textContaining('最近 15 份成功上传'), findsOneWidget);
    // 最新在前：第二份两份记录，第一份一条记录。
    expect(find.textContaining('Pixel 7（Android） · 2 条记录'), findsOneWidget);
    expect(find.textContaining('Pixel 7（Android） · 1 条记录'), findsOneWidget);
    expect(find.text('恢复'), findsNWidgets(2));
    // 尚未恢复过，因此没有本机恢复点。
    expect(find.text('还没有本机恢复点；第一次恢复时会自动创建。'), findsOneWidget);
  });

  testWidgets('取消恢复不替换本机数据，也不产生恢复点', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(home: CloudSnapshotHistoryPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();
    expect(find.text('恢复到该云端备份？'), findsOneWidget);
    expect(find.textContaining('本次恢复不会上传或覆盖云端。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await _goalTitles(database), ['First', 'Second']);
    expect(await repository.listLocalRecoveryPoints(), isEmpty);
    expect((await remote.inspect(userId: 'user-a'))?.revision, 2);
  });

  testWidgets('确认后恢复旧版本并保留可找回的本机恢复点', (tester) async {
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
    var refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSnapshotHistoryPage(
          repository: repository,
          onRestored: () async {
            refreshed = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();

    expect(await _goalTitles(database), ['First']);
    expect(refreshed, isTrue);
    expect((await remote.inspect(userId: 'user-a'))?.revision, 2);
    expect(find.textContaining('云端恢复前保存 · 2 条记录'), findsOneWidget);
    expect(find.text('找回'), findsOneWidget);
  });

  testWidgets('同步卡片提供历史备份入口并打开历史页', (tester) async {
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    final state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: repository,
            onDownloaded: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    // 来源只显示名称与平台，不显示设备标识。
    expect(find.textContaining('设备标识'), findsNothing);
    await tester.tap(find.text('历史备份'));
    await tester.pumpAndSettle();
    expect(find.text('云端备份'), findsOneWidget);
    expect(find.textContaining('Pixel 7（Android） · 1 条记录'), findsOneWidget);
  });

  testWidgets('云历史离线时仍显示并找回本机恢复点，云错误单独呈现', (tester) async {
    final failing = _FlakyHistoryRemote();
    remote = failing;
    final repository = repositoryFor();
    await _addGoal(database, id: 'goal-1', title: 'First');
    final earlier = await repository.captureLocalState();
    await _addGoal(database, id: 'goal-2', title: 'Second');
    final point = CloudRecoveryPoint(
      id: 'point-1',
      userId: 'user-a',
      createdAt: DateTime.utc(2026, 11, 13, 8),
      reason: CloudRecoveryReason.beforeCloudRestore,
      dataUpdatedAt: earlier.dataUpdatedAt,
      rowCount: earlier.rowCount,
      payload: earlier.payload,
    );
    await DriftCloudRecoveryPointStore(database).save(point);
    failing.failHistory = true;
    var cancelled = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSnapshotHistoryPage(
          repository: repository,
          onCancelPendingUpload: () async {
            cancelled++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('云端备份读取失败，请检查网络与登录状态。'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-cloud-history')), findsOneWidget);
    expect(find.textContaining('云端恢复前保存 · 1 条记录'), findsOneWidget);
    await tester.tap(find.text('找回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认找回'));
    await tester.pumpAndSettle();

    expect(cancelled, 1);
    expect(await _goalTitles(database), ['First']);
    expect(find.text('云端备份读取失败，请检查网络与登录状态。'), findsOneWidget);
  });

  testWidgets('本机恢复点读取失败不影响云端列表，并可单独重试', (tester) async {
    final repository = repositoryFor(
      recoveryPointStore: _FlakyRecoveryPointStore(database),
    );
    await _addGoal(database, id: 'goal-1', title: 'First');
    final state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );

    await tester.pumpWidget(
      MaterialApp(home: CloudSnapshotHistoryPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pixel 7（Android） · 1 条记录'), findsOneWidget);
    expect(find.text('本机恢复点读取失败，请重试。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-local-points')));
    await tester.pumpAndSettle();
    expect(find.text('还没有本机恢复点；第一次恢复时会自动创建。'), findsOneWidget);
    expect(find.text('本机恢复点读取失败，请重试。'), findsNothing);
  });

  testWidgets('云端恢复前取消待上传请求', (tester) async {
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
    var cancelled = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSnapshotHistoryPage(
          repository: repository,
          onCancelPendingUpload: () async {
            cancelled++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();

    expect(cancelled, 1);
    expect(await _goalTitles(database), ['First']);
  });
}

class _FlakyHistoryRemote extends InMemoryCloudSnapshotRemote {
  bool failHistory = false;

  @override
  Future<List<CloudSnapshotHistoryEntry>> history({
    required String userId,
  }) async {
    if (failHistory) throw StateError('offline');
    return super.history(userId: userId);
  }
}

class _FlakyRecoveryPointStore implements CloudRecoveryPointStore {
  _FlakyRecoveryPointStore(this.database);

  final PactaDatabase database;
  var failed = false;

  CloudRecoveryPointStore get _delegate =>
      DriftCloudRecoveryPointStore(database);

  @override
  Future<List<CloudRecoveryPointSummary>> list(String userId) async {
    if (!failed) {
      failed = true;
      throw StateError('disk unavailable');
    }
    return _delegate.list(userId);
  }

  @override
  Future<CloudRecoveryPoint?> load(String userId, String pointId) =>
      _delegate.load(userId, pointId);

  @override
  Future<void> save(CloudRecoveryPoint point) => _delegate.save(point);
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
