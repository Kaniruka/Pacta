import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/board/national_focus_summary_card.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';

void main() {
  testWidgets('无节点时显示空状态和按显示时区换算的下次检查点', (tester) async {
    var openedTree = false;
    final repository = _NationalFocusRepositoryWithCards(const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusSummaryCard(
            repository: repository,
            displayTimeZoneId: 'Asia/Shanghai',
            now: () => DateTime.utc(2026, 9, 25, 19, 59),
            onOpenTree: () => openedTree = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('国策树尚无节点。'), findsOneWidget);
    expect(find.text('下次检查点：2026-09-26 04:00 · Asia/Shanghai'), findsOneWidget);
    await tester.tap(find.text('打开国策树'));
    expect(openedTree, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('待核对节点不进入确定状态汇总并保留上次确认值', (tester) async {
    final repository = _NationalFocusRepositoryWithCards([
      _card('lit', NationalFocusCardState.lit),
      _card('pending', NationalFocusCardState.pendingTodayConfirmation),
      _card('extinguished', NationalFocusCardState.extinguished),
      _card('uncertain', NationalFocusCardState.lit, hasPendingReview: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusSummaryCard(
            repository: repository,
            displayTimeZoneId: 'Asia/Shanghai',
            now: () => DateTime.utc(2026, 9, 25, 19, 59),
            onOpenTree: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('点亮 1 · 待今日确认 1 · 熄灭 1'), findsOneWidget);
    expect(find.text('1 个节点待核对；争议状态不计入上方汇总。'), findsOneWidget);
    expect(find.text('uncertain · 上次已确认：5 天连续记录'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

NationalFocusCard _card(
  String id,
  NationalFocusCardState state, {
  bool hasPendingReview = false,
}) => NationalFocusCard(
  id: id,
  triggerCondition: id,
  action: '行动',
  isInTree: true,
  state: state,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  hasPendingReview: hasPendingReview,
  currentConsecutiveDays: 5,
);

class _NationalFocusRepositoryWithCards
    extends UnavailableNationalFocusRepository {
  _NationalFocusRepositoryWithCards(this.cards);

  final List<NationalFocusCard> cards;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(cards);

  @override
  Future<void> settleDueCheckpoints() async {}
}
