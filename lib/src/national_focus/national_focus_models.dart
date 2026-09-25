import 'dart:math' as math;

const maxNationalFocusStrengtheningLevels = 5;

enum NationalFocusCardState {
  lit,
  pendingTodayConfirmation,
  extinguished;

  String get storageValue => switch (this) {
    NationalFocusCardState.lit => 'lit',
    NationalFocusCardState.pendingTodayConfirmation =>
      'pending_today_confirmation',
    NationalFocusCardState.extinguished => 'extinguished',
  };

  String get label => switch (this) {
    NationalFocusCardState.lit => '点亮',
    NationalFocusCardState.pendingTodayConfirmation => '待今日确认',
    NationalFocusCardState.extinguished => '熄灭',
  };

  static NationalFocusCardState fromStorage(String value) => switch (value) {
    'lit' => NationalFocusCardState.lit,
    'pending_today_confirmation' =>
      NationalFocusCardState.pendingTodayConfirmation,
    'extinguished' => NationalFocusCardState.extinguished,
    _ => throw ArgumentError('Unknown National Focus card state: $value'),
  };
}

enum NationalFocusFailureCause {
  missedConfirmation,
  activeExtinguish;

  String get storageValue => switch (this) {
    NationalFocusFailureCause.missedConfirmation => 'missed_confirmation',
    NationalFocusFailureCause.activeExtinguish => 'active_extinguish',
  };

  String get label => switch (this) {
    NationalFocusFailureCause.missedConfirmation => '未完成今日确认',
    NationalFocusFailureCause.activeExtinguish => '主动熄灭',
  };

  static NationalFocusFailureCause fromStorage(String value) => switch (value) {
    'missed_confirmation' => NationalFocusFailureCause.missedConfirmation,
    'active_extinguish' => NationalFocusFailureCause.activeExtinguish,
    _ => throw ArgumentError('Unknown National Focus failure cause: $value'),
  };
}

enum NationalFocusCardDeletion { permanentlyDeleted, softDeleted }

class NationalFocusCard {
  const NationalFocusCard({
    required this.id,
    required this.triggerCondition,
    required this.action,
    required this.isInTree,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.hasPendingReview = false,
    this.successfulDays = 0,
    this.currentConsecutiveDays = 0,
    this.bestConsecutiveDays = 0,
    this.maintenanceCycleStarted = false,
    this.failureReason,
    this.cascadeSourceCardId,
    this.cascadePriorState,
    this.scope,
    this.exceptionNotes,
    this.parentId,
    this.strengtheningLevels = const [],
    this.activeStrengtheningLevel,
    this.requirementVersions = const [],
  });

  final String id;
  final String triggerCondition;
  final String action;
  final String? scope;
  final String? exceptionNotes;
  final bool isInTree;
  final String? parentId;
  final NationalFocusCardState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final bool hasPendingReview;
  final int successfulDays;
  final int currentConsecutiveDays;
  final int bestConsecutiveDays;
  final bool maintenanceCycleStarted;
  final String? failureReason;
  final String? cascadeSourceCardId;
  final NationalFocusCardState? cascadePriorState;
  final List<NationalFocusStrengtheningLevel> strengtheningLevels;
  final int? activeStrengtheningLevel;
  final List<NationalFocusRequirementVersion> requirementVersions;

  bool get isInLibrary => !isInTree;
  bool get isDeleted => deletedAt != null;
  bool get isTopLevel => isInTree && parentId == null;
  NationalFocusStrengtheningLevel? get activeStrengtheningDefinition {
    final activeLevel = activeStrengtheningLevel;
    if (activeLevel == null) return null;
    for (final level in strengtheningLevels) {
      if (level.levelNumber == activeLevel) return level;
    }
    return null;
  }

  String get effectiveTriggerCondition =>
      activeStrengtheningDefinition?.triggerCondition ?? triggerCondition;
  String get effectiveAction => activeStrengtheningDefinition?.action ?? action;

  double get internalizationProgress =>
      100 * (1 - math.exp(-successfulDays / 60));
}

