import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote remote;
  late LocalTaskRepository repository;

  final now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryTaskRemote();
    repository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: remote,
      now: () => now,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('目标完成状态由非空任务的手动完成状态派生', () async {
    final goal = await repository.createGoal(
      const GoalDraft(title: '准备发布', classification: TaskClassification.elite),
    );
    expect((await repository.getGoals()).single.isComplete, isFalse);

    final task = await repository.createTask(
      goal.id,
      const TaskDraft(title: '写说明', classification: null),
    );
    expect(task.classification, TaskClassification.elite);
    expect((await repository.getGoals()).single.isComplete, isFalse);

    await repository.setTaskCompletion(task.id, isComplete: true);
    expect((await repository.getGoals()).single.isComplete, isTrue);

    await repository.createTask(
      goal.id,
      const TaskDraft(title: '检查构建', classification: null),
    );
    expect((await repository.getGoals()).single.isComplete, isFalse);
  });

  test('编辑任务保留其目标且预计时长不是完成门槛', () async {
    final goal = await repository.createGoal(
      const GoalDraft(title: '学习', classification: TaskClassification.regular),
    );
    final task = await repository.createTask(
      goal.id,
      TaskDraft(
        title: '读一章',
        classification: TaskClassification.both,
        estimatedMinutes: 60,
        deadline: DateTime.utc(2026, 10, 1),
      ),
    );

    final edited = await repository.updateTask(
      task.id,
      TaskDraft(
        title: '读两章',
        classification: TaskClassification.elite,
        estimatedMinutes: 90,
        deadline: DateTime.utc(2026, 10, 2),
      ),
    );

    expect(edited.goalId, goal.id);
    expect(edited.title, '读两章');
    expect(edited.estimatedMinutes, 90);
    expect(edited.deadline, DateTime.utc(2026, 10, 2));
    expect(edited.isComplete, isFalse);

    await expectLater(
      repository.updateTask(
        task.id,
        const TaskDraft(
          title: '无效时长',
          classification: TaskClassification.elite,
          estimatedMinutes: -1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('同一秒内连续编辑仍产生单调更新时间', () async {
    final goal = await repository.createGoal(
      const GoalDraft(
        title: '连续编辑',
        classification: TaskClassification.regular,
      ),
    );
    final updatedGoal = await repository.updateGoal(
      goal.id,
      const GoalDraft(title: '连续编辑后', classification: TaskClassification.elite),
    );
    expect(updatedGoal.updatedAt.isAfter(goal.updatedAt), isTrue);

    final task = await repository.createTask(
      goal.id,
      const TaskDraft(title: '快速完成', classification: null),
    );
    await repository.setTaskCompletion(task.id, isComplete: true);
    final updatedTask = (await repository.getGoals()).single.tasks.single;
    expect(updatedTask.updatedAt.isAfter(task.updatedAt), isTrue);
  });

  test('本地写入可重启读取，重复同步不会重复创建', () async {
    final goal = await repository.createGoal(
      const GoalDraft(title: '离线工作', classification: TaskClassification.both),
    );
    await repository.createTask(
      goal.id,
      const TaskDraft(title: '断网编辑', classification: null),
    );

    await repository.sync();
    await repository.sync();

    expect(remote.goals, hasLength(1));
    expect(remote.tasks, hasLength(1));

    final restarted = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: remote,
      now: () => now,
    );
    expect((await restarted.getGoals()).single.tasks.single.title, '断网编辑');
  });

  test('本地数据按用户隔离', () async {
    final goal = await repository.createGoal(
      const GoalDraft(
        title: '私有目标',
        classification: TaskClassification.regular,
      ),
    );
    await repository.createTask(
      goal.id,
      const TaskDraft(title: '私有任务', classification: null),
    );

    final otherUser = LocalTaskRepository(
      database: database,
      userId: 'user-b',
      remote: remote,
      now: () => now,
    );
    expect(await otherUser.getGoals(), isEmpty);
  });

  test('普通目标元数据按更新时间解决跨端冲突', () async {
    final local = await repository.createGoal(
      const GoalDraft(
        title: '本地版本',
        classification: TaskClassification.regular,
      ),
    );
    await remote.upsertGoals(
      userId: 'user-a',
      goals: [
        local.copyWith(
          title: '另一端较新版本',
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      ],
    );

    await repository.sync();

    expect((await repository.getGoals()).single.title, '另一端较新版本');
  });
}
