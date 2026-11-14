import '../tasks/task_models.dart';

enum FocusChainMode {
  elite,
  regular;

  String get storageValue => switch (this) {
    FocusChainMode.elite => 'elite',
    FocusChainMode.regular => 'regular',
  };

  String get label => switch (this) {
    FocusChainMode.elite => '精锐链',
    FocusChainMode.regular => '普通链',
  };

  TaskClassification get taskClassification => switch (this) {
    FocusChainMode.elite => TaskClassification.elite,
    FocusChainMode.regular => TaskClassification.regular,
  };

  static FocusChainMode fromStorage(String value) => switch (value) {
    'elite' => FocusChainMode.elite,
    'regular' => FocusChainMode.regular,
    _ => throw ArgumentError('Unknown focus chain mode: $value'),
  };
}

enum FocusSessionStatus {
  active,
  paused,
  completed,
  failed;

  String get storageValue => switch (this) {
    FocusSessionStatus.active => 'active',
    FocusSessionStatus.paused => 'paused',
    FocusSessionStatus.completed => 'completed',
    FocusSessionStatus.failed => 'failed',
  };

  bool get isUnfinished => this == active || this == paused;

  bool get isFailed => this == FocusSessionStatus.failed;
}

enum FocusSessionCompletionType {
  countdown,
  precedentRule;

  String get storageValue => switch (this) {
    FocusSessionCompletionType.countdown => 'countdown',
    FocusSessionCompletionType.precedentRule => 'precedent_rule',
  };

  static FocusSessionCompletionType fromStorage(String? value) =>
      switch (value) {
        'precedent_rule' => FocusSessionCompletionType.precedentRule,
        _ => FocusSessionCompletionType.countdown,
      };
}

enum FocusRecordDisposition {
  accepted,
  pendingReview,
  duplicate;

  String get storageValue => switch (this) {
    FocusRecordDisposition.accepted => 'accepted',
    FocusRecordDisposition.pendingReview => 'pending_review',
    FocusRecordDisposition.duplicate => 'duplicate',
  };

  bool get contributesToFocusProgress => this == accepted;

  static FocusRecordDisposition fromStorage(String? value) => switch (value) {
    'pending_review' => FocusRecordDisposition.pendingReview,
    'duplicate' => FocusRecordDisposition.duplicate,
    _ => FocusRecordDisposition.accepted,
  };
}

class FocusTimeInterval {
  const FocusTimeInterval({
    required this.startedAt,
    required this.endedAt,
    this.measuredDurationSeconds,
    this.clockEpochId,
    this.monotonicStartedMicroseconds,
    this.monotonicEndedMicroseconds,
    this.monotonicCheckpointMicroseconds,
    this.lastObservedWallTime,
    this.observedStartedAt,
    this.observedEndedAt,
    this.clockDiscrepancySeconds,
    this.clockReviewStatus = FocusClockReviewStatus.none,
    this.excludeFromFocusProgress = false,
  });

  final DateTime startedAt;
  final DateTime? endedAt;

  /// Elapsed time measured by the monotonic clock, when available.
  final int? measuredDurationSeconds;
  final String? clockEpochId;
  final int? monotonicStartedMicroseconds;
  final int? monotonicEndedMicroseconds;

  /// Most recent local wall/monotonic sample persisted while this interval
  /// was open, used to detect clock rollback across process recovery.
  final int? monotonicCheckpointMicroseconds;
  final DateTime? lastObservedWallTime;

  /// Original device wall-clock values retained when they disagree with the
  /// monotonic timeline.
  final DateTime? observedStartedAt;
  final DateTime? observedEndedAt;
  final int? clockDiscrepancySeconds;
  final FocusClockReviewStatus clockReviewStatus;
  final bool excludeFromFocusProgress;

  bool get isAwaitingClockReview =>
      clockReviewStatus == FocusClockReviewStatus.pending ||
      clockReviewStatus == FocusClockReviewStatus.deferred;

