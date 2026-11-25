import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';

/// 卡片首行标题 + 48dp 行内操作按钮的统一头部。
///
/// 外层若直接套 `EdgeInsets.all(16)`，48dp 高的 `TextButton` 会把单行标题
/// 垂直居中，标题距卡片顶部被撑到约 29dp，与底部 16dp 不对称。这里把
/// 标题的视觉顶距固定为 16dp（8dp 外层补偿 + 8dp 内部偏移），同时让右侧
/// 操作保留完整的 48×48dp 命中区；没有 trailing 时也保持同样的 16dp 基线。
///
/// 尾部图标按钮的图标尺寸取 `PactaIconSizes`（行内 `compact`、主操作 `md`），
/// 页面不在此另写像素值。
class PactaCardHeader extends StatelessWidget {
  const PactaCardHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.titleStyle,
    this.padding,
  });

  final String title;

  /// 标题左侧的紧凑视觉锚点（例如卡片自定义图标井）。
  final Widget? leading;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final style = titleStyle ?? Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 12, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: PactaSpacing.sm),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: PactaSpacing.sm),
                child: Text(title, style: style),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
