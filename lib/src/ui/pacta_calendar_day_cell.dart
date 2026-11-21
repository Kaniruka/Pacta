import 'package:flutter/material.dart';

import '../theme/pacta_calendar_colors.dart';
import '../theme/pacta_fonts.dart';

/// 三层语义的共享日历日格。
///
/// 1. 背景只由业务数据决定：传入的 [backgroundColor] 原样保留，[selected]
///    与 [today] 都不覆写它；
/// 2. 外框只有一层、与单元格等大：选中用 2dp 主蓝描边，今天用 1.5dp 中性
///    描边，同时成立时选中优先，绝不叠加第二层内框；
/// 3. 今天另用固定左上角的 '今' 角标表达，与右上角 [topRightMarker] 分居
///    两侧，不会互相遮挡。
///
/// 计划日历可传农历/节气 [subLabel]；紧凑月历可省略。底部 [bottomDot] 用于
/// “有安排未全完 5dp 圆点 / 全完成勾”等状态，不参与背景语义。
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
  });

  final String dayNumber;
  final bool selected;
  final bool today;

  /// 业务底色（有安排/全部完成/放假日/热力档位）；为 null 时不铺底色。
  final Color? backgroundColor;

  /// 日期数字与副标签的前景色，由业务底色决定，须保证 ≥ 4.5:1。
  final Color foregroundColor;

  /// 农历、节气或节假日等副标签。
  final Widget? subLabel;

  /// 右上角标记：安排圆点、完成勾或失败红点。
  final Widget? topRightMarker;

  /// 底部小圆点，用于“有安排但未全部完成”等辅助状态。
  final Widget? bottomDot;

  final double minHeight;
  final double borderRadius;
  final VoidCallback? onTap;

  /// 供读屏使用的完整描述；提供后内部文字不再单独播报。
  final String? semanticLabel;

  /// 命中区域/渲染盒的 Key，便于测试与页面定位。
  final Key? cellKey;

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
                    // 12dp 顶栏：'今' 徽章自己收紧 textScaler（≤1.15x）并被
                    // FittedBox 二次缩放进剩余宽度，右上角标记始终贴右，
                    // 320dp × 2.0 字号下也不会触发 RenderFlex 右溢。
                    SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          if (today)
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _TodayBadge(colors: calendarColors),
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
                    // 也绝不换行或溢出，三层底色/描边/角标语义保持不变。
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
                    if (bottomDot != null)
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

/// 今天的独立标记：小号、medium 字重、高对比底衬，不依赖描边。
class _TodayBadge extends StatelessWidget {
  const _TodayBadge({required this.colors});

  final PactaCalendarColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: colors.todayBadgeBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      // 从主题字阶派生再收紧字号：字族/字距跟随主题，尺寸仍保持紧凑的
      // 9.5 与 [PactaFonts.medium]，不会退化成脱离主题的裸 TextStyle。
      //
      // textScaler 只允许 1.0–1.15：系统字号放大到 2.0 时，'今' 若跟着放大
      // 会把 32.3dp 窄格里的右上角标记挤出边界（RenderFlex 右溢 3.2px）。
      child: Text(
        '今',
        textScaler: MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.15),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9.5,
          height: 1,
          fontWeight: PactaFonts.medium,
          color: colors.todayBadgeForeground,
        ),
      ),
    );
  }
}
