import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../tasks/task_models.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_date_format.dart';
import '../ui/pacta_error_text.dart';
import 'focus_flow_helpers.dart';
import 'focus_models.dart';

class AppointmentPreparationPage extends ConsumerStatefulWidget {
  const AppointmentPreparationPage({
    super.key,
    required this.appointment,
    required this.taskTitle,
  });

  final AppointmentPreparation appointment;
  final String taskTitle;

  @override
  ConsumerState<AppointmentPreparationPage> createState() =>
      _AppointmentPreparationPageState();
}

class _AppointmentPreparationPageState
    extends ConsumerState<AppointmentPreparationPage> {
  Timer? _timer;
  AppointmentPreparation? _current;
  List<Task>? _tasks;
  late FocusChainMode _mode;
  late String _taskId;
  late final TextEditingController _duration;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.appointment;
    _mode = widget.appointment.mode;
    _taskId = widget.appointment.taskId;
    _duration = TextEditingController(
      text: _minutesFor(widget.appointment.durationSeconds).toString(),
    );
    unawaited(_syncAppointmentNotification(widget.appointment));
    unawaited(_loadTasks());
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    try {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      final tasks = [
        for (final goal in goals)
          for (final task in goal.tasks)
            if ((!task.isComplete && !task.isDeleted) || task.id == _taskId)
              task,
      ];
      if (mounted) setState(() => _tasks = tasks);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    }
  }

  Future<void> _refresh() async {
    final current = await ref
        .read(focusRepositoryProvider)
        .getAppointment(widget.appointment.id);
    if (!mounted || current == null) return;
    if (current.isSucceeded) {
      final session = await ref
          .read(focusRepositoryProvider)
          .getSession(current.sessionId ?? current.id);
      if (!mounted || session == null) return;
      await ref
          .read(focusNotificationServiceProvider)
          .appointmentEnteredFocus(
            appointmentId: current.id,
            taskTitle: _taskTitle(current.taskId),
          );
      if (!mounted) return;
      unawaited(_syncFocusNotification(session));
      _timer?.cancel();
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => FocusSessionPage(
            session: session,
            taskTitle: _taskTitle(current.taskId),
          ),
        ),
      );
      return;
    }
    if (current.isFailed) {
      _timer?.cancel();
      unawaited(_syncAppointmentNotification(null));
    }
    // 每次轮询都重建：准备倒计时与进度条按 displayClock 的当前时刻前进，
    // 只在配置变化时刷新会让停表卡在初始 MM:SS。通知仍只跟随状态跳变。
    if (mounted) setState(() => _current = current);
  }

  Future<void> _syncAppointmentNotification(
    AppointmentPreparation? appointment,
  ) async {
    try {
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            appointment: appointment?.isActive == true ? appointment : null,
            taskTitle: appointment == null
                ? widget.taskTitle
                : _taskTitle(appointment.taskId),
          );
    } catch (_) {
      // A notification failure does not affect the appointment flow.
    }
  }

  Future<void> _syncFocusNotification(FocusSession session) async {
    try {
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            session: session.isUnfinished ? session : null,
            taskTitle: _taskTitle(session.taskId),
          );
    } catch (_) {
      // A notification failure does not affect the focus session.
    }
  }

  Future<void> _saveConfig() async {
    final current = _current;
    final minutes = int.tryParse(_duration.text.trim());
    if (current == null || !current.isActive) return;
    if (minutes == null || minutes <= 0) {
      setState(() => _error = '请输入大于 0 的分钟数。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(focusRepositoryProvider)
          .updateAppointment(
            appointmentId: current.id,
            taskId: _taskId,
            mode: _mode,
            duration: Duration(minutes: minutes),
          );
      if (mounted) setState(() => _current = updated);
      unawaited(_syncAppointmentNotification(updated));
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterEarly() async {
    final current = _current;
    if (current == null || !current.isActive || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .enterAppointmentEarly(current.id);
      if (!mounted) return;
      await ref
          .read(focusNotificationServiceProvider)
          .appointmentEnteredFocus(
            appointmentId: current.id,
            taskTitle: _taskTitle(session.taskId),
          );
      await _syncFocusNotification(session);
      if (!mounted) return;
      _timer?.cancel();
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => FocusSessionPage(
            session: session,
            taskTitle: _taskTitle(session.taskId),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelAppointment() async {
    final current = _current;
    if (current == null || !current.isActive || _busy) return;
    final reason = await showTextEditor(
      context,
      title: '取消预约准备',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    final pageRoute = ModalRoute.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(focusRepositoryProvider)
          .cancelAppointment(appointmentId: current.id, failureReason: reason);
      await _syncAppointmentNotification(null);
      if (mounted && pageRoute?.isActive == true) {
        if (pageRoute!.isCurrent) {
          pageRoute.navigator?.pop();
        } else {
          pageRoute.navigator?.removeRoute(pageRoute);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _taskTitle(String taskId) {
    for (final task in _tasks ?? const <Task>[]) {
      if (task.id == taskId) return taskDisplayTitle(task);
    }
    return taskId == widget.appointment.taskId ? widget.taskTitle : '原预约任务';
  }

  String _friendlyFocusError(Object error) => formatUserError(error);

  @override
  Widget build(BuildContext context) {
    final appointment = _current ?? widget.appointment;
    final now = ref.watch(displayClockProvider)().toUtc();
    final preparationSeconds = appointment.effectivePreparationSeconds;
    final remainingSeconds = appointment.isActive
        ? appointment.endsAt
              .difference(now)
              .inSeconds
              .clamp(0, preparationSeconds)
        : 0;
    final progress = preparationSeconds <= 0
        ? 0.0
        : 1 - (remainingSeconds / preparationSeconds);
    final tasks = _tasks;
    final canEdit = !_busy;
    final canProceed = !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('预约准备')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: PactaSpacing.pageInsets(context),
            children: [
              Text(
                _taskTitle(appointment.taskId),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                appointment.isActive
                    ? '本场准备 ${AppointmentPreparationDuration.describe(preparationSeconds)}，结束后自动进入专注，不需要再次点击或执行专注标志。'
                    : appointment.isFailed
                    ? '预约已取消，预约链当前记录已清零。'
                    : '预约已成功进入专注。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Text(
                appointment.isActive ? formatClock(remainingSeconds) : '00:00',
                style: Theme.of(context).textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              const SizedBox(height: 16),
              if (appointment.isActive)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '准备配置',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (tasks == null)
                          const Center(child: CircularProgressIndicator())
                        else
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue:
                                tasks.any((task) => task.id == _taskId)
                                ? _taskId
                                : null,
                            decoration: const InputDecoration(labelText: '任务'),
                            items: [
                              for (final task in tasks)
                                DropdownMenuItem(
                                  value: task.id,
                                  child: Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: !canEdit
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _taskId = value);
                                    }
                                  },
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<FocusChainMode>(
                          initialValue: _mode,
                          decoration: const InputDecoration(labelText: '专注模式'),
                          items: [
                            for (final mode in FocusChainMode.values)
                              DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ),
                          ],
                          onChanged: !canEdit
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _mode = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _duration,
                          enabled: canEdit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '专注时长（分钟）',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: canEdit ? _saveConfig : null,
                          child: const Text('保存配置（不重置准备时间）'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              if (appointment.isActive) ...[
                FilledButton(
                  onPressed: canProceed ? _enterEarly : null,
                  child: const Text('提前进入专注'),
                ),
                TextButton(
                  onPressed: canProceed ? _cancelAppointment : null,
                  child: const Text('取消预约并填写失败原因'),
                ),
                const Text(
                  '准备阶段不能暂停，也不限制你在现实中的行为。',
                  textAlign: TextAlign.center,
                ),
              ] else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回专注链'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    super.key,
    required this.session,
    required this.taskTitle,
  });

  final FocusSession session;
  final String taskTitle;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage> {
  Timer? _timer;
  FocusSession? _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.session;
    unawaited(_syncSessionNotification(widget.session));
    _refresh();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    final session = await ref
        .read(focusRepositoryProvider)
        .getSession(widget.session.id);
    if (!mounted || session == null) return;
    final previous = _current;
    // 倒计时文本与进度条取决于“现在”，所以每次轮询都要重建：
    // 只按 status/endsAt/pausedAt 跳变才刷新会让停表停在初始 MM:SS。
    setState(() => _current = session);
    // 已结算就停表：页面尚未退栈时不再每 250ms 轮询数据库。
    if (!session.isUnfinished) _timer?.cancel();
    // 通知与结束事件仍只跟随状态跳变，不能随每秒轮询重复推送。
    if (previous?.status != session.status ||
        previous?.endsAt != session.endsAt ||
        previous?.pausedAt != session.pausedAt) {
      if (previous?.isUnfinished == true && !session.isUnfinished) {
        unawaited(
          ref
              .read(focusNotificationServiceProvider)
              .sessionEnded(
                sessionId: session.id,
                appointmentId: session.appointmentId,
                taskTitle: widget.taskTitle,
                status: session.status,
              ),
        );
      }
      unawaited(_syncSessionNotification(session));
    }
  }

  Future<void> _syncSessionNotification(FocusSession? session) async {
    try {
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            session: session?.isUnfinished == true ? session : null,
            taskTitle: widget.taskTitle,
          );
    } catch (_) {
      // A notification failure does not affect the focus session.
    }
  }

  Future<void> _togglePause() async {
    final session = _current;
    if (session == null || _busy) return;
    String? ruleText;
    if (!session.isPaused) {
      final repository = ref.read(focusRepositoryProvider);
      final rules = await repository.getPrecedentRules();
      if (!mounted) return;
      ruleText = await showPrecedentRulePicker(
        context,
        repository: repository,
        rules: rules,
        confirmLabel: '确认暂停',
      );
      if (ruleText == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(focusRepositoryProvider);
      _current = session.isPaused
          ? await repository.resumeSession(session.id)
          : await repository.pauseSession(session.id, ruleText: ruleText!);
      await _syncSessionNotification(_current);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeEarly() async {
    final session = _current;
    if (session == null || !session.isUnfinished || _busy) return;
    final repository = ref.read(focusRepositoryProvider);
    final rules = await repository.getPrecedentRules();
    if (!mounted) return;
    final ruleText = await showPrecedentRulePicker(
      context,
      repository: repository,
      rules: rules,
      confirmLabel: '选择依据',
    );
    if (ruleText == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认提前完成？'),
        content: Text('本次专注将按实际有效时间完成，并生成一个专注节点。\n依据：$ruleText'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('提前完成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      _current = await ref
          .read(focusRepositoryProvider)
          .completeEarlySession(sessionId: session.id, ruleText: ruleText);
      await ref
          .read(focusNotificationServiceProvider)
          .sessionEnded(
            sessionId: session.id,
            appointmentId: session.appointmentId,
            taskTitle: widget.taskTitle,
            status: _current!.status,
          );
      await _syncSessionNotification(_current);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon() async {
    final session = _current;
    if (session == null || !session.isUnfinished || _busy) return;
    final reason = await showTextEditor(
      context,
      title: '放弃本次专注',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      _current = await ref
          .read(focusRepositoryProvider)
          .abandonSession(sessionId: session.id, failureReason: reason);
      await ref
          .read(focusNotificationServiceProvider)
          .sessionEnded(
            sessionId: session.id,
            appointmentId: session.appointmentId,
            taskTitle: widget.taskTitle,
            status: _current!.status,
          );
      await _syncSessionNotification(_current);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(formatUserError(error))));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _current ?? widget.session;
    final now = ref.watch(displayClockProvider)().toUtc();
    final reference = session.isPaused ? (session.pausedAt ?? now) : now;
    final remaining = session.endsAt.difference(reference);
    final remainingSeconds = remaining.inSeconds.clamp(
      0,
      session.durationSeconds,
    );
    final progress = session.durationSeconds == 0
        ? 1.0
        : 1 - (remainingSeconds / session.durationSeconds);
    final settled = !session.isUnfinished;
    return Scaffold(
      appBar: AppBar(title: const Text('专注进行中')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.taskTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(session.mode.label, textAlign: TextAlign.center),
                const SizedBox(height: 36),
                Text(
                  settled ? '00:00' : formatClock(remainingSeconds),
                  style: Theme.of(context).textTheme.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: settled ? 1 : progress),
                const SizedBox(height: 20),
                Text(
                  session.isFailed
                      ? '本次专注已失败，已保留有效投入时间。任务仍需你单独确认完成。\n失败原因：${session.failureReason ?? '未填写'}'
                      : session.isEarlyCompleted
                      ? '本次专注已获准提前完成，已生成一个专注节点并记录有效时间。\n依据：${session.completionRuleText ?? '未记录'}'
                      : session.status == FocusSessionStatus.completed
                      ? '本次专注已完成，已生成一个专注节点并记录有效时间。任务仍需你单独确认完成。'
                      : session.isPaused
                      ? '本次专注已暂停，暂停时间不计入有效投入。'
                      : '倒计时归零后自动结算。返回其他页面不会使本次专注失败。',
                  textAlign: TextAlign.center,
                ),
                if (session.isUnfinished) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _togglePause,
                        icon: Icon(
                          session.isPaused ? Icons.play_arrow : Icons.pause,
                          size: PactaIconSizes.sm,
                        ),
                        label: Text(session.isPaused ? '继续' : '暂停'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _completeEarly,
                        icon: const Icon(
                          Icons.check_circle_outline,
                          size: PactaIconSizes.sm,
                        ),
                        label: const Text('依据规则提前完成'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _abandon,
                        child: const Text('放弃本次专注'),
                      ),
                    ],
                  ),
                ],
                if (settled) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回上一页'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatClock(int seconds) => formatPactaClock(seconds);

int _minutesFor(int seconds) => (seconds / 60).ceil();
