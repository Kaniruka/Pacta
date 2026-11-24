import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../focus/effective_duration_text.dart';
import '../focus/focus_flow_helpers.dart';
import '../focus/focus_models.dart';
import '../focus/focus_session_pages.dart';
import '../focus/focus_setup_dialog.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_check_circle.dart';
import '../ui/pacta_date_format.dart';
import '../ui/pacta_hold_action_reorder.dart';

/// 未完成任务行的圆角：拖拽代理、按住水波纹与空态起手行共用同一个 12dp。
const double _taskRowRadius = 12;

/// 任务行拖拽代理的实底：与卡片自身底色同值，且强制完全不透明。
///
/// 任务行本身没有 [Card]：没有实底时，拖拽动画刚产生 elevation 的那几帧
/// 阴影会从透明区域透出来，在目标卡上留下孤立暗块。
Color _taskProxyBaseColor(BuildContext context) {
  final theme = Theme.of(context);
  // cardTheme 是卡片底色的唯一来源；宿主没注入主题扩展时按亮度取同一份
  // 语义令牌，绝不让断言把组件树打穿。
  final base = theme.cardTheme.color ?? PactaSurfaces.cardFor(theme.brightness);
  return base.withValues(alpha: 1);
}

/// 浮起后的代理底色：卡片实底上叠一档 surfaceContainerHigh 的抬升色调。
///
/// 结果强制 alpha = 1：动画 t = 0..1 全程都是不透明填充，不会有透明穿透。
Color _taskProxyLiftColor(BuildContext context, Color base) {
  final tint = Theme.of(context).colorScheme.surfaceContainerHigh;
  return Color.alphaBlend(
    tint.withValues(alpha: 0.42),
    base,
  ).withValues(alpha: 1);
}

class GoalCard extends StatefulWidget {
  const GoalCard({
    super.key,
    required this.repository,
    required this.goal,
    required this.focusProgressSecondsByTask,
    this.hideCompletedTasks = false,
    this.onToggleHideCompleted,
    this.onHoldTask,
  });

  final TaskRepository repository;
  final Goal goal;

  /// 该目标是否隐藏已完成任务；按（用户, 目标）独立保存在设备偏好里。
  final bool hideCompletedTasks;

  /// 双入口之一：卡片底部的隐藏/显示切换。目标长按菜单提供另一个入口。
  final VoidCallback? onToggleHideCompleted;

  /// 任务行原地长按：由计划页弹出任务操作面板。
  final ValueChanged<Task>? onHoldTask;
  final Map<String, int>? focusProgressSecondsByTask;

  @override
  State<GoalCard> createState() => GoalCardState();
}

class GoalCardState extends State<GoalCard> {
  var _tasksExpanded = true;

  Widget _taskTile(Task task) => TaskTile(
    repository: widget.repository,
    task: widget.focusProgressSecondsByTask == null
        ? task
        : task.copyWith(
            focusProgressSeconds:
                widget.focusProgressSecondsByTask![task.id] ?? 0,
          ),
  );

  /// 已完成任务不参与排序，但仍要能原地长按弹菜单：用禁用的监听器把
  /// 指针认领掉，外层目标菜单才不会同时弹出。
  Widget _completedTaskRow(Task task) {
    final onHoldTask = widget.onHoldTask;
    return PactaHoldReorderListener(
      key: ValueKey('completed-task-${task.id}'),
      index: 0,
      enabled: false,
      onHoldMenu: onHoldTask == null ? null : (_) => onHoldTask(task),
      child: _taskTile(task),
    );
  }

  Future<void> _reorderOpenTasks(
    List<Task> openTasks,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = [for (final task in openTasks) task.id];
    final moved = ids.removeAt(oldIndex);
    // PactaHoldReorderList 已给出 post-removal 下标，不再做 newIndex -= 1。
    ids.insert(newIndex, moved);
    await widget.repository.reorderTasks(widget.goal.id, ids);
  }

  Future<void> _addTask() async {
    final draft = await showTaskDialog(context, goal: widget.goal);
    if (draft == null) return;
    await widget.repository.createTask(widget.goal.id, draft);
  }

