import 'dart:convert';

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

  test(
    'a complete version 2 payload gains unpinned defaults on read',
    () async {
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
        final goal = await tasksA.createGoal(
          const GoalDraft(
            title: '甲',
            classification: TaskClassification.regular,
          ),
        );
        await tasksA.createTask(goal.id, const TaskDraft(title: '旧任务'));
        await tasksA.setGoalPinned(goal.id, isPinned: true);

        final snapshotA = CloudSnapshotRepository(
          database: deviceA,
          remote: remote,
          userId: 'user-a',
          deviceId: 'device-a',
          deviceName: 'Phone A',
        );
        final captured = await snapshotA.captureLocalState();
        final version2 = _asVersion2(captured.payload);
        await remote.upload(
          userId: 'user-a',
          expectedRevision: 0,
          payload: version2,
          deviceId: 'device-a',
          deviceName: 'Phone A',
          dataUpdatedAt: DateTime.utc(2026, 11, 15),
          rowCount: (version2['tables'] as Map<String, dynamic>).values
              .cast<List<dynamic>>()
              .fold<int>(0, (total, rows) => total + rows.length),
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
          expectedRevision: 1,
          expectedFingerprint: localB.fingerprint,
        );

        final restored = (await tasksB.getGoals()).single;
        expect(restored.title, '甲');
        expect(restored.tasks.map((task) => task.title).toList(), ['旧任务']);
        expect(restored.isPinned, isFalse);
        expect(restored.sortOrder, isNull);
      } finally {
        await tasksA.dispose();
        await tasksB.dispose();
        await deviceA.close();
        await deviceB.close();
      }
    },
  );

  test(
    'a complete version 2 payload keeps the goal pins it already carries',
    () async {
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
          const GoalDraft(
            title: '甲',
            classification: TaskClassification.regular,
          ),
        );
        await tasksA.createGoal(
          const GoalDraft(
            title: '乙',
            classification: TaskClassification.regular,
          ),
        );
        await tasksA.setGoalPinned(first.id, isPinned: true);

        final snapshotA = CloudSnapshotRepository(
          database: deviceA,
          remote: remote,
          userId: 'user-a',
          deviceId: 'device-a',
          deviceName: 'Phone A',
        );
        final captured = await snapshotA.captureLocalState();
        final version2 = _declaredVersion2(captured.payload);
        await remote.upload(
          userId: 'user-a',
          expectedRevision: 0,
          payload: version2,
          deviceId: 'device-a',
          deviceName: 'Phone A',
          dataUpdatedAt: DateTime.utc(2026, 11, 15),
          rowCount: (version2['tables'] as Map<String, dynamic>).values
              .cast<List<dynamic>>()
              .fold<int>(0, (total, rows) => total + rows.length),
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
          expectedRevision: 1,
          expectedFingerprint: localB.fingerprint,
        );

        // 完整核心 2 里已经有的置顶值属于已知列：只补缺列，不改已知值。
        final restored = await tasksB.getGoals();
        expect(restored.first.title, '甲');
        expect(restored.first.isPinned, isTrue);
        expect(restored.first.sortOrder, 0);
        expect(restored.last.title, '乙');
        expect(restored.last.isPinned, isFalse);
      } finally {
        await tasksA.dispose();
        await tasksB.dispose();
        await deviceA.close();
        await deviceB.close();
      }
    },
  );

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

/// 只改版本声明，保留完整的核心 2 载荷（含它已经携带的置顶列）。
Map<String, dynamic> _declaredVersion2(Map<String, dynamic> payload) {
  final copy = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
  copy['schemaVersion'] = 2;
  return copy;
}

Map<String, dynamic> _asVersion2(Map<String, dynamic> payload) {
  final copy = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
  copy['schemaVersion'] = 2;
  final tables = copy['tables'] as Map<String, dynamic>;
  for (final row in (tables['local_goals'] as List)) {
    (row as Map<String, dynamic>)
      ..remove('is_pinned')
      ..remove('sort_order');
  }
  return copy;
}
