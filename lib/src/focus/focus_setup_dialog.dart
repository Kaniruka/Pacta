import 'dart:async';

import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter/widgets.dart' as flutter show FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../tasks/task_models.dart';
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
              const SizedBox(height: PactaSpacing.md),
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
              const SizedBox(height: PactaSpacing.md),
              TextField(
                key: _durationKey,
                focusNode: _durationFocus,
                controller: _duration,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '时长（分钟）'),
              ),
              const SizedBox(height: PactaSpacing.md),
              Text('预约准备时长', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: PactaSpacing.sm),
              Wrap(
                spacing: PactaSpacing.sm,
                runSpacing: PactaSpacing.xs,
                children: [
                  for (final minutes in AppointmentPreparationDuration.presets)
                    ChoiceChip(
                      label: Text('$minutes 分钟'),
                      selected: _preparationPreset == minutes,
                      onSelected: _busy
                          ? null
                          : (_) => _selectPreparationPreset(minutes),
                    ),
                ],
              ),
              const SizedBox(height: PactaSpacing.sm),
              // 输入框始终可见：快捷档位只是预填，手动输入也是同一份状态。
              TextField(
                controller: _preparation,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '预约准备时长（分钟）',
                  helperText: '1–60 分钟；超出范围或非整数不会开始预约。',
                ),
                onChanged: (_) => setState(() => _error = null),
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
                    dimension: 18,
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

/// 预约与专注标志的规则说明卡：浅色信息容器 + 行内 ⓘ。
///
/// 说明不再裸露成三行正文；信息量仍在，弹窗高度由信息卡承担，
/// 44/48dp 的点击区域挂在图标上，触摸与读屏都能命中。
class _SetupInstructions extends StatelessWidget {
  const _SetupInstructions({required this.repository, required this.mode});

  final ChainSignalsRepository repository;
  final FocusChainMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: const ValueKey('focus-setup-instructions'),
      padding: const EdgeInsets.fromLTRB(
        PactaSpacing.md,
        PactaSpacing.xs,
        PactaSpacing.xs,
        PactaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(PactaSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本场准备说明',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Tooltip(
                key: const ValueKey('focus-setup-instructions-info'),
                message: focusSetupInstructionsMessage,
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 8),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          ChainSignalInstructions(repository: repository, mode: mode),
          const SizedBox(height: PactaSpacing.xs),
        ],
      ),
    );
  }
}
