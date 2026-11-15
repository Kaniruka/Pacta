import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../auth/user_lifecycle.dart';
import '../calendar/calendar_models.dart';
import '../tasks/task_database.dart';
import 'calendar_import_models.dart';
import 'schedule_migration.dart';
import 'schedule_models.dart';

/// Pacta-owned schedules. Every write goes through the local database and is
/// carried by the whole-account business snapshot; there is no per-entity
/// remote and no system-calendar write path.
abstract interface class ScheduleRepository {
  /// Reads the selected range and reports which occurrences would be copied.
  ///
  /// Producing a preview writes no schedule, so cancelling leaves nothing
  /// behind.
  Future<CalendarImportPreview> previewCalendarImport(
    CalendarImportRequest request,
  );

  /// Creates owned copies for [preview], skipping occurrences already owned.
  ///
  /// Existing copies are never rewritten: a user edit or a reschedule stays.
  Future<CalendarImportOutcome> confirmCalendarImport(
    CalendarImportPreview preview,
  );

  Future<Schedule> createSchedule(ScheduleDraft draft);

  Future<Schedule> updateSchedule(String scheduleId, ScheduleDraft draft);

  Future<Schedule> rescheduleSchedule(String scheduleId, ScheduleWindow window);

  /// Removes one owned schedule. Deleting a schedule never touches focus data.
  Future<void> deleteSchedule(String scheduleId);

  Future<Schedule> setScheduleCompletion(
    String scheduleId, {
    required bool isCompleted,
  });

  /// Stores (or clears) the optional reminder offset. Delivery is a separate
  /// concern; an unset offset never produces a notification.
  Future<Schedule> setScheduleReminder(String scheduleId, {int? minutesBefore});

  Future<List<Schedule>> getSchedules({DateTime? from, DateTime? to});

  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to});

  /// Promotes the legacy calendar-block projection into owned schedule copies,
  /// once per account. Repeated calls report the recorded result.
  Future<SchedulePromotionResult> promoteLegacyCalendarBlocks();

  Future<ScheduleMigrationStatus> getLegacyMigrationStatus();

  /// Removes only the schedules created by the recorded promotion and proves
  /// the pre-migration calendar-block copies are still present.
  Future<ScheduleRollbackResult> rollbackLegacyCalendarBlockPromotion();

  Future<void> dispose();
}

class LocalScheduleRepository implements ScheduleRepository {
  LocalScheduleRepository({
    required this.database,
    required this.userId,
    UserLifecycleAccess? lifecycleAccess,
    DateTime Function()? now,
  }) : lifecycleAccess =
           lifecycleAccess ?? const AlwaysActiveUserLifecycleAccess(),
       _now = now ?? DateTime.now;

  final PactaDatabase database;
  final String userId;
  final UserLifecycleAccess lifecycleAccess;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();
  final _uuid = const Uuid();

  static const _maxReminderMinutesBefore = 7 * 24 * 60;

  @override
  Future<SchedulePromotionResult> promoteLegacyCalendarBlocks() async {
    await lifecycleAccess.requireActive();
    late SchedulePromotionResult result;
    await database.transaction(() async {
      result = await promoteLegacyCalendarBlocksInTransaction(
        database,
        userId: userId,
        migratedAt: _now().toUtc(),
      );
    });
    if (!result.alreadyPromoted) await _publish();
    return result;
  }

  @override
  Future<ScheduleMigrationStatus> getLegacyMigrationStatus() async {
    final run = await _migrationRun();
    if (run == null) {
      return const ScheduleMigrationStatus(
        hasCompletedMigration: false,
        isRolledBack: false,
        canRollback: false,
        promotedCount: 0,
        sourceBlockCount: 0,
      );
    }
    final completed =
        run.status == ScheduleMigrationState.completed.storageValue;
    return ScheduleMigrationStatus(
      hasCompletedMigration: completed,
      isRolledBack: !completed,
      canRollback: completed,
      promotedCount: run.promotedCount,
      sourceBlockCount: run.sourceBlockCount,
      migrationId: run.migrationId,
      completedAt: run.completedAt.toUtc(),
    );
  }

