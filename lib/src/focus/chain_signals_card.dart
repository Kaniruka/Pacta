import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_grouped_list.dart';
import 'chain_signals_repository.dart';
import 'focus_models.dart';
import 'effective_duration_text.dart';
import 'focus_statistics.dart';

/// 时长统计口径：指标卡提示、设备测试与文案测试共用这一句，避免各写一份。
const focusDurationRule = '累计与平均包含失败专注的有效时间，不含暂停。';

/// 共用动作的完整规则句：信号卡提示与测试共用一份。
const sharedFocusMarkerRule = '精锐链与普通链共用这一动作，两条链的连续记录仍各自独立。';

/// 预约链的入口说明：挂在链名所在行，说明预约成立后的下一步。
const appointmentEntryRule = '主动预约后进入准备';

/// 编辑弹窗里的共用动作说明：既说清共用关系，也说清留空的结果。
const sharedSignalHelperText = '精锐链与普通链共用，连续记录各自独立。留空即清除，已有记录不变。';

/// 非共用动作的弹窗说明：只说明留空的结果。
const singleSignalHelperText = '留空即清除，已有记录不变。';

/// 累计与平均口径提示的键：卡片与测试共用。
const focusChainNoteKey = ValueKey('focus-chain-note');

/// 预约链入口提示的键：卡片与测试共用。
const appointmentNoteKey = ValueKey('focus-chain-appointment-note');

/// 柔色圆底图标井：链名与承诺动作共用同一档视觉节奏。
///
/// 图标本身取 [PactaIconSizes.compact]，圆底 32dp；主链用主色容器，
/// 预约链与次级动作退到第二层容器，层级由底色而不是描边表达。
Widget _chainIconWell(
  BuildContext context,
  IconData icon, {
  required bool emphasised,
}) {
  final colors = Theme.of(context).colorScheme;
  final background = emphasised
      ? colors.primaryContainer
      : colors.secondaryContainer;
  final foreground = emphasised
      ? colors.onPrimaryContainer
      : colors.onSecondaryContainer;
  return Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Icon(icon, size: PactaIconSizes.compact, color: foreground),
  );
}

/// The two commitment actions the overview can edit.
///
/// The Focus Marker is shared by both Focus Chains, so it has one entry point;
/// the Appointment Chain keeps its own Trigger Signal.
enum _SignalTarget {
  marker(
    label: '专注标志',
    dialogTitle: '专注标志',
    tooltip: '编辑专注标志',
    icon: Icons.flag_outlined,
    note: sharedFocusMarkerRule,
  ),
  appointment(
    label: '触发信号',
    dialogTitle: '触发信号',
    tooltip: '编辑预约链触发信号',
    icon: Icons.notifications_outlined,
  );

  const _SignalTarget({
    required this.label,
    required this.dialogTitle,
    required this.tooltip,
    required this.icon,
    this.note,
  });

  final String label;
  final String dialogTitle;
  final String tooltip;
  final IconData icon;

  /// 作为行内提示展示的规则句；只有共用关系的动作需要。
  final String? note;

  String text(ChainSignalTexts texts) => switch (this) {
    marker => texts.focusMarker,
    appointment => texts.appointmentTriggerSignal,
  };

  Key get editKey => ValueKey('focus-signal-edit-$name');

