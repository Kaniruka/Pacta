import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/app/chain_theme.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/presentation/focus_chain_page.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/features/goals_tasks/presentation/goal_task_pages.dart';

class BoardPage extends ConsumerWidget {
  const BoardPage({required this.userId, super.key});

  final AppUserId userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(goalTaskSnapshotProvider(userId));
    ref.watch(goalTaskSyncProvider(userId));
    return snapshot.when(
      data: (value) => _BoardContent(userId: userId, snapshot: value),
      error: (error, stackTrace) => _BoardContent(
        userId: userId,
        snapshot: GoalTaskSnapshot.empty,
        errorMessage:
            'Using the local Board while synchronization is unavailable.',
      ),
      loading: () => const _BoardLoading(),
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({
    required this.userId,
    required this.snapshot,
    this.errorMessage,
  });

  final AppUserId userId;
  final GoalTaskSnapshot snapshot;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final activeTasks = snapshot.executableTasks;
    final completedTasks = snapshot.tasks
        .where((task) => task.isComplete)
        .toList();
    final goalsById = {for (final goal in snapshot.goals) goal.id: goal};
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      key: const PageStorageKey<String>('board'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TODAY\'S BOARD',
                        style: textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Today\'s Board', style: textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Choose the next concrete Task before reviewing progress.',
                        style: textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const Key('board-goals'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GoalsPage(userId: userId),
                    ),
                  ),
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Goals'),
                ),
                IconButton.filledTonal(
                  key: const Key('board-add-goal'),
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
          ),
        ),
        if (errorMessage != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Offline Board'),
                  subtitle: Text(errorMessage!),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Text('Executable Tasks', style: textTheme.titleLarge),
          ),
        ),
        if (activeTasks.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No executable Tasks yet'),
                  subtitle: Text('Create a Goal, then add its first Task.'),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: activeTasks.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _TaskCard(
                userId: userId,
                task: activeTasks[index],
                goal: goalsById[activeTasks[index].goalId]!,
              ),
            ),
          ),
        const _BoardSummarySliver(),
        if (completedTasks.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text('Completed Tasks', style: textTheme.titleLarge),
            ),
          ),
        if (completedTasks.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.separated(
              itemCount: completedTasks.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _TaskCard(
                userId: userId,
                task: completedTasks[index],
                goal: goalsById[completedTasks[index].goalId]!,
              ),
            ),
          ),
        if (completedTasks.isEmpty)
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({
    required this.userId,
    required this.task,
    required this.goal,
  });

  final AppUserId userId;
  final Task task;
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final chainColors = Theme.of(context).extension<ChainColors>();
    final repository = ref.read(goalTaskRepositoryProvider);
    return Card(
      key: Key('board-task-${task.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TaskDetailPage(userId: userId, taskId: task.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (task.isComplete)
                    Icon(
                      Icons.check_circle,
                      color: chainColors?.success ?? colors.tertiary,
                    )
                  else
                    TextButton(
                      key: Key('complete-task-${task.id}'),
                      onPressed: () async {
                        await repository.setTaskCompleted(
                          userId,
                          task.id,
                          true,
                        );
                      },
                      child: const Text('Complete'),
                    ),
                ],
              ),
              if (!task.isComplete)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: Key('configure-focus-${task.id}'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FocusChainPage(
                          userId: userId,
                          initialTaskId: task.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.radio_button_checked),
                    label: const Text('Configure Focus Chain'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MetaChip(label: 'Goal: ${goal.title}'),
                  _MetaChip(label: task.classification.label),
                  _MetaChip(
                    label:
                        'Status: ${task.isComplete ? 'Completed' : 'Active'}',
                  ),
                  _MetaChip(
                    label:
                        'Estimate: ${_durationLabel(task.estimatedDuration)}',
                  ),
                  _MetaChip(label: 'Deadline: ${_dateLabel(task.deadline)}'),
                  _MetaChip(
                    label:
                        'Focus Progress: ${_durationLabel(task.focusProgress)}',
                    color: colors.primaryContainer,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: color,
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BoardSummarySliver extends StatelessWidget {
  const _BoardSummarySliver();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      sliver: SliverList.list(
        children: const [
          _SummaryCard(
            title: 'Focus Progress',
            detail:
                'Actual completed-session time stays attached to each Task.',
            icon: Icons.timer_outlined,
          ),
          SizedBox(height: 10),
          _SummaryCard(
            title: 'National Focus',
            detail:
                'Your broader progress appears here when the tree is connected.',
            icon: Icons.account_tree_outlined,
          ),
          SizedBox(height: 10),
          _SummaryCard(
            title: 'Recent Focus Activity',
            detail: 'A read-only record of recent Focus Sessions.',
            icon: Icons.history,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }
}

class _BoardLoading extends StatelessWidget {
  const _BoardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
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
