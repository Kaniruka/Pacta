// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// 截图输出目录（相对 build/ui-layout-evidence）。
const _evidenceDir = String.fromEnvironment(
  'FOCUS_CHAIN_EVIDENCE_DIR',
  defaultValue: 'ticket-09/focus-chain-first-screen',
);

/// narrow：360×800 模拟常见手机；wide：桌面窗口与侧边导轨。
const _view = String.fromEnvironment(
  'FOCUS_CHAIN_VIEW',
  defaultValue: 'narrow',
);

const _rule = '允许短暂起身接水';
const _longRule = '允许短暂起身接水并察看窗外远处两分钟后再迅速回到座位继续专注';

const _longMarker = '戴上耳机，坐到书桌前，关闭消息提醒，把手机翻面并打开当前任务的第一页';

/// 同一份内存数据在两个平台上生成相同的首屏与对话框状态。
class _Data {
  _Data({
    required this.database,
    required this.auth,
    required this.tasks,
    required this.focus,
    required this.signals,
    required this.taskId,
    required this.clock,
  });

  final PactaDatabase database;
  final FakeAuthRepository auth;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final ChainSignalsRepository signals;
  final String taskId;
  final DateTime Function() clock;

  static Future<_Data> create() async {
    const userId = 'focus-chain-first-screen-device';
    final database = PactaDatabase(NativeDatabase.memory());
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    var now = DateTime(2026, 11, 15, 9);
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final signals = ChainSignalsRepository(database: database, userId: userId);
    await signals.save(
      const ChainSignalTexts(
        focusMarker: _longMarker,
        appointmentTriggerSignal: '合上手机，倒一杯水，把桌面清空',
      ),
    );
    await focus.createPrecedentRule(text: _rule);
    await focus.createPrecedentRule(text: _longRule);
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '把重要的事情向前推进',
        classification: TaskClassification.both,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '阅读一章，留下三个要点',
        classification: TaskClassification.both,
        estimatedMinutes: 30,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '梳理明天的计划',
        classification: TaskClassification.regular,
        estimatedMinutes: 15,
      ),
    );
    for (final mode in [FocusChainMode.elite, FocusChainMode.regular]) {
      for (var round = 0; round < 3; round++) {
        await focus.startSession(
          taskId: task.id,
          mode: mode,
          duration: const Duration(minutes: 25),
        );
        now = now.add(const Duration(minutes: 25));
        await focus.settleDueSessions();
      }
    }
    return _Data(
      database: database,
      auth: FakeAuthRepository()..signedInUser = userId,
      tasks: tasks,
      focus: focus,
      signals: signals,
      taskId: task.id,
      clock: () => now,
    );
  }

  Future<void> dispose() async {
    await database.close();
  }
}

Future<void> _captureDesktop(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) {
    fail('screenshot "$name": repaint boundary not found');
  }
  final image = await object.toImage(pixelRatio: tester.view.devicePixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) fail('screenshot "$name": PNG encoding returned null');
  final directory = Directory('build/ui-layout-evidence/$_evidenceDir');
  await directory.create(recursive: true);
  final file = File('${directory.path}/$name.png');
  if (await file.exists()) {
    fail('screenshot "$name": refusing to overwrite ${file.absolute.path}');
  }
  await file.writeAsBytes(data.buffer.asUint8List());
}

