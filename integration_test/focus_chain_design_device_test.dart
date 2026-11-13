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
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// 离线基线截图目录（相对 build/ui-layout-evidence）。
const _pilotDir = String.fromEnvironment(
  'FOCUS_PILOT_DIR',
  defaultValue: 'focus-pilot/current',
);

const _snapshotOnly = bool.fromEnvironment('FOCUS_DESIGN_SNAPSHOT_ONLY');
const _pilotMode = bool.fromEnvironment('FOCUS_PILOT_MODE');
const _scenario = String.fromEnvironment(
  'FOCUS_PILOT_SCENARIO',
  defaultValue: 'default',
);
const _viewName = String.fromEnvironment(
  'FOCUS_PILOT_VIEW',
  defaultValue: 'wide',
);

const _lightMode = bool.fromEnvironment('FOCUS_PILOT_LIGHT');

/// >0 时在首屏保持，供 Computer Use 做真实鼠标/窗口操作。
const _holdSeconds = int.fromEnvironment(
  'FOCUS_PILOT_HOLD_SECONDS',
  defaultValue: 0,
);

const _longAction = '打开笔记本，写下今天最重要的第一步，然后把手机放到看不见的地方，再核对明天的三个要点';

/// 桌面端截图：Android 走 driver 的 takeScreenshot，桌面用 RepaintBoundary。
///
/// [strict] 为 pilot 模式：缺 boundary、编码失败或同名文件已存在都直接失败，
/// 避免一次运行里的截图被静默跳过或覆盖。历史流程保持原来的静默返回。
Future<void> _captureDesktop(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name, {
  bool strict = false,
}) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) {
    if (strict) fail('screenshot "$name": repaint boundary not found');
    return;
  }
  final image = await object.toImage(pixelRatio: tester.view.devicePixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    if (strict) fail('screenshot "$name": PNG encoding returned null');
    return;
  }
  final directory = Directory('build/ui-layout-evidence/$_pilotDir');
  await directory.create(recursive: true);
  final file = File('${directory.path}/$name.png');
  if (strict && await file.exists()) {
    fail('screenshot "$name": refusing to overwrite ${file.absolute.path}');
  }
  await file.writeAsBytes(data.buffer.asUint8List());
}

/// 打印逻辑窗口、DPR、textScaler 与系统内边距。
void _printPilotMetrics(WidgetTester tester, String label) {
  final view = tester.view;
  final logical = view.physicalSize / view.devicePixelRatio;
  final media = MediaQuery.of(tester.element(find.byType(PactaApp)));
  print(
    '[focus-pilot] $label platform=${Platform.operatingSystem} '
    'scenario=$_scenario view=$_viewName '
    'logical=${logical.width.toStringAsFixed(1)}x'
    '${logical.height.toStringAsFixed(1)} '
    'dpr=${view.devicePixelRatio} '
    'textScaler=${media.textScaler.scale(1.0)} '
    'padding=${media.padding} '
    'viewPadding=${media.viewPadding} '
    'viewInsets=${media.viewInsets}',
  );
}

/// 宽屏（Windows）用 NavigationRail，窄屏用 NavigationBar。
Future<void> _openFocusChain(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final rail = find.byType(NavigationRail);
  final host = bar.evaluate().isNotEmpty ? bar : rail;
  await tester.tap(find.descendant(of: host, matching: find.text('专注链')));
  await tester.pumpAndSettle();
}

