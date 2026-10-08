import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_models.dart';
import 'national_focus_reconciliation_page.dart';
import 'national_focus_repository.dart';
import 'national_focus_strengthening_page.dart';

void _syncNationalFocusInBackground(NationalFocusRepository repository) {
  unawaited(repository.sync().catchError((Object _) {}));
}

Future<void> _openStrengtheningManager({
  required BuildContext context,
  required NationalFocusRepository repository,
  required String cardId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) =>
        NationalFocusStrengtheningPage(repository: repository, cardId: cardId),
  ),
);

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

  void _syncInBackground() {
    _syncNationalFocusInBackground(widget.repository);
  }

  Future<void> _confirmToday() async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final count = await widget.repository.confirmToday();
      _syncInBackground();
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
      _syncInBackground();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              card.state == NationalFocusCardState.pendingTodayConfirmation
                  ? '已确认「${card.name}」今日继续有效。'
                  : '已点亮「${card.name}」。',
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
      _syncInBackground();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已熄灭「${card.name}」。')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      _busyCardIds.remove(card.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openFailureHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationalFocusFailureHistoryPage(
          repository: widget.repository,
          displayTimeZoneId: _displayTimeZoneId,
        ),
      ),
    );
  }

  Future<void> _openNodeActions({
    required NationalFocusCard card,
    required bool lightBlocked,
    required String? cascadeSourceLabel,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
          ),
          child: _NodeActionsSheet(
            card: card,
            lightBlocked: lightBlocked,
            cascadeSourceLabel: cascadeSourceLabel,
            onAction: (action) async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;
              switch (action) {
                case _NodeAction.light:
                  await _lightCard(card);
                case _NodeAction.strengthening:
                  await _openStrengtheningManager(
                    context: context,
                    repository: widget.repository,
                    cardId: card.id,
                  );
                case _NodeAction.details:
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => _NationalFocusCardDetailPage(
                        repository: widget.repository,
                        card: card,
                        lightBlocked: lightBlocked,
                        cascadeSourceLabel: cascadeSourceLabel,
                      ),
                    ),
                  );
                case _NodeAction.addChild:
                  await _openLibrary(parentId: card.id);
                case _NodeAction.relocate:
                  _beginPlacement(card);
                case _NodeAction.extinguish:
                  await _extinguishCard(card);
                case _NodeAction.library:
                  await _moveBranchToLibrary(card);
              }
            },
          ),
        ),
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

  Future<void> _openLibrary({String? parentId}) async {
    final card = await Navigator.of(context).push<NationalFocusCard>(
      MaterialPageRoute<NationalFocusCard>(
        builder: (_) => NationalFocusCardLibraryPage(
          repository: widget.repository,
          selectCreatedCard: parentId != null,
        ),
      ),
    );
    if (!mounted || card == null) return;
    if (parentId != null) {
      await _placeCard(card, parentId);
      return;
    }
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
    await _placeCard(card, parentId);
  }

  Future<void> _placeCard(NationalFocusCard card, String? parentId) async {
    setState(() => _error = null);
    try {
      await widget.repository.placeCard(cardId: card.id, parentId: parentId);
      final placedCard = await widget.repository.getCard(card.id);
      _syncInBackground();
      if (!mounted) return;
      setState(() => _placementCard = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${parentId == null ? '已放到顶层' : '已放置到所选父节点下'}；'
            '${switch (placedCard.state) {
              NationalFocusCardState.extinguished => '请手动点亮。',
              NationalFocusCardState.pendingTodayConfirmation => '请确认。',
              NationalFocusCardState.lit => '当前已点亮。',
            }}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _moveBranchToLibrary(NationalFocusCard card) async {
    if (_busyCardIds.contains(card.id)) return;
    late final int descendantCount;
    try {
      final treeCards = await widget.repository.getTreeCards();
      final childrenByParent = <String, List<NationalFocusCard>>{};
      for (final treeCard in treeCards) {
        final parentId = treeCard.parentId;
        if (parentId != null) {
          childrenByParent.putIfAbsent(parentId, () => []).add(treeCard);
        }
      }
      descendantCount = _descendantsOf(card.id, childrenByParent).length;
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移入卡片库？'),
        content: Text(
          descendantCount == 0
              ? '「${card.name}」将移入卡片库。'
              : '「${card.name}」及 $descendantCount 张后代卡片将一起移入卡片库并解除父子关系。之后需要逐张重新放置和点亮。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移入卡片库'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_busyCardIds.add(card.id)) return;

    setState(() => _error = null);
    try {
      await widget.repository.moveCardToLibrary(card.id);
      _syncInBackground();
      if (mounted) {
        final message = descendantCount == 0
            ? '已将「${card.name}」移入卡片库。'
            : '已将「${card.name}」和 $descendantCount 张后代卡片移入卡片库。';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      _busyCardIds.remove(card.id);
      if (mounted) setState(() {});
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
            Expanded(
              child: CustomScrollView(
                key: const PageStorageKey<String>('national-focus-tree'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _TreePageHeader(
                          pendingCount: pendingCount,
                          confirming: _confirming,
                          onConfirm: _placementCard == null
                              ? _confirmToday
                              : null,
                          onLibrary: _placementCard == null
                              ? () => _openLibrary()
                              : null,
                          nextCheckpoint: _formatCheckpoint(
                            _now,
                            _displayTimeZoneId,
                          ),
                          displayTimeZoneId: _displayTimeZoneId,
                          onOpenHistory: _openFailureHistory,
                          detailed: _detailed,
                          onViewSelected: _placementCard == null
                              ? (value) => setState(() => _detailed = value)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: NationalFocusReviewPrompt(
                            repository: widget.repository,
                          ),
                        ),
                        if (_placementCard case final card?)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                            child: _PlacementBanner(
                              card: card,
                              onCancel: _cancelPlacement,
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: _InlineError(_error!),
                          ),
                      ],
                    ),
                  ),
                  if (_placementCard != null)
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
                          title: '还没有国策',
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
                      sliver: SliverToBoxAdapter(
                        child: _TreeCanvas(
                          treeWidth: roots.fold<double>(
                            0,
                            (width, root) =>
                                width +
                                _branchWidth(
                                  root,
                                  childrenByParent,
                                  _treeNodeWidth,
                                ),
                          ),
                          treeHeight:
                              _treeDepth(roots, childrenByParent) *
                              (_nodeHeight + 36),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                        ),
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
    final reviewBlocked = card.hasPendingReview;
    final selecting = _placementCard != null;
    final branch = _NationalFocusTreeNode(
      card: card,
      path: path,
      detailed: _detailed,
      selecting: selecting,
      blocked: isBlocked || reviewBlocked,
      onSelect: selecting && !isBlocked && !reviewBlocked
          ? () => _placeAt(card.id)
          : null,
      onOpen: selecting
          ? null
          : () => _openNodeActions(
              card: card,
              lightBlocked: hasExtinguishedAncestor,
              cascadeSourceLabel: card.cascadeSourceCardId == null
                  ? null
                  : cardsById[card.cascadeSourceCardId]?.name ?? '父节点',
            ),
    );
    final nodeWidth = _treeNodeWidth;
    final childWidths = [
      for (final child in children)
        _branchWidth(child, childrenByParent, nodeWidth),
    ];
    final width = _branchWidth(card, childrenByParent, nodeWidth);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            width: nodeWidth,
            height: _nodeHeight,
            child: KeyedSubtree(
              key: ValueKey('national-focus-node-${card.id}'),
              child: branch,
            ),
          ),
          if (children.isNotEmpty) ...[
            Builder(
              builder: (context) => CustomPaint(
                size: Size(width, 36),
                painter: _BranchConnectorPainter(
                  childWidths: childWidths,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  strokeWidth: math.max(2, 1.25 / _TreeCanvasScale.of(context)),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    hasExtinguishedAncestor: targetBranchIsExtinguished,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  double get _treeNodeWidth {
    return _detailed ? 210 : 148;
  }

  double get _nodeHeight =>
      (_detailed ? 124.0 : 100.0) * MediaQuery.textScalerOf(context).scale(1);

  int _treeDepth(
    List<NationalFocusCard> roots,
    Map<String, List<NationalFocusCard>> childrenByParent,
  ) {
    int depth(NationalFocusCard card) =>
        1 + (childrenByParent[card.id]?.map(depth).fold<int>(0, math.max) ?? 0);
    return roots.map(depth).fold<int>(0, math.max);
  }

  double _branchWidth(
    NationalFocusCard card,
    Map<String, List<NationalFocusCard>> childrenByParent,
    double nodeWidth,
  ) {
    final children = childrenByParent[card.id] ?? const [];
    return children.isEmpty
        ? nodeWidth + 16
        : children.fold<double>(
            0,
            (width, child) =>
                width + _branchWidth(child, childrenByParent, nodeWidth),
          );
  }
}

class _TreeCanvasScale extends InheritedWidget {
  const _TreeCanvasScale({required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TreeCanvasScale>()?.scale ??
      1;

  @override
  bool updateShouldNotify(_TreeCanvasScale oldWidget) =>
      oldWidget.scale != scale;
}

/// Touch drags stay in the surrounding scroll view until a second finger
/// joins. Mouse drags can claim the canvas with one pointer.
class _CanvasScaleRecognizer extends ScaleGestureRecognizer {
  final Set<int> _touchPointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touchPointers.add(event.pointer);
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent && _touchPointers.length >= 2) {
      super.resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touchPointers.remove(event.pointer);
    }
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted &&
        _touchPointers.isNotEmpty &&
        pointerCount < 2) {
      return;
    }
    super.resolve(disposition);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _touchPointers.clear();
  }
}

class _TreeCanvas extends StatefulWidget {
  const _TreeCanvas({
    required this.treeWidth,
    required this.treeHeight,
    required this.child,
  });

  final double treeWidth;
  final double treeHeight;
  final Widget child;

  @override
  State<_TreeCanvas> createState() => _TreeCanvasState();
}

class _TreeCanvasState extends State<_TreeCanvas> {
  final GlobalKey _gestureKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  double _scale = 1;
  double _gestureStartScale = 1;
  Offset _gestureSceneFocal = Offset.zero;
  bool _gestureIsTouch = false;
  Size? _viewport;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_syncScale);
  }

  @override
  void didUpdateWidget(covariant _TreeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.treeWidth != widget.treeWidth ||
        oldWidget.treeHeight != widget.treeHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _viewport != null) _fit(_viewport!);
      });
    }
  }

  void _syncScale() {
    // The canvas only scales in X/Y. Matrix4's max-axis helper includes Z=1,
    // so it reports 100% for every fitted tree below 100%.
    final scale = _transform.value.entry(0, 0).abs();
    _scale = scale;
  }

  @override
  void dispose() {
    _transform.removeListener(_syncScale);
    _transform.dispose();
    super.dispose();
  }

  void _onGestureStart(ScaleStartDetails details) {
    _gestureIsTouch = details.kind == PointerDeviceKind.touch;
    _gestureStartScale = _scale;
    _gestureSceneFocal = _transform.toScene(details.localFocalPoint);
  }

  void _onGestureUpdate(ScaleUpdateDetails details) {
    if (_gestureIsTouch && details.pointerCount < 2) return;
    final viewport = _viewport;
    if (viewport == null) return;
    final next = (_gestureStartScale * details.scale).clamp(
      _minimumScale(viewport),
      3.0,
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        details.localFocalPoint.dx - _gestureSceneFocal.dx * next,
        details.localFocalPoint.dy - _gestureSceneFocal.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, 1, 1);
  }

  void _zoomAt(Offset focal, double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final next = (_scale * factor).clamp(_minimumScale(viewport), 3.0);
    final sceneFocal = _transform.toScene(focal);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        focal.dx - sceneFocal.dx * next,
        focal.dy - sceneFocal.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, 1, 1);
  }

  double _fitScale(Size viewport) => math.min(
    1.0,
    math.min(
      math.max(1, viewport.width - 24) / widget.treeWidth,
      math.max(1, viewport.height - 24) / widget.treeHeight,
    ),
  );

  double _minimumScale(Size viewport) => math.min(0.01, _fitScale(viewport));

  void _fit(Size viewport) {
    _viewport = viewport;
    final scale = _fitScale(viewport);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - widget.treeWidth * scale) / 2,
        (viewport.height - widget.treeHeight * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _scale = scale);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(
        constraints.maxWidth,
        (MediaQuery.sizeOf(context).height * 0.65).clamp(360.0, 720.0),
      );
      if (_viewport != viewport) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(viewport);
        });
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: SizedBox(
          height: viewport.height,
          child: Stack(
            children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is! PointerScrollEvent ||
                      !HardwareKeyboard.instance.isControlPressed) {
                    return;
                  }
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (resolved) {
                      final renderBox = _gestureKey.currentContext
                          ?.findRenderObject();
                      if (renderBox is! RenderBox) return;
                      final focal = renderBox.globalToLocal(resolved.position);
                      _zoomAt(focal, math.exp(-event.scrollDelta.dy / 200));
                    },
                  );
                },
                child: ClipRect(
                  child: RawGestureDetector(
                    key: _gestureKey,
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      _CanvasScaleRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _CanvasScaleRecognizer
                          >(
                            () => _CanvasScaleRecognizer(),
                            (recognizer) => recognizer
                              ..onStart = _onGestureStart
                              ..onUpdate = _onGestureUpdate,
                          ),
                    },
                    child: SizedBox.expand(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            child: ValueListenableBuilder<Matrix4>(
                              valueListenable: _transform,
                              builder: (context, matrix, _) => Transform(
                                key: const ValueKey('national-focus-canvas'),
                                transform: matrix,
                                child: SizedBox(
                                  width: widget.treeWidth,
                                  height: widget.treeHeight,
                                  child: _TreeCanvasScale(
                                    scale: _scale,
                                    child: widget.child,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: IconButton(
                    tooltip: '适应屏幕',
                    onPressed: () => _fit(viewport),
                    icon: const Icon(Icons.fit_screen),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class NationalFocusCardLibraryPage extends StatefulWidget {
  const NationalFocusCardLibraryPage({
    super.key,
    required this.repository,
    this.selectCreatedCard = false,
  });

  final NationalFocusRepository repository;
  final bool selectCreatedCard;

  @override
  State<NationalFocusCardLibraryPage> createState() =>
      _NationalFocusCardLibraryPageState();
}

class _NationalFocusCardLibraryPageState
    extends State<NationalFocusCardLibraryPage> {
  Future<void> _renameCard(NationalFocusCard card) =>
      _renameNationalFocusCard(context, widget.repository, card);

  Future<void> _createCard(BuildContext context) async {
    final created = await Navigator.of(context).push<NationalFocusCard>(
      MaterialPageRoute<NationalFocusCard>(
        builder: (_) =>
            NationalFocusCardEditorPage(repository: widget.repository),
      ),
    );
    if (created != null && context.mounted && widget.selectCreatedCard) {
      Navigator.of(context).pop(created);
    }
  }

  Future<void> _deleteCard(NationalFocusCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除国策卡？'),
        content: const Text('失败历史快照引用的卡片会移入已删除列表，可恢复到卡片库；没有失败快照引用的卡片会永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await widget.repository.deleteCard(card.id);
      _syncNationalFocusInBackground(widget.repository);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == NationalFocusCardDeletion.softDeleted
                ? '历史快照引用这张卡；已移入已删除列表，可恢复。'
                : '没有失败快照引用；已永久删除这张卡。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  Future<void> _restoreCard(NationalFocusCard card) async {
    try {
      await widget.repository.restoreDeletedCard(card.id);
      _syncNationalFocusInBackground(widget.repository);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复到卡片库；树位置和点亮状态需要重新选择。')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('国策卡片库'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '卡片库'),
            Tab(text: '已删除'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _LibraryCardList(
            repository: widget.repository,
            onPlace: (card) => Navigator.of(context).pop(card),
            onDelete: _deleteCard,
            onRename: _renameCard,
            onManageStrengthening: (card) => _openStrengtheningManager(
              context: context,
              repository: widget.repository,
              cardId: card.id,
            ),
          ),
          _DeletedNationalFocusCardList(
            repository: widget.repository,
            onRestore: _restoreCard,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCard(context),
        icon: const Icon(Icons.add),
        label: const Text('新建国策卡'),
      ),
    ),
  );
}

class _LibraryCardList extends StatelessWidget {
  const _LibraryCardList({
    required this.repository,
    required this.onPlace,
    required this.onDelete,
    required this.onRename,
    required this.onManageStrengthening,
  });

  final NationalFocusRepository repository;
  final ValueChanged<NationalFocusCard> onPlace;
  final ValueChanged<NationalFocusCard> onDelete;
  final ValueChanged<NationalFocusCard> onRename;
  final ValueChanged<NationalFocusCard> onManageStrengthening;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<NationalFocusCard>>(
    stream: repository.watchLibraryCards(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _TreeMessage(
          icon: Icons.error_outline,
          title: '无法读取卡片库',
          message: _friendlyError(snapshot.error!),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final cards = snapshot.data!;
      if (cards.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _TreeMessage(
              icon: Icons.library_books_outlined,
              title: '卡片库还是空的',
              message: '新建国策卡，再放入国策树。',
            ),
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _LibraryCard(
              card: cards[index],
              onDetails: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _NationalFocusCardDetailPage(
                    repository: repository,
                    card: cards[index],
                    lightBlocked: false,
                    cascadeSourceLabel: null,
                  ),
                ),
              ),
              onEdit: cards[index].hasPendingReview
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NationalFocusCardEditorPage(
                          repository: repository,
                          card: cards[index],
                        ),
                      ),
                    ),
              onRename: cards[index].hasPendingReview
                  ? null
                  : () => onRename(cards[index]),
              onPlace: cards[index].hasPendingReview
                  ? null
                  : () => onPlace(cards[index]),
              onDelete: cards[index].hasPendingReview
                  ? null
                  : () => onDelete(cards[index]),
              onManageStrengthening: cards[index].hasPendingReview
                  ? null
                  : () => onManageStrengthening(cards[index]),
            ),
          ),
        ),
      );
    },
  );
}

class _DeletedNationalFocusCardList extends StatelessWidget {
  const _DeletedNationalFocusCardList({
    required this.repository,
    required this.onRestore,
  });

  final NationalFocusRepository repository;
  final ValueChanged<NationalFocusCard> onRestore;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<NationalFocusCard>>(
    stream: repository.watchDeletedCards(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _TreeMessage(
          icon: Icons.error_outline,
          title: '无法读取已删除卡片',
          message: _friendlyError(snapshot.error!),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final cards = snapshot.data!;
      if (cards.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _TreeMessage(
              icon: Icons.delete_outline,
              title: '没有可恢复的卡片',
              message: '有失败历史快照引用的卡片会保留在这里，可恢复到卡片库。',
            ),
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _DeletedLibraryCard(
              card: cards[index],
              onRestore: cards[index].hasPendingReview
                  ? null
                  : () => onRestore(cards[index]),
            ),
          ),
        ),
      );
    },
  );
}

class NationalFocusCardEditorPage extends StatefulWidget {
  const NationalFocusCardEditorPage({
    super.key,
    required this.repository,
    this.card,
  });

  final NationalFocusRepository repository;
  final NationalFocusCard? card;

  @override
  State<NationalFocusCardEditorPage> createState() =>
      _NationalFocusCardEditorPageState();
}

class _NationalFocusCardEditorPageState
    extends State<NationalFocusCardEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _trigger = TextEditingController();
  final _action = TextEditingController();
  final _scope = TextEditingController();
  final _exceptionNotes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    if (card == null) return;
    _name.text = card.name;
    _trigger.text = card.triggerCondition;
    _action.text = card.action;
    _scope.text = card.scope ?? '';
    _exceptionNotes.text = card.exceptionNotes ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
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
      final draft = NationalFocusCardDraft(
        name: _name.text,
        triggerCondition: _trigger.text,
        action: _action.text,
        scope: _scope.text,
        exceptionNotes: _exceptionNotes.text,
      );
      final existing = widget.card;
      final NationalFocusCard card;
      if (existing == null) {
        card = await widget.repository.createCard(draft);
      } else {
        await widget.repository.updateCard(cardId: existing.id, draft: draft);
        card = await widget.repository.getCard(existing.id);
      }
      _syncNationalFocusInBackground(widget.repository);
      if (mounted) Navigator.of(context).pop(card);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.card == null ? '新建国策卡' : '编辑国策卡')),
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
                  widget.card?.activeStrengtheningLevel != null
                      ? '编辑基础要求；已强化的字段仍使用强化要求。'
                      : '写下规则，由你判断是否有效。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '卡片名称'),
                  validator: (value) => _requiredFieldError(value, '卡片名称'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _trigger,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '触发条件（可选）',
                    hintText: '例如：坐到书桌前后',
                    alignLabelWithHint: true,
                  ),
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
            label: Text(
              _busy
                  ? '保存中'
                  : widget.card == null
                  ? '保存到卡片库'
                  : '保存',
            ),
          ),
        ),
      ),
    ),
  );
}

