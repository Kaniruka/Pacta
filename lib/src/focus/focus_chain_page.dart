import 'dart:async';

import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../tasks/task_models.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_page_header.dart';
import 'chain_signals_card.dart';
import 'effective_duration_text.dart';
import 'focus_flow_helpers.dart';
import 'focus_models.dart';
import 'focus_repository.dart';
import 'focus_session_pages.dart';
import 'focus_setup_dialog.dart';
import 'focus_statistics.dart';

class FocusChainPage extends ConsumerStatefulWidget {
  const FocusChainPage({super.key});

  @override
  ConsumerState<FocusChainPage> createState() => _FocusChainPageState();
}

class _FocusChainPageState extends ConsumerState<FocusChainPage> {
  bool _openingTaskPicker = false;
  FocusRepository? _projectionRepository;
  String? _projectionSignature;
  late Future<List<FocusChainRecord>> _chainRecordsFuture;
  late Future<AppointmentChainRecord> _appointmentChainRecordFuture;
  late Stream<AppointmentPreparation?> _activeAppointmentStream;
  late Future<List<PrecedentRule>> _precedentRulesFuture;

  @override
  void initState() {
    super.initState();
    _activeAppointmentStream = ref
        .read(focusRepositoryProvider)
        .watchActiveAppointment();
    _precedentRulesFuture = ref
        .read(focusRepositoryProvider)
        .getPrecedentRules();
  }

