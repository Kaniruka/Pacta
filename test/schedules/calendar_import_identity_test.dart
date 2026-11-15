import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';

void main() {
  CalendarEventOccurrence occurrence({
    required String sourceEventId,
    required String occurrenceId,
    String? deviceOccurrenceId,
  }) => CalendarEventOccurrence(
    sourceId: 'source-a',
    sourceEventId: sourceEventId,
    occurrenceId: occurrenceId,
    eventIdentity: occurrenceId,
    title: '周会',
    startsAt: DateTime.utc(2026, 11, 16, 9),
    endsAt: DateTime.utc(2026, 11, 16, 10),
    allDay: false,
    availability: CalendarAvailability.busy,
    timeZoneId: 'Asia/Shanghai',
    deviceOccurrenceId: deviceOccurrenceId,
  );

  const source = CalendarImportSource(
    id: 'source-a',
    displayName: '工作',
    localCalendarId: '7',
  );

  test('a provider occurrence carries the synced alias only', () {
    expect(
      calendarImportIdentityAliases(
        source: source,
        occurrence: occurrence(
          sourceEventId: 'evt-1@example.com',
          occurrenceId: 'evt-1@example.com@1',
        ),
      ),
      ['sync|source-a|evt-1@example.com|evt-1@example.com@1'],
    );
  });

  test(
    'the same device row keeps one alias before and after a provider id',
    () {
      final local = calendarImportIdentityAliases(
        source: source,
        occurrence: occurrence(
          sourceEventId: 'local:42',
          occurrenceId: 'local:42@1',
          deviceOccurrenceId: 'local:42@1',
        ),
        deviceProvenance: 'install-a',
      );
      final afterSync = calendarImportIdentityAliases(
        source: source,
        occurrence: occurrence(
          sourceEventId: 'evt-42@example.com',
          occurrenceId: 'evt-42@example.com@1',
          deviceOccurrenceId: 'local:42@1',
        ),
        deviceProvenance: 'install-a',
      );

      expect(local, ['device|install-a|7|local:42@1']);
      expect(afterSync, [
        'sync|source-a|evt-42@example.com|evt-42@example.com@1',
        'device|install-a|7|local:42@1',
      ]);
      expect(local.toSet().intersection(afterSync.toSet()), {
        'device|install-a|7|local:42@1',
      });
    },
  );

  test('a fallback identity without a device alias is rejected', () {
    expect(
      () => calendarImportIdentityAliases(
        source: source,
        occurrence: occurrence(
          sourceEventId: 'local:42',
          occurrenceId: 'local:42@1',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('structured identities round trip their aliases', () {
    const aliases = [
      'sync|source-a|evt-42@example.com|evt-42@example.com@1',
      'device|install-a|7|local:42@1',
    ];
    expect(
      decodeCalendarImportIdentityAliases(
        encodeCalendarImportIdentity(aliases),
      ),
      aliases,
    );
  });

  test('a numeric device scope from an earlier build never aliases', () {
    const stored = 'calendar-import/1|device:7|source-a|local:42|local:42@1';
    expect(decodeCalendarImportIdentityAliases(stored), [stored]);
  });

  test('a v1 synced identity keeps its cross-device alias', () {
    expect(
      decodeCalendarImportIdentityAliases(
        'calendar-import/1|sync|source-a|evt-1@example.com|evt-1@example.com@1',
      ),
      ['sync|source-a|evt-1@example.com|evt-1@example.com@1'],
    );
  });
}
