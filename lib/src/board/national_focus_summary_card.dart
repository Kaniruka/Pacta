import 'dart:async';

import 'package:flutter/material.dart';

import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import '../ui/pacta_card_header.dart';

/// 今日国策状态的纯计算口径。
///
/// 确认态节点按点亮 / 待确认 / 熄灭计数；待核对节点单独列出，绝不混进
/// 确定汇总（否则会把“不知道”说成“点亮”）。看板融合卡片与国策摘要共用
/// 这一份口径，两个入口对同一天的判断因此永远一致。
@immutable
class NationalFocusStatusCounts {
  const NationalFocusStatusCounts({
    required this.totalCount,
    required this.litCount,
    required this.pendingCount,
    required this.extinguishedCount,
    required this.pendingReview,
  });

  factory NationalFocusStatusCounts.fromCards(List<NationalFocusCard> cards) {
    var lit = 0;
    var pending = 0;
    var extinguished = 0;
    final review = <NationalFocusCard>[];
    for (final card in cards) {
      if (card.hasPendingReview) {
        review.add(card);
        continue;
      }
      switch (card.state) {
        case NationalFocusCardState.lit:
          lit += 1;
        case NationalFocusCardState.pendingTodayConfirmation:
          pending += 1;
        case NationalFocusCardState.extinguished:
          extinguished += 1;
      }
    }
    return NationalFocusStatusCounts(
      totalCount: cards.length,
      litCount: lit,
      pendingCount: pending,
      extinguishedCount: extinguished,
      pendingReview: List<NationalFocusCard>.unmodifiable(review),
    );
  }

  /// 国策树里的节点总数（含待核对）。
  final int totalCount;
  final int litCount;
  final int pendingCount;
  final int extinguishedCount;
  final List<NationalFocusCard> pendingReview;

  bool get isEmpty => totalCount == 0;

  /// 有确定结论的节点数，不含待核对。
  int get confirmedCount => litCount + pendingCount + extinguishedCount;

  /// 全部确定节点都点亮，且没有待核对节点。
  bool get allLit =>
      confirmedCount > 0 && litCount == confirmedCount && pendingReview.isEmpty;

  /// 没有任何确定结论，只剩待核对节点。
  bool get allPendingReview => confirmedCount == 0 && pendingReview.isNotEmpty;
}

/// 今日国策摘要卡片（独立入口）。
///
/// 看板已由 FocusNationalCalendarCard 承载融合展示（今日国策 + 专注热力 +
/// 日期详情），本组件保留作独立摘要入口与兼容测试，不再作为看板的默认卡片。
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

      final counts = NationalFocusStatusCounts.fromCards(cards);
      final pendingReview = counts.pendingReview;

      return _card(
        context,
        children: [
          if (counts.isEmpty)
            const Text('国策树尚无节点。')
          else if (counts.allPendingReview)
            const Text('国策状态均待核对。')
          else
            Text(
              '点亮 ${counts.litCount} · 确认 ${counts.pendingCount} · '
              '熄灭 ${counts.extinguishedCount}',
            ),
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
