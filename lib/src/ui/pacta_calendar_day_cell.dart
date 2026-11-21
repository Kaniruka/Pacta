import 'package:flutter/material.dart';

import '../theme/pacta_calendar_colors.dart';
import '../theme/pacta_fonts.dart';

/// 三层语义的共享日历日格。
///
/// 1. 背景只由业务数据决定：传入的 [backgroundColor] 原样保留，[selected]
///    与 [today] 都不覆写它；
/// 2. 外框只有一层、与单元格等大：选中用 2dp 主蓝描边，今天用 1.5dp 中性
///    描边，同时成立时选中优先，绝不叠加第二层内框；
/// 3. 今天另用固定位置的 '今' 微字表达：不铺胶囊底色，颜色由业务底色决定
///    （无底色 / heat0 用 [PactaCalendarColors.todayLabelColor]，业务色底用
///    调用方传进来的高对比 [foregroundColor]），与右上角 [topRightMarker]
///    分居两侧，不会互相遮挡。
///
/// 计划日历可传农历/节气 [subLabel]；紧凑月历可省略。底部 [bottomDot] 用于
/// “有安排未全完 5dp 圆点 / 全完成勾 / 国策失败细短杠”等状态，不参与背景
/// 语义。
///
/// 热力月历传 [centerTodayLabel] + [reserveBottomSlot]：'今' 居中置顶成为
/// 独立的一行微字，底部恒定保留 8dp 指示轨。于是同一行里“无状态日”“只有
/// 安排日”“有失败日”“双态日”的日期数字基线完全一致，状态变化不会让日期
/// 数字上下跳动。计划日历保持两个默认 false：'今' 左对齐、右侧放日程点/勾，
/// 下方保留农历副标签。
class PactaCalendarDayBox extends StatelessWidget {
  const PactaCalendarDayBox({
    super.key,
    required this.dayNumber,
    this.selected = false,
    this.today = false,
    this.backgroundColor,
    required this.foregroundColor,
    this.subLabel,
    this.topRightMarker,
    this.bottomDot,
    this.minHeight = 48,
    this.borderRadius = 12,
    this.onTap,
    this.semanticLabel,
    this.cellKey,
    this.centerTodayLabel = false,
    this.reserveBottomSlot = false,
  });

  final String dayNumber;
  final bool selected;
  final bool today;

  /// 业务底色（有安排/全部完成/放假日/热力档位）；为 null 时不铺底色。
  final Color? backgroundColor;

  /// 日期数字与副标签的前景色，由业务底色决定，须保证 ≥ 4.5:1；同时也是
  /// 业务色底上 '今' 微字的颜色。
  final Color foregroundColor;

  /// 农历、节气或节假日等副标签。
  final Widget? subLabel;

  /// 右上角标记：安排圆点、完成勾。热力月历不再使用它（改到底部指示轨）。
  final Widget? topRightMarker;

  /// 底部状态标记：安排微点、国策失败细短杠等，不参与背景语义。
  final Widget? bottomDot;

  final double minHeight;
  final double borderRadius;
  final VoidCallback? onTap;

  /// 供读屏使用的完整描述；提供后内部文字不再单独播报。
  final String? semanticLabel;

  /// 命中区域/渲染盒的 Key，便于测试与页面定位。
  final Key? cellKey;

  /// '今' 是否居中置顶独占一行（热力月历）；默认 false 表示沿用左对齐、
  /// 右侧留给 [topRightMarker] 的计划日历排版。
  final bool centerTodayLabel;

  /// 是否恒定保留底部 8dp 指示轨（热力月历）。为 true 时即使当天没有任何
  /// 状态点也占固定高度，同行日期数字不会因为有无状态而上下错位。
  final bool reserveBottomSlot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calendarColors = PactaCalendarColors.of(context);
    // 单层描边：选中优先于今天，二者都成立时也只画一层。
    final border = selected
        ? Border.all(color: calendarColors.selectedBorder, width: 2)
        : today
        ? Border.all(color: calendarColors.todayBorder, width: 1.5)
        : null;
    final todayLabel = _TodayLabel(
      colors: calendarColors,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
    return Semantics(
      container: true,
      selected: selected,
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        key: cellKey,
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                // 左右 3dp：360dp 手机下七列每列仅 44.5dp，2dp 的外间隙
                // 之外不能再让 4dp 内边距吃掉数字的可用宽度。
                padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 12dp 顶栏：'今' 自己收紧 textScaler（≤1.15x）并被
                    // FittedBox 二次缩放进剩余宽度，右上角标记始终贴右，
                    // 320dp × 2.0 字号下也不会触发 RenderFlex 右溢。
                    SizedBox(
                      height: 12,
                      child: centerTodayLabel && topRightMarker == null
                          // 热力月历：'今' 居中独占这一行；没有今天时也保留
                          // 同样的 12dp 高度，日期数字不会上下挪位。
                          ? (today
                                ? Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: todayLabel,
                                    ),
                                  )
                                : null)
                          : Row(
                              children: [
                                if (today)
                                  Flexible(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: todayLabel,
                                      ),
                                    ),
                                  )
                                else
                                  const Spacer(),
                                if (today && topRightMarker != null)
                                  const SizedBox(width: 2),
                                ?topRightMarker,
                              ],
                            ),
                    ),
                    // 日期数字等比收缩到可用宽度：320dp × 2.0 字号下
                    // 也绝不换行或溢出，三层底色/描边/今字语义保持不变。
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        dayNumber,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foregroundColor,
                          fontWeight: PactaFonts.medium,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (subLabel != null)
                      Align(alignment: Alignment.center, child: subLabel),
                    if (reserveBottomSlot) ...[
                      // 恒定 2dp 间隔 + 8dp 指示轨：没有任何状态点时这两行
                      // 仍然占位，同行日期数字基线严格对齐。
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 8,
                        child: bottomDot == null
                            ? null
                            : Center(child: bottomDot),
                      ),
                    ] else if (bottomDot != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Center(child: bottomDot),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 今天的独立标记：去胶囊的 10dp 微字，不依赖描边，也不铺底色。
///
/// 颜色按底色自适应，避免绿/黄底上出现蓝底白字或蓝字配绿底：
/// 无底色与 heat0 用 [PactaCalendarColors.todayLabelColor]，其余业务色底用
/// 调用方传入的 [foregroundColor]（深绿 heat3/heat4 上是白色，柔和黄上是
/// 深棕，浅绿 heat1 上是深绿）。
class _TodayLabel extends StatelessWidget {
  const _TodayLabel({
    required this.colors,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final PactaCalendarColors colors;
  final Color? backgroundColor;
  final Color foregroundColor;

  Color get _labelColor {
    final background = backgroundColor;
    if (background == null || background == colors.heat0Background) {
      return colors.todayLabelColor;
    }
    return foregroundColor;
  }

  @override
  Widget build(BuildContext context) {
    // 从主题字阶派生再收紧字号：字族/字距跟随主题，尺寸保持 10dp 与
    // [PactaFonts.semibold]，不会退化成脱离主题的裸 TextStyle。
    //
    // textScaler 只允许 1.0–1.15：系统字号放大到 2.0 时，'今' 若跟着放大
    // 会把 32.3dp 窄格里的右上角标记挤出边界（RenderFlex 右溢 3.2px）。
    return Text(
      '今',
      textScaler: MediaQuery.textScalerOf(context)
          .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.15),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 10,
        height: 1.0,
        fontWeight: PactaFonts.semibold,
        color: _labelColor,
      ),
    );
  }
}
