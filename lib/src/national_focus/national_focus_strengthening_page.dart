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
    final currentTitle = activeLevel == null
        ? '当前采用 · 基础要求'
        : '当前采用 · 强化等级 $activeLevel';
    final versionCount = card.requirementVersions.length;
    final levelCount = card.strengtheningLevels.length;

    return Scaffold(
      appBar: AppBar(title: const Text('国策强化要求')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _RequirementSummary(
                title: '基础要求',
                triggerCondition: card.triggerCondition,
                action: card.action,
                scope: card.scope,
                exceptionNotes: card.exceptionNotes,
              ),
              const SizedBox(height: 12),
              _RequirementSummary(
                title: currentTitle,
                triggerCondition: card.effectiveTriggerCondition,
                action: card.effectiveAction,
                scope: card.scope,
                exceptionNotes: card.exceptionNotes,
                emphasized: true,
              ),
              const SizedBox(height: 8),
              Text(
                '切换或编辑会立即采用新要求，不会自动点亮、熄灭、清除记录或要求重新确认；是否符合由你判断。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('生效版本记录 · $versionCount'),
                subtitle: Text(_currentIntervalLabel(card.requirementVersions)),
                children: [
                  for (final version in card.requirementVersions.reversed)
                    _RequirementVersionTile(version: version),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '强化等级 $levelCount/$maxNationalFocusStrengtheningLevels',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _busy ||
                            levelCount >= maxNationalFocusStrengtheningLevels
                        ? null
                        : () => _editLevel(card),
                    icon: const Icon(Icons.add),
                    label: const Text('新建强化等级'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (card.strengtheningLevels.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('还没有强化等级。可单独强化触发条件、行动或两者。'),
                  ),
                ),
              for (final level in card.strengtheningLevels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StrengtheningLevelCard(
                    card: card,
                    level: level,
                    active: activeLevel == level.levelNumber,
                    busy: _busy,
                    onEdit: () => _editLevel(card, level),
                    onSelect: () => _selectLevel(level.levelNumber),
                  ),
                ),
              if (activeLevel != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _selectLevel(null),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('切换到基础要求'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StrengtheningLevelCard extends StatelessWidget {
  const _StrengtheningLevelCard({
    required this.card,
    required this.level,
    required this.active,
    required this.busy,
    required this.onEdit,
    required this.onSelect,
  });

  final NationalFocusCard card;
  final NationalFocusStrengtheningLevel level;
  final bool active;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levelNumber = level.levelNumber;
    final title = '强化等级 $levelNumber';
    return Card(
      color: active ? theme.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                if (active)
                  const Chip(
                    label: Text('当前采用'),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: '编辑$title',
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ComparedRequirement(
              label: '主要触发条件',
              baseValue: card.triggerCondition,
              overrideValue: level.triggerCondition,
            ),
            const SizedBox(height: 10),
            _ComparedRequirement(
              label: '行动',
              baseValue: card.action,
              overrideValue: level.action,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: active
                  ? const Text('当前要求立即生效')
                  : OutlinedButton(
                      onPressed: busy ? null : onSelect,
                      child: Text('采用$title'),
                    ),
            ),
          ],
        ),
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
  late final TextEditingController _trigger;
  late final TextEditingController _action;

  @override
  void initState() {
    super.initState();
    _trigger = TextEditingController(
      text: widget.level?.triggerCondition ?? '',
    );
    _action = TextEditingController(text: widget.level?.action ?? '');
  }

  @override
  void dispose() {
    _trigger.dispose();
    _action.dispose();
    super.dispose();
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      NationalFocusStrengtheningLevelDraft(
        triggerCondition: _trigger.text,
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
              child: const Text('保存强化等级'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  '基础要求和本等级要求同时显示，便于比较。留空字段会沿用基础要求；至少填写触发条件或行动其中一项。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                _RequirementComparisonEditor(
                  title: '主要触发条件',
                  baseValue: widget.card.triggerCondition,
                  controller: _trigger,
                  fieldKey: const ValueKey('strengthened-trigger'),
                  fieldLabel: '强化后的主要触发条件',
                ),
                const SizedBox(height: 16),
                _RequirementComparisonEditor(
                  title: '行动',
                  baseValue: widget.card.action,
                  controller: _action,
                  fieldKey: const ValueKey('strengthened-action'),
                  fieldLabel: '强化后的行动',
                ),
                FormField<bool>(
                  validator: (_) =>
                      _trigger.text.trim().isEmpty &&
                          _action.text.trim().isEmpty
                      ? '至少填写触发条件或行动其中一项。'
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

class _RequirementComparisonEditor extends StatelessWidget {
  const _RequirementComparisonEditor({
    required this.title,
    required this.baseValue,
    required this.controller,
    required this.fieldKey,
    required this.fieldLabel,
  });

  final String title;
  final String baseValue;
  final TextEditingController controller;
  final Key fieldKey;
  final String fieldLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final base = _RequirementValueCard(title: '基础$title', value: baseValue);
      final strengthened = TextFormField(
        key: fieldKey,
        controller: controller,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: fieldLabel,
          helperText: '留空则沿用基础要求',
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      );
      final heading = Text(
        title,
        style: Theme.of(context).textTheme.titleSmall,
      );
      if (constraints.maxWidth < 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 8),
            base,
            const SizedBox(height: 10),
            strengthened,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: base),
              const SizedBox(width: 16),
              Expanded(child: strengthened),
            ],
          ),
        ],
      );
    },
  );
}

class _ComparedRequirement extends StatelessWidget {
  const _ComparedRequirement({
    required this.label,
    required this.baseValue,
    required this.overrideValue,
  });

  final String label;
  final String baseValue;
  final String? overrideValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levelValue = overrideValue ?? '沿用基础要求：$baseValue';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final base = _RequirementValueCard(title: '基础', value: baseValue);
            final level = _RequirementValueCard(
              title: '本等级',
              value: levelValue,
            );
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [base, const SizedBox(height: 8), level],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: base),
                const SizedBox(width: 12),
                Expanded(child: level),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RequirementSummary extends StatelessWidget {
  const _RequirementSummary({
    required this.title,
    required this.triggerCondition,
    required this.action,
    required this.scope,
    required this.exceptionNotes,
    this.emphasized = false,
  });

  final String title;
  final String triggerCondition;
  final String action;
  final String? scope;
  final String? exceptionNotes;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: emphasized ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _RequirementValueCard(title: '主要触发条件', value: triggerCondition),
            const SizedBox(height: 8),
            _RequirementValueCard(title: '行动', value: action),
            if (scope != null) ...[
              const SizedBox(height: 8),
              _RequirementValueCard(title: '适用范围', value: scope!),
            ],
            if (exceptionNotes != null) ...[
              const SizedBox(height: 8),
              _RequirementValueCard(title: '例外说明', value: exceptionNotes!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequirementValueCard extends StatelessWidget {
  const _RequirementValueCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    ),
  );
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
    final trigger = version.effectiveTriggerCondition;
    final action = version.effectiveAction;
    final start = _formatMoment(version.effectiveFrom);
    final versionNumber = version.versionNumber;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('版本 $versionNumber · $label'),
      subtitle: Text('主要触发条件：$trigger\n行动：$action\n$start — $end'),
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
