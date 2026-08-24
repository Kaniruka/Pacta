import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/app/chain_theme.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/data/drift_focus_session_repository.dart';
import 'package:pacta/features/focus_chain/data/focus_session_state.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:pacta/features/focus_chain/presentation/focus_session_page.dart';
import 'package:pacta/features/goals_tasks/data/drift_goal_task_repository.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/data/supabase_goal_task_source.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:pacta/private_data/private_data_state.dart';

void main() {
  testWidgets('opens a dedicated countdown surface without manual completion', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final userId = const AppUserId('session-page-user');
    var now = DateTime.utc(2026, 8, 24, 9);
    final goals = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );
    final goal = await goals.saveGoal(
      userId,
      const GoalDraft(title: 'Focus Goal'),
    );
    final task = await goals.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Write release notes',
        classification: TaskChainClassification.elite,
      ),
    );
    final sessions = DriftFocusSessionRepository(
      database: database,
      clock: () => now,
    );
    final config = FocusSessionConfig(
      task: task,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 15),
    );
    final started = await sessions.start(userId, config);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusSessionRepositoryProvider.overrideWithValue(sessions),
          goalTaskRepositoryProvider.overrideWithValue(goals),
          syncRetryTriggersProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: buildChainTheme(),
          home: FocusSessionPage(
            userId: userId,
            config: config,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Write release notes'), findsOneWidget);
    expect(find.text('Mode: Elite'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.byKey(const Key('focus-session-status')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byKey(const Key('manual-complete')), findsNothing);
    expect(find.text('Complete'), findsNothing);

    now = now.add(const Duration(minutes: 15));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Focus Node recorded'), findsOneWidget);
    expect(
      (await goals.read(userId)).tasks.single.focusProgress,
      const Duration(minutes: 15),
    );
    expect((await goals.read(userId)).tasks.single.isComplete, isFalse);
    expect(await sessions.readNodes(userId, started.id), hasLength(1));
  });
}
