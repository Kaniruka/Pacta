import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  test('account purge removes schedules and their migration copies', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    try {
      await database
          .into(database.localCalendarSources)
          .insert(
            LocalCalendarSourcesCompanion.insert(
              userId: 'user-a',
              sourceId: 'calendar-1',
              displayName: '工作',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );
      await database
          .into(database.localCalendarBlocks)
          .insert(
            LocalCalendarBlocksCompanion.insert(
              userId: 'user-a',
              sourceId: 'calendar-1',
              sourceEventId: 'event-1',
              occurrenceId: 'event-1:20261116',
              eventIdentity: 'event-1',
              title: '周会',
              startsAt: DateTime.utc(2026, 11, 16, 1),
              endsAt: DateTime.utc(2026, 11, 16, 2),
              availability: 'busy',
              timeZoneId: 'Asia/Shanghai',
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );
      await repository.promoteLegacyCalendarBlocks();
      await repository.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 17, 10),
            endsAt: DateTime.utc(2026, 11, 17, 11),
          ),
        ),
      );
      expect(await database.localUserIdsWithData(), contains('user-a'));

      final purged = await database.purgeUserDataForReceipt(
        userId: 'user-a',
        receipt: UserPurgeReceipt(
          userId: 'user-a',
          status: UserPurgeStatus.completed,
          purgedAt: DateTime.utc(2026, 11, 15),
        ),
      );

      expect(purged, isTrue);
      expect(await database.select(database.localSchedules).get(), isEmpty);
      expect(
        await database.select(database.localScheduleMigrations).get(),
        isEmpty,
      );
      expect(
        await database.select(database.localCalendarBlocks).get(),
        isEmpty,
      );
      expect(await database.localUserIdsWithData(), isNot(contains('user-a')));
    } finally {
      await repository.dispose();
      await database.close();
    }
  });
}
