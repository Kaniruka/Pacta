import 'focus_notification_plan.dart';

/// The next device-local National Focus reminder that still needs delivery.
///
/// Reminder wall-clock time is interpreted in Beijing time. This plan is only
/// about notification delivery; it never changes National Focus Checkpoints.
class NationalFocusReminderPlan {
  const NationalFocusReminderPlan({
    required this.dayKey,
    required this.scheduledAt,
    required this.isDeferred,
  });

  static const Duration _beijingOffset = Duration(hours: 8);

  final String dayKey;
  final DateTime scheduledAt;
  final bool isDeferred;

  static NationalFocusReminderPlan? next({
    required DateTime now,
    required int minuteOfDay,
    required bool hasPendingConfirmations,
    String? lastNotifiedDayKey,
    FocusNotificationPlan? activeFlow,
  }) {
    if (!hasPendingConfirmations) return null;
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw RangeError.range(minuteOfDay, 0, 24 * 60 - 1, 'minuteOfDay');
    }

    final nowUtc = now.toUtc();
    var beijingDate = _beijingDate(nowUtc);
    if (_dateKey(beijingDate) == lastNotifiedDayKey) {
      beijingDate = beijingDate.add(const Duration(days: 1));
    }

    final dayKey = _dateKey(beijingDate);
    final reminderAt = _reminderInstant(beijingDate, minuteOfDay);
    var scheduledAt = reminderAt.isAfter(nowUtc) ? reminderAt : nowUtc;
    var isDeferred = false;

    if (activeFlow?.isPaused == true) return null;
    final focusEndsAt = activeFlow?.focusEndsAt.toUtc();
    if (focusEndsAt != null && focusEndsAt.isAfter(scheduledAt)) {
      scheduledAt = focusEndsAt;
      isDeferred = true;
    }

    return NationalFocusReminderPlan(
      dayKey: dayKey,
      scheduledAt: scheduledAt,
      isDeferred: isDeferred,
    );
  }

  static DateTime _beijingDate(DateTime instantUtc) {
    final beijing = instantUtc.add(_beijingOffset);
    return DateTime.utc(beijing.year, beijing.month, beijing.day);
  }

  static DateTime _reminderInstant(DateTime beijingDate, int minuteOfDay) {
    final wallClock = DateTime.utc(
      beijingDate.year,
      beijingDate.month,
      beijingDate.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    return wallClock.subtract(_beijingOffset);
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
