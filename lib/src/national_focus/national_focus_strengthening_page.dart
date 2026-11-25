import 'package:flutter/material.dart';

import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_disclosure_section.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import 'national_focus_models.dart';
import 'national_focus_repository.dart';
import 'national_focus_shared_widgets.dart';

/// 强化要求草稿变更回调：档位列表与当前选中档位一起交回调用方。
typedef NationalFocusStrengtheningDraftChanged = void Function(
  List<NationalFocusStrengtheningLevel> levels,
  int? activeLevel,
);

/// 国策强化要求：查看全部档位、新建或编辑档位、切换当前使用项。
///
/// 两种构造：
/// - 默认构造直接读仓储并即时落盘（既有路由与单测使用）；
/// - [NationalFocusStrengtheningPage.draft] 只维护内存草稿，每次增改与切换
///   经 [onDraftChanged] 交回卡片编辑页，由编辑页底部唯一「保存」按钮随
///   卡片其余字段一次事务提交。
///
/// 页面不再维护「生效版本记录」：档位本身就是唯一的规则来源，选中行保持
/// 与列表一致的实底 card 色，只靠左侧主色强调条、选中图标与状态徽标表达
/// 「正在使用」，避免半透明混色造成的透明缺块感。
class NationalFocusStrengtheningPage extends StatefulWidget {
  const NationalFocusStrengtheningPage({
    super.key,
    required NationalFocusRepository this.repository,
    required this.cardId,
    this.displayTimeZoneId,
  }) : draftCard = null,
       initialLevels = null,
       initialActiveLevel = null,
       onDraftChanged = null;

  /// 草稿模式：不读也不写数据库。
  const NationalFocusStrengtheningPage.draft({
    super.key,
    required NationalFocusCard card,
    required List<NationalFocusStrengtheningLevel> levels,
    this.initialActiveLevel,
    this.onDraftChanged,
    this.displayTimeZoneId,
  }) : draftCard = card,
       repository = null,
       cardId = null,
       initialLevels = levels;

  final NationalFocusRepository? repository;
  final String? cardId;
  final String? displayTimeZoneId;
  final NationalFocusCard? draftCard;
  final List<NationalFocusStrengtheningLevel>? initialLevels;
  final int? initialActiveLevel;
  final NationalFocusStrengtheningDraftChanged? onDraftChanged;

  bool get isDraft => draftCard != null;

  @override
  State<NationalFocusStrengtheningPage> createState() =>
      _NationalFocusStrengtheningPageState();
}

