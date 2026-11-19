import '../schedules/schedule_repeat.dart';

/// 普通安排提醒被点击后要打开的 Plan 位置。
///
/// 通知本身由 06 负责；这里只约定"点开哪一个日历日/哪一条安排"，让 Plan
/// 选中正确日期并停留在日历视图，不启动专注流程、不创建专注记录。
///
/// 负载格式（[encodeDay] / [encodeItem] 生成，[tryParse] 解析）：
/// - `plan-day:<YYYY-MM-DD>`：打开该日的计划日历。
/// - `plan-item:<YYYY-MM-DD>:<scheduleId>`：打开该日并定位到这条安排。
///
/// 普通日程提醒另用 `ScheduleReminderRequest` 的 `schedule-reminder:` 负载：
/// 通知必须带着所有者身份才能在跨账号点击时拒绝打开，因此那条路径不能只靠
/// 日期与安排 id。两套负载都由 AppShell 路由，计划页只认 [PlanTarget]。
///
/// `scheduleId` 在负载里按 URI 组件转义（[encodeItem] / [tryParse] 成对），
/// 因此标识自身含 `:`、`%`、空格等字符时不会被第一个冒号截断，也不会被
/// 误解成别的转义序列。日期是账号显示时区的日历日，由通知侧按账号时区计算
/// 后写入；这里不再读设备时区，也不做第二个时区分支。
class PlanTarget {
  const PlanTarget({required this.day, this.scheduleId});

  /// 账号显示时区的日历日（只比较年月日）。
  final DateTime day;

  /// 要定位的已拥有安排；null 表示只打开这一天。
  final String? scheduleId;

  static const String dayPrefix = 'plan-day:';
  static const String itemPrefix = 'plan-item:';

  /// 只打开某一天（按账号显示时区的公民日）。
  static String encodeDay(DateTime day) => '$dayPrefix${formatDay(day)}';

  /// 打开某一天并定位到一条已拥有的安排。
  ///
  /// 标识按 [Uri.encodeComponent] 转义，与 [tryParse] 的还原一一对应。标识
  /// 是 opaque 的：编码与还原都保留原字符串，连首尾空格也不裁掉，否则通知
  /// 会把用户带到另一个 id 上。只有**全空白的标识**才算调用方错误。
  static String encodeItem(DateTime day, String scheduleId) {
    if (scheduleId.trim().isEmpty) {
      throw ArgumentError.value(scheduleId, 'scheduleId', '安排标识不能为空');
    }
    return '$itemPrefix${formatDay(day)}:${Uri.encodeComponent(scheduleId)}';
  }

  /// 负载里的公民日文本（`YYYY-MM-DD`）。
  static String formatDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

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
      if (day == null) return null;
      final String scheduleId;
      try {
        scheduleId = Uri.decodeComponent(rest.substring(separator + 1));
      } catch (_) {
        // 非法转义（如孤立的 % 或坏 UTF-8）不是 Plan 目标，交给其他分支。
        return null;
      }
      // opaque 标识原样保留（含首尾空格）；只有全空白才视为缺失。
      if (scheduleId.trim().isEmpty) return null;
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
