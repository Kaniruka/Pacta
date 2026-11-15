import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../schedules/schedule_models.dart';

/// The user-facing destination of one delivered ordinary schedule reminder.
///
/// The payload carries the schedule and the account civil day it belongs to so
/// a later Plan destination can open that day. It never carries a focus
/// session or appointment identity: a reminder is not a commitment.
class ScheduleReminderRequest {
  const ScheduleReminderRequest({
    required this.scheduleId,
    required this.dateKey,
  });

  static const String payloadPrefix = 'schedule-reminder:';

  final String scheduleId;

  /// The account-time-zone civil day of the reminder target, `YYYY-MM-DD`.
  final String dateKey;

  String toPayload() => '$payloadPrefix$scheduleId:$dateKey';

  static ScheduleReminderRequest? tryParse(String payload) {
    if (!payload.startsWith(payloadPrefix)) return null;
    final body = payload.substring(payloadPrefix.length);
    final separator = body.lastIndexOf(':');
    if (separator <= 0 || separator == body.length - 1) return null;
    final dateKey = body.substring(separator + 1);
    if (!_datePattern.hasMatch(dateKey)) return null;
    return ScheduleReminderRequest(
      scheduleId: body.substring(0, separator),
      dateKey: dateKey,
    );
  }

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
}

/// One ordinary schedule reminder that is still due after [ScheduleReminderPlanner.plan].
class ScheduleReminderPlan {
  const ScheduleReminderPlan({
    required this.identity,
    required this.notificationId,
    required this.scheduleId,
    required this.dateKey,
    required this.deliverAt,
    required this.title,
    required this.body,
  });

  /// Stable identity of the reminder target.
  ///
  /// A single schedule keeps its row id; one recurring instance keeps its
  /// original series and original local date, so a later rule split or display
  /// time zone change does not move the identity of history.
  final String identity;

  /// Device-local platform notification id inside the reserved namespace.
  final int notificationId;
  final String scheduleId;
  final String dateKey;

  /// The exact instant the platform should deliver at, in UTC.
  final DateTime deliverAt;
  final String title;
  final String body;

  String get payload => ScheduleReminderRequest(
    scheduleId: scheduleId,
    dateKey: dateKey,
  ).toPayload();
}

/// Resolves owned schedules into platform delivery plans.
///
/// Ordinary reminders never create a focus session, an appointment or a chain
/// record; this planner only turns the persisted business times into delivery
/// instants. Business offsets stay authoritative: a timed schedule delivers at
/// its stored start instant minus the stored minute offset, and an all-day
/// schedule resolves the account civil day boundary at its midnight, never an
/// invented wall-clock hour and never the device zone.
class ScheduleReminderPlanner {
  ScheduleReminderPlanner._();

  /// Reserved id namespace, deliberately outside the 2200-2205 focus ids.
  static const int idSpaceBase = 230000;
  static const int idSpaceSize = 100000;

  /// Future delivery window; anything beyond needs a later reconciliation.
  static const Duration horizon = Duration(days: 90);

  static bool _timeZonesInitialized = false;

  static List<ScheduleReminderPlan> plan({
    required Iterable<Schedule> schedules,
    required DateTime now,
    required String timeZoneId,
    String? ownerUserId,
    Duration horizon = horizon,
  }) {
    final location = _locationFor(timeZoneId);
    final nowUtc = now.toUtc();
    final windowEnd = nowUtc.add(horizon);
    final targets = <String, _Target>{};
    for (final schedule in schedules) {
      if (!schedule.hasReminder || schedule.isCompleted) continue;
      if (schedule.isRecurrenceCancelled) continue;
      final minutes = schedule.reminderMinutesBefore;
      if (minutes == null || minutes < 0) continue;
      final target = _targetFor(schedule, minutes: minutes, location: location);
      if (target == null) continue;
      if (!target.deliverAt.isAfter(nowUtc)) continue;
      if (target.deliverAt.isAfter(windowEnd)) continue;
      final previous = targets[target.identity];
      // A duplicate identity is one target; the earliest delivery wins so a
      // stale copy can never outlive its corrected time.
      if (previous == null || target.deliverAt.isBefore(previous.deliverAt)) {
        targets[target.identity] = target;
      }
    }

    final identities = targets.keys.toList()..sort();
    final ids = _allocate(identities);
    final plans =
        [
          for (final identity in identities)
            ScheduleReminderPlan(
              identity: identity,
              notificationId: ids[identity]!,
              scheduleId: targets[identity]!.scheduleId,
              dateKey: targets[identity]!.dateKey,
              deliverAt: targets[identity]!.deliverAt,
              title: '日程提醒',
              body: targets[identity]!.body,
            ),
        ]..sort((left, right) {
          final byTime = left.deliverAt.compareTo(right.deliverAt);
          return byTime != 0 ? byTime : left.identity.compareTo(right.identity);
        });
    return plans;
  }

