import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../focus/focus_time_zones.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_status_colors.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_page_header.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_library_page.dart';
import 'national_focus_failure_pages.dart';
import 'national_focus_models.dart';
import 'national_focus_reconciliation_page.dart';
import 'national_focus_repository.dart';
import 'national_focus_shared_widgets.dart';
import 'national_focus_view_preferences.dart';

export 'national_focus_library_page.dart';
export 'national_focus_failure_pages.dart';

/// The National Focus destination body. The app shell owns the app bar and
/// bottom navigation; this widget owns the tree canvas and its local flows.
class NationalFocusTreePage extends StatefulWidget {
  const NationalFocusTreePage({
    super.key,
    required this.repository,
    this.userId,
    this.viewPreferences = const NationalFocusViewPreferences(),
    this.onOpenAiAnalysis,
    this.onTodayConfirmed,
    this.onNotificationCapabilityUse,
    this.displayTimeZoneLoader,
    this.now,
  });

  final NationalFocusRepository repository;

  /// 今日确认成功后回调一次。批量确认在整批（含逐项例外）结束时只回调一次；
  /// 普通编辑、点亮、熄灭不触发。
  final Future<void> Function()? onTodayConfirmed;
  final String? userId;
  final NationalFocusViewPreferences viewPreferences;
  final VoidCallback? onOpenAiAnalysis;

  /// Called on the first user action that relies on reminder notifications.
  final VoidCallback? onNotificationCapabilityUse;
  final Future<String?> Function()? displayTimeZoneLoader;
  final DateTime Function()? now;

  @override
  State<NationalFocusTreePage> createState() => _NationalFocusTreePageState();
}

class _NationalFocusTreePageState extends State<NationalFocusTreePage> {
  bool _detailed = false;
  bool _viewBusy = false;
  bool _viewReadFailed = false;
  bool _viewSaveFailed = false;
  int _viewRequest = 0;
  NationalFocusCard? _placementCard;
  String? _error;
  String _displayTimeZoneId = 'Etc/UTC';
  late DateTime _now;
  final Set<String> _busyCardIds = {};
  bool _confirming = false;
  bool _todayBatchOpen = false;
  bool _todayBatchConfirmed = false;
  Timer? _settlementTimer;

