import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late LocalTaskRepository tasks;
  late LocalScheduleRepository schedules;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 11, 15, 1);
    DateTime clock() => now = now.add(const Duration(seconds: 1));
    tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: clock,
    );
    schedules = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: clock,
    );
  });

  tearDown(() async {
    await tasks.dispose();
    await schedules.dispose();
    await database.close();
  });

  Future<Goal> goal(String title) => tasks.createGoal(
    GoalDraft(title: title, classification: TaskClassification.regular),
  );

  test(
    'pins several goals and keeps the manual order after reopening',
    () async {
      final first = await goal('甲');
      final second = await goal('乙');
      final third = await goal('丙');

      await tasks.setGoalPinned(third.id, isPinned: true);
      await tasks.setGoalPinned(first.id, isPinned: true);
      await tasks.reorderPinnedGoals([first.id, third.id]);

      final reopened = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
      );
      final ordered = await reopened.getGoals();
      expect(ordered.map((item) => item.id).toList(), [
        first.id,
        third.id,
        second.id,
      ]);
      expect(ordered.take(2).every((item) => item.isPinned), isTrue);
      expect(ordered.last.isPinned, isFalse);
    },
  );

  test(
    'unpinning a goal removes it from the pinned block but keeps order',
    () async {
      final first = await goal('甲');
      final second = await goal('乙');
      await tasks.setGoalPinned(first.id, isPinned: true);
      await tasks.setGoalPinned(second.id, isPinned: true);
      await tasks.reorderPinnedGoals([second.id, first.id]);

      await tasks.setGoalPinned(second.id, isPinned: false);

      final ordered = await tasks.getGoals();
      expect(ordered.map((item) => item.id).toList(), [first.id, second.id]);
      expect(ordered.first.isPinned, isTrue);
      expect(ordered.last.isPinned, isFalse);
    },
  );

  test('rejects a reorder list that is not exactly the pinned goals', () async {
    final first = await goal('甲');
    final second = await goal('乙');
    await tasks.setGoalPinned(first.id, isPinned: true);

    expect(
      () => tasks.reorderPinnedGoals([first.id, second.id]),
      throwsArgumentError,
    );
  });

  test('deleting one task keeps the goal and its other tasks', () async {
    final parent = await goal('甲');
    final keep = await tasks.createTask(
      parent.id,
      const TaskDraft(title: '保留'),
    );
    final drop = await tasks.createTask(
      parent.id,
      const TaskDraft(title: '删除'),
    );

    await tasks.deleteTask(drop.id);

    final reloaded = await tasks.getGoals();
    expect(reloaded.single.tasks.map((task) => task.id).toList(), [keep.id]);
    final tombstone = await tasks.getGoals(includeDeleted: true);
    expect(tombstone.single.tasks.map((task) => task.id).toSet(), {
      keep.id,
      drop.id,
    });
  });

  test('deleting a task preserves the schedules already owned by it', () async {
    final parent = await goal('甲');
    final task = await tasks.createTask(
      parent.id,
      const TaskDraft(title: '写报告'),
    );
    final first = await schedules.createSchedule(
      ScheduleDraft(
        title: '写报告 上半场',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
        ),
        taskId: task.id,
      ),
    );
    final second = await schedules.createSchedule(
      ScheduleDraft(
        title: '写报告 下半场',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 10),
          endsAt: DateTime.utc(2026, 11, 16, 11),
        ),
        taskId: task.id,
      ),
    );

    await tasks.deleteTask(task.id);

    final remaining = await schedules.getSchedules();
    expect(remaining.map((item) => item.id).toSet(), {first.id, second.id});
    expect(remaining.every((item) => item.taskId == task.id), isTrue);
  });

  test(
    'next task is the earliest deadline, then no deadline, then creation',
    () async {
      final parent = await goal('甲');
      final noDeadline = await tasks.createTask(
        parent.id,
        const TaskDraft(title: '无截止'),
      );
      final later = await tasks.createTask(
        parent.id,
        TaskDraft(title: '晚截止', deadline: DateTime.utc(2026, 12, 1)),
      );
      final sooner = await tasks.createTask(
        parent.id,
        TaskDraft(title: '早截止', deadline: DateTime.utc(2026, 11, 20)),
      );

      final reloaded = (await tasks.getGoals()).single;
      expect(reloaded.nextTask?.id, sooner.id);

      await tasks.setTaskCompletion(sooner.id, isComplete: true);
      final after = (await tasks.getGoals()).single;
      expect(after.nextTask?.id, later.id);

      await tasks.setTaskCompletion(later.id, isComplete: true);
      final last = (await tasks.getGoals()).single;
      expect(last.nextTask?.id, noDeadline.id);
    },
  );

  test('an empty goal has no next task and stays incomplete', () async {
    await goal('甲');
    final reloaded = (await tasks.getGoals()).single;
    expect(reloaded.nextTask, isNull);
    expect(reloaded.isComplete, isFalse);
  });
}
