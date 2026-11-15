import 'package:timezone/timezone.dart' as tz;

import '../focus/focus_time_zones.dart';
import 'schedule_models.dart';

/// 重复日程的频率。只支持用户已确认的两种：每天、每周指定星期。
///
/// 结束日期是规则属性，不是第三种频率；按次数结束、排除日期等 RRULE 语义
/// 不在此实现。
enum ScheduleRepeatFrequency {
  daily,
  weekly;

  static ScheduleRepeatFrequency fromStorage(Object? value) =>
      values.firstWhere(
        (frequency) => frequency.name == value,
        orElse: () => throw ArgumentError('未知的重复频率：$value'),
      );

  String get storageValue => name;
}

/// 一次重复修改的作用范围。
enum ScheduleRepeatScope {
  /// 只改这一个实例：原样保留该实例，改写结果记为持久例外。
  onlyThis,

  /// 从该实例起截断原规则，并以该实例为起点生成新规则。
  thisAndFuture;

  static ScheduleRepeatScope fromStorage(Object? value) => values.firstWhere(
    (scope) => scope.name == value,
    orElse: () => throw ArgumentError('未知的重复修改范围：$value'),
  );

  String get storageValue => name;
}

/// 单次展开最多跨越的天数与最多生成的日期数。
///
/// 展开必须有界：仓储按查询范围展开，任何超出上限的请求整体拒绝，而不是
/// 静默截断或无限循环。
const int maxRecurrenceExpansionDays = 400;
const int maxRecurrenceOccurrences = 400;

/// 创建系列时预先落库的实例天数。
///
/// 未来实例按查询范围按需补齐，因此这里不必一次展开到底；有界预生成让
/// 刚创建的系列在计划/看板上立即可见，也避免无结束日期的规则无限写入。
const int recurrenceMaterializationHorizonDays = 90;

const Map<int, String> weekdayLabels = {
  1: '一',
  2: '二',
  3: '三',
  4: '四',
  5: '五',
  6: '六',
  7: '日',
};

/// 重复规则：频率 + 星期集合 + 结束日期 + 规则自己的时区。
///
/// 规则自带 IANA 时区，展开时按该时区的挂钟日历计算，绝不读取设备或当前
/// 显示时区。模板（全天/开始分钟/时长/跨天数）属于规则的内部表示，用于
/// 从日期生成实例窗口；用户界面只暴露频率、星期与结束日期。
class ScheduleRepeatRule {
  ScheduleRepeatRule({
    required this.id,
    required this.frequency,
    required Set<int> weekdays,
    required this.firstDate,
    this.endDate,
    required this.timeZoneId,
    this.allDay = false,
    this.startMinutesOfDay = 0,
    this.durationMinutes = 60,
    this.daySpan = 1,
  }) : weekdays = Set.unmodifiable(weekdays) {
    if (!FocusTimeZones.contains(timeZoneId)) {
      throw ArgumentError('未知的时区：$timeZoneId');
    }
    final first = parseRecurrenceDate(firstDate, '首日');
    if (frequency == ScheduleRepeatFrequency.daily &&
        this.weekdays.isNotEmpty) {
      throw ArgumentError('每天的重复日程不携带星期集合。');
    }
    for (final weekday in this.weekdays) {
      if (weekday < DateTime.monday || weekday > DateTime.sunday) {
        throw ArgumentError('星期必须是 1（周一）到 7（周日）。');
      }
    }
    if (frequency == ScheduleRepeatFrequency.weekly && this.weekdays.isEmpty) {
      throw ArgumentError('每周的重复日程至少要选一个星期。');
    }
    final end = endDate;
    if (end != null && parseRecurrenceDate(end, '结束日期').isBefore(first)) {
      throw ArgumentError('结束日期不能早于首日。');
    }
    if (allDay) {
      if (daySpan < 1) throw ArgumentError('全天日程至少要占一天。');
    } else {
      if (startMinutesOfDay < 0 || startMinutesOfDay > 24 * 60 - 1) {
        throw ArgumentError('开始时间必须落在当天之内。');
      }
      if (durationMinutes < 1) throw ArgumentError('时长必须大于零。');
    }
  }

  final String id;
  final ScheduleRepeatFrequency frequency;

  /// ISO 星期（1=周一 … 7=周日）。每天频率下为空。
  final Set<int> weekdays;

  /// 首次可能开始的本地日期（规则时区）。
  final String firstDate;

  /// 最后一次可能开始的本地日期，含当天；null 表示不结束。
  final String? endDate;

  final String timeZoneId;
  final bool allDay;
  final int startMinutesOfDay;
  final int durationMinutes;
  final int daySpan;

