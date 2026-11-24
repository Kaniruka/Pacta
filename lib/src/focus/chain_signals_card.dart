import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_grouped_list.dart';
import 'chain_signals_repository.dart';
import 'effective_duration_text.dart';
import 'focus_models.dart';
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
    this.appointmentStatistics,
  });

  final ChainSignalsRepository? repository;
  final List<FocusChainRecord> records;
  final AppointmentChainRecord? appointmentRecord;
  final Map<FocusChainMode, FocusSessionStatistics> statistics;

  /// 预约链的实际准备耗时统计；为空时按 0 秒显示，保持隔离组件调用兼容。
  ///
  /// 与专注链共用 [FocusSessionStatistics]，所以「累计/平均」的口径与
  /// 专注历史时间轴完全同源。
  final FocusSessionStatistics? appointmentStatistics;

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
    final elite = _recordFor(FocusChainMode.elite);
    final regular = _recordFor(FocusChainMode.regular);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 链记录卡：M3 Expressive 分段卡片。三条链各自成段，段间只留透明
        // 间隙；表头行已删除，数字直接跟在自己的链名下读，不再靠表格列对齐。
        PactaGroupedList(
          key: const ValueKey('focus-chain-table'),
          children: [
            _chainSegment(
              context,
              label: FocusChainMode.elite.label,
              icon: Icons.shield_outlined,
              current: elite?.currentConsecutive ?? 0,
              best: elite?.bestConsecutive ?? 0,
              statistics: statistics[FocusChainMode.elite],
              // 口径说明只挂在第一组「累计/平均」上：说明的正是这一行数字。
              note: focusDurationRule,
              noteKey: focusChainNoteKey,
            ),
            _chainSegment(
              context,
              label: FocusChainMode.regular.label,
              icon: Icons.all_inclusive,
              current: regular?.currentConsecutive ?? 0,
              best: regular?.bestConsecutive ?? 0,
              statistics: statistics[FocusChainMode.regular],
            ),
            _chainSegment(
              context,
              label: '预约链',
              icon: Icons.schedule_outlined,
              current: appointmentRecord?.currentConsecutive ?? 0,
              best: appointmentRecord?.bestConsecutive ?? 0,
              statistics: appointmentStatistics,
              isAppointment: true,
              note: appointmentEntryRule,
              noteKey: appointmentNoteKey,
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

  /// 一条链的分段卡片：左侧图标井 + 双行信息，右侧双行数值。
  ///
  /// 三条链共用同一套内边距与两行结构：链名行 + 「累计/平均」行；右侧是
  /// 「当前连续 / 历史最高」两行数值。三张卡的高度因此由同一套行高决定，
  /// 不再需要原来的「当前连续 | 历史最高」表头表格。
  Widget _chainSegment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required int current,
    required int best,
    required FocusSessionStatistics? statistics,
    bool isAppointment = false,
    String? note,
    Key? noteKey,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final captionStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    // 说明与它解释的内容绑在一起：点按链名、行内 ⓘ 或「累计/平均」都能展开。
    final explainedNote = isAppointment ? null : note;
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
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
            // 说明图标紧跟链名：与信号卡的标签行同构，也不和「累计/平均」
            // 抢同一行的宽度（窄屏下那会直接把时长挤到第二行）。
            if (note != null) ...[
              const SizedBox(width: PactaSpacing.xs),
              _infoGlyph(context),
            ],
          ],
        ),
        const SizedBox(height: PactaSpacing.xxs),
        // 「累计/平均」三条链都保留：预约链不再是只有连续次数、没有时长的
        // 孤岛；说明覆盖整列信息，ⓘ 与数值同属一条提示。
        _durationRow(context, label: label, statistics: statistics),
      ],
    );
    final content = Padding(
      // 纵向 8dp：两条文本行再加 12dp 上下内边距会让三张卡多出 12dp，
      // 360×800 的预约恢复态首屏因此要多滚一截。
      padding: const EdgeInsets.symmetric(
        horizontal: PactaSpacing.lg,
        vertical: PactaSpacing.sm,
      ),
      child: Row(
        children: [
          _chainIconWell(context, icon, emphasised: !isAppointment),
          // 图标井与信息列之间 8dp：12dp 时窄屏上精锐链的长时长会把
          // 「累计/平均」折成两行，三张卡立刻高矮不一。
          const SizedBox(width: PactaSpacing.sm),
          Expanded(
            child: explainedNote == null
                ? info
                : _explained(
                    noteKey: noteKey,
                    note: explainedNote,
                    child: info,
                  ),
          ),
          const SizedBox(width: PactaSpacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                label: '$label当前连续 $current 次',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$current', style: _primaryValueStyle(theme)),
                    const SizedBox(width: PactaSpacing.xxs),
                    Text('连续', style: captionStyle),
                  ],
                ),
              ),
              const SizedBox(height: PactaSpacing.xxs),
              Semantics(
                label: '$label历史最高 $best 次',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('最高', style: captionStyle),
                    const SizedBox(width: PactaSpacing.xxs),
                    Text(
                      '$best',
                      style: captionStyle?.copyWith(
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    // 预约链的入口句覆盖整条链：命中区是整行，而不是 14dp 的图标本身。
    if (isAppointment && note != null) {
      return _explained(noteKey: noteKey, note: note, child: content);
    }
    return content;
  }

  /// 当前连续：主强调数字，字重 600 + 等宽数字。
  ///
  /// 字阶取 titleMedium 而不是 titleLarge：卡片只有两行，主数字再高出一档
  /// 会把整张卡拉高 4dp，三张卡就吃掉首屏一档间距；强调由字重与等宽数字
  /// 承担，不再靠压过链名的字阶。
  TextStyle? _primaryValueStyle(ThemeData theme) =>
      theme.textTheme.titleMedium?.copyWith(
        fontFeatures: const [ui.FontFeature.tabularFigures()],
        fontWeight: PactaFonts.semibold,
      );

  /// 「累计 / 平均」一行：三条链共用同一结构，只有时长文本不同。
  ///
  /// 一行放两段时长：段间距与「标签 / 数值」间距都收到 2dp、字阶取
  /// labelSmall，给窄屏的长时长多留出一点宽度，尽量不折成第二行。
  Widget _durationRow(
    BuildContext context, {
    required String label,
    required FocusSessionStatistics? statistics,
  }) {
    return Wrap(
      spacing: PactaSpacing.xxs,
      runSpacing: PactaSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
    );
  }

  /// 说明与它解释的那一行绑在一起：点按整行显示提示。
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
      spacing: PactaSpacing.xxs,
      runSpacing: PactaSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(
          formatEffectiveDuration(seconds),
          style: theme.textTheme.labelSmall?.copyWith(
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
