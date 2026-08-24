import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

void main() {
  final userId = const AppUserId('session-user');
  final startedAt = DateTime.utc(2026, 8, 24, 9);
  final task = Task(
    id: 'task-1',
    userId: userId,
    goalId: 'goal-1',
    title: 'Focus task',
    classification: TaskChainClassification.both,
    createdAt: startedAt,
    updatedAt: startedAt,
  );
  final config = FocusSessionConfig(
    task: task,
    mode: FocusChainMode.elite,
    duration: const Duration(minutes: 30),
  );

  test('derives elapsed and remaining from an injected clock', () {
    final session = FocusSession(
      id: 'session-1',
      userId: userId,
      taskId: task.id,
      mode: FocusChainMode.elite,
      plannedDuration: const Duration(minutes: 30),
      startedAt: startedAt,
      outcome: null,
      actualElapsed: Duration.zero,
      createdAt: startedAt,
      updatedAt: startedAt,
    );

    expect(
      FocusSessionClockState.fromSession(session, startedAt).elapsed,
      Duration.zero,
    );
    expect(
      FocusSessionClockState.fromSession(
        session,
        startedAt.add(const Duration(minutes: 12)),
      ).remaining,
      const Duration(minutes: 18),
    );
    final atZero = FocusSessionClockState.fromSession(
      session,
      startedAt.add(const Duration(minutes: 30)),
    );
    expect(atZero.elapsed, const Duration(minutes: 30));
    expect(atZero.remaining, Duration.zero);
    expect(atZero.reachedZero, isTrue);
  });

  test('clamps late clock reads and completed Sessions are stable', () {
    final active = FocusSession(
      id: 'session-1',
      userId: userId,
      taskId: task.id,
      mode: FocusChainMode.regular,
      plannedDuration: const Duration(minutes: 5),
      startedAt: startedAt,
      outcome: null,
      actualElapsed: Duration.zero,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
    final late = FocusSessionClockState.fromSession(
      active,
      startedAt.add(const Duration(minutes: 20)),
    );
    expect(late.elapsed, const Duration(minutes: 5));
    expect(late.remaining, Duration.zero);

    final completed = active.copyWith(
      outcome: FocusSessionOutcome.completed,
      actualElapsed: const Duration(minutes: 5),
      completedAt: startedAt.add(const Duration(minutes: 5)),
    );
    final stable = FocusSessionClockState.fromSession(
      completed,
      startedAt.add(const Duration(hours: 2)),
    );
    expect(stable.elapsed, const Duration(minutes: 5));
    expect(stable.remaining, Duration.zero);
    expect(stable.reachedZero, isTrue);
  });

  test(
    'configuration preserves selected Task context without selecting completion',
    () {
      expect(config.task.id, task.id);
      expect(config.mode, FocusChainMode.elite);
      expect(config.duration, const Duration(minutes: 30));
      expect(task.isComplete, isFalse);
    },
  );
}
