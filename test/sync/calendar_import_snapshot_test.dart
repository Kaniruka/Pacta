import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
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

  CalendarImportRequest request() => CalendarImportRequest(
    sources: const [
      CalendarImportSource(
        id: 'source-a',
        displayName: '工作',
        localCalendarId: '7',
      ),
    ],
    occurrences: [
      CalendarEventOccurrence(
        sourceId: 'source-a',
        sourceEventId: 'evt-1@example.com',
        occurrenceId: 'evt-1@example.com@1763283600000',
        eventIdentity: 'evt-1@example.com@1763283600000',
        title: '周会',
        startsAt: _start,
        endsAt: _end,
        allDay: false,
        availability: CalendarAvailability.busy,
        timeZoneId: 'Asia/Shanghai',
      ),
    ],
    from: _rangeFrom,
    to: _rangeTo,
  );

  test(
    'import copies survive a snapshot round trip and keep skipping',
    () async {
      final deviceA = PactaDatabase(NativeDatabase.memory());
      final schedulesA = LocalScheduleRepository(
        database: deviceA,
        userId: 'user-a',
        now: () => DateTime.utc(2026, 11, 15, 1),
      );
      try {
        final preview = await schedulesA.previewCalendarImport(request());
        final created = await schedulesA.confirmCalendarImport(preview);
        expect(created.createdCount, 1);

        final snapshotA = CloudSnapshotRepository(
          database: deviceA,
          remote: remote,
          userId: 'user-a',
          deviceId: 'device-a',
          deviceName: 'Phone A',
        );
        final captured = await snapshotA.captureLocalState();
        expect(captured.payload['schemaVersion'], isNotNull);
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
          expect(restored.title, '周会');
          expect(restored.origin, ScheduleOrigin.calendarImport);
          expect(restored.sourceIds, ['source-a']);
          expect(restored.eventIdentity, startsWith('calendar-import/1|sync|'));

          final repeated = await schedulesB.previewCalendarImport(request());
          expect(repeated.pending, isEmpty);
          expect(repeated.duplicateCount, 1);
          final again = await schedulesB.confirmCalendarImport(repeated);
          expect(again.createdCount, 0);
          expect(await schedulesB.getSchedules(), hasLength(1));
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
}

final DateTime _start = DateTime.utc(2026, 11, 16, 9);
final DateTime _end = DateTime.utc(2026, 11, 16, 10);
final DateTime _rangeFrom = DateTime.utc(2026, 11, 16);
final DateTime _rangeTo = DateTime.utc(2026, 11, 23);
