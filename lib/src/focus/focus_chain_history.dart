import 'focus_models.dart';
import 'focus_statistics.dart';

/// 专注链的三条链：精锐链、普通链与预约链。
///
/// 前两条由 [FocusSession.mode] 区分，预约链只由已结算的
/// [AppointmentPreparation] 构成。三条链的连胜各自独立：一条链断链
/// 不会影响另外两条。
enum FocusChainType {
  elite('精锐链'),
  regular('普通链'),
  appointment('预约链');

  const FocusChainType(this.label);

  final String label;

  static FocusChainType fromMode(FocusChainMode mode) => switch (mode) {
    FocusChainMode.elite => FocusChainType.elite,
    FocusChainMode.regular => FocusChainType.regular,
  };
}

/// 一条记录在链式时间轴上的身份。
enum FocusChainHistoryEntryKind {
  /// 正常完成或获准提前完成：占据一个连续序号（#1、#2、#3…）。
  numbered,

  /// 失败：结束当前连胜段，后续重新从 #1 起算。
  broken,

  /// 现行单设备时钟跳变待核对：不占序号，也不打断连胜。
  awaitingClockReview,
}

/// 一条已结算记录在链式时间轴上的投影。
///
/// 纯值对象：不持有仓储、不读时钟，只把 [FocusSession] /
/// [AppointmentPreparation] 的既有字段摊平成时间轴需要的事实。
class FocusChainHistoryEntry {
  const FocusChainHistoryEntry({
    required this.id,
    required this.chain,
    required this.kind,
    required this.occurredAt,
    required this.effectiveSeconds,
    required this.taskId,
    this.streakIndex,
    this.failureReason,
    this.basisText,
  });

  /// 来源记录 id：专注记录用 session id，预约链用 appointment id。
  final String id;
  final FocusChainType chain;
  final FocusChainHistoryEntryKind kind;

  /// 结算时刻：专注记录取 completedAt ?? endsAt，预约取 settledAt ?? endsAt；
  /// 时间轴按它升序回放。
  final DateTime occurredAt;

  /// 本次可靠有效时长：专注记录复用 [focusEffectiveSecondsForSession]
  /// 的口径（不含暂停与待核对区间），预约链为实际准备时长。
  final int effectiveSeconds;
  final String taskId;

  /// 连胜序号；只有 [FocusChainHistoryEntryKind.numbered] 才有值。
  final int? streakIndex;

  /// 失败原因；只对断链节点有意义。
  final String? failureReason;

  /// 获准提前完成时引用的下必为例原文。
  final String? basisText;

  bool get isNumbered => kind == FocusChainHistoryEntryKind.numbered;
  bool get isBreak => kind == FocusChainHistoryEntryKind.broken;
  bool get isAwaitingClockReview =>
      kind == FocusChainHistoryEntryKind.awaitingClockReview;

  /// 时间轴徽章文案：#1、#2…；断链与待核对没有序号。
  String? get streakLabel => streakIndex == null ? null : '#$streakIndex';

  FocusChainHistoryEntry withStreakIndex(int index) => FocusChainHistoryEntry(
    id: id,
    chain: chain,
    kind: kind,
    occurredAt: occurredAt,
    effectiveSeconds: effectiveSeconds,
    taskId: taskId,
    streakIndex: index,
    failureReason: failureReason,
    basisText: basisText,
  );
}

/// 一段连续完成的连胜：段内序号从 #1 递增，紧跟其后的失败作为
/// [closingBreaks] 收尾。
class FocusChainStreakRun {
  FocusChainStreakRun({
    required List<FocusChainHistoryEntry> entries,
    List<FocusChainHistoryEntry> closingBreaks = const [],
  }) : entries = List.unmodifiable(entries),
       closingBreaks = List.unmodifiable(closingBreaks),
       assert(entries.isNotEmpty, '连胜段至少包含一条完成记录');

  /// 段内记录，按时间升序：#1 -> #2 -> #3。
  final List<FocusChainHistoryEntry> entries;

