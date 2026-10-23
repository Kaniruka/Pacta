import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('专注主页不预览任务，二级页筛选并保留取消设置后的筛选', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'navigation',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      remote: InMemoryFocusRemote(),
      database: database,
      userId: 'navigation',
      cloudSyncEnabled: false,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: 'navigation',
      cloudSyncEnabled: false,
    );
    addTearDown(database.close);
    final goal = await tasks.createGoal(
      const GoalDraft(title: '导航验收目标', classification: TaskClassification.both),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '普通任务',
        classification: TaskClassification.regular,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '精锐任务',
        classification: TaskClassification.elite,
        estimatedMinutes: 40,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(title: '双模式任务', classification: TaskClassification.both),
    );
    final completed = await tasks.createTask(
      goal.id,
      const TaskDraft(title: '已完成任务', classification: TaskClassification.both),
    );
    await tasks.setTaskCompletion(completed.id, isComplete: true);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'navigation',
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
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
    expect(find.text('普通任务'), findsNothing);
    expect(find.text('精锐任务'), findsNothing);
    expect(find.text('可选任务 3 个'), findsOneWidget);
    await tester.tap(find.text('选择任务'));
    await tester.pumpAndSettle();
    expect(find.text('普通任务'), findsOneWidget);
    expect(find.text('精锐任务'), findsOneWidget);
    expect(find.text('双模式任务'), findsOneWidget);
    expect(find.text('已完成任务'), findsNothing);
    expect(find.textContaining('导航验收目标'), findsWidgets);
    expect(find.textContaining('未设置'), findsWidgets);
    expect(find.textContaining('40'), findsWidgets);
    await tester.tap(find.text('精锐').first);
    await tester.pumpAndSettle();
    expect(find.text('普通任务'), findsNothing);
    expect(find.text('双模式任务'), findsOneWidget);
    await tester.tap(find.text('精锐任务'));
    await tester.pumpAndSettle();
    expect(find.text('开始倒计时'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('普通任务'), findsNothing);
    expect(find.text('精锐任务'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('选择任务'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets('大量任务取消和返回设置保持筛选与屏幕位置，启动后返回主页', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final h = _Harness();
    addTearDown(h.database.close);
    final goal = await h.tasks.createGoal(
      const GoalDraft(title: '长列表目标', classification: TaskClassification.both),
    );
    for (var i = 0; i < 60; i++) {
      await h.tasks.createTask(
        goal.id,
        TaskDraft(title: '浏览任务 $i', classification: TaskClassification.both),
      );
    }
    await h.show(tester);
    expect(find.text('可选任务 60 个'), findsOneWidget);
    expect(find.text('浏览任务 0'), findsNothing);
    await tester.tap(find.text('选择任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('浏览任务 30'), 300);
    await tester.ensureVisible(find.text('浏览任务 30'));
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(find.text('浏览任务 30'));
    await tester.tap(find.text('浏览任务 30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('浏览任务 30')), position);
    await tester.tap(find.text('浏览任务 30'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('浏览任务 30')), position);
    await tester.tap(find.text('浏览任务 30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始倒计时'));
    await tester.pumpAndSettle();
    final session = (await h.focus.getActiveSession())!;
    expect(session.mode, FocusChainMode.regular);
    expect(session.durationSeconds, 25 * 60);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('选择任务'), findsOneWidget);
    expect(find.text('全部'), findsNothing);
    expect((await h.focus.getActiveSession())?.id, session.id);
    expect(await h.focus.getSessions(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('二级导航保留当前主页中已成功预约的模式选择', (tester) async {
    final h = _Harness();
    addTearDown(h.database.close);
    final goal = await h.tasks.createGoal(
      const GoalDraft(title: '模式目标', classification: TaskClassification.both),
    );
    await h.tasks.createTask(
      goal.id,
      const TaskDraft(title: '可选模式任务', classification: TaskClassification.both),
    );
    await h.show(tester);
    await tester.tap(find.text('选择任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精锐').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('可选模式任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始准备（15分钟）'));
    await tester.pumpAndSettle();
    final appointment = (await h.focus.getActiveAppointment())!;
    expect(appointment.mode, FocusChainMode.elite);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await h.focus.cancelAppointment(
      appointmentId: appointment.id,
      failureReason: '导航模式回归验证',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('可选模式任务'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('精锐链')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  for (final state in ['active', 'paused', 'appointment']) {
    testWidgets('原任务完成并删除后入口恢复 $state 原流程', (tester) async {
      final h = _Harness();
      addTearDown(h.database.close);
      final goal = await h.tasks.createGoal(
        const GoalDraft(title: '原目标', classification: TaskClassification.both),
      );
      final task = await h.tasks.createTask(
        goal.id,
        const TaskDraft(title: '原任务', classification: TaskClassification.both),
      );
      final String id;
      if (state == 'appointment') {
        id = (await h.focus.startAppointment(
          taskId: task.id,
          mode: FocusChainMode.elite,
          duration: const Duration(minutes: 40),
        )).id;
      } else {
        id = (await h.focus.startSession(
          taskId: task.id,
          mode: FocusChainMode.elite,
          duration: const Duration(minutes: 40),
        )).id;
        if (state == 'paused') {
          await h.focus.pauseSession(id, ruleText: '必要时允许短暂离开');
        }
      }
      await h.tasks.setTaskCompletion(task.id, isComplete: true);
      await h.tasks.deleteGoal(goal.id);
      await h.show(tester);
      expect(find.text('可选任务 0 个'), findsOneWidget);
      await tester.ensureVisible(find.text('选择任务'));
      await tester.tap(find.text('选择任务'));
      await tester.pumpAndSettle();
      expect(find.text('原任务（已删除）'), findsOneWidget);
      if (state == 'appointment') {
        expect(find.text('预约准备'), findsOneWidget);
        expect((await h.focus.getActiveAppointment())?.id, id);
        expect(await h.focus.getAppointments(), hasLength(1));
        expect(await h.focus.getSessions(), isEmpty);
      } else {
        expect((await h.focus.getActiveSession())?.id, id);
        expect((await h.focus.getActiveSession())?.isPaused, state == 'paused');
        expect(await h.focus.getSessions(), hasLength(1));
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('选择任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}

class _Harness {
  final database = PactaDatabase(NativeDatabase.memory());
  late final tasks = LocalTaskRepository(
    database: database,
    userId: 'flows',
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  );
  late final focus = LocalFocusRepository(
    database: database,
    userId: 'flows',
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => DateTime.utc(2026, 10, 23, 8),
  );
  late final tree = LocalNationalFocusRepository(
    database: database,
    userId: 'flows',
    cloudSyncEnabled: false,
  );
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'flows',
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
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
  }
}
