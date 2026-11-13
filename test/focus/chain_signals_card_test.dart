import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/chain_signals_card.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_statistics.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;

/// The Focus Marker is shared by the Elite and Regular Focus Chains, so the
/// overview exposes exactly one entry point for it.
const markerEditKey = ValueKey('focus-signal-edit-marker');
const appointmentEditKey = ValueKey('focus-signal-edit-appointment');

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

  testWidgets('overview keeps one marker entry and independent chain records', (
    tester,
  ) async {
    await _pumpOverview(tester, repository);
    expect(find.text('精锐链'), findsOneWidget);
    expect(find.text('普通链'), findsOneWidget);
    expect(find.text('预约链'), findsOneWidget);
    expect(find.byKey(markerEditKey), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-signal-edit-elite')), findsNothing);
    expect(
      find.byKey(const ValueKey('focus-signal-edit-regular')),
      findsNothing,
    );
    expect(find.byKey(appointmentEditKey), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.text('最佳 12 次'), findsOneWidget);
    expect(find.text('1 小时 30 分钟 1 秒'), findsOneWidget);
    expect(find.text('平均每次'), findsNWidgets(2));
    await _disposeWidget(tester);
  });

  testWidgets('one marker edit gives both chains the same launch summary', (
    tester,
  ) async {
    await _pumpOverview(tester, repository, showInstructions: true);
    expect(find.text('精锐链专注标志：尚未设置'), findsOneWidget);
    expect(find.text('普通链专注标志：尚未设置'), findsOneWidget);

    await _editAndSave(tester, markerEditKey, '戴上指定耳机');

    expect(find.text('戴上指定耳机'), findsOneWidget);
    expect(find.text('精锐链专注标志：戴上指定耳机'), findsOneWidget);
    expect(find.text('普通链专注标志：戴上指定耳机'), findsOneWidget);
    await _disposeWidget(tester);
  });

  testWidgets('appointment trigger signal stays independent of the marker', (
    tester,
  ) async {
    await _pumpOverview(tester, repository, showInstructions: true);
    await _editAndSave(tester, markerEditKey, '共用动作');

    await _editAndSave(tester, appointmentEditKey, '预约动作');

    expect(find.text('预约触发信号：预约动作'), findsNWidgets(2));
    expect(find.text('精锐链专注标志：共用动作'), findsOneWidget);
    expect(find.text('普通链专注标志：共用动作'), findsOneWidget);

    await _openEditor(tester, appointmentEditKey);
    await tester.enterText(find.byType(TextField), '不应保存的改动');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('预约触发信号：预约动作'), findsNWidgets(2));
    expect(find.text('不应保存的改动'), findsNothing);
    await _disposeWidget(tester);
  });

  testWidgets('marker edits leave each chain record independent', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      repository,
      records: [
        FocusChainRecord(
          mode: FocusChainMode.elite,
          currentConsecutive: 7,
          bestConsecutive: 12,
          updatedAt: DateTime(2026),
        ),
        FocusChainRecord(
          mode: FocusChainMode.regular,
          currentConsecutive: 3,
          bestConsecutive: 5,
          hasPendingReview: true,
          updatedAt: DateTime(2026),
        ),
      ],
      statistics: const {
        FocusChainMode.elite: FocusSessionStatistics(
          totalDurationSeconds: 3600,
          acceptedSessionCount: 2,
        ),
        FocusChainMode.regular: FocusSessionStatistics(
          totalDurationSeconds: 125,
          acceptedSessionCount: 2,
        ),
      },
    );
    expect(find.text('最佳 12 次'), findsOneWidget);
    expect(find.text('最佳 5 次'), findsOneWidget);
    expect(find.text('记录待核对'), findsOneWidget);

    await _editAndSave(tester, markerEditKey, '坐到书桌前');

    expect(find.text('坐到书桌前'), findsOneWidget);
    expect(find.text('最佳 12 次'), findsOneWidget);
    expect(find.text('最佳 5 次'), findsOneWidget);
    expect(find.text('记录待核对'), findsOneWidget);
    expect(find.text('1 小时'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
    expect(find.text('2 分钟 5 秒'), findsOneWidget);
    expect(find.text('1 分钟 3 秒'), findsOneWidget);
    await _disposeWidget(tester);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 600.0, 960.0]) {
      testWidgets(
        'normal text keeps long actions and durations at $width in $brightness',
        (tester) async {
          const action = '坐到书桌前，整理所有准备材料，戴上耳机并写下本次专注要完成的第一步';
          await repository.save(const ChainSignalTexts(focusMarker: action));
          await _pumpOverview(
            tester,
            repository,
            width: width,
            brightness: brightness,
            eliteTotalSeconds: 360000001,
          );
          expect(find.text(action), findsOneWidget);
          expect(find.text('100000 小时 1 秒'), findsOneWidget);
          expect(find.text('最佳 12 次'), findsOneWidget);
          await _openEditor(tester, markerEditKey);
          expect(find.widgetWithText(TextField, action), findsOneWidget);
          await tester.enterText(find.byType(TextField), '取消的修改');
          await tester.tap(find.widgetWithText(TextButton, '取消'));
          await tester.pumpAndSettle();
          expect(find.text(action), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _disposeWidget(tester);
        },
      );
    }

    testWidgets('overview survives narrow 2x text in $brightness', (
      tester,
    ) async {
      await repository.save(
        const ChainSignalTexts(
          appointmentTriggerSignal: '开始前戴上耳机并整理桌面直到一切准备妥当',
          focusMarker: '坐到指定位置并打开当前任务阅读所有准备材料',
        ),
      );
      await _pumpOverview(
        tester,
        repository,
        width: 320,
        scale: 2,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('坐到指定位置并打开当前任务阅读所有准备材料'), findsOneWidget);
      await _disposeWidget(tester);
    });
  }

  testWidgets('overview without repository shows unconfigured actions', (
    tester,
  ) async {
    await _pumpOverview(tester, null);
    expect(find.text('尚未设置'), findsNWidgets(2));
    expect(find.byType(IconButton), findsNothing);
    await _disposeWidget(tester);
  });

  testWidgets(
    'zero records keep all three chains and both duration summaries',
    (tester) async {
      await _pumpCard(tester, repository);
      for (final title in ['精锐链', '普通链', '预约链']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('最佳 0 次'), findsNWidgets(3));
      expect(find.text('累计专注'), findsNWidgets(2));
      expect(find.text('平均每次'), findsNWidgets(2));
      expect(find.text('0 秒'), findsNWidgets(4));
      expect(find.text('尚未设置'), findsNWidgets(2));
      await _disposeWidget(tester);
    },
  );

  testWidgets('instructions show the shared marker in both chain flows', (
    tester,
  ) async {
    await repository.save(const ChainSignalTexts(focusMarker: '打开深度任务'));
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
                  mode: FocusChainMode.elite,
                ),
                ChainSignalInstructions(
                  repository: repository,
                  mode: FocusChainMode.regular,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('精锐链专注标志：打开深度任务'), findsOneWidget);
    expect(find.text('普通链专注标志：打开深度任务'), findsOneWidget);
    await _disposeWidget(tester);
  });
}

