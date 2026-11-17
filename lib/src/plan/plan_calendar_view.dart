import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../calendar/calendar_repository.dart';
import '../calendar/manual_calendar_import.dart';
import '../focus/focus_time_zones.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repeat.dart';
import '../schedules/schedule_repeat_editor.dart';
import '../schedules/schedule_repository.dart';
import '../tasks/task_models.dart';
import 'calendar_almanac.dart';

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
    this.calendarRepository,
    this.initialDay,
    this.highlightScheduleId,
    this.almanac,
  });

  final ScheduleRepository repository;
  final List<Goal> goals;
  final String displayTimeZoneId;
  final DateTime Function()? now;

  /// 手动导入的来源读取入口；为 null 时页面不显示导入入口。
  final CalendarRepository? calendarRepository;

  /// 打开时先选中的日历日（账号显示时区）；通知点击用它定位到具体安排。
  final DateTime? initialDay;

  /// 通知要定位的已拥有安排；只在当前账号的日程流里命中时才强调，
  /// 不存在（已删除或不属于本账号）就只停留在 [initialDay]，不建专注。
  final String? highlightScheduleId;

  /// 旧历/节气/休班知识；为 null 时由页面自己从 assets 加载。
  final CalendarAlmanac? almanac;

  @override
  State<PlanCalendarView> createState() => _PlanCalendarViewState();
}

