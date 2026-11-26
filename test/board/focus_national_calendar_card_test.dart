import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/board/focus_national_calendar_card.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/theme/pacta_calendar_colors.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_check_circle.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';

/// 工单 09：看板「专注与国策」融合卡片。
///
/// 覆盖今日国策点击、切月、5 档热力分级、历史无失败日必须显式渲染“未知”、
/// 有失败日的角标与记录、今日+选中只有一层 2dp 蓝色描边。
const _zone = 'Asia/Shanghai';

DateTime get _now => DateTime(2026, 11, 12, 10);

class _Harness {
  _Harness({
    List<NationalFocusCard> cards = const [],
    List<NationalFocusFailure> failures = const [],
    Map<int, int> seconds = const {},
    this.failing = false,
  }) : national = _FakeNationalFocusRepository(
         cards: cards,
         failures: failures,
       ),
       focus = _FakeFocusRepository(seconds: seconds, failing: failing);

  final _FakeNationalFocusRepository national;
  final _FakeFocusRepository focus;
  bool failing;

  var openedTree = 0;
  var retries = 0;

  Widget build({
    String? displayTimeZoneId = _zone,
    double width = 420,
    ScheduleRepository? schedules,
  }) {
    return MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: FocusNationalCalendarCard(
              focusRepository: focus,
              nationalFocusRepository: national,
              scheduleRepository: schedules,
              displayTimeZoneId: displayTimeZoneId,
              now: () => _now,
              onOpenNationalFocus: () => openedTree += 1,
              onRetryProjection: () => retries += 1,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

BoxDecoration _cellDecoration(WidgetTester tester, int day) {
  final ink = tester.widget<Ink>(
    find
        .descendant(
          of: find.byKey(ValueKey('board-focus-day-$day')),
          matching: find.byType(Ink),
        )
        .first,
  );
  return ink.decoration! as BoxDecoration;
}

Color? _cellColor(WidgetTester tester, int day) =>
    _cellDecoration(tester, day).color;

Border? _cellBorder(WidgetTester tester, int day) =>
    _cellDecoration(tester, day).border as Border?;

int _borderedLayerCount(WidgetTester tester, int day) => find
    .descendant(
      of: find.byKey(ValueKey('board-focus-day-$day')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration?)?.border != null,
      ),
    )
    .evaluate()
    .length;

void main() {
  final colors = PactaCalendarColors.light;

  testWidgets('5 档热力按专注时长铺底色，表头、图例与今天角标齐全', (tester) async {
    final harness = _Harness(
      seconds: {1: 0, 2: 60, 3: 1800, 4: 5400, 5: 10800, 12: 780},
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('专注与国策'), findsOneWidget);
    expect(find.text('专注热力月历'), findsOneWidget);
    // 完整年月只在热力月历的切换器里出现一次，卡片头不再重复一枚月份按钮。
    expect(find.text('2026年11月'), findsOneWidget);
    for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
      expect(find.text(label), findsOneWidget, reason: '星期表头 $label');
    }
    expect(_cellColor(tester, 1), colors.heat0Background);
    expect(_cellColor(tester, 2), colors.heat1Background);
    expect(_cellColor(tester, 3), colors.heat2Background);
    expect(_cellColor(tester, 4), colors.heat3Background);
    expect(_cellColor(tester, 5), colors.heat4Background);
    for (var level = 0; level <= 4; level++) {
      expect(find.byKey(ValueKey('pacta-heat-legend-$level')), findsOneWidget);
    }
    expect(find.text('专注时长：按颜色深浅区分'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-focus-day-12')),
        matching: find.text('今'),
      ),
      findsOneWidget,
    );
    // 默认选中本月今天，详情给出真实时长。
    expect(find.text('11 月 12 日（今日）'), findsOneWidget);
    expect(find.text('13分钟'), findsOneWidget);
    // 今日汇总只属于卡片顶部的「今日国策状态」，日期详情不再复述一次。
    expect(find.text('国策记录'), findsNothing);
    // 不传安排仓储就完全不渲染安排区块：不猜“有没有安排”。
    expect(find.textContaining('安排'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('今天且选中只有一层 2dp 蓝色描边与独立今角标', (tester) async {
    final harness = _Harness(seconds: {12: 780});
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    final border = _cellBorder(tester, 12)!;
    expect(border.top.width, 2);
    expect(border.top.color, colors.selectedBorder);
    expect(_borderedLayerCount(tester, 12), 0, reason: '不允许第二层内嵌描边');
    expect(_cellColor(tester, 12), colors.heat1Background);

    // 点选历史普通日：热力底色保留，描边仍是同一层 2dp 主蓝。
    await tester.tap(find.byKey(const ValueKey('board-focus-day-10')));
    await tester.pumpAndSettle();
    final historyBorder = _cellBorder(tester, 10)!;
    expect(historyBorder.top.width, 2);
    expect(historyBorder.top.color, colors.selectedBorder);
    expect(_borderedLayerCount(tester, 10), 0);
    // 今天回到未选中：中性 1.5dp 单层描边。
    final todayBorder = _cellBorder(tester, 12)!;
    expect(todayBorder.top.width, 1.5);
    expect(todayBorder.top.color, colors.todayBorder);
    expect(find.text('11 月 10 日'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('点击历史无失败记录日必须显式显示未知，而不是已完成', (tester) async {
    final harness = _Harness(seconds: {9: 900});
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('board-focus-day-9')));
    await tester.pumpAndSettle();

    expect(find.text('未知'), findsOneWidget);
    expect(find.text('有失败记录'), findsNothing);
    expect(find.text('全点亮'), findsNothing);
    expect(find.text('存在已确认'), findsNothing);
    expect(find.text('历史日期只显示实际有数据支持的记录；没有记录时明确标记为未知。'), findsOneWidget);
    expect(find.text('15分钟'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('未来日期显示未到结算，不预先推断结果', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('board-focus-day-20')));
    await tester.pumpAndSettle();

    expect(find.text('未到结算'), findsOneWidget);
    expect(find.text('未知'), findsNothing);
    expect(find.text('未来日期还没有结算数据，不预先推断结果。'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('有失败记录的历史日渲染角标、失败记录与节点名', (tester) async {
    final harness = _Harness(
      failures: [
        _failure(
          id: 'failure-1',
          cardId: 'card-1',
          cardName: '先写第一步',
          checkpointAt: DateTime.utc(2026, 11, 5, 20),
          cause: NationalFocusFailureCause.missedConfirmation,
        ),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('board-focus-failure-dot-6')),
      findsOneWidget,
      reason: '20:00Z 在上海是 11 月 6 日，失败细短杠落在 6 日',
    );
    expect(
      find.byKey(const ValueKey('board-focus-failure-dot-7')),
      findsNothing,
    );
    // 右上角不再挂任何孤立标记：失败标已经整体移到底部指示轨。
    final failureRect = tester.getRect(
      find.byKey(const ValueKey('board-focus-failure-dot-6')),
    );
    final cellRect = tester.getRect(
      find.byKey(const ValueKey('board-focus-day-6')),
    );
    final numberRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('board-focus-day-6')),
        matching: find.text('6'),
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-focus-day-6')),
        matching: find.byType(Row),
      ),
      findsWidgets,
    );
    expect(
      failureRect.top,
      greaterThanOrEqualTo(numberRect.bottom - 0.01),
      reason: '失败标必须位于日期数字下方，而不是右上角顶栏',
    );
    expect(failureRect.top, greaterThan(cellRect.top + 12));
    expect(
      failureRect.width,
      greaterThan(failureRect.height),
      reason: '失败标是横向细短杠，不是圆形红点',
    );
    expect(failureRect.width, closeTo(10, 0.01));
    expect(failureRect.height, closeTo(3, 0.01));
    final failureBar = tester.widget<Container>(
      find.byKey(const ValueKey('board-focus-failure-dot-6')),
    );
    final failureDecoration = failureBar.decoration! as BoxDecoration;
    expect(failureDecoration.color, colors.failureDotColor);
    expect(
      (failureDecoration.borderRadius! as BorderRadius).topLeft.x,
      greaterThan(failureRect.height),
      reason: '细短杠两端必须是胶囊圆角，不是方角',
    );
    // 6 日没有专注投入（heat0），失败短杠不需要托底光晕。
    expect(
      find.byKey(const ValueKey('board-focus-failure-halo-6')),
      findsNothing,
    );
    expect(_borderedLayerCount(tester, 6), 0, reason: '底部指示轨不得引入第二层描边');

    await tester.tap(find.byKey(const ValueKey('board-focus-day-6')));
    await tester.pumpAndSettle();

    expect(find.text('有失败记录'), findsOneWidget);
    expect(find.text('先写第一步（未完成今日确认）'), findsOneWidget);
    expect(find.text('未知'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('今日国策状态整卡可点，计数胶囊与摘要诚实', (tester) async {
    final harness = _Harness(
      cards: [
        _card('lit', NationalFocusCardState.lit),
        _card('pending', NationalFocusCardState.pendingTodayConfirmation),
        _card('out', NationalFocusCardState.extinguished),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.text('今日国策状态'), findsOneWidget);
    expect(find.text('实时状态'), findsOneWidget);
    expect(find.text('点亮 1'), findsOneWidget);
    expect(find.text('待确认 1'), findsOneWidget);
    expect(find.text('熄灭 1'), findsOneWidget);
    expect(find.text('点击查看国策树及具体节点状态 →'), findsOneWidget);
    // 今日选中时数字只在顶部出现一次：日期详情既不重复胶囊，也不重复
    // 「点亮 X · 待确认 Y · 熄灭 Z」这一行。
    expect(find.text('存在已熄灭'), findsNothing);
    expect(find.text('存在待确认'), findsNothing);
    expect(find.text('全点亮'), findsNothing);
    expect(find.text('暂无国策'), findsNothing);
    expect(find.textContaining('点亮 1 · 待确认 1'), findsNothing);
    expect(find.text('国策记录'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('board-today-national-focus')));
    await tester.pumpAndSettle();
    expect(harness.openedTree, 1);
    await _unmount(tester);
  });

  testWidgets('今日详情不再复述国策结论，历史日仍显式未知、未来日仍未到结算', (tester) async {
    final lit = _Harness(
      cards: [
        _card('a', NationalFocusCardState.lit),
        _card('b', NationalFocusCardState.lit),
      ],
    );
    await tester.pumpWidget(lit.build());
    await tester.pumpAndSettle();
    // 顶部只说实时计数；「全点亮」这类结论在今日不再重复第二遍。
    expect(find.text('点亮 2'), findsOneWidget);
    expect(find.text('全点亮'), findsNothing);
    expect(find.text('国策记录'), findsNothing);
    await _unmount(tester);

    final empty = _Harness();
    await tester.pumpWidget(empty.build());
    await tester.pumpAndSettle();
    expect(find.text('国策树尚无节点'), findsOneWidget);
    expect(find.text('暂无国策'), findsNothing);

    // 同一次切换里历史日与未来日仍保留各自诚实的结论：标题随选中日
    // 变成「X月X日国策记录」，日期详情不再重复第二个结论区块。
    await tester.tap(find.byKey(const ValueKey('board-focus-day-9')));
    await tester.pumpAndSettle();
    expect(find.text('11月9日国策记录'), findsOneWidget);
    expect(find.text('未知'), findsOneWidget);
    expect(find.text('国策记录'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('board-focus-day-20')));
    await tester.pumpAndSettle();
    expect(find.text('未到结算'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('切月按新月份重新查询，并回到该月默认日', (tester) async {
    final harness = _Harness(seconds: {12: 780});
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(harness.focus.requests.single.$2, DateTime.utc(2026, 11));

    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年12月'), findsOneWidget);
    expect(harness.focus.requests.last.$2, DateTime.utc(2026, 12));
    expect(harness.focus.requests.last.$1, _zone);
    expect(find.text('12 月 1 日'), findsOneWidget);

    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(harness.focus.requests.last.$2, DateTime.utc(2026, 10));
    expect(find.text('2026年10月'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('账号时区未解析时不发起投影查询，只显示就地加载', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build(displayTimeZoneId: null));
    await tester.pump();

    expect(harness.focus.requests, isEmpty);
    expect(find.text('月份待确认'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FocusNationalCalendarCard),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsWidgets,
    );
    // 加载态同样只保留标题：没有可确认的日期就不编造副文本。
    expect(find.text('日期详情'), findsOneWidget);
    expect(
      tester
          .widget<PactaSectionHeader>(find.byType(PactaSectionHeader))
          .trailing,
      isNull,
    );
    expect(find.text('正在读取专注投影…'), findsOneWidget);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(harness.focus.requests, hasLength(1));
    expect(find.text('2026年11月'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('320 宽 2 倍字号仍完整呈现且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = _Harness(
      seconds: {12: 780},
      cards: [_card('lit', NationalFocusCardState.lit)],
    );
    await tester.pumpWidget(harness.build(width: 320));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('专注与国策'), findsOneWidget);
    expect(find.text('今日国策状态'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-focus-day-12')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('读取失败显示可读错误与只读重试', (tester) async {
    final harness = _Harness(failing: true);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 热力区与日期详情都必须报错：日期详情不得停在「正在读取」假装还在加载。
    expect(find.text('暂时不能读取专注投影。'), findsOneWidget);
    expect(find.text('暂时不能读取这一天的专注记录。'), findsOneWidget);
    expect(find.text('正在读取专注投影…'), findsNothing);
    expect(find.byKey(const ValueKey('board-focus-day-12')), findsNothing);
    // 失败态保留分区标题，但不编造日期副文本。
    expect(find.text('日期详情'), findsOneWidget);
    expect(
      tester
          .widget<PactaSectionHeader>(find.byType(PactaSectionHeader))
          .trailing,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('board-focus-heat-retry')));
    await tester.pumpAndSettle();
    expect(harness.retries, 1);
    await tester.tap(
      find.byKey(const ValueKey('board-focus-day-detail-retry')),
    );
    await tester.pumpAndSettle();
    expect(harness.retries, 2);
    await _unmount(tester);
  });

  testWidgets('国策读取失败时顶部胶囊改为读取失败，不亮绿色实时状态', (tester) async {
    final focus = _FakeFocusRepository(seconds: const {});
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: FocusNationalCalendarCard(
                focusRepository: focus,
                nationalFocusRepository: _FailingNationalFocusRepository(),
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

    // 失败态必须是可读的「读取失败」，不能继续伪装成绿色「实时状态」。
    expect(find.text('实时状态'), findsNothing);
    expect(find.text('读取中'), findsNothing);
    final badge = tester.widget<PactaStatusBadge>(
      find.widgetWithText(PactaStatusBadge, '读取失败'),
    );
    expect(badge.tone, PactaStatusBadgeTone.warning);
    expect(find.text('国策状态暂不可用。'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('加载中顶部胶囊是中性读取中，成功后才是绿色实时状态', (tester) async {
    final pendingCards = StreamController<List<NationalFocusCard>>();
    final pendingFailures = StreamController<List<NationalFocusFailure>>();
    addTearDown(pendingCards.close);
    addTearDown(pendingFailures.close);
    final pending = _StreamNationalFocusRepository(
      cards: pendingCards.stream,
      failures: pendingFailures.stream,
    );
    final focus = _FakeFocusRepository(seconds: const {12: 780});
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: FocusNationalCalendarCard(
                focusRepository: focus,
                nationalFocusRepository: pending,
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
    await tester.pump();

    expect(find.text('实时状态'), findsNothing);
    final loading = tester.widget<PactaStatusBadge>(
      find.widgetWithText(PactaStatusBadge, '读取中'),
    );
    expect(loading.tone, PactaStatusBadgeTone.neutral);

    pendingCards.add([_card('lit', NationalFocusCardState.lit)]);
    pendingFailures.add(const <NationalFocusFailure>[]);
    await tester.pumpAndSettle();

    expect(find.text('读取中'), findsNothing);
    final ready = tester.widget<PactaStatusBadge>(
      find.widgetWithText(PactaStatusBadge, '实时状态'),
    );
    expect(ready.tone, PactaStatusBadgeTone.success);
    expect(find.text('点亮 1'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('换国策仓储时丢弃旧仓储的点亮数与失败标记', (tester) async {
    final first = _FakeNationalFocusRepository(
      cards: [_card('lit', NationalFocusCardState.lit)],
      failures: [
        _failure(
          id: 'failure-swap',
          cardId: 'lit',
          cardName: 'lit',
          checkpointAt: DateTime.utc(2026, 11, 12, 4),
          cause: NationalFocusFailureCause.missedConfirmation,
        ),
      ],
    );
    final pendingCards = StreamController<List<NationalFocusCard>>();
    final pendingFailures = StreamController<List<NationalFocusFailure>>();
    addTearDown(pendingCards.close);
    addTearDown(pendingFailures.close);
    final second = _StreamNationalFocusRepository(
      cards: pendingCards.stream,
      failures: pendingFailures.stream,
    );
    final focus = _FakeFocusRepository(seconds: const {12: 780});

    Widget build(NationalFocusRepository national) => MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: FocusNationalCalendarCard(
              focusRepository: focus,
              nationalFocusRepository: national,
              displayTimeZoneId: _zone,
              now: () => _now,
              onOpenNationalFocus: () {},
              onRetryProjection: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(first));
    await tester.pumpAndSettle();
    expect(find.text('点亮 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('board-focus-failure-dot-12')),
      findsOneWidget,
    );

    await tester.pumpWidget(build(second));
    await tester.pump();

    // 新仓储还没有首帧：旧账号的点亮数与失败标记必须已经清零，不能回显。
    expect(find.text('点亮 1'), findsNothing);
    expect(
      find.byKey(const ValueKey('board-focus-failure-dot-12')),
      findsNothing,
    );
    expect(find.text('正在读取国策状态…'), findsOneWidget);
    expect(find.text('读取中'), findsOneWidget);
    expect(find.text('实时状态'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('今日有失败记录时补一行节点明细，仍不复述计数', (tester) async {
    final harness = _Harness(
      cards: [_card('out', NationalFocusCardState.extinguished)],
      failures: [
        _failure(
          id: 'failure-today',
          cardId: 'out',
          cardName: '先写第一步',
          // 04:00Z 在上海是 12 日 12:00：失败确实落在今天。
          checkpointAt: DateTime.utc(2026, 11, 12, 4),
          cause: NationalFocusFailureCause.missedConfirmation,
        ),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 今日失败行并入顶部动态状态卡（最多 3 条 + 溢出提示），日期详情
    // 不再单开「今日失败记录」区块。
    expect(find.text('今日失败记录'), findsNothing);
    expect(find.text('先写第一步（未完成今日确认）'), findsOneWidget);
    // 顶部「今日国策状态」仍负责实时计数；详情只补失败追溯，不复述数字。
    expect(find.text('熄灭 1'), findsOneWidget);
    expect(find.text('存在已熄灭'), findsNothing);
    expect(find.textContaining('点亮 0 · 待确认 0'), findsNothing);
    expect(find.text('国策记录'), findsNothing);
    expect(
      find.byKey(const ValueKey('board-focus-failure-dot-12')),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('只读安排：今日项数、格底小点、切换日期与已完成样式', (tester) async {
    final schedules = _FakeScheduleRepository(
      rows: [
        _schedule(
          'schedule-today',
          '取快递',
          startsAt: DateTime.utc(2026, 11, 12, 4),
          duration: const Duration(hours: 1),
        ),
        _schedule(
          'schedule-history',
          '写周报',
          startsAt: DateTime.utc(2026, 11, 10, 4),
          duration: const Duration(hours: 1),
          isCompleted: true,
        ),
      ],
    );
    final harness = _Harness(seconds: {12: 780});
    await tester.pumpWidget(harness.build(schedules: schedules));
    await tester.pumpAndSettle();

    // 安排与月投影同属一次订阅：账号时区 + 展示月份只有一个窗口。
    expect(schedules.requests, hasLength(1));
    expect(schedules.requests.single.$1.isUtc, isTrue);
    expect(find.text('今日安排（1 项）'), findsOneWidget);
    expect(find.text('取快递'), findsOneWidget);
    // 04:00Z 在上海是 12:00–13:00。
    expect(find.text('12:00–13:00'), findsOneWidget);
    // 第四层语义：有安排的日才有底点，且不挡住今角标与失败红点。
    expect(
      find.byKey(const ValueKey('board-focus-schedule-dot-12')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('board-focus-schedule-dot-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('board-focus-schedule-dot-11')),
      findsNothing,
    );
    // 严格只读：勾选指示不接受 onChanged。
    final check = tester.widget<PactaCheckCircle>(
      find
          .descendant(
            of: find.byType(FocusNationalCalendarCard),
            matching: find.byType(PactaCheckCircle),
          )
          .first,
    );
    expect(check.onChanged, isNull);
    expect(check.compact, isTrue);

    await tester.tap(find.byKey(const ValueKey('board-focus-day-10')));
    await tester.pumpAndSettle();
    expect(find.text('当日安排（1 项）'), findsOneWidget);
    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('取快递'), findsNothing);
    expect(
      tester.widget<Text>(find.text('写周报')).style?.decoration,
      TextDecoration.lineThrough,
      reason: '已完成的安排用删除线表达，不提供勾选入口',
    );
    await _unmount(tester);
  });

  testWidgets('安排读取失败给出可读错误并可重试', (tester) async {
    final schedules = _FakeScheduleRepository(failing: true);
    final harness = _Harness();
    await tester.pumpWidget(harness.build(schedules: schedules));
    await tester.pumpAndSettle();

    expect(find.text('暂时不能读取安排。'), findsOneWidget);
    // 失败时标题不带项数：不能把“不知道”说成 0 项。
    expect(find.text('今日安排'), findsOneWidget);
    expect(find.textContaining('今日安排（'), findsNothing);
    expect(
      find.byKey(const ValueKey('board-focus-schedule-dot-12')),
      findsNothing,
    );

    final calls = schedules.requests.length;
    schedules.failing = false;
    final retry = find.byKey(const ValueKey('board-focus-schedule-retry'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(schedules.requests.length, greaterThan(calls));
    expect(find.text('暂时不能读取安排。'), findsNothing);
    expect(find.text('今日安排（0 项）'), findsOneWidget);
    expect(find.text('今天还没有安排。'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('日期详情用 PactaSectionHeader 与两块 tonal 容器分区', (tester) async {
    final schedules = _FakeScheduleRepository(
      rows: [
        _schedule(
          'schedule-today',
          '取快递',
          startsAt: DateTime.utc(2026, 11, 12, 4),
          duration: const Duration(hours: 1),
        ),
      ],
    );
    final harness = _Harness(seconds: {12: 780});
    await tester.pumpWidget(harness.build(schedules: schedules));
    await tester.pumpAndSettle();

    final card = find.byType(FocusNationalCalendarCard);
    final header = find.descendant(
      of: card,
      matching: find.byType(PactaSectionHeader),
    );
    expect(header, findsOneWidget);
    final title = find.descendant(of: header, matching: find.text('日期详情'));
    expect(title, findsOneWidget);
    final colors = Theme.of(tester.element(title)).colorScheme;
    expect(
      tester.widget<Text>(title).style?.color,
      colors.primary,
      reason: '「日期详情」是谷歌蓝分组标题，不再用灰色 titleSmall 裸文字',
    );
    // 日期作为 header 的右侧副文本，与标题同一行。
    final date = find.text('11 月 12 日（今日）');
    expect(date, findsOneWidget);
    final titleRect = tester.getRect(title);
    final dateRect = tester.getRect(date);
    expect(dateRect.left, greaterThanOrEqualTo(titleRect.right));
    expect(dateRect.top, lessThan(titleRect.bottom), reason: '日期与标题同一行');

    // 有效专注：独立柔和 tonal 容器，标签在上、时长在下，原 key 不变。
    final durationPanel = find.byKey(
      const ValueKey('board-focus-day-duration-panel'),
    );
    final duration = find.byKey(const ValueKey('board-focus-day-duration'));
    expect(durationPanel, findsOneWidget);
    expect(
      find.descendant(of: durationPanel, matching: duration),
      findsOneWidget,
    );
    final durationDecoration =
        tester.widget<Container>(durationPanel).decoration! as BoxDecoration;
    expect(durationDecoration.color, colors.surfaceContainerLow);
    expect(
      durationDecoration.borderRadius,
      BorderRadius.circular(PactaSpacing.md),
    );
    final durationLabel = find.descendant(
      of: durationPanel,
      matching: find.text('有效专注'),
    );
    expect(durationLabel, findsOneWidget);
    final durationLabelRect = tester.getRect(durationLabel);
    final durationRect = tester.getRect(duration);
    expect(
      durationRect.top,
      greaterThan(durationLabelRect.bottom),
      reason: '标签与时长各自成行，不挤成一团',
    );
    expect(durationRect.left, closeTo(durationLabelRect.left, 0.01));
    expect(tester.widget<Text>(duration).data, '13分钟');

    // 安排同样在独立 tonal 容器里，标题与列表之间留出 8dp。
    final schedulePanel = find.byKey(
      const ValueKey('board-focus-schedule-panel'),
    );
    expect(schedulePanel, findsOneWidget);
    expect(
      (tester.widget<Container>(schedulePanel).decoration! as BoxDecoration)
          .color,
      colors.surfaceContainerLow,
    );
    expect(
      find.descendant(of: schedulePanel, matching: find.text('今日安排（1 项）')),
      findsOneWidget,
    );
    final scheduleTitleRect = tester.getRect(find.text('今日安排（1 项）'));
    final scheduleRowRect = tester.getRect(find.text('取快递'));
    expect(
      scheduleRowRect.top - scheduleTitleRect.bottom,
      greaterThanOrEqualTo(PactaSpacing.sm - 0.01),
      reason: '标题与日程列表之间留出清晰呼吸间距',
    );
    // 两块容器与标题左缘严格对齐。
    expect(
      tester.getRect(durationPanel).left,
      closeTo(titleRect.left, 0.01),
      reason: 'tonal 容器与分区标题左缘对齐',
    );
    expect(tester.getRect(schedulePanel).left, closeTo(titleRect.left, 0.01));
    await _unmount(tester);
  });

  testWidgets('320 宽 2 倍字号下日期详情两块 tonal 容器完整落在卡片内', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final schedules = _FakeScheduleRepository(
      rows: [
        _schedule(
          'schedule-today',
          '取快递并顺路把上个月的快递单号核对完',
          startsAt: DateTime.utc(2026, 11, 12, 4),
          duration: const Duration(hours: 1),
        ),
      ],
    );
    final harness = _Harness(seconds: {12: 780});
    await tester.pumpWidget(harness.build(width: 320, schedules: schedules));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('日期详情'), findsOneWidget);
    expect(find.text('有效专注'), findsOneWidget);
    expect(find.text('今日安排（1 项）'), findsOneWidget);
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('board-focus-national-card')),
    );
    for (final finder in <Finder>[
      find.text('日期详情'),
      find.text('11 月 12 日（今日）'),
      find.byKey(const ValueKey('board-focus-day-duration')),
      find.text('今日安排（1 项）'),
      find.byKey(const ValueKey('board-focus-schedule-panel')),
    ]) {
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(cardRect.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(cardRect.right + 0.01));
    }
    await _unmount(tester);
  });

  testWidgets('320 宽 2 倍字号下日期详情失败态仍工整且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = _Harness(failing: true);
    await tester.pumpWidget(harness.build(width: 320));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('日期详情'), findsOneWidget);
    expect(find.text('暂时不能读取这一天的专注记录。'), findsOneWidget);
    expect(
      tester
          .widget<PactaSectionHeader>(find.byType(PactaSectionHeader))
          .trailing,
      isNull,
      reason: '失败态不编造日期副文本',
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('board-focus-national-card')),
    );
    for (final finder in <Finder>[
      find.text('日期详情'),
      find.text('暂时不能读取这一天的专注记录。'),
      find.byKey(const ValueKey('board-focus-day-detail-retry')),
    ]) {
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(cardRect.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(cardRect.right + 0.01));
    }
    await _unmount(tester);
  });

  testWidgets('320 宽 2 倍字号下安排失败态仍工整且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = _Harness();
    await tester.pumpWidget(
      harness.build(
        width: 320,
        schedules: _FakeScheduleRepository(failing: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('暂时不能读取安排。'), findsOneWidget);
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('board-focus-national-card')),
    );
    for (final finder in <Finder>[
      find.text('今日安排'),
      find.text('暂时不能读取安排。'),
      find.byKey(const ValueKey('board-focus-schedule-retry')),
    ]) {
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(cardRect.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(cardRect.right + 0.01));
    }
    await _unmount(tester);
  });

  testWidgets('360dp 宽下七列星期与月末日期全在卡片内，没有横向滚动', (tester) async {
    final harness = _Harness(seconds: {30: 3600});
    await tester.pumpWidget(harness.build(width: 360));
    await tester.pumpAndSettle();

    final card = tester.getRect(
      find.byKey(const ValueKey('board-focus-national-card')),
    );
    expect(card.width, 360);
    for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.right,
        lessThanOrEqualTo(card.right),
        reason: '星期 $label 不得越过卡片右缘',
      );
      expect(rect.left, greaterThanOrEqualTo(card.left));
    }
    // 2026-11-01 是周日（第 7 列），2026-11-30 是周一（最后一行首列）：
    // 第七列与最后一行都必须完整落在卡片内。
    for (final day in [1, 8, 30]) {
      final rect = tester.getRect(find.byKey(ValueKey('board-focus-day-$day')));
      expect(
        rect.right,
        lessThanOrEqualTo(card.right),
        reason: '$day 日不得越过卡片右缘',
      );
      expect(rect.left, greaterThanOrEqualTo(card.left));
    }
    expect(
      tester.getRect(find.byKey(const ValueKey('board-focus-day-1'))).right,
      greaterThan(card.right - 48),
      reason: '第 7 列贴着卡片右缘，而不是被压到左边留白',
    );
    expect(
      find.descendant(
        of: find.byType(FocusNationalCalendarCard),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
      reason: '月历内部不再出现横向滚动条',
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
  testWidgets('深绿底上的失败细短杠带同系半透托底，且不新增描边层', (tester) async {
    // 90 分钟专注 = heat3 深绿；同一天落一条国策失败。
    final harness = _Harness(
      seconds: {4: 5400},
      failures: [
        _failure(
          id: 'failure-heat3',
          cardId: 'card-1',
          cardName: '先写第一步',
          checkpointAt: DateTime.utc(2026, 11, 4, 4),
          cause: NationalFocusFailureCause.missedConfirmation,
        ),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(_cellColor(tester, 4), colors.heat3Background);
    final bar = find.byKey(const ValueKey('board-focus-failure-dot-4'));
    final halo = find.byKey(const ValueKey('board-focus-failure-halo-4'));
    expect(bar, findsOneWidget);
    expect(halo, findsOneWidget, reason: '深绿底必须给珊瑚红细杠留一层隔离托底');
    final haloContainer = tester.widget<Container>(halo);
    final haloDecoration = haloContainer.decoration! as BoxDecoration;
    expect(haloDecoration.border, isNull, reason: '托底只能用填充色：加 border 会立刻变成双层框');
    expect(haloDecoration.color, isNotNull);
    expect(haloDecoration.color!.a, closeTo(0.92, 0.01), reason: '托底是半透的同系表面色');
    expect(haloContainer.padding, const EdgeInsets.all(1));
    final haloRect = tester.getRect(halo);
    final numberRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('board-focus-day-4')),
        matching: find.text('4'),
      ),
    );
    expect(haloRect.top, greaterThanOrEqualTo(numberRect.bottom - 0.01));
    expect(
      haloRect.height,
      lessThanOrEqualTo(5.01),
      reason: '含光晕在内高 ≤ 5dp，稳定放进 8dp 指示轨',
    );
    expect(_borderedLayerCount(tester, 4), 0);
    expect(_cellBorder(tester, 4), isNull);
    await _unmount(tester);
  });

  testWidgets('同日安排微点与国策失败细杠同轨并排，互不重叠', (tester) async {
    final harness = _Harness(
      seconds: {16: 5400},
      failures: [
        _failure(
          id: 'failure-dual',
          cardId: 'card-1',
          cardName: '先写第一步',
          checkpointAt: DateTime.utc(2026, 11, 16, 4),
          cause: NationalFocusFailureCause.missedConfirmation,
        ),
      ],
    );
    final schedules = _FakeScheduleRepository(
      rows: [
        _schedule(
          'schedule-dual',
          '周会',
          startsAt: DateTime.utc(2026, 11, 16, 4),
          duration: const Duration(hours: 1),
        ),
      ],
    );
    await tester.pumpWidget(harness.build(schedules: schedules));
    await tester.pumpAndSettle();

    final dot = find.byKey(const ValueKey('board-focus-schedule-dot-16'));
    final bar = find.byKey(const ValueKey('board-focus-failure-dot-16'));
    expect(dot, findsOneWidget);
    expect(bar, findsOneWidget);
    final dotRect = tester.getRect(dot);
    final barRect = tester.getRect(bar);
    expect(dotRect.width, closeTo(dotRect.height, 0.01), reason: '安排点是等宽高微点');
    expect(barRect.width, greaterThan(barRect.height), reason: '失败标是横向细杠');
    expect(dotRect.overlaps(barRect), isFalse, reason: '微点与细杠不得重叠');
    expect(dotRect.right, lessThanOrEqualTo(barRect.left + 0.01));
    final numberRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('board-focus-day-16')),
        matching: find.text('16'),
      ),
    );
    for (final rect in [dotRect, barRect]) {
      expect(rect.top, greaterThanOrEqualTo(numberRect.bottom - 0.01));
      expect(
        rect.bottom,
        lessThanOrEqualTo(
          tester
                  .getRect(find.byKey(const ValueKey('board-focus-day-16')))
                  .bottom -
              0.01,
        ),
      );
    }
    expect(
      _borderedLayerCount(tester, 16),
      0,
      reason: '双态日同样只有日格最外层那一条 Ink 装饰',
    );
    await _unmount(tester);
  });
}

class _FakeScheduleRepository extends UnavailableScheduleRepository {
  _FakeScheduleRepository({this.rows = const [], this.failing = false});

  final List<Schedule> rows;
  bool failing;
  final requests = <(DateTime, DateTime)>[];

  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) {
    requests.add((from ?? DateTime.utc(1970), to ?? DateTime.utc(1970)));
    if (failing) {
      return Stream<List<Schedule>>.error(StateError('schedule failed'));
    }
    return Stream.value(rows);
  }
}

Schedule _schedule(
  String id,
  String title, {
  required DateTime startsAt,
  required Duration duration,
  bool isCompleted = false,
}) => Schedule(
  id: id,
  title: title,
  startsAt: startsAt,
  endsAt: startsAt.add(duration),
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  isCompleted: isCompleted,
);

class _FailingNationalFocusRepository
    extends UnavailableNationalFocusRepository {
  @override
  Stream<List<NationalFocusCard>> watchTreeCards() =>
      Stream.error(StateError('cards failed'));

  @override
  Stream<List<NationalFocusFailure>> watchFailures() =>
      Stream.error(StateError('failures failed'));

  @override
  Future<void> settleDueCheckpoints() async {}
}

class _StreamNationalFocusRepository
    extends UnavailableNationalFocusRepository {
  _StreamNationalFocusRepository({required this.cards, required this.failures});

  final Stream<List<NationalFocusCard>> cards;
  final Stream<List<NationalFocusFailure>> failures;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => cards;

  @override
  Stream<List<NationalFocusFailure>> watchFailures() => failures;

  @override
  Future<void> settleDueCheckpoints() async {}
}

class _FakeNationalFocusRepository extends UnavailableNationalFocusRepository {
  _FakeNationalFocusRepository({
    this.cards = const [],
    this.failures = const [],
  });

  final List<NationalFocusCard> cards;
  final List<NationalFocusFailure> failures;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(cards);

  @override
  Stream<List<NationalFocusFailure>> watchFailures() => Stream.value(failures);

  @override
  Future<void> settleDueCheckpoints() async {}
}

class _FakeFocusRepository extends UnavailableFocusRepository {
  _FakeFocusRepository({required this.seconds, this.failing = false});

  final Map<int, int> seconds;
  bool failing;
  final requests = <(String, DateTime)>[];

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    requests.add((timeZoneId, DateTime.utc(month.year, month.month)));
    if (failing) return Stream.error(StateError('projection failed'));
    // 只有 2026 年 11 月带专注记录：切到别的月份时默认日回到 1 日。
    return Stream.value(
      _metrics(month, month.month == 11 ? seconds : const {}, timeZoneId),
    );
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
  required NationalFocusFailureCause cause,
}) => NationalFocusFailure(
  id: id,
  batchId: 'batch-$id',
  cardId: cardId,
  checkpointAt: checkpointAt,
  cause: cause,
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
      updatedAt: DateTime.utc(2026, 11, 6),
    ),
  ],
);
