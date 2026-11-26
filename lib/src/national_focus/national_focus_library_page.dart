import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../theme/pacta_theme.dart';
import '../ui/pacta_card_header.dart';
import '../ui/pacta_disclosure_section.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_horizontal_pager.dart';
import 'national_focus_icons.dart';
import 'national_focus_models.dart';
import 'national_focus_repository.dart';
import 'national_focus_shared_widgets.dart';
import 'national_focus_strengthening_page.dart';

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
  Widget build(BuildContext context) =>
      PactaSurfaces.wrapIfMissing(context, Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) => Scaffold(
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
  String? _iconKey;
  List<NationalFocusStrengtheningLevel> _strengtheningLevels = const [];
  int? _activeStrengtheningLevel;
  late final String _initialName;
  late final String _initialAction;
  late final String _initialExceptionNotes;
  late final String? _initialIconKey;
  late final List<NationalFocusStrengtheningLevel> _initialStrengtheningLevels;
  late final int? _initialActiveStrengtheningLevel;
  bool _dirty = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _initialName = card?.name ?? '';
    _initialAction = card?.action ?? '';
    _initialExceptionNotes = card?.exceptionNotes ?? '';
    _initialIconKey = card?.iconKey;
    _initialStrengtheningLevels = List.unmodifiable(
      card?.strengtheningLevels ?? const <NationalFocusStrengtheningLevel>[],
    );
    _initialActiveStrengtheningLevel = card?.activeStrengtheningLevel;
    _name.text = _initialName;
    _action.text = _initialAction;
    _exceptionNotes.text = _initialExceptionNotes;
    _iconKey = _initialIconKey;
    _strengtheningLevels = [..._initialStrengtheningLevels];
    _activeStrengtheningLevel = _initialActiveStrengtheningLevel;
    _name.addListener(_onFieldChanged);
    _action.addListener(_onFieldChanged);
    _exceptionNotes.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onFieldChanged);
    _action.removeListener(_onFieldChanged);
    _exceptionNotes.removeListener(_onFieldChanged);
    _name.dispose();
    _action.dispose();
    _exceptionNotes.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final dirty = _hasUnsavedChanges();
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
  }

  /// 逐项对照进入页面时的快照：名称、规则、例外、图标、强化档位与当前选中
  /// 档位任一项变化都算未保存。强化草稿按编号与规则逐条比较，增删改都算。
  bool _hasUnsavedChanges() {
    if (_name.text != _initialName ||
        _action.text != _initialAction ||
        _exceptionNotes.text != _initialExceptionNotes ||
        _iconKey != _initialIconKey ||
        _activeStrengtheningLevel != _initialActiveStrengtheningLevel ||
        _strengtheningLevels.length != _initialStrengtheningLevels.length) {
      return true;
    }
    for (var index = 0; index < _strengtheningLevels.length; index++) {
      final current = _strengtheningLevels[index];
      final initial = _initialStrengtheningLevels[index];
      if (current.levelNumber != initial.levelNumber ||
          current.triggerCondition != initial.triggerCondition ||
          current.action != initial.action) {
        return true;
      }
    }
    return false;
  }

  /// 强化草稿页只读这份临时卡片：名称与基础规则取当前输入，不写库。
  NationalFocusCard _strengtheningDraftCard() {
    final card = widget.card;
    final timestamp = DateTime.now().toUtc();
    return NationalFocusCard(
      id: card?.id ?? 'draft',
      name: _name.text.trim().isEmpty ? '未命名国策卡' : _name.text.trim(),
      triggerCondition: '',
      action: _action.text.trim(),
      isInTree: card?.isInTree ?? false,
      state: card?.state ?? NationalFocusCardState.extinguished,
      createdAt: card?.createdAt ?? timestamp,
      updatedAt: card?.updatedAt ?? timestamp,
      strengtheningLevels: _strengtheningLevels,
      activeStrengtheningLevel: _activeStrengtheningLevel,
      iconKey: _iconKey,
    );
  }

  /// 强化等级是卡片草稿的一部分：进入子页调整，改动经回调写回本页状态，
  /// 直到点底部唯一「保存」才随卡片一次事务落盘。
  Future<void> _openStrengtheningDraft() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationalFocusStrengtheningPage.draft(
          card: _strengtheningDraftCard(),
          levels: _strengtheningLevels,
          initialActiveLevel: _activeStrengtheningLevel,
          displayTimeZoneId: widget.displayTimeZoneId,
          onDraftChanged: (levels, activeLevel) {
            if (!mounted) return;
            setState(() {
              _strengtheningLevels = List.unmodifiable(levels);
              _activeStrengtheningLevel = activeLevel;
              _dirty = _hasUnsavedChanges();
            });
          },
        ),
      ),
    );
    if (mounted) setState(() => _dirty = _hasUnsavedChanges());
  }

  Future<void> _pickIcon() async {
    final selection = await showNationalFocusIconPicker(
      context,
      selectedKey: _iconKey,
    );
    if (selection == null || !mounted) return;
    setState(() {
      _iconKey = selection == nationalFocusIconResetSelection
          ? null
          : selection;
      _dirty = _hasUnsavedChanges();
    });
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
        iconKey: _iconKey,
        strengtheningLevels: _strengtheningLevels,
        activeStrengtheningLevel: _activeStrengtheningLevel,
        updateStrengthening: true,
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

  Future<void> _requestExit() async {
    final choice = await showDialog<_UnsavedChangesChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('尚未保存更改'),
        content: const Text('名称、图标、国策规则、例外或强化草稿还有未保存的修改。'),
        actions: [
          TextButton(
            key: const ValueKey('national-focus-editor-discard'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChangesChoice.discard),
            child: const Text('放弃'),
          ),
          TextButton(
            key: const ValueKey('national-focus-editor-keep-editing'),
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(_UnsavedChangesChoice.keepEditing),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            key: const ValueKey('national-focus-editor-save'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnsavedChangesChoice.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _UnsavedChangesChoice.discard) {
      Navigator.of(context).pop();
    } else if (choice == _UnsavedChangesChoice.save) {
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) => PactaSurfaces.wrapIfMissing(
    context,
    PopScope<NationalFocusCard>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestExit();
      },
      child: Builder(builder: _buildForm),
    ),
  );

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaces = PactaSurfaces.of(context);
    final activeStrengtheningLevel = _activeStrengtheningLevel;
    return Scaffold(
      appBar: AppBar(title: Text(widget.card == null ? '新建国策卡' : '编辑国策卡')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: PactaSpacing.pageInsets(context),
              children: [
                const PactaSectionHeader(
                  title: '基础内容',
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                Card(
                  key: const ValueKey('national-focus-editor-base-card'),
                  child: Padding(
                    padding: PactaSpacing.cardInsets,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            NationalFocusCardIconWell(iconKey: _iconKey),
                            const SizedBox(width: PactaSpacing.md),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '卡片图标',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: PactaSpacing.xxs),
                                  Text(
                                    _iconKey == null
                                        ? '未设置（默认灯泡）'
                                        : nationalFocusIconLabel(_iconKey),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              key: const ValueKey('national-focus-editor-icon'),
                              onPressed: _busy ? null : _pickIcon,
                              icon: const Icon(
                                Icons.palette_outlined,
                                size: PactaIconSizes.sm,
                              ),
                              label: const Text('更换图标'),
                            ),
                          ],
                        ),
                        const SizedBox(height: PactaSpacing.lg),
                        if (activeStrengtheningLevel != null) ...[
                          NationalFocusInfoCallout(
                            message:
                                '当前正使用强化等级 $activeStrengtheningLevel，此处修改的是基础要求。',
                          ),
                          const SizedBox(height: PactaSpacing.lg),
                        ],
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          decoration: pactaCardInputDecoration(
                            context,
                            labelText: '卡片名称',
                          ),
                          validator: (value) =>
                              _requiredFieldError(value, '卡片名称'),
                        ),
                        const SizedBox(height: PactaSpacing.lg),
                        TextFormField(
                          controller: _action,
                          minLines: 3,
                          maxLines: 6,
                          textInputAction: TextInputAction.next,
                          decoration: pactaCardInputDecoration(
                            context,
                            labelText: '国策规则',
                            hintText: '写清在什么情况下做什么，例如：坐到书桌前后，先完成计划中的第一项',
                            alignLabelWithHint: true,
                          ),
                          validator: (value) =>
                              _requiredFieldError(value, '国策规则'),
                        ),
                      ],
                    ),
                  ),
                ),
                const PactaSectionHeader(title: '进阶设置'),
                PactaGroupedList(
                  children: [
                    PactaDisclosureSection(
                      leading: Icon(
                        Icons.menu_book_outlined,
                        size: PactaIconSizes.md,
                        color: colors.onSurfaceVariant,
                      ),
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: PactaSpacing.lg,
                        vertical: PactaSpacing.xs,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        PactaSpacing.lg,
                        0,
                        PactaSpacing.lg,
                        PactaSpacing.lg,
                      ),
                      title: const Text('例外与判例'),
                      // 只订阅输入框的值刷新副标题：展开状态与焦点都不受影响。
                      subtitle: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _exceptionNotes,
                        builder: (context, value, _) => Text(
                          value.text.trim().isNotEmpty
                              ? '已填写（按需展开）'
                              : '可选（按需展开）',
                        ),
                      ),
                      children: [
                        TextFormField(
                          key: const ValueKey('national-focus-exception-notes'),
                          controller: _exceptionNotes,
                          minLines: 2,
                          maxLines: 4,
                          textInputAction: TextInputAction.done,
                          decoration: pactaCardInputDecoration(
                            context,
                            hintText: '例如：出差时顺延；当天取消安排记“不适用”',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                    _StrengtheningEntry(
                      activeLevel: _activeStrengtheningLevel,
                      levelCount: _strengtheningLevels.length,
                      enabled: !_busy,
                      onManage: _openStrengtheningDraft,
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: PactaSpacing.lg),
                  NationalFocusInlineError(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
      // 底部固定操作区：白底 + 1dp 发丝线，与表单共用同一条页边距，保存按钮
      // 与「基础内容」白卡左右缘严格对齐。
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaces.actionBar,
          border: Border(top: BorderSide(color: surfaces.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: PactaSpacing.pageInsets(
                  context,
                  top: PactaSpacing.md,
                  bottom: PactaSpacing.md,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: PactaIconSizes.sm,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.save_outlined,
                            size: PactaIconSizes.sm,
                          ),
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
      ),
    );
  }
}

/// 编辑页返回时的三选一：放弃修改、留下继续编辑、校验后保存。
enum _UnsavedChangesChoice { discard, keepEditing, save }

/// The only entrance to strengthening management: the card editor.
///
/// 这里不再包一层 surfaceContainerLow 阴影框：页面底色本身就是浅蓝灰，
/// 再叠一层同族色只会读成"发灰的第二个卡片"。整行改用标准设置行，
/// 强化档位与已设数量各占一个语义位。
class _StrengtheningEntry extends StatelessWidget {
  const _StrengtheningEntry({
    required this.activeLevel,
    required this.levelCount,
    required this.enabled,
    required this.onManage,
  });

  final int? activeLevel;
  final int levelCount;
  final bool enabled;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final current = activeLevel == null ? '基础要求' : '强化等级 $activeLevel';
    return PactaSettingsTile(
      tileKey: const ValueKey('national-focus-editor-strengthening-entry'),
      leadingIcon: Icons.trending_up,
      title: '强化要求',
      subtitle: '当前使用$current，进入调整草稿并随卡片保存',
      statusBadge: PactaStatusBadge(
        label: '$levelCount / $maxNationalFocusStrengtheningLevels 级',
        tone: activeLevel == null
            ? PactaStatusBadgeTone.neutral
            : PactaStatusBadgeTone.primary,
      ),
      enabled: enabled,
      onTap: onManage,
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
    return _LibraryCardShell(
      card: card,
      // 整卡是详情入口：读者点标题、规则或留白都进同一个阅读页。
      onTap: onDetails,
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
            child: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
      action: FilledButton.tonalIcon(
        onPressed: onPlace,
        icon: const Icon(Icons.account_tree_outlined, size: PactaIconSizes.sm),
        label: const Text('放入国策树'),
      ),
    );
  }
}

/// 卡片库外壳：卡片库与已删除列表共用同一套三段式布局。
///
/// [onTap] 为空时（已删除卡片）不包 InkWell；[trailing] 为空时头部右侧改留
/// 16dp 内缘，标题不会因为少一颗按钮而贴边。[middle] 是规则与底栏之间的
/// 提示位（已删除卡片的恢复说明）；卡片内容宽度不足 300dp 时底栏自动上下
/// 堆叠，按钮右对齐，进度摘要不被挤成一条。
class _LibraryCardShell extends StatelessWidget {
  const _LibraryCardShell({
    required this.card,
    required this.action,
    this.onTap,
    this.trailing,
    this.middle,
  });

  final NationalFocusCard card;

  /// 底栏右侧的主操作（放入国策树 / 恢复到卡片库）。
  final Widget action;

  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? middle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final middleWidget = middle;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PactaCardHeader(
          title: card.name,
          // 卡片自定义图标：标题旁的紧凑圆形图标井，空值回落默认灯泡。
          leading: NationalFocusCardIconWell(
            iconKey: card.iconKey,
            diameter: PactaIconSizes.lg,
          ),
          titleStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: PactaFonts.semibold,
          ),
          padding: EdgeInsets.fromLTRB(16, 8, trailing == null ? 16 : 8, 4),
          trailing: trailing,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LibraryCardMeta(card: card),
              // 列表只负责识别这张卡：规则最多三行，全文留给详情页，
              // 滚动时不再被长文本撑成一屏一张卡。
              Text(
                card.effectiveAction.isEmpty ? '未设置' : card.effectiveAction,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (middleWidget != null) ...[
                const SizedBox(height: PactaSpacing.sm),
                middleWidget,
              ],
              const SizedBox(height: PactaSpacing.md),
              // 左右平衡底栏：左侧进度摘要吃满余宽，右侧只留一颗主操作。
              LayoutBuilder(
                builder: (context, constraints) {
                  final compactProgress = _LibraryCardProgress(card: card);
                  if (constraints.maxWidth >= 300) {
                    return Row(
                      children: [
                        Expanded(child: compactProgress),
                        const SizedBox(width: PactaSpacing.md),
                        action,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      compactProgress,
                      const SizedBox(height: PactaSpacing.md),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// 卡片库外壳的元数据胶囊行：强化档位 / 已内化 / 判例。
///
/// 三项都不成立时整行不占位，短卡片不会因为「胶囊槽」被撑出一条空带。
class _LibraryCardMeta extends StatelessWidget {
  const _LibraryCardMeta({required this.card});

  final NationalFocusCard card;

  @override
  Widget build(BuildContext context) {
    final strengtheningLevel = card.activeStrengtheningLevel;
    final hasExceptionNotes = (card.exceptionNotes ?? '').trim().isNotEmpty;
    if (strengtheningLevel == null &&
        !card.isInternalized &&
        !hasExceptionNotes) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: PactaSpacing.sm),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (strengtheningLevel != null)
            PactaStatusBadge(
              label: '强化 $strengtheningLevel 级',
              icon: Icons.trending_up,
              tone: PactaStatusBadgeTone.primary,
            ),
          if (card.isInternalized)
            const PactaStatusBadge(
              label: '已内化',
              icon: Icons.verified_outlined,
              tone: PactaStatusBadgeTone.success,
            ),
          if (hasExceptionNotes)
            const PactaStatusBadge(
              label: '含判例',
              icon: Icons.menu_book_outlined,
            ),
        ],
      ),
    );
  }
}

/// 卡片底栏左侧的等宽摘要 + 4dp 内化轨。
class _LibraryCardProgress extends StatelessWidget {
  const _LibraryCardProgress({required this.card});

  final NationalFocusCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = card.internalizationProgress.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '成功日 ${card.successfulDays} 天，内化 ${progress.toStringAsFixed(1)}%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        NationalFocusInternalizationBar(card: card, height: 4),
      ],
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
    return _LibraryCardShell(
      card: card,
      // 已删除列表与卡片库共用同一套三段布局，只把主操作换成恢复。
      middle: Text(
        '恢复后会回到卡片库；树位置和点亮状态需要重新选择。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      action: FilledButton.tonalIcon(
        onPressed: onRestore,
        icon: const Icon(Icons.restore, size: PactaIconSizes.sm),
        label: const Text('恢复到卡片库'),
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
  Widget build(BuildContext context) =>
      PactaSurfaces.wrapIfMissing(context, Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
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
        final sourceLabel = cascadeSourceLabel;
        return Scaffold(
          appBar: AppBar(
            title: const Text('国策卡详情'),
            // 编辑是这张卡唯一的写入口：收进顶栏右侧，与阅读内容不再抢位置。
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: PactaSpacing.sm),
                child: Tooltip(
                  message: '编辑卡片',
                  child: TextButton.icon(
                    key: const ValueKey('national-focus-detail-edit'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _editCard(context, card),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: PactaIconSizes.sm,
                    ),
                    label: const Text('编辑'),
                  ),
                ),
              ),
            ],
          ),
          // 推入式二级页统一居中并限制正文宽度：宽屏下与页面级卡片同一条
          // 阅读线，左右边距取对称的 PactaSpacing.pageInsets。
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: PactaSpacing.pageInsets(context),
                children: [
                  NationalFocusCardIdentityCard(
                    key: const ValueKey('national-focus-detail-header-card'),
                    card: card,
                    cascadeNote: sourceLabel == null
                        ? null
                        : lightBlocked
                        ? '因「$sourceLabel」连带熄灭；父节点恢复后仍需单独点亮。'
                        : '父节点已恢复；此节点仍需单独点亮。',
                  ),
                  const SizedBox(height: PactaSpacing.lg),
                  // 规则区与记录区各自成卡，和只读镜像共用同一对组件：
                  // 亮暗模式下都靠 M3 Card 的容器色和 16dp 间隙划界。
                  NationalFocusDetailRulesCard(
                    key: const ValueKey('national-focus-detail-rules-card'),
                    card: card,
                    footer: exceptionNotes.isEmpty
                        ? null
                        : _ExceptionNotesSection(notes: exceptionNotes),
                  ),
                  const SizedBox(height: PactaSpacing.lg),
                  NationalFocusDetailRecordsCard(
                    key: const ValueKey('national-focus-detail-records-card'),
                    card: card,
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

String? _requiredFieldError(String? value, String label) =>
    value == null || value.trim().isEmpty ? '请输入$label。' : null;
