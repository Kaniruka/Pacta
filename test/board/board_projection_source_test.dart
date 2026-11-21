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

/// 看板融合卡片的订阅契约：账号时区门禁、换仓储/换时区清空旧投影、
/// 失败可见与只读重试、账号变化退出月历路由。
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
        // 固定看板“今天”，日期详情与热力档位才有确定答案。
        displayClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 12, 10),
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

  testWidgets('融合卡片提供月历入口，按账号时区请求月投影', (tester) async {
    final focus = _RecordingFocusRepository();
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: _FixedProfileRepository('Asia/Shanghai'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('专注与国策'), findsOneWidget);
    // 完整年月只在热力月历的切换器里出现，卡片头不再重复一枚月份按钮。
    expect(find.text('2026年11月'), findsOneWidget);
    expect(focus.monthTimeZoneIds, ['Asia/Shanghai']);
    expect(focus.monthRequests.single.isUtc, isTrue);
    expect(focus.monthRequests.single.day, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('board-focus-open-month')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-focus-open-month')));
    await tester.pumpAndSettle();

    expect(find.byType(FocusMonthPage), findsOneWidget);
    expect(find.text('专注月历'), findsOneWidget);
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
    // 月历入口在「日期详情」里（卡片底部），先滚进视口再点。
    await tester.ensureVisible(
      find.byKey(const ValueKey('board-focus-open-month')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-focus-open-month')));
    await tester.pumpAndSettle();

    expect(find.byType(FocusMonthPage), findsOneWidget);
    expect(focus.monthTimeZoneIds.first, 'Etc/UTC');
  });

  testWidgets('切换仓储实例时不回显上一仓储的日期详情数字', (tester) async {
    final profile = _FixedProfileRepository('Asia/Shanghai');
    final first = _ScriptedFocusRepository(
      month: _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 780}),
    );
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: first,
        profileRepository: profile,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('13分00秒'), findsOneWidget);

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
      find.text('13分00秒'),
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
    expect(find.text('13分00秒'), findsOneWidget);

    profile.emit('America/New_York');
    // 资料事件经流送达后，卡片才切换到新时区投影；切换完成后新的流仍是
    // 静默的，旧时区的数字必须已经消失。多给一帧让清空后的重建落地。
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump();
      final switched =
          focus.requestedTimeZoneIds.contains('America/New_York') &&
          find.text('13分00秒').evaluate().isEmpty;
      if (switched) break;
    }
    expect(focus.requestedTimeZoneIds, contains('America/New_York'));
    expect(
      find.text('13分00秒'),
      findsNothing,
      reason: '换时区后要等待新投影，旧时区的日分摊不能留在屏上',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('切月后按新月份重新查询并清空旧数字', (tester) async {
    final focus = _DeferredFocusRepository();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: _FixedProfileRepository('Asia/Shanghai'),
      ),
    );
    await tester.pump();
    await tester.pump();
    focus.last.controller.add(
      _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 780}),
    );
    await tester.pumpAndSettle();
    expect(find.text('13分00秒'), findsOneWidget);
    expect(focus.requests, hasLength(1));

    await tester.ensureVisible(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下个月'));
    await tester.pump();
    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.text('13分00秒'), findsNothing);
    expect(focus.requests, hasLength(2));
    expect(focus.last.month, DateTime.utc(2026, 12));

    focus.last.controller.add(
      _monthMetrics(month: DateTime.utc(2026, 12), seconds: {3: 60}),
    );
    await tester.pumpAndSettle();
    expect(find.text('1分00秒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('账号时区解析前不查询投影，也不画兜底时区的数字', (tester) async {
    final profile = _DeferredProfileRepository();
    final focus = _RecordingFocusRepository();
    addTearDown(profile.disposeController);
    await tester.pumpWidget(
      boardHost(
        taskRepository: const UnavailableTaskRepository(),
        focusRepository: focus,
        profileRepository: profile,
      ),
    );
    await tester.pump();

    expect(focus.monthRequests, isEmpty, reason: '时区未知时不应发起投影查询');
    expect(find.text('月份待确认'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BoardPage),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsWidgets,
    );

    profile.emit('Asia/Shanghai');
    await tester.pumpAndSettle();
    expect(focus.monthTimeZoneIds, ['Asia/Shanghai']);
    expect(find.text('2026年11月'), findsOneWidget);
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
    final failedCalls = focus.monthCalls;
    final goalCalls = tasks.goalsCalls;

    focus.failing = false;
    // 日期详情也有一个只读重试：这里按 Key 精确点热力区那一颗。
    final heatRetry = find.byKey(const ValueKey('board-focus-heat-retry'));
    await tester.ensureVisible(heatRetry);
    await tester.pumpAndSettle();
    await tester.tap(heatRetry);
    await tester.pumpAndSettle();

    expect(focus.monthCalls, greaterThan(failedCalls));
    expect(tasks.goalsCalls, greaterThan(goalCalls), reason: '重试重新读取整块投影');
    expect(find.text('暂时不能读取专注投影。'), findsNothing);
    expect(find.text('13分00秒'), findsOneWidget);
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

    // 读取失败必须可见，且绝不能被渲染成“还没有置顶目标”。
    expect(find.text('暂时不能读取目标列表。'), findsOneWidget);
    expect(find.text('置顶目标'), findsOneWidget);
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('board-focus-open-month')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-focus-open-month')));
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

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    monthTimeZoneIds.add(timeZoneId);
    monthRequests.add(month);
    return Stream.value(_monthMetrics(month: month));
  }
}

