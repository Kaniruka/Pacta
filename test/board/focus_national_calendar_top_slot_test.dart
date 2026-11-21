import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/board/focus_national_calendar_card.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';
import 'package:pacta/src/ui/pacta_hold_action_reorder.dart';

/// 工单 03：单栏顶槽「国策状态 ⇄ 置顶目标」胶囊切换。
///
/// 覆盖 0 置顶、全确认默认置顶、有待确认默认国策、点选日历自动切回、
/// 最多 2 条 + 查看全部 + 完整 ID 排序、目标读取失败、历史未知/失败与
/// 未来未到结算。
const _zone = 'Asia/Shanghai';

DateTime get _now => DateTime(2026, 11, 12, 10);

const _statusTab = ValueKey('board-top-slot-status');
const _pinnedTab = ValueKey('board-top-slot-pinned');

class _Harness {
  _Harness({
    this.cards = const [],
    this.failures = const [],
    this.pinned = const [],
    this.goalsFailed = false,
    this.failingCards = false,
  }) : national = _FakeNationalFocusRepository(
         cards: cards,
         failures: failures,
         failing: failingCards,
       ),
       focus = _FakeFocusRepository(),
       tasks = _FakeTaskRepository(pinned);

  final List<NationalFocusCard> cards;
  final List<NationalFocusFailure> failures;
  final List<Goal> pinned;
  final bool goalsFailed;
  final bool failingCards;
  final _FakeNationalFocusRepository national;
  final _FakeFocusRepository focus;
  final _FakeTaskRepository tasks;

  var openedTree = 0;
  var openedPlan = 0;
  var retries = 0;

