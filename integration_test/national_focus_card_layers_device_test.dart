// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// Re-runnable screenshot fixture for the lightweight card layering (#91).
///
/// Runs the real [PactaApp] with its real theme, fake authentication and real
/// local repositories, then walks the card layers in the National Focus
/// destination: node sheet, detail, card editor and strengthening management.
///
/// Windows (RepaintBoundary into NF_CARD_LAYERS_CAPTURE_DIR):
///   flutter test integration_test/national_focus_card_layers_device_test.dart -d windows
///
/// Android (surface screenshot exported by the shared UI evidence driver):
///   flutter drive --driver=test_driver/ui_layout_acceptance_test.dart
///     --target=integration_test/national_focus_card_layers_device_test.dart -d DEVICE_ID
///   with UI_EVIDENCE_SUBDIR=national-focus-card-layers and, for a strict rerun,
///   UI_EVIDENCE_FAIL_ON_EXIST=1.
///
/// Optional dart-defines for both platforms: NF_CARD_LAYERS_THEME
/// (light|dark|system) and NF_CARD_LAYERS_WIDTH (logical pixels, >= 320).
const _user = 'national-focus-card-layers-device';
const _desktopCaptureDir = String.fromEnvironment(
  'NF_CARD_LAYERS_CAPTURE_DIR',
  defaultValue: 'build/ui-layout-evidence/national-focus-card-layers',
);
const _theme = String.fromEnvironment(
  'NF_CARD_LAYERS_THEME',
  defaultValue: 'system',
);
const _width = String.fromEnvironment('NF_CARD_LAYERS_WIDTH');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策卡轻量分层真实设备截图', (tester) async {
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
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
    );
    final boundaryKey = GlobalKey();
    final capturedNames = <String>{};
    var androidSurfaceReady = false;

    Future<void> shot(String state) async {
      final name = 'national-focus-card-layers-$state';
      if (!capturedNames.add(name)) fail('截图名重复：$name');
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else if (Platform.isWindows) {
        final object = boundaryKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          fail('截图「$name」未找到 RepaintBoundary');
        }
        final image = await object.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) fail('截图「$name」PNG 编码失败');
          final directory = Directory(_desktopCaptureDir);
          await directory.create(recursive: true);
          final file = File(
            '${directory.path}${Platform.pathSeparator}$name.png',
          );
          if (await file.exists()) {
            fail('拒绝覆盖截图文件：${file.absolute.path}');
          }
          await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
      } else {
        fail(
          '此 fixture 只支持 Android 与 Windows；当前平台为 ${Platform.operatingSystem}',
        );
      }
      print(
        '[national-focus-card-layers] platform=${Platform.operatingSystem} '
        'shot=$name',
      );
      expect(tester.takeException(), isNull, reason: '截图 $name 不应抛异常');
    }

    Future<void> pumpUi() async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<NationalFocusCard> createTreeCard({
      required String name,
      required String action,
      String? exceptionNotes,
      List<String> levels = const [],
    }) async {
      final created = await tree.createCard(
        NationalFocusCardDraft(
          name: name,
          action: action,
          exceptionNotes: exceptionNotes,
        ),
      );
      now = now.add(const Duration(seconds: 1));
      await tree.placeCard(cardId: created.id, parentId: null);
      await tree.lightCard(created.id);
      for (final level in levels) {
        await tree.saveStrengtheningLevel(
          cardId: created.id,
          draft: NationalFocusStrengtheningLevelDraft(action: level),
        );
        now = now.add(const Duration(seconds: 1));
      }
      return tree.getCard(created.id);
    }

    Future<void> openNode(NationalFocusCard card) async {
      final node = find.byKey(ValueKey('national-focus-node-${card.id}'));
      expect(node, findsOneWidget, reason: '国策节点「${card.name}」应在树中');
      await tester.ensureVisible(node);
      await tester.tap(node);
      await tester.pumpAndSettle();
    }

    Future<void> tapText(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '操作「$label」不应抛异常');
    }

    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '返回上一页不应抛异常');
    }

    try {
      if (_theme == 'light' || _theme == 'dark') {
        tester.platformDispatcher.platformBrightnessTestValue =
            _theme == 'light' ? Brightness.light : Brightness.dark;
      } else if (_theme != 'system') {
        fail('NF_CARD_LAYERS_THEME 只支持 light、dark 或 system');
      }
      if (_width.trim().isNotEmpty) {
        if (Platform.isAndroid) {
          fail('Android 窄屏验收请调整模拟器实际显示密度，不覆盖测试视图尺寸。');
        }
        final width = int.tryParse(_width.trim());
        if (width == null || width < 320) {
          fail('NF_CARD_LAYERS_WIDTH 必须是至少 320 的逻辑像素宽度');
        }
        tester.view.physicalSize = Size(
          width * tester.view.devicePixelRatio,
          tester.view.physicalSize.height,
        );
      }

      final morning = await createTreeCard(
        name: '晨光校准',
        action: '闹钟第一次响起时，打开床边灯，或拉开伸手可及的床帘；选最省力的一种即可。',
        exceptionNotes: '当天决定取消起床安排、继续休息，记“不适用”；正常触发却没有开灯或拉帘，记未完成。',
      );
      final strengthened = await createTreeCard(
        name: '写今日第一步',
        action: '坐到书桌前，写下今天最重要的第一步。',
        levels: const [
          '坐到书桌前，写下今天最重要的第一步，并读一遍今天的计划。',
          '坐到书桌前，写下今天最重要的第一步，读一遍计划并标注预计用时。',
        ],
      );
      await tree.selectStrengtheningLevel(
        cardId: strengthened.id,
        levelNumber: 1,
      );
      final atCap = await createTreeCard(
        name: '睡前复盘',
        action: '睡前用三分钟记下今天完成的事。',
        levels: const ['一级复盘', '二级复盘', '三级复盘', '四级复盘', '五级复盘'],
      );

      final app = PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      );
      await tester.pumpWidget(
        Platform.isWindows
            ? RepaintBoundary(key: boundaryKey, child: app)
            : app,
      );
      await pumpUi();
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is NavigationBar || widget is NavigationRail,
          ),
          matching: find.text('国策树'),
        ),
      );
      await pumpUi();
      await shot('01-tree');

      await openNode(morning);
      await shot('02-node-sheet');
      await tapText('查看详情');
      await shot('03-detail-collapsed');
      await tapText('例外与判例');
      await shot('04-detail-exceptions');
      await tapText('编辑卡片');
      await shot('05-card-editor');
      await back();
      await back();
      expect(
        find.byKey(ValueKey('national-focus-node-${morning.id}')),
        findsOneWidget,
        reason: '从编辑页返回后应回到国策树',
      );

      await openNode(strengthened);
      await tapText('查看详情');
      await shot('06-detail-strengthened');
      await tapText('编辑卡片');
      await tapText('管理强化要求');
      await shot('07-strengthening-manager');
      final secondLevel = find.byKey(
        const ValueKey('national-focus-strengthening-level-2'),
      );
      // Editing an inactive level must not change the requirement in force.
      final editSecondLevel = find.descendant(
        of: secondLevel,
        matching: find.byTooltip('编辑强化等级 2'),
      );
      await tester.ensureVisible(editSecondLevel);
      await tester.pumpAndSettle();
      await tester.tap(editSecondLevel);
      await tester.pumpAndSettle();
      await tapText('对照基础规则');
      await shot('08-strengthening-level-editor');
      await back();
      await tester.scrollUntilVisible(
        find.text('当前使用 · 强化等级 1'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('当前使用 · 强化等级 1'), findsOneWidget);
      await back();
      expect(find.text('编辑国策卡'), findsOneWidget);
      await back();
      expect(find.text('国策卡详情'), findsOneWidget);
      await back();
      expect(
        find.byKey(ValueKey('national-focus-node-${strengthened.id}')),
        findsOneWidget,
        reason: '强化管理往返后应回到国策树',
      );

      await openNode(atCap);
      await tapText('查看详情');
      await tapText('编辑卡片');
      await tapText('管理强化要求');
      await shot('09-strengthening-cap');
      expect(find.text('已达 5 级上限'), findsOneWidget);
      await back();
      await back();
      await back();
      expect(
        find.byKey(ValueKey('national-focus-node-${atCap.id}')),
        findsOneWidget,
        reason: '五级上限页返回后应回到国策树',
      );
      expect(tester.takeException(), isNull);
    } finally {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await focus.dispose();
      await tasks.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}
