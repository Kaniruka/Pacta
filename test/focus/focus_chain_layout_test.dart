import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

const _sessionStrip = ValueKey('focus-recovery-session');
const _chainTable = ValueKey('focus-chain-table');
const _historyEntry = ValueKey('focus-history-entry');

void main() {
  testWidgets('进行中恢复条是圆角容器（无左竖条），与统计表相隔 12dp', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');

    final strip = find.byKey(_sessionStrip);
    expect(strip, findsOneWidget);
    expect(find.text('已有进行中的专注'), findsOneWidget);
    final container = tester.widget<Container>(
      find.descendant(of: strip, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border, isNull, reason: '不再有左单边 3dp 竖条');
    expect(decoration.borderRadius, BorderRadius.circular(PactaSpacing.md));

    final gap =
        tester.getRect(find.byKey(_chainTable)).top -
        tester.getRect(strip).bottom;
    expect(gap, PactaSpacing.md, reason: '恢复条与统计表相隔 12dp');
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('选择任务页的连续任务卡片相隔 8dp', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.text('选择任务'));
    await tester.pumpAndSettle();

    final cards = find.descendant(
      of: find.byType(FocusTaskPickerPage),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(2));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(second.top - first.bottom, PactaSpacing.sm);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('专注历史页的连续记录卡片相隔 8dp', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    for (var index = 0; index < 2; index++) {
      await fixture.focus.startSession(
        taskId: fixture.taskIds.first,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      fixture.now = fixture.now.add(const Duration(minutes: 25));
      await fixture.focus.settleDueSessions();
    }
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();

    final cards = find.descendant(
      of: find.byType(FocusHistoryPage),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(2));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(second.top - first.bottom, PactaSpacing.sm);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });
}

Future<void> _mount(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PactaApp(
      authRepository: fixture.auth,
      taskRepositoryFactory: (_) => fixture.tasks,
      focusRepositoryFactory: (_) => fixture.focus,
      displayClock: () => fixture.now,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDestination(WidgetTester tester, String label) async {
  final bar = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: bar, matching: find.text(label)));
  await tester.pumpAndSettle();
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
    required this.taskIds,
    required this.clock,
  });

  final PactaDatabase database;
  final FakeAuthRepository auth;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final List<String> taskIds;
  final _Clock clock;

  DateTime get now => clock.value;
  set now(DateTime value) => clock.value = value;

  static Future<_Fixture> create() async {
    const userId = 'focus-chain-layout';
    final database = PactaDatabase(NativeDatabase.memory());
    final clock = _Clock(DateTime(2026, 11, 15, 9));
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      // 排序偏好依赖插件通道；本用例只验卡片间距，直接走内存兜底。
      taskOrderStore: GoalTaskOrderStore(
        preferencesLoader: () async =>
            throw MissingPluginException('卡片间距用例不读写设备偏好'),
      ),
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => clock.value,
    );
    final goal = await tasks.createGoal(
      const GoalDraft(title: '卡片间距验收', classification: TaskClassification.both),
    );
    final taskIds = <String>[];
    for (final title in ['阅读一章，留下三个要点', '梳理明天的计划']) {
      final task = await tasks.createTask(
        goal.id,
        TaskDraft(
          title: title,
          classification: TaskClassification.both,
          estimatedMinutes: 30,
        ),
      );
      taskIds.add(task.id);
    }
    return _Fixture(
      database: database,
      auth: FakeAuthRepository()..signedInUser = userId,
      tasks: tasks,
      focus: focus,
      taskIds: taskIds,
      clock: clock,
    );
  }

  Future<void> dispose() async {
    await database.close();
  }
}

class _Clock {
  _Clock(this.value);

  DateTime value;
}