  void _refreshActiveAppointment() {
    if (mounted) {
      setState(() {
        final repository = ref.read(focusRepositoryProvider);
        _activeAppointmentStream = repository.watchActiveAppointment();
        _appointmentChainRecordFuture = repository.getAppointmentChainRecord();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final signalsRepository = ref.watch(chainSignalsRepositoryProvider);
    return StreamBuilder<List<Goal>>(
      stream: taskRepository.watchGoals(includeDeleted: true),
      initialData: const [],
      builder: (context, snapshot) {
        final taskTitles = <String, String>{
          for (final goal in snapshot.data ?? const <Goal>[])
            for (final task in goal.tasks) task.id: taskDisplayTitle(task),
        };
        final allTasks = [
          for (final goal in snapshot.data ?? const <Goal>[]) ...goal.tasks,
        ];
        final tasks = [
          for (final goal in snapshot.data ?? const <Goal>[])
            if (!goal.isDeleted)
              for (final task in goal.tasks)
                if (!task.isDeleted && !task.isComplete) task,
        ];
        return StreamBuilder<List<FocusSession>>(
          stream: focusRepository.watchSessions(),
          initialData: const [],
          builder: (context, sessionsSnapshot) {
            final sessions = sessionsSnapshot.data ?? const <FocusSession>[];
            _updateProjectionFutures(focusRepository, sessions);
            final statistics = focusStatisticsByMode(sessions);
            final active = sessions
                .where((session) => session.isUnfinished)
                .firstOrNull;
            final activeTask = active == null
                ? null
                : allTasks
                      .where((task) => task.id == active.taskId)
                      .firstOrNull;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PactaSpacing.maxContentWidth,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        key: const ValueKey('focus-chain-list'),
                        padding: PactaSpacing.pageInsets(
                          context,
                          top: PactaSpacing.lg,
                          bottom: PactaSpacing.xs,
                        ),
                        children: [
                          PactaPageHeader(
                            title: '专注链',
                            trailing: TextButton.icon(
                              key: const ValueKey('focus-history-entry'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(64, 48),
                              ),
                              icon: const Icon(Icons.history, size: 20),
                              label: const Text('历史'),
                              onPressed: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => const FocusHistoryPage(),
                                ),
                              ),
                            ),
                          ),
                          if (active != null)
                            _FocusRecoveryStrip(
                              key: const ValueKey('focus-recovery-session'),
                              icon: Icons.timer_outlined,
                              title: '已有进行中的专注',
                              subtitle: activeTask == null
                                  ? '原任务'
                                  : taskDisplayTitle(activeTask),
                              trailing: FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(96, 48),
                                ),
                                onPressed: () => _openSession(
                                  active,
                                  taskTitles[active.taskId] ?? '原任务',
                                ),
                                child: const Text('返回专注'),
                              ),
                            ),
                          StreamBuilder<AppointmentPreparation?>(
                            key: const ValueKey('focus-active-appointment'),
                            stream: _activeAppointmentStream,
                            builder: (context, appointmentSnapshot) {
                              final appointment = appointmentSnapshot.data;
                              if (appointment == null) {
                                return const SizedBox.shrink();
                              }
                              final title =
                                  taskTitles[appointment.taskId] ?? '原预约任务';
                              return _FocusRecoveryStrip(
                                key: const ValueKey(
                                  'focus-recovery-appointment',
                                ),
                                icon: Icons.event_available,
                                title: '已有预约准备',
                                subtitle: appointment.isPendingReview
                                    ? '$title · 待核对'
                                    : title,
                                tone: _RecoveryStripTone.secondary,
                                actions: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: () =>
                                        _openAppointment(appointment, title),
                                    child: const Text('返回准备'),
                                  ),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: () =>
                                        _enterAppointment(appointment, title),
                                    child: const Text('提前进入专注'),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: () =>
                                        _cancelAppointment(appointment),
                                    child: const Text('取消预约'),
                                  ),
                                ],
                              );
                            },
                          ),
                          // 恢复条与下方统计表之间留出一档标准间距，
                          // 让恢复提示与数据卡各自成块，不再贴在一起。
                          const SizedBox(height: PactaSpacing.md),
                          FutureBuilder<List<FocusChainRecord>>(
                            future: _chainRecordsFuture,
                            builder: (context, recordSnapshot) {
                              if (recordSnapshot.hasError) {
                                return _recordReadError();
                              }
                              if (!recordSnapshot.hasData) {
                                return const LinearProgressIndicator();
                              }
                              return FutureBuilder<AppointmentChainRecord>(
                                future: _appointmentChainRecordFuture,
                                builder: (context, appointmentSnapshot) {
                                  if (appointmentSnapshot.hasError) {
                                    return _recordReadError();
                                  }
                                  if (!appointmentSnapshot.hasData) {
                                    return const LinearProgressIndicator();
                                  }
                                  return FocusChainOverview(
                                    repository: signalsRepository,
                                    records: recordSnapshot.data!,
                                    appointmentRecord: appointmentSnapshot.data,
                                    statistics: statistics,
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: PactaSpacing.sm),
                          _allowanceEntry(context),
                        ],
                      ),
                    ),
                    _FocusStartBar(
                      taskCount: tasks.length,
                      busy: _openingTaskPicker,
                      onPressed: _openTaskPicker,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 下必为例入口：首屏只负责进入完整管理页。
  ///
  /// 整张卡只有一个点击目标（行本身），不再让行内按钮重复一次同样的动作。
  Widget _allowanceEntry(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FutureBuilder<List<PrecedentRule>>(
      future: _precedentRulesFuture,
      builder: (context, snapshot) {
        final count = snapshot.data?.length;
        final subtitle = snapshot.hasError
            ? '读取失败，进入管理后可重试'
            : count == null
            ? '读取中…'
            : '$count 条持续许可';
        return Card(
          key: const ValueKey('focus-allowance-entry'),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const ValueKey('focus-allowance-manage'),
            contentPadding: const EdgeInsets.only(
              left: PactaSpacing.lg,
              right: PactaSpacing.sm,
            ),
            // 卡片标题保持 titleMedium；下方说明用 bodySmall，
            // 层级由字号与前景色区分。
            title: Text('下必为例', style: theme.textTheme.titleMedium),
            subtitle: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            onTap: _openPrecedentRules,
          ),
        );
      },
    );
  }

  Widget _recordReadError() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('链记录读取失败，请重试。'),
        TextButton(
          onPressed: () => setState(() {
            final repository = ref.read(focusRepositoryProvider);
            _chainRecordsFuture = repository.getChainRecords();
            _appointmentChainRecordFuture = repository
                .getAppointmentChainRecord();
          }),
          child: const Text('重试'),
        ),
      ],
    ),
  );

  void _updateProjectionFutures(
    FocusRepository repository,
    List<FocusSession> sessions,
  ) {
    final signature = sessions
        .map(
          (session) =>
              '${session.id}:${session.taskId}:${session.mode.storageValue}:'
              '${session.status.storageValue}:${session.reviewDisposition.storageValue}:'
              '${session.effectiveSeconds}:${session.completedAt}',
        )
        .join('|');
    if (identical(_projectionRepository, repository) &&
        _projectionSignature == signature) {
      return;
    }
    _projectionRepository = repository;
    _projectionSignature = signature;
    _chainRecordsFuture = repository.getChainRecords();
    _appointmentChainRecordFuture = repository.getAppointmentChainRecord();
  }

