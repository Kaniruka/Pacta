import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_time_zones.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repeat.dart';
import '../schedules/schedule_repeat_editor.dart';
import '../tasks/task_models.dart';

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 编辑器结果：草稿 + 可选提醒 + 重复设置（提醒只存配置，投递由 06 负责）。
class ScheduleEditorResult {
  const ScheduleEditorResult({
    required this.draft,
    required this.reminderMinutesBefore,
    this.repeat = const ScheduleRepeatSelection.none(),
    this.scope = ScheduleRepeatScope.onlyThis,
    this.isExistingRecurring = false,
  });

  final ScheduleDraft draft;
  final int? reminderMinutesBefore;

  /// 新建时的重复选择；编辑既有重复项时，本次及以后使用它的新规则。
  final ScheduleRepeatSelection repeat;

  /// 编辑既有重复项的作用范围；新建或非重复项忽略。
  final ScheduleRepeatScope scope;

  final bool isExistingRecurring;
}

/// 编辑器与改期对话框共用的日历边界。
///
/// 全部是**显示时区**里的公历日期：全天用 allDay 的起止日期原值，定时用
/// 开始/结束在显示时区的当地日期。全程不经过 UTC 反推，负时区的全天安排
/// 因此不会被挪到前一天，多天安排也不会被压回一天。
class ScheduleCalendarBounds {
  const ScheduleCalendarBounds({
    required this.allDay,
    required this.startDay,
    required this.endDay,
    required this.start,
    required this.end,
  });

