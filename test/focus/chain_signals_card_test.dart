import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/chain_signals_card.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late ChainSignalsRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = ChainSignalsRepository(database: database, userId: 'user-a');
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('editor saves the selected signal and preserves the others', (
    tester,
  ) async {
    await repository.save(
      const ChainSignalTexts(
        appointmentTriggerSignal: '原触发信号',
        eliteFocusMarker: '精锐标志',
        regularFocusMarker: '普通标志',
      ),
    );
    await _pumpCard(tester, repository);

    await tester.tap(find.text('编辑触发信号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '戴上指定耳机');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final saved = await repository.get();
    expect(saved.appointmentTriggerSignal, '戴上指定耳机');
    expect(saved.eliteFocusMarker, '精锐标志');
    expect(saved.regularFocusMarker, '普通标志');
    expect(find.text('戴上指定耳机'), findsOneWidget);
    await _disposeWidget(tester);
  });

  testWidgets('cancel closes the editor without saving its changes', (
    tester,
  ) async {
    await repository.save(
      const ChainSignalTexts(appointmentTriggerSignal: '原触发信号'),
    );
    await _pumpCard(tester, repository);

    await tester.tap(find.text('编辑触发信号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不应保存的改动');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect((await repository.get()).appointmentTriggerSignal, '原触发信号');
    expect(find.text('不应保存的改动'), findsNothing);
    expect(find.text('预约链 · 触发信号'), findsOneWidget);
    await _disposeWidget(tester);
  });

  testWidgets('saving an empty value clears only the selected signal', (
    tester,
  ) async {
    await repository.save(
      const ChainSignalTexts(
        appointmentTriggerSignal: '要清除的信号',
        eliteFocusMarker: '精锐标志',
        regularFocusMarker: '普通标志',
      ),
    );
    await _pumpCard(tester, repository);

    await tester.tap(find.text('编辑触发信号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final saved = await repository.get();
    expect(saved.appointmentTriggerSignal, isEmpty);
    expect(saved.eliteFocusMarker, '精锐标志');
    expect(saved.regularFocusMarker, '普通标志');
    expect(find.text('尚未设置'), findsOneWidget);
    await _disposeWidget(tester);
  });

  testWidgets('card lays out at 320 logical pixels with text scaled to 2×', (
    tester,
  ) async {
    await repository.save(
      const ChainSignalTexts(
        appointmentTriggerSignal: '开始前戴上耳机并整理桌面',
        eliteFocusMarker: '坐到指定位置并打开当前任务',
        regularFocusMarker: '拿起阅读材料并从上次位置继续',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: const Size(320, 800),
                  textScaler: const TextScaler.linear(2),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: ChainSignalsCard(repository: repository),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('神圣座位'), findsOneWidget);
    expect(find.text('拿起阅读材料并从上次位置继续'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('instructions show the marker for the currently selected mode', (
    tester,
  ) async {
    await repository.save(
      const ChainSignalTexts(
        appointmentTriggerSignal: '到达预约地点',
        eliteFocusMarker: '打开深度任务',
        regularFocusMarker: '翻开阅读材料',
      ),
    );
    var selectedMode = FocusChainMode.elite;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                DropdownButton<FocusChainMode>(
                  value: selectedMode,
                  items: [
                    for (final mode in FocusChainMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => selectedMode = mode);
                  },
                ),
                ChainSignalInstructions(
                  repository: repository,
                  mode: selectedMode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('预约触发信号：到达预约地点'), findsOneWidget);
    expect(find.text('精锐链专注标志：打开深度任务'), findsOneWidget);
    expect(find.text('普通链专注标志：翻开阅读材料'), findsNothing);

    await tester.tap(find.byType(DropdownButton<FocusChainMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(FocusChainMode.regular.label).last);
    await tester.pumpAndSettle();

    expect(find.text('预约触发信号：到达预约地点'), findsOneWidget);
    expect(find.text('普通链专注标志：翻开阅读材料'), findsOneWidget);
    expect(find.text('精锐链专注标志：打开深度任务'), findsNothing);
    await _disposeWidget(tester);
  });
}

Future<void> _pumpCard(
  WidgetTester tester,
  ChainSignalsRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChainSignalsCard(repository: repository),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
