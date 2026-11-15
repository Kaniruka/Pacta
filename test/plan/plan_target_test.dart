import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/plan/plan_target.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  group('PlanTarget 解析', () {
    test('plan-day 打开账号时区里的日历日', () {
      final target = PlanTarget.tryParse('plan-day:2026-12-03');
      expect(target, isNotNull);
      expect(target!.day, DateTime(2026, 12, 3));
      expect(target.scheduleId, isNull);
    });

    test('plan-item 带上要定位的安排', () {
      final target = PlanTarget.tryParse('plan-item:2026-12-03:schedule-42');
      expect(target!.day, DateTime(2026, 12, 3));
      expect(target.scheduleId, 'schedule-42');
    });

    test('不是 Plan 目标或日期非法时返回 null，交给其他通知分支', () {
      expect(PlanTarget.tryParse('session:abc'), isNull);
      expect(PlanTarget.tryParse('daily-open-reminder:1'), isNull);
      expect(PlanTarget.tryParse('plan-day:2026-02-30'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03:'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03'), isNull);
    });
  });

  testWidgets('带 Plan 目标打开日历时直接选中那一天', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'plan-target',
      now: () => DateTime.utc(2026, 11, 15, 9),
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PlanCalendarView(
            repository: repository,
            goals: const [],
            displayTimeZoneId: 'Etc/UTC',
            now: () => DateTime.utc(2026, 11, 15, 9),
            initialDay: DateTime(2026, 12, 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.textContaining('12月3日 · 0 项安排'), findsOneWidget);
  });
}
