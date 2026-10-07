import 'package:flutter/material.dart';

import 'chain_signals_repository.dart';
import 'focus_models.dart';

enum _SignalTarget {
  appointment('预约链 · 触发信号'),
  elite('精锐链 · 专注标志'),
  regular('普通链 · 专注标志');

  const _SignalTarget(this.label);
  final String label;
  String text(ChainSignalTexts texts) => switch (this) {
    appointment => texts.appointmentTriggerSignal,
    elite => texts.eliteFocusMarker,
    regular => texts.regularFocusMarker,
  };
}

class ChainSignalsCard extends StatelessWidget {
  const ChainSignalsCard({super.key, required this.repository});

  final ChainSignalsRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<ChainSignalTexts>(
    stream: repository.watch(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('动作设置读取失败，请稍后重试。'),
          ),
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final texts = snapshot.data!;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('神圣座位', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('由你执行的承诺动作，计数沿用下方三条链的连续记录。'),
              for (final target in _SignalTarget.values)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        target.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        target.text(texts).isEmpty
                            ? '尚未设置'
                            : target.text(texts),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _edit(context, target),
                          child: Text('编辑${target.label.split(' · ').last}'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _edit(BuildContext context, _SignalTarget target) async {
    final texts = await repository.get();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _SignalEditor(repository: repository, texts: texts, target: target),
    );
  }
}

class ChainSignalInstructions extends StatelessWidget {
  const ChainSignalInstructions({
    super.key,
    required this.repository,
    required this.mode,
  });
  final ChainSignalsRepository repository;
  final FocusChainMode mode;

  @override
  Widget build(BuildContext context) => StreamBuilder<ChainSignalTexts>(
    stream: repository.watch(),
    builder: (context, snapshot) {
      final texts = snapshot.data;
      if (texts == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '预约触发信号：${texts.appointmentTriggerSignal.isEmpty ? '尚未设置' : texts.appointmentTriggerSignal}',
          ),
          const SizedBox(height: 8),
          Text(
            '${mode.label}专注标志：${texts.focusMarker(mode).isEmpty ? '尚未设置' : texts.focusMarker(mode)}',
          ),
        ],
      );
    },
  );
}

class _SignalEditor extends StatefulWidget {
  const _SignalEditor({
    required this.repository,
    required this.texts,
    required this.target,
  });
  final ChainSignalsRepository repository;
  final ChainSignalTexts texts;
  final _SignalTarget target;
  @override
  State<_SignalEditor> createState() => _SignalEditorState();
}

class _SignalEditorState extends State<_SignalEditor> {
  late final _controller = TextEditingController(
    text: widget.target.text(widget.texts),
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Read the latest other fields so editing one action preserves concurrent edits.
      final current = await widget.repository.get();
      await widget.repository.save(
        ChainSignalTexts(
          appointmentTriggerSignal: widget.target == _SignalTarget.appointment
              ? _controller.text
              : current.appointmentTriggerSignal,
          eliteFocusMarker: widget.target == _SignalTarget.elite
              ? _controller.text
              : current.eliteFocusMarker,
          regularFocusMarker: widget.target == _SignalTarget.regular
              ? _controller.text
              : current.regularFocusMarker,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败，请确认当前账号可用后重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.target.label),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '承诺动作',
              hintText: '例如：戴上指定耳机',
              helperText: '留空可清除设置，不影响已有记录。',
              helperMaxLines: 3,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        onPressed: _busy ? null : _save,
        child: Text(_busy ? '保存中…' : '保存'),
      ),
    ],
  );
}
