import 'dart:convert';

import 'package:drift/drift.dart';

import '../tasks/task_database.dart';
import 'schedule_models.dart';

/// One legacy calendar-block row, normalized for the one-time promotion into an
/// owned schedule copy.
class LegacyCalendarBlockProjection {
  const LegacyCalendarBlockProjection({
    required this.sourceId,
    required this.sourceEventId,
    required this.occurrenceId,
    required this.eventIdentity,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
  });

  factory LegacyCalendarBlockProjection.fromLocalRow(LocalCalendarBlock row) =>
      LegacyCalendarBlockProjection(
        sourceId: row.sourceId,
        sourceEventId: row.sourceEventId,
        occurrenceId: row.occurrenceId,
        eventIdentity: row.eventIdentity,
        title: row.title,
        startsAt: row.startsAt.toUtc(),
        endsAt: row.endsAt.toUtc(),
        allDay: row.allDay,
        allDayStartDate: row.allDayStartDate,
        allDayEndDateExclusive: row.allDayEndDateExclusive,
      );

  final String sourceId;
  final String sourceEventId;
  final String occurrenceId;
  final String eventIdentity;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;
}

/// An owned schedule produced from one legacy calendar-block occurrence group.
class PromotedSchedule {
  const PromotedSchedule({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.sourceIds,
    required this.sourceNames,
    required this.createdAt,
    required this.updatedAt,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
    this.sourceEventId,
    this.occurrenceId,
    this.eventIdentity,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;
  final List<String> sourceIds;
  final List<String> sourceNames;
  final String? sourceEventId;
  final String? occurrenceId;
  final String? eventIdentity;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Stable identity for a promoted schedule.
///
/// Deterministic ids keep the promotion idempotent across devices: the same
/// source occurrence always maps to the same owned schedule, so a repeated
/// promotion can skip it instead of creating a duplicate.
String legacyCalendarBlockScheduleId(String eventIdentity) =>
    'legacy-calendar-block:$eventIdentity';

/// The one-time migration identity recorded in [LocalScheduleMigrations].
const legacyCalendarBlockMigrationId = 'legacy-calendar-blocks-v1';

/// Groups legacy calendar blocks by source occurrence and projects them into
/// owned schedule copies.
///
/// Blocks that carry the same [LegacyCalendarBlockProjection.eventIdentity] are
/// the same occurrence seen through several calendars; they become one schedule
/// that keeps every source id/name for later import deduplication. Blocks with
/// an empty title are skipped: an unnamed arrangement is not a usable schedule.
List<PromotedSchedule> projectLegacyCalendarBlocks(
  List<LegacyCalendarBlockProjection> blocks, {
  required DateTime migratedAt,
  Map<String, String> sourceNames = const {},
}) {
  final grouped = <String, List<LegacyCalendarBlockProjection>>{};
  for (final block in blocks) {
    if (block.title.trim().isEmpty) continue;
    final identity = block.eventIdentity.trim().isNotEmpty
        ? block.eventIdentity.trim()
        : '${block.sourceId}:${block.occurrenceId}';
    grouped.putIfAbsent(identity, () => []).add(block);
  }

  final promoted = <PromotedSchedule>[];
  for (final entry in grouped.entries) {
    final group = entry.value;
    var startsAt = group.first.startsAt;
    var endsAt = group.first.endsAt;
    String? allDayStartDate;
    String? allDayEndDateExclusive;
    final sourceIds = <String>[];
    final names = <String>[];
    for (final block in group) {
      if (block.startsAt.isBefore(startsAt)) startsAt = block.startsAt;
      if (block.endsAt.isAfter(endsAt)) endsAt = block.endsAt;
      if (!sourceIds.contains(block.sourceId)) {
        sourceIds.add(block.sourceId);
        names.add(
          sourceNames[block.sourceId]?.trim().isNotEmpty == true
              ? sourceNames[block.sourceId]!.trim()
              : '日历',
        );
      }
      if (block.allDay) {
        final start = block.allDayStartDate;
        final end = block.allDayEndDateExclusive;
        if (start != null &&
            (allDayStartDate == null || start.compareTo(allDayStartDate) < 0)) {
          allDayStartDate = start;
        }
        if (end != null &&
            (allDayEndDateExclusive == null ||
                end.compareTo(allDayEndDateExclusive) > 0)) {
          allDayEndDateExclusive = end;
        }
      }
    }
    if (!endsAt.isAfter(startsAt)) continue;
    final first = group.first;
    // A promoted all-day copy needs its original date range; without one it
    // stays a timed schedule instead of producing an invalid row.
    final isAllDay =
        first.allDay &&
        allDayStartDate != null &&
        allDayEndDateExclusive != null;
    promoted.add(
      PromotedSchedule(
        id: legacyCalendarBlockScheduleId(entry.key),
        title: first.title.trim(),
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: isAllDay,
        allDayStartDate: isAllDay ? allDayStartDate : null,
        allDayEndDateExclusive: isAllDay ? allDayEndDateExclusive : null,
        sourceIds: sourceIds,
        sourceNames: names,
        sourceEventId: first.sourceEventId,
        occurrenceId: first.occurrenceId,
        eventIdentity: first.eventIdentity,
        createdAt: migratedAt,
        updatedAt: migratedAt,
      ),
    );
  }
  promoted.sort((left, right) => left.id.compareTo(right.id));
  return promoted;
}

/// Promotes legacy calendar blocks for one user, or for every user when
/// [userId] is null.
///
/// Callers own the transaction: the database upgrade runs this inside Drift's
/// migration transaction, and [LocalScheduleRepository] wraps it in its own.
/// The promotion is idempotent per user because it records a completed run:
/// a repeated call reports the previous result and writes nothing.
Future<SchedulePromotionResult> promoteLegacyCalendarBlocksInTransaction(
  PactaDatabase database, {
  String? userId,
  required DateTime migratedAt,
}) async {
  if (userId == null && !await _hasCalendarTables(database)) {
    // A synthetic or partially restored database may predate the calendar
    // tables entirely; there is nothing to promote and no marker to write.
    return const SchedulePromotionResult(
      migrationId: legacyCalendarBlockMigrationId,
      promotedCount: 0,
      sourceBlockCount: 0,
      alreadyPromoted: false,
    );
  }
  final users = userId != null
      ? <String>[userId]
      : await _usersWithCalendarData(database);
  var alreadyPromoted = true;
  var promotedCount = 0;
  var sourceBlockCount = 0;
  for (final user in users) {
    final run = await (database.select(
      database.localScheduleMigrations,
    )..where((row) => row.userId.equals(user))).getSingleOrNull();
    if (run != null &&
        run.status == ScheduleMigrationState.completed.storageValue) {
      promotedCount += run.promotedCount;
      sourceBlockCount += run.sourceBlockCount;
      continue;
    }
    alreadyPromoted = false;
    final blockRows =
        await (database.select(database.localCalendarBlocks)
              ..where((row) => row.userId.equals(user))
              ..orderBy([(row) => OrderingTerm(expression: row.startsAt)]))
            .get();
    final sourceRows = await (database.select(
      database.localCalendarSources,
    )..where((row) => row.userId.equals(user))).get();
    final names = {
      for (final source in sourceRows) source.sourceId: source.displayName,
    };
    final promoted = projectLegacyCalendarBlocks(
      [
        for (final row in blockRows)
          LegacyCalendarBlockProjection.fromLocalRow(row),
      ],
      migratedAt: migratedAt,
      sourceNames: names,
    );
    final existingRows = await (database.select(
      database.localSchedules,
    )..where((row) => row.userId.equals(user))).get();
    final existingIds = {for (final row in existingRows) row.id};
    final insertedIds = <String>[];
    for (final schedule in promoted) {
      if (existingIds.contains(schedule.id)) continue;
      await database
          .into(database.localSchedules)
          .insert(_scheduleCompanion(user, schedule));
      insertedIds.add(schedule.id);
    }
    await database
        .into(database.localScheduleMigrations)
        .insertOnConflictUpdate(
          LocalScheduleMigrationsCompanion.insert(
            userId: user,
            migrationId: legacyCalendarBlockMigrationId,
            status: ScheduleMigrationState.completed.storageValue,
            sourceBlockCount: blockRows.length,
            promotedCount: insertedIds.length,
            promotedScheduleIds: Value(jsonEncode(insertedIds)),
            backupPayload: jsonEncode([
              for (final row in blockRows) _encodeBlockRow(row),
            ]),
            createdAt: migratedAt,
            completedAt: migratedAt,
            rolledBackAt: const Value(null),
          ),
        );
    promotedCount += insertedIds.length;
    sourceBlockCount += blockRows.length;
  }
  return SchedulePromotionResult(
    migrationId: legacyCalendarBlockMigrationId,
    promotedCount: promotedCount,
    sourceBlockCount: sourceBlockCount,
    alreadyPromoted: alreadyPromoted && users.isNotEmpty,
  );
}

/// Restores the pre-migration calendar-block rows recorded in a rollback copy.
///
/// The rows are upserted, never deleted: the promotion itself never modified
/// the calendar-block projection, so a rollback only needs to prove the copies
/// survived. Rows imported after the promotion therefore stay untouched.
Future<int> restoreLegacyCalendarBlocks(
  PactaDatabase database,
  String backupPayload,
) async {
  final decoded = jsonDecode(backupPayload);
  if (decoded is! List) throw StateError('日程迁移回滚副本已损坏。');
  var restored = 0;
  for (final item in decoded) {
    if (item is! Map) throw StateError('日程迁移回滚副本已损坏。');
    final row = Map<String, dynamic>.from(item);
    await database
        .into(database.localCalendarBlocks)
        .insertOnConflictUpdate(
          LocalCalendarBlocksCompanion.insert(
            userId: row['user_id'] as String,
            sourceId: row['source_id'] as String,
            sourceEventId: row['source_event_id'] as String,
            occurrenceId: row['occurrence_id'] as String,
            eventIdentity: row['event_identity'] as String,
            title: row['title'] as String,
            startsAt: _decodeDateTime(row['starts_at']),
            endsAt: _decodeDateTime(row['ends_at']),
            allDay: Value(row['all_day'] == 1),
            allDayStartDate: Value(row['all_day_start_date'] as String?),
            allDayEndDateExclusive: Value(
              row['all_day_end_date_exclusive'] as String?,
            ),
            availability: row['availability'] as String,
            timeZoneId: row['time_zone_id'] as String,
            updatedAt: _decodeDateTime(row['updated_at']),
          ),
        );
    restored++;
  }
  return restored;
}

/// Decodes the schedule ids recorded by one promotion run.
Set<String> promotedScheduleIdsFrom(LocalScheduleMigration run) {
  final decoded = jsonDecode(run.promotedScheduleIds);
  if (decoded is! List) return const {};
  return {
    for (final value in decoded)
      if (value is String && value.isNotEmpty) value,
  };
}

Future<bool> _hasCalendarTables(PactaDatabase database) async {
  final rows = await database.customSelect('''
    SELECT name FROM sqlite_master
    WHERE type = 'table'
      AND name IN ('local_calendar_blocks', 'local_calendar_sources')
  ''').get();
  return rows.length == 2;
}

/// Users that can own a legacy calendar copy. Only these get a migration run,
/// so accounts with no calendar data are never blocked from a later promotion.
Future<List<String>> _usersWithCalendarData(PactaDatabase database) async {
  final rows = await database.customSelect('''
    SELECT user_id FROM local_calendar_blocks
    UNION SELECT user_id FROM local_calendar_sources
    UNION SELECT user_id FROM local_schedules
    UNION SELECT user_id FROM local_schedule_migrations
  ''').get();
  final users = [for (final row in rows) row.read<String>('user_id')];
  users.sort();
  return users;
}

LocalSchedulesCompanion _scheduleCompanion(
  String userId,
  PromotedSchedule schedule,
) => LocalSchedulesCompanion.insert(
  userId: userId,
  id: schedule.id,
  title: schedule.title,
  startsAt: schedule.startsAt.toUtc(),
  endsAt: schedule.endsAt.toUtc(),
  allDay: Value(schedule.allDay),
  allDayStartDate: Value(schedule.allDayStartDate),
  allDayEndDateExclusive: Value(schedule.allDayEndDateExclusive),
  origin: Value(ScheduleOrigin.legacyCalendarBlock.storageValue),
  sourceIds: Value(jsonEncode(schedule.sourceIds)),
  sourceNames: Value(jsonEncode(schedule.sourceNames)),
  sourceEventId: Value(schedule.sourceEventId),
  occurrenceId: Value(schedule.occurrenceId),
  eventIdentity: Value(schedule.eventIdentity),
  createdAt: schedule.createdAt.toUtc(),
  updatedAt: schedule.updatedAt.toUtc(),
);

Map<String, Object?> _encodeBlockRow(LocalCalendarBlock row) => {
  'user_id': row.userId,
  'source_id': row.sourceId,
  'source_event_id': row.sourceEventId,
  'occurrence_id': row.occurrenceId,
  'event_identity': row.eventIdentity,
  'title': row.title,
  'starts_at': _encodeDateTime(row.startsAt),
  'ends_at': _encodeDateTime(row.endsAt),
  'all_day': row.allDay ? 1 : 0,
  'all_day_start_date': row.allDayStartDate,
  'all_day_end_date_exclusive': row.allDayEndDateExclusive,
  'availability': row.availability,
  'time_zone_id': row.timeZoneId,
  'updated_at': _encodeDateTime(row.updatedAt),
};

int _encodeDateTime(DateTime value) =>
    value.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime _decodeDateTime(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch((value as int) * 1000, isUtc: true);
