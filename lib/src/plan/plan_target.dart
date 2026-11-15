import '../schedules/schedule_repeat.dart';

/// 普通安排提醒被点击后要打开的 Plan 位置。
///
/// 通知本身由 06 负责；这里只约定"点开哪一个日历日/哪一条安排"，让 Plan
/// 选中正确日期并停留在日历视图，不启动专注流程、不创建专注记录。
///
/// 负载格式（06 生成，AppShell 路由）：
/// - `plan-day:<YYYY-MM-DD>`：打开该日的计划日历。
/// - `plan-item:<YYYY-MM-DD>:<scheduleId>`：打开该日并定位到这条安排。
///
/// 日期是账号显示时区的日历日，由通知侧按账号时区计算后写入；这里不再读
/// 设备时区，也不做第二个时区分支。
class PlanTarget {
  const PlanTarget({required this.day, this.scheduleId});

  /// 账号显示时区的日历日（只比较年月日）。
  final DateTime day;

  /// 要定位的已拥有安排；null 表示只打开这一天。
  final String? scheduleId;

  static const String dayPrefix = 'plan-day:';
  static const String itemPrefix = 'plan-item:';

  /// 解析 06 的通知负载；不是 Plan 目标时返回 null（交给专注/国策分支）。
  static PlanTarget? tryParse(String payload) {
    if (payload.startsWith(dayPrefix)) {
      final day = _parseDay(payload.substring(dayPrefix.length));
      return day == null ? null : PlanTarget(day: day);
    }
    if (payload.startsWith(itemPrefix)) {
      final rest = payload.substring(itemPrefix.length);
      final separator = rest.indexOf(':');
      if (separator <= 0) return null;
      final day = _parseDay(rest.substring(0, separator));
      final scheduleId = rest.substring(separator + 1).trim();
      if (day == null || scheduleId.isEmpty) return null;
      return PlanTarget(day: day, scheduleId: scheduleId);
    }
    return null;
  }

  static DateTime? _parseDay(String value) {
    try {
      final parsed = parseRecurrenceDate(value, '通知日期');
      return DateTime(parsed.year, parsed.month, parsed.day);
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlanTarget &&
      other.day.year == day.year &&
      other.day.month == day.month &&
      other.day.day == day.day &&
      other.scheduleId == scheduleId;

  @override
  int get hashCode => Object.hash(day.year, day.month, day.day, scheduleId);
}
