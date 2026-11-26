import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/effective_duration_text.dart';
import 'package:pacta/src/national_focus/national_focus_ai_access.dart';
import 'package:pacta/src/ui/pacta_date_format.dart';

void main() {
  group('formatPactaRelativePast', () {
    final now = DateTime.utc(2026, 11, 26, 10, 0, 0);

    test('formats sub-minute, minutes, hours, days, and old dates', () {
      expect(
        formatPactaRelativePast(
          now.subtract(const Duration(seconds: 20)),
          now: now,
        ),
        '刚刚',
      );
      expect(
        formatPactaRelativePast(
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        '5 分钟前',
      );
      expect(
        formatPactaRelativePast(
          now.subtract(const Duration(hours: 3, minutes: 40)),
          now: now,
        ),
        '3 小时前',
      );
      expect(
        formatPactaRelativePast(
          now.subtract(const Duration(days: 6)),
          now: now,
        ),
        '6 天前',
      );
      expect(
        formatPactaRelativePast(
          DateTime.utc(2026, 9, 15, 2, 0),
          now: now,
          timeZoneId: 'Asia/Shanghai',
        ),
        '9月15日',
      );
      expect(
        formatPactaRelativePast(
          DateTime.utc(2025, 12, 31, 2, 0),
          now: now,
          timeZoneId: 'Asia/Shanghai',
        ),
        '2025-12-31',
      );
    });
  });

  group('formatPactaCompactRemaining', () {
    test(
      'uses compact English units and omits lower units at higher scales',
      () {
        expect(formatPactaCompactRemaining(Duration.zero), '已到期');
        expect(
          formatPactaCompactRemaining(const Duration(seconds: 42)),
          '42s 后',
        );
        expect(
          formatPactaCompactRemaining(const Duration(minutes: 45, seconds: 19)),
          '45m 后',
        );
        expect(
          formatPactaCompactRemaining(
            const Duration(hours: 18, minutes: 16, seconds: 30),
          ),
          '18h16m 后',
        );
        expect(
          formatPactaCompactRemaining(
            const Duration(days: 7, hours: 18, minutes: 16),
          ),
          '7d18h 后',
        );
        expect(
          formatPactaCompactRemaining(const Duration(days: 45, hours: 10)),
          '45d 后',
        );
      },
    );
  });

  group('formatEffectiveDuration & formatExactEffectiveDuration', () {
    test('omits seconds at 10 minutes or above while exact keeps seconds', () {
      expect(formatEffectiveDuration(0), '0分钟');
      expect(formatEffectiveDuration(45), '45秒');
      expect(formatEffectiveDuration(185), '3分5秒');
      expect(formatEffectiveDuration(300), '5分钟');
      expect(formatEffectiveDuration(599), '9分59秒');
      expect(formatEffectiveDuration(600), '10分钟');
      expect(formatEffectiveDuration(645), '10分钟');
      expect(formatEffectiveDuration(3903), '1小时5分');
      expect(formatEffectiveDuration(7200), '2小时');

      expect(formatExactEffectiveDuration(600), '10分00秒');
      expect(formatExactEffectiveDuration(3903), '1小时05分03秒');
    });

    test('compact focus duration omits seconds at 10 minutes or above', () {
      expect(formatCompactFocusDuration(0), '0分');
      expect(formatCompactFocusDuration(45), '45秒');
      expect(formatCompactFocusDuration(185), '3分5秒');
      expect(formatCompactFocusDuration(645), '10分');
      expect(formatCompactFocusDuration(4498), '1小时14分');
    });
  });

  group('parseCustomNationalFocusTtl', () {
    test('validates bounds across minutes, hours, and days', () {
      expect(
        parseCustomNationalFocusTtl('30', NationalFocusAiCustomTtlUnit.minutes),
        const Duration(minutes: 30),
      );
      expect(
        parseCustomNationalFocusTtl('12', NationalFocusAiCustomTtlUnit.hours),
        const Duration(hours: 12),
      );
      expect(
        parseCustomNationalFocusTtl('14', NationalFocusAiCustomTtlUnit.days),
        const Duration(days: 14),
      );
      expect(
        parseCustomNationalFocusTtl('0', NationalFocusAiCustomTtlUnit.days),
        isNull,
      );
      expect(
        parseCustomNationalFocusTtl('3651', NationalFocusAiCustomTtlUnit.days),
        isNull,
      );
      expect(
        parseCustomNationalFocusTtl('abc', NationalFocusAiCustomTtlUnit.hours),
        isNull,
      );
    });
  });
}
