import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../focus/effective_duration_text.dart';
import '../focus/focus_models.dart';
import '../focus/focus_repository.dart';
import '../focus/focus_time_zones.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_repository.dart';
import '../plan/plan_calendar_view.dart' show scheduleTimeLabel, schedulesOnDay;
import '../profile/account_time_zone.dart';
import '../schedules/schedule_models.dart';
import '../schedules/schedule_repository.dart';
import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../theme/pacta_calendar_colors.dart';
import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_calendar_day_cell.dart';
import '../ui/pacta_check_circle.dart';
import '../ui/pacta_focus_heat_legend.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_hold_action_reorder.dart';
import '../ui/pacta_horizontal_pager.dart';
import 'board_pinned_goal_actions.dart';
import 'national_focus_summary_card.dart';

/// 看板「专注与国策」融合卡片。
///
/// 一张卡同时回答四件事，全部来自既有的只读投影（不新增表、不改
/// Cloud Snapshot）：
/// 1. 顶槽：随日历选中日切换的国策状态（[NationalFocusRepository.watchTreeCards]
///    + 周期检查点结算），点击进入国策树；
/// 2. 单栏时顶槽是一枚紧凑分段胶囊：国策状态 ⇄ 置顶目标 (N)。置顶目标
///    不再作为独立超高区块压在月历上方，热力月历因此仍高居首屏；
/// 3. 专注热力月历（[FocusRepository.watchMonthMetrics]，5 档绿色），
///    可切月、点选任意日；
/// 4. 日期详情：当天有效专注时长 + 只读安排。今天取实时状态、未来日期明确
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
    this.checkpointTimeZoneId,
    required this.now,
    required this.onOpenNationalFocus,
    required this.onRetryProjection,
    this.scheduleRepository,
    this.accountFailed = false,
    this.initialMonth,
    this.pinnedGoals = const <Goal>[],
    this.pinnedGoalsFailed = false,
    this.goalRepository,
    this.onOpenPlan,
  });

  final FocusRepository focusRepository;
  final NationalFocusRepository nationalFocusRepository;

  /// 账号显示时区；null 表示账号资料尚未解析完成（门禁，不发查询）。
  final String? displayTimeZoneId;

  /// 国策检查点时区（未设账号时区时回落 Asia/Shanghai）；用于对照设备时间。
  final String? checkpointTimeZoneId;

  /// 与计划日历、看板热力月历共用的注入时钟。
  final DateTime Function() now;

  final VoidCallback onOpenNationalFocus;

  /// 只读重试：由看板重新订阅整块投影，不写任何数据。
  final VoidCallback onRetryProjection;

  /// 账号资料读取失败：时区按统一兜底值显示，卡片必须说明来源。
  final bool accountFailed;

  /// 打开时先展示的月份（测试与分享入口用）。
  final DateTime? initialMonth;

  /// 只读安排来源；为 null 时卡片不订阅、也不渲染安排区块。
  final ScheduleRepository? scheduleRepository;

  /// 单栏顶槽里的置顶目标（宽屏双栏由看板左栏自己渲染，这里传空表）。
  ///
  /// 有置顶目标（或 [pinnedGoalsFailed]）时顶槽才出现「国策状态 ⇄ 置顶目标」
  /// 胶囊；一个都没有时整条切换栏与置顶视图都不占空间。
  final List<Goal> pinnedGoals;

  /// 目标列表读取失败：切换栏只写「置顶目标」，置顶视图必须给出可见失败。
  final bool pinnedGoalsFailed;

  /// 置顶目标的写入来源：按住拖动排序与长按取消置顶都走它。
  ///
  /// 为 null 时置顶视图只读列出前两条，不提供重排/操作入口。
  final TaskRepository? goalRepository;

  /// 置顶视图底部的「查看全部 N 个 →」出口（计划页）。
  final VoidCallback? onOpenPlan;

  @override
  State<FocusNationalCalendarCard> createState() =>
      _FocusNationalCalendarCardState();
}

/// 顶槽页签：动态选中日国策状态 / 置顶目标。
enum _TopSlotTab { status, pinned }