  final bool allDay;
  final DateTime startDay;
  final DateTime endDay;
  final TimeOfDay start;
  final TimeOfDay end;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _civilDateText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _localToUtc(
  timezone.Location location,
  DateTime day,
  TimeOfDay time,
) => timezone.TZDateTime(
  location,
  day.year,
  day.month,
  day.day,
  time.hour,
  time.minute,
).toUtc();

/// 从既有安排还原编辑器状态：全天读 allDay 的公历日期，定时读当地日期。
ScheduleCalendarBounds scheduleCalendarBounds(
  Schedule schedule,
  String displayTimeZoneId,
) {
  if (schedule.allDay) {
    final startDate = schedule.allDayStartDate;
    final endDate = schedule.allDayEndDateExclusive;
    if (startDate == null || endDate == null) {
      throw StateError('全天安排缺少日期范围。');
    }
    return ScheduleCalendarBounds(
      allDay: true,
      startDay: _dateOnly(DateTime.parse(startDate)),
      endDay: _dateOnly(DateTime.parse(endDate)),
      start: const TimeOfDay(hour: 0, minute: 0),
      end: const TimeOfDay(hour: 0, minute: 0),
    );
  }
  final location = FocusTimeZones.location(displayTimeZoneId);
  final start = timezone.TZDateTime.from(schedule.startsAt.toUtc(), location);
  final end = timezone.TZDateTime.from(schedule.endsAt.toUtc(), location);
  return ScheduleCalendarBounds(
    allDay: false,
    startDay: _dateOnly(start),
    endDay: _dateOnly(end),
    start: TimeOfDay(hour: start.hour, minute: start.minute),
    end: TimeOfDay(hour: end.hour, minute: end.minute),
  );
}

/// 由日历边界构造窗口。
///
/// 全天只用公历日期；定时在显示时区里把「日期 + 时刻」换成 UTC。结束不晚于
/// 开始时：同一天按**当地日历日**推进一天（不是 UTC +24h，夏令时切换才不会
/// 差一小时），跨天则视为无效输入。
ScheduleWindow buildScheduleWindow({
  required String displayTimeZoneId,
  required ScheduleCalendarBounds bounds,
}) {
  if (bounds.allDay) {
    if (!bounds.endDay.isAfter(bounds.startDay)) {
      throw ArgumentError('全天安排的结束日期必须晚于开始日期。');
    }
    return ScheduleWindow.allDayDates(
      startDate: _civilDateText(bounds.startDay),
      endDateExclusive: _civilDateText(bounds.endDay),
    );
  }
  final location = FocusTimeZones.location(displayTimeZoneId);
  final startUtc = _localToUtc(location, bounds.startDay, bounds.start);
  var endUtc = _localToUtc(location, bounds.endDay, bounds.end);
  if (!endUtc.isAfter(startUtc)) {
    final sameDay =
        bounds.endDay.year == bounds.startDay.year &&
        bounds.endDay.month == bounds.startDay.month &&
        bounds.endDay.day == bounds.startDay.day;
    if (!sameDay) {
      throw ArgumentError('结束必须晚于开始。');
    }
    final nextDay = DateTime(
      bounds.startDay.year,
      bounds.startDay.month,
      bounds.startDay.day + 1,
    );
    endUtc = _localToUtc(location, nextDay, bounds.end);
  }
  return ScheduleWindow.timed(startsAt: startUtc, endsAt: endUtc);
}

Future<ScheduleEditorResult?> showScheduleEditor(
  BuildContext context, {
  required List<Goal> goals,
  required String displayTimeZoneId,
  required DateTime initialDay,
  Schedule? initial,
  DateTime Function()? now,
  ScheduleRepeatSelection? initialRepeat,
  ScheduleRepeatSelection? existingRepeat,
  int? existingRuleReminder,
}) {
  return showDialog<ScheduleEditorResult>(
    context: context,
    builder: (_) => _ScheduleEditorDialog(
      goals: goals,
      displayTimeZoneId: displayTimeZoneId,
      initialDay: initialDay,
      initial: initial,
      now: now,
      initialRepeat: initialRepeat,
      existingRepeat: existingRepeat,
      existingRuleReminder: existingRuleReminder,
    ),
  );
}

/// 重复日程的修改范围选择：先确认「仅本次 / 本次及以后」，再进入具体编辑。
Future<ScheduleRepeatScope?> showRepeatScopeDialog(
  BuildContext context, {
  ScheduleRepeatScope initial = ScheduleRepeatScope.onlyThis,
}) {
  var scope = initial;
  return showDialog<ScheduleRepeatScope>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('修改这条重复安排'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('这次修改要影响哪些实例？'),
            const SizedBox(height: 8),
            ScheduleRepeatScopeSelector(
              value: scope,
              onChanged: (next) => setDialogState(() => scope = next),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('schedule-scope-confirm'),
            onPressed: () => Navigator.of(context).pop(scope),
            child: const Text('继续'),
          ),
        ],
      ),
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
    this.initialRepeat,
    this.existingRepeat,
    this.existingRuleReminder,
  });

  final List<Goal> goals;
  final String displayTimeZoneId;
  final DateTime initialDay;
  final Schedule? initial;
  final DateTime Function()? now;

  /// 编辑既有重复项时从规则还原的当前设置。
  final ScheduleRepeatSelection? existingRepeat;

  /// 规则模板自身的提醒偏移；"本次及以后"用它作为可见初值。
  final int? existingRuleReminder;

  /// 新建时的初始重复选择（默认不重复）。
  final ScheduleRepeatSelection? initialRepeat;

  @override
  State<_ScheduleEditorDialog> createState() => _ScheduleEditorDialogState();
}