  int get durationSeconds {
    if (excludeFromFocusProgress) return 0;
    if (measuredDurationSeconds != null) {
      return measuredDurationSeconds!.clamp(0, 1 << 31);
    }
    final seconds = endedAt?.difference(startedAt).inSeconds ?? 0;
    return seconds > 0 ? seconds : 0;
  }

  FocusTimeInterval copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    int? measuredDurationSeconds,
    String? clockEpochId,
    int? monotonicStartedMicroseconds,
    int? monotonicEndedMicroseconds,
    int? monotonicCheckpointMicroseconds,
    DateTime? lastObservedWallTime,
    DateTime? observedStartedAt,
    DateTime? observedEndedAt,
    int? clockDiscrepancySeconds,
    FocusClockReviewStatus? clockReviewStatus,
    bool? excludeFromFocusProgress,
  }) => FocusTimeInterval(
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    measuredDurationSeconds:
        measuredDurationSeconds ?? this.measuredDurationSeconds,
    clockEpochId: clockEpochId ?? this.clockEpochId,
    monotonicStartedMicroseconds:
        monotonicStartedMicroseconds ?? this.monotonicStartedMicroseconds,
    monotonicEndedMicroseconds:
        monotonicEndedMicroseconds ?? this.monotonicEndedMicroseconds,
    monotonicCheckpointMicroseconds:
        monotonicCheckpointMicroseconds ?? this.monotonicCheckpointMicroseconds,
    lastObservedWallTime: lastObservedWallTime ?? this.lastObservedWallTime,
    observedStartedAt: observedStartedAt ?? this.observedStartedAt,
    observedEndedAt: observedEndedAt ?? this.observedEndedAt,
    clockDiscrepancySeconds:
        clockDiscrepancySeconds ?? this.clockDiscrepancySeconds,
    clockReviewStatus: clockReviewStatus ?? this.clockReviewStatus,
    excludeFromFocusProgress:
        excludeFromFocusProgress ?? this.excludeFromFocusProgress,
  );
}

enum FocusClockReviewStatus {
  none,
  pending,
  deferred,
  resolved;

  String get storageValue => switch (this) {
    FocusClockReviewStatus.none => 'none',
    FocusClockReviewStatus.pending => 'pending',
    FocusClockReviewStatus.deferred => 'deferred',
    FocusClockReviewStatus.resolved => 'resolved',
  };

  static FocusClockReviewStatus fromStorage(String? value) => switch (value) {
    'pending' => FocusClockReviewStatus.pending,
    'deferred' => FocusClockReviewStatus.deferred,
    'resolved' => FocusClockReviewStatus.resolved,
    _ => FocusClockReviewStatus.none,
  };
}

enum FocusClockChangeDirection { forward, backward }

enum FocusClockReviewDecision { acceptMonotonicEstimate, keepReliableTimeOnly }

class FocusClockReviewCase {
  const FocusClockReviewCase({
    required this.id,
    required this.sessionId,
    required this.taskId,
    required this.direction,
    required this.reliableSeconds,
    required this.interval,
  });

  final String id;
  final String sessionId;
  final String taskId;
  final FocusClockChangeDirection direction;
  final int reliableSeconds;
  final FocusTimeInterval interval;

  bool get isDeferred =>
      interval.clockReviewStatus == FocusClockReviewStatus.deferred;
  bool get canAcceptMonotonicEstimate =>
      interval.measuredDurationSeconds != null;
  int? get uncertainSeconds => interval.measuredDurationSeconds;
}

class FocusActivityDay {
  const FocusActivityDay({required this.date, required this.activeSeconds});

  /// A calendar date stored as a UTC date-only value.
  final DateTime date;
  final int activeSeconds;
}

class FocusDashboardMetrics {
  const FocusDashboardMetrics({
    required this.focusProgressSecondsByTask,
    required this.recentActivity,
    required this.totalAcceptedFocusSeconds,
    required this.displayTimeZoneId,
    required this.followsDeviceTimeZone,
    this.hasPendingReview = false,
    this.pendingReviewTaskIds = const {},
  });

