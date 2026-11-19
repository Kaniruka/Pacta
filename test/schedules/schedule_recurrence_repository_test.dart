import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

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
  }) {
    final start = startsAt ?? DateTime.utc(2026, 11, 16, 1);
    return ScheduleDraft(
      title: title,
      window: ScheduleWindow.timed(
        startsAt: start,
        endsAt: start.add(Duration(minutes: minutes)),
      ),
    );
  }

  Future<List<Schedule>> window(DateTime from, DateTime to) =>
      repository.getSchedules(from: from, to: to);

  String label(Schedule schedule) =>
      '${schedule.recurrenceDate}:${schedule.title}';

  test('每天：展开到结束日期当天并保留规则时区的挂钟时刻', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    expect(series.rule.firstDate, '2026-11-16');
    expect(series.rule.endDate, '2026-11-18');
    expect(series.rule.timeZoneId, 'Asia/Shanghai');
    expect(series.rule.startMinutesOfDay, 9 * 60);
    expect(series.occurrences.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-17',
      '2026-11-18',
    ]);
    expect(series.occurrences.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 16, 1),
      DateTime.utc(2026, 11, 17, 1),
      DateTime.utc(2026, 11, 18, 1),
    ]);
    expect(
      series.occurrences.every(
        (schedule) =>
            schedule.isRecurring &&
            schedule.recurrenceId == series.rule.id &&
            schedule.recurrenceSeriesId == series.rule.id &&
            schedule.recurrenceTimeZoneId == 'Asia/Shanghai',
      ),
      isTrue,
    );

    final rules = await repository.getRecurrenceRules();
    expect(rules, hasLength(1));
    expect(rules.single, series.rule);
  });

  test('每周指定星期：只展开选中的星期', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {1, 3},
        endDate: '2026-11-25',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    expect(series.occurrences.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-18',
      '2026-11-23',
      '2026-11-25',
    ]);
    expect(series.rule.weekdays, {1, 3});
  });

  test('跨年：日历推进不因年末而中断', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(startsAt: DateTime.utc(2026, 12, 30, 1)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2027-01-02',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    expect(series.occurrences.map((schedule) => schedule.recurrenceDate), [
      '2026-12-30',
      '2026-12-31',
      '2027-01-01',
      '2027-01-02',
    ]);
  });

  test('全天日程：每个实例占满自己的日历日', () async {
    final series = await repository.createRecurringSchedule(
      draft: ScheduleDraft(
        title: '值班',
        window: ScheduleWindow.allDayDates(
          startDate: '2026-11-16',
          endDateExclusive: '2026-11-17',
        ),
      ),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    expect(series.occurrences.map((schedule) => schedule.allDayStartDate), [
      '2026-11-16',
      '2026-11-17',
      '2026-11-18',
    ]);
    expect(series.occurrences.every((schedule) => schedule.allDay), isTrue);
  });

  test('按规则时区的夏令时展开，不读取账号显示时区', () async {
    await database
        .into(database.focusPreferences)
        .insert(
          FocusPreferencesCompanion.insert(
            userId: 'user-a',
            lastMode: 'regular',
            displayTimeZoneId: const Value('Asia/Tokyo'),
          ),
        );

    final series = await repository.createRecurringSchedule(
      draft: timedDraft(startsAt: DateTime.utc(2026, 3, 7, 14)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-03-09',
      ),
      timeZoneId: 'America/New_York',
    );

    expect(series.occurrences.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 3, 7, 14),
      DateTime.utc(2026, 3, 8, 13),
      DateTime.utc(2026, 3, 9, 13),
    ]);
  });

  test('仅本次：只改写该实例，落库为例外且不被再次展开覆盖', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
    );
    final target = series.occurrences[1];

    final result = await repository.editRecurringSchedule(
      target.id,
      draft: timedDraft(
        title: '一对一',
        startsAt: DateTime.utc(2026, 11, 17, 2),
        minutes: 30,
      ),
      scope: ScheduleRepeatScope.onlyThis,
    );

    expect(result.updated.title, '一对一');
    expect(result.updated.isRecurrenceException, isTrue);
    expect(result.updated.recurrenceDate, '2026-11-17');
    expect(result.rule, series.rule);
    expect(result.truncatedRule, isNull);

    final expanded = await repository.expandRecurrences(
      from: DateTime.utc(2026, 11, 15),
      to: DateTime.utc(2026, 11, 20),
    );
    expect(expanded, 0);

    final schedules = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 20),
    );
    expect(schedules.map(label), [
      '2026-11-16:周会',
      '2026-11-17:一对一',
      '2026-11-18:周会',
    ]);
  });

  test('本次及以后：截断原规则、从该实例起新建规则，过去实例原样保留', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
    );
    await repository.setScheduleCompletion(
      series.occurrences.first.id,
      isCompleted: true,
    );

    final result = await repository.editRecurringSchedule(
      series.occurrences[1].id,
      // 只改内容：草稿窗口仍落在该实例自己的日期上。
      draft: timedDraft(title: '新周会', startsAt: series.occurrences[1].startsAt),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    expect(result.truncatedRule, isNotNull);
    expect(result.truncatedRule!.id, series.rule.id);
    expect(result.truncatedRule!.endDate, '2026-11-16');
    expect(result.rule.id, isNot(series.rule.id));
    expect(result.rule.firstDate, '2026-11-17');
    expect(result.rule.endDate, '2026-11-18');

    final rules = await repository.getRecurrenceRules();
    expect(rules, hasLength(2));
    expect(
      rules.firstWhere((rule) => rule.id == series.rule.id).endDate,
      '2026-11-16',
    );

    final schedules = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 20),
    );
    expect(schedules.map(label), [
      '2026-11-16:周会',
      '2026-11-17:新周会',
      '2026-11-18:新周会',
    ]);
    expect(schedules.first.isCompleted, isTrue);
    expect(schedules.first.recurrenceSeriesId, series.rule.id);
    expect(schedules[1].recurrenceId, result.rule.id);
    expect(schedules[1].recurrenceSeriesId, series.rule.id);
  });

  test('本次及以后从首个实例起改：原规则整体被替换', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    final result = await repository.editRecurringSchedule(
      series.occurrences.first.id,
      draft: timedDraft(title: '新周会'),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    final rules = await repository.getRecurrenceRules();
    expect(rules, hasLength(1));
    expect(rules.single.id, result.rule.id);

    final schedules = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 20),
    );
    expect(schedules.map((schedule) => schedule.title), ['新周会', '新周会', '新周会']);
  });

  test('删除单个实例后不再被展开复活', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-18',
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    await repository.deleteSchedule(series.occurrences[1].id);

    final schedules = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 20),
    );
    expect(schedules.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-18',
    ]);

    final expanded = await repository.expandRecurrences(
      from: DateTime.utc(2026, 11, 15),
      to: DateTime.utc(2026, 11, 20),
    );
    expect(expanded, 0);
    expect(
      await window(DateTime.utc(2026, 11, 15), DateTime.utc(2026, 11, 20)),
      hasLength(2),
    );
  });

  test('本次及以后改写不复活已删除的实例', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
        endDate: '2026-11-20',
      ),
      timeZoneId: 'Asia/Shanghai',
    );
    await repository.deleteSchedule(series.occurrences[1].id);

    await repository.editRecurringSchedule(
      series.occurrences.first.id,
      draft: timedDraft(title: '新周会'),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    final schedules = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 11, 21),
    );
    expect(schedules.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-18',
      '2026-11-19',
      '2026-11-20',
    ]);
  });

  test('读取范围按需补齐实例，且超出上限整体拒绝', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Asia/Shanghai',
    );
    expect(series.occurrences, hasLength(recurrenceMaterializationHorizonDays));
    expect(series.occurrences.last.recurrenceDate, '2027-02-13');

    final march = await window(
      DateTime.utc(2027, 3, 1),
      DateTime.utc(2027, 4, 1),
    );
    expect(march, hasLength(31));
    expect(march.first.recurrenceDate, '2027-03-01');
    expect(march.last.recurrenceDate, '2027-03-31');

    expect(
      () => repository.expandRecurrences(
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2028, 1, 1),
      ),
      throwsArgumentError,
    );
  });

  test('宽范围读取按分片补齐，不因跨度超过单次上限而失败', () async {
    await repository.createRecurringSchedule(
      draft: timedDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    final wide = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 16),
      to: DateTime.utc(2028, 3, 1),
    );

    expect(wide, isNotEmpty);
    expect(
      wide.map((schedule) => schedule.recurrenceDate).toSet(),
      hasLength(wide.length),
    );
  });

  test('非重复日程保持既有行为', () async {
    final plain = await repository.createSchedule(timedDraft());

    expect(plain.isRecurring, isFalse);
    expect(plain.isRecurrenceException, isFalse);
    expect(await repository.getRecurrenceRules(), isEmpty);
    expect(
      await repository.expandRecurrences(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 20),
      ),
      0,
    );
  });

  test('本次及以后改到另一天：实例与后续实例真的移动到新日期', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(startsAt: DateTime.utc(2026, 11, 16, 1)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {DateTime.monday},
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    final result = await repository.editRecurringSchedule(
      series.occurrences.first.id,
      draft: timedDraft(
        title: '改期周会',
        startsAt: DateTime.utc(2026, 11, 18, 2),
        minutes: 45,
      ),
      scope: ScheduleRepeatScope.thisAndFuture,
    );

    expect(result.updated.startsAt, DateTime.utc(2026, 11, 18, 2));
    expect(result.updated.endsAt, DateTime.utc(2026, 11, 18, 2, 45));
    // 可见日期右移，原始发生身份不漂移。
    expect(result.updated.recurrenceDate, '2026-11-16');
    expect(result.rule.firstDate, '2026-11-18');
    expect(result.rule.shiftDays, 2);
    expect(result.rule.originalFirstDate, '2026-11-16');
    expect(result.rule.weekdays, {DateTime.wednesday});
    expect(result.truncatedRule, isNull);

    final schedules = await window(
      DateTime.utc(2026, 11, 15),
      DateTime.utc(2026, 12, 10),
    );
    expect(schedules.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 18, 2),
      DateTime.utc(2026, 11, 25, 2),
      DateTime.utc(2026, 12, 2, 2),
      DateTime.utc(2026, 12, 9, 2),
    ]);
    expect(schedules.map((schedule) => schedule.recurrenceDate), [
      '2026-11-16',
      '2026-11-23',
      '2026-11-30',
      '2026-12-07',
    ]);
  });

  test('先按较晚实例分段、再按较早实例分段：被取代的较晚规则不再生成实例', () async {
    final series = await repository.createRecurringSchedule(
      draft: timedDraft(startsAt: DateTime.utc(2026, 11, 2, 1)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {DateTime.monday},
      ),
      timeZoneId: 'Asia/Shanghai',
    );

    // 1) 先按 11-30 那一期改到每周二。
    await repository.editRecurringSchedule(
      series.occurrences[4].id,
      draft: timedDraft(startsAt: DateTime.utc(2026, 12, 1, 2)),
      scope: ScheduleRepeatScope.thisAndFuture,
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {DateTime.tuesday},
      ),
    );

    // 2) 再按更早的 11-23 那一期改到每周三：更晚的分段必须一起让位。
    await repository.editRecurringSchedule(
      series.occurrences[3].id,
      draft: timedDraft(startsAt: DateTime.utc(2026, 11, 25, 3)),
      scope: ScheduleRepeatScope.thisAndFuture,
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.weekly,
        weekdays: {DateTime.wednesday},
      ),
    );

    final rules = await repository.getRecurrenceRules();
    expect(rules, hasLength(2));
    final ordered = [...rules]
      ..sort((left, right) => left.firstDate.compareTo(right.firstDate));
    expect(ordered.first.id, series.rule.id);
    expect(ordered.first.endDate, '2026-11-22');
    expect(ordered.last.firstDate, '2026-11-25');

    final firstRead = await window(
      DateTime.utc(2026, 11, 1),
      DateTime.utc(2026, 12, 20),
    );
    expect(firstRead.map((schedule) => schedule.startsAt), [
      DateTime.utc(2026, 11, 2, 1),
      DateTime.utc(2026, 11, 9, 1),
      DateTime.utc(2026, 11, 16, 1),
      DateTime.utc(2026, 11, 25, 3),
      DateTime.utc(2026, 12, 2, 3),
      DateTime.utc(2026, 12, 9, 3),
      DateTime.utc(2026, 12, 16, 3),
    ]);
    // 身份按原始发生日期稳定：25 号那一期仍是 23 号的身份。
    expect(firstRead.map((schedule) => schedule.recurrenceDate), [
      '2026-11-02',
      '2026-11-09',
      '2026-11-16',
      '2026-11-23',
      '2026-11-30',
      '2026-12-07',
      '2026-12-14',
    ]);

    // 再次展开不得新增任何实例。
    final secondRead = await window(
      DateTime.utc(2026, 11, 1),
      DateTime.utc(2026, 12, 20),
    );
    expect(
      secondRead.map((schedule) => schedule.id).toSet(),
      firstRead.map((schedule) => schedule.id).toSet(),
    );
  });
}