class _DeferredProfileRepository extends UnavailableProfileRepository {
  final _events = StreamController<String?>.broadcast();
  String? _current;

  void emit(String? timeZoneId) {
    _current = timeZoneId;
    _events.add(timeZoneId);
  }

  @override
  Stream<ProfileAccount> watchProfile() => _events.stream.map(
    (timeZoneId) =>
        ProfileAccount(userId: 'user-a', displayTimeZoneId: timeZoneId),
  );

  @override
  Future<ProfileAccount> getProfile() async =>
      ProfileAccount(userId: 'user-a', displayTimeZoneId: _current);

  void disposeController() => unawaited(_events.close());
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
  final _silent = StreamController<FocusMonthMetrics>.broadcast();
  final requestedTimeZoneIds = <String>[];

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    requestedTimeZoneIds.add(timeZoneId);
    if (timeZoneId != 'Asia/Shanghai') return _silent.stream;
    return Stream.value(
      _monthMetrics(month: month, seconds: {12: 780}, timeZoneId: timeZoneId),
    );
  }

  void disposeControllers() => unawaited(_silent.close());
}

class _ScriptedFocusRepository extends UnavailableFocusRepository {
  _ScriptedFocusRepository({required this.month});

  final FocusMonthMetrics month;

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) => Stream.value(this.month);
}

class _SilentFocusRepository extends UnavailableFocusRepository {
  final _month = StreamController<FocusMonthMetrics>.broadcast();

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) => _month.stream;

  void disposeControllers() => unawaited(_month.close());
}

class _FlakyFocusRepository extends UnavailableFocusRepository {
  var failing = true;
  var monthCalls = 0;

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    monthCalls += 1;
    if (failing) {
      return Stream<FocusMonthMetrics>.error(StateError('投影读取失败'));
    }
    return Stream.value(
      _monthMetrics(month: month, seconds: {12: 780}, timeZoneId: timeZoneId),
    );
  }
}

class _DeferredFocusRepository extends UnavailableFocusRepository {
  final requests = <_MonthRequest>[];

  _MonthRequest get last => requests.last;

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    final request = _MonthRequest(
      timeZoneId: timeZoneId,
      month: DateTime.utc(month.year, month.month),
      controller: StreamController<FocusMonthMetrics>(),
    );
    requests.add(request);
    return request.controller.stream;
  }

  @override
  Future<void> dispose() async {
    for (final request in requests) {
      await request.controller.close();
    }
  }
}

class _MonthRequest {
  _MonthRequest({
    required this.timeZoneId,
    required this.month,
    required this.controller,
  });

  final String timeZoneId;
  final DateTime month;
  final StreamController<FocusMonthMetrics> controller;
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

FocusMonthMetrics _monthMetrics({
  required DateTime month,
  Map<int, int> seconds = const {},
  String timeZoneId = 'Asia/Shanghai',
}) {
  final start = DateTime.utc(month.year, month.month);
  final count = DateTime.utc(start.year, start.month + 1, 0).day;
  return FocusMonthMetrics(
    displayTimeZoneId: timeZoneId,
    month: start,
    days: [
      for (var day = 1; day <= count; day++)
        FocusActivityDay(
          date: DateTime.utc(start.year, start.month, day),
          activeSeconds: seconds[day] ?? 0,
        ),
    ],
    totalActiveSeconds: seconds.values.fold(0, (sum, value) => sum + value),
    activeDayCount: seconds.values.where((value) => value > 0).length,
  );
}
