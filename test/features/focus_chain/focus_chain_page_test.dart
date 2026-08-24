import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/app/chain_theme.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/data/drift_focus_session_repository.dart';
import 'package:pacta/features/focus_chain/data/focus_session_state.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_repository.dart';
import 'package:pacta/features/focus_chain/presentation/focus_chain_page.dart';
import 'package:pacta/features/goals_tasks/data/drift_goal_task_repository.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/data/supabase_goal_task_source.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:pacta/private_data/private_data_state.dart';

void main() {
  final userId = const AppUserId('focus-page-user');
  final now = DateTime.utc(2026, 8, 24, 9);

  testWidgets('picker selection preserves Task context on setup', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );
    final goal = await repository.saveGoal(
      userId,
      const GoalDraft(title: 'Release Goal'),
    );
    final elite = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Elite Task',
        classification: TaskChainClassification.elite,
        estimatedDuration: const Duration(minutes: 45),
      ),
    );
    final regular = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Regular Task',
        classification: TaskChainClassification.regular,
        estimatedDuration: const Duration(minutes: 20),
      ),
    );
    await repository.setFocusProgress(
      userId,
      regular.id,
      const Duration(minutes: 5),
    );

    await _pump(
      tester,
      repository,
      FocusChainPage(userId: userId, initialTaskId: elite.id),
    );

    expect(find.text('Goal: Release Goal'), findsOneWidget);
    expect(find.text('Estimate: 45m'), findsOneWidget);
    expect(find.text('Classification: Elite'), findsOneWidget);
    expect(find.text('Focus Progress: 0m'), findsOneWidget);
    expect(
      find.textContaining('Choose Elite or Regular explicitly.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('start-immediate-focus'), skipOffstage: false),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('focus-select-task')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a Task'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-filter-regular')));
    await tester.pump();
    expect(find.byKey(Key('picker-task-${regular.id}')), findsOneWidget);
    expect(find.byKey(Key('picker-task-${elite.id}')), findsNothing);
    await tester.tap(find.byKey(Key('picker-task-${regular.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Goal: Release Goal'), findsOneWidget);
    expect(find.text('Estimate: 20m'), findsOneWidget);
    expect(find.text('Classification: Regular'), findsOneWidget);
    expect(find.text('Focus Progress: 5m'), findsOneWidget);

    await _chooseMode(tester, FocusChainMode.regular);
    final durationIncrease = find.byKey(
      const Key('duration-increase'),
      skipOffstage: false,
    );
    await tester.ensureVisible(durationIncrease);
    await tester.tap(durationIncrease);
    await tester.pump();
    expect(find.text('30 min'), findsOneWidget);
  });

  testWidgets('Elite suggestion requires explicit acceptance of Regular', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );
    final goal = await repository.saveGoal(
      userId,
      const GoalDraft(title: 'Goal'),
    );
    final task = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Regular only',
        classification: TaskChainClassification.regular,
      ),
    );

    await _pump(
      tester,
      repository,
      FocusChainPage(userId: userId, initialTaskId: task.id),
    );
    await _chooseMode(tester, FocusChainMode.elite);

    expect(find.byKey(const Key('regular-chain-suggestion')), findsOneWidget);
    expect(find.byKey(const Key('accept-regular-suggestion')), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept-regular-suggestion')));
    await tester.pump();
    final modeButton = tester.widget<SegmentedButton<FocusChainMode>>(
      find.byKey(const Key('focus-chain-mode'), skipOffstage: false),
    );
    expect(modeButton.selected, contains(FocusChainMode.regular));
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(
              const Key('start-appointment-chain'),
              skipOffstage: false,
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('does not suggest Regular when no Regular Task is available', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );

    await _pump(tester, repository, FocusChainPage(userId: userId));
    await _chooseMode(tester, FocusChainMode.elite);

    expect(find.byKey(const Key('regular-chain-suggestion')), findsNothing);
  });

  testWidgets('start actions retain explicit mode and protocol instructions', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );
    final goal = await repository.saveGoal(
      userId,
      const GoalDraft(title: 'Goal'),
    );
    final task = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Both task',
        classification: TaskChainClassification.both,
      ),
    );

    await _pump(
      tester,
      repository,
      FocusChainPage(userId: userId, initialTaskId: task.id),
    );
    expect(
      find.text('Appointment Signal', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Immediate-start Signal', skipOffstage: false),
      findsOneWidget,
    );
    await _chooseMode(tester, FocusChainMode.elite);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('start-appointment-chain'), skipOffstage: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appointment Chain configured'), findsOneWidget);
    expect(find.text('Both task · Elite · 15 min'), findsOneWidget);
    expect(
      find.textContaining('does not detect or auto-start'),
      findsOneWidget,
    );
  });

  testWidgets('Immediate start opens the dedicated Focus Session surface', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );
    final goal = await repository.saveGoal(
      userId,
      const GoalDraft(title: 'Immediate Goal'),
    );
    final task = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Immediate Task',
        classification: TaskChainClassification.elite,
      ),
    );
    final sessions = DriftFocusSessionRepository(
      database: database,
      clock: () => now,
    );

    await _pump(
      tester,
      repository,
      FocusChainPage(userId: userId, initialTaskId: task.id, clock: () => now),
      focusSessions: sessions,
    );
    await _chooseMode(tester, FocusChainMode.elite);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('start-immediate-focus'), skipOffstage: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Focus Session'), findsOneWidget);
    expect(find.text('Immediate Task'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('Complete'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  DriftGoalTaskRepository repository,
  Widget child, {
  FocusSessionRepository? focusSessions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalTaskRepositoryProvider.overrideWithValue(repository),
        if (focusSessions != null)
          focusSessionRepositoryProvider.overrideWithValue(focusSessions),
        syncRetryTriggersProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: MaterialApp(theme: buildChainTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseMode(WidgetTester tester, FocusChainMode mode) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('focus-chain-mode'), skipOffstage: false),
      matching: find.text(mode.label),
    ),
  );
  await tester.pump();
}
