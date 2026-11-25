import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_shared_widgets.dart';
import 'package:pacta/src/national_focus/national_focus_strengthening_page.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';

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

  testWidgets('可用要求分组零 Divider，相邻段之间只留 2dp 缝隙', (tester) async {
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

    final grouped = find.byKey(
      const ValueKey('national-focus-strengthening-tiers'),
    );
    expect(grouped, findsOneWidget);
    expect(
      find.descendant(of: grouped, matching: find.byType(Divider)),
      findsNothing,
      reason: '分段卡片靠透明缝隙分开，组内不出现 1dp 分隔线',
    );

    const rowKeys = <String>[
      'national-focus-strengthening-level-base',
      'national-focus-strengthening-level-1',
      'national-focus-strengthening-level-2',
      'national-focus-strengthening-create',
    ];
    final rects = <Rect>[];
    for (final key in rowKeys) {
      final row = find.byKey(ValueKey(key));
      expect(row, findsOneWidget);
      rects.add(tester.getRect(row));
    }
    for (var index = 1; index < rects.length; index++) {
      expect(
        rects[index].top - rects[index - 1].bottom,
        moreOrLessEquals(2, epsilon: 0.01),
        reason: '第 $index 段与上一段之间是 2dp 透明缝隙',
      );
    }
  });

  testWidgets('选中段与未选中段左缘像素对齐，选中只加主色强调条不换底色', (tester) async {
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

    final base = find.byKey(
      const ValueKey('national-focus-strengthening-level-base'),
    );
    final firstLevel = find.byKey(
      const ValueKey('national-focus-strengthening-level-1'),
    );

    Finder stateIcon(Finder row) => find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            (widget.icon == Icons.check_circle ||
                widget.icon == Icons.radio_button_unchecked),
      ),
    );

    // 基础要求默认生效，第一级未选中：两段的左侧图标必须落在同一条线上。
    expect(
      find.descendant(of: base, matching: find.text('正在使用')),
      findsOneWidget,
    );
    expect(
      tester.getRect(stateIcon(base)).left,
      moreOrLessEquals(
        tester.getRect(stateIcon(firstLevel)).left,
        epsilon: 0.5,
      ),
      reason: '选中与未选中段的水平内边距完全一致',
    );
    expect(
      tester.getRect(base).left,
      moreOrLessEquals(tester.getRect(firstLevel).left, epsilon: 0.5),
    );
    expect(
      tester.getRect(base).right,
      moreOrLessEquals(tester.getRect(firstLevel).right, epsilon: 0.5),
    );

    final activeMaterial = tester.widget<Material>(
      find.descendant(of: base, matching: find.byType(Material)).first,
    );
    final inactiveMaterial = tester.widget<Material>(
      find.descendant(of: firstLevel, matching: find.byType(Material)).first,
    );
    final surfaces = PactaSurfaces.of(tester.element(base));
    expect(
      activeMaterial.color,
      surfaces.card,
      reason: '选中段保持实底 card 色，不再用半透明主色混出透明缺块',
    );
    expect(inactiveMaterial.color, surfaces.card);

    final activeBar = find.descendant(
      of: base,
      matching: find.byKey(
        const ValueKey('national-focus-strengthening-active-bar'),
      ),
    );
    expect(activeBar, findsOneWidget);
    expect(
      tester.getSize(activeBar).width,
      moreOrLessEquals(3.5, epsilon: 0.01),
      reason: '左侧 3.5dp 主色竖条标识当前生效项',
    );
    expect(
      find.descendant(
        of: firstLevel,
        matching: find.byKey(
          const ValueKey('national-focus-strengthening-active-bar'),
        ),
      ),
      findsNothing,
    );

    // 每条强化等级仍保留自己的 48×48dp 编辑动作。
    final edit = find.descendant(
      of: firstLevel,
      matching: find.byTooltip('编辑强化等级 1'),
    );
    expect(tester.getSize(edit).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(edit).height, greaterThanOrEqualTo(48));
  });

  testWidgets('页面不再复述当前要求，说明收进顶栏 48dp 说明入口', (tester) async {
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

    final info = find.byKey(
      const ValueKey('national-focus-strengthening-info'),
    );
    expect(info, findsOneWidget);
    expect(
      tester.getSize(info).width,
      greaterThanOrEqualTo(48),
      reason: '说明入口保持 48dp 命中区',
    );
    expect(tester.getSize(info).height, greaterThanOrEqualTo(48));
    // 顶部蓝块与裸排免责声明都已下线：规则正文只出现一次。
    expect(find.text('阅读 5 页'), findsOneWidget);
    expect(find.text('当前使用 · 基础要求'), findsNothing);
    expect(find.text('切换即时生效，已有记录保持不变。是否符合由你判断。'), findsNothing);
    expect(find.text('基础要求'), findsOneWidget);
    expect(find.text('阅读 10 页'), findsOneWidget);
    expect(find.text('阅读 20 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('点按说明入口只弹规则说明，不再出现同名 conflict tooltip', (tester) async {
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

    final info = find.byKey(
      const ValueKey('national-focus-strengthening-info'),
    );
    expect(info, findsOneWidget);
    expect(tester.getSize(info).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(info).height, greaterThanOrEqualTo(48));
    // 可读名称留在 Semantics 上，读屏仍知道这是说明按钮。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '强化要求说明' &&
            widget.properties.button == true,
      ),
      findsOneWidget,
    );

    await tester.tap(info);
    await tester.pump();
    expect(find.text('切换即时生效，已有记录保持不变。是否符合由你判断。'), findsOneWidget);
    // 只有一句话的说明：旧 IconButton.tooltip 的具名气泡不再出现。
    expect(find.text('强化要求说明'), findsNothing);
    expect(find.byTooltip('强化要求说明'), findsNothing);

    // 卸载页面，让 overlay 里的气泡与计时器随宿主一起清理。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('切换失败时内联错误可见且不替换页面结构', (tester) async {
    final repository = _FailingSelectionRepository();
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

    final select = find.descendant(
      of: find.byKey(const ValueKey('national-focus-strengthening-level-1')),
      matching: find.text('选择'),
    );
    await tester.tap(select);
    await tester.pumpAndSettle();

    final error = find.byType(NationalFocusInlineError);
    expect(error, findsOneWidget);
    expect(
      find.descendant(of: error, matching: find.text('切换强化要求失败')),
      findsOneWidget,
      reason: '错误条回显同一条可继续操作的中文提示',
    );
    // 页面仍是完整的可用要求列表，而不是被错误页替换。
    expect(find.text('可用要求'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('national-focus-strengthening-tiers')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('national-focus-strengthening-level-base')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('national-focus-strengthening-level-1')),
      findsOneWidget,
    );
    expect(find.text('正在使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PendingCardRepository extends UnavailableNationalFocusRepository {
  final _card = Completer<NationalFocusCard>();

  @override
  Future<NationalFocusCard> getCard(String cardId) => _card.future;
}

class _FailingSelectionRepository extends _LevelCardRepository {
  @override
  Future<void> selectStrengtheningLevel({
    required String cardId,
    int? levelNumber,
  }) async {
    throw StateError('切换强化要求失败');
  }
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
