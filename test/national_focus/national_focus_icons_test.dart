import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pacta/src/national_focus/national_focus_icons.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

void main() {
  test('四套图标库各有 48–60 枚、键唯一、标签与字形齐全', () {
    expect(nationalFocusIconSets, hasLength(4));
    expect(nationalFocusIconSets.map((set) => set.title).toList(), [
      '默认',
      'Tabler',
      'Material',
      'Cupertino',
    ]);
    final keys = <String>{};
    for (final set in nationalFocusIconSets) {
      expect(
        set.options.length,
        inInclusiveRange(48, 60),
        reason: '${set.title} 必须精选 48–60 枚',
      );
      for (final option in set.options) {
        expect(option.key, startsWith(set.prefix));
        expect(keys.add(option.key), isTrue, reason: '图标键必须全局唯一：${option.key}');
        expect(option.label.trim(), isNotEmpty);
        expect(
          option.icon.fontFamily,
          isNotNull,
          reason: '每枚图标都要有真实字体族：${option.key}',
        );
      }
    }
  });

  test('空值与未知键安全回落 Lucide 灯泡', () {
    expect(nationalFocusDefaultIcon, LucideIcons.lightbulb);
    expect(nationalFocusIconData(null), LucideIcons.lightbulb);
    expect(nationalFocusIconData(''), LucideIcons.lightbulb);
    expect(nationalFocusIconData('  '), LucideIcons.lightbulb);
    expect(nationalFocusIconData('nope:book'), LucideIcons.lightbulb);
    expect(nationalFocusIconData('lucide:book-open'), LucideIcons.bookOpen);
    expect(nationalFocusIconLabel(null), '默认');
    expect(nationalFocusIconLabel('lucide:book-open'), '阅读');
    expect(nationalFocusIconOption('tabler:book')?.label, '阅读');
  });

  testWidgets('四页签图标选择器可选图标、可恢复默认', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.windows),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showNationalFocusIconPicker(
                    context,
                    selectedKey: 'lucide:book-open',
                  );
                },
                child: const Text('打开图标选择器'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开图标选择器'));
    await tester.pumpAndSettle();
    for (final title in const ['默认', 'Tabler', 'Material', 'Cupertino']) {
      expect(find.text(title), findsOneWidget);
    }
    // 首屏是 Lucide 页，选中项带边框徽标。
    expect(
      find.byKey(const ValueKey('national-focus-icon-grid-lucide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('national-focus-icon-lucide:book-open')),
      findsOneWidget,
    );

    await tester.tap(find.text('Tabler'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('national-focus-icon-grid-tabler')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('national-focus-icon-tabler:book')),
    );
    await tester.pumpAndSettle();
    expect(result, 'tabler:book');

    await tester.tap(find.text('打开图标选择器'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('national-focus-icon-reset')));
    await tester.pumpAndSettle();
    expect(result, nationalFocusIconResetSelection);
    expect(nationalFocusIconResetSelection, isEmpty);
  });

  testWidgets('没有选中图标时也可打开选择器并关闭', (tester) async {
    String? result = 'unchanged';
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.dark)
            .copyWith(platform: TargetPlatform.windows),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showNationalFocusIconPicker(context);
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('national-focus-icon-grid-cupertino')),
      findsNothing,
    );
    Navigator.of(tester.element(find.text('选择图标'))).pop();
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