  @override
  void initState() {
    super.initState();
    _now = (widget.now?.call() ?? DateTime.now()).toUtc();
    _loadDisplayTimeZone();
    _loadView();
    _settlementTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshCheckpointState(),
    );
  }

  @override
  void didUpdateWidget(covariant NationalFocusTreePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.viewPreferences != widget.viewPreferences) {
      _loadView();
    }
  }

  Future<void> _loadView() async {
    final request = ++_viewRequest;
    final userId = widget.userId;
    setState(() {
      _detailed = false;
      _viewReadFailed = false;
      _viewSaveFailed = false;
      _viewBusy = userId != null;
    });
    if (userId == null) return;
    try {
      final detailed = await widget.viewPreferences.load(userId);
      if (mounted && request == _viewRequest) {
        setState(() => _detailed = detailed);
      }
    } catch (_) {
      if (mounted && request == _viewRequest) {
        setState(() => _viewReadFailed = true);
      }
    } finally {
      if (mounted && request == _viewRequest) {
        setState(() => _viewBusy = false);
      }
    }
  }

  Future<void> _saveView(bool detailed) async {
    if (_viewBusy) return;
    final request = ++_viewRequest;
    final userId = widget.userId;
    setState(() {
      _detailed = detailed;
      _viewReadFailed = false;
      _viewSaveFailed = false;
      _viewBusy = userId != null;
    });
    if (userId == null) return;
    try {
      await widget.viewPreferences.save(userId, detailed);
    } catch (_) {
      if (mounted && request == _viewRequest) {
        setState(() => _viewSaveFailed = true);
      }
    } finally {
      if (mounted && request == _viewRequest) {
        setState(() => _viewBusy = false);
      }
    }
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
    syncNationalFocusInBackground(widget.repository);
  }

  Future<void> _confirmToday() async {
    if (_confirming) return;
    // Confirming is a real reminder-related use, so ask once if still needed.
    widget.onNotificationCapabilityUse?.call();
    setState(() {
      _confirming = true;
      _error = null;
    });
    final windowEnd = _confirmationWindowEnd();
    _todayBatchOpen = true;
    _todayBatchConfirmed = false;
    try {
      final count = await widget.repository.confirmToday(
        expectedConfirmationCheckpoint: windowEnd,
      );
      if (count > 0) _recordTodayConfirmation();
      _syncInBackground();
      if (count > 0 && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已确认 $count 个国策节点今日继续有效。')));
      }
      final handledWithException = await _confirmExceptionPendingCards(
        windowEnd,
      );
      if (!mounted) return;
      final remaining = await _loadedExceptionPendingCards();
      if (!mounted) return;
      if (count == 0 && handledWithException == 0 && remaining.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前没有待确认节点。')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
    } finally {
      _todayBatchOpen = false;
      // 部分成功（含逐项例外被关闭）也要为已成功的变更排一次上传。
      if (_todayBatchConfirmed) {
        _todayBatchConfirmed = false;
        _queueTodayConfirmationUpload();
      }
      if (mounted) setState(() => _confirming = false);
    }
  }

  /// 记录一次成功的今日确认；批量期间只记标记，结束后统一回调一次。
  void _recordTodayConfirmation() {
    if (_todayBatchOpen) {
      _todayBatchConfirmed = true;
      return;
    }
    _queueTodayConfirmationUpload();
  }

  void _queueTodayConfirmationUpload() {
    final callback = widget.onTodayConfirmed;
    if (callback == null) return;
    // 上传由协调器排队与重试，界面不为网络等待阻塞。
    unawaited(callback().catchError((Object _) {}));
  }

  /// Walks pending nodes that carry exception or precedent notes one by one.
  /// Closing the panel leaves the remaining nodes pending.
  Future<int> _confirmExceptionPendingCards(DateTime windowEnd) async {
    var handled = 0;
    while (mounted && _isSameConfirmationWindow(windowEnd)) {
      final pending = await _loadedExceptionPendingCards();
      if (!mounted) break;
      if (pending.isEmpty) break;
      if (!_isSameConfirmationWindow(windowEnd)) break;
      final card = pending.first;
      final action = await showDialog<_ExceptionConfirmationAction>(
        context: context,
        builder: (_) =>
            _ExceptionConfirmationDialog(card: card, remaining: pending.length),
      );
      if (!mounted ||
          action == null ||
          action == _ExceptionConfirmationAction.close) {
        break;
      }
      final stateBefore = card.state;
      if (action == _ExceptionConfirmationAction.confirm) {
        await _lightCard(card, expectedCheckpoint: windowEnd);
      } else {
        if (!_isSameConfirmationWindow(windowEnd)) break;
        await _extinguishCard(card, expectedCheckpoint: windowEnd);
      }
      if (!mounted) break;
      final refreshed = await widget.repository.getTreeCards();
      final updated = refreshed.where((item) => item.id == card.id).firstOrNull;
      if (updated == null || updated.state == stateBefore) break;
      handled++;
      _syncInBackground();
    }
    return handled;
  }

  DateTime _confirmationWindowEnd() => nextNationalFocusCheckpoint(
    (widget.now?.call() ?? DateTime.now()).toUtc(),
  );

  bool _isSameConfirmationWindow(DateTime windowEnd) =>
      _confirmationWindowEnd().isAtSameMomentAs(windowEnd);

  Future<List<NationalFocusCard>> _loadedExceptionPendingCards() async {
    final cards = await widget.repository.getTreeCards();
    final byId = {for (final card in cards) card.id: card};
    final pending =
        [
          for (final card in cards)
            if (card.state == NationalFocusCardState.pendingTodayConfirmation &&
                !card.hasPendingReview &&
                (card.exceptionNotes?.trim().isNotEmpty ?? false) &&
                !_hasExtinguishedAncestor(card, byId))
              card,
        ]..sort((first, second) {
          final byCreated = first.createdAt.compareTo(second.createdAt);
          return byCreated != 0 ? byCreated : first.id.compareTo(second.id);
        });
    return pending;
  }

  bool _hasExtinguishedAncestor(
    NationalFocusCard card,
    Map<String, NationalFocusCard> cardsById,
  ) {
    var ancestorId = card.parentId;
    final visited = <String>{card.id};
    while (ancestorId != null && visited.add(ancestorId)) {
      final ancestor = cardsById[ancestorId];
      if (ancestor == null) return false;
      if (ancestor.state == NationalFocusCardState.extinguished) return true;
      ancestorId = ancestor.parentId;
    }
    return false;
  }

  Future<void> _lightCard(
    NationalFocusCard card, {
    DateTime? expectedCheckpoint,
  }) async {
    if (!_busyCardIds.add(card.id)) return;
    setState(() => _error = null);
    try {
      await widget.repository.lightCard(
        card.id,
        expectedConfirmationCheckpoint: expectedCheckpoint,
      );
      if (card.state == NationalFocusCardState.pendingTodayConfirmation) {
        _recordTodayConfirmation();
      }
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
      if (mounted) setState(() => _error = formatUserError(error));
    } finally {
      _busyCardIds.remove(card.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _extinguishCard(
    NationalFocusCard card, {
    DateTime? expectedCheckpoint,
  }) async {
    late final List<NationalFocusCard> treeCards;
    try {
      treeCards = await widget.repository.getTreeCards();
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
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
    if (reason == null || !mounted) return;
    if (expectedCheckpoint != null &&
        !_isSameConfirmationWindow(expectedCheckpoint)) {
      // The reason dialog stayed open across the checkpoint. Settle and leave
      // the old batch rather than extinguishing new-day state.
      try {
        await widget.repository.settleDueCheckpoints();
      } catch (_) {
        // The next read still reflects the latest readable tree.
      }
      _syncInBackground();
      if (mounted) setState(() {});
      return;
    }
    if (!_busyCardIds.add(card.id)) return;

    setState(() => _error = null);
    try {
      await widget.repository.extinguishCard(
        cardId: card.id,
        failureReason: reason,
        expectedConfirmationCheckpoint: expectedCheckpoint,
      );
      _syncInBackground();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已熄灭「${card.name}」。')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
    } finally {
      _busyCardIds.remove(card.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openFailureRecords() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationalFocusFailureHistoryPage(
          repository: widget.repository,
          displayTimeZoneId: _displayTimeZoneId,
          nextCheckpointAt: nextNationalFocusCheckpoint(_now),
        ),
      ),
    );
  }

  Future<void> _openNodeActions({
    required NationalFocusCard card,
    required bool lightBlocked,
    required String? cascadeSourceLabel,
  }) async {
    final windowEnd = _confirmationWindowEnd();
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
                  await _lightCard(
                    card,
                    expectedCheckpoint:
                        card.state ==
                            NationalFocusCardState.pendingTodayConfirmation
                        ? windowEnd
                        : null,
                  );
                case _NodeAction.details:
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => NationalFocusCardDetailPage(
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
                  await _extinguishCard(card, expectedCheckpoint: windowEnd);
                case _NodeAction.library:
                  await _moveBranchToLibrary(card);
              }
            },
          ),
        ),
      ),
    );
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
      if (mounted) setState(() => _error = formatUserError(error));
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
      if (mounted) setState(() => _error = formatUserError(error));
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
      if (mounted) setState(() => _error = formatUserError(error));
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
          return NationalFocusTreeMessage(
            icon: Icons.error_outline,
            title: '无法读取国策树',
            message: formatUserError(snapshot.error!),
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
                        // 画布保留全宽，页头与其它目的地共用 960 内容列：
                        // 宽屏切换目的地时标题左边距不跳。
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: PactaSpacing.maxContentWidth,
                            ),
                            child: _TreePageHeader(
                              pendingCount: pendingCount,
                              confirming: _confirming,
                              onConfirm: _placementCard == null
                                  ? _confirmToday
                                  : null,
                              onLibrary: _placementCard == null
                                  ? () => _openLibrary()
                                  : null,
                              onOpenFailureRecords: _openFailureRecords,
                              onOpenAiAnalysis: _placementCard == null
                                  ? widget.onOpenAiAnalysis
                                  : null,
                              detailed: _detailed,
                              onViewSelected:
                                  _placementCard == null && !_viewBusy
                                  ? _saveView
                                  : null,
                            ),
                          ),
                        ),
                        if (_viewBusy)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Text('正在更新视图…'),
                          ),
                        if (_viewReadFailed || _viewSaveFailed)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: NationalFocusInlineError(
                                    _viewReadFailed
                                        ? '视图偏好读取失败，暂用简洁视图。'
                                        : '视图偏好未保存，请重试。',
                                  ),
                                ),
                                TextButton(
                                  onPressed: _viewBusy
                                      ? null
                                      : _viewReadFailed
                                      ? _loadView
                                      : () => _saveView(_detailed),
                                  child: Text(
                                    _viewReadFailed ? '重试读取' : '重试保存',
                                  ),
                                ),
                              ],
                            ),
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
                            child: NationalFocusInlineError(_error!),
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
                        child: NationalFocusTreeMessage(
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
                        child: NationalFocusTreeCanvas(
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
                        child: NationalFocusTreeMessage(
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
                painter: NationalFocusBranchConnectorPainter(
                  childWidths: childWidths,
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

enum _NodeAction { light, details, addChild, relocate, extinguish, library }

class _TreePageHeader extends StatelessWidget {
  const _TreePageHeader({
    required this.detailed,
    required this.onViewSelected,
    required this.pendingCount,
    required this.confirming,
    required this.onConfirm,
    required this.onLibrary,
    required this.onOpenFailureRecords,
    required this.onOpenAiAnalysis,
  });
  final bool detailed;
  final ValueChanged<bool>? onViewSelected;
  final int pendingCount;
  final bool confirming;
  final VoidCallback? onConfirm;
  final VoidCallback? onLibrary;
  final VoidCallback onOpenFailureRecords;
  final VoidCallback? onOpenAiAnalysis;

  @override
  Widget build(BuildContext context) {
    final gutter = PactaSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        PactaSpacing.lg,
        gutter,
        PactaSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PactaPageHeader(
            title: '国策树',
            trailing: TextButton.icon(
              onPressed: pendingCount == 0 || confirming ? null : onConfirm,
              icon: const Icon(Icons.done_all),
              label: Text('全部确认 ($pendingCount)'),
            ),
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
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
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
                  if (value == 'ai') {
                    onOpenAiAnalysis?.call();
                  } else if (value == 'records') {
                    onOpenFailureRecords();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'records', child: Text('失败记录')),
                  if (onOpenAiAnalysis != null)
                    const PopupMenuItem(value: 'ai', child: Text('国策 AI 分析')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    final theme = Theme.of(context);
    final reviewBlocked = card.hasPendingReview;
    final String? blockedReason = reviewBlocked
        ? '请先完成核对后再操作。'
        : lightBlocked && card.state != NationalFocusCardState.lit
        ? (cascadeSourceLabel == null
              ? '请先点亮父节点。'
              : '因「$cascadeSourceLabel」连带熄灭；父节点恢复后仍需单独点亮。')
        : null;
    Widget action(
      _NodeAction kind,
      IconData icon,
      String title, {
      String? subtitle,
      bool enabled = true,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      enabled: enabled,
      onTap: enabled ? () => onAction(kind) : null,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.name, style: theme.textTheme.headlineSmall),
          if (reviewBlocked) const NationalFocusReviewNotice(),
          const SizedBox(height: 12),
          Text(card.effectiveAction, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('national-focus-primary-state-action'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed:
                      !reviewBlocked &&
                          (card.state == NationalFocusCardState.lit ||
                              !lightBlocked)
                      ? () => onAction(
                          card.state == NationalFocusCardState.lit
                              ? _NodeAction.extinguish
                              : _NodeAction.light,
                        )
                      : null,
                  icon: Icon(
                    card.state == NationalFocusCardState.lit
                        ? Icons.lightbulb_outline
                        : Icons.lightbulb,
                  ),
                  label: Text(switch (card.state) {
                    NationalFocusCardState.lit => '熄灭',
                    NationalFocusCardState.pendingTodayConfirmation => '确认',
                    NationalFocusCardState.extinguished => '点亮',
                  }),
                ),
              ),
              if (card.state ==
                  NationalFocusCardState.pendingTodayConfirmation) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey(
                      'national-focus-secondary-state-action',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: reviewBlocked
                        ? null
                        : () => onAction(_NodeAction.extinguish),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('熄灭'),
                  ),
                ),
              ],
            ],
          ),
          if (blockedReason != null) ...[
            const SizedBox(height: 8),
            Text(blockedReason, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 4),
          action(_NodeAction.details, Icons.article_outlined, '查看详情'),
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
            NationalFocusCardState.lit => PactaStatusColors.of(
              context,
            ).successContainer,
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
              child: Icon(
                statusIcon,
                size: 24,
                color: card.hasPendingReview
                    ? colors.onErrorContainer
                    : switch (card.state) {
                        NationalFocusCardState.lit => PactaStatusColors.of(
                          context,
                        ).onSuccessContainer,
                        NationalFocusCardState.pendingTodayConfirmation =>
                          colors.onTertiaryContainer,
                        NationalFocusCardState.extinguished =>
                          colors.onSurfaceVariant,
                      },
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

enum _ExceptionConfirmationAction { confirm, extinguish, close }

class _ExceptionConfirmationDialog extends StatelessWidget {
  const _ExceptionConfirmationDialog({
    required this.card,
    required this.remaining,
  });

  final NationalFocusCard card;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(card.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确认今日继续有效？', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            remaining > 1 ? '还有 $remaining 个例外节点待逐项确认' : '这是最后一个例外节点',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('国策规则', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(card.effectiveAction),
          if (card.exceptionNotes != null) ...[
            const SizedBox(height: 12),
            Text('例外与判例', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(card.exceptionNotes!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_ExceptionConfirmationAction.extinguish),
          child: const Text('熄灭'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_ExceptionConfirmationAction.close),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_ExceptionConfirmationAction.confirm),
          child: const Text('确认'),
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
        if (widget.card.exceptionNotes != null) ...[
          const SizedBox(height: 12),
          Text('例外与判例', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(widget.card.exceptionNotes!),
        ],
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