  Future<void> _openTaskPicker() async {
    if (_openingTaskPicker) return;
    setState(() => _openingTaskPicker = true);
    try {
      final repository = ref.read(focusRepositoryProvider);
      final activeSession = await repository.getActiveSession();
      final activeAppointment = activeSession == null
          ? await repository.getActiveAppointment()
          : null;
      final mode = activeSession == null && activeAppointment == null
          ? await repository.getLastMode()
          : FocusChainMode.regular;
      if (!mounted) return;
      final result =
          activeSession ??
          activeAppointment ??
          await Navigator.of(context).push<Object>(
            MaterialPageRoute<Object>(
              builder: (_) => FocusTaskPickerPage(initialMode: mode),
            ),
          );
      if (!mounted || result == null) return;
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      if (!mounted) return;
      if (result is FocusSession) {
        _openSession(result, findTaskTitle(goals, result.taskId) ?? '原任务');
      } else if (result is AppointmentPreparation) {
        await _openAppointment(
          result,
          findTaskTitle(goals, result.taskId) ?? '原预约任务',
        );
      }
      _refreshActiveAppointment();
    } catch (error) {
      if (mounted) showFocusError(context, error);
    } finally {
      if (mounted) setState(() => _openingTaskPicker = false);
    }
  }

  Future<void> _openAppointment(
    AppointmentPreparation appointment,
    String taskTitle,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentPreparationPage(
          appointment: appointment,
          taskTitle: taskTitle,
        ),
      ),
    );
    _refreshActiveAppointment();
  }

  Future<void> _enterAppointment(
    AppointmentPreparation appointment,
    String taskTitle,
  ) async {
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .enterAppointmentEarly(appointment.id);
      if (!mounted) return;
      await ref
          .read(focusNotificationServiceProvider)
          .appointmentEnteredFocus(
            appointmentId: appointment.id,
            taskTitle: taskTitle,
          );
      await ref
          .read(focusNotificationServiceProvider)
          .sync(session: session, taskTitle: taskTitle);
      _openSession(session, taskTitle);
    } catch (error) {
      if (mounted) showFocusError(context, error);
    } finally {
      _refreshActiveAppointment();
    }
  }

  Future<void> _cancelAppointment(AppointmentPreparation appointment) async {
    final reason = await showTextEditor(
      context,
      title: '取消预约准备',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(focusRepositoryProvider)
          .cancelAppointment(
            appointmentId: appointment.id,
            failureReason: reason,
          );
      await ref.read(focusNotificationServiceProvider).sync(taskTitle: '当前任务');
      _refreshActiveAppointment();
    } catch (error) {
      if (mounted) showFocusError(context, error);
    }
  }

  Future<void> _openPrecedentRules() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PrecedentRulesPage()),
    );
    if (!mounted) return;
    setState(() {
      _precedentRulesFuture = ref
          .read(focusRepositoryProvider)
          .getPrecedentRules();
    });
  }

  void _openSession(FocusSession session, String taskTitle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FocusSessionPage(session: session, taskTitle: taskTitle),
      ),
    );
  }
}

enum _RecoveryStripTone { primary, secondary }

