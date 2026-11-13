// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../test/support/fake_auth_repository.dart';

const _user = 'national-focus-refinement-device';
const _captureDir = String.fromEnvironment(
  'NF_REFINEMENT_CAPTURE_DIR',
  defaultValue: 'build/ui-layout-evidence/national-focus-refinement',
);
const _theme = String.fromEnvironment(
  'NF_REFINEMENT_THEME',
  defaultValue: 'system',
);
const _width = String.fromEnvironment('NF_REFINEMENT_WIDTH');

Finder _nodeFinder(NationalFocusCard card) =>
    find.byKey(ValueKey('national-focus-node-${card.id}'));

Finder _nodeSheetText(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

void _expectNoException(WidgetTester tester, String action) {
  expect(tester.takeException(), isNull, reason: '操作「$action」不应抛异常');
}

Future<void> _tapAndSettle(
  WidgetTester tester,
  Finder finder,
  String action,
) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
  _expectNoException(tester, action);
}

Future<void> _tapNode(WidgetTester tester, NationalFocusCard card) async {
  final node = _nodeFinder(card);
  expect(node, findsOneWidget, reason: '国策节点「${card.name}」应在树中');
  await tester.ensureVisible(node);
  await _tapAndSettle(tester, node, '打开国策节点「${card.name}」');
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await _tapAndSettle(
    tester,
    find.descendant(of: host, matching: find.text(label)),
    '打开「$label」',
  );
}

Future<void> _unmountAndSettle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _captureDesktop(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) {
    fail('截图「$name」未找到 RepaintBoundary');
  }
  final image = await object.toImage(pixelRatio: tester.view.devicePixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) fail('截图「$name」PNG 编码失败');
    final directory = Directory(_captureDir);
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$name.png');
    if (await file.exists()) {
      fail('拒绝覆盖截图文件：${file.absolute.path}');
    }
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

void _setRequestedView(WidgetTester tester) {
  if (_theme == 'light') {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  } else if (_theme == 'dark') {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  } else if (_theme != 'system') {
    fail('NF_REFINEMENT_THEME 只支持 light、dark 或 system');
  }

  if (_width.trim().isEmpty) return;
  final width = int.tryParse(_width.trim());
  if (width == null || width < 320) {
    fail('NF_REFINEMENT_WIDTH 必须是至少 320 的逻辑像素宽度');
  }
  final devicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = Size(
    width * devicePixelRatio,
    tester.view.physicalSize.height,
  );
}

