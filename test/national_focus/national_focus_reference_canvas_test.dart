import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/national_focus_reference_fixture.dart';

void main() {
  final fontPath = Platform.environment['PACTA_UI_FONT'];
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (fontPath != null) {
      await (FontLoader('UiEvidence')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  testWidgets('窄窗少量节点的确认、次级入口和放置状态保持可用', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 10, 5, 19, 59);
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: 'issue-80-small-tree',
      cloudSyncEnabled: false,
      now: () => now,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repository.dispose();
      await database.close();
    });
    final root = await repository.createCard(
      const NationalFocusCardDraft(
        name: '根国策',
        action: '安排今天',
        triggerCondition: '每天',
      ),
    );
    await repository.placeCard(cardId: root.id, parentId: null);
    await repository.lightCard(root.id);
    for (final name in ['每日阅读', '规律运动']) {
      final card = await repository.createCard(
        NationalFocusCardDraft(
          name: name,
          action: '完成今天的小行动',
          triggerCondition: '晚饭后',
        ),
      );
      await repository.placeCard(cardId: card.id, parentId: root.id);
    }
    await repository.createCard(
      const NationalFocusCardDraft(
        name: '记录收获',
        action: '写下一句话',
        triggerCondition: '读书后',
      ),
    );
    now = DateTime.utc(2026, 10, 5, 20, 1);
    await repository.settleDueCheckpoints();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff385a52),
          fontFamily: fontPath == null ? null : 'UiEvidence',
        ),
        home: RepaintBoundary(
          key: const ValueKey('small-tree-evidence'),
          child: Scaffold(
            body: NationalFocusTreePage(repository: repository, now: () => now),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final path = Platform.environment['PACTA_UI_EVIDENCE_DIR'];
      if (path == null) return;
      await tester.runAsync(() async {
        await Directory(path).create(recursive: true);
        final output = File('$path/$name.png');
        if (await output.exists()) {
          throw StateError('Refusing to overwrite ${output.path}');
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('small-tree-evidence')),
        );
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('PNG encoding failed: $name');
          await output.writeAsBytes(data.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await capture('small-320-pending');
    await tester.tap(find.text('全部确认 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('全部确认 (0)'), findsOneWidget);
    await tester.tap(find.byTooltip('卡片库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放入国策树'));
    await tester.pumpAndSettle();
    expect(find.text('为「记录收获」选择位置：点顶层或一个节点。'), findsOneWidget);
    await capture('small-320-placement');
    await tester.tap(find.text('简洁视图'));
    await tester.tap(find.byTooltip('卡片库'));
    await tester.pumpAndSettle();
    expect(find.text('详细视图'), findsNothing);
    expect(find.text('国策卡片库'), findsNothing);
    await tester.tap(find.byTooltip('取消选择位置'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(546, 400);
    await tester.pumpAndSettle();
    await capture('small-short');
    await tester.tap(find.byTooltip('适应屏幕'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('更多'));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查点与失败记录'));
    await tester.pumpAndSettle();
    expect(find.text('查看失败记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('整棵图片样例在宽窄视口可适配、缩放、平移并查看卡片内容', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: 'national-focus-reference-canvas-fixture',
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 9, 25, 10),
    );
    final seed = (await tester.runAsync(() async {
      final fixture = await NationalFocusReferenceFixture.load();
      return fixture.seed(repository);
    }))!;

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });

    final screenshotDirectory = Directory(
      Platform.environment['PACTA_UI_EVIDENCE_DIR'] ??
          'build/national_focus_reference_preview/${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => screenshotDirectory.create(recursive: true));

    Future<void> captureScreenshot(String filename) async {
      await tester.runAsync(() async {
        final output = File('${screenshotDirectory.path}/$filename');
        if (await output.exists()) {
          throw StateError('Refusing to overwrite ${output.path}');
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('reference-preview-screen')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) throw StateError('PNG encoding failed: $filename');
          await output.writeAsBytes(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    Future<void> verifyViewport(Size size, String screenshotName) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorSchemeSeed: const Color(0xff385a52),
            fontFamily: fontPath == null ? null : 'UiEvidence',
          ),
          home: RepaintBoundary(
            key: const ValueKey('reference-preview-screen'),
            child: Scaffold(
              body: NationalFocusTreePage(repository: repository),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();

      final canvas = find.byKey(const ValueKey('national-focus-canvas'));
      final viewer = find
          .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
          .first;
      expect(viewer, findsOneWidget);
      for (final sourceId in seed.cardIdsBySourceId.keys) {
        expect(
          find.byKey(ValueKey('national-focus-node-${seed.cardId(sourceId)}')),
          findsOneWidget,
          reason: 'fixture node $sourceId should remain in the full canvas',
        );
      }

      final fitButton = find.byTooltip('适应屏幕');
      await tester.ensureVisible(fitButton);
      await tester.tap(fitButton);
      await tester.pumpAndSettle();
      final canvasWidget = tester.widget<Transform>(canvas);
      final sceneSize = tester.getSize(find.byWidget(canvasWidget.child!));
      final fittedScene = MatrixUtils.transformRect(
        canvasWidget.transform,
        Offset.zero & sceneSize,
      );
      final viewportSize = tester.getSize(viewer);
      expect(fittedScene.left, greaterThanOrEqualTo(-1));
      expect(fittedScene.top, greaterThanOrEqualTo(-1));
      expect(fittedScene.right, lessThanOrEqualTo(viewportSize.width + 1));
      expect(fittedScene.bottom, lessThanOrEqualTo(viewportSize.height + 1));

      final panBefore = tester
          .widget<Transform>(canvas)
          .transform
          .getTranslation();
      final focal = tester.getCenter(viewer);
      final first = await tester.startGesture(
        focal - const Offset(25, 0),
        pointer: 81,
      );
      final second = await tester.startGesture(
        focal + const Offset(25, 0),
        pointer: 82,
      );
      await first.moveBy(const Offset(-80, -48));
      await second.moveBy(const Offset(-80, -48));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Transform>(canvas).transform.getTranslation(),
        isNot(panBefore),
      );
      await captureScreenshot(screenshotName);
      await tester.ensureVisible(find.text('简洁视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简洁视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('详细视图'));
      await tester.pumpAndSettle();
      expect(find.textContaining('切换不同的国策树分支'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('适应屏幕'));
      await tester.tap(find.byTooltip('适应屏幕'));
      await tester.pumpAndSettle();
      await captureScreenshot(
        screenshotName.replaceFirst('.png', '-detailed.png'),
      );
      final firstCard = seed.cardId(seed.cardIdsBySourceId.keys.first);
      final firstNode = find.byKey(ValueKey('national-focus-node-$firstCard'));
      await tester.ensureVisible(firstNode);
      await tester.tap(firstNode);
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await verifyViewport(const Size(1265, 682), 'wide.png');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await verifyViewport(const Size(546, 682), 'narrow.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await verifyViewport(const Size(320, 800), 'compact.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await verifyViewport(const Size(546, 400), 'short.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
