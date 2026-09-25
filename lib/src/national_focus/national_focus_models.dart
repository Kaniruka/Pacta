import 'dart:math' as math;

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
  final int successfulDays;
  final int currentConsecutiveDays;
  final int bestConsecutiveDays;
  final bool maintenanceCycleStarted;
  final String? failureReason;
  final String? cascadeSourceCardId;
  final NationalFocusCardState? cascadePriorState;

  bool get isInLibrary => !isInTree;
  bool get isDeleted => deletedAt != null;
  bool get isTopLevel => isInTree && parentId == null;
  double get internalizationProgress =>
      100 * (1 - math.exp(-successfulDays / 60));
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
  });

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
  });

  final String id;
  final String batchId;
  final String cardId;
  final DateTime checkpointAt;
  final NationalFocusFailureCause cause;
  final String? failureReason;
  final String? sharedExplanation;
  final List<NationalFocusCardSnapshot> treeSnapshot;
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
