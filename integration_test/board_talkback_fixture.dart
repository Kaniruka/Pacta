import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

/// Manual device fixture. Uses no test binding and no persistent database.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final goal = await tasks.createGoal(
    const GoalDraft(
      title: '季度规划',
      description: '每周回顾并调整计划',
      classification: TaskClassification.both,
    ),
  );
  final task = await tasks.createTask(
    goal.id,
    const TaskDraft(
      title: '整理发布材料',
      description: '先核对发布清单',
      classification: TaskClassification.both,
      estimatedMinutes: 30,
    ),
  );
  await tasks.createGoal(
    const GoalDraft(title: '待规划目标', classification: TaskClassification.regular),
  );
  final session = await focus.startSession(
    taskId: task.id,
    mode: FocusChainMode.regular,
    duration: const Duration(minutes: 25),
  );
  now = DateTime.now();
  await focus.abandonSession(sessionId: session.id, failureReason: '设备界面验收样例');
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

  const textScalePercent = int.fromEnvironment('BOARD_TEXT_SCALE_PERCENT');
  final app = PactaApp(
    authRepository: FakeAuthRepository()..signedInUser = userId,
    taskRepositoryFactory: (_) => tasks,
    focusRepositoryFactory: (_) => focus,
    nationalFocusRepositoryFactory: (_) => nationalFocus,
    calendarRepositoryFactory: (_) => calendar,
  );
  runApp(
    textScalePercent > 0
        ? Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScalePercent / 100)),
              child: app,
            ),
          )
        : app,
  );
}