  /// 结束本段的失败记录，按时间升序；空表示本段尚未被断链（当前进行段）。
  final List<FocusChainHistoryEntry> closingBreaks;

  int get length => entries.length;
  DateTime get startedAt => entries.first.occurredAt;
  DateTime get endedAt => entries.last.occurredAt;
  bool get isBroken => closingBreaks.isNotEmpty;
}

/// 一条链的完整回放结果。
///
/// [runs] 按时间倒序：最新连胜段（或当前进行段）排在最前，便于首屏先读到
/// 当下状态；段内仍是升序，使每个段自己读起来就是 #1 -> #2 -> #3。
class FocusChainTimeline {
  FocusChainTimeline({
    required this.chain,
    List<FocusChainStreakRun> runs = const [],
    List<FocusChainHistoryEntry> leadingBreaks = const [],
    List<FocusChainHistoryEntry> awaitingClockReview = const [],
  }) : runs = List.unmodifiable(runs),
       leadingBreaks = List.unmodifiable(leadingBreaks),
       awaitingClockReview = List.unmodifiable(awaitingClockReview);

  final FocusChainType chain;

  /// 连胜段，按时间倒序：最新一段（当前进行段）排在最前。
  final List<FocusChainStreakRun> runs;

  /// 只有「连胜开始之前」的失败会落在这里，按时间倒序。
  final List<FocusChainHistoryEntry> leadingBreaks;

  /// 时钟待核对记录，按时间倒序；不计入任何连胜段。
  final List<FocusChainHistoryEntry> awaitingClockReview;

  bool get isEmpty =>
      runs.isEmpty && leadingBreaks.isEmpty && awaitingClockReview.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 最高连胜：所有段里最长的一段。
  int get bestStreak =>
      runs.fold(0, (best, run) => run.length > best ? run.length : best);

  /// 连胜段数（断链把链切成多段）。
  int get runCount => runs.length;

  /// 当前连续次数：链已断或从无连胜时为 0。
  int get currentStreak =>
      runs.isEmpty || runs.first.isBroken ? 0 : runs.first.length;

  /// 链当前是否处于断链状态（最近一条已结算记录是失败）。
  bool get isCurrentlyBroken => runs.isNotEmpty && runs.first.isBroken;
}

/// 三条链的回放结果。
class FocusChainHistory {
  FocusChainHistory(Map<FocusChainType, FocusChainTimeline> timelines)
    : timelines = Map.unmodifiable(timelines);

  final Map<FocusChainType, FocusChainTimeline> timelines;

  FocusChainTimeline timelineFor(FocusChainType chain) => timelines[chain]!;

  bool get isEmpty => timelines.values.every((timeline) => timeline.isEmpty);
}

/// 把已结算的专注记录与预约记录确定性回放成三条链。
///
/// 规则（与票面一致）：
/// - 正常完成 / 获准提前完成：序号 +1，写进当前连胜段；
/// - 失败：断链，结束当前段，后续重新从 #1 起算；
/// - 只要存在现行单设备 isAwaitingClockReview 区间：标为时钟待核对，
///   既不占序号也不断链；
/// - 非 accepted 的旧库残留：直接跳过，既不编号也不断链，界面上不暴露
///   任何旧多端核对概念。
///
/// 专注链与预约链分开回放，同一函数内不会互相影响。
FocusChainHistory buildFocusChainHistory({
  Iterable<FocusSession> sessions = const <FocusSession>[],
  Iterable<AppointmentPreparation> appointments =
      const <AppointmentPreparation>[],
}) {
  final entries = <FocusChainType, List<FocusChainHistoryEntry>>{
    for (final chain in FocusChainType.values)
      chain: <FocusChainHistoryEntry>[],
  };
  for (final session in sessions) {
    final entry = _sessionEntry(session);
    if (entry == null) continue;
    entries[FocusChainType.fromMode(session.mode)]!.add(entry);
  }
  for (final appointment in appointments) {
    final entry = _appointmentEntry(appointment);
    if (entry == null) continue;
    entries[FocusChainType.appointment]!.add(entry);
  }
  return FocusChainHistory({
    for (final chain in FocusChainType.values)
      chain: _replay(chain, entries[chain]!),
  });
}

