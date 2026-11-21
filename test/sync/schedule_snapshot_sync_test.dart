import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late InMemoryCloudSnapshotRemote remote;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remote = InMemoryCloudSnapshotRemote();
  });

  test(
    'migrated schedules survive a whole-account snapshot round trip',
    () async {
      final deviceA = PactaDatabase(NativeDatabase.memory());
      final schedulesA = LocalScheduleRepository(
        database: deviceA,
        userId: 'user-a',
        now: () => DateTime.utc(2026, 11, 15, 1),
      );
      try {
        final created = await schedulesA.createSchedule(
          ScheduleDraft(
            title: '取快递',
            notes: '驿站',
            window: ScheduleWindow.timed(
              startsAt: DateTime.utc(2026, 11, 16, 10),
              endsAt: DateTime.utc(2026, 11, 16, 11),
            ),
          ),
        );
        await schedulesA.setScheduleReminder(created.id, minutesBefore: 30);
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

        final deviceB = PactaDatabase(NativeDatabase.memory());
        final schedulesB = LocalScheduleRepository(
          database: deviceB,
          userId: 'user-a',
          now: () => DateTime.utc(2026, 11, 15, 2),
        );
        try {
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

          final restored = (await schedulesB.getSchedules()).single;
          expect(restored.id, created.id);
          expect(restored.title, '取快递');
          expect(restored.notes, '驿站');
          expect(restored.reminderMinutesBefore, 30);
          expect(restored.origin, ScheduleOrigin.owned);
          expect(restored.startsAt, DateTime.utc(2026, 11, 16, 10));
        } finally {
          await schedulesB.dispose();
          await deviceB.close();
        }
      } finally {
        await schedulesA.dispose();
        await deviceA.close();
      }
    },
  );

  test('rejects a version 2 payload that dropped the schedule table', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    final schedulesA = LocalScheduleRepository(
      database: deviceA,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    final deviceB = PactaDatabase(NativeDatabase.memory());
    final schedulesB = LocalScheduleRepository(
      database: deviceB,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 3),
    );
    try {
      await schedulesA.createSchedule(
        _draft(title: 'A 的日程', startsAt: DateTime.utc(2026, 11, 16, 9)),
      );
      await schedulesB.createSchedule(
        _draft(title: 'B 本机日程', startsAt: DateTime.utc(2026, 11, 17, 9)),
      );
      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final localA = await snapshotA.captureLocalState();
      final saved = await snapshotA.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: localA.fingerprint,
      );

      final brokenTables = Map<String, dynamic>.from(
        saved.payload!['tables'] as Map,
      )..remove('local_schedules');
      final brokenPayload = Map<String, dynamic>.from(saved.payload!)
        ..['tables'] = brokenTables;
      await remote.upload(
        userId: 'user-a',
        expectedRevision: saved.revision,
        payload: brokenPayload,
        deviceId: 'device-a',
        deviceName: 'Phone A',
        dataUpdatedAt: localA.dataUpdatedAt,
        rowCount: saved.rowCount - 1,
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
          expectedRevision: saved.revision + 1,
          expectedFingerprint: localB.fingerprint,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await schedulesB.getSchedules()).single.title, 'B 本机日程');
    } finally {
      await schedulesA.dispose();
      await schedulesB.dispose();
      await deviceA.close();
      await deviceB.close();
    }
  });

  test(
    'rejects an invalid version 1 payload before replacing local data',
    () async {
      final deviceB = PactaDatabase(NativeDatabase.memory());
      final schedulesB = LocalScheduleRepository(
        database: deviceB,
        userId: 'user-a',
        now: () => DateTime.utc(2026, 11, 15, 4),
      );
      try {
        await schedulesB.createSchedule(
          _draft(title: '保留的日程', startsAt: DateTime.utc(2026, 11, 18, 9)),
        );
        final deviceA = PactaDatabase(NativeDatabase.memory());
        try {
          final now = DateTime.utc(2026, 11, 1);
          await deviceA
              .into(deviceA.localCalendarSources)
              .insert(
                LocalCalendarSourcesCompanion.insert(
                  userId: 'user-a',
                  sourceId: 'calendar-1',
                  displayName: '工作',
                  timeZoneId: 'Asia/Shanghai',
                  updatedAt: now,
                ),
              );
          await deviceA
              .into(deviceA.localCalendarBlocks)
              .insert(
                LocalCalendarBlocksCompanion.insert(
                  userId: 'user-a',
                  sourceId: 'calendar-1',
                  sourceEventId: 'event-1',
                  occurrenceId: 'event-1:20261116',
                  eventIdentity: 'event-1',
                  title: '周会',
                  startsAt: DateTime.utc(2026, 11, 16, 1),
                  endsAt: DateTime.utc(2026, 11, 16, 2),
                  availability: 'busy',
                  timeZoneId: 'Asia/Shanghai',
                  updatedAt: now,
                ),
              );
          final snapshotA = CloudSnapshotRepository(
            database: deviceA,
            remote: remote,
            userId: 'user-a',
            deviceId: 'device-a',
            deviceName: 'Phone A',
          );
          final localA = await snapshotA.captureLocalState();
          final tables = Map<String, dynamic>.from(
            localA.payload['tables'] as Map,
          )..remove('local_schedules');
          tables['local_calendar_blocks'] = [
            for (final rawRow in tables['local_calendar_blocks'] as List)
              Map<String, dynamic>.from(rawRow as Map)..remove('availability'),
          ];
          await remote.upload(
            userId: 'user-a',
            expectedRevision: 0,
            payload: <String, dynamic>{
              'schemaVersion': 1,
              'userId': 'user-a',
              'tables': tables,
            },
            deviceId: 'legacy-device',
            deviceName: 'Old phone',
            dataUpdatedAt: localA.dataUpdatedAt,
            rowCount: 2,
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
            throwsA(isA<StateError>()),
          );
          expect((await schedulesB.getSchedules()).single.title, '保留的日程');
          expect(
            await deviceB.select(deviceB.localCalendarBlocks).get(),
            isEmpty,
          );
        } finally {
          await deviceA.close();
        }
      } finally {
        await schedulesB.dispose();
        await deviceB.close();
      }
    },
  );

  test('recurrence rules, instance basis and exceptions survive a whole-account round trip', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    final schedulesA = LocalScheduleRepository(
      database: deviceA,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    final deviceB = PactaDatabase(NativeDatabase.memory());
    final schedulesB = LocalScheduleRepository(
      database: deviceB,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 4),
    );
    try {
      final series = await schedulesA.createRecurringSchedule(
        draft: _draft(title: '周会', startsAt: DateTime.utc(2026, 11, 16, 1)),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
          endDate: '2026-11-18',
        ),
        timeZoneId: 'Asia/Shanghai',
      );
      await schedulesA.editRecurringSchedule(
        series.occurrences[1].id,
        draft: _draft(
          title: '一对一',
          startsAt: DateTime.utc(2026, 11, 17, 2),
          minutes: 30,
        ),
        scope: ScheduleRepeatScope.onlyThis,
      );
      await schedulesA.deleteSchedule(series.occurrences[2].id);

      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final captured = await snapshotA.captureLocalState();
      expect(captured.payload['schemaVersion'], cloudSnapshotSchemaVersion);
      final capturedTables = captured.payload['tables'] as Map<String, dynamic>;
      expect(capturedTables['local_schedule_recurrences'], hasLength(1));
      expect(capturedTables['local_schedules'], hasLength(3));
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

      final restoredRules = await schedulesB.getRecurrenceRules();
      expect(restoredRules, hasLength(1));
      expect(restoredRules.single, series.rule);

      final restored = await schedulesB.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 20),
      );
      expect(restored.map((schedule) => schedule.title), ['周会', '一对一']);
      expect(restored.first.recurrenceDate, '2026-11-16');
      expect(restored.first.recurrenceTimeZoneId, 'Asia/Shanghai');
      expect(restored.first.recurrenceStartMinutes, 9 * 60);
      expect(restored.first.recurrenceSeriesId, series.rule.id);
      expect(restored.last.isRecurrenceException, isTrue);
      expect(restored.last.startsAt, DateTime.utc(2026, 11, 17, 2));
    } finally {
      await schedulesA.dispose();
      await schedulesB.dispose();
      await deviceA.close();
      await deviceB.close();
    }
  });

  test('rejects a current payload that dropped the recurrence table', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    final schedulesA = LocalScheduleRepository(
      database: deviceA,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    final deviceB = PactaDatabase(NativeDatabase.memory());
    final schedulesB = LocalScheduleRepository(
      database: deviceB,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 6),
    );
    try {
      await schedulesA.createSchedule(
        _draft(title: 'A 的日程', startsAt: DateTime.utc(2026, 11, 16, 9)),
      );
      await schedulesB.createSchedule(
        _draft(title: 'B 本机日程', startsAt: DateTime.utc(2026, 11, 17, 9)),
      );
      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final localA = await snapshotA.captureLocalState();
      final saved = await snapshotA.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: localA.fingerprint,
      );

      final brokenTables = Map<String, dynamic>.from(
        saved.payload!['tables'] as Map,
      )..remove('local_schedule_recurrences');
      final brokenPayload = Map<String, dynamic>.from(saved.payload!)
        ..['tables'] = brokenTables;
      await remote.upload(
        userId: 'user-a',
        expectedRevision: saved.revision,
        payload: brokenPayload,
        deviceId: 'device-a',
        deviceName: 'Phone A',
        dataUpdatedAt: localA.dataUpdatedAt,
        rowCount: saved.rowCount,
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
          expectedRevision: saved.revision + 1,
          expectedFingerprint: localB.fingerprint,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await schedulesB.getSchedules()).single.title, 'B 本机日程');
    } finally {
      await schedulesA.dispose();
      await schedulesB.dispose();
      await deviceA.close();
      await deviceB.close();
    }
  });
}

ScheduleDraft _draft({
  required String title,
  required DateTime startsAt,
  int minutes = 60,
}) => ScheduleDraft(
  title: title,
  window: ScheduleWindow.timed(
    startsAt: startsAt,
    endsAt: startsAt.add(Duration(minutes: minutes)),
  ),
);
