import 'package:flutter/material.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_status_colors.dart';
import '../theme/pacta_surfaces.dart';

/// Google 服务式分组标题：主蓝色、左对齐、titleSmall 字号。
///
/// 默认上 16dp / 下 8dp 的内边距，与下方 [PactaGroupedList] 的 20dp 圆角
/// 白卡形成稳定的“标题 → 分组”节奏；尾部可放“管理”“全部”等次级入口。
class PactaSectionHeader extends StatelessWidget {
  const PactaSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 16, 4, 8),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: PactaFonts.medium,
    );
    // 没有尾部组件时不要套 Row：Row 会强迫标题占满整行并让调用方把 trailing
    // 包成 Flexible，形成 50%/50% 均分（窄屏把长摘要腰斩、短摘要也不贴右缘）。
    // 有 trailing 时：标题用 Expanded 吃满左余宽度（长标题自然换行，不被
    // 挤压），trailing 最多占 72% 宽并天然贴右缘。
    final trailingWidget = trailing;
    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: trailingWidget == null
            ? Text(title, style: style)
            : LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(child: Text(title, style: style)),
                    const SizedBox(width: PactaSpacing.sm),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.72,
                      ),
                      child: trailingWidget,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 单一圆角白卡容器，用 1dp 细分隔线切分相邻行。
///
/// 直接传入 [ListTile]、[SwitchListTile] 等整行组件即可混排；分隔线只出现
/// 在相邻两行之间，不包边、不割裂整块表面。与 [Card] 的区别是：这里表达
/// “同一组设置项”，而不是独立卡片。
class PactaGroupedList extends StatelessWidget {
  const PactaGroupedList({
    super.key,
    required this.children,
    this.backgroundColor,
    this.borderRadius = PactaSpacing.cardRadius,
  });

  final List<Widget> children;
  final Color? backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final surfaces = PactaSurfaces.of(context);
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        // hairline 是主题里专门切分同层内容的 1dp 线，比 page 色更清晰
        // 又不会像描边一样把分组拆散。
        rows.add(Divider(height: 1, thickness: 1, color: surfaces.hairline));
      }
      rows.add(children[index]);
    }
    return Material(
      color: backgroundColor ?? surfaces.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// 状态胶囊的语气；颜色全部取主题语义色，亮暗主题自动切换。
enum PactaStatusBadgeTone { neutral, primary, success, warning, error }

/// 紧凑圆角状态胶囊：中性/主色/成功/提醒/错误五种语义。
///
/// 背景与前景成对取自 [ColorScheme]、[PactaStatusColors]，对比度 ≥ 4.5:1；
/// 图标只是冗余提示，文字始终保留，状态不只靠颜色表达。
class PactaStatusBadge extends StatelessWidget {
  const PactaStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = PactaStatusBadgeTone.neutral,
  });

  final String label;
  final IconData? icon;
  final PactaStatusBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = PactaStatusColors.of(context);
    final (Color background, Color foreground) = switch (tone) {
      PactaStatusBadgeTone.neutral => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
      PactaStatusBadgeTone.primary => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      PactaStatusBadgeTone.success => (
        status.successContainer,
        status.onSuccessContainer,
      ),
      PactaStatusBadgeTone.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      PactaStatusBadgeTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: PactaFonts.medium,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置分组里的一整行：图标 + 标题 + 副标题 + 状态胶囊/值文本 + 箭头。
///
/// 行高至少 48dp，整行可点；[tileKey] 只挂在内部的 [ListTile] 上，避免同一个
/// Key 同时出现在 [PactaSettingsTile] 与 [ListTile] 两个节点。
class PactaSettingsTile extends StatelessWidget {
  const PactaSettingsTile({
    super.key,
    this.tileKey,
    this.leadingIcon,
    this.leading,
    required this.title,
    this.subtitle,
    this.statusBadge,
    this.trailing,
    this.showChevron = true,
    this.onTap,
    this.enabled = true,
  });

  /// 内部 [ListTile] 的 Key；与 [PactaSettingsTile] 自身的 Key 分开。
  final Key? tileKey;

  /// 左侧标准图标；[leading] 非空时优先使用 [leading]。
  final IconData? leadingIcon;

  /// 自定义左侧组件，例如头像或圆形色块。
  final Widget? leading;

  final String title;

  /// 副标题最多两行，超出省略，避免长中文把整行撑高。
  final String? subtitle;

  /// 右侧紧凑状态胶囊；与 [trailing] 互斥，[trailing] 优先。
  final PactaStatusBadge? statusBadge;

  /// 右侧自定义组件；传入后不再自动拼接状态胶囊与箭头。
  final Widget? trailing;

  final bool showChevron;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: ListTile(
        key: tileKey,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading:
            leading ??
            (leadingIcon == null
                ? null
                : Icon(
                    leadingIcon,
                    color: enabled ? colors.onSurfaceVariant : null,
                  )),
        title: Text(title),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: trailing ?? _buildTrailing(colors),
      ),
    );
  }

  Widget? _buildTrailing(ColorScheme colors) {
    final children = <Widget>[
      if (statusBadge != null) ...[
        statusBadge!,
        if (showChevron) const SizedBox(width: 4),
      ],
      if (showChevron)
        Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
    ];
    if (children.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
