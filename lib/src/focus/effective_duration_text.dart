/// 有效专注／有效投入的统一时长文案：满 10 分钟省略秒。
///
/// 满 1 小时写 `1小时5分` / `2小时`，满 10 分钟写 `25分钟`，不足 10 分钟
/// 保留非零秒（`3分20秒`、`5分钟`、`45秒`、`0分钟`），避免长记录被秒数噪音干扰。
String formatEffectiveDuration(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final hours = clamped ~/ 3600;
  final minutes = (clamped % 3600) ~/ 60;
  final remainingSeconds = clamped % 60;
  if (hours > 0) {
    return minutes == 0 ? '$hours小时' : '$hours小时$minutes分';
  }
  if (minutes >= 10) {
    return '$minutes分钟';
  }
  if (minutes > 0) {
    return remainingSeconds > 0 ? '$minutes分$remainingSeconds秒' : '$minutes分钟';
  }
  return remainingSeconds > 0 ? '$remainingSeconds秒' : '0分钟';
}

/// 秒级精确时长文案：仅用于专注时钟核对页等需要逐秒核验漂移的场景。
String formatExactEffectiveDuration(int seconds) {
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

/// 《选择任务》卡片副标题用的紧凑专注进度：满 10 分钟自动省略秒，整分省 `00秒`。
String formatCompactFocusDuration(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final hours = clamped ~/ 3600;
  final minutes = (clamped % 3600) ~/ 60;
  final remainingSeconds = clamped % 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours小时$minutes分' : '$hours小时';
  }
  if (minutes >= 10) {
    return '$minutes分';
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