/// Compact recovery strip for an unfinished session or a waiting appointment.
///
/// 圆角容器 + 左侧“标题 / 任务名”双行文本，右侧放唯一主操作；不再用
/// 左单边竖条强调，避免圆角容器上出现月牙状的边缘。纵向 padding 压到
/// 4dp，使双行文本与 3 个按钮同时存在时仍保住专注链首屏的一屏高度。
class _FocusRecoveryStrip extends StatelessWidget {
  const _FocusRecoveryStrip({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.actions = const [],
    this.tone = _RecoveryStripTone.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> actions;
  final _RecoveryStripTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = tone == _RecoveryStripTone.primary;
    final background = primary
        ? colors.primaryContainer
        : colors.secondaryContainer;
    final foreground = primary
        ? colors.onPrimaryContainer
        : colors.onSecondaryContainer;
    return Container(
      margin: const EdgeInsets.only(top: PactaSpacing.xs),
      padding: const EdgeInsets.fromLTRB(
        PactaSpacing.md,
        PactaSpacing.xs,
        PactaSpacing.xs,
        PactaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PactaSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: PactaSpacing.xxs),
                child: Icon(icon, size: 20, color: foreground),
              ),
              const SizedBox(width: PactaSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      // 标题用 titleSmall，副标题用 bodySmall：层级靠字阶，
                      // 不靠加粗或字色堆叠。
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing case final action?) ...[
                const SizedBox(width: PactaSpacing.sm),
                action,
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: PactaSpacing.xxs),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: PactaSpacing.xs,
              runSpacing: PactaSpacing.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Full 下必为例 manager, opened from the Focus Chain first screen.
class PrecedentRulesPage extends StatelessWidget {
  const PrecedentRulesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('下必为例')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: const [PrecedentRulesCard()],
    ),
  );
}

/// The pinned start action: choosing a task never requires scrolling away.
class _FocusStartBar extends StatelessWidget {
  const _FocusStartBar({
    required this.taskCount,
    required this.busy,
    required this.onPressed,
  });

  final int taskCount;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaces = PactaSurfaces.of(context);
    final gutter = PactaSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    // 定稿方案 A：全宽固定操作区，比页面与卡片各抬一档，顶部圆角 + 投影。
    return Material(
      color: surfaces.actionBar,
      elevation: 3,
      shadowColor: surfaces.actionBarShadow,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(PactaSpacing.actionBarRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          PactaSpacing.sm,
          gutter,
          PactaSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: PactaSpacing.sm,
              runSpacing: PactaSpacing.xs,
              children: [
                // 操作区标题保持 titleMedium；主操作由下方 48dp 按钮承担。
                Text('开始一次专注', style: theme.textTheme.titleMedium),
                Text(
                  '可选任务 $taskCount 个',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PactaSpacing.xs),
            FilledButton.icon(
              key: const ValueKey('focus-task-picker-entry'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: busy ? null : onPressed,
              icon: const Icon(Icons.playlist_play),
              label: const Text('选择任务'),
            ),
          ],
        ),
      ),
    );
  }
}

class FocusTaskPickerPage extends ConsumerStatefulWidget {
  const FocusTaskPickerPage({
    super.key,
    this.initialMode = FocusChainMode.regular,
  });

  final FocusChainMode initialMode;

  @override
  ConsumerState<FocusTaskPickerPage> createState() =>
      _FocusTaskPickerPageState();
}

