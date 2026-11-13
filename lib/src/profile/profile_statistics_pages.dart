import 'package:flutter/material.dart';

import '../focus/focus_models.dart';
import '../focus/focus_statistics.dart';
import '../national_focus/national_focus_models.dart';
import 'profile_format.dart';
import 'profile_overview.dart';

/// National-focus records behind the My-page counter.
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
        if (lit.isEmpty && internalized.isEmpty) {
          return const _DetailMessage('还没有点亮的国策节点。');
        }
        final entries = <Widget>[
          _SectionHeader(
            title: '当前点亮',
            summary: '${lit.length} 个树中节点',
            description: '只统计树中未删除且已确认点亮的节点，待今日确认不算点亮。',
          ),
          if (lit.isEmpty)
            const _EmptyRow('树中没有点亮的节点。')
          else
            for (final card in lit) _CardRow(card: card, showProgress: false),
          _SectionHeader(
            title: '已内化',
            summary: '${internalized.length} 张卡片',
            description:
                '累计成功国策日达到 180 天即计为已内化并封顶；入库卡片同样计数，'
                '历史成功日不因显示改写。',
          ),
          if (internalized.isEmpty)
            const _EmptyRow('还没有累计 180 天成功日的卡片。')
          else
            for (final card in internalized)
              _CardRow(card: card, showProgress: true),
        ];
        return _ReadableWidth(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: entries.length,
            itemBuilder: (context, index) => entries[index],
          ),
        );
      },
    ),
  );
}

/// Accepted focus records behind the My-page counter.
class FocusStatisticsPage extends StatelessWidget {
  const FocusStatisticsPage({super.key, required this.overview});

  final ProfileOverviewSource overview;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('专注统计明细')),
    body: StreamBuilder<List<FocusSession>>(
      stream: overview.watchSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _DetailMessage('专注记录暂时无法读取，请返回后重试。');
        }
        final sessions = snapshot.data;
        if (sessions == null) {
          return const _DetailMessage('正在读取专注记录…');
        }
        final completed = completedSessionsForOverview(sessions);
        if (completed.isEmpty) {
          return const _DetailMessage('还没有已完成的专注记录。');
        }
        return _ReadableWidth(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: completed.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SectionHeader(
                  title: '已完成专注',
                  summary: '${completed.length} 次',
                  description:
                      '只统计核对结果为已接受的 completed 记录；累计有效时间还包含'
                      '已接受失败记录的有效时间，不含暂停或排除区间。',
                );
              }
              final session = completed[index - 1];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_outlined),
                title: Text(
                  '${session.mode.label} · ${formatProfileDate(session.startedAt)}',
                ),
                subtitle: Text(
                  '有效时间 '
                  '${formatFocusDuration(focusEffectiveSecondsForSession(session))}',
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

/// Wide desktop windows keep a readable measure instead of stretching rows
/// across the whole window; narrow windows use the full width.
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.summary,
    required this.description,
  });

  final String title;
  final String summary;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(summary, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.showProgress});

  final NationalFocusCard card;
  final bool showProgress;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.account_tree_outlined),
    title: Text(card.name, softWrap: true),
    subtitle: Text(
      showProgress
          ? '累计成功 ${card.successfulDays} 天 · 已封顶'
          : '连续 ${card.currentConsecutiveDays} 天 · 累计 ${card.successfulDays} 天',
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
