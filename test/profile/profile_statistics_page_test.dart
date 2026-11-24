import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/profile/profile_overview.dart';
import 'package:pacta/src/profile/profile_statistics_pages.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';

/// 明细页只读 [ProfileOverviewSource]，不需要真实仓储。
class _StaticOverview implements ProfileOverviewSource {
  const _StaticOverview(this.cards);

  final List<NationalFocusCard> cards;

  @override
  Stream<List<NationalFocusCard>> watchCards() => Stream.value(cards);

  @override
  Stream<List<FocusSession>> watchSessions() => Stream.value(const []);
}

NationalFocusCard _card(
  String name, {
  required bool isInTree,
  NationalFocusCardState state = NationalFocusCardState.extinguished,
  int successfulDays = 0,
  int currentConsecutiveDays = 0,
  int bestConsecutiveDays = 0,
}) => NationalFocusCard(
  id: name,
  name: name,
  triggerCondition: '打开待办清单',
  action: '坐到书桌前先写下今天的第一步。',
  isInTree: isInTree,
  state: state,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  successfulDays: successfulDays,
  currentConsecutiveDays: currentConsecutiveDays,
  bestConsecutiveDays: bestConsecutiveDays,
);

Future<void> _pump(WidgetTester tester, ProfileOverviewSource overview) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: NationalFocusStatisticsPage(overview: overview),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('顶部双指标概览与两个分组标题同时在场', (tester) async {
    await _pump(
      tester,
      _StaticOverview([
        _card(
          '晨光',
          isInTree: true,
          state: NationalFocusCardState.lit,
          currentConsecutiveDays: 4,
          bestConsecutiveDays: 9,
          successfulDays: 12,
        ),
        _card('内化卡', isInTree: false, successfulDays: 200),
      ]),
    );

    final overview = find.byKey(
      const ValueKey('national-focus-statistics-overview'),
    );
    expect(overview, findsOneWidget);
    expect(
      find.descendant(of: overview, matching: find.text('个树中节点')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.text('张卡片')),
      findsOneWidget,
    );
    expect(find.byType(PactaSectionHeader), findsNWidgets(2));
    expect(find.text('当前点亮'), findsWidgets);
    expect(find.text('已内化'), findsWidgets);
    // 组内每行都是 M3 分段卡片，不出现 Divider。
    expect(find.byType(PactaGroupedList), findsNWidgets(2));
    expect(find.byType(Divider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡片行带连胜/内化徽章，点击进入只读详情', (tester) async {
    await _pump(
      tester,
      _StaticOverview([
        _card(
          '晨光',
          isInTree: true,
          state: NationalFocusCardState.lit,
          currentConsecutiveDays: 4,
          bestConsecutiveDays: 9,
          successfulDays: 12,
        ),
        _card('内化卡', isInTree: false, successfulDays: 200),
      ]),
    );

    expect(find.text('连续 4 天'), findsOneWidget);
    expect(find.text('200 天'), findsOneWidget);

    await tester.tap(find.text('晨光'));
    await tester.pumpAndSettle();

    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.text('坐到书桌前先写下今天的第一步。'), findsOneWidget);
    // 只读：详情页没有编辑或点亮动作，只有状态、规则与记录。
    expect(find.text('编辑卡片'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('点亮'), findsOneWidget, reason: '只展示当前状态标签');
    // 规则区与记录区各自成一张 Card，和可编辑详情页的两段边界完全对齐。
    final rules = find.byKey(
      const ValueKey('national-focus-readonly-rules-card'),
    );
    final records = find.byKey(
      const ValueKey('national-focus-readonly-records-card'),
    );
    expect(rules, findsOneWidget);
    expect(records, findsOneWidget);
    expect(
      find.descendant(of: rules, matching: find.text('国策规则')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: records, matching: find.text('记录')),
      findsOneWidget,
    );
    expect(find.descendant(of: rules, matching: find.text('记录')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('两边都为空时只留一句克制的空态', (tester) async {
    await _pump(tester, const _StaticOverview([]));

    expect(find.text('还没有点亮的国策节点。'), findsOneWidget);
    expect(find.text('树中没有点亮的节点。'), findsNothing);
    expect(find.byType(PactaSectionHeader), findsNothing);
    expect(
      find.byKey(const ValueKey('national-focus-statistics-overview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