  @override
  Future<ScheduleRollbackResult> rollbackLegacyCalendarBlockPromotion() async {
    await lifecycleAccess.requireActive();
    late ScheduleRollbackResult result;
    await database.transaction(() async {
      final run = await _migrationRun();
      if (run == null ||
          run.status != ScheduleMigrationState.completed.storageValue) {
        throw StateError('没有可回滚的旧日历迁移。');
      }
      final promotedIds = promotedScheduleIdsFrom(run);
      var removed = 0;
      if (promotedIds.isNotEmpty) {
        removed =
            await (database.delete(database.localSchedules)
                  ..where((row) => row.userId.equals(userId))
                  ..where((row) => row.id.isIn(promotedIds)))
                .go();
      }
      final restored = await restoreLegacyCalendarBlocks(
        database,
        run.backupPayload,
      );
      await (database.update(
        database.localScheduleMigrations,
      )..where((row) => row.userId.equals(userId))).write(
        LocalScheduleMigrationsCompanion(
          status: Value(ScheduleMigrationState.rolledBack.storageValue),
          rolledBackAt: Value(_now().toUtc()),
        ),
      );
      result = ScheduleRollbackResult(
        migrationId: run.migrationId,
        removedSchedules: removed,
        restoredBlocks: restored,
      );
    });
    await _publish();
    return result;
  }

  Future<LocalScheduleMigration?> _migrationRun() => (database.select(
    database.localScheduleMigrations,
  )..where((row) => row.userId.equals(userId))).getSingleOrNull();

  @override
  Future<CalendarImportPreview> previewCalendarImport(
    CalendarImportRequest request,
  ) async {
    await lifecycleAccess.requireActive();
    final needsDeviceAlias = request.occurrences.any(
      (occurrence) =>
          calendarImportEventIsDeviceLocal(occurrence.sourceEventId) ||
          (occurrence.deviceOccurrenceId?.trim().isNotEmpty ?? false),
    );
    // Only an installation alias needs provenance, so a preview of provider
    // occurrences without a device row keeps writing nothing at all.
    final deviceProvenance = needsDeviceAlias
        ? await _importDeviceProvenance()
        : await _existingDeviceProvenance();
    final index = await _importIdentityIndex(
      deviceProvenance: deviceProvenance,
    );
    final pending = <CalendarImportCandidate>[];
    final planned = <CalendarImportAlias>[];
    final aliasUpdates = <String, List<CalendarImportAlias>>{};
    var duplicates = 0;
    var ignored = 0;
    for (final occurrence in request.occurrences) {
      final source = request.sourceFor(occurrence.sourceId);
      if (source == null) {
        ignored++;
        continue;
      }
      if (!_occursWithin(occurrence, request.from, request.to)) continue;
      if (occurrence.title.trim().isEmpty) {
        ignored++;
        continue;
      }
      final aliases = calendarImportIdentityAliases(
        source: source,
        occurrence: occurrence,
        deviceProvenance: deviceProvenance,
      );
      final legacyIdentity = _legacyIdentityKey(source.id, occurrence);
      final owner = _aliasOwner(index, aliases);
      if (owner != null ||
          (legacyIdentity != null &&
              index.legacyIdentities.contains(legacyIdentity)) ||
          _aliasesOverlap(planned, aliases)) {
        duplicates++;
        if (owner != null) {
          // The same copy got a new alias (for example a provider id on the
          // device row that produced it). Recording it never rewrites content
          // and waits for confirm, so a cancelled preview writes nothing.
          final known = index.aliasesBySchedule[owner] ?? const [];
          final learned = aliases
              .where(
                (alias) => !known.any(
                  (existing) => existing.encode() == alias.encode(),
                ),
              )
              .toList();
          if (learned.isNotEmpty) {
            aliasUpdates.putIfAbsent(owner, () => []).addAll(learned);
          }
        }
        continue;
      }
      planned.addAll(aliases);
      pending.add(
        CalendarImportCandidate(
          occurrence: occurrence,
          sourceName: source.displayName,
          identityAliases: aliases,
        ),
      );
    }
    pending.sort((left, right) {
      final byStart = left.occurrence.startsAt.compareTo(
        right.occurrence.startsAt,
      );
      if (byStart != 0) return byStart;
      return left.identityKey.compareTo(right.identityKey);
    });
    return CalendarImportPreview(
      from: request.from,
      to: request.to,
      pending: pending,
      duplicateCount: duplicates,
      ignoredCount: ignored,
      pendingAliasUpdates: aliasUpdates,
    );
  }