class NationalFocusSyncSource {
  const NationalFocusSyncSource({
    required this.sourceId,
    required this.deviceId,
    required this.parentSourceIds,
    required this.occurredAt,
    required this.payload,
  });

  final String sourceId;
  final String deviceId;
  final List<String> parentSourceIds;
  final DateTime occurredAt;
  final String payload;
}

class NationalFocusStrengtheningLevel {
  const NationalFocusStrengtheningLevel({
    required this.levelNumber,
    this.triggerCondition,
    this.action,
  });

  final int levelNumber;
  final String? triggerCondition;
  final String? action;
}

class NationalFocusStrengtheningLevelDraft {
  const NationalFocusStrengtheningLevelDraft({
    this.triggerCondition,
    this.action,
  });

  final String? triggerCondition;
  final String? action;
}

class NationalFocusRequirementVersion {
  const NationalFocusRequirementVersion({
    required this.versionNumber,
    required this.strengtheningLevelNumber,
    required this.effectiveTriggerCondition,
    required this.effectiveAction,
    required this.effectiveFrom,
    this.scope,
    this.exceptionNotes,
    this.effectiveUntil,
  });

  final int versionNumber;
  final int? strengtheningLevelNumber;
  final String effectiveTriggerCondition;
  final String effectiveAction;
  final String? scope;
  final String? exceptionNotes;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
}

class NationalFocusCardSnapshot {
  const NationalFocusCardSnapshot({
    required this.id,
    required this.triggerCondition,
    required this.action,
    required this.isInTree,
    required this.state,
    required this.successfulDays,
    required this.currentConsecutiveDays,
    required this.bestConsecutiveDays,
    required this.maintenanceCycleStarted,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.scope,
    this.exceptionNotes,
    this.failureReason,
    this.cascadeSourceCardId,
    this.cascadePriorState,
    this.failureSourceCardId,
    this.activeStrengtheningLevel,
    this.requirementVersionNumber,
    String? effectiveTriggerCondition,
    String? effectiveAction,
  }) : effectiveTriggerCondition =
           effectiveTriggerCondition ?? triggerCondition,
       effectiveAction = effectiveAction ?? action;

  final String id;
  final String triggerCondition;
  final String action;
  final String? scope;
  final String? exceptionNotes;
  final bool isInTree;
  final String? parentId;
  final NationalFocusCardState state;
  final int successfulDays;
  final int currentConsecutiveDays;
  final int bestConsecutiveDays;
  final bool maintenanceCycleStarted;
  final String? failureReason;
  final String? cascadeSourceCardId;
  final NationalFocusCardState? cascadePriorState;
  final String? failureSourceCardId;
  final int? activeStrengtheningLevel;
  final int? requirementVersionNumber;
  final String effectiveTriggerCondition;
  final String effectiveAction;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class NationalFocusFailure {
  const NationalFocusFailure({
    required this.id,
    required this.batchId,
    required this.cardId,
    required this.checkpointAt,
    required this.cause,
    required this.failureReason,
    required this.sharedExplanation,
    required this.treeSnapshot,
    this.isPendingReview = false,
  });

  final String id;
  final String batchId;
  final String cardId;
  final DateTime checkpointAt;
  final NationalFocusFailureCause cause;
  final String? failureReason;
  final String? sharedExplanation;
  final List<NationalFocusCardSnapshot> treeSnapshot;
  final bool isPendingReview;
}

enum NationalFocusClockChangeDirection { forward, backward }

class NationalFocusReconciliationCardEffect {
  const NationalFocusReconciliationCardEffect({
    required this.cardId,
    this.triggerCondition,
    this.previousState,
    this.newState,
    this.previousParentId,
    this.newParentId,
    this.previousIsInTree,
    this.newIsInTree,
    this.previousFailureReason,
    this.newFailureReason,
    this.previousCascadeSourceCardId,
    this.newCascadeSourceCardId,
    this.previousSuccessfulDays,
    this.newSuccessfulDays,
    this.previousCurrentConsecutiveDays,
    this.newCurrentConsecutiveDays,
    this.previousBestConsecutiveDays,
    this.newBestConsecutiveDays,
    this.previousMaintenanceCycleStarted,
    this.newMaintenanceCycleStarted,
  });

