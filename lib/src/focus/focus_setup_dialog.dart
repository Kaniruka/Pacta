import 'dart:async';

import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter/widgets.dart' as flutter show FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../tasks/task_models.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_error_text.dart';
import 'chain_signals_card.dart';
import 'chain_signals_repository.dart';
import 'focus_models.dart';

/// 预约准备弹窗里的规则说明：挂在信息卡的行内 ⓘ 上，点开即可读全文。
///
/// 这句话原先裸露在弹窗底部，占用一整段高度；现在只作为提示内容存在，
/// 弹窗本身保持紧凑，底部只承担三个操作按钮。
const focusSetupInstructionsMessage =
    '触发信号和专注标志由你执行。可立即开始专注，或先按本场准备时长准备；'
    '准备结束自动进入专注，无需再次执行专注标志。';

class FocusSetupDialog extends ConsumerStatefulWidget {
  const FocusSetupDialog({
    super.key,
    required this.task,
    required this.initialMode,
  });

  final Task task;
  final FocusChainMode initialMode;

  @override
  ConsumerState<FocusSetupDialog> createState() => _FocusSetupDialogState();
}

class _FocusSetupDialogState extends ConsumerState<FocusSetupDialog> {
  final _errorKey = GlobalKey();
  final _durationKey = GlobalKey();
  final _durationFocus = flutter.FocusNode();
  late FocusChainMode _mode;
  late final TextEditingController _duration;

