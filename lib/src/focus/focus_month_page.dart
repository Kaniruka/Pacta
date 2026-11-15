import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../profile/account_time_zone.dart';
import 'focus_models.dart';
import 'focus_repository.dart';
import 'focus_time_zones.dart';

/// Read-only month view of accepted effective focus time.
///
/// The page is a projection of [FocusRepository.watchMonthMetrics]: it never
/// writes focus data, never creates sessions, and never talks to Plan
/// arrangements. A day without accepted time is a neutral empty day, not a
/// failure, a broken chain or an unmet daily target.
///
/// [accountTimeZoneIds] emits the account profile's display time zone (nullable
/// before a value exists); the page applies [AccountTimeZones.effectiveId], so
/// there is no device-time-zone branch here. The callback is invoked once per
/// subscription, which lets the caller build it from a provider without creating
/// a new stream on every rebuild.
///
/// The visible month is captured when a projection query starts. It advances
/// only through an explicit month switch, "回到本月" or a re-subscription
/// (account zone, repository, retry); a midnight rollover alone never relabels
/// numbers that are already on screen.
class FocusMonthPage extends StatefulWidget {
  const FocusMonthPage({
    super.key,
    required this.repository,
    required this.accountTimeZoneIds,
    this.initialMonth,
    this.now,
  });

  /// Accepted-effective-time projection. Read-only by contract.
  final FocusRepository repository;

  /// Account display time zone source; emits the profile value or null.
  final Stream<String?> Function() accountTimeZoneIds;

  /// Visible month when opened; defaults to the account zone's current month.
  final DateTime? initialMonth;

  /// Clock used for "this month"; injectable for fixtures and tests.
  final DateTime Function()? now;

  @override
  State<FocusMonthPage> createState() => _FocusMonthPageState();
}

class _FocusMonthPageState extends State<FocusMonthPage> {
  StreamSubscription<String?>? _zoneSubscription;
  StreamSubscription<FocusMonthMetrics>? _monthSubscription;
  String _timeZoneId = AccountTimeZones.fallbackId;
  DateTime? _monthOverride;

  /// The month on screen and the month of the running query.
  ///
  /// It is captured when the query starts (not recomputed in every build), so a
  /// midnight rollover can never relabel one month's numbers with the next
  /// month's name. It advances only through an explicit month change, "回到本月"
  /// or a re-subscription (account zone / repository / retry).
  late DateTime _month;
  int? _selectedDay;
  FocusMonthMetrics? _metrics;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  /// Whether the current account-zone source has produced a value (or closed).
  /// While it is false — a replacement source that has not emitted yet, or a
  /// failed source — the page must not query the month with the previous
  /// account's zone, so month switching stays disabled until it resolves.
  bool _zoneResolved = false;
  int _zoneSourceGeneration = 0;

  DateTime get _now => (widget.now ?? DateTime.now)();

  DateTime get _currentMonthInAccountZone {
    final location = FocusTimeZones.location(_timeZoneId);
    final local = timezone.TZDateTime.from(_now.toUtc(), location);
    return DateTime.utc(local.year, local.month);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth;
    _monthOverride = initial == null
        ? null
        : DateTime.utc(initial.year, initial.month);
    _month = _monthOverride ?? _currentMonthInAccountZone;
    _subscribeAccountTimeZone(notify: false);
  }

