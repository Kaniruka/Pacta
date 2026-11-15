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

  test('已改期的每周规则再次改名不叠加位移，正负位移都按增量旋转', () async {
    final series = await repository.createRecurringSchedule(
      draft: draft('周一', DateTime.utc(2026, 11, 16, 9)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {DateTime.monday},
      ),
      timeZoneId: 'Etc/UTC',
    );

    // 周一 → 周三：位移 2，可见星期变成周三。
    final moved = await repository.editRecurringSchedule(
      series.occurrences.first.id,
      draft: draft('周三', DateTime.utc(2026, 11, 18, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(moved.rule.shiftDays, 2);
    expect(moved.rule.weekdays, {DateTime.wednesday});

    // 同日只改名：总位移仍是 2，增量 0，星期必须保持周三。
    final renamed = await repository.editRecurringSchedule(
      moved.updated.id,
      draft: draft('周三改名', DateTime.utc(2026, 11, 18, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(renamed.rule.shiftDays, 2);
    expect(renamed.rule.weekdays, {DateTime.wednesday});
    final gap = await window(
      DateTime.utc(2026, 11, 19),
      DateTime.utc(2026, 11, 24),
    );
    expect(gap, isEmpty, reason: '下个周三是 11-25，改名不能生成 11-20 周五');

    final wednesdays = await window(
      DateTime.utc(2026, 11, 18),
      DateTime.utc(2026, 12, 3),
    );
    expect(wednesdays.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 18, 9),
      DateTime.utc(2026, 11, 25, 9),
      DateTime.utc(2026, 12, 2, 9),
    ]);

    // 周三 → 周四：增量 +1。
    final thursday = await repository.editRecurringSchedule(
      renamed.updated.id,
      draft: draft('周四', DateTime.utc(2026, 11, 19, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(thursday.rule.shiftDays, 3);
    expect(thursday.rule.weekdays, {DateTime.thursday});

    // 周四 → 周一：增量 -3，回到最初的星期而不是继续累加。
    final back = await repository.editRecurringSchedule(
      thursday.updated.id,
      draft: draft('周一回', DateTime.utc(2026, 11, 16, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(back.rule.shiftDays, 0);
    expect(back.rule.weekdays, {DateTime.monday});
    expect(back.updated.recurrenceDate, '2026-11-16');
  });

  test('未来分段改写不得删除已经开始的历史例外', () async {
    var now = DateTime.utc(2026, 11, 15, 1);
    final mutable = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    addTearDown(mutable.dispose);

    final series = await mutable.createRecurringSchedule(
      draft: draft('每日', DateTime.utc(2026, 11, 21, 9)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-25',
      ),
      timeZoneId: 'Etc/UTC',
    );
    // 未来的 11-23 那一期被"仅本次"挪到更早的 11-19（创建时仍在未来）。
    final moved = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-23',
    );
    await mutable.editRecurringSchedule(
      moved.id,
      draft: draft('挪到过去的例外', DateTime.utc(2026, 11, 19, 9)),
      scope: ScheduleRepeatScope.onlyThis,
    );
    final exception = (await mutable.getSchedules(
      from: DateTime.utc(2026, 11, 18),
      to: DateTime.utc(2026, 11, 20),
    )).single;
    await mutable.setScheduleCompletion(exception.id, isCompleted: true);

    // 时间走到 11-20：这条例外已经成为历史。
    now = DateTime.utc(2026, 11, 20, 1);

    // 改写仍属未来的 11-21 那一期。
    await mutable.editRecurringSchedule(
      series.occurrences.first.id,
      draft: draft('改后', DateTime.utc(2026, 11, 21, 9)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    final rows = await mutable.getSchedules(
      from: DateTime.utc(2026, 11, 18),
      to: DateTime.utc(2026, 11, 26),
    );
    expect(rows.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 19, 9),
      DateTime.utc(2026, 11, 21, 9),
      DateTime.utc(2026, 11, 22, 9),
      DateTime.utc(2026, 11, 24, 9),
      DateTime.utc(2026, 11, 25, 9),
    ]);
    final preserved = rows.first;
    expect(preserved.recurrenceDate, '2026-11-23');
    expect(preserved.isRecurrenceException, isTrue);
    expect(preserved.title, '挪到过去的例外');
    expect(preserved.isCompleted, isTrue);
    expect(rows.skip(1).map((schedule) => schedule.title).toSet(), {'改后'});
    // 原 11-23 不会被新规则重新生成。
    expect(
      rows.map((schedule) => schedule.startsAt),
      isNot(contains(DateTime.utc(2026, 11, 23, 9))),
    );
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
