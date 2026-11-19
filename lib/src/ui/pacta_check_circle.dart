import 'package:flutter/material.dart';

/// 完成任务/安排时统一的语义动作文案。
String completionActionLabel(String title, {required bool isCompleted}) =>
    isCompleted ? '将“$title”标记为未完成' : '完成“$title”';

/// 计划与会话共用的圆形勾选。
///
/// 视觉与看板今日安排一致（实心圆勾 / 空心圆），保留 48×48 命中区、
/// checked 语义和禁用态；点按行为由调用方决定（看板只读时 [compact]）。
class PactaCheckCircle extends StatelessWidget {
  const PactaCheckCircle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.visualSize,
    this.compact = false,
  }) : assert(!(compact && onChanged != null), 'compact 仅用于只读指示，不接受 onChanged');

  /// 交互式勾选的命中区，沿用 Material 的最小触控尺寸。
  static const double hitTargetSize = 48;

  /// 看板行内只读指示的默认视觉尺寸。
  static const double compactVisualSize = 18;

  /// 计划/安排行的默认视觉尺寸。
  static const double interactiveVisualSize = 24;

  final bool value;

  /// 为空表示禁用；[compact] 为 true 时表示只读指示，不提供点按。
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  /// 显式视觉尺寸；未提供时按 [compact] 选择 18/24。
  final double? visualSize;

  /// 看板行内只读指示：不额外撑高整行。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final effectiveVisualSize =
        visualSize ?? (compact ? compactVisualSize : interactiveVisualSize);
    final baseColor = value ? colors.primary : colors.onSurfaceVariant;
    final color = !compact && !enabled
        ? baseColor.withValues(alpha: 0.38)
        : baseColor;
    final icon = Icon(
      value ? Icons.check_circle : Icons.radio_button_unchecked,
      size: effectiveVisualSize,
      color: color,
    );
    if (compact) {
      return Semantics(
        container: true,
        checked: value,
        label: semanticLabel,
        child: ExcludeSemantics(child: icon),
      );
    }
    return SizedBox.square(
      dimension: hitTargetSize,
      child: Semantics(
        container: true,
        checked: value,
        enabled: enabled,
        button: true,
        label: semanticLabel,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: ExcludeSemantics(
          child: InkResponse(
            onTap: enabled ? () => onChanged!(!value) : null,
            radius: hitTargetSize / 2,
            containedInkWell: true,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
