import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../focus/focus_models.dart';
import '../focus/focus_repository.dart';
import '../profile/account_time_zone.dart';
import '../profile/profile_models.dart';
import '../schedules/schedule_repository.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_hold_action_reorder.dart';
import '../ui/pacta_page_header.dart';
import 'goal_task_cards.dart';
import 'goal_view_preferences.dart';
import 'plan_calendar_view.dart';
import 'plan_target.dart';

enum _PlanView { goals, calendar }

/// 计划目的地：目标与日历两个视图，承载既有目标/任务管理与自有日程。
///
/// 显示时区由调用方以账号值解析后传入（02 合并前是适配器），本页不读取
/// 设备级显示偏好；目标/任务的创建、编辑、完成、删除都在这里完成。

class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({
    super.key,
    required this.displayTimeZoneLoader,
    this.navigationTarget,
    this.goalViewPreferences = const GoalViewPreferences(),
  });

  final Future<String> Function() displayTimeZoneLoader;

  /// 每个目标独立的"隐藏已完成"设备偏好；测试可注入替身。
  final GoalViewPreferences goalViewPreferences;

  /// 普通安排提醒点开的目标（06 通知）；null 表示正常进入计划页。
  final PlanTarget? navigationTarget;

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  late var _view = widget.navigationTarget == null
      ? _PlanView.goals
      : _PlanView.calendar;
  late final Future<String> _fallbackDisplayTimeZoneId = widget
      .displayTimeZoneLoader();

  /// 键是 “用户::目标”，切换账号或目标都不会串门。
  final Map<String, bool> _hideCompletedByGoal = <String, bool>{};
  final Set<String> _hideCompletedLoading = <String>{};

  /// 内容区左右滑动与分段按钮共用同一个页码。
  late final PageController _pageController = PageController(
    initialPage: _pageOf(_view),
  );

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 页序显式映射：不把枚举序号当页码，改枚举顺序不会静默错位。
  static int _pageOf(_PlanView view) => switch (view) {
    _PlanView.goals => 0,
    _PlanView.calendar => 1,
  };

  static _PlanView _viewOfPage(int page) => switch (page) {
    0 => _PlanView.goals,
    _ => _PlanView.calendar,
  };

  /// 内容区横向拖动累计量（dp）：判定阈值用，不做跟手位移。
  double _dragDx = 0;
  double _dragDy = 0;

  int get _currentPage => _pageController.hasClients
      ? (_pageController.page?.round() ?? _pageOf(_view))
      : _pageOf(_view);

  /// 原始指针位移：水平识别器只上报 dx，斜率判定必须自己累计 dy。
  void _onPointerDown(PointerDownEvent event) {
    _dragDx = 0;
    _dragDy = 0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _dragDx += event.delta.dx;
    _dragDy += event.delta.dy;
  }

  /// 定案门槛：水平位移 >24dp 且 |dx| > 1.5|dy| 才翻页。
  /// 斜滑、短拖、以及点按造成的微小位移都停在原页。
  void _onHorizontalDragEnd(DragEndDetails details) {
    final dx = _dragDx;
    final dy = _dragDy.abs();
    _dragDx = 0;
    _dragDy = 0;
    if (dx.abs() <= 24 || dx.abs() <= dy * 1.5) return;
    final target = dx < 0 ? _currentPage + 1 : _currentPage - 1;
    if (target < 0 || target > 1) return;
    _selectView(_viewOfPage(target));
  }

  void _selectView(_PlanView next) {
    if (_view == next) return;
    setState(() => _view = next);
    if (!_pageController.hasClients) return;
    final target = _pageOf(next);
    final current = _pageController.page?.round();
    if (current == target) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(PlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationTarget == null ||
        widget.navigationTarget == oldWidget.navigationTarget) {
      return;
    }
    setState(() => _view = _PlanView.calendar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_pageOf(_PlanView.calendar));
    });
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final scheduleRepository = ref.watch(scheduleRepositoryProvider);
    final profileRepository = ref.watch(profileRepositoryProvider);
    // 账号时区是页面唯一的显示来源：资料流更新（含另一台设备写入）后
    // 日历与目标卡立即按新时区重建；设备时区只在资料为空时提供固定 fallback。
    return FutureBuilder<String>(
      future: _fallbackDisplayTimeZoneId,
      builder: (context, fallbackSnapshot) => StreamBuilder<ProfileAccount>(
        stream: profileRepository.watchProfile(),
        builder: (context, profileSnapshot) {
          final displayTimeZoneId = profileSnapshot.hasData
              ? AccountTimeZones.effectiveId(
                  profileSnapshot.data!.displayTimeZoneId,
                )
              : (fallbackSnapshot.data ?? 'Etc/UTC');
          return StreamBuilder<List<Goal>>(
            stream: taskRepository.watchGoals(),
            initialData: const [],
            builder: (context, snapshot) {
              final goals = snapshot.data ?? const <Goal>[];
              // 页头始终从 16 起排，与其它目的地一致；日历页自己的左右
              // 内边距收到 12，360 宽下 7 列仍保有 ≥48×48 的命中区
              // （(360-24)/7 = 48）。头部不参与横向滑动。
              final width = MediaQuery.sizeOf(context).width;
              final gutter = PactaSpacing.gutterFor(width);
              // 日历在窄屏收到 12：360 宽下 7 列仍保有 ≥48 的命中区
              // （(360-24)/7 = 48），宽屏回到统一页边距。
              final calendarGutter = PactaSpacing.isWide(width)
                  ? gutter
                  : PactaSpacing.md;
              return Column(
                // 宽屏下让页头铺满内容宽度，标题才与其它目的地一样靠左。
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      PactaSpacing.lg,
                      gutter,
                      0,
                    ),
                    child: PactaPageHeader(
                      title: '计划',
                      trailing: SegmentedButton<_PlanView>(
                        segments: const [
                          ButtonSegment(
                            value: _PlanView.goals,
                            icon: Icon(Icons.flag_outlined),
                            label: Text('目标'),
                          ),
                          ButtonSegment(
                            value: _PlanView.calendar,
                            icon: Icon(Icons.calendar_month_outlined),
                            label: Text('日历'),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (selection) =>
                            _selectView(selection.first),
                      ),
                    ),
                  ),
                  // 头部留在滑动区之外：分段控件与标题不随页面移动。
                  Expanded(
                    // 手势只在这一层：拖动累计到阈值才翻页，点按仍落到格子和按钮上。
                    child: Listener(
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      child: GestureDetector(
                        onHorizontalDragEnd: _onHorizontalDragEnd,
                        child: PageView.builder(
                          controller: _pageController,
                          // 拖动由上面的门槛接管；这里只保留页码吸附与程序化跳转。
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 2,
                          onPageChanged: (page) =>
                              setState(() => _view = _viewOfPage(page)),
                          itemBuilder: (context, page) => page == 0
                              ? ListView(
                                  padding: EdgeInsets.fromLTRB(
                                    gutter,
                                    PactaSpacing.md,
                                    gutter,
                                    PactaSpacing.xl,
                                  ),
                                  children: _buildGoals(
                                    context,
                                    taskRepository,
                                    goals,
                                    displayTimeZoneId,
                                  ),
                                )
                              // 宽屏下日历不跟着铺满 960：格宽过大时日期反而
                              // 更难扫读，内容收在 720 以内并居中。
                              : Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 720,
                                    ),
                                    child: ListView(
                                      padding: EdgeInsets.fromLTRB(
                                        calendarGutter,
                                        PactaSpacing.md,
                                        calendarGutter,
                                        PactaSpacing.xl,
                                      ),
                                      children: [
                                        _buildCalendar(
                                          context,
                                          taskRepository,
                                          scheduleRepository,
                                          goals,
                                          displayTimeZoneId,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildGoals(
    BuildContext context,
    TaskRepository taskRepository,
    List<Goal> goals,
    String displayTimeZoneId,
  ) {
    final userId = ref.watch(authUserIdProvider) ?? '';
    final focusRepository = ref.watch(focusRepositoryProvider);
    final pinned = [
      for (final goal in goals)
        if (goal.isPinned) goal,
    ];
    final others = [
      for (final goal in goals)
        if (!goal.isPinned) goal,
    ];
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '目标与任务',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: () => _createGoal(context, taskRepository),
            icon: const Icon(Icons.add),
            label: const Text('新建目标'),
          ),
        ],
      ),
      if (goals.isEmpty) ...[
        // 标题行与空态卡之间留一档：否则卡片顶边与「新建目标」按钮 0dp 贴合。
        const SizedBox(height: PactaSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.inbox_outlined, size: 48),
                const SizedBox(height: 12),
                Text('还没有目标', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('新建目标后在这里管理任务；看板只显示置顶目标摘要。'),
              ],
            ),
          ),
        ),
      ],
      if (pinned.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionLabel(context, '置顶目标 · 长按拖动排序'),
        // 置顶与其他目标各用一份独立列表：跨分组拖动没有意义，
        // 分组内排序又分别落到 local_goals.sort_order 的同一列。
        PactaHoldReorderList(
          itemCount: pinned.length,
          onReorder: (oldIndex, newIndex) => _reorderGoals(
            taskRepository,
            pinned,
            oldIndex,
            newIndex,
            pinned: true,
          ),
          onHoldMenu: (index) => unawaited(
            _openGoalActions(context, taskRepository, pinned[index], userId),
          ),
          // 12dp 行距由列表提供：拖拽代理只包 GoalCard 本体，高亮描边与
          // 阴影因此贴合卡片 20dp 圆角，不会把间距一起框进去。
          itemSpacing: PactaSpacing.md,
          itemBuilder: (context, index) => KeyedSubtree(
            key: ValueKey('pinned-goal-${pinned[index].id}'),
            child: _goalCard(
              context,
              taskRepository,
              focusRepository,
              pinned[index],
              userId: userId,
              displayTimeZoneId: displayTimeZoneId,
            ),
          ),
        ),
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        _sectionLabel(
          context,
          pinned.isEmpty ? '全部目标 · 长按拖动排序' : '其他目标 · 长按拖动排序',
        ),
        PactaHoldReorderList(
          itemCount: others.length,
          onReorder: (oldIndex, newIndex) => _reorderGoals(
            taskRepository,
            others,
            oldIndex,
            newIndex,
            pinned: false,
          ),
          onHoldMenu: (index) => unawaited(
            _openGoalActions(context, taskRepository, others[index], userId),
          ),
          itemSpacing: PactaSpacing.md,
          itemBuilder: (context, index) => KeyedSubtree(
            key: ValueKey('goal-${others[index].id}'),
            child: _goalCard(
              context,
              taskRepository,
              focusRepository,
              others[index],
              userId: userId,
              displayTimeZoneId: displayTimeZoneId,
            ),
          ),
        ),
      ],
    ];
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );

  Widget _goalCard(
    BuildContext context,
    TaskRepository taskRepository,
    FocusRepository focusRepository,
    Goal goal, {
    required String userId,
    required String displayTimeZoneId,
  }) {
    final hidden = _hideCompletedFor(goal, userId);
    return StreamBuilder<FocusDashboardMetrics>(
      stream: focusRepository.watchDashboardMetrics(
        timeZoneId: displayTimeZoneId,
      ),
      builder: (context, metricsSnapshot) {
        final metrics = metricsSnapshot.data;
        return GoalCard(
          key: ValueKey(goal.id),
          repository: taskRepository,
          goal: goal,
          hideCompletedTasks: hidden,
          onToggleHideCompleted: () =>
              unawaited(_toggleHideCompleted(goal, userId)),
          onHoldTask: (task) =>
              unawaited(_openTaskActions(context, taskRepository, task)),
          focusProgressSecondsByTask: metrics?.focusProgressSecondsByTask,
          pendingReviewTaskIds:
              metrics?.pendingReviewTaskIds ?? const <String>{},
        );
      },
    );
  }

  String _hideKey(String userId, String goalId) => '$userId::$goalId';

  /// 读取该目标的隐藏偏好；首帧先按默认的"显示"渲染，读到后再重建。
  bool _hideCompletedFor(Goal goal, String userId) {
    final key = _hideKey(userId, goal.id);
    final cached = _hideCompletedByGoal[key];
    if (cached != null) return cached;
    if (_hideCompletedLoading.add(key)) {
      unawaited(_loadHideCompleted(key, goal.id, userId));
    }
    return false;
  }

  Future<void> _loadHideCompleted(
    String key,
    String goalId,
    String userId,
  ) async {
    final hide = await widget.goalViewPreferences.hideCompletedTasks(
      userId: userId,
      goalId: goalId,
    );
    if (!mounted || _hideCompletedByGoal.containsKey(key)) return;
    setState(() => _hideCompletedByGoal[key] = hide);
  }

  Future<void> _toggleHideCompleted(Goal goal, String userId) async {
    final key = _hideKey(userId, goal.id);
    final next = !(_hideCompletedByGoal[key] ?? false);
    await widget.goalViewPreferences.setHideCompletedTasks(
      userId: userId,
      goalId: goal.id,
      hide: next,
    );
    if (!mounted) return;
    setState(() => _hideCompletedByGoal[key] = next);
  }

  /// 目标手势之一：按住原地不动 → 操作面板；按住上下移动由列表接管排序。
  Future<void> _openGoalActions(
    BuildContext context,
    TaskRepository repository,
    Goal goal,
    String userId,
  ) async {
    final completedCount = goal.tasks.where((task) => task.isComplete).length;
    final hidden = _hideCompletedFor(goal, userId);
    final status = goal.tasks.isEmpty
        ? '暂无任务 · 未完成'
        : goal.isComplete
        ? '已完成'
        : '进行中';
    await showPactaActionSheet(
      context,
      title: goal.title,
      subtitle: '${goal.tasks.length} 项任务 · $status',
      actions: [
        // 「添加任务」不再是卡片底部的大按钮：它是目标菜单的首项，空目标
        // 另有可点的空态引导行，两者都走同一条新建流程。
        PactaActionItem(
          id: 'add-task',
          label: '添加任务',
          icon: Icons.add_task,
          onTap: () => unawaited(_createTask(context, repository, goal)),
        ),
        PactaActionItem(
          id: 'edit-goal',
          label: '编辑目标',
          icon: Icons.edit_outlined,
          onTap: () => unawaited(_editGoal(context, repository, goal)),
        ),
        PactaActionItem(
          id: 'toggle-goal-pin',
          label: goal.isPinned ? '取消置顶' : '置顶目标',
          icon: goal.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          onTap: () => unawaited(
            repository.setGoalPinned(goal.id, isPinned: !goal.isPinned),
          ),
        ),
        if (completedCount > 0)
          PactaActionItem(
            id: 'toggle-hide-completed',
            label: hidden ? '显示已完成任务' : '隐藏已完成任务',
            icon: hidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            onTap: () => unawaited(_toggleHideCompleted(goal, userId)),
          ),
        PactaActionItem(
          id: 'delete-goal',
          label: '删除目标',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => unawaited(confirmDeleteGoal(context, repository, goal)),
        ),
      ],
    );
  }

  /// 任务手势之一：按住原地不动 → 操作面板（拖拽排序由内层列表接管）。
  Future<void> _openTaskActions(
    BuildContext context,
    TaskRepository repository,
    Task task,
  ) async {
    await showPactaActionSheet(
      context,
      title: task.title,
      subtitle: task.isComplete ? '已完成' : '未完成',
      actions: [
        if (!task.isComplete)
          PactaActionItem(
            id: 'start-focus',
            label: '开始专注',
            icon: Icons.play_arrow_rounded,
            onTap: () => unawaited(
              startFocusForTask(
                context: context,
                ref: ref,
                repository: repository,
                task: task,
              ),
            ),
          ),
        PactaActionItem(
          id: 'toggle-task-completion',
          label: task.isComplete ? '标记未完成' : '标记完成',
          icon: task.isComplete
              ? Icons.undo_outlined
              : Icons.check_circle_outline,
          onTap: () => unawaited(
            repository.setTaskCompletion(task.id, isComplete: !task.isComplete),
          ),
        ),
        PactaActionItem(
          id: 'edit-task',
          label: '编辑任务',
          icon: Icons.edit_outlined,
          onTap: () => unawaited(_editTask(context, repository, task)),
        ),
        PactaActionItem(
          id: 'delete-task',
          label: '删除任务',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => unawaited(confirmDeleteTask(context, repository, task)),
        ),
      ],
    );
  }

  Future<void> _createTask(
    BuildContext context,
    TaskRepository repository,
    Goal goal,
  ) async {
    final draft = await showTaskDialog(context, goal: goal);
    if (draft == null) return;
    await repository.createTask(goal.id, draft);
  }

  Future<void> _editGoal(
    BuildContext context,
    TaskRepository repository,
    Goal goal,
  ) async {
    final draft = await showGoalDialog(context, initial: goal);
    if (draft == null) return;
    await repository.updateGoal(goal.id, draft);
  }

  Future<void> _editTask(
    BuildContext context,
    TaskRepository repository,
    Task task,
  ) async {
    final draft = await showTaskDialog(context, task: task);
    if (draft == null) return;
    await repository.updateTask(task.id, draft);
  }

  /// onReorder 的 newIndex 已是 post-removal 下标：先移除再插入，不再修正。
  Future<void> _reorderGoals(
    TaskRepository repository,
    List<Goal> group,
    int oldIndex,
    int newIndex, {
    required bool pinned,
  }) async {
    final ids = [for (final goal in group) goal.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    if (pinned) {
      await repository.reorderPinnedGoals(ids);
    } else {
      await repository.reorderUnpinnedGoals(ids);
    }
  }

  /// 日历要能读出"已删除的任务"名称：按普通目标列表变化时刷新一次带墓碑的读取。
  List<Goal>? _calendarGoalsSource;
  Future<List<Goal>>? _calendarGoalsFuture;

  Future<List<Goal>> _calendarGoals(
    TaskRepository repository,
    List<Goal> goals,
  ) {
    if (!identical(_calendarGoalsSource, goals)) {
      _calendarGoalsSource = goals;
      _calendarGoalsFuture = repository.getGoals(includeDeleted: true);
    }
    return _calendarGoalsFuture!;
  }

  Widget _buildCalendar(
    BuildContext context,
    TaskRepository taskRepository,
    ScheduleRepository scheduleRepository,
    List<Goal> goals,
    String displayTimeZoneId,
  ) {
    return FutureBuilder<List<Goal>>(
      future: _calendarGoals(taskRepository, goals),
      builder: (context, goalSnapshot) => PlanCalendarView(
        repository: scheduleRepository,
        goals: goalSnapshot.data ?? goals,
        displayTimeZoneId: displayTimeZoneId,
        calendarRepository: ref.watch(calendarRepositoryProvider),
        initialDay: widget.navigationTarget?.day,
        highlightScheduleId: widget.navigationTarget?.scheduleId,
        // 与专注倒计时共用同一个注入时钟：日期、今天标记和月视图都能
        // 在同一份 fixture 里被固定，页面不各自读取系统时间。
        now: ref.watch(displayClockProvider),
      ),
    );
  }

  Future<void> _createGoal(
    BuildContext context,
    TaskRepository taskRepository,
  ) async {
    final draft = await showGoalDialog(context);
    if (draft != null) await taskRepository.createGoal(draft);
  }
}