Future<void> _openEditor(WidgetTester tester, Key key) async {
  final edit = find.byKey(key);
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

Future<void> _editAndSave(WidgetTester tester, Key key, String text) async {
  await _openEditor(tester, key);
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
}

Future<void> _pumpCard(
  WidgetTester tester,
  ChainSignalsRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FocusChainOverview(
            repository: repository,
            records: const [],
            statistics: const {},
          ),
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

Future<void> _pumpOverview(
  WidgetTester tester,
  ChainSignalsRepository? repository, {
  double width = 700,
  double scale = 1,
  Brightness brightness = Brightness.light,
  int eliteTotalSeconds = 5401,
  List<FocusChainRecord>? records,
  Map<FocusChainMode, FocusSessionStatistics>? statistics,
  bool showInstructions = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final overviewRecords =
      records ??
      [
        FocusChainRecord(
          mode: FocusChainMode.elite,
          currentConsecutive: 7,
          bestConsecutive: 12,
          updatedAt: DateTime(2026),
        ),
      ];
  final overviewStatistics =
      statistics ??
      {
        FocusChainMode.elite: FocusSessionStatistics(
          totalDurationSeconds: eliteTotalSeconds,
          acceptedSessionCount: 3,
        ),
      };
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff385a52),
          brightness: brightness,
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusChainOverview(
                        repository: repository,
                        records: overviewRecords,
                        statistics: overviewStatistics,
                      ),
                      if (showInstructions && repository != null) ...[
                        const SizedBox(height: 12),
                        for (final mode in FocusChainMode.values)
                          ChainSignalInstructions(
                            repository: repository,
                            mode: mode,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
