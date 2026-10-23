import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late CloudSnapshotRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    var successfulClockReads = 0;
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
      now: () => DateTime.utc(
        2026,
        10,
        23,
      ).add(Duration(minutes: successfulClockReads++)),
    );
  });

  tearDown(() => database.close());

  test('successful upload persists a user-isolated local baseline', () async {
    final before = await repository.captureLocalState();
    expect(await repository.loadSyncResult(), isNull);
    await repository.inspectCloud();
    expect(await repository.loadSyncResult(), isNull);
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: before.fingerprint,
    );
    final reopened = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
    final result = (await reopened.loadSyncResult())!;
    expect(result.localFingerprint, before.fingerprint);
    expect(result.cloudRevision, 1);
    expect(result.succeededAt, DateTime.utc(2026, 10, 23));
    final other = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-b',
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
    expect(await other.loadSyncResult(), isNull);
    remote.available = false;
    await expectLater(
      repository.uploadLocal(
        expectedRevision: 1,
        expectedFingerprint: before.fingerprint,
      ),
      throwsStateError,
    );
    expect((await reopened.loadSyncResult())!.succeededAt, result.succeededAt);
  });

  for (final upload in [true, false]) {
    test(
      '${upload ? 'upload' : 'download'} remains completed if local history cannot be saved',
      () async {
        await _addGoal(
          database,
          userId: 'user-a',
          id: 'goal-a',
          title: 'Original',
        );
        final original = await repository.captureLocalState();
        await repository.uploadLocal(
          expectedRevision: 0,
          expectedFingerprint: original.fingerprint,
        );
        final previous = (await repository.loadSyncResult())!;
        await _addGoal(
          database,
          userId: 'user-a',
          id: 'goal-a',
          title: 'Edited',
        );
        final edited = await repository.captureLocalState();
        final failure = StateError('Device storage is unavailable');
        final failingRepository = CloudSnapshotRepository(
          database: database,
          remote: remote,
          userId: 'user-a',
          deviceId: 'device-a',
          deviceName: 'Phone A',
          syncResultStore: CloudSyncResultStore(
            preferencesLoader: () async => throw failure,
          ),
        );
        CloudSyncResultPersistenceException? outcome;
        try {
          if (upload) {
            await failingRepository.uploadLocal(
              expectedRevision: 1,
              expectedFingerprint: edited.fingerprint,
            );
          } else {
            await failingRepository.downloadCloud(
              expectedRevision: 1,
              expectedFingerprint: edited.fingerprint,
            );
          }
          fail('Expected a completed transfer with unsaved local history');
        } on CloudSyncResultPersistenceException catch (error) {
          outcome = error;
        }
        expect(outcome.cause, same(failure));
        expect(outcome.result.cloudRevision, upload ? 2 : 1);
        final expected = upload ? edited : original;
        expect(outcome.result.localFingerprint, expected.fingerprint);
        expect(
          (await repository.captureLocalState()).fingerprint,
          expected.fingerprint,
        );
        expect(
          (await remote.download(userId: 'user-a')).payload,
          expected.payload,
        );
        expect(
          (await repository.loadSyncResult())!.succeededAt,
          previous.succeededAt,
        );
        expect(
          (await repository.loadSyncResult())!.localFingerprint,
          previous.localFingerprint,
        );
      },
    );
  }

  test(
    'legacy downloads persist the restored baseline and stable cloud token',
    () async {
      await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Cloud');
      final cloud = await repository.captureLocalState();
      remote.seedLegacySnapshot(
        userId: 'user-a',
        token: '0123456789abcdef0123456789abcdef',
        state: cloud,
      );
      await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Local');
      final local = await repository.captureLocalState();
      final inspected = (await repository.inspectCloud())!;
      await repository.downloadCloud(
        expectedRevision: inspected.revision,
        expectedFingerprint: local.fingerprint,
      );
      final result = (await repository.loadSyncResult())!;
      expect(result.localFingerprint, cloud.fingerprint);
      expect(result.localFingerprint, isNot(local.fingerprint));
      expect(result.cloudRevision, inspected.revision);
      expect(result.legacyToken, '0123456789abcdef0123456789abcdef');
      await repository.inspectCloud();
      expect(
        (await repository.loadSyncResult())!.succeededAt,
        result.succeededAt,
      );
      await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Edited');
      expect(
        (await repository.captureLocalState()).fingerprint,
        isNot(result.localFingerprint),
      );
    },
  );

  test('historical success with unknown baseline stays unknown', () async {
    await const CloudSyncResultStore().save(
      'user-a',
      CloudSyncResult(
        succeededAt: DateTime.utc(2026, 10, 22),
        localFingerprint: null,
        cloudRevision: 3,
      ),
    );
    final result = (await repository.loadSyncResult())!;
    expect(result.succeededAt, DateTime.utc(2026, 10, 22));
    expect(result.localFingerprint, isNull);
    await repository.inspectCloud();
    expect((await repository.loadSyncResult())!.localFingerprint, isNull);
  });

  test(
    'signals round-trip while legacy snapshots restore empty signal texts',
    () async {
      final signals = ChainSignalsRepository(
        database: database,
        userId: 'user-a',
      );
      await signals.save(
        const ChainSignalTexts(
          appointmentTriggerSignal: '戴耳机',
          eliteFocusMarker: '坐下',
        ),
      );
      final otherSignals = ChainSignalsRepository(
        database: database,
        userId: 'user-b',
      );
      await otherSignals.save(
        const ChainSignalTexts(eliteFocusMarker: '他人的标志'),
      );
      final captured = await repository.captureLocalState();
      await repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: captured.fingerprint,
      );
      await signals.save(
        const ChainSignalTexts(appointmentTriggerSignal: '改动'),
      );
      var local = await repository.captureLocalState();
      await repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: local.fingerprint,
      );
      expect((await signals.get()).appointmentTriggerSignal, '戴耳机');
      expect((await signals.get()).eliteFocusMarker, '坐下');
      final legacy = Map<String, dynamic>.from(captured.payload);
      legacy['tables'] = Map<String, dynamic>.from(legacy['tables'] as Map)
        ..remove('chain_signals');
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 1,
        payload: legacy,
        deviceId: 'legacy',
        deviceName: 'Legacy',
        dataUpdatedAt: DateTime.utc(2026, 10, 7),
        rowCount: 0,
      );
      local = await repository.captureLocalState();
      await repository.downloadCloud(
        expectedRevision: 2,
        expectedFingerprint: local.fingerprint,
      );
      expect((await signals.get()).appointmentTriggerSignal, isEmpty);
      expect((await otherSignals.get()).eliteFocusMarker, '他人的标志');
    },
  );

  test(
    'round-trips a user snapshot and advances revision with device metadata',
    () async {
      await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Cloud');
      final beforeUpload = await repository.captureLocalState();
      final saved = await repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: beforeUpload.fingerprint,
      );

      expect(saved.revision, 1);
      expect(saved.deviceId, 'device-a');
      expect(saved.deviceName, 'Phone A');
      expect(saved.rowCount, 1);
      expect(saved.dataUpdatedAt.year, 2026);

      await _addGoal(
        database,
        userId: 'user-a',
        id: 'goal-a',
        title: 'Local edit',
      );
      await _addGoal(
        database,
        userId: 'user-b',
        id: 'goal-b',
        title: 'Other user',
      );
      final beforeDownload = await repository.captureLocalState();
      await repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: beforeDownload.fingerprint,
      );

      final own = await (database.select(
        database.localGoals,
      )..where((row) => row.userId.equals('user-a'))).getSingle();
      final other = await (database.select(
        database.localGoals,
      )..where((row) => row.userId.equals('user-b'))).getSingle();
      expect(own.title, 'Cloud');
      expect(other.title, 'Other user');
    },
  );

  test(
    'whole snapshot restores the required National Focus card name',
    () async {
      await database
          .into(database.localNationalFocusCards)
          .insert(
            LocalNationalFocusCardsCompanion.insert(
              userId: 'user-a',
              id: 'card-a',
              name: '独立名称',
              triggerCondition: '开始工作',
              action: '打开文档',
              createdAt: DateTime.utc(2026, 10, 5),
              updatedAt: DateTime.utc(2026, 10, 5),
            ),
          );
      final beforeUpload = await repository.captureLocalState();
      await repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: beforeUpload.fingerprint,
      );
      await (database.delete(
        database.localNationalFocusCards,
      )..where((row) => row.userId.equals('user-a'))).go();
      final beforeDownload = await repository.captureLocalState();
      await repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: beforeDownload.fingerprint,
      );
      final restored = await (database.select(
        database.localNationalFocusCards,
      )..where((row) => row.userId.equals('user-a'))).getSingle();
      expect(restored.name, '独立名称');
    },
  );

  test('snapshot omits local preferences, lifecycle, queue, and device calendar ids', () async {
    await database
        .into(database.localCalendarSources)
        .insert(
          LocalCalendarSourcesCompanion.insert(
            userId: 'user-a',
            sourceId: 'source-a',
            displayName: 'Personal',
            timeZoneId: 'Asia/Shanghai',
            localCalendarId: const Value('native-calendar-123'),
            isSelected: const Value(true),
            updatedAt: DateTime.utc(2026, 10, 4),
          ),
        );
    await database
        .into(database.focusSourceDevices)
        .insert(
          FocusSourceDevicesCompanion.insert(
            userId: 'user-a',
            deviceId: 'device-a',
          ),
        );
    final state = await repository.captureLocalState();
    final serialized = state.payload.toString();
    expect(serialized, isNot(contains('focus_preferences')));
    expect(serialized, isNot(contains('local_user_lifecycle_states')));
    expect(serialized, isNot(contains('task_sync_entries')));
    expect(serialized, isNot(contains('native-calendar-123')));
    expect(serialized, isNot(contains('focus_source_devices')));

    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await (database.delete(
      database.localCalendarSources,
    )..where((row) => row.userId.equals('user-a'))).go();
    final beforeDownload = await repository.captureLocalState();
    await repository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: beforeDownload.fingerprint,
    );
    final restored = await (database.select(
      database.localCalendarSources,
    )..where((row) => row.userId.equals('user-a'))).getSingle();
    expect(restored.localCalendarId, null);
    expect(restored.isSelected, isFalse);
  });

  test(
    'preserves matching calendar import mapping from this device on download',
    () async {
      await database
          .into(database.localCalendarSources)
          .insert(
            LocalCalendarSourcesCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              displayName: 'Cloud name',
              timeZoneId: 'Asia/Shanghai',
              localCalendarId: const Value('native-before-upload'),
              isSelected: const Value(true),
              updatedAt: DateTime.utc(2026, 10, 4),
            ),
          );
      final initial = await repository.captureLocalState();
      await repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: initial.fingerprint,
      );
      await database
          .into(database.localCalendarSources)
          .insertOnConflictUpdate(
            LocalCalendarSourcesCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              displayName: 'Local name',
              timeZoneId: 'Asia/Shanghai',
              localCalendarId: const Value('native-current-device'),
              isSelected: const Value(true),
              updatedAt: DateTime.utc(2026, 10, 5),
            ),
          );
      final beforeDownload = await repository.captureLocalState();
      await repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: beforeDownload.fingerprint,
      );

      final restored = await (database.select(
        database.localCalendarSources,
      )..where((row) => row.sourceId.equals('source-a'))).getSingle();
      expect(restored.displayName, 'Cloud name');
      expect(restored.localCalendarId, 'native-current-device');
      expect(restored.isSelected, isTrue);
    },
  );

  test('rejects overwrite if local data changes after confirmation', () async {
    await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Cloud');
    final cloudBasis = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: cloudBasis.fingerprint,
    );
    await _addGoal(
      database,
      userId: 'user-a',
      id: 'goal-a',
      title: 'Before prompt',
    );
    final confirmed = await repository.captureLocalState();
    await _addGoal(
      database,
      userId: 'user-a',
      id: 'goal-a',
      title: 'Changed after prompt',
    );

    await expectLater(
      repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: confirmed.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );
    final goal = await (database.select(
      database.localGoals,
    )..where((row) => row.id.equals('goal-a'))).getSingle();
    expect(goal.title, 'Changed after prompt');
  });

  test('rejects stale cloud revision before local replacement', () async {
    await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'A');
    final local = await repository.captureLocalState();
    final first = await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: local.fingerprint,
    );
    await remote.upload(
      userId: 'user-a',
      expectedRevision: first.revision,
      payload: local.payload,
      deviceId: 'device-b',
      deviceName: 'Tablet B',
      dataUpdatedAt: local.dataUpdatedAt,
      rowCount: local.rowCount,
    );
    await _addGoal(
      database,
      userId: 'user-a',
      id: 'goal-a',
      title: 'Keep this',
    );
    final confirmed = await repository.captureLocalState();

    await expectLater(
      repository.downloadCloud(
        expectedRevision: first.revision,
        expectedFingerprint: confirmed.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );
    final goal = await (database.select(
      database.localGoals,
    )..where((row) => row.id.equals('goal-a'))).getSingle();
    expect(goal.title, 'Keep this');
  });

  test(
    'rolls back deletion when SQLite rejects an insert mid-transaction',
    () async {
      await _addGoal(
        database,
        userId: 'user-a',
        id: 'goal-a',
        title: 'Keep on rollback',
      );
      await database
          .into(database.localCalendarSources)
          .insert(
            LocalCalendarSourcesCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              displayName: 'Personal',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 10, 4),
            ),
          );
      await database
          .into(database.localCalendarBlocks)
          .insert(
            LocalCalendarBlocksCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              sourceEventId: 'event-a',
              occurrenceId: 'occurrence-a',
              eventIdentity: 'event-identity-a',
              title: 'Meeting',
              startsAt: DateTime.utc(2026, 10, 4, 10),
              endsAt: DateTime.utc(2026, 10, 4, 11),
              availability: 'busy',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 10, 4),
            ),
          );
      final source = await repository.captureLocalState();
      await repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: source.fingerprint,
      );
      final successfulBeforeFailure = (await repository.loadSyncResult())!;
      await database.customStatement('''
        CREATE TRIGGER fail_calendar_snapshot_insert
        BEFORE INSERT ON local_calendar_blocks
        BEGIN
          SELECT RAISE(ABORT, 'simulated snapshot insert failure');
        END
        ''');

      await expectLater(
        repository.downloadCloud(
          expectedRevision: 1,
          expectedFingerprint: source.fingerprint,
        ),
        throwsA(anything),
      );
      final goal = await (database.select(
        database.localGoals,
      )..where((row) => row.id.equals('goal-a'))).getSingle();
      final blockAfter = await (database.select(
        database.localCalendarBlocks,
      )..where((row) => row.occurrenceId.equals('occurrence-a'))).getSingle();
      expect(
        (await repository.loadSyncResult())!.succeededAt,
        successfulBeforeFailure.succeededAt,
      );
      expect(goal.title, 'Keep on rollback');
      expect(blockAfter.endsAt.toUtc(), DateTime.utc(2026, 10, 4, 11));
    },
  );

  test(
    'allows uploading an active flow but blocks downloading over it',
    () async {
      await database
          .into(database.focusAppointments)
          .insert(
            FocusAppointmentsCompanion.insert(
              userId: 'user-a',
              id: 'appointment-a',
              taskId: 'task-a',
              mode: 'regular',
              durationSeconds: 1800,
              startedAt: DateTime.utc(2026, 10, 4, 10),
              endsAt: DateTime.utc(2026, 10, 4, 10, 15),
              status: 'active',
              updatedAt: DateTime.utc(2026, 10, 4, 10),
            ),
          );
      final state = await repository.captureLocalState();
      expect(state.hasUnfinishedFlow, isTrue);
      final cloud = await repository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: state.fingerprint,
      );
      await expectLater(
        repository.downloadCloud(
          expectedRevision: cloud.revision,
          expectedFingerprint: state.fingerprint,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('legacy fallback uploads only with the exact inspected token', () async {
    final state = CloudSnapshotLocalState(
      fingerprint: 'legacy-fingerprint',
      payload: const {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
      rowCount: 0,
      dataUpdatedAt: DateTime.utc(2026, 10, 4),
      hasUnfinishedFlow: false,
    );
    remote.seedLegacySnapshot(
      userId: 'user-a',
      token: '0123456789abcdef0123456789abcdef',
      state: state,
    );
    final oldPreview = await remote.inspect(userId: 'user-a');
    expect(oldPreview?.isLegacy, isTrue);
    expect(oldPreview?.revision, lessThan(0));

    remote.seedLegacySnapshot(
      userId: 'user-a',
      token: '1123456789abcdef0123456789abcdef',
      state: state,
    );
    await remote.inspect(userId: 'user-a');
    await expectLater(
      remote.upload(
        userId: 'user-a',
        expectedRevision: oldPreview!.revision,
        payload: state.payload,
        deviceId: 'device-a',
        deviceName: 'Phone A',
        dataUpdatedAt: state.dataUpdatedAt,
        rowCount: state.rowCount,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('legacy fallback converts to canonical revision after matching token upload', () async {
    final state = CloudSnapshotLocalState(
      fingerprint: 'legacy-fingerprint',
      payload: const {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
      rowCount: 0,
      dataUpdatedAt: DateTime.utc(2026, 10, 4),
      hasUnfinishedFlow: false,
    );
    remote.seedLegacySnapshot(
      userId: 'user-a',
      token: '0123456789abcdef0123456789abcdef',
      state: state,
    );
    final preview = await remote.inspect(userId: 'user-a');
    final saved = await remote.upload(
      userId: 'user-a',
      expectedRevision: preview!.revision,
      payload: state.payload,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: state.dataUpdatedAt,
      rowCount: state.rowCount,
    );
    expect(saved.revision, 1);
    expect(saved.isLegacy, isFalse);
  });

  test('validates the full payload before deleting local rows', () async {
    await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Preserve');
    final malformed = <String, dynamic>{
      'schemaVersion': 1,
      'userId': 'user-a',
      'tables': <String, dynamic>{},
    };
    await remote.upload(
      userId: 'user-a',
      expectedRevision: 0,
      payload: malformed,
      deviceId: 'device-b',
      deviceName: 'Tablet B',
      dataUpdatedAt: DateTime.utc(2026, 10, 4),
      rowCount: 0,
    );
    final local = await repository.captureLocalState();

    await expectLater(
      repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: local.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );
    final goal = await (database.select(
      database.localGoals,
    )..where((row) => row.id.equals('goal-a'))).getSingle();
    expect(goal.title, 'Preserve');
  });

  test(
    'accepts version 1 cloud rows without goal and task descriptions as empty',
    () async {
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: const UnavailableTaskRemoteDataSource(),
        cloudSyncEnabled: false,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '本地目标',
          description: '本地目标描述',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '本地任务',
          description: '本地任务描述',
          classification: TaskClassification.regular,
        ),
      );
      final oldCloudState = await repository.captureLocalState();
      final tables = Map<String, dynamic>.from(
        oldCloudState.payload['tables'] as Map,
      );
      for (final table in const ['local_goals', 'local_tasks']) {
        tables[table] = [
          for (final rawRow in tables[table] as List)
            Map<String, dynamic>.from(rawRow as Map)
              ..remove('description')
              ..['title'] = table == 'local_goals' ? '云端旧目标' : '云端旧任务',
        ];
      }
      final oldPayload = <String, dynamic>{
        ...oldCloudState.payload,
        'tables': tables,
      };
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 0,
        payload: oldPayload,
        deviceId: 'legacy-device',
        deviceName: 'Legacy device',
        dataUpdatedAt: oldCloudState.dataUpdatedAt,
        rowCount: oldCloudState.rowCount,
      );
      await tasks.updateGoal(
        goal.id,
        const GoalDraft(
          title: '本地保留目标',
          description: '本地保留目标描述',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.updateTask(
        task.id,
        const TaskDraft(
          title: '本地保留任务',
          description: '本地保留任务描述',
          classification: TaskClassification.regular,
        ),
      );
      final beforeDownload = await repository.captureLocalState();

      await repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: beforeDownload.fingerprint,
      );

      final restored = (await tasks.getGoals()).single;
      expect(restored.title, '云端旧目标');
      expect(restored.description, isEmpty);
      expect(restored.tasks.single.title, '云端旧任务');
      expect(restored.tasks.single.description, isEmpty);
      await tasks.dispose();
    },
  );

  test(
    'normalizes Goal and Task descriptions when restoring a snapshot',
    () async {
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: const UnavailableTaskRemoteDataSource(),
        cloudSyncEnabled: false,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '本地目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '本地任务',
          classification: TaskClassification.regular,
        ),
      );
      final local = await repository.captureLocalState();
      final tables = Map<String, dynamic>.from(local.payload['tables'] as Map);
      tables['local_goals'] = [
        for (final rawRow in tables['local_goals'] as List)
          Map<String, dynamic>.from(rawRow as Map)
            ..['description'] = '  云端目标\r\n说明  ',
      ];
      tables['local_tasks'] = [
        for (final rawRow in tables['local_tasks'] as List)
          Map<String, dynamic>.from(rawRow as Map)
            ..['description'] = '  云端任务\r\n说明  ',
      ];
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 0,
        payload: <String, dynamic>{...local.payload, 'tables': tables},
        deviceId: 'device-b',
        deviceName: 'Tablet B',
        dataUpdatedAt: local.dataUpdatedAt,
        rowCount: local.rowCount,
      );

      await repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: local.fingerprint,
      );

      final restored = (await tasks.getGoals()).single;
      expect(restored.id, goal.id);
      expect(restored.description, '云端目标 说明');
      expect(restored.tasks.single.id, task.id);
      expect(restored.tasks.single.description, '云端任务 说明');

      final beforeInvalidDownload = await repository.captureLocalState();
      final tooLongDescription = List.filled(201, '👨‍👩‍👧‍👦').join();
      final invalidTables = Map<String, dynamic>.from(
        beforeInvalidDownload.payload['tables'] as Map,
      );
      invalidTables['local_goals'] = [
        for (final rawRow in invalidTables['local_goals'] as List)
          Map<String, dynamic>.from(rawRow as Map)
            ..['description'] = tooLongDescription,
      ];
      invalidTables['local_tasks'] = [
        for (final rawRow in invalidTables['local_tasks'] as List)
          Map<String, dynamic>.from(rawRow as Map)
            ..['description'] = tooLongDescription,
      ];
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 1,
        payload: <String, dynamic>{
          ...beforeInvalidDownload.payload,
          'tables': invalidTables,
        },
        deviceId: 'device-b',
        deviceName: 'Tablet B',
        dataUpdatedAt: beforeInvalidDownload.dataUpdatedAt,
        rowCount: beforeInvalidDownload.rowCount,
      );

      await expectLater(
        repository.downloadCloud(
          expectedRevision: 2,
          expectedFingerprint: beforeInvalidDownload.fingerprint,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        (await repository.captureLocalState()).fingerprint,
        beforeInvalidDownload.fingerprint,
      );
      final preserved = (await tasks.getGoals()).single;
      expect(preserved.description, '云端目标 说明');
      expect(preserved.tasks.single.description, '云端任务 说明');
      await tasks.dispose();
    },
  );

  test(
    'rejects unexpected row columns without replacing local tasks',
    () async {
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: const UnavailableTaskRemoteDataSource(),
        cloudSyncEnabled: false,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '保留目标',
          description: '本地目标描述',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '保留任务',
          description: '本地任务描述',
          classification: TaskClassification.regular,
        ),
      );
      final local = await repository.captureLocalState();
      final tables = Map<String, dynamic>.from(local.payload['tables'] as Map);
      tables['local_goals'] = [
        for (final rawRow in tables['local_goals'] as List)
          Map<String, dynamic>.from(rawRow as Map)
            ..['title'] = '非法云端目标'
            ..['unexpected'] = 'must be rejected',
      ];
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 0,
        payload: <String, dynamic>{...local.payload, 'tables': tables},
        deviceId: 'device-b',
        deviceName: 'Tablet B',
        dataUpdatedAt: local.dataUpdatedAt,
        rowCount: local.rowCount,
      );

      await expectLater(
        repository.downloadCloud(
          expectedRevision: 1,
          expectedFingerprint: local.fingerprint,
        ),
        throwsA(isA<StateError>()),
      );

      final preserved = (await tasks.getGoals()).single;
      expect(preserved.title, '保留目标');
      expect(preserved.description, '本地目标描述');
      expect(preserved.tasks.single.title, '保留任务');
      expect(preserved.tasks.single.description, '本地任务描述');
      await tasks.dispose();
    },
  );

  test('rejects another users rows before any local replacement', () async {
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: const UnavailableTaskRemoteDataSource(),
      cloudSyncEnabled: false,
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '本地目标',
        description: '本机内容',
        classification: TaskClassification.regular,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '本地任务',
        description: '本机内容',
        classification: TaskClassification.regular,
      ),
    );
    final local = await repository.captureLocalState();
    final tables = Map<String, dynamic>.from(local.payload['tables'] as Map);
    tables['local_goals'] = [
      for (final rawRow in tables['local_goals'] as List)
        Map<String, dynamic>.from(rawRow as Map)..['title'] = '别人的云目标',
    ];
    tables['local_tasks'] = [
      for (final rawRow in tables['local_tasks'] as List)
        Map<String, dynamic>.from(rawRow as Map)..['user_id'] = 'user-b',
    ];
    await remote.upload(
      userId: 'user-a',
      expectedRevision: 0,
      payload: <String, dynamic>{...local.payload, 'tables': tables},
      deviceId: 'device-b',
      deviceName: 'Tablet B',
      dataUpdatedAt: local.dataUpdatedAt,
      rowCount: local.rowCount,
    );

    await expectLater(
      repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: local.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );

    final preserved = (await tasks.getGoals()).single;
    expect(preserved.title, '本地目标');
    expect(preserved.description, '本机内容');
    expect(preserved.tasks.single.title, '本地任务');
    expect(preserved.tasks.single.description, '本机内容');
    await tasks.dispose();
  });
}

Future<void> _addGoal(
  PactaDatabase database, {
  required String userId,
  required String id,
  required String title,
}) async {
  final now = DateTime.utc(2026, 10, 4);
  await database
      .into(database.localGoals)
      .insertOnConflictUpdate(
        LocalGoalsCompanion.insert(
          userId: userId,
          id: id,
          title: title,
          classification: 'regular',
          createdAt: now,
          updatedAt: now,
        ),
      );
}
