import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_shared_widgets.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

/// 工单 10：国策树简洁/详细视图的卡片辨识度、两行规则与连续点亮胶囊。
final _createdAt = DateTime.utc(2026, 11, 20, 9);

NationalFocusCard _card(
  String id,
  String name, {
  required NationalFocusCardState state,
  String action = '坐到书桌前先写下今天的第一步，再核对昨天的落实情况。',
  bool hasPendingReview = false,
  int currentConsecutiveDays = 0,
  int bestConsecutiveDays = 0,
}) => NationalFocusCard(
  id: id,
  name: name,
  triggerCondition: '触发条件',
  action: action,
  isInTree: true,
  state: state,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  hasPendingReview: hasPendingReview,
  currentConsecutiveDays: currentConsecutiveDays,
  bestConsecutiveDays: bestConsecutiveDays,
);

class _FixtureRepository extends UnavailableNationalFocusRepository {
  _FixtureRepository(this.cards);

  final List<NationalFocusCard> cards;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(cards);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value(const <NationalFocusCard>[]);
}

void main() {
  Future<void> pumpTree(
    WidgetTester tester,
    NationalFocusRepository repository, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size size = const Size(1000, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(brightness),
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tearDownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> switchToDetailed(WidgetTester tester) async {
    final entry = find.text('简洁视图');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细视图').last);
    await tester.pumpAndSettle();
  }

  Finder nodeKey(String id) => find.byKey(ValueKey('national-focus-node-$id'));
  Finder cardKey(String id) => find.byKey(ValueKey('national-focus-card-$id'));

  double contrast(Color foreground, Color background) {
    final first = foreground.computeLuminance();
    final second = background.computeLuminance();
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }

  testWidgets('简洁视图严格只剩圆形状态图标与名称，没有任何卡片外观', (tester) async {
    final card = _card(
      'lit-card',
      '根国策',
      state: NationalFocusCardState.lit,
      currentConsecutiveDays: 5,
      bestConsecutiveDays: 9,
    );
    final repository = _FixtureRepository([card]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);

    final node = nodeKey(card.id);
    expect(node, findsOneWidget);
    expect(
      find.descendant(of: node, matching: find.byType(Card)),
      findsNothing,
    );
    final materials = tester.widgetList<Material>(
      find.descendant(of: node, matching: find.byType(Material)),
    );
    expect(materials, isNotEmpty);
    expect(
      materials.every((material) => material.type == MaterialType.transparency),
      isTrue,
      reason: '简洁视图只保留透明表面，没有底色、外框与投影',
    );
    expect(
      find.descendant(of: node, matching: find.text(card.name)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: node, matching: find.text(card.effectiveAction)),
      findsNothing,
      reason: '简洁视图不展示国策规则',
    );
    expect(
      find.descendant(of: node, matching: find.byIcon(Icons.lightbulb)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('详细视图卡片底色与画布分层并按状态着色 ${brightness.name}', (tester) async {
      final lit = _card('lit', '点亮卡', state: NationalFocusCardState.lit);
      final pending = _card(
        'pending',
        '待确认卡',
        state: NationalFocusCardState.pendingTodayConfirmation,
      );
      final extinguished = _card(
        'out',
        '熄灭卡',
        state: NationalFocusCardState.extinguished,
      );
      final review = _card(
        'review',
        '待核对卡',
        state: NationalFocusCardState.lit,
        hasPendingReview: true,
      );
      final repository = _FixtureRepository([
        lit,
        pending,
        extinguished,
        review,
      ]);
      addTearDown(repository.dispose);
      await pumpTree(tester, repository, brightness: brightness);
      await switchToDetailed(tester);

      final colors = Theme.of(
        tester.element(find.byKey(const ValueKey('national-focus-canvas'))),
      ).colorScheme;
      final canvas = colors.surfaceContainerLow;
      final cards = <NationalFocusCard, Card>{
        for (final card in [lit, pending, extinguished, review])
          card: tester.widget<Card>(cardKey(card.id)),
      };
      for (final entry in cards.entries) {
        final card = entry.value;
        expect(
          card.color,
          isNot(canvas),
          reason: '${entry.key.name} 的卡片底色必须与画布 surfaceContainerLow 拉开层级',
        );
        expect(
          contrast(colors.onSurface, card.color!),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key.name} 的正文在卡片底色上必须达到 AA 对比度',
        );
        final shape = card.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(16));
        expect(shape.side.width, greaterThan(0));
        expect(shape.side.color, isNot(canvas));
        expect(card.elevation, 1);
        expect(card.margin, EdgeInsets.zero);
      }
      // 熄灭态用最纯的高亮表面 + 细边；点亮态是柔绿，待确认是柔琥珀。
      expect(cards[extinguished]!.color, colors.surfaceContainerLowest);
      expect(cards[lit]!.color, isNot(cards[extinguished]!.color));
      expect(cards[pending]!.color, isNot(cards[lit]!.color));
      expect(cards[pending]!.color, isNot(cards[extinguished]!.color));
      expect(cards[review]!.color, isNot(cards[lit]!.color));
      expect(tester.takeException(), isNull);
      await tearDownTree(tester);
    });
  }

  testWidgets('详细视图规则固定两行，节点高度随字号缩放且 1x/2x 都不溢出', (tester) async {
    for (final scale in [1.0, 2.0]) {
      final card = _card('rule-card', '根国策', state: NationalFocusCardState.lit);
      final repository = _FixtureRepository([card]);
      await pumpTree(
        tester,
        repository,
        size: const Size(320, 800),
        textScale: scale,
      );
      await switchToDetailed(tester);

      final rule = tester.widget<Text>(
        find.descendant(
          of: cardKey(card.id),
          matching: find.text(card.effectiveAction),
        ),
      );
      expect(rule.maxLines, 2, reason: '${scale}x 字号下规则仍固定两行');
      expect(rule.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(cardKey(card.id)).height,
        closeTo(148 * scale, 0.01),
        reason: '详细视图节点高度 148dp 随 textScaler 线性缩放',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await repository.dispose();
    }
  });

  testWidgets('node 弹层与卡详情名称旁并排展示当前/最高连续点亮胶囊', (tester) async {
    final card = _card(
      'streak-card',
      '根国策',
      state: NationalFocusCardState.lit,
      currentConsecutiveDays: 5,
      bestConsecutiveDays: 12,
    );
    final repository = _FixtureRepository([card]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);

    await tester.tap(nodeKey(card.id));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final currentPill = find.descendant(of: sheet, matching: find.text('5d'));
    final bestPill = find.descendant(of: sheet, matching: find.text('12d'));
    expect(currentPill, findsOneWidget);
    expect(bestPill, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.byTooltip('当前连续点亮 5 天')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byTooltip('历史最高连续点亮 12 天')),
      findsOneWidget,
    );
    final nameRect = tester.getRect(
      find.descendant(of: sheet, matching: find.text(card.name)),
    );
    final currentRect = tester.getRect(currentPill);
    expect(
      currentRect.left,
      greaterThanOrEqualTo(nameRect.right),
      reason: '胶囊紧跟在名称右侧同一行',
    );
    expect(
      (currentRect.center.dy - nameRect.center.dy).abs(),
      lessThan(8),
      reason: '胶囊与名称垂直居中对齐',
    );

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.byType(NationalFocusStreakTags), findsOneWidget);
    expect(find.text('5d'), findsOneWidget);
    expect(find.text('12d'), findsOneWidget);
    expect(find.byTooltip('当前连续点亮 5 天'), findsOneWidget);
    expect(find.byTooltip('历史最高连续点亮 12 天'), findsOneWidget);
    final detailName = tester.getRect(find.text(card.name));
    expect(
      tester.getRect(find.text('5d')).left,
      greaterThanOrEqualTo(detailName.right),
      reason: '详情页胶囊同样紧跟在名称右侧',
    );
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  testWidgets('0 天用中性胶囊，长名称在两倍字号窄屏下安全换行不溢出', (tester) async {
    final longName = List.filled(10, '在重要工作开始之前保持专注').join();
    final card = _card(
      'long-card',
      longName,
      state: NationalFocusCardState.lit,
      bestConsecutiveDays: 3,
    );
    final repository = _FixtureRepository([card]);
    addTearDown(repository.dispose);
    await pumpTree(
      tester,
      repository,
      size: const Size(320, 800),
      textScale: 2,
    );

    await tester.ensureVisible(nodeKey(card.id));
    await tester.tap(nodeKey(card.id));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text(longName)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('0d')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('3d')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byTooltip('当前连续点亮 0 天')),
      findsOneWidget,
    );
    // 0 天用中性浅灰底，不用点亮态的绿底。
    final colors = Theme.of(tester.element(sheet)).colorScheme;
    final currentPill = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('national-focus-streak-current')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (currentPill.decoration as BoxDecoration).color,
      colors.surfaceContainerHighest,
    );
    final sheetRect = tester.getRect(sheet);
    for (final pill in ['0d', '3d']) {
      final rect = tester.getRect(
        find.descendant(of: sheet, matching: find.text(pill)),
      );
      expect(rect.right, lessThanOrEqualTo(sheetRect.right));
    }
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });
}
