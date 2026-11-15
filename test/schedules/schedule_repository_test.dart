import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
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

  test(
    'creates an owned schedule without a task and lists it in a window',
    () async {
      final schedule = await repository.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 10),
            endsAt: DateTime.utc(2026, 11, 16, 11),
          ),
        ),
      );

      expect(schedule.id, isNotEmpty);
      expect(schedule.title, '取快递');
      expect(schedule.taskId, isNull);
      expect(schedule.origin, ScheduleOrigin.owned);
      expect(schedule.isCompleted, isFalse);
      expect(schedule.hasReminder, isFalse);
      expect(schedule.startsAt, DateTime.utc(2026, 11, 16, 10));
      expect(schedule.endsAt, DateTime.utc(2026, 11, 16, 11));

      final listed = await repository.getSchedules();
      expect(listed.map((item) => item.id), [schedule.id]);
      expect(
        await repository.getSchedules(
          from: DateTime.utc(2026, 11, 17),
          to: DateTime.utc(2026, 11, 18),
        ),
        isEmpty,
      );
    },
  );

  test(
    'links a schedule to an existing task and rejects an unknown task',
    () async {
      await _seedTask(database, id: 'task-a', title: '写周报');

      final linked = await repository.createSchedule(
        ScheduleDraft(
          title: '写周报',
          taskId: 'task-a',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 9),
            endsAt: DateTime.utc(2026, 11, 16, 10),
          ),
        ),
      );

      expect(linked.taskId, 'task-a');
      await expectLater(
        repository.createSchedule(
          ScheduleDraft(
            title: '不存在的任务',
            taskId: 'task-missing',
            window: ScheduleWindow.timed(
              startsAt: DateTime.utc(2026, 11, 16, 9),
              endsAt: DateTime.utc(2026, 11, 16, 10),
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('edits a schedule without changing its identity', () async {
    final created = await repository.createSchedule(
      ScheduleDraft(
        title: '取快递',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 10),
          endsAt: DateTime.utc(2026, 11, 16, 11),
        ),
      ),
    );

    final edited = await repository.updateSchedule(
      created.id,
      ScheduleDraft(
        title: '  取快递（带取件码） ',
        notes: '  驿站 18:00 前  ',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 10),
          endsAt: DateTime.utc(2026, 11, 16, 11),
        ),
      ),
    );

    expect(edited.id, created.id);
    expect(edited.title, '取快递（带取件码）');
    expect(edited.notes, '驿站 18:00 前');
    expect(edited.createdAt, created.createdAt);
    expect(edited.updatedAt.isBefore(created.updatedAt), isFalse);
    expect((await repository.getSchedules()).single.title, '取快递（带取件码）');

    await expectLater(
      repository.updateSchedule(
        'missing-schedule',
        ScheduleDraft(
          title: '不存在',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 10),
            endsAt: DateTime.utc(2026, 11, 16, 11),
          ),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'reschedules a schedule while keeping its content and identity',
    () async {
      final created = await repository.createSchedule(
        ScheduleDraft(
          title: '看牙医',
          notes: '带医保卡',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 10),
            endsAt: DateTime.utc(2026, 11, 16, 11),
          ),
        ),
      );

      final moved = await repository.rescheduleSchedule(
        created.id,
        ScheduleWindow.allDayDates(
          startDate: '2026-11-18',
          endDateExclusive: '2026-11-19',
        ),
      );

      expect(moved.id, created.id);
      expect(moved.title, '看牙医');
      expect(moved.notes, '带医保卡');
      expect(moved.allDay, isTrue);
      expect(moved.allDayStartDate, '2026-11-18');
      expect(moved.allDayEndDateExclusive, '2026-11-19');
      expect(moved.startsAt, DateTime.utc(2026, 11, 18));
      expect(moved.endsAt, DateTime.utc(2026, 11, 19));
      expect(moved.createdAt, created.createdAt);
      expect(moved.updatedAt.isBefore(created.updatedAt), isFalse);
      expect((await repository.getSchedules()).single.allDay, isTrue);
    },
  );

  test(
    'completes and reopens a schedule without touching focus or task data',
    () async {
      await _seedTask(database, id: 'task-a', title: '写周报');
      final created = await repository.createSchedule(
        ScheduleDraft(
          title: '写周报',
          taskId: 'task-a',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 9),
            endsAt: DateTime.utc(2026, 11, 16, 10),
          ),
        ),
      );

      final completed = await repository.setScheduleCompletion(
        created.id,
        isCompleted: true,
      );

      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect(completed.taskId, 'task-a');
      expect(await database.select(database.focusSessions).get(), isEmpty);
      expect(await database.select(database.focusAppointments).get(), isEmpty);
      expect(await database.select(database.focusChainRecords).get(), isEmpty);
      expect(
        await database.select(database.appointmentChainRecords).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.localTasks).get()).single.isComplete,
        isFalse,
      );

      final reopened = await repository.setScheduleCompletion(
        created.id,
        isCompleted: false,
      );
      expect(reopened.isCompleted, isFalse);
      expect(reopened.completedAt, isNull);
    },
  );

  test(
    'a missed schedule stays in place and is never judged by chain records',
    () async {
      final missed = await repository.createSchedule(
        ScheduleDraft(
          title: '上周的体检',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 10, 9),
            endsAt: DateTime.utc(2026, 11, 10, 10),
          ),
        ),
      );

      final now = DateTime.utc(2026, 11, 15, 1);
      expect(missed.isOverdueAt(now), isTrue);
      final listed = await repository.getSchedules();
      expect(listed.single.id, missed.id);
      expect(listed.single.isCompleted, isFalse);
      expect(listed.single.startsAt, DateTime.utc(2026, 11, 10, 9));
      expect(listed.single.endsAt, DateTime.utc(2026, 11, 10, 10));
      expect(await database.select(database.focusSessions).get(), isEmpty);
      expect(await database.select(database.focusChainRecords).get(), isEmpty);
      expect(
        await database.select(database.appointmentChainRecords).get(),
        isEmpty,
      );
    },
  );

  test(
    'stores an optional reminder offset and rejects out-of-range offsets',
    () async {
      final created = await repository.createSchedule(
        ScheduleDraft(
          title: '交材料',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 9),
            endsAt: DateTime.utc(2026, 11, 16, 10),
          ),
        ),
      );
      expect(created.hasReminder, isFalse);

      final reminded = await repository.setScheduleReminder(
        created.id,
        minutesBefore: 15,
      );
      expect(reminded.hasReminder, isTrue);
      expect(reminded.reminderMinutesBefore, 15);
      expect(
        (await repository.getSchedules()).single.reminderMinutesBefore,
        15,
      );

      final cleared = await repository.setScheduleReminder(
        created.id,
        minutesBefore: null,
      );
      expect(cleared.hasReminder, isFalse);

      await expectLater(
        repository.setScheduleReminder(created.id, minutesBefore: -1),
        throwsArgumentError,
      );
      await expectLater(
        repository.setScheduleReminder(created.id, minutesBefore: 10081),
        throwsArgumentError,
      );
    },
  );

  test('deletes a schedule and reports the change to watchers', () async {
    final created = await repository.createSchedule(
      ScheduleDraft(
        title: '临时事项',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
        ),
      ),
    );

    final emissions = <List<Schedule>>[];
    final subscription = repository.watchSchedules().listen(emissions.add);
    await pumpEventQueue();
    expect(emissions.single.single.id, created.id);

    await repository.deleteSchedule(created.id);
    await pumpEventQueue();
    expect(emissions.last, isEmpty);
    expect(await repository.getSchedules(), isEmpty);
    await subscription.cancel();

    await expectLater(
      repository.deleteSchedule(created.id),
      throwsA(isA<StateError>()),
    );
  });

  test('keeps schedules isolated per account', () async {
    final otherUser = LocalScheduleRepository(
      database: database,
      userId: 'user-b',
      now: () => DateTime.utc(2026, 11, 15, 2),
    );
    addTearDown(otherUser.dispose);
    final mine = await repository.createSchedule(
      ScheduleDraft(
        title: '我的日程',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
        ),
      ),
    );
    expect(await otherUser.getSchedules(), isEmpty);

    final theirs = await otherUser.createSchedule(
      ScheduleDraft(
        title: '别人的日程',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
        ),
      ),
    );
    await repository.deleteSchedule(mine.id);
    expect((await otherUser.getSchedules()).single.id, theirs.id);
    expect(await repository.getSchedules(), isEmpty);
  });
}

Future<void> _seedTask(
  PactaDatabase database, {
  required String id,
  required String title,
}) async {
  final now = DateTime.utc(2026, 11, 15);
  await database
      .into(database.localTasks)
      .insert(
        LocalTasksCompanion.insert(
          userId: 'user-a',
          id: id,
          goalId: 'goal-a',
          title: title,
          classification: 'regular',
          createdAt: now,
          updatedAt: now,
        ),
      );
}
