import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../auth/user_lifecycle.dart';
import '../calendar/calendar_models.dart';
import '../focus/focus_time_zones.dart';
import '../tasks/task_database.dart';
import 'calendar_import_models.dart';
import 'schedule_migration.dart';
import 'schedule_models.dart';
import 'schedule_repeat.dart';

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

  /// 新建重复日程系列：一条规则 + 有界预生成的实例。
  ///
  /// [timeZoneId] 由调用方注入账号时区（例如 07 的账号时区适配器），仓储
  /// 不读取设备或当前显示时区。非法规则整体拒绝，不落库。
  Future<ScheduleSeries> createRecurringSchedule({
    required ScheduleDraft draft,
    required ScheduleRepeatSpec repeat,
    required String timeZoneId,
  });

  /// 改写重复日程的一个实例。
  ///
  /// [ScheduleRepeatScope.onlyThis] 只改写该实例并落库为例外；
  /// [ScheduleRepeatScope.thisAndFuture] 截断原规则、从该实例起新建规则，
  /// 已过去的实例原样保留，不会被当前规则重算。
  Future<ScheduleRepeatEditResult> editRecurringSchedule(
    String scheduleId, {
    required ScheduleDraft draft,
    required ScheduleRepeatScope scope,
    ScheduleRepeatSpec? repeat,
  });

  /// 当前账号的重复规则（供计划页展示重复设置）。
  Future<List<ScheduleRepeatRule>> getRecurrenceRules();

  /// 在查询范围内补齐尚未生成的实例，返回新生成的实例数。
  ///
  /// 范围必须有界：超出上限整体拒绝，绝不静默截断。
  Future<int> expandRecurrences({required DateTime from, required DateTime to});

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

  /// 观察本账号日程的数据库级变化；跨仓储实例与快照整体替换都能到达。
  final _watches = <_ScheduleWatch>{};
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
    await database.transaction(() async {
      final index = await _importIdentityIndex(
        deviceProvenance: await _existingDeviceProvenance(),
      );
      for (final entry in preview.pendingAliasUpdates.entries) {
        await _rememberImportAliases(entry.key, entry.value, index);
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
          if (owner != null) {
            await _rememberImportAliases(
              owner,
              candidate.identityAliases,
              index,
            );
          }
          continue;
        }
        final copy = _calendarCopy(candidate);
        await _saveSchedule(copy);
        index.addAliases(copy.id, candidate.identityAliases);
        created.add(copy);
      }
    });
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
    // 原关联任务若已被删除（墓碑），未改动就保留链接身份；改指新任务仍要求
    // 目标存在且未删除，因此不会出现"新建链接到已删除任务"。
    final taskId = draft.taskId == existing.taskId
        ? existing.taskId
        : await _requiredTaskId(draft.taskId);
    final updated = _replaceFields(
      existing,
      title: _requiredTitle(draft.title),
      notes: draft.notes.trim(),
      window: window,
      taskId: taskId,
    );
    await _saveSchedule(updated);
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
    return updated;
  }

  @override
  Future<void> deleteSchedule(String scheduleId) async {
    await lifecycleAccess.requireActive();
    final existing = await _findSchedule(scheduleId);
    if (existing.isRecurring) {
      // 重复实例保留墓碑：否则按范围展开会把它重新生成出来。
      await (database.update(database.localSchedules)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.id.equals(scheduleId)))
          .write(
            LocalSchedulesCompanion(
              isRecurrenceCancelled: const Value(true),
              updatedAt: Value(_nextTimestamp(existing.updatedAt)),
            ),
          );
    } else {
      await (database.delete(database.localSchedules)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.id.equals(scheduleId)))
          .go();
    }
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
    final updated = existing.copyWith(
      isCompleted: isCompleted,
      completedAt: completedAt,
      clearCompletedAt: !isCompleted,
      updatedAt: completedAt ?? _nextTimestamp(existing.updatedAt),
    );
    await _saveSchedule(updated);
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
    final updated = existing.copyWith(
      reminderMinutesBefore: minutesBefore,
      clearReminder: minutesBefore == null,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
    await _saveSchedule(updated);
    return updated;
  }

  @override
  Future<ScheduleSeries> createRecurringSchedule({
    required ScheduleDraft draft,
    required ScheduleRepeatSpec repeat,
    required String timeZoneId,
  }) async {
    await lifecycleAccess.requireActive();
    final title = _requiredTitle(draft.title);
    final window = _validateWindow(draft.window);
    final taskId = await _requiredTaskId(draft.taskId);
    final rule = buildRepeatRule(
      id: _uuid.v4(),
      spec: repeat,
      window: window,
      timeZoneId: timeZoneId,
    ).copyWith(title: title, notes: draft.notes.trim(), taskId: taskId);
    late List<Schedule> occurrences;
    await database.transaction(() async {
      await _saveRule(rule, _nextTimestamp());
      occurrences = await _materializeRule(
        rule: rule,
        seriesId: rule.id,
        fromDate: rule.firstDate,
        toDate: _horizonEndDate(rule),
      );
    });
    return ScheduleSeries(rule: rule, occurrences: occurrences);
  }

  @override
  Future<ScheduleRepeatEditResult> editRecurringSchedule(
    String scheduleId, {
    required ScheduleDraft draft,
    required ScheduleRepeatScope scope,
    ScheduleRepeatSpec? repeat,
  }) async {
    await lifecycleAccess.requireActive();
    final existing = await _findSchedule(scheduleId);
    final ruleId = existing.recurrenceId;
    final originalDate = existing.recurrenceDate;
    if (ruleId == null || originalDate == null) {
      throw StateError('这条日程不是重复日程，请使用普通编辑。');
    }
    final rule = await _findRule(ruleId);
    if (rule == null) throw StateError('重复规则不存在，请重新展开后再修改。');
    final title = _requiredTitle(draft.title);
    final window = _validateWindow(draft.window);
    final taskId = await _requiredTaskId(draft.taskId);
    final seriesId = existing.recurrenceSeriesId ?? rule.id;

    late ScheduleRepeatEditResult result;
    await database.transaction(() async {
      if (scope == ScheduleRepeatScope.onlyThis) {
        final updated = existing.copyWith(
          title: title,
          notes: draft.notes.trim(),
          startsAt: window.startsAt,
          endsAt: window.endsAt,
          allDay: window.allDay,
          allDayStartDate: window.allDayStartDate,
          allDayEndDateExclusive: window.allDayEndDateExclusive,
          taskId: taskId,
          clearTaskId: taskId == null,
          isRecurrenceException: true,
          updatedAt: _nextTimestamp(existing.updatedAt),
        );
        await _saveSchedule(updated);
        result = ScheduleRepeatEditResult(
          updated: updated,
          rule: rule,
          generated: 0,
        );
        return;
      }

      final splitAt = parseRecurrenceDate(originalDate, '实例日期');
      // 改动前先取出该系列仍存活的规则：本次及以后会接管 split 之后的分段。
      final seriesRules = await _rulesForSeries(seriesId);
      final dayBeforeSplit = formatRecurrenceDate(
        DateTime.utc(splitAt.year, splitAt.month, splitAt.day - 1),
      );
      final keepsEarlierInstances = splitAt.isAfter(
        parseRecurrenceDate(rule.originalFirstDate, '首日'),
      );
      final newRuleId = _uuid.v4();
      final nowUtc = _now().toUtc();
      // 本次改动会整段替换 split 之后的分段规则；被替换规则名下仍保留的行
      // （墓碑、已过去的例外）在删除规则前统一改挂到新规则，保持引用有效。
      final replacedRuleIds = <String>{};
      ScheduleRepeatRule? truncated;
      if (keepsEarlierInstances) {
        // 截断写在可见日期域：身份 splitAt-1 对应的可见日期是它加上位移。
        final truncateAt = shiftRecurrenceDate(dayBeforeSplit, rule.shiftDays);
        final currentEnd = rule.endDate;
        truncated = currentEnd != null && currentEnd.compareTo(truncateAt) <= 0
            ? rule
            : rule.copyWith(endDate: truncateAt);
        await _saveRule(truncated, _nextTimestamp());
      } else {
        // 该实例就是首个实例：原规则不再拥有任何实例，整体移除而不是留下
        // 一条违反"结束日期不早于首日"的空规则。
        replacedRuleIds.add(rule.id);
      }
      // split 之后的分段规则已被这次改动取代：留下它们会在同一段日期上再生成
      // 一套实例，重复展开后出现重影。
      for (final stale in seriesRules) {
        if (stale.id == rule.id) continue;
        if (stale.originalFirstDate.compareTo(originalDate) < 0) continue;
        replacedRuleIds.add(stale.id);
      }

      // 只重写**尚未开始**的实例。身份日期在 cut 之后、但可见时间已经开始的
      // 实例（例如被"仅本次"挪到过去的例外）属于历史：删除它们会丢失例外、
      // 完成状态与到达方式，等于改写已经发生的事。墓碑照旧保留。
      await (database.delete(database.localSchedules)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.recurrenceSeriesId.equals(seriesId))
            ..where(
              (row) => row.recurrenceDate.isBiggerOrEqualValue(originalDate),
            )
            ..where((row) => row.isRecurrenceCancelled.equals(false))
            ..where((row) => row.startsAt.isBiggerOrEqualValue(nowUtc)))
          .go();

      // 被替换规则剩下的行（墓碑 + 保留下来的过去实例）改挂到新规则：
      // 身份日期不变，取消语义与完成状态也不变。
      for (final removedRuleId in replacedRuleIds) {
        await _reassignRuleRows(removedRuleId, newRuleId);
        await _deleteRule(removedRuleId);
      }

      final draftFirstDate = window.allDay
          ? window.allDayStartDate!
          : formatRecurrenceDate(
              _zoneDate(
                window.startsAt,
                FocusTimeZones.location(rule.timeZoneId),
              ),
            );
      final shiftDays = parseRecurrenceDate(
        draftFirstDate,
        '草稿日期',
      ).difference(splitAt).inDays;
      // 星期在**已有可见规则**上按增量位移旋转，而不是再叠加一次总位移：
      // rule.weekdays 已经是"当前可见星期"，第二次同日改名/改时的总位移没变，
      // 增量就是 0，星期必须原样保留（否则周三会被再推成周五）。
      final incrementalShift = shiftDays - rule.shiftDays;
      final spec =
          repeat ??
          ScheduleRepeatSpec(
            frequency: rule.frequency,
            weekdays: incrementalShift == 0
                ? rule.weekdays
                : {
                    for (final day in rule.weekdays)
                      ((day - 1 + incrementalShift) % 7) + 1,
                  },
            endDate: rule.endDate,
          );
      // 新规则：可见首日 = 草稿日期，原始发生身份 = 可见日期 - 位移；
      // 内容模板属于规则自身，后续按范围补齐的实例都从它取内容。
      final newRule =
          buildRepeatRule(
            id: newRuleId,
            spec: spec,
            window: window,
            timeZoneId: rule.timeZoneId,
          ).copyWith(
            shiftDays: shiftDays,
            title: title,
            notes: draft.notes.trim(),
            taskId: taskId,
          );
      final updated = existing.copyWith(
        title: title,
        notes: draft.notes.trim(),
        startsAt: window.startsAt,
        endsAt: window.endsAt,
        allDay: window.allDay,
        allDayStartDate: window.allDayStartDate,
        allDayEndDateExclusive: window.allDayEndDateExclusive,
        taskId: taskId,
        clearTaskId: taskId == null,
        recurrenceId: newRule.id,
        // 原始发生身份不随改期漂移：取消过的同一期始终是同一身份。
        recurrenceDate: originalDate,
        recurrenceTimeZoneId: newRule.timeZoneId,
        recurrenceStartMinutes: newRule.allDay
            ? null
            : newRule.startMinutesOfDay,
        isRecurrenceException: false,
        updatedAt: _nextTimestamp(existing.updatedAt),
      );
      await _saveRule(newRule, _nextTimestamp());
      await _saveSchedule(updated);
      final generated = await _materializeRule(
        rule: newRule,
        seriesId: seriesId,
        fromDate: newRule.firstDate,
        toDate: _horizonEndDate(newRule),
      );
      result = ScheduleRepeatEditResult(
        updated: updated,
        rule: newRule,
        generated: generated.length,
        truncatedRule: truncated,
      );
    });
    return result;
  }

  @override
  Future<List<ScheduleRepeatRule>> getRecurrenceRules() async {
    final rows =
        await (database.select(database.localScheduleRecurrences)
              ..where((row) => row.userId.equals(userId))
              ..orderBy([
                (row) => OrderingTerm(expression: row.firstDate),
                (row) => OrderingTerm(expression: row.id),
              ]))
            .get();
    return [for (final row in rows) _ruleFromRow(row)];
  }

  @override
  Future<int> expandRecurrences({
    required DateTime from,
    required DateTime to,
  }) async {
    await lifecycleAccess.requireActive();
    return _expandInRange(from, to);
  }

  /// 按上限分片补齐：每个分片自身有界，整体跨度不设隐性上限。
  Future<int> _expandRangeChunked(DateTime from, DateTime to) async {
    final fromUtc = from.toUtc();
    final toUtc = to.toUtc();
    if (toUtc.isBefore(fromUtc)) {
      throw ArgumentError('重复日程的展开结束时间不能早于开始时间。');
    }
    // 分片跨度取"天数上限 - 1"：含首尾的日子数正好落在实例数上限内。
    const chunk = Duration(days: maxRecurrenceExpansionDays - 1);
    var cursor = fromUtc;
    var generated = 0;
    while (cursor.isBefore(toUtc)) {
      final end = cursor.add(chunk).isBefore(toUtc) ? cursor.add(chunk) : toUtc;
      generated += await _expandInRange(cursor, end);
      cursor = end;
    }
    return generated;
  }

  Future<int> _expandInRange(DateTime from, DateTime to) async {
    final fromUtc = from.toUtc();
    final toUtc = to.toUtc();
    if (toUtc.isBefore(fromUtc)) {
      throw ArgumentError('重复日程的展开结束时间不能早于开始时间。');
    }
    if (toUtc.difference(fromUtc).inDays > maxRecurrenceExpansionDays) {
      throw ArgumentError('重复日程的展开范围过大，请缩小查询区间。');
    }
    // 规则读取、已有身份去重与写入必须是同一个数据库事务。
    //
    // 三个步骤分开执行时，两个观察者会各自读到"还没有实例"，再各自生成一套
    // 不同 UUID 但同系列同日期的行：主键是 (userId, id)，拦不住这种重复。
    // 事务同时把整份快照替换/清除挡在外面——要么展开先提交、随后被替换删掉，
    // 要么替换先提交、展开读到的是替换后的规则，不会给已经不存在的规则补行。
    var generated = 0;
    await database.transaction(() async {
      final rules = await getRecurrenceRules();
      if (rules.isEmpty) return;
      for (final rule in rules) {
        final location = FocusTimeZones.location(rule.timeZoneId);
        final localFrom = formatRecurrenceDate(_zoneDate(fromUtc, location));
        final localTo = formatRecurrenceDate(_zoneDate(toUtc, location));
        if (localTo.compareTo(localFrom) < 0) continue;
        // 与查询区间完全不相交的规则直接跳过：查重复日程开始之前的月份应当
        // 返回空集合，而不是拿反向区间去触发严格展开的拒绝。
        if (rule.firstDate.compareTo(localTo) > 0) continue;
        final ruleEnd = rule.endDate;
        if (ruleEnd != null && ruleEnd.compareTo(localFrom) < 0) continue;
        final created = await _materializeRule(
          rule: rule,
          seriesId: await _seriesIdForRule(rule.id),
          fromDate: localFrom,
          toDate: localTo,
        );
        generated += created.length;
      }
    });
    return generated;
  }

  @override
  Future<List<Schedule>> getSchedules({DateTime? from, DateTime? to}) async {
    if (from != null && to != null) {
      // 读取范围内按需补齐重复实例；已存在的实例（含例外与墓碑）永不重写。
      // 宽范围按有界分片补齐，既能覆盖长区间查询，也不会一次展开到底。
      await _expandRangeChunked(from, to);
    }
    final query = database.select(database.localSchedules)
      ..where((row) => row.userId.equals(userId))
      ..where((row) => row.isRecurrenceCancelled.equals(false))
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

  /// 当前日程，随后每一次数据库变更再推一次。
  ///
  /// 观察的是数据库里的日程表本身，而不是本仓储实例的写入口：云快照恢复
  /// 直接事务替换整份账号数据、另一个仓储实例（同一数据库、另一个页面）
  /// 写入，都不会经过这个对象，却都必须让计划页与提醒看到新状态。
  ///
  /// 流仍显式构造而不是 `async*`：取消订阅要立即释放数据库观察，不能让一个
  /// 停在 `await for` 里的生成器等到下一次变更才醒来。
  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) {
    final watch = _ScheduleWatch(repository: this, from: from, to: to);
    _watches.add(watch);
    return watch.stream;
  }

  void _forgetWatch(_ScheduleWatch watch) => _watches.remove(watch);

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
    return existing.copyWith(
      title: title,
      notes: notes,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      allDay: window.allDay,
      allDayStartDate: window.allDayStartDate,
      allDayEndDateExclusive: window.allDayEndDateExclusive,
      taskId: taskId,
      clearTaskId: taskId == null,
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
            recurrenceId: Value(schedule.recurrenceId),
            recurrenceSeriesId: Value(schedule.recurrenceSeriesId),
            recurrenceDate: Value(schedule.recurrenceDate),
            recurrenceTimeZoneId: Value(schedule.recurrenceTimeZoneId),
            recurrenceStartMinutes: Value(schedule.recurrenceStartMinutes),
            isRecurrenceException: Value(schedule.isRecurrenceException),
            isRecurrenceCancelled: Value(schedule.isRecurrenceCancelled),
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
    recurrenceId: row.recurrenceId,
    recurrenceSeriesId: row.recurrenceSeriesId,
    recurrenceDate: row.recurrenceDate,
    recurrenceTimeZoneId: row.recurrenceTimeZoneId,
    recurrenceStartMinutes: row.recurrenceStartMinutes,
    isRecurrenceException: row.isRecurrenceException,
    isRecurrenceCancelled: row.isRecurrenceCancelled,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
  );

  Future<ScheduleRepeatRule?> _findRule(String ruleId) async {
    final row =
        await (database.select(database.localScheduleRecurrences)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.id.equals(ruleId)))
            .getSingleOrNull();
    if (row == null) return null;
    return _ruleFromRow(row);
  }

  /// 规则此刻是否仍属于本账号。
  ///
  /// 展开只在事务里读写，事务本身已经排除了交错；这一步是写入前的最后一道
  /// 身份检查，让"给已被整份替换掉的旧规则补实例"在结构上不可能发生。
  Future<bool> _ruleExists(String ruleId) async {
    final row =
        await (database.select(database.localScheduleRecurrences)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.id.equals(ruleId)))
            .getSingleOrNull();
    return row != null;
  }

  ScheduleRepeatRule _ruleFromRow(LocalScheduleRecurrence row) =>
      ScheduleRepeatRule(
        id: row.id,
        frequency: ScheduleRepeatFrequency.fromStorage(row.frequency),
        weekdays: {
          for (final value in _decodeIntegers(row.weekdays))
            if (value >= DateTime.monday && value <= DateTime.sunday) value,
        },
        firstDate: row.firstDate,
        endDate: row.endDate,
        timeZoneId: row.timeZoneId,
        allDay: row.allDay,
        startMinutesOfDay: row.startMinutesOfDay,
        durationMinutes: row.durationMinutes,
        daySpan: row.daySpan,
        shiftDays: row.shiftDays,
        title: row.title,
        notes: row.notes,
        taskId: row.taskId,
      );

  List<int> _decodeIntegers(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const [];
    return [
      for (final value in decoded)
        if (value is int) value,
    ];
  }

  Future<void> _saveRule(ScheduleRepeatRule rule, DateTime timestamp) async {
    await database
        .into(database.localScheduleRecurrences)
        .insertOnConflictUpdate(
          LocalScheduleRecurrencesCompanion.insert(
            userId: userId,
            id: rule.id,
            frequency: rule.frequency.storageValue,
            weekdays: Value(jsonEncode(rule.weekdays.toList()..sort())),
            firstDate: rule.firstDate,
            endDate: Value(rule.endDate),
            timeZoneId: rule.timeZoneId,
            allDay: Value(rule.allDay),
            startMinutesOfDay: Value(rule.startMinutesOfDay),
            durationMinutes: Value(rule.durationMinutes),
            daySpan: Value(rule.daySpan),
            shiftDays: Value(rule.shiftDays),
            title: Value(rule.title),
            notes: Value(rule.notes),
            taskId: Value(rule.taskId),
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
  }

  /// 规则被删除前，把它名下所有剩余行改挂到接手的规则上。
  ///
  /// 剩余行只有两种：墓碑（"用户删掉了这一期"）与已经过去的例外实例。二者都必须
  /// 保持有效引用，否则本机导出的快照会被引用校验拒绝；身份日期不变，所以取消
  /// 语义与完成状态随改期一起平移，也不会被新规则重新生成。
  Future<void> _reassignRuleRows(String fromRuleId, String toRuleId) async {
    await (database.update(database.localSchedules)
          ..where((row) => row.userId.equals(userId))
          ..where((row) => row.recurrenceId.equals(fromRuleId)))
        .write(LocalSchedulesCompanion(recurrenceId: Value(toRuleId)));
  }

  Future<void> _deleteRule(String ruleId) async {
    await (database.delete(database.localScheduleRecurrences)
          ..where((rule) => rule.userId.equals(userId))
          ..where((rule) => rule.id.equals(ruleId)))
        .go();
  }

  String _horizonEndDate(ScheduleRepeatRule rule) {
    final first = parseRecurrenceDate(rule.firstDate, '首日');
    final horizon = formatRecurrenceDate(
      DateTime.utc(
        first.year,
        first.month,
        first.day + recurrenceMaterializationHorizonDays - 1,
      ),
    );
    final end = rule.endDate;
    if (end != null && end.compareTo(horizon) < 0) return end;
    return horizon;
  }

  DateTime _zoneDate(DateTime instant, tz.Location location) {
    final local = tz.TZDateTime.from(instant.toUtc(), location);
    return DateTime.utc(local.year, local.month, local.day);
  }

  Future<Set<String>> _existingOccurrenceDates(String seriesId) async {
    final rows =
        await (database.select(database.localSchedules)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.recurrenceSeriesId.equals(seriesId)))
            .get();
    return {
      for (final row in rows)
        if (row.recurrenceDate != null) row.recurrenceDate!,
    };
  }

  /// 该系列仍存活的规则：由实例携带的规则归属反查，规则本身不带系列列。
  Future<List<ScheduleRepeatRule>> _rulesForSeries(String seriesId) async {
    final rows =
        await (database.select(database.localSchedules)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.recurrenceSeriesId.equals(seriesId)))
            .get();
    final ruleIds = {
      for (final row in rows)
        if (row.recurrenceId != null) row.recurrenceId!,
    };
    if (ruleIds.isEmpty) return const [];
    return [
      for (final rule in await getRecurrenceRules())
        if (ruleIds.contains(rule.id)) rule,
    ];
  }

  /// 该规则当前拥有实例时使用的稳定系列身份。
  ///
  /// "本次及以后"截断后新规则会接手原有实例，它们仍带着原系列身份；按系列
  /// 身份去重才能既不重复生成、也不把 UUID 当成标题。
  Future<String> _seriesIdForRule(String ruleId) async {
    final row =
        await (database.select(database.localSchedules)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.recurrenceId.equals(ruleId))
              ..orderBy([(row) => OrderingTerm(expression: row.startsAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.recurrenceSeriesId ?? ruleId;
  }

  /// 规则自己的内容模板。
  ///
  /// 模板随规则持久化：按范围补齐的实例只从所属规则取内容，"仅本次"例外
  /// 与更早的其它分段都不会污染它。只有模板列出现之前创建的旧规则才回退到
  /// 该系列最早的非例外实例。
  Future<({String title, String notes, String? taskId})?> _ruleTemplate(
    ScheduleRepeatRule rule,
    String seriesId,
  ) async {
    if (rule.title.trim().isNotEmpty) {
      return (title: rule.title, notes: rule.notes, taskId: rule.taskId);
    }
    return _seriesTemplate(seriesId);
  }

  /// 旧规则的兜底模板：该系列最早的一条**非例外**实例。
  ///
  /// 例外实例承载的是用户对某一次的改写，不能当作后续实例的模板。
  Future<({String title, String notes, String? taskId})?> _seriesTemplate(
    String seriesId,
  ) async {
    final row =
        await (database.select(database.localSchedules)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.recurrenceSeriesId.equals(seriesId))
              ..where((row) => row.isRecurrenceException.equals(false))
              ..orderBy([(row) => OrderingTerm(expression: row.startsAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return (title: row.title, notes: row.notes, taskId: row.taskId);
  }

  Future<List<Schedule>> _materializeRule({
    required ScheduleRepeatRule rule,
    required String seriesId,
    required String fromDate,
    required String toDate,
  }) async {
    if (!await _ruleExists(rule.id)) return const [];
    final startDate = fromDate.compareTo(rule.firstDate) < 0
        ? rule.firstDate
        : fromDate;
    // 范围整体落在规则开始之前（或结束之后）时没有实例可补：返回空集合，
    // 而不是把反向区间交给严格的日历展开去拒绝。
    if (startDate.compareTo(toDate) > 0) return const [];
    final dates = expandOccurrenceDates(
      rule,
      fromDate: startDate,
      toDate: toDate,
    );
    if (dates.isEmpty) return const [];
    final resolved = await _ruleTemplate(rule, seriesId);
    if (resolved == null) return const [];
    final existing = await _existingOccurrenceDates(seriesId);
    final created = <Schedule>[];
    for (final date in dates) {
      // 稳定身份 = 可见日期 - 改期位移；去重、取消与例外都按它对齐。
      final occurrenceDate = shiftRecurrenceDate(date, -rule.shiftDays);
      if (existing.contains(occurrenceDate)) continue;
      final window = resolveOccurrenceWindow(rule, date);
      final timestamp = _nextTimestamp();
      final schedule = Schedule(
        id: _uuid.v4(),
        title: resolved.title,
        notes: resolved.notes,
        startsAt: window.startsAt,
        endsAt: window.endsAt,
        allDay: window.allDay,
        allDayStartDate: window.allDayStartDate,
        allDayEndDateExclusive: window.allDayEndDateExclusive,
        taskId: resolved.taskId,
        recurrenceId: rule.id,
        recurrenceSeriesId: seriesId,
        recurrenceDate: occurrenceDate,
        recurrenceTimeZoneId: rule.timeZoneId,
        recurrenceStartMinutes: rule.allDay ? null : rule.startMinutesOfDay,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await _saveSchedule(schedule);
      created.add(schedule);
    }
    return created;
  }

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

  @override
  Future<void> dispose() async {
    // 关掉仍存活的观察，之后任何迟到的查询结果都不会再推给已取消/已切号的
    // 订阅者。
    final watches = _watches.toList();
    _watches.clear();
    for (final watch in watches) {
      await watch.close();
    }
  }
}

/// 一次 [LocalScheduleRepository.watchSchedules] 订阅背后的数据库观察。
///
/// 触发源是 drift 的表变更通知（本仓储写入、同库另一个仓储实例写入，以及云
/// 快照恢复在事务提交后显式发出的 notifyUpdates），因此边界是"这两张表变了"，
/// 具体内容仍以重新查询为准。范围物化会写行，所以查询自身也会被通知：相同
/// 结果按签名去重，不会把同一份旧数据反复推给订阅者，也不会形成自触发循环。
/// 取消订阅与仓储关闭都会释放观察，查询途中返回的旧结果直接丢弃。
class _ScheduleWatch {
  _ScheduleWatch({required this.repository, this.from, this.to});

  static const _tickQuery = 'SELECT 1 AS tick';

  final LocalScheduleRepository repository;
  final DateTime? from;
  final DateTime? to;

  late final StreamController<List<Schedule>> _controller =
      StreamController<List<Schedule>>(
        onListen: _start,
        onCancel: () => unawaited(close()),
      );
  StreamSubscription<void>? _changes;
  String? _signature;
  bool _closed = false;
  bool _running = false;
  bool _rerun = false;

  Stream<List<Schedule>> get stream => _controller.stream;

  PactaDatabase get _database => repository.database;

  void _start() {
    if (_closed) return;
    _changes = _database
        .customSelect(
          _tickQuery,
          readsFrom: {
            _database.localSchedules,
            _database.localScheduleRecurrences,
          },
        )
        .watch()
        .listen((_) => unawaited(_refresh()), onError: _emitError);
  }

  Future<void> _refresh() async {
    if (_closed || _controller.isClosed) return;
    if (_running) {
      // 本轮查询自己的物化写入会再发一次通知：合并成一次重读，不排成队列。
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        final List<Schedule> schedules;
        try {
          schedules = await repository.getSchedules(from: from, to: to);
        } catch (error, stackTrace) {
          _emitError(error, stackTrace);
          return;
        }
        // 取消或关闭可能发生在查询途中：旧结果绝不推给已经离开的订阅者。
        if (_closed || _controller.isClosed) return;
        final signature = _signatureOf(schedules);
        if (signature == _signature) continue;
        _signature = signature;
        _controller.add(schedules);
      } while (_rerun);
    } finally {
      _running = false;
    }
  }

  void _emitError(Object error, [StackTrace? stackTrace]) {
    if (_closed || _controller.isClosed) return;
    _controller.addError(error, stackTrace);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    repository._forgetWatch(this);
    final changes = _changes;
    _changes = null;
    if (changes != null) {
      try {
        await changes.cancel();
      } catch (_) {
        // 关库途中取消观察失败不改变"已经停止"这一事实。
      }
    }
    if (!_controller.isClosed) await _controller.close();
  }

  /// 结果签名：按行序拼出可观察到的身份与内容。updatedAt 由每次写入推进，
  /// 所以未变化的读取一定得到相同签名。
  String _signatureOf(List<Schedule> schedules) {
    final buffer = StringBuffer();
    for (final schedule in schedules) {
      buffer
        ..write(schedule.id)
        ..write('\u0001')
        ..write(schedule.updatedAt.toUtc().toIso8601String())
        ..write('\u0001')
        ..write(schedule.title)
        ..write('\u0001')
        ..write(schedule.startsAt.toUtc().toIso8601String())
        ..write('\u0001')
        ..write(schedule.endsAt.toUtc().toIso8601String())
        ..write('\u0001')
        ..write(schedule.isCompleted ? '1' : '0')
        ..write(schedule.isRecurrenceException ? '1' : '0')
        ..write(schedule.isRecurrenceCancelled ? '1' : '0')
        ..write('\u0002');
    }
    return buffer.toString();
  }
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

/// 未登录或快照未启用时使用的空实现：页面保持可见，但没有任何写入路径。
class UnavailableScheduleRepository implements ScheduleRepository {
  const UnavailableScheduleRepository();

  @override
  Future<CalendarImportPreview> previewCalendarImport(
    CalendarImportRequest request,
  ) => _unavailable();

  @override
  Future<CalendarImportOutcome> confirmCalendarImport(
    CalendarImportPreview preview,
  ) => _unavailable();

  @override
  Future<ScheduleSeries> createRecurringSchedule({
    required ScheduleDraft draft,
    required ScheduleRepeatSpec repeat,
    required String timeZoneId,
  }) => _unavailable();

  @override
  Future<ScheduleRepeatEditResult> editRecurringSchedule(
    String scheduleId, {
    required ScheduleDraft draft,
    required ScheduleRepeatScope scope,
    ScheduleRepeatSpec? repeat,
  }) => _unavailable();

  @override
  Future<List<ScheduleRepeatRule>> getRecurrenceRules() async => const [];

  @override
  Future<int> expandRecurrences({
    required DateTime from,
    required DateTime to,
  }) async => 0;

  @override
  Future<Schedule> createSchedule(ScheduleDraft draft) => _unavailable();

  @override
  Future<Schedule> updateSchedule(String scheduleId, ScheduleDraft draft) =>
      _unavailable();

  @override
  Future<Schedule> rescheduleSchedule(
    String scheduleId,
    ScheduleWindow window,
  ) => _unavailable();

  @override
  Future<void> deleteSchedule(String scheduleId) => _unavailable();

  @override
  Future<Schedule> setScheduleCompletion(
    String scheduleId, {
    required bool isCompleted,
  }) => _unavailable();

  @override
  Future<Schedule> setScheduleReminder(
    String scheduleId, {
    int? minutesBefore,
  }) => _unavailable();

  @override
  Future<List<Schedule>> getSchedules({DateTime? from, DateTime? to}) async =>
      const [];

  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) =>
      Stream.value(const []);

  @override
  Future<SchedulePromotionResult> promoteLegacyCalendarBlocks() =>
      _unavailable();

  @override
  Future<ScheduleMigrationStatus> getLegacyMigrationStatus() async =>
      ScheduleMigrationStatus(
        hasCompletedMigration: true,
        isRolledBack: false,
        canRollback: false,
        promotedCount: 0,
        sourceBlockCount: 0,
      );

  @override
  Future<ScheduleRollbackResult> rollbackLegacyCalendarBlockPromotion() =>
      _unavailable();

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async => throw StateError('日程功能需要登录后使用。');
}
