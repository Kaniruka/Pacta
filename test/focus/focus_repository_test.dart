import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote taskRemote;
  late InMemoryFocusRemote focusRemote;
  late LocalTaskRepository taskRepository;
  late LocalFocusRepository focusRepository;
  var now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    taskRemote = InMemoryTaskRemote();
    focusRemote = InMemoryFocusRemote();
    taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: taskRemote,
      now: () => now,
    );
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
  });

  tearDown(() async {
    await focusRepository.dispose();
    await taskRepository.dispose();
    await database.close();
  });

  Future<Task> createTask(String title, {int? estimatedMinutes}) async {
    final goal = await taskRepository.createGoal(
      const GoalDraft(title: '本周工作', classification: TaskClassification.both),
    );
    return taskRepository.createTask(
      goal.id,
      TaskDraft(
        title: title,
        classification: TaskClassification.both,
        estimatedMinutes: estimatedMinutes,
      ),
    );
  }

  test('倒计时归零只结算一次节点、链记录和任务有效时间', () async {
    final task = await createTask('写发布说明', estimatedMinutes: 1);
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(seconds: 80),
    );

    expect(session.isActive, isTrue);
    now = now.add(const Duration(seconds: 80));

    final completed = (await focusRepository.getSessions()).single;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 80);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await focusRepository.getChainRecords())
          .singleWhere((record) => record.mode == FocusChainMode.elite)
          .currentConsecutive,
      1,
    );
    final completedTask = (await taskRepository.getGoals()).single.tasks.single;
    expect(completedTask.focusProgressSeconds, 80);
    expect(completedTask.isComplete, isFalse);

    await focusRepository.getSessions();
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      80,
    );
  });

  test('已有进行中的专注返回原会话，不静默新建', () async {
    final task = await createTask('整理资料');
    final first = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 5),
    );

    final returned = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 30),
    );

    expect(returned.id, first.id);
    expect(returned.mode, FocusChainMode.regular);
    expect(await focusRepository.getSessions(), hasLength(1));
  });

  test('正常结算可重启读取并同步到远端', () async {
    final task = await createTask('复核构建');
    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 10),
    );
    now = now.add(const Duration(seconds: 10));
    await focusRepository.sync();

    final remoteSnapshot = await focusRemote.pull(userId: 'user-a');
    expect(remoteSnapshot.sessions.single.status, FocusSessionStatus.completed);
    expect(remoteSnapshot.nodes, hasLength(1));
    expect(
      remoteSnapshot.records
          .singleWhere((record) => record.mode == FocusChainMode.regular)
          .currentConsecutive,
      1,
    );

    final restarted = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    addTearDown(restarted.dispose);
    expect(
      (await restarted.getSessions()).single.status,
      FocusSessionStatus.completed,
    );
    expect(await restarted.getNodes(), hasLength(1));
  });
}
