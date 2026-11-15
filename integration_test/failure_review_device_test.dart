// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';
import '../test/support/fake_calendar_provider.dart';

/// Re-runnable Windows screenshot/interaction fixture for ticket 11.
///
/// Real [PactaApp] with the real pactaTheme/MiSans, fake auth, an in-memory
/// Drift database and in-memory remotes: no server, no real user data.
///
/// Flow: Board review hint -> failure records page directly (collapsed,
/// expanded) -> frozen visual tree -> node frozen requirements -> back to the
/// same record context -> mark reviewed without any note -> Board hint gone.
///
/// Run on Windows (root runs it and inspects the PNGs):
///   flutter test integration_test/failure_review_device_test.dart -d windows
///     --dart-define=NF_FAILURE_REVIEW_CAPTURE_DIR=C:/abs/failure-review-evidence
///
/// Optional dart-defines:
///   NF_FAILURE_REVIEW_THEMES=light,dark   (subset, order preserved)
///   NF_FAILURE_REVIEW_WIDTHS=360,1440     (logical widths)
///   NF_FAILURE_REVIEW_DPR=1               (capture pixel ratio)
///
/// The output directory must be an absolute path and must be absent or empty:
/// the fixture refuses to reuse or overwrite existing evidence.
const _user = 'failure-review-windows-fixture';
const _captureDir = String.fromEnvironment('NF_FAILURE_REVIEW_CAPTURE_DIR');
const _themesDefine = String.fromEnvironment(
  'NF_FAILURE_REVIEW_THEMES',
  defaultValue: 'light,dark',
);
const _widthsDefine = String.fromEnvironment(
  'NF_FAILURE_REVIEW_WIDTHS',
  defaultValue: '360,1440',
);
const _dprDefine = String.fromEnvironment(
  'NF_FAILURE_REVIEW_DPR',
  defaultValue: '1',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('失败回顾 看板提示到标记真实截图', (tester) async {
    final outputDirectory = _resolveOutputDirectory();
    final themes = _parseThemes();
    final widths = _parseWidths();
    final dpr = _parseDevicePixelRatio();

    final written = <String>[];
    for (final theme in themes) {
      for (final width in widths) {
        written.addAll(
          await _runScenario(
            tester: tester,
            theme: theme,
            width: width,
            devicePixelRatio: dpr,
            outputDirectory: outputDirectory,
          ),
        );
      }
    }

    expect(written, isNotEmpty);
    print(
      '[failure-review] 完成：${written.length} 张截图，目录 '
      '${outputDirectory.absolute.path}',
    );
    for (final path in written) {
      print('[failure-review] $path');
    }
  });
}

Directory _resolveOutputDirectory() {
  final raw = _captureDir.trim();
  if (raw.isEmpty) {
    fail(
      '必须提供绝对输出目录：'
      '--dart-define=NF_FAILURE_REVIEW_CAPTURE_DIR=<绝对路径>（例如 C:/abs/evidence）',
    );
  }
  final directory = Directory(raw);
  if (!directory.isAbsolute) {
    fail('输出目录必须是绝对路径，当前为：$raw');
  }
  if (directory.existsSync()) {
    final entries = directory.listSync();
    if (entries.isNotEmpty) {
      fail('拒绝复用或覆盖已有截图目录：${directory.absolute.path}（请换一个空的唯一目录）');
    }
  }
  return directory;
}

List<Brightness> _parseThemes() {
  final themes = <Brightness>[];
  for (final token in _themesDefine.split(',')) {
    final value = token.trim().toLowerCase();
    if (value.isEmpty) continue;
    switch (value) {
      case 'light':
        if (!themes.contains(Brightness.light)) themes.add(Brightness.light);
      case 'dark':
        if (!themes.contains(Brightness.dark)) themes.add(Brightness.dark);
      case 'system':
      case 'both':
        for (final brightness in Brightness.values) {
          if (!themes.contains(brightness)) themes.add(brightness);
        }
      default:
        fail('无法识别的主题「$value」，可用 light/dark/system。');
    }
  }
  if (themes.isEmpty) fail('NF_FAILURE_REVIEW_THEMES 至少要包含一个主题。');
  return themes;
}