  final Map<String, int> focusProgressSecondsByTask;
  final List<FocusActivityDay> recentActivity;
  final int totalAcceptedFocusSeconds;
  final String displayTimeZoneId;
  final bool followsDeviceTimeZone;
  final bool hasPendingReview;
  final Set<String> pendingReviewTaskIds;
}

/// 每场预约准备时长：5 / 10 / 15 分钟预设，或 1–60 分钟的整分钟自定义值。
///
/// 1–60 是本票选定的技术输入边界，不是从产品规则推导的结论：分钟是本模块唯一的
/// 整数时长单位，0 与不足一分钟不构成延迟启动；通知与状态栏按 `mm:ss` 呈现且
/// 分钟字段为两位，上界保持在两位分钟数内，使整段准备倒计时在既有展示中完整可见、
/// 永不触发静默截断。非法值一律抛 [ArgumentError]，从不截断。
abstract final class AppointmentPreparationDuration {
  static const int minimumMinutes = 1;
  static const int maximumMinutes = 60;
  static const int defaultMinutes = 15;
  static const List<int> presets = <int>[5, 10, 15];
  static const Duration defaultDuration = Duration(minutes: defaultMinutes);

  static const String invalidMessage = '准备时长需为 1–60 分钟的整数。';

  /// 校验整分钟输入；越界或非整数抛出 [ArgumentError]。
  static Duration validateMinutes(int minutes) {
    if (minutes < minimumMinutes || minutes > maximumMinutes) {
      throw ArgumentError.value(minutes, 'minutes', invalidMessage);
    }
    return Duration(minutes: minutes);
  }

  /// 校验准备时长；非整分钟、0、负数与越界值都被拒绝。
  /// 用微秒判断整分钟，避免 `inSeconds` 截断把 1 分 0.5 秒当成合法值。
  static Duration validate(Duration value) {
    if (value.inMicroseconds % Duration.microsecondsPerMinute != 0) {
      throw ArgumentError.value(value, 'preparation', invalidMessage);
    }
    return validateMinutes(
      value.inMicroseconds ~/ Duration.microsecondsPerMinute,
    );
  }

  static String describe(int seconds) =>
      '${(seconds / Duration.secondsPerMinute).ceil()} 分钟';
}

enum AppointmentPreparationStatus {
  active,
  succeeded,
  failed;

  String get storageValue => switch (this) {
    AppointmentPreparationStatus.active => 'active',
    AppointmentPreparationStatus.succeeded => 'succeeded',
    AppointmentPreparationStatus.failed => 'failed',
  };

  bool get isActive => this == AppointmentPreparationStatus.active;

  static AppointmentPreparationStatus fromStorage(String value) =>
      switch (value) {
        'active' => AppointmentPreparationStatus.active,
        'failed' => AppointmentPreparationStatus.failed,
        _ => AppointmentPreparationStatus.succeeded,
      };
}

