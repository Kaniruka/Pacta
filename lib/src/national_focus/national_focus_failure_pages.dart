import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_status_colors.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_disclosure_section.dart';
import '../ui/pacta_error_text.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_models.dart';
import 'national_focus_repository.dart';
import 'national_focus_shared_widgets.dart';

class _FailureExplanationDialog extends StatefulWidget {
  const _FailureExplanationDialog({required this.initialExplanation});

  final String? initialExplanation;

  @override
  State<_FailureExplanationDialog> createState() =>
      _FailureExplanationDialogState();
}

class _FailureExplanationDialogState extends State<_FailureExplanationDialog> {
  late String _explanation = widget.initialExplanation ?? '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('补充失败记录说明'),
    content: TextFormField(
      initialValue: _explanation,
      autofocus: true,
      maxLength: 500,
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => _explanation = value,
      decoration: const InputDecoration(
        labelText: '说明（可选）',
        hintText: '可以补充背景，也可以留空清除已有说明',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(''),
        child: const Text('清除说明'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_explanation),
        child: const Text('保存'),
      ),
    ],
  );
}

class NationalFocusFailureHistoryPage extends StatefulWidget {
  const NationalFocusFailureHistoryPage({
    super.key,
    required this.repository,
    required this.displayTimeZoneId,
    this.nextCheckpointAt,
  });

  final NationalFocusRepository repository;
  final String displayTimeZoneId;

  /// The checkpoint that closes the current National Focus Day. Callers pass
  /// the instant they already display so this page never drifts from the tree.
  final DateTime? nextCheckpointAt;

  @override
  State<NationalFocusFailureHistoryPage> createState() =>
      _NationalFocusFailureHistoryPageState();
}