  /// 预约准备时长只有一个来源：始终可见的数字输入框。
  ///
  /// 快捷 chip 只是预填，不再有“自定义”开关，因此输入框与按钮文案
  /// 永远反映同一份值，不存在两套状态互相覆盖。
  late final TextEditingController _preparation;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _durationFocus.addListener(_revealFocusedDuration);
    _mode = widget.initialMode;
    _duration = TextEditingController(text: '25');
    _preparation = TextEditingController(
      text: '${AppointmentPreparationDuration.defaultMinutes}',
    );
  }

  @override
  void dispose() {
    _durationFocus.dispose();
    _duration.dispose();
    _preparation.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      _showDurationError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // The first focus flow is a real user action that relies on the reminder
    // notification, so this is where the permission is requested once.
    unawaited(
      ref
          .read(focusNotificationServiceProvider)
          .ensureNotificationPermissionForUse(),
    );
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .startSession(
            taskId: widget.task.id,
            mode: _mode,
            duration: Duration(minutes: minutes),
          );
      if (mounted) Navigator.of(context).pop(session);
    } catch (error) {
      if (mounted) {
        setState(() => _error = formatUserError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 本场准备时长；输入框里的值非法时返回 null，由界面就地拒绝而不是截断。
  Duration? _resolvedPreparation() {
    final minutes = int.tryParse(_preparation.text.trim());
    if (minutes == null) return null;
    try {
      return AppointmentPreparationDuration.validateMinutes(minutes);
    } on ArgumentError {
      return null;
    }
  }

  /// 输入框里当前值对应的快捷档位；其他数字（如 7）不命中任何 chip。
  int? get _preparationPreset {
    final minutes = int.tryParse(_preparation.text.trim());
    return AppointmentPreparationDuration.presets.contains(minutes)
        ? minutes
        : null;
  }

  String get _preparationButtonLabel {
    final preparation = _resolvedPreparation();
    if (preparation == null) return '开始准备';
    return '开始准备（${preparation.inMinutes}分钟）';
  }

  void _selectPreparationPreset(int minutes) {
    if (_busy) return;
    setState(() {
      _preparation.text = '$minutes';
      _preparation.selection = TextSelection.collapsed(
        offset: _preparation.text.length,
      );
      _error = null;
    });
  }

  void _showPreparationError() {
    setState(() => _error = AppointmentPreparationDuration.invalidMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _errorKey.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  Future<void> _startAppointment() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      _showDurationError();
      return;
    }
    final preparation = _resolvedPreparation();
    if (preparation == null) {
      _showPreparationError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    unawaited(
      ref
          .read(focusNotificationServiceProvider)
          .ensureNotificationPermissionForUse(),
    );
    try {
      final appointment = await ref
          .read(focusRepositoryProvider)
          .startAppointment(
            taskId: widget.task.id,
            mode: _mode,
            duration: Duration(minutes: minutes),
            preparation: preparation,
          );
      if (mounted) Navigator.of(context).pop(appointment);
    } catch (error) {
      if (mounted) {
        setState(() => _error = formatUserError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 单个快捷档位：等宽、单行、无勾号占位。
  ///
  /// 选中时 ChoiceChip 默认会插入一个勾号，把芯片撑宽后三枚档位就会换行；
  /// 这里关掉勾号、清零内边距，并用 FittedBox 兜住放大字号，使三枚档位在
  /// 360dp 手机弹窗里始终严格同排等宽。
  Widget _presetChip(BuildContext context, int minutes) => ChoiceChip(
    key: ValueKey('focus-preparation-preset-$minutes'),
    showCheckmark: false,
    padding: EdgeInsets.zero,
    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    label: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$minutes 分钟', maxLines: 1, softWrap: false),
      ),
    ),
    selected: _preparationPreset == minutes,
    onSelected: _busy ? null : (_) => _selectPreparationPreset(minutes),
  );

  void _showDurationError() {
    setState(() => _error = '请输入大于 0 的分钟数。');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _errorKey.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  void _revealFocusedDuration() {
    if (!_durationFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_durationFocus.hasFocus) return;
      final context = _errorKey.currentContext ?? _durationKey.currentContext;
      if (context != null) Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('开始专注'),
    content: NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _revealFocusedDuration();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.task.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: PactaSpacing.sm),
              DropdownButtonFormField<FocusChainMode>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: '专注模式'),
                items: [
                  for (final mode in FocusChainMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _mode = value!),
              ),
              const SizedBox(height: PactaSpacing.sm),
              TextField(
                key: _durationKey,
                focusNode: _durationFocus,
                controller: _duration,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '时长（分钟）'),
              ),
              const SizedBox(height: PactaSpacing.sm),
              // 输入框在上、快捷档位在下：先看到要填什么，再看到可以直接点的档位。
              // 输入框始终可见：快捷档位只是预填，手动输入也是同一份状态。
              TextField(
                controller: _preparation,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '预约准备时长（分钟）',
                  helperText: '1–60 分钟；超出范围或非整数不会开始预约。',
                  // 360dp 弹窗里这行提示放不进单行：允许两行，不要省略号。
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: PactaSpacing.xs),
              // 三个档位强制单排：360dp 弹窗内容区约 232dp，等宽 Expanded +
              // 去掉选中勾号占位 + FittedBox 缩放，任何字号下都不折行、不溢出。
              Row(
                spacing: PactaSpacing.sm,
                children: [
                  for (final minutes in AppointmentPreparationDuration.presets)
                    Expanded(child: _presetChip(context, minutes)),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: PactaSpacing.sm),
                Text(
                  _error!,
                  key: _errorKey,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (ref.watch(chainSignalsRepositoryProvider)
                  case final repository?) ...[
                const SizedBox(height: PactaSpacing.md),
                _SetupInstructions(repository: repository, mode: _mode),
              ],
            ],
          ),
        ),
      ),
    ),
    // 全宽纵向排列：主操作、次操作、取消各占一行，右下角不再折行成阶梯。
    actions: [
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _start,
            child: _busy
                ? const SizedBox.square(
                    dimension: PactaIconSizes.sm,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('开始倒计时'),
          ),
          const SizedBox(height: PactaSpacing.sm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _startAppointment,
            child: Text(_preparationButtonLabel),
          ),
          const SizedBox(height: PactaSpacing.xs),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    ],
  );
}

/// 预约与专注标志的规则说明卡：紧凑双行键值表 + 行内 ⓘ。
///
/// 整张卡片就是提示的命中区：标题行与 48dp 的大图标行都不再占高度，
/// 弹窗只保留「触发信号」「专注标志」两行事实，点按卡片展开完整规则。
class _SetupInstructions extends StatelessWidget {
  const _SetupInstructions({required this.repository, required this.mode});

  final ChainSignalsRepository repository;
  final FocusChainMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      key: const ValueKey('focus-setup-instructions-info'),
      message: focusSetupInstructionsMessage,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      child: Container(
        key: const ValueKey('focus-setup-instructions'),
        padding: const EdgeInsets.fromLTRB(
          PactaSpacing.md,
          PactaSpacing.sm,
          PactaSpacing.md,
          PactaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(PactaSpacing.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ChainSignalInstructions(
                repository: repository,
                mode: mode,
              ),
            ),
            const SizedBox(width: PactaSpacing.sm),
            Icon(
              Icons.info_outline,
              size: PactaIconSizes.micro,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
