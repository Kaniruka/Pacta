import 'dart:async';

import 'package:flutter/material.dart';

import 'national_focus_models.dart';
import 'national_focus_repository.dart';

class NationalFocusStrengtheningPage extends StatefulWidget {
  const NationalFocusStrengtheningPage({
    super.key,
    required this.repository,
    required this.cardId,
  });

  final NationalFocusRepository repository;
  final String cardId;

  @override
  State<NationalFocusStrengtheningPage> createState() =>
      _NationalFocusStrengtheningPageState();
}

class _NationalFocusStrengtheningPageState
    extends State<NationalFocusStrengtheningPage> {
  NationalFocusCard? _card;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final card = await widget.repository.getCard(widget.cardId);
      if (!mounted) return;
      setState(() {
        _card = card;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _editLevel(
    NationalFocusCard card, [
    NationalFocusStrengtheningLevel? level,
  ]) async {
    final draft = await Navigator.of(context)
        .push<NationalFocusStrengtheningLevelDraft>(
          MaterialPageRoute<NationalFocusStrengtheningLevelDraft>(
            builder: (_) =>
                _StrengtheningLevelEditorPage(card: card, level: level),
          ),
        );
    if (draft == null || !mounted) return;
    await _run(() async {
      await widget.repository.saveStrengtheningLevel(
        cardId: card.id,
        levelNumber: level?.levelNumber,
        draft: draft,
      );
    });
  }

  Future<void> _selectLevel(int? levelNumber) async {
    await _run(
      () => widget.repository.selectStrengtheningLevel(
        cardId: widget.cardId,
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
      unawaited(widget.repository.sync().catchError((Object _) {}));
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('国策强化要求')),
        body: Center(child: Text(_error ?? '无法读取这张国策卡。')),
      );
    }

    final activeLevel = card.activeStrengtheningLevel;
    final versionCount = card.requirementVersions.length;
    final levelCount = card.strengtheningLevels.length;
    final atCapacity = levelCount >= maxNationalFocusStrengtheningLevels;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('国策强化要求')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _CurrentRequirementPanel(
                label: activeLevel == null
                    ? '当前使用 · 基础要求'
                    : '当前使用 · 强化等级 $activeLevel',
                rule: card.effectiveAction,
              ),
              const SizedBox(height: 8),
              Text(
                '修改立即生效，不改变节点状态、清除记录或要求重新确认；是否符合由你判断。',
                style: theme.textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('生效版本记录 · $versionCount'),
                subtitle: Text(_currentIntervalLabel(card.requirementVersions)),
                children: [
                  for (final version in card.requirementVersions.reversed)
                    _RequirementVersionTile(version: version),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('可用要求', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    '$levelCount / $maxNationalFocusStrengtheningLevels 级',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _AvailableRequirementRow(
                key: const ValueKey('national-focus-strengthening-level-base'),
                numberLabel: '基础',
                rule: card.action.trim().isEmpty ? '未设置' : card.action,
                active: activeLevel == null,
                busy: _busy,
                onSelect: () => _selectLevel(null),
              ),
              for (final level in card.strengtheningLevels)
                _AvailableRequirementRow(
                  key: ValueKey(
                    'national-focus-strengthening-level-${level.levelNumber}',
                  ),
                  numberLabel: '${level.levelNumber} 级',
                  rule: level.action == null
                      ? '沿用基础要求：${card.action}'
                      : level.action!,
                  active: activeLevel == level.levelNumber,
                  busy: _busy,
                  onSelect: () => _selectLevel(level.levelNumber),
                  onEdit: () => _editLevel(card, level),
                  editTooltip: '编辑强化等级 ${level.levelNumber}',
                ),
              if (card.strengtheningLevels.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '暂无强化等级。可为这张卡设置更严格的国策规则。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _busy || atCapacity
                      ? null
                      : () => _editLevel(card),
                  icon: const Icon(Icons.add),
                  label: const Text('新建强化要求'),
                ),
              ),
              if (atCapacity) ...[
                const SizedBox(height: 6),
                Text(
                  '已达 $maxNationalFocusStrengtheningLevels 级上限',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The requirement in force, set apart from the list of the other levels.
class _CurrentRequirementPanel extends StatelessWidget {
  const _CurrentRequirementPanel({required this.label, required this.rule});

  final String label;
  final String rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              rule,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One compact row in the available requirements list. The active row is the
/// only one carrying the in-use marker and the edit affordance.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = active ? colors.onSecondaryContainer : colors.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: active
          ? BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      padding: EdgeInsets.symmetric(horizontal: active ? 12 : 0, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              numberLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: active ? foreground : colors.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              rule,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            Text(
              '正在使用',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
              ),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: editTooltip,
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
          ] else
            TextButton(
              onPressed: busy ? null : onSelect,
              child: const Text('选择'),
            ),
        ],
      ),
    );
  }
}

class _StrengtheningLevelEditorPage extends StatefulWidget {
  const _StrengtheningLevelEditorPage({required this.card, this.level});

  final NationalFocusCard card;
  final NationalFocusStrengtheningLevel? level;

  @override
  State<_StrengtheningLevelEditorPage> createState() =>
      _StrengtheningLevelEditorPageState();
}

class _StrengtheningLevelEditorPageState
    extends State<_StrengtheningLevelEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _action;
  late final String? _legacyTriggerCondition;

  bool get _isEditingExistingLevel => widget.level != null;

  @override
  void initState() {
    super.initState();
    _legacyTriggerCondition = widget.level?.triggerCondition;
    _action = TextEditingController(text: widget.level?.action ?? '');
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final levelNumber =
        widget.level?.levelNumber ?? widget.card.strengtheningLevels.length + 1;
    final title = widget.level == null
        ? '新建强化等级 $levelNumber'
        : '编辑强化等级 $levelNumber';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonal(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  _isEditingExistingLevel
                      ? '同时显示基础和本级国策规则，便于比较。留空会沿用基础要求。'
                      : '同时显示基础和本级国策规则，便于比较。填写强化后的国策规则。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('strengthened-rule'),
                  controller: _action,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: '强化后的国策规则',
                    helperText: '留空则沿用基础要求',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: const Text('对照基础规则'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.card.action.trim().isEmpty
                            ? '未设置'
                            : widget.card.action,
                      ),
                    ),
                  ],
                ),
                FormField<bool>(
                  validator: (_) =>
                      _action.text.trim().isEmpty &&
                          (_legacyTriggerCondition ?? '').trim().isEmpty
                      ? '填写强化后的国策规则。'
                      : null,
                  builder: (state) => state.hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            state.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequirementVersionTile extends StatelessWidget {
  const _RequirementVersionTile({required this.version});

  final NationalFocusRequirementVersion version;

  @override
  Widget build(BuildContext context) {
    final levelNumber = version.strengtheningLevelNumber;
    final label = levelNumber == null ? '基础要求' : '强化等级 $levelNumber';
    final endText = version.effectiveUntil == null
        ? '当前仍生效'
        : _formatMoment(version.effectiveUntil!);
    final end = version.effectiveUntil == null ? endText : '至 $endText';
    final legacyTrigger = version.effectiveTriggerCondition.trim();
    final exceptionNotes = version.exceptionNotes?.trim();
    final start = _formatMoment(version.effectiveFrom);
    final versionNumber = version.versionNumber;
    final rule = version.effectiveAction;
    final details = [
      '国策规则：$rule',
      if (exceptionNotes != null && exceptionNotes.isNotEmpty)
        '例外与判例：$exceptionNotes',
      if (legacyTrigger.isNotEmpty) '旧触发条件：$legacyTrigger',
      '$start — $end',
    ].join('\n');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('版本 $versionNumber · $label'),
      subtitle: Text(details),
      isThreeLine: true,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}

String _currentIntervalLabel(List<NationalFocusRequirementVersion> versions) {
  if (versions.isEmpty) return '尚无生效版本记录';
  final current = versions.last;
  final versionNumber = current.versionNumber;
  final effectiveFrom = _formatMoment(current.effectiveFrom);
  return '当前版本 $versionNumber · 自 $effectiveFrom 生效';
}

String _formatMoment(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
