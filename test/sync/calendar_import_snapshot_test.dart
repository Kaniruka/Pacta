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

  CalendarImportRequest localRequest({String title = '本机事件'}) =>
      CalendarImportRequest(
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
            sourceEventId: 'local:42',
            occurrenceId: 'local:42@1',
            eventIdentity: 'local:42@1',
            deviceOccurrenceId: 'local:42@1',
            title: title,
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

  CalendarImportRequest providerRequest() => CalendarImportRequest(
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
        sourceEventId: 'evt-42@example.com',
        occurrenceId: 'evt-42@example.com@${_start.millisecondsSinceEpoch}',
        eventIdentity: 'evt-42@example.com@${_start.millisecondsSinceEpoch}',
        deviceOccurrenceId: 'local:42@1',
        title: '先导入的本机事件',
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

  Future<void> seedInstallation(PactaDatabase db, String installId) => db
      .into(db.focusSourceDevices)
      .insert(
        FocusSourceDevicesCompanion.insert(
          userId: 'user-a',
          deviceId: installId,
        ),
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
          expect(
            decodeCalendarImportIdentityAliases(restored.eventIdentity).single,
            startsWith('sync|source-a|evt-1@example.com|'),
          );

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

  test('two installations with the same local calendar and event ids never collide', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    await seedInstallation(deviceA, 'install-a');
    final schedulesA = LocalScheduleRepository(
      database: deviceA,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    try {
      final preview = await schedulesA.previewCalendarImport(
        localRequest(title: 'A 的本机事件'),
      );
      final created = await schedulesA.confirmCalendarImport(preview);
      expect(created.createdCount, 1);
      expect(
        decodeCalendarImportIdentityAliases(
          created.created.single.eventIdentity,
        ),
        ['device|install-a|7|local:42@1'],
      );

      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final captured = await snapshotA.captureLocalState();
      final saved = await snapshotA.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: captured.fingerprint,
      );

      final deviceB = PactaDatabase(NativeDatabase.memory());
      await seedInstallation(deviceB, 'install-b');
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

        final received = (await schedulesB.getSchedules()).single;
        expect(decodeCalendarImportIdentityAliases(received.eventIdentity), [
          'device|install-a|7|local:42@1',
        ]);

        final candidate = await schedulesB.previewCalendarImport(
          localRequest(title: 'B 的本机事件'),
        );
        expect(candidate.duplicateCount, 0);
        expect(candidate.pending, hasLength(1));
        expect(
          decodeCalendarImportIdentityAliases(
            candidate.pending.single.identityKey,
          ),
          ['device|install-b|7|local:42@1'],
        );

        final imported = await schedulesB.confirmCalendarImport(candidate);
        expect(imported.createdCount, 1);
        final copies = await schedulesB.getSchedules();
        expect(copies, hasLength(2));
        expect(copies.map((copy) => copy.title).toSet(), {
          'A 的本机事件',
          'B 的本机事件',
        });
      } finally {
        await schedulesB.dispose();
        await deviceB.close();
      }
    } finally {
      await schedulesA.dispose();
      await deviceA.close();
    }
  });

  test('a provider id assigned to a device-local import dedups on another installation', () async {
    final deviceA = PactaDatabase(NativeDatabase.memory());
    await seedInstallation(deviceA, 'install-a');
    final schedulesA = LocalScheduleRepository(
      database: deviceA,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    try {
      final localPreview = await schedulesA.previewCalendarImport(
        localRequest(title: '先导入的本机事件'),
      );
      await schedulesA.confirmCalendarImport(localPreview);

      // Android later assigns a provider id to that same device row.
      final providerPreview = await schedulesA.previewCalendarImport(
        providerRequest(),
      );
      expect(providerPreview.pending, isEmpty);
      expect(providerPreview.duplicateCount, 1);
      await schedulesA.confirmCalendarImport(providerPreview);

      final localCopy = (await schedulesA.getSchedules()).single;
      expect(localCopy.title, '先导入的本机事件');
      expect(
        decodeCalendarImportIdentityAliases(localCopy.eventIdentity).toSet(),
        {
          'sync|source-a|evt-42@example.com|evt-42@example.com@${_start.millisecondsSinceEpoch}',
          'device|install-a|7|local:42@1',
        },
      );

      final snapshotA = CloudSnapshotRepository(
        database: deviceA,
        remote: remote,
        userId: 'user-a',
        deviceId: 'device-a',
        deviceName: 'Phone A',
      );
      final captured = await snapshotA.captureLocalState();
      final saved = await snapshotA.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: captured.fingerprint,
      );

      final deviceB = PactaDatabase(NativeDatabase.memory());
      await seedInstallation(deviceB, 'install-b');
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

        final repeated = await schedulesB.previewCalendarImport(
          providerRequest(),
        );
        expect(repeated.pending, isEmpty);
        expect(repeated.duplicateCount, 1);
        final again = await schedulesB.confirmCalendarImport(repeated);
        expect(again.createdCount, 0);
        expect((await schedulesB.getSchedules()).single.title, '先导入的本机事件');
      } finally {
        await schedulesB.dispose();
        await deviceB.close();
      }
    } finally {
      await schedulesA.dispose();
      await deviceA.close();
    }
  });
}

final DateTime _start = DateTime.utc(2026, 11, 16, 9);
final DateTime _end = DateTime.utc(2026, 11, 16, 10);
final DateTime _rangeFrom = DateTime.utc(2026, 11, 16);
final DateTime _rangeTo = DateTime.utc(2026, 11, 23);
