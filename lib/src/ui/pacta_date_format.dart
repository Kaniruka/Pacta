/// 全站统一的日期/时间/钟表文本。
///
/// 只负责格式，不解释业务时区：调用方传入的 [DateTime] 一律先转本地时区
/// （`toLocal()`），因此同一时刻在计划、任务、看板与专注页显示一致。
String formatPactaDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String formatPactaDateTimeSeconds(DateTime value) {
  final local = value.toLocal();
  return '${formatPactaDateTime(local)}:${_two(local.second)}';
}

String formatPactaDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String formatPactaMonthDayTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// 倒计时/准备时长：`MM:SS`，不足两位补零；负数按 0 处理。
String formatPactaClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${_two(safe ~/ 60)}:${_two(safe % 60)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
