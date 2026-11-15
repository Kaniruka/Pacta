import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../auth/user_lifecycle.dart';
import '../focus/focus_time_zones.dart';
import '../tasks/task_database.dart';
import 'schedule_migration.dart';
import 'schedule_models.dart';
import 'schedule_repeat.dart';

/// Pacta-owned schedules. Every write goes through the local database and is
/// carried by the whole-account business snapshot; there is no per-entity
/// remote and no system-calendar write path.
abstract interface class ScheduleRepository {
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
    final updated = existing.copyWith(
      isCompleted: isCompleted,
      completedAt: completedAt,
      clearCompletedAt: !isCompleted,
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
    final updated = existing.copyWith(
      reminderMinutesBefore: minutesBefore,
      clearReminder: minutesBefore == null,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
    await _saveSchedule(updated);
    await _publish();
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
    if (occurrences.isNotEmpty) await _publish();
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
    await _publish();
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
    final rules = await getRecurrenceRules();
    if (rules.isEmpty) return 0;
    var generated = 0;
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

  Future<void> _publish() async {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> dispose() async => _changes.close();
}
