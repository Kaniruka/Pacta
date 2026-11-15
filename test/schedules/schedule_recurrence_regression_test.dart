import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

/// r3 复审的公开回归：范围不相交、规则模板、稳定身份、严格日历解析。
///
/// 全部走 LocalScheduleRepository 的公开 API，不读内部表结构。
void main() {
  late PactaDatabase database;
  late LocalScheduleRepository repository;
  late LocalTaskRepository tasks;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await tasks.dispose();
    await database.close();
  });

  ScheduleDraft draft(
    String title,
    DateTime start, {
    int minutes = 60,
    String notes = '',
    String? taskId,
  }) => ScheduleDraft(
    title: title,
    notes: notes,
    taskId: taskId,
    window: ScheduleWindow.timed(
      startsAt: start,
      endsAt: start.add(Duration(minutes: minutes)),
    ),
  );

  Future<List<Schedule>> window(DateTime from, DateTime to) =>
      repository.getSchedules(from: from, to: to);

  const daily = ScheduleRepeatSpec(frequency: ScheduleRepeatFrequency.daily);

  test('重复日程开始之前的范围返回空，且不影响普通日程', () async {
    await repository.createSchedule(
      draft('十月普通日程', DateTime.utc(2026, 10, 5, 9)),
    );
    await repository.createRecurringSchedule(
      draft: draft('每日', DateTime.utc(2026, 11, 16, 9)),
      repeat: daily,
      timeZoneId: 'Etc/UTC',
    );

    final october = await window(
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 11, 1),
    );
    expect(october.map((schedule) => schedule.title), ['十月普通日程']);

    // 同一区间重复读取仍不能抛错，也不能凭空生成实例。
    final again = await window(
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 11, 1),
    );
    expect(again.map((schedule) => schedule.id), october.map((s) => s.id));
  });

  test('分段规则自己的内容模板在预生成窗口之外仍然生效', () async {
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '模板目标',
        classification: TaskClassification.regular,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(title: '模板任务', classification: null),
    );
    final series = await repository.createRecurringSchedule(
      draft: draft('原始', DateTime.utc(2026, 11, 16, 9), notes: '原始备注'),
      repeat: daily,
      timeZoneId: 'Etc/UTC',
    );

    await repository.editRecurringSchedule(
      series.occurrences[1].id,
      draft: draft(
        '改后',
        DateTime.utc(2026, 11, 17, 9),
        notes: '改后备注',
        taskId: task.id,
      ),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    final may = await window(
      DateTime.utc(2027, 5, 1),
      DateTime.utc(2027, 5, 2),
    );
    expect(may, hasLength(1));
    expect(may.single.title, '改后');
    expect(may.single.notes, '改后备注');
    expect(may.single.taskId, task.id);
  });

  test('仅本次例外不会污染后续补齐实例的内容', () async {
    final series = await repository.createRecurringSchedule(
      draft: draft('原始', DateTime.utc(2026, 11, 16, 9)),
      repeat: daily,
      timeZoneId: 'Etc/UTC',
    );
    await repository.editRecurringSchedule(
      series.occurrences.first.id,
      draft: draft('例外', DateTime.utc(2026, 11, 16, 10)),
      scope: ScheduleRepeatScope.onlyThis,
    );

    final april = await window(
      DateTime.utc(2027, 4, 1),
      DateTime.utc(2027, 4, 2),
    );
    expect(april.single.title, '原始');
  });

  test('改期分段按原始身份保留取消：被删的原 18 号不会在别处复活', () async {
    final series = await repository.createRecurringSchedule(
      draft: draft('每日', DateTime.utc(2026, 11, 16, 9)),
      repeat: daily,
      timeZoneId: 'Etc/UTC',
    );
    final eighteenth = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-18',
    );
    await repository.deleteSchedule(eighteenth.id);

    // 原 17 号整体后移一天：可见日期变 18 号，身份仍是 17 号。
    await repository.editRecurringSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-17')
          .id,
      draft: draft('每日', DateTime.utc(2026, 11, 18, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    final rows = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 23),
    );
    expect(rows.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 16, 9),
      DateTime.utc(2026, 11, 18, 9),
      DateTime.utc(2026, 11, 20, 9),
      DateTime.utc(2026, 11, 21, 9),
      DateTime.utc(2026, 11, 22, 9),
    ]);
    expect(rows.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-17',
      '2026-11-19',
      '2026-11-20',
      '2026-11-21',
    ]);
    // 原 18 号（墓碑）后移后落在 19 号，仍必须缺席。
    expect(
      rows.map((schedule) => schedule.startsAt),
      isNot(contains(DateTime.utc(2026, 11, 19, 9))),
    );
    // 身份不重复：同一期不会既是活实例又是墓碑。
    expect(
      rows.map((schedule) => schedule.recurrenceDate).toSet(),
      hasLength(rows.length),
    );
  });

  test('从首个实例改期：后续原发生日仍按身份保留取消', () async {
    final series = await repository.createRecurringSchedule(
      draft: draft('每日', DateTime.utc(2026, 11, 16, 9)),
      repeat: daily,
      timeZoneId: 'Etc/UTC',
    );
    final eighteenth = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-18',
    );
    await repository.deleteSchedule(eighteenth.id);

    // 原 16 号整体后移一天：可见变 17 号，身份 16 号。
    await repository.editRecurringSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-16')
          .id,
      draft: draft('每日', DateTime.utc(2026, 11, 17, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    final rows = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 22),
    );
    expect(rows.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 17, 9),
      DateTime.utc(2026, 11, 18, 9),
      DateTime.utc(2026, 11, 20, 9),
      DateTime.utc(2026, 11, 21, 9),
    ]);
    expect(rows.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-17',
      '2026-11-19',
      '2026-11-20',
    ]);
  });

  test('严格日历解析拒绝顺移日期与不可用规则时区', () {
    expect(() => parseRecurrenceDate('2026-02-30', '日期'), throwsArgumentError);
    expect(() => parseRecurrenceDate('2026-11-31', '日期'), throwsArgumentError);
    expect(() => parseRecurrenceDate('2026-99-99', '日期'), throwsArgumentError);
    expect(parseRecurrenceDate('2026-02-28', '日期'), DateTime.utc(2026, 2, 28));
    expect(
      () => ScheduleRepeatRule(
        id: 'rule',
        frequency: ScheduleRepeatFrequency.daily,
        weekdays: const {},
        firstDate: '2026-11-16',
        timeZoneId: 'Mars/Olympus',
      ),
      throwsArgumentError,
    );
  });
}
