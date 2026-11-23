import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/ui/pacta_date_format.dart';

/// 显示层按账号时区格式化时刻；时区无效时退回本机，绝不改动时刻本身。
void main() {
  test('按账号时区格式化日期时间与时刻', () {
    final instant = DateTime.utc(2026, 9, 25, 20, 30);
    expect(
      formatPactaDateTimeInZone(instant, timeZoneId: 'Asia/Tokyo'),
      '2026-09-26 05:30',
    );
    expect(formatPactaTimeInZone(instant, timeZoneId: 'Asia/Tokyo'), '05:30');
    expect(
      formatPactaDateTimeInZone(instant, timeZoneId: 'America/New_York'),
      '2026-09-25 16:30',
    );
    expect(formatPactaTimeInZone(instant, timeZoneId: 'Etc/UTC'), '20:30');
  });

  test('时区缺失或未知时退回本机时区', () {
    final instant = DateTime.utc(2026, 9, 25, 20, 30);
    final local = instant.toLocal();
    final expected =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(formatPactaDateTimeInZone(instant), expected);
    expect(
      formatPactaDateTimeInZone(instant, timeZoneId: 'Mars/Olympus'),
      expected,
    );
    expect(formatPactaDateTime(instant), expected);
  });

  test('夏令时口径跟随 IANA 规则', () {
    expect(
      formatPactaTimeInZone(
        DateTime.utc(2026, 1, 15, 4),
        timeZoneId: 'Europe/London',
      ),
      '04:00',
    );
    expect(
      formatPactaTimeInZone(
        DateTime.utc(2026, 7, 15, 3),
        timeZoneId: 'Europe/London',
      ),
      '04:00',
    );
  });
}
