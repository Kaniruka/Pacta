import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_calendar_provider.dart';

const _user = 'plan-import-flow';

class _Harness {
  _Harness(this.database, {required this.clock, this.calendar});

  final PactaDatabase database;
  final DateTime Function() clock;
  final LocalCalendarRepository? calendar;
  late LocalScheduleRepository schedules;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    schedules = LocalScheduleRepository(
      database: database,
      userId: _user,
      now: clock,
    );
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        scheduleRepositoryFactory: (_) => schedules,
        calendarRepositoryFactory: calendar == null ? null : (_) => calendar!,
        displayClock: clock,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await schedules.dispose().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    await database.close().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }
}

Future<void> _openCalendar(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('计划')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('日历'));
  await tester.pumpAndSettle();
}

CalendarEventOccurrence _weeklyMeeting() => CalendarEventOccurrence(
  sourceId: 'cal-a',
  sourceEventId: 'evt-weekly@example.com',
  occurrenceId: 'evt-weekly@2026-11-16T09:00Z',
  eventIdentity: 'evt-weekly@2026-11-16T09:00Z',
  title: '周会',
  startsAt: DateTime.utc(2026, 11, 16, 9),
  endsAt: DateTime.utc(2026, 11, 16, 10),
  allDay: false,
  availability: CalendarAvailability.busy,
  timeZoneId: 'Asia/Shanghai',
);

void main() {
  testWidgets('系统日历不可用时导入给出可执行的说明，自有安排仍可管理', (tester) async {
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: () => DateTime.utc(2026, 11, 15, 9),
    );
    try {
      await harness.pump(tester);
      await _openCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('plan-import-open')));
      await tester.pumpAndSettle();
      expect(find.text('这台设备暂时不能读取系统日历；你自己的安排仍可新建和编辑。'), findsOneWidget);

      // 导入不可用不影响自有安排的创建入口。
      expect(find.text('新建安排'), findsOneWidget);
      expect(find.text('添加事项'), findsOneWidget);
      expect(await harness.schedules.getSchedules(), isEmpty);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('手动导入先预览再复制；重复导入跳过且不覆盖已改过的副本', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final calendar = LocalCalendarRepository(
      database: database,
      userId: _user,
      provider: FakeCalendarProvider(
        sources: const [
          CalendarSource(
            id: 'cal-a',
            displayName: '工作',
            timeZoneId: 'Asia/Shanghai',
            localCalendarId: '7',
          ),
        ],
        permission: CalendarPermissionState.granted,
        events: [_weeklyMeeting()],
      ),
      remote: InMemoryCalendarRemote(),
      cloudSyncEnabled: false,
    );
    final harness = _Harness(
      database,
      clock: () => DateTime.utc(2026, 11, 15, 9),
      calendar: calendar,
    );
    try {
      await harness.pump(tester);
      await _openCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('plan-import-open')));
      await tester.pumpAndSettle();
      expect(find.text('从系统日历导入'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('plan-import-source-cal-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-import-preview')));
      await tester.pumpAndSettle();

      // 预览只说明会发生什么，此时还没有写任何副本。
      expect(find.text('将复制 1 项安排'), findsOneWidget);
      expect(find.text('已导入过的 0 项会跳过：不会重复添加，也不会覆盖你改过的内容。'), findsOneWidget);
      expect(await harness.schedules.getSchedules(), isEmpty);

      await tester.tap(find.byKey(const Key('plan-import-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('已复制 1 项安排；跳过 0 项已经导入过的。'), findsOneWidget);
      // 让上一条提示退场，第二次导入的结果提示才会显示。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final imported = (await harness.schedules.getSchedules()).single;
      expect(imported.title, '周会');
      expect(imported.origin, ScheduleOrigin.calendarImport);

      // 用户改过副本之后再次导入：跳过，不覆盖用户内容。
      await harness.schedules.updateSchedule(
        imported.id,
        ScheduleDraft(title: '周会（改）', window: imported.window),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-import-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-import-source-cal-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-import-preview')));
      await tester.pumpAndSettle();

      expect(find.text('所选范围内都是已导入过的安排，已跳过 1 项。'), findsOneWidget);
      final schedules = await harness.schedules.getSchedules();
      expect(schedules, hasLength(1));
      expect(schedules.single.title, '周会（改）');
    } finally {
      await harness.dispose(tester);
    }
  });
}
