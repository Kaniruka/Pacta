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
