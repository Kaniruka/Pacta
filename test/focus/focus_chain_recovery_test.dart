import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

const _rule = '允许短暂起身接水';
const _historyEntry = ValueKey('focus-history-entry');
const _allowanceManage = ValueKey('focus-allowance-manage');

void main() {
  testWidgets('进行中的专注可从专注链恢复进入', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskId,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await _openFocusChain(tester, fixture);

    expect(find.text('已有进行中的专注'), findsOneWidget);
    await tester.tap(find.text('返回专注'));
    await _boundedSettle(tester);

    expect(find.byType(FocusSessionPage), findsOneWidget);
    expect(find.text('专注进行中'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('预约准备恢复条保留三个动作并可返回准备页', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startAppointment(
      taskId: fixture.taskId,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
      preparation: const Duration(minutes: 10),
    );
    await _openFocusChain(tester, fixture);

    expect(find.text('已有预约准备'), findsOneWidget);
    expect(find.text('返回准备'), findsOneWidget);
    expect(find.text('提前进入专注'), findsOneWidget);
    expect(find.text('取消预约'), findsOneWidget);

    await tester.tap(find.text('返回准备'));
    await _boundedSettle(tester);
    expect(find.byType(AppointmentPreparationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('执行中的暂停仍可选择下必为例作为依据', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final session = await fixture.focus.startSession(
      taskId: fixture.taskId,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 25),
    );
    await _openFocusChain(tester, fixture);
    await tester.tap(find.text('返回专注'));
    await _boundedSettle(tester);
    expect(find.byType(FocusSessionPage), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '暂停'));
    await _boundedSettle(tester);
    expect(find.text('选择下必为例'), findsOneWidget);

    await tester.tap(find.text(_rule));
    await _boundedSettle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认暂停'));
    await _boundedSettle(tester);

    final paused = await fixture.focus.getActiveSession();
    expect(paused!.id, session.id);
    expect(paused.isPaused, isTrue);
    expect(paused.pauseRuleText, _rule);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('专注链首屏的许可管理入口可新建规则并回填数量', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _openFocusChain(tester, fixture);
    expect(find.text('1 条持续许可'), findsOneWidget);

    await tester.tap(find.byKey(_allowanceManage));
    await _boundedSettle(tester);
    expect(find.byType(PrecedentRulesPage), findsOneWidget);
    expect(find.text('下必为例'), findsWidgets);
    expect(find.text(_rule), findsOneWidget);

    await tester.tap(find.text('新建规则'));
    await _boundedSettle(tester);
    expect(find.text('新建下必为例'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '允许查询相关资料');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _boundedSettle(tester);
    expect(find.text('允许查询相关资料'), findsOneWidget);

    await tester.pageBack();
    await _boundedSettle(tester);
    expect(find.text('2 条持续许可'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('专注链已挂载后从看板新建预约，恢复条实时出现并在取消后清除', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _openFocusChain(tester, fixture);
    expect(find.text('已有预约准备'), findsNothing);

    // Create the appointment through the real Board flow after Focus Chain
    // has already mounted; the recovery strip must update without a session.
    await _openDestination(tester, '看板');
    await tester.tap(find.byTooltip('开始专注'));
    await _boundedSettle(tester);
    await tester.tap(find.text('10 分钟'));
    await _boundedSettle(tester);
    await tester.tap(find.text('开始准备（10分钟）'));
    await _boundedSettle(tester);
    expect(find.byType(AppointmentPreparationPage), findsOneWidget);

    await tester.pageBack();
    await _boundedSettle(tester);
    await _openDestination(tester, '专注链');
    expect(find.text('已有预约准备'), findsOneWidget);
    expect(find.text('返回准备'), findsOneWidget);
    expect(find.text('提前进入专注'), findsOneWidget);
    expect(find.text('取消预约'), findsOneWidget);
    expect(find.text('已有进行中的专注'), findsNothing);
    expect(await fixture.focus.getActiveSession(), isNull);

    await tester.tap(find.text('取消预约'));
    await _boundedSettle(tester);
    await tester.enterText(find.byType(TextField), '实时刷新验证');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _boundedSettle(tester);
    expect(find.text('已有预约准备'), findsNothing);
    expect(find.text('返回准备'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('历史入口在两种常见手机宽度下都可达', (tester) async {
    for (final size in [const Size(360, 800), const Size(390, 844)]) {
      final fixture = await _Fixture.create();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        PactaApp(
          authRepository: fixture.auth,
          taskRepositoryFactory: (_) => fixture.tasks,
          focusRepositoryFactory: (_) => fixture.focus,
        ),
      );
      await _boundedSettle(tester);
      await _openFocusChain(tester, fixture, pump: false);
      expect(
        find.byKey(_historyEntry),
        findsOneWidget,
        reason: '${size.width}',
      );
      await tester.tap(find.byKey(_historyEntry));
      await _boundedSettle(tester);
      expect(find.text('专注历史'), findsWidgets);
      await tester.pageBack();
      await _boundedSettle(tester);
      await _disposeWidget(tester);
      await fixture.dispose();
    }
  });
}

Future<void> _openDestination(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _boundedSettle(tester);
}

Future<void> _openFocusChain(
  WidgetTester tester,
  _Fixture fixture, {
  bool pump = true,
}) async {
  if (pump) {
    await tester.pumpWidget(
      PactaApp(
        authRepository: fixture.auth,
        taskRepositoryFactory: (_) => fixture.tasks,
        focusRepositoryFactory: (_) => fixture.focus,
      ),
    );
    await _boundedSettle(tester);
  }
  await _openDestination(tester, '专注链');
}

/// 有界等待：推进路由与对话框动画，不等周期性定时器。
Future<void> _boundedSettle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
}

class _Fixture {
  _Fixture({
    required this.database,
    required this.auth,
    required this.tasks,
    required this.focus,
    required this.taskId,
  });

  final PactaDatabase database;
  final FakeAuthRepository auth;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final String taskId;

  static Future<_Fixture> create() async {
    const userId = 'focus-chain-recovery';
    final database = PactaDatabase(NativeDatabase.memory());
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    var now = DateTime(2026, 11, 15, 9);
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    await focus.createPrecedentRule(text: _rule);
    final goal = await tasks.createGoal(
      const GoalDraft(title: '恢复入口验收', classification: TaskClassification.both),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '阅读一章，留下三个要点',
        classification: TaskClassification.both,
        estimatedMinutes: 30,
      ),
    );
    return _Fixture(
      database: database,
      auth: FakeAuthRepository()..signedInUser = userId,
      tasks: tasks,
      focus: focus,
      taskId: task.id,
    );
  }

  Future<void> dispose() async {
    await database.close();
  }
}
