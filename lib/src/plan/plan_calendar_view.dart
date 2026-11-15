import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repository.dart';
import '../tasks/task_models.dart';

/// 计划日历：按账号显示时区呈现 Pacta 自有日程。
///
/// 一条安排不等于一次专注：完成安排只改安排自身，不写专注记录、不勾选任务。
/// 显示时区由调用方以账号值传入（02 合并前用适配器解析），本视图不读取设备
/// 级偏好。
class PlanCalendarView extends StatefulWidget {
  const PlanCalendarView({
    super.key,
    required this.repository,
    required this.goals,
    required this.displayTimeZoneId,
    this.now,
  });

  final ScheduleRepository repository;
  final List<Goal> goals;
  final String displayTimeZoneId;
  final DateTime Function()? now;

  @override
  State<PlanCalendarView> createState() => _PlanCalendarViewState();
}

class _PlanCalendarViewState extends State<PlanCalendarView> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  timezone.Location get _location =>
      FocusTimeZones.location(widget.displayTimeZoneId);

  DateTime _nowInZone() => timezone.TZDateTime.from(
    (widget.now ?? DateTime.now)().toUtc(),
    _location,
  );

  @override
  void initState() {
    super.initState();
    final now = _nowInZone();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  timezone.TZDateTime _zoned(DateTime date, {int hour = 0, int minute = 0}) =>
      timezone.TZDateTime(
        _location,
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );

  DateTime _utcStart(DateTime date) => _zoned(date).toUtc();

  @override
  Widget build(BuildContext context) {
    final monthStart = _visibleMonth;
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1);
    // 前后各留一天，覆盖时区偏移与全天日程的 UTC 午夜边界。
    final from = _utcStart(monthStart).subtract(const Duration(days: 1));
    final to = _utcStart(nextMonth).add(const Duration(days: 2));
    return StreamBuilder<List<Schedule>>(
      stream: widget.repository.watchSchedules(from: from, to: to),
      builder: (context, snapshot) {
        final schedules = snapshot.data ?? const <Schedule>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, schedules),
            const SizedBox(height: 8),
            _buildMonthGrid(context, schedules),
            const SizedBox(height: 16),
            _buildDaySection(context, schedules),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, List<Schedule> schedules) {
    return Row(
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: () => setState(() {
            _visibleMonth = DateTime(
              _visibleMonth.year,
              _visibleMonth.month - 1,
            );
            _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
          }),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${_visibleMonth.year}年${_visibleMonth.month}月',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: '下个月',
          onPressed: () => setState(() {
            _visibleMonth = DateTime(
              _visibleMonth.year,
              _visibleMonth.month + 1,
            );
            _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
          }),
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _createSchedule(context),
          icon: const Icon(Icons.add),
          label: const Text('新建安排'),
        ),
      ],
    );
  }

  Widget _buildMonthGrid(BuildContext context, List<Schedule> schedules) {
    final marked = _markedDays(schedules);
    final firstWeekday = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    ).weekday;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leading = firstWeekday - 1;
    final cells = <Widget>[];
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    for (final label in labels) {
      cells.add(
        Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    for (var index = 0; index < leading + daysInMonth; index++) {
      if (index < leading) {
        cells.add(const SizedBox.shrink());
        continue;
      }
      final day = DateTime(
        _visibleMonth.year,
        _visibleMonth.month,
        index - leading + 1,
      );
      cells.add(_buildDayCell(context, day, marked.contains(day)));
    }
    final rows = <Widget>[];
    for (var start = 0; start < cells.length; start += 7) {
      rows.add(
        Row(
          children: [
            for (var offset = 0; offset < 7; offset++)
              Expanded(
                child: start + offset < cells.length
                    ? cells[start + offset]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(BuildContext context, DateTime day, bool marked) {
    final theme = Theme.of(context);
    final selected = day == _selectedDay;
    final today = day == _todayKey();
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${day.month}月${day.day}日',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedDay = day),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: today && !selected
                ? Border.all(color: colorScheme.primary)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${day.day}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: marked
                      ? (selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.primary)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaySection(BuildContext context, List<Schedule> schedules) {
    final daySchedules = schedulesOnDay(
      schedules,
      _selectedDay,
      widget.displayTimeZoneId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedDay.month}月${_selectedDay.day}日 · '
                '${daySchedules.length} 项安排',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => _createSchedule(context, day: _selectedDay),
              icon: const Icon(Icons.add),
              label: const Text('添加事项'),
            ),
          ],
        ),
        if (daySchedules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '这一天还没有安排。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final schedule in daySchedules)
            _ScheduleTile(
              key: ValueKey('schedule-${schedule.id}'),
              schedule: schedule,
              timeLabel: scheduleTimeLabel(schedule, widget.displayTimeZoneId),
              taskLabel: _taskLabel(schedule.taskId),
              onToggleCompletion: (value) => _setCompletion(schedule, value),
              onEdit: () => _editSchedule(context, schedule),
              onReschedule: () => _reschedule(context, schedule),
              onDelete: () => _confirmDelete(context, schedule),
            ),
      ],
    );
  }

  DateTime _todayKey() {
    final now = _nowInZone();
    return DateTime(now.year, now.month, now.day);
  }

  String? _taskLabel(String? taskId) {
    if (taskId == null) return null;
    for (final goal in widget.goals) {
      for (final task in goal.tasks) {
        if (task.id == taskId) return task.title;
      }
    }
    return '已删除的任务';
  }

  Set<DateTime> _markedDays(List<Schedule> schedules) => {
    for (final schedule in schedules)
      for (final day in scheduleDays(schedule, widget.displayTimeZoneId)) day,
  };

  Future<void> _setCompletion(Schedule schedule, bool value) async {
    try {
      await widget.repository.setScheduleCompletion(
        schedule.id,
        isCompleted: value,
      );
    } catch (_) {
      if (!mounted) return;
      _showError(context, '安排没有更新，请稍后重试。');
    }
  }

  Future<void> _createSchedule(BuildContext context, {DateTime? day}) async {
    final result = await showScheduleEditor(
      context,
      goals: widget.goals,
      displayTimeZoneId: widget.displayTimeZoneId,
      initialDay: day ?? _selectedDay,
      now: widget.now,
    );
    if (result == null) return;
    try {
      final created = await widget.repository.createSchedule(result.draft);
      if (result.reminderMinutesBefore != null) {
        await widget.repository.setScheduleReminder(
          created.id,
          minutesBefore: result.reminderMinutesBefore,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showError(this.context, '安排没有保存，请稍后重试。');
    }
  }

  Future<void> _editSchedule(BuildContext context, Schedule schedule) async {
    final result = await showScheduleEditor(
      context,
      goals: widget.goals,
      displayTimeZoneId: widget.displayTimeZoneId,
      initial: schedule,
      initialDay: _selectedDay,
      now: widget.now,
    );
    if (result == null) return;
    try {
      await widget.repository.updateSchedule(schedule.id, result.draft);
      await widget.repository.setScheduleReminder(
        schedule.id,
        minutesBefore: result.reminderMinutesBefore,
      );
    } catch (_) {
      if (!mounted) return;
      _showError(this.context, '安排没有更新，请稍后重试。');
    }
  }

  Future<void> _reschedule(BuildContext context, Schedule schedule) async {
    final window = await showRescheduleDialog(
      context,
      schedule: schedule,
      displayTimeZoneId: widget.displayTimeZoneId,
    );
    if (window == null) return;
    try {
      await widget.repository.rescheduleSchedule(schedule.id, window);
    } catch (_) {
      if (!mounted) return;
      _showError(this.context, '新的时间没有保存，请稍后重试。');
    }
  }

  Future<void> _confirmDelete(BuildContext context, Schedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条安排？'),
        content: Text(
          '“${schedule.title}”将从计划日历移除。'
          '任务、专注记录和链记录都不受影响，已完成的专注仍然保留。',
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
    if (confirmed != true) return;
    try {
      await widget.repository.deleteSchedule(schedule.id);
    } catch (_) {
      if (!mounted) return;
      _showError(this.context, '安排没有删除，请稍后重试。');
    }
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    super.key,
    required this.schedule,
    required this.timeLabel,
    required this.taskLabel,
    required this.onToggleCompletion,
    required this.onEdit,
    required this.onReschedule,
    required this.onDelete,
  });

  final Schedule schedule;
  final String timeLabel;
  final String? taskLabel;
  final ValueChanged<bool> onToggleCompletion;
  final VoidCallback onEdit;
  final VoidCallback onReschedule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Checkbox(
          value: schedule.isCompleted,
          onChanged: (value) {
            if (value != null) onToggleCompletion(value);
          },
        ),
        title: Text(
          schedule.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: schedule.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(timeLabel),
            if (taskLabel != null)
              Text(
                '任务：$taskLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                '独立事项',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (schedule.notes.isNotEmpty)
              Text(
                schedule.notes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            if (schedule.hasReminder)
              Text(
                '提前 ${formatReminderOffset(schedule.reminderMinutesBefore!)}提醒',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '安排操作',
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
              case 'reschedule':
                onReschedule();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑安排')),
            PopupMenuItem(value: 'reschedule', child: Text('改期')),
            PopupMenuItem(value: 'delete', child: Text('删除安排')),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

/// 编辑器结果：草稿 + 可选提醒（提醒只存配置，投递由 06 负责）。
class ScheduleEditorResult {
  const ScheduleEditorResult({
    required this.draft,
    required this.reminderMinutesBefore,
  });

  final ScheduleDraft draft;
  final int? reminderMinutesBefore;
}

Future<ScheduleEditorResult?> showScheduleEditor(
  BuildContext context, {
  required List<Goal> goals,
  required String displayTimeZoneId,
  required DateTime initialDay,
  Schedule? initial,
  DateTime Function()? now,
}) {
  return showDialog<ScheduleEditorResult>(
    context: context,
    builder: (_) => _ScheduleEditorDialog(
      goals: goals,
      displayTimeZoneId: displayTimeZoneId,
      initialDay: initialDay,
      initial: initial,
      now: now,
    ),
  );
}

class _ScheduleEditorDialog extends StatefulWidget {
  const _ScheduleEditorDialog({
    required this.goals,
    required this.displayTimeZoneId,
    required this.initialDay,
    this.initial,
    this.now,
  });

  final List<Goal> goals;
  final String displayTimeZoneId;
  final DateTime initialDay;
  final Schedule? initial;
  final DateTime Function()? now;

  @override
  State<_ScheduleEditorDialog> createState() => _ScheduleEditorDialogState();
}

class _ScheduleEditorDialogState extends State<_ScheduleEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late bool _allDay;
  late DateTime _day;
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _taskId;
  int? _reminderMinutesBefore;

  timezone.Location get _location =>
      FocusTimeZones.location(widget.displayTimeZoneId);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
    _taskId = initial?.taskId;
    _reminderMinutesBefore = initial?.reminderMinutesBefore;
    if (initial == null) {
      _allDay = false;
      _day = widget.initialDay;
      _start = const TimeOfDay(hour: 9, minute: 0);
      _end = const TimeOfDay(hour: 10, minute: 0);
      return;
    }
    _allDay = initial.allDay;
    final startLocal = timezone.TZDateTime.from(
      initial.startsAt.toUtc(),
      _location,
    );
    _day = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final start = initial.allDay
        ? startLocal
        : timezone.TZDateTime.from(initial.startsAt.toUtc(), _location);
    final end = timezone.TZDateTime.from(initial.endsAt.toUtc(), _location);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = TimeOfDay(hour: end.hour, minute: end.minute);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _startDate =>
      '${_day.year.toString().padLeft(4, '0')}-'
      '${_day.month.toString().padLeft(2, '0')}-'
      '${_day.day.toString().padLeft(2, '0')}';

  String get _endDate {
    final end = DateTime(_day.year, _day.month, _day.day + 1);
    return '${end.year.toString().padLeft(4, '0')}-'
        '${end.month.toString().padLeft(2, '0')}-'
        '${end.day.toString().padLeft(2, '0')}';
  }

  DateTime _toUtc(DateTime day, TimeOfDay time) => timezone.TZDateTime(
    _location,
    day.year,
    day.month,
    day.day,
    time.hour,
    time.minute,
  ).toUtc();

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError(context, '安排需要一个名称。');
      return;
    }
    final ScheduleWindow window;
    if (_allDay) {
      window = ScheduleWindow.allDayDates(
        startDate: _startDate,
        endDateExclusive: _endDate,
      );
    } else {
      final start = _toUtc(_day, _start);
      var end = _toUtc(_day, _end);
      if (!end.isAfter(start)) {
        // 结束早于开始时视为跨到次日同一时刻。
        end = end.add(const Duration(days: 1));
      }
      window = ScheduleWindow.timed(startsAt: start, endsAt: end);
    }
    Navigator.pop(
      context,
      ScheduleEditorResult(
        draft: ScheduleDraft(
          title: title,
          notes: _notes.text.trim(),
          window: window,
          taskId: _taskId,
        ),
        reminderMinutesBefore: _reminderMinutesBefore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = [
      for (final goal in widget.goals)
        for (final task in goal.tasks) (goal: goal, task: task),
    ];
    return AlertDialog(
      title: Text(widget.initial == null ? '新建安排' : '编辑安排'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: '名称',
                helperText: '例如：写报告 上半场，或取快递',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                alignLabelWithHint: true,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allDay,
              onChanged: (value) => setState(() => _allDay = value),
              title: const Text('全天'),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _day = picked);
                      }
                    },
                    icon: const Icon(Icons.event),
                    label: Text(_startDate),
                  ),
                ),
                if (!_allDay) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _start,
                        );
                        if (picked != null) setState(() => _start = picked);
                      },
                      child: Text('开始 ${_start.format(context)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _end,
                        );
                        if (picked != null) setState(() => _end = picked);
                      },
                      child: Text('结束 ${_end.format(context)}'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _taskId,
              decoration: const InputDecoration(labelText: '关联任务（可选）'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('独立事项（不关联任务）'),
                ),
                for (final entry in tasks)
                  DropdownMenuItem<String?>(
                    value: entry.task.id,
                    child: Text(
                      entry.task.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _taskId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _reminderMinutesBefore,
              decoration: const InputDecoration(labelText: '提醒（可选）'),
              items: const [
                DropdownMenuItem<int?>(value: null, child: Text('不提醒')),
                DropdownMenuItem<int?>(value: 5, child: Text('提前 5 分钟')),
                DropdownMenuItem<int?>(value: 10, child: Text('提前 10 分钟')),
                DropdownMenuItem<int?>(value: 15, child: Text('提前 15 分钟')),
                DropdownMenuItem<int?>(value: 30, child: Text('提前 30 分钟')),
                DropdownMenuItem<int?>(value: 1440, child: Text('提前 1 天')),
              ],
              onChanged: (value) =>
                  setState(() => _reminderMinutesBefore = value),
            ),
            const SizedBox(height: 8),
            Text(
              '提醒只是提醒：到点不会自动开始专注。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

/// 改期：只选新的时间窗口，保留名称、备注、任务关联与提醒配置。
Future<ScheduleWindow?> showRescheduleDialog(
  BuildContext context, {
  required Schedule schedule,
  required String displayTimeZoneId,
}) {
  return showDialog<ScheduleWindow>(
    context: context,
    builder: (_) => _RescheduleDialog(
      schedule: schedule,
      displayTimeZoneId: displayTimeZoneId,
    ),
  );
}

class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({
    required this.schedule,
    required this.displayTimeZoneId,
  });

  final Schedule schedule;
  final String displayTimeZoneId;

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  late DateTime _day;
  late TimeOfDay _start;
  late TimeOfDay _end;

  timezone.Location get _location =>
      FocusTimeZones.location(widget.displayTimeZoneId);

  @override
  void initState() {
    super.initState();
    final start = timezone.TZDateTime.from(
      widget.schedule.startsAt.toUtc(),
      _location,
    );
    final end = timezone.TZDateTime.from(
      widget.schedule.endsAt.toUtc(),
      _location,
    );
    _day = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = TimeOfDay(hour: end.hour, minute: end.minute);
  }

  String get _startDate =>
      '${_day.year.toString().padLeft(4, '0')}-'
      '${_day.month.toString().padLeft(2, '0')}-'
      '${_day.day.toString().padLeft(2, '0')}';

  String get _endDate {
    final end = DateTime(_day.year, _day.month, _day.day + 1);
    return '${end.year.toString().padLeft(4, '0')}-'
        '${end.month.toString().padLeft(2, '0')}-'
        '${end.day.toString().padLeft(2, '0')}';
  }

  DateTime _toUtc(TimeOfDay time) => timezone.TZDateTime(
    _location,
    _day.year,
    _day.month,
    _day.day,
    time.hour,
    time.minute,
  ).toUtc();

  void _save() {
    if (widget.schedule.allDay) {
      Navigator.pop(
        context,
        ScheduleWindow.allDayDates(
          startDate: _startDate,
          endDateExclusive: _endDate,
        ),
      );
      return;
    }
    final start = _toUtc(_start);
    var end = _toUtc(_end);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    Navigator.pop(context, ScheduleWindow.timed(startsAt: start, endsAt: end));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('改期'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _day = picked);
            },
            icon: const Icon(Icons.event),
            label: Text(_startDate),
          ),
          if (!widget.schedule.allDay) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _start,
                      );
                      if (picked != null) setState(() => _start = picked);
                    },
                    child: Text('开始 ${_start.format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _end,
                      );
                      if (picked != null) setState(() => _end = picked);
                    },
                    child: Text('结束 ${_end.format(context)}'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

/// 单条安排覆盖的日历日（账号显示时区）。
///
/// 全天日程直接使用已存的日期串；定时日程把 UTC 时刻换算到显示时区，
/// 结束时刻恰为零点时不计入次日。
List<DateTime> scheduleDays(Schedule schedule, String displayTimeZoneId) {
  if (schedule.allDay) {
    final start = _parseScheduleDate(schedule.allDayStartDate);
    if (start == null) return const [];
    final endExclusive = _parseScheduleDate(schedule.allDayEndDateExclusive);
    final result = <DateTime>[];
    var cursor = start;
    final limit = endExclusive ?? start.add(const Duration(days: 1));
    var guard = 0;
    while (cursor.isBefore(limit) && guard < 370) {
      result.add(cursor);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      guard++;
    }
    return result;
  }
  final location = FocusTimeZones.location(displayTimeZoneId);
  final start = timezone.TZDateTime.from(schedule.startsAt.toUtc(), location);
  var end = timezone.TZDateTime.from(schedule.endsAt.toUtc(), location);
  if (!end.isAfter(start)) end = start;
  final endsAtMidnight = end.hour == 0 && end.minute == 0;
  final lastDay = endsAtMidnight && end.isAfter(start)
      ? end.subtract(const Duration(minutes: 1))
      : end;
  return [
    for (
      var day = DateTime(start.year, start.month, start.day);
      !day.isAfter(DateTime(lastDay.year, lastDay.month, lastDay.day));
      day = DateTime(day.year, day.month, day.day + 1)
    )
      day,
  ];
}

/// 某一天内的安排，按全天在前、开始时刻、稳定 id 排序。
List<Schedule> schedulesOnDay(
  List<Schedule> schedules,
  DateTime day,
  String displayTimeZoneId,
) {
  final result = [
    for (final schedule in schedules)
      if (scheduleDays(schedule, displayTimeZoneId).contains(day)) schedule,
  ];
  result.sort((left, right) {
    if (left.allDay != right.allDay) return left.allDay ? -1 : 1;
    final byStart = left.startsAt.compareTo(right.startsAt);
    if (byStart != 0) return byStart;
    return left.id.compareTo(right.id);
  });
  return result;
}

/// 日程时间标签（账号显示时区）。
String scheduleTimeLabel(Schedule schedule, String displayTimeZoneId) {
  if (schedule.allDay) return '全天';
  final location = FocusTimeZones.location(displayTimeZoneId);
  final start = timezone.TZDateTime.from(schedule.startsAt.toUtc(), location);
  final end = timezone.TZDateTime.from(schedule.endsAt.toUtc(), location);
  return formatScheduleTime(start, end);
}

/// 账号显示时区里的“今天”（仅日期部分）。
DateTime scheduleToday(String displayTimeZoneId, {DateTime? now}) {
  final location = FocusTimeZones.location(displayTimeZoneId);
  final zoned = timezone.TZDateTime.from(
    (now ?? DateTime.now()).toUtc(),
    location,
  );
  return DateTime(zoned.year, zoned.month, zoned.day);
}

/// 覆盖某一天的查询窗口；前后各留一天，避免时区偏移漏掉边界记录。
({DateTime from, DateTime to}) scheduleQueryWindow(
  DateTime day,
  String displayTimeZoneId,
) {
  final location = FocusTimeZones.location(displayTimeZoneId);
  final start = timezone.TZDateTime(
    location,
    day.year,
    day.month,
    day.day,
  ).toUtc();
  final next = timezone.TZDateTime(
    location,
    day.year,
    day.month,
    day.day + 1,
  ).toUtc();
  return (
    from: start.subtract(const Duration(days: 1)),
    to: next.add(const Duration(days: 1)),
  );
}

DateTime? _parseScheduleDate(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 时间文本：调用方已把时刻换算到账号显示时区。
String formatScheduleTime(DateTime startsAt, DateTime endsAt) {
  final start = startsAt;
  final end = endsAt;
  String two(int value) => value.toString().padLeft(2, '0');
  final startText = '${two(start.hour)}:${two(start.minute)}';
  final endText = '${two(end.hour)}:${two(end.minute)}';
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) return '$startText–$endText';
  return '$startText – ${end.month}/${end.day} $endText';
}

String formatReminderOffset(int minutes) {
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
  return '$minutes 分钟';
}