FocusChainHistoryEntry? _sessionEntry(FocusSession session) {
  if (session.status.isUnfinished) return null;
  // 旧库残留的非 accepted 记录既不编号也不断链：只做防呆跳过。
  if (!session.reviewDisposition.contributesToFocusProgress) return null;
  final awaitingClockReview = session.effectiveIntervals.any(
    (interval) => interval.isAwaitingClockReview,
  );
  final kind = awaitingClockReview
      ? FocusChainHistoryEntryKind.awaitingClockReview
      : session.isFailed
      ? FocusChainHistoryEntryKind.broken
      : FocusChainHistoryEntryKind.numbered;
  return FocusChainHistoryEntry(
    id: session.id,
    chain: FocusChainType.fromMode(session.mode),
    kind: kind,
    occurredAt: session.completedAt ?? session.endsAt,
    effectiveSeconds: focusEffectiveSecondsForSession(session),
    taskId: session.taskId,
    failureReason: session.failureReason,
    basisText: session.completionRuleText,
  );
}

FocusChainHistoryEntry? _appointmentEntry(AppointmentPreparation appointment) {
  if (appointment.isActive) return null;
  if (!appointment.reviewDisposition.contributesToFocusProgress) return null;
  return FocusChainHistoryEntry(
    id: appointment.id,
    chain: FocusChainType.appointment,
    kind: appointment.isFailed
        ? FocusChainHistoryEntryKind.broken
        : FocusChainHistoryEntryKind.numbered,
    occurredAt: appointment.settledAt ?? appointment.endsAt,
    effectiveSeconds: appointment.effectivePreparationSeconds,
    taskId: appointment.taskId,
    failureReason: appointment.failureReason,
  );
}

/// 按时间升序回放一条链：编号、断链、分组一次算完。
FocusChainTimeline _replay(
  FocusChainType chain,
  List<FocusChainHistoryEntry> entries,
) {
  final ordered = [...entries]..sort(_compareEntries);
  final builders = <_RunBuilder>[];
  final leadingBreaks = <FocusChainHistoryEntry>[];
  final awaiting = <FocusChainHistoryEntry>[];
  _RunBuilder? current;
  var streak = 0;

  for (final entry in ordered) {
    switch (entry.kind) {
      case FocusChainHistoryEntryKind.awaitingClockReview:
        awaiting.add(entry);
      case FocusChainHistoryEntryKind.broken:
        streak = 0;
        if (current != null) {
          current.closingBreaks.add(entry);
          builders.add(current);
          current = null;
        } else if (builders.isNotEmpty) {
          // 连续两次失败：都记在上一段的收尾里。
          builders.last.closingBreaks.add(entry);
        } else {
          leadingBreaks.add(entry);
        }
      case FocusChainHistoryEntryKind.numbered:
        current ??= _RunBuilder();
        streak += 1;
        current.entries.add(entry.withStreakIndex(streak));
    }
  }
  if (current != null) builders.add(current);

  return FocusChainTimeline(
    chain: chain,
    // 段按时间倒序：最新一段在最顶部。
    runs: [for (final builder in builders.reversed) builder.build()],
    leadingBreaks: leadingBreaks.reversed.toList(),
    awaitingClockReview: awaiting.reversed.toList(),
  );
}

int _compareEntries(FocusChainHistoryEntry a, FocusChainHistoryEntry b) {
  final byTime = a.occurredAt.compareTo(b.occurredAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}

class _RunBuilder {
  final entries = <FocusChainHistoryEntry>[];
  final closingBreaks = <FocusChainHistoryEntry>[];

  FocusChainStreakRun build() =>
      FocusChainStreakRun(entries: entries, closingBreaks: closingBreaks);
}
