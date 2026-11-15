import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// The merged local schema is 31: the owned schedule tables (ticket 03) and the
/// explicit appointment preparation duration (ticket 08) have to coexist.
///
/// Both tickets shipped an incomplete schema 30 on its own, so an upgrade must
/// add only what a database is missing and never rebuild or clear stored rows.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const userId = 'user-a';
  final startsAt = DateTime.utc(2026, 11, 16, 1);
  final endsAt = startsAt.add(const Duration(hours: 1));
  final updatedAt = DateTime.utc(2026, 11, 15, 2);

  Future<void> seedCalendarBlock(PactaDatabase database) async {
    await database
        .into(database.localCalendarSources)
        .insert(
          LocalCalendarSourcesCompanion.insert(
            userId: userId,
            sourceId: 'calendar-1',
            displayName: '工作',
            timeZoneId: 'Asia/Shanghai',
            updatedAt: updatedAt,
          ),
        );
    await database
        .into(database.localCalendarBlocks)
        .insert(
          LocalCalendarBlocksCompanion.insert(
            userId: userId,
            sourceId: 'calendar-1',
            sourceEventId: 'event-1',
            occurrenceId: 'event-1:20261116',
            eventIdentity: 'event-1:20261116',
            title: '周会',
            startsAt: startsAt,
            endsAt: endsAt,
            availability: 'busy',
            timeZoneId: 'Asia/Shanghai',
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> seedAppointment(
    PactaDatabase database, {
    required int? preparationSeconds,
  }) async {
    await database
        .into(database.focusAppointments)
        .insert(
          FocusAppointmentsCompanion.insert(
            userId: userId,
            id: 'appointment-1',
            taskId: 'task-1',
            mode: FocusChainMode.regular.storageValue,
            durationSeconds: 30 * 60,
            startedAt: startsAt,
            endsAt: endsAt,
            status: AppointmentPreparationStatus.active.storageValue,
            updatedAt: updatedAt,
            preparationSeconds: Value(preparationSeconds),
          ),
        );
  }

  /// Rebuilds focus_appointments without preparation_seconds and keeps every
  /// stored row: the ticket 03 shape of schema 30.
  Future<void> dropPreparationColumn(PactaDatabase database) async {
    await database.customStatement('''
      CREATE TABLE focus_appointments_v30 (
        user_id TEXT NOT NULL,
        id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        mode TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        started_at INTEGER NOT NULL,
        ends_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        settled_at INTEGER,
        session_id TEXT,
        failure_reason TEXT,
        updated_at INTEGER NOT NULL,
        review_disposition TEXT NOT NULL DEFAULT 'accepted',
        review_disposition_updated_at INTEGER,
        configuration_basis_source_id TEXT,
        PRIMARY KEY (user_id, id)
      )
    ''');
    await database.customStatement('''
      INSERT INTO focus_appointments_v30 (
        user_id, id, task_id, mode, duration_seconds, started_at, ends_at,
        status, settled_at, session_id, failure_reason, updated_at,
        review_disposition, review_disposition_updated_at,
        configuration_basis_source_id
      )
      SELECT
        user_id, id, task_id, mode, duration_seconds, started_at, ends_at,
        status, settled_at, session_id, failure_reason, updated_at,
        review_disposition, review_disposition_updated_at,
        configuration_basis_source_id
      FROM focus_appointments
    ''');
    await database.customStatement('DROP TABLE focus_appointments');
    await database.customStatement(
      'ALTER TABLE focus_appointments_v30 RENAME TO focus_appointments',
    );
  }

  Future<Set<String>> tableNames(PactaDatabase database) async {
    final rows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<Set<String>> appointmentColumns(PactaDatabase database) async {
    final rows = await database
        .customSelect('PRAGMA table_info(focus_appointments)')
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  test('schema 31 adds the schedule tables to the ticket 08 shape and promotes blocks', () async {
    final directory = await Directory.systemTemp.createTemp('pacta-s31-08-');
    final file = File('${directory.path}/pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(file));
    try {
      await seedCalendarBlock(database);
      await seedAppointment(database, preparationSeconds: 420);
      // 08 发布的 30：准备列已在，日程表从来不存在。
      await database.customStatement('DROP TABLE local_schedules');
      await database.customStatement('DROP TABLE local_schedule_migrations');
      await database.customStatement('PRAGMA user_version = 30');
    } finally {
      await database.close();
    }

    database = PactaDatabase(NativeDatabase(file));
    try {
      expect(await tableNames(database), contains('local_schedules'));
      expect(await tableNames(database), contains('local_schedule_migrations'));

      final schedules = await database.select(database.localSchedules).get();
      expect(schedules, hasLength(1));
      expect(schedules.single.origin, ScheduleOrigin.legacyCalendarBlock.name);
      expect(schedules.single.sourceEventId, 'event-1');
      expect(schedules.single.eventIdentity, 'event-1:20261116');

      final markers = await database
          .select(database.localScheduleMigrations)
          .get();
      expect(markers, hasLength(1));
      expect(markers.single.promotedCount, 1);

      // 已存的准备时长和旧日历块都没有被重算或清空。
      final appointment =
          (await database.select(database.focusAppointments).get()).single;
      expect(appointment.preparationSeconds, 420);
      expect(
        await database.select(database.localCalendarBlocks).get(),
        hasLength(1),
      );
    } finally {
      await database.close();
    }

    // 再次打开不会重复提升。
    database = PactaDatabase(NativeDatabase(file));
    try {
      expect(
        await database.select(database.localSchedules).get(),
        hasLength(1),
      );
      expect(
        (await database.select(database.localScheduleMigrations).get())
            .single
            .promotedCount,
        1,
      );
    } finally {
      await database.close();
    }
    await directory.delete(recursive: true);
  });

  test(
    'schema 31 only adds preparation_seconds to the ticket 03 shape',
    () async {
      final directory = await Directory.systemTemp.createTemp('pacta-s31-03-');
      final file = File('${directory.path}/pacta.sqlite');
      var database = PactaDatabase(NativeDatabase(file));
      try {
        await seedCalendarBlock(database);
        await seedAppointment(database, preparationSeconds: null);
        await database
            .into(database.localSchedules)
            .insert(
              LocalSchedulesCompanion.insert(
                userId: userId,
                id: 'schedule-owned',
                title: '用户自己的日程',
                startsAt: startsAt,
                endsAt: endsAt,
                createdAt: updatedAt,
                updatedAt: updatedAt,
              ),
            );
        await database
            .into(database.localScheduleMigrations)
            .insert(
              LocalScheduleMigrationsCompanion.insert(
                userId: userId,
                migrationId: 'legacy-calendar-blocks-v1',
                status: ScheduleMigrationState.completed.storageValue,
                sourceBlockCount: 1,
                promotedCount: 1,
                backupPayload: '[]',
                createdAt: updatedAt,
                completedAt: updatedAt,
              ),
            );
        // 03 发布的 30：日程表已在，准备列从来不存在。
        await dropPreparationColumn(database);
        await database.customStatement('PRAGMA user_version = 30');
      } finally {
        await database.close();
      }

      database = PactaDatabase(NativeDatabase(file));
      try {
        expect(
          await appointmentColumns(database),
          contains('preparation_seconds'),
        );
        // 用户自己的日程、提升标记与旧日历块都原样保留，没有第二次提升。
        final schedules = await database.select(database.localSchedules).get();
        expect(schedules, hasLength(1));
        expect(schedules.single.id, 'schedule-owned');
        expect(schedules.single.origin, ScheduleOrigin.owned.name);
        final marker =
            (await database.select(database.localScheduleMigrations).get())
                .single;
        expect(marker.promotedCount, 1);
        expect(marker.sourceBlockCount, 1);
        final appointment =
            (await database.select(database.focusAppointments).get()).single;
        expect(appointment.preparationSeconds, isNull);
        // 旧的 15 分钟兜底口径由 appointment_preparation_migration_test 覆盖。
      } finally {
        await database.close();
      }
      await directory.delete(recursive: true);
    },
  );

  test(
    'schema 29 upgrades straight to the merged structure in one pass',
    () async {
      final directory = await Directory.systemTemp.createTemp('pacta-s31-29-');
      final file = File('${directory.path}/pacta.sqlite');
      var database = PactaDatabase(NativeDatabase(file));
      try {
        await seedCalendarBlock(database);
        await seedAppointment(database, preparationSeconds: null);
        await database.customStatement('DROP TABLE local_schedules');
        await database.customStatement('DROP TABLE local_schedule_migrations');
        await dropPreparationColumn(database);
        await database.customStatement('PRAGMA user_version = 29');
      } finally {
        await database.close();
      }

      database = PactaDatabase(NativeDatabase(file));
      try {
        expect(await tableNames(database), contains('local_schedules'));
        expect(
          await appointmentColumns(database),
          contains('preparation_seconds'),
        );
        final schedules = await database.select(database.localSchedules).get();
        expect(schedules, hasLength(1));
        expect(
          schedules.single.origin,
          ScheduleOrigin.legacyCalendarBlock.name,
        );
        expect(
          (await database.select(database.focusAppointments).get())
              .single
              .preparationSeconds,
          isNull,
        );
      } finally {
        await database.close();
      }
      await directory.delete(recursive: true);
    },
  );
}
