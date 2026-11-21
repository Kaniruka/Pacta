import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  test(
    'schema 29 upgrade promotes legacy calendar blocks into owned copies',
    () async {
      final timestamp =
          DateTime.utc(2026, 11, 1).millisecondsSinceEpoch ~/ 1000;
      final startsAt =
          DateTime.utc(2026, 11, 16, 1).millisecondsSinceEpoch ~/ 1000;
      final endsAt =
          DateTime.utc(2026, 11, 16, 2).millisecondsSinceEpoch ~/ 1000;
      final database = PactaDatabase(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase.execute('''
              CREATE TABLE local_calendar_sources (
                user_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                time_zone_id TEXT NOT NULL,
                local_calendar_id TEXT,
                is_selected INTEGER NOT NULL DEFAULT 0,
                is_stale INTEGER NOT NULL DEFAULT 0,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (user_id, source_id)
              )
            ''');
            rawDatabase.execute('''
              CREATE TABLE local_calendar_blocks (
                user_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_event_id TEXT NOT NULL,
                occurrence_id TEXT NOT NULL,
                event_identity TEXT NOT NULL,
                title TEXT NOT NULL,
                starts_at INTEGER NOT NULL,
                ends_at INTEGER NOT NULL,
                all_day INTEGER NOT NULL DEFAULT 0,
                all_day_start_date TEXT,
                all_day_end_date_exclusive TEXT,
                availability TEXT NOT NULL,
                time_zone_id TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (user_id, source_id, occurrence_id)
              )
            ''');
            rawDatabase.execute(
              '''
              INSERT INTO local_calendar_sources
                (user_id, source_id, display_name, time_zone_id, updated_at)
              VALUES (?, ?, ?, ?, ?)
            ''',
              ['user-a', 'calendar-1', '工作', 'Asia/Shanghai', timestamp],
            );
            for (final event in [
              ('event-1', 'event-1:20261116', '周会', startsAt, endsAt),
              (
                'event-2',
                'event-2:20261117',
                '体检',
                startsAt + 86400,
                endsAt + 86400,
              ),
            ]) {
              rawDatabase.execute(
                '''
                INSERT INTO local_calendar_blocks
                  (user_id, source_id, source_event_id, occurrence_id,
                   event_identity, title, starts_at, ends_at, availability,
                   time_zone_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ''',
                [
                  'user-a',
                  'calendar-1',
                  event.$1,
                  event.$2,
                  event.$1,
                  event.$3,
                  event.$4,
                  event.$5,
                  'busy',
                  'Asia/Shanghai',
                  timestamp,
                ],
              );
            }
            rawDatabase.execute('PRAGMA user_version = 29');
          },
        ),
      );

      try {
        final repository = LocalScheduleRepository(
          database: database,
          userId: 'user-a',
          now: () => DateTime.utc(2026, 11, 15, 1),
        );
        final schedules = await repository.getSchedules();
        expect(schedules, hasLength(2));
        expect(
          schedules.every(
            (schedule) => schedule.origin == ScheduleOrigin.legacyCalendarBlock,
          ),
          isTrue,
        );
        expect(schedules.map((schedule) => schedule.sourceIds.single).toSet(), {
          'calendar-1',
        });
        expect(schedules.map((schedule) => schedule.eventIdentity).toSet(), {
          'event-1',
          'event-2',
        });

        final runs = await database
            .select(database.localScheduleMigrations)
            .get();
        expect(runs, hasLength(1));
        expect(runs.single.backupPayload, contains('event-1'));

        await repository.dispose();
      } finally {
        await database.close();
      }
    },
  );
}
