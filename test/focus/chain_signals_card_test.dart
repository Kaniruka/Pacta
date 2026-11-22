import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/chain_signals_card.dart'
    show
        ChainSignalInstructions,
        FocusChainOverview,
        appointmentEntryRule,
        appointmentNoteKey,
        focusChainNoteKey,
        focusDurationRule,
        sharedFocusMarkerRule,
        sharedSignalHelperText,
        singleSignalHelperText;
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_statistics.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/theme/pacta_icon_sizes.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';

/// The Focus Marker is shared by the Elite and Regular Focus Chains, so the
/// overview exposes exactly one entry point for it.
const markerEditKey = ValueKey('focus-signal-edit-marker');
const appointmentEditKey = ValueKey('focus-signal-edit-appointment');
const chainTable = ValueKey('focus-chain-table');

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
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1小时30分01秒'), findsOneWidget);
    // 三条链都带「累计/平均」：预约链不再只有连续次数、没有时长。
    expect(find.text('累计'), findsNWidgets(3));
    expect(find.text('平均'), findsNWidgets(3));
    // 表头行已删除：数字直接跟在自己的链名下读，不再靠表格列对齐。
    expect(find.text('当前连续'), findsNothing);
    expect(find.text('历史最高'), findsNothing);
    expect(find.text('连续'), findsNWidgets(3));
    expect(find.text('最高'), findsNWidgets(3));
    await _disposeWidget(tester);
  });

  testWidgets('one marker edit gives both chains the same launch summary', (
    tester,
  ) async {
    await _pumpOverview(tester, repository, showInstructions: true);
    expect(_instructionText('触发信号'), findsNWidgets(2));
    expect(_instructionText('专注标志'), findsNWidgets(2));
    expect(_instructionText('未设置'), findsNWidgets(4));

    await _editAndSave(tester, markerEditKey, '戴上指定耳机');

    // 值只在说明行里出现两次，不再重复「精锐链专注标志：」这类长前缀。
    expect(
      find.descendant(
        of: find.byType(ChainSignalInstructions),
        matching: find.text('戴上指定耳机'),
      ),
      findsNWidgets(2),
    );
    expect(_instructionText('未设置'), findsNWidgets(2));
    await _disposeWidget(tester);
  });

  testWidgets('appointment trigger signal stays independent of the marker', (
    tester,
  ) async {
    await _pumpOverview(tester, repository, showInstructions: true);
    await _editAndSave(tester, markerEditKey, '共用动作');

    await _editAndSave(tester, appointmentEditKey, '预约动作');

    expect(
      find.descendant(
        of: find.byType(ChainSignalInstructions),
        matching: find.text('预约动作'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byType(ChainSignalInstructions),
        matching: find.text('共用动作'),
      ),
      findsNWidgets(2),
    );

    await _openEditor(tester, appointmentEditKey);
    await tester.enterText(find.byType(TextField), '不应保存的改动');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ChainSignalInstructions),
        matching: find.text('预约动作'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('不应保存的改动'), findsNothing);
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
          expect(find.text('100000小时00分01秒'), findsOneWidget);
          expect(find.text('12'), findsOneWidget);
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
      expect(find.text('0'), findsNWidgets(6));
      expect(find.text('累计'), findsNWidgets(3));
      expect(find.text('平均'), findsNWidgets(3));
      expect(find.text('0分00秒'), findsNWidgets(6));
      expect(find.text('尚未设置'), findsNWidgets(2));
      await _disposeWidget(tester);
    },
  );

  testWidgets('三条链是等高的 M3 分段卡片，段间只有 2dp 透明间隙', (tester) async {
    for (final width in [700.0, 360.0]) {
      await _pumpOverview(tester, repository, width: width);
      final table = find.byKey(chainTable);
      final segments = find.descendant(
        of: table,
        matching: find.byType(Material),
      );
      final rects = [
        for (var index = 0; index < segments.evaluate().length; index++)
          tester.getRect(segments.at(index)),
      ];
      expect(rects, hasLength(3), reason: '$width: 三条链各自成段');
      for (var index = 1; index < rects.length; index++) {
        expect(
          rects[index].top - rects[index - 1].bottom,
          moreOrLessEquals(2, epsilon: 0.01),
          reason: '$width: 第 $index 段与上一段之间是 2dp 透明间隙',
        );
      }
      expect(find.byType(Divider), findsNothing, reason: '分段靠间隙，不靠细线');

      // 统一内边距 + 统一双行结构：三张卡的外高严格相等。
      expect(
        rects[1].height,
        moreOrLessEquals(rects[0].height, epsilon: 1.0),
        reason: '$width: 普通链与精锐链等高',
      );
      expect(
        rects[2].height,
        moreOrLessEquals(rects[0].height, epsilon: 1.0),
        reason: '$width: 预约链与精锐链等高',
      );
      await _disposeWidget(tester);
    }
  });

  testWidgets('320dp 2 倍字号下三条链卡片不溢出、不互相挤压', (tester) async {
    await _pumpOverview(tester, repository, width: 320, scale: 2);
    expect(tester.takeException(), isNull);
    for (final label in ['精锐链', '普通链', '预约链']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('累计'), findsNWidgets(3));
    expect(find.text('平均'), findsNWidgets(3));
    expect(
      tester.getSize(find.byKey(chainTable)).width,
      lessThanOrEqualTo(320),
    );
    await _disposeWidget(tester);
  });

  testWidgets('预约链累计与平均来自实际准备耗时统计', (tester) async {
    await _pumpOverview(
      tester,
      repository,
      appointmentStatistics: const FocusSessionStatistics(
        totalDurationSeconds: 1830,
        acceptedSessionCount: 2,
      ),
    );
    // 1830s = 30分30秒；平均 915s = 15分15秒。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('focus-chain-stat-预约链-累计')),
        matching: find.text('30分30秒'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('focus-chain-stat-预约链-平均')),
        matching: find.text('15分15秒'),
      ),
      findsOneWidget,
    );
    await _disposeWidget(tester);
  });

  testWidgets('规则说明折进信息提示：折叠时不占正文，点开才出现', (tester) async {
    await _pumpOverview(tester, repository);
    expect(find.text(focusDurationRule), findsNothing);
    expect(find.text(sharedFocusMarkerRule), findsNothing);

    // 说明挂在「累计/平均」那一行，而不是表头或卡片外。
    expect(find.byKey(focusChainNoteKey), findsOneWidget);
    await tester.tap(find.byKey(focusChainNoteKey));
    await tester.pumpAndSettle();
    expect(find.text(focusDurationRule), findsOneWidget);

    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    expect(find.text(focusDurationRule), findsNothing);

    await tester.tap(find.byKey(const ValueKey('focus-signal-note-marker')));
    await tester.pumpAndSettle();
    expect(find.text(sharedFocusMarkerRule), findsOneWidget);
    // 触发信号没有共用关系，不挂提示。
    expect(
      find.byKey(const ValueKey('focus-signal-note-appointment')),
      findsNothing,
    );
    await _disposeWidget(tester);
  });

  testWidgets('预约入口提示挂在链名行：点行内文字即可展开，命中区覆盖整行', (tester) async {
    await _pumpOverview(
      tester,
      repository,
      appointmentRecord: AppointmentChainRecord(
        currentConsecutive: 2,
        bestConsecutive: 4,
        updatedAt: DateTime(2026),
      ),
    );
    // 入口句不作为正文出现，图标与「预约链」同属一条标题行。
    expect(find.text(appointmentEntryRule), findsNothing);
    final noteFinder = find.byKey(appointmentNoteKey);
    expect(noteFinder, findsOneWidget);
    expect(
      find.descendant(of: noteFinder, matching: find.text('预约链')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: noteFinder,
        matching: find.byIcon(Icons.info_outline),
      ),
      findsOneWidget,
    );

    // 命中区是整条标题行（链名 + 两个数值列），不是 12dp 图标本身。
    final rowWidth = tester.getSize(noteFinder).width;
    final cardWidth = tester.getSize(find.byKey(chainTable)).width;
    expect(rowWidth, greaterThan(cardWidth * 0.9));

    await tester.tap(find.text('预约链'));
    await tester.pumpAndSettle();
    expect(find.text(appointmentEntryRule), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    expect(find.text(appointmentEntryRule), findsNothing);
    await _disposeWidget(tester);
  });

  testWidgets('预约入口句进入语义：读屏读得到，不只在视觉提示里', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpOverview(tester, repository);
    expect(
      tester
          .getSemantics(find.byKey(appointmentNoteKey))
          .getSemanticsData()
          .tooltip,
      appointmentEntryRule,
    );
    // 时长口径句同样独立成节点，两条说明不会互相覆盖。
    expect(
      tester
          .getSemantics(find.byKey(focusChainNoteKey))
          .getSemanticsData()
          .tooltip,
      focusDurationRule,
    );
    semantics.dispose();
    await _disposeWidget(tester);
  });

  testWidgets('提示的语义边界不吞掉累计与平均的数值', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpOverview(tester, repository);
    final data = tester
        .getSemantics(find.byKey(const ValueKey('focus-chain-stat-精锐链-累计')))
        .getSemanticsData();
    expect(data.label, contains('累计'));
    expect(data.label, contains('1小时30分01秒'));
    expect(data.label, contains('平均'));
    expect(data.label, contains('30分00秒'));
    semantics.dispose();
    await _disposeWidget(tester);
  });

  testWidgets('编辑弹窗说明只说共用关系与清除结果', (tester) async {
    await _pumpOverview(tester, repository);

    await _openEditor(tester, markerEditKey);
    final markerDialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: markerDialog,
        matching: find.text(sharedSignalHelperText),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: markerDialog,
        matching: find.text(singleSignalHelperText),
      ),
      findsNothing,
    );
    // 弹窗只放简短说明，完整规则句留在卡片提示里。
    expect(
      find.descendant(
        of: markerDialog,
        matching: find.text(sharedFocusMarkerRule),
      ),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    await _openEditor(tester, appointmentEditKey);
    final appointmentDialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: appointmentDialog,
        matching: find.text(singleSignalHelperText),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: appointmentDialog,
        matching: find.text(sharedSignalHelperText),
      ),
      findsNothing,
    );
    await _disposeWidget(tester);
  });

  testWidgets('说明图标不高于正文：micro 档图标，提示用悬停/点按', (tester) async {
    await _pumpOverview(tester, repository);
    final glyphs = tester.widgetList<Icon>(find.byIcon(Icons.info_outline));
    expect(glyphs, isNotEmpty);
    for (final glyph in glyphs) {
      expect(
        glyph.size,
        PactaIconSizes.micro,
        reason: '说明图标应与辅助文本同级，不抢标题的视觉重量',
      );
    }
    await _disposeWidget(tester);
  });

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

    // 两条链各自一份说明：标签同排对齐，值不再挂链名前缀。
    expect(_instructionText('触发信号'), findsNWidgets(2));
    expect(_instructionText('专注标志'), findsNWidgets(2));
    expect(_instructionText('打开深度任务'), findsNWidgets(2));
    expect(_instructionText('未设置'), findsNWidgets(2));
    await _disposeWidget(tester);
  });
}

/// 说明卡里的文字：与信号卡自身的动作标签区分开。
Finder _instructionText(String text) => find.descendant(
  of: find.byType(ChainSignalInstructions),
  matching: find.text(text),
);

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
      theme: ThemeData(extensions: const [PactaSurfaces.light]),
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
  AppointmentChainRecord? appointmentRecord,
  FocusSessionStatistics? appointmentStatistics,
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
        // 分组列表从主题扩展取卡片与 hairline；组件测试也要带上同一套令牌。
        extensions: [
          brightness == Brightness.dark
              ? PactaSurfaces.dark
              : PactaSurfaces.light,
        ],
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
                        appointmentRecord: appointmentRecord,
                        statistics: overviewStatistics,
                        appointmentStatistics: appointmentStatistics,
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