class PrecedentRule {
  const PrecedentRule({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class FocusSession {
  const FocusSession({
    required this.id,
    required this.taskId,
    required this.mode,
    required this.durationSeconds,
    required this.startedAt,
    required this.endsAt,
    required this.status,
    required this.completedAt,
    required this.effectiveSeconds,
    this.completionType = FocusSessionCompletionType.countdown,
    this.completionRuleText,
    this.pausedAt,
    this.pausedSeconds = 0,
    this.pauseRuleText,
    this.failureReason,
    this.appointmentId,
    this.effectiveIntervals = const [],
    this.reviewDisposition = FocusRecordDisposition.accepted,
    this.reviewDispositionUpdatedAt,
    this.configurationBasisSourceId,
    this.outcomeBasisSourceId,
  });

  final String id;
  final String taskId;
  final FocusChainMode mode;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endsAt;
  final FocusSessionStatus status;
  final DateTime? completedAt;
  final int effectiveSeconds;
  final FocusSessionCompletionType completionType;
  final String? completionRuleText;
  final DateTime? pausedAt;
  final int pausedSeconds;
  final String? pauseRuleText;
  final String? failureReason;
  final String? appointmentId;
  final List<FocusTimeInterval> effectiveIntervals;
  final FocusRecordDisposition reviewDisposition;
  final DateTime? reviewDispositionUpdatedAt;
  final String? configurationBasisSourceId;
  final String? outcomeBasisSourceId;

  bool get isActive => status == FocusSessionStatus.active;
  bool get isPaused => status == FocusSessionStatus.paused;
  bool get isUnfinished => status.isUnfinished;
  bool get isFailed => status.isFailed;
  bool get isPendingReview =>
      reviewDisposition == FocusRecordDisposition.pendingReview;
  bool get isEarlyCompleted =>
      status == FocusSessionStatus.completed &&
      completionType == FocusSessionCompletionType.precedentRule;

  FocusSession copyWithReviewDisposition({
    required FocusRecordDisposition disposition,
    required DateTime reviewedAt,
  }) => FocusSession(
    id: id,
    taskId: taskId,
    mode: mode,
    durationSeconds: durationSeconds,
    startedAt: startedAt,
    endsAt: endsAt,
    status: status,
    completedAt: completedAt,
    effectiveSeconds: effectiveSeconds,
    completionType: completionType,
    completionRuleText: completionRuleText,
    pausedAt: pausedAt,
    pausedSeconds: pausedSeconds,
    pauseRuleText: pauseRuleText,
    failureReason: failureReason,
    appointmentId: appointmentId,
    effectiveIntervals: effectiveIntervals,
    reviewDisposition: disposition,
    reviewDispositionUpdatedAt: reviewedAt,
    configurationBasisSourceId: configurationBasisSourceId,
    outcomeBasisSourceId: outcomeBasisSourceId,
  );
}

/// Immutable state captured when one installation changes a Focus Session or
/// Appointment. Stable IDs make retries idempotent while parent IDs preserve
/// the state each installation had observed before the change.
class FocusSyncSource {
  const FocusSyncSource({
    required this.sourceId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.occurredAt,
    required this.payload,
    this.parentSourceId,
    this.parentSourceIds = const [],
  });

  final String sourceId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String? parentSourceId;
  final List<String> parentSourceIds;
  final DateTime occurredAt;
  final String payload;
}

class FocusSessionSourceOption {
  const FocusSessionSourceOption({
    required this.sourceId,
    required this.deviceId,
    required this.occurredAt,
    required this.session,
  });

  final String sourceId;
  final String deviceId;
  final DateTime occurredAt;
  final FocusSession session;
}

class FocusReconciliationSession {
  const FocusReconciliationSession({
    required this.session,
    required this.availableSources,
    required this.selectedConfigurationSource,
    required this.selectedOutcomeSource,
    required this.requiresConfigurationChoice,
    required this.requiresOutcomeChoice,
  });

  final FocusSession session;
  final List<FocusSessionSourceOption> availableSources;
  final FocusSessionSourceOption? selectedConfigurationSource;
  final FocusSessionSourceOption? selectedOutcomeSource;
  final bool requiresConfigurationChoice;
  final bool requiresOutcomeChoice;
}

class FocusReconciliationCase {
  const FocusReconciliationCase({required this.id, required this.sessions});

  final String id;
  final List<FocusReconciliationSession> sessions;

  bool get isPendingReview =>
      sessions.any((entry) => entry.session.isPendingReview);
  bool get hasOverlappingSessions => sessions.length > 1;
}

class FocusSessionReconciliationSelection {
  const FocusSessionReconciliationSelection({
    this.configurationSourceId,
    this.outcomeSourceId,
  });

  final String? configurationSourceId;
  final String? outcomeSourceId;
}

class FocusAppointmentSourceOption {
  const FocusAppointmentSourceOption({
    required this.sourceId,
    required this.deviceId,
    required this.occurredAt,
    required this.taskId,
    required this.mode,
    required this.durationSeconds,
  });

  final String sourceId;
  final String deviceId;
  final DateTime occurredAt;
  final String taskId;
  final FocusChainMode mode;
  final int durationSeconds;
}

class AppointmentPreparation {
  const AppointmentPreparation({
    required this.id,
    required this.taskId,
    required this.mode,
    required this.durationSeconds,
    required this.startedAt,
    required this.endsAt,
    required this.status,
    required this.settledAt,
    required this.updatedAt,
    this.sessionId,
    this.failureReason,
    this.reviewDisposition = FocusRecordDisposition.accepted,
    this.reviewDispositionUpdatedAt,
    this.configurationBasisSourceId,
    this.preparationSeconds,
  });

  final String id;
  final String taskId;
  final FocusChainMode mode;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endsAt;
  final AppointmentPreparationStatus status;
  final DateTime? settledAt;
  final DateTime updatedAt;
  final String? sessionId;
  final String? failureReason;
  final FocusRecordDisposition reviewDisposition;
  final DateTime? reviewDispositionUpdatedAt;
  final String? configurationBasisSourceId;

  /// 本场显式存储的准备时长；仅旧记录为 `null`。
  final int? preparationSeconds;

  /// 读取口径的准备时长：显式值优先；旧记录沿用已存起止时刻，
  /// 仅当该边界不是正数时才回到旧的 15 分钟规则。
  int get effectivePreparationSeconds {
    final stored = preparationSeconds;
    if (stored != null && stored > 0) return stored;
    final retained = endsAt.difference(startedAt).inSeconds;
    return retained > 0
        ? retained
        : AppointmentPreparationDuration.defaultDuration.inSeconds;
  }

  bool get isActive => status.isActive;
  bool get isSucceeded => status == AppointmentPreparationStatus.succeeded;
  bool get isFailed => status == AppointmentPreparationStatus.failed;
  bool get isPendingReview =>
      reviewDisposition == FocusRecordDisposition.pendingReview;

  AppointmentPreparation copyWithReviewDisposition({
    required FocusRecordDisposition disposition,
    required DateTime reviewedAt,
  }) => AppointmentPreparation(
    id: id,
    taskId: taskId,
    mode: mode,
    durationSeconds: durationSeconds,
    startedAt: startedAt,
    endsAt: endsAt,
    status: status,
    settledAt: settledAt,
    updatedAt: updatedAt,
    sessionId: sessionId,
    failureReason: failureReason,
    reviewDisposition: disposition,
    reviewDispositionUpdatedAt: reviewedAt,
    configurationBasisSourceId: configurationBasisSourceId,
    preparationSeconds: preparationSeconds,
  );

  AppointmentPreparation copyWithConfiguration({
    required String taskId,
    required FocusChainMode mode,
    required int durationSeconds,
    required String? sourceId,
    required DateTime updatedAt,
  }) => AppointmentPreparation(
    id: id,
    taskId: taskId,
    mode: mode,
    durationSeconds: durationSeconds,
    startedAt: startedAt,
    endsAt: endsAt,
    status: status,
    settledAt: settledAt,
    updatedAt: updatedAt,
    sessionId: sessionId,
    failureReason: failureReason,
    reviewDisposition: reviewDisposition,
    reviewDispositionUpdatedAt: reviewDispositionUpdatedAt,
    configurationBasisSourceId: sourceId,
    preparationSeconds: preparationSeconds,
  );
}

class AppointmentChainRecord {
  const AppointmentChainRecord({
    required this.currentConsecutive,
    required this.bestConsecutive,
    required this.updatedAt,
    this.hasPendingReview = false,
  });

  final int currentConsecutive;
  final int bestConsecutive;
  final DateTime updatedAt;
  final bool hasPendingReview;
}

class FocusNode {
  const FocusNode({
    required this.id,
    required this.sessionId,
    required this.taskId,
    required this.mode,
    required this.createdAt,
    required this.effectiveSeconds,
    this.note,
  });

  final String id;
  final String sessionId;
  final String taskId;
  final FocusChainMode mode;
  final DateTime createdAt;
  final int effectiveSeconds;
  final String? note;
}

class FocusChainRecord {
  const FocusChainRecord({
    required this.mode,
    required this.currentConsecutive,
    required this.bestConsecutive,
    required this.updatedAt,
    this.hasPendingReview = false,
  });

  final FocusChainMode mode;
  final int currentConsecutive;
  final int bestConsecutive;
  final DateTime updatedAt;
  final bool hasPendingReview;
}