Future<NationalFocusCard> _createLitTreeCard(
  LocalNationalFocusRepository repository, {
  required String name,
  required String action,
  String? exceptionNotes,
  String? parentId,
}) async {
  final card = await repository.createCard(
    NationalFocusCardDraft(
      name: name,
      action: action,
      exceptionNotes: exceptionNotes,
    ),
  );
  await repository.placeCard(cardId: card.id, parentId: parentId);
  await repository.lightCard(card.id);
  return repository.getCard(card.id);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策例外确认与熄灭强化真实设备验收', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    // Seed one day before the live clock, then settle through it so the
    // repository and the page use the same current checkpoint window.
    final capturedNow = DateTime.now().toUtc();
    var now = capturedNow.subtract(const Duration(days: 1));

    void advanceFixtureClock() {
      now = now.add(const Duration(seconds: 1));
    }

    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    final boundaryKey = GlobalKey();
    final capturedNames = <String>{};
    var androidSurfaceReady = false;
    var changedViewWidth = false;

    Future<void> shot(String state) async {
      final name = 'national-focus-refinement-$state';
      if (!capturedNames.add(name)) fail('截图名重复：$name');
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else if (Platform.isWindows) {
        await _captureDesktop(tester, boundaryKey, name);
      } else {
        fail(
          '此 fixture 只支持 Android 与 Windows；当前平台为 ${Platform.operatingSystem}',
        );
      }
      print('[national-focus-refinement] shot=$name');
      _expectNoException(tester, '截图 $name');
    }

    try {
      _setRequestedView(tester);
      changedViewWidth = _width.trim().isNotEmpty;

      final ordinary = await _createLitTreeCard(
        tree,
        name: '日常复盘',
        action: '每天收尾时整理今天的进展和下一步。',
      );
      advanceFixtureClock();
      final directException = await _createLitTreeCard(
        tree,
        name: '单点例外确认',
        action: '睡前读完当天的计划，再写下明天的第一步。',
        exceptionNotes: '发热时休息，恢复后再继续。',
      );
      advanceFixtureClock();
      final batchExceptionToExtinguish = await _createLitTreeCard(
        tree,
        name: '批量例外一',
        action: '周末计划完成后，补齐一次本周回顾。',
        exceptionNotes: '有紧急家庭事务时可留到次日，并记录原因。',
      );
      advanceFixtureClock();
      final batchExceptionToKeep = await _createLitTreeCard(
        tree,
        name: '批量例外二',
        action: '工作日结束后整理桌面并归档材料。',
        exceptionNotes: '出差当天可暂停，返程后恢复。',
      );
      advanceFixtureClock();
      final parent = await _createLitTreeCard(
        tree,
        name: '晨间复盘',
        action: '早餐前回顾昨天并安排今天。',
      );
      advanceFixtureClock();
      final blockedChild = await _createLitTreeCard(
        tree,
        name: '写下今日第一步',
        action: '复盘后写下今天最重要的第一步。',
        parentId: parent.id,
      );
      await tree.extinguishCard(cardId: parent.id, failureReason: '调整晨间安排');

      now = capturedNow;
      await tree.settleDueCheckpoints();
      expect(
        (await tree.getCard(ordinary.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(
        (await tree.getCard(directException.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(
        (await tree.getCard(batchExceptionToExtinguish.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(
        (await tree.getCard(batchExceptionToKeep.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(
        (await tree.getCard(blockedChild.id)).state,
        NationalFocusCardState.extinguished,
      );

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = _user,
            nationalFocusRepositoryFactory: (_) => tree,
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectNoException(tester, '打开 Pacta');
      await _openTab(tester, '国策树');
      expect(
        find.byKey(const PageStorageKey<String>('national-focus-tree')),
        findsOneWidget,
      );
      expect(find.text('日常复盘'), findsOneWidget);
      expect(find.text('单点例外确认'), findsOneWidget);
      await shot('tree-after-current-checkpoint-settlement');

      await _tapNode(tester, blockedChild);
      final blockedSheet = find.byType(BottomSheet);
      expect(blockedSheet, findsOneWidget);
      expect(_nodeSheetText('写下今日第一步'), findsOneWidget);
      final blockedLightAction = find.ancestor(
        of: _nodeSheetText('点亮'),
        matching: find.byType(ListTile),
      );
      expect(blockedLightAction, findsOneWidget);
      final blockedLightTile = tester.widget<ListTile>(blockedLightAction);
      expect(blockedLightTile.enabled, isFalse);
      expect(blockedLightTile.subtitle, isA<Text>());
      expect(
        (blockedLightTile.subtitle! as Text).data,
        contains('父节点'),
        reason: '受阻的点亮操作应说明父节点仍阻塞该子节点',
      );
      await shot('parent-extinguished-blocks-child');
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      _expectNoException(tester, '关闭父节点阻塞面板');

      await _tapNode(tester, directException);
      await _tapAndSettle(tester, _nodeSheetText('查看详情'), '打开例外节点详情');
      expect(find.text('国策卡详情'), findsOneWidget);
      await _tapAndSettle(tester, find.byTooltip('卡片操作'), '打开例外卡片操作菜单');
      await _tapAndSettle(tester, find.text('编辑卡片'), '打开三字段编辑页');
      expect(find.text('卡片名称'), findsOneWidget);
      expect(find.text('国策规则'), findsOneWidget);
      expect(find.text('例外与判例（可选）'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3));
      await shot('three-field-card-editor');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      _expectNoException(tester, '从编辑页返回国策树');

      await _tapNode(tester, directException);
      expect(_nodeSheetText('确认'), findsOneWidget);
      expect(_nodeSheetText('发热时休息，恢复后再继续。'), findsOneWidget);
      await shot('single-node-exception-confirm-sheet');
      await _tapAndSettle(tester, _nodeSheetText('确认'), '单点确认带例外节点');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await tree.getCard(directException.id)).state,
        NationalFocusCardState.lit,
      );
      _expectNoException(tester, '单点确认后不重复弹窗');

      await _tapAndSettle(
        tester,
        find.textContaining('全部确认'),
        '批量确认普通节点并打开例外逐项确认',
      );
      final firstBatchDialog = find.byType(AlertDialog);
      expect(firstBatchDialog, findsOneWidget);
      expect(
        find.descendant(of: firstBatchDialog, matching: find.text('批量例外一')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: firstBatchDialog,
          matching: find.text('周末计划完成后，补齐一次本周回顾。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: firstBatchDialog,
          matching: find.text('有紧急家庭事务时可留到次日，并记录原因。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstBatchDialog, matching: find.text('熄灭')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstBatchDialog, matching: find.text('确认')),
        findsOneWidget,
      );
      expect(
        (await tree.getCard(ordinary.id)).state,
        NationalFocusCardState.lit,
        reason: '批量确认应先点亮没有例外的普通节点',
      );
      expect(
        (await tree.getCard(batchExceptionToExtinguish.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
        reason: '例外节点应等待逐项判断',
      );
      await shot('batch-exception-first-item');
      await _tapAndSettle(tester, find.text('关闭'), '关闭批量例外确认');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await tree.getCard(ordinary.id)).state,
        NationalFocusCardState.lit,
      );
      expect(
        (await tree.getCard(batchExceptionToExtinguish.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(
        (await tree.getCard(batchExceptionToKeep.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );

      await _tapAndSettle(tester, find.textContaining('全部确认'), '重新打开待处理的例外节点');
      final repeatedBatchDialog = find.byType(AlertDialog);
      expect(repeatedBatchDialog, findsOneWidget);
      expect(
        find.descendant(of: repeatedBatchDialog, matching: find.text('批量例外一')),
        findsOneWidget,
      );
      await _tapAndSettle(
        tester,
        find.descendant(of: repeatedBatchDialog, matching: find.text('熄灭')),
        '选择熄灭批量例外节点',
      );
      final extinguishDialog = find.byType(AlertDialog);
      expect(extinguishDialog, findsOneWidget);
      expect(find.text('熄灭这个节点？'), findsOneWidget);
      expect(
        find.descendant(
          of: extinguishDialog,
          matching: find.text('有紧急家庭事务时可留到次日，并记录原因。'),
        ),
        findsOneWidget,
      );
      await shot('exception-extinguish-reason');
      await _tapAndSettle(tester, find.text('暂不填写'), '不填写原因并熄灭例外节点');
      final secondBatchDialog = find.byType(AlertDialog);
      expect(secondBatchDialog, findsOneWidget);
      expect(
        find.descendant(of: secondBatchDialog, matching: find.text('批量例外二')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: secondBatchDialog,
          matching: find.text('工作日结束后整理桌面并归档材料。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: secondBatchDialog,
          matching: find.text('出差当天可暂停，返程后恢复。'),
        ),
        findsOneWidget,
      );
      await shot('batch-exception-second-item');
      expect(
        (await tree.getCard(batchExceptionToExtinguish.id)).state,
        NationalFocusCardState.extinguished,
      );
      expect(
        (await tree.getCard(batchExceptionToKeep.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      await _tapAndSettle(tester, find.text('关闭'), '关闭剩余例外确认');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await tree.getCard(ordinary.id)).state,
        NationalFocusCardState.lit,
        reason: '关闭未处理例外后普通节点仍保持已点亮',
      );
      expect(
        (await tree.getCard(batchExceptionToKeep.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
        reason: '关闭后未处理的例外节点仍待确认',
      );
      _expectNoException(tester, '结束国策例外确认流程');
    } finally {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      if (changedViewWidth) tester.view.resetPhysicalSize();
      await _unmountAndSettle(tester);
      await tree.dispose();
      await database.close();
    }
  });
}