  @override
  void didUpdateWidget(FocusMonthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.accountTimeZoneIds != oldWidget.accountTimeZoneIds) {
      // The replacement source has not resolved yet: drop the old projection and
      // wait for its first value instead of querying with the previous account's
      // zone. The pending restart also covers a simultaneous repository change.
      _subscribeAccountTimeZone();
    } else if (widget.repository != oldWidget.repository) {
      // A different account owns different data: drop the old projection now and
      // rebuild from the new repository instead of showing the previous user.
      _restartMonth(notify: false);
    }
  }

  @override
  void dispose() {
    _cancel(_zoneSubscription);
    _cancel(_monthSubscription);
    super.dispose();
  }

  /// Replaces the account-zone source.
  ///
  /// The projection is invalidated first; the new month query starts only once
  /// the replacement source resolves (first value or done). A synchronous throw
  /// from the callback and an asynchronous stream error both land in the same
  /// recoverable error card instead of leaving the page loading forever.
  void _subscribeAccountTimeZone({bool notify = true}) {
    _cancel(_zoneSubscription);
    _zoneSubscription = null;
    _zoneResolved = false;
    _invalidateProjection(notify: notify);

    final source = ++_zoneSourceGeneration;
    var resolved = false;

    bool stale() => source != _zoneSourceGeneration;

    void fail(Object error) {
      if (stale()) return;
      _cancel(_zoneSubscription);
      _zoneSubscription = null;
      _zoneResolved = false;
      _generation++;
      _cancel(_monthSubscription);
      _monthSubscription = null;
      _applyError(error);
    }

    void start() {
      if (stale() || resolved) return;
      resolved = true;
      _zoneResolved = true;
      // A source that closes without a value carries no account zone: use the
      // explicit account fallback instead of inheriting the previous source's
      // zone.
      _timeZoneId = AccountTimeZones.fallbackId;
      _restartMonth(notify: mounted);
    }

    final Stream<String?> ids;
    try {
      ids = widget.accountTimeZoneIds();
    } catch (error) {
      fail(error);
      return;
    }
    try {
      _zoneSubscription = ids.listen(
        (value) {
          if (stale()) return;
          final zoneId = AccountTimeZones.effectiveId(value);
          final first = !resolved;
          resolved = true;
          _zoneResolved = true;
          if (!first && zoneId == _timeZoneId) return;
          _timeZoneId = zoneId;
          if (!first) _selectedDay = null;
          _restartMonth(notify: mounted);
        },
        onError: (Object error, StackTrace stackTrace) => fail(error),
        onDone: start,
      );
    } catch (error) {
      fail(error);
    }
  }

  /// Re-reads both required sources: the account zone (its first value gates the
  /// query) and, once it resolves, the month projection.
  void _retry() {
    _subscribeAccountTimeZone();
  }

  void _invalidateProjection({required bool notify}) {
    _generation++;
    _cancel(_monthSubscription);
    _monthSubscription = null;

    void reset() {
      _loading = true;
      _error = null;
      _metrics = null;
    }

    if (notify && mounted) {
      setState(reset);
    } else {
      reset();
    }
  }

  void _applyError(Object error) {
    void apply() {
      _loading = false;
      _error = error;
      _metrics = null;
      _selectedDay = null;
    }

    // Errors can arrive after the initial build (an asynchronous stream error
    // from the initial non-notifying subscription), so always schedule the
    // rebuild that shows the recoverable error card.
    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _restartMonth({bool notify = true}) {
    final generation = ++_generation;
    _cancel(_monthSubscription);
    _monthSubscription = null;

    final month = _monthOverride ?? _currentMonthInAccountZone;
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

    try {
      _monthSubscription = widget.repository
          .watchMonthMetrics(timeZoneId: _timeZoneId, month: month)
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
      if (generation == _generation) {
        _applyError(error);
      }
    }
  }

  void _showMonth(DateTime month) {
    // No query while the account zone is unknown or failed: the month buttons
    // are disabled in that state, and this guard keeps a programmatic call from
    // re-reading the previous account's zone.
    if (!_zoneResolved) return;
    _monthOverride = DateTime.utc(month.year, month.month);
    _selectedDay = null;
    _restartMonth();
  }

  void _showCurrentMonth() {
    if (!_zoneResolved) return;
    _monthOverride = null;
    _selectedDay = null;
    _restartMonth();
  }

  void _selectDay(int day) {
    setState(() {
      _selectedDay = _selectedDay == day ? null : day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final month = _month;
    final isCurrentMonth = month == _currentMonthInAccountZone;
    return Scaffold(
      appBar: AppBar(
        title: const Text('专注月历'),
        actions: [
          if (_zoneResolved && !isCurrentMonth)
            TextButton(onPressed: _showCurrentMonth, child: const Text('回到本月')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _MonthHeader(
                  month: month,
                  onPrevious: _zoneResolved
                      ? () => _showMonth(
                          DateTime.utc(month.year, month.month - 1),
                        )
                      : null,
                  onNext: _zoneResolved
                      ? () => _showMonth(
                          DateTime.utc(month.year, month.month + 1),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                ..._buildMonthBody(context, month),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMonthBody(BuildContext context, DateTime month) {
    if (_loading) {
      return const [
        SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final error = _error;
    if (error != null) {
      return [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('专注月历加载失败。')),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _retry, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ];
    }
    final metrics = _metrics;
    if (metrics == null) {
      return const [
        SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final secondsByDay = <int, int>{
      for (final day in metrics.days) day.date.day: day.activeSeconds,
    };
    return [
      const _WeekdayHeader(),
      const SizedBox(height: 4),
      ..._buildGrid(context, month, secondsByDay),
      const SizedBox(height: 16),
      _MonthSummaryCard(
        month: month,
        metrics: metrics,
        selectedDay: _selectedDay,
        onClearSelection: () => _selectDay(_selectedDay ?? 0),
      ),
    ];
  }

  List<Widget> _buildGrid(
    BuildContext context,
    DateTime month,
    Map<int, int> secondsByDay,
  ) {
    final firstWeekday = DateTime.utc(month.year, month.month).weekday;
    final dayCount = DateTime.utc(month.year, month.month + 1, 0).day;
    final leading = firstWeekday - DateTime.monday;
    final cellCount = leading + dayCount;
    final rows = (cellCount + 6) ~/ 7;
    return [
      for (var row = 0; row < rows; row++)
        Row(
          children: [
            for (var column = 0; column < 7; column++)
              Expanded(
                child: _buildDayCell(
                  context,
                  month: month,
                  day: row * 7 + column - leading + 1,
                  secondsByDay: secondsByDay,
                  dayCount: dayCount,
                ),
              ),
          ],
        ),
    ];
  }

  Widget _buildDayCell(
    BuildContext context, {
    required DateTime month,
    required int day,
    required Map<int, int> secondsByDay,
    required int dayCount,
  }) {
    if (day < 1 || day > dayCount) return const SizedBox(height: 48);
    final seconds = secondsByDay[day] ?? 0;
    final hasActivity = seconds > 0;
    final selected = _selectedDay == day;
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Semantics(
      label:
          '${month.month}月$day日，'
          '${hasActivity ? '有效投入 ${_formatDuration(seconds)}' : '无有效投入'}',
      container: true,
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('focus-month-day-$day'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectDay(day),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: foreground),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                width: 6,
                child: hasActivity
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.primary,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${month.year}年${month.month}月',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: '下个月',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      children: [
        for (final label in _labels)
          Expanded(
            child: Text(label, textAlign: TextAlign.center, style: style),
          ),
      ],
    );
  }
}

class _MonthSummaryCard extends StatelessWidget {
  const _MonthSummaryCard({
    required this.month,
    required this.metrics,
    required this.selectedDay,
    required this.onClearSelection,
  });

  final DateTime month;
  final FocusMonthMetrics metrics;
  final int? selectedDay;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final day = selectedDay;
    final daySeconds = day == null
        ? 0
        : metrics.activeSecondsOn(DateTime.utc(month.year, month.month, day));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (day == null) ...[
              Text('本月有效投入', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (metrics.hasActivity) ...[
                Text(
                  _formatDuration(metrics.totalActiveSeconds),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text('有投入的天数 ${metrics.activeDayCount} 天'),
              ] else
                const Text('本月暂无有效投入。'),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${month.month}月$day日',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: onClearSelection,
                    child: const Text('查看整月'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                daySeconds > 0
                    ? '有效投入 ${_formatDuration(daySeconds)}'
                    : '这一天没有有效投入。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '空白只表示当天没有有效投入。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  return [
    if (hours > 0) '$hours 小时',
    if (minutes > 0) '$minutes 分钟',
    if (remainingSeconds > 0 || seconds == 0) '$remainingSeconds 秒',
  ].join(' ');
}

void _cancel(StreamSubscription<Object?>? subscription) {
  if (subscription != null) unawaited(subscription.cancel());
}