/// Offline UI evidence: no credentials, persistent database, or cloud writes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('专注链 Android 模拟器布局与承诺动作编辑', (tester) async {
    const userId = 'focus-design-offline-fixture';
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime(2026, 10, 7, 9);
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
    );
    final signals = ChainSignalsRepository(database: database, userId: userId);
    final longScenario = _scenario == 'long';
    await signals.save(
      ChainSignalTexts(
        appointmentTriggerSignal: longScenario
            ? '合上手机，倒一杯水，把桌面清空后坐下'
            : '合上手机，倒一杯水',
        focusMarker: longScenario ? _longAction : '戴上耳机，坐到书桌前',
      ),
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '把重要的事情向前推进',
        classification: TaskClassification.both,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      TaskDraft(
        title: longScenario ? '阅读一章专业书并留下三个要点，然后再复述一遍给明天的自己' : '阅读一章，留下三个要点',
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
    if (_scenario != 'zero') {
      final rounds = _scenario == 'few' ? 1 : 3;
      for (final mode in FocusChainMode.values) {
        if (_scenario == 'default' || longScenario) {
          final failed = await focus.startSession(
            taskId: task.id,
            mode: mode,
            duration: const Duration(minutes: 25),
          );
          now = now.add(const Duration(minutes: 10));
          await focus.abandonSession(
            sessionId: failed.id,
            failureReason: '独立界面样例：临时事务',
          );
        }
        for (var index = 0; index < rounds; index++) {
          await focus.startSession(
            taskId: task.id,
            mode: mode,
            duration: const Duration(minutes: 25),
          );
          now = now.add(const Duration(minutes: 25));
          await focus.settleDueSessions();
        }
      }
    }
    if (_viewName == 'narrow') {
      final dpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(420 * dpr, 820 * dpr);
    }
    if (_lightMode) {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    }
    final boundaryKey = GlobalKey();
    var androidSurfaceReady = false;
    Future<void> shot(String state) async {
      _printPilotMetrics(tester, state);
      final name = 'focus-$_scenario-$_viewName-$state';
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else {
        await _captureDesktop(tester, boundaryKey, name, strict: true);
      }
      print('[focus-pilot] shot=$name dir=$_pilotDir');
    }

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = userId,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
            chainSignalsRepositoryFactory: (_) => signals,
          ),
        ),
      );
      await tester.pumpAndSettle();
      _printPilotMetrics(tester, 'shell');
      await _openFocusChain(tester);
      expect(tester.takeException(), isNull);
      if (_pilotMode) {
        // Android's screenshot ImageView only acquires a new frame when the
        // driver captures it. Keep the native surface live for manual input.
        if (Platform.isAndroid && _holdSeconds > 0) {
          _printPilotMetrics(tester, 'manual-overview');
        } else {
          await shot('overview');
        }
        if (_holdSeconds > 0) {
          print('[focus-pilot] hold=${_holdSeconds}s');
          final previous = binding.shouldPropagateDevicePointerEvents;
          binding.shouldPropagateDevicePointerEvents = true;
          try {
            final deadline = DateTime.now().add(
              Duration(seconds: _holdSeconds),
            );
            while (DateTime.now().isBefore(deadline)) {
              await tester.pump(const Duration(milliseconds: 100));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
            }
          } finally {
            binding.shouldPropagateDevicePointerEvents = previous;
          }
          await tester.pumpAndSettle();
          await shot('overview-after-hold');
        }
        if (_snapshotOnly) {
          return;
        }
        final markerEdit = find.byKey(
          const ValueKey('focus-signal-edit-marker'),
        );
        await tester.scrollUntilVisible(
          markerEdit,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await shot('records-scroll');
        await tester.tap(markerEdit);
        await tester.pumpAndSettle();
        await shot('edit-dialog');
        await tester.enterText(find.byType(TextField).first, '取消不应保存');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        final afterCancel = await signals.get();
        expect(afterCancel.focusMarker, isNot('取消不应保存'));
        await shot('edit-cancel');
        await tester.tap(markerEdit);
        await tester.pumpAndSettle();
        final saved = longScenario ? _longAction : '戴上耳机，坐到书桌前并开始';
        await tester.enterText(find.byType(TextField).first, saved);
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect((await signals.get()).focusMarker, saved);
        await shot('edit-save');
        await tester.scrollUntilVisible(
          find.text('选择任务'),
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('选择任务'));
        await tester.pumpAndSettle();
        final start = find.byTooltip('开始任务：${task.title}');
        await tester.scrollUntilVisible(
          start,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(find.text('开始倒计时'), findsOneWidget);
        await tester.tap(find.text('开始倒计时'));
        await tester.pumpAndSettle();
        final active = await focus.getActiveSession();
        expect(active, isNotNull);
        expect(tester.takeException(), isNull);
        await shot('active');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('已有进行中的专注'), findsOneWidget);
        await shot('after-back');
        await tester.tap(find.text('返回专注'));
        await tester.pumpAndSettle();
        expect(find.text('暂停'), findsWidgets);
        await shot('restore');
        final activeId = active!.id;
        final restored = await focus.getActiveSession();
        expect(restored?.id, activeId);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await focus.abandonSession(
          sessionId: activeId,
          failureReason: '结束独立界面验收',
        );
        await tester.pumpAndSettle();
        return;
      }
      _printPilotMetrics(tester, 'focus-chain-normal');
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        androidSurfaceReady = true;
        await binding.takeScreenshot('focus-chain-overview');
      } else {
        await _captureDesktop(tester, boundaryKey, 'focus-chain-normal');
      }
      if (_snapshotOnly) {
        return;
      }
      final editor = find.byKey(const ValueKey('focus-signal-edit-marker'));
      await tester.ensureVisible(editor);
      await tester.pumpAndSettle();
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-records');
      }
      await tester.tap(editor);
      await tester.pumpAndSettle();
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-edit');
      }
      await tester.enterText(find.byType(TextField).first, '戴上耳机，坐到书桌前并开始');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await signals.get()).focusMarker, '戴上耳机，坐到书桌前并开始');
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await tester.ensureVisible(editor);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _printPilotMetrics(tester, 'focus-chain-large-dark');
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-large-dark');
      } else {
        await _captureDesktop(tester, boundaryKey, 'focus-chain-large-dark');
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpAndSettle();
      final appointmentEdit = find.byKey(
        const ValueKey('focus-signal-edit-appointment'),
      );
      await tester.ensureVisible(appointmentEdit);
      await tester.pumpAndSettle();
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-appointment-record');
      }
      await tester.scrollUntilVisible(
        find.text('选择任务'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('选择任务'));
      await tester.pumpAndSettle();
      final start = find.byTooltip('开始任务：${task.title}');
      await tester.scrollUntilVisible(
        start,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.text('开始倒计时'), findsOneWidget);
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-setup');
      }
      await tester.tap(find.text('开始倒计时'));
      await tester.pumpAndSettle();
      final active = await focus.getActiveSession();
      expect(active, isNotNull);
      expect(tester.takeException(), isNull);
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-active');
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await focus.abandonSession(
        sessionId: active!.id,
        failureReason: '结束独立界面验收',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择任务'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        start,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始准备（15分钟）'));
      await tester.pumpAndSettle();
      expect(await focus.getActiveAppointment(), isNotNull);
      expect(tester.takeException(), isNull);
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-appointment');
      }
    } finally {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}