  Widget build({
    List<Goal>? pinnedGoals,
    bool? pinnedGoalsFailed,
    double width = 420,
    bool readOnlyPinned = false,
    DateTime? initialMonth,
  }) {
    final goals = pinnedGoals ?? pinned;
    return MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: FocusNationalCalendarCard(
              focusRepository: focus,
              nationalFocusRepository: national,
              displayTimeZoneId: _zone,
              now: () => _now,
              onOpenNationalFocus: () => openedTree += 1,
              onRetryProjection: () => retries += 1,
              pinnedGoals: goals,
              pinnedGoalsFailed: pinnedGoalsFailed ?? goalsFailed,
              initialMonth: initialMonth,
              goalRepository: readOnlyPinned ? null : tasks,
              onOpenPlan: () => openedPlan += 1,
            ),
          ),
        ),
      ),
    );
  }
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _tapDay(WidgetTester tester, int day) async {
  final cell = find.byKey(ValueKey('board-focus-day-$day'));
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

PactaStatusBadge _badge(WidgetTester tester, String label) => tester
    .widget<PactaStatusBadge>(find.widgetWithText(PactaStatusBadge, label));

void main() {
  testWidgets('0 个置顶目标且读取正常：顶槽没有切换胶囊，直接显示动态国策状态', (tester) async {
    _useTallView(tester);
    final harness = _Harness(cards: [_card('lit', NationalFocusCardState.lit)]);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 零多余 chrome：切换条与置顶视图都不存在，也不出现「置顶目标」文案。
    expect(find.byKey(_statusTab), findsNothing);
    expect(find.byKey(_pinnedTab), findsNothing);
    expect(find.text('置顶目标'), findsNothing);
    expect(find.text('还没有置顶目标'), findsNothing);
    expect(find.text('今日国策状态'), findsOneWidget);
    expect(find.text('点亮 1'), findsOneWidget);
    // 顶槽仍在热力月历之上，且没有空占位把月历挤下去。
    final statusRect = tester.getRect(
      find.byKey(const ValueKey('board-today-national-focus')),
    );
    final heatTitle = tester.getRect(find.text('专注热力月历'));
    expect(statusRect.bottom, lessThanOrEqualTo(heatTitle.top));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('全部确认且有待置顶目标：默认优先展示置顶目标页签', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [
        _card('a', NationalFocusCardState.lit),
        _card('b', NationalFocusCardState.lit),
      ],
      pinned: [_goal('goal-a', '写周报'), _goal('goal-b', '读文档')],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('置顶目标 (2)'), findsOneWidget);
    expect(find.byKey(_pinnedTab), findsOneWidget);
    // Q8 #1：待确认数为 0 → 默认置顶目标，两条都在。
    expect(
      find.byKey(const ValueKey('board-pinned-goal-goal-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('board-pinned-goal-goal-b')),
      findsOneWidget,
    );
    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('读文档'), findsOneWidget);
    // 国策状态此刻不在屏上。
    expect(find.text('点亮 2'), findsNothing);
    // 两条以内不出现「查看全部」。
    expect(
      find.byKey(const ValueKey('board-top-slot-pinned-all')),
      findsNothing,
    );

    // 手动切回后尊重用户选择。
    await tester.tap(find.byKey(_statusTab));
    await tester.pumpAndSettle();
    expect(find.text('点亮 2'), findsOneWidget);
    expect(find.text('写周报'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('有待确认节点：默认展示国策状态而不是置顶目标', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [
        _card('a', NationalFocusCardState.lit),
        _card('b', NationalFocusCardState.pendingTodayConfirmation),
      ],
      pinned: [_goal('goal-a', '写周报')],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('今日国策状态'), findsOneWidget);
    expect(find.text('待确认 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('board-pinned-goal-goal-a')),
      findsNothing,
    );
    expect(find.text('置顶目标 (1)'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('国策树无节点时默认仍是国策状态，不把空树当成全部确认', (tester) async {
    _useTallView(tester);
    final harness = _Harness(pinned: [_goal('goal-a', '写周报')]);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('国策树尚无节点'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('board-pinned-goal-goal-a')),
      findsNothing,
    );
    await _unmount(tester);
  });

  testWidgets('停在置顶目标页签时点选日历日期自动切回国策状态', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '写周报')],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(find.text('写周报'), findsOneWidget);

    await _tapDay(tester, 9);
    // 点选即切回国策状态：历史日诚实显示未知，置顶视图让位。
    expect(find.text('11月9日国策记录'), findsOneWidget);
    expect(find.text('未知'), findsOneWidget);
    expect(find.text('写周报'), findsNothing);
    expect(find.text('专注与国策'), findsOneWidget);

    // 再点回今天：实时状态与计数回到顶槽。
    await _tapDay(tester, 12);
    expect(find.text('今日国策状态'), findsOneWidget);
    expect(find.text('点亮 1'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('最多显示 2 条置顶，第 3 条以后经「查看全部 N 个」去计划页', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [
        _goal('goal-a', '甲目标'),
        _goal('goal-b', '乙目标'),
        _goal('goal-c', '丙目标'),
        _goal('goal-d', '丁目标'),
        _goal('goal-e', '戊目标'),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('置顶目标 (5)'), findsOneWidget);
    expect(find.text('甲目标'), findsOneWidget);
    expect(find.text('乙目标'), findsOneWidget);
    expect(find.text('丙目标'), findsNothing);
    expect(find.text('丁目标'), findsNothing);
    expect(find.text('戊目标'), findsNothing);
    expect(
      find.byKey(const ValueKey('board-pinned-goal-goal-c')),
      findsNothing,
    );

    final all = find.byKey(const ValueKey('board-top-slot-pinned-all'));
    await tester.ensureVisible(all);
    await tester.pumpAndSettle();
    expect(find.text('查看全部 5 个 →'), findsOneWidget);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(harness.openedPlan, 1);
    await _unmount(tester);
  });

  testWidgets('重排前两条时写回全部置顶 ID，第 3..N 个原序保留', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [
        _goal('goal-a', '甲目标'),
        _goal('goal-b', '乙目标'),
        _goal('goal-c', '丙目标'),
        _goal('goal-d', '丁目标'),
        _goal('goal-e', '戊目标'),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    final list = tester.widget<PactaHoldReorderList>(
      find.byType(PactaHoldReorderList),
    );
    expect(list.itemCount, 2, reason: '顶槽只渲染前两条');
    expect(list.itemSpacing, 8);
    expect(list.proxyBorderRadius, PactaSpacing.cardRadius);
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('board-pinned-goal-goal-b')),
              )
              .dy -
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('board-pinned-goal-goal-a')),
              )
              .dy,
      8,
      reason: '间距由 itemSpacing 承担，卡片自身零 margin',
    );

    list.onReorder(0, 1);
    await tester.pumpAndSettle();

    // 完整 5 个 ID 全部写回：前两条交换，第 3..5 个按原序接在后面。
    expect(harness.tasks.reordered, hasLength(1));
    expect(harness.tasks.reordered.single, [
      'goal-b',
      'goal-a',
      'goal-c',
      'goal-d',
      'goal-e',
    ]);
    await _unmount(tester);
  });

  testWidgets('只有两个置顶目标时重排同样写回两条完整 ID', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '甲目标'), _goal('goal-b', '乙目标')],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    tester
        .widget<PactaHoldReorderList>(find.byType(PactaHoldReorderList))
        .onReorder(1, 0);
    await tester.pumpAndSettle();
    expect(harness.tasks.reordered.single, ['goal-b', 'goal-a']);
    await _unmount(tester);
  });

  testWidgets('长按置顶目标打开操作面板并可取消置顶', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '写周报')],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('写周报'));
    await tester.pumpAndSettle();
    expect(find.text('在计划中查看'), findsOneWidget);
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    expect(harness.tasks.unpinned, ['goal-a']);
    await _unmount(tester);
  });

  testWidgets('目标列表读取失败：切换栏只写置顶目标并可只读重试', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      goalsFailed: true,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 失败时不能写成「置顶目标 (0)」：条数未知。
    expect(find.text('置顶目标'), findsOneWidget);
    expect(find.text('置顶目标 (0)'), findsNothing);
    await tester.tap(find.byKey(_pinnedTab));
    await tester.pumpAndSettle();
    expect(find.text('暂时不能读取目标列表。'), findsOneWidget);
    expect(find.text('还没有置顶目标'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('board-top-slot-pinned-retry')));
    await tester.pumpAndSettle();
    expect(harness.retries, 1);
    await _unmount(tester);
  });

  testWidgets('历史日有失败记录给 warning 胶囊与最多三行明细，未来日未到结算', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      failures: [
        for (var index = 0; index < 4; index++)
          _failure(
            id: 'failure-$index',
            cardId: 'card-$index',
            cardName: '节点$index',
            checkpointAt: DateTime.utc(2026, 11, 9, 4 + index),
          ),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await _tapDay(tester, 9);
    expect(find.text('11月9日国策记录'), findsOneWidget);
    expect(_badge(tester, '有失败记录').tone, PactaStatusBadgeTone.warning);
    expect(find.text('节点0 · 未完成今日确认'), findsOneWidget);
    expect(find.text('节点1 · 未完成今日确认'), findsOneWidget);
    expect(find.text('节点2 · 未完成今日确认'), findsOneWidget);
    expect(find.text('节点3 · 未完成今日确认'), findsNothing);
    expect(find.text('等 4 个节点'), findsOneWidget);
    expect(find.text('未知'), findsNothing);

    await _tapDay(tester, 20);
    expect(find.text('11月20日国策状态'), findsOneWidget);
    expect(_badge(tester, '未到结算').tone, PactaStatusBadgeTone.neutral);
    expect(find.text('未来日期还没有结算数据，不预先推断结果。'), findsOneWidget);
    expect(find.text('有失败记录'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('360dp 首屏：两条置顶在顶槽里，热力月历仍完整落在首屏', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '甲目标'), _goal('goal-b', '乙目标')],
    );
    await tester.pumpWidget(harness.build(width: 360));
    await tester.pumpAndSettle();

    // 默认置顶目标页签，两条都在；热力月历的标题与第一行日格仍在 800dp
    // 首屏之内，置顶目标没有把它挤出屏幕。
    expect(find.text('甲目标'), findsOneWidget);
    expect(find.text('乙目标'), findsOneWidget);
    final heatTitle = tester.getRect(find.text('专注热力月历'));
    expect(heatTitle.bottom, lessThan(800));
    final firstRow = tester.getRect(
      find.byKey(const ValueKey('board-focus-day-1')),
    );
    expect(firstRow.top, lessThan(800));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('320dp 2 倍字号：胶囊与置顶视图不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [
        _goal('goal-a', '一个相当长的置顶目标名称用于验证两倍字号下的换行'),
        _goal('goal-b', '乙目标'),
        _goal('goal-c', '丙目标'),
      ],
    );
    await tester.pumpWidget(harness.build(width: 320));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(_statusTab), findsOneWidget);
    expect(find.byKey(_pinnedTab), findsOneWidget);
    expect(find.text('查看全部 3 个 →'), findsOneWidget);
    // 换行只发生在文本内部，卡片仍完整落在 320 视口内。
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('board-focus-national-card')),
    );
    expect(cardRect.right, lessThanOrEqualTo(320));
    await _unmount(tester);
  });

  testWidgets('历史日失败流读取失败时仍是未知，不推断为全部确认', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      failures: const [],
      failingCards: false,
      pinned: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: FocusNationalCalendarCard(
                focusRepository: harness.focus,
                nationalFocusRepository: _FailingFailuresRepository(),
                displayTimeZoneId: _zone,
                now: () => _now,
                onOpenNationalFocus: () {},
                onRetryProjection: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapDay(tester, 9);
    expect(find.text('11月9日国策记录'), findsOneWidget);
    expect(_badge(tester, '未知').tone, PactaStatusBadgeTone.neutral);
    expect(find.text('暂时不能读取国策失败记录，历史日期一律标记为未知。'), findsOneWidget);
    expect(find.text('有失败记录'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('只读多置顶：两张卡片之间保留 8dp，不贴成一整块', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '甲目标'), _goal('goal-b', '乙目标')],
    );
    await tester.pumpWidget(harness.build(readOnlyPinned: true));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('board-pinned-goal-goal-a'));
    final second = find.byKey(const ValueKey('board-pinned-goal-goal-b'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(
      tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy,
      greaterThanOrEqualTo(PactaSpacing.sm),
      reason: 'CardThemeData.margin 为零：只读多置顶必须靠 SizedBox 分开',
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('停用账号取消置顶只弹可读提示，不丢未捕获异常', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '写周报')],
    )..tasks.writeError = const UserOperationsSuspendedException();
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('写周报'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();

    expect(find.text('用户已停用，恢复前不能创建或修改业务数据。'), findsOneWidget);
    expect(harness.tasks.unpinned, isEmpty, reason: '停用账号不写入');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('停用账号重排只弹可读提示，不丢未捕获异常', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '甲目标'), _goal('goal-b', '乙目标')],
    )..tasks.writeError = const UserOperationsSuspendedException();
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    tester
        .widget<PactaHoldReorderList>(find.byType(PactaHoldReorderList))
        .onReorder(0, 1);
    await tester.pumpAndSettle();

    expect(find.text('用户已停用，恢复前不能创建或修改业务数据。'), findsOneWidget);
    expect(harness.tasks.reordered, isEmpty, reason: '停用账号不写入顺序');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('31 日月份点选后切入 2 月：选中日重置到当月合法日期', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      pinned: [_goal('goal-a', '写周报')],
    );
    await tester.pumpWidget(harness.build(initialMonth: DateTime.utc(2027, 1)));
    await tester.pumpAndSettle();
    expect(find.text('2027年1月'), findsOneWidget);

    await _tapDay(tester, 31);
    expect(find.text('1月31日国策状态'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('board-focus-next-month')));
    await tester.pumpAndSettle();
    expect(find.text('2027年2月'), findsOneWidget);
    // 2 月没有 31 日：选中日必须重置到当月合法日期，而不是留下非法 day。
    expect(find.byKey(const ValueKey('board-focus-day-31')), findsNothing);
    expect(find.text('1月31日国策状态'), findsNothing);
    expect(find.text('2月12日国策状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('失败记录找不到卡名时显示已移除的国策卡，不暴露内部 UUID', (tester) async {
    _useTallView(tester);
    final harness = _Harness(
      cards: [_card('a', NationalFocusCardState.lit)],
      failures: [
        NationalFocusFailure(
          id: 'removed-failure',
          batchId: 'removed-batch',
          cardId: 'card-uuid-removed',
          checkpointAt: DateTime.utc(2026, 11, 9, 4),
          cause: NationalFocusFailureCause.missedConfirmation,
          failureReason: null,
          sharedExplanation: null,
          treeSnapshot: const [],
        ),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await _tapDay(tester, 9);
    expect(find.textContaining('已移除的国策卡'), findsOneWidget);
    expect(find.textContaining('card-uuid-removed'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}

class _FakeFocusRepository extends UnavailableFocusRepository {
  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) => Stream.value(_metrics(month, {12: 780}, timeZoneId));
}

class _FakeNationalFocusRepository extends UnavailableNationalFocusRepository {
  _FakeNationalFocusRepository({
    required this.cards,
    required this.failures,
    required this.failing,
  });

  final List<NationalFocusCard> cards;
  final List<NationalFocusFailure> failures;
  final bool failing;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() =>
      failing ? Stream.error(StateError('cards failed')) : Stream.value(cards);

  @override
  Stream<List<NationalFocusFailure>> watchFailures() => Stream.value(failures);

  @override
  Future<void> settleDueCheckpoints() async {}
}

class _FailingFailuresRepository extends UnavailableNationalFocusRepository {
  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(const []);

  @override
  Stream<List<NationalFocusFailure>> watchFailures() =>
      Stream.error(StateError('failures failed'));

  @override
  Future<void> settleDueCheckpoints() async {}
}

class _FakeTaskRepository extends UnavailableTaskRepository {
  _FakeTaskRepository(this.pinned);

  final List<Goal> pinned;
  final reordered = <List<String>>[];
  final unpinned = <String>[];

  /// 非空时模拟停用账号/参数不合法：写回直接抛这个异常。
  Object? writeError;

  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) =>
      Stream.value(pinned);

  @override
  Future<void> reorderPinnedGoals(List<String> orderedGoalIds) async {
    final error = writeError;
    if (error != null) throw error;
    reordered.add(List<String>.of(orderedGoalIds));
  }

  @override
  Future<void> setGoalPinned(String goalId, {required bool isPinned}) async {
    final error = writeError;
    if (error != null) throw error;
    if (!isPinned) unpinned.add(goalId);
  }
}

FocusMonthMetrics _metrics(
  DateTime month,
  Map<int, int> seconds,
  String timeZoneId,
) {
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
    days: days,
    totalActiveSeconds: days.fold(0, (sum, day) => sum + day.activeSeconds),
    activeDayCount: days.where((day) => day.activeSeconds > 0).length,
  );
}

Goal _goal(String id, String title) => Goal(
  id: id,
  title: title,
  classification: TaskClassification.regular,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  isPinned: true,
);

NationalFocusCard _card(String id, NationalFocusCardState state) =>
    NationalFocusCard(
      id: id,
      name: id,
      triggerCondition: id,
      action: '行动',
      isInTree: true,
      state: state,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      currentConsecutiveDays: 5,
    );

NationalFocusFailure _failure({
  required String id,
  required String cardId,
  required String cardName,
  required DateTime checkpointAt,
}) => NationalFocusFailure(
  id: id,
  batchId: 'batch-$id',
  cardId: cardId,
  checkpointAt: checkpointAt,
  cause: NationalFocusFailureCause.missedConfirmation,
  failureReason: null,
  sharedExplanation: null,
  treeSnapshot: [
    NationalFocusCardSnapshot(
      id: cardId,
      name: cardName,
      triggerCondition: '开始前',
      action: '写一步',
      isInTree: true,
      state: NationalFocusCardState.pendingTodayConfirmation,
      successfulDays: 1,
      currentConsecutiveDays: 0,
      bestConsecutiveDays: 1,
      maintenanceCycleStarted: true,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 11, 9),
    ),
  ],
);
