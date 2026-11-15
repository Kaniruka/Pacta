import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chain_signals_repository.dart';
import 'focus_models.dart';
import 'focus_statistics.dart';

/// The two commitment actions the overview can edit.
///
/// The Focus Marker is shared by both Focus Chains, so it has one entry point;
/// the Appointment Chain keeps its own Trigger Signal.
enum _SignalTarget {
  marker(label: '专注标志', dialogTitle: '专注标志（精锐链与普通链共用）', tooltip: '编辑专注标志'),
  appointment(label: '触发信号', dialogTitle: '预约链触发信号', tooltip: '编辑预约链触发信号');

  const _SignalTarget({
    required this.label,
    required this.dialogTitle,
    required this.tooltip,
  });

  final String label;
  final String dialogTitle;
  final String tooltip;

  String text(ChainSignalTexts texts) => switch (this) {
    marker => texts.focusMarker,
    appointment => texts.appointmentTriggerSignal,
  };

  Key get editKey => ValueKey('focus-signal-edit-$name');
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

  FocusChainRecord? _recordFor(FocusChainMode mode) {
    FocusChainRecord? record;
    for (final candidate in records) {
      if (candidate.mode == mode) record = candidate;
    }
    return record;
  }

  Widget _content(BuildContext context, ChainSignalTexts texts) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final columnLabel = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const ValueKey('focus-chain-table'),
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Spacer(flex: 3),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '当前连续',
                        textAlign: TextAlign.right,
                        style: columnLabel,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '历史最高',
                        textAlign: TextAlign.right,
                        style: columnLabel,
                      ),
                    ),
                  ],
                ),
                _ChainTableRow(
                  label: FocusChainMode.elite.label,
                  icon: Icons.shield_outlined,
                  record: _recordFor(FocusChainMode.elite),
                  statistics: statistics[FocusChainMode.elite],
                ),
                _ChainTableRow(
                  label: FocusChainMode.regular.label,
                  icon: Icons.all_inclusive,
                  record: _recordFor(FocusChainMode.regular),
                  statistics: statistics[FocusChainMode.regular],
                ),
                _ChainTableRow(
                  label: '预约链',
                  icon: Icons.schedule_outlined,
                  current: appointmentRecord?.currentConsecutive ?? 0,
                  best: appointmentRecord?.bestConsecutive ?? 0,
                  pendingReview: appointmentRecord?.hasPendingReview ?? false,
                  isAppointment: true,
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          key: const ValueKey('focus-chain-signals'),
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SignalAction(
                  target: _SignalTarget.marker,
                  texts: texts,
                  repository: repository,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 2),
                  child: Text(
                    '精锐链与普通链共用这一动作，两条链的连续记录仍各自独立。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Divider(height: 1, color: colors.outlineVariant),
                _SignalAction(
                  target: _SignalTarget.appointment,
                  texts: texts,
                  repository: repository,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One aligned chain row: name, current streak, best streak, and its footnote.
///
/// Elite and Regular rows carry the accumulated and average effective focus
/// time; the Appointment row states how it is entered instead.
class _ChainTableRow extends StatelessWidget {
  const _ChainTableRow({
    required this.label,
    required this.icon,
    this.record,
    this.current,
    this.best,
    this.pendingReview,
    this.statistics,
    this.isAppointment = false,
    this.isLast = false,
  });

  final String label;
  final IconData icon;
  final FocusChainRecord? record;
  final int? current;
  final int? best;
  final bool? pendingReview;
  final FocusSessionStatistics? statistics;
  final bool isAppointment;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final currentValue = current ?? record?.currentConsecutive ?? 0;
    final bestValue = best ?? record?.bestConsecutive ?? 0;
    final pendingValue = pendingReview ?? record?.hasPendingReview ?? false;
    final appointment = isAppointment;
    final footnotes = <Widget>[
      if (pendingValue) Text('记录待核对', style: labelStyle),
      if (appointment && !pendingValue) Text('主动预约后进入准备', style: labelStyle),
      if (!appointment) ...[
        _DurationMetric(
          key: ValueKey('focus-chain-stat-$label-累计专注'),
          label: '累计专注',
          seconds: statistics?.totalDurationSeconds ?? 0,
        ),
        _DurationMetric(
          key: ValueKey('focus-chain-stat-$label-平均每次'),
          label: '平均每次',
          seconds: statistics?.averageDurationSeconds.round() ?? 0,
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: colors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  label: '$label当前连续 $currentValue 次',
                  excludeSemantics: true,
                  child: Text(
                    '$currentValue',
                    textAlign: TextAlign.right,
                    style: valueStyle,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Semantics(
                  label: '$label历史最高 $bestValue 次',
                  excludeSemantics: true,
                  child: Text(
                    '$bestValue',
                    textAlign: TextAlign.right,
                    style: valueStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: footnotes,
          ),
        ),
        if (!isLast) Divider(height: 1, color: colors.outlineVariant),
      ],
    );
  }
}

class _SignalAction extends StatelessWidget {
  const _SignalAction({
    required this.target,
    required this.texts,
    required this.repository,
  });

  final _SignalTarget target;
  final ChainSignalTexts texts;
  final ChainSignalsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final action = target.text(texts);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target.label,
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
            key: target.editKey,
            tooltip: target.tooltip,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => _editSignal(context, repository!, target),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
      ],
    );
  }
}

class _DurationMetric extends StatelessWidget {
  const _DurationMetric({
    super.key,
    required this.label,
    required this.seconds,
  });
  final String label;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(_formatDuration(seconds), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  return [
    if (hours > 0) '$hours 小时',
    if (minutes > 0) '$minutes 分钟',
    if (remainingSeconds > 0 || seconds == 0) '$remainingSeconds 秒',
  ].join(' ');
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

  /// The chain whose flow shows the instruction; the Focus Marker itself is
  /// shared by both chains.
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
            '${mode.label}专注标志：${texts.focusMarker.isEmpty ? '尚未设置' : texts.focusMarker}',
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
      // Read the latest other field so editing one action preserves concurrent edits.
      final current = await widget.repository.get();
      await widget.repository.save(
        ChainSignalTexts(
          appointmentTriggerSignal: widget.target == _SignalTarget.appointment
              ? _controller.text
              : current.appointmentTriggerSignal,
          focusMarker: widget.target == _SignalTarget.marker
              ? _controller.text
              : current.focusMarker,
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
    title: Text(widget.target.dialogTitle),
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
