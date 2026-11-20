import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_strengthening_page.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';

void main() {
  testWidgets('读取强化要求期间保留 AppBar 并可返回上一页', (tester) async {
    final repository = _PendingCardRepository();
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => NationalFocusStrengtheningPage(
                      repository: repository,
                      cardId: 'card',
                    ),
                  ),
                ),
                child: const Text('打开强化要求'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开强化要求'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 读取态同样是完整页面：标题可见、返回入口在，不是没有出口的空白页。
    expect(find.widgetWithText(AppBar, '国策强化要求'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('打开强化要求'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('强化等级行之间保持 8dp 间距', (tester) async {
    final repository = _LevelCardRepository();
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusStrengtheningPage(
          repository: repository,
          cardId: 'card',
        ),
      ),
    );
    await tester.pumpAndSettle();

    const levels = ['base', '1', '2'];
    final rects = <Rect>[];
    for (final level in levels) {
      final row = find.byKey(
        ValueKey('national-focus-strengthening-level-$level'),
      );
      expect(row, findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(of: row, matching: find.byType(Container)).first,
      );
      final margin = container.margin! as EdgeInsets;
      // 全局 CardThemeData.margin 为零：行自身的下边距必须撑出 8dp。
      expect(margin.bottom, greaterThanOrEqualTo(PactaSpacing.sm));
      rects.add(tester.getRect(row));
    }
    expect(rects[1].top, greaterThanOrEqualTo(rects[0].bottom));
    expect(rects[2].top, greaterThanOrEqualTo(rects[1].bottom));

    final firstRule = tester.getRect(find.text('阅读 10 页'));
    final secondRule = tester.getRect(find.text('阅读 20 页'));
    expect(
      secondRule.top - firstRule.bottom,
      greaterThanOrEqualTo(PactaSpacing.sm),
    );
  });
}

class _PendingCardRepository extends UnavailableNationalFocusRepository {
  final _card = Completer<NationalFocusCard>();

  @override
  Future<NationalFocusCard> getCard(String cardId) => _card.future;
}

class _LevelCardRepository extends UnavailableNationalFocusRepository {
  @override
  Future<NationalFocusCard> getCard(String cardId) async => NationalFocusCard(
    id: cardId,
    name: '阅读',
    triggerCondition: '每天早餐后',
    action: '阅读 5 页',
    isInTree: true,
    state: NationalFocusCardState.lit,
    createdAt: DateTime.utc(2026, 10, 4),
    updatedAt: DateTime.utc(2026, 10, 4),
    strengtheningLevels: const [
      NationalFocusStrengtheningLevel(levelNumber: 1, action: '阅读 10 页'),
      NationalFocusStrengtheningLevel(levelNumber: 2, action: '阅读 20 页'),
    ],
  );
}
