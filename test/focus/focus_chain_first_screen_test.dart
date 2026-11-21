import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_card.dart'
    show
        appointmentEntryRule,
        appointmentNoteKey,
        focusChainNoteKey,
        focusDurationRule;
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

/// Public entry points of the 专注链 first screen.
const historyEntry = ValueKey('focus-history-entry');
const chainList = ValueKey('focus-chain-list');
const chainTable = ValueKey('focus-chain-table');
const signalsSurface = ValueKey('focus-chain-signals');
const allowanceEntry = ValueKey('focus-allowance-entry');
const allowanceManage = ValueKey('focus-allowance-manage');
const taskPickerEntry = ValueKey('focus-task-picker-entry');

const orderRule = '允许短暂起身接水';
const materialRule = '允许查询与本次任务相关的资料';

void main() {
  testWidgets('专注链首屏在 360×800 同屏呈现全部信息块与许可管理入口', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _pumpApp(
      tester,
      fixture,
      width: 360,
      height: 800,
      topInset: 24,
      bottomInset: 48,
    );

    await _openFocusChain(tester);

    for (final key in [
      chainTable,
      signalsSurface,
      allowanceEntry,
      focusChainNoteKey,
      taskPickerEntry,
      historyEntry,
    ]) {
      expect(find.byKey(key), findsOneWidget, reason: '$key 应保留在首屏');
    }
    // 说明折成提示后，首屏仍要能点开读到原句（不只是图标存在）。
    expect(find.text(focusDurationRule), findsNothing);
    await tester.tap(find.byKey(focusChainNoteKey));
    await tester.pumpAndSettle();
    expect(find.text(focusDurationRule), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    expect(find.text('当前连续'), findsOneWidget);
    expect(find.text('历史最高'), findsOneWidget);
    for (final chain in ['精锐链', '普通链', '预约链']) {
      expect(find.text(chain), findsOneWidget);
    }
    expect(find.text('累计'), findsNWidgets(2));
    expect(find.text('平均'), findsNWidgets(2));
    expect(find.text('选择任务'), findsOneWidget);
    expect(find.text('可选任务 2 个'), findsOneWidget);

    // 许可管理入口只做入口：完整 CRUD 在专注链管理页。
    expect(find.text(orderRule), findsNothing);
    expect(find.text('2 条持续许可'), findsOneWidget);
    await tester.tap(find.byKey(allowanceManage));
    await tester.pumpAndSettle();
    expect(find.text(orderRule), findsOneWidget);
    expect(find.text(materialRule), findsOneWidget);
    expect(find.text('新建规则'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_maxScrollExtent(tester), 0, reason: '360×800 常见手机高度应一屏容纳');
    expect(tester.takeException(), isNull);
    _printBounds(tester, '360x800');
    await _disposeWidget(tester);
  });

  testWidgets('我的不再重复承载下必为例管理面且管理仍从专注链进入', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _pumpApp(
      tester,
      fixture,
      width: 360,
      height: 800,
      topInset: 24,
      bottomInset: 48,
    );

    await _openDestination(tester, '我的');
    await tester.scrollUntilVisible(
      find.text('通知与设备权限'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(MyPage),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 40,
    );
    await tester.pump();
    expect(find.text('新建规则'), findsNothing);
    expect(find.byTooltip('编辑下必为例'), findsNothing);
    expect(find.text(orderRule), findsNothing);
    expect(find.text(materialRule), findsNothing);

    await _openFocusChain(tester);
    expect(find.text('2 条持续许可'), findsOneWidget);
    await tester.tap(find.byKey(allowanceManage));
    await tester.pumpAndSettle();
    expect(find.text('新建规则'), findsOneWidget);
    expect(find.text(orderRule), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('预约恢复与长信号在 360×800/390×844 下全部信息可见且无需滚动', (tester) async {
    for (final size in [const Size(360, 800), const Size(390, 844)]) {
      final fixture = await _Fixture.create();
      await _saveLongSignals(fixture);
      await fixture.focus.startAppointment(
        taskId: await _primaryTaskId(fixture),
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
        preparation: const Duration(minutes: 10),
      );
      await _pumpApp(tester, fixture, width: size.width, height: size.height);
      await _openFocusChain(tester);
      expect(find.text('已有预约准备'), findsOneWidget);
      // 入口句不占正文，提示挂在预约链标题行并留在首屏；展开交互由组件测试覆盖。
      expect(find.text(appointmentEntryRule), findsNothing);
      expect(find.byKey(appointmentNoteKey), findsOneWidget);
      _expectAllInformationVisible(tester, _sizeLabel(size));
      await _disposeWidget(tester);
      await fixture.dispose();
    }
  });

  testWidgets('预约恢复与长信号在 360×800/390×844 下全部信息可见且无需滚动', (tester) async {
    for (final size in [const Size(360, 800), const Size(390, 844)]) {
      final fixture = await _Fixture.create();
      await _saveLongSignals(fixture);
      await fixture.focus.startAppointment(
        taskId: await _primaryTaskId(fixture),
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
        preparation: const Duration(minutes: 10),
      );
      await _pumpApp(tester, fixture, width: size.width, height: size.height);
      await _openFocusChain(tester);
      _expectAllInformationVisible(tester, _sizeLabel(size));
      await _disposeWidget(tester);
      await fixture.dispose();
    }
  });
  testWidgets('专注链首屏在 390×844 与 360×800 布局一致且一屏容纳', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _pumpApp(
      tester,
      fixture,
      width: 390,
      height: 844,
      topInset: 47,
      bottomInset: 34,
    );
    await _openFocusChain(tester);

    expect(find.byKey(chainTable), findsOneWidget);
    expect(find.text('当前连续'), findsOneWidget);
    expect(_maxScrollExtent(tester), 0, reason: '390×844 常见手机高度应一屏容纳');
    expect(tester.takeException(), isNull);
    _printBounds(tester, '390x844');
    await _disposeWidget(tester);
  });

  testWidgets('320×568 极小窗口可滚动且不裁切全部信息块', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _pumpApp(
      tester,
      fixture,
      width: 320,
      height: 568,
      topInset: 24,
      bottomInset: 48,
    );
    await _openFocusChain(tester);

    expect(_maxScrollExtent(tester), greaterThan(0), reason: '极小窗口允许滚动，不宣称无滚动');
    const keys = {
      'table': chainTable,
      'signals': signalsSurface,
      'allowance': allowanceEntry,
      'note': focusChainNoteKey,
      'start': taskPickerEntry,
    };
    final blocks = <String, Object?>{};
    for (final entry in keys.entries) {
      await tester.scrollUntilVisible(
        find.byKey(entry.value),
        120,
        scrollable: _chainScrollable(tester),
        maxScrolls: 40,
      );
      await tester.pump();
      expect(
        find.byKey(entry.value),
        findsOneWidget,
        reason: '${entry.key} 可滚动到达',
      );
      final rect = tester.getRect(find.byKey(entry.value));
      expect(rect.width, greaterThan(0), reason: '${entry.key} 未被裁切');
      expect(rect.right, lessThanOrEqualTo(320), reason: '${entry.key} 未横向裁切');
      blocks[entry.key] = _rectJson(rect);
    }
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print(
      '[focus-chain-bounds] ${jsonEncode({'viewport': '320x568', 'maxScrollExtent': _maxScrollExtent(tester), 'blocks': blocks})}',
    );
    await _disposeWidget(tester);
  });
}

Future<void> _saveLongSignals(_Fixture fixture) => fixture.signals.save(
  const ChainSignalTexts(
    focusMarker: '戴上耳机，坐到书桌前，关闭消息提醒，把手机翻面并打开当前任务的第一页',
    appointmentTriggerSignal: '合上手机，倒一杯水，把桌面清空',
  ),
);

Future<String> _primaryTaskId(_Fixture fixture) async {
  final goals = await fixture.tasks.getGoals(includeDeleted: true);
  return goals.first.tasks.first.id;
}

String _sizeLabel(Size size) => '${size.width.toInt()}×${size.height.toInt()}';

void _expectAllInformationVisible(WidgetTester tester, String viewport) {
  final state = tester.state<ScrollableState>(_chainScrollable(tester));
  final list = tester.getRect(find.byKey(chainList));
  expect(state.position.maxScrollExtent, 0, reason: '$viewport 预约恢复态不应需要纵向滚动');
  for (final key in [
    historyEntry,
    chainTable,
    signalsSurface,
    allowanceEntry,
    focusChainNoteKey,
  ]) {
    final rect = tester.getRect(find.byKey(key));
    expect(
      rect.top,
      greaterThanOrEqualTo(list.top - 0.5),
      reason: '$viewport $key 顶部在可视列表内',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(list.bottom + 0.5),
      reason: '$viewport $key 底部在可视列表内',
    );
    expect(
      rect.left,
      greaterThanOrEqualTo(list.left - 0.5),
      reason: '$viewport $key 左侧未被裁切',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(list.right + 0.5),
      reason: '$viewport $key 右侧未被裁切',
    );
  }
  for (final label in ['已有预约准备', '返回准备', '提前进入专注', '取消预约']) {
    final rect = tester.getRect(find.text(label));
    expect(
      rect.bottom,
      lessThanOrEqualTo(list.bottom + 0.5),
      reason: '$viewport $label 完整可见',
    );
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  _Fixture fixture, {
  required double width,
  required double height,
  double topInset = 0,
  double bottomInset = 0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: topInset, bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(top: topInset, bottom: bottomInset);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PactaApp(
      authRepository: fixture.auth,
      taskRepositoryFactory: (_) => fixture.tasks,
      focusRepositoryFactory: (_) => fixture.focus,
      nationalFocusRepositoryFactory: (_) => fixture.tree,
      chainSignalsRepositoryFactory: (_) => fixture.signals,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDestination(WidgetTester tester, String label) async {
  final host = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _openFocusChain(WidgetTester tester) =>
    _openDestination(tester, '专注链');

Finder _chainScrollable(WidgetTester tester) => find.descendant(
  of: find.byKey(chainList),
  matching: find.byType(Scrollable),
);

double _maxScrollExtent(WidgetTester tester) {
  final state = tester.state<ScrollableState>(_chainScrollable(tester));
  return state.position.maxScrollExtent;
}

Future<void> _disposeWidget(WidgetTester tester) async {
  // ignore: avoid_print
  print('[focus-chain-test] dispose:start');
  await tester.pumpWidget(const SizedBox.shrink());
  // ignore: avoid_print
  print('[focus-chain-test] dispose:unmounted');
  await tester.pump(const Duration(milliseconds: 100));
  // ignore: avoid_print
  print('[focus-chain-test] dispose:done');
}

void _printBounds(WidgetTester tester, String viewport) {
  const keys = {
    'history': historyEntry,
    'table': chainTable,
    'signals': signalsSurface,
    'allowance': allowanceEntry,
    'note': focusChainNoteKey,
    'start': taskPickerEntry,
  };
  final inventory = <String, Object?>{
    'viewport': viewport,
    'maxScrollExtent': _maxScrollExtent(tester),
    'blocks': {
      for (final entry in keys.entries)
        entry.key: _rectJson(tester.getRect(find.byKey(entry.value))),
    },
  };
  // ignore: avoid_print
  print('[focus-chain-bounds] ${jsonEncode(inventory)}');
}

Map<String, double> _rectJson(Rect rect) => {
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
  'width': rect.width,
  'height': rect.height,
};

class _Fixture {
  _Fixture({
    required this.database,
    required this.auth,
    required this.tasks,
    required this.focus,
    required this.tree,
    required this.signals,
  });

  final PactaDatabase database;
  final FakeAuthRepository auth;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository tree;
  final ChainSignalsRepository signals;

  static Future<_Fixture> create() async {
    const userId = 'focus-first-screen';
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
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
    );
    final signals = ChainSignalsRepository(database: database, userId: userId);
    await signals.save(
      const ChainSignalTexts(
        focusMarker: '戴上耳机，坐到书桌前',
        appointmentTriggerSignal: '合上手机，倒一杯水',
      ),
    );
    await focus.createPrecedentRule(text: orderRule);
    await focus.createPrecedentRule(text: materialRule);
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '把重要的事情向前推进',
        classification: TaskClassification.both,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '阅读一章，留下三个要点',
        classification: TaskClassification.both,
        estimatedMinutes: 30,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '梳理明天的计划',
        classification: TaskClassification.regular,
        estimatedMinutes: 15,
      ),
    );
    for (final mode in [FocusChainMode.elite, FocusChainMode.regular]) {
      for (var round = 0; round < 3; round++) {
        await focus.startSession(
          taskId: task.id,
          mode: mode,
          duration: const Duration(minutes: 25),
        );
        now = now.add(const Duration(minutes: 25));
        await focus.settleDueSessions();
      }
    }
    return _Fixture(
      database: database,
      auth: FakeAuthRepository()..signedInUser = userId,
      tasks: tasks,
      focus: focus,
      tree: tree,
      signals: signals,
    );
  }

  Future<void> dispose() async {
    // The widget tree is already unmounted by the test; closing the database
    // releases its drift stream queries.
    await database.close();
  }
}
