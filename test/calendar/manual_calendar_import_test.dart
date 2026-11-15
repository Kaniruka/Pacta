import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/calendar/manual_calendar_import.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';

import '../support/fake_calendar_provider.dart';
import '../support/test_database.dart';

const _user = 'manual-import-zone';

class _RecordingProvider extends FakeCalendarProvider {
  _RecordingProvider({required super.events})
    : super(
        sources: const [
          CalendarSource(
            id: 'cal-a',
            displayName: '工作',
            timeZoneId: 'America/New_York',
            localCalendarId: '7',
          ),
        ],
        permission: CalendarPermissionState.granted,
      );

  DateTime? receivedFrom;
  DateTime? receivedTo;

  @override
  Future<List<CalendarEventOccurrence>> readEvents({
    required Set<String> sourceIds,
    required DateTime from,
    required DateTime to,
  }) {
    receivedFrom = from.toUtc();
    receivedTo = to.toUtc();
    return super.readEvents(sourceIds: sourceIds, from: from, to: to);
  }
}

CalendarEventOccurrence _timed({
  required DateTime startsAt,
  required String title,
}) => CalendarEventOccurrence(
  sourceId: 'cal-a',
  sourceEventId: 'evt-$title@example.com',
  occurrenceId: 'evt-$title@${startsAt.toUtc().toIso8601String()}',
  eventIdentity: 'evt-$title@${startsAt.toUtc().toIso8601String()}',
  title: title,
  startsAt: startsAt,
  endsAt: startsAt.add(const Duration(hours: 1)),
  allDay: false,
  availability: CalendarAvailability.busy,
  timeZoneId: 'America/New_York',
);

CalendarEventOccurrence _allDay({
  required String startDate,
  required String endDateExclusive,
  required String title,
}) {
  final start = DateTime.parse('${startDate}T00:00:00Z');
  final end = DateTime.parse('${endDateExclusive}T00:00:00Z');
  return CalendarEventOccurrence(
    sourceId: 'cal-a',
    sourceEventId: 'evt-$title@example.com',
    occurrenceId: 'evt-$title@$startDate',
    eventIdentity: 'evt-$title@$startDate',
    title: title,
    startsAt: start,
    endsAt: end,
    allDay: true,
    allDayStartDate: startDate,
    allDayEndDateExclusive: endDateExclusive,
    availability: CalendarAvailability.busy,
    timeZoneId: 'America/New_York',
  );
}

void main() {
  test('纽约跨夏令时的账号时区边界按日历日构造', () {
    final range = calendarZoneRange(
      displayTimeZoneId: 'America/New_York',
      firstDay: DateTime.utc(2026, 3, 7),
      lastDayInclusive: DateTime.utc(2026, 3, 13),
    );
    // 03-07 00:00 EST = 05:00Z；03-14 00:00 EDT = 04:00Z（回拨后少一小时）。
    expect(range.from, DateTime.utc(2026, 3, 7, 5));
    expect(range.toExclusive, DateTime.utc(2026, 3, 14, 4));

    final query = calendarImportQueryRange(
      displayTimeZoneId: 'America/New_York',
      firstDay: DateTime.utc(2026, 3, 7),
      lastDayInclusive: DateTime.utc(2026, 3, 13),
    );
    expect(query.from, DateTime.utc(2026, 3, 6, 5));
    expect(query.to, DateTime.utc(2026, 3, 15, 4));
  });

  test('全天事件按公民日过滤：负时区不多导次日，正时区不多导前日', () {
    final events = [
      _allDay(
        startDate: '2026-03-06',
        endDateExclusive: '2026-03-07',
        title: '前一天',
      ),
      _allDay(
        startDate: '2026-03-07',
        endDateExclusive: '2026-03-08',
        title: '首日',
      ),
      _allDay(
        startDate: '2026-03-13',
        endDateExclusive: '2026-03-14',
        title: '末日',
      ),
      _allDay(
        startDate: '2026-03-14',
        endDateExclusive: '2026-03-15',
        title: '次日',
      ),
      _timed(startsAt: DateTime.utc(2026, 3, 14, 2), title: '末日晚'),
      _timed(startsAt: DateTime.utc(2026, 3, 14, 5), title: '次日凌晨'),
    ];

    final newYork = occurrencesWithinAccountDays(
      events,
      displayTimeZoneId: 'America/New_York',
      firstDay: DateTime.utc(2026, 3, 7),
      lastDayInclusive: DateTime.utc(2026, 3, 13),
    );
    expect(newYork.map((event) => event.title), ['首日', '末日', '末日晚']);

    final kiritimati = occurrencesWithinAccountDays(
      events,
      displayTimeZoneId: 'Pacific/Kiritimati',
      firstDay: DateTime.utc(2026, 3, 7),
      lastDayInclusive: DateTime.utc(2026, 3, 13),
    );
    // +14 时区里“前一天”的 UTC 哨兵仍与区间重叠，但公民日不在范围内。
    expect(kiritimati.map((event) => event.title), ['首日', '末日']);
  });

  testWidgets('Plan 导入按账号时区向平台查询，并把全天边界挡在区间外', (tester) async {
    final provider = _RecordingProvider(
      events: [
        _allDay(
          startDate: '2026-03-06',
          endDateExclusive: '2026-03-07',
          title: '前一日全天',
        ),
        _allDay(
          startDate: '2026-03-07',
          endDateExclusive: '2026-03-08',
          title: '首日全天',
        ),
        _allDay(
          startDate: '2026-03-14',
          endDateExclusive: '2026-03-15',
          title: '次日全天',
        ),
      ],
    );
    final database = openTestDatabase();
    final calendar = LocalCalendarRepository(
      database: database,
      userId: _user,
      provider: provider,
      remote: InMemoryCalendarRemote(),
      cloudSyncEnabled: false,
    );
    final schedules = LocalScheduleRepository(
      database: database,
      userId: _user,
      now: () => DateTime.utc(2026, 3, 7, 12),
    );
    addTearDown(() async {
      // 先卸掉页面，再关仓储；最后推一帧，跑完 drift 关闭查询流时排的
      // 零延迟计时器（否则会以 “A Timer is still pending” 失败）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      await schedules.dispose();
      await calendar.dispose();
      await database.close();
      await tester.pump(const Duration(milliseconds: 20));
    });

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PlanCalendarView(
            repository: schedules,
            goals: const [],
            displayTimeZoneId: 'America/New_York',
            now: () => DateTime.utc(2026, 3, 7, 12),
            calendarRepository: calendar,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('plan-import-open')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-import-source-cal-a')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-import-preview')));
    await tester.pumpAndSettle();

    expect(provider.receivedFrom, DateTime.utc(2026, 3, 6, 5));
    expect(provider.receivedTo, DateTime.utc(2026, 3, 15, 4));
    expect(find.text('将复制 1 项安排'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendar-import-confirm')));
    await tester.pumpAndSettle();

    final imported = await schedules.getSchedules();
    expect(imported.map((schedule) => schedule.title), ['首日全天']);
  });
}