List<int> _parseWidths() {
  final widths = <int>[];
  for (final token in _widthsDefine.split(',')) {
    final value = token.trim();
    if (value.isEmpty) continue;
    final width = int.tryParse(value);
    if (width == null || width < 320) {
      fail('逻辑宽度必须是不小于 320 的整数，当前为「$value」。');
    }
    if (!widths.contains(width)) widths.add(width);
  }
  if (widths.isEmpty) fail('NF_FAILURE_REVIEW_WIDTHS 至少要包含一个宽度。');
  return widths;
}

double _parseDevicePixelRatio() {
  final dpr = double.tryParse(_dprDefine.trim());
  if (dpr == null || dpr < 1 || dpr > 4) {
    fail('NF_FAILURE_REVIEW_DPR 必须是 1 到 4 之间的数字，当前为「$_dprDefine」。');
  }
  return dpr;
}

Future<List<String>> _runScenario({
  required WidgetTester tester,
  required Brightness theme,
  required int width,
  required double devicePixelRatio,
  required Directory outputDirectory,
}) async {
  final label = '${theme == Brightness.dark ? 'dark' : 'light'}-${width}w';
  final capturedNames = <String>{};
  final written = <String>[];
  final boundaryKey = GlobalKey();

  SharedPreferences.setMockInitialValues({});
  final database = PactaDatabase(NativeDatabase.memory());
  var now = DateTime.utc(2026, 11, 13, 9);
  final tree = LocalNationalFocusRepository(
    database: database,
    userId: _user,
    cloudSyncEnabled: false,
    now: () => now,
  );
  final tasks = LocalTaskRepository(
    database: database,
    userId: _user,
    remote: InMemoryTaskRemote(),
    now: () => now,
  );
  final focus = LocalFocusRepository(
    database: database,
    userId: _user,
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => now,
  );
  final calendar = LocalCalendarRepository(
    database: database,
    userId: _user,
    provider: FakeCalendarProvider(
      sources: const [],
      permission: CalendarPermissionState.granted,
      events: const [],
    ),
    remote: InMemoryCalendarRemote(),
    cloudSyncEnabled: false,
    now: () => now,
  );

  Future<void> pumpUi() async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(String step) async {
    await pumpUi();
    final name = 'failure-review-$label-$step';
    if (!capturedNames.add(name)) fail('截图名重复：$name');
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      fail('截图「$name」未找到 RepaintBoundary');
    }
    final image = await object.toImage(pixelRatio: devicePixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) fail('截图「$name」PNG 编码失败');
      await outputDirectory.create(recursive: true);
      final file = File(
        '${outputDirectory.path}${Platform.pathSeparator}$name.png',
      );
      if (await file.exists()) {
        fail('拒绝覆盖截图文件：${file.absolute.path}');
      }
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      written.add(file.absolute.path);
    } finally {
      image.dispose();
    }
    expect(tester.takeException(), isNull, reason: '截图 $name 不应抛异常');
  }

  // 真实失败记录：两张卡在同一检查点熄灭，构成一组失败。
  for (final name in ['接到临时需求', '把报告写完']) {
    final card = await tree.createCard(
      NationalFocusCardDraft(name: name, action: '先做十五分钟'),
    );
    await tree.placeCard(cardId: card.id, parentId: null);
    await tree.lightCard(card.id);
  }
  now = DateTime.utc(2026, 11, 13, 20);
  await tree.settleDueCheckpoints();
  now = DateTime.utc(2026, 11, 14, 20);
  await tree.settleDueCheckpoints();
  final failures = await tree.getFailures();
  expect(failures, hasLength(2), reason: '看板提示需要一组含两张卡的失败记录');
  final batchId = failures.first.batchId;
  expect(failures.every((failure) => failure.batchId == batchId), isTrue);

  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    width * devicePixelRatio,
    (width >= 900 ? 900 : 800) * devicePixelRatio,
  );
  tester.platformDispatcher.platformBrightnessTestValue = theme;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
        calendarRepositoryFactory: (_) => calendar,
        cloudCheckClock: () => now,
      ),
    ),
  );
  await pumpUi();

  // 1. 看板未回顾提示。
  final hintFinder = find.byKey(const ValueKey('board-failure-review-hint'));
  expect(hintFinder, findsOneWidget, reason: '看板应提示待回顾失败');
  expect(find.text('1 组国策失败待回顾'), findsOneWidget);
  await shot('01-board-review-hint');

  // 2. 直达失败记录页（不是只把主导航切到国策树）。
  await tester.tap(hintFinder);
  await pumpUi();
  expect(find.byType(NationalFocusFailureHistoryPage), findsOneWidget);
  expect(find.text('国策失败记录'), findsOneWidget);
  expect(find.byType(BoardPage), findsNothing);
  await shot('02-history-collapsed');

  // 3. 展开这一组失败记录。
  await tester.tap(find.textContaining('2 个节点'));
  await pumpUi();
  expect(find.text('查看当时树'), findsOneWidget);
  await shot('03-history-expanded');

  // 4. 冻结的当时树（只读）。
  await tester.tap(find.text('查看当时树'));
  await pumpUi();
  expect(find.text('当时树（只读）'), findsOneWidget);
  await shot('04-frozen-tree');

  // 5. 节点冻结要求。
  final nodeFinder = find.byKey(
    ValueKey('national-focus-history-node-${failures.first.cardId}'),
  );
  expect(nodeFinder, findsOneWidget, reason: '冻结树应包含失败节点');
  await tester.ensureVisible(nodeFinder);
  await tester.tap(nodeFinder);
  await pumpUi();
  expect(find.text('冻结要求'), findsOneWidget);
  expect(find.text('当时状态'), findsOneWidget);
  await shot('05-frozen-node-requirements');

  // 关闭节点详情，回到记录页并保留同一条记录上下文。
  await tester.tapAt(const Offset(6, 6));
  await pumpUi();
  await tester.pageBack();
  await pumpUi();
  expect(find.byType(NationalFocusFailureHistoryPage), findsOneWidget);
  expect(find.textContaining('2 个节点'), findsOneWidget);
  expect(
    find.byKey(const ValueKey('national-focus-mark-reviewed')),
    findsOneWidget,
  );
  await shot('06-history-back-context');

  // 6. 不填说明直接标记已回顾。
  await tester.tap(find.byKey(const ValueKey('national-focus-mark-reviewed')));
  await pumpUi();
  expect(find.textContaining('已回顾'), findsWidgets);
  expect(
    find.byKey(const ValueKey('national-focus-mark-reviewed')),
    findsNothing,
  );
  final marked = await tree.getFailures();
  expect(marked.every((failure) => failure.isReviewed), isTrue);
  expect(
    marked.every((failure) => failure.sharedExplanation == null),
    isTrue,
    reason: '不填说明也能标为已回顾',
  );
  expect(marked.map((failure) => failure.treeSnapshot.length).toSet(), {
    2,
  }, reason: '回顾不得改写冻结快照');
  await shot('07-history-reviewed');

  // 7. 回到看板：提示消失。
  await tester.pageBack();
  await pumpUi();
  expect(find.byType(BoardPage), findsOneWidget);
  expect(hintFinder, findsNothing);
  expect(find.text('1 组国策失败待回顾'), findsNothing);
  await shot('08-board-hint-gone');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tree.dispose();
  await database.close();
  return written;
}
