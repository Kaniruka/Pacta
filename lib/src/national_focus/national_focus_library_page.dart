import 'package:flutter/material.dart';

import '../ui/pacta_card_header.dart';
import '../ui/pacta_disclosure_section.dart';
import '../ui/pacta_error_text.dart';
import 'national_focus_models.dart';
import 'national_focus_repository.dart';
import 'national_focus_shared_widgets.dart';

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
      syncNationalFocusInBackground(widget.repository);
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
      syncNationalFocusInBackground(widget.repository);
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _LibraryCard(
              card: cards[index],
              onDetails: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NationalFocusCardDetailPage(
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
    await pushStrengtheningManager(
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
      syncNationalFocusInBackground(widget.repository);
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strengtheningLevel = card.activeStrengtheningLevel;
    return Card(
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NationalFocusFieldText(
                  label: '国策规则',
                  value: card.effectiveAction,
                ),
                if (card.exceptionNotes != null) ...[
                  const SizedBox(height: 12),
                  NationalFocusFieldText(
                    label: '例外与判例',
                    value: card.exceptionNotes!,
                  ),
                ],
                if (card.hasPendingReview) ...[
                  const SizedBox(height: 12),
                  const NationalFocusReviewNotice(),
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
        ],
      ),
    );
  }
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
          NationalFocusFieldText(label: '国策规则', value: card.effectiveAction),
          if (card.exceptionNotes != null) ...[
            const SizedBox(height: 12),
            NationalFocusFieldText(label: '例外与判例', value: card.exceptionNotes!),
          ],
          const SizedBox(height: 12),
          _NationalFocusRecordSummary(card: card),
          if (card.hasPendingReview) ...[
            const SizedBox(height: 12),
            const NationalFocusReviewNotice(),
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

class NationalFocusCardDetailPage extends StatelessWidget {
  const NationalFocusCardDetailPage({
    super.key,
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
              NationalFocusFieldText(
                label: ruleLabel,
                value: card.effectiveAction,
              ),
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

String? _requiredFieldError(String? value, String label) =>
    value == null || value.trim().isEmpty ? '请输入$label。' : null;
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
    syncNationalFocusInBackground(repository);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(formatUserError(error))));
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
