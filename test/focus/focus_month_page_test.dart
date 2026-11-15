import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_month_page.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote taskRemote;
  late InMemoryFocusRemote focusRemote;
  late LocalTaskRepository taskRepository;
  late LocalFocusRepository focusRepository;
  var now = DateTime.utc(2026, 11, 20, 8);

  setUp(() {
    now = DateTime.utc(2026, 11, 20, 8);
    database = PactaDatabase(NativeDatabase.memory());
    taskRemote = InMemoryTaskRemote();
    focusRemote = InMemoryFocusRemote();
    taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: taskRemote,
      now: () => now,
    );
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
  });

  /// Unmount the page first: it keeps a live projection subscription, and a
  /// drift database cannot close while that stream is still listened to.
  Future<void> withFixture(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await focusRepository.dispose();
      await taskRepository.dispose();
      await database.close();
    }
  }

  /// Repository setup runs inside [WidgetTester.runAsync]: the in-memory
  /// database and the whole-account sync use real I/O, which a fake-async
  /// widget test never advances on its own.
  Future<Task> createTask(WidgetTester tester) async {
    late Task task;
    await tester.runAsync(() async {
      final goal = await taskRepository.createGoal(
        const GoalDraft(title: '本周工作', classification: TaskClassification.both),
      );
      task = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          classification: TaskClassification.both,
        ),
      );
    });
    return task;
  }

  Future<void> seed(
    WidgetTester tester,
    Task task,
    Map<DateTime, int> sessions,
  ) => tester.runAsync(() async {
    await focusRemote.upsertSessions(
      userId: 'user-a',
      sessions: [
        for (final entry in sessions.entries)
          FocusSession(
            id: 'session-${entry.key.toIso8601String()}',
            taskId: task.id,
            mode: FocusChainMode.regular,
            durationSeconds: entry.value,
            startedAt: entry.key,
            endsAt: entry.key.add(Duration(seconds: entry.value)),
            status: FocusSessionStatus.completed,
            completedAt: entry.key.add(Duration(seconds: entry.value)),
            effectiveSeconds: entry.value,
            effectiveIntervals: [
              FocusTimeInterval(
                startedAt: entry.key,
                endedAt: entry.key.add(Duration(seconds: entry.value)),
              ),
            ],
            reviewDisposition: FocusRecordDisposition.accepted,
          ),
      ],
    );
    await focusRepository.sync();
  });

  Widget host({
    required FocusRepository repository,
    Stream<String?> Function()? accountTimeZoneIds,
    DateTime? initialMonth,
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: pactaTheme(brightness),
      home: FocusMonthPage(
        repository: repository,
        accountTimeZoneIds:
            accountTimeZoneIds ?? () => Stream<String?>.value('Asia/Shanghai'),
        initialMonth: initialMonth ?? DateTime(2026, 11),
        now: () => now,
      ),
    );
  }

  testWidgets(
    '月历显示本月合计、日期标记与选中日时长',
    (tester) => withFixture(tester, () async {
      final task = await createTask(tester);
      await seed(tester, task, {
        DateTime.utc(2026, 11, 3, 2): 45 * 60,
        DateTime.utc(2026, 11, 12, 2): 45 * 60,
      });

      await tester.pumpWidget(host(repository: focusRepository));
      await tester.pumpAndSettle();

      expect(find.text('专注月历'), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('本月有效投入'), findsOneWidget);
      expect(find.text('1 小时 30 分钟'), findsOneWidget);
      expect(find.text('有投入的天数 2 天'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('focus-month-day-12')));
      await tester.pumpAndSettle();

      expect(find.text('11月12日'), findsOneWidget);
      expect(find.text('有效投入 45 分钟'), findsOneWidget);
      expect(find.text('1 小时 30 分钟'), findsNothing);
    }),
  );

  testWidgets(
    '空白日与空月份只表达零有效投入，不出现失败或断链语言',
    (tester) => withFixture(tester, () async {
      await tester.pumpWidget(host(repository: focusRepository));
      await tester.pumpAndSettle();

      expect(find.text('本月暂无有效投入。'), findsOneWidget);
      expect(find.textContaining('失败'), findsNothing);
      expect(find.textContaining('断链'), findsNothing);
      expect(find.textContaining('未达标'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('focus-month-day-5')));
      await tester.pumpAndSettle();
      expect(find.text('11月5日'), findsOneWidget);
      expect(find.text('这一天没有有效投入。'), findsOneWidget);
      expect(find.textContaining('失败'), findsNothing);
    }),
  );

  testWidgets(
    '切换月份显示加载态且不回显上个月数据',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(host(repository: repository));
      await tester.pump();
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {3: 45 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('45 分钟'), findsOneWidget);

      await tester.tap(find.byTooltip('下个月'));
      await tester.pump();

      expect(find.text('2026年12月'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsNothing);

      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 12), seconds: {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('本月暂无有效投入。'), findsOneWidget);
    }),
  );

  testWidgets(
    '读取失败显示重试，重试后恢复真实数据',
    (tester) => withFixture(tester, () async {
      final repository = _FlakyFocusRepository();
      await tester.pumpWidget(host(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('专注月历加载失败。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      repository.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('专注月历加载失败。'), findsNothing);
      expect(find.text('10 分钟'), findsOneWidget);
      expect(repository.calls, 2);
    }),
  );

  testWidgets(
    '账号显示时区变化后按新时区重新分摊',
    (tester) => withFixture(tester, () async {
      final task = await createTask(tester);
      // 上海 12 月 1 日 00:00；UTC 仍是 11 月 30 日。
      await seed(tester, task, {DateTime.utc(2026, 11, 30, 16): 2 * 60 * 60});
      final zones = StreamController<String?>();
      addTearDown(zones.close);

      await tester.pumpWidget(
        host(
          repository: focusRepository,
          accountTimeZoneIds: () => zones.stream,
        ),
      );
      zones.add('Asia/Shanghai');
      await tester.pumpAndSettle();
      expect(find.text('本月暂无有效投入。'), findsOneWidget);

      zones.add('Etc/UTC');
      await tester.pumpAndSettle();
      expect(find.text('2 小时'), findsOneWidget);
    }),
  );

  testWidgets(
    '切换账号仓库后不回显上一账号的投入',
    (tester) => withFixture(tester, () async {
      final repositoryA = _DeferredFocusRepository();
      final repositoryB = _DeferredFocusRepository();
      addTearDown(repositoryA.dispose);
      addTearDown(repositoryB.dispose);
      var current = repositoryA;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return FocusMonthPage(
                repository: current,
                accountTimeZoneIds: () =>
                    Stream<String?>.value('Asia/Shanghai'),
                initialMonth: DateTime(2026, 11),
                now: () => now,
              );
            },
          ),
        ),
      );
      await tester.pump();
      repositoryA.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 45 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('45 分钟'), findsOneWidget);

      rebuild(() => current = repositoryB);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsNothing);

      repositoryB.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 10 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('10 分钟'), findsOneWidget);
    }),
  );

  testWidgets(
    '360 窄窗与 1440 宽窗都能完整呈现，亮暗主题可读',
    (tester) => withFixture(tester, () async {
      final task = await createTask(tester);
      await seed(tester, task, {DateTime.utc(2026, 11, 3, 2): 45 * 60});
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final size in [const Size(360, 800), const Size(1440, 900)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(host(repository: focusRepository));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('2026年11月'), findsOneWidget);
        expect(find.byKey(const ValueKey('focus-month-day-3')), findsOneWidget);
      }

      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(
        host(repository: focusRepository, brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2026年11月'), findsOneWidget);
    }),
  );
}

FocusMonthMetrics _monthMetrics({
  required DateTime month,
  required Map<int, int> seconds,
  String timeZoneId = 'Asia/Shanghai',
}) {
  final start = DateTime.utc(month.year, month.month);
  final count = DateTime.utc(start.year, start.month + 1, 0).day;
  final days = [
    for (var day = 1; day <= count; day++)
      FocusActivityDay(
        date: DateTime.utc(start.year, start.month, day),
        activeSeconds: seconds[day] ?? 0,
      ),
  ];
  return FocusMonthMetrics(
    displayTimeZoneId: timeZoneId,
    month: start,
    days: List.unmodifiable(days),
    totalActiveSeconds: days.fold<int>(
      0,
      (sum, day) => sum + day.activeSeconds,
    ),
    activeDayCount: days.where((day) => day.activeSeconds > 0).length,
  );
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

class _FlakyFocusRepository extends UnavailableFocusRepository {
  int calls = 0;
  bool fail = true;

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    calls++;
    if (fail) return Stream.error(StateError('projection failed'));
    return Stream.value(
      _monthMetrics(
        month: month,
        seconds: {5: 10 * 60},
        timeZoneId: timeZoneId,
      ),
    );
  }
}