class _NationalFocusReviewNotice extends StatelessWidget {
  const _NationalFocusReviewNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.sync_problem, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '同步操作存在分歧，状态和统计待核对；核对前暂不能修改这张卡。',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.onEdit,
    required this.onDetails,
    required this.card,
    required this.onPlace,
    required this.onDelete,
    required this.onRename,
    required this.onManageStrengthening,
  });

  final NationalFocusCard card;
  final VoidCallback? onPlace;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onEdit;
  final VoidCallback onDetails;
  final VoidCallback? onManageStrengthening;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card.activeStrengtheningLevel != null) ...[
            Text(
              '当前要求 · 强化等级 ${card.activeStrengtheningLevel}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  card.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '卡片操作',
                onSelected: (value) {
                  if (value == 'details') {
                    onDetails();
                  } else if (value == 'edit') {
                    onEdit?.call();
                  } else {
                    onRename?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'details', child: Text('查看详情')),
                  PopupMenuItem(
                    value: 'edit',
                    enabled: onEdit != null,
                    child: const Text('编辑卡片'),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    enabled: onRename != null,
                    child: const Text('修改名称'),
                  ),
                ],
              ),
            ],
          ),
          _FieldText(label: '触发条件', value: card.effectiveTriggerCondition),
          const SizedBox(height: 12),
          _FieldText(label: '行动', value: card.effectiveAction),
          if (card.scope != null) ...[
            const SizedBox(height: 12),
            _FieldText(label: '适用范围', value: card.scope!),
          ],
          if (card.exceptionNotes != null) ...[
            const SizedBox(height: 12),
            _FieldText(label: '例外说明', value: card.exceptionNotes!),
          ],
          if (card.hasPendingReview) ...[
            const SizedBox(height: 12),
            const _NationalFocusReviewNotice(),
          ],
          const SizedBox(height: 12),
          _NationalFocusRecordSummary(card: card),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除'),
              ),
              OutlinedButton.icon(
                onPressed: onManageStrengthening,
                icon: const Icon(Icons.tune),
                label: Text(
                  '强化等级 ${card.strengtheningLevels.length}/$maxNationalFocusStrengtheningLevels',
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onPlace,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('放入国策树'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DeletedLibraryCard extends StatelessWidget {
  const _DeletedLibraryCard({required this.card, required this.onRestore});

  final NationalFocusCard card;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.name, style: Theme.of(context).textTheme.titleMedium),
          _FieldText(label: '触发条件', value: card.effectiveTriggerCondition),
          const SizedBox(height: 12),
          _FieldText(label: '行动', value: card.effectiveAction),
          const SizedBox(height: 12),
          _NationalFocusRecordSummary(card: card),
          if (card.hasPendingReview) ...[
            const SizedBox(height: 12),
            const _NationalFocusReviewNotice(),
          ],
          const SizedBox(height: 8),
          Text(
            '恢复后会回到卡片库；树位置和点亮状态需要重新选择。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: onRestore,
              icon: const Icon(Icons.restore),
              label: const Text('恢复到卡片库'),
            ),
          ),
        ],
      ),
    ),
  );
}