  /// Every platform id this planner may legitimately own.
  static bool ownsNotificationId(int id) =>
      id >= idSpaceBase && id < idSpaceBase + idSpaceSize;

  static _Target? _targetFor(
    Schedule schedule, {
    required int minutes,
    required timezone.Location location,
  }) {
    final offset = Duration(minutes: minutes);
    final DateTime boundary;
    final String dateKey;
    final String bodySuffix;
    if (schedule.allDay) {
      final date = schedule.allDayStartDate ?? _utcDateKey(schedule.startsAt);
      final parsed = _parseDate(date);
      if (parsed == null) return null;
      boundary = timezone.TZDateTime(
        location,
        parsed.year,
        parsed.month,
        parsed.day,
      ).toUtc();
      dateKey = date;
      bodySuffix = '全天';
    } else {
      boundary = schedule.startsAt.toUtc();
      final local = timezone.TZDateTime.from(boundary, location);
      dateKey = _dateKey(local.year, local.month, local.day);
      bodySuffix = '${_two(local.hour)}:${_two(local.minute)} 开始';
    }
    return _Target(
      identity: _identity(schedule),
      scheduleId: schedule.id,
      dateKey: dateKey,
      deliverAt: boundary.subtract(offset),
      body: '${schedule.title} · $bodySuffix',
    );
  }

  static String _identity(Schedule schedule) {
    if (schedule.isRecurring) {
      final series = schedule.recurrenceSeriesId ?? schedule.recurrenceId;
      final date = schedule.recurrenceDate ?? _utcDateKey(schedule.startsAt);
      return 'series:$series:$date';
    }
    return 'schedule:${schedule.id}';
  }

  /// Deterministic id allocation with open addressing for hash collisions.
  static Map<String, int> _allocate(List<String> identities) {
    final ids = <String, int>{};
    final taken = <int>{};
    for (final identity in identities) {
      final start = _fnv1a(identity) % idSpaceSize;
      final step = 1 + _fnv1a(identity, seed: 0x9e3779b9) % (idSpaceSize - 1);
      var offset = 0;
      var index = start;
      while (taken.contains(index) && offset < idSpaceSize) {
        offset += 1;
        index = (start + offset * step) % idSpaceSize;
      }
      taken.add(index);
      ids[identity] = idSpaceBase + index;
    }
    return ids;
  }

  static int _fnv1a(String value, {int seed = 0x811c9dc5}) {
    var hash = seed & 0xFFFFFFFF;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static timezone.Location _locationFor(String timeZoneId) {
    if (!_timeZonesInitialized) {
      timezone_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    try {
      return timezone.getLocation(timeZoneId);
    } catch (_) {
      // An unknown account value falls back to the documented account
      // fallback, never to the device zone.
      return timezone.getLocation('Etc/UTC');
    }
  }

  static DateTime? _parseDate(String value) {
    final matched = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (matched == null) return null;
    final year = int.tryParse(matched.group(1)!);
    final month = int.tryParse(matched.group(2)!);
    final day = int.tryParse(matched.group(3)!);
    if (year == null || month == null || day == null) return null;
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static String _utcDateKey(DateTime value) {
    final utc = value.toUtc();
    return _dateKey(utc.year, utc.month, utc.day);
  }

  static String _dateKey(int year, int month, int day) =>
      '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

  static String _two(int value) => _pad(value, 2);

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}

class _Target {
  const _Target({
    required this.identity,
    required this.scheduleId,
    required this.dateKey,
    required this.deliverAt,
    required this.body,
  });

  final String identity;
  final String scheduleId;
  final String dateKey;
  final DateTime deliverAt;
  final String body;
}
