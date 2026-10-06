import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/national_focus_reference_fixture.dart';

void main() {
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
      'build/national_focus_reference_preview',
    );
    await tester.runAsync(() => screenshotDirectory.create(recursive: true));

    Future<void> captureScreenshot(String filename) async {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('reference-preview-screen')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${screenshotDirectory.path}/$filename')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    Future<void> verifyViewport(Size size, String screenshotName) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('reference-preview-screen'),
              child: NationalFocusTreePage(repository: repository),
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

      final fitButton = find.byTooltip('查看整棵树');
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

      final scaleFinder = find.textContaining('%');
      final scaleBeforeZoom = tester.widget<Text>(scaleFinder).data;
      await tester.tap(find.byTooltip('放大国策树'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(scaleFinder).data, isNot(scaleBeforeZoom));

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
      await tester.ensureVisible(find.text('详细'));
      await tester.tap(find.text('详细'));
      await tester.pumpAndSettle();
      expect(find.textContaining('切换不同的国策树分支'), findsOneWidget);
      final firstCard = seed.cardId(seed.cardIdsBySourceId.keys.first);
      final firstNode = find.byKey(ValueKey('national-focus-node-$firstCard'));
      await tester.ensureVisible(firstNode);
      await tester.tap(firstNode);
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await verifyViewport(const Size(1280, 900), 'wide.png');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await verifyViewport(const Size(390, 844), 'narrow.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
