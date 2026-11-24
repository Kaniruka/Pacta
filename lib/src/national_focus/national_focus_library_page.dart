import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';
import '../theme/pacta_theme.dart';
import '../ui/pacta_card_header.dart';
import '../ui/pacta_disclosure_section.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_horizontal_pager.dart';
import 'national_focus_models.dart';
import 'national_focus_repository.dart';
import 'national_focus_shared_widgets.dart';

class NationalFocusCardLibraryPage extends StatefulWidget {
  const NationalFocusCardLibraryPage({
    super.key,
    required this.repository,
    this.selectCreatedCard = false,
    this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final bool selectCreatedCard;
  final String? displayTimeZoneId;

  @override
  State<NationalFocusCardLibraryPage> createState() =>
      _NationalFocusCardLibraryPageState();
}

class _NationalFocusCardLibraryPageState
    extends State<NationalFocusCardLibraryPage>
    with SingleTickerProviderStateMixin {
  static const _pageTransition = Duration(milliseconds: 240);

  /// 页签与分页共用一套索引：点按 TabBar、横拖、触控板、滚轮与快捷键都落
  /// 到这里，指示条与页面永远指向同一页。
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  late final PageController _pageController = PageController();

  int _activeIndex = 0;
  int? _animatingToIndex;
  bool _animatingTab = false;

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 程序化切页期间以目标页为准：跨页途中不能被中途页改写高亮。
  int get _settledIndex => _animatingTab && _animatingToIndex != null
      ? _animatingToIndex!
      : _activeIndex;

  void _selectTab(int index) {
    final int target = index.clamp(0, 1);
    if (_activeIndex != target) setState(() => _activeIndex = target);
    if (_tabController.index != target && !_tabController.indexIsChanging) {
      _tabController.animateTo(target);
    }
    final PageController controller = _pageController;
    if (!controller.hasClients) return;
    final double targetPage = target.toDouble();
    final double current = controller.page ?? targetPage;
    if ((current - targetPage).abs() < 0.001) return;
    _animatingToIndex = target;
    _animatingTab = true;
    unawaited(
      controller
          .animateToPage(
            target,
            duration: _pageTransition,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted || _animatingToIndex != target) return;
            _animatingToIndex = null;
            _animatingTab = false;
          }),
    );
  }

  /// 滚轮/快捷键的一步切页：两端钳位，不循环。
  void _stepTab(int step) {
    final int next = (_settledIndex + step).clamp(0, 1);
    if (next == _settledIndex) return;
    _selectTab(next);
  }

  void _onPageChanged(int index) {
    if (_animatingTab) return;
    if (_activeIndex != index) setState(() => _activeIndex = index);
    if (_tabController.index != index && !_tabController.indexIsChanging) {
      _tabController.index = index;
    }
  }

  /// 拖动中让指示条 1:1 跟手：TabBar 的位置就是 index + offset。
  bool _syncIndicator(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final ScrollMetrics metrics = notification.metrics;
    if (metrics is! PageMetrics) return false;
    final double? page = metrics.page;
    if (page == null) return false;
    // TabController 自己在做页签切换动画时 offset 不可写。
    if (_tabController.indexIsChanging) return false;
    _tabController.offset = (page - _tabController.index).clamp(-1.0, 1.0);
    return false;
  }

