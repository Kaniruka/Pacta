import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/theme/pacta_calendar_colors.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_calendar_day_cell.dart';

void main() {
  test('五档专注热力在亮暗主题都达到 4.5:1', () {
    for (final colors in [
      PactaCalendarColors.light,
      PactaCalendarColors.dark,
    ]) {
      for (var level = 0; level <= 4; level++) {
        final (background, foreground) = colors.heatColorsForLevel(level);
        expect(
          _contrast(background, foreground),
          greaterThanOrEqualTo(4.5),
          reason: '热力第 $level 档前景对比度',
        );
      }
    }
  });

  test('去胶囊今字色在白底与 heat0 上亮暗主题都达到 4.5:1', () {
    // '今' 不再铺实心胶囊，直接落在格子的业务底色或卡片面上：
    // 亮主题的“无底色”格落在纯白卡片（#FFFFFF）上，暗主题落在深色卡片面
    // （PactaSurfaces.dark.card）上——把白色当成暗主题承载面会与配色自相
    // 矛盾，因此按主题各自取真实承载面。
    final light = PactaCalendarColors.light;
    for (final background in [
      PactaSurfaces.light.card,
      light.heat0Background,
    ]) {
      expect(
        _contrast(light.todayLabelColor, background),
        greaterThanOrEqualTo(4.5),
        reason: '亮主题今字色与承载面 $background 的对比度',
      );
    }
    final dark = PactaCalendarColors.dark;
    for (final background in [PactaSurfaces.dark.card, dark.heat0Background]) {
      expect(
        _contrast(dark.todayLabelColor, background),
        greaterThanOrEqualTo(4.5),
        reason: '暗主题今字色与承载面 $background 的对比度',
      );
    }
    // 亮主题的白底断言必须真的包含纯白卡片面，不能只测 heat0。
    expect(PactaSurfaces.light.card, const Color(0xffffffff));
  });

  test('计划日历四类业务底与 heat0 中性底块的正文/标记达到 4.5:1', () {
    for (final colors in [
      PactaCalendarColors.light,
      PactaCalendarColors.dark,
    ]) {
      for (final (name, background, foreground) in <(String, Color, Color)>[
        ('全部完成', colors.allCompleteBackground, colors.allCompleteForeground),
        ('有安排', colors.hasPlansBackground, colors.hasPlansForeground),
        ('放假日', colors.holidayBackground, colors.holidayForeground),
        ('普通 heat0', colors.heat0Background, colors.heat0Foreground),
      ]) {
        expect(
          _contrast(background, foreground),
          greaterThanOrEqualTo(4.5),
          reason: '$name 底的公历数字与底部标记对比度',
        );
      }
      // 放假日短标签会叠加在黄/绿业务底上；'今' 微字落在 heat0 中性底块上。
      for (final background in [
        colors.hasPlansBackground,
        colors.allCompleteBackground,
      ]) {
        expect(
          _contrast(background, colors.holidayForeground),
          greaterThanOrEqualTo(4.5),
          reason: '放假日短标签在 $background 上',
        );
      }
      expect(
        _contrast(colors.heat0Background, colors.todayLabelColor),
        greaterThanOrEqualTo(4.5),
        reason: 'heat0 底块上的今字',
      );
    }
  });

  test('失败标记是温和珊瑚红，不再使用刺眼纯红', () {
    expect(PactaCalendarColors.light.failureDotColor, const Color(0xFFD94B43));
    expect(PactaCalendarColors.dark.failureDotColor, const Color(0xFFF28B82));
    // 珊瑚红不再停在绿阶里冒充“又一层绿”：它与 heat3/heat4 明确不同色相，
    // 深绿底上的可读性由日格里的同系半透托底（halo）负责，而不是把失败标
    // 染成刺眼的高饱和纯红。
    for (final colors in [
      PactaCalendarColors.light,
      PactaCalendarColors.dark,
    ]) {
      for (final background in [
        colors.heat3Background,
        colors.heat4Background,
      ]) {
        expect(
          colors.failureDotColor,
          isNot(background),
          reason: '失败标不能与热力底色同色',
        );
      }
    }
  });

  test('copyWith 与 lerp 都携带 todayLabelColor', () {
    final custom = const Color(0xFF123456);
    expect(
      PactaCalendarColors.light
          .copyWith(todayLabelColor: custom)
          .todayLabelColor,
      custom,
    );
    final lerped = PactaCalendarColors.light.lerp(
      PactaCalendarColors.dark,
      0.5,
    );
    expect(
      lerped.todayLabelColor,
      Color.lerp(
        PactaCalendarColors.light.todayLabelColor,
        PactaCalendarColors.dark.todayLabelColor,
        0.5,
      ),
    );
  });

  test('热力档位按 30 / 90 / 180 分钟边界划分', () {
    expect(PactaCalendarColors.heatLevelForSeconds(0), 0);
    expect(PactaCalendarColors.heatLevelForSeconds(-1), 0);
    expect(PactaCalendarColors.heatLevelForSeconds(1), 1);
    expect(PactaCalendarColors.heatLevelForSeconds(1799), 1);
    expect(PactaCalendarColors.heatLevelForSeconds(1800), 2);
    expect(PactaCalendarColors.heatLevelForSeconds(5399), 2);
    expect(PactaCalendarColors.heatLevelForSeconds(5400), 3);
    expect(PactaCalendarColors.heatLevelForSeconds(10799), 3);
    expect(PactaCalendarColors.heatLevelForSeconds(10800), 4);
    expect(PactaCalendarColors.heatLevelForSeconds(999999), 4);
  });

  test('heatColorsForLevel 夹取越界档位', () {
    final colors = PactaCalendarColors.light;
    expect(colors.heatColorsForLevel(-3), (
      colors.heat0Background,
      colors.heat0Foreground,
    ));
    expect(colors.heatColorsForLevel(9), (
      colors.heat4Background,
      colors.heat4Foreground,
    ));
  });

  testWidgets('today + selected：只保留一层选中描边、业务背景不被覆写、今标识仍在', (tester) async {
    const cellKey = ValueKey('day-cell');
    var taps = 0;
    final colors = PactaCalendarColors.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: PactaCalendarDayBox(
                dayNumber: '20',
                selected: true,
                today: true,
                backgroundColor: colors.heat2Background,
                foregroundColor: colors.heat2Foreground,
                subLabel: const Text('初八'),
                topRightMarker: const SizedBox(
                  key: ValueKey('top-marker'),
                  width: 6,
                  height: 6,
                ),
                bottomDot: const SizedBox(
                  key: ValueKey('bottom-dot'),
                  width: 5,
                  height: 5,
                ),
                cellKey: cellKey,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );

    final ink = tester.widget<Ink>(
      find.descendant(of: find.byKey(cellKey), matching: find.byType(Ink)),
    );
    final decoration = ink.decoration! as BoxDecoration;
    // 业务背景原样保留：selected/today 不覆写背景。
    expect(decoration.color, colors.heat2Background);
    final border = decoration.border! as Border;
    // 选中优先：只有一层 2dp 主蓝描边。
    expect(border.top.width, 2);
    expect(border.left.width, 2);
    expect(border.right.width, 2);
    expect(border.bottom.width, 2);
    expect(border.top.color, colors.selectedBorder);
    // 外框与单元格等大，且不存在第二层带边框的 DecoratedBox。
    expect(tester.getSize(find.byType(Ink)), const Size(80, 80));
    final secondBorder = find.descendant(
      of: find.byKey(cellKey),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
      ),
    );
    expect(secondBorder, findsNothing);

    // 去胶囊：'今' 直接是文字，没有包裹它的实心底衬，也不与业务前景撞色。
    expect(find.text('今'), findsOneWidget);
    expect(
      _todayLabelHasFilledBackdrop(tester),
      isFalse,
      reason: '今字不得再被填充胶囊包住',
    );
    final todayLabel = tester.widget<Text>(find.text('今'));
    expect(todayLabel.style?.fontSize, 10);
    expect(todayLabel.style?.color, colors.heat2Foreground);
    expect(find.text('初八'), findsOneWidget);
    expect(find.byKey(const ValueKey('top-marker')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-dot')), findsOneWidget);

    final semantics = tester.widget<Semantics>(
      find
          .ancestor(of: find.byKey(cellKey), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics.properties.selected, isTrue);
    expect(semantics.properties.button, isTrue);

    await tester.tap(find.byKey(cellKey));
    expect(taps, 1);
  });

  testWidgets('仅今天：1.5dp 中性描边与独立今标识', (tester) async {
    final colors = PactaCalendarColors.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 72,
              height: 72,
              child: PactaCalendarDayBox(
                dayNumber: '21',
                today: true,
                foregroundColor: colors.heat0Foreground,
                backgroundColor: colors.heat0Background,
                cellKey: const ValueKey('today-cell'),
              ),
            ),
          ),
        ),
      ),
    );
    final ink = tester.widget<Ink>(
      find.descendant(
        of: find.byKey(const ValueKey('today-cell')),
        matching: find.byType(Ink),
      ),
    );
    final border = (ink.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, colors.todayBorder);
    expect(find.text('今'), findsOneWidget);
    // heat0 不是业务色底：'今' 用 todayLabelColor，而不是 heat0Foreground。
    expect(_todayLabelHasFilledBackdrop(tester), isFalse);
    final todayLabel = tester.widget<Text>(find.text('今'));
    expect(todayLabel.style?.color, colors.todayLabelColor);
    expect(todayLabel.style?.fontSize, 10);
    expect(todayLabel.style?.height, 1.0);
  });

  testWidgets('仅选中：不显示今标识；都未设置时不画边框', (tester) async {
    final colors = PactaCalendarColors.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: PactaCalendarDayBox(
                  dayNumber: '22',
                  selected: true,
                  foregroundColor: colors.selectedForeground,
                  cellKey: const ValueKey('selected-cell'),
                ),
              ),
              SizedBox(
                width: 72,
                height: 72,
                child: PactaCalendarDayBox(
                  dayNumber: '23',
                  foregroundColor: colors.heat0Foreground,
                  cellKey: const ValueKey('plain-cell'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final selectedInk = tester.widget<Ink>(
      find.descendant(
        of: find.byKey(const ValueKey('selected-cell')),
        matching: find.byType(Ink),
      ),
    );
    final selectedBorder =
        (selectedInk.decoration! as BoxDecoration).border! as Border;
    expect(selectedBorder.top.width, 2);
    expect(selectedBorder.top.color, colors.selectedBorder);
    expect(find.text('今'), findsNothing);

    final plainInk = tester.widget<Ink>(
      find.descendant(
        of: find.byKey(const ValueKey('plain-cell')),
        matching: find.byType(Ink),
      ),
    );
    expect((plainInk.decoration! as BoxDecoration).border, isNull);
    expect((plainInk.decoration! as BoxDecoration).color, isNull);
  });
  testWidgets('无底色与业务色底上的今字自适应取色，且从不铺胶囊', (tester) async {
    final colors = PactaCalendarColors.light;
    final cases = <(String, Color?, Color, Color)>[
      ('无底色', null, colors.heat0Foreground, colors.todayLabelColor),
      (
        'heat0',
        colors.heat0Background,
        colors.heat0Foreground,
        colors.todayLabelColor,
      ),
      (
        'heat3 深绿',
        colors.heat3Background,
        colors.heat3Foreground,
        colors.heat3Foreground,
      ),
      (
        '有安排 柔和黄',
        colors.hasPlansBackground,
        colors.hasPlansForeground,
        colors.hasPlansForeground,
      ),
      (
        '全部完成 浅绿',
        colors.allCompleteBackground,
        colors.allCompleteForeground,
        colors.allCompleteForeground,
      ),
    ];
    for (final (name, background, foreground, expected) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 72,
                height: 72,
                child: PactaCalendarDayBox(
                  key: ValueKey('label-case-$name'),
                  dayNumber: '9',
                  today: true,
                  backgroundColor: background,
                  foregroundColor: foreground,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今'), findsOneWidget, reason: '$name：今天仍有今字');
      expect(
        _todayLabelHasFilledBackdrop(tester),
        isFalse,
        reason: '$name：今字不得被填充胶囊包住',
      );
      final label = tester.widget<Text>(find.text('今'));
      expect(label.style?.color, expected, reason: '$name：今字颜色自适应底色');
    }
  });
}

double _contrast(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  final lighter = luminanceA > luminanceB ? luminanceA : luminanceB;
  final darker = luminanceA > luminanceB ? luminanceB : luminanceA;
  return (lighter + 0.05) / (darker + 0.05);
}

/// '今' 与格子之间是否存在带填充色的 Container / DecoratedBox（旧胶囊底衬）。
bool _todayLabelHasFilledBackdrop(WidgetTester tester) {
  final filled = find.ancestor(
    of: find.text('今'),
    matching: find.byWidgetPredicate((widget) {
      if (widget is Container) {
        if (widget.color != null) return true;
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color != null;
      }
      if (widget is DecoratedBox) {
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color != null;
      }
      return false;
    }),
  );
  return filled.evaluate().isNotEmpty;
}
