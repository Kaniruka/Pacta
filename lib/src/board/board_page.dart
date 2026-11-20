import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'national_focus_summary_card.dart';
import '../focus/effective_duration_text.dart';
import '../focus/focus_clock_review_page.dart';
import '../focus/focus_models.dart';
import '../focus/focus_month_page.dart';
import '../focus/focus_reconciliation_page.dart';
import '../focus/focus_repository.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import '../national_focus/national_focus_tree_page.dart';
import '../plan/plan_calendar_view.dart';
import '../profile/account_time_zone.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repository.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_card_header.dart';
import '../ui/pacta_check_circle.dart';
import '../ui/pacta_hold_action_reorder.dart';
import '../ui/pacta_page_header.dart';
import '../app/app_providers.dart';

class _FocusReconciliationPrompt extends StatelessWidget {
  const _FocusReconciliationPrompt({
    required this.focusRepository,
    required this.taskRepository,
  });

  final FocusRepository focusRepository;
  final TaskRepository taskRepository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FocusReconciliationCase>>(
      stream: focusRepository.watchFocusReconciliations(),
      builder: (context, snapshot) {
        final pendingCount = (snapshot.data ?? const [])
            .where((item) => item.isPendingReview)
            .length;
        if (pendingCount == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text('$pendingCount 组专注记录待核对'),
              subtitle: const Text('争议记录暂不计入统计，其他任务仍可继续。'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FocusReconciliationPage(
                    focusRepository: focusRepository,
                    taskRepository: taskRepository,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusClockReviewPrompt extends StatelessWidget {
  const _FocusClockReviewPrompt({required this.repository});

  final FocusRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FocusClockReviewCase>>(
      stream: repository.watchClockReviewCases(),
      builder: (context, snapshot) {
        final cases = snapshot.data ?? const <FocusClockReviewCase>[];
        if (cases.isEmpty) return const SizedBox.shrink();
        final deferredCount = cases.where((item) => item.isDeferred).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text('${cases.length} 段专注时间待核对'),
              subtitle: Text(
                deferredCount == 0
                    ? '时钟变化后的区间保留待核对，不会直接判为失败。'
                    : '$deferredCount 段已暂缓；可靠时间仍可继续使用。',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FocusClockReviewPage(repository: repository),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ticket 11：看板对未回顾失败记录的提示入口。
///
/// 提示只负责把用户带到国策树里的失败记录页（10 号已有的入口），
/// 标记回顾不会介入专注、预约或结算。
class _FailureReviewPrompt extends StatelessWidget {
  const _FailureReviewPrompt({
    required this.repository,
    required this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final String displayTimeZoneId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NationalFocusFailure>>(
      stream: repository.watchFailures(),
      builder: (context, snapshot) {
        final pendingBatches = <String>{
          for (final failure in snapshot.data ?? const <NationalFocusFailure>[])
            if (failure.needsReflection) failure.batchId,
        };
        if (pendingBatches.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              key: const ValueKey('board-failure-review-hint'),
              leading: const Icon(Icons.history_toggle_off),
              title: Text('${pendingBatches.length} 组国策失败待回顾'),
              subtitle: const Text('稍后再看也可以；回顾只做标记，不改动当时的失败结果。'),
              trailing: const Icon(Icons.chevron_right),
              // 直达 10 号已有的失败记录页，而不是只切换主导航；
              // 完整回顾仍在那一页里进入冻结树二级页。
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NationalFocusFailureHistoryPage(
                    repository: repository,
                    displayTimeZoneId: displayTimeZoneId,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({
    super.key,
    required this.onOpenNationalFocus,
    required this.onOpenPlan,
  });

  final VoidCallback onOpenNationalFocus;
  final VoidCallback onOpenPlan;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  /// 重试只换订阅：递增代次让带 key 的 StreamBuilder 换元素，旧的读取随元素
  /// 释放，重新订阅一次当前仓储与时区。它不写任何数据，也不改仓储实例。
  var _projectionGeneration = 0;

  void _retryProjection() {
    if (!mounted) return;
    setState(() => _projectionGeneration += 1);
  }

  /// 看板只提供入口：投影、时区门禁、错误重试都由月历页自己负责，
  /// 这里不复制它的读取或写入路径。owner 与时钟在打开时绑定，
  /// 账号变化由路由自己退出，避免显示上一个账号的月份。
  void _openFocusMonth() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _FocusMonthRoute(
          ownerUserId: ref.read(authUserIdProvider),
          repository: ref.read(focusRepositoryProvider),
          profileRepository: ref.read(profileRepositoryProvider),
          now: ref.read(displayClockProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final nationalFocusRepository = ref.watch(nationalFocusRepositoryProvider);
    final scheduleRepository = ref.watch(scheduleRepositoryProvider);
    final profileRepository = ref.watch(profileRepositoryProvider);
    // 看板是只读投影：一个（资料, 目标, 专注仓储 + 重试代次）对应一次显式订阅，
    // 身份一变就换 key，旧状态连同订阅一起释放；因此上一账号/上一时区的数字
    // 不会留在屏上，也不需要通用回放层。读取失败交给状态里可见的错误与重试。
    return _BoardProjectionScope(
      key: ValueKey<Object>((
        'board-projection',
        profileRepository,
        taskRepository,
        focusRepository,
        _projectionGeneration,
      )),
      profileRepository: profileRepository,
      taskRepository: taskRepository,
      focusRepository: focusRepository,
      builder: (context, projection) => _BoardContent(
        displayTimeZoneId: projection.displayTimeZoneId,
        now: ref.read(displayClockProvider),
        repository: taskRepository,
        focusRepository: focusRepository,
        nationalFocusRepository: nationalFocusRepository,
        scheduleRepository: scheduleRepository,
        onOpenNationalFocus: widget.onOpenNationalFocus,
        onOpenPlan: widget.onOpenPlan,
        onOpenFocusMonth: _openFocusMonth,
        goals: projection.goals,
        metrics: projection.metrics,
        accountFailed: projection.accountFailed,
        metricsFailed: projection.metricsFailed,
        goalsFailed: projection.goalsFailed,
        onRetryProjection: _retryProjection,
      ),
    );
  }
}

/// 看板一次读取的结果：账号时区、目标、近期投影与失败标记。
class _BoardProjection {
  const _BoardProjection({
    required this.displayTimeZoneId,
    required this.goals,
    required this.metrics,
    required this.accountFailed,
    required this.metricsFailed,
    required this.goalsFailed,
  });

  final String displayTimeZoneId;
  final List<Goal> goals;
  final FocusDashboardMetrics? metrics;

  /// 账号资料读取失败：时区按统一兜底值显示，但屏幕必须说明这一点。
  final bool accountFailed;

  /// 近期投影读取失败：不再显示成"正在加载"。
  final bool metricsFailed;

  /// 目标列表读取失败：不能渲染成"还没有置顶目标"。
  final bool goalsFailed;
}

/// 看板的只读订阅宿主。
///
/// 身份由外层 key 决定：仓储或重试代次一变就是新的 State，旧订阅随
/// [dispose] 一起取消。这里不缓存旧快照——换时区时先清空投影再订阅，所以
/// 屏上不会出现上一个账号/时区的数字，也不需要一层通用回放流；读取失败
/// 以可见标记上报，重试只是换 key 重新订阅，不写任何数据。
class _BoardProjectionScope extends StatefulWidget {
  const _BoardProjectionScope({
    super.key,
    required this.profileRepository,
    required this.taskRepository,
    required this.focusRepository,
    required this.builder,
  });

  final ProfileRepository profileRepository;
  final TaskRepository taskRepository;
  final FocusRepository focusRepository;
  final Widget Function(BuildContext context, _BoardProjection projection)
  builder;

  @override
  State<_BoardProjectionScope> createState() => _BoardProjectionScopeState();
}

class _BoardProjectionScopeState extends State<_BoardProjectionScope> {
  StreamSubscription<ProfileAccount>? _profileSubscription;
  StreamSubscription<FocusDashboardMetrics>? _metricsSubscription;
  StreamSubscription<List<Goal>>? _goalsSubscription;
  String _displayTimeZoneId = AccountTimeZones.fallbackId;
  List<Goal> _goals = const [];
  FocusDashboardMetrics? _metrics;
  bool _accountFailed = false;
  bool _metricsFailed = false;
  bool _goalsFailed = false;
  bool _hasBuilt = false;

  /// Whether the account profile produced its first value or error.
  ///
  /// Until then the display zone is unknown, and querying the projection with
  /// the fallback zone would paint UTC-allocated bars before the account's own
  /// zone arrives. The board waits instead of showing a number it cannot stand
  /// behind.
  bool _profileResolved = false;

  @override
  void initState() {
    super.initState();
    _subscribeProfile();
    _subscribeGoals();
  }

  @override
  void dispose() {
    unawaited(_profileSubscription?.cancel());
    unawaited(_metricsSubscription?.cancel());
    unawaited(_goalsSubscription?.cancel());
    super.dispose();
  }

  /// 首帧之前的同步事件直接改字段，避免在挂载途中 setState。
  void _apply(VoidCallback change) {
    if (!mounted) return;
    if (_hasBuilt) {
      setState(change);
    } else {
      change();
    }
  }

  void _subscribeProfile() {
    _profileSubscription = widget.profileRepository.watchProfile().listen(
      (profile) {
        final nextZone = AccountTimeZones.effectiveId(
          profile.displayTimeZoneId,
        );
        final zoneChanged = nextZone != _displayTimeZoneId;
        final firstValue = !_profileResolved;
        _apply(() {
          _accountFailed = false;
          _profileResolved = true;
          if (!zoneChanged) return;
          // 换时区先丢掉旧投影：新流首帧到达前屏上是加载态，不是旧数字。
          _displayTimeZoneId = nextZone;
          _metrics = null;
          _metricsFailed = false;
        });
        if (zoneChanged || firstValue) _subscribeMetrics();
      },
      onError: (Object error, StackTrace stackTrace) {
        final firstValue = !_profileResolved;
        _apply(() {
          _accountFailed = true;
          _profileResolved = true;
        });
        if (firstValue) _subscribeMetrics();
      },
    );
  }

  void _subscribeGoals() {
    _goalsSubscription = widget.taskRepository.watchGoals().listen(
      (goals) => _apply(() {
        _goals = goals;
        _goalsFailed = false;
      }),
      onError: (Object error, StackTrace stackTrace) {
        _apply(() {
          _goals = const [];
          _goalsFailed = true;
        });
      },
    );
  }

  void _subscribeMetrics() {
    unawaited(_metricsSubscription?.cancel());
    final timeZoneId = _displayTimeZoneId;
    _metricsSubscription = widget.focusRepository
        .watchDashboardMetrics(timeZoneId: timeZoneId)
        .listen(
          (metrics) => _apply(() {
            _metrics = metrics;
            _metricsFailed = false;
          }),
          onError: (Object error, StackTrace stackTrace) {
            _apply(() {
              _metrics = null;
              _metricsFailed = true;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    _hasBuilt = true;
    return widget.builder(
      context,
      _BoardProjection(
        displayTimeZoneId: _displayTimeZoneId,
        goals: _goals,
        metrics: _metrics,
        accountFailed: _accountFailed,
        metricsFailed: _metricsFailed,
        goalsFailed: _goalsFailed,
      ),
    );
  }
}

/// 只读月历路由：owner 变化时退出，不把上一个账号的投影留在屏幕上。
class _FocusMonthRoute extends ConsumerWidget {
  const _FocusMonthRoute({
    required this.ownerUserId,
    required this.repository,
    required this.profileRepository,
    required this.now,
  });

  final String? ownerUserId;
  final FocusRepository repository;
  final ProfileRepository profileRepository;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authUserIdProvider) != ownerUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const SizedBox.shrink();
    }
    return FocusMonthPage(
      repository: repository,
      accountTimeZoneIds: () => profileRepository.watchProfile().map(
        (profile) => profile.displayTimeZoneId,
      ),
      now: now,
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({
    required this.displayTimeZoneId,
    required this.now,
    required this.repository,
    required this.focusRepository,
    required this.nationalFocusRepository,
    required this.scheduleRepository,
    required this.onOpenNationalFocus,
    required this.onOpenPlan,
    required this.onOpenFocusMonth,
    required this.goals,
    required this.metrics,
    required this.accountFailed,
    required this.metricsFailed,
    required this.goalsFailed,
    required this.onRetryProjection,
  });

  final String displayTimeZoneId;

  /// Shared display clock: the board's "today" must be the same day the Plan
  /// calendar starts on, so an injected clock fixes both surfaces at once.
  final DateTime Function() now;
  final TaskRepository repository;
  final FocusRepository focusRepository;
  final NationalFocusRepository nationalFocusRepository;
  final ScheduleRepository scheduleRepository;
  final VoidCallback onOpenNationalFocus;
  final VoidCallback onOpenPlan;
  final VoidCallback onOpenFocusMonth;
  final List<Goal> goals;
  final FocusDashboardMetrics? metrics;

  /// 账号资料读取失败：时区退回统一兜底值，卡片里要说明这一点。
  final bool accountFailed;

  /// 近期投影读取失败。失败不能被当成"暂无数据"渲染；
  /// 卡片给出可见说明和只读重试。
  final bool metricsFailed;

  /// 目标列表读取失败；同样不能静默显示成"没有置顶目标"。
  final bool goalsFailed;
  final VoidCallback onRetryProjection;

  @override
  Widget build(BuildContext context) {
    final pinned = [
      for (final goal in goals)
        if (goal.isPinned) goal,
    ];
    final gutter = PactaSpacing.gutterFor(MediaQuery.sizeOf(context).width);
    final header = PactaPageHeader(
      title: '今天先做什么',
      trailing: TextButton.icon(
        onPressed: onOpenPlan,
        icon: const Icon(Icons.event_note_outlined),
        label: const Text('打开计划'),
      ),
    );
    final primary = <Widget>[
      _TodayArrangementsCard(
        repository: scheduleRepository,
        displayTimeZoneId: displayTimeZoneId,
        now: now,
        onOpenPlan: onOpenPlan,
      ),
      const SizedBox(height: 8),
      _FocusReconciliationPrompt(
        focusRepository: focusRepository,
        taskRepository: repository,
      ),
      _FocusClockReviewPrompt(repository: focusRepository),
      _FailureReviewPrompt(
        repository: nationalFocusRepository,
        displayTimeZoneId: displayTimeZoneId,
      ),
      const SizedBox(height: 8),
      _PinnedGoalSummarySection(
        repository: repository,
        goals: pinned,
        onOpenPlan: onOpenPlan,
        failed: goalsFailed,
        onRetry: onRetryProjection,
      ),
    ];
    final secondary = <Widget>[
      NationalFocusSummaryCard(
        repository: nationalFocusRepository,
        onOpenTree: onOpenNationalFocus,
      ),
      const SizedBox(height: 12),
      _RecentFocusActivityCard(
        metrics: metrics,
        failed: metricsFailed,
        accountFailed: accountFailed,
        onRetry: onRetryProjection,
        onOpenFocusMonth: onOpenFocusMonth,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn =
            constraints.maxWidth >= 960 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.6;
        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, PactaSpacing.lg, gutter, 28),
          children: [
            // 页头横跨整个目的地宽度：宽屏两栏时尾部操作仍在页面右缘，
            // 与计划/专注链/国策/我的保持同一条标题行。
            header,
            if (twoColumn)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: primary,
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: secondary,
                    ),
                  ),
                ],
              )
            else ...[
              ...primary,
              const SizedBox(height: 20),
              ...secondary,
            ],
          ],
        );
      },
    );
  }
}

/// 看板今日安排：只读摘要，安排的管理动作全部在计划页。
class _TodayArrangementsCard extends StatelessWidget {
  const _TodayArrangementsCard({
    required this.repository,
    required this.displayTimeZoneId,
    required this.now,
    required this.onOpenPlan,
  });

  final ScheduleRepository repository;
  final String displayTimeZoneId;
  final DateTime Function() now;
  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final today = scheduleToday(displayTimeZoneId, now: now());
    final window = scheduleQueryWindow(today, displayTimeZoneId);
    return StreamBuilder<List<Schedule>>(
      stream: repository.watchSchedules(from: window.from, to: window.to),
      builder: (context, snapshot) {
        final todays = schedulesOnDay(
          snapshot.data ?? const <Schedule>[],
          today,
          displayTimeZoneId,
        );
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 48dp 行内按钮会把单行标题垂直居中，标题距顶部被撑到约 29dp；
              // 统一头部把标题视觉顶距固定为 16dp，上下才对称。
              PactaCardHeader(
                title: '今天 · ${todays.length} 项安排',
                trailing: TextButton(
                  onPressed: onOpenPlan,
                  child: const Text('安排'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (todays.isEmpty)
                      Text(
                        '今天还没有安排。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      for (final schedule in todays)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              PactaCheckCircle(
                                value: schedule.isCompleted,
                                onChanged: null,
                                compact: true,
                                semanticLabel: schedule.isCompleted
                                    ? '已完成'
                                    : '未完成',
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  schedule.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: schedule.isCompleted
                                      ? const TextStyle(
                                          decoration:
                                              TextDecoration.lineThrough,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                scheduleTimeLabel(schedule, displayTimeZoneId),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 置顶目标摘要：标题 + 下一项任务；无任务时显示空态，不伪造占位任务。
///
/// 与计划页共用同一列 `local_goals.sort_order`：按住拖动即时写回，
/// 两处看到的顺序始终一致；按住原地不动则打开操作面板。
class _PinnedGoalSummarySection extends StatelessWidget {
  const _PinnedGoalSummarySection({
    required this.repository,
    required this.goals,
    required this.onOpenPlan,
    required this.failed,
    required this.onRetry,
  });

  final TaskRepository repository;
  final List<Goal> goals;
  final VoidCallback onOpenPlan;

  /// 目标列表读取失败时不能渲染成"还没有置顶目标"。
  final bool failed;
  final VoidCallback onRetry;

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final ids = [for (final goal in goals) goal.id];
    final moved = ids.removeAt(oldIndex);
    // PactaHoldReorderList 的 newIndex 已是 post-removal 下标。
    ids.insert(newIndex, moved);
    await repository.reorderPinnedGoals(ids);
  }

  void _openActions(BuildContext context, Goal goal) {
    unawaited(
      showPactaActionSheet(
        context,
        title: goal.title,
        subtitle: goal.nextTask == null
            ? '暂无任务'
            : '下一项：${goal.nextTask!.title}',
        actions: [
          PactaActionItem(
            id: 'open-plan',
            label: '在计划中查看',
            icon: Icons.event_note_outlined,
            onTap: onOpenPlan,
          ),
          PactaActionItem(
            id: 'unpin-goal',
            label: '取消置顶',
            icon: Icons.push_pin_outlined,
            onTap: () =>
                unawaited(repository.setGoalPinned(goal.id, isPinned: false)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('置顶目标', style: theme.textTheme.titleMedium)),
            TextButton(onPressed: onOpenPlan, child: const Text('管理')),
          ],
        ),
        if (failed)
          _BoardReadFailure(message: '暂时不能读取目标列表。', onRetry: onRetry)
        else if (goals.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('还没有置顶目标'),
              subtitle: const Text('在计划里置顶多个目标并手动排序，这里只显示摘要与下一项任务。'),
              trailing: TextButton(
                onPressed: onOpenPlan,
                child: const Text('去计划'),
              ),
            ),
          )
        else ...[
          Text(
            '按住拖动可调整顺序；按住不动打开操作。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          PactaHoldReorderList(
            itemCount: goals.length,
            onReorder: _reorder,
            onHoldMenu: (index) => _openActions(context, goals[index]),
            itemBuilder: (context, index) {
              final goal = goals[index];
              return Card(
                key: ValueKey('board-pinned-goal-${goal.id}'),
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: const Icon(Icons.push_pin, size: 20),
                  title: Text(
                    goal.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    goal.nextTask == null
                        ? '暂无任务'
                        : '下一项：${goal.nextTask!.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// 看板可读失败的最小呈现：说明 + 只读重试（只重新订阅，不写数据）。
class _BoardReadFailure extends StatelessWidget {
  const _BoardReadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _RecentFocusActivityCard extends StatelessWidget {
  const _RecentFocusActivityCard({
    required this.metrics,
    required this.failed,
    required this.accountFailed,
    required this.onRetry,
    required this.onOpenFocusMonth,
  });

  final FocusDashboardMetrics? metrics;

  /// 读取失败且没有可用值时，显示可见错误而不是一直转圈；重试只换订阅。
  final bool failed;

  /// 账号时区没有读到：数字仍按统一兜底时区显示，但必须说明来源。
  final bool accountFailed;
  final VoidCallback onRetry;
  final VoidCallback onOpenFocusMonth;

  @override
  Widget build(BuildContext context) {
    final value = metrics;
    final hasRecentActivity =
        value?.recentActivity.any((day) => day.activeSeconds > 0) ?? false;
    // The label promises a seven-day window; the lifetime total is a different
    // number and must not be shown under it.
    final recentSeconds =
        value?.recentActivity.fold<int>(
          0,
          (sum, day) => sum + day.activeSeconds,
        ) ??
        0;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 与今日安排、国策状态共用同一个头部基线：标题视觉顶距 16dp。
          PactaCardHeader(
            title: '近期专注活动',
            trailing: TextButton.icon(
              onPressed: onOpenFocusMonth,
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('打开月历'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (accountFailed)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('暂时不能确认账号时区，以下按 UTC 显示。')),
                      ],
                    ),
                  ),
                if (value == null)
                  if (failed)
                    _BoardReadFailure(message: '暂时不能读取专注投影。', onRetry: onRetry)
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                else ...[
                  Text(
                    '近 7 天 · 累计有效专注 '
                    '${formatEffectiveDuration(recentSeconds)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (value.hasPendingReview)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('存在待核对专注记录；争议部分暂不计入上述统计。'),
                    ),
                  const SizedBox(height: 12),
                  if (!hasRecentActivity)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.timelapse_outlined),
                          SizedBox(width: 10),
                          Expanded(child: Text('近 7 天暂无专注活动。')),
                        ],
                      ),
                    )
                  else
                    for (final day in value.recentActivity)
                      _FocusActivityDayRow(
                        day: day,
                        maximumSeconds: value.recentActivity.fold<int>(
                          0,
                          (maximum, item) => item.activeSeconds > maximum
                              ? item.activeSeconds
                              : maximum,
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusActivityDayRow extends StatelessWidget {
  const _FocusActivityDayRow({required this.day, required this.maximumSeconds});

  final FocusActivityDay day;
  final int maximumSeconds;

  @override
  Widget build(BuildContext context) {
    final dayName = switch (day.date.weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      _ => '周日',
    };
    final label = '${day.date.month}月${day.date.day}日 · $dayName';
    final progress = maximumSeconds == 0
        ? 0.0
        : (day.activeSeconds / maximumSeconds).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        label: '$label，${formatEffectiveDuration(day.activeSeconds)}',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final bar = ExcludeSemantics(
              child: LinearProgressIndicator(value: progress),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(label),
                      Text(formatEffectiveDuration(day.activeSeconds)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  bar,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 118, child: Text(label)),
                Expanded(child: bar),
                const SizedBox(width: 12),
                SizedBox(
                  width: 68,
                  child: Text(
                    formatEffectiveDuration(day.activeSeconds),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
