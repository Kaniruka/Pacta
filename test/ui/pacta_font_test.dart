import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/theme/pacta_fonts.dart';

import '../support/fake_auth_repository.dart';

const _styleNames = <String>[
  'displayLarge',
  'displayMedium',
  'displaySmall',
  'headlineLarge',
  'headlineMedium',
  'headlineSmall',
  'titleLarge',
  'titleMedium',
  'titleSmall',
  'bodyLarge',
  'bodyMedium',
  'bodySmall',
  'labelLarge',
  'labelMedium',
  'labelSmall',
];

void main() {
  test('亮暗主题所有语义字号与回退都收敛到 MiSans', () {
    for (final brightness in Brightness.values) {
      final theme = pactaTheme(brightness);
      for (final name in _styleNames) {
        final style = _styleOf(theme.textTheme, name);
        expect(style, isNotNull, reason: '${brightness.name} $name 存在');
        expect(
          style!.fontFamily,
          PactaFonts.family,
          reason: '${brightness.name} $name 字体族',
        );
        expect(
          style.fontFamilyFallback,
          anyOf(isNull, everyElement(PactaFonts.family)),
          reason: '${brightness.name} $name 不得回退到其它字体',
        );
        expect(
          style.fontWeight,
          isIn([
            PactaFonts.regular,
            PactaFonts.medium,
            PactaFonts.semibold,
            PactaFonts.bold,
          ]),
          reason: '${brightness.name} $name 字重必须有对应 MiSans 文件',
        );
      }
      final primary = theme.primaryTextTheme;
      for (final name in _styleNames) {
        final style = _styleOf(primary, name);
        expect(
          style?.fontFamily,
          PactaFonts.family,
          reason: '${brightness.name} primary $name 字体族',
        );
        expect(
          style?.fontWeight,
          isIn([
            PactaFonts.regular,
            PactaFonts.medium,
            PactaFonts.semibold,
            PactaFonts.bold,
          ]),
          reason: '${brightness.name} primary $name 字重必须有对应文件',
        );
      }
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: MiSans'));
    for (final weight in [400, 500, 600, 700]) {
      final pattern = RegExp(
        r'asset:\s*assets/fonts/MiSans-[A-Za-z]+\.ttf\s*\r?\n\s*weight:\s*'
        '$weight'
        r'\b',
      );
      expect(
        pattern.hasMatch(pubspec),
        isTrue,
        reason: 'pubspec 应声明 MiSans $weight 字重文件',
      );
    }
  });

  testWidgets('五个一级页面与计划日历的可见文字都使用 MiSans', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository()..signedInUser = 'font-user';
    await tester.pumpWidget(PactaApp(authRepository: auth));
    await tester.pumpAndSettle();

    for (final label in ['看板', '计划', '国策树', '专注链', '我的']) {
      await _openDestination(tester, label);
      _expectMiSans(tester, label);
    }

    await _openDestination(tester, '计划');
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    _expectMiSans(tester, '计划日历');

    await tester.tap(find.text('目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建目标'));
    await tester.pumpAndSettle();
    _expectMiSans(tester, '新建目标对话框');
    for (final editable in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(editable.style.fontFamily, PactaFonts.family);
    }
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Tooltip、SnackBar、对话框与输入框的有效字体均为 MiSans', (tester) async {
    final controller = TextEditingController(text: '输入内容');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Tooltip(
                  message: '提示文字',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Text('提示目标'),
                ),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '输入标签',
                    helperText: '输入说明',
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('保存成功'))),
                  child: const Text('显示消息'),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('对话框标题'),
                      content: const Text('对话框正文'),
                      actions: [
                        TextButton(onPressed: null, child: Text('对话框动作')),
                      ],
                    ),
                  ),
                  child: const Text('显示对话框'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final editable in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(editable.style.fontFamily, PactaFonts.family);
    }

    await tester.tap(find.text('提示目标'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('提示文字'), findsOneWidget);
    _expectMiSans(tester, 'Tooltip');
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();

    await tester.tap(find.text('显示消息'));
    await tester.pump();
    expect(find.text('保存成功'), findsOneWidget);
    _expectMiSans(tester, 'SnackBar');
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.text('显示对话框'));
    await tester.pumpAndSettle();
    expect(find.text('对话框标题'), findsOneWidget);
    _expectMiSans(tester, '对话框');
    await tester.tap(find.text('对话框动作'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

TextStyle? _styleOf(TextTheme theme, String name) => switch (name) {
  'displayLarge' => theme.displayLarge,
  'displayMedium' => theme.displayMedium,
  'displaySmall' => theme.displaySmall,
  'headlineLarge' => theme.headlineLarge,
  'headlineMedium' => theme.headlineMedium,
  'headlineSmall' => theme.headlineSmall,
  'titleLarge' => theme.titleLarge,
  'titleMedium' => theme.titleMedium,
  'titleSmall' => theme.titleSmall,
  'bodyLarge' => theme.bodyLarge,
  'bodyMedium' => theme.bodyMedium,
  'bodySmall' => theme.bodySmall,
  'labelLarge' => theme.labelLarge,
  'labelMedium' => theme.labelMedium,
  'labelSmall' => theme.labelSmall,
  _ => null,
};

Future<void> _openDestination(WidgetTester tester, String label) async {
  final host = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void _expectMiSans(WidgetTester tester, String where) {
  var checked = 0;
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    void visit(InlineSpan span, TextStyle? inherited) {
      final style = span.style == null
          ? inherited
          : (inherited?.merge(span.style) ?? span.style);
      final text = span is TextSpan ? span.text ?? '' : '';
      if (text.trim().isNotEmpty) {
        if (style?.fontFamily == Icons.check.fontFamily) return;
        expect(
          style?.fontFamily,
          PactaFonts.family,
          reason: '$where 文本“$text”的有效字体族',
        );
        checked++;
      }
      if (span is TextSpan) {
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }
    }

    visit(render.text, null);
  }
  expect(checked, greaterThan(0), reason: '$where 应至少读到一段文字');
}
