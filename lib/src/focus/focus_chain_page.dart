import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../theme/pacta_theme.dart';
import '../ui/pacta_date_format.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_page_header.dart';
import 'chain_signals_card.dart';
import 'effective_duration_text.dart';
import 'focus_chain_history.dart';
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
  late Future<List<AppointmentPreparation>> _appointmentsFuture;
  late Stream<AppointmentPreparation?> _activeAppointmentStream;
  late Future<List<PrecedentRule>> _precedentRulesFuture;

  @override
  void initState() {
    super.initState();
    _activeAppointmentStream = ref
        .read(focusRepositoryProvider)
        .watchActiveAppointment();
    _appointmentsFuture = ref.read(focusRepositoryProvider).getAppointments();
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
        // 预约链的“累计/平均”与首屏同源：预约结算、取消或提前进入后
        // 必须重新读已结算记录，否则统计停在上一份快照。
        _appointmentsFuture = repository.getAppointments();
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
                              icon: const Icon(
                                Icons.history,
                                size: PactaIconSizes.sm,
                              ),
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
                                subtitle: title,
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
                                  return FutureBuilder<
                                    List<AppointmentPreparation>
                                  >(
                                    future: _appointmentsFuture,
                                    builder: (context, appointmentsSnapshot) {
                                      // 预约链的「累计/平均」与专注链同一统计
                                      // 类型，读取口径也完全一致：失败就交给
                                      // 重试卡，不能把未知的准备时长回落成
                                      // 0分00秒，让用户以为预约从未发生。
                                      if (appointmentsSnapshot.hasError) {
                                        return _recordReadError();
                                      }
                                      if (!appointmentsSnapshot.hasData) {
                                        return const LinearProgressIndicator();
                                      }
                                      final appointmentStatistics =
                                          appointmentPreparationStatistics(
                                            appointmentsSnapshot.data!,
                                          );
                                      return FocusChainOverview(
                                        repository: signalsRepository,
                                        records: recordSnapshot.data!,
                                        appointmentRecord:
                                            appointmentSnapshot.data,
                                        statistics: statistics,
                                        appointmentStatistics:
                                            appointmentStatistics,
                                      );
                                    },
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
  Widget _allowanceEntry(BuildContext context) =>
      FutureBuilder<List<PrecedentRule>>(
        future: _precedentRulesFuture,
        builder: (context, snapshot) {
          final count = snapshot.data?.length;
          final subtitle = snapshot.hasError
              ? '读取失败，进入管理后可重试'
              : count == null
              ? '读取中…'
              : '$count 条持续许可';
          // 与信号卡同一套分组语法：单行设置项 + 右侧箭头，整行 48dp 命中区。
          return PactaGroupedList(
            key: const ValueKey('focus-allowance-entry'),
            children: [
              PactaSettingsTile(
                tileKey: const ValueKey('focus-allowance-manage'),
                leadingIcon: Icons.rule_outlined,
                title: '下必为例',
                subtitle: subtitle,
                statusBadge: snapshot.hasError
                    ? const PactaStatusBadge(
                        label: '读取失败',
                        tone: PactaStatusBadgeTone.error,
                      )
                    : null,
                onTap: _openPrecedentRules,
              ),
            ],
          );
        },
      );

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
            _appointmentsFuture = repository.getAppointments();
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
    _appointmentsFuture = repository.getAppointments();
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
      final recovered = activeSession != null || activeAppointment != null;
      final mode = recovered
          ? FocusChainMode.regular
          : await repository.getLastMode();
      if (!mounted) return;
      // 弹窗刚创建的对象自带任务标题（用户点的就是那张卡），标题随结果一起
      // 回来；只有从已有流程恢复时才按原逻辑回查一次任务树。
      final selection = recovered
          ? _FocusStartSelection.fromObject(activeSession ?? activeAppointment!)
          : await Navigator.of(context).push<_FocusStartSelection>(
              MaterialPageRoute<_FocusStartSelection>(
                builder: (_) => FocusTaskPickerPage(initialMode: mode),
              ),
            );
      if (!mounted || selection == null) return;
      final taskTitle =
          selection.taskTitle ??
          switch (selection) {
            _FocusSessionStartSelection(:final session) => await _findTaskTitle(
              session.taskId,
              '原任务',
            ),
            _FocusAppointmentStartSelection(:final appointment) =>
              await _findTaskTitle(appointment.taskId, '原预约任务'),
          };
      if (!mounted) return;
      switch (selection) {
        case _FocusSessionStartSelection(:final session):
          _openSession(session, taskTitle);
        case _FocusAppointmentStartSelection(:final appointment):
          await _openAppointment(appointment, taskTitle);
      }
      _refreshActiveAppointment();
    } catch (error) {
      if (mounted) showFocusError(context, error);
    } finally {
      if (mounted) setState(() => _openingTaskPicker = false);
    }
  }

  /// 只在恢复已有流程时用到：按 taskId 回查标题，读不到就退回占位文案。
  Future<String> _findTaskTitle(String taskId, String fallback) async {
    try {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      return findTaskTitle(goals, taskId) ?? fallback;
    } catch (_) {
      return fallback;
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
                child: Icon(
                  icon,
                  size: PactaIconSizes.compact,
                  color: foreground,
                ),
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
    // 推入式二级页统一居中并限制正文宽度：桌面宽屏下与页面级卡片同一
    // 阅读节奏，不再横向撑满整块画布。
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: PactaSpacing.pageInsets(
            context,
            top: PactaSpacing.sm,
            bottom: PactaSpacing.xl,
          ),
          // 页面本身已有 AppBar 标题「下必为例」，卡片不再重复一次。
          children: const [PrecedentRulesCard(showTitle: false)],
        ),
      ),
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
    // 悬浮卡片：左右留 gutter、底部留一档边距，四周统一 20dp 圆角 + 投影，
    // 与页面卡片同一半径，不再贴边成一条通栏操作区。
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          PactaSpacing.xs,
          gutter,
          PactaSpacing.md,
        ),
        child: Material(
          key: const ValueKey('focus-start-bar'),
          color: surfaces.actionBar,
          elevation: 3,
          shadowColor: surfaces.actionBarShadow,
          borderRadius: BorderRadius.circular(PactaSpacing.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PactaSpacing.lg,
              PactaSpacing.sm,
              PactaSpacing.lg,
              PactaSpacing.md,
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
                  icon: const Icon(
                    Icons.playlist_play,
                    size: PactaIconSizes.sm,
                  ),
                  label: const Text('选择任务'),
                ),
              ],
            ),
          ),
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
  /// 三档筛选与 PageView 页序一一对应：全部 / 精锐 / 普通。
  static const _filters = <TaskClassification?>[
    null,
    TaskClassification.elite,
    TaskClassification.regular,
  ];

  static const _pageTransition = Duration(milliseconds: 240);

  TaskClassification? _filter;
  bool _openingSetup = false;
  late final PageController _pageController;

  /// 程序化切页的目标与进行标记：跨两页时 `onPageChanged` 会先报中间页，
  /// 不能让它把胶囊高亮改回中间那一档。
  TaskClassification? _animatingToFilter;
  bool _animatingFilter = false;

  /// 同一仓储只订阅一次：翻页触发的 setState 不会重建流。
  TaskRepository? _goalsRepository;
  Stream<List<Goal>>? _goalsStream;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Stream<List<Goal>> _watchGoals(TaskRepository repository) {
    if (!identical(_goalsRepository, repository)) {
      _goalsRepository = repository;
      _goalsStream = repository.watchGoals();
    }
    return _goalsStream!;
  }

  @override
  Widget build(BuildContext context) {
    final gutter = PactaSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    final goalsStream = _watchGoals(ref.watch(taskRepositoryProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('选择任务')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: PactaSpacing.maxContentWidth,
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  PactaSpacing.sm,
                  gutter,
                  PactaSpacing.sm,
                ),
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
                  onSelectionChanged: (values) => _selectFilter(values.single),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Goal>>(
                  // 流在翻页前后保持同一实例：三页共用一次读取，切页不会
                  // 先闪一帧空列表再重新加载。
                  stream: goalsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('任务读取失败，请返回后重试。'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final goals = snapshot.data!;
                    return ScrollConfiguration(
                      // 桌面按住鼠标横拖也能翻页；触控板与触控笔同权。
                      behavior: const PactaScrollBehavior(),
                      child: PageView(
                        key: const ValueKey('focus-task-picker-pager'),
                        controller: _pageController,
                        onPageChanged: _selectFilterPage,
                        children: [
                          for (final (index, filter) in _filters.indexed)
                            _taskPage(
                              goals: goals,
                              filter: filter,
                              index: index,
                              gutter: gutter,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskPage({
    required List<Goal> goals,
    required TaskClassification? filter,
    required int index,
    required double gutter,
  }) {
    final entries = [
      for (final goal in goals)
        if (!goal.isDeleted)
          for (final task in goal.tasks)
            if (!task.isDeleted &&
                !task.isComplete &&
                _matchesFilter(task, filter))
              (goal: goal, task: task),
    ];
    if (entries.isEmpty) {
      return const Center(child: Text('当前筛选下没有可开始的任务。'));
    }
    return ListView.separated(
      // 每页独立保存滚动位置：从精锐滑回全部不会跳回顶部。
      key: PageStorageKey<String>('focus-task-picker-list-$index'),
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, PactaSpacing.xl),
      itemCount: entries.length,
      // 主题把 Card 的外边距设为 0，连续卡片会紧贴；
      // 任务卡之间补一档 8dp，滚动时仍能区分相邻任务。
      separatorBuilder: (context, index) =>
          const SizedBox(height: PactaSpacing.sm),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final task = entry.task;
        return Card(
          child: ListTile(
            leading: _TaskTypeWell(classification: task.classification),
            title: Text(task.title),
            subtitle: Text(_taskSubtitle(entry.goal, task)),
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
  }

  /// 卡片副标题：只留图标没有表达的事实——目标名、预计时长与已专注进度。
  ///
  /// 分类由左侧 [_TaskTypeWell] 的图标承担，不再重复写「精锐 / 普通」；
  /// 没有预计时长时也不写「预计时长：未设置」这种零信息占位。
  String _taskSubtitle(Goal goal, Task task) {
    final estimate = task.estimatedMinutes;
    final progress = formatCompactFocusDuration(task.focusProgressSeconds);
    if (estimate == null) {
      return task.focusProgressSeconds > 0
          ? '${goal.title} · 已专注 $progress'
          : '${goal.title} · 尚未专注';
    }
    return '${goal.title} · 已专注 $progress / '
        '${formatCompactEstimateMinutes(estimate)}';
  }

  void _selectFilter(TaskClassification? filter) {
    final index = _filters.indexOf(filter);
    if (index < 0) return;
    if (_filter != filter) setState(() => _filter = filter);
    if (!_pageController.hasClients) return;
    _animatingToFilter = filter;
    _animatingFilter = true;
    unawaited(
      _pageController
          .animateToPage(
            index,
            duration: _pageTransition,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (_animatingToFilter != filter) return;
            _animatingToFilter = null;
            _animatingFilter = false;
          }),
    );
  }

  void _selectFilterPage(int index) {
    // 程序化切页跨两页时会经过中间页；中途页不能覆写用户的胶囊选择。
    if (_animatingFilter) return;
    final filter = _filters[index];
    if (_filter == filter) return;
    setState(() => _filter = filter);
  }

  bool _matchesFilter(Task task, TaskClassification? filter) {
    return switch (filter) {
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
      final recovered = activeSession ?? activeAppointment;
      final result =
          recovered ??
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
      if (!mounted || result == null) return;
      // 新建的会话／预约就是这张卡本身：标题一并回传，专注链不再为拿一个
      // 标题重查整个任务树——那段查询与随后的二次推进正是开始后 2–3 秒
      // 延迟的主要来源，倒计时会因此一进页面就少两秒。
      final selection = _FocusStartSelection.fromObject(
        result,
        taskTitle: recovered == null ? taskDisplayTitle(task) : null,
      );
      if (selection == null) return;
      Navigator.of(context).pop(selection);
    } catch (error) {
      if (mounted) showFocusError(context, error);
    } finally {
      _openingSetup = false;
    }
  }
}

/// 选择任务页回传给专注链的结果：开始的对象 + 它的任务标题。
///
/// 标题为 null 表示对象来自「恢复已有流程」，此时由专注链按 taskId 回查。
sealed class _FocusStartSelection {
  const _FocusStartSelection({this.taskTitle});

  final String? taskTitle;

  static _FocusStartSelection? fromObject(Object? value, {String? taskTitle}) =>
      switch (value) {
        FocusSession session => _FocusSessionStartSelection(
          session,
          taskTitle: taskTitle,
        ),
        AppointmentPreparation appointment => _FocusAppointmentStartSelection(
          appointment,
          taskTitle: taskTitle,
        ),
        _ => null,
      };
}

final class _FocusSessionStartSelection extends _FocusStartSelection {
  const _FocusSessionStartSelection(this.session, {super.taskTitle});

  final FocusSession session;
}

final class _FocusAppointmentStartSelection extends _FocusStartSelection {
  const _FocusAppointmentStartSelection(this.appointment, {super.taskTitle});

  final AppointmentPreparation appointment;
}

/// 任务卡左侧的柔色圆底图标井：精锐 / 普通 / 双模式各一档图标与底色。
class _TaskTypeWell extends StatelessWidget {
  const _TaskTypeWell({required this.classification});

  final TaskClassification classification;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (
      IconData icon,
      Color background,
      Color foreground,
    ) = switch (classification) {
      TaskClassification.elite => (
        Icons.shield_outlined,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      TaskClassification.regular => (
        Icons.all_inclusive,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      TaskClassification.both => (
        Icons.swap_horiz,
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: PactaIconSizes.compact, color: foreground),
    );
  }
}

/// 专注历史：按链切换的纵向链式时间轴。
///
/// 顶部三段切换（精锐链 / 普通链 / 预约链），下方把已结算记录回放成递进的
/// 连胜段。每段按「倒链」展示：最新在最上，最上方是该段的收尾断链（如果有），
/// 其后按 #N -> #1 倒序排列；段头写清连续长度，段内用纵向连接线与圆形序号
/// 徽章串联，断链卡明确下一段重新从 #1 起算。
/// 现行单设备时钟待核对只挂轻量徽标，不占序号也不断链。
class FocusHistoryPage extends ConsumerStatefulWidget {
  const FocusHistoryPage({super.key});

  @override
  ConsumerState<FocusHistoryPage> createState() => _FocusHistoryPageState();
}

class _FocusHistoryData {
  const _FocusHistoryData({
    required this.nodes,
    required this.appointments,
    required this.nodesFailed,
    required this.appointmentsFailed,
  });

  final List<FocusNode> nodes;
  final List<AppointmentPreparation> appointments;

  /// 节点备注与预约记录各自读取失败：失败只降级对应信息，不隐藏已有记录。
  final bool nodesFailed;
  final bool appointmentsFailed;
}

class _FocusHistoryPageState extends ConsumerState<FocusHistoryPage> {
  static const _pageTransition = Duration(milliseconds: 240);

  /// 用户显式选中的链；为空时按「第一条有记录的链」做默认选择。
  FocusChainType? _chain;

  /// 首次数据就绪时锁定的落点：之后流刷新不再重新计算默认链，
  /// 用户主动滑动或点选后由 [_chain] 接管。
  FocusChainType? _initialChain;
  PageController? _pageController;
  FocusChainType? _animatingToChain;
  bool _animatingChain = false;
  FocusRepository? _dataRepository;
  String? _dataSignature;
  late Future<_FocusHistoryData> _dataFuture;
  String? _displayTimeZoneId;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _refreshDisplayTimeZone() async {
    final zoneId = await readAccountDisplayTimeZone(ref);
    if (!mounted || zoneId == _displayTimeZoneId) return;
    setState(() => _displayTimeZoneId = zoneId);
  }

  Future<_FocusHistoryData> _readData(FocusRepository repository) async {
    List<FocusNode> nodes = const <FocusNode>[];
    var nodesFailed = false;
    try {
      nodes = await repository.getNodes();
    } catch (_) {
      nodesFailed = true;
    }
    List<AppointmentPreparation> appointments =
        const <AppointmentPreparation>[];
    var appointmentsFailed = false;
    try {
      appointments = await repository.getAppointments();
    } catch (_) {
      appointmentsFailed = true;
    }
    return _FocusHistoryData(
      nodes: nodes,
      appointments: appointments,
      nodesFailed: nodesFailed,
      appointmentsFailed: appointmentsFailed,
    );
  }

  /// 专注记录变化（新结算、改正失败原因）时，节点备注与预约记录一起刷新；
  /// 只有签名变化才重新读，避免每帧重复查询。
  void _syncForSessions(
    FocusRepository repository,
    List<FocusSession> sessions,
  ) {
    final signature = [
      for (final session in sessions)
        '${session.id}:${session.status.storageValue}:'
            '${session.reviewDisposition.storageValue}:'
            '${session.failureReason}',
    ].join('|');
    if (identical(_dataRepository, repository) && _dataSignature == signature) {
      return;
    }
    _dataRepository = repository;
    _dataSignature = signature;
    _dataFuture = _readData(repository);
    unawaited(_refreshDisplayTimeZone());
  }

  void _reload(FocusRepository repository) {
    if (!mounted) return;
    setState(() {
      _dataFuture = _readData(repository);
    });
  }

  /// 默认落在第一条有记录的链：精锐链没有记录时不必先看到空态再手动切换。
  FocusChainType _defaultChain(FocusChainHistory history) {
    for (final chain in FocusChainType.values) {
      if (history.timelineFor(chain).isNotEmpty) return chain;
    }
    return FocusChainType.elite;
  }

  /// 首次拿到完整数据时锁定落点，并让 PageController 以该页为初始页。
  ///
  /// 不先渲染精锐链再 `jumpToPage`：默认链在第一次 build 就参与
  /// `initialPage` 计算，首帧直接落在有记录的那一链上。
  FocusChainType _resolveChain(FocusChainHistory history) {
    final chosen = _chain ?? _initialChain;
    if (chosen != null) return chosen;
    return _initialChain = _defaultChain(history);
  }

  void _selectChain(FocusChainType chain) {
    final index = FocusChainType.values.indexOf(chain);
    if (index < 0) return;
    if (_chain != chain) setState(() => _chain = chain);
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    _animatingToChain = chain;
    _animatingChain = true;
    unawaited(
      controller
          .animateToPage(
            index,
            duration: _pageTransition,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (_animatingToChain != chain) return;
            _animatingToChain = null;
            _animatingChain = false;
          }),
    );
  }

  void _onChainPageChanged(int index) {
    // 程序化切页跨两页时会经过中间链；中途页不能覆写用户的选择。
    if (_animatingChain) return;
    final chain = FocusChainType.values[index];
    if (_chain == chain) return;
    setState(() => _chain = chain);
  }

  Widget _chainSwitch(BuildContext context, FocusChainType chain) {
    final gutter = PactaSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        PactaSpacing.sm,
        gutter,
        PactaSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.center,
        child: FittedBox(
          // 「字比框大」的根因是 compact 密度 + 8dp 内边距把中文标签顶到边框。
          // 改成标准密度与对称的 12/4 内边距，48dp 最小高度让文字稳稳包在
          // 胶囊中线；360dp 窄屏或 2 倍字号时由 FittedBox 整体等比收缩，
          // 不溢出也不截断。
          fit: BoxFit.scaleDown,
          child: SegmentedButton<FocusChainType>(
            key: const ValueKey('focus-history-chain-switch'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 48),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(
                horizontal: PactaSpacing.md,
                vertical: PactaSpacing.xs,
              ),
            ),
            segments: [
              for (final chain in FocusChainType.values)
                ButtonSegment<FocusChainType>(
                  value: chain,
                  label: Text(chain.label),
                ),
            ],
            selected: {chain},
            onSelectionChanged: (selection) => _selectChain(selection.single),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(focusRepositoryProvider);
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
              final sessions = [
                for (final session in sessionsSnapshot.data!)
                  if (!session.isUnfinished) session,
              ];
              _syncForSessions(repository, sessions);
              return FutureBuilder<_FocusHistoryData>(
                future: _dataFuture,
                builder: (context, dataSnapshot) {
                  if (dataSnapshot.hasError) {
                    return const Center(child: Text('暂时无法读取专注历史。'));
                  }
                  final data = dataSnapshot.data;
                  if (data == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final history = buildFocusChainHistory(
                    sessions: sessions,
                    appointments: data.appointments,
                  );
                  final chain = _resolveChain(history);
                  final pageController = _pageController ??= PageController(
                    initialPage: FocusChainType.values.indexOf(chain),
                  );
                  // 三链切换、统计摘要与时间轴同受 800dp 居中约束：桌面宽屏
                  // 不再把时间轴拉成 1248dp 的通栏。
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        children: [
                          _chainSwitch(context, chain),
                          Expanded(
                            child: ScrollConfiguration(
                              // 桌面按住鼠标横拖也能换链；触控板与触控笔同权。
                              behavior: const PactaScrollBehavior(),
                              child: PageView.builder(
                                key: const ValueKey('focus-history-pager'),
                                controller: pageController,
                                itemCount: FocusChainType.values.length,
                                onPageChanged: _onChainPageChanged,
                                itemBuilder: (context, index) {
                                  final pageChain =
                                      FocusChainType.values[index];
                                  return _FocusHistoryTimeline(
                                    // 每链独立保存滚动位置，来回滑动不串位。
                                    key: PageStorageKey<String>(
                                      'focus-history-page-${pageChain.name}',
                                    ),
                                    repository: repository,
                                    chain: pageChain,
                                    timeline: history.timelineFor(pageChain),
                                    nodes: data.nodes,
                                    taskTitles: taskTitles,
                                    displayTimeZoneId: _displayTimeZoneId,
                                    dataNotice: _dataNotice(data),
                                    onNodeNoteUpdated: () =>
                                        _reload(repository),
                                    onSessionUpdated: () => _reload(repository),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String? _dataNotice(_FocusHistoryData data) {
    if (data.nodesFailed) return '节点备注暂时不可用，专注记录仍可查看。';
    if (data.appointmentsFailed) return '预约记录暂时不可用，专注记录仍可查看。';
    return null;
  }
}

/// 纵向链式时间轴：段头 + 连接线 + 圆形序号徽章。
class _FocusHistoryTimeline extends StatelessWidget {
  const _FocusHistoryTimeline({
    super.key,
    required this.repository,
    required this.chain,
    required this.timeline,
    required this.nodes,
    required this.taskTitles,
    required this.displayTimeZoneId,
    required this.dataNotice,
    required this.onNodeNoteUpdated,
    required this.onSessionUpdated,
  });

  final FocusRepository repository;
  final FocusChainType chain;
  final FocusChainTimeline timeline;
  final List<FocusNode> nodes;
  final Map<String, String> taskTitles;
  final String? displayTimeZoneId;
  final String? dataNotice;
  final VoidCallback onNodeNoteUpdated;

  /// 一条已结算记录被事后改判时需要重读的数据（节点已删除、时间轴已变）。
  final VoidCallback onSessionUpdated;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) return _emptyState(context);
    final nodesBySession = <String, FocusNode>{
      for (final node in nodes) node.sessionId: node,
    };
    final gutter = PactaSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    return ListView(
      key: const ValueKey('focus-history-timeline'),
      padding: EdgeInsets.fromLTRB(
        gutter,
        PactaSpacing.md,
        gutter,
        PactaSpacing.xl,
      ),
      children: [
        if (dataNotice case final notice?) _notice(context, notice),
        _summary(context),
        if (timeline.awaitingClockReview.isNotEmpty) ...[
          const SizedBox(height: PactaSpacing.lg),
          _sectionHeader(context, '待核对的专注', '不计入链号，也不打断连胜'),
          const SizedBox(height: PactaSpacing.sm),
          for (final entry in timeline.awaitingClockReview) ...[
            _clockReviewCard(context, entry),
            const SizedBox(height: PactaSpacing.sm),
          ],
        ],
        for (final (index, run) in timeline.runs.indexed) ...[
          const SizedBox(height: PactaSpacing.lg),
          _runSection(
            context,
            run: run,
            isNewest: index == 0,
            nodesBySession: nodesBySession,
          ),
        ],
        if (timeline.leadingBreaks.isNotEmpty) ...[
          const SizedBox(height: PactaSpacing.lg),
          _sectionHeader(context, '更早的断链记录', '第一次连胜之前的失败'),
          const SizedBox(height: PactaSpacing.sm),
          for (final entry in timeline.leadingBreaks) ...[
            _breakCard(context, entry),
            const SizedBox(height: PactaSpacing.sm),
          ],
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final message = switch (chain) {
      FocusChainType.elite || FocusChainType.regular => '完成或结束专注后，记录会显示在这里。',
      FocusChainType.appointment => '完成或结束预约准备后，记录会显示在这里。',
    };
    return Center(
      key: const ValueKey('focus-history-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PactaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: PactaIconSizes.hero,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: PactaSpacing.md),
            Text(
              '${chain.label}还没有连胜记录。',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PactaSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, String notice) => Padding(
    padding: const EdgeInsets.only(bottom: PactaSpacing.sm),
    child: Text(
      notice,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  /// 段数摘要：当前连续、最高连胜与段数一次读全。
  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontWeight: PactaFonts.semibold,
    );
    Widget metric(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: PactaSpacing.xxs),
          Text(value, style: valueStyle),
        ],
      ),
    );
    return PactaGroupedList(
      key: const ValueKey('focus-history-summary'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PactaSpacing.lg,
            vertical: PactaSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              metric('当前连续', '${timeline.currentStreak} 次'),
              metric('最高连胜', '${timeline.bestStreak} 次'),
              metric('连胜段数', '${timeline.runCount} 段'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String caption) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: PactaFonts.semibold,
          ),
        ),
        const SizedBox(width: PactaSpacing.sm),
        Expanded(
          child: Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 一段连胜：段头写明连续长度，段内节点与断链共用一条连接线。
  ///
  /// 连接线不再是一条从段顶贯通到段底的竖线：每一行只画自己的上半 / 下半
  /// 两截，首行不画上半、末行不画下半，行与行之间用 8dp 桥接行补齐。于是
  /// 线永远起止于徽章圆心，最后一条气泡下方不会再拖出一截无名竖线。
  Widget _runSection(
    BuildContext context, {
    required FocusChainStreakRun run,
    required bool isNewest,
    required Map<String, FocusNode> nodesBySession,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final header = isNewest && !run.isBroken
        ? '当前连续 ${run.length} 次'
        : '连续 ${run.length} 次';
    // 倒链：每段从上到下都是最新在前——先收尾断链，再 #N -> #1 倒序。
    // 打开历史页第一眼就是最新记录，不必滚到段尾才看到刚发生的事。
    final rows = <({FocusChainHistoryEntry entry, Widget badge, Widget card})>[
      for (final entry in run.closingBreaks.reversed)
        (
          entry: entry,
          badge: _breakBadge(context),
          card: _breakCard(context, entry),
        ),
      for (final entry in run.entries.reversed)
        (
          entry: entry,
          badge: _streakBadge(context, entry.streakIndex!),
          card: _completedCard(context, entry, nodesBySession[entry.id]),
        ),
    ];
    return Column(
      key: ValueKey(
        'focus-history-run-${run.length}-${run.startedAt.millisecondsSinceEpoch}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              header,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: PactaFonts.semibold,
              ),
            ),
            const SizedBox(width: PactaSpacing.sm),
            Expanded(
              child: Text(
                '${formatPactaMonthDayTime(run.startedAt, timeZoneId: displayTimeZoneId)} – '
                '${formatPactaMonthDayTime(run.endedAt, timeZoneId: displayTimeZoneId)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: PactaSpacing.sm),
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) _timelineBridge(context),
          _timelineRow(
            context,
            entry: row.entry,
            badge: row.badge,
            card: row.card,
            isFirst: index == 0,
            isLast: index == rows.length - 1,
          ),
        ],
      ],
    );
  }

  /// 行间桥：一截 8dp 高的竖线，把上一行底部与下一行顶部接起来。
  ///
  /// 桥接行与卡片间距同高，所以相邻卡片的间距仍是严格的 8dp；右侧留白，
  /// 不会多出一条通栏背景或第二个命中区。
  Widget _timelineBridge(BuildContext context) {
    final surfaces = PactaSurfaces.of(context);
    return SizedBox(
      height: PactaSpacing.sm,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(
              child: SizedBox(
                width: 2,
                height: PactaSpacing.sm,
                child: ColoredBox(color: surfaces.hairline),
              ),
            ),
          ),
          const SizedBox(width: PactaSpacing.sm),
        ],
      ),
    );
  }

  /// 一截轨道竖线：不可见时留空，可见时铺满所在的上下半格。
  Widget _timelineLine(BuildContext context, {required bool visible}) {
    if (!visible) return const SizedBox.shrink();
    final surfaces = PactaSurfaces.of(context);
    return Center(
      child: SizedBox(
        width: 2,
        height: double.infinity,
        child: ColoredBox(color: surfaces.hairline),
      ),
    );
  }

  /// 一行节点：左侧 32dp 轨道内是上下两截连接线 + 居中徽章，右侧是卡片。
  ///
  /// 徽章在整行里严格垂直居中，因此它与右侧 [Card] 的中心永远在同一条
  /// 水平线上；首行不画上半截、末行不画下半截，线只在相邻徽章之间出现。
  Widget _timelineRow(
    BuildContext context, {
    required FocusChainHistoryEntry entry,
    required Widget badge,
    required Widget card,
    required bool isFirst,
    required bool isLast,
  }) => IntrinsicHeight(
    child: Row(
      key: ValueKey('focus-history-row-${entry.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  Expanded(child: _timelineLine(context, visible: !isFirst)),
                  Expanded(child: _timelineLine(context, visible: !isLast)),
                ],
              ),
              badge,
            ],
          ),
        ),
        const SizedBox(width: PactaSpacing.sm),
        Expanded(child: card),
      ],
    ),
  );

  Widget _streakBadge(BuildContext context, int index) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '#$index',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: PactaFonts.semibold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _breakBadge(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.errorContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.link_off,
        size: PactaIconSizes.micro,
        color: colors.onErrorContainer,
      ),
    );
  }

  /// 专注历史卡片外壳：上下严格同为 `md`，使单行、多行卡片与右侧按钮共用一套对称垂直留白。
  Widget _historyTimelineCard({
    required Key cardKey,
    Key? textColumnKey,
    required List<Widget> content,
    Widget? trailing,
  }) => Card(
    key: cardKey,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        PactaSpacing.lg,
        PactaSpacing.md,
        PactaSpacing.xs,
        PactaSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              key: textColumnKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _completedCard(
    BuildContext context,
    FocusChainHistoryEntry entry,
    FocusNode? node,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = switch (entry.chain) {
      FocusChainType.appointment => '预约成功',
      FocusChainType.elite ||
      FocusChainType.regular => entry.basisText == null ? '正常完成' : '获准提前完成',
    };
    final occurred = formatPactaDateTimeInZone(
      entry.occurredAt,
      timeZoneId: displayTimeZoneId,
    );
    final meta =
        '$status · $occurred · '
        '${formatEffectiveDuration(entry.effectiveSeconds)}';
    return _historyTimelineCard(
      cardKey: ValueKey('focus-history-node-${entry.id}'),
      textColumnKey: const ValueKey('focus-history-card-text'),
      content: [
        Text(
          taskTitles[entry.taskId] ?? '原任务',
          style: theme.textTheme.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: PactaSpacing.xxs),
        Text(
          meta,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (entry.basisText case final basis?) ...[
          const SizedBox(height: PactaSpacing.xxs),
          Text(
            '依据：$basis',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
      trailing: _completedCardActions(context, entry, node),
    );
  }

  /// 已完成卡片的尾部动作。
  ///
  /// 精锐链与普通链把「编辑节点备注」和危险的「判定为失败」收进同一个
  /// 菜单：右侧只留一个 48×48dp 命中区，窄屏与两倍字号下标题不会被两个
  /// 图标挤成两行。预约链没有事后改判的语义，保持原来的单颗备注按钮。
  Widget? _completedCardActions(
    BuildContext context,
    FocusChainHistoryEntry entry,
    FocusNode? node,
  ) {
    if (entry.chain == FocusChainType.appointment) {
      return node == null
          ? null
          : IconButton(
              key: ValueKey('focus-history-node-note-${entry.id}'),
              tooltip: '编辑节点备注',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(
                Icons.sticky_note_2_outlined,
                size: PactaIconSizes.compact,
              ),
              onPressed: () => _editNodeNote(context, node),
            );
    }
    final colors = Theme.of(context).colorScheme;
    // PopupMenuButton 的内建 IconButton 自带 48×48dp 最小命中区。
    return PopupMenuButton<String>(
      key: ValueKey('focus-history-node-menu-${entry.id}'),
      tooltip: '更多操作',
      icon: const Icon(Icons.more_vert, size: PactaIconSizes.compact),
      onSelected: (value) {
        switch (value) {
          case 'note':
            if (node != null) unawaited(_editNodeNote(context, node));
          case 'fail':
            unawaited(_markSessionFailed(context, entry));
        }
      },
      itemBuilder: (context) => [
        if (node != null)
          const PopupMenuItem<String>(value: 'note', child: Text('编辑节点备注')),
        PopupMenuItem<String>(
          value: 'fail',
          child: Text(
            '判定为失败',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }

  /// 断链节点：失败徽标、原因与有效时长，并说明下一次从 #1 重新起算。
  Widget _breakCard(BuildContext context, FocusChainHistoryEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final durationLabel = entry.chain == FocusChainType.appointment
        ? '准备时长'
        : '有效专注';
    final editable = entry.chain != FocusChainType.appointment;
    return _historyTimelineCard(
      cardKey: ValueKey('focus-history-break-${entry.id}'),
      textColumnKey: const ValueKey('focus-history-card-text'),
      content: [
        Wrap(
          spacing: PactaSpacing.sm,
          runSpacing: PactaSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const PactaStatusBadge(
              label: '断链',
              icon: Icons.link_off,
              tone: PactaStatusBadgeTone.error,
            ),
            Text(
              formatPactaDateTimeInZone(
                entry.occurredAt,
                timeZoneId: displayTimeZoneId,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: PactaSpacing.xs),
        Text(
          '${taskTitles[entry.taskId] ?? '原任务'} · '
          '原因：${entry.failureReason ?? '未填写'}',
          style: theme.textTheme.bodyMedium,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: PactaSpacing.xxs),
        Text(
          '$durationLabel '
          '${formatEffectiveDuration(entry.effectiveSeconds)}'
          ' · 之后重新从 #1 起算',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      trailing: !editable
          ? null
          : IconButton(
              key: ValueKey('focus-history-break-reason-${entry.id}'),
              tooltip: '编辑失败原因',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(
                Icons.edit_note_outlined,
                size: PactaIconSizes.compact,
              ),
              onPressed: () => _editFailureReason(context, entry),
            ),
    );
  }

  Widget _clockReviewCard(BuildContext context, FocusChainHistoryEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _historyTimelineCard(
      cardKey: ValueKey('focus-history-clock-review-${entry.id}'),
      content: [
        Text(
          taskTitles[entry.taskId] ?? '原任务',
          style: theme.textTheme.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: PactaSpacing.xxs),
        Text(
          '${formatPactaDateTimeInZone(entry.occurredAt, timeZoneId: displayTimeZoneId)} · '
          '${formatEffectiveDuration(entry.effectiveSeconds)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: PactaSpacing.sm),
          PactaStatusBadge(
            label: '时钟待核对',
            icon: Icons.schedule,
            tone: PactaStatusBadgeTone.warning,
          ),
        ],
      ),
    );
  }

  Future<void> _editNodeNote(BuildContext context, FocusNode node) async {
    final note = await showTextEditor(
      context,
      title: '编辑节点备注',
      label: '备注（可选）',
      initial: node.note ?? '',
    );
    if (note == null) return;
    // 停用账号、备注超长或离线都会在写入时抛：降级成可读提示，不让异步
    // 异常从按钮的 onPressed 里逃出去。
    try {
      await repository.updateNodeNote(nodeId: node.id, note: note);
    } catch (error) {
      if (!context.mounted) return;
      showFocusError(context, error);
      return;
    }
    if (!context.mounted) return;
    onNodeNoteUpdated();
  }

  Future<void> _editFailureReason(
    BuildContext context,
    FocusChainHistoryEntry entry,
  ) async {
    final reason = await showTextEditor(
      context,
      title: '编辑失败原因',
      label: '失败原因',
      initial: entry.failureReason ?? '',
      required: true,
    );
    if (reason == null) return;
    // 同 _editNodeNote：写入失败只提示，不把异常丢给上层事件循环。
    try {
      await repository.updateFailureReason(
        sessionId: entry.id,
        failureReason: reason,
      );
    } catch (error) {
      if (!context.mounted) return;
      showFocusError(context, error);
    }
  }

  /// 把一条已完成记录单向改判为失败。
  ///
  /// 仓储负责回收专注节点并按完整历史重算链记录；这里只负责提示代价、
  /// 提交与刷新时间轴。写入失败只弹脱敏提示，异常不从按钮里逃出去。
  Future<void> _markSessionFailed(
    BuildContext context,
    FocusChainHistoryEntry entry,
  ) async {
    final reason = await showFocusFailureReasonDialog(
      context,
      description: markFailedConsequenceHint,
    );
    if (reason == null || !context.mounted) return;
    try {
      await repository.markSessionFailed(
        sessionId: entry.id,
        failureReason: reason,
      );
    } catch (error) {
      if (!context.mounted) return;
      showFocusError(context, error);
      return;
    }
    if (!context.mounted) return;
    onSessionUpdated();
  }
}

class PrecedentRulesCard extends ConsumerStatefulWidget {
  const PrecedentRulesCard({super.key, this.showTitle = true});

  /// 独立页已有 AppBar 标题时关掉卡片标题，避免同屏重复两次「下必为例」。
  final bool showTitle;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(PactaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitle) ...[
              Text('下必为例', style: theme.textTheme.titleMedium),
              const SizedBox(height: PactaSpacing.sm),
            ],
            Text(
              '专注中断时可直接选择或新建；规则含义由你自己判断。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: PactaSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: PactaSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_rules.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: PactaSpacing.md),
                child: Text('还没有共享规则。'),
              )
            else
              // 规则是一组同质条目：行间只放 1dp hairline，不散落成独立卡片。
              Column(
                children: [
                  for (final (index, rule) in _rules.indexed) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.outlineVariant,
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(rule.text),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑下必为例',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: _busy ? null : () => _edit(rule),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: PactaIconSizes.compact,
                            ),
                          ),
                          IconButton(
                            tooltip: '删除下必为例',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: _busy ? null : () => _delete(rule),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: PactaIconSizes.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: PactaSpacing.sm),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            const SizedBox(height: PactaSpacing.md),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add, size: PactaIconSizes.sm),
              label: const Text('新建规则'),
            ),
          ],
        ),
      ),
    );
  }
}
