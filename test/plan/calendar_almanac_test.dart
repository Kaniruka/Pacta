import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/plan/calendar_almanac.dart';

/// T1：旧历/节气/法定节假日与调休的统一描述。
///
/// 期望值来源：国务院办公厅通知原文（2025/2026/2027 三份已逐条核对），
/// 农历与节气来自 lunar 1.7.9；断言只写死外部可核对的事实，不复用实现换算。
CalendarAlmanac _assetAlmanac() {
  final entries = <CalendarHoliday>[];
  for (var year = 2020; year <= 2027; year++) {
    final json = jsonDecode(
      File('assets/holidays/$year.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    entries.addAll(CalendarHoliday.listFromJson(json));
  }
  return CalendarAlmanac(entries);
}

void main() {
  final almanac = _assetAlmanac();

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

  test('清明：法定节日与节气同日仍只出一个标签', () {
    final info = almanac.describe(DateTime(2026, 4, 5));
    expect(info.shortLabel, '清明');
    expect(info.kind, CalendarDayKind.holiday);
  });

  test('补班日：短标签为「班」，详情说明补班归属', () {
    final info = almanac.describe(DateTime(2026, 2, 14));
    expect(info.shortLabel, '班');
    expect(info.kind, CalendarDayKind.workday);
    expect(info.detail, contains('补班'));
  });

  test('闰月：2025 闰六月初一按旧历原样显示', () {
    final info = almanac.describe(DateTime(2025, 7, 25));
    expect(info.detail, contains('闰六月'));
  });

  test('同天双节：2020-10-01 用组合名，不拆成两个', () {
    final info = almanac.describe(DateTime(2020, 10, 1));
    expect(info.shortLabel, '国庆中秋');
  });

  test('普通日回落到旧历日，短标签不超过 4 字', () {
    final info = almanac.describe(DateTime(2026, 3, 10));
    expect(info.kind, CalendarDayKind.ordinary);
    expect(info.shortLabel.characters.length, lessThanOrEqualTo(4));
    expect(info.shortLabel, '廿二');
  });

  test('2020–2027 每个日期的短标签都不超过 4 字', () {
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
