import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';

/// 结算点小时（账号时区当地墙钟时间）。
///
/// 墨墨背单词式的"按账号时区凌晨 4 点换天"：换天由账号时区决定，设备时区
/// 只影响显示，不移动结算边界。
const nationalFocusCheckpointHour = 4;

/// 北京时间 04:00 对应的 UTC 小时，保留给仍按 UTC 理解旧规则的调用方。
const nationalFocusCheckpointUtcHour = 20;

/// 一个自然日。
const nationalFocusCheckpointPeriod = Duration(days: 1);

/// 两次结算之间的最小间隔。
///
/// 账号时区改变时，相邻两次 04:00 在 UTC 上可能只差一两小时（例如从东九区
/// 切到东八区）。间隔不足 12 小时则顺延一个日历日，保证既不重复结算同一段
/// 时间，也绝不把 `lastSettledCheckpointAt` 往回拨。
const nationalFocusMinimumSettlementGap = Duration(hours: 12);

/// 账号尚未记录时区时的结算时区。
const nationalFocusDefaultTimeZoneId = 'Asia/Shanghai';

/// 把任意标识收敛成可用的时区：未知或为空一律回到北京时区。
timezone.Location _checkpointLocation(String? timeZoneId) {
  final fallback = timeZoneId != null && FocusTimeZones.contains(timeZoneId)
      ? timeZoneId
      : nationalFocusDefaultTimeZoneId;
  return FocusTimeZones.location(fallback);
}

/// 返回不晚于 [instant] 的最近一次 [timeZoneId] 当地 04:00。
///
/// 用日历日回退（`d - 1`）而不是减 24 小时，夏令时切换日仍然是当地 04:00。
DateTime nationalFocusCheckpointAtOrBefore(
  DateTime instant, {
  String timeZoneId = nationalFocusDefaultTimeZoneId,
}) {
  final location = _checkpointLocation(timeZoneId);
  final local = timezone.TZDateTime.from(instant.toUtc(), location);
  var checkpoint = timezone.TZDateTime(
    location,
    local.year,
    local.month,
    local.day,
    nationalFocusCheckpointHour,
  );
  if (checkpoint.isAfter(local)) {
    checkpoint = timezone.TZDateTime(
      location,
      local.year,
      local.month,
      local.day - 1,
      nationalFocusCheckpointHour,
    );
  }
  return checkpoint.toUtc();
}

/// 返回严格晚于 [instant] 的下一个 [timeZoneId] 当地 04:00。
///
/// 传入 [lastSettledCheckpointAt]（即上一次已结算的时刻）时，候选时刻与它的
/// 间隔不足 [nationalFocusMinimumSettlementGap] 就继续顺延日历日：切换时区
/// 后既不会在 12 小时内结算两次，也不会把已结算进度往回拨。
DateTime nextNationalFocusCheckpoint(
  DateTime instant, {
  String timeZoneId = nationalFocusDefaultTimeZoneId,
  DateTime? lastSettledCheckpointAt,
}) {
  final location = _checkpointLocation(timeZoneId);
  final anchor = timezone.TZDateTime.from(
    nationalFocusCheckpointAtOrBefore(instant, timeZoneId: timeZoneId),
    location,
  );
  var checkpoint = timezone.TZDateTime(
    location,
    anchor.year,
    anchor.month,
    anchor.day + 1,
    nationalFocusCheckpointHour,
  );
  final lastSettled = lastSettledCheckpointAt?.toUtc();
  if (lastSettled == null) return checkpoint.toUtc();
  while (checkpoint.toUtc().difference(lastSettled) <
      nationalFocusMinimumSettlementGap) {
    checkpoint = timezone.TZDateTime(
      location,
      checkpoint.year,
      checkpoint.month,
      checkpoint.day + 1,
      nationalFocusCheckpointHour,
    );
  }
  return checkpoint.toUtc();
}