class _PlanCalendarViewState extends State<PlanCalendarView> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  String? _highlightedScheduleId;

  /// 通知目标定位请求的代次：只接受最新一次请求的结果。
  int _targetRequest = 0;

  /// 当前订阅的数据源身份：换仓储（账号所有者）或换月窗口都会换一份。
  ///
  /// 换源时必须**立即丢弃**上一源已渲染的数据：新流要到下一次数据库读取
  /// 才会 emit，这段时间继续显示旧 rows 就是把别的账号/别的月份的安排
  /// 当成当前内容。
  _ScheduleSource? _scheduleSource;

  /// 当前源的行；只在代次匹配时写入。
  List<Schedule> _schedules = const <Schedule>[];

  /// 读取失败。与"正常空内容"分开：失败不会被渲染成 0 项安排。
  Object? _schedulesError;

  /// 新源订阅后、首个事件到达前为 true。
  bool _loadingSchedules = true;

  /// 订阅代次：旧源/旧订阅的迟到事件一律丢弃。
  int _sourceGeneration = 0;

  /// 旧历/节气/休班知识；加载完成前只显示公历日期，不阻塞日历。
  CalendarAlmanac? _almanac;

  StreamSubscription<List<Schedule>>? _scheduleSubscription;

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
    final initial = widget.initialDay ?? DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(initial.year, initial.month);
    _selectedDay = DateTime(initial.year, initial.month, initial.day);
    _highlightedScheduleId = widget.highlightScheduleId;
    _almanac = widget.almanac;
    if (_almanac == null) unawaited(_loadAlmanac());
    unawaited(_resolveHighlightedSchedule());
  }

  Future<void> _loadAlmanac() async {
    final almanac = await loadCalendarAlmanac();
    if (!mounted || almanac.isEmpty) return;
    setState(() => _almanac = almanac);
  }

  @override
  void didUpdateWidget(PlanCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.initialDay;
    final idChanged =
        widget.highlightScheduleId != oldWidget.highlightScheduleId;
    final dayChanged = target != null && target != oldWidget.initialDay;
    // 数据源换了（仓储/账号所有者）或显示时区换了：旧请求一律作废。
    final sourceChanged =
        !identical(widget.repository, oldWidget.repository) ||
        widget.displayTimeZoneId != oldWidget.displayTimeZoneId;
    if (!idChanged && !dayChanged && !sourceChanged) return;
    _targetRequest += 1;
    setState(() {
      if (idChanged) _highlightedScheduleId = widget.highlightScheduleId;
      if (dayChanged) {
        _selectedDay = DateTime(target.year, target.month, target.day);
        _visibleMonth = DateTime(target.year, target.month);
      }
    });
    if (_highlightedScheduleId != null) {
      unawaited(_resolveHighlightedSchedule());
    }
  }

  /// 用户自己换了日子/月份：通知带来的强调与在途请求一起失效。
  void _clearHighlightedSchedule() {
    _highlightedScheduleId = null;
    _targetRequest += 1;
  }

  /// 通知指向的安排若被改期，就跟它当前所在的账号时区日走。
  ///
  /// 月视图只订阅当前月的窗口，所以这里按 id 做一次**只读**的全量读取：
  /// 命中当前账号的安排就移到它所在的那一天；id 已不存在（删除或不属于
  /// 本账号）时保留负载日期，不猜、不写、不建专注。
  Future<void> _resolveHighlightedSchedule() async {
    final id = _highlightedScheduleId;
    if (id == null) return;
    // 捕获本次请求的来源与代次：等待期间仓储/账号所有者/时区/目标日可能
    // 已经换掉，旧结果即使命中同一个 id 也不能改写新账号的日期。
    final repository = widget.repository;
    final zoneId = widget.displayTimeZoneId;
    final request = ++_targetRequest;
    final List<Schedule> schedules;
    try {
      schedules = await repository.getSchedules();
    } catch (_) {
      return;
    }
    if (!mounted || request != _targetRequest) return;
    if (_highlightedScheduleId != id) return;
    if (!identical(widget.repository, repository)) return;
    if (widget.displayTimeZoneId != zoneId) return;
    Schedule? match;
    for (final schedule in schedules) {
      if (schedule.id != id) continue;
      match = schedule;
      break;
    }
    if (match == null) return;
    final days = scheduleDays(match, widget.displayTimeZoneId);
    if (days.isEmpty || days.contains(_selectedDay)) return;
    final sorted = days.toList()..sort();
    final day = sorted.firstWhere(
      (candidate) =>
          candidate.year == _selectedDay.year &&
          candidate.month == _selectedDay.month,
      orElse: () => sorted.first,
    );
    setState(() {
      _selectedDay = day;
      _visibleMonth = DateTime(day.year, day.month);
    });
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
  void dispose() {
    _scheduleSubscription?.cancel();
    _scheduleSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 订阅身份只从渲染输入推导：仓储、显示时区、月窗口任何一处变了，这里
    // 都会先清掉旧数据再订阅新流，不依赖每个改月入口各自记得刷新。
    _ensureScheduleStream(_sourceFor(_visibleMonth));
    final schedules = _schedules;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 8),
        _buildMonthGrid(context, schedules),
        const SizedBox(height: 16),
        _buildDaySection(context, schedules),
      ],
    );
  }

  _ScheduleSource _sourceFor(DateTime month) {
    final nextMonth = DateTime(month.year, month.month + 1);
    return _ScheduleSource(
      repository: widget.repository,
      month: month,
      // 前后各留一天，覆盖时区偏移与全天日程的 UTC 午夜边界。
      from: _utcStart(month).subtract(const Duration(days: 1)),
      to: _utcStart(nextMonth).add(const Duration(days: 2)),
    );
  }

  /// 同一个仓储、同一个月窗口沿用一份订阅；否则换源。
  void _ensureScheduleStream(_ScheduleSource source) {
    final current = _scheduleSource;
    if (current != null && current.matches(source)) return;
    _scheduleSource = source;
    // 旧 rows 属于上一 owner/窗口：新流首个事件到达前不得继续显示。
    _schedules = const <Schedule>[];
    _schedulesError = null;
    _loadingSchedules = true;
    _subscribe(source);
  }

  void _subscribe(_ScheduleSource source) {
    final previous = _scheduleSubscription;
    _sourceGeneration += 1;
    final generation = _sourceGeneration;
    try {
      _scheduleSubscription = source.repository
          .watchSchedules(from: source.from, to: source.to)
          .listen(
            (rows) => _applySchedules(generation, rows),
            onError: (Object error, StackTrace stackTrace) =>
                _applySchedulesError(generation, error),
            onDone: () => _applySchedulesDone(generation),
          );
    } catch (error) {
      // 已释放或不可用的仓储会在调用时就抛：同样要给可见失败，而不是空安排。
      _scheduleSubscription = null;
      _applySchedulesError(generation, error);
    }
    unawaited(previous?.cancel());
  }

  /// 只接受当前代次的结果：换源后的迟到事件不得回显。
  void _applySchedules(int generation, List<Schedule> rows) =>
      _mutateSchedules(generation, () {
        _schedules = rows;
        _schedulesError = null;
        _loadingSchedules = false;
      });

  void _applySchedulesError(int generation, Object error) =>
      _mutateSchedules(generation, () {
        // 失败不是空内容：清掉上一源的行，把错误留给可见的重试入口。
        _schedules = const <Schedule>[];
        _schedulesError = error;
        _loadingSchedules = false;
      });

  void _applySchedulesDone(int generation) => _mutateSchedules(generation, () {
    _loadingSchedules = false;
  });

  void _mutateSchedules(int generation, VoidCallback change) {
    if (!mounted || generation != _sourceGeneration) return;
    // 同步流可能在 build 期间回灌：推到本帧之后再 setState。
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (!mounted || generation != _sourceGeneration) return;
        setState(change);
      });
      return;
    }
    setState(change);
  }

  /// 只读重试：重新订阅当前源，不改动任何安排。
  void _retrySchedules() {
    final source = _scheduleSource;
    if (source == null) return;
    setState(() {
      _schedules = const <Schedule>[];
      _schedulesError = null;
      _loadingSchedules = true;
    });
    _subscribe(source);
  }

  static const double _narrowHeaderWidth = 480;

  Widget _buildHeader(BuildContext context) {
    final monthLabel = Text(
      '${_visibleMonth.year}年${_visibleMonth.month}月',
      key: const ValueKey('plan-month-label'),
      style: Theme.of(context).textTheme.titleMedium,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    final previous = IconButton(
      tooltip: '上个月',
      onPressed: () => setState(() {
        _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
        _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
        _clearHighlightedSchedule();
      }),
      icon: const Icon(Icons.chevron_left),
    );
    final next = IconButton(
      tooltip: '下个月',
      onPressed: () => setState(() {
        _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
        _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
        _clearHighlightedSchedule();
      }),
      icon: const Icon(Icons.chevron_right),
    );
    final import = widget.calendarRepository == null
        ? null
        : IconButton(
            key: const ValueKey('plan-import-open'),
            tooltip: '从系统日历导入',
            onPressed: _importFromCalendar,
            icon: const Icon(Icons.download_outlined),
          );
    final create = FilledButton.icon(
      onPressed: _createSchedule,
      icon: const Icon(Icons.add),
      label: const Text('新建安排'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏把导航和操作分成两行：年月要整段单行可读。挤在同一行会被折成
        // 「2026年11」+「月」，看起来像两个不相干的标签。
        if (constraints.maxWidth < _narrowHeaderWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  previous,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Align(
                        alignment: Alignment.center,
                        child: monthLabel,
                      ),
                    ),
                  ),
                  next,
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (import != null) import else const SizedBox(width: 8),
                  const Spacer(),
                  create,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            previous,
            Expanded(child: monthLabel),
            next,
            ?import,
            const SizedBox(width: 8),
            create,
          ],
        );
      },
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
    final info = _almanac?.describe(day);
    final labelColor = selected
        ? colorScheme.onPrimaryContainer
        : info?.kind == CalendarDayKind.holiday
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${day.month}月${day.day}日${info == null ? '' : ' ${info.shortLabel}'}',
      child: InkWell(
        key: ValueKey(
          'plan-day-${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
        ),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _selectedDay = day;
          // 用户自己换了日子，就不再强调通知带来的那一条。
          _clearHighlightedSchedule();
        }),
        child: Container(
          // 定案：日期格第二行 48→64dp，短标签最多 4 字。
          constraints: const BoxConstraints(minHeight: 64),
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
              SizedBox(
                height: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (marked)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.primary,
                        ),
                      ),
                    if (marked && info != null) const SizedBox(width: 3),
                    if (info != null)
                      Flexible(
                        child: Text(
                          info.shortLabel,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: labelColor,
                          ),
                        ),
                      ),
                  ],
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
    final dayLabel = '${_selectedDay.month}月${_selectedDay.day}日';
    // 失败/加载都不冒充"0 项安排"：那不是空内容，是还没读到或读不到。
    final String summary;
    if (_schedulesError != null) {
      summary = '$dayLabel · 读取失败';
    } else if (_loadingSchedules) {
      summary = '$dayLabel · 正在读取';
    } else {
      summary = '$dayLabel · ${daySchedules.length} 项安排';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary, style: Theme.of(context).textTheme.titleSmall),
        if (_almanac != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _almanac!.describe(_selectedDay).detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_schedulesError != null)
          _buildSchedulesError(context)
        else if (_loadingSchedules)
          _buildSchedulesLoading(context)
        else if (daySchedules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '这一天还没有安排。用上方「新建安排」添加。',
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
              highlighted: schedule.id == _highlightedScheduleId,
              timeLabel: scheduleTimeLabel(schedule, widget.displayTimeZoneId),
              taskLabel: _taskLabel(schedule.taskId),
              onToggleCompletion: (value) => _setCompletion(schedule, value),
              onEdit: () => _editSchedule(schedule),
              onReschedule: () => _reschedule(schedule),
              onDelete: () => _confirmDelete(schedule),
            ),
      ],
    );
  }

  /// 读取失败：说明没有删除数据，重试只重新读取。
  Widget _buildSchedulesError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('plan-schedules-error'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '暂时不能读取安排。',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '安排本身没有被删除；重试只重新读取，不会改动任何安排。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onErrorContainer),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('plan-schedules-retry'),
              onPressed: _retrySchedules,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }

  /// 新源首个事件到达前：明确在读取，不显示上一源的行。
  Widget _buildSchedulesLoading(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
          Text(
            '正在读取安排…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
        if (task.id != taskId) continue;
        // 任务被删除（墓碑）时链接仍然保留：用可读名称说明它已删除。
        return task.isDeleted ? '已删除的任务：${task.title}' : task.title;
      }
    }
    return '已删除的任务';
  }

  Set<DateTime> _markedDays(List<Schedule> schedules) => {
    for (final schedule in schedules)
      for (final day in scheduleDays(schedule, widget.displayTimeZoneId)) day,
  };

  Future<void> _importFromCalendar() async {
    final calendar = widget.calendarRepository;
    if (calendar == null) return;
    final message = await runManualCalendarImport(
      context,
      calendar: calendar,
      schedules: widget.repository,
      now: (widget.now ?? DateTime.now)(),
      displayTimeZoneId: widget.displayTimeZoneId,
      initialDay: _selectedDay,
    );
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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

  Future<void> _createSchedule({DateTime? day}) async {
    final result = await showScheduleEditor(
      context,
      goals: widget.goals,
      displayTimeZoneId: widget.displayTimeZoneId,
      initialDay: day ?? _selectedDay,
      now: widget.now,
    );
    if (result == null) return;
    try {
      final spec = result.repeat.spec;
      if (spec != null) {
        // 重复规则自带时区、窗口模板与提醒偏移；实例由仓储按规则生成。
        await widget.repository.createRecurringSchedule(
          draft: result.draft,
          repeat: spec,
          timeZoneId: widget.displayTimeZoneId,
          reminderMinutesBefore: result.reminderMinutesBefore,
        );
        return;
      }
      final created = await widget.repository.createSchedule(result.draft);
      await widget.repository.setScheduleReminder(
        created.id,
        minutesBefore: result.reminderMinutesBefore,
      );
    } catch (_) {
      if (!mounted) return;
      _showError(context, '安排没有保存，请稍后重试。');
    }
  }

  /// 既有重复实例所属规则：重复设置与规则级提醒；规则缺失时返回 null。
  Future<({ScheduleRepeatSelection selection, int? reminder})?> _ruleStateFor(
    Schedule schedule,
  ) async {
    if (!schedule.isRecurring) return null;
    try {
      final rules = await widget.repository.getRecurrenceRules();
      for (final rule in rules) {
        if (rule.id != schedule.recurrenceId) continue;
        return (
          selection: ScheduleRepeatSelection.repeating(
            frequency: rule.frequency,
            weekdays: rule.weekdays,
            endDate: rule.endDate,
          ),
          reminder: rule.reminderMinutesBefore,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _editSchedule(Schedule schedule) async {
    final ruleState = await _ruleStateFor(schedule);
    if (!mounted) return;
    if (schedule.isRecurring && ruleState == null) {
      _showError(context, '这条重复安排的规则暂时读不到，请稍后再试。');
      return;
    }
    final result = await showScheduleEditor(
      context,
      goals: widget.goals,
      displayTimeZoneId: widget.displayTimeZoneId,
      initial: schedule,
      initialDay: _selectedDay,
      now: widget.now,
      existingRepeat: ruleState?.selection,
      existingRuleReminder: ruleState?.reminder,
    );
    if (result == null) return;
    if (schedule.isRecurring) {
      try {
        // 界面总是显式提交可见的提醒选择：整数或清除，从不依赖省略。
        await widget.repository.editRecurringSchedule(
          schedule.id,
          draft: result.draft,
          scope: result.scope,
          repeat: result.scope == ScheduleRepeatScope.thisAndFuture
              ? result.repeat.spec
              : null,
          reminderMinutesBefore: result.reminderMinutesBefore,
          clearReminder: result.reminderMinutesBefore == null,
        );
      } catch (_) {
        if (!mounted) return;
        _showError(context, '安排没有更新，请稍后重试。');
      }
      return;
    }
    try {
      await widget.repository.updateSchedule(schedule.id, result.draft);
      await widget.repository.setScheduleReminder(
        schedule.id,
        minutesBefore: result.reminderMinutesBefore,
      );
    } catch (_) {
      if (!mounted) return;
      _showError(context, '安排没有更新，请稍后重试。');
    }
  }

  Future<void> _reschedule(Schedule schedule) async {
    var scope = ScheduleRepeatScope.onlyThis;
    if (schedule.isRecurring) {
      final chosen = await showRepeatScopeDialog(context);
      if (chosen == null || !mounted) return;
      scope = chosen;
    }
    final window = await showRescheduleDialog(
      context,
      schedule: schedule,
      displayTimeZoneId: widget.displayTimeZoneId,
    );
    if (window == null) return;
    try {
      if (schedule.isRecurring) {
        // 重复实例改期同样走实例/系列编辑：仅本次会留下持久例外，
        // 本次及以后才截断规则，历史实例不被当前规则重算。
        await widget.repository.editRecurringSchedule(
          schedule.id,
          draft: ScheduleDraft(
            title: schedule.title,
            notes: schedule.notes,
            window: window,
            taskId: schedule.taskId,
          ),
          scope: scope,
        );
      } else {
        await widget.repository.rescheduleSchedule(schedule.id, window);
      }
    } catch (_) {
      if (!mounted) return;
      _showError(context, '新的时间没有保存，请稍后重试。');
    }
  }

  Future<void> _confirmDelete(Schedule schedule) async {
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
      _showError(context, '安排没有删除，请稍后重试。');
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
    required this.highlighted,
    required this.timeLabel,
    required this.taskLabel,
    required this.onToggleCompletion,
    required this.onEdit,
    required this.onReschedule,
    required this.onDelete,
  });

  final Schedule schedule;

  /// 通知点开的那一条：只用边框强调，不改变任何数据或专注状态。
  final bool highlighted;
  final String timeLabel;
  final String? taskLabel;
  final ValueChanged<bool> onToggleCompletion;
  final VoidCallback onEdit;
  final VoidCallback onReschedule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      selected: highlighted,
      child: Card(
        key: ValueKey(
          highlighted
              ? 'schedule-highlight-${schedule.id}'
              : 'schedule-card-${schedule.id}',
        ),
        margin: const EdgeInsets.only(top: 8),
        shape: highlighted
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: theme.colorScheme.primary, width: 2),
              )
            : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
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
              if (schedule.isRecurring)
                Text(
                  '重复安排',
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
      ),
    );
  }
}

/// 订阅身份：同一个仓储、同一个月窗口才复用同一条订阅。
class _ScheduleSource {
  const _ScheduleSource({
    required this.repository,
    required this.month,
    required this.from,
    required this.to,
  });

  final ScheduleRepository repository;
  final DateTime month;
  final DateTime from;
  final DateTime to;

  bool matches(_ScheduleSource other) =>
      identical(repository, other.repository) &&
      month == other.month &&
      from == other.from &&
      to == other.to;
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
