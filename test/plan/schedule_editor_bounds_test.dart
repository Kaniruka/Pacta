import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// 票 07 编辑器/改期回归：日历边界与"已删除任务"链接。
///
/// 期望值一律写死（当地公历日期或 UTC 字面量），不复用实现里的换算。
const _user = 'schedule-editor-bounds';
const _newYork = 'America/New_York';
final _fixtureNow = DateTime.utc(2026, 3, 1, 12);

class _Fixture {
  _Fixture(this.database, this.tasks, this.schedules, this.focus, this.tree);

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalScheduleRepository schedules;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository tree;

  static _Fixture create() {
    final database = PactaDatabase(NativeDatabase.memory());
    return _Fixture(
      database,
      LocalTaskRepository(
        database: database,
        userId: _user,
        remote: InMemoryTaskRemote(),
        now: () => _fixtureNow,
      ),
      LocalScheduleRepository(
        database: database,
        userId: _user,
        now: () => _fixtureNow,
      ),
      LocalFocusRepository(
        database: database,
        userId: _user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => _fixtureNow,
      ),
      LocalNationalFocusRepository(
        database: database,
        userId: _user,
        cloudSyncEnabled: false,
        now: () => _fixtureNow,
      ),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await schedules.dispose();
    await focus.dispose();
    await tree.dispose();
    await database.close();
  }
}

/// 只做一件事的宿主：真实对话框、真实主题。
///
/// [inspect] 在保存前检查打开着的对话框；返回的是编辑器**实际交出的**窗口，
/// 因此断言的是编辑器换算本身，而不是数据库里原来的那一行（不会自证）。
Future<ScheduleEditorResult?> _runEditor(
  WidgetTester tester, {
  List<Goal> goals = const [],
  Schedule? schedule,
  DateTime? initialDay,
  String? newTitle,
  bool toggleAllDay = false,
  void Function()? inspect,
}) async {
  ScheduleEditorResult? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showScheduleEditor(
                  context,
                  goals: goals,
                  displayTimeZoneId: _newYork,
                  initialDay: initialDay ?? DateTime(2026, 3, 14),
                  initial: schedule,
                  now: () => _fixtureNow,
                );
              },
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
  inspect?.call();
  if (toggleAllDay) {
    await tester.tap(find.text('全天'));
    await tester.pumpAndSettle();
  }
  if (newTitle != null) {
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '名称',
      ),
      newTitle,
    );
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('全天安排按公历日期往返：负时区不会挪到前一天', (tester) async {
    final fixture = _Fixture.create();
    try {
      final created = await fixture.schedules.createSchedule(
        ScheduleDraft(
          title: '纽约三天工作坊',
          window: ScheduleWindow.allDayDates(
            startDate: '2026-03-14',
            endDateExclusive: '2026-03-16',
          ),
        ),
      );
      // 全天窗口按约定以 UTC 午夜承载公历日期。
      expect(created.startsAt, DateTime.utc(2026, 3, 14));
      expect(created.endsAt, DateTime.utc(2026, 3, 16));

      final result = await _runEditor(
        tester,
        goals: const [],
        schedule: created,
        inspect: () {
          // 负时区（纽约）下仍是 14 日到 16 日，不是 13 日。
          expect(find.text('开始 2026-03-14'), findsOneWidget);
          expect(find.text('结束（不含） 2026-03-16'), findsOneWidget);
        },
      );
      final window = result!.draft.window;
      expect(window.allDay, isTrue);
      expect(window.allDayStartDate, '2026-03-14');
      expect(window.allDayEndDateExclusive, '2026-03-16');
      expect(window.startsAt, DateTime.utc(2026, 3, 14));
      expect(window.endsAt, DateTime.utc(2026, 3, 16));
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('多天定时安排只改标题：两端边界原样保留', (tester) async {
    final fixture = _Fixture.create();
    try {
      // 纽约 3/9 09:00 EDT = 13:00Z；3/11 17:00 EDT = 21:00Z。
      final created = await fixture.schedules.createSchedule(
        ScheduleDraft(
          title: '跨城评审',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 3, 9, 13),
            endsAt: DateTime.utc(2026, 3, 11, 21),
          ),
        ),
      );
      final result = await _runEditor(
        tester,
        goals: const [],
        schedule: created,
        newTitle: '跨城评审（改期前）',
        inspect: () {
          expect(find.text('开始 2026-03-09'), findsOneWidget);
          expect(find.text('结束 2026-03-11'), findsOneWidget);
        },
      );
      expect(result!.draft.title, '跨城评审（改期前）');
      final window = result.draft.window;
      expect(window.allDay, isFalse);
      expect(window.startsAt, DateTime.utc(2026, 3, 9, 13));
      expect(window.endsAt, DateTime.utc(2026, 3, 11, 21));
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('新建安排切到全天：默认就是一天，不需要额外改结束日期', (tester) async {
    final result = await _runEditor(
      tester,
      initialDay: DateTime(2026, 3, 14),
      newTitle: '取快递',
      inspect: () {
        expect(find.text('开始 2026-03-14'), findsOneWidget);
        expect(find.text('结束 2026-03-14'), findsOneWidget);
      },
      toggleAllDay: true,
    );
    final window = result!.draft.window;
    expect(window.allDay, isTrue);
    expect(window.allDayStartDate, '2026-03-14');
    expect(window.allDayEndDateExclusive, '2026-03-15');
    expect(window.startsAt, DateTime.utc(2026, 3, 14));
    expect(window.endsAt, DateTime.utc(2026, 3, 15));
  });

  testWidgets('360 宽真实 MiSans 字体下安排编辑器与下拉都不溢出', (tester) async {
    // Windows 实机在 360 宽 + MiSans 下暴露过 1.6px 的水平溢出：
    // 下拉的选中项按最小宽度排布，真实字体比测试字体略宽就撑破一行。
    final fontLoader = FontLoader('MiSans')
      ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));
    await fontLoader.load();

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showScheduleEditor(
                  context,
                  goals: const [],
                  displayTimeZoneId: 'Etc/UTC',
                  initialDay: DateTime(2026, 3, 14),
                  now: () => _fixtureNow,
                ),
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    expect(find.text('独立事项（不关联任务）'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '360 宽 + MiSans 下不应溢出');

    // 打开任务下拉，菜单项同样不能溢出。
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    expect(find.text('独立事项（不关联任务）'), findsWidgets);
    expect(tester.takeException(), isNull, reason: '下拉菜单在 360 宽下不应溢出');
  });

  testWidgets('跨夜结束按当地日历日推进：春季 DST 缺口', (tester) async {
    // 纽约 2026-03-07 22:00 EST = 03-08T03:00Z；次日 06:00 EDT = 03-08T10:00Z。
    // 用 UTC +24h 会得到 03-08T11:00Z，正好差一小时。
    final window = buildScheduleWindow(
      displayTimeZoneId: _newYork,
      bounds: ScheduleCalendarBounds(
        allDay: false,
        startDay: DateTime(2026, 3, 7),
        endDay: DateTime(2026, 3, 7),
        start: const TimeOfDay(hour: 22, minute: 0),
        end: const TimeOfDay(hour: 6, minute: 0),
      ),
    );
    expect(window.startsAt, DateTime.utc(2026, 3, 8, 3));
    expect(window.endsAt, DateTime.utc(2026, 3, 8, 10));
  });

  testWidgets('跨夜结束按当地日历日推进：秋季 DST 回拨', (tester) async {
    // 纽约 2026-10-31 23:30 EDT = 11-01T03:30Z；
    // 次日 01:30 落在回拨的重复小时，取较早一次（EDT）= 11-01T05:30Z。
    final window = buildScheduleWindow(
      displayTimeZoneId: _newYork,
      bounds: ScheduleCalendarBounds(
        allDay: false,
        startDay: DateTime(2026, 10, 31),
        endDay: DateTime(2026, 10, 31),
        start: const TimeOfDay(hour: 23, minute: 30),
        end: const TimeOfDay(hour: 1, minute: 30),
      ),
    );
    expect(window.startsAt, DateTime.utc(2026, 11, 1, 3, 30));
    expect(window.endsAt, DateTime.utc(2026, 11, 1, 5, 30));
  });

  testWidgets('已删除任务的既有链接保留可读，新链接仍被拒绝', (tester) async {
    final fixture = _Fixture.create();
    try {
      final goal = await fixture.tasks.createGoal(
        const GoalDraft(
          title: '写作',
          classification: TaskClassification.regular,
        ),
      );
      final task = await fixture.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写提纲',
          classification: TaskClassification.regular,
        ),
      );
      final linked = await fixture.schedules.createSchedule(
        ScheduleDraft(
          title: '上午整理',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 3, 14, 13),
            endsAt: DateTime.utc(2026, 3, 14, 14),
          ),
          taskId: task.id,
        ),
      );
      await fixture.tasks.deleteTask(task.id);

      // 仓储：未改动的链接保留身份，不被"任务已删除"拒绝。
      final updated = await fixture.schedules.updateSchedule(
        linked.id,
        ScheduleDraft(
          title: '上午整理（改名）',
          window: ScheduleWindow.timed(
            startsAt: linked.startsAt,
            endsAt: linked.endsAt,
          ),
          taskId: task.id,
        ),
      );
      expect(updated.taskId, task.id);

      // 编辑器：拉出记录带墓碑的目标列表，下拉里显示可读的已删除标签。
      final goals = await fixture.tasks.getGoals(includeDeleted: true);
      final result = await _runEditor(
        tester,
        goals: goals,
        schedule: updated,
        inspect: () {
          expect(tester.takeException(), isNull, reason: '既有链接不能让下拉断言失败');
          expect(find.text('已删除的任务：写提纲'), findsOneWidget);
        },
      );
      expect(result!.draft.taskId, task.id, reason: '只改名称时链接身份必须保留');
      expect((await fixture.schedules.getSchedules()).first.taskId, task.id);

      // 新建链接到已删除任务仍然整体拒绝。
      final standalone = await fixture.schedules.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 3, 15, 13),
            endsAt: DateTime.utc(2026, 3, 15, 14),
          ),
        ),
      );
      await expectLater(
        fixture.schedules.updateSchedule(
          standalone.id,
          ScheduleDraft(
            title: '取快递',
            window: ScheduleWindow.timed(
              startsAt: standalone.startsAt,
              endsAt: standalone.endsAt,
            ),
            taskId: task.id,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        fixture.schedules.createSchedule(
          ScheduleDraft(
            title: '新安排',
            window: ScheduleWindow.timed(
              startsAt: DateTime.utc(2026, 3, 16, 13),
              endsAt: DateTime.utc(2026, 3, 16, 14),
            ),
            taskId: task.id,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('计划日历把已删除任务显示为可读标签', (tester) async {
    final fixture = _Fixture.create();
    try {
      final goal = await fixture.tasks.createGoal(
        const GoalDraft(
          title: '写作',
          classification: TaskClassification.regular,
        ),
      );
      final task = await fixture.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写提纲',
          classification: TaskClassification.regular,
        ),
      );
      final today = DateTime.now();
      await fixture.schedules.createSchedule(
        ScheduleDraft(
          title: '上午整理',
          window: ScheduleWindow.timed(
            startsAt: DateTime(today.year, today.month, today.day, 9),
            endsAt: DateTime(today.year, today.month, today.day, 10),
          ),
          taskId: task.id,
        ),
      );
      await fixture.tasks.deleteTask(task.id);

      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = _user,
          taskRepositoryFactory: (_) => fixture.tasks,
          focusRepositoryFactory: (_) => fixture.focus,
          nationalFocusRepositoryFactory: (_) => fixture.tree,
          scheduleRepositoryFactory: (_) => fixture.schedules,
        ),
      );
      await tester.pumpAndSettle();
      await openPlan(tester);
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      expect(find.text('上午整理'), findsOneWidget);
      expect(find.text('任务：已删除的任务：写提纲'), findsOneWidget);
    } finally {
      await fixture.dispose(tester);
    }
  });
}
