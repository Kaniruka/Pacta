import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';

/// 目的地页头：所有一级页面共用同一行高、内边距、字号与尾部操作区。
///
/// [resolveRowHeight] 按当前 `textScaler` 实测标题行高后取
/// `max(minRowHeight, 行高 + PactaSpacing.md)`，因此有无尾部操作、系统字号
/// 多大，五个页面的页头都保持同一高度。尾部操作宽度超过内容区 65% 时由
/// [FittedBox] 等比缩小；这只是极窄屏/大字号下的防溢出兜底，正常字号不缩放。
/// 标题只允许单行省略，标题 y 坐标由页面顶部内边距与行高决定。
///
/// 尾部图标按钮的图标尺寸取 `PactaIconSizes`（页头次级入口用 `compact`、
/// 主操作用 `md`），页面不在此另写像素值。
class PactaPageHeader extends StatelessWidget {
  const PactaPageHeader({super.key, required this.title, this.trailing});

  /// 标题行最小高度，与 Material 最小触控尺寸一致。
  static const double minRowHeight = 48;

  /// 页头与页面内容之间的固定间距。
  static const double bottomGap = PactaSpacing.sm;

  final String title;
  final Widget? trailing;

  /// 用当前语义标题样式和 `textScaler` 实测行高，返回固定行高。
  static double resolveRowHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    final painter = TextPainter(
      text: TextSpan(text: '国', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final lineHeight = painter.height;
    painter.dispose();
    return math.max(minRowHeight, lineHeight + PactaSpacing.md);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: bottomGap),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final rowHeight = resolveRowHeight(context);
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (trailing case final widget?) ...[
                const SizedBox(width: PactaSpacing.lg),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, constraints.maxWidth * 0.65),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: widget,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
