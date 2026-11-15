import '../focus/focus_time_zones.dart';

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

  /// 修改资料里可选的常见城市；不含"跟随设备"。
  static const List<DisplayTimeZoneCity> cities = [
    DisplayTimeZoneCity(label: '北京', timeZoneId: 'Asia/Shanghai'),
    DisplayTimeZoneCity(label: '新加坡', timeZoneId: 'Asia/Singapore'),
    DisplayTimeZoneCity(label: '东京', timeZoneId: 'Asia/Tokyo'),
    DisplayTimeZoneCity(label: '伦敦', timeZoneId: 'Europe/London'),
    DisplayTimeZoneCity(label: '纽约', timeZoneId: 'America/New_York'),
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

  /// 城市名单中的条目；值不在名单内时返回 null（例如旧设备写过的其他时区）。
  static DisplayTimeZoneCity? cityFor(String? timeZoneId) {
    if (timeZoneId == null) return null;
    for (final city in cities) {
      if (city.timeZoneId == timeZoneId) return city;
    }
    return null;
  }
}
