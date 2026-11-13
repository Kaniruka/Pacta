/// The next device-local daily reminder that still needs delivery.
///
/// The reminder follows this device's local wall clock, so a reminder time is
/// kept across daylight-saving changes. Past days are never replayed: when the
/// app has been closed or the device was off, only the next local occurrence is
/// planned, which keeps multi-day backlog from accumulating.
class DailyOpenReminderPlan {
  const DailyOpenReminderPlan({
    required this.dayKey,
    required this.scheduledAt,
  });

  final String dayKey;
  final DateTime scheduledAt;

  static DailyOpenReminderPlan next({
    required DateTime now,
    required int minuteOfDay,
  }) {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw RangeError.range(minuteOfDay, 0, 24 * 60 - 1, 'minuteOfDay');
    }
    final local = now.toLocal();
    final hour = minuteOfDay ~/ 60;
    final minute = minuteOfDay % 60;
    var candidate = DateTime(local.year, local.month, local.day, hour, minute);
    if (!candidate.isAfter(local)) {
      candidate = DateTime(
        local.year,
        local.month,
        local.day + 1,
        hour,
        minute,
      );
    }
    return DailyOpenReminderPlan(
      dayKey: dateKey(candidate),
      scheduledAt: candidate,
    );
  }

  /// The local calendar day of [value] as an ordering-safe key.
  static String dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
