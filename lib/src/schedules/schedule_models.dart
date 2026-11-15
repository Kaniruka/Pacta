/// Where an owned schedule came from.
///
/// Every schedule belongs to Pacta. The only provenance currently recorded is a
/// one-time promotion of the legacy calendar-block projection, which keeps the
/// source identity so a later calendar import can skip what already exists.
enum ScheduleOrigin {
  owned,

  /// A copy of a system-calendar occurrence. Pacta owns the content; the
  /// source only supplies the identity used to skip repeated imports.
  calendarImport,
  legacyCalendarBlock;

  static ScheduleOrigin fromStorage(Object? value) => values.firstWhere(
    (origin) => origin.name == value,
    orElse: () => ScheduleOrigin.owned,
  );

  String get storageValue => name;
}

/// The time window of a schedule.
///
/// Timed schedules carry an instant range. All-day schedules keep their original
/// date range (start inclusive, end exclusive) as `YYYY-MM-DD` strings and derive
/// UTC midnight bounds from it; display layers apply the account time zone
/// preference, never a device-level rule.
class ScheduleWindow {
  const ScheduleWindow._({
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
  });

  factory ScheduleWindow.timed({
    required DateTime startsAt,
    required DateTime endsAt,
  }) => ScheduleWindow._(
    startsAt: startsAt.toUtc(),
    endsAt: endsAt.toUtc(),
    allDay: false,
  );

  factory ScheduleWindow.allDayDates({
    required String startDate,
    required String endDateExclusive,
  }) {
    final start = _parseDate(startDate, '开始日期');
    final end = _parseDate(endDateExclusive, '结束日期');
    if (!end.isAfter(start)) {
      throw ArgumentError('全天日程的结束日期必须晚于开始日期。');
    }
    return ScheduleWindow._(
      startsAt: DateTime.utc(start.year, start.month, start.day),
      endsAt: DateTime.utc(end.year, end.month, end.day),
      allDay: true,
      allDayStartDate: startDate,
      allDayEndDateExclusive: endDateExclusive,
    );
  }

  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;

  static DateTime _parseDate(String value, String label) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw ArgumentError('$label必须是 YYYY-MM-DD。');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw ArgumentError('$label无效。');
    return parsed;
  }
}

/// A Pacta-owned schedule. One schedule is one arrangement, never a focus
/// session: completing it does not touch tasks, chains or the focus calendar.
class Schedule {
  const Schedule({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
    this.notes = '',
    this.allDay = false,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
    this.isCompleted = false,
    this.completedAt,
    this.taskId,
    this.reminderMinutesBefore,
    this.origin = ScheduleOrigin.owned,
    this.sourceIds = const [],
    this.sourceNames = const [],
    this.sourceEventId,
    this.occurrenceId,
    this.eventIdentity,
  });

  final String id;
  final String title;
  final String notes;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;

  /// Manual completion only; focus time never completes a schedule.
  final bool isCompleted;
  final DateTime? completedAt;

  /// Null means the schedule stands alone (for example, picking up a parcel).
  final String? taskId;

  /// Optional reminder offset in minutes before [startsAt]. Notification
  /// delivery is not part of this model; an unset value produces no reminder.
  final int? reminderMinutesBefore;

  final ScheduleOrigin origin;

  /// Source calendar identity kept for later import deduplication. Empty for
  /// schedules created in the app.
  final List<String> sourceIds;
  final List<String> sourceNames;
  final String? sourceEventId;
  final String? occurrenceId;

  /// Structured import identity: every alias that proves this occurrence
  /// (synced provider identity and/or this installation's device row).
  ///
  /// Imported copies keep it across rescheduling and snapshot sync; other
  /// schedules leave it null.
  final String? eventIdentity;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasReminder => reminderMinutesBefore != null;

  ScheduleWindow get window => allDay
      ? ScheduleWindow._(
          startsAt: startsAt,
          endsAt: endsAt,
          allDay: true,
          allDayStartDate: allDayStartDate,
          allDayEndDateExclusive: allDayEndDateExclusive,
        )
      : ScheduleWindow.timed(startsAt: startsAt, endsAt: endsAt);

  /// A missed schedule stays as it is: it is never moved forward automatically.
  bool isOverdueAt(DateTime now) =>
      !isCompleted && endsAt.toUtc().isBefore(now.toUtc());
}

/// How far the one-time promotion of legacy calendar blocks got.
enum ScheduleMigrationState {
  completed,
  rolledBack;

  String get storageValue => name;
}

class SchedulePromotionResult {
  const SchedulePromotionResult({
    required this.migrationId,
    required this.promotedCount,
    required this.sourceBlockCount,
    required this.alreadyPromoted,
  });

  final String migrationId;
  final int promotedCount;
  final int sourceBlockCount;

  /// True when this account had already been promoted and nothing was written.
  final bool alreadyPromoted;
}

class ScheduleMigrationStatus {
  const ScheduleMigrationStatus({
    required this.hasCompletedMigration,
    required this.isRolledBack,
    required this.canRollback,
    required this.promotedCount,
    required this.sourceBlockCount,
    this.migrationId,
    this.completedAt,
  });

  final bool hasCompletedMigration;
  final bool isRolledBack;
  final bool canRollback;
  final int promotedCount;
  final int sourceBlockCount;
  final String? migrationId;
  final DateTime? completedAt;
}

class ScheduleRollbackResult {
  const ScheduleRollbackResult({
    required this.migrationId,
    required this.removedSchedules,
    required this.restoredBlocks,
  });

  final String migrationId;
  final int removedSchedules;
  final int restoredBlocks;
}

/// Fields the user edits on a schedule.
class ScheduleDraft {
  const ScheduleDraft({
    required this.title,
    required this.window,
    this.notes = '',
    this.taskId,
  });

  final String title;
  final String notes;
  final ScheduleWindow window;
  final String? taskId;
}
