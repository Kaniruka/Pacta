import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_shared_widgets.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

/// 工单 10 / Phase 5 Ticket 05：国策树简洁/详细视图的卡片辨识度、
/// 亮暗分层、根节点层次、已内化标识与恒两行规则。
final _createdAt = DateTime.utc(2026, 11, 20, 9);

NationalFocusCard _card(
  String id,
  String name, {
  required NationalFocusCardState state,
  String action = '坐到书桌前先写下今天的第一步，再核对昨天的落实情况。',
  int currentConsecutiveDays = 0,
  int bestConsecutiveDays = 0,
  int successfulDays = 0,
  String? parentId,
}) => NationalFocusCard(
  id: id,
  name: name,
  triggerCondition: '触发条件',
  action: action,
  isInTree: true,
  state: state,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  currentConsecutiveDays: currentConsecutiveDays,
  bestConsecutiveDays: bestConsecutiveDays,
  successfulDays: successfulDays,
  parentId: parentId,
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
      successfulDays: 200,
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
    // 简洁视图同样不展示状态微标、根节点微标与已内化徽记。
    for (final label in ['点亮', '根', '已内化', '连续 5 天']) {
      expect(
        find.descendant(of: node, matching: find.text(label)),
        findsNothing,
        reason: '简洁视图不出现 $label 徽记',
      );
    }
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('详细视图卡片底色高于画布并按状态着色 ${brightness.name}', (tester) async {
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
      final repository = _FixtureRepository([lit, pending, extinguished]);
      addTearDown(repository.dispose);
      await pumpTree(tester, repository, brightness: brightness);
      await switchToDetailed(tester);

      final colors = Theme.of(
        tester.element(find.byKey(const ValueKey('national-focus-canvas'))),
      ).colorScheme;
      final canvas = colors.surfaceContainerLow;
      final canvasLuminance = canvas.computeLuminance();
      final cards = <NationalFocusCard, Card>{
        for (final card in [lit, pending, extinguished])
          card: tester.widget<Card>(cardKey(card.id)),
      };
      for (final entry in cards.entries) {
        final card = entry.value;
        final fill = card.color!;
        expect(
          fill,
          isNot(canvas),
          reason: '${entry.key.name} 的卡片底色必须与画布 surfaceContainerLow 拉开层级',
        );
        expect(
          contrast(colors.onSurface, fill),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key.name} 的正文在卡片底色上必须达到 AA 对比度',
        );
        // 核心回归：暗色下卡片不能比画布更暗，否则整棵树像陷进画布里。
        expect(
          fill.computeLuminance(),
          greaterThan(canvasLuminance),
          reason: '${entry.key.name} 的卡片必须比画布更亮',
        );
        if (brightness == Brightness.dark) {
          expect(
            fill,
            isNot(colors.surfaceContainerLowest),
            reason: '暗色卡片不能再用比画布更暗的 surfaceContainerLowest',
          );
          expect(
            fill.computeLuminance(),
            greaterThanOrEqualTo(canvasLuminance * 1.25),
            reason: '${entry.key.name} 在暗色下必须明显浮于画布',
          );
        }
        final shape = card.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(16));
        expect(shape.side.width, greaterThan(0));
        expect(shape.side.color, isNot(canvas));
        expect(
          contrast(shape.side.color, fill),
          greaterThan(1.5),
          reason: '${entry.key.name} 的状态描边要在卡片底色上看得见',
        );
        final rule = tester.widget<Text>(
          find.descendant(
            of: cardKey(entry.key.id),
            matching: find.text(entry.key.effectiveAction),
          ),
        );
        expect(
          rule.style?.color,
          colors.onSurfaceVariant,
          reason: '${entry.key.name} 的规则用次级前景色，和名称拉开层次',
        );
        expect(
          contrast(colors.onSurfaceVariant, fill),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key.name} 的规则在卡片底色上仍需 AA 对比度',
        );
        expect(card.elevation, 2);
        expect(card.margin, EdgeInsets.zero);
        expect(
          tester.getSize(cardKey(entry.key.id)).width,
          closeTo(228, 0.01),
          reason: '详细卡片宽度固定 228dp，抬头行才放得下图标井、名称与微标',
        );
      }
      expect(cards[lit]!.color, isNot(cards[extinguished]!.color));
      expect(cards[pending]!.color, isNot(cards[lit]!.color));
      expect(cards[pending]!.color, isNot(cards[extinguished]!.color));
      expect(tester.takeException(), isNull);
      await tearDownTree(tester);
    });
  }

  testWidgets('详细视图顶部 3dp 状态条贴顶满宽并按状态取色', (tester) async {
    final lit = _card('lit', '点亮卡', state: NationalFocusCardState.lit);
    final pending = _card(
      'pending',
      '待确认卡',
      state: NationalFocusCardState.pendingTodayConfirmation,
    );
    final out = _card('out', '熄灭卡', state: NationalFocusCardState.extinguished);
    final repository = _FixtureRepository([lit, pending, out]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);
    await switchToDetailed(tester);

    Color stripeOf(String id) {
      final stripe = find.descendant(
        of: cardKey(id),
        matching: find.byType(ColoredBox),
      );
      expect(stripe, findsOneWidget, reason: '每张详细卡片只有一条顶部状态条');
      expect(tester.getSize(stripe).height, closeTo(3, 0.01));
      expect(
        tester.getTopLeft(stripe).dy,
        closeTo(tester.getTopLeft(cardKey(id)).dy, 0.5),
        reason: '状态条贴住卡片上沿',
      );
      expect(
        tester.getSize(stripe).width,
        closeTo(tester.getSize(cardKey(id)).width, 0.01),
        reason: '状态条满宽铺开',
      );
      return tester.widget<ColoredBox>(stripe).color;
    }

    final litStripe = stripeOf(lit.id);
    final pendingStripe = stripeOf(pending.id);
    final outStripe = stripeOf(out.id);
    // 点亮是绿、待确认是琥珀、熄灭是中性灰：色相完全不同，一眼可分。
    expect(litStripe.g, greaterThan(litStripe.r));
    expect(litStripe.g, greaterThan(litStripe.b));
    expect(pendingStripe.r, greaterThan(pendingStripe.b));
    expect(pendingStripe.g, greaterThan(pendingStripe.b));
    expect((outStripe.r - outStripe.g).abs(), lessThan(0.05));
    expect((outStripe.g - outStripe.b).abs(), lessThan(0.05));
    expect({litStripe, pendingStripe, outStripe}, hasLength(3));
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  testWidgets('根节点用 根 微标与更粗外框区分于子节点', (tester) async {
    final root = _card('root', '根国策', state: NationalFocusCardState.lit);
    final child = _card(
      'child',
      '子国策',
      state: NationalFocusCardState.lit,
      parentId: root.id,
    );
    final repository = _FixtureRepository([root, child]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);
    await switchToDetailed(tester);

    expect(root.isTopLevel, isTrue);
    expect(child.isTopLevel, isFalse);
    final rootShape =
        tester.widget<Card>(cardKey(root.id)).shape! as RoundedRectangleBorder;
    final childShape =
        tester.widget<Card>(cardKey(child.id)).shape! as RoundedRectangleBorder;
    expect(rootShape.side.width, greaterThanOrEqualTo(2), reason: '根节点用更粗外框');
    expect(rootShape.side.width, greaterThan(childShape.side.width));

    expect(
      find.descendant(of: cardKey(root.id), matching: find.text('根')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardKey(child.id), matching: find.text('根')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  testWidgets('内化达标显示 已内化 徽记，连续天数始终在底部信息栏', (tester) async {
    final done = _card(
      'done',
      '内化卡',
      state: NationalFocusCardState.lit,
      successfulDays: 180,
      currentConsecutiveDays: 12,
    );
    final almost = _card(
      'almost',
      '接近卡',
      state: NationalFocusCardState.lit,
      successfulDays: 179,
      currentConsecutiveDays: 3,
    );
    final repository = _FixtureRepository([done, almost]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);
    await switchToDetailed(tester);

    expect(done.isInternalized, isTrue);
    expect(almost.isInternalized, isFalse);
    expect(
      find.descendant(of: cardKey(done.id), matching: find.text('已内化')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardKey(almost.id), matching: find.text('已内化')),
      findsNothing,
    );
    expect(
      find.descendant(of: cardKey(done.id), matching: find.text('连续 12 天')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardKey(almost.id), matching: find.text('连续 3 天')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  testWidgets('详细视图规则固定两行、左对齐，节点高度随字号缩放且 1x/2x 都不溢出', (tester) async {
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

      final cardFinder = cardKey(card.id);
      final rule = tester.widget<Text>(
        find.descendant(
          of: cardFinder,
          matching: find.text(card.effectiveAction),
        ),
      );
      expect(rule.maxLines, 2, reason: '${scale}x 字号下规则仍固定两行');
      expect(rule.overflow, TextOverflow.ellipsis);
      expect(rule.textAlign, TextAlign.start, reason: '规则左对齐，便于连续扫读');
      final name = tester.widget<Text>(
        find.descendant(of: cardFinder, matching: find.text(card.name)),
      );
      expect(name.maxLines, 2, reason: '${scale}x 字号下名称最多两行');
      expect(
        tester.getSize(cardFinder).height,
        closeTo(160 * scale, 0.01),
        reason: '详细视图节点高度 160dp 随 textScaler 线性缩放',
      );
      // 规则最多两行时不得垂直溢出，也不能把名称或信息栏挤掉。
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
