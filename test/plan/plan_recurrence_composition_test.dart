import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

const _user = 'plan-recurrence-composition';

class _Harness {
  _Harness(this.database, {required this.clock});

  final PactaDatabase database;
  final DateTime Function() clock;
  late LocalTaskRepository tasks;
  late final LocalScheduleRepository schedules = LocalScheduleRepository(
    database: database,
    userId: _user,
    now: clock,
  );

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        scheduleRepositoryFactory: (_) => schedules,
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

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _openCreateDialog(WidgetTester tester) async {
  await tester.tap(find.text('添加事项'));
  await tester.pumpAndSettle();
}

Future<ScheduleSeries> _seedDailySeries(
  _Harness harness, {
  String title = '每日站会',
  String? taskId,
}) => harness.schedules.createRecurringSchedule(
  draft: ScheduleDraft(
    title: title,
    window: ScheduleWindow.timed(
      startsAt: DateTime.utc(2026, 11, 13, 9),
      endsAt: DateTime.utc(2026, 11, 13, 10),
    ),
    taskId: taskId,
  ),
  repeat: const ScheduleRepeatSpec(frequency: ScheduleRepeatFrequency.daily),
  timeZoneId: 'Etc/UTC',
);

void main() {
  testWidgets('新建重复安排：每周指定星期 + 结束日期写入规则并生成实例', (tester) async {
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: () => DateTime.utc(2026, 11, 15, 9),
    );
    try {
      await harness.pump(tester);
      await _openCalendar(tester);
      await _openCreateDialog(tester);

      await tester.enterText(_field('名称'), '每周复盘');
      await tester.ensureVisible(find.text('重复'));
      await tester.tap(find.text('重复'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('每周'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周三'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('不结束'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('2026-11-20'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final rules = await harness.schedules.getRecurrenceRules();
      expect(rules, hasLength(1));
      expect(rules.single.frequency, ScheduleRepeatFrequency.weekly);
      expect(rules.single.weekdays, {DateTime.monday, DateTime.wednesday});
      expect(rules.single.endDate, '2026-11-20');

      final instances = await harness.schedules.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 22),
      );
      expect(
        [for (final instance in instances) instance.recurrenceDate],
        ['2026-11-16', '2026-11-18'],
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('既有重复项编辑只提供范围选择，仅本次不改规则并保留墓碑任务链接', (tester) async {
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: () => DateTime.utc(2026, 11, 15, 9),
    );
    try {
      await harness.pump(tester);
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '写作',
          classification: TaskClassification.regular,
        ),
      );
      final task = await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写周报',
          classification: TaskClassification.regular,
        ),
      );
      await _seedDailySeries(harness, taskId: task.id);
      await tester.pumpAndSettle();
      // 任务随后被删除成墓碑；未改动的链接必须仍可编辑。
      await harness.tasks.deleteTask(task.id);
      await tester.pumpAndSettle();
      await _openCalendar(tester);

      final before = (await harness.schedules.getRecurrenceRules()).single;

      await tester.tap(find.text('每日站会'));
      await tester.pumpAndSettle();

      expect(find.text('不重复，只发生这一次'), findsNothing);
      expect(find.text('仅本次'), findsOneWidget);
      expect(find.text('本次及以后'), findsOneWidget);
      expect(find.text('已删除的任务：写周报'), findsWidgets);

      await tester.enterText(_field('名称'), '每日站会（仅本次）');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final after = (await harness.schedules.getRecurrenceRules()).single;
      expect(after.id, before.id);
      expect(after.endDate, before.endDate);
      expect(after.title, before.title);

      final instances = await harness.schedules.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 18),
      );
      final today = instances.singleWhere(
        (instance) => instance.recurrenceDate == '2026-11-15',
      );
      expect(today.title, '每日站会（仅本次）');
      expect(today.isRecurrenceException, isTrue);
      expect(today.taskId, task.id);
      expect(
        instances
            .singleWhere((instance) => instance.recurrenceDate == '2026-11-16')
            .title,
        '每日站会',
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('本次及以后截断规则：过去实例保留，后续实例采用新内容', (tester) async {
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: () => DateTime.utc(2026, 11, 15, 9),
    );
    try {
      await harness.pump(tester);
      await _seedDailySeries(harness);
      await tester.pumpAndSettle();
      await _openCalendar(tester);

      await tester.tap(find.text('每日站会'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本次及以后'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('名称'), '每日站会（新规则）');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final instances = await harness.schedules.getSchedules(
        from: DateTime.utc(2026, 11, 13),
        to: DateTime.utc(2026, 11, 19),
      );
      String titleOn(String date) => instances
          .singleWhere((instance) => instance.recurrenceDate == date)
          .title;
      expect(titleOn('2026-11-13'), '每日站会');
      expect(titleOn('2026-11-14'), '每日站会');
      expect(titleOn('2026-11-15'), '每日站会（新规则）');
      expect(titleOn('2026-11-16'), '每日站会（新规则）');

      final rules = await harness.schedules.getRecurrenceRules();
      expect(rules, hasLength(2));
      expect(
        rules.singleWhere((rule) => rule.endDate != null).endDate,
        '2026-11-14',
      );
      final replacement = rules.singleWhere((rule) => rule.endDate == null);
      expect(replacement.firstDate, '2026-11-15');
      expect(replacement.title, '每日站会（新规则）');
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('重复项改期先选范围，仅本次留下例外而规则不变', (tester) async {
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: () => DateTime.utc(2026, 11, 15, 9),
    );
    try {
      await harness.pump(tester);
      await _seedDailySeries(harness);
      await tester.pumpAndSettle();
      await _openCalendar(tester);
      final ruleBefore = (await harness.schedules.getRecurrenceRules()).single;

      await tester.tap(find.byTooltip('安排操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('改期'));
      await tester.pumpAndSettle();

      expect(find.text('修改这条重复安排'), findsOneWidget);
      expect(find.text('这次修改要影响哪些实例？'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final instances = await harness.schedules.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 17),
      );
      final today = instances.singleWhere(
        (instance) => instance.recurrenceDate == '2026-11-15',
      );
      expect(today.isRecurrenceException, isTrue);
      final ruleAfter = (await harness.schedules.getRecurrenceRules()).single;
      expect(ruleAfter.id, ruleBefore.id);
      expect(ruleAfter.endDate, ruleBefore.endDate);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('非重复安排的提醒可以显式清除', (tester) async {
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: () => DateTime.utc(2026, 11, 15, 9),
    );
    try {
      await harness.pump(tester);
      final created = await harness.schedules.createSchedule(
        ScheduleDraft(
          title: '整理资料',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 15, 9),
            endsAt: DateTime.utc(2026, 11, 15, 10),
          ),
        ),
      );
      await harness.schedules.setScheduleReminder(
        created.id,
        minutesBefore: 10,
      );
      await tester.pumpAndSettle();
      await _openCalendar(tester);

      expect(find.text('提前 10 分钟提醒'), findsOneWidget);
      await tester.tap(find.text('整理资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不提醒').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final updated = (await harness.schedules.getSchedules()).single;
      expect(updated.reminderMinutesBefore, isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
