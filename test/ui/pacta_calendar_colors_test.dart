import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/theme/pacta_calendar_colors.dart';
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

    expect(find.text('今'), findsOneWidget);
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
}

double _contrast(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  final lighter = luminanceA > luminanceB ? luminanceA : luminanceB;
  final darker = luminanceA > luminanceB ? luminanceB : luminanceA;
  return (lighter + 0.05) / (darker + 0.05);
}
