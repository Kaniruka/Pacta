import 'dart:async';

import 'package:flutter/material.dart';

import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import '../ui/pacta_card_header.dart';

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
            const Text('国策状态均待核对。')
          else
            Text('点亮 $litCount · 确认 $pendingCount · 熄灭 $extinguishedCount'),
          if (pendingReview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${pendingReview.length} 个节点待核对，未计入上方汇总。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final card in pendingReview)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${card.name} · 上次确认：连续 '
                  '${card.currentConsecutiveDays} 天',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题 + 48dp 操作按钮改用统一头部：标题视觉顶距 16dp，
          // 不再因为按钮把单行标题垂直居中而出现上空下紧。
          PactaCardHeader(
            title: '国策状态',
            trailing: TextButton.icon(
              onPressed: widget.onOpenTree,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('打开国策树', softWrap: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const SizedBox(height: 8), ...children],
            ),
          ),
        ],
      ),
    );
  }
}
