import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_month_page.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/profile/profile_models.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  Widget boardHost({
    required TaskRepository taskRepository,
    required FocusRepository focusRepository,
    required ProfileRepository profileRepository,
    AuthRepository? authRepository,
    String userId = 'user-a',
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          authRepository ?? (FakeAuthRepository()..signedInUser = userId),
        ),
        taskRepositoryFactoryProvider.overrideWithValue((_) => taskRepository),
        focusRepositoryFactoryProvider.overrideWithValue(
          (_) => focusRepository,
        ),
        profileRepositoryFactoryProvider.overrideWithValue(
          (_) => profileRepository,
        ),
      ],
      child: MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: BoardPage(onOpenNationalFocus: () {}, onOpenPlan: () {}),
        ),
      ),
    );
  }

  testWidgets('近期专注卡提供月历入口，按账号时区请求月投影', (tester) async {
    final focus = _RecordingFocusRepository();
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: _FixedProfileRepository('Asia/Shanghai'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('近期专注活动'), findsOneWidget);
    await tester.tap(find.text('打开月历'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusMonthPage), findsOneWidget);
    expect(find.text('专注月历'), findsOneWidget);
    expect(focus.monthTimeZoneIds, ['Asia/Shanghai']);
    expect(focus.monthRequests.single.isUtc, isTrue);
    expect(focus.monthRequests.single.day, 1);
  });

  testWidgets('账号时区为空时月历入口沿统一兜底时区查询', (tester) async {
    final focus = _RecordingFocusRepository();
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: _FixedProfileRepository(null),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开月历'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusMonthPage), findsOneWidget);
    expect(focus.monthTimeZoneIds, ['Etc/UTC']);
  });

  testWidgets('切换仓储实例时不回显上一仓储的近期数字', (tester) async {
    final profile = _FixedProfileRepository('Asia/Shanghai');
    final first = _ScriptedFocusRepository(
      dashboard: FocusDashboardMetrics(
        focusProgressSecondsByTask: const {},
        recentActivity: [
          FocusActivityDay(
            date: DateTime.utc(2026, 11, 12),
            activeSeconds: 780,
          ),
        ],
        totalAcceptedFocusSeconds: 780,
        displayTimeZoneId: 'Asia/Shanghai',
      ),
    );
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: first,
        profileRepository: profile,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);

    final silent = _SilentFocusRepository();
    addTearDown(silent.disposeControllers);
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: silent,
        profileRepository: profile,
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('累计有效专注 13分00秒'),
      findsNothing,
      reason: '等待新仓储的首个投影时，不能继续显示上一仓储的数字',
    );
    expect(
      find.descendant(
        of: find.byType(BoardPage),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('账号时区变化后不保留旧时区的日分摊数字', (tester) async {
    final profile = _MutableProfileRepository();
    final focus = _ZoneScriptedFocusRepository();
    addTearDown(profile.disposeController);
    addTearDown(focus.disposeControllers);
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: profile,
      ),
    );
    await tester.pump();
    profile.emit('Asia/Shanghai');
    await tester.pumpAndSettle();
    expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);

    profile.emit('America/New_York');
    // 资料事件经流送达后，看板才切换到新时区投影；切换完成后新的流仍是
    // 静默的，旧时区的数字必须已经消失。多给一帧让清空后的重建落地。
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump();
      final switched =
          focus.requestedTimeZoneIds.contains('America/New_York') &&
          find.textContaining('累计有效专注 13分00秒').evaluate().isEmpty;
      if (switched) break;
    }
    expect(focus.requestedTimeZoneIds, contains('America/New_York'));
    expect(
      find.textContaining('累计有效专注 13分00秒'),
      findsNothing,
      reason: '换时区后要等待新投影，旧时区的日分摊不能留在屏上',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('投影读取失败时给出可见错误，重试只重建订阅', (tester) async {
    final focus = _FlakyFocusRepository();
    final tasks = _CountingTaskRepository();
    await tester.pumpWidget(
      boardHost(
        taskRepository: tasks,
        focusRepository: focus,
        profileRepository: _FixedProfileRepository('Asia/Shanghai'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时不能读取专注投影。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BoardPage),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: '读取失败不能一直显示成加载中',
    );
    final failedCalls = focus.dashboardCalls;
    final goalCalls = tasks.goalsCalls;

    focus.failing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(focus.dashboardCalls, greaterThan(failedCalls));
    expect(tasks.goalsCalls, greaterThan(goalCalls), reason: '重试重新读取整块投影');
    expect(find.text('暂时不能读取专注投影。'), findsNothing);
    expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('目标列表读取失败时不渲染成没有置顶目标', (tester) async {
    final tasks = _FailingGoalsTaskRepository();
    await tester.pumpWidget(
      boardHost(
        taskRepository: tasks,
        focusRepository: _RecordingFocusRepository(),
        profileRepository: _FixedProfileRepository('Asia/Shanghai'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时不能读取目标列表。'), findsOneWidget);
    expect(find.text('还没有置顶目标'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('账号变化时月历路由退出，不保留上一个账号的月份', (tester) async {
    final auth = _MutableAuthRepository('user-a');
    addTearDown(auth.disposeEvents);
    final focus = _RecordingFocusRepository();
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: _FixedProfileRepository('Asia/Shanghai'),
        authRepository: auth,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开月历'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusMonthPage), findsOneWidget);

    auth.switchUser('user-b');
    await tester.pumpAndSettle();

    expect(find.byType(FocusMonthPage), findsNothing);
    expect(find.byType(BoardPage), findsOneWidget);
  });
}

class _MutableAuthRepository extends FakeAuthRepository {
  _MutableAuthRepository(String user) {
    signedInUser = user;
  }

  final _events = StreamController<String?>.broadcast();

  @override
  Stream<String?> get authState async* {
    yield signedInUser;
    yield* _events.stream;
  }

  void switchUser(String? user) {
    signedInUser = user;
    _events.add(user);
  }

  void disposeEvents() => unawaited(_events.close());
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

class _RecordingFocusRepository extends UnavailableFocusRepository {
  final monthTimeZoneIds = <String>[];
  final monthRequests = <DateTime>[];
  final dashboardZones = <String>[];
  var dashboardCalls = 0;

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String timeZoneId,
  }) {
    dashboardCalls += 1;
    dashboardZones.add(timeZoneId);
    return Stream.value(
      FocusDashboardMetrics(
        focusProgressSecondsByTask: const {},
        recentActivity: const [],
        totalAcceptedFocusSeconds: 0,
        displayTimeZoneId: timeZoneId,
      ),
    );
  }

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    monthTimeZoneIds.add(timeZoneId);
    monthRequests.add(month);
    return Stream.value(_emptyMonthMetrics(timeZoneId, month));
  }
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
        recentActivity: [
          FocusActivityDay(
            date: DateTime.utc(2026, 11, 12),
            activeSeconds: 780,
          ),
        ],
        totalAcceptedFocusSeconds: 780,
        displayTimeZoneId: timeZoneId,
      ),
    );
  }

  void disposeControllers() => unawaited(_silent.close());
}

class _ScriptedFocusRepository extends UnavailableFocusRepository {
  _ScriptedFocusRepository({required this.dashboard});

  final FocusDashboardMetrics dashboard;

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String timeZoneId,
  }) => Stream.value(dashboard);
}

class _SilentFocusRepository extends UnavailableFocusRepository {
  final _dashboard = StreamController<FocusDashboardMetrics>.broadcast();
  final _month = StreamController<FocusMonthMetrics>.broadcast();

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String timeZoneId,
  }) => _dashboard.stream;

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) => _month.stream;

  void disposeControllers() {
    unawaited(_dashboard.close());
    unawaited(_month.close());
  }
}

