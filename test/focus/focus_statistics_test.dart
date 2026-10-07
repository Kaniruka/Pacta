import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_statistics.dart';

void main() {
  final startedAt = DateTime.utc(2026, 10, 7, 8);

  test('按专注链分别汇总已接受的完成与失败会话有效时长', () {
    final statistics = focusStatisticsByMode([
      _session(
        id: 'elite-completed',
        mode: FocusChainMode.elite,
        status: FocusSessionStatus.completed,
        effectiveSeconds: 900,
        intervals: [
          _interval(startedAt, seconds: 300),
          _interval(startedAt.add(const Duration(minutes: 10)), seconds: 420),
        ],
      ),
      _session(
        id: 'elite-failed',
        mode: FocusChainMode.elite,
        status: FocusSessionStatus.failed,
        effectiveSeconds: 180,
        intervals: [_interval(startedAt, seconds: 180)],
      ),
      _session(
        id: 'regular-completed',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.completed,
        effectiveSeconds: 600,
        intervals: [_interval(startedAt, seconds: 600)],
      ),
    ]);

    expect(statistics[FocusChainMode.elite]!.totalDurationSeconds, 900);
    expect(statistics[FocusChainMode.elite]!.acceptedSessionCount, 2);
    expect(statistics[FocusChainMode.elite]!.averageDurationSeconds, 450);
    expect(statistics[FocusChainMode.regular]!.totalDurationSeconds, 600);
    expect(statistics[FocusChainMode.regular]!.acceptedSessionCount, 1);
    expect(statistics[FocusChainMode.regular]!.averageDurationSeconds, 600);
  });

  test('排除未结算、待核对和重复会话，零有效时长仍计入平均次数', () {
    final statistics = focusStatisticsByMode([
      _session(
        id: 'completed-with-time',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.completed,
        effectiveSeconds: 600,
        intervals: [_interval(startedAt, seconds: 600)],
      ),
      _session(
        id: 'failed-clock-review',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.failed,
        effectiveSeconds: 1200,
        intervals: [
          _interval(
            startedAt,
            seconds: 1200,
            clockReviewStatus: FocusClockReviewStatus.deferred,
          ),
        ],
      ),
      _session(
        id: 'failed-no-reliable-time',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.failed,
        effectiveSeconds: 1200,
        intervals: [
          _interval(startedAt, seconds: 1200, excludeFromFocusProgress: true),
        ],
      ),
      _session(
        id: 'pending',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.completed,
        effectiveSeconds: 900,
        disposition: FocusRecordDisposition.pendingReview,
        intervals: [_interval(startedAt, seconds: 900)],
      ),
      _session(
        id: 'duplicate',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.failed,
        effectiveSeconds: 900,
        disposition: FocusRecordDisposition.duplicate,
        intervals: [_interval(startedAt, seconds: 900)],
      ),
      _session(
        id: 'active',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.active,
        effectiveSeconds: 300,
        intervals: [_interval(startedAt, seconds: 300)],
      ),
      _session(
        id: 'paused',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.paused,
        effectiveSeconds: 300,
        intervals: [_interval(startedAt, seconds: 300)],
      ),
    ]);

    expect(statistics[FocusChainMode.regular]!.totalDurationSeconds, 600);
    expect(statistics[FocusChainMode.regular]!.acceptedSessionCount, 3);
    expect(statistics[FocusChainMode.regular]!.averageDurationSeconds, 200);
  });

  test('没有区间数据的旧会话回退到有效时长汇总，空链统计为零', () {
    final statistics = focusStatisticsByMode([
      _session(
        id: 'legacy',
        mode: FocusChainMode.elite,
        status: FocusSessionStatus.failed,
        effectiveSeconds: 75,
      ),
      _session(
        id: 'empty-regular',
        mode: FocusChainMode.regular,
        status: FocusSessionStatus.completed,
        effectiveSeconds: 90,
        intervals: const [],
      ),
    ]);

    expect(statistics[FocusChainMode.elite]!.totalDurationSeconds, 75);
    expect(statistics[FocusChainMode.elite]!.averageDurationSeconds, 75);
    expect(statistics[FocusChainMode.regular]!.totalDurationSeconds, 90);
    expect(statistics[FocusChainMode.regular]!.acceptedSessionCount, 1);
  });

  test('空输入仍返回两条专注链的零值统计', () {
    final statistics = focusStatisticsByMode(const []);

    expect(statistics.keys, containsAll(FocusChainMode.values));
    for (final mode in FocusChainMode.values) {
      expect(statistics[mode]!.totalDurationSeconds, 0);
      expect(statistics[mode]!.acceptedSessionCount, 0);
      expect(statistics[mode]!.averageDurationSeconds, 0);
    }
    expect(() => statistics.clear(), throwsUnsupportedError);
  });
}

FocusSession _session({
  required String id,
  required FocusChainMode mode,
  required FocusSessionStatus status,
  required int effectiveSeconds,
  FocusRecordDisposition disposition = FocusRecordDisposition.accepted,
  List<FocusTimeInterval> intervals = const [],
}) {
  final startedAt = DateTime.utc(2026, 10, 7, 8);
  final endsAt = startedAt.add(const Duration(hours: 1));
  return FocusSession(
    id: id,
    taskId: 'task-$id',
    mode: mode,
    durationSeconds: 3600,
    startedAt: startedAt,
    endsAt: endsAt,
    status: status,
    completedAt:
        status == FocusSessionStatus.completed ||
            status == FocusSessionStatus.failed
        ? endsAt
        : null,
    effectiveSeconds: effectiveSeconds,
    effectiveIntervals: intervals,
    reviewDisposition: disposition,
  );
}

FocusTimeInterval _interval(
  DateTime startedAt, {
  required int seconds,
  bool excludeFromFocusProgress = false,
  FocusClockReviewStatus clockReviewStatus = FocusClockReviewStatus.none,
}) => FocusTimeInterval(
  startedAt: startedAt,
  endedAt: startedAt.add(Duration(seconds: seconds)),
  measuredDurationSeconds: seconds,
  excludeFromFocusProgress: excludeFromFocusProgress,
  clockReviewStatus: clockReviewStatus,
);
