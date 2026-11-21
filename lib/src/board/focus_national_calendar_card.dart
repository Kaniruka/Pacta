import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/effective_duration_text.dart';
import '../focus/focus_models.dart';
import '../focus/focus_month_page.dart' show PactaFocusHeatLegend;
import '../focus/focus_repository.dart';
import '../focus/focus_time_zones.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import '../plan/plan_calendar_view.dart' show scheduleTimeLabel, schedulesOnDay;
import '../profile/account_time_zone.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repository.dart';
import '../theme/pacta_calendar_colors.dart';
import '../theme/pacta_fonts.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_calendar_day_cell.dart';
import '../ui/pacta_check_circle.dart';
import '../ui/pacta_grouped_list.dart';
import 'national_focus_summary_card.dart';

/// 看板「专注与国策」融合卡片。
///
/// 一张卡同时回答三件事，全部来自既有的只读投影（不新增表、不改
/// Cloud Snapshot）：
/// 1. 今日国策实时状态（[NationalFocusRepository.watchTreeCards] + 周期
///    检查点结算），点击进入国策树；
/// 2. 专注热力月历（[FocusRepository.watchMonthMetrics]，5 档绿色），
///    可切月、点选任意日；
/// 3. 日期详情：当天有效专注时长 + 国策记录。今天取实时状态、未来日期明确
///    标为“未到结算”、历史日期只认真实的失败记录，没有记录时严格显示
///    “未知”，绝不把未知推断成“全部确认/已点亮”。
///
/// 账号时区守卫：[displayTimeZoneId] 为 null 表示资料还没解析出账号时区，
/// 此时不发起任何月投影查询、也不画兜底 UTC 的数字，只显示就地加载态。
///
/// 只读安排融合：传入 [scheduleRepository] 时，卡片按同一账号时区边界订阅
/// 展示月份的安排，在日格底部画安排小点、在日期详情下方列出当天安排。它
/// 只读——不勾选、不新增、不改时间；管理动作仍只在计划页。
class FocusNationalCalendarCard extends StatefulWidget {
  const FocusNationalCalendarCard({
    super.key,
    required this.focusRepository,
    required this.nationalFocusRepository,
    required this.displayTimeZoneId,
    required this.now,
    required this.onOpenNationalFocus,
    required this.onOpenFocusMonth,
    required this.onRetryProjection,
    this.scheduleRepository,
    this.accountFailed = false,
    this.initialMonth,
  });

  final FocusRepository focusRepository;
  final NationalFocusRepository nationalFocusRepository;

  /// 账号显示时区；null 表示账号资料尚未解析完成（门禁，不发查询）。
  final String? displayTimeZoneId;

  /// 与计划日历、专注月历共用的注入时钟。
  final DateTime Function() now;

  final VoidCallback onOpenNationalFocus;
  final VoidCallback onOpenFocusMonth;

  /// 只读重试：由看板重新订阅整块投影，不写任何数据。
  final VoidCallback onRetryProjection;

  /// 账号资料读取失败：时区按统一兜底值显示，卡片必须说明来源。
  final bool accountFailed;

  /// 打开时先展示的月份（测试与分享入口用）。
  final DateTime? initialMonth;

  /// 只读安排来源；为 null 时卡片不订阅、也不渲染安排区块。
  final ScheduleRepository? scheduleRepository;

  @override
  State<FocusNationalCalendarCard> createState() =>
      _FocusNationalCalendarCardState();
}

