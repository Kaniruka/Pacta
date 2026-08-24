import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/presentation/task_picker_page.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

class FocusChainPage extends ConsumerStatefulWidget {
  const FocusChainPage({required this.userId, this.initialTaskId, super.key});

  final AppUserId userId;
  final String? initialTaskId;

  @override
  ConsumerState<FocusChainPage> createState() => _FocusChainPageState();
}

class _FocusChainPageState extends ConsumerState<FocusChainPage> {
  static const _minDurationMinutes = 5;
  static const _maxDurationMinutes = 180;
  static const _durationStepMinutes = 5;
  static const _appointmentMinutes = 15;

  String? _selectedTaskId;
  FocusChainMode? _selectedMode;
  int _durationMinutes = 25;

  @override
  void initState() {
    super.initState();
    _selectedTaskId = widget.initialTaskId;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(goalTaskSnapshotProvider(widget.userId));
    ref.watch(goalTaskSyncProvider(widget.userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Chain Setup')),
      body: snapshot.when(
        data: (value) => _buildSetup(context, value),
        error: (error, stackTrace) =>
            Center(child: Text('Unable to open Focus Chain setup: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildSetup(BuildContext context, GoalTaskSnapshot snapshot) {
    final task = _taskForId(snapshot, _selectedTaskId);
    final goal = task == null ? null : _goalForId(snapshot, task.goalId);
    final mode = _selectedMode;
    final eliteAvailable = hasEligibleTask(
      snapshot.tasks,
      FocusChainMode.elite,
    );
    final regularAvailable = hasEligibleTask(
      snapshot.tasks,
      FocusChainMode.regular,
    );
    final selectedTaskEligible =
        task != null && mode != null && isEligibleForMode(task, mode);
    final canStart = selectedTaskEligible;

    return ListView(
      key: const PageStorageKey<String>('focus-chain-setup'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          'Choose one Task and explicitly choose how to focus on it.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const Key('focus-select-task'),
          onPressed: () => _selectTask(snapshot),
          icon: const Icon(Icons.list_alt_outlined),
          label: Text(task == null ? 'Choose a Task' : 'Change Task'),
        ),
        const SizedBox(height: 12),
        if (task == null)
          const Card(
            child: ListTile(
              leading: Icon(Icons.touch_app_outlined),
              title: Text('No Task selected'),
              subtitle: Text('Select a Task before configuring a Focus Chain.'),
            ),
          )
        else
          _TaskContextCard(task: task, goal: goal),
        const SizedBox(height: 20),
        Text(
          'Focus Chain Selection',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<FocusChainMode>(
          key: const Key('focus-chain-mode'),
          emptySelectionAllowed: true,
          selected: mode == null ? const {} : {mode},
          segments: [
            for (final candidate in FocusChainMode.values)
              ButtonSegment<FocusChainMode>(
                value: candidate,
                label: Text(candidate.label),
                icon: Icon(
                  candidate == FocusChainMode.elite
                      ? Icons.bolt_outlined
                      : Icons.self_improvement_outlined,
                ),
              ),
          ],
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              setState(() => _selectedMode = selection.single);
            }
          },
        ),
        if (mode == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Choose Elite or Regular explicitly. Task classification does not choose for you.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        if (mode == FocusChainMode.elite && !eliteAvailable && regularAvailable)
          Card(
            key: const Key('regular-chain-suggestion'),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('Regular may be available'),
              subtitle: const Text(
                'Elite has no eligible executable Tasks. Accept the suggestion to change mode.',
              ),
              trailing: TextButton(
                key: const Key('accept-regular-suggestion'),
                onPressed: () =>
                    setState(() => _selectedMode = FocusChainMode.regular),
                child: const Text('Accept'),
              ),
            ),
          ),
        if (task != null && mode != null && !selectedTaskEligible)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${task.title} is not eligible for ${mode.label}. Choose another Task or mode.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Countdown duration',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('duration-decrease'),
                tooltip: 'Decrease duration',
                onPressed: _durationMinutes <= _minDurationMinutes
                    ? null
                    : () => setState(
                        () => _durationMinutes -= _durationStepMinutes,
                      ),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 130,
                child: Text(
                  '$_durationMinutes min',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                key: const Key('duration-increase'),
                tooltip: 'Increase duration',
                onPressed: _durationMinutes >= _maxDurationMinutes
                    ? null
                    : () => setState(
                        () => _durationMinutes += _durationStepMinutes,
                      ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        Text(
          'You choose the countdown. Elite and Regular classification never determines its length.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _SignalCard(
          title: 'Appointment Signal',
          icon: Icons.event_available_outlined,
          text:
              'Perform the Appointment Signal yourself. Pacta does not detect the signal or start a Focus Chain automatically.',
        ),
        const SizedBox(height: 10),
        _SignalCard(
          title: 'Immediate-start Signal',
          icon: Icons.play_circle_outline,
          text:
              'Perform the Immediate-start Signal yourself when you are ready. Pacta only responds after you choose to continue.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('start-appointment-chain'),
          onPressed: canStart ? () => _startAppointment(task, mode) : null,
          icon: const Icon(Icons.event_available),
          label: const Text('Appointment Chain · 15 min'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('start-immediate-focus'),
          onPressed: canStart ? () => _startImmediate(task, mode) : null,
          icon: const Icon(Icons.play_arrow),
          label: Text('Immediate start · $_durationMinutes min'),
        ),
      ],
    );
  }

  Future<void> _selectTask(GoalTaskSnapshot snapshot) async {
    final taskId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => TaskPickerPage(snapshot: snapshot),
      ),
    );
    if (taskId != null && mounted) {
      setState(() => _selectedTaskId = taskId);
    }
  }

  void _startAppointment(Task task, FocusChainMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FocusStartPreviewPage(
          task: task,
          mode: mode,
          duration: const Duration(minutes: _appointmentMinutes),
          kind: FocusStartKind.appointment,
        ),
      ),
    );
  }

  void _startImmediate(Task task, FocusChainMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FocusStartPreviewPage(
          task: task,
          mode: mode,
          duration: Duration(minutes: _durationMinutes),
          kind: FocusStartKind.immediate,
        ),
      ),
    );
  }
}

