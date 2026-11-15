import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';

void main() {
  CalendarEventOccurrence occurrence({
    required String sourceEventId,
    required String occurrenceId,
    String? deviceOccurrenceId,
    bool isRecurring = false,
    DateTime? startsAt,
  }) {
    final start = startsAt ?? DateTime.utc(2026, 11, 16, 9);
    return CalendarEventOccurrence(
      sourceId: 'source-a',
      sourceEventId: sourceEventId,
      occurrenceId: occurrenceId,
      eventIdentity: occurrenceId,
      title: '周会',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      allDay: false,
      availability: CalendarAvailability.busy,
      timeZoneId: 'Asia/Shanghai',
      deviceOccurrenceId: deviceOccurrenceId,
      isRecurring: isRecurring,
    );
  }

  const source = CalendarImportSource(
    id: 'source-a',
    displayName: '工作',
    localCalendarId: '7',
  );

  List<String> encodings(List<CalendarImportAlias> aliases) => [
    for (final alias in aliases) alias.encode(),
  ];

  test('a single event names no occurrence', () {
    final aliases = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'evt-1@example.com',
        occurrenceId: 'evt-1@example.com@1',
        deviceOccurrenceId: 'local:42',
      ),
      deviceProvenance: 'install-a',
    );

    expect(aliases, hasLength(2));
    expect(aliases.first.kind, calendarImportAliasSync);
    expect(aliases.first.occurrenceId, isNull);
    expect(aliases.last.kind, calendarImportAliasDevice);
    expect(aliases.last.deviceRowId, 'local:42');
    expect(aliases.last.occurrenceId, isNull);
  });

  test('moving a non-recurring event keeps both aliases', () {
    final before = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'evt-1@example.com',
        occurrenceId: 'evt-1@example.com@1',
        deviceOccurrenceId: 'local:42',
      ),
      deviceProvenance: 'install-a',
    );
    final moved = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'evt-1@example.com',
        occurrenceId: 'evt-1@example.com@2',
        deviceOccurrenceId: 'local:42',
        startsAt: DateTime.utc(2026, 11, 16, 15),
      ),
      deviceProvenance: 'install-a',
    );

    expect(encodings(moved), encodings(before));
  });

  test('a recurring event names its original occurrence', () {
    final first = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'evt-9@example.com',
        occurrenceId: 'evt-9@example.com@100',
        deviceOccurrenceId: 'local:9@100',
        isRecurring: true,
      ),
      deviceProvenance: 'install-a',
    );
    final exception = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'evt-9@example.com',
        occurrenceId: 'evt-9@example.com@100',
        deviceOccurrenceId: 'local:9@100',
        isRecurring: true,
        startsAt: DateTime.utc(2026, 11, 18, 15),
      ),
      deviceProvenance: 'install-a',
    );
    final secondInstance = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'evt-9@example.com',
        occurrenceId: 'evt-9@example.com@200',
        deviceOccurrenceId: 'local:9@200',
        isRecurring: true,
      ),
      deviceProvenance: 'install-a',
    );

    expect(encodings(exception), encodings(first));
    expect(first.first.occurrenceId, 'evt-9@example.com@100');
    expect(first.last.occurrenceId, 'local:9@100');
    expect(first.first.proves(secondInstance.first), isFalse);
    expect(first.last.proves(secondInstance.last), isFalse);
  });

  test('separators inside public ids never collide', () {
    final left = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'e|x',
        occurrenceId: 'o',
        deviceOccurrenceId: 'local:1',
        isRecurring: true,
      ),
      deviceProvenance: 'install-a',
    ).first;
    final right = calendarImportIdentityAliases(
      source: source,
      occurrence: occurrence(
        sourceEventId: 'e',
        occurrenceId: 'x|o',
        deviceOccurrenceId: 'local:2',
        isRecurring: true,
      ),
      deviceProvenance: 'install-a',
    ).first;

    expect(left.encode(), isNot(right.encode()));
    expect(left.proves(right), isFalse);
    expect(right.proves(left), isFalse);
  });

  test('structured identities round trip their aliases', () {
    const aliases = [
      CalendarImportAlias.sync(
        sourceId: 'source-a',
        sourceEventId: 'evt-42@example.com',
        occurrenceId: 'evt-42@example.com@1',
      ),
      CalendarImportAlias.device(
        installId: 'install-a',
        calendarId: '7',
        deviceRowId: 'local:42',
      ),
    ];
    expect(
      encodings(
        decodeCalendarImportIdentityAliases(
          encodeCalendarImportIdentity(aliases),
        ),
      ),
      encodings(aliases),
    );
  });

  test('an installation-scoped v1 device identity is converted', () {
    final aliases = decodeCalendarImportIdentityAliases(
      'calendar-import/1|device:install-a:7|source-a|local:42|local:42@1',
      deviceProvenance: 'install-a',
    );

    expect(aliases, hasLength(1));
    expect(aliases.single.kind, calendarImportAliasDevice);
    expect(aliases.single.installId, 'install-a');
    expect(aliases.single.calendarId, '7');
    expect(aliases.single.deviceRowId, 'local:42');
    expect(aliases.single.occurrenceId, 'local:42@1');
    expect(
      aliases.single.proves(
        const CalendarImportAlias.device(
          installId: 'install-a',
          calendarId: '7',
          deviceRowId: 'local:42',
        ),
      ),
      isTrue,
    );
  });

  test('a v1 device scope of another installation stays opaque', () {
    expect(
      decodeCalendarImportIdentityAliases(
        'calendar-import/1|device:install-b:7|source-a|local:42|local:42@1',
        deviceProvenance: 'install-a',
      ),
      isEmpty,
    );
  });

  test('a numeric-only v1 device scope stays opaque', () {
    expect(
      decodeCalendarImportIdentityAliases(
        'calendar-import/1|device:7|source-a|local:42|local:42@1',
        deviceProvenance: '7',
      ),
      isEmpty,
    );
  });

  test('a v1 synced identity keeps its provider alias', () {
    final aliases = decodeCalendarImportIdentityAliases(
      'calendar-import/1|sync|source-a|evt-1@example.com|evt-1@example.com@1',
    );
    expect(aliases.single.kind, calendarImportAliasSync);
    expect(aliases.single.sourceEventId, 'evt-1@example.com');
    expect(aliases.single.occurrenceId, 'evt-1@example.com@1');
  });

  test('malformed alias payloads never alias', () {
    expect(
      decodeCalendarImportIdentityAliases(
        '{"v":2,"aliases":[{"kind":"sync"}]}',
      ),
      isEmpty,
    );
    expect(
      decodeCalendarImportIdentityAliases('{"v":2,"aliases":"x"}'),
      isEmpty,
    );
    expect(
      decodeCalendarImportIdentityAliases(
        '{"v":2,"aliases":[{"kind":"sync","source":"s","event":"e","occurrence":5}]}',
      ),
      isEmpty,
    );
    expect(decodeCalendarImportIdentityAliases('not-json'), isEmpty);
  });
}