class _FocusTaskPickerPageState extends ConsumerState<FocusTaskPickerPage> {
  TaskClassification? _filter;
  bool _openingSetup = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('选择任务')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<TaskClassification?>(
                segments: const [
                  ButtonSegment<TaskClassification?>(
                    value: null,
                    label: Text('全部'),
                  ),
                  ButtonSegment<TaskClassification?>(
                    value: TaskClassification.elite,
                    label: Text('精锐'),
                  ),
                  ButtonSegment<TaskClassification?>(
                    value: TaskClassification.regular,
                    label: Text('普通'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (values) =>
                    setState(() => _filter = values.single),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Goal>>(
                stream: ref.watch(taskRepositoryProvider).watchGoals(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('任务读取失败，请返回后重试。'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final goals = snapshot.data!;
                  final entries = [
                    for (final goal in goals)
                      if (!goal.isDeleted)
                        for (final task in goal.tasks)
                          if (!task.isDeleted &&
                              !task.isComplete &&
                              _matchesFilter(task))
                            (goal: goal, task: task),
                  ];
                  if (entries.isEmpty) {
                    return const Center(child: Text('当前筛选下没有可开始的任务。'));
                  }
                  return ListView.separated(
                    key: const PageStorageKey('focus-task-picker-list'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    itemCount: entries.length,
                    // 主题把 Card 的外边距设为 0，连续卡片会紧贴；
                    // 任务卡之间补一档 8dp，滚动时仍能区分相邻任务。
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: PactaSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final task = entry.task;
                      final estimate = task.estimatedMinutes == null
                          ? '未设置'
                          : '${task.estimatedMinutes} 分钟';
                      return Card(
                        child: ListTile(
                          title: Text(task.title),
                          subtitle: Text(
                            '目标：${entry.goal.title} · ${task.classification.label} · '
                            '预计时长：$estimate · 已专注 ${formatEffectiveDuration(task.focusProgressSeconds)}',
                          ),
                          onTap: () => _showSetup(task),
                          trailing: Tooltip(
                            message: '开始任务：${task.title}',
                            child: FilledButton.tonal(
                              onPressed: () => _showSetup(task),
                              child: const Text('开始'),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  bool _matchesFilter(Task task) {
    return switch (_filter) {
      null => true,
      TaskClassification.elite =>
        task.classification == TaskClassification.elite ||
            task.classification == TaskClassification.both,
      TaskClassification.regular =>
        task.classification == TaskClassification.regular ||
            task.classification == TaskClassification.both,
      TaskClassification.both => true,
    };
  }

  Future<void> _showSetup(Task task) async {
    if (_openingSetup) return;
    _openingSetup = true;
    try {
      final repository = ref.read(focusRepositoryProvider);
      final activeSession = await repository.getActiveSession();
      final activeAppointment = activeSession == null
          ? await repository.getActiveAppointment()
          : null;
      if (!mounted) return;
      final result =
          activeSession ??
          activeAppointment ??
          await showDialog<Object>(
            context: context,
            builder: (_) => FocusSetupDialog(
              task: task,
              initialMode: initialFocusModeFor(
                task.classification,
                widget.initialMode,
              ),
            ),
          );
      if (mounted && result != null) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) showFocusError(context, error);
    } finally {
      _openingSetup = false;
    }
  }
}

class FocusHistoryPage extends ConsumerStatefulWidget {
  const FocusHistoryPage({super.key});

  @override
  ConsumerState<FocusHistoryPage> createState() => _FocusHistoryPageState();
}

class _FocusHistoryPageState extends ConsumerState<FocusHistoryPage> {
  FocusRepository? _nodesRepository;
  String? _nodesSessionSignature;
  late Future<List<FocusNode>> _nodesFuture;

  @override
  void initState() {
    super.initState();
    _loadNodes(ref.read(focusRepositoryProvider));
  }

  void _loadNodes(FocusRepository repository) {
    _nodesRepository = repository;
    _nodesSessionSignature = null;
    _nodesFuture = repository.getNodes();
  }

  void _refreshNodesForSessions(
    FocusRepository repository,
    List<FocusSession> sessions,
  ) {
    final signature = sessions.map((session) => session.id).join('|');
    if (!identical(_nodesRepository, repository) ||
        _nodesSessionSignature != signature) {
      _nodesRepository = repository;
      _nodesSessionSignature = signature;
      _nodesFuture = repository.getNodes();
    }
  }

  void _reloadNodes(FocusRepository repository) {
    if (!mounted) return;
    setState(() {
      _nodesFuture = repository.getNodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(focusRepositoryProvider);
    if (!identical(_nodesRepository, repository)) _loadNodes(repository);
    final taskRepository = ref.watch(taskRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('专注历史')),
      body: StreamBuilder<List<Goal>>(
        stream: taskRepository.watchGoals(includeDeleted: true),
        builder: (context, goalsSnapshot) {
          if (goalsSnapshot.hasError) {
            return const Center(child: Text('暂时无法读取任务名称。'));
          }
          if (!goalsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final taskTitles = <String, String>{
            for (final goal in goalsSnapshot.data!)
              for (final task in goal.tasks) task.id: taskDisplayTitle(task),
          };
          return StreamBuilder<List<FocusSession>>(
            stream: repository.watchSessions(),
            builder: (context, sessionsSnapshot) {
              if (sessionsSnapshot.hasError) {
                return const Center(child: Text('暂时无法读取专注历史。'));
              }
              if (!sessionsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final sessions = sessionsSnapshot.data!
                  .where((session) => !session.isUnfinished)
                  .toList();
              _refreshNodesForSessions(repository, sessions);
              if (sessions.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('完成或结束专注后，记录会显示在这里。'),
                  ),
                );
              }
              return FutureBuilder<List<FocusNode>>(
                future: _nodesFuture,
                builder: (context, nodesSnapshot) => _FocusHistoryList(
                  repository: repository,
                  sessions: sessions,
                  nodes: nodesSnapshot.data ?? const [],
                  taskTitles: taskTitles,
                  nodeError: nodesSnapshot.hasError,
                  onNodeNoteUpdated: () => _reloadNodes(repository),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FocusHistoryList extends StatelessWidget {
  const _FocusHistoryList({
    required this.repository,
    required this.sessions,
    required this.nodes,
    required this.taskTitles,
    required this.nodeError,
    required this.onNodeNoteUpdated,
  });

  final FocusRepository repository;
  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final Map<String, String> taskTitles;
  final bool nodeError;
  final VoidCallback onNodeNoteUpdated;

  @override
  Widget build(BuildContext context) {
    final nodesBySession = {for (final node in nodes) node.sessionId: node};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (nodeError)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('节点备注暂时不可用，专注记录仍可查看。'),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${sessions.length} 次已结算专注',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final (index, session) in sessions.indexed) ...[
          // 卡片外边距为 0，历史记录之间补一档 8dp 才能读成独立条目。
          if (index > 0) const SizedBox(height: PactaSpacing.sm),
          Card(
            child: ListTile(
              title: Text(taskTitles[session.taskId] ?? '原任务'),
              subtitle: Text(
                session.isFailed
                    ? '失败 · ${formatEffectiveDuration(session.effectiveSeconds)}\n原因：${session.failureReason ?? '未填写'}'
                    : session.isEarlyCompleted
                    ? '获准提前完成 · ${formatEffectiveDuration(session.effectiveSeconds)}\n依据：${session.completionRuleText ?? '未记录'}'
                    : '正常完成 · ${formatEffectiveDuration(session.effectiveSeconds)}',
              ),
              trailing: Wrap(
                children: [
                  if (session.isFailed)
                    IconButton(
                      tooltip: '编辑失败原因',
                      icon: const Icon(Icons.edit_note_outlined),
                      onPressed: () async {
                        final reason = await showTextEditor(
                          context,
                          title: '编辑失败原因',
                          label: '失败原因',
                          initial: session.failureReason ?? '',
                          required: true,
                        );
                        if (reason != null) {
                          await repository.updateFailureReason(
                            sessionId: session.id,
                            failureReason: reason,
                          );
                        }
                      },
                    ),
                  if (nodesBySession[session.id] case final node?)
                    IconButton(
                      tooltip: '编辑节点备注',
                      icon: const Icon(Icons.sticky_note_2_outlined),
                      onPressed: () async {
                        final note = await showTextEditor(
                          context,
                          title: '编辑节点备注',
                          label: '备注（可选）',
                          initial: node.note ?? '',
                        );
                        if (note != null) {
                          await repository.updateNodeNote(
                            nodeId: node.id,
                            note: note,
                          );
                          onNodeNoteUpdated();
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PrecedentRulesCard extends ConsumerStatefulWidget {
  const PrecedentRulesCard({super.key});

  @override
  ConsumerState<PrecedentRulesCard> createState() => _PrecedentRulesCardState();
}

class _PrecedentRulesCardState extends ConsumerState<PrecedentRulesCard> {
  List<PrecedentRule> _rules = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await ref.read(focusRepositoryProvider).getPrecedentRules();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = formatUserError(error);
      });
    }
  }

  Future<void> _create() async {
    final text = await showTextEditor(
      context,
      title: '新建下必为例',
      label: '下必为例',
      initial: '',
      required: true,
    );
    if (text == null || !mounted) return;
    await _run(() async {
      await ref.read(focusRepositoryProvider).createPrecedentRule(text: text);
    });
  }

  Future<void> _edit(PrecedentRule rule) async {
    final text = await showTextEditor(
      context,
      title: '编辑下必为例',
      label: '下必为例',
      initial: rule.text,
      required: true,
    );
    if (text == null || !mounted) return;
    await _run(() async {
      await ref
          .read(focusRepositoryProvider)
          .updatePrecedentRule(ruleId: rule.id, text: text);
    });
  }

  Future<void> _delete(PrecedentRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除下必为例？'),
        content: const Text('删除后不会再出现在新的中断操作中，已经确认的记录保留原文字。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(focusRepositoryProvider).deletePrecedentRule(rule.id),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('下必为例', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('专注中断时可直接选择或新建；规则含义由你自己判断。'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有共享规则。'),
            )
          else
            for (final rule in _rules)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(rule.text),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: '编辑下必为例',
                      onPressed: _busy ? null : () => _edit(rule),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '删除下必为例',
                      onPressed: _busy ? null : () => _delete(rule),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('新建规则'),
          ),
        ],
      ),
    ),
  );
}
