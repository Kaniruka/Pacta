import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 重复提醒后端回归：提醒偏移属于规则模板，实例按懒展开继承。
void main() {
  late PactaDatabase database;
  late LocalScheduleRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  ScheduleDraft timedDraft({
    String title = '周会',
    DateTime? startsAt,
    int minutes = 60,
    String? taskId,
  }) {
    final start = startsAt ?? DateTime.utc(2026, 11, 16, 1);
    return ScheduleDraft(
      title: title,
      window: ScheduleWindow.timed(
        startsAt: start,
        endsAt: start.add(Duration(minutes: minutes)),
      ),
      taskId: taskId,
    );
  }

  test('创建重复日程时提醒偏移进入规则并继承到已生成的实例', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
      reminderMinutesBefore: 30,
    );

    expect(series.rule.reminderMinutesBefore, 30);
    expect(series.rule.hasReminder, isTrue);
    expect(
      series.occurrences.map((schedule) => schedule.reminderMinutesBefore),
      [30, 30, 30],
    );
    final rules = await repository.getRecurrenceRules();
    expect(rules.single.reminderMinutesBefore, 30);
  });

  test('不指定提醒时规则与实例都没有提醒', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-17',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    expect(series.rule.reminderMinutesBefore, isNull);
    expect(series.rule.hasReminder, isFalse);
    expect(
      series.occurrences.map((schedule) => schedule.reminderMinutesBefore),
      [null, null],
    );
  });

  test('超过预生成窗口的懒展开实例仍继承规则提醒', () async {
    await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 45,
    );

    final later = await repository.getSchedules(
      from: DateTime.utc(2027, 2, 20),
      to: DateTime.utc(2027, 2, 23),
    );

    expect(later.map((schedule) => schedule.recurrenceDate), [
      '2027-02-20',
      '2027-02-21',
      '2027-02-22',
    ]);
    expect(later.map((schedule) => schedule.reminderMinutesBefore), [
      45,
      45,
      45,
    ]);
  });

  test('规则模板的提醒偏移参与复制与相等性', () {
    final base = ScheduleRepeatRule(
      id: 'rule-a',
      frequency: ScheduleRepeatFrequency.daily,
      weekdays: const {},
      firstDate: '2026-11-16',
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 45,
    );

    expect(base.copyWith(title: '改名').reminderMinutesBefore, 45);
    expect(base.copyWith(reminderMinutesBefore: 10).reminderMinutesBefore, 10);
    expect(base.copyWith(clearReminder: true).reminderMinutesBefore, isNull);
    expect(base.copyWith(clearReminder: true).hasReminder, isFalse);
    expect(
      base == base.copyWith(title: '改名'),
      isFalse,
      reason: '内容模板不同不算同一条规则',
    );
    expect(
      base ==
          ScheduleRepeatRule(
            id: 'rule-a',
            frequency: ScheduleRepeatFrequency.daily,
            weekdays: const {},
            firstDate: '2026-11-16',
            timeZoneId: 'Etc/UTC',
          ),
      isFalse,
      reason: '提醒偏移是规则配置的一部分',
    );
    expect(base.copyWith(clearReminder: true).reminderMinutesBefore, isNull);
  });

  test('仅本次只改该实例的提醒，规则模板与其他实例不变', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-19',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    final target = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-17',
    );

    final result = await repository.editRecurringSchedule(
      target.id,
      draft: timedDraft(title: '仅本次', startsAt: DateTime.utc(2026, 11, 17, 1)),
      scope: ScheduleRepeatScope.onlyThis,
      reminderMinutesBefore: 5,
    );

    expect(result.updated.reminderMinutesBefore, 5);
    expect(result.rule.reminderMinutesBefore, 30);
    expect(await _remindersByDate(repository), {
      '2026-11-16': 30,
      '2026-11-17': 5,
      '2026-11-18': 30,
      '2026-11-19': 30,
    });
  });

  test('仅本次省略提醒时保留该实例已有的提醒覆盖', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    final target = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-17',
    );
    await repository.setScheduleReminder(target.id, minutesBefore: 15);

    final result = await repository.editRecurringSchedule(
      target.id,
      draft: timedDraft(title: '只改名', startsAt: DateTime.utc(2026, 11, 17, 1)),
      scope: ScheduleRepeatScope.onlyThis,
    );

    expect(result.updated.reminderMinutesBefore, 15);
    expect(result.rule.reminderMinutesBefore, 30);
    expect(await _remindersByDate(repository), {
      '2026-11-16': 30,
      '2026-11-17': 15,
      '2026-11-18': 30,
    });
  });

  test('仅本次显式清除提醒只影响该实例', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    final target = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-17',
    );

    final result = await repository.editRecurringSchedule(
      target.id,
      draft: timedDraft(title: '不提醒', startsAt: DateTime.utc(2026, 11, 17, 1)),
      scope: ScheduleRepeatScope.onlyThis,
      clearReminder: true,
    );

    expect(result.updated.reminderMinutesBefore, isNull);
    expect(result.rule.reminderMinutesBefore, 30);
    expect((await _remindersByDate(repository))['2026-11-18'], 30);
    expect((await _remindersByDate(repository))['2026-11-17'], isNull);
  });

  test('本次及以后只改标题时提醒随规则模板保留', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-20',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    final target = series.occurrences.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-18',
    );

    final result = await repository.editRecurringSchedule(
      target.id,
      draft: timedDraft(title: '改后', startsAt: DateTime.utc(2026, 11, 18, 1)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    expect(result.rule.reminderMinutesBefore, 30);
    expect(result.updated.reminderMinutesBefore, 30);
    expect(await _remindersByDate(repository), {
      '2026-11-16': 30,
      '2026-11-17': 30,
      '2026-11-18': 30,
      '2026-11-19': 30,
      '2026-11-20': 30,
    });
  });

  test('本次及以后显式改值再清除提醒，历史行保持原值', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-21',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );

    await repository.editRecurringSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-18')
          .id,
      draft: timedDraft(title: '四十五', startsAt: DateTime.utc(2026, 11, 18, 1)),
      scope: ScheduleRepeatScope.thisAndFuture,
      reminderMinutesBefore: 45,
    );
    expect(await _remindersByDate(repository), {
      '2026-11-16': 30,
      '2026-11-17': 30,
      '2026-11-18': 45,
      '2026-11-19': 45,
      '2026-11-20': 45,
      '2026-11-21': 45,
    });

    final cleared = await repository.editRecurringSchedule(
      (await repository.getSchedules(
        from: DateTime.utc(2026, 11, 19),
        to: DateTime.utc(2026, 11, 20),
      )).single.id,
      draft: timedDraft(title: '清除', startsAt: DateTime.utc(2026, 11, 19, 1)),
      scope: ScheduleRepeatScope.thisAndFuture,
      clearReminder: true,
    );
    expect(cleared.rule.reminderMinutesBefore, isNull);
    expect(await _remindersByDate(repository), {
      '2026-11-16': 30,
      '2026-11-17': 30,
      '2026-11-18': 45,
      '2026-11-19': null,
      '2026-11-20': null,
      '2026-11-21': null,
    });

    final again = await repository.editRecurringSchedule(
      (await repository.getSchedules(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 11, 21),
      )).single.id,
      draft: timedDraft(title: '再改', startsAt: DateTime.utc(2026, 11, 20, 1)),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(again.rule.reminderMinutesBefore, isNull);
    expect((await _remindersByDate(repository))['2026-11-21'], isNull);
  });

  test('清除提醒与设置提醒互相矛盾时整体拒绝', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-17',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );

    await expectLater(
      repository.editRecurringSchedule(
        series.occurrences.first.id,
        draft: timedDraft(title: '矛盾'),
        scope: ScheduleRepeatScope.onlyThis,
        reminderMinutesBefore: 15,
        clearReminder: true,
      ),
      throwsArgumentError,
    );
    expect(
      (await repository.getRecurrenceRules()).single.reminderMinutesBefore,
      30,
    );
    expect(await _remindersByDate(repository), {
      '2026-11-16': 30,
      '2026-11-17': 30,
    });
  });

  test('非法提醒偏移整体不写，规则与实例保持原样', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    final before = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 15),
      to: DateTime.utc(2026, 11, 19),
    );
    final signature = {
      for (final schedule in before) schedule.id: schedule.updatedAt,
    };

    for (final invalid in [-1, 10081]) {
      await expectLater(
        repository.editRecurringSchedule(
          series.occurrences.first.id,
          draft: timedDraft(title: '越界'),
          scope: ScheduleRepeatScope.onlyThis,
          reminderMinutesBefore: invalid,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.createRecurringSchedule(
          draft: timedDraft(title: '越界新建'),
          repeat: const ScheduleRepeatSpec(
            frequency: ScheduleRepeatFrequency.daily,
          ),
          timeZoneId: 'Etc/UTC',
          reminderMinutesBefore: invalid,
        ),
        throwsArgumentError,
      );
    }

    final after = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 15),
      to: DateTime.utc(2026, 11, 19),
    );
    expect({
      for (final schedule in after) schedule.id: schedule.updatedAt,
    }, signature);
    expect(
      (await repository.getRecurrenceRules()).single.reminderMinutesBefore,
      30,
    );
    expect(await database.select(database.focusSessions).get(), isEmpty);
    expect(
      await database.select(database.localScheduleRecurrences).get(),
      hasLength(1),
    );
  });

  test('关联任务被删后，保留原关联的重复项仍可编辑', () async {
    await _seedTask(database, id: 'task-a', title: '写报告', userId: 'user-a');
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(taskId: 'task-a'),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    await (database.update(
      database.localTasks,
    )..where((task) => task.id.equals('task-a'))).write(
      LocalTasksCompanion(deletedAt: Value(DateTime.utc(2026, 11, 15, 2))),
    );

    final onlyThis = await repository.editRecurringSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-17')
          .id,
      draft: timedDraft(
        title: '仅本次改名',
        startsAt: DateTime.utc(2026, 11, 17, 1),
        taskId: 'task-a',
      ),
      scope: ScheduleRepeatScope.onlyThis,
      reminderMinutesBefore: 10,
    );
    expect(onlyThis.updated.taskId, 'task-a');
    expect(onlyThis.updated.reminderMinutesBefore, 10);

    final thisAndFuture = await repository.editRecurringSchedule(
      series.occurrences.first.id,
      draft: timedDraft(title: '后续改名', taskId: 'task-a'),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(thisAndFuture.updated.taskId, 'task-a');
    expect(thisAndFuture.rule.taskId, 'task-a');
    expect(thisAndFuture.rule.reminderMinutesBefore, 30);
  });

  test('已删除任务不能作为新关联，跨用户任务同样不可见', () async {
    await _seedTask(database, id: 'task-a', title: '写报告', userId: 'user-a');
    await _seedTask(database, id: 'task-b', title: '旧任务', userId: 'user-a');
    await _seedTask(database, id: 'task-other', title: '别人的', userId: 'user-b');
    await (database.update(
      database.localTasks,
    )..where((task) => task.id.equals('task-b'))).write(
      LocalTasksCompanion(deletedAt: Value(DateTime.utc(2026, 11, 15, 2))),
    );

    final series = await repository.createRecurringSchedule(
      draft: timedDraft(taskId: 'task-a'),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );

    await expectLater(
      repository.editRecurringSchedule(
        series.occurrences.first.id,
        draft: timedDraft(title: '改选已删', taskId: 'task-b'),
        scope: ScheduleRepeatScope.onlyThis,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.createRecurringSchedule(
        draft: timedDraft(title: '新建到已删', taskId: 'task-b'),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
        ),
        timeZoneId: 'Etc/UTC',
      ),
      throwsStateError,
    );
    await expectLater(
      repository.createRecurringSchedule(
        draft: timedDraft(title: '跨用户', taskId: 'task-other'),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
        ),
        timeZoneId: 'Etc/UTC',
      ),
      throwsStateError,
    );
    expect(
      (await repository.getSchedules())
          .map((schedule) => schedule.taskId)
          .toSet(),
      {'task-a'},
    );
  });

  test('本次及以后改提醒保留历史、完成状态与取消墓碑', () async {
    await repository.dispose();
    repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 14, 22),
    );
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(startsAt: DateTime.utc(2026, 11, 10, 1)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-20',
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );
    await repository.setScheduleCompletion(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-12')
          .id,
      isCompleted: true,
    );
    await repository.deleteSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-14')
          .id,
    );

    final result = await repository.editRecurringSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-13')
          .id,
      draft: timedDraft(title: '改后', startsAt: DateTime.utc(2026, 11, 13, 1)),
      scope: ScheduleRepeatScope.thisAndFuture,
      reminderMinutesBefore: 45,
    );
    expect(result.rule.reminderMinutesBefore, 45);

    final visible = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 9),
      to: DateTime.utc(2026, 11, 21),
    );
    expect(
      {
        for (final schedule in visible)
          schedule.recurrenceDate: schedule.reminderMinutesBefore,
      },
      {
        '2026-11-10': 30,
        '2026-11-11': 30,
        '2026-11-12': 30,
        '2026-11-13': 45,
        '2026-11-15': 45,
        '2026-11-16': 45,
        '2026-11-17': 45,
        '2026-11-18': 45,
        '2026-11-19': 45,
        '2026-11-20': 45,
      },
    );
    expect(
      visible.map((schedule) => schedule.recurrenceDate),
      isNot(contains('2026-11-14')),
      reason: '取消的实例保持墓碑，不被新规则重新生成',
    );
    final completed = visible.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-12',
    );
    expect(completed.isCompleted, isTrue);
    expect(completed.completedAt, isNotNull);
    expect(
      visible
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-13')
          .isRecurrenceException,
      isFalse,
    );
    expect(
      await repository.expandRecurrences(
        from: DateTime.utc(2026, 11, 9),
        to: DateTime.utc(2026, 11, 21),
      ),
      0,
    );
    expect(
      (await repository.getSchedules(
        from: DateTime.utc(2026, 11, 9),
        to: DateTime.utc(2026, 11, 21),
      )).map((schedule) => schedule.recurrenceDate),
      isNot(contains('2026-11-14')),
    );
    expect(await database.select(database.focusSessions).get(), isEmpty);
  });

  test('连续两次改期后提醒与原始身份都保持', () async {
    await repository.dispose();
    repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 0, 30),
    );
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
      reminderMinutesBefore: 30,
    );

    await repository.editRecurringSchedule(
      series.occurrences
          .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-18')
          .id,
      draft: timedDraft(title: '后移两天', startsAt: DateTime.utc(2026, 11, 20, 1)),
      scope: ScheduleRepeatScope.thisAndFuture,
      reminderMinutesBefore: 45,
    );
    var rows = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 15),
      to: DateTime.utc(2026, 12, 10),
    );
    final identities = rows.map((schedule) => schedule.recurrenceDate).toList();
    expect(identities.toSet(), hasLength(identities.length));
    expect(
      identities.toSet(),
      containsAll({for (var day = 16; day <= 30; day++) '2026-11-$day'}),
    );
    expect(
      {
        for (final schedule in rows)
          if (schedule.recurrenceDate!.compareTo('2026-11-16') >= 0 &&
              schedule.recurrenceDate!.compareTo('2026-11-30') <= 0)
            schedule.recurrenceDate!: schedule.startsAt,
      },
      {
        for (var day = 16; day <= 30; day++)
          '2026-11-$day': DateTime.utc(2026, 11, day <= 17 ? day : day + 2, 1),
      },
    );
    expect(
      rows
          .where(
            (schedule) => schedule.recurrenceDate!.compareTo('2026-11-18') >= 0,
          )
          .map((schedule) => schedule.reminderMinutesBefore)
          .toSet(),
      {45},
    );

    final shifted = rows.firstWhere(
      (schedule) => schedule.recurrenceDate == '2026-11-22',
    );
    final second = await repository.editRecurringSchedule(
      shifted.id,
      draft: timedDraft(
        title: '再后移两天',
        startsAt: DateTime.utc(2026, 11, 26, 1),
      ),
      scope: ScheduleRepeatScope.thisAndFuture,
    );
    expect(second.rule.reminderMinutesBefore, 45);

    rows = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 15),
      to: DateTime.utc(2026, 12, 10),
    );
    final shiftedIdentities = rows
        .map((schedule) => schedule.recurrenceDate)
        .toList();
    expect(shiftedIdentities.toSet(), hasLength(shiftedIdentities.length));
    expect(
      shiftedIdentities.toSet(),
      containsAll({for (var day = 16; day <= 30; day++) '2026-11-$day'}),
    );
    expect(
      {
        for (final schedule in rows)
          if (schedule.recurrenceDate!.compareTo('2026-11-16') >= 0 &&
              schedule.recurrenceDate!.compareTo('2026-11-30') <= 0)
            schedule.recurrenceDate!: schedule.startsAt,
      },
      {
        for (var day = 16; day <= 30; day++)
          '2026-11-$day': DateTime.utc(
            2026,
            11,
            day <= 17 ? day : (day <= 21 ? day + 2 : day + 4),
            1,
          ),
      },
    );
    expect(
      rows
          .where(
            (schedule) => schedule.recurrenceDate!.compareTo('2026-11-18') >= 0,
          )
          .map((schedule) => schedule.reminderMinutesBefore)
          .toSet(),
      {45},
    );
    expect(
      rows
          .where(
            (schedule) => schedule.recurrenceDate!.compareTo('2026-11-18') < 0,
          )
          .map((schedule) => schedule.reminderMinutesBefore)
          .toSet(),
      {30},
    );
    expect(
      await repository.expandRecurrences(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 12, 10),
      ),
      0,
    );
    expect(await database.select(database.focusSessions).get(), isEmpty);
  });
}

Future<void> _seedTask(
  PactaDatabase database, {
  required String id,
  required String title,
  required String userId,
}) async {
  final now = DateTime.utc(2026, 11, 15);
  await database
      .into(database.localTasks)
      .insert(
        LocalTasksCompanion.insert(
          userId: userId,
          id: id,
          goalId: 'goal-a',
          title: title,
          classification: 'regular',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<Map<String?, int?>> _remindersByDate(
  LocalScheduleRepository repository,
) async {
  final schedules = await repository.getSchedules(
    from: DateTime.utc(2026, 11, 15),
    to: DateTime.utc(2026, 11, 23),
  );
  return {
    for (final schedule in schedules)
      schedule.recurrenceDate: schedule.reminderMinutesBefore,
  };
}
