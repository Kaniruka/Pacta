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

  testWidgets('详细视图取消顶部状态条与右上角状态胶囊，状态只由图标井、填色与边框表达', (tester) async {
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

    for (final card in [lit, pending, out]) {
      final finder = cardKey(card.id);
      expect(finder, findsOneWidget);
      // 顶部 3dp 状态条彻底移除：卡片内不再出现任何 ColoredBox。
      expect(
        find.descendant(of: finder, matching: find.byType(ColoredBox)),
        findsNothing,
        reason: '${card.name} 没有顶部状态条',
      );
      final cardRect = tester.getRect(finder);
      final nameRect = tester.getRect(
        find.descendant(of: finder, matching: find.text(card.name)),
      );
      expect(
        nameRect.top - cardRect.top,
        closeTo(8, 0.01),
        reason: '${card.name} 的标题行直接贴着 8dp 内边距开始，顶部没有额外占位',
      );
      // 四边等宽：RoundedRectangleBorder 只有一条 BorderSide，四条边同宽。
      final shape =
          tester.widget<Card>(finder).shape! as RoundedRectangleBorder;
      expect(shape.side.width, closeTo(2, 0.001), reason: '根节点四边同为 2dp');
      // 右上角不再有状态文字胶囊，但状态图标井还在。
      for (final label in const ['点亮', '确认', '熄灭']) {
        expect(
          find.descendant(of: finder, matching: find.text(label)),
          findsNothing,
          reason: '${card.name} 不再渲染状态文字胶囊',
        );
      }
      final statusIcon = find.descendant(
        of: finder,
        matching: find.byIcon(switch (card.state) {
          NationalFocusCardState.lit => Icons.lightbulb,
          NationalFocusCardState.pendingTodayConfirmation =>
            Icons.hourglass_top,
          NationalFocusCardState.extinguished => Icons.lightbulb_outline,
        }),
      );
      expect(statusIcon, findsOneWidget, reason: '状态仍由左侧图标井表达');
      // 语义层仍完整播报状态：视觉去掉文字胶囊不等于对读屏也去掉状态。
      final semantics = tester.widget<Semantics>(
        find
            .descendant(of: nodeKey(card.id), matching: find.byType(Semantics))
            .first,
      );
      expect(
        semantics.properties.label,
        contains(card.state.label),
        reason: 'Semantics 仍播报 ${card.state.label}',
      );
    }
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
    expect(rootShape.side.width, closeTo(2, 0.001), reason: '根节点四条边同为 2dp');
    expect(
      childShape.side.width,
      closeTo(1.2, 0.001),
      reason: '子节点四条边同为 1.2dp',
    );
    expect(rootShape.borderRadius, childShape.borderRadius);

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

  testWidgets('放置模式下可选子节点用 1.5dp 四边等宽描边', (tester) async {
    final root = _card('root', '根国策', state: NationalFocusCardState.lit);
    final child = _card(
      'child',
      '子国策',
      state: NationalFocusCardState.lit,
      parentId: root.id,
    );
    final moving = _card('moving', '待放置卡', state: NationalFocusCardState.lit);
    final repository = _FixtureRepository([root, child, moving]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);
    await switchToDetailed(tester);

    await tester.ensureVisible(nodeKey(moving.id));
    await tester.tap(nodeKey(moving.id));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整树中位置'));
    await tester.pumpAndSettle();

    // 可选子节点：1.5dp 四条等宽描边；根节点仍是最粗的 2dp。
    final childShape =
        tester.widget<Card>(cardKey(child.id)).shape! as RoundedRectangleBorder;
    expect(
      childShape.side.width,
      closeTo(1.5, 0.001),
      reason: '可选父节点四边同为 1.5dp，没有单边强调',
    );
    expect(
      find.descendant(of: cardKey(child.id), matching: find.byType(ColoredBox)),
      findsNothing,
    );
    final rootShape =
        tester.widget<Card>(cardKey(root.id)).shape! as RoundedRectangleBorder;
    expect(rootShape.side.width, closeTo(2, 0.001));
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  testWidgets('内化达标显示 已内化 胶囊，连续天数胶囊移到标题下方', (tester) async {
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
    // 连续天数改成详情页同款矢量胶囊，紧贴标题区下方，不再用「连续 X 天」文字。
    expect(
      find.descendant(
        of: cardKey(done.id),
        matching: find.byType(NationalFocusStreakTags),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardKey(done.id), matching: find.text('12d')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardKey(almost.id), matching: find.text('3d')),
      findsOneWidget,
    );
    expect(find.textContaining('连续 12 天'), findsNothing);
    expect(find.textContaining('连续 3 天'), findsNothing);
    final doneNameRect = tester.getRect(
      find.descendant(of: cardKey(done.id), matching: find.text(done.name)),
    );
    final doneTagsRect = tester.getRect(
      find.descendant(
        of: cardKey(done.id),
        matching: find.byType(NationalFocusStreakTags),
      ),
    );
    expect(
      doneTagsRect.top,
      greaterThanOrEqualTo(doneNameRect.bottom),
      reason: '胶囊行在标题区下方，不再压到底部信息栏',
    );
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  testWidgets('0 天既不渲染连续胶囊也不留空行，有记录时才显示详情页同款胶囊', (tester) async {
    final root = _card('root', '根国策', state: NationalFocusCardState.lit);
    final quiet = _card(
      'quiet',
      '安静卡',
      state: NationalFocusCardState.lit,
      parentId: root.id,
    );
    final active = _card(
      'active',
      '有记录卡',
      state: NationalFocusCardState.lit,
      parentId: root.id,
      currentConsecutiveDays: 5,
      bestConsecutiveDays: 9,
    );
    final repository = _FixtureRepository([root, quiet, active]);
    addTearDown(repository.dispose);
    await pumpTree(tester, repository);
    await switchToDetailed(tester);

    // 0 天 + 非根 + 未内化：整块胶囊行都不渲染，标题与规则之间只留 6dp。
    expect(
      find.descendant(
        of: cardKey(quiet.id),
        matching: find.byType(NationalFocusStreakTags),
      ),
      findsNothing,
      reason: 'current == 0 && best == 0 时不渲染连续胶囊',
    );
    expect(
      find.descendant(of: cardKey(quiet.id), matching: find.text('0d')),
      findsNothing,
    );
    expect(find.textContaining('连续 0 天'), findsNothing, reason: '0 天不再有文字噪声');
    final quietHeaderRect = tester.getRect(
      find.descendant(of: cardKey(quiet.id), matching: find.byType(Row)).first,
    );
    final quietRuleRect = tester.getRect(
      find.descendant(
        of: cardKey(quiet.id),
        matching: find.text(quiet.effectiveAction),
      ),
    );
    expect(
      quietRuleRect.top - quietHeaderRect.bottom,
      closeTo(6, 0.01),
      reason: '没有胶囊时不留空行，规则紧接标题区（只隔 6dp）',
    );

    // 根节点 0 天：只有 根 胶囊，仍不出现连续胶囊。
    expect(
      find.descendant(of: cardKey(root.id), matching: find.text('根')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardKey(root.id),
        matching: find.byType(NationalFocusStreakTags),
      ),
      findsNothing,
    );

    // 有任何一天记录就渲染详情页同款矢量胶囊（d 后缀 + Tooltip）。
    final activeTags = find.descendant(
      of: cardKey(active.id),
      matching: find.byType(NationalFocusStreakTags),
    );
    expect(activeTags, findsOneWidget);
    expect(
      find.descendant(of: cardKey(active.id), matching: find.text('5d')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardKey(active.id), matching: find.text('9d')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardKey(active.id),
        matching: find.byTooltip('当前连续点亮 5 天'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cardKey(active.id),
        matching: find.byTooltip('历史最高连续点亮 9 天'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(activeTags).top,
      greaterThanOrEqualTo(
        tester
            .getRect(
              find.descendant(
                of: cardKey(active.id),
                matching: find.text(active.name),
              ),
            )
            .bottom,
      ),
      reason: '胶囊行紧贴标题区下方',
    );
    expect(tester.takeException(), isNull);
    await tearDownTree(tester);
  });

  // 最坏节点：2 行长标题 + 180d/180d + 根 + 已内化 + 3 行长规则，320×800 窄屏。
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('详细视图最坏节点三行规则完整且零溢出 ${scale}x ${brightness.name}', (
        tester,
      ) async {
        final longName = List.filled(6, '在重要工作开始之前保持专注').join();
        final longAction = List.filled(6, '坐到书桌前先写下今天的第一步再核对昨天的落实情况').join();
        final card = _card(
          'worst',
          longName,
          state: NationalFocusCardState.lit,
          action: longAction,
          currentConsecutiveDays: 180,
          bestConsecutiveDays: 180,
          successfulDays: 180,
        );
        expect(card.isTopLevel, isTrue);
        expect(card.isInternalized, isTrue);
        final repository = _FixtureRepository([card]);
        addTearDown(repository.dispose);
        await pumpTree(
          tester,
          repository,
          brightness: brightness,
          size: const Size(320, 800),
          textScale: scale,
        );
        await switchToDetailed(tester);

        final cardFinder = cardKey(card.id);
        expect(cardFinder, findsOneWidget);
        expect(
          tester.getSize(cardFinder).height,
          closeTo(160 * scale, 0.01),
          reason: '详细视图节点高度 160dp 随 textScaler 线性缩放',
        );
        expect(
          find.descendant(of: cardFinder, matching: find.byType(ColoredBox)),
          findsNothing,
        );
        // 最坏胶囊组合同时在场。
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byType(NationalFocusStreakTags),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('180d')),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byTooltip('当前连续点亮 180 天'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byTooltip('历史最高连续点亮 180 天'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('根')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('已内化')),
          findsOneWidget,
        );

        // 名称仍最多两行；规则升到最多三行并左对齐。
        final nameFinder = find.descendant(
          of: cardFinder,
          matching: find.text(card.name),
        );
        final ruleFinder = find.descendant(
          of: cardFinder,
          matching: find.text(card.effectiveAction),
        );
        final name = tester.widget<Text>(nameFinder);
        final rule = tester.widget<Text>(ruleFinder);
        expect(name.maxLines, 2);
        expect(rule.maxLines, 3, reason: '${scale}x 字号下规则最多三行');
        expect(rule.overflow, TextOverflow.ellipsis);
        expect(rule.textAlign, TextAlign.start, reason: '规则左对齐，便于连续扫读');

        // 用同一套字级与 textScaler 重排一遍：行数与显示高度一致，才算三行完整可见。
        final theme = Theme.of(tester.element(cardFinder));
        final scaler = MediaQuery.textScalerOf(tester.element(cardFinder));
        TextPainter paint(
          String text,
          TextStyle? style,
          int maxLines,
          double width,
        ) {
          return TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: width);
        }

        final namePainter = paint(
          card.name,
          theme.textTheme.titleSmall,
          2,
          tester.getSize(nameFinder).width,
        );
        expect(
          namePainter.computeLineMetrics(),
          hasLength(2),
          reason: '最坏标题恰好占满两行',
        );
        expect(
          tester.getSize(nameFinder).height,
          closeTo(namePainter.height, 0.51),
          reason: '两行标题没有被压成一行',
        );
        final rulePainter = paint(
          card.effectiveAction,
          rule.style,
          3,
          tester.getSize(ruleFinder).width,
        );
        expect(
          rulePainter.computeLineMetrics(),
          hasLength(3),
          reason: '最坏规则需要三行才放得下',
        );
        expect(rulePainter.didExceedMaxLines, isTrue);
        expect(
          tester.getSize(ruleFinder).height,
          closeTo(rulePainter.height, 0.51),
          reason: '三行规则完整可见，没有被 Expanded 压少',
        );

        // 几何预算：内容全部落在卡片内，顶部与底部呼吸接近，无大块底部死白。
        final cardRect = tester.getRect(cardFinder);
        final nameRect = tester.getRect(nameFinder);
        final ruleRect = tester.getRect(ruleFinder);
        expect(nameRect.top - cardRect.top, closeTo(8, 0.01));
        expect(ruleRect.bottom, lessThan(cardRect.bottom - 6));
        expect(
          cardRect.bottom - ruleRect.bottom - (nameRect.top - cardRect.top),
          lessThan(24),
          reason: '底部留白不比顶部多出一大块',
        );
        expect(tester.takeException(), isNull);
        await tearDownTree(tester);
      });
    }
  }

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
