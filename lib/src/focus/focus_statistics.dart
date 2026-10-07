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

int _focusSecondsForProjection(FocusSession session) {
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