  /// 0 任务且展开时的轻量起手行：点一下就是新建任务。
  ///
  /// 「添加任务」按钮已移入目标长按菜单首项，空目标仍保留一键起手体验；
  /// 文案与图标都用主色，保证在卡片底色上达到 AA 对比度。
  Widget _emptyTasksHint(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: const ValueKey('goal-empty-task-hint'),
      onTap: _addTask,
      borderRadius: BorderRadius.circular(_taskRowRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(
              Icons.add_circle_outline,
              size: PactaIconSizes.compact,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: PactaSpacing.sm),
            Flexible(
              child: Text(
                '暂无任务，点击添加',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: PactaFonts.medium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final theme = Theme.of(context);
    // 任务行是透明的：拖拽代理必须自带与卡片同值的实底，阴影才不会穿透。
    final proxyBaseColor = _taskProxyBaseColor(context);
    final completedCount = goal.tasks.where((task) => task.isComplete).length;
    final openTasks = [
      for (final task in goal.tasks)
        if (!task.isComplete) task,
    ];
    final completedTasks = [
      for (final task in goal.tasks)
        if (task.isComplete) task,
    ];
    final status = goal.tasks.isEmpty
        ? '暂无任务 · 未完成'
        : goal.isComplete
        ? '已完成'
        : '进行中';
    final summary = StringBuffer('${goal.tasks.length} 项任务 · $status');
    if (widget.hideCompletedTasks && completedCount > 0) {
      summary.write(' · 已隐藏 $completedCount 项已完成');
    }
    final allCompletedHidden =
        widget.hideCompletedTasks && goal.tasks.isNotEmpty && openTasks.isEmpty;
    // 是否有可展开的内容：决定头部下边距，收起态上下边距因此严格对称。
    final hasExpandedContent =
        goal.tasks.isEmpty ||
        allCompletedHidden ||
        openTasks.isNotEmpty ||
        (!widget.hideCompletedTasks && completedTasks.isNotEmpty) ||
        (completedCount > 0 && widget.onToggleHideCompleted != null);
    final header = Semantics(
      key: ValueKey('goal-header-${goal.id}'),
      container: true,
      expanded: _tasksExpanded,
      button: true,
      value: _tasksExpanded ? '已展开' : '已折叠',
      child: Tooltip(
        message: _tasksExpanded ? '收起任务' : '展开任务',
        child: InkWell(
          onTap: () => setState(() => _tasksExpanded = !_tasksExpanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            // 头部内边距本身承担全部节奏：收起态 16/16 严格对称；展开态底边
            // 收到 12dp，这 12dp 就是头部末行到首条任务的全部间隔，不随
            // "有无描述"或标题行数变化。
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                12,
                (_tasksExpanded && hasExpandedContent) ? 12 : 16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (goal.isPinned)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 3,
                                  right: 4,
                                ),
                                child: Icon(
                                  Icons.push_pin,
                                  size: PactaIconSizes.sm,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                goal.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        if (goal.description.isNotEmpty)
                          Text(
                            goal.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        Text(
                          summary.toString(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 唯一常驻的头部动作：展开/折叠。管理动作全部收进长按菜单，
                  // 窄屏不再出现两排图标把标题挤成两行。图标本体只有 24dp，
                  // 必然矮于右侧两行文字块，不会反向撑高头部。
                  ExcludeSemantics(
                    child: Icon(
                      _tasksExpanded ? Icons.expand_less : Icons.expand_more,
                      size: PactaIconSizes.md,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Card(
      // 卡片自身的边距交给 PactaHoldReorderList(itemSpacing: 12)：拖拽代理
      // 只包卡片本体，高亮描边与阴影才能严丝合缝贴住 20dp 圆角。
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_tasksExpanded && hasExpandedContent)
            // 头部底边已经是精确的 12dp，展开区不再补一段间隔：首条任务顶边
            // 到头部末行文字底边因此恒为 PactaSpacing.md。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (goal.tasks.isEmpty) _emptyTasksHint(context),
                  // 全部任务都已完成并被隐藏时，绝不能显示成"暂无任务"：
                  // 明确说明数量，并给出一步恢复展示的入口。
                  if (allCompletedHidden)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('全部 ${goal.tasks.length} 项任务已完成并隐藏'),
                        if (widget.onToggleHideCompleted != null)
                          TextButton(
                            key: const ValueKey('show-completed-inline'),
                            onPressed: widget.onToggleHideCompleted,
                            child: const Text('显示已完成'),
                          ),
                      ],
                    ),
                  if (openTasks.isNotEmpty)
                    PactaHoldReorderList(
                      itemCount: openTasks.length,
                      onReorder: (oldIndex, newIndex) =>
                          _reorderOpenTasks(openTasks, oldIndex, newIndex),
                      onHoldMenu: widget.onHoldTask == null
                          ? null
                          : (index) => widget.onHoldTask!(openTasks[index]),
                      // 行距由 TaskTile 自身决定：间距加在列表里会让首条任务
                      // 比后续任务多一段顶部空隙。
                      itemSpacing: 0,
                      // 任务行没有 Card：代理内层用与卡片同值的实底铺满
                      // 12dp 圆角本体。外层 Material 仍是 transparent，间距
                      // 区不会被框进高亮（见 pacta_hold_action_reorder）。
                      proxyBorderRadius: _taskRowRadius,
                      proxyBaseColor: proxyBaseColor,
                      proxyBackgroundColor: _taskProxyLiftColor(
                        context,
                        proxyBaseColor,
                      ),
                      itemBuilder: (context, index) => KeyedSubtree(
                        key: ValueKey('task-${openTasks[index].id}'),
                        child: _taskTile(openTasks[index]),
                      ),
                    ),
                  if (!widget.hideCompletedTasks)
                    for (final task in completedTasks) _completedTaskRow(task),
                  // 「添加任务」已移入目标长按菜单首项；底部只保留按目标独立的
                  // 「隐藏/显示已完成」开关，0 任务时由可点的空态引导行承担起手。
                  if (completedCount > 0 &&
                      widget.onToggleHideCompleted != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: widget.hideCompletedTasks
                              ? '显示已完成的 $completedCount 项任务'
                              : '隐藏已完成的 $completedCount 项任务',
                          child: TextButton.icon(
                            onPressed: widget.onToggleHideCompleted,
                            icon: Icon(
                              widget.hideCompletedTasks
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            label: Text(
                              widget.hideCompletedTasks
                                  ? '显示已完成 ($completedCount)'
                                  : '隐藏已完成 ($completedCount)',
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.repository, required this.task});

  final TaskRepository repository;
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadline = task.deadline == null
        ? null
        : '截止 ${formatPactaDateTime(task.deadline!.toLocal())}';
    final hasMeta =
        task.estimatedMinutes != null ||
        task.focusProgressSeconds > 0 ||
        deadline != null;
    final hasDescription = task.description.isNotEmpty;
    final hasSubtitle = hasMeta || hasDescription;
    return ListTile(
      isThreeLine: hasMeta && hasDescription,
      contentPadding: EdgeInsets.zero,
      // 按住水波纹与高亮从按下首帧起就按 12dp 圆角裁切：与拖拽代理同一边界，
      // 行高与 contentPadding 完全不受影响。
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(_taskRowRadius)),
      ),
      titleAlignment: hasSubtitle
          ? ListTileTitleAlignment.top
          : ListTileTitleAlignment.center,
      leading: PactaCheckCircle(
        value: task.isComplete,
        semanticLabel: completionActionLabel(
          task.title,
          isCompleted: task.isComplete,
        ),
        onChanged: (value) =>
            repository.setTaskCompletion(task.id, isComplete: value),
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        // 完成态只改字形：字号/字距仍从主题字阶派生，不另起一套裸 TextStyle。
        style: task.isComplete
            ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: !hasMeta && !hasDescription
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMeta)
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      if (task.estimatedMinutes != null)
                        Text('${task.estimatedMinutes} 分钟'),
                      if (task.focusProgressSeconds > 0)
                        Text(
                          '已专注 ${formatEffectiveDuration(task.focusProgressSeconds)}',
                        ),
                      if (deadline != null) Text(deadline),
                    ],
                  ),
                if (hasDescription)
                  Text(
                    task.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
      // 行内只保留未完成任务的唯一起点：删除等管理动作全部移到长按菜单，
      // 已完成任务右侧不再留任何图标。
      trailing: task.isComplete
          ? null
          : IconButton(
              tooltip: '开始专注',
              onPressed: () => startFocusForTask(
                context: context,
                ref: ref,
                repository: repository,
                task: task,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
      onTap: () async {
        final draft = await showTaskDialog(context, task: task);
        if (draft != null) await repository.updateTask(task.id, draft);
      },
    );
  }
}

/// 开始专注的唯一起点：任务行右侧按钮与任务长按菜单共用同一条路径。
///
/// 已有活动预约/进行中的专注优先交接，其次才打开新的专注设置；
/// 这里不写任务完成状态，专注结束仍由 09/11 的结算逻辑处理。
Future<void> startFocusForTask({
  required BuildContext context,
  required WidgetRef ref,
  required TaskRepository repository,
  required Task task,
}) async {
  final focusRepository = ref.read(focusRepositoryProvider);
  final activeAppointment = await focusRepository.getActiveAppointment();
  if (!context.mounted) return;
  if (activeAppointment != null) {
    final goals = await repository.getGoals(includeDeleted: true);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentPreparationPage(
          appointment: activeAppointment,
          taskTitle: findTaskTitle(goals, activeAppointment.taskId) ?? '原预约任务',
        ),
      ),
    );
    return;
  }
  final activeSession = await focusRepository.getActiveSession();
  if (!context.mounted) return;
  if (activeSession != null) {
    final goals = await repository.getGoals(includeDeleted: true);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FocusSessionPage(
          session: activeSession,
          taskTitle: findTaskTitle(goals, activeSession.taskId) ?? '原任务',
        ),
      ),
    );
    return;
  }
  final mode = await focusRepository.getLastMode();
  if (!context.mounted) return;
  final result = await showDialog<Object>(
    context: context,
    builder: (_) => FocusSetupDialog(
      task: task,
      initialMode: initialFocusModeFor(task.classification, mode),
    ),
  );
  if (result is FocusSession && context.mounted) {
    var taskTitle = task.title;
    if (result.taskId != task.id) {
      final goals = await repository.getGoals(includeDeleted: true);
      if (!context.mounted) return;
      taskTitle = findTaskTitle(goals, result.taskId) ?? '原任务';
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FocusSessionPage(session: result, taskTitle: taskTitle),
      ),
    );
  }
  if (result is AppointmentPreparation && context.mounted) {
    var taskTitle = task.title;
    if (result.taskId != task.id) {
      final goals = await repository.getGoals(includeDeleted: true);
      if (!context.mounted) return;
      taskTitle = findTaskTitle(goals, result.taskId) ?? '原任务';
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentPreparationPage(
          appointment: result,
          taskTitle: taskTitle,
        ),
      ),
    );
  }
}

/// 删除目标的确认框：长按菜单与既有入口共用同一段文案与墓碑语义。
Future<void> confirmDeleteGoal(
  BuildContext context,
  TaskRepository repository,
  Goal goal,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除目标和任务？'),
      content: Text(
        '“${goal.title}”及其全部任务将从工作清单移除，且不能恢复。'
        '已有预约、专注和暂停会继续有效，历史会保留原任务名称并标记为已删除。',
      ),
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
  if (confirmed == true) await repository.deleteGoal(goal.id);
}

Future<void> confirmDeleteTask(
  BuildContext context,
  TaskRepository repository,
  Task task,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除任务？'),
      content: Text(
        '“${task.title}”将从目标中移除，且不能恢复。'
        '已安排到这条任务的日程仍然保留，历史会保留原任务名称并标记为已删除。',
      ),
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
  if (confirmed == true) await repository.deleteTask(task.id);
}

Future<GoalDraft?> showGoalDialog(BuildContext context, {Goal? initial}) {
  return showDialog<GoalDraft>(
    context: context,
    builder: (_) => _GoalDialog(initial: initial),
  );
}

Future<TaskDraft?> showTaskDialog(
  BuildContext context, {
  Goal? goal,
  Task? task,
}) {
  return showDialog<TaskDraft>(
    context: context,
    builder: (_) => _TaskDialog(goal: goal, initial: task),
  );
}

final _descriptionInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.deny(
    RegExp(r'\r\n|[\r\n\u000b\u000c\u0085\u2028\u2029]'),
    replacementString: ' ',
  ),
];

class DescriptionField extends StatelessWidget {
  const DescriptionField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.multiline,
    minLines: 2,
    maxLines: 4,
    maxLength: taskDescriptionMaxGraphemes,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    inputFormatters: _descriptionInputFormatters,
    decoration: const InputDecoration(
      labelText: '描述（可选）',
      helperText: '单段，最多200个字符',
      helperMaxLines: 2,
      alignLabelWithHint: true,
    ),
  );
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({this.initial});

  final Goal? initial;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late TaskClassification _classification;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _description = TextEditingController(text: widget.initial?.description);
    _classification =
        widget.initial?.classification ?? TaskClassification.regular;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建目标' : '编辑目标'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '目标名称'),
          ),
          const SizedBox(height: 12),
          DescriptionField(controller: _description),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskClassification>(
            initialValue: _classification,
            decoration: const InputDecoration(labelText: '新任务默认分类'),
            items: [
              for (final classification in TaskClassification.values)
                DropdownMenuItem(
                  value: classification,
                  child: Text(classification.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _classification = value);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          GoalDraft(
            title: _title.text,
            description: _description.text,
            classification: _classification,
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({this.goal, this.initial});

  final Goal? goal;
  final Task? initial;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _estimatedValue;
  late TaskClassification _classification;
  _EstimateUnit _estimateUnit = _EstimateUnit.minutes;
  String? _estimateError;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _description = TextEditingController(text: widget.initial?.description);
    _estimatedValue = TextEditingController(
      text: widget.initial?.estimatedMinutes?.toString(),
    );
    _classification =
        widget.initial?.classification ??
        widget.goal?.classification ??
        TaskClassification.regular;
    _deadline = widget.initial?.deadline?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimatedValue.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final initialDate = _deadline ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initialDate,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline ?? DateTime.now()),
    );
    if (!mounted || time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  /// 仅防 int 存储溢出（2^53-1，double 可精确表示的最大整数）。
  static const _maxStoredMinutes = 9007199254740991;

  /// 浮点误差级容差：只用于消掉 1/60*60 这类噪声，不改变用户输入。
  static const _minuteEpsilon = 1e-7;

  /// 原始输入折算成的分钟数；空串、非法输入或非有限值返回 null。
  double? _estimatedMinutesValue() {
    final text = _estimatedValue.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    final minutes = value * _estimateUnit.minutesPerUnit;
    if (!minutes.isFinite || minutes <= 0) return null;
    return minutes;
  }

  void _switchEstimateUnit(_EstimateUnit unit) {
    if (unit == _estimateUnit) return;
    final minutes = _estimatedMinutesValue();
    setState(() {
      if (minutes != null) {
        final converted = minutes / unit.minutesPerUnit;
        // 只抹掉浮点噪声（如 1/60*60 = 0.9999999999999999），不截断精度。
        final rounded = converted.roundToDouble();
        final shown = (converted - rounded).abs() <= _minuteEpsilon
            ? rounded
            : converted;
        final text = shown.toString();
        _estimatedValue.text = text.endsWith('.0')
            ? text.substring(0, text.length - 2)
            : text;
      }
      _estimateUnit = unit;
      _estimateError = null;
    });
  }

  /// 空输入表示不设置；统一折算成分钟保存，内部字段仍是分钟。
  int? _parseEstimatedMinutes() {
    final minutes = _estimatedMinutesValue();
    if (minutes == null) return null;
    final rounded = minutes.round();
    if (rounded < 1 || (minutes - rounded).abs() > _minuteEpsilon) return null;
    return rounded;
  }

  bool _validateEstimatedValue() {
    final text = _estimatedValue.text.trim();
    if (text.isEmpty) {
      setState(() => _estimateError = null);
      return true;
    }
    final minutes = _estimatedMinutesValue();
    if (minutes == null) {
      setState(() => _estimateError = '请输入大于 0 的数字，留空表示不设置');
      return false;
    }
    if (minutes > _maxStoredMinutes) {
      setState(() => _estimateError = '数值超出可存储范围，请使用更小的值');
      return false;
    }
    final rounded = minutes.round();
    if (rounded < 1) {
      setState(() => _estimateError = '按分钟至少 1 分钟');
      return false;
    }
    if ((minutes - rounded).abs() > _minuteEpsilon) {
      setState(() => _estimateError = '按分钟需为整数，例如 1.5 小时');
      return false;
    }
    setState(() => _estimateError = null);
    return true;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建任务' : '编辑任务'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '任务名称'),
          ),
          const SizedBox(height: 12),
          DescriptionField(controller: _description),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskClassification>(
            initialValue: _classification,
            decoration: const InputDecoration(labelText: '适用专注链'),
            items: [
              for (final classification in TaskClassification.values)
                DropdownMenuItem(
                  value: classification,
                  child: Text(classification.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _classification = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _estimatedValue,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '预计时长（可选）',
              errorText: _estimateError,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 132,
              child: DropdownButtonFormField<String>(
                initialValue: _estimateUnit.name,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '单位'),
                items: [
                  for (final unit in _EstimateUnit.values)
                    DropdownMenuItem(value: unit.name, child: Text(unit.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _switchEstimateUnit(
                    _EstimateUnit.values.firstWhere(
                      (unit) => unit.name == value,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _deadline == null
                      ? '未设置截止时间'
                      : '截止 ${formatPactaDateTime(_deadline!)}',
                ),
              ),
              IconButton(
                tooltip: '设置截止时间',
                onPressed: _pickDeadline,
                icon: const Icon(Icons.event_outlined),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: '清除截止时间',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!_validateEstimatedValue()) return;
          Navigator.pop(
            context,
            TaskDraft(
              title: _title.text,
              description: _description.text,
              classification: _classification,
              estimatedMinutes: _parseEstimatedMinutes(),
              deadline: _deadline,
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

enum _EstimateUnit {
  minutes('分钟', 1),
  hours('小时', 60);

  const _EstimateUnit(this.label, this.minutesPerUnit);

  final String label;
  final int minutesPerUnit;
}
