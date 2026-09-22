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
    this.pausedAt,
    this.pausedSeconds = 0,
    this.pauseRuleText,
    this.failureReason,
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
  final DateTime? pausedAt;
  final int pausedSeconds;
  final String? pauseRuleText;
  final String? failureReason;

  bool get isActive => status == FocusSessionStatus.active;
  bool get isPaused => status == FocusSessionStatus.paused;
  bool get isUnfinished => status.isUnfinished;
  bool get isFailed => status.isFailed;
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
