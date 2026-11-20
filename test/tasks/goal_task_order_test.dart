import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

/// 工单 04：目标与任务的跨端手动排序、Goal.nextTask 联动。
///
/// 纯 Dart 测试不初始化 `WidgetsFlutterBinding`：偏好存储不可用时
/// [GoalTaskOrderStore] 必须退化为内存兜底而不是抛出或挂起。
void main() {
  late PactaDatabase database;
  late LocalTaskRepository repository;
  late DateTime clock;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026, 11, 20, 8);
    repository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => clock = clock.add(const Duration(seconds: 1)),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<Goal> goal(String title) => repository.createGoal(
    GoalDraft(title: title, classification: TaskClassification.regular),
  );

  Future<Task> task(String goalId, String title, {DateTime? deadline}) =>
      repository.createTask(
        goalId,
        TaskDraft(title: title, deadline: deadline),
      );

  test('reorderTasks 持久化未完成顺序并驱动 Goal.nextTask', () async {
    final parent = await goal('交付');
    final first = await task(
      parent.id,
      '甲',
      deadline: DateTime.utc(2026, 12, 1),
    );
    final second = await task(parent.id, '乙');
    final third = await task(
      parent.id,
      '丙',
      deadline: DateTime.utc(2026, 11, 25),
    );

    final before = (await repository.getGoals()).single;
    expect(before.hasManualTaskOrder, isFalse);
    expect(before.nextTask?.id, third.id, reason: '未排序时仍按最早截止时间挑选');

    await repository.reorderTasks(parent.id, [second.id, first.id, third.id]);

    final after = (await repository.getGoals()).single;
    expect(after.hasManualTaskOrder, isTrue);
    expect(after.tasks.map((item) => item.id).toList(), [
      second.id,
      first.id,
      third.id,
    ]);
    expect(after.nextTask?.id, second.id, reason: '手动顺序优先于截止时间');
  });

  test('排序后新增的未完成任务接在既有顺序之后，已完成留在末尾', () async {
    final parent = await goal('交付');
    final first = await task(parent.id, '甲');
    final second = await task(parent.id, '乙');
    await repository.reorderTasks(parent.id, [second.id, first.id]);

    final added = await task(parent.id, '丙');
    await repository.setTaskCompletion(second.id, isComplete: true);

    final reloaded = (await repository.getGoals()).single;
    expect(reloaded.tasks.map((item) => item.title).toList(), ['甲', '丙', '乙']);
    expect(reloaded.nextTask?.id, first.id);

    // 删除手动顺序里已失效的 id 不会崩：剩余任务仍按顺序读取。
    await repository.deleteTask(first.id);
    final afterDelete = (await repository.getGoals()).single;
    expect(afterDelete.tasks.map((item) => item.title).toList(), ['丙', '乙']);
    expect(afterDelete.nextTask?.id, added.id);
  });

  test('全部完成后再新增任务时优雅回退到新任务', () async {
    final parent = await goal('交付');
    final first = await task(parent.id, '甲');
    final second = await task(parent.id, '乙');
    await repository.reorderTasks(parent.id, [first.id, second.id]);
    await repository.setTaskCompletion(first.id, isComplete: true);
    await repository.setTaskCompletion(second.id, isComplete: true);

    var reloaded = (await repository.getGoals()).single;
    expect(reloaded.nextTask, isNull, reason: '全部完成没有下一项');

    final added = await task(parent.id, '新一步');
    reloaded = (await repository.getGoals()).single;
    expect(reloaded.tasks.map((item) => item.id).toList(), [
      added.id,
      first.id,
      second.id,
    ], reason: '唯一未完成任务排在前面，已完成任务保持在末尾');
    expect(reloaded.nextTask?.id, added.id);
  });

  test('reorderTasks 拒绝重复 id、缺失覆盖与跨用户目标', () async {
    final parent = await goal('交付');
    final first = await task(parent.id, '甲');
    final second = await task(parent.id, '乙');

    await expectLater(
      repository.reorderTasks(parent.id, [first.id, first.id]),
      throwsArgumentError,
    );
    await expectLater(
      repository.reorderTasks(parent.id, [first.id]),
      throwsArgumentError,
    );
    await expectLater(
      repository.reorderTasks(parent.id, [first.id, second.id, 'unknown']),
      throwsArgumentError,
    );

    final otherUser = LocalTaskRepository(
      database: database,
      userId: 'user-b',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    addTearDown(otherUser.dispose);
    await expectLater(
      otherUser.reorderTasks(parent.id, const []),
      throwsStateError,
      reason: '越权目标不可写排序',
    );
  });

  test('reorderUnpinnedGoals 持久化未置顶顺序并在重开后保持', () async {
    final first = await goal('甲');
    final second = await goal('乙');
    final third = await goal('丙');

    expect((await repository.getGoals()).map((item) => item.id).toList(), [
      first.id,
      second.id,
      third.id,
    ]);

    await repository.reorderUnpinnedGoals([third.id, first.id, second.id]);
    expect((await repository.getGoals()).map((item) => item.id).toList(), [
      third.id,
      first.id,
      second.id,
    ]);

    final reopened = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    addTearDown(reopened.dispose);
    expect((await reopened.getGoals()).map((item) => item.id).toList(), [
      third.id,
      first.id,
      second.id,
    ]);
  });

  test('reorderUnpinnedGoals 只覆盖未置顶目标', () async {
    final pinned = await goal('置顶');
    final first = await goal('甲');
    final second = await goal('乙');
    await repository.setGoalPinned(pinned.id, isPinned: true);

    await expectLater(
      repository.reorderUnpinnedGoals([first.id, second.id, pinned.id]),
      throwsArgumentError,
      reason: '置顶目标不属于未置顶分组',
    );
    await expectLater(
      repository.reorderUnpinnedGoals([first.id, first.id]),
      throwsArgumentError,
    );
    await expectLater(
      repository.reorderUnpinnedGoals([]),
      throwsArgumentError,
      reason: '必须覆盖全部未置顶目标',
    );

    await repository.reorderUnpinnedGoals([second.id, first.id]);
    expect((await repository.getGoals()).map((item) => item.id).toList(), [
      pinned.id,
      second.id,
      first.id,
    ]);
  });
  test('旧手动顺序的任务全部完成后，新建任务回退到最早截止时间', () async {
    final parent = await goal('交付');
    final oldFirst = await task(parent.id, '旧甲');
    final oldSecond = await task(parent.id, '旧乙');
    await repository.reorderTasks(parent.id, [oldSecond.id, oldFirst.id]);

    var reloaded = (await repository.getGoals()).single;
    expect(reloaded.hasManualTaskOrder, isTrue, reason: '此时顺序仍命中未完成任务');

    await repository.setTaskCompletion(oldFirst.id, isComplete: true);
    await repository.setTaskCompletion(oldSecond.id, isComplete: true);

    // 新任务故意让"创建更早"的那条截止更晚：回退逻辑必须按截止时间，
    // 而不是按 updatedAt 的第一条（那会选中创建更早的新甲）。
    final newLater = await task(
      parent.id,
      '新甲',
      deadline: DateTime.utc(2026, 12, 1),
    );
    final newSooner = await task(
      parent.id,
      '新乙',
      deadline: DateTime.utc(2026, 11, 25),
    );

    reloaded = (await repository.getGoals()).single;
    expect(
      reloaded.hasManualTaskOrder,
      isFalse,
      reason: '保存的顺序已没有任何有效未完成任务，不应再声称手动顺序生效',
    );
    expect(reloaded.nextTask?.id, newSooner.id, reason: '回退到最早截止时间');
    expect(reloaded.tasks.first.id, newLater.id, reason: '稳定分组仍按更新时间排列');
  });

  test('旧手动顺序的任务全部删除后，新任务同样回退到最早截止时间', () async {
    final parent = await goal('交付');
    final oldFirst = await task(parent.id, '旧甲');
    final oldSecond = await task(parent.id, '旧乙');
    await repository.reorderTasks(parent.id, [oldFirst.id, oldSecond.id]);
    await repository.deleteTask(oldFirst.id);
    await repository.deleteTask(oldSecond.id);

    final newLater = await task(
      parent.id,
      '新甲',
      deadline: DateTime.utc(2026, 12, 1),
    );
    final newSooner = await task(
      parent.id,
      '新乙',
      deadline: DateTime.utc(2026, 11, 25),
    );

    final reloaded = (await repository.getGoals()).single;
    expect(reloaded.hasManualTaskOrder, isFalse);
    expect(reloaded.nextTask?.id, newSooner.id);
    expect(reloaded.tasks.map((item) => item.id).toSet(), {
      newLater.id,
      newSooner.id,
    });
  });
}