  /// 行内提示的 Key：每个动作一个独立语义节点。
  Key get noteKey => ValueKey('focus-signal-note-$name');
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
        // 链记录卡：分组白底 + 1dp hairline 分隔，图标井与主次数字分层。
        PactaGroupedList(
          key: const ValueKey('focus-chain-table'),
          children: [
            // 表头与数据行共用同一行结构与同一组 flex，
            // 右对齐边界由布局本身保证，不靠各处比例碰巧一致。
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PactaSpacing.lg,
                PactaSpacing.xs,
                PactaSpacing.lg,
                PactaSpacing.xxs,
              ),
              child: _metricRow(
                leading: const SizedBox.shrink(),
                current: header('当前连续'),
                best: header('历史最高'),
              ),
            ),
            _chainBlock(
              context,
              label: FocusChainMode.elite.label,
              icon: Icons.shield_outlined,
              record: elite,
              statistics: statistics[FocusChainMode.elite],
              // 口径说明只挂在第一组「累计/平均」上：说明的正是这一行数字。
              footnoteNote: focusDurationRule,
              footnoteNoteKey: focusChainNoteKey,
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
              titleNote: appointmentEntryRule,
              titleNoteKey: appointmentNoteKey,
            ),
          ],
        ),
        const SizedBox(height: PactaSpacing.sm),
        // 信号卡：与「下必为例」入口同一节奏的分组列表。
        PactaGroupedList(
          key: const ValueKey('focus-chain-signals'),
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
      ],
    );
  }

  /// 三条链共用的列：名称 4 份、当前连续 2 份、历史最高 2 份。
  Widget _metricRow({
    required Widget leading,
    required Widget current,
    required Widget best,
  }) => Row(
    children: [
      Expanded(flex: 4, child: leading),
      Expanded(flex: 2, child: current),
      Expanded(flex: 2, child: best),
    ],
  );

  /// One aligned chain row: tinted icon well, name and streak values on one
  /// line, optional detail underneath, with each explanation attached to the
  /// row it describes.
  Widget _chainBlock(
    BuildContext context, {
    required String label,
    required IconData icon,
    FocusChainRecord? record,
    FocusSessionStatistics? statistics,
    AppointmentChainRecord? appointment,
    bool isAppointment = false,
    String? footnoteNote,
    Key? footnoteNoteKey,
    String? titleNote,
    Key? titleNoteKey,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final footnoteStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final current =
        appointment?.currentConsecutive ?? record?.currentConsecutive ?? 0;
    final best = appointment?.bestConsecutive ?? record?.bestConsecutive ?? 0;
    final footnotes = _footnoteChildren(
      label: label,
      isAppointment: isAppointment,
      statistics: statistics,
      style: footnoteStyle,
    );
    final hasDetail = footnoteNote != null || footnotes.isNotEmpty;
    final chainRow = Padding(
      // 三行共用一个紧凑行高：图标井 32dp + 上下 4dp，正好读成一档 40dp 行。
      padding: const EdgeInsets.fromLTRB(
        PactaSpacing.lg,
        PactaSpacing.xs,
        PactaSpacing.lg,
        PactaSpacing.xs,
      ),
      child: _metricRow(
        leading: Row(
          children: [
            _chainIconWell(context, icon, emphasised: !isAppointment),
            const SizedBox(width: PactaSpacing.md),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 链名保持 titleMedium 的 medium；右侧数字用 semibold
                // 单独强调，层级不再靠整行加粗。
                style: theme.textTheme.titleMedium,
              ),
            ),
            // 提示挂在整行上，图标紧跟链名，与信号卡的标签行同构。
            if (titleNote != null) ...[
              const SizedBox(width: PactaSpacing.xs),
              _infoGlyph(context),
            ],
          ],
        ),
        current: _metricValue(
          '$current',
          _primaryValueStyle(theme),
          '$label当前连续 $current 次',
        ),
        best: _metricValue(
          '$best',
          _secondaryValueStyle(theme),
          '$label历史最高 $best 次',
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titleNote case final note?)
          _explained(noteKey: titleNoteKey, note: note, child: chainRow)
        else
          chainRow,
        if (hasDetail)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PactaSpacing.lg,
              0,
              PactaSpacing.lg,
              PactaSpacing.xs,
            ),
            child: _withNote(
              context,
              noteKey: footnoteNoteKey,
              note: footnoteNote,
              child: footnotes.isEmpty
                  ? null
                  : Wrap(
                      spacing: PactaSpacing.sm,
                      runSpacing: PactaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: footnotes,
                    ),
            ),
          ),
      ],
    );
  }

  /// 当前连续：主强调数字，字阶更大、字重 600。
  TextStyle? _primaryValueStyle(ThemeData theme) =>
      theme.textTheme.titleLarge?.copyWith(
        fontFeatures: const [ui.FontFeature.tabularFigures()],
        fontWeight: PactaFonts.semibold,
      );

  /// 历史最高：次级数字，字阶收一档并退到 onSurfaceVariant。
  TextStyle? _secondaryValueStyle(ThemeData theme) =>
      theme.textTheme.titleMedium?.copyWith(
        fontFeatures: const [ui.FontFeature.tabularFigures()],
        fontWeight: PactaFonts.medium,
        color: theme.colorScheme.onSurfaceVariant,
      );

  /// 说明与它解释的那一行绑在一起：点按整行显示提示。
  Widget _withNote(
    BuildContext context, {
    Key? noteKey,
    required String? note,
    Widget? child,
  }) {
    if (note == null) return child ?? const SizedBox.shrink();
    return _explained(
      noteKey: noteKey,
      note: note,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (child case final content?) ...[
            Flexible(child: content),
            const SizedBox(width: PactaSpacing.xs),
          ],
          _infoGlyph(context),
        ],
      ),
    );
  }

  /// 提示自带独立语义节点：同一容器内的多条提示会并成一个节点，只有一条能被读出。
  Widget _explained({
    Key? noteKey,
    required String note,
    required Widget child,
  }) => Semantics(
    container: true,
    child: Tooltip(
      key: noteKey,
      message: note,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      child: child,
    ),
  );

  Icon _infoGlyph(BuildContext context) => Icon(
    Icons.info_outline,
    size: PactaIconSizes.micro,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  List<Widget> _footnoteChildren({
    required String label,
    required bool isAppointment,
    required FocusSessionStatistics? statistics,
    required TextStyle? style,
  }) {
    return [
      if (!isAppointment) ...[
        _DurationMetric(
          key: ValueKey('focus-chain-stat-$label-累计'),
          label: '累计',
          seconds: statistics?.totalDurationSeconds ?? 0,
        ),
        _DurationMetric(
          key: ValueKey('focus-chain-stat-$label-平均'),
          label: '平均',
          seconds: statistics?.averageDurationSeconds.round() ?? 0,
        ),
      ],
    ];
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

  Widget _signalLabelRow(
    ThemeData theme,
    ColorScheme colors, {
    bool showGlyph = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        target.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      if (showGlyph) ...[
        const SizedBox(width: PactaSpacing.xs),
        Icon(
          Icons.info_outline,
          size: PactaIconSizes.micro,
          color: colors.onSurfaceVariant,
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final action = target.text(texts);
    return ConstrainedBox(
      // 与设置行同一节奏：行高不低于 52dp，图标井、标签与整行 48dp 操作位对齐。
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PactaSpacing.lg,
          PactaSpacing.xs,
          PactaSpacing.xs,
          PactaSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _chainIconWell(
              context,
              target.icon,
              emphasised: target == _SignalTarget.marker,
            ),
            const SizedBox(width: PactaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 规则句绑在标签上：整行可点，图标只是提示，不另占一行。
                  if (target.note case final note?)
                    Tooltip(
                      key: target.noteKey,
                      message: note,
                      triggerMode: TooltipTriggerMode.tap,
                      showDuration: const Duration(seconds: 8),
                      child: _signalLabelRow(theme, colors, showGlyph: true),
                    )
                  else
                    _signalLabelRow(theme, colors),
                  const SizedBox(height: PactaSpacing.xxs),
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
                onPressed: () =>
                    _editSignal(context, repository!, target, texts),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: PactaIconSizes.compact,
                ),
              ),
          ],
        ),
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
          style: theme.textTheme.bodySmall?.copyWith(
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
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

/// 一句「触发信号 / 专注标志」的紧凑双行说明。
///
/// 旧版把「预约触发信号：」「精锐链专注标志：」写进正文，两行都以长前缀开头，
/// 值被挤到右侧换行。现在标签退成同宽的弱化列，值占满剩余宽度；链名信息
/// 交给读屏语义，视觉上不再重复。
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(
        right: PactaSpacing.sm,
        bottom: PactaSpacing.xxs,
      ),
      child: Text(text, style: labelStyle),
    );
    Widget value(String text, String semanticsLabel) => Padding(
      padding: const EdgeInsets.only(bottom: PactaSpacing.xxs),
      child: Semantics(
        label: semanticsLabel,
        child: Text(text, style: valueStyle),
      ),
    );
    return StreamBuilder<ChainSignalTexts>(
      stream: repository.watch(),
      builder: (context, snapshot) {
        final texts = snapshot.data;
        if (texts == null) return const SizedBox.shrink();
        return Table(
          // 标签列按内容取宽，两行天然对齐；值列吃掉剩余宽度。
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            TableRow(
              children: [
                label('触发信号'),
                value(
                  texts.appointmentTriggerSignal.isEmpty
                      ? '未设置'
                      : texts.appointmentTriggerSignal,
                  '触发信号',
                ),
              ],
            ),
            TableRow(
              children: [
                label('专注标志'),
                value(
                  texts.focusMarker.isEmpty ? '未设置' : texts.focusMarker,
                  '${mode.label}专注标志',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
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
                  ? sharedSignalHelperText
                  : singleSignalHelperText,
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
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
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
