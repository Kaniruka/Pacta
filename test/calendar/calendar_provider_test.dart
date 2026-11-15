import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.pacta/calendar');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'listCalendars':
              return [
                {
                  'sourceId': 'source-a',
                  'displayName': '工作',
                  'timeZoneId': 'Asia/Shanghai',
                  'localCalendarId': '7',
                },
              ];
            case 'readEvents':
              return [
                {
                  'sourceId': 'source-a',
                  'sourceEventId': 'local:100',
                  'occurrenceId': 'local:100@5000',
                  'eventIdentity': 'local:100@5000',
                  'deviceOccurrenceId': 'local:100@5000',
                  'isRecurring': true,
                  'title': '周会',
                  'startsAt': 1763283600000,
                  'endsAt': 1763287200000,
                  'allDay': false,
                  'availability': 'busy',
                  'timeZoneId': 'Asia/Shanghai',
                },
              ];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('platform rows keep the device row and recurrence metadata', () async {
    const provider = AndroidCalendarProvider();
    final occurrences = await provider.readEvents(
      sourceIds: {'source-a'},
      from: DateTime.utc(2026, 11, 16),
      to: DateTime.utc(2026, 11, 23),
    );

    final occurrence = occurrences.single;
    expect(occurrence.isRecurring, isTrue);
    expect(occurrence.deviceOccurrenceId, 'local:100@5000');
    expect(occurrence.sourceEventId, 'local:100');
    expect(occurrence.availability, CalendarAvailability.busy);
  });
}
