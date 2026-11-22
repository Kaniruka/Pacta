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
  group('预约链实际准备时长', () {
    final startedAt = DateTime.utc(2026, 11, 15, 9);

    test('到期完成按实际经过时间累计，累计与平均同源', () {
      final statistics = appointmentPreparationStatistics([
        _appointment(id: 'due', startedAt: startedAt, settledMinutes: 15),
        _appointment(
          id: 'due-later',
          startedAt: startedAt.add(const Duration(hours: 1)),
          settledMinutes: 15,
        ),
      ]);

      expect(statistics.totalDurationSeconds, 1800);
      expect(statistics.acceptedSessionCount, 2);
      expect(statistics.averageDurationSeconds, 900);
    });

    test('提前进入专注只计到结算时刻的实际耗时', () {
      final appointment = _appointment(
        id: 'early',
        startedAt: startedAt,
        settledMinutes: 6,
      );

      expect(appointmentActualPreparationSeconds(appointment), 360);
      final statistics = appointmentPreparationStatistics([appointment]);
      expect(statistics.totalDurationSeconds, 360);
      expect(statistics.acceptedSessionCount, 1);
      expect(statistics.averageDurationSeconds, 360);
    });

    test('主动取消同样按实际经过时间计入累计', () {
      final appointment = _appointment(
        id: 'cancelled',
        startedAt: startedAt,
        settledMinutes: 4,
        status: AppointmentPreparationStatus.failed,
      );

      expect(appointmentActualPreparationSeconds(appointment), 240);
      final statistics = appointmentPreparationStatistics([appointment]);
      expect(statistics.totalDurationSeconds, 240);
      expect(statistics.acceptedSessionCount, 1, reason: '失败预约同样占一次平均');
    });

    test('晚结算被钳制在约好的准备时长内', () {
      final appointment = _appointment(
        id: 'late',
        startedAt: startedAt,
        settledMinutes: 40,
      );

      expect(appointment.effectivePreparationSeconds, 900);
      expect(
        appointmentActualPreparationSeconds(appointment),
        900,
        reason: '实际准备时长不得超过预约的准备时长',
      );
    });

    test('时钟回拨产生的负数被钳制为零，仍留在平均分母里', () {
      final appointment = _appointment(
        id: 'clock-skew',
        startedAt: startedAt,
        settledMinutes: -5,
      );

      expect(appointmentActualPreparationSeconds(appointment), 0);
      final statistics = appointmentPreparationStatistics([appointment]);
      expect(statistics.totalDurationSeconds, 0);
      expect(statistics.acceptedSessionCount, 1);
      expect(statistics.averageDurationSeconds, 0);
    });

    test('缺少结算时刻时回落到到期时刻', () {
      final appointment = AppointmentPreparation(
        id: 'no-settlement',
        taskId: 'task-no-settlement',
        mode: FocusChainMode.regular,
        durationSeconds: 1500,
        startedAt: startedAt,
        endsAt: startedAt.add(const Duration(minutes: 15)),
        status: AppointmentPreparationStatus.succeeded,
        settledAt: null,
        updatedAt: startedAt,
        preparationSeconds: 900,
      );

      expect(appointmentActualPreparationSeconds(appointment), 900);
    });

    test('进行中与非 accepted 的预约不进入统计', () {
      final statistics = appointmentPreparationStatistics([
        _appointment(id: 'accepted', startedAt: startedAt, settledMinutes: 10),
        _appointment(
          id: 'active',
          startedAt: startedAt.add(const Duration(hours: 1)),
          settledMinutes: 10,
          status: AppointmentPreparationStatus.active,
        ),
        _appointment(
          id: 'pending-review',
          startedAt: startedAt.add(const Duration(hours: 2)),
          settledMinutes: 10,
          disposition: FocusRecordDisposition.pendingReview,
        ),
        _appointment(
          id: 'duplicate',
          startedAt: startedAt.add(const Duration(hours: 3)),
          settledMinutes: 10,
          disposition: FocusRecordDisposition.duplicate,
        ),
      ]);

      expect(statistics.totalDurationSeconds, 600);
      expect(statistics.acceptedSessionCount, 1);
    });

    test('空输入返回零值统计', () {
      final statistics = appointmentPreparationStatistics(const []);

      expect(statistics.totalDurationSeconds, 0);
      expect(statistics.acceptedSessionCount, 0);
      expect(statistics.averageDurationSeconds, 0);
    });
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

AppointmentPreparation _appointment({
  required String id,
  required DateTime startedAt,
  required int settledMinutes,
  AppointmentPreparationStatus status = AppointmentPreparationStatus.succeeded,
  FocusRecordDisposition disposition = FocusRecordDisposition.accepted,
}) => AppointmentPreparation(
  id: id,
  taskId: 'task-$id',
  mode: FocusChainMode.regular,
  durationSeconds: 1500,
  startedAt: startedAt,
  endsAt: startedAt.add(const Duration(minutes: 15)),
  status: status,
  settledAt: startedAt.add(Duration(minutes: settledMinutes)),
  updatedAt: startedAt,
  preparationSeconds: 900,
  reviewDisposition: disposition,
);

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
