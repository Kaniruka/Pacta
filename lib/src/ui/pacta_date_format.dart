import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';

/// 全站统一的日期/时间/钟表文本。
///
/// 只负责格式，不解释业务时区：调用方传入的 [DateTime] 一律先转本地时区
/// （`toLocal()`），因此同一时刻在计划、任务、看板与专注页显示一致。
String formatPactaDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// 按账号显示时区格式化的日期时间；时区无效时退回本机时区。
///
/// 只影响显示，不改变任何结算或存储语义：账号时区决定的只是这一串字符。
String formatPactaDateTimeInZone(DateTime value, {String? timeZoneId}) {
  final local = _inZone(value, timeZoneId);
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// 按账号显示时区格式化的 `HH:mm`；时区无效时退回本机时区。
String formatPactaTimeInZone(DateTime value, {String? timeZoneId}) {
  final local = _inZone(value, timeZoneId);
  return '${_two(local.hour)}:${_two(local.minute)}';
}

String formatPactaDateTimeSeconds(DateTime value, {String? timeZoneId}) {
  final local = _inZone(value, timeZoneId);
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String formatPactaDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String formatPactaMonthDayTime(DateTime value, {String? timeZoneId}) {
  final local = _inZone(value, timeZoneId);
  return '${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// 倒计时/准备时长：`MM:SS`，不足两位补零；负数按 0 处理。
String formatPactaClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${_two(safe ~/ 60)}:${_two(safe % 60)}';
}

/// 过去时刻的中文相对时间（如 `刚刚`、`5 分钟前`、`3 小时前`、`4 天前`）。
///
/// 超过 30 天后回落到简洁日期（同年 `M月d日`，跨年 `yyyy-MM-dd`），
/// 避免在摘要行堆砌精确到秒的完整时间戳。
String formatPactaRelativePast(
  DateTime value, {
  DateTime? now,
  String? timeZoneId,
}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(value);
  if (diff.isNegative || diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final localValue = _inZone(value, timeZoneId);
  final localNow = _inZone(reference, timeZoneId);
  if (localValue.year == localNow.year) {
    return '${localValue.month}月${localValue.day}日';
  }
  return '${localValue.year}-${_two(localValue.month)}-${_two(localValue.day)}';
}

/// 未来剩余时长的紧凑英文写法（如 `7d18h 后`、`18h16m 后`、`45m 后`）。
///
/// 高位量级足够大时自动省略低位与秒：满 30 天只显天，满 1 天显天+时，
/// 满 1 小时显时+分，满 1 分钟只显分，不足 1 分钟显秒。
String formatPactaCompactRemaining(Duration remaining) {
  final totalSeconds = remaining.inSeconds;
  if (totalSeconds <= 0) return '已到期';
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (days >= 30) return '${days}d 后';
  if (days > 0) return hours > 0 ? '${days}d${hours}h 后' : '${days}d 后';
  if (hours > 0) return minutes > 0 ? '${hours}h${minutes}m 后' : '${hours}h 后';
  if (minutes > 0) return '${minutes}m 后';
  return '${seconds}s 后';
}

DateTime _inZone(DateTime value, String? timeZoneId) {
  if (timeZoneId != null && FocusTimeZones.contains(timeZoneId)) {
    return timezone.TZDateTime.from(
      value.toUtc(),
      FocusTimeZones.location(timeZoneId),
    );
  }
  return value.toLocal();
}

String _two(int value) => value.toString().padLeft(2, '0');
