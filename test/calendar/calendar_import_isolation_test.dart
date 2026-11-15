import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_calendar_provider.dart';

void main() {
  late PactaDatabase database;
  late FakeCalendarProvider provider;
  late LocalCalendarRepository calendarRepository;
  late LocalScheduleRepository scheduleRepository;

  final startsAt = DateTime.utc(2026, 11, 16, 9);

  CalendarEventOccurrence occurrence() => CalendarEventOccurrence(
    sourceId: 'source-a',
    sourceEventId: 'evt-1@example.com',
    occurrenceId: 'evt-1@example.com@1',
    eventIdentity: 'evt-1@example.com@1',
    title: '周会',
    startsAt: startsAt,
    endsAt: startsAt.add(const Duration(hours: 1)),
    allDay: false,
    availability: CalendarAvailability.busy,
    timeZoneId: 'Asia/Shanghai',
  );

  CalendarImportRequest request() => CalendarImportRequest(
    sources: const [
      CalendarImportSource(
        id: 'source-a',
        displayName: '工作',
        localCalendarId: '7',
      ),
    ],
    occurrences: [occurrence()],
    from: DateTime.utc(2026, 11, 16),
    to: DateTime.utc(2026, 11, 23),
  );

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    provider = FakeCalendarProvider(
      sources: const [
        CalendarSource(
          id: 'source-a',
          displayName: '工作',
          timeZoneId: 'Asia/Shanghai',
          localCalendarId: '7',
        ),
      ],
      permission: CalendarPermissionState.granted,
      events: [occurrence()],
    );
    calendarRepository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: provider,
      remote: InMemoryCalendarRemote(),
    );
    scheduleRepository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
  });

  tearDown(() async {
    await scheduleRepository.dispose();
    await calendarRepository.dispose();
    await database.close();
  });

  test('removing a calendar source keeps imported copies intact', () async {
    await calendarRepository.requestAccess();
    final preview = await scheduleRepository.previewCalendarImport(request());
    final outcome = await scheduleRepository.confirmCalendarImport(preview);
    expect(outcome.createdCount, 1);

    await calendarRepository.removeSources({'source-a'});

    final copies = await scheduleRepository.getSchedules();
    expect(copies, hasLength(1));
    expect(copies.single.title, '周会');
    expect(copies.single.origin.name, 'calendarImport');
    expect(await database.select(database.localCalendarSources).get(), isEmpty);
  });

  test(
    'a revoked permission leaves copies and refuses a new preview read',
    () async {
      await calendarRepository.requestAccess();
      final preview = await scheduleRepository.previewCalendarImport(request());
      await scheduleRepository.confirmCalendarImport(preview);

      provider.permission = CalendarPermissionState.denied;
      await expectLater(
        calendarRepository.readOccurrences(
          sourceIds: {'source-a'},
          from: DateTime.utc(2026, 11, 16),
          to: DateTime.utc(2026, 11, 23),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await scheduleRepository.getSchedules(), hasLength(1));
    },
  );
}
