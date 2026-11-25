import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../national_focus/national_focus_icons.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_shared_widgets.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_grouped_list.dart';
import 'profile_overview.dart';

/// 国策记录的只读明细页。
///
/// M3 Expressive 版式：顶部一张双指标概览卡（当前点亮 / 已内化，等宽数字），
/// 下面按 [PactaSectionHeader] 分成两组，每组的行都是 [PactaGroupedList] 的
/// 分段卡片：图标舱 + 国策卡名称 + 连胜／内化进度胶囊 + 右箭头。区块解释折进
/// 行内 ⓘ，不再用长段说明文字把标题撑成三行。
///
/// 页面只读：点开卡片进入只读详情，不提供点亮、确认或编辑动作——这些属于
/// 国策树与卡片库，统计页只解释已经存在的记录。
class NationalFocusStatisticsPage extends StatelessWidget {
  const NationalFocusStatisticsPage({super.key, required this.overview});

  final ProfileOverviewSource overview;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('国策统计明细')),
    body: StreamBuilder<List<NationalFocusCard>>(
      stream: overview.watchCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _DetailMessage('国策记录暂时无法读取，请返回后重试。');
        }
        final cards = snapshot.data;
        if (cards == null) {
          return const _DetailMessage('正在读取国策记录…');
        }
        final lit = litCardsForOverview(cards);
        final internalized = internalizedCardsForOverview(cards);
        final empty = lit.isEmpty && internalized.isEmpty;
        return _ReadableWidth(
          child: ListView(
            padding: PactaSpacing.pageInsets(context, top: PactaSpacing.sm),
            children: [
              _OverviewMetrics(
                litCount: lit.length,
                internalizedCount: internalized.length,
              ),
              // 两边都空时只留一句空态：不给两个空分区各配一行说明。
              if (empty)
                const Padding(
                  padding: EdgeInsets.only(top: PactaSpacing.lg),
                  child: _EmptyState('还没有点亮的国策节点。'),
                )
              else ...[
                PactaSectionHeader(
                  title: '当前点亮',
                  trailing: _SectionNote(
                    summary: '${lit.length} 个树中节点',
                    note: '只统计树中未删除且已确认点亮的节点，待今日确认不算点亮。',
                  ),
                ),
                if (lit.isEmpty)
                  const _EmptyState('树中没有点亮的节点。')
                else
                  PactaGroupedList(
                    children: [
                      for (final card in lit)
                        _CardTile(card: card, internalized: false),
                    ],
                  ),
                const SizedBox(height: PactaSpacing.lg),
                PactaSectionHeader(
                  title: '已内化',
                  trailing: _SectionNote(
                    summary: '${internalized.length} 张卡片',
                    note:
                        '累计成功国策日达到 180 天即计为已内化并封顶；'
                        '入库卡片同样计数，历史成功日不因显示改写。',
                  ),
                ),
                if (internalized.isEmpty)
                  const _EmptyState('还没有累计 180 天成功日的卡片。')
                else
                  PactaGroupedList(
                    children: [
                      for (final card in internalized)
                        _CardTile(card: card, internalized: true),
                    ],
                  ),
              ],
              const SizedBox(height: PactaSpacing.xl),
            ],
          ),
        );
      },
    ),
  );
}

/// 宽桌面窗口保持可读行宽，窄窗口用满整幅。
class _ReadableWidth extends StatelessWidget {
  const _ReadableWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );
}

