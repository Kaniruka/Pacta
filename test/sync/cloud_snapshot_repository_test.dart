import 'package:drift/native.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late CloudSnapshotRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
  });

  tearDown(() => database.close());

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
