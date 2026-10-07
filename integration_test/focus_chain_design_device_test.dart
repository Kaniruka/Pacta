import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
    await signals.save(
      const ChainSignalTexts(
        appointmentTriggerSignal: '合上手机，倒一杯水',
        eliteFocusMarker: '戴上耳机，坐到书桌前',
        regularFocusMarker: '打开笔记本，写下第一步',
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
    for (final mode in FocusChainMode.values) {
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
      for (var index = 0; index < 3; index++) {
        await focus.startSession(
          taskId: task.id,
          mode: mode,
          duration: const Duration(minutes: 25),
        );
        now = now.add(const Duration(minutes: 25));
        await focus.settleDueSessions();
      }
    }
    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = userId,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => tree,
          chainSignalsRepositoryFactory: (_) => signals,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('专注链'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('focus-chain-overview');
      }
      if (const bool.fromEnvironment('FOCUS_DESIGN_SNAPSHOT_ONLY')) {
        return;
      }
      final editor = find.byKey(const ValueKey('focus-signal-edit-regular'));
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
      await tester.enterText(find.byType(TextField).first, '打开笔记本，开始第一步');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await signals.get()).regularFocusMarker, '打开笔记本，开始第一步');
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await tester.ensureVisible(editor);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.isAndroid) {
        await binding.takeScreenshot('focus-chain-large-dark');
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
      final start = find.byTooltip('开始任务：阅读一章，留下三个要点');
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