class _NationalFocusStrengtheningPageState
    extends State<NationalFocusStrengtheningPage> {
  /// 顶栏说明的锚点：点按 IconButton 时由它把 Tooltip 主动显形。
  final GlobalKey<TooltipState> _infoTooltipKey = GlobalKey<TooltipState>();

  NationalFocusCard? _card;
  List<NationalFocusStrengtheningLevel> _levels = const [];
  int? _activeLevel;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = widget.draftCard;
    if (draft != null) {
      _card = draft;
      _levels = [...?widget.initialLevels]
        ..sort((left, right) => left.levelNumber.compareTo(right.levelNumber));
      _activeLevel = widget.initialActiveLevel;
      _loading = false;
      return;
    }
    _reload();
  }

  Future<void> _reload() async {
    try {
      final card = await widget.repository!.getCard(widget.cardId!);
      if (!mounted) return;
      setState(() {
        _card = card;
        _levels = card.strengtheningLevels;
        _activeLevel = card.activeStrengtheningLevel;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = formatUserError(error);
      });
    }
  }

  void _notifyDraft() {
    widget.onDraftChanged?.call(List.unmodifiable(_levels), _activeLevel);
  }

  Future<void> _editLevel(
    NationalFocusCard card, [
    NationalFocusStrengtheningLevel? level,
  ]) async {
    final levelNumber = level?.levelNumber ?? _levels.length + 1;
    final draft = await Navigator.of(context)
        .push<NationalFocusStrengtheningLevelDraft>(
          MaterialPageRoute<NationalFocusStrengtheningLevelDraft>(
            builder: (_) => _StrengtheningLevelEditorPage(
              baseAction: card.action,
              levelNumber: levelNumber,
              initialAction: level?.action,
              initialTriggerCondition: level?.triggerCondition,
            ),
          ),
        );
    if (draft == null || !mounted) return;
    if (widget.isDraft) {
      final updated = NationalFocusStrengtheningLevel(
        levelNumber: levelNumber,
        triggerCondition: draft.triggerCondition,
        action: draft.action,
      );
      setState(() {
        final next = [..._levels];
        final index = next.indexWhere(
          (item) => item.levelNumber == levelNumber,
        );
        if (index >= 0) {
          next[index] = updated;
        } else {
          next.add(updated);
        }
        next.sort(
          (left, right) => left.levelNumber.compareTo(right.levelNumber),
        );
        _levels = next;
        _error = null;
      });
      _notifyDraft();
      return;
    }
    await _run(
      () => widget.repository!.saveStrengtheningLevel(
        cardId: card.id,
        levelNumber: level?.levelNumber,
        draft: draft,
      ),
    );
  }

  Future<void> _selectLevel(int? levelNumber) async {
    if (widget.isDraft) {
      if (_activeLevel == levelNumber) return;
      setState(() {
        _activeLevel = levelNumber;
        _error = null;
      });
      _notifyDraft();
      return;
    }
    await _run(
      () => widget.repository!.selectStrengtheningLevel(
        cardId: widget.cardId!,
        levelNumber: levelNumber,
      ),
    );
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      PactaSurfaces.wrapIfMissing(context, Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final card = _card;
    if (_loading) {
      // 读取期间也要保留返回路径：缺 AppBar 时用户只能等读取结束才能退出。
      return Scaffold(
        appBar: AppBar(title: const Text('国策强化要求')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('国策强化要求')),
        body: Center(child: Text(_error ?? '无法读取这张国策卡。')),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activeLevel = _activeLevel;
    final levelCount = _levels.length;
    final atCapacity = levelCount >= maxNationalFocusStrengtheningLevels;
    final infoMessage = widget.isDraft
        ? '增改与切换都是草稿；点卡片编辑页底部「保存」后随卡片一并生效。'
        : '切换即时生效，已有记录保持不变。是否符合由你判断。';

    return Scaffold(
      appBar: AppBar(
        title: const Text('国策强化要求'),
        actions: [
          // 规则说明收进顶栏 48×48dp 的问号：页面正文不再用一段免责文字
          // 抢占首屏，也不再和选中行重复抄写同一条要求。
          Padding(
            padding: const EdgeInsets.only(right: PactaSpacing.sm),
            // 只有一个 Tooltip：触屏点按（triggerMode.tap）与桌面悬停都只弹
            // 那句规则说明；IconButton 不再自带上具名的第二层 tooltip，
            // 避免点按后冒出「强化要求说明」的冲突气泡。Semantics 保留可读
            // 名称，读屏仍能识别这是说明按钮。
            child: Semantics(
              label: '强化要求说明',
              button: true,
              child: Tooltip(
                key: _infoTooltipKey,
                triggerMode: TooltipTriggerMode.tap,
                message: infoMessage,
                child: IconButton(
                  key: const ValueKey('national-focus-strengthening-info'),
                  onPressed: () =>
                      _infoTooltipKey.currentState?.ensureTooltipVisible(),
                  icon: const Icon(Icons.info_outline, size: PactaIconSizes.md),
                ),
              ),
            ),
          ),
        ],
      ),
      // 顶对齐：20:9 全面屏（393×873dp）下 Center 会把整段正文压到页
      // 垂直中线，顶部掉出一大截空白；长屏只能从顶部开始读。
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          // 整页只有两小段（可用要求 / 新建），一次布局比懒加载更稳：窄屏
          // 两倍字号下滚动到新建行时，上方的分组标题仍留在树里，标题与
          // 动作的相对位置不会因复用而消失。
          child: SingleChildScrollView(
            padding: PactaSpacing.pageInsets(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  NationalFocusInlineError(_error!),
                  const SizedBox(height: PactaSpacing.md),
                ],
                PactaSectionHeader(
                  title: '可用要求',
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  trailing: Text(
                    '$levelCount / $maxNationalFocusStrengtheningLevels 级',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                PactaGroupedList(
                  key: const ValueKey('national-focus-strengthening-tiers'),
                  children: [
                    _AvailableRequirementRow(
                      key: const ValueKey(
                        'national-focus-strengthening-level-base',
                      ),
                      numberLabel: '基础要求',
                      rule: card.action.trim().isEmpty ? '未设置' : card.action,
                      active: activeLevel == null,
                      busy: _busy,
                      onSelect: () => _selectLevel(null),
                    ),
                    for (final level in _levels)
                      _AvailableRequirementRow(
                        key: ValueKey(
                          'national-focus-strengthening-level-${level.levelNumber}',
                        ),
                        numberLabel: '强化 ${level.levelNumber} 级',
                        rule: level.action == null
                            ? '沿用基础要求：${card.action}'
                            : level.action!,
                        active: activeLevel == level.levelNumber,
                        busy: _busy,
                        onSelect: () => _selectLevel(level.levelNumber),
                        onEdit: () => _editLevel(card, level),
                        editTooltip: '编辑强化等级 ${level.levelNumber}',
                      ),
                    // 新建与各等级同处一个分组：它也是"可用要求"的一行，
                    // 但用设置行的视觉语言和上面的可选择段区分开。
                    PactaSettingsTile(
                      tileKey: const ValueKey(
                        'national-focus-strengthening-create',
                      ),
                      leading: Icon(
                        Icons.add_circle_outline,
                        size: PactaIconSizes.md,
                        color: atCapacity || _busy
                            ? colors.onSurfaceVariant
                            : colors.primary,
                      ),
                      title: '新建强化要求',
                      subtitle: atCapacity
                          ? '已达 $maxNationalFocusStrengtheningLevels 级上限'
                          : _levels.isEmpty
                          ? '为这张卡设置更严格的国策规则（最多 $maxNationalFocusStrengtheningLevels 级）'
                          : '添加强化等级 ${levelCount + 1}',
                      enabled: !_busy && !atCapacity,
                      showChevron: !atCapacity,
                      onTap: atCapacity ? null : () => _editLevel(card),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the available requirements list.
///
/// 选中段与未选中段共用同一段水平内边距（左 16 / 右 12），所以左侧的选中
/// 图标在两种状态下落在同一条像素线上；选中只加左侧强调条与状态徽标，不挪
/// 动任何几何、也不把行底换成半透明混色——两种状态都是与列表一致的实底
/// [PactaSurfaces.card]，列表分段之间不会出现透明缺块。
class _AvailableRequirementRow extends StatelessWidget {
  const _AvailableRequirementRow({
    super.key,
    required this.numberLabel,
    required this.rule,
    required this.active,
    required this.busy,
    required this.onSelect,
    this.onEdit,
    this.editTooltip,
  });

  final String numberLabel;
  final String rule;
  final bool active;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;
  final String? editTooltip;

  /// Row width below which the rule moves to its own line. At 320 dp the list
  /// content is about 280 dp wide, which leaves the rule too little room next
  /// to the level label and the two controls.
  static const double _stackedBreakpoint = 440;

  /// Minimum touch target for Android (48 logical pixels).
  static const double _hitTarget = 48;

  /// 当前选中项的左侧强调竖条宽度。
  static const double _accentWidth = 3.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaces = PactaSurfaces.of(context);
    final label = Text(
      numberLabel,
      style: theme.textTheme.labelLarge?.copyWith(
        color: active ? colors.onSurface : colors.primary,
      ),
    );
    final ruleText = Text(
      rule,
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface),
    );
    final edit = onEdit == null
        ? null
        : IconButton(
            tooltip: editTooltip,
            onPressed: busy ? null : onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: _hitTarget,
              height: _hitTarget,
            ),
            icon: const Icon(Icons.edit_outlined, size: PactaIconSizes.compact),
          );
    return Material(
      // 实底：与未选中段、与整个分组完全同色。透明底一旦叠上半透明混色，
      // 在分段卡片里就会读成缺一块的透明洞。
      color: surfaces.card,
      child: InkWell(
        onTap: busy || active ? null : onSelect,
        child: Stack(
          children: [
            if (active)
              Positioned(
                left: 0,
                top: PactaSpacing.sm,
                bottom: PactaSpacing.sm,
                width: _accentWidth,
                child: DecoratedBox(
                  key: const ValueKey(
                    'national-focus-strengthening-active-bar',
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(_accentWidth),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final selection = _selection(context);
                  if (constraints.maxWidth < _stackedBreakpoint) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _stateIcon(colors),
                            const SizedBox(width: PactaSpacing.sm),
                            Expanded(child: label),
                            selection,
                            ?edit,
                          ],
                        ),
                        const SizedBox(height: 6),
                        ruleText,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _stateIcon(colors),
                      const SizedBox(width: PactaSpacing.sm),
                      label,
                      const SizedBox(width: PactaSpacing.md),
                      Expanded(child: ruleText),
                      const SizedBox(width: PactaSpacing.sm),
                      selection,
                      ?edit,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateIcon(ColorScheme colors) => Icon(
    active ? Icons.check_circle : Icons.radio_button_unchecked,
    size: PactaIconSizes.compact,
    color: active ? colors.primary : colors.onSurfaceVariant,
  );

  /// State and selection stay separate from editing: an inactive level can be
  /// edited without changing which requirement is currently in force.
  Widget _selection(BuildContext context) => active
      ? const PactaStatusBadge(
          label: '正在使用',
          tone: PactaStatusBadgeTone.primary,
        )
      : TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, _hitTarget)),
          onPressed: busy ? null : onSelect,
          child: const Text('选择'),
        );
}

class _StrengtheningLevelEditorPage extends StatefulWidget {
  const _StrengtheningLevelEditorPage({
    required this.baseAction,
    required this.levelNumber,
    this.initialAction,
    this.initialTriggerCondition,
  });

  final String baseAction;
  final int levelNumber;
  final String? initialAction;
  final String? initialTriggerCondition;

  @override
  State<_StrengtheningLevelEditorPage> createState() =>
      _StrengtheningLevelEditorPageState();
}

class _StrengtheningLevelEditorPageState
    extends State<_StrengtheningLevelEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _action;
  late final String? _legacyTriggerCondition;
  late final String _initialAction;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _legacyTriggerCondition = widget.initialTriggerCondition;
    _initialAction = widget.initialAction ?? '';
    _action = TextEditingController(text: _initialAction);
    _action.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final dirty = _action.text != _initialAction;
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
  }

  @override
  void dispose() {
    _action.removeListener(_onTextChanged);
    _action.dispose();
    super.dispose();
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      NationalFocusStrengtheningLevelDraft(
        // Legacy trigger overrides stay stored; they are no longer a new
        // input field and are passed through unchanged when editing.
        triggerCondition: _legacyTriggerCondition,
        action: _action.text,
      ),
    );
  }

  /// 有未保存输入时系统返回 / 顶栏返回都先确认：强化规则是用户手写的
  /// 判据，不能像普通弹层一样一按就吞掉。
  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: Text('强化等级 ${widget.levelNumber} 的修改还没有保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PactaSurfaces.wrapIfMissing(
    context,
    PopScope<NationalFocusStrengtheningLevelDraft>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: Builder(builder: _buildPage),
    ),
  );

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isEditing = widget.initialAction != null;
    final title =
        (isEditing ? '编辑强化等级 ' : '新建强化等级 ') + widget.levelNumber.toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: PactaSpacing.md),
            child: FilledButton.tonal(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: PactaSpacing.pageInsets(context),
              children: [
                const PactaSectionHeader(
                  title: '强化规则',
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                Card(
                  child: Padding(
                    padding: PactaSpacing.cardInsets,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const ValueKey('strengthened-rule'),
                          controller: _action,
                          minLines: 3,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: pactaCardInputDecoration(
                            context,
                            labelText: '强化后的国策规则',
                            helperText: '留空则沿用基础要求',
                            alignLabelWithHint: true,
                          ),
                        ),
                        FormField<bool>(
                          validator: (_) =>
                              _action.text.trim().isEmpty &&
                                  (_legacyTriggerCondition ?? '').trim().isEmpty
                              ? '填写强化后的国策规则。'
                              : null,
                          builder: (state) => state.hasError
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: PactaSpacing.md,
                                  ),
                                  child: Text(
                                    state.errorText!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.error,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: PactaSpacing.lg),
                // 对照参考是只读材料：默认折叠，需要核对时展开同一张白卡。
                const PactaSectionHeader(
                  title: '参考对照',
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: PactaDisclosureSection(
                    leading: Icon(
                      Icons.article_outlined,
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
                    title: const Text('对照基础规则'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.baseAction.trim().isEmpty
                              ? '未设置'
                              : widget.baseAction,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