class _ScheduleEditorDialogState extends State<_ScheduleEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late bool _allDay;
  late DateTime _day;
  late DateTime _endDay;
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _taskId;
  int? _reminderMinutesBefore;
  late ScheduleRepeatSelection _repeat;
  var _scope = ScheduleRepeatScope.onlyThis;
  final ScrollController _scrollController = ScrollController();
  double _lastViewInsetBottom = 0;

  /// 浮动标签画在字段上沿之外，内容顶部至少留一行标签的高度。
  static const double _dialogContentTopInset = 12;

  bool get _isExistingRecurring => widget.initial?.isRecurring ?? false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
    _taskId = initial?.taskId;
    _reminderMinutesBefore = initial?.reminderMinutesBefore;
    _repeat =
        widget.existingRepeat ??
        widget.initialRepeat ??
        const ScheduleRepeatSelection.none();
    if (initial == null) {
      _allDay = false;
      _day = _dateOnly(widget.initialDay);
      _endDay = _day;
      _start = const TimeOfDay(hour: 9, minute: 0);
      _end = const TimeOfDay(hour: 10, minute: 0);
      return;
    }
    // 既有安排按它自己的日历边界还原：全天读公历日期，定时读当地日期，
    // 不改写、不压缩多天安排。
    final bounds = scheduleCalendarBounds(initial, widget.displayTimeZoneId);
    _allDay = bounds.allDay;
    _day = bounds.startDay;
    _endDay = bounds.endDay;
    _start = bounds.start;
    _end = bounds.end;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    // 只在键盘**收起**时复位：收起后视口恢复，滚动位置若原样保留，首字段的
    // 浮动标签会被推到视口上沿之外。弹出方向不复位——那会把用户正滚动到
    // 下方字段的位置抢回顶部。
    final closing = insetBottom == 0 && _lastViewInsetBottom > 0;
    _lastViewInsetBottom = insetBottom;
    if (!closing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.offset != 0) _scrollController.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ScheduleCalendarBounds get _bounds => ScheduleCalendarBounds(
    allDay: _allDay,
    startDay: _day,
    endDay: _endDay,
    start: _start,
    end: _end,
  );

  /// 本次是否会写出重复规则：新建重复，或既有重复项改到"本次及以后"。
  bool get _writesRepeatRule => _isExistingRecurring
      ? _scope == ScheduleRepeatScope.thisAndFuture
      : _repeat.repeats;

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError(context, '安排需要一个名称。');
      return;
    }
    if (_writesRepeatRule && !_repeat.isValid) {
      _showError(context, '每周重复至少要选一天，结束日期要用有效日历日。');
      return;
    }
    final ScheduleWindow window;
    try {
      window = buildScheduleWindow(
        displayTimeZoneId: widget.displayTimeZoneId,
        bounds: _bounds,
      );
    } on ArgumentError catch (error) {
      _showError(context, '${error.message}');
      return;
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
        repeat: _repeat,
        scope: _writesRepeatRule
            ? ScheduleRepeatScope.thisAndFuture
            : ScheduleRepeatScope.onlyThis,
        isExistingRecurring: _isExistingRecurring,
      ),
    );
  }

  /// 既有链接若指向已删除任务，返回可读标签；指向在用任务时返回 null。
  String? _linkedTaskLabel() {
    final taskId = _taskId;
    if (taskId == null) return null;
    for (final goal in widget.goals) {
      for (final task in goal.tasks) {
        if (task.id != taskId) continue;
        return task.isDeleted ? '已删除的任务：${task.title}' : null;
      }
    }
    return '已删除的任务（保留原关联）';
  }

  @override
  Widget build(BuildContext context) {
    // 已删除的任务不再出现在可选项里：既不能新建关联，也不能被重新挂上。
    final tasks = [
      for (final goal in widget.goals)
        for (final task in goal.tasks)
          if (!task.isDeleted) (goal: goal, task: task),
    ];
    final linkedLabel = _linkedTaskLabel();
    return AlertDialog(
      title: Text(widget.initial == null ? '新建安排' : '编辑安排'),
      content: SingleChildScrollView(
        controller: _scrollController,
        // 浮动标签画在字段上沿之外，顶部至少要留出一行标签的高度，
        // 否则滚动到顶时标签上半会被视口裁掉。
        padding: const EdgeInsets.only(top: _dialogContentTopInset),
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
              onChanged: (value) => setState(() {
                _allDay = value;
                // 切到全天时，同一天的定时草稿没有合法的"不含结束日"：
                // 只把这一种情况推进到次日；已有多天范围原样保留。
                if (value && !_endDay.isAfter(_day)) {
                  _endDay = DateTime(_day.year, _day.month, _day.day + 1);
                }
              }),
              title: const Text('全天'),
            ),
            Column(
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
                    if (picked != null) {
                      setState(() {
                        _day = _dateOnly(picked);
                        // 开始日越过结束日时：全天推到次日，定时回到同一天。
                        if (!_endDay.isAfter(_day)) {
                          _endDay = _allDay
                              ? DateTime(_day.year, _day.month, _day.day + 1)
                              : _day;
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.event),
                  label: Text('开始 ${_civilDateText(_day)}'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDay.isAfter(_day)
                          ? _endDay
                          : DateTime(_day.year, _day.month, _day.day + 1),
                      firstDate: _day,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _endDay = _dateOnly(picked));
                    }
                  },
                  icon: const Icon(Icons.event_available),
                  label: Text(
                    _allDay
                        ? '结束（不含） ${_civilDateText(_endDay)}'
                        : '结束 ${_civilDateText(_endDay)}',
                  ),
                ),
                if (!_allDay) ...[
                  const SizedBox(height: 8),
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
                if (_allDay)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '全天安排按日历日期保存，结束日期不含当天。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isExistingRecurring) ...[
              Text('重复安排', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ScheduleRepeatScopeSelector(
                value: _scope,
                onChanged: (next) => setState(() {
                  _scope = next;
                  // 两种范围各自有一个明确初值：仅本次是这条实例的提醒，
                  // 本次及以后是规则模板的提醒。切换时直接换成对应值，
                  // 保存时再显式提交，不把实例值悄悄写进规则。
                  _reminderMinutesBefore = next == ScheduleRepeatScope.onlyThis
                      ? widget.initial?.reminderMinutesBefore
                      : widget.existingRuleReminder;
                }),
              ),
              if (_scope == ScheduleRepeatScope.onlyThis)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '仅本次只改这一个实例，重复规则和其他实例保持原样。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                ScheduleRepeatEditor(
                  value: _repeat,
                  onChanged: (next) => setState(() => _repeat = next),
                  firstDate: _day,
                  allowDisable: false,
                ),
            ] else
              ScheduleRepeatEditor(
                value: _repeat,
                onChanged: (next) => setState(() => _repeat = next),
                firstDate: _day,
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _taskId,
              // 选中项按整行宽度排布并省略，避免真实字体（MiSans）在 360 宽下
              // 于最小宽度的一行里溢出。菜单项同样受此约束。
              isExpanded: true,
              decoration: const InputDecoration(labelText: '关联任务（可选）'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('独立事项（不关联任务）', overflow: TextOverflow.ellipsis),
                ),
                for (final entry in tasks)
                  DropdownMenuItem<String?>(
                    value: entry.task.id,
                    child: Text(
                      entry.task.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                // 原关联任务已被删除时保留身份：只显示只读条目，
                // 既不让下拉断言失败，也不允许新关联到已删除的任务。
                if (linkedLabel != null)
                  DropdownMenuItem<String?>(
                    value: _taskId,
                    enabled: false,
                    child: Text(linkedLabel, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _taskId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              // 切换修改范围会替换提醒初值；用范围作 key 让表单字段按新初值重建。
              key: ValueKey('schedule-reminder-${_scope.name}'),
              initialValue: _reminderMinutesBefore,
              isExpanded: true,
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
  late DateTime _endDay;
  late TimeOfDay _start;
  late TimeOfDay _end;

  @override
  void initState() {
    super.initState();
    // 改期同样按安排自己的日历边界还原：全天用公历日期，定时用当地日期，
    // 多天窗口原样保留，不压回一天。
    final bounds = scheduleCalendarBounds(
      widget.schedule,
      widget.displayTimeZoneId,
    );
    _day = bounds.startDay;
    _endDay = bounds.endDay;
    _start = bounds.start;
    _end = bounds.end;
  }

  void _save() {
    final ScheduleWindow window;
    try {
      window = buildScheduleWindow(
        displayTimeZoneId: widget.displayTimeZoneId,
        bounds: ScheduleCalendarBounds(
          allDay: widget.schedule.allDay,
          startDay: _day,
          endDay: _endDay,
          start: _start,
          end: _end,
        ),
      );
    } on ArgumentError catch (error) {
      _showError(context, '${error.message}');
      return;
    }
    Navigator.pop(context, window);
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
              if (picked != null) {
                setState(() {
                  _day = _dateOnly(picked);
                  if (!_endDay.isAfter(_day)) {
                    _endDay = widget.schedule.allDay
                        ? DateTime(_day.year, _day.month, _day.day + 1)
                        : _day;
                  }
                });
              }
            },
            icon: const Icon(Icons.event),
            label: Text('开始 ${_civilDateText(_day)}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDay.isAfter(_day)
                    ? _endDay
                    : DateTime(_day.year, _day.month, _day.day + 1),
                firstDate: _day,
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => _endDay = _dateOnly(picked));
              }
            },
            icon: const Icon(Icons.event_available),
            label: Text(
              widget.schedule.allDay
                  ? '结束（不含） ${_civilDateText(_endDay)}'
                  : '结束 ${_civilDateText(_endDay)}',
            ),
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
