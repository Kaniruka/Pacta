import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';

/// 随包年度表覆盖的年份（含端点）。
///
/// 只覆盖国务院已发布安排的年份：2028 起没有官方数据，不做规则推定。
/// 新年度通知发布后，补一个 JSON 并同步这里与 pubspec 的 assets 列表。
const int firstHolidayYear = 2020;
const int lastHolidayYear = 2027;

/// 读取随包年度表（`assets/holidays/<year>.json`）后构造。
///
/// 缺年份（资产未随包）时跳过，日历只是少了休/班标记；坏 JSON 直接抛出，
/// 不把数据错误伪装成「今年没有节假日」。
Future<CalendarAlmanac> loadCalendarAlmanac({
  AssetBundle? bundle,
  int firstYear = firstHolidayYear,
  int lastYear = lastHolidayYear,
}) async {
  final loader = bundle ?? rootBundle;
  final entries = <CalendarHoliday>[];
  for (var year = firstYear; year <= lastYear; year++) {
    try {
      final raw = await loader.loadString('assets/holidays/$year.json');
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        entries.addAll(CalendarHoliday.listFromJson(json));
      }
    } on FlutterError {
      // 该年资产不存在：跳过，不阻塞日历。
    }
  }
  return CalendarAlmanac(entries);
}

/// 一天的法定状态：放假、补班（调休上班）或普通日。
enum CalendarDayKind { ordinary, holiday, workday }

/// 一条法定节假日/调休记录。数据来自随包 JSON（按年、版本入库）。
class CalendarHoliday {
  const CalendarHoliday({
    required this.date,
    required this.name,
    required this.kind,
  });

  /// yyyy-MM-dd
  final String date;
  final String name;
  final CalendarDayKind kind;

  static List<CalendarHoliday> listFromJson(Map<String, dynamic> json) {
    final days = json['days'];
    if (days is! List) return const [];
    return [
      for (final raw in days)
        if (raw is Map<String, dynamic>)
          CalendarHoliday(
            date: raw['date'] as String,
            name: raw['name'] as String? ?? '',
            kind: raw['kind'] == 'workday'
                ? CalendarDayKind.workday
                : CalendarDayKind.holiday,
          ),
    ];
  }
}

/// 一天在日历上的呈现：第二行短标签 + 选中日详情。
class CalendarDayInfo {
  const CalendarDayInfo({
    required this.kind,
    required this.shortLabel,
    required this.detail,
  });

  final CalendarDayKind kind;
  final String shortLabel;
  final String detail;
}

/// 日历外部知识：法定节假日/调休（随包 JSON）+ 农历/节气（lunar）。
///
/// 纯函数：不读网络、不读时钟；资产加载由 [loadCalendarAlmanac] 在边界完成。
/// 短标签只取三档（用户定案）：法定/传统节日 > 节气 > 旧历日。
/// 放假/补班不进短标签，只进详情——与「详情显示完整旧历与放假/补班」一致。
class CalendarAlmanac {
  CalendarAlmanac(Iterable<CalendarHoliday> days)
    : _byDate = {for (final d in days) d.date: d};

  final Map<String, CalendarHoliday> _byDate;

  bool get isEmpty => _byDate.isEmpty;

  CalendarDayInfo describe(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final entry = _byDate[_ymd(date)];
    final solar = Solar.fromYmd(date.year, date.month, date.day);
    final lunar = solar.getLunar();
    final lunarText = '${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}';
    final festivals = lunar.getFestivals();
    final jieQi = lunar.getJieQi();

    // 法定名只在「这段假的第一天」出现：元旦/劳动/国庆没有农历锚点，
    // 整段都用同一个名字会看不出哪天才是节日本身。若这段假里另有同名节气
    // （清明），首日让位给节气，避免 4 月 3 日也被标成清明。
    final legal = entry?.name ?? '';
    final span = entry == null ? null : _spanOf(date, entry);
    final legalOnFirstDay =
        entry != null &&
        span != null &&
        span.$1 == date &&
        legal.isNotEmpty &&
        !_hasJieQiInSpan(span, legal);

    final String label;
    if (legalOnFirstDay) {
      label = legal;
    } else if (festivals.isNotEmpty) {
      label = festivals.first;
    } else if (jieQi.isNotEmpty) {
      label = jieQi;
    } else if (lunar.getDayInChinese() == '初一') {
      label = '${lunar.getMonthInChinese()}月';
    } else {
      label = lunar.getDayInChinese();
    }

    return CalendarDayInfo(
      kind: entry?.kind ?? CalendarDayKind.ordinary,
      shortLabel: _truncateLabel(label),
      detail: _detail(date, entry, lunarText, span),
    );
  }

  String _detail(
    DateTime date,
    CalendarHoliday? entry,
    String lunarText,
    (DateTime, DateTime)? span,
  ) {
    final status = switch (entry?.kind) {
      CalendarDayKind.holiday => '放假',
      CalendarDayKind.workday => '补班',
      _ => '',
    };
    final String suffix;
    if (entry == null) {
      suffix = '';
    } else if (entry.kind == CalendarDayKind.workday) {
      suffix = '$status（${entry.name}调休）';
    } else if (span != null && span.$1 != span.$2) {
      suffix =
          '$status（${span.$1.month}月${span.$1.day}日–${span.$2.month}月${span.$2.day}日）';
    } else {
      suffix = '$status（${entry.name}）';
    }
    return [
      '${date.year}年${date.month}月${date.day}日',
      lunarText,
      if (entry != null && entry.name.isNotEmpty) entry.name,
      if (suffix.isNotEmpty) suffix,
    ].join('，');
  }

  /// 与 [entry] 同名且相邻的连续日期区间（含端点）。
  (DateTime, DateTime)? _spanOf(DateTime day, CalendarHoliday entry) {
    if (entry.kind != CalendarDayKind.holiday) return null;
    var start = day;
    var end = day;
    while (true) {
      final prev = start.subtract(const Duration(days: 1));
      if (!_sameSpan(prev, entry)) break;
      start = prev;
    }
    while (true) {
      final next = end.add(const Duration(days: 1));
      if (!_sameSpan(next, entry)) break;
      end = next;
    }
    return (start, end);
  }

  bool _sameSpan(DateTime day, CalendarHoliday entry) {
    final other = _byDate[_ymd(day)];
    return other != null &&
        other.kind == CalendarDayKind.holiday &&
        other.name == entry.name;
  }

  bool _hasJieQiInSpan((DateTime, DateTime) span, String jieQiName) {
    for (
      var d = span.$1;
      !d.isAfter(span.$2);
      d = d.add(const Duration(days: 1))
    ) {
      if (Solar.fromYmd(d.year, d.month, d.day).getLunar().getJieQi() ==
          jieQiName) {
        return true;
      }
    }
    return false;
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 日期格第二行最多 4 字（用户定案），超长名按前 4 个字符截断。
  static String _truncateLabel(String label) {
    final chars = label.characters;
    return chars.length <= 4 ? label : chars.take(4).toString();
  }
}