  @override
  Future<CalendarImportOutcome> confirmCalendarImport(
    CalendarImportPreview preview,
  ) async {
    await lifecycleAccess.requireActive();
    final created = <Schedule>[];
    var skipped = 0;
    var identityChanged = false;
    await database.transaction(() async {
      final index = await _importIdentityIndex(
        deviceProvenance: await _existingDeviceProvenance(),
      );
      for (final entry in preview.pendingAliasUpdates.entries) {
        if (await _rememberImportAliases(entry.key, entry.value, index)) {
          identityChanged = true;
        }
      }
      for (final candidate in preview.pending) {
        final legacyIdentity = _legacyIdentityKey(
          candidate.occurrence.sourceId,
          candidate.occurrence,
        );
        final owner = _aliasOwner(index, candidate.identityAliases);
        if (owner != null ||
            (legacyIdentity != null &&
                index.legacyIdentities.contains(legacyIdentity))) {
          skipped++;
          if (owner != null &&
              await _rememberImportAliases(
                owner,
                candidate.identityAliases,
                index,
              )) {
            identityChanged = true;
          }
          continue;
        }
        final copy = _calendarCopy(candidate);
        await _saveSchedule(copy);
        index.addAliases(copy.id, candidate.identityAliases);
        created.add(copy);
      }
    });
    if (created.isNotEmpty || identityChanged) await _publish();
    return CalendarImportOutcome(created: created, skippedDuplicates: skipped);
  }

