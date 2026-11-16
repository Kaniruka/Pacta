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
    '仅替换时区来源时立即清空旧投影，等待新来源解析再查询',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);
      final zonesA = StreamController<String?>();
      final zonesB = StreamController<String?>();
      addTearDown(zonesA.close);
      addTearDown(zonesB.close);
      var activeZoneStream = zonesA.stream;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return FocusMonthPage(
                repository: repository,
                accountTimeZoneIds: () => activeZoneStream,
                initialMonth: DateTime(2026, 11),
                now: () => now,
              );
            },
          ),
        ),
      );
      zonesA.add('Asia/Shanghai');
      await tester.pump();
      await tester.pump();
      expect(repository.requests, hasLength(1));
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 45 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('45 分钟'), findsOneWidget);
      expect(repository.requests, hasLength(1));
      expect(repository.last.timeZoneId, 'Asia/Shanghai');

      // Same repository, new zone source that has not emitted yet: the old
      // account's projection must be dropped, and no query may run until the
      // replacement source resolves.
      rebuild(() => activeZoneStream = zonesB.stream);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsNothing);
      expect(repository.requests, hasLength(1));

      // Month switching cannot bypass the pending source: both arrows are
      // disabled and a tap issues no query against the previous zone.
      expect(_monthNavigationDisabled(tester, '上个月'), isTrue);
      expect(_monthNavigationDisabled(tester, '下个月'), isTrue);
      await tester.tap(find.byTooltip('下个月'));
      await tester.pump();
      expect(repository.requests, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // A late emission from the replaced source cannot resurrect the old
      // projection either.
      repository.requests.single.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 90 * 60}),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('1 小时 30 分钟'), findsNothing);

      zonesB.add('Etc/UTC');
      await tester.pump();
      await tester.pump();
      expect(repository.requests, hasLength(2));
      expect(repository.last.timeZoneId, 'Etc/UTC');

      repository.last.controller.add(
        _monthMetrics(
          month: DateTime.utc(2026, 11),
          seconds: {12: 10 * 60},
          timeZoneId: 'Etc/UTC',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('10 分钟'), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsNothing);
    }),
  );

  testWidgets(
    '资料时区流异步失败进入可恢复错误态，重试重新读取时区与月投影',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);
      var attempts = 0;
      Stream<String?> source() {
        attempts++;
        if (attempts == 1) {
          return Stream<String?>.error(StateError('profile unavailable'));
        }
        return Stream<String?>.value('Asia/Shanghai');
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: FocusMonthPage(
            repository: repository,
            accountTimeZoneIds: source,
            initialMonth: DateTime(2026, 11),
            now: () => now,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('专注月历加载失败。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('45 分钟'), findsNothing);

      // A failed source also blocks month switching: the error must not be
      // bypassed with a query against the previous zone.
      expect(_monthNavigationDisabled(tester, '上个月'), isTrue);
      expect(_monthNavigationDisabled(tester, '下个月'), isTrue);
      await tester.tap(find.byTooltip('下个月'));
      await tester.pump();
      expect(repository.requests, isEmpty);
      expect(find.text('专注月历加载失败。'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();

      expect(attempts, 2);
      expect(repository.requests, hasLength(1));
      expect(repository.last.timeZoneId, 'Asia/Shanghai');

      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {5: 10 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.text('专注月历加载失败。'), findsNothing);
      expect(find.textContaining('10 分钟'), findsOneWidget);
    }),
  );

  testWidgets(
    '资料时区回调同步抛错进入可恢复错误态，重试后恢复真实数据',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);
      var attempts = 0;
      Stream<String?> source() {
        attempts++;
        if (attempts == 1) throw StateError('profile unavailable');
        return Stream<String?>.value('Asia/Shanghai');
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: FocusMonthPage(
            repository: repository,
            accountTimeZoneIds: source,
            initialMonth: DateTime(2026, 11),
            now: () => now,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('专注月历加载失败。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();

      expect(attempts, 2);
      expect(repository.requests, hasLength(1));
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {6: 5 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.text('专注月历加载失败。'), findsNothing);
      expect(find.textContaining('5 分钟'), findsOneWidget);
    }),
  );

  testWidgets(
    '跨月后新投影不会把上月数据标成当月，标题与数据一起停留',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);
      // 上海 11 月 30 日 23:59（UTC 仍是 11 月 30 日 15:59）。
      now = DateTime.utc(2026, 11, 30, 15, 59);
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: FocusMonthPage(
            repository: repository,
            accountTimeZoneIds: () => Stream<String?>.value('Asia/Shanghai'),
            now: () => now,
          ),
        ),
      );
      await tester.pump();
      expect(repository.requests, hasLength(1));
      expect(repository.last.month, DateTime.utc(2026, 11));
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {30: 45 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsOneWidget);

      // Midnight passes in the account zone; a settled session arrives without
      // touching the month selector.
      now = DateTime.utc(2026, 11, 30, 16, 0, 5);
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {30: 60 * 60}),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('2026年12月'), findsNothing);
      expect(find.textContaining('1 小时'), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsNothing);
      expect(repository.requests, hasLength(1));

      // The current-month label is the explicit way forward; it re-queries.
      await tester.tap(find.text('回到本月'));
      await tester.pump();
      expect(find.text('2026年12月'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.requests, hasLength(2));
      expect(repository.last.month, DateTime.utc(2026, 12));
    }),
  );

  testWidgets(
    '来源未解析时“回到本月”不可用，不会按旧时区查询',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);
      final zonesA = StreamController<String?>();
      final zonesB = StreamController<String?>();
      addTearDown(zonesA.close);
      addTearDown(zonesB.close);
      var activeZoneStream = zonesA.stream;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return FocusMonthPage(
                repository: repository,
                accountTimeZoneIds: () => activeZoneStream,
                initialMonth: DateTime(2026, 10),
                now: () => now,
              );
            },
          ),
        ),
      );
      zonesA.add('Asia/Shanghai');
      await tester.pump();
      await tester.pump();
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 10), seconds: {9: 30 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.textContaining('30 分钟'), findsOneWidget);
      expect(find.text('回到本月'), findsOneWidget);

      rebuild(() => activeZoneStream = zonesB.stream);
      await tester.pump();

      expect(find.text('回到本月'), findsNothing);
      expect(_monthNavigationDisabled(tester, '下个月'), isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.requests, hasLength(1));

      zonesB.add('Etc/UTC');
      await tester.pump();
      await tester.pump();

      // Resolution re-queries the month already on screen (October), now in the
      // replacement account zone.
      expect(repository.requests, hasLength(2));
      expect(repository.last.timeZoneId, 'Etc/UTC');
      expect(repository.last.month, DateTime.utc(2026, 10));
      expect(find.text('2026年10月'), findsOneWidget);
      repository.last.controller.add(
        _monthMetrics(
          month: DateTime.utc(2026, 10),
          seconds: {9: 30 * 60},
          timeZoneId: 'Etc/UTC',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('回到本月'), findsOneWidget);

      await tester.tap(find.text('回到本月'));
      await tester.pump();
      expect(find.text('2026年11月'), findsOneWidget);
      expect(repository.requests, hasLength(3));
      expect(repository.last.month, DateTime.utc(2026, 11));
    }),
  );

  testWidgets(
    '替换来源为空时使用账号兜底时区，不继承上一个来源',
    (tester) => withFixture(tester, () async {
      final repository = _DeferredFocusRepository();
      addTearDown(repository.dispose);
      final zonesA = StreamController<String?>();
      addTearDown(zonesA.close);
      var activeZoneStream = zonesA.stream;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return FocusMonthPage(
                repository: repository,
                accountTimeZoneIds: () => activeZoneStream,
                initialMonth: DateTime(2026, 11),
                now: () => now,
              );
            },
          ),
        ),
      );
      zonesA.add('Asia/Shanghai');
      await tester.pump();
      await tester.pump();
      repository.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 45 * 60}),
      );
      await tester.pumpAndSettle();
      expect(repository.last.timeZoneId, 'Asia/Shanghai');

      // The replacement source closes without a value: the account fallback is
      // used explicitly; the previous source's zone must not leak through.
      rebuild(() => activeZoneStream = Stream<String?>.empty());
      await tester.pump();
      await tester.pump();

      expect(repository.requests, hasLength(2));
      expect(repository.last.timeZoneId, 'Etc/UTC');
      expect(repository.last.month, DateTime.utc(2026, 11));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('45 分钟'), findsNothing);

      repository.last.controller.add(
        _monthMetrics(
          month: DateTime.utc(2026, 11),
          seconds: {12: 10 * 60},
          timeZoneId: 'Etc/UTC',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('10 分钟'), findsOneWidget);
    }),
  );

  testWidgets(
    '来源未解析时更换仓库不查询，解析后只查询新仓库',
    (tester) => withFixture(tester, () async {
      final repositoryA = _DeferredFocusRepository();
      final repositoryB = _DeferredFocusRepository();
      addTearDown(repositoryA.dispose);
      addTearDown(repositoryB.dispose);
      final zones = StreamController<String?>();
      addTearDown(zones.close);
      Stream<String?> zoneSource() => zones.stream;
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
                accountTimeZoneIds: zoneSource,
                initialMonth: DateTime(2026, 11),
                now: () => now,
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(repositoryA.requests, isEmpty);
      expect(repositoryB.requests, isEmpty);

      // Same stable zone callback, replacement repository, source still
      // unresolved: no query may run against either repository yet.
      rebuild(() => current = repositoryB);
      await tester.pump();
      expect(repositoryA.requests, isEmpty);
      expect(repositoryB.requests, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);

      // Resolution queries the current repository once, in the resolved zone.
      zones.add('Asia/Shanghai');
      await tester.pump();
      await tester.pump();
      expect(repositoryB.requests, hasLength(1));
      expect(repositoryB.last.timeZoneId, 'Asia/Shanghai');
      expect(repositoryA.requests, isEmpty);

      repositoryB.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {12: 10 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('10 分钟'), findsOneWidget);
    }),
  );

  testWidgets(
    '来源失败后更换仓库保持错误态不查询，重试后只读新仓库',
    (tester) => withFixture(tester, () async {
      final repositoryA = _DeferredFocusRepository();
      final repositoryB = _DeferredFocusRepository();
      addTearDown(repositoryA.dispose);
      addTearDown(repositoryB.dispose);
      var attempts = 0;
      Stream<String?> zoneSource() {
        attempts++;
        if (attempts == 1) {
          return Stream<String?>.error(StateError('profile unavailable'));
        }
        return Stream<String?>.value('Asia/Shanghai');
      }

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
                accountTimeZoneIds: zoneSource,
                initialMonth: DateTime(2026, 11),
                now: () => now,
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('专注月历加载失败。'), findsOneWidget);
      expect(repositoryA.requests, isEmpty);

      // A repository swap while the source is failed keeps the recoverable error
      // and never queries with a stale/previous zone.
      rebuild(() => current = repositoryB);
      await tester.pump();

      expect(find.text('专注月历加载失败。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repositoryA.requests, isEmpty);
      expect(repositoryB.requests, isEmpty);

      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();

      expect(repositoryB.requests, hasLength(1));
      expect(repositoryB.last.timeZoneId, 'Asia/Shanghai');
      expect(repositoryA.requests, isEmpty);

      repositoryB.last.controller.add(
        _monthMetrics(month: DateTime.utc(2026, 11), seconds: {7: 20 * 60}),
      );
      await tester.pumpAndSettle();
      expect(find.text('专注月历加载失败。'), findsNothing);
      expect(find.textContaining('20 分钟'), findsOneWidget);
    }),
  );

  testWidgets(
    '切换账号仓库后不回显上一账号的投入',
    (tester) => withFixture(tester, () async {
      final repositoryA = _DeferredFocusRepository();
      final repositoryB = _DeferredFocusRepository();
      addTearDown(repositoryA.dispose);
      addTearDown(repositoryB.dispose);
      Stream<String?> zoneSource() => Stream<String?>.value('Asia/Shanghai');
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
                accountTimeZoneIds: zoneSource,
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

bool _monthNavigationDisabled(WidgetTester tester, String tooltip) {
  final button = tester
      .widgetList<IconButton>(find.byType(IconButton))
      .singleWhere((button) => button.tooltip == tooltip);
  return button.onPressed == null;
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