class _FocusNationalCalendarCardState extends State<FocusNationalCalendarCard> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  /// 单栏顶槽最多展示的置顶目标条数（Q8 #3）：再多的目标只经「查看全部」
  /// 去计划页看，热力月历因此不会被置顶列表压到首屏之外。
  static const _pinnedSlotLimit = 2;

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

  /// 顶槽当前页签与「用户已手动选过」标记。
  ///
  /// 默认页签只在用户尚未手动切换前按 Q8 #1 规则决定；一旦用户点过胶囊，
  /// 流刷新与月份重读都不再改写他的选择。点选日历日期时若正停在置顶目标
  /// 页签，会自动切回国策状态（Q8 #2），那也算一次用户选择。
  _TopSlotTab _topSlotTab = _TopSlotTab.status;
  bool _topSlotTabChosen = false;

  /// 顶槽横向滑动累计位移：只有明确横拖超过 [_topSlotSwipeThreshold] 才切页，
  /// 原地长按与垂直拖拽排序都不会误触。
  double _topSlotDragDistance = 0;
  static const _topSlotSwipeThreshold = 24.0;

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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 顶槽与日期详情共用的选中日：月份还没解析时按账号时区里的今天兜底，
  /// 两处永远指向同一天，不会一个说 12 日、另一个说今天。
  DateTime get _selectedDate {
    final month = _month ?? _currentMonthInZone;
    final day = _selectedDay ?? _defaultDayFor(month, _metrics);
    return DateTime.utc(month.year, month.month, day);
  }

  /// 顶槽是否需要切换栏：有置顶目标，或目标列表读取失败。
  ///
  /// 两者都没有时整条胶囊消失，顶槽直接就是动态国策状态，零多余 chrome。
  bool get _showTopSlotSwitch =>
      widget.pinnedGoals.isNotEmpty || widget.pinnedGoalsFailed;

  /// Q8 #1 默认页签：国策树有节点、今日待确认数为 0 且目标读取正常时，
  /// 优先展示置顶目标；其余情况默认国策状态。
  _TopSlotTab get _defaultTopSlotTab {
    if (!_showTopSlotSwitch) return _TopSlotTab.status;
    final cards = _cards;
    if (_cardsFailed || cards == null) return _TopSlotTab.status;
    final counts = NationalFocusStatusCounts.fromCards(cards);
    if (counts.isEmpty || counts.pendingCount != 0) return _TopSlotTab.status;
    return _TopSlotTab.pinned;
  }

  /// 用户尚未手动切换前，跟随最新数据重算默认页签。
  void _syncTopSlotDefault() {
    if (_topSlotTabChosen) return;
    _topSlotTab = _defaultTopSlotTab;
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
    if (_pinnedGoalsChanged(oldWidget.pinnedGoals, widget.pinnedGoals) ||
        oldWidget.pinnedGoalsFailed != widget.pinnedGoalsFailed) {
      // 置顶目标迟到或增减：用户没手动选过时重算默认页签；一个置顶目标
      // 都不剩时顶槽必须回到国策状态，不能停在空的置顶视图上。
      _apply(() {
        if (!_showTopSlotSwitch) {
          _topSlotTab = _TopSlotTab.status;
        } else {
          _syncTopSlotDefault();
        }
      });
    }
  }

  bool _pinnedGoalsChanged(List<Goal> previous, List<Goal> next) {
    if (identical(previous, next)) return false;
    if (previous.length != next.length) return true;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].id != next[index].id) return true;
    }
    return false;
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
        _syncTopSlotDefault();
      }),
      onError: (Object error, StackTrace stackTrace) => _apply(() {
        _cards = null;
        _cardsFailed = true;
        _syncTopSlotDefault();
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

  /// 失败记录按账号显示时区归到自然日；检查点时刻本身按账号时区当地 04:00
  /// 结算，设备时区只决定这一行的归类与显示。
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
          // 按钮，也不再提供独立的「完整月历」二级页。
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
                    size: PactaIconSizes.sm,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('暂时不能确认账号时区，以下按 UTC 显示。')),
                ],
              ),
            ),
          // 顶槽：动态选中日国策状态；单栏有置顶目标时先出现一枚紧凑胶囊
          // 切换栏。置顶目标因此不再压出一个独立超高区块，热力月历仍在上
          // 面一屏可见。左右 16dp，与标题同一版心。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildTopSlot(context),
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
  // 顶槽：动态选中日国策状态 ⇄ 置顶目标
  // ---------------------------------------------------------------------

  Widget _buildTopSlot(BuildContext context) {
    final showSwitch = _showTopSlotSwitch;
    final content = showSwitch && _topSlotTab == _TopSlotTab.pinned
        ? _buildPinnedSlot(context)
        : _buildSelectedDayNationalFocus(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSwitch) ...[
          _buildTopSlotSwitch(context),
          const SizedBox(height: 8),
        ],
        if (showSwitch)
          // 顶槽左右滑动：国策状态 ⇄ 置顶目标。高度随内容自适应，不用固定
          // 高度的 PageView 裁切置顶卡；横向识别器只在超过 touch slop 的
          // 明确横拖时才赢竞技场，长按菜单与垂直拖拽排序保持原样。
          PactaHorizontalPagerScope(
            enabled: showSwitch,
            pageCount: 2,
            currentPage: _topSlotTab == _TopSlotTab.status ? 0 : 1,
            onStepPage: _stepTopSlot,
            child: GestureDetector(
              key: const ValueKey('board-top-slot-swipe'),
              // 透明边距也要能直接横拖：deferToChild 会让卡片外的留白
              // 变成死区，桌面鼠标因此只能从内容上起手。
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _topSlotDragDistance = 0,
              onHorizontalDragUpdate: (details) =>
                  _topSlotDragDistance += details.delta.dx,
              onHorizontalDragCancel: () => _topSlotDragDistance = 0,
              onHorizontalDragEnd: _endTopSlotSwipe,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: content,
                ),
              ),
            ),
          )
        else
          content,
      ],
    );
  }

  /// 左滑去置顶目标、右滑回国策状态；与胶囊点击走同一条 [_selectTopSlot]。
  void _endTopSlotSwipe(DragEndDetails details) {
    final distance = _topSlotDragDistance;
    _topSlotDragDistance = 0;
    if (!_showTopSlotSwitch) return;
    if (distance <= -_topSlotSwipeThreshold) {
      _selectTopSlot(_TopSlotTab.pinned);
    } else if (distance >= _topSlotSwipeThreshold) {
      _selectTopSlot(_TopSlotTab.status);
    }
  }

  /// 紧凑分段胶囊：两枚标签始终并排，极端字号下由 Wrap 换行而不是溢出。
  Widget _buildTopSlotSwitch(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _TopSlotPill(
          key: const ValueKey('board-top-slot-status'),
          label: '国策状态',
          selected: _topSlotTab == _TopSlotTab.status,
          onTap: () => _selectTopSlot(_TopSlotTab.status),
        ),
        _TopSlotPill(
          key: const ValueKey('board-top-slot-pinned'),
          // 目标列表读取失败时不写条数：那是「不知道」，不是 0 个。
          label: widget.pinnedGoalsFailed
              ? '置顶目标'
              : '置顶目标 (${widget.pinnedGoals.length})',
          selected: _topSlotTab == _TopSlotTab.pinned,
          onTap: () => _selectTopSlot(_TopSlotTab.pinned),
        ),
      ],
    );
  }

  void _selectTopSlot(_TopSlotTab tab) {
    setState(() {
      _topSlotTabChosen = true;
      _topSlotTab = tab;
    });
  }

  /// 滚轮/快捷键的一步切换：只在两枚胶囊同时存在时按页序钳位，不循环。
  void _stepTopSlot(int step) {
    if (!_showTopSlotSwitch) return;
    final int current = _topSlotTab == _TopSlotTab.status ? 0 : 1;
    final int next = (current + step).clamp(0, 1);
    if (next == current) return;
    _selectTopSlot(next == 0 ? _TopSlotTab.status : _TopSlotTab.pinned);
  }

  /// 动态选中日国策状态：今天取实时计数，历史只认真实失败记录，未来明确
  /// 未到结算；三者绝不互相推断。
  Widget _buildSelectedDayNationalFocus(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = _selectedDate;
    final today = _todayInZone;
    final isToday = _sameDay(date, today);
    final isFuture = date.isAfter(today);
    final failures = _failuresOn(date);
    final cards = _cards;
    final counts = cards == null
        ? null
        : NationalFocusStatusCounts.fromCards(cards);
    final title = isToday
        ? '今日国策状态'
        : isFuture
        ? '${date.month}月${date.day}日国策状态'
        : '${date.month}月${date.day}日国策记录';
    // 胶囊必须与真实状态一致：失败/加载/成功、未知/失败、未到结算各自
    // 可读，绝不在读取失败时继续亮绿色成功色。
    final Widget badge;
    if (isToday) {
      if (_cardsFailed) {
        badge = const PactaStatusBadge(
          label: '读取失败',
          tone: PactaStatusBadgeTone.warning,
        );
      } else if (cards == null) {
        badge = const PactaStatusBadge(
          label: '读取中',
          tone: PactaStatusBadgeTone.neutral,
        );
      } else {
        badge = const PactaStatusBadge(
          label: '实时状态',
          tone: PactaStatusBadgeTone.success,
        );
      }
    } else if (isFuture) {
      badge = const PactaStatusBadge(
        label: '未到结算',
        tone: PactaStatusBadgeTone.neutral,
      );
    } else if (failures.isEmpty) {
      badge = const PactaStatusBadge(
        label: '未知',
        tone: PactaStatusBadgeTone.neutral,
      );
    } else {
      final extinguishing = failures.any(
        (failure) =>
            failure.cause == NationalFocusFailureCause.activeExtinguish,
      );
      badge = PactaStatusBadge(
        label: '有失败记录',
        tone: extinguishing
            ? PactaStatusBadgeTone.error
            : PactaStatusBadgeTone.warning,
      );
    }

    final checkpointComparison = AccountTimeZones.formatCheckpointComparison(
      accountTimeZoneId: widget.checkpointTimeZoneId ?? _effectiveZoneId,
      referenceUtc: _now,
    );
    final showCheckpointDiff = checkpointComparison.contains('当前设备时间');

    final body = <Widget>[];
    if (isToday) {
      if (_cardsFailed) {
        body.add(Text('国策状态暂不可用。', style: theme.textTheme.bodyMedium));
      } else if (counts == null) {
        body.add(Text('正在读取国策状态…', style: theme.textTheme.bodyMedium));
      } else if (counts.isEmpty) {
        body.add(Text('国策树尚无节点', style: theme.textTheme.bodyMedium));
      } else {
        body.add(
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
        );
      }
      if (showCheckpointDiff && !_cardsFailed && counts != null) {
        body.add(const SizedBox(height: 6));
        body.add(
          Text(
            checkpointComparison,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      }
      // 今天真落有检查点失败时补失败行（最多 3 条 + 溢出提示），保留追溯
      // 能力；否则一行都不加，实时计数只在上面出现一次。
      if (failures.isNotEmpty) {
        body.add(const SizedBox(height: 8));
        for (final line in _failureLines(failures)) {
          body.add(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
          );
        }
      }
    } else if (isFuture) {
      body.add(Text('未来日期还没有结算数据，不预先推断结果。', style: theme.textTheme.bodyMedium));
      if (showCheckpointDiff) {
        body.add(const SizedBox(height: 6));
        body.add(
          Text(
            checkpointComparison,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      }
    } else {
      // 历史日期：没有真实失败记录就只能是「未知」，失败流读不到时也说
      // 读不到——绝不把「无记录」推断成「全部确认」。
      body.add(
        Text(
          _failuresFailed
              ? '暂时不能读取国策失败记录，历史日期一律标记为未知。'
              : failures.isEmpty
              ? '历史日期只显示实际有数据支持的记录；没有记录时明确标记为未知。'
              : '按账号时区归到这一天；$checkpointComparison。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
      if (!_failuresFailed && failures.isEmpty && showCheckpointDiff) {
        body.add(const SizedBox(height: 4));
        body.add(
          Text(
            checkpointComparison,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      }
      for (final line in _failureLines(failures)) {
        body.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(line, style: theme.textTheme.bodySmall),
          ),
        );
      }
    }

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
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                  badge,
                ],
              ),
              const SizedBox(height: 10),
              ...body,
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

  /// 顶槽置顶视图：最多两条，保留按住拖动排序与长按操作菜单。
  Widget _buildPinnedSlot(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goals = widget.pinnedGoals;
    final visible = goals.take(_pinnedSlotLimit).toList(growable: false);
    final repository = widget.goalRepository;
    final children = <Widget>[
      if (widget.pinnedGoalsFailed)
        Row(
          children: [
            Icon(
              Icons.error_outline,
              size: PactaIconSizes.compact,
              color: scheme.error,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('暂时不能读取目标列表。')),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('board-top-slot-pinned-retry'),
              onPressed: widget.onRetryProjection,
              child: const Text('重试'),
            ),
          ],
        )
      else if (visible.isEmpty)
        Text(
          '还没有置顶目标。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        )
      else if (repository == null)
        // 只读多置顶：CardThemeData 外边距为零，两张卡直接贴在一起会变成
        // 一整块；用与可拖拽列表同一档 8dp 间距分开。
        for (final (index, goal) in visible.indexed) ...[
          if (index > 0) const SizedBox(height: PactaSpacing.sm),
          _pinnedGoalTile(context, goal),
        ]
      else
        PactaHoldReorderList(
          itemCount: visible.length,
          itemSpacing: 8,
          proxyBorderRadius: PactaSpacing.cardRadius,
          onReorder: _reorderPinned,
          onHoldMenu: (index) => _openPinnedActions(context, visible[index]),
          itemBuilder: (context, index) =>
              _pinnedGoalTile(context, visible[index]),
        ),
      if (goals.length > _pinnedSlotLimit)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('board-top-slot-pinned-all'),
            onPressed: widget.onOpenPlan,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Text('查看全部 ${goals.length} 个 →'),
          ),
        ),
    ];
    // 可拖拽列表会为每一项（含 index == 0）额外加 8dp 顶部透明间隔，
    // 目的是让拖拽代理与卡片等高、浮起时不超框。顶槽因此把上内边距收到
    // 2dp：首卡视觉顶距 = 2 + 8 = 10dp，与末卡底距 10dp、左右 10dp 严格
    // 对称。失败 / 空 / 只读三种分支没有这层 8dp 间隔，继续用 10dp。
    final usesReorderList =
        !widget.pinnedGoalsFailed && visible.isNotEmpty && repository != null;
    return Material(
      key: const ValueKey('board-top-slot-pinned-surface'),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: usesReorderList
            ? const EdgeInsets.fromLTRB(10, 2, 10, 10)
            : const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _pinnedGoalTile(BuildContext context, Goal goal) {
    return Card(
      key: ValueKey('board-pinned-goal-${goal.id}'),
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.push_pin, size: PactaIconSizes.compact),
        title: Text(goal.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          goal.nextTask == null ? '暂无任务' : '下一项：${goal.nextTask!.title}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// 只重排可见的前两条，但写回的是全部置顶 ID：原第 3..N 个按原序接在
  /// 后面，绝不因为顶槽只显示两条就把后面的置顶目标挤掉。
  void _reorderPinned(int oldIndex, int newIndex) {
    final repository = widget.goalRepository;
    if (repository == null) return;
    final ids = [for (final goal in widget.pinnedGoals) goal.id];
    final head = ids.take(_pinnedSlotLimit).toList();
    if (head.length < 2 || oldIndex < 0 || oldIndex >= head.length) return;
    final moved = head.removeAt(oldIndex);
    final target = newIndex < 0
        ? 0
        : newIndex > head.length
        ? head.length
        : newIndex;
    head.insert(target, moved);
    unawaited(
      savePinnedGoalOrder(
        context: context,
        repository: repository,
        orderedGoalIds: <String>[...head, ...ids.skip(head.length)],
      ),
    );
  }

  void _openPinnedActions(BuildContext context, Goal goal) {
    final repository = widget.goalRepository;
    if (repository == null) return;
    openPinnedGoalActions(
      context,
      goal: goal,
      repository: repository,
      onOpenPlan: widget.onOpenPlan,
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
                    icon: const Icon(
                      Icons.chevron_left,
                      size: PactaIconSizes.md,
                    ),
                  ),
                  // 完整年月，与 PlanCalendarView 的「2026年11月」一致；
                  // 窄屏或 2 倍字号下由外层 Wrap 换行、文本自身省略，绝不
                  // 把卡片撑破。
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
                    icon: const Icon(
                      Icons.chevron_right,
                      size: PactaIconSizes.md,
                    ),
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
                Icon(
                  Icons.error_outline,
                  size: PactaIconSizes.compact,
                  color: scheme.error,
                ),
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
    final heatLevel = PactaCalendarColors.heatLevelForSeconds(seconds);
    final (background, foreground) = colors.heatColorsForLevel(heatLevel);
    final date = DateTime.utc(month.year, month.month, day);
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final failures = _failuresOn(date);
    // 第四层语义：统一指示轨只表示“这天有安排 / 这天有国策失败”，与热力
    // 底色、选中/今天描边、'今' 微字互不遮挡。右上角不再放任何孤立标记，
    // 全部收进日期数字下方的 8dp 轨道。
    final scheduleDot = hasSchedules
        ? ExcludeSemantics(
            child: Container(
              key: ValueKey('board-focus-schedule-dot-$day'),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: foreground.withValues(alpha: 0.72),
              ),
            ),
          )
        : null;
    final failureIndicator = failures.isEmpty
        ? null
        : _failureIndicator(
            context,
            day: day,
            colors: colors,
            heatLevel: heatLevel,
          );
    final bottomDot = scheduleDot == null && failureIndicator == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?scheduleDot,
              if (scheduleDot != null && failureIndicator != null)
                const SizedBox(width: 3),
              ?failureIndicator,
            ],
          );
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
            // Q8 #2：正停在「置顶目标」页签时点任意日期格，立即切回
            // 「国策状态」，让用户马上看到所选日期的结论；这也算一次手动
            // 选择，后续流刷新不再改写页签。
            onTap: () => setState(() {
              _selectedDay = day;
              if (_topSlotTab == _TopSlotTab.pinned) {
                _topSlotTabChosen = true;
                _topSlotTab = _TopSlotTab.status;
              }
            }),
            // 热力月历的固定形态：'今' 居中置顶、底部恒定 8dp 指示轨，
            // 右上角不再挂任何标记。
            centerTodayLabel: true,
            reserveBottomSlot: true,
            topRightMarker: null,
            bottomDot: bottomDot,
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

  /// 国策失败的底部细短杠：横向 10dp × 3dp 圆角，与安排微点同轨并排。
  ///
  /// 深绿底（heat ≥ 2）上细杠几乎与底色同亮度，因此外包一层同系半透托底
  /// 把标记与底色隔开。托底只用填充色、**绝不设 border**：日格的
  /// “只允许一层等大外框”守卫依赖装饰层不带描边，加边框会立刻变成双层框。
  Widget _failureIndicator(
    BuildContext context, {
    required int day,
    required PactaCalendarColors colors,
    required int heatLevel,
  }) {
    final bar = ExcludeSemantics(
      child: Container(
        key: ValueKey('board-focus-failure-dot-$day'),
        width: 10,
        height: 3,
        decoration: BoxDecoration(
          color: colors.failureDotColor,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
    if (heatLevel < 2) return bar;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final haloColor =
        (theme.brightness == Brightness.dark
                ? scheme.surfaceContainerLow
                : scheme.surfaceContainerLowest)
            .withValues(alpha: 0.92);
    return Container(
      key: ValueKey('board-focus-failure-halo-$day'),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: haloColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: bar,
    );
  }

  // ---------------------------------------------------------------------
  // 日期详情
  // ---------------------------------------------------------------------

  Widget _buildDayDetail(BuildContext context, DateTime? month) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = _metrics;
    // 完整月历二级页已删除：日期详情只回答「这一天的专注时长与安排」，
    // 国策结论统一由卡片顶部的动态选中日状态卡给出，这里不再复述。
    // 失败必须先于加载判定：_restartMonth 出错时把 _metrics 置空且
    // _loading=false，若这里先看 metrics 就会把失败永久说成「正在读取」。
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDayDetailHeader(context),
          const SizedBox(height: PactaSpacing.xs),
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: PactaIconSizes.compact,
                color: scheme.error,
              ),
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
          _buildDayDetailHeader(context),
          const SizedBox(height: PactaSpacing.xs),
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
    // 点亮/待确认/熄灭、失败行、历史未知与未来未结算全部只在顶部动态
    // 状态卡里出现一次；日期详情不再重复「国策记录」区块。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 「日期详情」用谷歌蓝分组标题，日期作为右侧副文本；标题与日期
        // 各自换行，窄屏 2.0x 字号下也不会溢出或截断。
        _buildDayDetailHeader(
          context,
          dateLabel: '${month.month} 月 $day 日${isToday ? ' · 今日' : ''}',
        ),
        // 有效专注单独装进柔和 tonal 容器：标签与时长各自成行，不再和
        // 日期副文本、安排标题挤成一团裸文字。
        _buildDurationPanel(context, seconds: daySeconds),
        ..._buildScheduleSection(context, date: date, isToday: isToday),
      ],
    );
  }

  /// 日期详情分区标题：谷歌蓝 [PactaSectionHeader] + 右侧日期副文本。
  ///
  /// 有日期时标题由 [PactaSectionHeader] 的 Expanded 承接剩余宽度，日期最多
  /// 两行软换行：320dp + 2.0x 字号下日期先换行而不是被省略号截断，标题本身
  /// 也不会把整行撑破。加载与失败分支没有可确认的日期，因此只渲染标题。
  Widget _buildDayDetailHeader(BuildContext context, {String? dateLabel}) {
    final theme = Theme.of(context);
    final label = dateLabel;
    return PactaSectionHeader(
      title: '日期详情',
      // 外层已经给了 16dp 版心与段前距：这里左侧归零，标题与下方两块
      // tonal 容器共用同一条左缘；下方 8dp 是标题到内容的呼吸。
      padding: const EdgeInsets.fromLTRB(0, 0, 0, PactaSpacing.sm),
      trailing: label == null
          ? null
          : Text(
              label,
              maxLines: 2,
              softWrap: true,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  /// 柔和 tonal 容器：「有效专注」与「安排」两块内容共用同一种底与圆角。
  ///
  /// 底色固定取 `surfaceContainerLow`，12dp 圆角配 12dp 内边距：亮色下是
  /// 浅蓝灰、暗色下沉于卡片表面，两块内容因此各自成组，而不是一段长文本。
  /// 颜色不收参数：token 只在这里出现一次，调用方不会各写一套底色。
  Widget _tonalPanel({Key? key, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.all(PactaSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(PactaSpacing.md),
      ),
      child: child,
    );
  }

  /// 有效专注：标签在上、时长在下，整块放进 tonal 容器。
  Widget _buildDurationPanel(BuildContext context, {required int seconds}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _tonalPanel(
      key: const ValueKey('board-focus-day-duration-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '有效专注',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: PactaSpacing.xxs),
          Text(
            formatEffectiveDuration(seconds),
            key: const ValueKey('board-focus-day-duration'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: PactaFonts.semibold,
              color: seconds > 0 ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
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
      const SizedBox(height: PactaSpacing.md),
      // 安排整块放进独立的柔和 tonal 容器：标题在上、列表/空态在下，
      // 中间固定 8dp 呼吸，加载与失败分支也各占一行，绝不与上方挤成一段。
      _tonalPanel(
        key: const ValueKey('board-focus-schedule-panel'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _schedulesLoading || failed
                  ? scheduleTitle
                  : '$scheduleTitle · ${daySchedules.length} 项',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: PactaSpacing.sm),
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
                  Icon(
                    Icons.error_outline,
                    size: PactaIconSizes.sm,
                    color: scheme.error,
                  ),
                  const SizedBox(width: PactaSpacing.sm),
                  const Expanded(child: Text('暂时不能读取安排。')),
                  const SizedBox(width: PactaSpacing.sm),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: PactaSpacing.xxs,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        // 严格只读：compact 指示不接受 onChanged，不可勾选。
                        PactaCheckCircle(
                          value: schedule.isCompleted,
                          onChanged: null,
                          compact: true,
                          semanticLabel: schedule.isCompleted ? '已完成' : '未完成',
                        ),
                        const SizedBox(width: PactaSpacing.sm),
                        Expanded(
                          child: Text(
                            schedule.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: schedule.isCompleted
                                ? theme.textTheme.bodyMedium?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: PactaSpacing.sm),
                        // 时刻最多占整行 60%：2.0x 字号下先让时刻收窄并省略，
                        // 首行永远留给标题，整行不会横向溢出。
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.6,
                          ),
                          child: Text(
                            scheduleTimeLabel(schedule, zoneId),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    ];
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

  String _failureCardName(NationalFocusFailure failure) {
    for (final snapshot in failure.treeSnapshot) {
      if (snapshot.id == failure.cardId) return snapshot.name;
    }
    // 卡片已被移除时快照里没有名字：不把内部 UUID 当成用户可见名称。
    return '已移除的国策卡';
  }
}

/// 分段胶囊的一枚标签：选中态用主色容器，未选中态保持中性表面。
///
/// 胶囊是顶槽的页签，不是主操作：高度 34dp、横向 12dp 内边距，选中不只
/// 靠颜色表达——[Semantics] 同时给出 selected 状态。
class _TopSlotPill extends StatelessWidget {
  const _TopSlotPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? PactaFonts.semibold : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