enum _NodeAction {
  light,
  strengthening,
  details,
  addChild,
  relocate,
  extinguish,
  library,
}

class _TreePageHeader extends StatelessWidget {
  const _TreePageHeader({
    required this.detailed,
    required this.onViewSelected,
    required this.pendingCount,
    required this.confirming,
    required this.onConfirm,
    required this.onLibrary,
    required this.nextCheckpoint,
    required this.displayTimeZoneId,
    required this.onOpenHistory,
  });
  final bool detailed;
  final ValueChanged<bool>? onViewSelected;
  final int pendingCount;
  final bool confirming;
  final VoidCallback? onConfirm;
  final VoidCallback? onLibrary;
  final String nextCheckpoint;
  final String displayTimeZoneId;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            Text('国策树', style: Theme.of(context).textTheme.headlineSmall),
            TextButton.icon(
              onPressed: pendingCount == 0 || confirming ? null : onConfirm,
              icon: const Icon(Icons.done_all),
              label: Text('全部确认 ($pendingCount)'),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            PopupMenuButton<bool>(
              enabled: onViewSelected != null,
              onSelected: onViewSelected,
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('简洁视图')),
                PopupMenuItem(value: true, child: Text('详细视图')),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(detailed ? '详细视图' : '简洁视图'),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            ),
            Tooltip(
              message: '卡片库',
              child: TextButton.icon(
                onPressed: onLibrary,
                icon: const Icon(Icons.library_books_outlined),
                label: const Text('卡片库'),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'records') {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('检查点与失败记录')),
                        body: ListView(
                          children: [
                            ListTile(
                              title: Text(nextCheckpoint),
                              subtitle: Text(
                                '固定规则为北京时间 04:00；显示时区 $displayTimeZoneId 不会移动结算边界。',
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Icons.history),
                              title: const Text('查看失败记录'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: onOpenHistory,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'records', child: Text('检查点与失败记录')),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _NodeActionsSheet extends StatelessWidget {
  const _NodeActionsSheet({
    required this.card,
    required this.lightBlocked,
    required this.cascadeSourceLabel,
    required this.onAction,
  });
  final NationalFocusCard card;
  final bool lightBlocked;
  final String? cascadeSourceLabel;
  final ValueChanged<_NodeAction> onAction;

  @override
  Widget build(BuildContext context) {
    final reviewBlocked = card.hasPendingReview;
    Widget action(
      _NodeAction kind,
      IconData icon,
      String title, {
      bool enabled = true,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      enabled: enabled,
      onTap: enabled ? () => onAction(kind) : null,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.name, style: Theme.of(context).textTheme.headlineSmall),
          if (reviewBlocked) const _NationalFocusReviewNotice(),
          const SizedBox(height: 12),
          Text(
            card.effectiveAction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(height: 16),

          action(
            card.state == NationalFocusCardState.lit
                ? _NodeAction.extinguish
                : _NodeAction.light,
            card.state == NationalFocusCardState.lit
                ? Icons.lightbulb_outline
                : Icons.lightbulb,
            switch (card.state) {
              NationalFocusCardState.lit => '熄灭',
              NationalFocusCardState.pendingTodayConfirmation => '确认',
              NationalFocusCardState.extinguished => '点亮',
            },
            enabled:
                !reviewBlocked &&
                (card.state == NationalFocusCardState.lit || !lightBlocked),
          ),
          if (reviewBlocked) const Text('请先完成核对后再操作。'),
          if (!reviewBlocked &&
              lightBlocked &&
              card.state != NationalFocusCardState.lit)
            const Text('请先点亮父节点。'),
          action(_NodeAction.details, Icons.article_outlined, '查看详情'),
          action(
            _NodeAction.strengthening,
            Icons.tune,
            '管理强化要求',
            enabled: !reviewBlocked,
          ),
          action(
            _NodeAction.addChild,
            Icons.add_circle_outline,
            '添加子节点',
            enabled: !reviewBlocked,
          ),
          action(
            _NodeAction.relocate,
            Icons.drive_file_move_outline,
            '调整树中位置',
            enabled: !reviewBlocked,
          ),
          if (card.state == NationalFocusCardState.pendingTodayConfirmation)
            action(
              _NodeAction.extinguish,
              Icons.lightbulb_outline,
              '熄灭',
              enabled: !reviewBlocked,
            ),
          action(
            _NodeAction.library,
            Icons.library_add_outlined,
            '移入卡片库',
            enabled: !reviewBlocked,
          ),
        ],
      ),
    );
  }
}

class _NationalFocusCardDetailPage extends StatelessWidget {
  const _NationalFocusCardDetailPage({
    required this.repository,
    required this.card,
    required this.lightBlocked,
    required this.cascadeSourceLabel,
  });
  final NationalFocusRepository repository;
  final NationalFocusCard card;
  final bool lightBlocked;
  final String? cascadeSourceLabel;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<NationalFocusCard>>(
    stream: card.isInTree
        ? repository.watchTreeCards()
        : repository.watchLibraryCards(),
    builder: (context, snapshot) {
      final card =
          snapshot.data?.where((item) => item.id == this.card.id).firstOrNull ??
          this.card;
      return Scaffold(
        appBar: AppBar(
          title: const Text('国策卡详情'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '卡片操作',
              onSelected: (value) async {
                if (value == 'edit') {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NationalFocusCardEditorPage(
                        repository: repository,
                        card: card,
                      ),
                    ),
                  );
                } else {
                  await _renameNationalFocusCard(context, repository, card);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  enabled: !card.hasPendingReview,
                  child: const Text('编辑卡片'),
                ),
                PopupMenuItem(
                  value: 'rename',
                  enabled: !card.hasPendingReview,
                  child: const Text('修改名称'),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(card.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              card.state.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            _FieldText(label: '触发条件', value: card.effectiveTriggerCondition),
            const SizedBox(height: 20),
            _FieldText(label: '行动', value: card.effectiveAction),
            if (card.scope != null) ...[
              const SizedBox(height: 20),
              _FieldText(label: '适用范围', value: card.scope!),
            ],
            if (card.exceptionNotes != null) ...[
              const SizedBox(height: 20),
              _FieldText(label: '例外说明', value: card.exceptionNotes!),
            ],
            const SizedBox(height: 24),
            Text('强化要求', style: Theme.of(context).textTheme.titleMedium),
            Text(
              card.activeStrengtheningLevel == null
                  ? '当前使用基础要求'
                  : '当前要求 · 强化等级 ${card.activeStrengtheningLevel}',
            ),
            const SizedBox(height: 24),
            Text('记录', style: Theme.of(context).textTheme.titleMedium),
            _NationalFocusRecordSummary(card: card),
            if (cascadeSourceLabel != null)
              _CascadeStatusNote(
                sourceLabel: cascadeSourceLabel!,
                lightBlocked: lightBlocked,
              ),
          ],
        ),
      );
    },
  );
}

class _NationalFocusTreeNode extends StatelessWidget {
  const _NationalFocusTreeNode({
    required this.card,
    required this.path,
    required this.detailed,
    required this.selecting,
    required this.blocked,
    required this.onSelect,
    required this.onOpen,
  });
  final NationalFocusCard card;
  final String path;
  final bool detailed;
  final bool selecting;
  final bool blocked;
  final VoidCallback? onSelect;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusIcon = card.hasPendingReview
        ? Icons.sync_problem_outlined
        : switch (card.state) {
            NationalFocusCardState.lit => Icons.lightbulb,
            NationalFocusCardState.pendingTodayConfirmation =>
              Icons.hourglass_top,
            NationalFocusCardState.extinguished => Icons.lightbulb_outline,
          };
    final status = card.hasPendingReview
        ? '待核对，${card.state.label}'
        : card.state.label;
    final iconBackground = card.hasPendingReview
        ? colors.errorContainer
        : switch (card.state) {
            NationalFocusCardState.lit => colors.primaryContainer,
            NationalFocusCardState.pendingTodayConfirmation =>
              colors.tertiaryContainer,
            NationalFocusCardState.extinguished =>
              colors.surfaceContainerHighest,
          };
    final content = InkWell(
      onTap: selecting ? onSelect : onOpen,
      borderRadius: BorderRadius.circular(12),
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
              child: Icon(statusIcon, size: 24, color: colors.onSurface),
            ),
            const SizedBox(height: 3),
            Text(
              card.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (detailed) ...[
              const SizedBox(height: 3),
              Text(
                card.effectiveAction,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? 2
                    : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: selecting ? !blocked : true,
      label:
          '节点 $path，${card.name}，$status${selecting
              ? blocked
                    ? card.hasPendingReview
                          ? '，不能选作父节点：待核对状态需先完成核对'
                          : '，不能选作父节点：此节点当前无效'
                    : '，选择为父节点'
              : '，打开操作'}',
      child: detailed
          ? Card(
              clipBehavior: Clip.antiAlias,
              color: selecting && !blocked
                  ? colors.secondaryContainer
                  : colors.surfaceContainerLow,
              child: content,
            )
          : Material(color: Colors.transparent, child: content),
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
    title: const Text('熄灭这个节点？'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('「${widget.card.name}」会在下一检查点结算；此前重新点亮可保留当前连续记录。'),
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

class NationalFocusFailureHistoryPage extends StatefulWidget {
  const NationalFocusFailureHistoryPage({
    super.key,
    required this.repository,
    required this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final String displayTimeZoneId;

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
      _syncNationalFocusInBackground(widget.repository);
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('国策失败记录')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
        return first.effectiveTriggerCondition.compareTo(
          second.effectiveTriggerCondition,
        );
      });
    return Card(
      child: Column(
        children: [
          ExpansionTile(
            title: Text(
              '$checkpointLabel · ${failures.length} 个节点'
              '${failures.any((failure) => failure.isPendingReview) ? ' · 待核对' : ''}',
            ),
            subtitle: Text(
              '${representative.cause.label}'
              '${representative.isPendingReview ? ' · 此记录尚未裁定' : ''}',
            ),
            children: [
              for (final failure in failures)
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(_snapshotName(failure)),
                  subtitle: Text(
                    '${failure.cause.label} · '
                    '${failure.failureReason ?? '原因未填写'}'
                    '${failure.isPendingReview ? ' · 待核对' : ''}',
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
                          '${card.isInTree ? '' : '卡片库内 · '}${card.name} · ${card.effectiveTriggerCondition}'
                          '${card.activeStrengtheningLevel == null ? '' : ' · 强化等级 ${card.activeStrengtheningLevel}'} · '
                          '${card.effectiveAction} · ${card.state.label} · '
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
          .map((card) => card.name)
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
    return ' · 因「${source?.name ?? '父节点'}」连带熄灭';
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
              '为「${card.name}」选择位置：点顶层或一个节点。',
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
      SelectableText(
        value.isEmpty ? '未设置' : value,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
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

class _BranchConnectorPainter extends CustomPainter {
  const _BranchConnectorPainter({
    required this.childWidths,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> childWidths;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final centers = <double>[];
    var offset = 0.0;
    for (final width in childWidths) {
      centers.add(offset + width / 2);
      offset += width;
    }
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, middle),
      paint,
    );
    canvas.drawLine(
      Offset(centers.first, middle),
      Offset(centers.last, middle),
      paint,
    );
    for (final center in centers) {
      canvas.drawLine(
        Offset(center, middle),
        Offset(center, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BranchConnectorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      !listEquals(oldDelegate.childWidths, childWidths);
}

Future<void> _renameNationalFocusCard(
  BuildContext context,
  NationalFocusRepository repository,
  NationalFocusCard card,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameCardDialog(name: card.name),
  );
  if (name == null || !context.mounted) return;
  try {
    await repository.renameCard(cardId: card.id, name: name);
    _syncNationalFocusInBackground(repository);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }
}

class _RenameCardDialog extends StatefulWidget {
  const _RenameCardDialog({required this.name});
  final String name;
  @override
  State<_RenameCardDialog> createState() => _RenameCardDialogState();
}

class _RenameCardDialogState extends State<_RenameCardDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.name,
  );
  final _formKey = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改卡片名称'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '卡片名称'),
        validator: (value) => _requiredFieldError(value, '卡片名称'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.of(context).pop(_controller.text.trim());
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