class _NationalFocusFailureHistoryPageState
    extends State<NationalFocusFailureHistoryPage> {
  late Future<List<NationalFocusFailure>> _failures;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _failures = widget.repository.getFailures();
  }

  Future<void> _editExplanation(NationalFocusFailure failure) async {
    final explanation = await showDialog<String>(
      context: context,
      builder: (_) => _FailureExplanationDialog(
        initialExplanation: failure.sharedExplanation,
      ),
    );
    if (explanation == null || !mounted) return;
    try {
      await widget.repository.updateFailureExplanation(
        batchId: failure.batchId,
        explanation: explanation,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(formatUserError(error))));
      }
    }
  }

  /// 标记整组失败记录为已回顾。不需要填写说明，也不改写失败结果；
  /// 重复触发同一组时仓储层是幂等的。
  Future<void> _markReviewed(NationalFocusFailure failure) async {
    try {
      await widget.repository.markFailureReviewed(batchId: failure.batchId);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(formatUserError(error))));
      }
    }
  }

  Future<void> _openFailureTree(NationalFocusFailure failure) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationalFocusFailureTreePage(
          failure: failure,
          checkpointLabel: _formatCheckpoint(failure.checkpointAt),
        ),
      ),
    );
  }

  String _formatCheckpoint(DateTime checkpoint) {
    final local = FocusTimeZones.contains(widget.displayTimeZoneId)
        ? timezone.TZDateTime.from(
            checkpoint,
            FocusTimeZones.location(widget.displayTimeZoneId),
          )
        : checkpoint.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('国策失败记录')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: PactaSpacing.pageInsets(
              context,
              top: PactaSpacing.xs,
              bottom: PactaSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CheckpointExplanation(
                  nextCheckpointLabel:
                      '下次检查点：'
                      '${_formatCheckpoint(widget.nextCheckpointAt ?? nextNationalFocusCheckpoint(DateTime.now().toUtc()))}'
                      ' · ${widget.displayTimeZoneId}',
                  displayTimeZoneId: widget.displayTimeZoneId,
                ),
                const SizedBox(height: PactaSpacing.sm),
                Expanded(
                  child: FutureBuilder<List<NationalFocusFailure>>(
                    future: _failures,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(formatUserError(snapshot.error!)),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final grouped = <String, List<NationalFocusFailure>>{};
                      for (final failure in snapshot.data!) {
                        grouped
                            .putIfAbsent(failure.batchId, () => [])
                            .add(failure);
                      }
                      if (grouped.isEmpty) {
                        return const Center(child: Text('还没有国策失败记录。'));
                      }
                      final batches = grouped.values.toList(growable: false);
                      return ListView.separated(
                        itemCount: batches.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: PactaSpacing.sm),
                        itemBuilder: (context, index) => _FailureBatchCard(
                          failures: batches[index],
                          checkpointLabel: _formatCheckpoint(
                            batches[index].first.checkpointAt,
                          ),
                          onOpenTree: () =>
                              _openFailureTree(batches[index].first),
                          onEditExplanation: () =>
                              _editExplanation(batches[index].first),
                          onMarkReviewed: () =>
                              _markReviewed(batches[index].first),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CheckpointExplanation extends StatelessWidget {
  const _CheckpointExplanation({
    required this.nextCheckpointLabel,
    required this.displayTimeZoneId,
  });

  final String nextCheckpointLabel;
  final String displayTimeZoneId;

  @override
  Widget build(BuildContext context) => Card(
    child: PactaDisclosureSection(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: const Text('检查点说明'),
      subtitle: Text(nextCheckpointLabel),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('固定规则为北京时间 04:00；显示时区 $displayTimeZoneId 不会移动结算边界。'),
        ),
      ],
    ),
  );
}

class _FailureBatchCard extends StatelessWidget {
  const _FailureBatchCard({
    required this.failures,
    required this.checkpointLabel,
    required this.onOpenTree,
    required this.onEditExplanation,
    required this.onMarkReviewed,
  });

  final List<NationalFocusFailure> failures;
  final String checkpointLabel;
  final VoidCallback onOpenTree;
  final VoidCallback onEditExplanation;
  final VoidCallback onMarkReviewed;

  @override
  Widget build(BuildContext context) {
    final representative = failures.first;
    final isReviewed = failures.every((failure) => failure.isReviewed);
    return Card(
      child: PactaDisclosureSection(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          '$checkpointLabel · ${failures.length} 个节点'
          '${isReviewed ? ' · 已回顾' : ' · 未回顾'}',
        ),
        subtitle: Text(representative.cause.label),
        children: [
          for (final failure in failures)
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(_snapshotName(failure)),
              subtitle: Text(
                '${failure.cause.label}'
                '${failure.failureReason == failure.cause.label ? '' : ' · ${failure.failureReason ?? '原因未填写'}'}',
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onOpenTree,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('查看当时树'),
                ),
                TextButton.icon(
                  onPressed: onEditExplanation,
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    representative.sharedExplanation == null
                        ? '补充说明'
                        : '编辑共同说明',
                  ),
                ),
                if (!isReviewed)
                  TextButton.icon(
                    key: const ValueKey('national-focus-mark-reviewed'),
                    onPressed: onMarkReviewed,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('标记已回顾'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _snapshotName(NationalFocusFailure failure) =>
      failure.treeSnapshot
          .where((card) => card.id == failure.cardId)
          .map((card) => card.name)
          .firstOrNull ??
      '已移除的国策卡';
}

/// Read-only browser for the tree snapshot frozen when a failure batch closed.
///
/// It receives the frozen snapshot value and never a repository, so browsing it
/// cannot restore, rewrite, or recompute the current tree with today's rules.
class NationalFocusFailureTreePage extends StatelessWidget {
  const NationalFocusFailureTreePage({
    super.key,
    required this.failure,
    required this.checkpointLabel,
  });

  final NationalFocusFailure failure;
  final String checkpointLabel;

  @override
  Widget build(BuildContext context) {
    final index = _HistoryTreeIndex(failure.treeSnapshot);
    final nodeHeight = _historyNodeHeight(context);
    return Scaffold(
      appBar: AppBar(title: const Text('当时树（只读）')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: PactaSpacing.pageInsets(context, top: PactaSpacing.sm),
              children: [
                Text(
                  '检查点时的完整树快照',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '$checkpointLabel · ${failure.cause.label}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '点按节点查看当时状态与冻结要求；快照固定在检查点，此页只读，'
                  '不能恢复、改写或用当前规则重算当时节点。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (index.roots.isEmpty)
                  const NationalFocusTreeMessage(
                    icon: Icons.account_tree_outlined,
                    title: '当时树没有节点',
                    message: '这份快照里没有位于树中的节点。',
                  )
                else
                  NationalFocusTreeCanvas(
                    treeWidth: _historyForestWidth(index, _historyNodeWidth),
                    treeHeight: _historyForestHeight(index, nodeHeight),
                    minimumFitScale: _historyMinimumFitScale,
                    fitViewportToContent: true,
                    // 独立根纵向排列：小森林在窄窗里按原始尺寸显示，
                    // 不会为了并排放置两个根把字号压到看不清。
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          var position = 0;
                          position < index.roots.length;
                          position++
                        ) ...[
                          if (position > 0)
                            const SizedBox(height: _historyRootGap),
                          _buildBranch(
                            context: context,
                            card: index.roots[position],
                            path: '${position + 1}',
                            index: index,
                            nodeHeight: nodeHeight,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (index.library.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _HistoricalLibrarySection(
                    cards: index.library,
                    onOpen: (card) => _openNode(context, card, index),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranch({
    required BuildContext context,
    required NationalFocusCardSnapshot card,
    required String path,
    required _HistoryTreeIndex index,
    required double nodeHeight,
  }) {
    final children = index.childrenOf(card.id);
    final width = index.branchWidth(card, _historyNodeWidth);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            width: _historyNodeWidth,
            height: nodeHeight,
            child: KeyedSubtree(
              key: ValueKey('national-focus-history-node-${card.id}'),
              child: _HistoricalFocusNode(
                card: card,
                path: path,
                onOpen: () => _openNode(context, card, index),
              ),
            ),
          ),
          if (children.isNotEmpty) ...[
            Builder(
              builder: (context) => CustomPaint(
                size: Size(width, _historyBranchGap),
                painter: NationalFocusBranchConnectorPainter(
                  childWidths: [
                    for (final child in children)
                      index.branchWidth(child, _historyNodeWidth),
                  ],
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  strokeWidth: math.max(
                    2,
                    1.25 / NationalFocusTreeCanvasScale.of(context),
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var position = 0; position < children.length; position++)
                  _buildBranch(
                    context: context,
                    card: children[position],
                    path: '$path.${position + 1}',
                    index: index,
                    nodeHeight: nodeHeight,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openNode(
    BuildContext context,
    NationalFocusCardSnapshot card,
    _HistoryTreeIndex index,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                card.name,
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '检查点时的只读快照，不随当前树变化。',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              NationalFocusFieldText(
                label: '当时状态',
                value: card.isInTree
                    ? _historyStateLabel(card.state)
                    : '${_historyStateLabel(card.state)}（当时在卡片库）',
              ),
              const SizedBox(height: 12),
              Text('冻结要求', style: Theme.of(sheetContext).textTheme.titleSmall),
              const SizedBox(height: 8),
              NationalFocusFieldText(
                label: '触发条件',
                value: card.effectiveTriggerCondition,
              ),
              const SizedBox(height: 12),
              NationalFocusFieldText(
                label: '国策规则',
                value: card.effectiveAction,
              ),
              if (card.scope != null) ...[
                const SizedBox(height: 12),
                NationalFocusFieldText(label: '范围', value: card.scope!),
              ],
              if (card.exceptionNotes != null) ...[
                const SizedBox(height: 12),
                NationalFocusFieldText(
                  label: '例外与判例',
                  value: card.exceptionNotes!,
                ),
              ],
              if (card.activeStrengtheningLevel != null) ...[
                const SizedBox(height: 12),
                NationalFocusFieldText(
                  label: '强化等级',
                  value: [
                    '等级 ${card.activeStrengtheningLevel}',
                    if (card.requirementVersionNumber != null)
                      '要求版本 ${card.requirementVersionNumber}',
                  ].join(' · '),
                ),
              ],
              const SizedBox(height: 12),
              NationalFocusFieldText(
                label: '记录',
                value:
                    '连续 ${card.currentConsecutiveDays} 天'
                    ' · 最高 ${card.bestConsecutiveDays} 天'
                    ' · 成功日 ${card.successfulDays} 天',
              ),
              for (final note in _failureNotes(card, index))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    note,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                '此页只读：不能恢复、改写或用当前规则重算当时状态。',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<String> _failureNotes(
    NationalFocusCardSnapshot card,
    _HistoryTreeIndex index,
  ) {
    final notes = <String>[];
    final failureSourceId = card.failureSourceCardId;
    if (failureSourceId != null) {
      notes.add(
        failureSourceId == card.id
            ? '独立失败来源。'
            : '因「${index.nameOf(failureSourceId)}」连带熄灭。',
      );
    }
    final cascadeSourceId = card.cascadeSourceCardId;
    if (cascadeSourceId != null) {
      final priorState = card.cascadePriorState;
      notes.add(
        '因「${index.nameOf(cascadeSourceId)}」连带熄灭；'
        '熄灭前状态：${priorState == null ? '未知' : _historyStateLabel(priorState)}。',
      );
    }
    return notes;
  }
}

const _historyNodeWidth = 210.0;
const _historyBranchGap = 36.0;
const _historyRootGap = 28.0;

/// 历史视角的初始可读下限：即便森林较大，初始取景也不把字号压到
/// 原始尺寸的 85% 以下；显式「适应屏幕」仍按全览拟合，保证整片森林
/// 完整可见；捏合可继续缩放、平移。
const _historyMinimumFitScale = 0.85;

double _historyNodeHeight(BuildContext context) =>
    140 * MediaQuery.textScalerOf(context).scale(1);

/// 历史视角对冻结状态的措辞：描述检查点时已经发生的状态，
/// 而不是沿用实时树里进行时的动作标签（点亮/确认/熄灭）。
String _historyStateLabel(NationalFocusCardState state) => switch (state) {
  NationalFocusCardState.lit => '已点亮',
  NationalFocusCardState.pendingTodayConfirmation => '待今日确认',
  NationalFocusCardState.extinguished => '已熄灭',
};

/// 垂直堆叠时整片森林的宽度：舍入到最宽的一支。
double _historyForestWidth(_HistoryTreeIndex index, double nodeWidth) {
  var width = 0.0;
  for (final root in index.roots) {
    width = math.max(width, index.branchWidth(root, nodeWidth));
  }
  return width;
}

/// 垂直堆叠时整片森林的高度：各根分支高度之和加上根间距。
double _historyForestHeight(_HistoryTreeIndex index, double nodeHeight) {
  var height = 0.0;
  for (final root in index.roots) {
    height += _historyBranchHeight(index, root, nodeHeight);
  }
  if (index.roots.length > 1) {
    height += _historyRootGap * (index.roots.length - 1);
  }
  return height;
}

double _historyBranchHeight(
  _HistoryTreeIndex index,
  NationalFocusCardSnapshot card,
  double nodeHeight,
) {
  final children = index.childrenOf(card.id);
  if (children.isEmpty) return nodeHeight;
  final childHeight = children
      .map((child) => _historyBranchHeight(index, child, nodeHeight))
      .reduce(math.max);
  return nodeHeight + _historyBranchGap + childHeight;
}

/// Groups one frozen snapshot into a browsable forest without changing it.
///
/// Only isInTree nodes participate in the tree; cards that were in the
/// library at the checkpoint are kept aside. A corrupt parent cycle is broken
/// by promoting the node to a root instead of recursing forever.
class _HistoryTreeIndex {
  _HistoryTreeIndex(List<NationalFocusCardSnapshot> snapshot)
    : byId = {for (final card in snapshot) card.id: card} {
    for (final card in snapshot) {
      if (!card.isInTree) {
        library.add(card);
        continue;
      }
      final parentId = card.parentId;
      final parent = parentId == null ? null : byId[parentId];
      final resolvedParentId =
          parent != null && parent.isInTree && !_wouldCycle(card, parent)
          ? parentId
          : null;
      childrenByParent.putIfAbsent(resolvedParentId, () => []).add(card);
    }
    roots = childrenByParent[null] ?? const <NationalFocusCardSnapshot>[];
  }

  final Map<String, NationalFocusCardSnapshot> byId;
  final Map<String?, List<NationalFocusCardSnapshot>> childrenByParent = {};
  final List<NationalFocusCardSnapshot> library = [];
  late final List<NationalFocusCardSnapshot> roots;

  bool _wouldCycle(
    NationalFocusCardSnapshot card,
    NationalFocusCardSnapshot parent,
  ) {
    String? currentId = parent.id;
    final visited = <String>{};
    while (currentId != null && visited.add(currentId)) {
      if (currentId == card.id) return true;
      currentId = byId[currentId]?.parentId;
    }
    return false;
  }

  List<NationalFocusCardSnapshot> childrenOf(String cardId) =>
      childrenByParent[cardId] ?? const [];

  String nameOf(String cardId) => byId[cardId]?.name ?? '父节点';

  int get depth => _depth(roots, <String>{});

  int _depth(List<NationalFocusCardSnapshot> nodes, Set<String> visited) {
    var best = 0;
    for (final node in nodes) {
      if (visited.contains(node.id)) continue;
      final next = {...visited, node.id};
      best = math.max(best, 1 + _depth(childrenOf(node.id), next));
    }
    return best;
  }

  double branchWidth(NationalFocusCardSnapshot card, double nodeWidth) =>
      _branchWidth(card, nodeWidth, <String>{});

  double _branchWidth(
    NationalFocusCardSnapshot card,
    double nodeWidth,
    Set<String> visited,
  ) {
    final children = childrenOf(card.id);
    if (visited.contains(card.id) || children.isEmpty) return nodeWidth + 16;
    final next = {...visited, card.id};
    return children.fold<double>(
      0,
      (width, child) => width + _branchWidth(child, nodeWidth, next),
    );
  }
}

class _HistoricalFocusNode extends StatelessWidget {
  const _HistoricalFocusNode({
    required this.card,
    required this.path,
    required this.onOpen,
  });

  final NationalFocusCardSnapshot card;
  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 画布本身是 surfaceContainerLow：历史节点必须换成卡片底色再加一圈
    // 细边框，否则整张卡融进画布，节点边界和可点区域都读不出来。
    final cardSurface = PactaSurfaces.cardFor(Theme.of(context).brightness);
    final statusIcon = switch (card.state) {
      NationalFocusCardState.lit => Icons.lightbulb,
      NationalFocusCardState.pendingTodayConfirmation => Icons.hourglass_top,
      NationalFocusCardState.extinguished => Icons.lightbulb_outline,
    };
    final iconBackground = switch (card.state) {
      NationalFocusCardState.lit => PactaStatusColors.of(
        context,
      ).successContainer,
      NationalFocusCardState.pendingTodayConfirmation =>
        colors.tertiaryContainer,
      NationalFocusCardState.extinguished => colors.surfaceContainerHighest,
    };
    final iconColor = switch (card.state) {
      NationalFocusCardState.lit => PactaStatusColors.of(
        context,
      ).onSuccessContainer,
      NationalFocusCardState.pendingTodayConfirmation =>
        colors.onTertiaryContainer,
      NationalFocusCardState.extinguished => colors.onSurfaceVariant,
    };
    return Semantics(
      button: true,
      label:
          '历史节点 $path，${card.name}，${_historyStateLabel(card.state)}，'
          '连续 ${card.currentConsecutiveDays} 天，打开冻结要求',
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PactaSpacing.cardRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(PactaSpacing.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconBackground,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Icon(
                    statusIcon,
                    size: PactaIconSizes.md,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  card.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_historyStateLabel(card.state)} · 连续 ${card.currentConsecutiveDays} 天',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  card.effectiveAction,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoricalLibrarySection extends StatelessWidget {
  const _HistoricalLibrarySection({required this.cards, required this.onOpen});

  final List<NationalFocusCardSnapshot> cards;
  final ValueChanged<NationalFocusCardSnapshot> onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: PactaDisclosureSection(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text('当时在卡片库（${cards.length}）'),
      subtitle: const Text('这些节点在检查点不在树中，按当时快照只读展示。'),
      children: [
        for (final card in cards)
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('卡片库内 · ${card.name}'),
            subtitle: Text('${card.state.label} · ${card.effectiveAction}'),
            onTap: () => onOpen(card),
          ),
      ],
    ),
  );
}
