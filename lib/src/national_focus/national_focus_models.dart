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

class NationalFocusCard {
  const NationalFocusCard({
    required this.id,
    required this.triggerCondition,
    required this.action,
    required this.isInTree,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
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

  bool get isInLibrary => !isInTree;
  bool get isTopLevel => isInTree && parentId == null;
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