  ScheduleRepeatRule copyWith({
    String? id,
    ScheduleRepeatFrequency? frequency,
    Set<int>? weekdays,
    String? firstDate,
    String? endDate,
    bool clearEndDate = false,
    String? timeZoneId,
    bool? allDay,
    int? startMinutesOfDay,
    int? durationMinutes,
    int? daySpan,
  }) => ScheduleRepeatRule(
    id: id ?? this.id,
    frequency: frequency ?? this.frequency,
    weekdays: weekdays ?? this.weekdays,
    firstDate: firstDate ?? this.firstDate,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    timeZoneId: timeZoneId ?? this.timeZoneId,
    allDay: allDay ?? this.allDay,
    startMinutesOfDay: startMinutesOfDay ?? this.startMinutesOfDay,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    daySpan: daySpan ?? this.daySpan,
  );

  @override
  bool operator ==(Object other) =>
      other is ScheduleRepeatRule &&
      other.id == id &&
      other.frequency == frequency &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.firstDate == firstDate &&
      other.endDate == endDate &&
      other.timeZoneId == timeZoneId &&
      other.allDay == allDay &&
      other.startMinutesOfDay == startMinutesOfDay &&
      other.durationMinutes == durationMinutes &&
      other.daySpan == daySpan;

  @override
  int get hashCode => Object.hash(
    id,
    frequency,
    Object.hashAllUnordered(weekdays),
    firstDate,
    endDate,
    timeZoneId,
    allDay,
    startMinutesOfDay,
    durationMinutes,
    daySpan,
  );

  @override
  String toString() =>
      'ScheduleRepeatRule($id, ${frequency.name}, $firstDate..${endDate ?? '∞'}, $timeZoneId)';
}

/// 严格解析 `YYYY-MM-DD` 为 UTC 日历日；不受本地时区影响。
DateTime parseRecurrenceDate(String value, String label) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw ArgumentError('$label必须是 YYYY-MM-DD。');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null) throw ArgumentError('$label无效。');
  return parsed;
}

String formatRecurrenceDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 在 [fromDate, toDate] 内按规则展开开始日期（本地日历日，含首尾）。
///
/// 展开有界：范围过宽或命中次数过多时整体拒绝。日期只做日历加法，不使用
/// 固定 86400 秒，因此不产生跨夏令时的漂移。
List<String> expandOccurrenceDates(
  ScheduleRepeatRule rule, {
  required String fromDate,
  required String toDate,
  int maxOccurrences = maxRecurrenceOccurrences,
}) {
  final from = parseRecurrenceDate(fromDate, '查询开始日期');
  final to = parseRecurrenceDate(toDate, '查询结束日期');
  if (to.isBefore(from)) {
    throw ArgumentError('查询结束日期不能早于开始日期。');
  }
  if (to.difference(from).inDays > maxRecurrenceExpansionDays) {
    throw ArgumentError('重复日程的展开范围过大，请缩小查询区间。');
  }
  final first = parseRecurrenceDate(rule.firstDate, '首日');
  final last = rule.endDate == null
      ? null
      : parseRecurrenceDate(rule.endDate!, '结束日期');
  var cursor = from.isAfter(first) ? from : first;
  final limit = last == null || to.isBefore(last) ? to : last;
  final dates = <String>[];
  while (!cursor.isAfter(limit)) {
    final matches =
        rule.frequency == ScheduleRepeatFrequency.daily ||
        rule.weekdays.contains(cursor.weekday);
    if (matches) {
      if (dates.length >= maxOccurrences) {
        throw ArgumentError('重复日程在本次范围内生成的实例过多，请缩小查询区间。');
      }
      dates.add(formatRecurrenceDate(cursor));
    }
    cursor = DateTime.utc(cursor.year, cursor.month, cursor.day + 1);
  }
  return dates;
}

/// 实例的稳定标识：规则 id + 该实例原始的本地开始日期。
///
/// "本次及以后"截断会生成新规则 id，但已有实例保留原规则 id 与原始日期，
/// 因此历史实例的身份不因后续规则修改而改变。
String occurrenceIdentity(String seriesId, String date) => '$seriesId@$date';

/// 从规则与本地日期解析出实例窗口。
///
/// 定时日程按**规则时区**的挂钟构造瞬时，全程做日历运算而不是累加 86400 秒：
///
/// * 春季不存在的挂钟时刻（DST 间隙）向后顺移到间隙结束，仍对应唯一瞬时；
/// * 秋季重复的挂钟时刻（DST 重叠）取较早的那个偏移（即夏令时一侧）；
/// * 时长按实际经过时间叠加，跨越间隙的一场会议不会因此变长或变短。
///
/// 全天日程沿用既有约定：起止是 `YYYY-MM-DD` 日历日，瞬时取该日期的 UTC
/// 零点，结束日期排除式。
ScheduleWindow resolveOccurrenceWindow(ScheduleRepeatRule rule, String date) {
  final day = parseRecurrenceDate(date, '实例日期');
  if (rule.allDay) {
    return ScheduleWindow.allDayDates(
      startDate: formatRecurrenceDate(day),
      endDateExclusive: formatRecurrenceDate(
        DateTime.utc(day.year, day.month, day.day + rule.daySpan),
      ),
    );
  }
  final location = FocusTimeZones.location(rule.timeZoneId);
  final local = tz.TZDateTime(
    location,
    day.year,
    day.month,
    day.day,
    rule.startMinutesOfDay ~/ 60,
    rule.startMinutesOfDay % 60,
  );
  final startsAt = local.toUtc();
  return ScheduleWindow.timed(
    startsAt: startsAt,
    endsAt: startsAt.add(Duration(minutes: rule.durationMinutes)),
  );
}

