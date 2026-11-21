import 'package:flutter/material.dart';

import '../theme/pacta_calendar_colors.dart';

/// 专注热力五档图例。
///
/// 看板「专注与国策」融合卡片内部使用这一份色阶说明，深浅含义只有一处
/// 定义；色块从 [PactaCalendarColors] 取色，亮暗主题自动跟随。
///
/// 五档色块是冗余提示，读屏不逐块朗读：整块收敛成一条语义说明，真正的
/// 时长数字仍由调用方在页面上给出，颜色不承担唯一的语义线索。
class PactaFocusHeatLegend extends StatelessWidget {
  const PactaFocusHeatLegend({super.key, this.label = '专注时长：按颜色深浅区分'});

  /// 图例前缀说明，默认与看板融合卡内的说明保持同一句话。
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PactaCalendarColors.of(context);
    return Semantics(
      container: true,
      label: '专注热力图例：颜色越深表示当天有效专注时长越长',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var level = 0; level <= 4; level++)
                Padding(
                  padding: EdgeInsets.only(left: level == 0 ? 0 : 3),
                  child: Container(
                    key: ValueKey('pacta-heat-legend-$level'),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors.heatColorsForLevel(level).$1,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
