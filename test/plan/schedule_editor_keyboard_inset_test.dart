import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';

/// T4 回归：键盘出现再收起后，编辑框首个字段的浮动标签不得被视口上沿裁切。
///
/// 断言的是渲染几何（行为），不依赖滚动控制器或内边距数值：
/// 只要求「名称」标签完整落在对话框内容视口内。真实 MiSans 字体参与排版，
/// 与 Windows/Android 的标签高度可比。
Future<void> _pumpEditor(WidgetTester tester, Size size) async {
  final fontLoader = FontLoader('MiSans')
    ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));
  await fontLoader.load();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  await tester.pumpWidget(
    MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showScheduleEditor(
                context,
                goals: const [],
                displayTimeZoneId: 'Asia/Shanghai',
                initialDay: DateTime(2026, 11, 17),
              ),
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}

Finder _scrollView() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(SingleChildScrollView),
);

Rect _contentViewport(WidgetTester tester) => tester.getRect(_scrollView());

Rect _nameLabel(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(AlertDialog), matching: find.text('名称')),
);

void _expectLabelInsideViewport(WidgetTester tester) {
  final viewport = _contentViewport(tester);
  final label = _nameLabel(tester);
  expect(
    label.top,
    greaterThanOrEqualTo(viewport.top - 0.5),
    reason:
        '浮动标签上沿被内容视口裁切：label.top=${label.top}, viewport.top=${viewport.top}',
  );
  expect(
    label.bottom,
    lessThanOrEqualTo(viewport.bottom + 0.5),
    reason:
        '浮动标签下沿超出内容视口：label.bottom=${label.bottom}, viewport.bottom=${viewport.bottom}',
  );
}

void main() {
  for (final height in [731.0, 320.0]) {
    testWidgets('键盘收起后名称标签完整可见（411x$height）', (tester) async {
      await _pumpEditor(tester, Size(411, height));

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      _expectLabelInsideViewport(tester);
    });
  }

  testWidgets('向下滚动后收起键盘：内容回到顶部，首字段重新完整可见', (tester) async {
    await _pumpEditor(tester, const Size(411, 731));

    await tester.drag(_scrollView(), const Offset(0, -160));
    await tester.pumpAndSettle();
    final scrolled = _nameLabel(tester).top;
    expect(
      scrolled,
      lessThan(_contentViewport(tester).top),
      reason: '拖动后首字段应被滚出视口，否则这条用例没有判别力',
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    _expectLabelInsideViewport(tester);
  });
}
