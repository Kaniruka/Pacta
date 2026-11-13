import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

/// 体验问题复现后的行为回归（2026-11-13）。
///
/// 红（默认模式规则变更）：看板/任务选择页对单一精锐任务默认精锐链；
/// 看板预约交接保持所选模式。
/// 绿（时间/生命周期回归）：看板直接完成、预约交接完成后完成、后台→前台结算、
/// 暂停+依据规则提前完成、任务已有非零累计进度后再完成。
/// 每个用例 finally 卸载控件树并 dispose 仓储，计时相关只用有界 pump。
void main() {
  late _Harness h;

  setUp(() {
    h = _Harness();
  });

  testWidgets('看板单精锐任务默认精锐链', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await tester.tap(find.byTooltip('开始专注'));
      await _boundedSettle(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('精锐链'),
        ),
        findsOneWidget,
        reason: '新默认规则：单一精锐任务的看板入口应预选精锐链',
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('任务选择页单精锐任务默认精锐链', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.show(tester);
      await h.openTab(tester, '专注链');

      await tester.tap(find.text('选择任务'));
      await _boundedSettle(tester);
      await tester.tap(find.text('精锐任务'));
      await _boundedSettle(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('精锐链'),
        ),
        findsOneWidget,
        reason: '新默认规则：任务选择页选择单一精锐任务应预选精锐链',
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('看板预约准备自动交接保持所选模式', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await tester.tap(find.byTooltip('开始专注'));
      await _boundedSettle(tester);
      await tester.tap(find.text('开始准备（15分钟）'));
      await _boundedSettle(tester);

      final appointment = (await h.focus.getActiveAppointment())!;
      final appointmentMode = appointment.mode.label;

      h.advance(const Duration(minutes: 15));
      await _pumpTicks(tester);

      final session = (await h.focus.getActiveSession())!;
      expect(
        session.mode,
        FocusChainMode.elite,
        reason: '看板预约（预约模式=$appointmentMode）交接后应以同一模式进入专注',
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('回归 看板直接完成：看板时长与专注链累计同时增加', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await h.startEliteFromBoard(tester);
      final started = (await h.focus.getActiveSession())!;
      expect(started.mode, FocusChainMode.elite);

      h.advance(const Duration(minutes: 25));
      await _pumpTicks(tester);
      await _pumpTicks(tester);

      final settled = (await h.focus.getSession(started.id))!;
      expect(settled.status, FocusSessionStatus.completed);
      expect(settled.effectiveSeconds, 25 * 60);

      await tester.tap(find.text('返回上一页'));
      await _boundedSettle(tester);

      expect(find.text('已专注 25分00秒'), findsOneWidget);
      await h.openTab(tester, '专注链');
      expect(
        find.text('连续 1 次', findRichText: true),
        findsWidgets,
        reason: '专注链次数应加 1',
      );
      expect(
        find.descendant(
          of: _metric('精锐链', '累计专注'),
          matching: find.text('25 分钟'),
        ),
        findsOneWidget,
        reason: '专注链卡片的累计专注应为 25 分钟',
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('回归 预约交接完成后完成：看板时长与累计都增加', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await tester.tap(find.byTooltip('开始专注'));
      await _boundedSettle(tester);
      await tester.tap(find.byType(DropdownButtonFormField<FocusChainMode>));
      await _boundedSettle(tester);
      await tester.tap(find.text('精锐链').last);
      await _boundedSettle(tester);
      await tester.tap(find.text('开始准备（15分钟）'));
      await _boundedSettle(tester);

      h.advance(const Duration(minutes: 15));
      await _pumpTicks(tester);
      final handoff = (await h.focus.getActiveSession())!;
      expect(handoff.mode, FocusChainMode.elite);

      h.advance(const Duration(minutes: 25));
      await _pumpTicks(tester);
      await _pumpTicks(tester);

      final settled = (await h.focus.getSession(handoff.id))!;
      expect(settled.status, FocusSessionStatus.completed);
      expect(settled.effectiveSeconds, 25 * 60);

      await tester.tap(find.text('返回上一页'));
      await _boundedSettle(tester);
      expect(find.text('已专注 25分00秒'), findsOneWidget);

      await h.openTab(tester, '专注链');
      expect(
        find.descendant(
          of: _metric('精锐链', '累计专注'),
          matching: find.text('25 分钟'),
        ),
        findsOneWidget,
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('回归 真实 AppShell 后台到前台后到期结算', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await h.startEliteFromBoard(tester);
      final started = (await h.focus.getActiveSession())!;

      h.advance(const Duration(minutes: 25));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _boundedSettle(tester);
      await _boundedSettle(tester);

      final settled = (await h.focus.getSession(started.id))!;
      expect(
        settled.status,
        FocusSessionStatus.completed,
        reason: '前台恢复时应结算到期会话',
      );
      expect(settled.effectiveSeconds, 25 * 60);

      await tester.tap(find.text('返回上一页'));
      await _boundedSettle(tester);
      expect(find.text('已专注 25分00秒'), findsOneWidget);

      await h.openTab(tester, '专注链');
      expect(
        find.descendant(
          of: _metric('精锐链', '累计专注'),
          matching: find.text('25 分钟'),
        ),
        findsOneWidget,
        reason: '后台恢复结算后累计专注应为 25 分钟',
      );
      expect(find.text('连续 1 次', findRichText: true), findsWidgets);
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('回归 暂停后依据规则提前完成只计有效时间', (tester) async {
    try {
      await h.seedTask('精锐任务', TaskClassification.elite);
      await h.focus.createPrecedentRule(text: '需要喝水时允许短暂离开');
      await h.show(tester);
      await h.openTab(tester, '看板');

      await h.startEliteFromBoard(tester);
      final started = (await h.focus.getActiveSession())!;

      h.advance(const Duration(minutes: 10));
      await tester.tap(find.text('暂停'));
      await _boundedSettle(tester);
      await tester.tap(find.byType(RadioListTile<String>));
      await tester.pump();
      await tester.tap(find.text('确认暂停'));
      await _boundedSettle(tester);
      expect((await h.focus.getSession(started.id))?.isPaused, isTrue);

      h.advance(const Duration(minutes: 5));
      await tester.tap(find.text('继续'));
      await _boundedSettle(tester);
      expect((await h.focus.getSession(started.id))?.isActive, isTrue);

      h.advance(const Duration(minutes: 10));
      await tester.tap(find.text('依据规则提前完成'));
      await _boundedSettle(tester);
      await tester.tap(find.byType(RadioListTile<String>));
      await tester.pump();
      await tester.tap(find.text('选择依据'));
      await _boundedSettle(tester);
      expect(find.text('确认提前完成？'), findsOneWidget);
      await tester.tap(find.text('提前完成'));
      await _boundedSettle(tester);

      final settled = (await h.focus.getSession(started.id))!;
      expect(settled.isEarlyCompleted, isTrue);
      expect(settled.effectiveSeconds, 20 * 60, reason: '暂停 5 分钟后仅计 20 分钟有效时间');

      await tester.tap(find.text('返回上一页'));
      await _boundedSettle(tester);
      expect(find.text('已专注 20分00秒'), findsOneWidget);

      await h.openTab(tester, '专注链');
      expect(
        find.descendant(
          of: _metric('精锐链', '累计专注'),
          matching: find.text('20 分钟'),
        ),
        findsOneWidget,
      );
      expect(find.text('连续 1 次', findRichText: true), findsWidgets);
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('回归 任务已有非零进度后再完成继续累加', (tester) async {
    try {
      final task = await h.seedTask('精锐任务', TaskClassification.elite);
      // 已建立的历史进度：10 分钟精锐链完成会话。
      await h.focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 10),
      );
      h.advance(const Duration(minutes: 10));
      await h.focus.settleDueSessions();
      expect(
        (await h.tasks.getGoals()).single.tasks.single.focusProgressSeconds,
        10 * 60,
      );

      await h.show(tester);
      await h.openTab(tester, '看板');

      await h.startEliteFromBoard(tester);
      h.advance(const Duration(minutes: 25));
      await _pumpTicks(tester);
      await _pumpTicks(tester);
      await tester.tap(find.text('返回上一页'));
      await _boundedSettle(tester);

      expect(
        find.text('已专注 35分00秒'),
        findsOneWidget,
        reason: '已有 10 分钟后完成 25 分钟应显示 35 分钟',
      );

      await h.openTab(tester, '专注链');
      expect(
        find.descendant(
          of: _metric('精锐链', '累计专注'),
          matching: find.text('35 分钟'),
        ),
        findsOneWidget,
        reason: '专注链卡片累计专注应为 35 分钟',
      );
      expect(
        find.text('连续 2 次', findRichText: true),
        findsWidgets,
        reason: '第二次完成后连续次数为 2',
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('对照组 看板单普通任务默认普通链', (tester) async {
    try {
      await h.seedTask('普通任务', TaskClassification.regular);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await tester.tap(find.byTooltip('开始专注'));
      await _boundedSettle(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('普通链'),
        ),
        findsOneWidget,
      );
    } finally {
      await h.teardown(tester);
    }
  });

  testWidgets('对照组 看板双分类任务沿用上次成功模式', (tester) async {
    try {
      await h.seedTask('双模式任务', TaskClassification.both);
      await h.show(tester);
      await h.openTab(tester, '看板');

      await tester.tap(find.byTooltip('开始专注'));
      await _boundedSettle(tester);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('普通链'),
        ),
        findsOneWidget,
        reason: '首次且无上次模式时双分类任务默认普通链',
      );
      await tester.tap(find.byType(DropdownButtonFormField<FocusChainMode>));
      await _boundedSettle(tester);
      await tester.tap(find.text('精锐链').last);
      await _boundedSettle(tester);
      await tester.tap(find.text('开始倒计时'));
      await _boundedSettle(tester);
      final session = (await h.focus.getActiveSession())!;
      expect(session.mode, FocusChainMode.elite);
      // 结束原会话后再观察下一次默认，避免把"恢复原流程"误判为缺陷。
      await h.focus.abandonSession(
        sessionId: session.id,
        failureReason: '对照组清理',
      );
      await tester.pageBack();
      await _boundedSettle(tester);

      await tester.tap(find.byTooltip('开始专注'));
      await _boundedSettle(tester);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('精锐链'),
        ),
        findsOneWidget,
        reason: '双分类任务应沿用上次成功开始的精锐链',
      );
    } finally {
      await h.teardown(tester);
    }
  });
}

/// 专注链概览中的单链卡片（标题为"精锐链"/"普通链"/"预约链"）。
Finder _chainCard(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card)).first;

/// 链卡内指定指标（如"累计专注"）的数值所在列。
Finder _metric(String chainTitle, String label) => find.descendant(
  of: _chainCard(chainTitle),
  matching: find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first,
);

/// 有界等待：完成路由/对话框动画，但不等周期性定时器。
Future<void> _boundedSettle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 触发对话页 250ms 轮询若干次，让仓储结算并刷新界面。
Future<void> _pumpTicks(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 260));
  }
}

class _Harness {
  DateTime now = DateTime.utc(2026, 11, 13, 8);
  Duration monotonic = Duration.zero;
  final database = PactaDatabase(NativeDatabase.memory());
  var _disposed = false;

  late final tasks = LocalTaskRepository(
    database: database,
    userId: 'repro',
    now: () => now,
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  );
  late final focus = LocalFocusRepository(
    database: database,
    userId: 'repro',
    now: () => now,
    monotonicNow: () => monotonic,
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
  );
  late final tree = LocalNationalFocusRepository(
    database: database,
    userId: 'repro',
    cloudSyncEnabled: false,
  );

  void advance(Duration delta) {
    now = now.add(delta);
    monotonic += delta;
  }

  Future<Task> seedTask(String title, TaskClassification classification) async {
    final goal = await tasks.createGoal(
      GoalDraft(title: '$title 目标', classification: classification),
    );
    return tasks.createTask(
      goal.id,
      TaskDraft(title: title, classification: classification),
    );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'repro',
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      ),
    );
    await _boundedSettle(tester);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await _boundedSettle(tester);
  }

  /// 看板入口：开始专注 → 显式选择精锐链 → 开始倒计时。
  Future<void> startEliteFromBoard(WidgetTester tester) async {
    await tester.tap(find.byTooltip('开始专注'));
    await _boundedSettle(tester);
    await tester.tap(find.byType(DropdownButtonFormField<FocusChainMode>));
    await _boundedSettle(tester);
    await tester.tap(find.text('精锐链').last);
    await _boundedSettle(tester);
    await tester.tap(find.text('开始倒计时'));
    await _boundedSettle(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    try {
      await focus.dispose();
    } catch (_) {}
    try {
      await tasks.dispose();
    } catch (_) {}
    await database.close();
  }
}
