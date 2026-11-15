import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import '../theme/pacta_status_colors.dart';
import '../ui/pacta_disclosure_section.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_models.dart';
import 'national_focus_reconciliation_page.dart';
import 'national_focus_repository.dart';
import 'national_focus_strengthening_page.dart';
import 'national_focus_view_preferences.dart';

void _syncNationalFocusInBackground(NationalFocusRepository repository) {
  unawaited(repository.sync().catchError((Object _) {}));
}

Future<void> _pushStrengtheningManager({
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
    _syncNationalFocusInBackground(widget.repository);
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
      if (mounted) setState(() => _error = _friendlyError(error));
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
      if (mounted) setState(() => _error = _friendlyError(error));
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
      if (mounted) setState(() => _error = _friendlyError(error));
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
                          onOpenFailureRecords: _openFailureRecords,
                          onOpenAiAnalysis: _placementCard == null
                              ? widget.onOpenAiAnalysis
                              : null,
                          detailed: _detailed,
                          onViewSelected: _placementCard == null && !_viewBusy
                              ? _saveView
                              : null,
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
                                  child: _InlineError(
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
    this.minimumFitScale = 0,
    this.fitViewportToContent = false,
  });

  final double treeWidth;
  final double treeHeight;
  final Widget child;

  /// 初始取景允许的最小可读比例。0 表示沿用现有树的行为：
  /// 只在需要时缩小，绝不放大原始尺寸的内容；历史视角用 0.85 保证初始
  /// 字号可读，显式「适应屏幕」仍按全览拟合。
  final double minimumFitScale;

  /// 视口高度是否贴合内容高度。历史小森林据此不再漂浮在整屏空白里；
  /// 现有树保持固定视口比例不变。
  final bool fitViewportToContent;

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

  /// 全览拟合比例：把整棵树放进视口，不套用可读下限。
  ///
  /// 「适应屏幕」按这个比例取景，保证宽兄弟与高森林都能完整看到。
  double _fitAllScale(Size viewport) => math.min(
    1.0,
    math.min(
      math.max(1, viewport.width - 24) / widget.treeWidth,
      math.max(1, viewport.height - 24) / widget.treeHeight,
    ),
  );

  /// 初始取景比例：在全览比例之上套用可读下限。
  ///
  /// 历史视角因此一开始就把字号保持在 85% 以上，即便森林更大；
  /// 现有树的 minimumFitScale 为 0，初始取景与全览完全一致。
  double _initialFitScale(Size viewport) =>
      math.max(_fitAllScale(viewport), widget.minimumFitScale.clamp(0.0, 1.0));

  double _minimumScale(Size viewport) =>
      math.min(0.01, _initialFitScale(viewport));

  void _fit(Size viewport, {bool fitAll = false}) {
    _viewport = viewport;
    final scale = fitAll ? _fitAllScale(viewport) : _initialFitScale(viewport);
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
      final availableHeight = (MediaQuery.sizeOf(context).height * 0.65).clamp(
        360.0,
        720.0,
      );
      final viewport = Size(
        constraints.maxWidth,
        widget.fitViewportToContent
            ? (widget.treeHeight + 24).clamp(200.0, availableHeight)
            : availableHeight,
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
                    onPressed: () => _fit(viewport, fitAll: true),
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
  });

  final NationalFocusRepository repository;
  final ValueChanged<NationalFocusCard> onPlace;
  final ValueChanged<NationalFocusCard> onDelete;
  final ValueChanged<NationalFocusCard> onRename;

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
  final _action = TextEditingController();
  final _exceptionNotes = TextEditingController();
  late NationalFocusCard? _card = widget.card;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    if (card == null) return;
    _name.text = card.name;
    _action.text = card.action;
    _exceptionNotes.text = card.exceptionNotes ?? '';
  }

  /// The strengthening manager is a pushed route: this editor stays mounted, so
  /// unsaved text in the controllers survives the round trip. Only the
  /// strengthening summary needs a refresh.
  Future<void> _openStrengtheningManager() async {
    final card = _card;
    if (card == null) return;
    await _pushStrengtheningManager(
      context: context,
      repository: widget.repository,
      cardId: card.id,
    );
    if (!mounted) return;
    try {
      final refreshed = await widget.repository.getCard(card.id);
      if (mounted) setState(() => _card = refreshed);
    } catch (_) {
      // The summary keeps the previous values; saving still reports its own error.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _action.dispose();
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
        triggerCondition: '',
        action: _action.text,
        scope: null,
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
                  controller: _action,
                  minLines: 3,
                  maxLines: 6,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '国策规则',
                    hintText: '写清在什么情况下做什么，例如：坐到书桌前后，先完成计划中的第一项',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => _requiredFieldError(value, '国策规则'),
                ),
                const SizedBox(height: 16),
                PactaDisclosureSection(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: const Text('例外与判例'),
                  subtitle: const Text('可选，按需展开'),
                  children: [
                    TextFormField(
                      key: const ValueKey('national-focus-exception-notes'),
                      controller: _exceptionNotes,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '例如：出差时顺延；当天取消安排记“不适用”',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _InlineError(_error!),
                ],
                if (_card != null) ...[
                  const SizedBox(height: 8),
                  _StrengtheningEntry(
                    card: _card!,
                    enabled: !_busy,
                    onManage: _openStrengtheningManager,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
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
      ),
    ),
  );
}

/// The only entrance to strengthening management: the card editor.
class _StrengtheningEntry extends StatelessWidget {
  const _StrengtheningEntry({
    required this.card,
    required this.enabled,
    required this.onManage,
  });

  final NationalFocusCard card;
  final bool enabled;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeLevel = card.activeStrengtheningLevel;
    final current = activeLevel == null ? '基础要求' : '强化等级 $activeLevel';
    final configured = card.strengtheningLevels.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('强化要求', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '当前使用$current · 已设 $configured / '
                    '$maxNationalFocusStrengtheningLevels 级',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: enabled ? onManage : null,
              child: const Text('管理强化要求'),
            ),
          ],
        ),
      ),
    );
  }
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
  });

  final NationalFocusCard card;
  final VoidCallback? onPlace;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onEdit;
  final VoidCallback onDetails;

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
          _FieldText(label: '国策规则', value: card.effectiveAction),
          if (card.exceptionNotes != null) ...[
            const SizedBox(height: 12),
            _FieldText(label: '例外与判例', value: card.exceptionNotes!),
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
          _FieldText(label: '国策规则', value: card.effectiveAction),
          if (card.exceptionNotes != null) ...[
            const SizedBox(height: 12),
            _FieldText(label: '例外与判例', value: card.exceptionNotes!),
          ],
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
          if (reviewBlocked) const _NationalFocusReviewNotice(),
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

  Future<void> _editCard(BuildContext context, NationalFocusCard card) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              NationalFocusCardEditorPage(repository: repository, card: card),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<NationalFocusCard>>(
      stream: card.isInTree
          ? repository.watchTreeCards()
          : repository.watchLibraryCards(),
      builder: (context, snapshot) {
        final card =
            snapshot.data
                ?.where((item) => item.id == this.card.id)
                .firstOrNull ??
            this.card;
        final exceptionNotes = card.exceptionNotes?.trim() ?? '';
        final ruleLabel = card.activeStrengtheningLevel == null
            ? '国策规则'
            : '当前规则 · 强化等级 ${card.activeStrengtheningLevel}';
        return Scaffold(
          appBar: AppBar(title: const Text('国策卡详情')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(card.state.label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              Text(card.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 22),
              _FieldText(label: ruleLabel, value: card.effectiveAction),
              if (exceptionNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ExceptionNotesSection(notes: exceptionNotes),
              ],
              const SizedBox(height: 24),
              Text('记录', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              _NationalFocusRecordSummary(card: card),
              if (cascadeSourceLabel != null) ...[
                const SizedBox(height: 16),
                _CascadeStatusNote(
                  sourceLabel: cascadeSourceLabel!,
                  lightBlocked: lightBlocked,
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: card.hasPendingReview
                      ? null
                      : () => _editCard(context, card),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑卡片'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Collapsed-by-default reading layer for exception notes and precedents.
class _ExceptionNotesSection extends StatelessWidget {
  const _ExceptionNotesSection({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) => PactaDisclosureSection(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    title: const Text('例外与判例'),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(notes, style: Theme.of(context).textTheme.bodyLarge),
      ),
    ],
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
      _syncNationalFocusInBackground(widget.repository);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    }
  }

  /// 标记整组失败记录为已回顾。不需要填写说明，也不改写失败结果；
  /// 重复触发同一组时仓储层是幂等的。
  Future<void> _markReviewed(NationalFocusFailure failure) async {
    try {
      await widget.repository.markFailureReviewed(batchId: failure.batchId);
      _syncNationalFocusInBackground(widget.repository);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
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
            const SizedBox(height: 8),
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
                      onOpenTree: () => _openFailureTree(batches[index].first),
                      onEditExplanation: () =>
                          _editExplanation(batches[index].first),
                      onMarkReviewed: () => _markReviewed(batches[index].first),
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
          '${failures.any((failure) => failure.isPendingReview) ? ' · 待核对' : ''}'
          '${isReviewed ? ' · 已回顾' : ' · 未回顾'}',
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
                '${failure.cause.label}'
                '${failure.failureReason == failure.cause.label ? '' : ' · ${failure.failureReason ?? '原因未填写'}'}'
                '${failure.isPendingReview ? ' · 待核对' : ''}',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('检查点时的完整树快照', style: Theme.of(context).textTheme.titleMedium),
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
              const _TreeMessage(
                icon: Icons.account_tree_outlined,
                title: '当时树没有节点',
                message: '这份快照里没有位于树中的节点。',
              )
            else
              _TreeCanvas(
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
                      if (position > 0) const SizedBox(height: _historyRootGap),
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
                painter: _BranchConnectorPainter(
                  childWidths: [
                    for (final child in children)
                      index.branchWidth(child, _historyNodeWidth),
                  ],
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  strokeWidth: math.max(2, 1.25 / _TreeCanvasScale.of(context)),
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
              _FieldText(
                label: '当时状态',
                value: card.isInTree
                    ? _historyStateLabel(card.state)
                    : '${_historyStateLabel(card.state)}（当时在卡片库）',
              ),
              const SizedBox(height: 12),
              Text('冻结要求', style: Theme.of(sheetContext).textTheme.titleSmall),
              const SizedBox(height: 8),
              _FieldText(label: '触发条件', value: card.effectiveTriggerCondition),
              const SizedBox(height: 12),
              _FieldText(label: '国策规则', value: card.effectiveAction),
              if (card.scope != null) ...[
                const SizedBox(height: 12),
                _FieldText(label: '范围', value: card.scope!),
              ],
              if (card.exceptionNotes != null) ...[
                const SizedBox(height: 12),
                _FieldText(label: '例外与判例', value: card.exceptionNotes!),
              ],
              if (card.activeStrengtheningLevel != null) ...[
                const SizedBox(height: 12),
                _FieldText(
                  label: '强化等级',
                  value: [
                    '等级 ${card.activeStrengtheningLevel}',
                    if (card.requirementVersionNumber != null)
                      '要求版本 ${card.requirementVersionNumber}',
                  ].join(' · '),
                ),
              ],
              const SizedBox(height: 12),
              _FieldText(
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
        color: colors.surfaceContainerLow,
        child: InkWell(
          onTap: onOpen,
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
                  child: Icon(statusIcon, size: 24, color: iconColor),
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
      Text(label, style: Theme.of(context).textTheme.titleSmall),
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
