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
    required this.ownerId,
    required this.scheduleId,
    required this.dateKey,
  });

  static const String payloadPrefix = 'schedule-reminder:';

  /// The account that owned the reminder when it was registered.
  ///
  /// A delivered notification outlives the account binding, so activation must
  /// compare this value with the signed-in owner before opening anything.
  final String ownerId;
  final String scheduleId;

  /// The account-time-zone civil day of the reminder target, `YYYY-MM-DD`.
  final String dateKey;

  String toPayload() =>
      '$payloadPrefix${Uri.encodeComponent(ownerId)}:$scheduleId:$dateKey';

  static ScheduleReminderRequest? tryParse(String payload) {
    if (!payload.startsWith(payloadPrefix)) return null;
    final body = payload.substring(payloadPrefix.length);
    final ownerSeparator = body.indexOf(':');
    final dateSeparator = body.lastIndexOf(':');
    if (ownerSeparator <= 0 || dateSeparator <= ownerSeparator + 1) return null;
    final dateKey = body.substring(dateSeparator + 1);
    if (!_datePattern.hasMatch(dateKey)) return null;
    final String ownerId;
    try {
      ownerId = Uri.decodeComponent(body.substring(0, ownerSeparator));
    } catch (_) {
      return null;
    }
    if (ownerId.isEmpty) return null;
    return ScheduleReminderRequest(
      ownerId: ownerId,
      scheduleId: body.substring(ownerSeparator + 1, dateSeparator),
      dateKey: dateKey,
    );
  }

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
}

/// One ordinary schedule reminder that is still due after [ScheduleReminderPlanner.plan].
class ScheduleReminderPlan {
  const ScheduleReminderPlan({
    required this.ownerId,
    required this.identity,
    required this.notificationId,
    required this.scheduleId,
    required this.dateKey,
    required this.deliverAt,
    required this.title,
    required this.body,
  });

  /// The account that asked for this reminder.
  final String ownerId;

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
    ownerId: ownerId,
    scheduleId: scheduleId,
    dateKey: dateKey,
  ).toPayload();

  /// Full-content equality used to decide whether a registration is reusable.
  bool sameRegistration(ScheduleReminderPlan other) =>
      other.ownerId == ownerId &&
      other.identity == identity &&
      other.scheduleId == scheduleId &&
      other.dateKey == dateKey &&
      other.deliverAt.isAtSameMomentAs(deliverAt) &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;
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

  /// Largest stored reminder offset a schedule may carry.
  static const Duration maxReminderOffset = Duration(days: 7);

  static List<ScheduleReminderPlan> plan({
    required Iterable<Schedule> schedules,
    required DateTime now,
    required String timeZoneId,
    required String ownerId,
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
              ownerId: ownerId,
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

  /// Upper bound of a schedule query that must still see every deliverable
  /// reminder: an event may start after the delivery horizon when its stored
  /// offset pushes delivery inside the window.
  static DateTime queryEnd(DateTime now, {Duration horizon = horizon}) =>
      now.toUtc().add(horizon + maxReminderOffset);

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
      body: '${schedule.title}（$bodySuffix）',
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
  ///
  /// The probe step is coprime with the namespace size, so probing reaches every
  /// slot exactly once. Exhaustion throws instead of returning an occupied id.
  static Map<String, int> _allocate(List<String> identities) =>
      allocateIds(identities);

  /// Allocates platform ids for [identities]; public for collision and capacity
  /// regression tests. [spaceSize] defaults to the real namespace.
  static Map<String, int> allocateIds(
    List<String> identities, {
    int spaceSize = idSpaceSize,
  }) {
    final ids = <String, int>{};
    final taken = <int>{};
    for (final identity in identities) {
      final start = startIndexFor(identity, spaceSize: spaceSize);
      final step = _coprimeStep(_fnv1a(identity, seed: 0x9e3779b9), spaceSize);
      var index = start;
      var probes = 0;
      while (taken.contains(index)) {
        probes += 1;
        if (probes >= spaceSize) {
          throw StateError('schedule reminder id space exhausted');
        }
        index = (index + step) % spaceSize;
      }
      taken.add(index);
      ids[identity] = idSpaceBase + index;
    }
    return ids;
  }

  /// First candidate slot for [identity]; public so tests can construct real
  /// hash collisions instead of trusting a large sample.
  static int startIndexFor(String identity, {int spaceSize = idSpaceSize}) =>
      _fnv1a(identity) % spaceSize;

  static int _coprimeStep(int hash, int spaceSize) {
    if (spaceSize <= 1) return 1;
    var candidate = 1 + hash % (spaceSize - 1);
    var attempts = 0;
    while (_gcd(candidate, spaceSize) != 1) {
      candidate = candidate % (spaceSize - 1) + 1;
      attempts += 1;
      if (attempts > spaceSize) return 1;
    }
    return candidate;
  }

  static int _gcd(int left, int right) {
    var a = left;
    var b = right;
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a;
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