void _expectFirstScreenGeometry(
  WidgetTester tester,
  String state,
  List<String> recoveryLabels,
) {
  final list = tester.getRect(find.byKey(const ValueKey('focus-chain-list')));
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('focus-chain-list')),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.maxScrollExtent, 0, reason: '$state 首屏不应需要纵向滚动');
  for (final key in const [
    'focus-chain-table',
    'focus-chain-signals',
    'focus-allowance-entry',
    'focus-chain-note',
  ]) {
    final rect = tester.getRect(find.byKey(ValueKey(key)));
    expect(
      rect.top,
      greaterThanOrEqualTo(list.top - 0.5),
      reason: '$state $key 顶部在可视列表内',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(list.bottom + 0.5),
      reason: '$state $key 底部在可视列表内',
    );
    expect(
      rect.left,
      greaterThanOrEqualTo(list.left - 0.5),
      reason: '$state $key 左侧未被裁切',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(list.right + 0.5),
      reason: '$state $key 右侧未被裁切',
    );
  }
  for (final label in recoveryLabels) {
    final rect = tester.getRect(find.text(label));
    expect(
      rect.bottom,
      lessThanOrEqualTo(list.bottom + 0.5),
      reason: '$state $label 完整可见',
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('专注链首屏：同一份内存数据的亮暗窄宽截图', (tester) async {
    final data = await _Data.create();
    if (_view == 'narrow') {
      final dpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(360 * dpr, 800 * dpr);
    } else {
      final dpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(1280 * dpr, 900 * dpr);
    }
    final boundaryKey = GlobalKey();
    var androidSurfaceReady = false;

    Future<void> shot(String state) async {
      final name = 'focus-first-$_view-$state';
      // The manager route makes the Focus Chain list offstage; read the
      // active route's media instead of requiring that page to be visible.
      final media = MediaQuery.of(tester.element(find.byType(Scaffold).first));
      print(
        '[focus-first] state=$state view=$_view platform=${Platform.operatingSystem} '
        'logical=${(tester.view.physicalSize / tester.view.devicePixelRatio)} '
        'dpr=${tester.view.devicePixelRatio} '
        'textScaler=${media.textScaler.scale(1)} padding=${media.padding}',
      );
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else {
        await _captureDesktop(tester, boundaryKey, name);
      }
    }

    Future<void> openFocusChain() async {
      final host = find.byType(NavigationBar).evaluate().isNotEmpty
          ? find.byType(NavigationBar)
          : find.byType(NavigationRail);
      await tester.tap(find.descendant(of: host, matching: find.text('专注链')));
      await tester.pumpAndSettle();
    }

    try {
      // The host may already be dark; pin the light baseline explicitly.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: data.auth,
            taskRepositoryFactory: (_) => data.tasks,
            focusRepositoryFactory: (_) => data.focus,
            chainSignalsRepositoryFactory: (_) => data.signals,
            displayClock: data.clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openFocusChain();

      // 亮色首屏：链表、承诺动作、许可入口、开始动作。
      await shot('light-overview');
      final listState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('focus-chain-list')),
          matching: find.byType(Scrollable),
        ),
      );
      print(
        '[focus-first] maxScrollExtent=${listState.position.maxScrollExtent} '
        'viewport=${listState.position.viewportDimension}',
      );
      for (final key in const [
        'focus-chain-table',
        'focus-chain-signals',
        'focus-allowance-entry',
        'focus-chain-note',
        'focus-task-picker-entry',
        'focus-history-entry',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        print('[focus-first] block=$key rect=$rect');
      }

      // 暗色首屏。
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await shot('dark-overview');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();

      // 承诺动作编辑：字段标签与保存动作。
      await tester.tap(find.byKey(const ValueKey('focus-signal-edit-marker')));
      await tester.pumpAndSettle();
      await shot('light-signal-dialog');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 下必为例管理页：完整既有列表与新建动作。
      await tester.tap(find.byKey(const ValueKey('focus-allowance-manage')));
      await tester.pumpAndSettle();
      await shot('light-allowance-manager');
      await tester.tap(find.text('新建规则'));
      await tester.pumpAndSettle();
      await shot('light-allowance-create-field');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 恢复条：预约准备中的三个动作与进行中会话的返回动作。
      await data.focus.startAppointment(
        taskId: data.taskId,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
        preparation: const Duration(minutes: 10),
      );
      await tester.pumpAndSettle();
      expect(find.text('已有预约准备'), findsOneWidget);
      expect(find.text('返回准备'), findsOneWidget);
      expect(find.text('提前进入专注'), findsOneWidget);
      expect(find.text('取消预约'), findsOneWidget);
      _expectFirstScreenGeometry(tester, 'appointment-recovery', const [
        '已有预约准备',
        '返回准备',
        '提前进入专注',
        '取消预约',
      ]);
      await shot('light-appointment-recovery');
      final appointment = await data.focus.getActiveAppointment();
      await data.focus.cancelAppointment(
        appointmentId: appointment!.id,
        failureReason: '独立界面截图结束后取消',
      );
      await tester.pumpAndSettle();
      expect(find.text('已有预约准备'), findsNothing);

      await data.focus.startSession(
        taskId: data.taskId,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 25),
      );
      await tester.pumpAndSettle();
      expect(find.text('已有进行中的专注'), findsOneWidget);
      expect(find.text('返回专注'), findsOneWidget);
      _expectFirstScreenGeometry(tester, 'session-recovery', const [
        '已有进行中的专注',
        '返回专注',
      ]);
      await shot('light-session-recovery');

      // Keep this session active: the recovery strip's 返回专注 entry is the
      // subject of the picker flow below. Final cleanup abandons it once the
      // picker and back navigation have been exercised.
      // 规则选择对话框：未选择时确认禁用，选择后可确认。
      await tester.tap(find.text('返回专注'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FocusSessionPage), findsOneWidget);
      // 进行中操作区已重构：暂停变成上排左侧的 tonal 填充按钮。
      await tester.tap(
        find.byKey(const ValueKey('focus-session-pause-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('选择下必为例'), findsOneWidget);
      await shot('light-rule-picker-disabled');
      await tester.tap(find.text(_rule));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await shot('light-rule-picker-enabled');
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final paused = await data.focus.getActiveSession();
      if (paused != null && paused.isUnfinished) {
        await data.focus.abandonSession(
          sessionId: paused.id,
          failureReason: '独立界面截图结束',
        );
      }
      await tester.pumpAndSettle();
    } finally {
      tester.view.reset();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await data.dispose();
    }
  });
}
