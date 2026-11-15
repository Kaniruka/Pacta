import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalScheduleRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  CalendarEventOccurrence timed({
    String sourceId = 'source-a',
    String sourceEventId = 'evt-1@example.com',
    String? occurrenceId,
    String title = '周会',
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    final start = startsAt ?? DateTime.utc(2026, 11, 16, 9);
    return CalendarEventOccurrence(
      sourceId: sourceId,
      sourceEventId: sourceEventId,
      occurrenceId:
          occurrenceId ?? '$sourceEventId@${start.millisecondsSinceEpoch}',
      eventIdentity:
          occurrenceId ?? '$sourceEventId@${start.millisecondsSinceEpoch}',
      title: title,
      startsAt: start,
      endsAt: endsAt ?? start.add(const Duration(hours: 1)),
      allDay: false,
      availability: CalendarAvailability.busy,
      timeZoneId: 'Asia/Shanghai',
    );
  }

  CalendarImportRequest request(List<CalendarEventOccurrence> occurrences) =>
      CalendarImportRequest(
        sources: const [
          CalendarImportSource(
            id: 'source-a',
            displayName: '工作',
            localCalendarId: '7',
          ),
        ],
        occurrences: occurrences,
        from: DateTime.utc(2026, 11, 16),
        to: DateTime.utc(2026, 11, 23),
      );

  test('preview counts copies to import and writes nothing', () async {
    final preview = await repository.previewCalendarImport(
      request([timed(), timed(sourceEventId: 'evt-2@example.com')]),
    );

    expect(preview.pending, hasLength(2));
    expect(preview.duplicateCount, 0);
    expect(preview.totalCount, 2);
    expect(preview.pending.first.identityKey, startsWith('calendar-import/1|'));
    expect(preview.pending.first.identityKey, contains('|source-a|'));
    expect(await repository.getSchedules(), isEmpty);
  });

  test(
    'confirm creates owned copies and skips them on a repeat import',
    () async {
      final first = await repository.previewCalendarImport(
        request([timed(), timed(sourceEventId: 'evt-2@example.com')]),
      );
      final outcome = await repository.confirmCalendarImport(first);

      expect(outcome.createdCount, 2);
      expect(outcome.skippedDuplicates, 0);
      final copies = await repository.getSchedules();
      expect(copies, hasLength(2));
      final copy = copies.firstWhere(
        (item) => item.sourceEventId == 'evt-1@example.com',
      );
      expect(copy.origin, ScheduleOrigin.calendarImport);
      expect(copy.sourceIds, ['source-a']);
      expect(copy.sourceNames, ['工作']);
      expect(copy.sourceEventId, 'evt-1@example.com');
      expect(
        copy.eventIdentity,
        startsWith('calendar-import/1|sync|source-a|'),
      );
      expect(copy.isCompleted, isFalse);

      final again = await repository.previewCalendarImport(
        request([timed(), timed(sourceEventId: 'evt-2@example.com')]),
      );
      expect(again.pending, isEmpty);
      expect(again.duplicateCount, 2);
      final second = await repository.confirmCalendarImport(again);
      expect(second.createdCount, 0);
      expect(second.skippedDuplicates, 0);
      expect(await repository.getSchedules(), hasLength(2));
    },
  );

  test('a user-edited copy is neither overwritten nor duplicated', () async {
    final preview = await repository.previewCalendarImport(request([timed()]));
    final created = (await repository.confirmCalendarImport(preview))
        .created
        .single;
    final edited = await repository.updateSchedule(
      created.id,
      ScheduleDraft(
        title: '改到下午的周会',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 15),
          endsAt: DateTime.utc(2026, 11, 16, 16),
        ),
      ),
    );
    expect(edited.eventIdentity, created.eventIdentity);

    final again = await repository.previewCalendarImport(request([timed()]));
    expect(again.pending, isEmpty);
    expect(again.duplicateCount, 1);
    await repository.confirmCalendarImport(again);

    final stored = (await repository.getSchedules()).single;
    expect(stored.title, '改到下午的周会');
    expect(stored.startsAt, DateTime.utc(2026, 11, 16, 15));
    expect(stored.eventIdentity, created.eventIdentity);
  });

  test('raw source ids from different calendars never collapse', () async {
    final twoSources = CalendarImportRequest(
      sources: const [
        CalendarImportSource(
          id: 'source-a',
          displayName: '工作',
          localCalendarId: '7',
        ),
        CalendarImportSource(
          id: 'source-b',
          displayName: '个人',
          localCalendarId: '8',
        ),
      ],
      occurrences: [
        timed(),
        timed(sourceId: 'source-b'),
      ],
      from: DateTime.utc(2026, 11, 16),
      to: DateTime.utc(2026, 11, 23),
    );
    final preview = await repository.previewCalendarImport(twoSources);
    expect(preview.pending, hasLength(2));
    expect(preview.duplicateCount, 0);
    final outcome = await repository.confirmCalendarImport(preview);
    expect(outcome.createdCount, 2);
    expect(
      (await repository.getSchedules())
          .map((item) => item.sourceIds.single)
          .toSet(),
      {'source-a', 'source-b'},
    );
  });

  test('device-local fallback ids are scoped by the local calendar', () async {
    final localA = timed(
      sourceId: 'source-a',
      sourceEventId: 'local:42',
      occurrenceId: 'local:42@1',
      title: '本机私事',
    );
    final localB = timed(
      sourceId: 'source-b',
      sourceEventId: 'local:42',
      occurrenceId: 'local:42@1',
      title: '本机私事',
    );
    final twoDevices = CalendarImportRequest(
      sources: const [
        CalendarImportSource(
          id: 'source-a',
          displayName: '本机 7',
          localCalendarId: '7',
        ),
        CalendarImportSource(
          id: 'source-b',
          displayName: '本机 8',
          localCalendarId: '8',
        ),
      ],
      occurrences: [localA, localB],
      from: DateTime.utc(2026, 11, 16),
      to: DateTime.utc(2026, 11, 23),
    );

    final preview = await repository.previewCalendarImport(twoDevices);
    expect(preview.pending, hasLength(2));
    expect(
      preview.pending.map((item) => item.identityKey).toSet(),
      hasLength(2),
    );
    expect(preview.pending.first.identityKey, contains('|device:7|'));
    expect(preview.pending.last.identityKey, contains('|device:8|'));
  });

  test('imports stay independent per occurrence of one series', () async {
    final series = [
      timed(occurrenceId: 'evt-1@1', startsAt: DateTime.utc(2026, 11, 16, 9)),
      timed(occurrenceId: 'evt-1@2', startsAt: DateTime.utc(2026, 11, 17, 9)),
    ];
    final preview = await repository.previewCalendarImport(request(series));
    expect(preview.pending, hasLength(2));
    expect(preview.duplicateCount, 0);
  });

  test('out-of-range and untitled occurrences never become copies', () async {
    final outside = timed(startsAt: DateTime.utc(2026, 12, 1, 9));
    final untitled = timed(sourceEventId: 'evt-3@example.com', title: '  ');
    final preview = await repository.previewCalendarImport(
      request([outside, untitled]),
    );
    expect(preview.pending, isEmpty);
    expect(preview.ignoredCount, 1);
    expect(preview.totalCount, 1);
  });

  test(
    'legacy promoted copies still match on the same source origin',
    () async {
      await database
          .into(database.localCalendarSources)
          .insert(
            LocalCalendarSourcesCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              displayName: '工作',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );
      const rawIdentity = 'evt-1@example.com@1763283600000';
      await database
          .into(database.localCalendarBlocks)
          .insert(
            LocalCalendarBlocksCompanion.insert(
              userId: 'user-a',
              sourceId: 'source-a',
              sourceEventId: 'evt-1@example.com',
              occurrenceId: rawIdentity,
              eventIdentity: rawIdentity,
              title: '周会',
              startsAt: DateTime.utc(2026, 11, 16, 9),
              endsAt: DateTime.utc(2026, 11, 16, 10),
              availability: 'busy',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );
      await repository.promoteLegacyCalendarBlocks();
      final promoted = (await repository.getSchedules()).single;
      expect(promoted.origin, ScheduleOrigin.legacyCalendarBlock);

      final sameOrigin = await repository.previewCalendarImport(
        request([
          timed(sourceEventId: 'evt-1@example.com', occurrenceId: rawIdentity),
        ]),
      );
      expect(sameOrigin.pending, isEmpty);
      expect(sameOrigin.duplicateCount, 1);

      final otherOrigin = await repository.previewCalendarImport(
        CalendarImportRequest(
          sources: const [
            CalendarImportSource(id: 'source-b', displayName: '个人'),
          ],
          occurrences: [
            timed(
              sourceId: 'source-b',
              sourceEventId: 'evt-1@example.com',
              occurrenceId: rawIdentity,
            ),
          ],
          from: DateTime.utc(2026, 11, 16),
          to: DateTime.utc(2026, 11, 23),
        ),
      );
      expect(otherOrigin.pending, hasLength(1));
      expect(otherOrigin.duplicateCount, 0);
    },
  );
}