  Future<void> _createCard(BuildContext context) async {
    final created = await Navigator.of(context).push<NationalFocusCard>(
      MaterialPageRoute<NationalFocusCard>(
        builder: (_) => NationalFocusCardEditorPage(
          repository: widget.repository,
          displayTimeZoneId: widget.displayTimeZoneId,
        ),
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
          .showSnackBar(SnackBar(content: Text(formatUserError(error))));
    }
  }

  Future<void> _restoreCard(NationalFocusCard card) async {
    try {
      await widget.repository.restoreDeletedCard(card.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复到卡片库；树位置和点亮状态需要重新选择。')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(formatUserError(error))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('国策卡片库'),
      bottom: TabBar(
        controller: _tabController,
        onTap: _selectTab,
        tabs: const [
          Tab(text: '卡片库'),
          Tab(text: '已删除'),
        ],
      ),
    ),
    // 分页作用域铺满整窗：横拖、触控板、Shift+滚轮与快捷键共用一套页签。
    body: PactaHorizontalPagerScope(
      pageCount: 2,
      currentPage: _settledIndex,
      onStepPage: _stepTab,
      child: ScrollConfiguration(
        // 桌面按住鼠标横拖也能切页；触控板与触控笔同权。
        behavior: const PactaScrollBehavior(),
        child: NotificationListener<ScrollNotification>(
          onNotification: _syncIndicator,
          child: PageView(
            key: const ValueKey('national-focus-library-pager'),
            controller: _pageController,
            // 吸附由 PactaPageScrollPhysics 承担，宽屏慢拖也翻页。
            pageSnapping: false,
            physics: const PactaPageScrollPhysics(),
            onPageChanged: _onPageChanged,
            children: [
              PactaPagerWheelCatcher(
                child: _LibraryCardList(
                  repository: widget.repository,
                  onPlace: (card) => Navigator.of(context).pop(card),
                  onDelete: _deleteCard,
                  displayTimeZoneId: widget.displayTimeZoneId,
                ),
              ),
              PactaPagerWheelCatcher(
                child: _DeletedNationalFocusCardList(
                  repository: widget.repository,
                  onRestore: _restoreCard,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _createCard(context),
      icon: const Icon(Icons.add),
      label: const Text('新建国策卡'),
    ),
  );
}

class _LibraryCardList extends StatelessWidget {
  const _LibraryCardList({
    required this.repository,
    required this.onPlace,
    required this.onDelete,
    this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final ValueChanged<NationalFocusCard> onPlace;
  final ValueChanged<NationalFocusCard> onDelete;
  final String? displayTimeZoneId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<NationalFocusCard>>(
    stream: repository.watchLibraryCards(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return NationalFocusTreeMessage(
          icon: Icons.error_outline,
          title: '无法读取卡片库',
          message: formatUserError(snapshot.error!),
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
            child: NationalFocusTreeMessage(
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
            padding: PactaSpacing.pageInsets(context).copyWith(bottom: 100),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: PactaSpacing.md),
            itemBuilder: (context, index) => _LibraryCard(
              card: cards[index],
              onDetails: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NationalFocusCardDetailPage(
                    repository: repository,
                    card: cards[index],
                    lightBlocked: false,
                    cascadeSourceLabel: null,
                    displayTimeZoneId: displayTimeZoneId,
                  ),
                ),
              ),
              onPlace: () => onPlace(cards[index]),
              onDelete: () => onDelete(cards[index]),
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
        return NationalFocusTreeMessage(
          icon: Icons.error_outline,
          title: '无法读取已删除卡片',
          message: formatUserError(snapshot.error!),
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
            child: NationalFocusTreeMessage(
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
            padding: PactaSpacing.pageInsets(context).copyWith(bottom: 100),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: PactaSpacing.md),
            itemBuilder: (context, index) => _DeletedLibraryCard(
              card: cards[index],
              onRestore: () => onRestore(cards[index]),
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
    this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final NationalFocusCard? card;
  final String? displayTimeZoneId;

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
    await pushStrengtheningManager(
      context: context,
      repository: widget.repository,
      cardId: card.id,
      displayTimeZoneId: widget.displayTimeZoneId,
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
      if (mounted) Navigator.of(context).pop(card);
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
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
              padding: PactaSpacing.pageInsets(context, top: PactaSpacing.xl),
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
                  NationalFocusInlineError(_error!),
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
            // 底部固定操作区与表单用同一条页边距：保存按钮的左右缘必须
            // 与输入框严格对齐。
            padding: PactaSpacing.pageInsets(
              context,
              top: PactaSpacing.sm,
              bottom: PactaSpacing.md,
            ),
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

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.onDetails,
    required this.card,
    required this.onPlace,
    required this.onDelete,
  });

  final NationalFocusCard card;
  final VoidCallback? onPlace;
  final VoidCallback? onDelete;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strengtheningLevel = card.activeStrengtheningLevel;
    final hasExceptionNotes = (card.exceptionNotes ?? '').trim().isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 整卡是详情入口：读者点标题、规则或留白都进同一个阅读页。
        onTap: onDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (strengtheningLevel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  '当前要求 · 强化等级 $strengtheningLevel',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            // 48dp 的弹出菜单按钮会把单行标题垂直居中，标题距卡片顶部被撑到
            // 约 29dp；统一头部把标题视觉顶距固定为 16dp，并保留 48×48dp
            // 命中区。有强化等级说明时由头部内部 8dp 补偿衔接，不叠加。
            PactaCardHeader(
              title: card.name,
              padding: EdgeInsets.fromLTRB(
                16,
                strengtheningLevel == null ? 8 : 0,
                8,
                16,
              ),
              trailing: PopupMenuButton<String>(
                tooltip: '卡片操作',
                onSelected: (value) {
                  if (value == 'details') {
                    onDetails();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'details', child: Text('查看详情')),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: onDelete != null,
                    child: Text(
                      '删除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 列表只负责识别这张卡：规则最多三行，判例收成徽标，全文
                  // 留给详情页，滚动时不再被长文本撑成一屏一张卡。
                  Text('国策规则', style: theme.textTheme.titleSmall),
                  const SizedBox(height: PactaSpacing.xs),
                  Text(
                    card.effectiveAction.isEmpty ? '未设置' : card.effectiveAction,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (hasExceptionNotes) ...[
                    const SizedBox(height: PactaSpacing.sm),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: PactaStatusBadge(
                        label: '含判例',
                        icon: Icons.menu_book_outlined,
                      ),
                    ),
                  ],
                  const SizedBox(height: PactaSpacing.md),
                  _NationalFocusRecordSummary(card: card, compact: true),
                  const SizedBox(height: PactaSpacing.md),
                  // 删除只留在溢出菜单：底栏不再并排一颗重复的危险按钮。
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: onPlace,
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('放入国策树'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeletedLibraryCard extends StatelessWidget {
  const _DeletedLibraryCard({required this.card, required this.onRestore});

  final NationalFocusCard card;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasExceptionNotes = (card.exceptionNotes ?? '').trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(card.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: PactaSpacing.sm),
            // 已删除列表与卡片库保持同一档信息密度：三行规则 + 判例徽标。
            Text('国策规则', style: theme.textTheme.titleSmall),
            const SizedBox(height: PactaSpacing.xs),
            Text(
              card.effectiveAction.isEmpty ? '未设置' : card.effectiveAction,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
            if (hasExceptionNotes) ...[
              const SizedBox(height: PactaSpacing.sm),
              const Align(
                alignment: Alignment.centerLeft,
                child: PactaStatusBadge(
                  label: '含判例',
                  icon: Icons.menu_book_outlined,
                ),
              ),
            ],
            const SizedBox(height: PactaSpacing.md),
            _NationalFocusRecordSummary(card: card, compact: true),
            const SizedBox(height: PactaSpacing.sm),
            Text('恢复后会回到卡片库；树位置和点亮状态需要重新选择。', style: theme.textTheme.bodySmall),
            const SizedBox(height: PactaSpacing.sm),
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
}

class NationalFocusCardDetailPage extends StatelessWidget {
  const NationalFocusCardDetailPage({
    super.key,
    required this.repository,
    required this.card,
    required this.lightBlocked,
    required this.cascadeSourceLabel,
    this.displayTimeZoneId,
  });
  final NationalFocusRepository repository;
  final NationalFocusCard card;
  final bool lightBlocked;
  final String? cascadeSourceLabel;
  final String? displayTimeZoneId;

  Future<void> _editCard(BuildContext context, NationalFocusCard card) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NationalFocusCardEditorPage(
            repository: repository,
            card: card,
            displayTimeZoneId: displayTimeZoneId,
          ),
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
          // 推入式二级页统一居中并限制正文宽度：宽屏下与页面级卡片同一条
          // 阅读线，左右边距改回对称的 PactaSpacing.pageInsets。
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: PactaSpacing.pageInsets(context),
                children: [
                  Text(card.state.label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  // 名称与连续点亮胶囊同排：短名称时胶囊紧跟右侧，长名称自动换行。
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(card.name, style: theme.textTheme.headlineSmall),
                      NationalFocusStreakTags(
                        currentConsecutiveDays: card.currentConsecutiveDays,
                        bestConsecutiveDays: card.bestConsecutiveDays,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  // 规则区与记录区各自成卡：亮暗模式下都靠 M3 Card 的容器色
                  // 和 16dp 间隙划界，读者不会把「要求什么」和「记录了什么」
                  // 读成同一段文字。
                  Card(
                    key: const ValueKey('national-focus-detail-rules-card'),
                    child: Padding(
                      padding: PactaSpacing.cardInsets,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NationalFocusFieldText(
                            label: ruleLabel,
                            value: card.effectiveAction,
                          ),
                          if (exceptionNotes.isNotEmpty) ...[
                            const SizedBox(height: PactaSpacing.sm),
                            _ExceptionNotesSection(notes: exceptionNotes),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: PactaSpacing.lg),
                  Card(
                    key: const ValueKey('national-focus-detail-records-card'),
                    child: Padding(
                      padding: PactaSpacing.cardInsets,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('记录', style: theme.textTheme.titleSmall),
                          const SizedBox(height: PactaSpacing.sm),
                          // 连续天数已在名称旁的胶囊里，记录区只留累计成功日
                          // 与内化进度。
                          _NationalFocusRecordSummary(
                            card: card,
                            showStreaks: false,
                          ),
                        ],
                      ),
                    ),
                  ),
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
                      onPressed: () => _editCard(context, card),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑卡片'),
                    ),
                  ),
                ],
              ),
            ),
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
  const _NationalFocusRecordSummary({
    required this.card,
    this.showStreaks = true,
    this.compact = false,
  });

  final NationalFocusCard card;

  /// 详情页名称旁已用 [NationalFocusStreakTags] 展示连续天数，记录区不再重复。
  final bool showStreaks;

  /// 列表卡片的紧凑档：一行「成功日 / 内化」加一条进度条，不再铺三行。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final progress = card.internalizationProgress.clamp(0.0, 100.0);
    if (compact) {
      final theme = Theme.of(context);
      final style = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('成功日 ${card.successfulDays} 天', style: style),
              ),
              Text('内化 ${progress.toStringAsFixed(1)}%', style: style),
            ],
          ),
          const SizedBox(height: PactaSpacing.xs),
          Semantics(
            label: '内化进度 ${progress.toStringAsFixed(1)}%',
            child: LinearProgressIndicator(value: progress / 100),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          showStreaks
              ? '当前连续 ${card.currentConsecutiveDays} 天 · 历史最高 '
                    '${card.bestConsecutiveDays} 天 · 成功日 ${card.successfulDays} 天'
              : '累计成功日 ${card.successfulDays} 天',
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

String? _requiredFieldError(String? value, String label) =>
    value == null || value.trim().isEmpty ? '请输入$label。' : null;
