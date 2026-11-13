import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/profile/profile_statistics.dart';

NationalFocusCard _card(
  String id, {
  required bool isInTree,
  NationalFocusCardState state = NationalFocusCardState.extinguished,
  int successfulDays = 0,
  DateTime? deletedAt,
}) => NationalFocusCard(
  id: id,
  name: id,
  triggerCondition: '触发',
  action: '行动',
  isInTree: isInTree,
  state: state,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  deletedAt: deletedAt,
  successfulDays: successfulDays,
);

FocusSession _session(
  String id, {
  FocusSessionStatus status = FocusSessionStatus.completed,
  FocusRecordDisposition disposition = FocusRecordDisposition.accepted,
  List<FocusTimeInterval> intervals = const [],
  int effectiveSeconds = 0,
}) {
  final startedAt = DateTime.utc(2026, 3, 1, 9);
  return FocusSession(
    id: id,
    taskId: 'task-$id',
    mode: FocusChainMode.regular,
    durationSeconds: 3600,
    startedAt: startedAt,
    endsAt: startedAt.add(const Duration(hours: 1)),
    status: status,
    completedAt: startedAt.add(const Duration(hours: 1)),
    effectiveSeconds: effectiveSeconds,
    effectiveIntervals: intervals,
    reviewDisposition: disposition,
  );
}

FocusTimeInterval _interval(int seconds, {bool excluded = false}) {
  final startedAt = DateTime.utc(2026, 3, 1, 9);
  return FocusTimeInterval(
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: seconds)),
    excludeFromFocusProgress: excluded,
  );
}

void main() {
  test('空记录的四项统计都是 0', () {
    final statistics = computeProfileStatistics(
      cards: const [],
      sessions: const [],
    );
    expect(statistics.litCardCount, 0);
    expect(statistics.internalizedCardCount, 0);
    expect(statistics.completedFocusCount, 0);
    expect(statistics.effectiveFocusSeconds, 0);
  });

  test('点亮数只统计树中未删除的 Lit 卡片', () {
    final statistics = computeProfileStatistics(
      cards: [
        _card('tree-lit', isInTree: true, state: NationalFocusCardState.lit),
        _card(
          'tree-pending',
          isInTree: true,
          state: NationalFocusCardState.pendingTodayConfirmation,
        ),
        _card(
          'tree-extinguished',
          isInTree: true,
          state: NationalFocusCardState.extinguished,
        ),
        _card(
          'deleted-lit',
          isInTree: true,
          state: NationalFocusCardState.lit,
          deletedAt: DateTime.utc(2026, 2, 1),
        ),
        _card(
          'library-lit',
          isInTree: false,
          state: NationalFocusCardState.lit,
        ),
      ],
      sessions: const [],
    );
    expect(statistics.litCardCount, 1);
  });

  test('已内化数量按未删除卡片的成功日 180 天边界计数', () {
    final statistics = computeProfileStatistics(
      cards: [
        _card('below', isInTree: true, successfulDays: 179),
        _card('at-180', isInTree: true, successfulDays: 180),
        _card('at-365', isInTree: false, successfulDays: 365),
        _card(
          'deleted-180',
          isInTree: true,
          successfulDays: 180,
          deletedAt: DateTime.utc(2026, 2, 1),
        ),
      ],
      sessions: const [],
    );
    expect(statistics.internalizedCardCount, 2);
  });

  test('专注完成次数只统计已接受的 completed 记录', () {
    final statistics = computeProfileStatistics(
      cards: const [],
      sessions: [
        _session('completed', effectiveSeconds: 600),
        _session('failed', status: FocusSessionStatus.failed),
        _session(
          'completed-pending',
          disposition: FocusRecordDisposition.pendingReview,
        ),
        _session(
          'completed-duplicate',
          disposition: FocusRecordDisposition.duplicate,
        ),
        _session('active', status: FocusSessionStatus.active),
      ],
    );
    expect(statistics.completedFocusCount, 1);
  });

  test('累计有效时间沿用现有口径，包含已接受失败记录的有效区间', () {
    final statistics = computeProfileStatistics(
      cards: const [],
      sessions: [
        _session('completed', intervals: [_interval(900)]),
        _session(
          'failed',
          status: FocusSessionStatus.failed,
          intervals: [_interval(300)],
        ),
        _session(
          'completed-pending',
          disposition: FocusRecordDisposition.pendingReview,
          intervals: [_interval(1200)],
        ),
        _session('excluded', intervals: [_interval(600, excluded: true)]),
      ],
    );
    // 区间被排除的已完成记录仍计入次数，但不贡献有效时间。
    expect(statistics.effectiveFocusSeconds, 1200);
    expect(statistics.completedFocusCount, 2);
  });

  test('已内化不改变成功日累计，179 与 180 天显示进度不提前封顶', () {
    final cards = [
      _card('below', isInTree: true, successfulDays: 179),
      _card('at-180', isInTree: true, successfulDays: 180),
    ];
    final statistics = computeProfileStatistics(
      cards: cards,
      sessions: const [],
    );
    expect(statistics.internalizedCardCount, 1);
    expect(cards.first.internalizationProgress.toStringAsFixed(0), '100');
    expect(cards.first.isInternalized, isFalse);
    expect(cards.last.isInternalized, isTrue);
  });
}
