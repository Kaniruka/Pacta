import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../focus/focus_clock_review_page.dart';
import '../focus/focus_models.dart';
import '../focus/focus_month_page.dart';
import '../focus/focus_repository.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import '../national_focus/national_focus_tree_page.dart';
import '../profile/account_time_zone.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../schedules/schedule_repository.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_hold_action_reorder.dart';
import '../ui/pacta_page_header.dart';
import 'focus_national_calendar_card.dart';

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
      builder: (context, projection) => _BoardContent(
        displayTimeZoneId: projection.displayTimeZoneId,
        zoneResolved: projection.zoneResolved,
        now: ref.read(displayClockProvider),
        repository: taskRepository,
        focusRepository: focusRepository,
        nationalFocusRepository: nationalFocusRepository,
        scheduleRepository: scheduleRepository,
        onOpenNationalFocus: widget.onOpenNationalFocus,
        onOpenPlan: widget.onOpenPlan,
        onOpenFocusMonth: _openFocusMonth,
        goals: projection.goals,
        accountFailed: projection.accountFailed,
        goalsFailed: projection.goalsFailed,
        onRetryProjection: _retryProjection,
      ),
    );
  }
}

/// 看板一次读取的结果：账号时区门禁、目标与失败标记。
///
/// 专注月投影不再由看板订阅：融合卡片拿到 [zoneResolved] 与账号时区后
/// 自己按展示月份查询，因此换仓储/换时区时旧数字不会留在屏上。
class _BoardProjection {
  const _BoardProjection({
    required this.displayTimeZoneId,
    required this.zoneResolved,
    required this.goals,
    required this.accountFailed,
    required this.goalsFailed,
  });

  final String displayTimeZoneId;

  /// 账号时区是否已经解析（首次值或首次错误都算解析完成）。
  ///
  /// 为 false 时看板不发起任何专注投影查询，也不画兜底 UTC 的数字。
  final bool zoneResolved;

  final List<Goal> goals;

  /// 账号资料读取失败：时区按统一兜底值显示，但屏幕必须说明这一点。
  final bool accountFailed;

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
    required this.builder,
  });

  final ProfileRepository profileRepository;
  final TaskRepository taskRepository;
  final Widget Function(BuildContext context, _BoardProjection projection)
  builder;

  @override
  State<_BoardProjectionScope> createState() => _BoardProjectionScopeState();
}

