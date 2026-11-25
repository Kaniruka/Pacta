import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/focus_chain_history.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';

import '../support/fake_auth_repository.dart';

const _sessionStrip = ValueKey('focus-recovery-session');
const _chainTable = ValueKey('focus-chain-table');
const _historyEntry = ValueKey('focus-history-entry');
const _startBar = ValueKey('focus-start-bar');
const _startBarCard = ValueKey('focus-task-picker-entry');

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

  testWidgets('底部选择任务栏是四周 20dp 圆角、带左右 gutter 与底部边距的悬浮卡片', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');

    final barFinder = find.byKey(_startBar);
    expect(barFinder, findsOneWidget);
    final card = tester.widget<Material>(barFinder);
    expect(card.elevation, 3);
    expect(card.clipBehavior, Clip.antiAlias);
    final radius = card.borderRadius!.resolve(TextDirection.ltr);
    for (final corner in [
      radius.topLeft,
      radius.topRight,
      radius.bottomLeft,
      radius.bottomRight,
    ]) {
      expect(
        corner,
        const Radius.circular(PactaSpacing.cardRadius),
        reason: '四周统一 20dp 圆角，不再是只抬顶部的通栏',
      );
    }

    // 悬浮几何：左右各留一档 gutter，底部再留 12dp，与导航栏不贴边。
    final bar = tester.getRect(barFinder);
    expect(bar.left, PactaSpacing.lg);
    expect(bar.right, 420 - PactaSpacing.lg);
    final navigation = tester.getRect(find.byType(NavigationBar));
    expect(
      navigation.top - bar.bottom,
      PactaSpacing.md,
      reason: '悬浮卡片与底部导航之间保留 12dp',
    );
    expect(
      tester.getRect(find.byKey(_startBarCard)).width,
      lessThan(bar.width),
      reason: '按钮不再通栏贴边',
    );
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

  testWidgets('专注历史页的连胜节点卡片相隔 8dp 且按 #2 -> #1 倒链', (tester) async {
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

    // 默认停在精锐链，先切到已经有记录的普通链。
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();
    expect(find.text('当前连续 2 次'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);

    final cards = find.descendant(
      of: find.byType(FocusHistoryPage),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(2));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(second.top - first.bottom, PactaSpacing.sm);

    // 倒链：每段从上到下都是最新在前，#2 落在 #1 之上。
    final badge1 = tester.getRect(find.text('#1'));
    final badge2 = tester.getRect(find.text('#2'));
    expect(
      badge2.bottom,
      lessThanOrEqualTo(badge1.top),
      reason: '打开历史页第一眼就是最新记录',
    );
    expect(badge1.center.dx, badge2.center.dx);
    expect(badge1.right, lessThan(first.left));
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('倒链段严格从新到旧：断链在最上，其后 #2、#1', (tester) async {
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
    final broken = await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 3));
    await fixture.focus.abandonSession(
      sessionId: broken.id,
      failureReason: '被电话打断',
    );

    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    final breakRect = tester.getRect(find.text('断链'));
    final badge2 = tester.getRect(find.text('#2'));
    final badge1 = tester.getRect(find.text('#1'));
    expect(breakRect.top, lessThan(badge2.top), reason: '最新断链排在本段最上方');
    expect(badge2.bottom, lessThanOrEqualTo(badge1.top), reason: '#2 在 #1 之上');
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('倒链卡片内部上下留白对称（误差 ≤ 0.5dp）', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 25));
    await fixture.focus.settleDueSessions();
    final broken = await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 3));
    await fixture.focus.abandonSession(
      sessionId: broken.id,
      failureReason: '被电话打断',
    );

    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    final cards = find.descendant(
      of: find.byType(FocusHistoryPage),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(2));

    // 文字列显式收紧主轴，Row 的 center 才是真正的内容居中。
    final textColumns = find.descendant(
      of: find.byType(FocusHistoryPage),
      matching: find.byKey(const ValueKey('focus-history-card-text')),
    );
    expect(textColumns, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      expect(
        tester.widget<Column>(textColumns.at(index)).mainAxisSize,
        MainAxisSize.min,
        reason: '第 ${index + 1} 行文字列必须 mainAxisSize.min',
      );
    }

    for (var index = 0; index < 2; index++) {
      final cardFinder = cards.at(index);
      final cardRect = tester.getRect(cardFinder);
      // 量左侧文字块（Column）到卡片上下边缘的距离：单个 Text 的行盒会带上
      // 字体 ascent/descent 的取整误差，量整块内容才是用户看到的留白。
      final blockRect = tester.getRect(
        find.descendant(
          of: cardFinder,
          matching: find.byKey(const ValueKey('focus-history-card-text')),
        ),
      );
      final upperGap = blockRect.top - cardRect.top;
      final lowerGap = cardRect.bottom - blockRect.bottom;
      expect(
        upperGap,
        closeTo(lowerGap, 0.5),
        reason:
            '第 ${index + 1} 行文字块到卡片顶/底边距离应相等：'
            '上 $upperGap / 下 $lowerGap',
      );
      expect(
        upperGap,
        greaterThanOrEqualTo(PactaSpacing.md - 0.5),
        reason: '文字块不贴边：上下至少留一档 12dp',
      );
    }

    // 带 48dp 溢出菜单的完成卡片：直接量首个 Text 顶缘与末个 Text 底缘。
    final completedCard = find.ancestor(
      of: find.byType(PopupMenuButton<String>),
      matching: find.byType(Card),
    );
    expect(completedCard, findsOneWidget);
    final completedRect = tester.getRect(completedCard);
    final texts = find.descendant(
      of: completedCard,
      matching: find.byType(Text),
    );
    final topGap = tester.getRect(texts.first).top - completedRect.top;
    final bottomGap = completedRect.bottom - tester.getRect(texts.last).bottom;
    expect(
      (topGap - bottomGap).abs(),
      lessThanOrEqualTo(1.5),
      reason: '完成卡片首行顶距 $topGap / 末行底距 $bottomGap 必须对称',
    );

    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('历史卡片溢出菜单的危险项与普通项同为 labelLarge 字阶', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 25));
    await fixture.focus.settleDueSessions();

    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    final failText = tester.widget<Text>(find.text('判定为失败'));
    final noteText = tester.widget<Text>(find.text('编辑节点备注'));
    // 只传颜色、不碰 textTheme：字号继承自菜单主题的 labelLarge。
    expect(failText.style?.fontSize, isNull);
    expect(noteText.style?.fontSize, isNull);
    final errorColor = Theme.of(tester.element(find.text('判定为失败')))
        .colorScheme
        .error;
    expect(failText.style?.color, errorColor);
    expect(noteText.style?.color, isNull, reason: '普通项不覆写颜色');
    // 渲染尺寸一致性：同组菜单不允许出现两种字号。
    expect(
      tester.getSize(find.text('判定为失败')).height,
      closeTo(tester.getSize(find.text('编辑节点备注')).height, 0.5),
    );

    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('时间轴气泡与卡片同心、行间 8dp，连接线起止于圆心', (tester) async {
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
    final broken = await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 3));
    await fixture.focus.abandonSession(
      sessionId: broken.id,
      failureReason: '被电话打断',
    );

    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    final rows = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'focus-history-row-',
          ),
    );
    expect(rows, findsNWidgets(3), reason: '#1、#2 与断链节点各占一行');
    // 倒链顺序：断链（最新）在最上，其后 #2、#1。
    final badges = [
      find
          .descendant(of: rows.at(0), matching: find.byIcon(Icons.link_off))
          .first,
      find.descendant(of: rows.at(1), matching: find.text('#2')),
      find.descendant(of: rows.at(2), matching: find.text('#1')),
    ];

    Rect? previousCard;
    final badgeCenters = <Offset>[];
    for (var index = 0; index < badges.length; index++) {
      final card = find.descendant(
        of: rows.at(index),
        matching: find.byType(Card),
      );
      expect(card, findsOneWidget, reason: '第 ${index + 1} 行右侧是一张卡片');
      final cardRect = tester.getRect(card);
      final badgeRect = tester.getRect(badges[index]);
      expect(
        (badgeRect.center.dy - cardRect.center.dy).abs(),
        lessThanOrEqualTo(1.0),
        reason: '第 ${index + 1} 行气泡必须与右侧卡片垂直同心',
      );
      expect(
        badgeRect.center.dx,
        lessThan(cardRect.left),
        reason: '气泡落在卡片左侧的 32dp 轨道内',
      );
      badgeCenters.add(badgeRect.center);
      if (previousCard != null) {
        expect(
          cardRect.top - previousCard.bottom,
          moreOrLessEquals(PactaSpacing.sm, epsilon: 0.01),
          reason: '第 ${index + 1} 行与上一行卡片之间仍是 8dp',
        );
      }
      previousCard = cardRect;
    }
    expect(
      badgeCenters.map((center) => center.dx).toSet(),
      hasLength(1),
      reason: '三枚气泡共用同一条竖轴',
    );

    // 连接线：2dp 宽、与气泡同轴，并且只出现在首末气泡之间。
    final lines = find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox && widget.color == PactaSurfaces.light.hairline,
    );
    expect(lines, findsWidgets);
    final run = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'focus-history-run-',
          ),
    );
    final runRect = tester.getRect(run);
    final firstBadge = badgeCenters.first;
    final lastBadge = badgeCenters.last;
    final lastCard = tester.getRect(
      find.descendant(of: rows.at(2), matching: find.byType(Card)),
    );
    for (var index = 0; index < lines.evaluate().length; index++) {
      final line = tester.getRect(lines.at(index));
      expect(line.width, moreOrLessEquals(2, epsilon: 0.01));
      expect(
        (line.center.dx - firstBadge.dx).abs(),
        lessThanOrEqualTo(0.01),
        reason: '连接线与气泡同轴',
      );
      expect(
        line.top,
        greaterThanOrEqualTo(firstBadge.dy - 0.01),
        reason: '首条气泡上半截没有线',
      );
      expect(
        line.bottom,
        lessThanOrEqualTo(lastBadge.dy + 0.01),
        reason: '末条气泡下半截没有线',
      );
    }
    expect(
      runRect.bottom,
      moreOrLessEquals(lastCard.bottom, epsilon: 0.01),
      reason: '最后一张卡下方不再多出一截竖线占位',
    );
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('三链切换胶囊：48dp 高、文字不顶边，360dp 两倍字号不溢出', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _mount(tester, fixture, size: const Size(360, 800));
    await tester.pumpAndSettle();
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(
      const ValueKey('focus-history-chain-switch'),
    );
    expect(switchFinder, findsOneWidget);
    final rect = tester.getRect(switchFinder);
    expect(rect.height, greaterThanOrEqualTo(48), reason: '胶囊至少 48dp 高');
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360), reason: '360dp 窄屏不横向溢出');

    final label = tester.getRect(find.text('精锐链'));
    expect(label.top, greaterThan(rect.top), reason: '文字不顶到框的上边缘');
    expect(label.bottom, lessThan(rect.bottom), reason: '文字不顶到框的下边缘');
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('专注历史三段切换：空态按选中链给出提示', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();

    expect(find.text('精锐链还没有连胜记录。'), findsOneWidget);
    expect(find.text('完成或结束专注后，记录会显示在这里。'), findsOneWidget);

    await tester.tap(find.text('预约链'));
    await tester.pumpAndSettle();
    expect(find.text('预约链还没有连胜记录。'), findsOneWidget);
    expect(find.text('完成或结束预约准备后，记录会显示在这里。'), findsOneWidget);
    expect(find.text('精锐链还没有连胜记录。'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('断链节点保留编辑失败原因动作', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final session = await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await fixture.focus.abandonSession(
      sessionId: session.id,
      failureReason: '被消息打断',
    );
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    expect(find.text('断链'), findsOneWidget);
    expect(find.textContaining('原因：被消息打断'), findsOneWidget);
    expect(find.textContaining('之后重新从 #1 起算'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑失败原因'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '需要照顾家人');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原因：需要照顾家人'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('最新记录就是断链时：当前连续归零、最高连胜保留、时间轴收尾在断链', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 25));
    await fixture.focus.settleDueSessions();
    final broken = await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 3));
    await fixture.focus.abandonSession(
      sessionId: broken.id,
      failureReason: '被电话打断',
    );

    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    final timeline = buildFocusChainHistory(
      sessions: await fixture.focus.getSessions(),
    ).timelineFor(FocusChainType.regular);
    expect(timeline.isCurrentlyBroken, isTrue, reason: '最新一条已结算记录就是失败');
    expect(timeline.currentStreak, 0);
    expect(timeline.bestStreak, 1);

    // 摘要卡是「标签 + 数值」两段文本：当前连续归零，最高连胜与段数保留。
    expect(find.text('当前连续'), findsOneWidget);
    expect(find.text('0 次'), findsOneWidget);
    expect(find.text('最高连胜'), findsOneWidget);
    expect(find.text('1 次'), findsOneWidget);
    expect(find.text('1 段'), findsOneWidget);
    expect(find.text('断链'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsNothing, reason: '断链后不继续编号');
    expect(find.text('连续 1 次'), findsOneWidget);
    expect(find.textContaining('原因：被电话打断'), findsOneWidget);
    // 倒链：最新状态在最上方——断链卡排在 #1 之上。
    expect(
      tester.getRect(find.text('断链')).top,
      lessThan(tester.getRect(find.text('#1')).top),
    );
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('节点备注写入失败只弹可读提示，不丢未捕获异常', (tester) async {
    final fixture = await _Fixture.create(suspendedWrites: true);
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 25));
    await fixture.focus.settleDueSessions();
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑节点备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '停用后不应写入');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 停用账号：写入被拒，页面留下一条可读提示，异常不外泄。
    expect(find.text('用户已停用，恢复前不能创建或修改业务数据。'), findsOneWidget);
    expect(find.byType(FocusHistoryPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('失败原因写入失败只弹可读提示，不丢未捕获异常', (tester) async {
    final fixture = await _Fixture.create(suspendedWrites: true);
    addTearDown(fixture.dispose);
    final session = await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await fixture.focus.abandonSession(
      sessionId: session.id,
      failureReason: '被消息打断',
    );
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑失败原因'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '需要照顾家人');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('用户已停用，恢复前不能创建或修改业务数据。'), findsOneWidget);
    expect(find.textContaining('原因：被消息打断'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('时钟待核对只挂轻量徽标：不占链号也不出现旧多端文案', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()
          ..signedInUser = 'clock-review-history',
        focusRepositoryFactory: (_) => _ClockReviewHistoryRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();

    expect(find.text('时钟待核对'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget, reason: '待核对记录不占序号');
    expect(find.text('当前连续 1 次'), findsOneWidget);
    for (final obsolete in ['多端冲突', '重复记录', 'pendingReview', '待复核']) {
      expect(find.textContaining(obsolete), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('完成节点保留编辑节点备注动作', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startSession(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 25));
    await fixture.focus.settleDueSessions();
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();

    expect(find.text('#1'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑节点备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '这次坐得很稳');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final nodes = await fixture.focus.getNodes();
    expect(nodes.single.note, '这次坐得很稳');
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('已完成记录可在历史页事后判定为失败，并重算链连击', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final sessionIds = <String>[];
    for (var index = 0; index < 2; index++) {
      final session = await fixture.focus.startSession(
        taskId: fixture.taskIds.first,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      sessionIds.add(session.id);
      fixture.now = fixture.now.add(const Duration(minutes: 25));
      await fixture.focus.settleDueSessions();
    }
    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通链'));
    await tester.pumpAndSettle();
    expect(find.text('当前连续 2 次'), findsOneWidget);
    expect(await fixture.focus.getNodes(), hasLength(2));

    // 最新一条（#2）改判失败：只剩 #1 成段，断链把当前连胜清掉。
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑节点备注'), findsOneWidget);
    await tester.tap(find.text('判定为失败'));
    await tester.pumpAndSettle();
    expect(find.text('填写失败原因'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '其实并没有真的专注');
    await tester.tap(find.widgetWithText(FilledButton, '确认改判'));
    await tester.pumpAndSettle();

    final failed = (await fixture.focus.getSession(sessionIds.last))!;
    expect(failed.isFailed, isTrue);
    expect(failed.failureReason, '其实并没有真的专注');
    expect(failed.effectiveSeconds, 25 * 60, reason: '有效专注时长原样保留');
    expect(await fixture.focus.getNodes(), hasLength(1), reason: '节点随改判一起移除');
    final record = (await fixture.focus.getChainRecords()).singleWhere(
      (entry) => entry.mode == FocusChainMode.regular,
    );
    expect(record.currentConsecutive, 0);
    expect(record.bestConsecutive, 1);

    final summary = find.byKey(const ValueKey('focus-history-summary'));
    expect(
      find.descendant(of: summary, matching: find.text('0 次')),
      findsOneWidget,
      reason: '当前连续归零',
    );
    expect(
      find.descendant(of: summary, matching: find.text('1 次')),
      findsOneWidget,
      reason: '最高连胜按完整历史收敛到 1',
    );
    expect(find.text('连续 1 次'), findsOneWidget, reason: '最新一段只剩 #1');
    expect(find.text('断链'), findsOneWidget);
    expect(find.textContaining('原因：其实并没有真的专注'), findsOneWidget);
    expect(
      find.byKey(ValueKey('focus-history-node-menu-${sessionIds.last}')),
      findsNothing,
      reason: '改判后的记录不再挂在已完成卡片上',
    );
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('预约链的已完成卡片不提供事后改判入口', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.focus.startAppointment(
      taskId: fixture.taskIds.first,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    fixture.now = fixture.now.add(const Duration(minutes: 15));
    await fixture.focus.settleDueAppointments();

    await _mount(tester, fixture);
    await _openDestination(tester, '专注链');
    await tester.tap(find.byKey(_historyEntry));
    await tester.pumpAndSettle();

    expect(find.textContaining('预约成功'), findsOneWidget);
    expect(find.text('判定为失败'), findsNothing, reason: '预约链没有事后改判语义');
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
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

  static Future<_Fixture> create({bool suspendedWrites = false}) async {
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
    final LocalFocusRepository focus = suspendedWrites
        ? _SuspendedWriteFocusRepository(
            database: database,
            userId: userId,
            remote: InMemoryFocusRemote(),
            cloudSyncEnabled: false,
            now: () => clock.value,
          )
        : LocalFocusRepository(
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

/// 停用账号的写入替身：备注与失败原因写回都被拒，读路径保持真实。
class _SuspendedWriteFocusRepository extends LocalFocusRepository {
  _SuspendedWriteFocusRepository({
    required super.database,
    required super.userId,
    required super.remote,
    super.cloudSyncEnabled,
    super.now,
  });

  @override
  Future<void> updateNodeNote({
    required String nodeId,
    required String note,
  }) async => throw const UserOperationsSuspendedException();

  @override
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  }) async => throw const UserOperationsSuspendedException();
}

/// 固定返回一条完成记录与一条时钟待核对记录的历史仓储。
class _ClockReviewHistoryRepository extends UnavailableFocusRepository {
  @override
  Stream<List<FocusSession>> watchSessions() => Stream.value([
    _session(id: 'completed', at: DateTime.utc(2026, 11, 15, 9)),
    _session(
      id: 'clock-review',
      at: DateTime.utc(2026, 11, 15, 10),
      clockReviewStatus: FocusClockReviewStatus.pending,
    ),
  ]);
}

FocusSession _session({
  required String id,
  required DateTime at,
  FocusClockReviewStatus? clockReviewStatus,
}) => FocusSession(
  id: id,
  taskId: 'task-1',
  mode: FocusChainMode.elite,
  durationSeconds: 1500,
  startedAt: at.subtract(const Duration(minutes: 25)),
  endsAt: at,
  status: FocusSessionStatus.completed,
  completedAt: at,
  effectiveSeconds: 1500,
  effectiveIntervals: clockReviewStatus == null
      ? const []
      : [
          FocusTimeInterval(
            startedAt: at.subtract(const Duration(minutes: 25)),
            endedAt: at,
            measuredDurationSeconds: 1500,
            clockReviewStatus: clockReviewStatus,
          ),
        ],
);
