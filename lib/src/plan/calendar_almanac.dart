import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';

/// 读取随包年度表（`assets/holidays/<year>.json`）后构造。
///
/// 缺失年份直接跳过：新年度通知未发布或数据包未更新时，日历只是少了
/// 「休/班」标记，旧历与节气照常显示，不阻塞页面。更新方式见
/// assets/holidays/README.md。
Future<CalendarAlmanac> loadCalendarAlmanac({
  AssetBundle? bundle,
  int firstYear = 2020,
  int lastYear = 2027,
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
    } catch (_) {
      // 年度表缺失：保留已加载年份，继续。
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
/// 短标签优先级（用户已定案）：法定/传统节日 > 节气 > 旧历日；
/// 「休/班」排在节气之后、旧历日之前，使补班日不被旧历日淹没。
class CalendarAlmanac {
  CalendarAlmanac(Iterable<CalendarHoliday> days)
    : _byDate = {for (final d in days) d.date: d};

  final Map<String, CalendarHoliday> _byDate;

  bool get isEmpty => _byDate.isEmpty;

  CalendarDayInfo describe(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final key = _ymd(date);
    final entry = _byDate[key];
    final solar = Solar.fromYmd(date.year, date.month, date.day);
    final lunar = solar.getLunar();
    final lunarText = '${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}';
    // 只取中国传统节日：公历节日（情人节/圣诞等）不在本次范围内，
    // 否则补班日会被「情人节」盖掉，用户看不到「班」。
    final festivals = lunar.getFestivals();
    final jieQi = lunar.getJieQi();

    // 法定名里「国庆中秋」是组合名：同日双节应显示组合，不拆成「中秋」。
    final legal = entry?.name ?? '';
    final firstOfSpan = entry != null && _isFirstOfSpan(date, entry);
    final String label;
    if (entry?.kind == CalendarDayKind.workday) {
      // 补班日是一周里最容易被误读的一天：先标「班」，节日归属放详情。
      label = '班';
    } else if (legal.contains('国庆中秋') && firstOfSpan) {
      label = legal;
    } else if (festivals.isNotEmpty) {
      label = festivals.first;
    } else if (jieQi.isNotEmpty) {
      label = jieQi;
    } else if (legal.isNotEmpty && firstOfSpan) {
      // 元旦/劳动/国庆没有农历锚点：只在假期首日标名，其余日子标「休」，
      // 否则整段假期都会顶着同一个节日名，看不出哪天才是节日本身。
      label = legal;
    } else if (entry != null) {
      label = '休';
    } else {
      label = lunar.getDayInChinese() == '初一'
          ? '${lunar.getMonthInChinese()}月'
          : lunar.getDayInChinese();
    }

    final status = switch (entry?.kind) {
      CalendarDayKind.holiday => '放假',
      CalendarDayKind.workday => '补班',
      _ => '',
    };
    final span = entry == null ? '' : _spanText(date, entry);
    final detail = [
      '${date.year}年${date.month}月${date.day}日',
      lunarText,
      if (entry != null && entry.name.isNotEmpty) entry.name,
      if (status.isNotEmpty) '$status$span',
    ].join(' · ');

    return CalendarDayInfo(
      kind: entry?.kind ?? CalendarDayKind.ordinary,
      shortLabel: _clamp(label),
      detail: detail,
    );
  }

  /// 是否是该段同名假期的第一天。
  bool _isFirstOfSpan(DateTime day, CalendarHoliday entry) {
    final prev = _byDate[_ymd(day.subtract(const Duration(days: 1)))];
    return prev == null ||
        prev.kind != CalendarDayKind.holiday ||
        prev.name != entry.name;
  }

  /// 同名的连续放假区间，例如春节 2月15日–2月23日。
  String _spanText(DateTime day, CalendarHoliday entry) {
    if (entry.kind != CalendarDayKind.holiday) return '（${entry.name}调休）';
    var start = day;
    var end = day;
    while (true) {
      final prev = start.subtract(const Duration(days: 1));
      final e = _byDate[_ymd(prev)];
      if (e == null ||
          e.kind != CalendarDayKind.holiday ||
          e.name != entry.name) {
        break;
      }
      start = prev;
    }
    while (true) {
      final next = end.add(const Duration(days: 1));
      final e = _byDate[_ymd(next)];
      if (e == null ||
          e.kind != CalendarDayKind.holiday ||
          e.name != entry.name) {
        break;
      }
      end = next;
    }
    if (start == end) return '（${entry.name}）';
    return '（${start.month}月${start.day}日–${end.month}月${end.day}日）';
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 日期格第二行最多 4 字（用户定案），超长名按前 4 字截断。
  static String _clamp(String label) {
    final chars = label.characters;
    if (chars.length <= 4) return label;
    return chars.take(4).toString();
  }
}
