import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T12 看板入口核对时钟跳变，允许暂缓且专注不被判失败', (tester) async {
    const userId = 'ticket-12-user';
    final database = PactaDatabase(NativeDatabase.memory());
    final taskRemote = InMemoryTaskRemote();
    final focusRemote = InMemoryFocusRemote();
    var wallTime = DateTime.utc(2026, 9, 25, 9);
    var monotonicTime = Duration.zero;
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: taskRemote,
      now: () => wallTime,
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: focusRemote,
      now: () => wallTime,
      monotonicNow: () => monotonicTime,
    );
    final auth = FakeAuthRepository()..signedInUser = userId;

    try {
      final goal = await taskRepository.createGoal(
        const GoalDraft(
          title: 'T12 平板验收',
          classification: TaskClassification.both,
        ),
      );
      final task = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '整理设备时钟证据',
          classification: TaskClassification.both,
        ),
      );
      final started = await focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 10),
      );

      wallTime = wallTime.add(const Duration(minutes: 2));
      monotonicTime += const Duration(minutes: 2);
      await focusRepository.getSession(started.id);
      wallTime = wallTime.add(const Duration(hours: 2));
      monotonicTime += const Duration(seconds: 1);
      final afterJump = (await focusRepository.getSession(started.id))!;
      expect(afterJump.status, FocusSessionStatus.active);
      expect(afterJump.failureReason, isNull);
      expect(await focusRepository.getClockReviewCases(), hasLength(1));
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => taskRepository,
          focusRepositoryFactory: (_) => focusRepository,
        ),
      );
      await _pumpUi(tester);

      final dashboardPrompt = find.text('1 段专注时间待核对');
      expect(dashboardPrompt, findsOneWidget);
      await tester.tap(dashboardPrompt);
      await _pumpUi(tester);
      expect(find.text('设备时间核对'), findsOneWidget);
      expect(find.text('设备时钟前跳'), findsOneWidget);
      expect(find.text('跳变前已确认 2分'), findsOneWidget);
      expect(find.text('稍后处理'), findsOneWidget);

      await tester.tap(find.text('稍后处理'));
      await _pumpUi(tester);
      expect(find.text('已暂缓'), findsOneWidget);
      expect(
        (await focusRepository.getClockReviewCases()).single.isDeferred,
        isTrue,
      );

      await tester.tap(find.text('采用连续计时并核对顺序'));
      await _pumpUi(tester);

      expect(find.text('当前没有待核对的设备时间记录'), findsOneWidget);
      expect(await focusRepository.getClockReviewCases(), isEmpty);
      final reviewed = (await focusRepository.getSession(started.id))!;
      expect(reviewed.status, FocusSessionStatus.active);
      expect(reviewed.failureReason, isNull);
      expect(
        reviewed.effectiveSeconds,
        const Duration(minutes: 2, seconds: 1).inSeconds,
      );
      expect(
        reviewed.effectiveIntervals.any(
          (interval) =>
              interval.clockReviewStatus == FocusClockReviewStatus.resolved &&
              interval.observedStartedAt != null &&
              interval.observedEndedAt != null,
        ),
        isTrue,
      );

      await tester.pageBack();
      await _pumpUi(tester);
      wallTime = wallTime.add(const Duration(minutes: 1));
      monotonicTime += const Duration(minutes: 1);
      await focusRepository.getSession(started.id);
      wallTime = wallTime.subtract(const Duration(hours: 2));
      monotonicTime += const Duration(seconds: 1);
      final afterBackwardJump = (await focusRepository.getSession(started.id))!;
      final backwardCase = (await focusRepository.getClockReviewCases()).single;
      expect(afterBackwardJump.status, FocusSessionStatus.active);
      expect(afterBackwardJump.failureReason, isNull);
      expect(backwardCase.direction, FocusClockChangeDirection.backward);
      expect(backwardCase.reliableSeconds, 181);

      await _pumpUi(tester);
      await tester.tap(dashboardPrompt);
      await _pumpUi(tester);
      expect(find.text('设备时钟后跳'), findsOneWidget);
      expect(find.text('跳变前已确认 3分1秒'), findsOneWidget);
      await tester.tap(find.text('排除这段不确定时间'));
      await _pumpUi(tester);
      expect(find.text('当前没有待核对的设备时间记录'), findsOneWidget);
      expect(await focusRepository.getClockReviewCases(), isEmpty);
      final backwardReviewed = (await focusRepository.getSession(started.id))!;
      expect(backwardReviewed.status, FocusSessionStatus.active);
      expect(backwardReviewed.failureReason, isNull);
      expect(backwardReviewed.effectiveSeconds, 181);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await focusRepository.dispose();
      await taskRepository.dispose();
      await database.close();
    }
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  // The active-session watchdog keeps scheduling state updates. Finish route
  // animations with finite pumps instead of waiting for the app to go idle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
