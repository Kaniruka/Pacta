// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// 离线基线截图：只读本机 fixture，不写云、不读凭据。
const _dir = String.fromEnvironment(
  'UI_BASELINE_DIR',
  defaultValue: 'ui-baseline/current',
);

/// `matrix`：桌面端按 360/411/1280 × 亮暗 × 1.0/2.0 逐格截图；
/// `device`：移动端只按设备自身窗口截亮暗与两种字号。
const _mode = String.fromEnvironment(
  'UI_BASELINE_MODE',
  defaultValue: 'device',
);

const _pages = String.fromEnvironment(
  'UI_BASELINE_PAGES',
  defaultValue: 'focus,plan-goals,plan-calendar,my',
);

const _sizes = <Size>[
  Size(320, 568),
  Size(360, 800),
  Size(411, 731),
  Size(1280, 800),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('四目的地亮暗与字号基线截图', (tester) async {
    const userId = 'ui-baseline-offline-fixture';
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime(2026, 11, 18, 9);
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
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
    final schedules = LocalScheduleRepository(
      database: database,
      userId: userId,
      now: () => now,
    );
    await signals.save(
      const ChainSignalTexts(
        focusMarker: '戴上耳机，坐到书桌前',
        appointmentTriggerSignal: '合上手机，倒一杯水',
      ),
    );
    await focus.createPrecedentRule(text: '允许短暂起身接水');
    await focus.createPrecedentRule(text: '允许查询与本次任务相关的资料');
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
    await schedules.createSchedule(
      ScheduleDraft(
        title: '与设计评审对齐专注链层级',
        window: ScheduleWindow.timed(
          startsAt: DateTime(2026, 11, 18, 10),
          endsAt: DateTime(2026, 11, 18, 11),
        ),
        taskId: task.id,
      ),
    );

    final boundaryKey = GlobalKey();
    var androidSurfaceReady = false;
    Future<void> shot(String name) async {
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else {
        final object = boundaryKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          fail('screenshot "$name": repaint boundary not found');
        }
        final image = await object.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) fail('screenshot "$name": PNG encoding failed');
        final directory = Directory('build/ui-layout-evidence/$_dir');
        await directory.create(recursive: true);
        final file = File('${directory.path}/$name.png');
        if (await file.exists()) {
          fail('screenshot "$name": refusing to overwrite');
        }
        await file.writeAsBytes(data.buffer.asUint8List());
      }
      print('[ui-baseline] shot=$name dir=$_dir');
    }

    // 桌面窗口被遮挡时 pumpAndSettle 可能等不到新帧；固定推进两帧更稳。
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> openDestination(String label) async {
      final bar = find.byType(NavigationBar);
      final rail = find.byType(NavigationRail);
      final host = bar.evaluate().isNotEmpty ? bar : rail;
      await tester.tap(find.descendant(of: host, matching: find.text(label)));
      await settle();
    }

    Future<void> captureAll(String suffix) async {
      final wanted = _pages.split(',').map((page) => page.trim()).toSet();
      const known = {
        'focus',
        'plan-goals',
        'plan-calendar',
        'my',
        'national',
        'board',
      };
      final unknown = wanted.difference(known);
      if (unknown.isNotEmpty) {
        fail('UI_BASELINE_PAGES 含未知页面：${unknown.join(', ')}');
      }
      if (wanted.contains('focus')) {
        await openDestination('专注链');
        await shot('focus-$suffix');
      }
      if (wanted.contains('plan-goals') || wanted.contains('plan-calendar')) {
        await openDestination('计划');
        if (wanted.contains('plan-goals')) {
          await shot('plan-goals-$suffix');
        }
        if (wanted.contains('plan-calendar')) {
          await tester.tap(find.text('日历'));
          await settle();
          await shot('plan-calendar-$suffix');
          // 选中态移开后，今日只剩描边：两种状态必须仍可分辨。
          final now = DateTime.now();
          final otherDay = now.day == 1 ? 2 : 1;
          await tester.tap(
            find.byKey(
              ValueKey(
                'plan-day-${now.year.toString().padLeft(4, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${otherDay.toString().padLeft(2, '0')}',
              ),
            ),
          );
          await settle();
          await shot('plan-calendar-today-outline-$suffix');
          // 上一个月：10 月是法定节假日最密集的一个月，放假日底色要能判读。
          await tester.tap(find.byIcon(Icons.chevron_left));
          await settle();
          await shot('plan-calendar-prev-month-$suffix');
          await tester.tap(find.byIcon(Icons.chevron_right));
          await settle();
          await tester.tap(find.text('目标'));
          await settle();
        }
      }
      if (wanted.contains('my')) {
        await openDestination('我的');
        await shot('my-$suffix');
      }
      if (wanted.contains('national')) {
        await openDestination('国策树');
        await shot('national-$suffix');
      }
      if (wanted.contains('board')) {
        await openDestination('看板');
        await shot('board-$suffix');
      }
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
            scheduleRepositoryFactory: (_) => schedules,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sizes = _mode == 'matrix'
          ? _sizes
          : [tester.view.physicalSize / tester.view.devicePixelRatio];
      for (final size in sizes) {
        if (_mode == 'matrix') {
          final dpr = tester.view.devicePixelRatio;
          tester.view.physicalSize = size * dpr;
          await settle();
        }
        for (final brightness in Brightness.values) {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          for (final scale in const [1.0, 2.0]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await settle();
            final suffix =
                '${size.width.toInt()}x${size.height.toInt()}-'
                '${brightness == Brightness.dark ? 'dark' : 'light'}-'
                's${scale.toStringAsFixed(1)}';
            _printMetrics(tester, suffix);
            await captureAll(suffix);
          }
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      if (Platform.isWindows) {
        // Windows 上的鼠标反馈：把指针悬停在主操作上再截一张。
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        final dpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(1280, 800) * dpr;
        await settle();
        await openDestination('专注链');
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        final target = find.byKey(const ValueKey('focus-task-picker-entry'));
        await gesture.moveTo(tester.getCenter(target));
        await settle();
        await shot('focus-1280x800-light-s1.0-hover');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      }
    } finally {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await tree.dispose();
      await schedules.dispose();
      await database.close();
    }
  });
}

void _printMetrics(WidgetTester tester, String label) {
  final view = tester.view;
  final logical = view.physicalSize / view.devicePixelRatio;
  final media = MediaQuery.of(tester.element(find.byType(PactaApp)));
  print(
    '[ui-baseline] $label platform=${Platform.operatingSystem} '
    'logical=${logical.width.toStringAsFixed(1)}x'
    '${logical.height.toStringAsFixed(1)} dpr=${view.devicePixelRatio} '
    'textScaler=${media.textScaler.scale(1.0)}',
  );
}
