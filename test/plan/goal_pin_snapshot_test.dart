import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late InMemoryCloudSnapshotRemote remote;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remote = InMemoryCloudSnapshotRemote();
  });

  test('pins and manual order survive a whole-account round trip', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    final tasksA = LocalTaskRepository(
      database: deviceA,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final deviceB = PactaDatabase(NativeDatabase.memory());
    final tasksB = LocalTaskRepository(
      database: deviceB,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    try {
      final first = await tasksA.createGoal(
        const GoalDraft(title: '甲', classification: TaskClassification.regular),
      );
      final second = await tasksA.createGoal(
        const GoalDraft(title: '乙', classification: TaskClassification.regular),
      );
      final third = await tasksA.createGoal(
        const GoalDraft(title: '丙', classification: TaskClassification.regular),
      );
      await tasksA.setGoalPinned(third.id, isPinned: true);
      await tasksA.setGoalPinned(first.id, isPinned: true);
      await tasksA.reorderPinnedGoals([first.id, third.id]);

      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final captured = await snapshotA.captureLocalState();
      expect(captured.payload['schemaVersion'], cloudSnapshotSchemaVersion);
      final saved = await snapshotA.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: captured.fingerprint,
      );

      final snapshotB = CloudSnapshotRepository(
        database: deviceB,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-b',
        deviceName: 'Tablet B',
      );
      final localB = await snapshotB.captureLocalState();
      await snapshotB.downloadCloud(
        expectedRevision: saved.revision,
        expectedFingerprint: localB.fingerprint,
      );

      final restored = await tasksB.getGoals();
      expect(restored.map((goal) => goal.id).toList(), [
        first.id,
        third.id,
        second.id,
      ]);
      expect(restored[0].isPinned, isTrue);
      expect(restored[1].isPinned, isTrue);
      expect(restored[2].isPinned, isFalse);
    } finally {
      await tasksA.dispose();
      await tasksB.dispose();
      await deviceA.close();
      await deviceB.close();
    }
  });

  test('a version 3 payload must carry every goal pin column', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    final tasksA = LocalTaskRepository(
      database: deviceA,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final deviceB = PactaDatabase(NativeDatabase.memory());
    final tasksB = LocalTaskRepository(
      database: deviceB,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    try {
      await tasksA.createGoal(
        const GoalDraft(title: '甲', classification: TaskClassification.regular),
      );
      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final captured = await snapshotA.captureLocalState();
      final payload = captured.payload;
      final tables = payload['tables'] as Map<String, dynamic>;
      for (final row in (tables['local_goals'] as List)) {
        (row as Map<String, dynamic>).remove('sort_order');
      }
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 0,
        payload: payload,
        deviceId: 'device-a',
        deviceName: 'Phone A',
        dataUpdatedAt: DateTime.utc(2026, 11, 15),
        rowCount: tables.values.cast<List<dynamic>>().fold<int>(
          0,
          (total, rows) => total + rows.length,
        ),
      );

      final snapshotB = CloudSnapshotRepository(
        database: deviceB,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-b',
        deviceName: 'Tablet B',
      );
      final localB = await snapshotB.captureLocalState();
      await expectLater(
        snapshotB.downloadCloud(
          expectedRevision: 1,
          expectedFingerprint: localB.fingerprint,
        ),
        throwsStateError,
      );
      expect(await tasksB.getGoals(), isEmpty);
    } finally {
      await tasksA.dispose();
      await tasksB.dispose();
      await deviceA.close();
      await deviceB.close();
    }
  });
}
