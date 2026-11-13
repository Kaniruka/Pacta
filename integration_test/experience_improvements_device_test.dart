// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _user = 'experience-improvements-device';
const _captureDir = String.fromEnvironment(
  'EXPERIENCE_CAPTURE_DIR',
  defaultValue: 'build/ui-layout-evidence/experience-improvements',
);
const _theme = String.fromEnvironment(
  'EXPERIENCE_THEME',
  defaultValue: 'system',
);

Finder _taskTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;

Finder _estimateField() =>
    find.ancestor(of: find.text('预计时长（可选）'), matching: find.byType(TextField));

List<String?> _popupLabels(WidgetTester tester) =>
    find.byType(PopupMenuItem<String>).evaluate().map((element) {
      final child = (element.widget as PopupMenuItem<String>).child;
      return child is Text ? child.data : null;
    }).toList();

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

Future<void> _enterText(
  WidgetTester tester,
  Finder finder,
  String text,
  String action,
) async {
  await tester.enterText(finder, text);
  await tester.pump();
  _expectNoException(tester, action);
}

Future<void> _ensureVisible(
  WidgetTester tester,
  Finder finder,
  String action, {
  double scrollDelta = 200,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      scrollDelta,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 30,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  _expectNoException(tester, action);
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
    final file = File('${directory.path}/$name.png');
    if (await file.exists()) {
      fail('拒绝覆盖截图文件：${file.absolute.path}');
    }
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('体验修复真实设备验收与截图', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 11, 13, 10);
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
      now: () => now,
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      now: () => now,
      cloudSyncEnabled: false,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    final signals = ChainSignalsRepository(
      database: database,
      userId: _user,
      now: () => now,
    );
    final boundaryKey = GlobalKey();
    final capturedNames = <String>{};
    var androidSurfaceReady = false;

    Future<void> shot(WidgetTester tester, String state) async {
      final name = 'experience-improvements-$state';
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
      print('[experience-improvements] shot=$name');
      _expectNoException(tester, '截图 $name');
    }

    try {
      if (_theme == 'light') {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
      } else if (_theme == 'dark') {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      } else if (_theme != 'system') {
        fail('EXPERIENCE_THEME 只支持 light、dark 或 system');
      }

      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '推进重要工作',
          classification: TaskClassification.elite,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '完成第一步',
          classification: TaskClassification.elite,
        ),
      );
      await signals.save(const ChainSignalTexts(focusMarker: '坐到桌前，打开笔记'));
      final card = await tree.createCard(
        const NationalFocusCardDraft(
          name: '先写第一步',
          triggerCondition: '坐到书桌前',
          action: '写下第一步',
        ),
      );
      await tree.saveStrengtheningLevel(
        cardId: card.id,
        draft: const NationalFocusStrengtheningLevelDraft(
          triggerCondition: '起床后坐到书桌前',
          action: '写下第一步并读一遍',
        ),
      );
      await tree.selectStrengtheningLevel(cardId: card.id, levelNumber: 1);

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = _user,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
            chainSignalsRepositoryFactory: (_) => signals,
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectNoException(tester, '打开 Pacta');

      final goalCard = find.ancestor(
        of: find.text(goal.title),
        matching: find.byType(Card),
      );
      await _ensureVisible(tester, goalCard, '显示目标与任务');
      expect(find.text(task.title), findsOneWidget);
      expect(tester.widget<ListTile>(_taskTile(task.title)).subtitle, isNull);
      expect(
        find.descendant(of: goalCard, matching: find.byTooltip('编辑目标')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: goalCard, matching: find.byTooltip('删除目标')),
        findsOneWidget,
      );
      await shot(tester, 'board-empty-options-goal-actions');

      await _tapAndSettle(tester, find.text(task.title), '打开任务编辑');
      expect(find.text('编辑任务'), findsOneWidget);
      expect(find.text('预计时长（可选）'), findsOneWidget);
      await _tapAndSettle(
        tester,
        find.byType(DropdownButtonFormField<String>),
        '打开预计时长单位菜单',
      );
      await _tapAndSettle(tester, find.text('小时').last, '选择小时单位');
      await _enterText(tester, _estimateField(), '1.5', '输入 1.5 小时');
      await _tapAndSettle(tester, find.text('保存'), '保存任务时长');
      expect(find.text('90 分钟'), findsOneWidget);
      expect((await tasks.getGoals()).single.tasks.single.estimatedMinutes, 90);

      await _tapAndSettle(tester, find.text(task.title), '重新打开任务编辑');
      expect(tester.widget<TextField>(_estimateField()).controller!.text, '90');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await _ensureVisible(tester, _estimateField(), '显示已保存的预计时长');
      await shot(tester, 'task-editor-reopened-90-minutes');
      await _tapAndSettle(tester, find.text('取消'), '关闭任务编辑');

      await _tapAndSettle(tester, find.byTooltip('开始专注'), '打开精锐任务专注设置');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('精锐链'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<FocusChainMode>>(
              find.byType(DropdownButtonFormField<FocusChainMode>),
            )
            .initialValue,
        FocusChainMode.elite,
      );
      await shot(tester, 'focus-setup-default-elite');
      await _tapAndSettle(tester, find.text('取消'), '取消专注设置');
      expect(await focus.getActiveSession(), isNull);

      await _openTab(tester, '专注链');
      final markerEditor = find.byKey(
        const ValueKey('focus-signal-edit-marker'),
      );
      expect(markerEditor, findsOneWidget);
      await _ensureVisible(tester, markerEditor, '显示共享专注标记');
      await _tapAndSettle(tester, markerEditor, '打开共享专注标记编辑');
      expect(find.byType(AlertDialog), findsOneWidget);
      const savedMarker = '戴上耳机，坐到书桌前并开始';
      await _enterText(
        tester,
        find.byType(TextField).first,
        savedMarker,
        '编辑共享专注标记',
      );
      await _tapAndSettle(tester, find.text('保存'), '保存共享专注标记');
      expect((await signals.get()).focusMarker, savedMarker);
      expect(tester.takeException(), isNull);
      await shot(tester, 'focus-marker-saved');

      await _openTab(tester, '国策树');
      await _tapAndSettle(tester, find.text('卡片库'), '打开国策卡片库');
      await _tapAndSettle(tester, find.byTooltip('卡片操作'), '打开卡片操作菜单');
      await _tapAndSettle(tester, find.text('查看详情'), '打开国策卡详情');
      expect(find.text('国策卡详情'), findsOneWidget);
      expect(find.textContaining('当前要求 · 强化等级 1'), findsOneWidget);

      final manageStrengthening = find.text('管理强化要求');
      await _ensureVisible(tester, manageStrengthening, '显示强化管理入口');
      await _tapAndSettle(tester, manageStrengthening, '打开强化要求管理');
      expect(find.text('国策强化要求'), findsOneWidget);
      expect(find.text('当前采用 · 强化等级 1'), findsOneWidget);
      final resetRequirement = find.text('切换到基础要求');
      await _ensureVisible(tester, resetRequirement, '显示基础要求切换操作');
      await _tapAndSettle(tester, resetRequirement, '切换到基础要求');
      await _ensureVisible(
        tester,
        find.text('当前采用 · 基础要求'),
        '滚回当前要求摘要',
        scrollDelta: -200,
      );
      expect(find.text('当前采用 · 基础要求'), findsOneWidget);
      await shot(tester, 'national-strengthening-basic-selected');

      await tester.pageBack();
      await tester.pumpAndSettle();
      _expectNoException(tester, '返回国策卡详情');
      expect(find.text('国策卡详情'), findsOneWidget);
      expect(find.text('当前使用基础要求'), findsOneWidget);
      expect(find.textContaining('当前要求 · 强化等级 1'), findsNothing);
      await shot(tester, 'national-card-detail-refreshed');

      await _tapAndSettle(tester, find.byTooltip('卡片操作'), '打开国策卡详情菜单');
      expect(_popupLabels(tester), ['编辑卡片']);
      expect(find.text('修改名称'), findsNothing);
      await _tapAndSettle(tester, find.text('编辑卡片'), '打开国策卡编辑');
      expect(find.text('卡片名称'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      _expectNoException(tester, '返回国策卡详情');
      expect(find.text('国策卡详情'), findsOneWidget);
    } finally {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await _unmountAndSettle(tester);
      await tasks.dispose();
      await focus.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}
