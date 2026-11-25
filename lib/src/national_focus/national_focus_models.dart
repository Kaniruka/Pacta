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
    NationalFocusCardState.pendingTodayConfirmation => '确认',
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
    NationalFocusFailureCause.activeExtinguish => '熄灭',
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
    required this.name,
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
    this.strengtheningLevels = const [],
    this.activeStrengtheningLevel,
    this.iconKey,
  });

  final String id;
  final String name;
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
  final List<NationalFocusStrengtheningLevel> strengtheningLevels;
  final int? activeStrengtheningLevel;

  /// 卡片自定义图标键（如 `lucide:book`）；空值按默认灯泡图标呈现，
  /// 经 Cloud Snapshot 的 `icon_key` 跨端同步。
  final String? iconKey;

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

  bool get isInternalized => successfulDays >= 180;

  double get internalizationProgress => isInternalized
      ? 100
      : 100 * (1 - math.exp(-successfulDays / 60)) / (1 - math.exp(-3));
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

class NationalFocusCardSnapshot {
  const NationalFocusCardSnapshot({
    required this.id,
    required this.name,
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
    this.iconKey,
    String? effectiveTriggerCondition,
    String? effectiveAction,
  }) : effectiveTriggerCondition =
           effectiveTriggerCondition ?? triggerCondition,
       effectiveAction = effectiveAction ?? action;

  final String id;
  final String name;
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

  /// 失败当时卡片的自定义图标键；旧快照缺这一项时回落 `null`。
  final String? iconKey;
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
    this.reviewedAt,
  });

  final String id;
  final String batchId;
  final String cardId;
  final DateTime checkpointAt;
  final NationalFocusFailureCause cause;
  final String? failureReason;
  final String? sharedExplanation;
  final List<NationalFocusCardSnapshot> treeSnapshot;

  /// 回顾标记的持久时间戳；`null` 表示这条失败记录还没有被回顾。
  final DateTime? reviewedAt;

  /// 失败记录是否已被回顾，看板据此撤下未回顾提示。
  bool get isReviewed => reviewedAt != null;

  /// 是否仍待回顾。
  bool get needsReflection => reviewedAt == null;
}

class NationalFocusCardDraft {
  const NationalFocusCardDraft({
    required this.name,
    this.triggerCondition = '',
    required this.action,
    this.scope,
    this.exceptionNotes,
    this.iconKey,
    this.strengtheningLevels,
    this.activeStrengtheningLevel,
    this.updateStrengthening = false,
  });

  final String name;
  final String triggerCondition;
  final String action;
  final String? scope;
  final String? exceptionNotes;

  /// 卡片自定义图标键；`null` 表示回落默认图标。
  final String? iconKey;

  /// 强化档位草稿。非 `null` 时随卡片在同一次事务里整体替换；
  /// 传 `null` 表示这次编辑不触碰已存的强化档位。
  final List<NationalFocusStrengtheningLevel>? strengtheningLevels;

  /// 草稿当前选中的强化档位；必须存在于 [strengtheningLevels] 中。
  final int? activeStrengtheningLevel;

  /// `true` 时即使 [strengtheningLevels] 与现库一致也重写档位行；
  /// 编辑器用它表达"这次保存包含强化草稿"。
  final bool updateStrengthening;
}
