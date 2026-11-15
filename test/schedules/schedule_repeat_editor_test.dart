import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repeat_editor.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认不重复，打开后给出每天的重复设置', (tester) async {
    var selection = const ScheduleRepeatSelection.none();
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ScheduleRepeatEditor(
          value: selection,
          onChanged: (next) => setState(() => selection = next),
        ),
      ),
    );

    expect(selection.repeats, isFalse);
    expect(find.text('每天'), findsNothing);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(selection.repeats, isTrue);
    expect(selection.frequency, ScheduleRepeatFrequency.daily);
    expect(selection.weekdays, isEmpty);
    expect(selection.isValid, isTrue);
    expect(find.text('每天'), findsOneWidget);
    expect(find.text('每周'), findsOneWidget);
  });

  testWidgets('切到每周后可选星期，未选满时标记为无效', (tester) async {
    var selection = const ScheduleRepeatSelection.repeating(
      frequency: ScheduleRepeatFrequency.weekly,
      weekdays: {},
    );
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ScheduleRepeatEditor(
          value: selection,
          onChanged: (next) => setState(() => selection = next),
        ),
      ),
    );

    expect(selection.isValid, isFalse);
    expect(find.text('每周至少选一天'), findsOneWidget);

    await tester.tap(find.text('周三'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周五'));
    await tester.pumpAndSettle();

    expect(selection.weekdays, {3, 5});
    expect(selection.isValid, isTrue);
    expect(find.text('每周至少选一天'), findsNothing);

    await tester.tap(find.text('周三'));
    await tester.pumpAndSettle();
    expect(selection.weekdays, {5});
  });

  testWidgets('结束日期可选可清空，并映射为规则属性', (tester) async {
    var selection = const ScheduleRepeatSelection.repeating(
      frequency: ScheduleRepeatFrequency.daily,
    );
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ScheduleRepeatEditor(
          value: selection,
          firstDate: DateTime.utc(2026, 11, 16),
          onChanged: (next) => setState(() => selection = next),
        ),
      ),
    );

    expect(find.text('不结束'), findsOneWidget);

    await tester.tap(find.text('不结束'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(selection.endDate, '2026-11-20');
    expect(find.text('2026-11-20'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schedule-repeat-clear-end')));
    await tester.pumpAndSettle();
    expect(selection.endDate, isNull);
    expect(find.text('不结束'), findsOneWidget);
  });

  testWidgets('重复设置映射为仓储可直接使用的 spec', (tester) async {
    const selection = ScheduleRepeatSelection.repeating(
      frequency: ScheduleRepeatFrequency.weekly,
      weekdays: {1, 3},
      endDate: '2026-12-31',
    );

    final spec = selection.spec!;
    expect(spec.frequency, ScheduleRepeatFrequency.weekly);
    expect(spec.weekdays, {1, 3});
    expect(spec.endDate, '2026-12-31');
    expect(const ScheduleRepeatSelection.none().spec, isNull);
    expect(
      () => const ScheduleRepeatSelection.repeating(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {},
      ).spec,
      throwsArgumentError,
    );
  });

  testWidgets('修改范围选择器给出两种范围', (tester) async {
    var scope = ScheduleRepeatScope.onlyThis;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ScheduleRepeatScopeSelector(
          value: scope,
          onChanged: (next) => setState(() => scope = next),
        ),
      ),
    );

    expect(find.text('仅本次'), findsOneWidget);
    expect(find.text('本次及以后'), findsOneWidget);
    expect(scope, ScheduleRepeatScope.onlyThis);

    await tester.tap(find.text('本次及以后'));
    await tester.pumpAndSettle();
    expect(scope, ScheduleRepeatScope.thisAndFuture);
  });
}
