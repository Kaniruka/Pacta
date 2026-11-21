import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/theme/pacta_calendar_colors.dart';
import 'package:pacta/src/theme/pacta_icon_sizes.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_focus_heat_legend.dart';

/// 工单 01：全站图标尺度与共享热力图例。
///
/// 两个接缝都在这里锁死：主题层的七档常量是唯一尺寸来源；图例在
/// lib/src/ui/ 里按亮暗主题取 PactaCalendarColors 的五档色块。

Widget _legend({required Brightness brightness, String? label}) => MaterialApp(
  theme: pactaTheme(brightness),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: label == null
          ? const PactaFocusHeatLegend()
          : PactaFocusHeatLegend(label: label),
    ),
  ),
);

BoxDecoration _swatchDecoration(WidgetTester tester, int level) =>
    tester
            .widget<Container>(find.byKey(ValueKey('pacta-heat-legend-$level')))
            .decoration!
        as BoxDecoration;

void main() {
  test('PactaIconSizes 七档常量固定为 14/18/20/24/32/40/48 且严格递增', () {
    expect(PactaIconSizes.micro, 14);
    expect(PactaIconSizes.sm, 18);
    expect(PactaIconSizes.compact, 20);
    expect(PactaIconSizes.md, 24);
    expect(PactaIconSizes.lg, 32);
    expect(PactaIconSizes.hero, 40);
    expect(PactaIconSizes.heroLarge, 48);

    const scale = <double>[
      PactaIconSizes.micro,
      PactaIconSizes.sm,
      PactaIconSizes.compact,
      PactaIconSizes.md,
      PactaIconSizes.lg,
      PactaIconSizes.hero,
      PactaIconSizes.heroLarge,
    ];
    expect(scale, <double>[14, 18, 20, 24, 32, 40, 48]);
    for (var index = 1; index < scale.length; index++) {
      expect(
        scale[index],
        greaterThan(scale[index - 1]),
        reason: '尺度必须严格递增：${scale[index - 1]} -> ${scale[index]}',
      );
    }
  });

  testWidgets('PactaFocusHeatLegend 在亮暗主题各渲染五档色块与一条语义说明', (tester) async {
    for (final brightness in Brightness.values) {
      final colors = brightness == Brightness.dark
          ? PactaCalendarColors.dark
          : PactaCalendarColors.light;
      await tester.pumpWidget(_legend(brightness: brightness));
      await tester.pumpAndSettle();

      expect(
        find.text('专注时长：按颜色深浅区分'),
        findsOneWidget,
        reason: '${brightness.name}：默认说明文案',
      );
      for (var level = 0; level <= 4; level++) {
        final swatch = find.byKey(ValueKey('pacta-heat-legend-$level'));
        expect(
          swatch,
          findsOneWidget,
          reason: '${brightness.name}：第 $level 档色块必须存在',
        );
        final decoration = _swatchDecoration(tester, level);
        expect(
          decoration.color,
          colors.heatColorsForLevel(level).$1,
          reason: '${brightness.name}：第 $level 档取当前主题的热力底色',
        );
        expect(decoration.borderRadius, BorderRadius.circular(3));
        expect(tester.getSize(swatch), const Size(12, 12));
      }

      // 五档色块不逐块朗读：整块收敛成一条语义说明。
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(PactaFocusHeatLegend),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.container, isTrue);
      expect(semantics.excludeSemantics, isTrue);
      expect(semantics.properties.label, '专注热力图例：颜色越深表示当天有效专注时长越长');

      final label = tester.widget<Text>(find.text('专注时长：按颜色深浅区分'));
      final theme = Theme.of(tester.element(find.byType(PactaFocusHeatLegend)));
      expect(label.style?.color, theme.colorScheme.onSurfaceVariant);
      expect(label.style?.fontSize, theme.textTheme.bodySmall?.fontSize);
    }
  });

  testWidgets('亮暗主题的色块颜色来自各自色阶而不是同一套写死颜色', (tester) async {
    Future<List<Color?>> palette(Brightness brightness) async {
      await tester.pumpWidget(_legend(brightness: brightness));
      await tester.pumpAndSettle();
      return [
        for (var level = 0; level <= 4; level++)
          _swatchDecoration(tester, level).color,
      ];
    }

    final light = await palette(Brightness.light);
    final dark = await palette(Brightness.dark);
    expect(light, isNot(equals(dark)));
    expect(light, [
      for (var level = 0; level <= 4; level++)
        PactaCalendarColors.light.heatColorsForLevel(level).$1,
    ]);
    expect(dark, [
      for (var level = 0; level <= 4; level++)
        PactaCalendarColors.dark.heatColorsForLevel(level).$1,
    ]);
  });

  testWidgets('自定义 label 只替换说明文字，五档色块与语义不变', (tester) async {
    await tester.pumpWidget(
      _legend(brightness: Brightness.light, label: '本周专注：越深越久'),
    );
    await tester.pumpAndSettle();

    expect(find.text('本周专注：越深越久'), findsOneWidget);
    expect(find.text('专注时长：按颜色深浅区分'), findsNothing);
    for (var level = 0; level <= 4; level++) {
      expect(find.byKey(ValueKey('pacta-heat-legend-$level')), findsOneWidget);
    }
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(PactaFocusHeatLegend),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      semantics.properties.label,
      '专注热力图例：颜色越深表示当天有效专注时长越长',
      reason: '语义说明不随可见文案改写，读屏仍解释同一件事',
    );
  });
}
