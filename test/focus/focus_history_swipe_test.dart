import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/app/app_providers.dart';
import 'package:pacta/src/focus/focus_chain_history.dart';
import 'package:pacta/src/focus/focus_chain_page.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

/// 工单 06：专注历史三链左右滑动 + 默认落点与流刷新不覆写。
void main() {
  testWidgets('首次数据落到第一条有记录的链，触控横滑三链双向联动', (tester) async {
    final focus = _HistoryFocusRepository(
      appointments: [
        _appointment(
          id: 'appointment-1',
          mode: FocusChainMode.regular,
          at: DateTime.utc(2026, 11, 15, 11),
        ),
      ],
    );
    addTearDown(focus.close);
    await _pumpHistory(tester, focus);
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();

    // 精锐链没有记录，默认直接落在普通链：不先闪一下精锐链空态。
    final controller = _pagerController(tester);
    expect(controller.page, 1.0);
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    expect(find.text('当前连续 2 次'), findsOneWidget);
    expect(find.text('精锐链还没有连胜记录。'), findsNothing);

    final pager = find.byKey(const ValueKey('focus-history-pager'));

    // 左滑到预约链。
    await tester.drag(pager, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(controller.page, 2.0);
    expect(find.textContaining('预约成功'), findsOneWidget);
    expect(find.text('当前连续 2 次'), findsNothing);

    // 已在最后一页，继续左滑仍停在预约链，不越界。
    await tester.drag(pager, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(controller.page, 2.0);

    // 右滑回普通链，再右滑到精锐链空态。
    await tester.drag(pager, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    expect(controller.page, 1.0);
    expect(find.text('当前连续 2 次'), findsOneWidget);

    await tester.drag(pager, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.elite});
    expect(controller.page, 0.0);
    expect(find.text('精锐链还没有连胜记录。'), findsOneWidget);

    // 点选胶囊与滑动共用同一 PageController：高亮与页面同步。
    await tester.tap(find.text('预约链'));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(controller.page, 2.0);
    expect(find.textContaining('预约成功'), findsOneWidget);

    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    expect(controller.page, 1.0);
    expect(find.text('当前连续 2 次'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标按住横拖同样能切换三链', (tester) async {
    final focus = _HistoryFocusRepository();
    addTearDown(focus.close);
    await _pumpHistory(tester, focus);
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();

    final pager = find.byKey(const ValueKey('focus-history-pager'));
    await tester.drag(
      pager,
      const Offset(-400, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });

    await tester.drag(
      pager,
      const Offset(400, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    expect(tester.takeException(), isNull);
  });

  testWidgets('用户滑动后流刷新不再改写选中链与页码', (tester) async {
    final focus = _HistoryFocusRepository();
    addTearDown(focus.close);
    await _pumpHistory(tester, focus);
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('focus-history-pager')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(_pagerController(tester).page, 2.0);

    // 新记录到达：即使精锐链从空变有，默认规则也只负责首帧，不再覆写。
    focus.emitSessions([
      ..._regularSessions(),
      _completedSession(
        id: 'elite-late',
        mode: FocusChainMode.elite,
        at: DateTime.utc(2026, 11, 15, 12),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(_pagerController(tester).page, 2.0);
    expect(find.text('预约链还没有连胜记录。'), findsOneWidget);

    // 主动点选精锐链才切换，且新到达的记录已经可读。
    await tester.tap(find.text('精锐链'));
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.elite});
    expect(_pagerController(tester).page, 0.0);
    expect(find.text('当前连续 1 次'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280x800 宽屏左留白鼠标横拖也能切链', (tester) async {
    final focus = _HistoryFocusRepository();
    addTearDown(focus.close);
    await _pumpHistory(tester, focus, size: const Size(1280, 800));
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();
    expect(_pagerController(tester).page, 1.0, reason: '默认落在普通链');

    // 阅读线只有 800dp：x 落在最左侧留白里，页面依旧能接住鼠标横拖。
    final pagerRect = tester.getRect(
      find.byKey(const ValueKey('focus-history-pager')),
    );
    final blankPoint = Offset(pagerRect.left + 4, pagerRect.center.dy);
    await tester.dragFrom(
      blankPoint,
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(_pagerController(tester).page, 2.0);

    await tester.dragFrom(
      blankPoint,
      const Offset(300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    expect(_pagerController(tester).page, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift+滚轮与横向滚轮切链，竖直滚轮不抢', (tester) async {
    final focus = _HistoryFocusRepository();
    addTearDown(focus.close);
    await _pumpHistory(tester, focus, size: const Size(1280, 800));
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();
    final pager = find.byKey(const ValueKey('focus-history-pager'));
    final center = tester.getCenter(pager);

    // 普通竖直滚轮交给时间轴列表，不切链。
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(_pagerController(tester).page, 1.0, reason: '竖直滚轮不抢分页');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 100),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(-100, 0),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    expect(tester.takeException(), isNull);
  });

  testWidgets('方向键与 Ctrl+Tab 切链，两端钳位', (tester) async {
    final focus = _HistoryFocusRepository();
    addTearDown(focus.close);
    await _pumpHistory(tester, focus, size: const Size(1280, 800));
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_pagerController(tester).page, 2.0, reason: '末端 → 不循环');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{FocusChainType.regular});
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入框与上方弹窗都不让背景链翻页', (tester) async {
    final focus = _HistoryFocusRepository();
    addTearDown(focus.close);
    await _pumpHistory(
      tester,
      focus,
      size: const Size(1280, 800),
      leading: const Material(
        color: Colors.transparent,
        child: SizedBox(
          height: 56,
          child: TextField(key: ValueKey('history-leading-field')),
        ),
      ),
    );
    focus.emitSessions(_regularSessions());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-leading-field')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('history-leading-field')),
      '正在输入',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_pagerController(tester).page, 1.0, reason: '输入中不抢方向键');

    // 弹窗盖在页面上：背景页不是当前路由，方向键不应切链。
    final pageContext = tester.element(find.byType(FocusHistoryPage));
    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (context) => const AlertDialog(title: Text('历史页上的弹窗')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('历史页上的弹窗'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_pagerController(tester).page, 1.0, reason: '弹窗盖住时不切链');

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('历史页上的弹窗'), findsNothing);
    // 弹窗关掉后焦点仍在输入框：方向键继续归文本编辑器。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_pagerController(tester).page, 1.0, reason: '输入框仍持有焦点');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_selectedChain(tester), <FocusChainType>{
      FocusChainType.appointment,
    });
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHistory(
  WidgetTester tester,
  _HistoryFocusRepository focus, {
  Size size = const Size(480, 1000),
  Widget? leading,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const page = FocusHistoryPage();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        focusRepositoryProvider.overrideWithValue(focus),
        taskRepositoryProvider.overrideWithValue(
          _TaskRepository([_goalWithTask()]),
        ),
      ],
      child: MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: leading == null
            ? page
            : Column(
                children: [
                  leading,
                  const Expanded(child: page),
                ],
              ),
      ),
    ),
  );
  await tester.pump();
}

PageController _pagerController(WidgetTester tester) => tester
    .widget<PageView>(find.byKey(const ValueKey('focus-history-pager')))
    .controller!;

Set<FocusChainType> _selectedChain(WidgetTester tester) => tester
    .widget<SegmentedButton<FocusChainType>>(
      find.byKey(const ValueKey('focus-history-chain-switch')),
    )
    .selected;

List<FocusSession> _regularSessions() => [
  _completedSession(
    id: 'regular-1',
    mode: FocusChainMode.regular,
    at: DateTime.utc(2026, 11, 15, 9),
  ),
  _completedSession(
    id: 'regular-2',
    mode: FocusChainMode.regular,
    at: DateTime.utc(2026, 11, 15, 10),
  ),
];

FocusSession _completedSession({
  required String id,
  required FocusChainMode mode,
  required DateTime at,
}) => FocusSession(
  id: id,
  taskId: 'task-1',
  mode: mode,
  durationSeconds: 1500,
  startedAt: at.subtract(const Duration(minutes: 25)),
  endsAt: at,
  status: FocusSessionStatus.completed,
  completedAt: at,
  effectiveSeconds: 1500,
);

AppointmentPreparation _appointment({
  required String id,
  required FocusChainMode mode,
  required DateTime at,
}) => AppointmentPreparation(
  id: id,
  taskId: 'task-1',
  mode: mode,
  durationSeconds: 900,
  startedAt: at.subtract(const Duration(minutes: 15)),
  endsAt: at,
  status: AppointmentPreparationStatus.succeeded,
  settledAt: at,
  updatedAt: at,
  preparationSeconds: 900,
);

Goal _goalWithTask() {
  final createdAt = DateTime.utc(2026, 11, 1);
  return Goal(
    id: 'goal-1',
    title: '每日精进',
    classification: TaskClassification.both,
    createdAt: createdAt,
    updatedAt: createdAt,
    tasks: [
      Task(
        id: 'task-1',
        goalId: 'goal-1',
        title: '整理笔记',
        classification: TaskClassification.regular,
        estimatedMinutes: 30,
        deadline: null,
        isComplete: false,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );
}

class _HistoryFocusRepository extends UnavailableFocusRepository {
  _HistoryFocusRepository({this.appointments = const []});

  final List<AppointmentPreparation> appointments;
  final _sessions = StreamController<List<FocusSession>>.broadcast();

  @override
  Stream<List<FocusSession>> watchSessions() => _sessions.stream;

  @override
  Future<List<FocusNode>> getNodes() async => const [];

  @override
  Future<List<AppointmentPreparation>> getAppointments() async => appointments;

  void emitSessions(List<FocusSession> sessions) => _sessions.add(sessions);

  void close() {
    unawaited(_sessions.close());
  }
}

class _TaskRepository extends UnavailableTaskRepository {
  _TaskRepository(this.goals);

  final List<Goal> goals;

  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) =>
      Stream.value(goals);
}
