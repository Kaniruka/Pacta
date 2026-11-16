import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_month_page.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// Android device acceptance for the approved redesign: the five destinations,
/// the board month entry, the Plan calendar staying independent from focus
/// time, the account time zone entry and dark mode.
///
///   flutter drive --driver=test_driver/android_acceptance_test.dart
///     --target=integration_test/android_acceptance_test.dart -d SERIAL
///
/// In-memory database only, fixed clock, real theme and bundled fonts; every
/// capture is preceded by a visible-state assertion.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 验收：五入口、月历、日历、时区与暗色', (tester) async {
    final clock = DateTime.utc(2026, 11, 18, 9);
    final database = PactaDatabase(NativeDatabase.memory());
    final focusRemote = InMemoryFocusRemote();
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'android-acceptance',
      remote: InMemoryTaskRemote(),
      now: () => clock,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'android-acceptance',
      remote: focusRemote,
      now: () => clock,
    );
    final schedules = LocalScheduleRepository(
      database: database,
      userId: 'android-acceptance',
      now: () => clock,
    );
    final profiles = LocalProfileRepository(
      database: database,
      userId: 'android-acceptance',
      now: () => clock,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: 'android-acceptance',
    );

    Future<void> shot(String name) async {
      if (!Platform.isAndroid) return;
      // Screen captures read the rendered surface, which can trail the frame
      // that first showed the new route; give it one settled frame.
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('android-$name');
    }

    Future<void> settle() async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    try {
      await profiles.saveProfile(
        displayName: '安卓验收',
        timeZoneId: 'Asia/Shanghai',
      );
      final goal = await tasks.createGoal(
        const GoalDraft(title: '季度发布', classification: TaskClassification.both),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          classification: TaskClassification.both,
        ),
      );
      await tasks.setGoalPinned(goal.id, isPinned: true);
      await focusRemote.upsertSessions(
        userId: 'android-acceptance',
        sessions: [
          FocusSession(
            id: 'android-fx',
            taskId: task.id,
            mode: FocusChainMode.regular,
            durationSeconds: 13 * 60,
            startedAt: DateTime.utc(2026, 11, 18, 2),
            endsAt: DateTime.utc(2026, 11, 18, 2, 13),
            completedAt: DateTime.utc(2026, 11, 18, 2, 13),
            status: FocusSessionStatus.completed,
            effectiveSeconds: 13 * 60,
            effectiveIntervals: [
              FocusTimeInterval(
                startedAt: DateTime.utc(2026, 11, 18, 2),
                endedAt: DateTime.utc(2026, 11, 18, 2, 13),
              ),
            ],
            reviewDisposition: FocusRecordDisposition.accepted,
          ),
        ],
      );
      await focus.sync();
      final rootCard = await tree.createCard(
        const NationalFocusCardDraft(
          name: '开始一天之前',
          triggerCondition: '开始一天之前',
          action: '确定今天最重要的一步',
        ),
      );
      await tree.placeCard(cardId: rootCard.id, parentId: null);
      final schedule = await schedules.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 18, 8),
            endsAt: DateTime.utc(2026, 11, 18, 9),
          ),
        ),
      );

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()
            ..signedInUser = 'android-acceptance',
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          scheduleRepositoryFactory: (_) => schedules,
          profileRepositoryFactory: (_) => profiles,
          nationalFocusRepositoryFactory: (_) => tree,
          displayClock: () => clock,
          cloudCheckClock: () => clock,
          deviceTimeZoneIdReader: () async => null,
        ),
      );
      await settle();
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      await settle();

      // 1. Board: today's arrangement, pinned goal with next task, recent effort.
      expect(find.text('今天先做什么'), findsOneWidget);
      expect(find.text('取快递'), findsWidgets);
      expect(find.text('下一项：整理发布材料'), findsOneWidget);
      expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);
      expect(find.text('打开月历'), findsOneWidget);
      await shot('01-board');

      // 2. Month entry: the board pushes the standalone month page.
      await tester.tap(find.text('打开月历'));
      await settle();
      expect(find.byType(FocusMonthPage), findsOneWidget);
      expect(find.text('专注月历'), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('13分00秒'), findsOneWidget);
      final dayCell = find.byKey(const ValueKey('focus-month-day-12'));
      expect(dayCell, findsOneWidget);
      final daySize = tester.getSize(dayCell);
      expect(daySize.width, greaterThanOrEqualTo(48));
      expect(daySize.height, greaterThanOrEqualTo(48));
      await shot('02-month');
      await tester.pageBack();
      await settle();

      // 3. Plan goals: the pinned goal keeps its task disclosure.
      await tester.tap(find.text('计划'));
      await settle();
      expect(find.text('目标'), findsWidgets);
      expect(find.text('季度发布'), findsWidgets);
      await shot('03-plan-goals');

      // 4. Plan calendar: completing an arrangement writes no focus record.
      await tester.tap(find.text('日历'));
      await settle();
      final card = find.byKey(ValueKey('schedule-card-${schedule.id}'));
      expect(card, findsOneWidget);
      await shot('04-plan-calendar');
      // The selected day's list sits below the month grid on a phone.
      await tester.ensureVisible(card);
      await settle();
      await tester.tap(
        find.descendant(of: card, matching: find.byType(Checkbox)),
      );
      await settle();
      expect((await schedules.getSchedules()).single.isCompleted, isTrue);
      final sessions = await focus.getSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'android-fx');
      await shot('05-plan-completed');

      // 5. Focus chain: the start surface stays visible.
      await tester.tap(find.text('专注链'));
      await settle();
      expect(find.text('选择任务'), findsWidgets);
      await shot('06-focus-chain');

      // 6. National focus tree: the seeded root card renders.
      await tester.tap(find.text('国策树'));
      await settle();
      expect(find.text('开始一天之前'), findsWidgets);
      await shot('07-national-focus');

      // 7. My: profile, notification settings entry.
      await tester.tap(find.text('我的'));
      await settle();
      expect(find.text('安卓验收'), findsWidgets);
      expect(find.text('提醒与通知'), findsOneWidget);
      await shot('08-my');
      await tester.tap(find.text('提醒与通知'));
      await settle();
      expect(find.byType(FocusNotificationSettingsPage), findsOneWidget);
      await shot('09-notification-settings');
      await tester.pageBack();
      await settle();

      // 8. Account time zone through the real edit page.
      await tester.tap(find.text('编辑'));
      await settle();
      expect(find.text('编辑资料'), findsOneWidget);
      await tester.tap(find.text('纽约'));
      await settle();
      expect(find.textContaining('纽约 · America/New_York'), findsWidgets);
      await shot('10-profile-time-zone');
      await tester.pageBack();
      await settle();

      // 9. Dark mode on the board.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.tap(find.text('看板'));
      await settle();
      await shot('11-board-dark');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await schedules.dispose();
      await tree.dispose();
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    }
  });
}
