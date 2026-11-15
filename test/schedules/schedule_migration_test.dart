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
    'promotes legacy calendar blocks once and keeps source identity for dedup',
    () async {
      await _seedSource(database, sourceId: 'source-a', name: '工作');
      await _seedSource(database, sourceId: 'source-b', name: '个人');
      await _seedBlock(
        database,
        sourceId: 'source-a',
        eventIdentity: 'event-1',
        occurrenceId: 'event-1:20261116',
        title: '周会',
        startsAt: DateTime.utc(2026, 11, 16, 1),
        endsAt: DateTime.utc(2026, 11, 16, 2),
      );
      await _seedBlock(
        database,
        sourceId: 'source-b',
        eventIdentity: 'event-1',
        occurrenceId: 'event-1:20261116',
        title: '周会',
        startsAt: DateTime.utc(2026, 11, 16, 1),
        endsAt: DateTime.utc(2026, 11, 16, 2),
      );
      await _seedBlock(
        database,
        sourceId: 'source-a',
        eventIdentity: 'event-2',
        occurrenceId: 'event-2:20261117',
        title: '体检',
        startsAt: DateTime.utc(2026, 11, 17, 3),
        endsAt: DateTime.utc(2026, 11, 17, 4),
      );

      final result = await repository.promoteLegacyCalendarBlocks();

      expect(result.alreadyPromoted, isFalse);
      expect(result.sourceBlockCount, 3);
      expect(result.promotedCount, 2);
      final schedules = await repository.getSchedules();
      expect(schedules, hasLength(2));
      final meeting = schedules.firstWhere(
        (schedule) => schedule.eventIdentity == 'event-1',
      );
      expect(meeting.title, '周会');
      expect(meeting.origin, ScheduleOrigin.legacyCalendarBlock);
      expect(meeting.sourceIds, ['source-a', 'source-b']);
      expect(meeting.sourceNames, ['工作', '个人']);
      expect(meeting.sourceEventId, 'event-1');
      expect(meeting.occurrenceId, 'event-1:20261116');
      expect(meeting.taskId, isNull);
      expect(meeting.isCompleted, isFalse);

      final status = await repository.getLegacyMigrationStatus();
      expect(status.hasCompletedMigration, isTrue);
      expect(status.canRollback, isTrue);
      expect(status.promotedCount, 2);

      final again = await repository.promoteLegacyCalendarBlocks();
      expect(again.alreadyPromoted, isTrue);
      expect(again.promotedCount, 2);
      expect(await repository.getSchedules(), hasLength(2));
    },
  );

  test('keeps user edits when promotion is requested again', () async {
    await _seedSource(database, sourceId: 'source-a', name: '工作');
    await _seedBlock(
      database,
      sourceId: 'source-a',
      eventIdentity: 'event-1',
      occurrenceId: 'event-1:20261116',
      title: '周会',
      startsAt: DateTime.utc(2026, 11, 16, 1),
      endsAt: DateTime.utc(2026, 11, 16, 2),
    );
    final promoted = (await repository.promoteLegacyCalendarBlocks());
    expect(promoted.promotedCount, 1);
    final schedule = (await repository.getSchedules()).single;

    final edited = await repository.updateSchedule(
      schedule.id,
      ScheduleDraft(
        title: '周会（改到下午）',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 6),
          endsAt: DateTime.utc(2026, 11, 16, 7),
        ),
      ),
    );
    expect(edited.sourceIds, ['source-a']);
    expect(edited.eventIdentity, 'event-1');

    await repository.promoteLegacyCalendarBlocks();
    final after = (await repository.getSchedules()).single;
    expect(after.title, '周会（改到下午）');
    expect(after.startsAt, DateTime.utc(2026, 11, 16, 6));
  });

  test(
    'rolls back a promotion without deleting the calendar block copies',
    () async {
      await _seedSource(database, sourceId: 'source-a', name: '工作');
      await _seedBlock(
        database,
        sourceId: 'source-a',
        eventIdentity: 'event-1',
        occurrenceId: 'event-1:20261116',
        title: '周会',
        startsAt: DateTime.utc(2026, 11, 16, 1),
        endsAt: DateTime.utc(2026, 11, 16, 2),
      );
      await _seedBlock(
        database,
        sourceId: 'source-a',
        eventIdentity: 'event-2',
        occurrenceId: 'event-2:20261117',
        title: '体检',
        startsAt: DateTime.utc(2026, 11, 17, 3),
        endsAt: DateTime.utc(2026, 11, 17, 4),
      );
      await repository.promoteLegacyCalendarBlocks();

      final rollback = await repository.rollbackLegacyCalendarBlockPromotion();

      expect(rollback.removedSchedules, 2);
      expect(rollback.restoredBlocks, 2);
      expect(await repository.getSchedules(), isEmpty);
      expect(
        await database.select(database.localCalendarBlocks).get(),
        hasLength(2),
      );
      final status = await repository.getLegacyMigrationStatus();
      expect(status.hasCompletedMigration, isFalse);
      expect(status.isRolledBack, isTrue);
      expect(status.canRollback, isFalse);

      final again = await repository.promoteLegacyCalendarBlocks();
      expect(again.alreadyPromoted, isFalse);
      expect(again.promotedCount, 2);
    },
  );

  test(
    'removing a source calendar copy never deletes the promoted schedule',
    () async {
      await _seedSource(database, sourceId: 'source-a', name: '工作');
      await _seedBlock(
        database,
        sourceId: 'source-a',
        eventIdentity: 'event-1',
        occurrenceId: 'event-1:20261116',
        title: '周会',
        startsAt: DateTime.utc(2026, 11, 16, 1),
        endsAt: DateTime.utc(2026, 11, 16, 2),
      );
      await repository.promoteLegacyCalendarBlocks();

      // Source removal (permission revoked or calendar deselected) only touches
      // the imported copies; owned schedules stay.
      await (database.delete(
        database.localCalendarBlocks,
      )..where((row) => row.userId.equals('user-a'))).go();
      await (database.delete(
        database.localCalendarSources,
      )..where((row) => row.userId.equals('user-a'))).go();

      final schedule = (await repository.getSchedules()).single;
      expect(schedule.title, '周会');
      expect(schedule.origin, ScheduleOrigin.legacyCalendarBlock);
      expect(schedule.sourceIds, ['source-a']);
    },
  );

  test('reports no rollback when no promotion happened', () async {
    await expectLater(
      repository.rollbackLegacyCalendarBlockPromotion(),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _seedSource(
  PactaDatabase database, {
  required String sourceId,
  required String name,
}) async {
  await database
      .into(database.localCalendarSources)
      .insert(
        LocalCalendarSourcesCompanion.insert(
          userId: 'user-a',
          sourceId: sourceId,
          displayName: name,
          timeZoneId: 'Asia/Shanghai',
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
      );
}

Future<void> _seedBlock(
  PactaDatabase database, {
  required String sourceId,
  required String eventIdentity,
  required String occurrenceId,
  required String title,
  required DateTime startsAt,
  required DateTime endsAt,
}) async {
  await database
      .into(database.localCalendarBlocks)
      .insert(
        LocalCalendarBlocksCompanion.insert(
          userId: 'user-a',
          sourceId: sourceId,
          sourceEventId: eventIdentity,
          occurrenceId: occurrenceId,
          eventIdentity: eventIdentity,
          title: title,
          startsAt: startsAt,
          endsAt: endsAt,
          availability: 'busy',
          timeZoneId: 'Asia/Shanghai',
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
      );
}
