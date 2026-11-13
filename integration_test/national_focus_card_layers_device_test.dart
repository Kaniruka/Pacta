// ignore_for_file: avoid_print

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

/// Re-runnable screenshot fixture for the lightweight card layering (#91):
/// node sheet, detail, card editor and strengthening management.
///
/// Windows: flutter test integration_test/national_focus_card_layers_device_test.dart -d windows
/// Android: flutter test integration_test/national_focus_card_layers_device_test.dart -d DEVICE_ID
///
/// Optional dart-defines: NF_CARD_LAYERS_CAPTURE_DIR, NF_CARD_LAYERS_THEME
/// (light|dark|system), NF_CARD_LAYERS_WIDTH (logical pixels, >= 320).
const _user = 'national-focus-card-layers-device';
const _captureDir = String.fromEnvironment(
  'NF_CARD_LAYERS_CAPTURE_DIR',
  defaultValue: 'build/ui-layout-evidence/national-focus-card-layers',
);
const _theme = String.fromEnvironment(
  'NF_CARD_LAYERS_THEME',
  defaultValue: 'system',
);
const _width = String.fromEnvironment('NF_CARD_LAYERS_WIDTH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策卡轻量分层真实设备截图', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 11, 13, 9);
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    final boundaryKey = GlobalKey();
    final capturedNames = <String>{};

    Future<void> shot(String state) async {
      final name = 'national-focus-card-layers-$state';
      if (!capturedNames.add(name)) fail('截图名重复：$name');
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
        final directory = Directory(_captureDir);
        await directory.create(recursive: true);
        final file = File(
          '${directory.path}${Platform.pathSeparator}$name.png',
        );
        if (await file.exists()) fail('拒绝覆盖截图文件：${file.absolute.path}');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
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
      final created = await repository.createCard(
        NationalFocusCardDraft(
          name: name,
          action: action,
          exceptionNotes: exceptionNotes,
        ),
      );
      now = now.add(const Duration(seconds: 1));
      await repository.placeCard(cardId: created.id, parentId: null);
      await repository.lightCard(created.id);
      for (final level in levels) {
        await repository.saveStrengtheningLevel(
          cardId: created.id,
          draft: NationalFocusStrengtheningLevelDraft(action: level),
        );
        now = now.add(const Duration(seconds: 1));
      }
      return repository.getCard(created.id);
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
    }

    try {
      if (_theme == 'light' || _theme == 'dark') {
        tester.platformDispatcher.platformBrightnessTestValue =
            _theme == 'light' ? Brightness.light : Brightness.dark;
      } else if (_theme != 'system') {
        fail('NF_CARD_LAYERS_THEME 只支持 light、dark 或 system');
      }
      if (_width.trim().isNotEmpty) {
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
      await repository.selectStrengtheningLevel(
        cardId: strengthened.id,
        levelNumber: 1,
      );
      final atCap = await createTreeCard(
        name: '睡前复盘',
        action: '睡前用三分钟记下今天完成的事。',
        levels: const ['一级复盘', '二级复盘', '三级复盘', '四级复盘', '五级复盘'],
      );

      final brightness = _theme == 'dark'
          ? Brightness.dark
          : _theme == 'light'
          ? Brightness.light
          : tester.platformDispatcher.platformBrightness;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: NationalFocusTreePage(repository: repository)),
          ),
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

      await openNode(strengthened);
      await tapText('查看详情');
      await shot('06-detail-strengthened');
      await tapText('编辑卡片');
      await tapText('管理强化要求');
      await shot('07-strengthening-manager');
      final secondLevel = find.byKey(
        const ValueKey('national-focus-strengthening-level-2'),
      );
      await tester.tap(
        find.descendant(of: secondLevel, matching: find.text('选择')),
      );
      await tester.pumpAndSettle();
      await shot('08-strengthening-manager-level-2');
      await tester.tap(find.byTooltip('编辑强化等级 2'));
      await tester.pumpAndSettle();
      await tapText('对照基础规则');
      await shot('09-strengthening-level-editor');
      await back();
      await back();
      await back();

      await openNode(atCap);
      await tapText('查看详情');
      await tapText('编辑卡片');
      await tapText('管理强化要求');
      await shot('10-strengthening-cap');
      expect(find.text('已达 5 级上限'), findsOneWidget);
    } finally {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await repository.dispose();
      await database.close();
    }
  });
}
