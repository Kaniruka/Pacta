import 'dart:async';

import 'package:flutter/material.dart';

import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';

class NationalFocusSummaryCard extends StatefulWidget {
  const NationalFocusSummaryCard({
    super.key,
    required this.repository,
    required this.onOpenTree,
  });

  final NationalFocusRepository repository;
  final VoidCallback onOpenTree;

  @override
  State<NationalFocusSummaryCard> createState() =>
      _NationalFocusSummaryCardState();
}

class _NationalFocusSummaryCardState extends State<NationalFocusSummaryCard> {
  late Stream<List<NationalFocusCard>> _treeCardsStream;
  Timer? _checkpointTimer;

  @override
  void initState() {
    super.initState();
    _treeCardsStream = widget.repository.watchTreeCards();
    _settleDueCheckpoints();
    _checkpointTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshCheckpoint(),
    );
  }

  @override
  void dispose() {
    _checkpointTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NationalFocusSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _treeCardsStream = widget.repository.watchTreeCards();
      _settleDueCheckpoints();
    }
  }

  void _settleDueCheckpoints() {
    unawaited(
      widget.repository.settleDueCheckpoints().catchError((Object _) {}),
    );
  }

  void _refreshCheckpoint() {
    _settleDueCheckpoints();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<NationalFocusCard>>(
    stream: _treeCardsStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _card(context, children: [const Text('国策状态暂不可用。')]);
      }

      final cards = snapshot.data;
      if (cards == null) {
        return _card(context, children: [const Text('正在读取国策状态…')]);
      }

      final pendingReview = cards
          .where((card) => card.hasPendingReview)
          .toList(growable: false);
      final confirmedCards = cards
          .where((card) => !card.hasPendingReview)
          .toList(growable: false);
      final litCount = confirmedCards
          .where((card) => card.state == NationalFocusCardState.lit)
          .length;
      final pendingCount = confirmedCards
          .where(
            (card) =>
                card.state == NationalFocusCardState.pendingTodayConfirmation,
          )
          .length;
      final extinguishedCount = confirmedCards
          .where((card) => card.state == NationalFocusCardState.extinguished)
          .length;

      return _card(
        context,
        children: [
          if (cards.isEmpty)
            const Text('国策树尚无节点。')
          else if (confirmedCards.isEmpty)
            const Text('所有国策节点的当前状态均待核对。')
          else
            Text('点亮 $litCount · 待今日确认 $pendingCount · 熄灭 $extinguishedCount'),
          if (pendingReview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${pendingReview.length} 个节点待核对；争议状态不计入上方汇总。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final card in pendingReview)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${card.name} · 上次已确认：'
                  '${card.currentConsecutiveDays} 天连续记录',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      );
    },
  );

  Widget _card(BuildContext context, {required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              '国策状态',
              style: Theme.of(context).textTheme.titleMedium,
            );
            final openTree = TextButton.icon(
              onPressed: widget.onOpenTree,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('打开国策树'),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (constraints.maxWidth < 320) ...[
                  title,
                  Align(alignment: Alignment.centerRight, child: openTree),
                ] else
                  Row(
                    children: [
                      Expanded(child: title),
                      openTree,
                    ],
                  ),
                ...children,
              ],
            );
          },
        ),
      ),
    );
  }
}
