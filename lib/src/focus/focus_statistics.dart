import 'focus_models.dart';

/// Statistics for accepted, settled sessions in one focus-chain mode.
class FocusSessionStatistics {
  const FocusSessionStatistics({
    required this.totalDurationSeconds,
    required this.acceptedSessionCount,
  });

  final int totalDurationSeconds;
  final int acceptedSessionCount;

  /// The arithmetic mean of effective duration, including accepted sessions
  /// whose reliable effective duration is zero.
  double get averageDurationSeconds => acceptedSessionCount == 0
      ? 0
      : totalDurationSeconds / acceptedSessionCount;
}

/// Projects lifetime focus time and average session length by chain mode.
///
/// Only completed or failed sessions with an accepted review disposition
/// contribute. Effective duration uses the same reliable interval basis as
/// task focus progress: paused time is absent from the effective intervals,
/// intervals pending clock review or explicitly excluded are omitted, and
/// legacy sessions without interval data fall back to [FocusSession.effectiveSeconds].
/// Accepted settled sessions remain in the average's denominator even when
/// they have no reliable effective time.
Map<FocusChainMode, FocusSessionStatistics> focusStatisticsByMode(
  Iterable<FocusSession> sessions,
) {
  final totals = <FocusChainMode, int>{
    for (final mode in FocusChainMode.values) mode: 0,
  };
  final counts = <FocusChainMode, int>{
    for (final mode in FocusChainMode.values) mode: 0,
  };

  for (final session in sessions) {
    if (session.status != FocusSessionStatus.completed &&
        session.status != FocusSessionStatus.failed) {
      continue;
    }
    if (!session.reviewDisposition.contributesToFocusProgress) continue;

    counts.update(session.mode, (count) => count + 1, ifAbsent: () => 1);
    totals.update(
      session.mode,
      (seconds) => seconds + _focusSecondsForProjection(session),
      ifAbsent: () => _focusSecondsForProjection(session),
    );
  }

  return Map.unmodifiable({
    for (final mode in FocusChainMode.values)
      mode: FocusSessionStatistics(
        totalDurationSeconds: totals[mode]!,
        acceptedSessionCount: counts[mode]!,
      ),
  });
}

/// Reliable effective time of one settled session.
///
/// Shared by the focus statistics and the My-page profile statistics so both
/// surfaces keep one time basis: paused or excluded intervals are absent,
/// intervals awaiting clock review are omitted, and legacy sessions without
/// interval data fall back to [FocusSession.effectiveSeconds].
int focusEffectiveSecondsForSession(FocusSession session) {
  final intervals = session.effectiveIntervals;
  if (intervals.isEmpty) {
    return session.effectiveSeconds > 0 ? session.effectiveSeconds : 0;
  }

  return intervals.fold<int>(0, (seconds, interval) {
    if (interval.endedAt == null ||
        interval.durationSeconds <= 0 ||
        interval.isAwaitingClockReview ||
        interval.excludeFromFocusProgress) {
      return seconds;
    }
    return seconds + interval.durationSeconds;
  });
}

/// 预约准备的“实际耗时”：从开始准备到真正结算（或到期）之间经过的秒数。
///
/// 到期自动完成、提前进入专注与主动取消都落在同一条时间轴上，因此三条
/// 路径都复用这一处口径：
/// - 结算时刻优先取 [AppointmentPreparation.settledAt]，缺失时回落到到期
///   时刻 [AppointmentPreparation.endsAt]；
/// - 实际经过时间钳制在 0 到 [AppointmentPreparation.effectivePreparationSeconds]
///   之间：设备时钟回拨不得产生负数，晚结算也不得超过约好的准备时长。
int appointmentActualPreparationSeconds(AppointmentPreparation appointment) {
  final settledAt = appointment.settledAt ?? appointment.endsAt;
  final elapsedSeconds = settledAt.difference(appointment.startedAt).inSeconds;
  return elapsedSeconds
      .clamp(0, appointment.effectivePreparationSeconds)
      .toInt();
}

/// 预约链的累计与平均统计：与专注链共用 [FocusSessionStatistics] 的同一份
/// 均值算法（零时长也留在分母里）。
///
/// 只统计已结算（成功或失败）且 [AppointmentPreparation.reviewDisposition]
/// 计入专注进度的预约记录；进行中的预约既不累加也不占平均次数。
FocusSessionStatistics appointmentPreparationStatistics(
  Iterable<AppointmentPreparation> appointments,
) {
  var totalDurationSeconds = 0;
  var acceptedCount = 0;
  for (final appointment in appointments) {
    if (!appointment.isSucceeded && !appointment.isFailed) continue;
    if (!appointment.reviewDisposition.contributesToFocusProgress) continue;
    totalDurationSeconds += appointmentActualPreparationSeconds(appointment);
    acceptedCount += 1;
  }
  return FocusSessionStatistics(
    totalDurationSeconds: totalDurationSeconds,
    acceptedSessionCount: acceptedCount,
  );
}

int _focusSecondsForProjection(FocusSession session) =>
    focusEffectiveSecondsForSession(session);