/// 用户可配置的重复设置：频率 + 星期集合 + 结束日期。
///
/// 时区由调用方注入账号时区（不读取设备或当前显示时区），窗口模板由首个
/// 实例的窗口推导；界面只暴露这三项。
class ScheduleRepeatSpec {
  const ScheduleRepeatSpec({
    required this.frequency,
    this.weekdays = const {},
    this.endDate,
  });

  final ScheduleRepeatFrequency frequency;

  /// ISO 星期（1=周一 … 7=周日）；每天频率下为空。
  final Set<int> weekdays;

  /// 最后一次可能开始的本地日期（含当天）；null 表示不结束。
  final String? endDate;

  ScheduleRepeatSpec copyWith({
    ScheduleRepeatFrequency? frequency,
    Set<int>? weekdays,
    String? endDate,
    bool clearEndDate = false,
  }) => ScheduleRepeatSpec(
    frequency: frequency ?? this.frequency,
    weekdays: weekdays ?? this.weekdays,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
  );

  @override
  bool operator ==(Object other) =>
      other is ScheduleRepeatSpec &&
      other.frequency == frequency &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.endDate == endDate;

  @override
  int get hashCode =>
      Object.hash(frequency, Object.hashAllUnordered(weekdays), endDate);
}

/// 由首个实例窗口与调用方注入的账号时区构造规则。
///
/// 首日是窗口开始时刻在该时区的日历日；定时日程的挂钟模板取当时的本地
/// 开始分钟与实际时长，全天日程取日历日跨度。规则校验（星期、结束日期、
/// 时区合法性）全部在构造函数里完成，非法规则不会被创建。
ScheduleRepeatRule buildRepeatRule({
  required String id,
  required ScheduleRepeatSpec spec,
  required ScheduleWindow window,
  required String timeZoneId,
}) {
  if (!FocusTimeZones.contains(timeZoneId)) {
    throw ArgumentError('未知的时区：$timeZoneId');
  }
  if (window.allDay) {
    final start = window.allDayStartDate;
    final end = window.allDayEndDateExclusive;
    if (start == null || end == null) {
      throw ArgumentError('全天日程缺少日历日区间。');
    }
    final daySpan = parseRecurrenceDate(
      end,
      '结束日期',
    ).difference(parseRecurrenceDate(start, '开始日期')).inDays;
    return ScheduleRepeatRule(
      id: id,
      frequency: spec.frequency,
      weekdays: spec.weekdays,
      firstDate: start,
      endDate: spec.endDate,
      timeZoneId: timeZoneId,
      allDay: true,
      daySpan: daySpan,
      durationMinutes: 0,
    );
  }
  final location = FocusTimeZones.location(timeZoneId);
  final local = tz.TZDateTime.from(window.startsAt.toUtc(), location);
  final durationMinutes = window.endsAt
      .toUtc()
      .difference(window.startsAt.toUtc())
      .inMinutes;
  if (durationMinutes < 1) {
    throw ArgumentError('重复日程的时长必须大于零分钟。');
  }
  return ScheduleRepeatRule(
    id: id,
    frequency: spec.frequency,
    weekdays: spec.weekdays,
    firstDate: formatRecurrenceDate(
      DateTime.utc(local.year, local.month, local.day),
    ),
    endDate: spec.endDate,
    timeZoneId: timeZoneId,
    startMinutesOfDay: local.hour * 60 + local.minute,
    durationMinutes: durationMinutes,
  );
}

/// 一次创建得到的系列：规则 + 已生成的实例。
class ScheduleSeries {
  const ScheduleSeries({required this.rule, required this.occurrences});

  final ScheduleRepeatRule rule;
  final List<Schedule> occurrences;
}

/// 一次重复修改的结果。
class ScheduleRepeatEditResult {
  const ScheduleRepeatEditResult({
    required this.updated,
    required this.rule,
    required this.generated,
    this.truncatedRule,
  });

  /// 被改写的那个实例。
  final Schedule updated;

  /// 改写后拥有它（以及后续实例）的规则：仅本次时是原规则。
  final ScheduleRepeatRule rule;

  /// 新生成的实例数。
  final int generated;

  /// "本次及以后"被截断的原规则；仅本次时为 null。
  final ScheduleRepeatRule? truncatedRule;
}
