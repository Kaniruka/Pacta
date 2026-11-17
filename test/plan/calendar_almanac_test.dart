import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/plan/calendar_almanac.dart';

/// T1：旧历/节气/法定节假日与调休的统一描述。
///
/// 期望值来源：国务院办公厅通知原文（2025/2026/2027 三份已逐条核对）。
/// 断言写死外部可核对的事实，不复用实现换算。
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> _span(int y, int m, int d1, int d2) => [
  for (var d = d1; d <= d2; d++) _ymd(DateTime(y, m, d)),
];

/// 通知原文：放假区间。
final Map<int, Set<String>> _officialHolidays = {
  2025: {
    ..._span(2025, 1, 1, 1),
    ..._span(2025, 1, 28, 31),
    ..._span(2025, 2, 1, 4),
    ..._span(2025, 4, 4, 6),
    ..._span(2025, 5, 1, 5),
    ..._span(2025, 5, 31, 31),
    ..._span(2025, 6, 1, 2),
    ..._span(2025, 10, 1, 8),
  },
  2026: {
    ..._span(2026, 1, 1, 3),
    ..._span(2026, 2, 15, 23),
    ..._span(2026, 4, 4, 6),
    ..._span(2026, 5, 1, 5),
    ..._span(2026, 6, 19, 21),
    ..._span(2026, 9, 25, 27),
    ..._span(2026, 10, 1, 7),
  },
  2027: {
    ..._span(2027, 1, 1, 3),
    ..._span(2027, 2, 5, 13),
    ..._span(2027, 4, 3, 5),
    ..._span(2027, 5, 1, 5),
    ..._span(2027, 6, 9, 9),
    ..._span(2027, 9, 15, 15),
    ..._span(2027, 10, 1, 7),
  },
};

/// 通知原文：调休上班日。
const Map<int, Set<String>> _officialWorkdays = {
  2025: {'2025-01-26', '2025-02-08', '2025-04-27', '2025-09-28', '2025-10-11'},
  2026: {
    '2026-01-04',
    '2026-02-14',
    '2026-02-28',
    '2026-05-09',
    '2026-09-20',
    '2026-10-10',
  },
  2027: {'2027-01-31', '2027-02-14', '2027-05-08', '2027-09-26', '2027-10-09'},
};

Map<String, dynamic> _yearJson(int year) =>
    jsonDecode(File('assets/holidays/$year.json').readAsStringSync())
        as Map<String, dynamic>;

CalendarAlmanac _assetAlmanac() {
  final entries = <CalendarHoliday>[];
  for (var year = firstHolidayYear; year <= lastHolidayYear; year++) {
    entries.addAll(CalendarHoliday.listFromJson(_yearJson(year)));
  }
  return CalendarAlmanac(entries);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final almanac = _assetAlmanac();

  test('年份覆盖：2020–2027 每年都有随包表，上限与常量一致', () {
    expect(firstHolidayYear, 2020);
    expect(lastHolidayYear, 2027, reason: '2028 起没有官方数据，不得提前扩');
    for (var year = firstHolidayYear; year <= lastHolidayYear; year++) {
      final json = _yearJson(year);
      expect(json['year'], year, reason: '$year 文件自述年份');
      expect((json['days'] as List), isNotEmpty, reason: '$year 不应为空表');
    }
  });

  for (final year in [2025, 2026, 2027]) {
    test('通知原文全等校验：$year 放假与补班集合', () {
      final days = (_yearJson(year)['days'] as List)
          .cast<Map<String, dynamic>>();
      final holidays = {
        for (final d in days)
          if (d['kind'] == 'holiday') d['date'] as String,
      };
      final workdays = {
        for (final d in days)
          if (d['kind'] == 'workday') d['date'] as String,
      };
      expect(holidays, _officialHolidays[year], reason: '$year 放假集合必须与通知一致');
      expect(workdays, _officialWorkdays[year], reason: '$year 补班集合必须与通知一致');
    });
  }

  test('rootBundle 能读到年度表（资产声明正确）', () async {
    final loaded = await loadCalendarAlmanac();
    expect(loaded.isEmpty, isFalse);
    expect(loaded.describe(DateTime(2026, 2, 17)).shortLabel, '春节');
  });

  test('缺失年份被跳过而不抛错', () async {
    final loaded = await loadCalendarAlmanac(firstYear: 1999, lastYear: 1999);
    expect(loaded.isEmpty, isTrue);
  });

  test('春节初一：法定节日名进入短标签，详情含完整旧历与放假区间', () {
    final info = almanac.describe(DateTime(2026, 2, 17));
    expect(info.shortLabel, '春节');
    expect(info.kind, CalendarDayKind.holiday);
    expect(info.detail, contains('正月初一'));
    expect(info.detail, contains('放假'));
    expect(info.detail, contains('2月15日'));
    expect(info.detail, contains('2月23日'));
  });

  test('除夕：传统节日名优先于整段假期名', () {
    final info = almanac.describe(DateTime(2026, 2, 16));
    expect(info.shortLabel, '除夕');
    expect(info.kind, CalendarDayKind.holiday);
  });

  test('清明：法定节日与节气同日仍只出一个标签，假首日不被标成清明', () {
    expect(almanac.describe(DateTime(2026, 4, 5)).shortLabel, '清明');
    // 4/4 是假期第一天但清明节气在 4/5：首日让位，退回旧历日。
    expect(almanac.describe(DateTime(2026, 4, 4)).shortLabel, isNot('清明'));
  });

  test('补班日：短标签仍是旧历，详情说明补班归属', () {
    final info = almanac.describe(DateTime(2026, 2, 14));
    expect(info.kind, CalendarDayKind.workday);
    expect(info.shortLabel, isNot('班'), reason: '休/班只进详情，不进第二行');
    expect(info.detail, contains('补班'));
  });

  test('闰月：2025 闰六月初一按旧历原样显示', () {
    expect(almanac.describe(DateTime(2025, 7, 25)).detail, contains('闰六月'));
  });

  test('同天双节：2020-10-01 用组合名，整段假期区间不被切断', () {
    expect(almanac.describe(DateTime(2020, 10, 1)).shortLabel, '国庆中秋');
    // 10/2 在库里叫「国庆」，归并后应仍指向 10/1–10/8 这一段。
    final second = almanac.describe(DateTime(2020, 10, 2));
    expect(second.detail, contains('10月1日–10月8日'));
  });

  test('普通日回落到旧历日，短标签不超过 4 字', () {
    final info = almanac.describe(DateTime(2026, 3, 10));
    expect(info.kind, CalendarDayKind.ordinary);
    expect(info.shortLabel, '廿二');
  });

  test('2020–2027 每个日期的短标签都不超过 4 字且非空', () {
    for (var year = 2020; year <= 2027; year++) {
      for (
        var t = DateTime(year, 1, 1);
        t.year == year;
        t = t.add(const Duration(days: 1))
      ) {
        final label = almanac.describe(t).shortLabel;
        expect(
          label.characters.length,
          lessThanOrEqualTo(4),
          reason: '$t -> $label',
        );
        expect(label, isNotEmpty, reason: '$t 标签为空');
      }
    }
  });
}
