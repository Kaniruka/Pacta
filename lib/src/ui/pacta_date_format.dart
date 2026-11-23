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