class _FlakyFocusRepository extends UnavailableFocusRepository {
  var failing = true;
  var dashboardCalls = 0;

  @override
  Stream<FocusDashboardMetrics> watchDashboardMetrics({
    required String timeZoneId,
  }) {
    dashboardCalls += 1;
    if (failing) {
      return Stream<FocusDashboardMetrics>.error(StateError('投影读取失败'));
    }
    return Stream.value(
      FocusDashboardMetrics(
        focusProgressSecondsByTask: const {},
        recentActivity: [
          FocusActivityDay(
            date: DateTime.utc(2026, 11, 12),
            activeSeconds: 780,
          ),
        ],
        totalAcceptedFocusSeconds: 780,
        displayTimeZoneId: timeZoneId,
      ),
    );
  }
}

class _FailingGoalsTaskRepository extends UnavailableTaskRepository {
  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) =>
      Stream<List<Goal>>.error(StateError('目标读取失败'));
}

class _CountingTaskRepository extends UnavailableTaskRepository {
  var goalsCalls = 0;

  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) {
    goalsCalls += 1;
    return super.watchGoals(includeDeleted: includeDeleted);
  }
}

FocusMonthMetrics _emptyMonthMetrics(String timeZoneId, DateTime month) {
  final start = DateTime.utc(month.year, month.month);
  final count = DateTime.utc(start.year, start.month + 1, 0).day;
  return FocusMonthMetrics(
    displayTimeZoneId: timeZoneId,
    month: start,
    days: [
      for (var day = 1; day <= count; day++)
        FocusActivityDay(
          date: DateTime.utc(start.year, start.month, day),
          activeSeconds: 0,
        ),
    ],
    totalActiveSeconds: 0,
    activeDayCount: 0,
  );
}
