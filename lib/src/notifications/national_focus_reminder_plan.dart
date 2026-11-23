import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import 'focus_notification_plan.dart';

/// The next device-local National Focus reminder that still needs delivery.
///
/// 提醒的墙钟时间按账号时区解释（默认北京时间），所以人在国外、账号仍设成
/// 北京时区时，提醒落在账号当地的 22:00。时区无效时回到北京时间。这个计划
/// 只负责通知投递，永远不改变国策检查点。
class NationalFocusReminderPlan {
  const NationalFocusReminderPlan({
    required this.dayKey,
    required this.scheduledAt,
    required this.isDeferred,
  });

  /// 未指定时区时的提醒时区，即旧的北京时间行为。
  static const String defaultTimeZoneId = 'Asia/Shanghai';

  final String dayKey;
  final DateTime scheduledAt;
  final bool isDeferred;

  static NationalFocusReminderPlan? next({
    required DateTime now,
    required int minuteOfDay,
    required bool hasPendingConfirmations,
    String? lastNotifiedDayKey,
    FocusNotificationPlan? activeFlow,
    String timeZoneId = defaultTimeZoneId,
  }) {
    if (!hasPendingConfirmations) return null;
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw RangeError.range(minuteOfDay, 0, 24 * 60 - 1, 'minuteOfDay');
    }

    final location = _locationFor(timeZoneId);
    final nowUtc = now.toUtc();
    var localDate = _dateInZone(nowUtc, location);
    if (_dateKey(localDate) == lastNotifiedDayKey) {
      localDate = localDate.add(const Duration(days: 1));
    }

    final dayKey = _dateKey(localDate);
    final reminderAt = _reminderInstant(localDate, minuteOfDay, location);
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

  static timezone.Location _locationFor(String timeZoneId) =>
      FocusTimeZones.location(
        FocusTimeZones.contains(timeZoneId) ? timeZoneId : defaultTimeZoneId,
      );

  static DateTime _dateInZone(DateTime instantUtc, timezone.Location location) {
    final local = timezone.TZDateTime.from(instantUtc, location);
    return DateTime.utc(local.year, local.month, local.day);
  }

  static DateTime _reminderInstant(
    DateTime localDate,
    int minuteOfDay,
    timezone.Location location,
  ) => timezone.TZDateTime(
    location,
    localDate.year,
    localDate.month,
    localDate.day,
    minuteOfDay ~/ 60,
    minuteOfDay % 60,
  ).toUtc();

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
