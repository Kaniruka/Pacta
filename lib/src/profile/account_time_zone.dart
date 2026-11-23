import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import '../national_focus/national_focus_checkpoints.dart';

/// One selectable display time zone in "修改资料".
///
/// 城市按 IANA 规则处理夏令时：这里只保存 IANA 标识，偏移与夏令时切换由
/// 时区数据库计算，不写死固定偏移。
class DisplayTimeZoneCity {
  const DisplayTimeZoneCity({required this.label, required this.timeZoneId});

  final String label;
  final String timeZoneId;
}

/// 账号级显示时区。
///
/// 值是账号资料里的 IANA 标识：各设备读到同一值，显示路径不会由设备时区
/// 决定。[fallbackId] 是"账号尚无值时"的统一临时显示值，是固定常量而不是
/// 按设备推导的回退；设备时区只在首次迁移时作为一次性写入输入。
///
/// [FocusTimeZones] 保留完整 IANA 解析（导入事件原始时区必须原样保留），
/// 因此可编辑的城市名单 [cities] 单独放在这里，不用于收窄校验。
class AccountTimeZones {
  AccountTimeZones._();

  /// 账号没有记录时区时的统一显示值。
  static const String fallbackId = 'Etc/UTC';

  /// 账号没有记录时区时的国策结算时区：沿用旧行为按北京时间凌晨 04:00 换天。
  static const String defaultNationalFocusTimeZoneId = 'Asia/Shanghai';

  /// 修改资料里可选的常见城市；不含"跟随设备"。
  ///
  /// 覆盖主流留学地区并按 IANA 处理夏令时：伦敦、悉尼、奥克兰、北美东西岸
  /// 都会随当地规则切换，不是固定偏移。
  static const List<DisplayTimeZoneCity> cities = [
    DisplayTimeZoneCity(label: '北京', timeZoneId: 'Asia/Shanghai'),
    DisplayTimeZoneCity(label: '香港', timeZoneId: 'Asia/Hong_Kong'),
    DisplayTimeZoneCity(label: '新加坡', timeZoneId: 'Asia/Singapore'),
    DisplayTimeZoneCity(label: '东京', timeZoneId: 'Asia/Tokyo'),
    DisplayTimeZoneCity(label: '首尔', timeZoneId: 'Asia/Seoul'),
    DisplayTimeZoneCity(label: '悉尼', timeZoneId: 'Australia/Sydney'),
    DisplayTimeZoneCity(label: '墨尔本', timeZoneId: 'Australia/Melbourne'),
    DisplayTimeZoneCity(label: '奥克兰', timeZoneId: 'Pacific/Auckland'),
    DisplayTimeZoneCity(label: '伦敦', timeZoneId: 'Europe/London'),
    DisplayTimeZoneCity(label: '巴黎', timeZoneId: 'Europe/Paris'),
    DisplayTimeZoneCity(label: '柏林', timeZoneId: 'Europe/Berlin'),
    DisplayTimeZoneCity(label: '多伦多', timeZoneId: 'America/Toronto'),
    DisplayTimeZoneCity(label: '温哥华', timeZoneId: 'America/Vancouver'),
    DisplayTimeZoneCity(label: '纽约', timeZoneId: 'America/New_York'),
    DisplayTimeZoneCity(label: '芝加哥', timeZoneId: 'America/Chicago'),
    DisplayTimeZoneCity(label: '洛杉矶', timeZoneId: 'America/Los_Angeles'),
    DisplayTimeZoneCity(label: 'UTC', timeZoneId: 'Etc/UTC'),
  ];

  /// 是否是时区数据库认识的值。仍接受城市名单以外的 IANA 标识，这样旧数据
  /// 或另一台设备写入的合法时区不会被显示层悄悄改掉。
  static bool isKnown(String? timeZoneId) =>
      timeZoneId != null && FocusTimeZones.contains(timeZoneId);

  /// 账号时区的显示值；账号尚无有效值时返回 [fallbackId]。
  static String effectiveId(String? accountTimeZoneId) =>
      isKnown(accountTimeZoneId) ? accountTimeZoneId! : fallbackId;

  /// 国策结算用的时区：账号记录了有效时区就用它，否则回到北京时间。
  static String checkpointTimeZoneId(String? accountTimeZoneId) =>
      isKnown(accountTimeZoneId)
      ? accountTimeZoneId!
      : defaultNationalFocusTimeZoneId;

  /// 账号时区下、严格晚于 [referenceUtc] 的下一个 04:00 检查点（UTC 时刻）。
  static DateTime nextCheckpointUtc({
    required String? accountTimeZoneId,
    required DateTime referenceUtc,
  }) => nextNationalFocusCheckpoint(
    referenceUtc.toUtc(),
    timeZoneId: checkpointTimeZoneId(accountTimeZoneId),
  );

  /// 国策结算说明：账号时区的 04:00，必要时并列本机设备时间。
  ///
  /// 人在东八区、账号设成东六区时，账号当地 04:00 就是设备上的 06:00；这种
  /// 偏移差异必须说清楚，否则用户会以为结算漏了一天。设备偏移默认取
  /// [referenceUtc] 的本机偏移，测试可以传 [deviceOffsetOverride]。
  static String formatCheckpointComparison({
    required String? accountTimeZoneId,
    required DateTime referenceUtc,
    Duration? deviceOffsetOverride,
  }) {
    final zoneId = checkpointTimeZoneId(accountTimeZoneId);
    final reference = referenceUtc.toUtc();
    final checkpoint = nextNationalFocusCheckpoint(
      reference,
      timeZoneId: zoneId,
    );
    final location = FocusTimeZones.location(zoneId);
    final accountLocal = timezone.TZDateTime.from(checkpoint, location);
    final accountLabel = _clockLabel(accountLocal);
    final accountOffset = accountLocal.timeZoneOffset;
    final deviceOffset =
        deviceOffsetOverride ?? reference.toLocal().timeZoneOffset;
    if (accountOffset == deviceOffset) return '每日结算：$accountLabel';

    final deviceWallClock = checkpoint.add(deviceOffset);
    final deviceDayOffset = _dayOffset(accountLocal, deviceWallClock);
    final dayPrefix = switch (deviceDayOffset) {
      1 => '次日 ',
      -1 => '前日 ',
      _ => '',
    };
    final deviceLabel = '$dayPrefix${_clockLabel(deviceWallClock)}';
    return '每日结算：账号时区 $accountLabel（当前设备时间 $deviceLabel）';
  }

  /// 城市名单中的条目；值不在名单内时返回 null（例如旧设备写过的其他时区）。
  static DisplayTimeZoneCity? cityFor(String? timeZoneId) {
    if (timeZoneId == null) return null;
    for (final city in cities) {
      if (city.timeZoneId == timeZoneId) return city;
    }
    return null;
  }

  static String _clockLabel(DateTime value) =>
      '${_two(value.hour)}:${_two(value.minute)}';

  /// 设备墙钟相对账号墙钟的自然日差：1 表示设备已到次日。
  static int _dayOffset(DateTime accountWallClock, DateTime deviceWallClock) {
    final accountDay = DateTime.utc(
      accountWallClock.year,
      accountWallClock.month,
      accountWallClock.day,
    );
    final deviceDay = DateTime.utc(
      deviceWallClock.year,
      deviceWallClock.month,
      deviceWallClock.day,
    );
    return deviceDay.difference(accountDay).inDays;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
