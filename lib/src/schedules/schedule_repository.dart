import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../auth/user_lifecycle.dart';
import '../tasks/task_database.dart';
import 'schedule_migration.dart';
import 'schedule_models.dart';

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

/// 未登录或快照未启用时使用的空实现：页面保持可见，但没有任何写入路径。
class UnavailableScheduleRepository implements ScheduleRepository {
  const UnavailableScheduleRepository();

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
