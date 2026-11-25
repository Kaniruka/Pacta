import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 国策 v4 / 云快照 v4 的六状态真机截图夹具。
///
/// 真实 [PactaDatabase]（内存）+ 真实仓储 + 真实页面与主题，没有服务器、没有
/// 真实账号。按顺序采集并自检：
///   01-editor-with-icon          编辑页基础内容卡的图标预览
///   02-icon-picker-tabs          四套图标分页选择器
///   03-strengthening-solid-selected  强化要求选中行实底 + 主色强调条
///   04-editor-unsaved-prompt     返回时的未保存三选一确认
///   05-tree-custom-icons         国策树节点按 iconKey 渲染
///   06-failure-history-clean     无检查点说明的高对比失败记录页
///
/// Windows：
///   flutter test integration_test/national_focus_v4_ui_device_test.dart -d windows
///     --dart-define=NF_V4_CAPTURE_DIR=C:/abs/nf-v4-evidence
///     --dart-define=NF_V4_THEME=light        （或 dark / light,dark）
///
/// Android：
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/national_focus_v4_ui_device_test.dart -d emulator-5554
///
/// Windows 默认视口 393×873dp（20:9 全面屏），Android 使用设备真实视口并走
/// IntegrationTestWidgetsFlutterBinding.takeScreenshot。
const String _captureDir = String.fromEnvironment('NF_V4_CAPTURE_DIR');
const String _themeDefine = String.fromEnvironment(
  'NF_V4_THEME',
  defaultValue: 'light',
);
const String _user = 'nf-v4-ui-fixture';
const Size _windowsViewport = Size(393, 873);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策 v4 六状态截图自检', (tester) async {
    final themes = _parseThemes();
    final outputDirectory = _resolveOutputDirectory(themes.length);
    if (!Platform.isAndroid) {
      tester.view.physicalSize = _windowsViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    } else {
      // Android 截图必须先把 Flutter 表面转成图片，否则 takeScreenshot 抛
      // "Call convertFlutterSurfaceToImage() before taking a screenshot"。
      await IntegrationTestWidgetsFlutterBinding.instance
          .convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }
    SharedPreferences.setMockInitialValues({});
    final boundaryKey = GlobalKey();
    final written = <String>[];

    for (final brightness in themes) {
      final run = await _seed(tester);
      final suffix = themes.length > 1
          ? '-${brightness == Brightness.dark ? 'dark' : 'light'}'
          : '';
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final path = await _capture(
          tester,
          name: name + suffix,
          outputDirectory: outputDirectory,
          boundaryKey: boundaryKey,
        );
        written.add(path);
        if (!Platform.isAndroid) {
          final file = File(path);
          expect(
            file.existsSync() && file.lengthSync() > 0,
            isTrue,
            reason: '截图必须真实落盘：$path',
          );
        }
      }

      Widget frame(Widget home) => RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: pactaTheme(brightness),
          home: home,
        ),
      );

      // 01 编辑页：基础内容卡顶部的卡片图标预览。
      await tester.pumpWidget(
        frame(
          NationalFocusCardEditorPage(
            repository: run.repository,
            card: run.parent,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('national-focus-editor-icon')),
        findsOneWidget,
      );
      await capture('01-editor-with-icon');

      // 02 四套图标分页选择器。
      await tester.tap(
        find.byKey(const ValueKey('national-focus-editor-icon')),
      );
      await tester.pumpAndSettle();
      for (final title in const ['默认', 'Tabler', 'Material', 'Cupertino']) {
        expect(find.text(title), findsWidgets);
      }
      expect(
        find.byKey(const ValueKey('national-focus-icon-grid-lucide')),
        findsOneWidget,
      );
      await capture('02-icon-picker-tabs');
      Navigator.of(tester.element(find.text('选择图标'))).pop();
      await tester.pumpAndSettle();

      // 03 强化要求：选中行必须是实底 card + 左侧 3.5dp 主色条。
      final entry = find.text('强化要求');
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('正在使用'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('national-focus-strengthening-active-bar')),
        findsOneWidget,
      );
      expect(find.text('生效版本记录'), findsNothing);
      await capture('03-strengthening-solid-selected');

      // 切到第二档（草稿），返回编辑页后触发未保存确认。
      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('national-focus-strengthening-level-2'),
          ),
          matching: find.text('选择'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      // 编辑页是根路由：用系统返回手势触发同一个 PopScope 确认。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('尚未保存更改'), findsOneWidget);
      await capture('04-editor-unsaved-prompt');
      await tester.tap(
        find.byKey(const ValueKey('national-focus-editor-keep-editing')),
      );
      await tester.pumpAndSettle();

      // 05 树：两枚自定义图标（lucide / tabler）都必须真实渲染。
      await tester.pumpWidget(
        frame(
          Scaffold(body: NationalFocusTreePage(repository: run.repository)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('national-focus-node-${run.parent.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('national-focus-node-${run.child.id}')),
        findsOneWidget,
      );
      await capture('05-tree-custom-icons');

      // 06 失败记录：没有检查点说明折叠卡，批次卡高对比结构。
      await tester.pumpWidget(
        frame(
          NationalFocusFailureHistoryPage(
            repository: run.repository,
            displayTimeZoneId: 'Asia/Shanghai',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('检查点说明'), findsNothing);
      expect(find.text('失败记录'), findsOneWidget);
      expect(find.textContaining('未回顾'), findsWidgets);
      await capture('06-failure-history-clean');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await run.repository.dispose();
      await run.database.close();
    }

    expect(written, hasLength(themes.length * 6));
    debugPrint('[nf-v4] 完成 ${written.length} 张截图');
    for (final path in written) {
      debugPrint('[nf-v4] $path');
    }
  });
}

class _ScenarioData {
  const _ScenarioData({
    required this.database,
    required this.repository,
    required this.parent,
    required this.child,
  });

  final PactaDatabase database;
  final LocalNationalFocusRepository repository;
  final NationalFocusCard parent;
  final NationalFocusCard child;
}

Future<_ScenarioData> _seed(WidgetTester tester) async {
  final database = PactaDatabase(NativeDatabase.memory());
  var now = DateTime.utc(2026, 11, 24, 19, 59);
  final repository = LocalNationalFocusRepository(
    database: database,
    userId: _user,
    cloudSyncEnabled: false,
    now: () => now,
  );
  final parent = await repository.createCard(
    const NationalFocusCardDraft(
      name: '晨间阅读',
      action: '坐到书桌前，先读十页',
      iconKey: 'lucide:book-open',
      strengtheningLevels: [
        NationalFocusStrengtheningLevel(levelNumber: 1, action: '读二十页'),
        NationalFocusStrengtheningLevel(levelNumber: 2, action: '读三十页'),
      ],
      activeStrengtheningLevel: 1,
      updateStrengthening: true,
    ),
  );
  final child = await repository.createCard(
    const NationalFocusCardDraft(
      name: '晨跑',
      action: '出门慢跑十五分钟',
      iconKey: 'tabler:run',
    ),
  );
  await repository.placeCard(cardId: parent.id, parentId: null);
  await repository.placeCard(cardId: child.id, parentId: parent.id);
  await repository.lightCard(parent.id);
  await repository.lightCard(child.id);
  now = DateTime.utc(2026, 11, 25, 20);
  await repository.settleDueCheckpoints();
  now = DateTime.utc(2026, 11, 26, 20);
  await repository.settleDueCheckpoints();
  await tester.pump();
  return _ScenarioData(
    database: database,
    repository: repository,
    parent: await repository.getCard(parent.id),
    child: await repository.getCard(child.id),
  );
}

List<Brightness> _parseThemes() {
  final themes = <Brightness>[];
  for (final token in _themeDefine.split(',')) {
    final value = token.trim().toLowerCase();
    if (value.isEmpty) continue;
    final brightness = switch (value) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      'both' || 'system' => null,
      _ => throw ArgumentError('无法识别的主题「$value」，可用 light/dark/both。'),
    };
    if (value == 'both' || value == 'system') {
      themes
        ..add(Brightness.light)
        ..add(Brightness.dark);
      continue;
    }
    final resolved = brightness!;
    if (!themes.contains(resolved)) themes.add(resolved);
  }
  if (themes.isEmpty) {
    throw ArgumentError('NF_V4_THEME 至少要包含一个主题。');
  }
  return themes;
}

Directory _resolveOutputDirectory(int themeCount) {
  final raw = _captureDir.trim();
  if (Platform.isAndroid) {
    // Android 由 driver 的 takeScreenshot 落盘，目录由 driver 决定。
    return Directory(raw.isEmpty ? '.' : raw);
  }
  if (raw.isEmpty) {
    throw StateError(
      'Windows 截图必须提供绝对目录：'
      '--dart-define=NF_V4_CAPTURE_DIR=C:/abs/nf-v4-evidence',
    );
  }
  final directory = Directory(raw);
  if (!directory.isAbsolute) {
    throw StateError('输出目录必须是绝对路径，当前为：$raw');
  }
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    throw StateError('拒绝复用或覆盖已有截图目录：${directory.absolute.path}');
  }
  return directory;
}

Future<String> _capture(
  WidgetTester tester, {
  required String name,
  required Directory outputDirectory,
  required GlobalKey boundaryKey,
}) async {
  await tester.pumpAndSettle();
  final binding = IntegrationTestWidgetsFlutterBinding.instance;
  if (Platform.isAndroid) {
    await binding.takeScreenshot(name);
    return name;
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('截图编码失败：$name');
  }
  outputDirectory.createSync(recursive: true);
  final path = '${outputDirectory.path}${Platform.pathSeparator}$name.png';
  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
  return path;
}
