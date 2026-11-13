/// Short duration for a statistics line, e.g. `12 小时 30 分钟`.
String formatFocusDuration(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final totalMinutes = seconds ~/ 60;
  if (totalMinutes < 1) return '不足 1 分钟';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分钟';
}

/// Date of a retained record in local time, e.g. `11月13日 09:05`.
String formatProfileDate(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}月${local.day}日 $hour:$minute';
}
