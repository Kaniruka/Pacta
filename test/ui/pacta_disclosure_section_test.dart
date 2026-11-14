import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/ui/pacta_disclosure_section.dart';

void main() {
  testWidgets(
    'collapsing a focused form closes its input connection and preserves draft',
    (tester) async {
      final focus = FocusNode();
      final controller = TextEditingController();
      addTearDown(focus.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PactaDisclosureSection(
              title: const Text('表单'),
              children: [TextField(focusNode: focus, controller: controller)],
            ),
          ),
        ),
      );
      await tester.tap(find.text('表单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '未保存草稿');
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.text('表单'));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.text('表单'));
      await tester.pumpAndSettle();
      expect(find.text('未保存草稿'), findsOneWidget);
    },
  );

  testWidgets('collapsing does not clear focus in another form', (
    tester,
  ) async {
    final outsideFocus = FocusNode();
    addTearDown(outsideFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const ValueKey('outside'),
                focusNode: outsideFocus,
              ),
              const PactaDisclosureSection(
                title: Text('表单'),
                children: [TextField()],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('表单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outside')));
    expect(outsideFocus.hasFocus, isTrue);
    await tester.tap(find.text('表单'));
    await tester.pumpAndSettle();
    expect(outsideFocus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'filled floating label remains inside disclosure paint area $brightness',
      (tester) async {
        final controller = TextEditingController(text: '已填内容');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: PactaDisclosureSection(
                  title: const Text('表单'),
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: '浮动标签',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('表单'));
        await tester.pumpAndSettle();
        final content = tester.getRect(
          find.byKey(const ValueKey('pacta-disclosure-content')),
        );
        final field = tester.getRect(find.byType(TextField));
        final label = tester.getRect(find.text('浮动标签'));
        expect(label.top, greaterThanOrEqualTo(content.top));
        expect(label.bottom, lessThanOrEqualTo(content.bottom));
        expect(field.top - content.top, greaterThanOrEqualTo(8));
        await tester.tap(find.text('表单'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('表单'));
        await tester.pumpAndSettle();
        expect(find.text('已填内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
