import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

class GoalsPage extends ConsumerWidget {
  const GoalsPage({required this.userId, super.key});

  final AppUserId userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(goalTaskSnapshotProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          IconButton(
            key: const Key('goals-add-goal'),
            tooltip: 'Create Goal',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GoalEditorPage(userId: userId),
              ),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: snapshot.when(
        data: (value) {
          if (value.goals.isEmpty) {
            return const Center(child: Text('No Goals yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: value.goals.length,
            itemBuilder: (context, index) {
              final goal = value.goals[index];
              final tasks = value.tasksForGoal(goal.id);
              final complete = value.isGoalComplete(goal.id);
              return Card(
                child: ListTile(
                  key: Key('goal-${goal.id}'),
                  title: Text(goal.title),
                  subtitle: Text(
                    '${complete ? 'Complete' : 'In progress'} · ${tasks.length} Task${tasks.length == 1 ? '' : 's'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          GoalDetailPage(userId: userId, goalId: goal.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
        error: (error, stackTrace) =>
            Center(child: Text('Unable to open Goals: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class GoalEditorPage extends ConsumerStatefulWidget {
  const GoalEditorPage({required this.userId, this.goal, super.key});

  final AppUserId userId;
  final Goal? goal;

  @override
  ConsumerState<GoalEditorPage> createState() => _GoalEditorPageState();
}

class _GoalEditorPageState extends ConsumerState<GoalEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.goal?.title);
    _notesController = TextEditingController(text: widget.goal?.notes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goal == null ? 'Create Goal' : 'Edit Goal'),
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              key: const Key('goal-title-field'),
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Goal title'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('goal-notes-field'),
              controller: _notesController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('save-goal'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save Goal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Enter a Goal title.');
      return;
    }
    setState(() => _saving = true);
    try {
      final goal = await ref
          .read(goalTaskRepositoryProvider)
          .saveGoal(
            widget.userId,
            GoalDraft(
              id: widget.goal?.id,
              title: _titleController.text,
              notes: _emptyToNull(_notesController.text),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              GoalDetailPage(userId: widget.userId, goalId: goal.id),
        ),
      );
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({required this.userId, required this.goalId, super.key});

  final AppUserId userId;
  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(goalTaskSnapshotProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal'),
        actions: [
          IconButton(
            key: const Key('edit-goal'),
            tooltip: 'Edit Goal',
            onPressed: () async {
              final current = await ref
                  .read(goalTaskRepositoryProvider)
                  .read(userId);
              final goal = _goalOrNull(current, goalId);
              if (goal == null || !context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GoalEditorPage(userId: userId, goal: goal),
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: snapshot.when(
        data: (value) =>
            _GoalDetailContent(userId: userId, goalId: goalId, snapshot: value),
        error: (error, stackTrace) =>
            Center(child: Text('Unable to open Goal: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _GoalDetailContent extends StatelessWidget {
  const _GoalDetailContent({
    required this.userId,
    required this.goalId,
    required this.snapshot,
  });

  final AppUserId userId;
  final String goalId;
  final GoalTaskSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final goal = _goalOrNull(snapshot, goalId);
    if (goal == null) {
      return const Center(child: Text('Goal is no longer available.'));
    }
    final tasks = snapshot.tasksForGoal(goalId);
    final complete = snapshot.isGoalComplete(goalId);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(goal.title, style: Theme.of(context).textTheme.headlineSmall),
        if (goal.notes != null) ...[
          const SizedBox(height: 8),
          Text(goal.notes!, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(
              complete ? Icons.check_circle : Icons.pending_outlined,
            ),
            title: Text(complete ? 'Complete' : 'In progress'),
            subtitle: Text(
              complete
                  ? 'Every Task was explicitly completed.'
                  : 'A Goal completes only after every Task is explicitly completed.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Tasks',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('add-task'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TaskEditorPage(userId: userId, goalId: goalId),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add Task'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Card(child: ListTile(title: Text('No Tasks yet.')))
        else
          for (final task in tasks)
            Card(
              child: ListTile(
                key: Key('goal-task-${task.id}'),
                title: Text(task.title),
                subtitle: Text(
                  '${task.classification.label} · ${task.isComplete ? 'Completed' : 'Active'} · Focus ${_durationLabel(task.focusProgress)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TaskDetailPage(userId: userId, taskId: task.id),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class TaskEditorPage extends ConsumerStatefulWidget {
  const TaskEditorPage({
    required this.userId,
    required this.goalId,
    this.task,
    super.key,
  });

  final AppUserId userId;
  final String goalId;
  final Task? task;

  @override
  ConsumerState<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends ConsumerState<TaskEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _estimateController;
  late TaskChainClassification _classification;
  DateTime? _deadline;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title);
    _notesController = TextEditingController(text: task?.notes);
    _estimateController = TextEditingController(
      text: task?.estimatedDuration?.inMinutes.toString(),
    );
    _classification = task?.classification ?? TaskChainClassification.regular;
    _deadline = task?.deadline;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _estimateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Create Task' : 'Edit Task'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            key: const Key('task-title-field'),
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Task title'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TaskChainClassification>(
            key: const Key('task-classification-field'),
            initialValue: _classification,
            decoration: const InputDecoration(labelText: 'Classification'),
            items: [
              for (final classification in TaskChainClassification.values)
                DropdownMenuItem(
                  value: classification,
                  child: Text(classification.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _classification = value);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('task-estimate-field'),
            controller: _estimateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Estimate (minutes, optional)',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _deadline == null
                  ? 'Deadline: Not set'
                  : 'Deadline: ${_dateLabel(_deadline)}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  key: const Key('choose-task-deadline'),
                  tooltip: 'Choose deadline',
                  onPressed: _chooseDeadline,
                  icon: const Icon(Icons.event_outlined),
                ),
                if (_deadline != null)
                  IconButton(
                    tooltip: 'Clear deadline',
                    onPressed: () => setState(() => _deadline = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('task-notes-field'),
            controller: _notesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('save-task'),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Task'),
          ),
          if (widget.task != null) ...[
            const SizedBox(height: 12),
            Text(
              'Focus Progress: ${_durationLabel(widget.task!.focusProgress)} (read-only)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _chooseDeadline() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _deadline ?? DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _deadline = picked.toUtc());
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Enter a Task title.');
      return;
    }
    final minutes = int.tryParse(_estimateController.text.trim());
    if (_estimateController.text.trim().isNotEmpty &&
        (minutes == null || minutes <= 0)) {
      _showError('Estimate must be a positive number of minutes.');
      return;
    }
    setState(() => _saving = true);
    try {
      final task = await ref
          .read(goalTaskRepositoryProvider)
          .saveTask(
            widget.userId,
            TaskDraft(
              id: widget.task?.id,
              goalId: widget.goalId,
              title: _titleController.text,
              notes: _emptyToNull(_notesController.text),
              deadline: _deadline,
              estimatedDuration: minutes == null
                  ? null
                  : Duration(minutes: minutes),
              classification: _classification,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              TaskDetailPage(userId: widget.userId, taskId: task.id),
        ),
      );
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class TaskDetailPage extends ConsumerWidget {
  const TaskDetailPage({required this.userId, required this.taskId, super.key});

  final AppUserId userId;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(goalTaskSnapshotProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task'),
        actions: [
          IconButton(
            key: const Key('edit-task'),
            tooltip: 'Edit Task',
            onPressed: () async {
              final current = await ref
                  .read(goalTaskRepositoryProvider)
                  .read(userId);
              final task = _taskOrNull(current, taskId);
              if (task == null || !context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskEditorPage(
                    userId: userId,
                    goalId: task.goalId,
                    task: task,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: snapshot.when(
        data: (value) =>
            _TaskDetailContent(userId: userId, taskId: taskId, snapshot: value),
        error: (error, stackTrace) =>
            Center(child: Text('Unable to open Task: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _TaskDetailContent extends ConsumerWidget {
  const _TaskDetailContent({
    required this.userId,
    required this.taskId,
    required this.snapshot,
  });

  final AppUserId userId;
  final String taskId;
  final GoalTaskSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = _taskOrNull(snapshot, taskId);
    if (task == null) {
      return const Center(child: Text('Task is no longer available.'));
    }
    final goal = _goalOrNull(snapshot, task.goalId);
    final repository = ref.read(goalTaskRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (goal != null) Text('Goal: ${goal.title}'),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Status'),
                trailing: Text(task.isComplete ? 'Completed' : 'Active'),
              ),
              ListTile(
                title: const Text('Classification'),
                trailing: Text(task.classification.label),
              ),
              ListTile(
                title: const Text('Estimate'),
                trailing: Text(_durationLabel(task.estimatedDuration)),
              ),
              ListTile(
                title: const Text('Deadline'),
                trailing: Text(_dateLabel(task.deadline)),
              ),
              ListTile(
                title: const Text('Focus Progress'),
                trailing: Text(_durationLabel(task.focusProgress)),
              ),
            ],
          ),
        ),
        if (task.notes != null) ...[
          const SizedBox(height: 16),
          Text(task.notes!, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          key: Key(
            task.isComplete
                ? 'reopen-task-$taskId'
                : 'complete-detail-task-$taskId',
          ),
          onPressed: () async {
            await repository.setTaskCompleted(
              userId,
              task.id,
              !task.isComplete,
            );
          },
          icon: Icon(task.isComplete ? Icons.undo : Icons.check),
          label: Text(
            task.isComplete ? 'Reopen Task' : 'Explicitly complete Task',
          ),
        ),
      ],
    );
  }
}

Goal? _goalOrNull(GoalTaskSnapshot snapshot, String id) {
  for (final goal in snapshot.goals) {
    if (goal.id == id) return goal;
  }
  return null;
}

Task? _taskOrNull(GoalTaskSnapshot snapshot, String id) {
  for (final task in snapshot.tasks) {
    if (task.id == id) return task;
  }
  return null;
}

String? _emptyToNull(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _durationLabel(Duration? value) {
  if (value == null) {
    return 'Not set';
  }
  if (value.inHours > 0) {
    return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
  }
  return '${value.inMinutes}m';
}

String _dateLabel(DateTime? value) {
  if (value == null) return 'Not set';
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
