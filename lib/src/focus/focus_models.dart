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
  const FocusTimeInterval({required this.startedAt, required this.endedAt});

  final DateTime startedAt;
  final DateTime? endedAt;

  int get durationSeconds {
    final seconds = endedAt?.difference(startedAt).inSeconds ?? 0;
    return seconds > 0 ? seconds : 0;
  }

  FocusTimeInterval copyWith({DateTime? endedAt}) =>
      FocusTimeInterval(startedAt: startedAt, endedAt: endedAt ?? this.endedAt);
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
  });

  final Map<String, int> focusProgressSecondsByTask;
  final List<FocusActivityDay> recentActivity;
  final int totalAcceptedFocusSeconds;
  final String displayTimeZoneId;
  final bool followsDeviceTimeZone;
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

  bool get isActive => status == FocusSessionStatus.active;
  bool get isPaused => status == FocusSessionStatus.paused;
  bool get isUnfinished => status.isUnfinished;
  bool get isFailed => status.isFailed;
  bool get isEarlyCompleted =>
      status == FocusSessionStatus.completed &&
      completionType == FocusSessionCompletionType.precedentRule;
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

  bool get isActive => status.isActive;
  bool get isSucceeded => status == AppointmentPreparationStatus.succeeded;
  bool get isFailed => status == AppointmentPreparationStatus.failed;
}

class AppointmentChainRecord {
  const AppointmentChainRecord({
    required this.currentConsecutive,
    required this.bestConsecutive,
    required this.updatedAt,
  });

  final int currentConsecutive;
  final int bestConsecutive;
  final DateTime updatedAt;
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
  });

  final FocusChainMode mode;
  final int currentConsecutive;
  final int bestConsecutive;
  final DateTime updatedAt;
}
