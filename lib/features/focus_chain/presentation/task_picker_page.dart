import 'package:flutter/material.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

class TaskPickerPage extends StatefulWidget {
  const TaskPickerPage({
    required this.snapshot,
    this.initialFilter = TaskPickerFilter.all,
    super.key,
  });

  final GoalTaskSnapshot snapshot;
  final TaskPickerFilter initialFilter;

  @override
  State<TaskPickerPage> createState() => _TaskPickerPageState();
}

class _TaskPickerPageState extends State<TaskPickerPage> {
  late TaskPickerFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = filterTasks(widget.snapshot.tasks, _filter);
    final goals = {for (final goal in widget.snapshot.goals) goal.id: goal};
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Task')),
      body: Column(
        children: [
          SingleChildScrollView(
            key: const Key('task-picker-filters'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in TaskPickerFilter.values) ...[
                  ChoiceChip(
                    key: Key('task-filter-${filter.name}'),
                    label: Text(filter.label),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      _filter == TaskPickerFilter.all
                          ? 'No executable Tasks are available.'
                          : 'No executable Tasks match this filter.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: tasks.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final goal = goals[task.goalId];
                      return Card(
                        child: ListTile(
                          key: Key('picker-task-${task.id}'),
                          title: Text(task.title),
                          subtitle: Text(
                            'Goal: ${goal?.title ?? 'Unknown'} · '
                            '${task.classification.label} · '
                            'Estimate: ${durationLabel(task.estimatedDuration)} · '
                            'Focus Progress: ${durationLabel(task.focusProgress)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(task.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String durationLabel(Duration? value) {
  if (value == null) return 'Not set';
  if (value.inHours > 0) {
    return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
  }
  return '${value.inMinutes}m';
}

String dateLabel(DateTime? value) {
  if (value == null) return 'Not set';
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
