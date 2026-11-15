import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';

void main() {
  ScheduleRepeatRule rule({
    ScheduleRepeatFrequency frequency = ScheduleRepeatFrequency.daily,
    Set<int> weekdays = const {},
    String firstDate = '2026-11-16',
    String? endDate,
    String timeZoneId = 'Asia/Shanghai',
  }) => ScheduleRepeatRule(
    id: 'rule-1',
    frequency: frequency,
    weekdays: weekdays,
    firstDate: firstDate,
    endDate: endDate,
    timeZoneId: timeZoneId,
    allDay: false,
    startMinutesOfDay: 9 * 60,
    durationMinutes: 60,
    daySpan: 1,
  );

  group('每天', () {
    test('按日历日展开，不含结束日期之后的日期', () {
      final dates = expandOccurrenceDates(
        rule(endDate: '2026-11-18'),
        fromDate: '2026-11-16',
        toDate: '2026-11-30',
      );

      expect(dates, ['2026-11-16', '2026-11-17', '2026-11-18']);
    });

    test('查询范围早于首日时从首日开始', () {
      final dates = expandOccurrenceDates(
        rule(),
        fromDate: '2026-11-01',
        toDate: '2026-11-17',
      );

      expect(dates, ['2026-11-16', '2026-11-17']);
    });
  });

  group('每周指定星期', () {
    test('只展开选中的星期（1=周一，7=周日）', () {
      final dates = expandOccurrenceDates(
        rule(
          frequency: ScheduleRepeatFrequency.weekly,
          weekdays: {1, 3},
          firstDate: '2026-11-16',
        ),
        fromDate: '2026-11-16',
        toDate: '2026-11-29',
      );

      expect(dates, ['2026-11-16', '2026-11-18', '2026-11-23', '2026-11-25']);
    });

    test('结束日期当天仍是最后一次开始日', () {
      final dates = expandOccurrenceDates(
        rule(
          frequency: ScheduleRepeatFrequency.weekly,
          weekdays: {3},
          firstDate: '2026-11-16',
          endDate: '2026-11-25',
        ),
        fromDate: '2026-11-16',
        toDate: '2026-12-31',
      );

      expect(dates, ['2026-11-18', '2026-11-25']);
    });
  });

  group('边界', () {
    test('跨月与跨年按日历推进', () {
      final dates = expandOccurrenceDates(
        rule(firstDate: '2026-12-30', endDate: '2027-01-02'),
        fromDate: '2026-12-30',
        toDate: '2027-01-31',
      );

      expect(dates, ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02']);
    });

    test('闰日按日历推进', () {
      final dates = expandOccurrenceDates(
        rule(firstDate: '2028-02-28', endDate: '2028-03-01'),
        fromDate: '2028-02-28',
        toDate: '2028-03-02',
      );

      expect(dates, ['2028-02-28', '2028-02-29', '2028-03-01']);
    });

    test('范围过大整体拒绝，不做无界展开', () {
      expect(
        () => expandOccurrenceDates(
          rule(),
          fromDate: '2026-11-16',
          toDate: '2030-11-16',
        ),
        throwsArgumentError,
      );
    });

    test('倒置范围拒绝', () {
      expect(
        () => expandOccurrenceDates(
          rule(),
          fromDate: '2026-11-20',
          toDate: '2026-11-19',
        ),
        throwsArgumentError,
      );
    });
  });

  group('规则校验', () {
    test('每周必须至少选一个合法星期', () {
      expect(
        () => rule(frequency: ScheduleRepeatFrequency.weekly),
        throwsArgumentError,
      );
      expect(
        () => rule(frequency: ScheduleRepeatFrequency.weekly, weekdays: {0}),
        throwsArgumentError,
      );
      expect(
        () => rule(frequency: ScheduleRepeatFrequency.weekly, weekdays: {8}),
        throwsArgumentError,
      );
    });

    test('结束日期早于首日拒绝', () {
      expect(() => rule(endDate: '2026-11-15'), throwsArgumentError);
    });

    test('未知时区拒绝', () {
      expect(() => rule(timeZoneId: 'Mars/Olympus'), throwsArgumentError);
    });

    test('每天不携带星期集合', () {
      expect(() => rule(weekdays: {1}), throwsArgumentError);
    });
  });
}