/// 顶部双指标概览：两个数字并排，各有自己的浅底图标舱。
///
/// 数字使用 [ui.FontFeature.tabularFigures]，进度从 9 变到 10 时不会左右跳动。
class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({
    required this.litCount,
    required this.internalizedCount,
  });

  final int litCount;
  final int internalizedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('national-focus-statistics-overview'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PactaSpacing.lg,
          vertical: PactaSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.account_tree_outlined,
                label: '当前点亮',
                value: litCount,
                unit: '个树中节点',
              ),
            ),
            SizedBox(
              height: PactaSpacing.xxl + PactaSpacing.lg,
              child: VerticalDivider(
                width: PactaSpacing.xl,
                thickness: 1,
                color: theme.dividerColor,
              ),
            ),
            Expanded(
              child: _Metric(
                icon: Icons.verified_outlined,
                label: '已内化',
                value: internalizedCount,
                unit: '张卡片',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final String label;
  final int value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: PactaSpacing.xxl + PactaSpacing.xs,
              height: PactaSpacing.xxl + PactaSpacing.xs,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(PactaSpacing.md),
              ),
              child: Icon(
                icon,
                size: PactaIconSizes.sm,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: PactaSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: PactaSpacing.sm),
        Text(
          '$value',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        Text(
          unit,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 分区标题右侧的摘要 + 行内 ⓘ：解释放 tooltip，标题只占一行。
class _SectionNote extends StatelessWidget {
  const _SectionNote({required this.summary, required this.note});

  final String summary;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: PactaSpacing.xs),
        Tooltip(
          triggerMode: TooltipTriggerMode.tap,
          message: note,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                Icons.info_outline,
                size: PactaIconSizes.sm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 一行国策记录：图标舱 + 名称 + 连胜／内化进度胶囊 + 右箭头。
class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.internalized});

  final NationalFocusCard card;
  final bool internalized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PactaSettingsTile(
      tileKey: ValueKey('national-focus-statistics-${card.id}'),
      leading: Container(
        width: PactaSpacing.xxl + PactaSpacing.xs,
        height: PactaSpacing.xxl + PactaSpacing.xs,
        decoration: BoxDecoration(
          color: internalized
              ? colors.secondaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(PactaSpacing.md),
        ),
        child: Icon(
          // 与只读详情页同一套图标：未内化时直接呈现卡片自定义图标，
          // 空值/未知键回落默认灯泡。
          internalized
              ? Icons.verified_outlined
              : nationalFocusIconData(card.iconKey),
          size: PactaIconSizes.sm,
          color: internalized
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
      title: card.name,
      statusBadge: PactaStatusBadge(
        label: internalized
            ? '${card.successfulDays} 天'
            : '连续 ${card.currentConsecutiveDays} 天',
        tone: internalized
            ? PactaStatusBadgeTone.success
            : PactaStatusBadgeTone.primary,
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _NationalFocusCardReadOnlyPage(card: card),
        ),
      ),
    );
  }
}

/// 统计页点开的只读详情：只解释这张卡已经存在的记录，不提供任何写操作。
///
/// 三卡结构与可编辑详情页一一对应（身份总览 / 规则 / 记录），只是没有顶栏
/// 编辑入口、也没有可展开的编辑控件：读者在这里看到的就是卡片当前的样子。
class _NationalFocusCardReadOnlyPage extends StatelessWidget {
  const _NationalFocusCardReadOnlyPage({required this.card});

  final NationalFocusCard card;

  @override
  Widget build(BuildContext context) =>
      PactaSurfaces.wrapIfMissing(context, Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final exceptionNotes = card.exceptionNotes?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('国策卡详情')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // 与可编辑详情页同一条 800dp 阅读线、同一组卡间距与卡内边距。
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: PactaSpacing.pageInsets(context),
            children: [
              NationalFocusCardIdentityCard(
                key: const ValueKey('national-focus-readonly-header-card'),
                card: card,
              ),
              const SizedBox(height: PactaSpacing.lg),
              NationalFocusDetailRulesCard(
                key: const ValueKey('national-focus-readonly-rules-card'),
                card: card,
                // 只读页不折叠：判例直接摊开，没有可展开/收起的编辑暗示。
                footer: exceptionNotes.isEmpty
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('例外与判例', style: theme.textTheme.titleSmall),
                          const SizedBox(height: PactaSpacing.xxs),
                          Text(
                            exceptionNotes,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: PactaSpacing.lg),
              NationalFocusDetailRecordsCard(
                key: const ValueKey('national-focus-readonly-records-card'),
                card: card,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态：克制的一句话，不再画插图或再加一颗按钮。
class _EmptyState extends StatelessWidget {
  const _EmptyState(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PactaSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PactaSpacing.xl),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