  Schedule _calendarCopy(CalendarImportCandidate candidate) {
    final occurrence = candidate.occurrence;
    final timestamp = _nextTimestamp();
    final allDay = occurrence.allDay;
    return Schedule(
      id: _uuid.v4(),
      title: occurrence.title.trim(),
      startsAt: occurrence.startsAt.toUtc(),
      endsAt: occurrence.endsAt.toUtc(),
      allDay: allDay,
      allDayStartDate: allDay
          ? (occurrence.allDayStartDate ?? _utcDateKey(occurrence.startsAt))
          : null,
      allDayEndDateExclusive: allDay
          ? (occurrence.allDayEndDateExclusive ??
                _utcDateKey(occurrence.endsAt))
          : null,
      origin: ScheduleOrigin.calendarImport,
      sourceIds: [occurrence.sourceId],
      sourceNames: [candidate.sourceName],
      sourceEventId: occurrence.sourceEventId,
      occurrenceId: occurrence.occurrenceId,
      eventIdentity: candidate.identityKey,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// Persisted installation identity used to namespace device-local fallback
  /// ids.
  ///
  /// `focus_source_devices` is per-user and deliberately excluded from business
  /// snapshots, so restoring another device's data never renames this
  /// installation. Without it, a `local:` fallback id would claim a global
  /// identity that two devices' numeric calendar and event rows can share.
  Future<String?> _existingDeviceProvenance() async {
    final existing = await (database.select(
      database.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    return existing?.deviceId;
  }

  Future<String> _importDeviceProvenance() async {
    final existing = await (database.select(
      database.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (existing != null) return existing.deviceId;
    final generated = _uuid.v4();
    await database
        .into(database.focusSourceDevices)
        .insertOnConflictUpdate(
          FocusSourceDevicesCompanion.insert(
            userId: userId,
            deviceId: generated,
          ),
        );
    return generated;
  }

  /// Identities already owned by this account, indexed for skip checks.
  ///
  /// Every copy contributes all aliases it recorded, so a device-local alias and
  /// a provider alias for the same occurrence both take part in deduplication.
  Future<_ImportIdentityIndex> _importIdentityIndex({
    String? deviceProvenance,
  }) async {
    final rows = await (database.select(
      database.localSchedules,
    )..where((row) => row.userId.equals(userId))).get();
    final index = _ImportIdentityIndex();
    for (final row in rows) {
      final identity = row.eventIdentity?.trim();
      if (identity == null || identity.isEmpty) continue;
      index.addAliases(
        row.id,
        decodeCalendarImportIdentityAliases(
          identity,
          deviceProvenance: deviceProvenance,
        ),
      );
      if (row.origin != ScheduleOrigin.legacyCalendarBlock.storageValue) {
        continue;
      }
      if (calendarImportEventIsDeviceLocal(identity)) {
        continue;
      }
      for (final sourceId in _decodeStrings(row.sourceIds)) {
        index.legacyIdentities.add(
          calendarImportLegacyIdentityKey(
            sourceId: sourceId,
            rawIdentity: identity,
          ),
        );
      }
    }
    return index;
  }

  /// Copy that owns any alias of [aliases], if one already exists.
  String? _aliasOwner(
    _ImportIdentityIndex index,
    List<CalendarImportAlias> aliases,
  ) {
    for (final entry in index.aliasesBySchedule.entries) {
      if (_aliasesOverlap(entry.value, aliases)) return entry.key;
    }
    return null;
  }

  bool _aliasesOverlap(
    List<CalendarImportAlias> existing,
    List<CalendarImportAlias> incoming,
  ) {
    for (final alias in existing) {
      for (final candidate in incoming) {
        if (alias.proves(candidate)) return true;
      }
    }
    return false;
  }

  /// Records aliases learned after the copy was created.
  ///
  /// This happens when the platform assigns a provider identity to the device
  /// row that produced a device-local copy: the copy is the same arrangement, so
  /// it keeps its content (title, times, completion, notes) and only gains the
  /// alias that lets other installations skip it. The conversation is never
  /// inferred from a raw numeric id.
  Future<bool> _rememberImportAliases(
    String scheduleId,
    List<CalendarImportAlias> aliases,
    _ImportIdentityIndex index,
  ) async {
    final existing = index.aliasesBySchedule[scheduleId] ?? const [];
    final merged = _canonicalAliases([...existing, ...aliases]);
    if (merged.length == existing.length) return false;
    await (database.update(database.localSchedules)
          ..where((row) => row.id.equals(scheduleId))
          ..where((row) => row.userId.equals(userId)))
        .write(
          LocalSchedulesCompanion(
            eventIdentity: Value(encodeCalendarImportIdentity(merged)),
          ),
        );
    index.addAliases(scheduleId, merged);
    return true;
  }

  List<CalendarImportAlias> _canonicalAliases(
    Iterable<CalendarImportAlias> aliases,
  ) {
    final byEncoding = {for (final alias in aliases) alias.encode(): alias};
    final encodings = byEncoding.keys.toList()..sort();
    return [for (final encoding in encodings) byEncoding[encoding]!];
  }

  /// Raw identity left behind by the one-time legacy block promotion.
  ///
  /// Legacy copies recorded no installation provenance, so a `local:` fallback
  /// identity is not provable across devices: two installations can reuse the
  /// same numeric row id. Matching it would skip a genuine new arrangement, so
  /// only provider identities take part in legacy matching.
  String? _legacyIdentityKey(
    String sourceId,
    CalendarEventOccurrence occurrence,
  ) {
    if (calendarImportEventIsDeviceLocal(occurrence.sourceEventId)) {
      return null;
    }
    final raw = occurrence.occurrenceId.trim().isNotEmpty
        ? occurrence.occurrenceId.trim()
        : occurrence.eventIdentity.trim();
    if (raw.isEmpty) return null;
    return calendarImportLegacyIdentityKey(
      sourceId: sourceId,
      rawIdentity: raw,
    );
  }

  bool _occursWithin(
    CalendarEventOccurrence occurrence,
    DateTime from,
    DateTime to,
  ) {
    final start = occurrence.startsAt.toUtc();
    final end = occurrence.endsAt.toUtc();
    return start.isBefore(to.toUtc()) && end.isAfter(from.toUtc());
  }

  String _utcDateKey(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<Schedule> createSchedule(ScheduleDraft draft) async {
    await lifecycleAccess.requireActive();
    final title = _requiredTitle(draft.title);
    final window = _validateWindow(draft.window);
    final taskId = await _requiredTaskId(draft.taskId);
    final timestamp = _nextTimestamp();
    final schedule = Schedule(
      id: _uuid.v4(),
      title: title,
      notes: draft.notes.trim(),
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      allDay: window.allDay,
      allDayStartDate: window.allDayStartDate,
      allDayEndDateExclusive: window.allDayEndDateExclusive,
      taskId: taskId,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _saveSchedule(schedule);
    await _publish();
    return schedule;
  }

  @override
  Future<Schedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  ) async {
    await lifecycleAccess.requireActive();
    final existing = await _findSchedule(scheduleId);
    final window = _validateWindow(draft.window);
    final taskId = await _requiredTaskId(draft.taskId);
    final updated = _replaceFields(
      existing,
      title: _requiredTitle(draft.title),
      notes: draft.notes.trim(),
      window: window,
      taskId: taskId,
    );
    await _saveSchedule(updated);
    await _publish();
    return updated;
  }

  @override
  Future<Schedule> rescheduleSchedule(
    String scheduleId,
    ScheduleWindow window,
  ) async {
    await lifecycleAccess.requireActive();
    final existing = await _findSchedule(scheduleId);
    final updated = _replaceFields(
      existing,
      title: existing.title,
      notes: existing.notes,
      window: _validateWindow(window),
      taskId: existing.taskId,
    );
    await _saveSchedule(updated);
    await _publish();
    return updated;
  }

  @override
  Future<void> deleteSchedule(String scheduleId) async {
    await lifecycleAccess.requireActive();
    await _findSchedule(scheduleId);
    await (database.delete(database.localSchedules)
          ..where((row) => row.userId.equals(userId))
          ..where((row) => row.id.equals(scheduleId)))
        .go();
    await _publish();
  }

  @override
  Future<Schedule> setScheduleCompletion(
    String scheduleId, {
    required bool isCompleted,
  }) async {
    await lifecycleAccess.requireActive();
    final existing = await _findSchedule(scheduleId);
    if (existing.isCompleted == isCompleted) return existing;
    final completedAt = isCompleted ? _nextTimestamp(existing.updatedAt) : null;
    final updated = Schedule(
      id: existing.id,
      title: existing.title,
      notes: existing.notes,
      startsAt: existing.startsAt,
      endsAt: existing.endsAt,
      allDay: existing.allDay,
      allDayStartDate: existing.allDayStartDate,
      allDayEndDateExclusive: existing.allDayEndDateExclusive,
      isCompleted: isCompleted,
      completedAt: completedAt,
      taskId: existing.taskId,
      reminderMinutesBefore: existing.reminderMinutesBefore,
      origin: existing.origin,
      sourceIds: existing.sourceIds,
      sourceNames: existing.sourceNames,
      sourceEventId: existing.sourceEventId,
      occurrenceId: existing.occurrenceId,
      eventIdentity: existing.eventIdentity,
      createdAt: existing.createdAt,
      updatedAt: completedAt ?? _nextTimestamp(existing.updatedAt),
    );
    await _saveSchedule(updated);
    await _publish();
    return updated;
  }

  @override
  Future<Schedule> setScheduleReminder(
    String scheduleId, {
    int? minutesBefore,
  }) async {
    await lifecycleAccess.requireActive();
    if (minutesBefore != null &&
        (minutesBefore < 0 || minutesBefore > _maxReminderMinutesBefore)) {
      throw ArgumentError('提醒时间必须介于开始前 0 分钟到 7 天之间。');
    }
    final existing = await _findSchedule(scheduleId);
    final updated = Schedule(
      id: existing.id,
      title: existing.title,
      notes: existing.notes,
      startsAt: existing.startsAt,
      endsAt: existing.endsAt,
      allDay: existing.allDay,
      allDayStartDate: existing.allDayStartDate,
      allDayEndDateExclusive: existing.allDayEndDateExclusive,
      isCompleted: existing.isCompleted,
      completedAt: existing.completedAt,
      taskId: existing.taskId,
      reminderMinutesBefore: minutesBefore,
      origin: existing.origin,
      sourceIds: existing.sourceIds,
      sourceNames: existing.sourceNames,
      sourceEventId: existing.sourceEventId,
      occurrenceId: existing.occurrenceId,
      eventIdentity: existing.eventIdentity,
      createdAt: existing.createdAt,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
    await _saveSchedule(updated);
    await _publish();
    return updated;
  }

  @override
  Future<List<Schedule>> getSchedules({DateTime? from, DateTime? to}) async {
    final query = database.select(database.localSchedules)
      ..where((row) => row.userId.equals(userId))
      ..orderBy([
        (row) => OrderingTerm(expression: row.startsAt),
        (row) => OrderingTerm(expression: row.id),
      ]);
    final rows = await query.get();
    final fromUtc = from?.toUtc();
    final toUtc = to?.toUtc();
    return [
      for (final row in rows)
        if (_overlaps(row, fromUtc, toUtc)) _scheduleFromRow(row),
    ];
  }

  /// Emits the current schedules, then one emission per change.
  ///
  /// The stream is built explicitly instead of with `async*` so that cancelling
  /// the subscription returns immediately: an `async*` generator suspended in
  /// `await for` cannot observe cancellation until another event arrives.
  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) {
    late StreamController<List<Schedule>> controller;
    StreamSubscription<void>? changes;
    Future<void> emit() async {
      try {
        final schedules = await getSchedules(from: from, to: to);
        if (!controller.isClosed) controller.add(schedules);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<Schedule>>(
      onListen: () {
        changes = _changes.stream.listen(
          (_) => emit(),
          onDone: () async {
            await emit();
            if (!controller.isClosed) await controller.close();
          },
        );
        emit();
      },
      onCancel: () async {
        await changes?.cancel();
        changes = null;
      },
    );
    return controller.stream;
  }

  bool _overlaps(LocalSchedule row, DateTime? from, DateTime? to) {
    if (from != null && !row.endsAt.toUtc().isAfter(from)) return false;
    if (to != null && !row.startsAt.toUtc().isBefore(to)) return false;
    return true;
  }

  Future<Schedule> _findSchedule(String scheduleId) async {
    final row =
        await (database.select(database.localSchedules)
              ..where((schedule) => schedule.userId.equals(userId))
              ..where((schedule) => schedule.id.equals(scheduleId)))
            .getSingleOrNull();
    if (row == null) throw StateError('日程不存在或已不属于当前用户。');
    return _scheduleFromRow(row);
  }

  /// Keeps identity, completion state and provenance; only the editable fields
  /// change. Provenance must survive an edit so a later import can still skip
  /// the original source occurrence.
  Schedule _replaceFields(
    Schedule existing, {
    required String title,
    required String notes,
    required ScheduleWindow window,
    required String? taskId,
  }) {
    return Schedule(
      id: existing.id,
      title: title,
      notes: notes,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      allDay: window.allDay,
      allDayStartDate: window.allDayStartDate,
      allDayEndDateExclusive: window.allDayEndDateExclusive,
      isCompleted: existing.isCompleted,
      completedAt: existing.completedAt,
      taskId: taskId,
      reminderMinutesBefore: existing.reminderMinutesBefore,
      origin: existing.origin,
      sourceIds: existing.sourceIds,
      sourceNames: existing.sourceNames,
      sourceEventId: existing.sourceEventId,
      occurrenceId: existing.occurrenceId,
      eventIdentity: existing.eventIdentity,
      createdAt: existing.createdAt,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
  }

  Future<void> _saveSchedule(Schedule schedule) async {
    await database
        .into(database.localSchedules)
        .insertOnConflictUpdate(
          LocalSchedulesCompanion.insert(
            userId: userId,
            id: schedule.id,
            title: schedule.title,
            notes: Value(schedule.notes),
            startsAt: schedule.startsAt.toUtc(),
            endsAt: schedule.endsAt.toUtc(),
            allDay: Value(schedule.allDay),
            allDayStartDate: Value(schedule.allDayStartDate),
            allDayEndDateExclusive: Value(schedule.allDayEndDateExclusive),
            isCompleted: Value(schedule.isCompleted),
            completedAt: Value(schedule.completedAt),
            taskId: Value(schedule.taskId),
            reminderMinutesBefore: Value(schedule.reminderMinutesBefore),
            origin: Value(schedule.origin.storageValue),
            sourceIds: Value(jsonEncode(schedule.sourceIds)),
            sourceNames: Value(jsonEncode(schedule.sourceNames)),
            sourceEventId: Value(schedule.sourceEventId),
            occurrenceId: Value(schedule.occurrenceId),
            eventIdentity: Value(schedule.eventIdentity),
            createdAt: schedule.createdAt.toUtc(),
            updatedAt: schedule.updatedAt.toUtc(),
          ),
        );
  }

  Schedule _scheduleFromRow(LocalSchedule row) => Schedule(
    id: row.id,
    title: row.title,
    notes: row.notes,
    startsAt: row.startsAt.toUtc(),
    endsAt: row.endsAt.toUtc(),
    allDay: row.allDay,
    allDayStartDate: row.allDayStartDate,
    allDayEndDateExclusive: row.allDayEndDateExclusive,
    isCompleted: row.isCompleted,
    completedAt: row.completedAt?.toUtc(),
    taskId: row.taskId,
    reminderMinutesBefore: row.reminderMinutesBefore,
    origin: ScheduleOrigin.fromStorage(row.origin),
    sourceIds: _decodeStrings(row.sourceIds),
    sourceNames: _decodeStrings(row.sourceNames),
    sourceEventId: row.sourceEventId,
    occurrenceId: row.occurrenceId,
    eventIdentity: row.eventIdentity,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
  );

  List<String> _decodeStrings(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const [];
    return [
      for (final value in decoded)
        if (value is String && value.isNotEmpty) value,
    ];
  }

  String _requiredTitle(String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) throw ArgumentError('日程名称不能为空。');
    return normalized;
  }

  ScheduleWindow _validateWindow(ScheduleWindow window) {
    if (!window.endsAt.isAfter(window.startsAt)) {
      throw ArgumentError('日程结束时间必须晚于开始时间。');
    }
    if (window.allDay &&
        (window.allDayStartDate == null ||
            window.allDayEndDateExclusive == null)) {
      throw ArgumentError('全天日程必须提供日期范围。');
    }
    return window;
  }

  Future<String?> _requiredTaskId(String? taskId) async {
    final normalized = taskId?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final row =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(normalized)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      throw StateError('任务不存在或已删除。');
    }
    return normalized;
  }

  DateTime _nextTimestamp([DateTime? previous]) {
    final candidate = _now().toUtc();
    final second = DateTime.fromMillisecondsSinceEpoch(
      candidate.millisecondsSinceEpoch - candidate.millisecond,
      isUtc: true,
    );
    if (previous == null) return second;
    final previousUtc = previous.toUtc();
    return second.isAfter(previousUtc)
        ? second
        : previousUtc.add(const Duration(seconds: 1));
  }

  Future<void> _publish() async {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> dispose() async => _changes.close();
}

/// Identity sets used to skip already owned import copies.
class _ImportIdentityIndex {
  final Map<String, List<CalendarImportAlias>> aliasesBySchedule = {};
  final Set<String> legacyIdentities = {};

  void addAliases(String scheduleId, Iterable<CalendarImportAlias> aliases) {
    final owned = aliasesBySchedule.putIfAbsent(
      scheduleId,
      () => <CalendarImportAlias>[],
    );
    final known = {for (final alias in owned) alias.encode()};
    for (final alias in aliases) {
      if (known.add(alias.encode())) owned.add(alias);
    }
  }
}
