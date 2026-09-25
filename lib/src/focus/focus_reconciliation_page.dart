import 'dart:async';

import 'package:flutter/material.dart' hide FocusNode;

import '../tasks/task_repository.dart';
import 'focus_models.dart';
import 'focus_repository.dart';

class FocusReconciliationPage extends StatefulWidget {
  const FocusReconciliationPage({
    super.key,
    required this.focusRepository,
    required this.taskRepository,
  });

  final FocusRepository focusRepository;
  final TaskRepository taskRepository;

  @override
  State<FocusReconciliationPage> createState() =>
      _FocusReconciliationPageState();
}

class _FocusReconciliationPageState extends State<FocusReconciliationPage> {
  late final Stream<List<FocusReconciliationCase>> _cases;
  late final Future<Map<String, String>> _taskTitles;

  @override
  void initState() {
    super.initState();
    _cases = widget.focusRepository.watchFocusReconciliations();
    _taskTitles = _loadTaskTitles();
  }

  Future<Map<String, String>> _loadTaskTitles() async {
    final goals = await widget.taskRepository.getGoals(includeDeleted: true);
    return {
      for (final goal in goals)
        for (final task in goal.tasks) task.id: task.title,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('专注记录核对')),
      body: SafeArea(
        child: FutureBuilder<Map<String, String>>(
          future: _taskTitles,
          builder: (context, titleSnapshot) {
            if (titleSnapshot.hasError) {
              return const Center(child: Text('暂时无法读取任务名称。'));
            }
            if (!titleSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<List<FocusReconciliationCase>>(
              stream: _cases,
              builder: (context, caseSnapshot) {
                if (caseSnapshot.hasError) {
                  return const Center(child: Text('暂时无法读取核对记录。'));
                }
                if (!caseSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _ReconciliationList(
                  cases: caseSnapshot.data!,
                  taskTitles: titleSnapshot.data!,
                  focusRepository: widget.focusRepository,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReconciliationList extends StatelessWidget {
  const _ReconciliationList({
    required this.cases,
    required this.taskTitles,
    required this.focusRepository,
  });

  final List<FocusReconciliationCase> cases;
  final Map<String, String> taskTitles;
  final FocusRepository focusRepository;

  @override
  Widget build(BuildContext context) {
    final pending = cases.where((item) => item.isPendingReview).toList();
    final completed = cases.where((item) => !item.isPendingReview).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 720 ? 32.0 : 16.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                32,
              ),
              children: [
                if (pending.isEmpty)
                  const _NoPendingReviewsCard()
                else ...[
                  _SectionHeading(
                    title: '待核对',
                    count: pending.length,
                    subtitle: '未决定的记录暂不计入专注统计。',
                  ),
                  const SizedBox(height: 8),
                  for (final item in pending)
                    _PendingReconciliationCard(
                      key: ValueKey('pending-${item.id}'),
                      reconciliation: item,
                      taskTitles: taskTitles,
                      focusRepository: focusRepository,
                    ),
                ],
                if (completed.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionHeading(
                    title: '已核对',
                    count: completed.length,
                    subtitle: '保留原始来源和最终采用结果，便于回看。',
                  ),
                  const SizedBox(height: 8),
                  for (final item in completed)
                    _ResolvedReconciliationCard(
                      reconciliation: item,
                      taskTitles: taskTitles,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.count,
    required this.subtitle,
  });

  final String title;
  final int count;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Badge(label: Text('$count')),
      ],
    );
  }
}

class _NoPendingReviewsCard extends StatelessWidget {
  const _NoPendingReviewsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前没有待核对的专注记录'),
                  SizedBox(height: 4),
                  Text('已完成的核对结果会保留在下方。'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingReconciliationCard extends StatefulWidget {
  const _PendingReconciliationCard({
    super.key,
    required this.reconciliation,
    required this.taskTitles,
    required this.focusRepository,
  });

  final FocusReconciliationCase reconciliation;
  final Map<String, String> taskTitles;
  final FocusRepository focusRepository;

  @override
  State<_PendingReconciliationCard> createState() =>
      _PendingReconciliationCardState();
}

class _PendingReconciliationCardState
    extends State<_PendingReconciliationCard> {
  final _configurationSources = <String, String?>{};
  final _outcomeSources = <String, String?>{};
  String? _adoptedSessionId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initializeSelections();
  }

  void _initializeSelections() {
    for (final entry in widget.reconciliation.sessions) {
      final firstSource = entry.availableSources.isEmpty
          ? null
          : entry.availableSources.first.sourceId;
      _configurationSources[entry.session.id] =
          entry.requiresConfigurationChoice ? null : firstSource;
      _outcomeSources[entry.session.id] = entry.requiresOutcomeChoice
          ? null
          : firstSource;
    }
  }

  bool get _canSave {
    if (widget.reconciliation.hasOverlappingSessions &&
        _adoptedSessionId == null) {
      return false;
    }
    for (final entry in widget.reconciliation.sessions) {
      if (entry.availableSources.isEmpty) return false;
      if (entry.requiresConfigurationChoice &&
          _configurationSources[entry.session.id] == null) {
        return false;
      }
      if (entry.requiresOutcomeChoice &&
          _outcomeSources[entry.session.id] == null) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.focusRepository.resolveFocusReconciliation(
        caseId: widget.reconciliation.id,
        adoptedSessionId: _adoptedSessionId,
        sessionSelections: {
          for (final entry in widget.reconciliation.sessions)
            entry.session.id: FocusSessionReconciliationSelection(
              configurationSourceId: _configurationSources[entry.session.id],
              outcomeSourceId: _outcomeSources[entry.session.id],
            ),
        },
      );
      try {
        await widget.focusRepository.sync();
        messenger.showSnackBar(const SnackBar(content: Text('核对结果已保存并同步。')));
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('核对结果已保存在本机，联网后会继续同步。')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reconciliation = widget.reconciliation;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reconciliation.hasOverlappingSessions
                  ? '有 ${reconciliation.sessions.length} 条专注记录时间重叠'
                  : '同一次专注存在多个来源',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              reconciliation.hasOverlappingSessions
                  ? '比较各条记录，选择实际采用的一条；其他记录会保留并标记为重复。'
                  : '配置、专注结果和有效时间分别核对，来源记录会完整保留。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final entry in reconciliation.sessions)
              _SessionSourceChoices(
                entry: entry,
                taskTitle: widget.taskTitles[entry.session.taskId] ?? '原任务',
                configurationSourceId: _configurationSources[entry.session.id],
                outcomeSourceId: _outcomeSources[entry.session.id],
                chooseConfiguration: (sourceId) => setState(() {
                  _configurationSources[entry.session.id] = sourceId;
                }),
                chooseOutcome: (sourceId) => setState(() {
                  _outcomeSources[entry.session.id] = sourceId;
                }),
                taskTitles: widget.taskTitles,
              ),
            if (reconciliation.hasOverlappingSessions) ...[
              const Divider(height: 20),
              Text('选择实际采用的记录', style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<String>(
                groupValue: _adoptedSessionId,
                onChanged: (value) => setState(() {
                  _adoptedSessionId = value;
                }),
                child: Column(
                  children: [
                    for (final entry in reconciliation.sessions)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: entry.session.id,
                        title: Text(
                          widget.taskTitles[entry.session.taskId] ?? '原任务',
                        ),
                        subtitle: Text(
                          '${entry.session.mode.label} · ${_formatDuration(entry.session.effectiveSeconds)}有效时间 · ${_outcomeLabel(entry.session)}',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _canSave && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_saving ? '正在保存' : '确认并保存核对'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionSourceChoices extends StatelessWidget {
  const _SessionSourceChoices({
    required this.entry,
    required this.taskTitle,
    required this.configurationSourceId,
    required this.outcomeSourceId,
    required this.chooseConfiguration,
    required this.chooseOutcome,
    required this.taskTitles,
  });

  final FocusReconciliationSession entry;
  final String taskTitle;
  final String? configurationSourceId;
  final String? outcomeSourceId;
  final ValueChanged<String> chooseConfiguration;
  final ValueChanged<String> chooseOutcome;
  final Map<String, String> taskTitles;

  @override
  Widget build(BuildContext context) {
    final session = entry.session;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(taskTitle, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '${session.mode.label} · ${_formatDuration(session.effectiveSeconds)}有效时间 · ${_formatRange(session)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (entry.requiresConfigurationChoice) ...[
                const Divider(height: 24),
                const Text('选择配置来源'),
                RadioGroup<String>(
                  groupValue: configurationSourceId,
                  onChanged: (value) {
                    if (value != null) chooseConfiguration(value);
                  },
                  child: Column(
                    children: [
                      for (final option in entry.availableSources)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: option.sourceId,
                          title: Text(_configurationLabel(option, taskTitles)),
                          subtitle: Text(_sourceContext(option)),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                    ],
                  ),
                ),
              ] else if (entry.selectedConfigurationSource != null) ...[
                const SizedBox(height: 8),
                Text(
                  '配置依据：${_configurationLabel(entry.selectedConfigurationSource!, taskTitles)} · ${_sourceContext(entry.selectedConfigurationSource!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (entry.requiresOutcomeChoice) ...[
                const Divider(height: 24),
                const Text('选择专注结果来源'),
                RadioGroup<String>(
                  groupValue: outcomeSourceId,
                  onChanged: (value) {
                    if (value != null) chooseOutcome(value);
                  },
                  child: Column(
                    children: [
                      for (final option in entry.availableSources)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: option.sourceId,
                          title: Text(
                            '${_outcomeLabel(option.session)} · ${_formatDuration(option.session.effectiveSeconds)}有效时间',
                          ),
                          subtitle: Text(_sourceContext(option)),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                    ],
                  ),
                ),
              ] else if (entry.selectedOutcomeSource != null) ...[
                const SizedBox(height: 4),
                Text(
                  '结果依据：${_outcomeLabel(entry.selectedOutcomeSource!.session)} · ${_sourceContext(entry.selectedOutcomeSource!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResolvedReconciliationCard extends StatelessWidget {
  const _ResolvedReconciliationCard({
    required this.reconciliation,
    required this.taskTitles,
  });

  final FocusReconciliationCase reconciliation;
  final Map<String, String> taskTitles;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in reconciliation.sessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.session.reviewDisposition ==
                          FocusRecordDisposition.duplicate
                      ? Icons.copy_all_outlined
                      : Icons.check_circle_outline,
                  color: colors.primary,
                ),
                title: Text(
                  taskTitles[entry.session.taskId] ?? '原任务',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    entry.session.reviewDisposition ==
                            FocusRecordDisposition.duplicate
                        ? '已标记重复 · 不计入进度、节点或专注链'
                        : '已采用 · ${_formatDuration(entry.session.effectiveSeconds)}有效时间',
                    if (entry.selectedConfigurationSource != null)
                      '配置来源：${_sourceContext(entry.selectedConfigurationSource!)}',
                    if (entry.selectedOutcomeSource != null)
                      '结果来源：${_sourceContext(entry.selectedOutcomeSource!)}',
                  ].join('\n'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _configurationLabel(
  FocusSessionSourceOption option,
  Map<String, String> taskTitles,
) {
  final session = option.session;
  final title = taskTitles[session.taskId] ?? '原任务';
  return '$title · ${session.mode.label} · ${_formatDuration(session.durationSeconds)}';
}

String _sourceContext(FocusSessionSourceOption option) =>
    '设备 ${option.deviceId} · ${_formatDateTime(option.occurredAt)}';

String _outcomeLabel(FocusSession session) => switch (session.status) {
  FocusSessionStatus.completed => session.isEarlyCompleted ? '依规则提前完成' : '正常完成',
  FocusSessionStatus.failed => '失败：${session.failureReason ?? '未记录原因'}',
  FocusSessionStatus.paused => '已暂停',
  FocusSessionStatus.active => '进行中',
};

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes == 0) return '$remainingSeconds秒';
  if (remainingSeconds == 0) return '$minutes分钟';
  return '$minutes分${remainingSeconds.toString().padLeft(2, '0')}秒';
}

String _formatRange(FocusSession session) {
  final end = session.completedAt ?? session.endsAt;
  return '${_formatDateTime(session.startedAt)} – ${_formatDateTime(end)}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}
