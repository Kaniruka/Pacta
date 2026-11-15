import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_page.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/schedules/calendar_import_models.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_calendar_provider.dart';

void main() {
  late PactaDatabase database;
  late LocalCalendarRepository calendarRepository;
  late LocalScheduleRepository scheduleRepository;
  late FakeCalendarProvider provider;

  final today = DateTime.now();
  final dayStart = DateTime(today.year, today.month, today.day);
  DateTime atLocalHour(int day, int hour) =>
      dayStart.add(Duration(days: day, hours: hour));

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
      events: [
        CalendarEventOccurrence(
          sourceId: 'source-a',
          sourceEventId: 'evt-1@example.com',
          occurrenceId: 'evt-1@example.com@1',
          eventIdentity: 'evt-1@example.com@1',
          title: '周会',
          startsAt: atLocalHour(1, 9).toUtc(),
          endsAt: atLocalHour(1, 10).toUtc(),
          allDay: false,
          availability: CalendarAvailability.busy,
          timeZoneId: 'Asia/Shanghai',
        ),
        CalendarEventOccurrence(
          sourceId: 'source-a',
          sourceEventId: 'evt-2@example.com',
          occurrenceId: 'evt-2@example.com@1',
          eventIdentity: 'evt-2@example.com@1',
          title: '评审',
          startsAt: atLocalHour(2, 14).toUtc(),
          endsAt: atLocalHour(2, 15).toUtc(),
          allDay: false,
          availability: CalendarAvailability.busy,
          timeZoneId: 'Asia/Shanghai',
        ),
      ],
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

  Future<void> pumpPage(WidgetTester tester, {required bool isAndroid}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarSourcesPage(
          repository: calendarRepository,
          isAndroid: isAndroid,
          scheduleRepository: scheduleRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Android previews the selected range and writes nothing on cancel',
    (tester) async {
      await pumpPage(tester, isAndroid: true);

      await tester.tap(find.byKey(const Key('calendar-import-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-source-source-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-preview')));
      await tester.pumpAndSettle();

      expect(find.text('将导入 2 个日程'), findsOneWidget);
      expect(find.text('已存在将跳过 0 个'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await scheduleRepository.getSchedules(), isEmpty);
    },
  );

  testWidgets('Android confirm writes copies and a repeat preview skips them', (
    tester,
  ) async {
    await pumpPage(tester, isAndroid: true);

    await tester.tap(find.byKey(const Key('calendar-import-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-source-source-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-confirm')));
    await tester.pumpAndSettle();

    final copies = await scheduleRepository.getSchedules();
    expect(copies, hasLength(2));
    expect(
      copies.map((item) => item.origin),
      everyElement(ScheduleOrigin.calendarImport),
    );
    expect(find.textContaining('已导入 2 个日程'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendar-import-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-source-source-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-preview')));
    await tester.pumpAndSettle();

    expect(find.text('已存在将跳过 2 个'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await scheduleRepository.getSchedules(), hasLength(2));
  });

  testWidgets('Windows states that system calendar reading is unavailable', (
    tester,
  ) async {
    await scheduleRepository.createSchedule(
      ScheduleDraft(
        title: '自有日程',
        window: ScheduleWindow.timed(
          startsAt: atLocalHour(1, 9).toUtc(),
          endsAt: atLocalHour(1, 10).toUtc(),
        ),
      ),
    );

    await pumpPage(tester, isAndroid: false);

    expect(find.textContaining('暂不支持读取系统日历'), findsOneWidget);
    expect(find.text('导入系统日历'), findsNothing);
    final owned = await scheduleRepository.getSchedules();
    expect(owned.single.title, '自有日程');
    expect(owned.single.origin, ScheduleOrigin.owned);
  });

  testWidgets(
    'revoking permission keeps imported copies and blocks re-import',
    (tester) async {
      await calendarRepository.requestAccess();
      final preview = await scheduleRepository.previewCalendarImport(
        CalendarImportRequest(
          sources: const [
            CalendarImportSource(
              id: 'source-a',
              displayName: '工作',
              localCalendarId: '7',
            ),
          ],
          occurrences: provider.events,
          from: dayStart,
          to: dayStart.add(const Duration(days: 7)),
        ),
      );
      await scheduleRepository.confirmCalendarImport(preview);
      provider.permission = CalendarPermissionState.denied;

      await pumpPage(tester, isAndroid: true);

      expect(find.text('设备日历权限已关闭'), findsOneWidget);
      expect(await scheduleRepository.getSchedules(), hasLength(2));
      await tester.tap(find.byKey(const Key('calendar-import-start')));
      await tester.pumpAndSettle();
      expect(find.textContaining('未获得日历读取权限'), findsOneWidget);
      expect(await scheduleRepository.getSchedules(), hasLength(2));
    },
  );
}
