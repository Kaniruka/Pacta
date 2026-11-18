import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';

/// 目的地页头：四个一级页面共用同一套字号与对齐。
///
/// 标题只用主题的 `headlineSmall`，不再逐页加重；右侧入口放在同一个
/// 换行容器里，大字号时自动换行而不是挤压标题。
class PactaPageHeader extends StatelessWidget {
  const PactaPageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.bottomSpacing = PactaSpacing.md,
  });

  final String title;
  final Widget? trailing;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottomSpacing),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: PactaSpacing.lg,
      runSpacing: PactaSpacing.sm,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ?trailing,
      ],
    ),
  );
}
