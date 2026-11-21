import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;

/// Writes settled focus sessions straight into the local table.
///
/// 旧的多端逐实体同步已被移除，测试不再经过远端拉取来准备落地数据；
/// 这条种子路径只复刻 `focus_sessions` 的行形状（含区间 JSON），
/// 让投影类测试继续在真实列上运行。
Future<void> seedFocusSessions(
  PactaDatabase database, {
  required String userId,
  required List<FocusSession> sessions,
}) async {
  for (final session in sessions) {
    await database
        .into(database.focusSessions)
        .insertOnConflictUpdate(
          FocusSessionsCompanion.insert(
            userId: userId,
            id: session.id,
            appointmentId: Value(session.appointmentId),
            taskId: session.taskId,
            mode: session.mode.storageValue,
            durationSeconds: session.durationSeconds,
            startedAt: session.startedAt,
            endsAt: session.endsAt,
            status: session.status.storageValue,
            completedAt: Value(session.completedAt),
            effectiveSeconds: Value(session.effectiveSeconds),
            completionType: Value(session.completionType.storageValue),
            completionRuleText: Value(session.completionRuleText),
            pausedAt: Value(session.pausedAt),
            pausedSeconds: Value(session.pausedSeconds),
            pauseRuleText: Value(session.pauseRuleText),
            failureReason: Value(session.failureReason),
            effectiveIntervals: Value(
              jsonEncode([
                for (final interval in session.effectiveIntervals)
                  _intervalJson(interval),
              ]),
            ),
            reviewDisposition: Value(session.reviewDisposition.storageValue),
            reviewDispositionUpdatedAt: Value(
              session.reviewDispositionUpdatedAt,
            ),
            configurationBasisSourceId: Value(
              session.configurationBasisSourceId,
            ),
            outcomeBasisSourceId: Value(session.outcomeBasisSourceId),
          ),
        );
  }
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

Map<String, Object?> _intervalJson(FocusTimeInterval interval) => {
  'started_at': _iso(interval.startedAt),
  'ended_at': interval.endedAt == null ? null : _iso(interval.endedAt!),
  'measured_duration_seconds': interval.measuredDurationSeconds,
  'clock_epoch_id': interval.clockEpochId,
  'monotonic_started_microseconds': interval.monotonicStartedMicroseconds,
  'monotonic_ended_microseconds': interval.monotonicEndedMicroseconds,
  'monotonic_checkpoint_microseconds': interval.monotonicCheckpointMicroseconds,
  'last_observed_wall_time': interval.lastObservedWallTime == null
      ? null
      : _iso(interval.lastObservedWallTime!),
  'observed_started_at': interval.observedStartedAt == null
      ? null
      : _iso(interval.observedStartedAt!),
  'observed_ended_at': interval.observedEndedAt == null
      ? null
      : _iso(interval.observedEndedAt!),
  'clock_discrepancy_seconds': interval.clockDiscrepancySeconds,
  'clock_review_status': interval.clockReviewStatus.storageValue,
  'exclude_from_focus_progress': interval.excludeFromFocusProgress,
};
