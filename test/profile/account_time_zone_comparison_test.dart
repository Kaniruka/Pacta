import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/account_time_zone.dart';

/// 账号时区是留学生的核心设置：城市名单必须覆盖主流留学地区并按 IANA
/// 处理夏令时，结算说明必须把账号时区的 04:00 换算成本机设备时间。
void main() {
  test('城市名单覆盖主流留学地区，且保留 IANA 标识', () {
    final ids = {for (final city in AccountTimeZones.cities) city.timeZoneId};
    expect(AccountTimeZones.cities, hasLength(17));
    expect(ids, hasLength(AccountTimeZones.cities.length));
    expect(
      ids,
      containsAll(<String>[
        'Asia/Shanghai',
        'Asia/Hong_Kong',
        'Asia/Singapore',
        'Asia/Tokyo',
        'Asia/Seoul',
        'Australia/Sydney',
        'Australia/Melbourne',
        'Pacific/Auckland',
        'Europe/London',
        'Europe/Paris',
        'Europe/Berlin',
        'America/Toronto',
        'America/Vancouver',
        'America/New_York',
        'America/Chicago',
        'America/Los_Angeles',
        'Etc/UTC',
      ]),
    );
    expect(AccountTimeZones.fallbackId, 'Etc/UTC');
    expect(AccountTimeZones.cityFor('Australia/Sydney')?.label, '悉尼');
    expect(AccountTimeZones.cityFor('Antarctica/Troll'), isNull);
    expect(AccountTimeZones.isKnown(null), isFalse);
    expect(AccountTimeZones.isKnown('Mars/Olympus'), isFalse);
    expect(AccountTimeZones.effectiveId(null), 'Etc/UTC');
    expect(AccountTimeZones.effectiveId('Asia/Tokyo'), 'Asia/Tokyo');
  });

  test('未设或未知时区按北京时间结算，已知时区跟随账号', () {
    expect(AccountTimeZones.defaultNationalFocusTimeZoneId, 'Asia/Shanghai');
    expect(AccountTimeZones.checkpointTimeZoneId(null), 'Asia/Shanghai');
    expect(
      AccountTimeZones.checkpointTimeZoneId('Mars/Olympus'),
      'Asia/Shanghai',
    );
    expect(
      AccountTimeZones.checkpointTimeZoneId('America/New_York'),
      'America/New_York',
    );
  });

  test('东六区账号在东八区手机上显示 06:00 的设备对照', () {
    // 达卡 04:00（+06）= 前一日 22:00Z = 东八区 06:00。
    expect(
      AccountTimeZones.formatCheckpointComparison(
        accountTimeZoneId: 'Asia/Dhaka',
        referenceUtc: DateTime.utc(2026, 9, 25, 12),
        deviceOffsetOverride: const Duration(hours: 8),
      ),
      '每日结算：账号时区 04:00（当前设备时间 06:00）',
    );
  });

  test('设备与账号时区偏移相同时只说 04:00', () {
    expect(
      AccountTimeZones.formatCheckpointComparison(
        accountTimeZoneId: 'Asia/Shanghai',
        referenceUtc: DateTime.utc(2026, 9, 25, 12),
        deviceOffsetOverride: const Duration(hours: 8),
      ),
      '每日结算：04:00',
    );
    // 账号尚无时区时按北京时间，与东八区设备一致。
    expect(
      AccountTimeZones.formatCheckpointComparison(
        accountTimeZoneId: null,
        referenceUtc: DateTime.utc(2026, 9, 25, 12),
        deviceOffsetOverride: const Duration(hours: 8),
      ),
      '每日结算：04:00',
    );
  });

  test('账号时区与设备时区跨日时注明前一日/次日', () {
    // 奥克兰 9 月为 NZST（+12）：04:00 = 前一日 16:00Z。
    expect(
      AccountTimeZones.formatCheckpointComparison(
        accountTimeZoneId: 'Pacific/Auckland',
        referenceUtc: DateTime.utc(2026, 9, 25, 12),
        deviceOffsetOverride: const Duration(hours: -10),
      ),
      '每日结算：账号时区 04:00（当前设备时间 前日 06:00）',
    );
    expect(
      AccountTimeZones.formatCheckpointComparison(
        accountTimeZoneId: 'America/Los_Angeles',
        referenceUtc: DateTime.utc(2026, 9, 25, 12),
        deviceOffsetOverride: const Duration(hours: 14),
      ),
      '每日结算：账号时区 04:00（当前设备时间 次日 01:00）',
    );
  });

  test('下一检查点按账号时区的当地 04:00 计算，夏令时随之移动', () {
    expect(
      AccountTimeZones.nextCheckpointUtc(
        accountTimeZoneId: 'Europe/London',
        referenceUtc: DateTime.utc(2026, 1, 15, 12),
      ),
      DateTime.utc(2026, 1, 16, 4),
    );
    expect(
      AccountTimeZones.nextCheckpointUtc(
        accountTimeZoneId: 'Europe/London',
        referenceUtc: DateTime.utc(2026, 7, 15, 12),
      ),
      DateTime.utc(2026, 7, 16, 3),
    );
    expect(
      AccountTimeZones.nextCheckpointUtc(
        accountTimeZoneId: 'Asia/Tokyo',
        referenceUtc: DateTime.utc(2026, 9, 25, 19, 30),
      ),
      DateTime.utc(2026, 9, 26, 19),
    );
  });
}
