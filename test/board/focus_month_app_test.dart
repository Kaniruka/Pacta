import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_month_page.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/profile/profile_models.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_database.dart';

/// Public App navigation evidence for ticket 12: the Board entry, the two
/// calendars staying independent, pinned order/next task and account/zone
/// lifecycle. All repositories are in-memory; the clock is injected.
void main() {
  var now = DateTime.utc(2026, 11, 12, 10);

  Widget appHost({
    required TaskRepository tasks,
    required FocusRepository focus,
    required ScheduleRepository schedules,
    required ProfileRepository profile,
    AuthRepository? authRepository,
    String user = 'user-a',
  }) {
    return PactaApp(
      authRepository:
          authRepository ?? (FakeAuthRepository()..signedInUser = user),
      taskRepositoryFactory: (_) => tasks,
      focusRepositoryFactory: (_) => focus,
      scheduleRepositoryFactory: (_) => schedules,
      profileRepositoryFactory: (_) => profile,
      displayClock: () => now,
      cloudCheckClock: () => now,
      deviceTimeZoneIdReader: () async => null,
    );
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Widget app, {
    Size size = const Size(1200, 900),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('看板打开月历：真实入口、账号时区与当前月', (tester) async {
    final database = openTestDatabase();
    final focusRemote = InMemoryFocusRemote();
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    final schedules = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    try {
      final goal = await tasks.createGoal(
        const GoalDraft(title: '季度发布', classification: TaskClassification.both),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          classification: TaskClassification.both,
        ),
      );
      await focusRemote.upsertSessions(
        userId: 'user-a',
        sessions: [
          FocusSession(
            id: 'app-entry',
            taskId: task.id,
            mode: FocusChainMode.regular,
            durationSeconds: 780,
            startedAt: DateTime.utc(2026, 11, 12, 2),
            endsAt: DateTime.utc(2026, 11, 12, 2, 13),
            completedAt: DateTime.utc(2026, 11, 12, 2, 13),
            status: FocusSessionStatus.completed,
            effectiveSeconds: 780,
            effectiveIntervals: [
              FocusTimeInterval(
                startedAt: DateTime.utc(2026, 11, 12, 2),
                endedAt: DateTime.utc(2026, 11, 12, 2, 13),
              ),
            ],
            reviewDisposition: FocusRecordDisposition.accepted,
          ),
        ],
      );
      await focus.sync();

      await pumpApp(
        tester,
        appHost(
          tasks: tasks,
          focus: focus,
          schedules: schedules,
          profile: _FixedProfileRepository('Asia/Shanghai'),
        ),
        size: const Size(360, 800),
      );
      expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);

      await tester.tap(find.text('打开月历'));
      await tester.pumpAndSettle();

      expect(find.byType(FocusMonthPage), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('13 分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await schedules.dispose();
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    }
  });

  testWidgets('计划日历完成独立事项不写入专注月历', (tester) async {
    final database = openTestDatabase();
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final schedules = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    try {
      final schedule = await schedules.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 12, 8),
            endsAt: DateTime.utc(2026, 11, 12, 9),
          ),
        ),
      );
      await pumpApp(
        tester,
        appHost(
          tasks: tasks,
          focus: focus,
          schedules: schedules,
          profile: _FixedProfileRepository('Asia/Shanghai'),
        ),
      );

      await tester.tap(find.text('计划'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();

      final card = find.byKey(ValueKey('schedule-card-${schedule.id}'));
      expect(card, findsOneWidget);
      await tester.tap(
        find.descendant(of: card, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();

      final stored = await schedules.getSchedules();
      expect(stored.single.isCompleted, isTrue);
      expect(await focus.getSessions(), isEmpty);

      await tester.tap(find.text('看板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开月历'));
      await tester.pumpAndSettle();
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('本月暂无有效投入。'), findsOneWidget);
      expect(find.textContaining('失败'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await schedules.dispose();
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    }
  });

  testWidgets('看板保持置顶手序与每个目标的下一项任务', (tester) async {
    final database = openTestDatabase();
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final schedules = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    try {
      final reading = await tasks.createGoal(
        const GoalDraft(
          title: '阅读',
          classification: TaskClassification.regular,
        ),
      );
      final writing = await tasks.createGoal(
        const GoalDraft(
          title: '写作',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        reading.id,
        const TaskDraft(
          title: '读一章',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        writing.id,
        const TaskDraft(
          title: '写一段',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.setGoalPinned(reading.id, isPinned: true);
      await tasks.setGoalPinned(writing.id, isPinned: true);
      await tasks.reorderPinnedGoals([writing.id, reading.id]);

      await pumpApp(
        tester,
        appHost(
          tasks: tasks,
          focus: focus,
          schedules: schedules,
          profile: _FixedProfileRepository('Asia/Shanghai'),
        ),
        size: const Size(1440, 1200),
      );

      expect(find.textContaining('下一项：写一段'), findsOneWidget);
      expect(find.textContaining('下一项：读一章'), findsOneWidget);
      expect(
        tester.getRect(find.text('写作')).top,
        lessThan(tester.getRect(find.text('阅读')).top),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await schedules.dispose();
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    }
  });

  testWidgets('切账号后不显示上一账号数字，资料时区迟到不保留旧日分摊', (tester) async {
    final firstDatabase = openTestDatabase();
    final firstFocus = _ZoneScriptedFocusRepository();
    final firstTasks = LocalTaskRepository(
      database: firstDatabase,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final firstSchedules = LocalScheduleRepository(
      database: firstDatabase,
      userId: 'user-a',
      now: () => now,
    );
    addTearDown(firstFocus.disposeControllers);

    final secondTasks = LocalTaskRepository(
      database: firstDatabase,
      userId: 'user-b',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final secondFocus = _SilentFocusRepository();
    final secondSchedules = LocalScheduleRepository(
      database: firstDatabase,
      userId: 'user-b',
      now: () => now,
    );
    addTearDown(secondFocus.disposeControllers);

    try {
      await pumpApp(
        tester,
        appHost(
          tasks: firstTasks,
          focus: firstFocus,
          schedules: firstSchedules,
          profile: _FixedProfileRepository('Asia/Shanghai'),
        ),
        size: const Size(360, 800),
      );
      expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);

      await tester.pumpWidget(
        appHost(
          tasks: secondTasks,
          focus: secondFocus,
          schedules: secondSchedules,
          profile: _FixedProfileRepository('Asia/Shanghai'),
          user: 'user-b',
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('累计有效专注 13分00秒'),
        findsNothing,
        reason: '切账号后等待新投影时，不能继续显示上一账号的数字',
      );

      final profile = _MutableProfileRepository();
      addTearDown(profile.disposeController);
      final zoneFocus = _ZoneScriptedFocusRepository();
      addTearDown(zoneFocus.disposeControllers);
      await tester.pumpWidget(
        appHost(
          tasks: secondTasks,
          focus: zoneFocus,
          schedules: secondSchedules,
          profile: profile,
        ),
      );
      await tester.pump();
      profile.emit('Asia/Shanghai');
      await tester.pumpAndSettle();
      expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);

      profile.emit('America/New_York');
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
        final switched =
            zoneFocus.requestedTimeZoneIds.contains('America/New_York') &&
            find.textContaining('累计有效专注 13分00秒').evaluate().isEmpty;
        if (switched) break;
      }
      expect(zoneFocus.requestedTimeZoneIds, contains('America/New_York'));
      expect(find.textContaining('累计有效专注 13分00秒'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await firstSchedules.dispose();
      await firstTasks.dispose();
      await firstDatabase.close();
      await secondSchedules.dispose();
      await secondTasks.dispose();
    }
  });
}

class _FixedProfileRepository extends UnavailableProfileRepository {
  _FixedProfileRepository(this.timeZoneId);

  final String? timeZoneId;

  @override
  Stream<ProfileAccount> watchProfile() => Stream.value(
    ProfileAccount(userId: 'user-a', displayTimeZoneId: timeZoneId),
  );

  @override
  Future<ProfileAccount> getProfile() async =>
      ProfileAccount(userId: 'user-a', displayTimeZoneId: timeZoneId);
}

class _MutableProfileRepository extends UnavailableProfileRepository {
  final _events = StreamController<String?>.broadcast();
  String? _current;

  void emit(String? timeZoneId) {
    _current = timeZoneId;
    _events.add(timeZoneId);
  }

  @override
  Stream<ProfileAccount> watchProfile() async* {
    yield ProfileAccount(userId: 'user-a', displayTimeZoneId: _current);
    yield* _events.stream.map(
      (timeZoneId) =>
          ProfileAccount(userId: 'user-a', displayTimeZoneId: timeZoneId),
    );
  }

  @override
  Future<ProfileAccount> getProfile() async =>
      ProfileAccount(userId: 'user-a', displayTimeZoneId: _current);

  void disposeController() => unawaited(_events.close());
}

class _ZoneScriptedFocusRepository extends UnavailableFocusRepository {
  final _silent = StreamController<FocusDashboardMetrics>.broadcast();
  final requestedTimeZoneIds = <String>[];

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String timeZoneId,
  }) {
    requestedTimeZoneIds.add(timeZoneId);
    if (timeZoneId != 'Asia/Shanghai') return _silent.stream;
    return Stream.value(
      FocusDashboardMetrics(
        focusProgressSecondsByTask: const {},
        recentActivity: const [],
        totalAcceptedFocusSeconds: 780,
        displayTimeZoneId: timeZoneId,
      ),
    );
  }

  void disposeControllers() => unawaited(_silent.close());
}

class _SilentFocusRepository extends UnavailableFocusRepository {
  final _dashboard = StreamController<FocusDashboardMetrics>.broadcast();

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String timeZoneId,
  }) => _dashboard.stream;

  void disposeControllers() => unawaited(_dashboard.close());
}
