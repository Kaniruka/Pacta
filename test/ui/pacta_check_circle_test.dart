import 'dart:ui' show CheckedState, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/ui/pacta_check_circle.dart';

SemanticsData _semanticsData(WidgetTester tester) => tester
    .getSemantics(
      find
          .descendant(
            of: find.byType(PactaCheckCircle),
            matching: find.byType(Semantics),
            matchRoot: true,
          )
          .first,
    )
    .getSemanticsData();

void main() {
  testWidgets('圆形勾选保留 48dp 命中区与 checked 语义，点按切换值', (tester) async {
    var value = false;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => PactaCheckCircle(
                value: value,
                semanticLabel: '完成任务',
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );

    final finder = find.byType(PactaCheckCircle);
    expect(tester.getSize(finder), const Size(48, 48));
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

    var data = _semanticsData(tester);
    expect(data.flagsCollection.isChecked, CheckedState.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(finder);
    await tester.pump();
    expect(value, isTrue);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    data = _semanticsData(tester);
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    expect(data.label, '完成任务');
    semantics.dispose();
  });

  testWidgets('禁用态保留圆形与 checked 语义但不响应点按', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PactaCheckCircle(
              value: true,
              semanticLabel: '已完成安排',
              onChanged: null,
            ),
          ),
        ),
      ),
    );

    final finder = find.byType(PactaCheckCircle);
    expect(tester.getSize(finder), const Size(48, 48));
    expect(tester.widget<InkResponse>(find.byType(InkResponse)).onTap, isNull);

    final data = _semanticsData(tester);
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('看板只读圆点保持 18dp 视觉但仍是 checked 语义', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PactaCheckCircle(
              value: true,
              onChanged: null,
              compact: true,
              semanticLabel: '已完成',
            ),
          ),
        ),
      ),
    );

    final finder = find.byType(PactaCheckCircle);
    expect(tester.getSize(finder), const Size(18, 18));
    final data = _semanticsData(tester);
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    expect(data.label, '已完成');
    semantics.dispose();
  });
}
