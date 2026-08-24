import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/app/chain_theme.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/data/drift_goal_task_repository.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/data/supabase_goal_task_source.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/features/goals_tasks/presentation/board_page.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:pacta/private_data/private_data_state.dart';

void main() {
  final userId = const AppUserId('board-user');
  final now = DateTime.utc(2026, 8, 24, 9);

  testWidgets('shows executable Tasks before summaries and exposes metadata', (
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
      const GoalDraft(title: 'Release goal'),
    );
    final task = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Prepare notes',
        classification: TaskChainClassification.elite,
        estimatedDuration: const Duration(minutes: 45),
        deadline: DateTime.utc(2026, 8, 30),
      ),
    );
    await repository.setFocusProgress(
      userId,
      task.id,
      const Duration(minutes: 15),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalTaskRepositoryProvider.overrideWithValue(repository),
          syncRetryTriggersProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: buildChainTheme(),
          home: BoardPage(userId: userId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Prepare notes'), findsOneWidget);
    expect(find.text('Goal: Release goal'), findsOneWidget);
    expect(find.text('Elite'), findsOneWidget);
    expect(find.text('Estimate: 45m'), findsOneWidget);
    expect(find.text('Deadline: 2026-08-30'), findsOneWidget);
    expect(find.text('Status: Active'), findsOneWidget);
    expect(find.text('Focus Progress: 15m'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Recent Focus Activity'),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    final tasksY = tester
        .getTopLeft(find.text('Executable Tasks', skipOffstage: false))
        .dy;
    final summaryY = tester.getTopLeft(find.text('Recent Focus Activity')).dy;
    expect(tasksY, lessThan(summaryY));
  });

  testWidgets('Board completion is an explicit action', (tester) async {
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
        title: 'Task',
        classification: TaskChainClassification.both,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalTaskRepositoryProvider.overrideWithValue(repository),
          syncRetryTriggersProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: buildChainTheme(),
          home: BoardPage(userId: userId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status: Active'), findsOneWidget);
    await tester.tap(find.byKey(Key('complete-task-${task.id}')));
    await tester.pumpAndSettle();

    final saved = await repository.read(userId);
    expect(saved.tasks.single.isComplete, isTrue);
    expect(saved.isGoalComplete(goal.id), isTrue);
  });

  testWidgets('Board Task opens Focus Chain setup with preserved context', (
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
      const GoalDraft(title: 'Context Goal'),
    );
    final task = await repository.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Context Task',
        classification: TaskChainClassification.both,
        estimatedDuration: const Duration(minutes: 35),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalTaskRepositoryProvider.overrideWithValue(repository),
          syncRetryTriggersProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: buildChainTheme(),
          home: BoardPage(userId: userId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('configure-focus-${task.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Focus Chain Setup'), findsOneWidget);
    expect(find.text('Goal: Context Goal'), findsOneWidget);
    expect(find.text('Estimate: 35m'), findsOneWidget);
    expect(find.text('Classification: Both'), findsOneWidget);
  });
}
