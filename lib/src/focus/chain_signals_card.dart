import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';
import 'chain_signals_repository.dart';
import 'focus_models.dart';
import 'effective_duration_text.dart';
import 'focus_statistics.dart';

/// The two commitment actions the overview can edit.
///
/// The Focus Marker is shared by both Focus Chains, so it has one entry point;
/// the Appointment Chain keeps its own Trigger Signal.
enum _SignalTarget {
  marker(
    label: '专注标志',
    dialogTitle: '专注标志',
    tooltip: '编辑专注标志',
    helper: '精锐链与普通链共用，连续记录各自独立。',
  ),
  appointment(label: '触发信号', dialogTitle: '触发信号', tooltip: '编辑预约链触发信号');

  const _SignalTarget({
    required this.label,
    required this.dialogTitle,
    required this.tooltip,
    this.helper,
  });

  final String label;
  final String dialogTitle;
  final String tooltip;

  /// 行下方的说明；只有共用关系的动作需要。
  final String? helper;

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
              padding: EdgeInsets.only(bottom: PactaSpacing.md),
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
    Widget header(String text) =>
        Text(text, textAlign: TextAlign.right, style: columnLabel);
    final elite = _recordFor(FocusChainMode.elite);
    final regular = _recordFor(FocusChainMode.regular);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const ValueKey('focus-chain-table'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PactaSpacing.md,
              PactaSpacing.sm,
              PactaSpacing.md,
              PactaSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 表头与数据行共用同一行结构与同一组 flex，
                // 右对齐边界由布局本身保证，不靠各处比例碰巧一致。
                _metricRow(
                  leading: const SizedBox.shrink(),
                  current: header('当前连续'),
                  best: header('历史最高'),
                ),
                _chainBlock(
                  context,
                  label: FocusChainMode.elite.label,
                  icon: Icons.shield_outlined,
                  record: elite,
                  statistics: statistics[FocusChainMode.elite],
                ),
                _chainBlock(
                  context,
                  label: FocusChainMode.regular.label,
                  icon: Icons.all_inclusive,
                  record: regular,
                  statistics: statistics[FocusChainMode.regular],
                ),
                _chainBlock(
                  context,
                  label: '预约链',
                  icon: Icons.schedule_outlined,
                  appointment: appointmentRecord,
                  isAppointment: true,
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: PactaSpacing.xxs,
                    top: PactaSpacing.xxs,
                  ),
                  child: Text(
                    '累计与平均包含失败专注的有效时间，不含暂停。',
                    key: const ValueKey('focus-chain-footnote'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: PactaSpacing.md),
        Card(
          key: const ValueKey('focus-chain-signals'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SignalAction(
                target: _SignalTarget.marker,
                texts: texts,
                repository: repository,
              ),
              _SignalAction(
                target: _SignalTarget.appointment,
                texts: texts,
                repository: repository,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 三条链共用的列：名称 3 份、当前连续 2 份、历史最高 2 份。
  Widget _metricRow({
    required Widget leading,
    required Widget current,
    required Widget best,
  }) => Row(
    children: [
      Expanded(flex: 3, child: leading),
      Expanded(flex: 2, child: current),
      Expanded(flex: 2, child: best),
    ],
  );

  /// One aligned chain row: name on the left, current and best streak on the
  /// right, and its footnote on a wrapped line underneath.
  Widget _chainBlock(
    BuildContext context, {
    required String label,
    required IconData icon,
    FocusChainRecord? record,
    FocusSessionStatistics? statistics,
    AppointmentChainRecord? appointment,
    bool isAppointment = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final footnoteStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final current =
        appointment?.currentConsecutive ?? record?.currentConsecutive ?? 0;
    final best = appointment?.bestConsecutive ?? record?.bestConsecutive ?? 0;
    final pending =
        appointment?.hasPendingReview ?? record?.hasPendingReview ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: PactaSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _metricRow(
            leading: Row(
              children: [
                Icon(icon, size: 18, color: colors.primary),
                const SizedBox(width: PactaSpacing.sm),
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
            current: _metricValue(
              '$current',
              valueStyle,
              '$label当前连续 $current 次',
            ),
            best: _metricValue('$best', valueStyle, '$label历史最高 $best 次'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: PactaSpacing.xxs),
            child: Wrap(
              spacing: PactaSpacing.sm,
              runSpacing: PactaSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (pending)
                  Text('记录待核对', style: footnoteStyle)
                else if (isAppointment)
                  Text('主动预约后进入准备', style: footnoteStyle),
                // 普通链即使还没有统计也要显示 0，不能因为缺省数据少一行。
                if (!isAppointment) ...[
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricValue(String value, TextStyle? style, String semanticsLabel) =>
      Padding(
        padding: const EdgeInsets.only(left: PactaSpacing.sm),
        child: Semantics(
          label: semanticsLabel,
          excludeSemantics: true,
          child: Text(value, textAlign: TextAlign.right, style: style),
        ),
      );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PactaSpacing.lg,
        PactaSpacing.xs,
        PactaSpacing.sm,
        PactaSpacing.xs,
      ),
      // 尾部图标按行内容垂直居中，不再落在文字基线下方。
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  target.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: PactaSpacing.xxs),
                Text(
                  action.isEmpty ? '尚未设置' : action,
                  style: theme.textTheme.bodyMedium,
                ),
                if (target.helper case final helper?) ...[
                  const SizedBox(height: PactaSpacing.xxs),
                  Text(
                    helper,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (repository != null)
            IconButton(
              key: target.editKey,
              tooltip: target.tooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _editSignal(context, repository!, target, texts),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
        ],
      ),
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
      spacing: PactaSpacing.xs,
      runSpacing: PactaSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(
          formatEffectiveDuration(seconds),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

Future<void> _editSignal(
  BuildContext context,
  ChainSignalsRepository repository,
  _SignalTarget target,
  ChainSignalTexts texts,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      _SignalEditor(repository: repository, texts: texts, target: target),
);

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
          const SizedBox(height: PactaSpacing.sm),
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
            key: const ValueKey('focus-signal-field'),
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '承诺动作',
              hintText: '例如：戴上指定耳机',
            ),
          ),
          // 说明不放进 InputDecoration.helperText：光标水滴会压在它上面。
          Padding(
            padding: const EdgeInsets.only(top: PactaSpacing.md),
            child: Text(
              widget.target == _SignalTarget.marker
                  ? '精锐链与普通链共用这一动作，两条链的连续记录仍各自独立。留空可清除设置，不影响已有记录。'
                  : '留空可清除设置，不影响已有记录。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: PactaSpacing.sm),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