class _TaskContextCard extends StatelessWidget {
  const _TaskContextCard({required this.task, required this.goal});

  final Task task;
  final Goal? goal;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('focus-task-context-${task.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Goal: ${goal?.title ?? 'Unknown'}'),
            Text('Estimate: ${durationLabel(task.estimatedDuration)}'),
            Text('Classification: ${task.classification.label}'),
            Text('Focus Progress: ${durationLabel(task.focusProgress)}'),
          ],
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.title,
    required this.icon,
    required this.text,
  });

  final String title;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(text),
      ),
    );
  }
}

enum FocusStartKind { appointment, immediate }

class FocusStartPreviewPage extends StatelessWidget {
  const FocusStartPreviewPage({
    required this.task,
    required this.mode,
    required this.duration,
    required this.kind,
    super.key,
  });

  final Task task;
  final FocusChainMode mode;
  final Duration duration;
  final FocusStartKind kind;

  @override
  Widget build(BuildContext context) {
    final appointment = kind == FocusStartKind.appointment;
    return Scaffold(
      appBar: AppBar(
        title: Text(appointment ? 'Appointment Chain' : 'Immediate Focus'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                appointment ? Icons.event_available : Icons.play_circle,
              ),
              title: Text(
                appointment
                    ? 'Appointment Chain configured'
                    : 'Focus Session configured',
              ),
              subtitle: Text(
                '${task.title} · ${mode.label} · ${duration.inMinutes} min',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            appointment
                ? 'The Appointment Signal remains a manual User action. Pacta does not detect or auto-start it.'
                : 'The Immediate-start Signal remains a manual User action. Pacta does not detect or auto-start it.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('return-to-focus-chain'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Return to Focus Chain'),
          ),
        ],
      ),
    );
  }
}

Task? _taskForId(GoalTaskSnapshot snapshot, String? id) {
  if (id == null) return null;
  for (final task in snapshot.tasks) {
    if (task.id == id) return task;
  }
  return null;
}

Goal? _goalForId(GoalTaskSnapshot snapshot, String id) {
  for (final goal in snapshot.goals) {
    if (goal.id == id) return goal;
  }
  return null;
}
