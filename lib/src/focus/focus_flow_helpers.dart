import 'package:flutter/material.dart';

import '../tasks/task_models.dart';
import '../ui/pacta_error_text.dart';
import 'focus_models.dart';
import 'focus_repository.dart';

FocusChainMode initialFocusModeFor(
  TaskClassification classification,
  FocusChainMode fallbackMode,
) => switch (classification) {
  TaskClassification.elite => FocusChainMode.elite,
  TaskClassification.regular => FocusChainMode.regular,
  TaskClassification.both => fallbackMode,
};

String? findTaskTitle(List<Goal> goals, String taskId) {
  for (final goal in goals) {
    for (final task in goal.tasks) {
      if (task.id == taskId) return taskDisplayTitle(task);
    }
  }
  return null;
}

String taskDisplayTitle(Task task) =>
    task.isDeleted ? '${task.title}（已删除）' : task.title;

void showFocusError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(formatUserError(error))));
}

Future<String?> showTextEditor(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextEditorDialog(
      title: title,
      label: label,
      initial: initial,
      required: required,
    ),
  );
}

class _TextEditorDialog extends StatefulWidget {
  const _TextEditorDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.required = false,
  });

  final String title;
  final String label;
  final String initial;
  final bool required;

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late final TextEditingController _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = '请填写${widget.label}。');
      return;
    }
    if (value.length > 500) {
      setState(() => _error = '内容不能超过 500 字。');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLines: 4,
      maxLength: 500,
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}

Future<String?> showPrecedentRulePicker(
  BuildContext context, {
  required FocusRepository repository,
  required List<PrecedentRule> rules,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PrecedentRulePickerDialog(
      repository: repository,
      rules: rules,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PrecedentRulePickerDialog extends StatefulWidget {
  const _PrecedentRulePickerDialog({
    required this.repository,
    required this.rules,
    required this.confirmLabel,
  });

  final FocusRepository repository;
  final List<PrecedentRule> rules;
  final String confirmLabel;

  @override
  State<_PrecedentRulePickerDialog> createState() =>
      _PrecedentRulePickerDialogState();
}

class _PrecedentRulePickerDialogState
    extends State<_PrecedentRulePickerDialog> {
  late List<PrecedentRule> _rules;
  String? _selectedRuleId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rules = [...widget.rules];
  }

  Future<void> _createAndUse() async {
    final text = await showTextEditor(
      context,
      title: '新建并使用下必为例',
      label: '下必为例',
      initial: '',
      required: true,
    );
    if (text == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final rule = await widget.repository.createPrecedentRule(text: text);
      if (!mounted) return;
      setState(() {
        _rules = [rule, ..._rules];
        _selectedRuleId = rule.id;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = formatUserError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择下必为例'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('选择已有规则，或新建一条并立即使用。'),
          const SizedBox(height: 12),
          if (_rules.isEmpty)
            const Text('还没有共享规则，请先新建。')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: _selectedRuleId,
                  onChanged: _busy
                      ? (_) {}
                      : (value) => setState(() => _selectedRuleId = value),
                  child: Column(
                    children: [
                      for (final rule in _rules)
                        RadioListTile<String>(
                          value: rule.id,
                          title: Text(rule.text),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _createAndUse,
            icon: const Icon(Icons.add),
            label: const Text('新建并使用'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy || _selectedRuleId == null
            ? null
            : () {
                final selected = _rules.firstWhere(
                  (rule) => rule.id == _selectedRuleId,
                );
                Navigator.pop(context, selected.text);
              },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
