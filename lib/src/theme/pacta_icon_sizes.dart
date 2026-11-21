/// 全站语义图标尺度：界面里所有图标尺寸只从这里取。
///
/// 档位按"图标在版面里承担什么"划分，而不是按组件名：
/// - [micro] / [sm] 是行内辅助信息，必须与同排文字的中线对齐；
/// - [compact] / [md] 是列表、导航与设置行的常规操作位；
/// - [lg] / [hero] / [heroLarge] 是状态与空态的主视觉，一屏只出现一次。
///
/// 这里给的是视觉尺寸，不是命中区：可点图标的命中区仍按 48×48dp 处理，
/// 图标变小不代表点击区域变小。页面里不再出现 12/13/16/18/20 之类的散值。
abstract final class PactaIconSizes {
  /// 最小行内图标：状态胶囊内的图标、行内说明用的 `ⓘ`（14dp）。
  static const double micro = 14;

  /// 小号图标：按钮前置图标、Chip 内图标、行内元数据或轻提示（18dp）。
  static const double sm = 18;

  /// 紧凑操作位：列表右侧 `chevron_right`、紧凑行内操作图标（20dp）。
  static const double compact = 20;

  /// 标准尺寸：设置行左侧图标、AppBar/导航栏与卡片主操作图标（24dp）。
  static const double md = 24;

  /// 中等强调：卡片内的状态图标（32dp）。
  static const double lg = 32;

  /// 主状态视觉：空态或主状态插图的主图标（40dp）。
  static const double hero = 40;

  /// 大状态页头：独立状态页的头图图标（48dp）。
  static const double heroLarge = 48;
}