class _FocusNationalCalendarCardState extends State<FocusNationalCalendarCard> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  StreamSubscription<FocusMonthMetrics>? _monthSubscription;
  StreamSubscription<List<NationalFocusCard>>? _cardsSubscription;
  StreamSubscription<List<NationalFocusFailure>>? _failuresSubscription;
  StreamSubscription<List<Schedule>>? _scheduleSubscription;
  Timer? _checkpointTimer;

  DateTime? _monthOverride;

  /// 当前展示的月份（UTC 日期值，只取年月）与正在查询的月份是同一个；
  /// 账号时区未解析时为 null。
  DateTime? _month;
  int? _selectedDay;
  FocusMonthMetrics? _metrics;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  List<NationalFocusCard>? _cards;
  bool _cardsFailed = false;
  List<NationalFocusFailure> _failures = const [];
  bool _failuresFailed = false;
  bool _hasBuilt = false;

  /// 只读安排：仓储、账号时区或月份一变就整份丢弃并重新订阅；代次保证
  /// 上一账号/上一时区/上一月的迟到事件不会回显到屏上。
  List<Schedule> _schedules = const [];
  Object? _schedulesError;
  bool _schedulesLoading = true;
  int _scheduleGeneration = 0;

  String? get _effectiveZoneId {
    final zoneId = widget.displayTimeZoneId;
    return zoneId == null ? null : AccountTimeZones.effectiveId(zoneId);
  }

  DateTime get _now => widget.now();

  DateTime _dayInZone(DateTime instant) {
    final zoneId = _effectiveZoneId;
    if (zoneId == null) {
      final local = instant.toLocal();
      return DateTime.utc(local.year, local.month, local.day);
    }
    final local = timezone.TZDateTime.from(
      instant.toUtc(),
      FocusTimeZones.location(zoneId),
    );
    return DateTime.utc(local.year, local.month, local.day);
  }

  DateTime get _todayInZone => _dayInZone(_now);

  DateTime get _currentMonthInZone {
    final today = _todayInZone;
    return DateTime.utc(today.year, today.month);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth;
    _monthOverride = initial == null
        ? null
        : DateTime.utc(initial.year, initial.month);
    _subscribeCards();
    _subscribeFailures();
    _settleDueCheckpoints();
    _checkpointTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshCheckpoint(),
    );
    _restartMonth(notify: false);
  }

  @override
  void didUpdateWidget(FocusNationalCalendarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nationalFocusRepository != widget.nationalFocusRepository) {
      // 换仓储等于换账号：旧仓储的点亮/失败数字属于上一份数据，先清零再
      // 订阅，避免新流首帧之前把旧账号的统计回显给用户。
      _apply(() {
        _cards = null;
        _failures = const [];
        _cardsFailed = false;
        _failuresFailed = false;
      });
      _subscribeCards();
      _subscribeFailures();
      _settleDueCheckpoints();
    }
    if (oldWidget.scheduleRepository != widget.scheduleRepository) {
      // 换安排仓储等于换账号：旧行属于上一份数据，先清空再按同一月份订阅。
      _restartSchedules();
    }
    if (oldWidget.focusRepository != widget.focusRepository ||
        oldWidget.displayTimeZoneId != widget.displayTimeZoneId) {
      // 换仓储或换时区：旧投影属于上一账号/上一时区，立即丢弃，
      // 选中日也重新按新月份默认。
      _selectedDay = null;
      _restartMonth();
    }
  }

  @override
  void dispose() {
    _checkpointTimer?.cancel();
    _cancel(_monthSubscription);
    _cancel(_cardsSubscription);
    _cancel(_failuresSubscription);
    _cancel(_scheduleSubscription);
    super.dispose();
  }

  void _cancel(StreamSubscription<Object?>? subscription) {
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// 首帧之前的同步事件直接改字段，避免在挂载途中 setState。
  void _apply(VoidCallback change) {
    if (!mounted) return;
    if (_hasBuilt) {
      setState(change);
    } else {
      change();
    }
  }

  void _subscribeCards() {
    _cancel(_cardsSubscription);
    _cardsSubscription = widget.nationalFocusRepository.watchTreeCards().listen(
      (cards) => _apply(() {
        _cards = cards;
        _cardsFailed = false;
      }),
      onError: (Object error, StackTrace stackTrace) => _apply(() {
        _cards = null;
        _cardsFailed = true;
      }),
    );
  }

  void _subscribeFailures() {
    _cancel(_failuresSubscription);
    _failuresSubscription = widget.nationalFocusRepository
        .watchFailures()
        .listen(
          (failures) => _apply(() {
            _failures = failures;
            _failuresFailed = false;
          }),
          onError: (Object error, StackTrace stackTrace) => _apply(() {
            _failures = const [];
            _failuresFailed = true;
          }),
        );
  }

  void _settleDueCheckpoints() {
    unawaited(
      widget.nationalFocusRepository.settleDueCheckpoints().catchError(
        (Object _) {},
      ),
    );
  }

  void _refreshCheckpoint() {
    _settleDueCheckpoints();
    if (mounted) setState(() {});
  }

  /// 丢弃旧月投影并（在账号时区已解析时）重新查询。
  void _restartMonth({bool notify = true}) {
    final generation = ++_generation;
    _cancel(_monthSubscription);
    _monthSubscription = null;

    final zoneId = _effectiveZoneId;
    final month = zoneId == null
        ? null
        : (_monthOverride ?? _currentMonthInZone);
    final monthChanged = month != _month;
    _month = month;

    void reset() {
      _loading = true;
      _error = null;
      _metrics = null;
      if (monthChanged) _selectedDay = null;
    }

    if (notify && mounted) {
      setState(reset);
    } else {
      reset();
    }

    // 安排与月投影同属“展示月份 + 账号时区”的一份订阅：这里一起换源。
    _restartSchedules();

    // 账号时区未知：不查询、也不画兜底时区的数字。
    if (zoneId == null || month == null) return;

    try {
      _monthSubscription = widget.focusRepository
          .watchMonthMetrics(timeZoneId: zoneId, month: month)
          .listen(
            (metrics) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _metrics = metrics;
                _loading = false;
                _error = null;
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _metrics = null;
                _loading = false;
                _error = error;
              });
            },
          );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _metrics = null;
        _loading = false;
        _error = error;
      });
    }
  }

  /// 订阅展示月份的只读安排。
  ///
  /// 账号时区解析前不查询；仓储、时区或月份一变就先清空旧行并置加载态，
  /// 因此上一账号/上一月的安排标题与格底小点绝不会在首帧闪一下。
  void _restartSchedules() {
    final generation = ++_scheduleGeneration;
    _cancel(_scheduleSubscription);
    _scheduleSubscription = null;
    _apply(() {
      _schedules = const <Schedule>[];
      _schedulesError = null;
      _schedulesLoading = true;
    });

    final repository = widget.scheduleRepository;
    final zoneId = _effectiveZoneId;
    final month = _month;
    if (repository == null || zoneId == null || month == null) return;

    // 与 PlanCalendarView._sourceFor 完全一致的账号时区边界：
    // 月初往前一天、下月初往后两天，覆盖时区偏移与全天日程的 UTC 午夜边界。
    final location = FocusTimeZones.location(zoneId);
    final from = timezone.TZDateTime(
      location,
      month.year,
      month.month,
      1,
    ).toUtc().subtract(const Duration(days: 1));
    final to = timezone.TZDateTime(
      location,
      month.year,
      month.month + 1,
      1,
    ).toUtc().add(const Duration(days: 2));
    try {
      _scheduleSubscription = repository
          .watchSchedules(from: from, to: to)
          .listen(
            (rows) {
              if (!mounted || generation != _scheduleGeneration) return;
              setState(() {
                _schedules = rows;
                _schedulesError = null;
                _schedulesLoading = false;
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || generation != _scheduleGeneration) return;
              setState(() {
                // 失败不是空内容：清掉旧行，把错误留给可见的重试入口。
                _schedules = const <Schedule>[];
                _schedulesError = error;
                _schedulesLoading = false;
              });
            },
          );
    } catch (error) {
      // 不可用的仓储会在调用时就抛：同样给可见失败，而不是“没有安排”。
      if (!mounted || generation != _scheduleGeneration) return;
      setState(() {
        _schedules = const <Schedule>[];
        _schedulesError = error;
        _schedulesLoading = false;
      });
    }
  }

  void _showMonth(int year, int month) {
    _monthOverride = DateTime.utc(year, month);
    _selectedDay = null;
    _restartMonth();
  }

  /// 失败记录按账号显示时区归到自然日；检查点时刻本身仍按北京时间规则结算。
  Map<DateTime, List<NationalFocusFailure>> get _failuresByDay {
    final grouped = <DateTime, List<NationalFocusFailure>>{};
    for (final failure in _failures) {
      final day = _dayInZone(failure.checkpointAt);
      grouped.putIfAbsent(day, () => <NationalFocusFailure>[]).add(failure);
    }
    return grouped;
  }

  List<NationalFocusFailure> _failuresOn(DateTime day) =>
      _failuresByDay[DateTime.utc(day.year, day.month, day.day)] ??
      const <NationalFocusFailure>[];

  /// 默认选中日：本月今天 → 本月最后一个有记录的日子 → 第 1 日。
  int _defaultDayFor(DateTime month, FocusMonthMetrics? metrics) {
    final today = _todayInZone;
    if (today.year == month.year && today.month == month.month) {
      return today.day;
    }
    final days = metrics?.days ?? const <FocusActivityDay>[];
    for (final day in days.reversed) {
      if (day.activeSeconds > 0 && day.date.month == month.month) {
        return day.date.day;
      }
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    _hasBuilt = true;
    final theme = Theme.of(context);
    final surfaces = PactaSurfaces.of(context);
    final month = _month;
    return Card(
      key: const ValueKey('board-focus-national-card'),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 年月只在热力月历的切换器里出现一次：卡片头不再重复一枚月份
          // 按钮，进入完整月历的唯一入口是「日期详情」的「完整月历 →」。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text('专注与国策', style: theme.textTheme.titleMedium),
          ),
          if (widget.accountFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('暂时不能确认账号时区，以下按 UTC 显示。')),
                ],
              ),
            ),
          // 今日国策状态：左右 16dp，与标题同一版心。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildTodayNationalFocus(context),
          ),
          const SizedBox(height: 16),
          // 热力月历：标题行 16dp、七列网格只留 8dp。360dp 手机下卡片
          // 内宽 = 360 - 32(list) - 16 = 312dp，每列 44.5dp，第 7 列
          // 100% 落在卡片内，没有内部横向滚动条。
          _buildHeatCalendar(context, month),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const PactaFocusHeatLegend(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, thickness: 1, color: surfaces.hairline),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildDayDetail(context, month),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 今日国策实时状态
  // ---------------------------------------------------------------------

  Widget _buildTodayNationalFocus(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cards = _cards;
    final counts = cards == null
        ? null
        : NationalFocusStatusCounts.fromCards(cards);
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('board-today-national-focus'),
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onOpenNationalFocus,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('今日国策状态', style: theme.textTheme.titleSmall),
                  ),
                  // 胶囊必须与真实状态一致：失败/加载/成功三态各自可读，绝不
                  // 在读取失败时继续亮绿色成功色。
                  if (_cardsFailed)
                    const PactaStatusBadge(
                      label: '读取失败',
                      tone: PactaStatusBadgeTone.warning,
                    )
                  else if (_cards == null)
                    const PactaStatusBadge(
                      label: '读取中',
                      tone: PactaStatusBadgeTone.neutral,
                    )
                  else
                    const PactaStatusBadge(
                      label: '实时状态',
                      tone: PactaStatusBadgeTone.success,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_cardsFailed)
                Text('国策状态暂不可用。', style: theme.textTheme.bodyMedium)
              else if (counts == null)
                Text('正在读取国策状态…', style: theme.textTheme.bodyMedium)
              else if (counts.isEmpty)
                Text('国策树尚无节点', style: theme.textTheme.bodyMedium)
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    PactaStatusBadge(
                      label: '点亮 ${counts.litCount}',
                      tone: PactaStatusBadgeTone.success,
                    ),
                    PactaStatusBadge(
                      label: '待确认 ${counts.pendingCount}',
                      tone: PactaStatusBadgeTone.warning,
                    ),
                    PactaStatusBadge(
                      label: '熄灭 ${counts.extinguishedCount}',
                      tone: PactaStatusBadgeTone.neutral,
                    ),
                  ],
                ),
              if (counts != null && counts.allPendingReview)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('国策状态均待核对。'),
                ),
              if (counts != null && counts.pendingReview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${counts.pendingReview.length} 个节点待核对，未计入上方汇总。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '点击查看国策树及具体节点状态 →',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 专注热力月历
  // ---------------------------------------------------------------------

  Widget _buildHeatCalendar(BuildContext context, DateTime? month) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text('专注热力月历', style: theme.textTheme.titleSmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('board-focus-previous-month'),
                    tooltip: '上个月',
                    onPressed: month == null
                        ? null
                        : () => _showMonth(month.year, month.month - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  // 完整年月，与 FocusMonthPage / PlanCalendarView 的
                  // 「2026年11月」一致；窄屏或 2 倍字号下由外层 Wrap 换行、
                  // 文本自身省略，绝不把卡片撑破。
                  Flexible(
                    child: Text(
                      month == null ? '月份待确认' : '${month.year}年${month.month}月',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('board-focus-next-month'),
                    tooltip: '下个月',
                    onPressed: month == null
                        ? null
                        : () => _showMonth(month.year, month.month + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (month == null || _loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 20, color: scheme.error),
                const SizedBox(width: 10),
                const Expanded(child: Text('暂时不能读取专注投影。')),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('board-focus-heat-retry'),
                  onPressed: widget.onRetryProjection,
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (_metrics case final metrics?)
          _buildGrid(context, month, metrics),
      ],
    );
  }

  Widget _buildGrid(
    BuildContext context,
    DateTime month,
    FocusMonthMetrics metrics,
  ) {
    final firstWeekday = DateTime.utc(month.year, month.month).weekday;
    final dayCount = DateTime.utc(month.year, month.month + 1, 0).day;
    final leading = firstWeekday - DateTime.monday;
    final cellCount = leading + dayCount;
    final rowCount = (cellCount + 6) ~/ 7;
    final secondsByDay = <int, int>{
      for (final day in metrics.days) day.date.day: day.activeSeconds,
    };
    final today = _todayInZone;
    final selectedDay = _selectedDay ?? _defaultDayFor(month, metrics);
    // 安排点只在拿到确定结果时画：加载中或失败都不猜“有没有安排”。
    final zoneId = _effectiveZoneId;
    final scheduledDays = <int>{};
    if (widget.scheduleRepository != null &&
        zoneId != null &&
        !_schedulesLoading &&
        _schedulesError == null) {
      for (var day = 1; day <= dayCount; day++) {
        final date = DateTime.utc(month.year, month.month, day);
        if (_schedulesOn(date, zoneId).isNotEmpty) scheduledDays.add(day);
      }
    }
    return Padding(
      // 网格左右只留 8dp：360dp 手机下卡片内宽 312dp，七列每列 44.5dp，
      // 全部落在卡片内且没有内部横向滚动条。
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < rowCount; row++)
            Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _buildDayCell(
                      context,
                      month: month,
                      day: row * 7 + column - leading + 1,
                      dayCount: dayCount,
                      secondsByDay: secondsByDay,
                      today: today,
                      selectedDay: selectedDay,
                      hasSchedules: scheduledDays.contains(
                        row * 7 + column - leading + 1,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context, {
    required DateTime month,
    required int day,
    required int dayCount,
    required Map<int, int> secondsByDay,
    required DateTime today,
    required int selectedDay,
    required bool hasSchedules,
  }) {
    if (day < 1 || day > dayCount) return const SizedBox(height: 48);
    final colors = PactaCalendarColors.of(context);
    final seconds = secondsByDay[day] ?? 0;
    final (background, foreground) = colors.heatColorsForLevel(
      PactaCalendarColors.heatLevelForSeconds(seconds),
    );
    final date = DateTime.utc(month.year, month.month, day);
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final failures = _failuresOn(date);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 312dp 版心七等分后每列 44.5dp：≥46dp 才让出 2dp 视觉间隙，
        // 更窄时收到 1dp，命中区仍完整落在卡片内。
        final gap = constraints.maxWidth >= 46 ? 2.0 : 1.0;
        return Padding(
          padding: EdgeInsets.all(gap),
          child: PactaCalendarDayBox(
            cellKey: ValueKey('board-focus-day-$day'),
            dayNumber: '$day',
            selected: selectedDay == day,
            today: isToday,
            backgroundColor: background,
            foregroundColor: foreground,
            minHeight: 48,
            borderRadius: 12,
            onTap: () => setState(() => _selectedDay = day),
            topRightMarker: failures.isEmpty
                ? null
                : ExcludeSemantics(
                    child: Container(
                      key: ValueKey('board-focus-failure-dot-$day'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.failureDotColor,
                      ),
                    ),
                  ),
            // 第四层语义：底部小点只表示“这天有安排”，与热力底色、
            // 选中/今天描边、今角标、国策失败红点互不遮挡。
            bottomDot: hasSchedules
                ? ExcludeSemantics(
                    child: Container(
                      key: ValueKey('board-focus-schedule-dot-$day'),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: foreground,
                      ),
                    ),
                  )
                : null,
            semanticLabel:
                '${month.month}月$day日，'
                '${seconds > 0 ? '有效专注 ${formatEffectiveDuration(seconds)}' : '无有效专注'}'
                '${failures.isEmpty ? '' : '，有 ${failures.length} 条国策失败记录'}'
                '${hasSchedules ? '，有安排' : ''}'
                '${isToday ? '，今天' : ''}',
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // 日期详情
  // ---------------------------------------------------------------------

  Widget _buildDayDetail(BuildContext context, DateTime? month) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = _metrics;
    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text('日期详情', style: theme.textTheme.titleSmall),
        TextButton(
          key: const ValueKey('board-focus-open-month'),
          onPressed: month == null ? null : widget.onOpenFocusMonth,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('完整月历 →'),
        ),
      ],
    );
    // 失败必须先于加载判定：_restartMonth 出错时把 _metrics 置空且
    // _loading=false，若这里先看 metrics 就会把失败永久说成「正在读取」。
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: scheme.error),
              const SizedBox(width: 10),
              const Expanded(child: Text('暂时不能读取这一天的专注记录。')),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('board-focus-day-detail-retry'),
                onPressed: widget.onRetryProjection,
                child: const Text('重试'),
              ),
            ],
          ),
        ],
      );
    }
    if (month == null || _loading || metrics == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 4),
          Text(
            '正在读取专注投影…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final day = _selectedDay ?? _defaultDayFor(month, metrics);
    final date = DateTime.utc(month.year, month.month, day);
    final today = _todayInZone;
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final daySeconds = metrics.activeSecondsOn(date);
    final failures = _failuresOn(date);
    // 今天：实时汇总只在卡片顶部的「今日国策状态」里出现一次，这里不再
    // 复述点亮/待确认/熄灭；只有真的落有检查点失败时才补一行失败记录，
    // 保留追溯能力而零重复。未来日与历史日仍由国策记录区块给结论。
    final nationalFocusSection = isToday
        ? <Widget>[
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('今日失败记录', style: theme.textTheme.bodyMedium),
              for (final line in _failureLines(failures))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(line, style: theme.textTheme.bodySmall),
                ),
            ],
          ]
        : _recordSection(context, _nationalFocusRecordFor(date, today));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Text(
          '${month.month} 月 $day 日${isToday ? ' · 今日' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '有效专注',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          formatEffectiveDuration(daySeconds),
          key: const ValueKey('board-focus-day-duration'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: PactaFonts.semibold,
            color: daySeconds > 0 ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        ...nationalFocusSection,
        ..._buildScheduleSection(context, date: date, isToday: isToday),
      ],
    );
  }

  /// 「国策记录」结论区块：未来日明确未结算，历史日只认真实失败记录。
  List<Widget> _recordSection(
    BuildContext context,
    _DayNationalFocusRecord record,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return [
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: Text('国策记录', style: theme.textTheme.bodyMedium)),
          PactaStatusBadge(
            key: const ValueKey('board-focus-day-record'),
            label: record.label,
            tone: record.tone,
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        record.note,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      for (final line in record.details)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(line, style: theme.textTheme.bodySmall),
        ),
    ];
  }

  /// 紧凑只读「安排」区块：只列标题、完成状态与账号时区里的实际时刻。
  ///
  /// 没有传入仓储、或账号时区还没解析时不渲染任何东西——不给“暂时没有”
  /// 这种无法站住的结论。管理动作（勾选、增删改）仍只在计划页。
  List<Widget> _buildScheduleSection(
    BuildContext context, {
    required DateTime date,
    required bool isToday,
  }) {
    final repository = widget.scheduleRepository;
    final zoneId = _effectiveZoneId;
    if (repository == null || zoneId == null) return const [];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scheduleTitle = isToday ? '今日安排' : '当日安排';
    final failed = _schedulesError != null;
    final daySchedules = _schedulesLoading || failed
        ? const <Schedule>[]
        : _schedulesOn(date, zoneId);
    return [
      const SizedBox(height: 12),
      Text(
        _schedulesLoading || failed
            ? scheduleTitle
            : '$scheduleTitle · ${daySchedules.length} 项',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 4),
      if (_schedulesLoading)
        Text(
          '正在读取安排…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        )
      else if (failed)
        Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('暂时不能读取安排。')),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('board-focus-schedule-retry'),
              onPressed: _restartSchedules,
              child: const Text('重试'),
            ),
          ],
        )
      else if (daySchedules.isEmpty)
        Text(
          isToday ? '今天还没有安排。' : '当天还没有安排。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        )
      else
        for (final schedule in daySchedules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                // 严格只读：compact 指示不接受 onChanged，不可勾选。
                PactaCheckCircle(
                  value: schedule.isCompleted,
                  onChanged: null,
                  compact: true,
                  semanticLabel: schedule.isCompleted ? '已完成' : '未完成',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    schedule.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: schedule.isCompleted
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  scheduleTimeLabel(schedule, zoneId),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
    ];
  }

  /// 选中日的国策记录：未来明确未结算、历史只认真实失败记录。
  ///
  /// 今天不走这里：今日汇总已在卡片顶部展示，重复一次只会制造两个数字。
  _DayNationalFocusRecord _nationalFocusRecordFor(
    DateTime date,
    DateTime today,
  ) {
    if (date.isAfter(today)) {
      return const _DayNationalFocusRecord(
        label: '未到结算',
        tone: PactaStatusBadgeTone.neutral,
        note: '未来日期还没有结算数据，不预先推断结果。',
      );
    }
    return _historyRecord(date);
  }

  /// 某一天（卡片内部用 UTC 日期值表示）在这份只读安排里的行。
  ///
  /// `schedulesOnDay` 按本地墙钟日期比较自然日，这里只做表示法转换，
  /// 取到的日子与日格上的日期完全一致。
  List<Schedule> _schedulesOn(DateTime date, String zoneId) => schedulesOnDay(
    _schedules,
    DateTime(date.year, date.month, date.day),
    zoneId,
  );

  /// 失败节点明细：最多三行，超出时给出总数，不隐藏发生过的事。
  List<String> _failureLines(List<NationalFocusFailure> failures) => [
    for (final failure in failures.take(3))
      '${_failureCardName(failure)} · ${failure.cause.label}',
    if (failures.length > 3) '等 ${failures.length} 个节点',
  ];

  _DayNationalFocusRecord _historyRecord(DateTime date) {
    final failures = _failuresOn(date);
    if (failures.isEmpty) {
      return _DayNationalFocusRecord(
        label: '未知',
        tone: PactaStatusBadgeTone.neutral,
        note: _failuresFailed
            ? '暂时不能读取国策失败记录，历史日期一律标记为未知。'
            : '历史日期只显示实际有数据支持的记录；没有记录时明确标记为未知。',
      );
    }
    final extinguishing = failures.any(
      (failure) => failure.cause == NationalFocusFailureCause.activeExtinguish,
    );
    final details = <String>[
      for (final failure in failures.take(3))
        '${_failureCardName(failure)} · ${failure.cause.label}',
      if (failures.length > 3) '等 ${failures.length} 个节点',
    ];
    return _DayNationalFocusRecord(
      label: '有失败记录',
      tone: extinguishing
          ? PactaStatusBadgeTone.error
          : PactaStatusBadgeTone.warning,
      note: '按账号显示时区归到这一天；检查点仍固定北京时间 04:00。',
      details: details,
    );
  }

  String _failureCardName(NationalFocusFailure failure) {
    for (final snapshot in failure.treeSnapshot) {
      if (snapshot.id == failure.cardId) return snapshot.name;
    }
    return failure.cardId;
  }
}

/// 一天的国策记录结论：徽标文案、语气、诚实说明与可选的节点明细。
@immutable
class _DayNationalFocusRecord {
  const _DayNationalFocusRecord({
    required this.label,
    required this.tone,
    required this.note,
    this.details = const [],
  });

  final String label;
  final PactaStatusBadgeTone tone;
  final String note;
  final List<String> details;
}
