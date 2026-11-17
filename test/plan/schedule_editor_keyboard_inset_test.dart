import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';

/// T4 回归：键盘出现再收起后，编辑框首个字段的浮动标签不得被视口上沿裁切。
///
/// 这是行为断言（渲染几何），不依赖滚动控制器、内边距等实现细节：
/// 只要求「名称」标签完整落在对话框内容视口内。
Future<void> _pumpEditor(WidgetTester tester, Size size) async {
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

Rect _contentViewport(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(SingleChildScrollView),
  ),
);

Rect _nameLabel(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(AlertDialog), matching: find.text('名称')),
);

void main() {
  for (final height in [731.0, 320.0]) {
    testWidgets('键盘收起后名称标签完整可见（411x$height）', (tester) async {
      await _pumpEditor(tester, Size(411, height));

      // 键盘弹出：内容视口被压缩，输入框会滚动到可见位置。
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      // 键盘收起：视口恢复，滚动位置不应把首字段顶到视口外。
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

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
    });
  }
}