  final String cardId;
  final String? triggerCondition;
  final String? previousState;
  final String? newState;
  final String? previousParentId;
  final String? newParentId;
  final bool? previousIsInTree;
  final bool? newIsInTree;
  final String? previousFailureReason;
  final String? newFailureReason;
  final String? previousCascadeSourceCardId;
  final String? newCascadeSourceCardId;
  final int? previousSuccessfulDays;
  final int? newSuccessfulDays;
  final int? previousCurrentConsecutiveDays;
  final int? newCurrentConsecutiveDays;
  final int? previousBestConsecutiveDays;
  final int? newBestConsecutiveDays;
  final bool? previousMaintenanceCycleStarted;
  final bool? newMaintenanceCycleStarted;
}

class NationalFocusReconciliationOperation {
  const NationalFocusReconciliationOperation({
    required this.sourceId,
    required this.deviceId,
    required this.operation,
    required this.occurredAt,
    required this.effects,
  });

  final String sourceId;
  final String deviceId;
  final String operation;
  final DateTime occurredAt;
  final List<NationalFocusReconciliationCardEffect> effects;
}

class NationalFocusReconciliationOption {
  const NationalFocusReconciliationOption({
    required this.sourceId,
    required this.operations,
    required this.effects,
  });

  /// The immutable synchronization source whose complete branch is selected.
  final String sourceId;
  final List<NationalFocusReconciliationOperation> operations;
  final List<NationalFocusReconciliationCardEffect> effects;
}

class NationalFocusReconciliationCase {
  const NationalFocusReconciliationCase({
    required this.id,
    required this.createdAt,
    required this.cardIds,
    required this.cardNames,
    required this.options,
    this.isDeferred = false,
  });

  final String id;
  final DateTime createdAt;
  final List<String> cardIds;
  final Map<String, String> cardNames;
  final List<NationalFocusReconciliationOption> options;
  final bool isDeferred;
}

class NationalFocusReconciliationResult {
  const NationalFocusReconciliationResult({
    required this.caseId,
    required this.resolvedAt,
    required this.cardIds,
    required this.acceptedSourceIds,
    required this.retainedSourceIds,
  });

  final String caseId;
  final DateTime resolvedAt;
  final List<String> cardIds;
  final List<String> acceptedSourceIds;
  final List<String> retainedSourceIds;
}

class NationalFocusClockReviewCase {
  const NationalFocusClockReviewCase({
    required this.id,
    required this.direction,
    required this.detectedAt,
    required this.previousWallTime,
    required this.observedWallTime,
    required this.reliableThroughTime,
    required this.estimatedElapsedSeconds,
    required this.cardIds,
    this.isDeferred = false,
  });

  final String id;
  final NationalFocusClockChangeDirection direction;
  final DateTime detectedAt;
  final DateTime previousWallTime;
  final DateTime observedWallTime;
  final DateTime reliableThroughTime;
  final int estimatedElapsedSeconds;
  final List<String> cardIds;
  final bool isDeferred;
}

class NationalFocusReviewState {
  const NationalFocusReviewState({
    this.reconciliationCases = const [],
    this.clockReviewCases = const [],
    this.reconciliationHistory = const [],
    this.clockReviewHistory = const [],
  });

  final List<NationalFocusReconciliationCase> reconciliationCases;
  final List<NationalFocusClockReviewCase> clockReviewCases;
  final List<NationalFocusReconciliationResult> reconciliationHistory;
  final List<NationalFocusClockReviewCase> clockReviewHistory;
}

class NationalFocusCardDraft {
  const NationalFocusCardDraft({
    required this.triggerCondition,
    required this.action,
    this.scope,
    this.exceptionNotes,
  });

  final String triggerCondition;
  final String action;
  final String? scope;
  final String? exceptionNotes;
}
