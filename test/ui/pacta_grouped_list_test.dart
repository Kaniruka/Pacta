import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/theme/pacta_fonts.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';

void main() {
  testWidgets('PactaSectionHeader 使用主蓝色 titleSmall 与默认内边距', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PactaSectionHeader(
            title: '账号',
            trailing: TextButton(onPressed: () {}, child: const Text('管理')),
          ),
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.text('账号')));
    final title = tester.widget<Text>(find.text('账号'));
    expect(title.style?.color, theme.colorScheme.primary);
    expect(title.style?.fontWeight, PactaFonts.medium);
    expect(title.style?.fontSize, theme.textTheme.titleSmall?.fontSize);
    expect(
      tester
          .widget<PactaSectionHeader>(find.byType(PactaSectionHeader))
          .padding,
      const EdgeInsets.fromLTRB(4, 16, 4, 8),
    );
    expect(find.text('管理'), findsOneWidget);
  });

  testWidgets('360dp 宽下长 trailing 最多占 72% 且贴右缘，标题不被挤压', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const summary = '洛杉矶 · America/Los_Angeles';
    // 页面左右各 20dp，分组标题内边距左右各 4dp：内容宽 360-40-8 = 312dp；
    // trailing 上限 72% = 224.64dp，减去 4dp 间隙与 18dp ⓘ 是文本可用宽度。
    const contentWidth = 312.0;
    const summaryAllowance = contentWidth * 0.72 - PactaSpacing.xs - 18;

    Widget build(Widget trailing) => MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PactaSectionHeader(title: '显示时区', trailing: trailing),
        ),
      ),
    );

    await tester.pumpWidget(
      build(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: PactaSpacing.xs),
            const Icon(Icons.info_outline, size: 18),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerRight = tester.getRect(find.byType(PactaSectionHeader)).right;
    // 关键回归：trailing 整体贴右缘；旧实现停在 50% 分界处，距右缘还差一截。
    expect(
      tester.getRect(find.byIcon(Icons.info_outline)).right,
      moreOrLessEquals(headerRight - 4, epsilon: 0.01),
      reason: 'trailing 必须贴齐标题内容区右缘',
    );
    // 长 trailing 拿到 72% 上限内的全部宽度，而不是与标题五五分。
    expect(
      tester.getRect(find.text(summary)).width,
      moreOrLessEquals(summaryAllowance, epsilon: 0.5),
      reason:
          '旧实现只给 (312-8)/2-22 = 130dp，'
          '新实现给满 72% 上限内的 $summaryAllowance dp',
    );
    // 标题不吃亏：仍有足够宽度单行容纳，且与 trailing 不重叠。
    final title = tester.renderObject<RenderParagraph>(find.text('显示时区'));
    expect(title.didExceedMaxLines, isFalse);
    expect(
      title.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(title.size.width),
      reason: '标题拿到超过自身固有宽度的空间，不被长 trailing 挤压',
    );
    expect(
      tester.getRect(find.text('显示时区')).right,
      lessThanOrEqualTo(tester.getRect(find.text(summary)).left),
    );
    expect(tester.takeException(), isNull);

    // 极端长 trailing 仍被 72% 上限收敛，剩下的宽度全部留给标题。
    const longTrailing = '很长很长的尾部入口很长很长的尾部入口很长很长的尾部入口';
    await tester.pumpWidget(
      build(
        const Text(
          longTrailing,
          key: ValueKey('long-trailing'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('long-trailing'))).width,
      lessThanOrEqualTo(contentWidth * 0.72 + 0.01),
      reason: 'trailing 最多占 72% 宽',
    );
    final squeezed = tester.renderObject<RenderParagraph>(find.text('显示时区'));
    expect(
      squeezed.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(squeezed.size.width),
      reason: '72% 上限之外的宽度仍然留给标题',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('PactaGroupedList 只在相邻行之间插入 1dp 分隔线', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PactaGroupedList(
            children: [
              const ListTile(title: Text('A')),
              SwitchListTile(
                title: const Text('B'),
                value: true,
                onChanged: (_) {},
              ),
              const ListTile(title: Text('C')),
            ],
          ),
        ),
      ),
    );
    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(2));
    for (final divider in dividers) {
      expect(divider.height, 1);
      expect(divider.thickness, 1);
      expect(divider.color, PactaSurfaces.light.hairline);
    }
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PactaGroupedList),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, PactaSurfaces.light.card);
    expect(material.clipBehavior, Clip.antiAlias);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(PactaSpacing.cardRadius));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('PactaGroupedList 支持自定义底色与圆角', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.dark),
        home: Scaffold(
          body: PactaGroupedList(
            backgroundColor: const Color(0xff112233),
            borderRadius: 8,
            children: const [ListTile(title: Text('唯一行'))],
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PactaGroupedList),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, const Color(0xff112233));
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('PactaStatusBadge 五种语气在亮暗主题都达到 4.5:1', (tester) async {
    for (final brightness in Brightness.values) {
      for (final tone in PactaStatusBadgeTone.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: pactaTheme(brightness),
            home: Scaffold(
              body: Center(
                child: PactaStatusBadge(
                  key: ValueKey(tone),
                  label: tone.name,
                  icon: Icons.check,
                  tone: tone,
                ),
              ),
            ),
          ),
        );
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey(tone)),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        final background = decoration.color!;
        expect(decoration.borderRadius, BorderRadius.circular(999));
        final label = tester.widget<Text>(find.text(tone.name));
        final foreground = label.style!.color!;
        expect(
          _contrast(background, foreground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} ${tone.name} 前景对比度',
        );
        expect(find.byIcon(Icons.check), findsOneWidget);
      }
    }
  });

  testWidgets('PactaSettingsTile 整行可点、状态胶囊与箭头同排且 Key 不重复', (tester) async {
    var taps = 0;
    const tileKey = ValueKey('settings-tile');
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PactaGroupedList(
            children: [
              PactaSettingsTile(
                tileKey: tileKey,
                leadingIcon: Icons.person_outline,
                title: '资料',
                subtitle: '昵称与头像',
                statusBadge: const PactaStatusBadge(
                  label: '已同步',
                  tone: PactaStatusBadgeTone.success,
                ),
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(tileKey), findsOneWidget);
    expect(find.byType(PactaSettingsTile), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('昵称与头像'), findsOneWidget);
    expect(find.text('已同步'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(
      tester.getSize(find.byKey(tileKey)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(tileKey));
    expect(taps, 1);
  });

  testWidgets('PactaSettingsTile 禁用时不触发 onTap，隐藏箭头时只留值文本', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              PactaSettingsTile(
                tileKey: const ValueKey('disabled-tile'),
                title: '禁用项',
                onTap: () => taps++,
                enabled: false,
                showChevron: false,
              ),
              const PactaSettingsTile(
                tileKey: ValueKey('value-tile'),
                title: '时区',
                trailing: Text('Asia/Shanghai'),
                showChevron: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('disabled-tile')));
    expect(taps, 0);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('Asia/Shanghai'), findsOneWidget);
  });
}

double _contrast(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  final lighter = luminanceA > luminanceB ? luminanceA : luminanceB;
  final darker = luminanceA > luminanceB ? luminanceB : luminanceA;
  return (lighter + 0.05) / (darker + 0.05);
}
