import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';
import '../test/support/fake_calendar_provider.dart';

/// Offline dashboard evidence using an in-memory database and fake auth.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('看板层级、我的设置入口与窄屏大字深色布局', (tester) async {
    const userId = 'board-design-offline-fixture';
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.now().subtract(const Duration(minutes: 13));
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
    );
    final source = CalendarSource(
      id: 'board-design-calendar',
      displayName: '工作日历',
      timeZoneId: 'Asia/Shanghai',
      localCalendarId: '7',
    );
    final calendarProvider = FakeCalendarProvider(
      sources: [source],
      permission: CalendarPermissionState.granted,
      events: [
        CalendarEventOccurrence(
          sourceId: source.id,
          sourceEventId: 'board-design-event',
          occurrenceId: 'board-design-event-today',
          eventIdentity: 'board-design-event-today',
          title: '设计评审',
          startsAt: DateTime(now.year, now.month, now.day, 14),
          endsAt: DateTime(now.year, now.month, now.day, 15),
          allDay: false,
          availability: CalendarAvailability.busy,
          timeZoneId: source.timeZoneId,
        ),
      ],
    );
    final calendar = LocalCalendarRepository(
      database: database,
      userId: userId,
      provider: calendarProvider,
      remote: InMemoryCalendarRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    try {
      final goal = await tasks.createGoal(
        const GoalDraft(title: '季度规划', classification: TaskClassification.both),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          classification: TaskClassification.both,
          estimatedMinutes: 30,
        ),
      );
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      now = DateTime.now();
      await focus.abandonSession(
        sessionId: session.id,
        failureReason: '设备界面验收样例',
      );
      final card = await nationalFocus.createCard(
        const NationalFocusCardDraft(
          name: '开始工作前',
          triggerCondition: '开始工作前',
          action: '写下第一步',
        ),
      );
      await nationalFocus.placeCard(cardId: card.id, parentId: null);
      await nationalFocus.lightCard(card.id);
      await calendar.importCalendars({source.id});

      final initialPixelRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(
        320 * initialPixelRatio,
        800 * initialPixelRatio,
      );
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = userId,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => nationalFocus,
          calendarRepositoryFactory: (_) => calendar,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今天先做什么'), findsOneWidget);
      expect(find.text('整理发布材料'), findsOneWidget);
      expect(
        tester.getCenter(find.text('打开国策树')).dy,
        closeTo(tester.getCenter(find.text('国策状态')).dy, 1),
      );
      expect(find.textContaining('检查点'), findsNothing);
      expect(find.textContaining('固定规则为北京时间'), findsNothing);
      expect(find.text('日历块'), findsNothing);
      expect(find.text('显示时区'), findsNothing);
      final devicePixelRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(
        360 * devicePixelRatio,
        800 * devicePixelRatio,
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('近期专注活动'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('近期专注活动'), findsOneWidget);
      expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);
      expect(find.textContaining('检查点'), findsNothing);
      expect(find.textContaining('固定规则为北京时间'), findsNothing);
      expect(find.text('日历块'), findsNothing);
      expect(find.text('显示时区'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('设计评审'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('设计评审'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.view.resetPhysicalSize();
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('我的'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('显示时区'), findsOneWidget);
      await tester.tap(find.text('显示时区'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'America/Los_Angeles',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('America/Los_Angeles').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('America/Los_Angeles'), findsOneWidget);

      await tester.tap(find.text('日历块'));
      await tester.pumpAndSettle();
      expect(find.text('工作日历'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.view.resetPhysicalSize();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await nationalFocus.dispose();
      await calendar.dispose();
      await database.close();
    }
  });
}
