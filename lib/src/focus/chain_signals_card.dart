import 'package:flutter/material.dart';

import 'chain_signals_repository.dart';
import 'focus_models.dart';
import 'focus_statistics.dart';

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

/// Keeps each commitment action next to the chain it belongs to.
class FocusChainOverview extends StatelessWidget {
  const FocusChainOverview({
    super.key,
    this.repository,
    required this.records,
    this.appointmentRecord,
    required this.statistics,
  });

  final ChainSignalsRepository? repository;
  final List<FocusChainRecord> records;
  final AppointmentChainRecord? appointmentRecord;
  final Map<FocusChainMode, FocusSessionStatistics> statistics;

  @override
  Widget build(BuildContext context) {
    if (repository == null) return _content(context, const ChainSignalTexts());
    return StreamBuilder<ChainSignalTexts>(
      stream: repository!.watch(),
      builder: (context, snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.hasError)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('动作设置读取失败，请稍后重试。'),
            ),
          _content(context, snapshot.data ?? const ChainSignalTexts()),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, ChainSignalTexts texts) {
    Widget focusCard(FocusChainMode mode) {
      FocusChainRecord? record;
      for (final candidate in records) {
        if (candidate.mode == mode) record = candidate;
      }
      return _ChainSummaryCard(
        title: mode.label,
        icon: mode == FocusChainMode.elite
            ? Icons.shield_outlined
            : Icons.all_inclusive,
        current: record?.currentConsecutive ?? 0,
        best: record?.bestConsecutive ?? 0,
        pendingReview: record?.hasPendingReview ?? false,
        target: mode == FocusChainMode.elite
            ? _SignalTarget.elite
            : _SignalTarget.regular,
        texts: texts,
        repository: repository,
        statistics: statistics[mode],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final elite = focusCard(FocusChainMode.elite);
            final regular = focusCard(FocusChainMode.regular);
            if (constraints.maxWidth >= 600 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: elite),
                  const SizedBox(width: 12),
                  Expanded(child: regular),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [elite, const SizedBox(height: 12), regular],
            );
          },
        ),
        const SizedBox(height: 12),
        _ChainSummaryCard(
          title: '预约链',
          icon: Icons.schedule_outlined,
          current: appointmentRecord?.currentConsecutive ?? 0,
          best: appointmentRecord?.bestConsecutive ?? 0,
          pendingReview: appointmentRecord?.hasPendingReview ?? false,
          target: _SignalTarget.appointment,
          texts: texts,
          repository: repository,
        ),
      ],
    );
  }
}

class _ChainSummaryCard extends StatelessWidget {
  const _ChainSummaryCard({
    required this.title,
    required this.icon,
    required this.current,
    required this.best,
    required this.pendingReview,
    required this.target,
    required this.texts,
    required this.repository,
    this.statistics,
  });

  final String title;
  final IconData icon;
  final int current;
  final int best;
  final bool pendingReview;
  final _SignalTarget target;
  final ChainSignalTexts texts;
  final ChainSignalsRepository? repository;
  final FocusSessionStatistics? statistics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appointment = target == _SignalTarget.appointment;
    final actionLabel = appointment ? '触发信号' : '专注标志';
    final action = target.text(texts);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  label: '$title连续 $current 次',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '连续 ',
                          style: theme.textTheme.bodyMedium,
                        ),
                        TextSpan(
                          text: '$current',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        TextSpan(text: ' 次', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                Text(
                  '最佳 $best 次',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (pendingReview)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('记录待核对', style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 16),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actionLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.isEmpty ? '尚未设置' : action,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (repository != null)
                  IconButton(
                    key: ValueKey('focus-signal-edit-${target.name}'),
                    tooltip: '编辑$title$actionLabel',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => _editSignal(context, repository!, target),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
              ],
            ),
            if (!appointment) ...[
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 240 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.5;
                  final total = _DurationMetric(
                    label: '累计专注',
                    seconds: statistics?.totalDurationSeconds ?? 0,
                  );
                  final average = _DurationMetric(
                    label: '平均每次',
                    seconds: statistics?.averageDurationSeconds.round() ?? 0,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: total),
                        const SizedBox(width: 12),
                        Expanded(child: average),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [total, const SizedBox(height: 12), average],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DurationMetric extends StatelessWidget {
  const _DurationMetric({required this.label, required this.seconds});
  final String label;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    final duration = [
      if (hours > 0) '$hours 小时',
      if (minutes > 0) '$minutes 分钟',
      if (remainingSeconds > 0 || seconds == 0) '$remainingSeconds 秒',
    ].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(duration, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

Future<void> _editSignal(
  BuildContext context,
  ChainSignalsRepository repository,
  _SignalTarget target,
) async {
  final texts = await repository.get();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) =>
        _SignalEditor(repository: repository, texts: texts, target: target),
  );
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