class _BoardProjectionScopeState extends State<_BoardProjectionScope> {
  StreamSubscription<ProfileAccount>? _profileSubscription;
  StreamSubscription<List<Goal>>? _goalsSubscription;
  String _displayTimeZoneId = AccountTimeZones.fallbackId;
  List<Goal> _goals = const [];
  bool _accountFailed = false;
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
        _apply(() {
          _accountFailed = false;
          _profileResolved = true;
          // 换时区时只更新门禁与账号时区：融合卡片以 (时区, 月份) 为订阅
          // 身份，自己丢弃上一个时区的投影，屏上不会出现旧数字。
          _displayTimeZoneId = nextZone;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        _apply(() {
          _accountFailed = true;
          _profileResolved = true;
        });
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

  @override
  Widget build(BuildContext context) {
    _hasBuilt = true;
    return widget.builder(
      context,
      _BoardProjection(
        displayTimeZoneId: _displayTimeZoneId,
        zoneResolved: _profileResolved,
        goals: _goals,
        accountFailed: _accountFailed,
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
    required this.zoneResolved,
    required this.now,
    required this.repository,
    required this.focusRepository,
    required this.nationalFocusRepository,
    required this.scheduleRepository,
    required this.onOpenNationalFocus,
    required this.onOpenPlan,
    required this.onOpenFocusMonth,
    required this.goals,
    required this.accountFailed,
    required this.goalsFailed,
    required this.onRetryProjection,
  });

  final String displayTimeZoneId;

  /// 账号时区是否已解析；未解析时融合卡片不查询、也不画兜底数字。
  final bool zoneResolved;

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

  /// 账号资料读取失败：时区退回统一兜底值，卡片里要说明这一点。
  final bool accountFailed;

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
      title: '看板',
      trailing: TextButton.icon(
        onPressed: onOpenPlan,
        icon: const Icon(Icons.event_note_outlined),
        label: const Text('打开计划'),
      ),
    );
    // 空置顶目标完全隐藏：没有置顶、也没有读取失败时，整块「置顶目标」
    // 标题、「管理」入口与空卡片都不存在，融合卡直接贴着页头。
    final showPinnedSection = pinned.isNotEmpty || goalsFailed;
    final pinnedSection = showPinnedSection
        ? _PinnedGoalSummarySection(
            repository: repository,
            goals: pinned,
            onOpenPlan: onOpenPlan,
            failed: goalsFailed,
            onRetry: onRetryProjection,
          )
        : null;
    // 两个回顾提示在有内容时自带 bottom: 8 的间距、无内容时是零高度；
    // 外面不再套固定 SizedBox，避免顶部凭空多出 16dp 死空间。
    final prompts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusClockReviewPrompt(repository: focusRepository),
        _FailureReviewPrompt(
          repository: nationalFocusRepository,
          displayTimeZoneId: displayTimeZoneId,
        ),
      ],
    );
    // 原「国策状态」「近期专注活动」以及独立的「今日安排」融合为一张：
    // 今日国策实时状态直达国策树，热力月历与日期详情直达完整月历，当天
    // 安排只读地并进日期详情，不再各占一张卡。
    final fusedCard = FocusNationalCalendarCard(
      focusRepository: focusRepository,
      nationalFocusRepository: nationalFocusRepository,
      scheduleRepository: scheduleRepository,
      displayTimeZoneId: zoneResolved ? displayTimeZoneId : null,
      now: now,
      accountFailed: accountFailed,
      onOpenNationalFocus: onOpenNationalFocus,
      onOpenFocusMonth: onOpenFocusMonth,
      onRetryProjection: onRetryProjection,
    );
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
              showPinnedSection
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [pinnedSection!, prompts],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // 420dp 让桌面七列月历更舒展；320dp 会把第七列
                        // 压到 43dp 以下，选中描边挤在一起。
                        SizedBox(
                          width: 420,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [fusedCard],
                          ),
                        ),
                      ],
                    )
                  // 没有置顶目标就不画左侧空栏：融合卡居中单栏、最多
                  // 720dp，不再被挤进右侧 320dp 的窄列。
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        prompts,
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: fusedCard,
                          ),
                        ),
                      ],
                    )
            else ...[
              // 单栏顺序：置顶（若有）→ 回顾提示 → 融合卡。无置顶时没有
              // 任何占位，融合卡紧贴页头；提示为空时高度为 0。
              if (pinnedSection != null) ...[
                pinnedSection,
                const SizedBox(height: 16),
              ],
              prompts,
              fusedCard,
            ],
          ],
        );
      },
    );
  }
}

/// 置顶目标摘要：标题 + 下一项任务。
///
/// 只有「有置顶目标」或「目标列表读取失败」时才由看板构建本区块：
/// 空置顶目标不再渲染标题、管理入口或空卡片，也不伪造占位任务。
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
          // 读取失败必须可见：绝不能让失败静默成“没有置顶目标”。
          _BoardReadFailure(message: '暂时不能读取目标列表。', onRetry: onRetry)
        else ...[
          Text(
            '按住拖动可调整顺序；按住不动打开操作。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          PactaHoldReorderList(
            itemCount: goals.length,
            // 间距交给列表：拖拽代理的高亮描边只包卡片本体，与 20dp 圆角
            // 严丝合缝，不会把顶部间距一起框进高亮里。
            itemSpacing: 8,
            proxyBorderRadius: PactaSpacing.cardRadius,
            onReorder: _reorder,
            onHoldMenu: (index) => _openActions(context, goals[index]),
            itemBuilder: (context, index) {
              final goal = goals[index];
              return Card(
                key: ValueKey('board-pinned-goal-${goal.id}'),
                margin: EdgeInsets.zero,
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
