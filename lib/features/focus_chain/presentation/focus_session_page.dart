import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/data/focus_session_state.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    required this.userId,
    required this.config,
    this.clock,
    super.key,
  });

  final AppUserId userId;
  final FocusSessionConfig config;
  final DateTime Function()? clock;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage>
    with WidgetsBindingObserver {
  FocusSession? _session;
  DateTime _now = DateTime.now().toUtc();
  Object? _error;
  bool _loading = true;
  bool _reconcileInFlight = false;
  Timer? _timer;

  DateTime _readClock() => (widget.clock?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = _readClock();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_open());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcile());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(focusSessionSyncProvider(widget.userId));
    ref.watch(goalTaskSyncProvider(widget.userId));
    final session = _session;
    final clockState = session == null
        ? null
        : FocusSessionClockState.fromSession(session, _now);
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Session')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(error: _error!)
          : session == null || clockState == null
          ? const Center(child: Text('Focus Session is unavailable.'))
          : _SessionBody(
              session: session,
              clockState: clockState,
              taskTitle: widget.config.task.title,
            ),
    );
  }

  Future<void> _open() async {
    try {
      final session = await ref
          .read(focusSessionRepositoryProvider)
          .start(widget.userId, widget.config);
      if (!mounted) return;
      setState(() {
        _session = session;
        _now = _readClock();
        _loading = false;
      });
      await _reconcile();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _tick() {
    final session = _session;
    if (!mounted || session == null) return;
    final now = _readClock();
    setState(() => _now = now);
    if (session.isActive &&
        FocusSessionClockState.fromSession(session, now).reachedZero) {
      unawaited(_reconcile());
    }
  }

  Future<void> _reconcile() async {
    final session = _session;
    if (!mounted || session == null || _reconcileInFlight) return;
    _reconcileInFlight = true;
    try {
      final updated = await ref
          .read(focusSessionRepositoryProvider)
          .reconcile(widget.userId, session.id);
      if (!mounted) return;
      setState(() {
        _session = updated;
        _now = _readClock();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _reconcileInFlight = false;
    }
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.session,
    required this.clockState,
    required this.taskTitle,
  });

  final FocusSession session;
  final FocusSessionClockState clockState;
  final String taskTitle;

  @override
  Widget build(BuildContext context) {
    final completed = session.outcome == FocusSessionOutcome.completed;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  taskTitle,
                  key: const Key('focus-session-task'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('Mode: ${session.mode.label}'),
                Text('Planned: ${_durationLabel(session.plannedDuration)}'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      completed
                          ? Icons.check_circle_outline
                          : Icons.radio_button_checked,
                      color: completed
                          ? colorScheme.primary
                          : colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      completed ? 'Completed' : 'Active',
                      key: const Key('focus-session-status'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _TimeCard(
          label: 'Elapsed',
          value: _clockLabel(clockState.elapsed),
          key: const Key('focus-session-elapsed'),
        ),
        const SizedBox(height: 12),
        _TimeCard(
          label: 'Remaining',
          value: _clockLabel(clockState.remaining),
          key: const Key('focus-session-remaining'),
        ),
        if (completed) ...[
          const SizedBox(height: 20),
          Card(
            color: colorScheme.primaryContainer,
            child: const ListTile(
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('Focus Node recorded'),
              subtitle: Text(
                'Focus Progress was updated. Task and Goal completion remain explicit actions.',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Unable to start Focus Session: $error'));
  }
}

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  return '$minutes min';
}

String _clockLabel(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
