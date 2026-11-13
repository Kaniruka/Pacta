import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/profile/profile_overview.dart';
import 'package:pacta/src/profile/profile_statistics.dart';

NationalFocusCard _card(
  String name, {
  required bool isInTree,
  NationalFocusCardState state = NationalFocusCardState.extinguished,
  int successfulDays = 0,
  DateTime? deletedAt,
}) => NationalFocusCard(
  id: name,
  name: name,
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
  int effectiveSeconds = 600,
}) {
  final startedAt = DateTime.utc(2026, 11, 1, 9);
  return FocusSession(
    id: id,
    taskId: 'task',
    mode: FocusChainMode.regular,
    durationSeconds: effectiveSeconds,
    startedAt: startedAt.add(Duration(minutes: id.length)),
    endsAt: startedAt.add(Duration(seconds: effectiveSeconds)),
    status: status,
    completedAt: startedAt.add(Duration(seconds: effectiveSeconds)),
    effectiveSeconds: effectiveSeconds,
    reviewDisposition: disposition,
  );
}

void main() {
  test('合并树与国策库两个流后输出共同结果', () async {
    final tree = StreamController<List<NationalFocusCard>>();
    final library = StreamController<List<NationalFocusCard>>();
    final merged = combineLatest2(
      tree.stream,
      library.stream,
      (List<NationalFocusCard> a, List<NationalFocusCard> b) => [...a, ...b],
    );
    final received = <List<NationalFocusCard>>[];
    final subscription = merged.listen(received.add);

    tree.add([_card('树中', isInTree: true)]);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
    library.add([_card('库中', isInTree: false)]);
    await Future<void>.delayed(Duration.zero);
    expect(received.single.map((card) => card.name), ['树中', '库中']);

    tree.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(received.last.map((card) => card.name), ['库中']);
    await subscription.cancel();
    await tree.close();
    await library.close();
  });

  test('一路报错时取消两路订阅并关闭输出', () async {
    final first = StreamController<int>();
    final second = StreamController<int>();
    final output = combineLatest2(
      first.stream,
      second.stream,
      (int a, int b) => a + b,
    );
    final errors = <Object>[];
    var completed = false;
    final subscription = output.listen(
      (_) {},
      onError: errors.add,
      onDone: () => completed = true,
    );

    first.add(1);
    second.add(2);
    await Future<void>.delayed(Duration.zero);
    first.addError(StateError('broken'));
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(completed, isTrue, reason: '错误后输出必须结束');
    expect(first.hasListener, isFalse, reason: '出错一路应释放订阅');
    expect(second.hasListener, isFalse, reason: '另一路也应释放订阅');
    await subscription.cancel();
    await first.close();
    await second.close();
  });

  test('明细页分别取点亮、已内化与已完成记录', () {
    final cards = [
      _card('点亮', isInTree: true, state: NationalFocusCardState.lit),
      _card(
        '待确认',
        isInTree: true,
        state: NationalFocusCardState.pendingTodayConfirmation,
      ),
      _card('已内化', isInTree: false, successfulDays: 180),
      _card(
        '已删除',
        isInTree: true,
        state: NationalFocusCardState.lit,
        successfulDays: 200,
        deletedAt: DateTime.utc(2026, 2, 1),
      ),
    ];
    expect(litCardsForOverview(cards).map((card) => card.name), ['点亮']);
    expect(internalizedCardsForOverview(cards).map((card) => card.name), [
      '已内化',
    ]);

    final sessions = [
      _session('a'),
      _session('failed', status: FocusSessionStatus.failed),
      _session('pending', disposition: FocusRecordDisposition.pendingReview),
    ];
    expect(completedSessionsForOverview(sessions).map((s) => s.id), ['a']);
    expect(
      statisticsForOverview(cards: cards, sessions: sessions),
      isA<ProfileStatistics>(),
    );
  });
}
