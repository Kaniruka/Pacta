import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_models.dart';
import 'national_focus_repository.dart';

/// The National Focus destination body. The app shell owns the app bar and
/// bottom navigation; this widget owns the tree canvas and its local flows.
class NationalFocusTreePage extends StatefulWidget {
  const NationalFocusTreePage({
    super.key,
    required this.repository,
    this.displayTimeZoneLoader,
    this.now,
  });

  final NationalFocusRepository repository;
  final Future<String?> Function()? displayTimeZoneLoader;
  final DateTime Function()? now;

  @override
  State<NationalFocusTreePage> createState() => _NationalFocusTreePageState();
}

class _NationalFocusTreePageState extends State<NationalFocusTreePage> {
  bool _detailed = false;
  NationalFocusCard? _placementCard;
  String? _error;
  String _displayTimeZoneId = 'Etc/UTC';
  late DateTime _now;
  final Set<String> _busyCardIds = {};
  bool _confirming = false;
  Timer? _settlementTimer;

  @override
  void initState() {
    super.initState();
    _now = (widget.now?.call() ?? DateTime.now()).toUtc();
    _loadDisplayTimeZone();
    _settlementTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshCheckpointState(),
    );
  }

  @override
  void dispose() {
    _settlementTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDisplayTimeZone() async {
    try {
      final zoneId = await widget.displayTimeZoneLoader?.call();
      if (!mounted || zoneId == null || !FocusTimeZones.contains(zoneId)) {
        return;
      }
      setState(() => _displayTimeZoneId = zoneId);
    } catch (_) {
      // UTC remains a clear fallback if the device zone cannot be read.
    }
  }

  Future<void> _refreshCheckpointState() async {
    _now = (widget.now?.call() ?? DateTime.now()).toUtc();
    try {
      await widget.repository.settleDueCheckpoints();
    } catch (_) {
      // Keep the last readable tree visible; the next repository operation
      // retries settlement and reports any actionable error.
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmToday() async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final count = await widget.repository.confirmToday();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0 ? '当前没有待确认节点。' : '已确认 $count 个国策节点今日继续有效。',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _lightCard(NationalFocusCard card) async {
    if (!_busyCardIds.add(card.id)) return;
    setState(() => _error = null);
    try {
      await widget.repository.lightCard(card.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              card.state == NationalFocusCardState.pendingTodayConfirmation
                  ? '已确认「${card.triggerCondition}」今日继续有效。'
                  : '已点亮「${card.triggerCondition}」。',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      _busyCardIds.remove(card.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _extinguishCard(NationalFocusCard card) async {
    late final List<NationalFocusCard> treeCards;
    try {
      treeCards = await widget.repository.getTreeCards();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
      return;
    }
    if (!mounted) return;
    final childrenByParent = <String, List<NationalFocusCard>>{};
    for (final treeCard in treeCards) {
      final parentId = treeCard.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(treeCard);
      }
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ExtinguishReasonDialog(
        card: card,
        descendantCount: _descendantsOf(card.id, childrenByParent).length,
      ),
    );
    if (reason == null || !mounted || !_busyCardIds.add(card.id)) return;

    setState(() => _error = null);
    try {
      await widget.repository.extinguishCard(
        cardId: card.id,
        failureReason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已熄灭「${card.triggerCondition}」。')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      _busyCardIds.remove(card.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openFailureHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NationalFocusFailureHistorySheet(
        repository: widget.repository,
        displayTimeZoneId: _displayTimeZoneId,
      ),
    );
  }

  String _formatCheckpoint(DateTime now, String timeZoneId) {
    final checkpoint = nextNationalFocusCheckpoint(now);
    final localTime = FocusTimeZones.contains(timeZoneId)
        ? timezone.TZDateTime.from(
            checkpoint,
            FocusTimeZones.location(timeZoneId),
          )
        : checkpoint.toLocal();
    final date =
        '${localTime.year}-'
        '${localTime.month.toString().padLeft(2, '0')}-'
        '${localTime.day.toString().padLeft(2, '0')}';
    final time =
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}';
    return '下次检查点：$date $time · $timeZoneId';
  }

  Future<void> _openLibrary() async {
    final card = await Navigator.of(context).push<NationalFocusCard>(
      MaterialPageRoute<NationalFocusCard>(
        builder: (_) =>
            NationalFocusCardLibraryPage(repository: widget.repository),
      ),
    );
    if (!mounted || card == null) return;
    setState(() {
      _placementCard = card;
      _error = null;
    });
  }

  void _beginPlacement(NationalFocusCard card) {
    setState(() {
      _placementCard = card;
      _error = null;
    });
  }

  Future<void> _placeAt(String? parentId) async {
    final card = _placementCard;
    if (card == null) return;
    setState(() => _error = null);
    try {
      await widget.repository.placeCard(cardId: card.id, parentId: parentId);
      if (!mounted) return;
      setState(() => _placementCard = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parentId == null ? '已放到顶层；卡片仍为熄灭状态。' : '已放置到所选父节点下；卡片仍为熄灭状态。',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  void _cancelPlacement() {
    setState(() {
      _placementCard = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: StreamBuilder<List<NationalFocusCard>>(
      stream: widget.repository.watchTreeCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _TreeMessage(
            icon: Icons.error_outline,
            title: '无法读取国策树',
            message: _friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cards = snapshot.data!;
        final cardsById = {for (final card in cards) card.id: card};
        final pendingCount = cards
            .where(
              (card) =>
                  card.state == NationalFocusCardState.pendingTodayConfirmation,
            )
            .length;
        final childrenByParent = <String, List<NationalFocusCard>>{};
        final roots = <NationalFocusCard>[];
        for (final card in cards) {
          final parentId = card.parentId;
          if (parentId == null) {
            roots.add(card);
          } else {
            childrenByParent.putIfAbsent(parentId, () => []).add(card);
          }
        }
        final blockedParentIds = _descendantsOf(
          _placementCard?.id,
          childrenByParent,
        );
        if (_placementCard != null) blockedParentIds.add(_placementCard!.id);
        final placementContainsActiveCard =
            _placementCard != null &&
            _subtreeContainsActiveCard(
              _placementCard!.id,
              childrenByParent,
              cardsById,
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '国策树',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '确认节点今日继续有效，并查看连续记录与内化进度。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _placementCard == null ? _openLibrary : null,
                    icon: const Icon(Icons.library_books_outlined),
                    label: const Text('卡片库'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _MaintenanceSummary(
                nextCheckpoint: _formatCheckpoint(_now, _displayTimeZoneId),
                displayTimeZoneId: _displayTimeZoneId,
                pendingCount: pendingCount,
                confirming: _confirming,
                onConfirm: _placementCard == null ? _confirmToday : null,
                onOpenHistory: _openFailureHistory,
              ),
            ),
            if (_placementCard case final card?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: _PlacementBanner(card: card, onCancel: _cancelPlacement),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _InlineError(_error!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.account_tree_outlined),
                      label: Text('结构'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.article_outlined),
                      label: Text('详情'),
                    ),
                  ],
                  selected: {_detailed},
                  onSelectionChanged: _placementCard == null
                      ? (value) => setState(() => _detailed = value.single)
                      : null,
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                key: const PageStorageKey<String>('national-focus-tree'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: _TopLevelPosition(
                        isSelecting: _placementCard != null,
                        onTap: _placementCard == null
                            ? null
                            : () => _placeAt(null),
                      ),
                    ),
                  ),
                  if (roots.isEmpty && _placementCard == null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      sliver: SliverToBoxAdapter(
                        child: _TreeMessage(
                          icon: Icons.account_tree_outlined,
                          title: '树画布还是空的',
                          message: '先在卡片库创建国策卡，再回到这里选择顶层或父节点。',
                          action: FilledButton.icon(
                            onPressed: _openLibrary,
                            icon: const Icon(Icons.library_books_outlined),
                            label: const Text('打开卡片库'),
                          ),
                        ),
                      ),
                    )
                  else if (roots.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList.list(
                        children: [
                          for (var index = 0; index < roots.length; index++)
                            _buildBranch(
                              card: roots[index],
                              path: '${index + 1}',
                              depth: 0,
                              childrenByParent: childrenByParent,
                              blockedParentIds: blockedParentIds,
                              cardsById: cardsById,
                              placementContainsActiveCard:
                                  placementContainsActiveCard,
                              hasExtinguishedAncestor: false,
                            ),
                        ],
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      sliver: SliverToBoxAdapter(
                        child: _TreeMessage(
                          icon: Icons.touch_app_outlined,
                          title: '选择树中的父节点',
                          message: '树中暂时没有可选父节点；你可以把这张卡放到顶层。',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildBranch({
    required NationalFocusCard card,
    required String path,
    required int depth,
    required Map<String, List<NationalFocusCard>> childrenByParent,
    required Set<String> blockedParentIds,
    required Map<String, NationalFocusCard> cardsById,
    required bool placementContainsActiveCard,
    required bool hasExtinguishedAncestor,
  }) {
    final children = childrenByParent[card.id] ?? const [];
    final targetBranchIsExtinguished =
        hasExtinguishedAncestor ||
        card.state == NationalFocusCardState.extinguished;
    final isBlocked =
        blockedParentIds.contains(card.id) ||
        (placementContainsActiveCard && targetBranchIsExtinguished);
    final selecting = _placementCard != null;
    final branch = _NationalFocusTreeNode(
      card: card,
      path: path,
      detailed: _detailed,
      selecting: selecting,
      blocked: isBlocked,
      lightBlocked: hasExtinguishedAncestor,
      cascadeSourceLabel: card.cascadeSourceCardId == null
          ? null
          : cardsById[card.cascadeSourceCardId]?.triggerCondition ?? '父节点',
      onSelect: selecting && !isBlocked ? () => _placeAt(card.id) : null,
      onRelocate: () => _beginPlacement(card),
      onLight: selecting || hasExtinguishedAncestor
          ? null
          : () => _lightCard(card),
      onExtinguish: selecting ? null : () => _extinguishCard(card),
      busy: _busyCardIds.contains(card.id),
    );
    return Padding(
      padding: EdgeInsets.only(left: math.min(depth, 6) * 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          branch,
          if (children.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 18),
              padding: const EdgeInsets.only(left: 12, top: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < children.length; index++)
                    _buildBranch(
                      card: children[index],
                      path: '$path.${index + 1}',
                      depth: depth + 1,
                      childrenByParent: childrenByParent,
                      blockedParentIds: blockedParentIds,
                      cardsById: cardsById,
                      placementContainsActiveCard: placementContainsActiveCard,
                      hasExtinguishedAncestor:
                          hasExtinguishedAncestor ||
                          card.state == NationalFocusCardState.extinguished,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class NationalFocusCardLibraryPage extends StatelessWidget {
  const NationalFocusCardLibraryPage({super.key, required this.repository});

  final NationalFocusRepository repository;

  Future<void> _createCard(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NationalFocusCardEditorPage(repository: repository),
      ),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('卡片已保存到卡片库；放置位置还未确定。')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('国策卡片库')),
    body: StreamBuilder<List<NationalFocusCard>>(
      stream: repository.watchLibraryCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _TreeMessage(
            icon: Icons.error_outline,
            title: '无法读取卡片库',
            message: snapshot.error.toString(),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cards = snapshot.data!;
        if (cards.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _TreeMessage(
                icon: Icons.library_books_outlined,
                title: '卡片库还是空的',
                message: '创建一张国策卡，再单独选择它在树画布中的位置。',
                action: FilledButton.icon(
                  onPressed: () => _createCard(context),
                  icon: const Icon(Icons.add),
                  label: const Text('新建国策卡'),
                ),
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _LibraryCard(
                  card: cards[index],
                  onPlace: () => Navigator.of(context).pop(cards[index]),
                ),
              ),
            ),
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _createCard(context),
      icon: const Icon(Icons.add),
      label: const Text('新建国策卡'),
    ),
  );
}

class NationalFocusCardEditorPage extends StatefulWidget {
  const NationalFocusCardEditorPage({super.key, required this.repository});

  final NationalFocusRepository repository;

  @override
  State<NationalFocusCardEditorPage> createState() =>
      _NationalFocusCardEditorPageState();
}

class _NationalFocusCardEditorPageState
    extends State<NationalFocusCardEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _trigger = TextEditingController();
  final _action = TextEditingController();
  final _scope = TextEditingController();
  final _exceptionNotes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _trigger.dispose();
    _action.dispose();
    _scope.dispose();
    _exceptionNotes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createCard(
        NationalFocusCardDraft(
          triggerCondition: _trigger.text,
          action: _action.text,
          scope: _scope.text,
          exceptionNotes: _exceptionNotes.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新建国策卡')),
    body: Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  '写下你自己判断是否有效的规则。应用只保存和展示内容，不会评估现实是否符合。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _trigger,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '主要触发条件',
                    hintText: '例如：坐到书桌前后',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => _requiredFieldError(value, '主要触发条件'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _action,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '行动',
                    hintText: '例如：先完成计划中的第一项',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => _requiredFieldError(value, '行动'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _scope,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '适用范围（可选）',
                    hintText: '例如：仅工作日',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _exceptionNotes,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '例外说明（可选）',
                    hintText: '例如：出差时顺延',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _InlineError(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_busy ? '保存中' : '保存到卡片库'),
          ),
        ),
      ),
    ),
  );
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.card, required this.onPlace});

  final NationalFocusCard card;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldText(label: '主要触发条件', value: card.triggerCondition),
          const SizedBox(height: 12),
          _FieldText(label: '行动', value: card.action),
          if (card.scope != null) ...[
            const SizedBox(height: 12),
            _FieldText(label: '适用范围', value: card.scope!),
          ],
          if (card.exceptionNotes != null) ...[
            const SizedBox(height: 12),
            _FieldText(label: '例外说明', value: card.exceptionNotes!),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: onPlace,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('放入树画布'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _NationalFocusTreeNode extends StatelessWidget {
  const _NationalFocusTreeNode({
    required this.card,
    required this.path,
    required this.detailed,
    required this.selecting,
    required this.blocked,
    required this.lightBlocked,
    required this.cascadeSourceLabel,
    required this.onSelect,
    required this.onRelocate,
    required this.onLight,
    required this.onExtinguish,
    required this.busy,
  });

  final NationalFocusCard card;
  final String path;
  final bool detailed;
  final bool selecting;
  final bool blocked;
  final bool lightBlocked;
  final String? cascadeSourceLabel;
  final VoidCallback? onSelect;
  final VoidCallback onRelocate;
  final VoidCallback? onLight;
  final VoidCallback? onExtinguish;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = detailed
        ? _DetailedTreeCard(
            card: card,
            path: path,
            selecting: selecting,
            blocked: blocked,
            lightBlocked: lightBlocked,
            cascadeSourceLabel: cascadeSourceLabel,
            onRelocate: onRelocate,
            onLight: onLight,
            onExtinguish: onExtinguish,
            busy: busy,
          )
        : _StructureTreeCard(
            card: card,
            path: path,
            blocked: selecting && blocked,
            lightBlocked: lightBlocked,
            cascadeSourceLabel: cascadeSourceLabel,
            onLight: onLight,
            onExtinguish: onExtinguish,
            busy: busy,
          );

    if (!selecting) return Card(child: content);
    return Semantics(
      button: !blocked,
      enabled: !blocked,
      label: blocked ? '第 $path 个节点不能选作父节点' : '选择第 $path 个节点作为父节点',
      child: Card(
        color: blocked ? colors.surfaceContainerLow : colors.secondaryContainer,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(12),
          child: content,
        ),
      ),
    );
  }
}

class _StructureTreeCard extends StatelessWidget {
  const _StructureTreeCard({
    required this.card,
    required this.path,
    required this.blocked,
    required this.lightBlocked,
    required this.cascadeSourceLabel,
    required this.onLight,
    required this.onExtinguish,
    required this.busy,
  });

  final NationalFocusCard card;
  final String path;
  final bool blocked;
  final bool lightBlocked;
  final String? cascadeSourceLabel;
  final VoidCallback? onLight;
  final VoidCallback? onExtinguish;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: blocked
                    ? colors.surfaceContainerHighest
                    : colors.primaryContainer,
                child: Icon(
                  Icons.account_tree_outlined,
                  color: blocked
                      ? colors.onSurfaceVariant
                      : colors.onPrimaryContainer,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '节点 $path · ${card.state.label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (blocked)
                const Tooltip(
                  message: '不能把有效分支放到本人、后代或熄灭分支下',
                  child: Icon(Icons.block_outlined),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: colors.onSurfaceVariant,
                  semanticLabel: '树节点',
                ),
            ],
          ),
        ),
        if (onLight != null || onExtinguish != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NationalFocusRecordSummary(card: card),
                if (cascadeSourceLabel != null) ...[
                  const SizedBox(height: 8),
                  _CascadeStatusNote(
                    sourceLabel: cascadeSourceLabel!,
                    lightBlocked: lightBlocked,
                  ),
                ],
                const SizedBox(height: 12),
                _NodeMaintenanceAction(
                  card: card,
                  onLight: onLight,
                  onExtinguish: onExtinguish,
                  busy: busy,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CascadeStatusNote extends StatelessWidget {
  const _CascadeStatusNote({
    required this.sourceLabel,
    required this.lightBlocked,
  });

  final String sourceLabel;
  final bool lightBlocked;

  @override
  Widget build(BuildContext context) => Text(
    lightBlocked ? '因「$sourceLabel」连带熄灭；父节点恢复后仍需单独点亮。' : '父节点已恢复；此节点仍需单独点亮。',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

class _DetailedTreeCard extends StatelessWidget {
  const _DetailedTreeCard({
    required this.card,
    required this.path,
    required this.selecting,
    required this.blocked,
    required this.lightBlocked,
    required this.cascadeSourceLabel,
    required this.onRelocate,
    required this.onLight,
    required this.onExtinguish,
    required this.busy,
  });

  final NationalFocusCard card;
  final String path;
  final bool selecting;
  final bool blocked;
  final bool lightBlocked;
  final String? cascadeSourceLabel;
  final VoidCallback onRelocate;
  final VoidCallback? onLight;
  final VoidCallback? onExtinguish;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '节点 $path',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _StateChip(state: card.state),
          ],
        ),
        const SizedBox(height: 16),
        _FieldText(label: '主要触发条件', value: card.triggerCondition),
        const SizedBox(height: 12),
        _FieldText(label: '行动', value: card.action),
        if (card.scope != null) ...[
          const SizedBox(height: 12),
          _FieldText(label: '适用范围', value: card.scope!),
        ],
        if (card.exceptionNotes != null) ...[
          const SizedBox(height: 12),
          _FieldText(label: '例外说明', value: card.exceptionNotes!),
        ],
        const SizedBox(height: 16),
        _NationalFocusRecordSummary(card: card),
        if (cascadeSourceLabel != null) ...[
          const SizedBox(height: 8),
          _CascadeStatusNote(
            sourceLabel: cascadeSourceLabel!,
            lightBlocked: lightBlocked,
          ),
        ],
        if (!selecting) ...[
          const SizedBox(height: 12),
          _NodeMaintenanceAction(
            card: card,
            onLight: onLight,
            onExtinguish: onExtinguish,
            busy: busy,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRelocate,
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('调整树中位置'),
            ),
          ),
        ] else if (blocked) ...[
          const SizedBox(height: 8),
          Text(
            '不能把有效分支放到本人、后代或熄灭分支下。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class _MaintenanceSummary extends StatelessWidget {
  const _MaintenanceSummary({
    required this.nextCheckpoint,
    required this.displayTimeZoneId,
    required this.pendingCount,
    required this.confirming,
    required this.onConfirm,
    required this.onOpenHistory,
  });

  final String nextCheckpoint;
  final String displayTimeZoneId;
  final int pendingCount;
  final bool confirming;
  final VoidCallback? onConfirm;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.schedule_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nextCheckpoint,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '固定规则为北京时间 04:00；显示时区 $displayTimeZoneId 不会移动结算边界。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pendingCount == 0 ? '今日没有待确认节点。' : '待今日确认：$pendingCount 个节点',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onConfirm == null || pendingCount == 0 || confirming
                    ? null
                    : onConfirm,
                icon: confirming
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all),
                label: Text(confirming ? '正在确认' : '一键确认今日'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenHistory,
                icon: const Icon(Icons.history),
                label: const Text('查看失败记录'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NationalFocusRecordSummary extends StatelessWidget {
  const _NationalFocusRecordSummary({required this.card});

  final NationalFocusCard card;

  @override
  Widget build(BuildContext context) {
    final progress = card.internalizationProgress.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '当前连续 ${card.currentConsecutiveDays} 天 · 历史最高 '
          '${card.bestConsecutiveDays} 天 · 成功日 ${card.successfulDays} 天',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '内化进度 ${progress.toStringAsFixed(1)}%',
          child: LinearProgressIndicator(value: progress / 100),
        ),
        const SizedBox(height: 4),
        Text(
          '内化进度 ${progress.toStringAsFixed(1)}% · 按成功日累计计算',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _NodeMaintenanceAction extends StatelessWidget {
  const _NodeMaintenanceAction({
    required this.card,
    required this.onLight,
    required this.onExtinguish,
    required this.busy,
  });

  final NationalFocusCard card;
  final VoidCallback? onLight;
  final VoidCallback? onExtinguish;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (card.state == NationalFocusCardState.lit) {
      return OutlinedButton.icon(
        onPressed: busy ? null : onExtinguish,
        icon: const Icon(Icons.lightbulb_outline),
        label: const Text('主动熄灭'),
      );
    }
    if (card.state == NationalFocusCardState.pendingTodayConfirmation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: busy ? null : onLight,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('确认今日继续有效'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onExtinguish,
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('主动熄灭'),
          ),
        ],
      );
    }
    return FilledButton.tonalIcon(
      onPressed: busy ? null : onLight,
      icon: const Icon(Icons.lightbulb),
      label: const Text('点亮'),
    );
  }
}

class _ExtinguishReasonDialog extends StatefulWidget {
  const _ExtinguishReasonDialog({
    required this.card,
    required this.descendantCount,
  });

  final NationalFocusCard card;
  final int descendantCount;

  @override
  State<_ExtinguishReasonDialog> createState() =>
      _ExtinguishReasonDialogState();
}

class _ExtinguishReasonDialogState extends State<_ExtinguishReasonDialog> {
  String _reason = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('主动熄灭这个节点？'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('「${widget.card.triggerCondition}」会在下一检查点结算；此前重新点亮可保留当前连续记录。'),
        if (widget.descendantCount > 0) ...[
          const SizedBox(height: 8),
          Text('此操作也会熄灭 ${widget.descendantCount} 个后代。父节点恢复后，后代仍需逐个点亮。'),
        ],
        const SizedBox(height: 16),
        TextField(
          autofocus: true,
          maxLength: 300,
          minLines: 1,
          maxLines: 3,
          onChanged: (value) => _reason = value,
          decoration: const InputDecoration(
            labelText: '失败原因（可选）',
            hintText: '可以留空，之后再补充说明',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(''),
        child: const Text('暂不填写'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_reason),
        child: const Text('保存原因并熄灭'),
      ),
    ],
  );
}

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

class NationalFocusFailureHistorySheet extends StatefulWidget {
  const NationalFocusFailureHistorySheet({
    super.key,
    required this.repository,
    required this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final String displayTimeZoneId;

  @override
  State<NationalFocusFailureHistorySheet> createState() =>
      _NationalFocusFailureHistorySheetState();
}

class _NationalFocusFailureHistorySheetState
    extends State<NationalFocusFailureHistorySheet> {
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
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    }
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
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('国策失败记录', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<NationalFocusFailure>>(
                future: _failures,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(_friendlyError(snapshot.error!)));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final grouped = <String, List<NationalFocusFailure>>{};
                  for (final failure in snapshot.data!) {
                    grouped.putIfAbsent(failure.batchId, () => []).add(failure);
                  }
                  if (grouped.isEmpty) {
                    return const Center(child: Text('还没有国策失败记录。'));
                  }
                  final batches = grouped.values.toList(growable: false);
                  return ListView.separated(
                    itemCount: batches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _FailureBatchCard(
                      failures: batches[index],
                      checkpointLabel: _formatCheckpoint(
                        batches[index].first.checkpointAt,
                      ),
                      onEditExplanation: () =>
                          _editExplanation(batches[index].first),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FailureBatchCard extends StatelessWidget {
  const _FailureBatchCard({
    required this.failures,
    required this.checkpointLabel,
    required this.onEditExplanation,
  });

  final List<NationalFocusFailure> failures;
  final String checkpointLabel;
  final VoidCallback onEditExplanation;

  @override
  Widget build(BuildContext context) {
    final representative = failures.first;
    final snapshotById = {
      for (final card in representative.treeSnapshot) card.id: card,
    };
    final snapshotCards = [...representative.treeSnapshot]
      ..sort((first, second) {
        final depthOrder = _snapshotDepth(
          first,
          snapshotById,
        ).compareTo(_snapshotDepth(second, snapshotById));
        if (depthOrder != 0) return depthOrder;
        return first.triggerCondition.compareTo(second.triggerCondition);
      });
    return Card(
      child: Column(
        children: [
          ExpansionTile(
            title: Text('$checkpointLabel · ${failures.length} 个节点'),
            subtitle: Text(representative.cause.label),
            children: [
              for (final failure in failures)
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(_snapshotName(failure)),
                  subtitle: Text(
                    '${failure.cause.label} · '
                    '${failure.failureReason ?? '原因未填写'}',
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '检查点时的完整树快照',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final card in snapshotCards)
                      Padding(
                        padding: EdgeInsets.only(
                          top: 6,
                          left: _snapshotDepth(card, snapshotById) * 14,
                        ),
                        child: Text(
                          '${card.triggerCondition} · ${card.state.label} · '
                          '连续 ${card.currentConsecutiveDays} 天 · '
                          '最高 ${card.bestConsecutiveDays} 天'
                          '${_snapshotFailureAnnotation(card, snapshotById)}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onEditExplanation,
                icon: const Icon(Icons.edit_note),
                label: Text(
                  representative.sharedExplanation == null ? '补充说明' : '编辑共同说明',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _snapshotName(NationalFocusFailure failure) =>
      failure.treeSnapshot
          .where((card) => card.id == failure.cardId)
          .map((card) => card.triggerCondition)
          .firstOrNull ??
      '已移除的国策卡';

  int _snapshotDepth(
    NationalFocusCardSnapshot card,
    Map<String, NationalFocusCardSnapshot> cardsById,
  ) {
    var depth = 0;
    var parentId = card.parentId;
    final visited = <String>{card.id};
    while (parentId != null && visited.add(parentId)) {
      final parent = cardsById[parentId];
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  String _snapshotFailureAnnotation(
    NationalFocusCardSnapshot card,
    Map<String, NationalFocusCardSnapshot> cardsById,
  ) {
    final sourceId = card.failureSourceCardId;
    if (sourceId == null) return '';
    if (sourceId == card.id) return ' · 独立失败来源';
    final source = cardsById[sourceId];
    return ' · 因「${source?.triggerCondition ?? '父节点'}」连带熄灭';
  }
}

class _TopLevelPosition extends StatelessWidget {
  const _TopLevelPosition({required this.isSelecting, required this.onTap});

  final bool isSelecting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: isSelecting
          ? colors.tertiaryContainer
          : colors.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.vertical_align_top, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '顶层位置',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isSelecting ? '放置当前卡片到这里' : '只确定树结构；顶层位置本身没有状态。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isSelecting)
                const Icon(Icons.chevron_right, semanticLabel: '放到顶层'),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementBanner extends StatelessWidget {
  const _PlacementBanner({required this.card, required this.onCancel});

  final NationalFocusCard card;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '为「${card.triggerCondition}」选择位置：点顶层或一个节点。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: '取消选择位置',
            onPressed: onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final NationalFocusCardState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (state) {
      NationalFocusCardState.lit => (
        Icons.lightbulb,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      NationalFocusCardState.pendingTodayConfirmation => (
        Icons.hourglass_top,
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      NationalFocusCardState.extinguished => (
        Icons.lightbulb_outline,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Semantics(
      label: '卡片状态：${state.label}',
      child: Chip(
        avatar: Icon(icon, size: 18, color: foreground),
        label: Text(state.label),
        backgroundColor: background,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _FieldText extends StatelessWidget {
  const _FieldText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

class _TreeMessage extends StatelessWidget {
  const _TreeMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}

Set<String> _descendantsOf(
  String? cardId,
  Map<String, List<NationalFocusCard>> childrenByParent,
) {
  if (cardId == null) return {};
  final result = <String>{};
  final pending = [...?childrenByParent[cardId]?.map((card) => card.id)];
  while (pending.isNotEmpty) {
    final next = pending.removeLast();
    if (!result.add(next)) continue;
    pending.addAll(childrenByParent[next]?.map((card) => card.id) ?? const []);
  }
  return result;
}

bool _subtreeContainsActiveCard(
  String cardId,
  Map<String, List<NationalFocusCard>> childrenByParent,
  Map<String, NationalFocusCard> cardsById,
) {
  final branchIds = <String>{
    cardId,
    ..._descendantsOf(cardId, childrenByParent),
  };
  return branchIds.any((id) {
    final card = cardsById[id];
    return card != null && card.state != NationalFocusCardState.extinguished;
  });
}

String? _requiredFieldError(String? value, String label) =>
    value == null || value.trim().isEmpty ? '请输入$label。' : null;

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
