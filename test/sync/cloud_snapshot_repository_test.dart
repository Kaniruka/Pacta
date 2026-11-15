import 'dart:async';

import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
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

  test(
    'uploads optional manufacturer and model metadata without changing names',
    () async {
      await _addGoal(database, userId: 'user-a', id: 'goal-a', title: 'Cloud');
      final metadataRepository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
        deviceManufacturer: '  Example Corp  ',
        deviceModel: '  Example Phone  ',
      );
      final local = await metadataRepository.captureLocalState();

      final saved = await metadataRepository.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: local.fingerprint,
      );
      final downloaded = await remote.download(userId: 'user-a');

      expect(saved.deviceName, 'Phone A');
      expect(saved.deviceManufacturer, 'Example Corp');
      expect(saved.deviceModel, 'Example Phone');
      expect(downloaded.deviceManufacturer, 'Example Corp');
      expect(downloaded.deviceModel, 'Example Phone');
    },
  );

  test(
    'empty and absent hardware metadata stays unknown on old snapshots',
    () async {
      await remote.upload(
        userId: 'user-a',
        expectedRevision: 0,
        payload: const {'schemaVersion': 1, 'userId': 'user-a', 'tables': {}},
        deviceId: 'old-device',
        deviceName: 'Older phone',
        dataUpdatedAt: DateTime.utc(2026, 10, 4),
        rowCount: 0,
        deviceManufacturer: '   ',
        deviceModel: '',
      );

      final inspected = await remote.inspect(userId: 'user-a');
      final downloaded = await remote.download(userId: 'user-a');

      expect(inspected?.deviceName, 'Older phone');
      expect(inspected?.deviceManufacturer, isNull);
      expect(inspected?.deviceModel, isNull);
      expect(downloaded.deviceName, 'Older phone');
      expect(downloaded.deviceManufacturer, isNull);
      expect(downloaded.deviceModel, isNull);
    },
  );

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
          focusMarker: '坐下',
        ),
      );
      final otherSignals = ChainSignalsRepository(
        database: database,
        userId: 'user-b',
      );
      await otherSignals.save(const ChainSignalTexts(focusMarker: '他人的标志'));
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
      expect((await signals.get()).focusMarker, '坐下');
      // A version 1 payload predates both the signal table and the owned
      // schedule table; mark it as such instead of hand-editing a current one.
      final legacy = Map<String, dynamic>.from(captured.payload)
        ..['schemaVersion'] = 1;
      legacy['tables'] = Map<String, dynamic>.from(legacy['tables'] as Map)
        ..remove('chain_signals')
        ..remove('local_schedules');
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
      expect((await otherSignals.get()).focusMarker, '他人的标志');
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

  test('pausing focus after preview still rejects an upload despite checkpoint normalization', () async {
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: 'Goal',
        classification: TaskClassification.regular,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(title: 'Task', classification: null),
    );
    await tasks.dispose();
    var now = DateTime.utc(2026, 10, 25);
    var elapsed = Duration.zero;
    final focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
      monotonicNow: () => elapsed,
    );
    try {
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      final preview = await repository.captureLocalState();
      now = now.add(const Duration(seconds: 3));
      elapsed += const Duration(seconds: 3);
      await focus.pauseSession(session.id, ruleText: 'Pause after preview');
      await expectLater(
        repository.uploadLocal(
          expectedRevision: 0,
          expectedFingerprint: preview.fingerprint,
        ),
        throwsStateError,
      );
      expect(await remote.inspect(userId: 'user-a'), isNull);
      expect(
        (await focus.getSession(session.id))!.status,
        FocusSessionStatus.paused,
      );
    } finally {
      await focus.dispose();
    }
  });

  test('设备标识读取期间取消后不再发出上传请求，也不写基线', () async {
    var cancelled = false;
    final deviceIdGate = Completer<String>();
    var deviceIdReads = 0;
    final gatedRepository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceName: 'Phone A',
      deviceIdLoader: () {
        deviceIdReads++;
        return deviceIdGate.future;
      },
    );
    final before = await gatedRepository.captureLocalState();

    final uploading = gatedRepository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: before.fingerprint,
      requestId: 'request-cancel',
      captured: before,
      isCancelled: () => cancelled,
    );
    // 上传参数求值期间就取消：关闭开关、切换账号或恢复备份都走这条路径。
    await Future<void>.delayed(Duration.zero);
    expect(deviceIdReads, 1);
    cancelled = true;
    deviceIdGate.complete('device-a');

    await expectLater(uploading, throwsA(isA<CloudUploadCancelled>()));
    expect(
      await remote.inspect(userId: 'user-a'),
      isNull,
      reason: '取消之后不得再发送旧快照',
    );
    expect(await gatedRepository.loadSyncResult(), isNull, reason: '取消后无成功基线');
    expect(await remote.history(userId: 'user-a'), isEmpty);
  });

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
      // Version 1 payloads predate the owned schedule table, so the legacy
      // read is marked as such instead of editing a current payload in place.
      final oldPayload = <String, dynamic>{
        ...oldCloudState.payload,
        'schemaVersion': 1,
        'tables': tables..remove('local_schedules'),
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

  test('exports schema version 2 and reads version 1 appointments by their retained boundary', () async {
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: const UnavailableTaskRemoteDataSource(),
      cloudSyncEnabled: false,
    );
    var clock = DateTime.utc(2026, 11, 15, 8);
    final focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => clock,
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '准备时长目标',
        classification: TaskClassification.regular,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '准备时长任务',
        classification: TaskClassification.regular,
      ),
    );
    final appointment = await focus.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
      preparation: const Duration(minutes: 37),
    );
    await focus.cancelAppointment(
      appointmentId: appointment.id,
      failureReason: '快照往返准备',
    );
    final settled = (await focus.getAppointment(appointment.id))!;

    final local = await repository.captureLocalState();
    expect(local.payload['schemaVersion'], cloudSnapshotSchemaVersion);
    final localTables = Map<String, dynamic>.from(
      local.payload['tables'] as Map,
    );
    expect(
      (localTables['focus_appointments'] as List).single,
      containsPair('preparation_seconds', 37 * 60),
    );

    // 版本 1 的云端备份既没有显式准备时长，也没有自有日程表：读取后沿用已存
    // 起止时刻，日程只从旧日历块提升。
    final legacyTables = Map<String, dynamic>.from(localTables)
      ..remove('local_schedules');
    legacyTables['focus_appointments'] = [
      for (final rawRow in localTables['focus_appointments'] as List)
        Map<String, dynamic>.from(rawRow as Map)..remove('preparation_seconds'),
    ];
    final legacyPayload = <String, dynamic>{
      ...local.payload,
      'schemaVersion': 1,
      'tables': legacyTables,
    };
    await remote.upload(
      userId: 'user-a',
      expectedRevision: 0,
      payload: legacyPayload,
      deviceId: 'legacy-device',
      deviceName: 'Legacy device',
      dataUpdatedAt: local.dataUpdatedAt,
      rowCount: local.rowCount,
    );

    await repository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: local.fingerprint,
    );

    final restored = (await focus.getAppointment(appointment.id))!;
    expect(restored.status, AppointmentPreparationStatus.failed);
    expect(restored.startedAt.isAtSameMomentAs(settled.startedAt), isTrue);
    expect(restored.endsAt.isAtSameMomentAs(settled.endsAt), isTrue);
    expect(restored.settledAt!.isAtSameMomentAs(settled.settledAt!), isTrue);
    expect(restored.preparationSeconds, isNull);
    expect(restored.effectivePreparationSeconds, 37 * 60);
    await focus.dispose();
    await tasks.dispose();
  });

  test(
    'rejects a version 2 snapshot that drops the stored preparation length',
    () async {
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: const UnavailableTaskRemoteDataSource(),
        cloudSyncEnabled: false,
      );
      final focus = LocalFocusRepository(
        database: database,
        userId: 'user-a',
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => DateTime.utc(2026, 11, 15, 8),
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '版本二严格目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '版本二严格任务',
          classification: TaskClassification.regular,
        ),
      );
      final appointment = await focus.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
        preparation: const Duration(minutes: 10),
      );
      await focus.cancelAppointment(
        appointmentId: appointment.id,
        failureReason: '版本二严格校验',
      );
      final local = await repository.captureLocalState();
      final tables = Map<String, dynamic>.from(local.payload['tables'] as Map);
      tables['focus_appointments'] = [
        for (final rawRow in tables['focus_appointments'] as List)
          Map<String, dynamic>.from(rawRow as Map)
            ..remove('preparation_seconds'),
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

      final preserved = (await focus.getAppointment(appointment.id))!;
      expect(preserved.preparationSeconds, 10 * 60);
      await focus.dispose();
      await tasks.dispose();
    },
  );

  test('rejects an unsupported snapshot schema version', () async {
    final local = await repository.captureLocalState();
    await remote.upload(
      userId: 'user-a',
      expectedRevision: 0,
      payload: <String, dynamic>{...local.payload, 'schemaVersion': 4},
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
  });

  test('rejects a version 2 payload that lost the owned schedules', () async {
    final local = await repository.captureLocalState();
    final tables = Map<String, dynamic>.from(local.payload['tables'] as Map)
      ..remove('local_schedules');
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
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('日程表'),
        ),
      ),
    );
  });

  test('rejects a version 2 payload whose appointments lost the preparation duration', () async {
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: const UnavailableTaskRemoteDataSource(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 11, 15, 8),
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '缺列目标',
        classification: TaskClassification.regular,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '缺列任务',
        classification: TaskClassification.regular,
      ),
    );
    final appointment = await focus.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
      preparation: const Duration(minutes: 10),
    );
    // 结束在途流程，否则下载会被“预约尚未结束”守卫挡在校验之前。
    await focus.cancelAppointment(
      appointmentId: appointment.id,
      failureReason: '缺列校验',
    );
    final local = await repository.captureLocalState();
    final tables = Map<String, dynamic>.from(local.payload['tables'] as Map);
    expect(
      (tables['focus_appointments'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['id'] == appointment.id),
      containsPair('preparation_seconds', 10 * 60),
    );
    tables['focus_appointments'] = [
      for (final rawRow in tables['focus_appointments'] as List)
        Map<String, dynamic>.from(rawRow as Map)..remove('preparation_seconds'),
    ];
    expect(
      (tables['focus_appointments'] as List).cast<Map>().every(
        (row) => !row.containsKey('preparation_seconds'),
      ),
      isTrue,
    );
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
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('准备时长'),
        ),
      ),
    );
    await focus.dispose();
    await tasks.dispose();
  });

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
