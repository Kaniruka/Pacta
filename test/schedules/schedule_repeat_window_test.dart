import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';

void main() {
  ScheduleRepeatRule rule({
    String timeZoneId = 'America/New_York',
    int startMinutesOfDay = 9 * 60,
    int durationMinutes = 60,
    bool allDay = false,
    int daySpan = 1,
  }) => ScheduleRepeatRule(
    id: 'rule-1',
    frequency: ScheduleRepeatFrequency.daily,
    weekdays: const {},
    firstDate: '2026-01-01',
    timeZoneId: timeZoneId,
    startMinutesOfDay: startMinutesOfDay,
    durationMinutes: durationMinutes,
    allDay: allDay,
    daySpan: daySpan,
  );

  group('挂钟算术不随夏令时漂移', () {
    test('跨春季前进日仍是同一个本地 09:00，UTC 偏移改变一小时', () {
      final before = resolveOccurrenceWindow(rule(), '2026-03-07');
      final after = resolveOccurrenceWindow(rule(), '2026-03-08');

      expect(before.startsAt, DateTime.utc(2026, 3, 7, 14));
      expect(after.startsAt, DateTime.utc(2026, 3, 8, 13));
      expect(
        after.startsAt.difference(before.startsAt),
        const Duration(hours: 23),
      );
    });

    test('跨秋季回退日仍是同一个本地 09:00', () {
      final before = resolveOccurrenceWindow(rule(), '2026-10-31');
      final after = resolveOccurrenceWindow(rule(), '2026-11-01');

      expect(before.startsAt, DateTime.utc(2026, 10, 31, 13));
      expect(after.startsAt, DateTime.utc(2026, 11, 1, 14));
    });
  });

  group('夏令时空隙与重叠', () {
    test('落在春季不存在的那一小时时向后顺移，仍是唯一瞬时', () {
      final window = resolveOccurrenceWindow(
        rule(startMinutesOfDay: 2 * 60 + 30),
        '2026-03-08',
      );

      expect(window.startsAt, DateTime.utc(2026, 3, 8, 7, 30));
      expect(window.endsAt, DateTime.utc(2026, 3, 8, 8, 30));
    });

    test('落在秋季重复的那一小时时取较早偏移', () {
      final window = resolveOccurrenceWindow(
        rule(startMinutesOfDay: 1 * 60 + 30),
        '2026-11-01',
      );

      expect(window.startsAt, DateTime.utc(2026, 11, 1, 5, 30));
    });

    test('跨越间隙的时长按实际经过时间计算', () {
      final window = resolveOccurrenceWindow(
        rule(startMinutesOfDay: 1 * 60, durationMinutes: 180),
        '2026-03-08',
      );

      expect(window.startsAt, DateTime.utc(2026, 3, 8, 6));
      expect(window.endsAt, DateTime.utc(2026, 3, 8, 9));
    });
  });

  group('其他时区与跨年', () {
    test('无夏令时城市按固定偏移换算', () {
      final window = resolveOccurrenceWindow(
        rule(timeZoneId: 'Asia/Shanghai', startMinutesOfDay: 23 * 60),
        '2026-12-31',
      );

      expect(window.startsAt, DateTime.utc(2026, 12, 31, 15));
    });

    test('南半球夏令时同样按挂钟计算', () {
      final window = resolveOccurrenceWindow(
        rule(timeZoneId: 'Australia/Lord_Howe', startMinutesOfDay: 2 * 60 + 15),
        '2026-10-04',
      );

      expect(window.startsAt, DateTime.utc(2026, 10, 3, 15, 45));
    });
  });

  group('全天实例', () {
    test('按日历日占位，结束日期为排除式', () {
      final window = resolveOccurrenceWindow(
        rule(allDay: true, daySpan: 2),
        '2026-03-08',
      );

      expect(window.allDay, isTrue);
      expect(window.allDayStartDate, '2026-03-08');
      expect(window.allDayEndDateExclusive, '2026-03-10');
      expect(window.startsAt, DateTime.utc(2026, 3, 8));
      expect(window.endsAt, DateTime.utc(2026, 3, 10));
    });

    test('跨年的全天实例仍按日历推进', () {
      final window = resolveOccurrenceWindow(
        rule(allDay: true, daySpan: 1),
        '2026-12-31',
      );

      expect(window.allDayEndDateExclusive, '2027-01-01');
    });
  });

  group('实例标识', () {
    test('实例标识由规则与本地日期稳定组成', () {
      expect(occurrenceIdentity('rule-1', '2026-11-16'), 'rule-1@2026-11-16');
      expect(
        occurrenceIdentity('rule-1', '2026-11-16'),
        occurrenceIdentity('rule-1', '2026-11-16'),
      );
      expect(
        occurrenceIdentity('rule-1', '2026-11-16'),
        isNot(occurrenceIdentity('rule-2', '2026-11-16')),
      );
    });
  });
}
