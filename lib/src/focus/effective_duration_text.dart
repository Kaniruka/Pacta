/// 有效专注／有效投入的统一时长文案。
///
/// 秒级精确值在所有界面上共用这一种写法：`13分00秒`、`1小时05分03秒`。
/// 月份汇总、链信号与对账页不再各自拼小时/分钟/秒，避免同一指标出现
/// `12分5秒`、`12分钟`、`1 小时 5 分钟` 三种写法。
String formatEffectiveDuration(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final hours = clamped ~/ 3600;
  final minutes = (clamped % 3600) ~/ 60;
  final remainingSeconds = clamped % 60;
  final paddedSeconds = remainingSeconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours小时${minutes.toString().padLeft(2, '0')}分$paddedSeconds秒';
  }
  return '$minutes分$paddedSeconds秒';
}

/// 《选择任务》卡片副标题用的紧凑专注进度：整分时省掉末尾的 `00秒`。
///
/// 与 [formatEffectiveDuration] 分工：对账、链信号与统计表需要
/// `13分00秒` 这种秒级可核对的写法；任务卡只有一行副标题，`1500` 秒读作
/// `25分`、`45` 秒读作 `45秒`、`4498` 秒读作 `1小时14分58秒`，零值写
/// `0分`。小时位只在非零时出现，分钟为零时也不补 `0分` 噪音。
String formatCompactFocusDuration(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final hours = clamped ~/ 3600;
  final minutes = (clamped % 3600) ~/ 60;
  final remainingSeconds = clamped % 60;
  if (hours > 0) {
    final buffer = StringBuffer('$hours小时');
    if (minutes > 0) buffer.write('$minutes分');
    if (remainingSeconds > 0) buffer.write('$remainingSeconds秒');
    return buffer.toString();
  }
  if (minutes > 0) {
    return remainingSeconds > 0 ? '$minutes分$remainingSeconds秒' : '$minutes分';
  }
  return remainingSeconds > 0 ? '$remainingSeconds秒' : '0分';
}

/// 《选择任务》卡片副标题用的预计时长：满 60 分钟自动换算成小时与分。
///
/// `60` → `1小时`、`90` → `1小时30分`、`2880` → `48小时`、
/// `25` → `25分钟`。不足一小时保留分钟，读起来仍是完整的时长而不是裸数字。
String formatCompactEstimateMinutes(int minutes) {
  final clamped = minutes < 0 ? 0 : minutes;
  final hours = clamped ~/ 60;
  final remainingMinutes = clamped % 60;
  if (hours == 0) return '$remainingMinutes分钟';
  return remainingMinutes == 0 ? '$hours小时' : '$hours小时$remainingMinutes分';
}
