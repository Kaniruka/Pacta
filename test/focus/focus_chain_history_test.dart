import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_chain_history.dart';
import 'package:pacta/src/focus/focus_models.dart';

void main() {
  group('buildFocusChainHistory 空输入', () {
    test('三条链都没有记录，摘要全为零', () {
      final history = buildFocusChainHistory();
      expect(history.isEmpty, isTrue);
      for (final chain in FocusChainType.values) {
        final timeline = history.timelineFor(chain);
        expect(timeline.isEmpty, isTrue, reason: chain.label);
        expect(timeline.runs, isEmpty);
        expect(timeline.leadingBreaks, isEmpty);
        expect(timeline.awaitingClockReview, isEmpty);
        expect(timeline.bestStreak, 0);
        expect(timeline.runCount, 0);
        expect(timeline.currentStreak, 0);
        expect(timeline.isCurrentlyBroken, isFalse);
      }
    });

    test('进行中的记录不进入链式历史', () {
      final history = buildFocusChainHistory(
        sessions: [
          _session(
            id: 'active',
            at: DateTime(2026, 11, 15, 9),
            status: FocusSessionStatus.active,
            completedAt: null,
          ),
        ],
      );
      expect(history.timelineFor(FocusChainType.elite).isEmpty, isTrue);
    });
  });

  group('连续完成', () {
    test('三次连续完成得到 #1 -> #2 -> #3，段内按时间升序', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s3', DateTime(2026, 11, 15, 11)),
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _completed('s2', DateTime(2026, 11, 15, 10)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.runs, hasLength(1));
      expect(elite.runs.single.entries.map((entry) => entry.streakLabel), [
        '#1',
        '#2',
        '#3',
      ]);
      expect(elite.runs.single.entries.map((entry) => entry.id), [
        's1',
        's2',
        's3',
      ], reason: '输入顺序不影响回放顺序');
      expect(elite.currentStreak, 3);
      expect(elite.bestStreak, 3);
      expect(elite.runCount, 1);
      expect(elite.isCurrentlyBroken, isFalse);
    });

    test('获准提前完成与正常完成共用同一递增序号', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _completed(
            's2',
            DateTime(2026, 11, 15, 10),
            completionType: FocusSessionCompletionType.precedentRule,
            completionRuleText: '允许短暂起身接水',
          ),
        ],
      );
      final run = history.timelineFor(FocusChainType.elite).runs.single;
      expect(run.entries.map((entry) => entry.streakLabel), ['#1', '#2']);
      expect(run.entries.last.basisText, '允许短暂起身接水');
    });
  });

  group('断链', () {
    test('#1 -> #2 -> 断链 -> #1：新段在最顶部，失败收尾旧段', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _completed('s2', DateTime(2026, 11, 15, 10)),
          _failed('f1', DateTime(2026, 11, 15, 11), reason: '被消息打断'),
          _completed('s3', DateTime(2026, 11, 15, 12)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.runs, hasLength(2));
      expect(elite.runCount, 2);
      expect(elite.bestStreak, 2);
      expect(elite.currentStreak, 1, reason: '断链后从 #1 重新起算');
      expect(elite.isCurrentlyBroken, isFalse);
      // 最新一段在最顶部。
      expect(elite.runs.first.entries.single.streakLabel, '#1');
      expect(elite.runs.first.entries.single.id, 's3');
      // 旧段保留 #1、#2，并用失败的断链收尾。
      final older = elite.runs.last;
      expect(older.entries.map((entry) => entry.streakLabel), ['#1', '#2']);
      expect(older.isBroken, isTrue);
      expect(older.closingBreaks.single.id, 'f1');
      expect(older.closingBreaks.single.failureReason, '被消息打断');
      expect(older.closingBreaks.single.streakIndex, isNull);
    });

    test('连续两次失败都记在上一段收尾，不产生空段', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _failed('f1', DateTime(2026, 11, 15, 10)),
          _failed('f2', DateTime(2026, 11, 15, 11)),
          _completed('s2', DateTime(2026, 11, 15, 12)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.runs, hasLength(2));
      expect(elite.runs.last.closingBreaks.map((entry) => entry.id), [
        'f1',
        'f2',
      ]);
      expect(elite.bestStreak, 1);
      expect(elite.currentStreak, 1);
    });

    test('最近一条是失败时当前连续归零且链处于断链状态', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _completed('s2', DateTime(2026, 11, 15, 10)),
          _failed('f1', DateTime(2026, 11, 15, 11)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.isCurrentlyBroken, isTrue);
      expect(elite.currentStreak, 0);
      expect(elite.bestStreak, 2);
      expect(elite.runCount, 1);
      expect(elite.runs.single.closingBreaks.single.id, 'f1');
    });

    test('连胜开始之前的失败进入更早断链记录，且不影响后续编号', () {
      final history = buildFocusChainHistory(
        sessions: [
          _failed('f1', DateTime(2026, 11, 15, 8)),
          _completed('s1', DateTime(2026, 11, 15, 9)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.runs.single.entries.single.streakLabel, '#1');
      expect(elite.leadingBreaks.single.id, 'f1');
      expect(elite.currentStreak, 1);
    });
  });

  group('单设备时钟待核对', () {
    test('待核对记录不占序号也不打断连胜', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _awaitingClockReview('r1', DateTime(2026, 11, 15, 10)),
          _completed('s2', DateTime(2026, 11, 15, 11)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.awaitingClockReview, hasLength(1));
      expect(elite.awaitingClockReview.single.id, 'r1');
      expect(elite.awaitingClockReview.single.isAwaitingClockReview, isTrue);
      expect(elite.runs.single.entries.map((entry) => entry.streakLabel), [
        '#1',
        '#2',
      ]);
      expect(elite.currentStreak, 2);
      expect(elite.isCurrentlyBroken, isFalse);
      expect(elite.bestStreak, 2);
    });

    test('失败记录带待核对区间时同样不打断连胜', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('s1', DateTime(2026, 11, 15, 9)),
          _awaitingClockReview(
            'r1',
            DateTime(2026, 11, 15, 10),
            status: FocusSessionStatus.failed,
          ),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.isCurrentlyBroken, isFalse);
      expect(elite.currentStreak, 1);
      expect(
        elite.awaitingClockReview.single.kind,
        FocusChainHistoryEntryKind.awaitingClockReview,
      );
    });
  });

  group('三条链互相独立', () {
    test('精锐链、普通链与预约链各自回放', () {
      final history = buildFocusChainHistory(
        sessions: [
          _completed('e1', DateTime(2026, 11, 15, 9)),
          _completed('e2', DateTime(2026, 11, 15, 10)),
          _completed(
            'r1',
            DateTime(2026, 11, 15, 11),
            mode: FocusChainMode.regular,
          ),
          _failed(
            'r2',
            DateTime(2026, 11, 15, 12),
            mode: FocusChainMode.regular,
          ),
        ],
        appointments: [
          _appointment('a1', DateTime(2026, 11, 15, 13)),
          _appointment('a2', DateTime(2026, 11, 15, 14)),
          _appointment('a3', DateTime(2026, 11, 15, 15)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      final regular = history.timelineFor(FocusChainType.regular);
      final appointment = history.timelineFor(FocusChainType.appointment);
      expect(elite.currentStreak, 2);
      expect(elite.runCount, 1);
      expect(regular.currentStreak, 0);
      expect(regular.isCurrentlyBroken, isTrue);
      expect(regular.bestStreak, 1);
      expect(appointment.currentStreak, 3);
      expect(appointment.runCount, 1);
      expect(appointment.bestStreak, 3);
      expect(appointment.runs.single.entries.map((entry) => entry.id), [
        'a1',
        'a2',
        'a3',
      ], reason: '预约链只回放预约记录，不读专注记录');
    });

    test('预约链成功与失败回放出断链与重新起算', () {
      final history = buildFocusChainHistory(
        appointments: [
          _appointment('a1', DateTime(2026, 11, 15, 9)),
          _appointment(
            'a2',
            DateTime(2026, 11, 15, 10),
            status: AppointmentPreparationStatus.failed,
            reason: '提前取消',
          ),
          _appointment('a3', DateTime(2026, 11, 15, 11)),
        ],
      );
      final timeline = history.timelineFor(FocusChainType.appointment);
      expect(timeline.runs, hasLength(2));
      expect(timeline.runs.first.entries.single.streakLabel, '#1');
      expect(timeline.runs.last.entries.single.streakLabel, '#1');
      expect(timeline.runs.last.closingBreaks.single.failureReason, '提前取消');
      expect(timeline.bestStreak, 1);
      expect(timeline.runCount, 2);
      expect(timeline.currentStreak, 1);
    });

    test('未结算的预约不进入时间轴', () {
      final history = buildFocusChainHistory(
        appointments: [
          _appointment(
            'a1',
            DateTime(2026, 11, 15, 9),
            status: AppointmentPreparationStatus.active,
            settledAt: null,
          ),
        ],
      );
      expect(history.timelineFor(FocusChainType.appointment).isEmpty, isTrue);
    });
  });

  group('旧库防呆', () {
    test('非 accepted 的残留记录既不编号也不断链', () {
      final history = buildFocusChainHistory(
        sessions: [
          _session(
            id: 'legacy',
            at: DateTime(2026, 11, 15, 9),
            status: FocusSessionStatus.completed,
            reviewDisposition: FocusRecordDisposition.pendingReview,
          ),
          _completed('s1', DateTime(2026, 11, 15, 10)),
        ],
      );
      final elite = history.timelineFor(FocusChainType.elite);
      expect(elite.runs.single.entries.single.id, 's1');
      expect(elite.runs.single.entries.single.streakLabel, '#1');
      expect(elite.runs.single.closingBreaks, isEmpty);
      expect(elite.awaitingClockReview, isEmpty);
    });

    test('completedAt 缺失时回落到 endsAt', () {
      final at = DateTime(2026, 11, 15, 9);
      final history = buildFocusChainHistory(
        sessions: [
          _session(
            id: 's1',
            at: at,
            status: FocusSessionStatus.completed,
            completedAt: null,
          ),
        ],
      );
      expect(
        history
            .timelineFor(FocusChainType.elite)
            .runs
            .single
            .entries
            .single
            .occurredAt,
        at,
      );
    });
  });
  group('预约链有效时长与首屏同源', () {
    test('到期完成的预约记录完整准备时长', () {
      final at = DateTime(2026, 11, 15, 9);
      final entry = buildFocusChainHistory(
        appointments: [_appointment('a1', at)],
      ).timelineFor(FocusChainType.appointment).runs.single.entries.single;

      expect(entry.effectiveSeconds, 15 * 60);
    });

    test('提前进入专注时，时间轴只记录实际准备耗时', () {
      final at = DateTime(2026, 11, 15, 9);
      // 准备自 8:45 开始，8:54 提前进入专注：真实准备 9 分钟。
      final entry = buildFocusChainHistory(
        appointments: [
          _appointment(
            'a1',
            at,
            settledAt: at.subtract(const Duration(minutes: 6)),
          ),
        ],
      ).timelineFor(FocusChainType.appointment).runs.single.entries.single;

      expect(
        entry.effectiveSeconds,
        9 * 60,
        reason: '与首屏累计/平均同源，不能沿用约好的 15 分钟',
      );
    });

    test('主动取消按实际经过时间记录，并作为断链收尾', () {
      final first = DateTime(2026, 11, 15, 8);
      final second = DateTime(2026, 11, 15, 9);
      final history = buildFocusChainHistory(
        appointments: [
          _appointment('a1', first),
          _appointment(
            'a2',
            second,
            status: AppointmentPreparationStatus.failed,
            settledAt: second.subtract(const Duration(minutes: 12)),
            reason: '临时改变计划',
          ),
        ],
      );
      final broken = history
          .timelineFor(FocusChainType.appointment)
          .runs
          .single
          .closingBreaks
          .single;

      expect(broken.effectiveSeconds, 3 * 60);
      expect(broken.failureReason, '临时改变计划');
      expect(broken.isBreak, isTrue);
    });

    test('时钟回拨产生的负数被钳制为零', () {
      final at = DateTime(2026, 11, 15, 9);
      final entry = buildFocusChainHistory(
        appointments: [
          _appointment(
            'a1',
            at,
            settledAt: at.subtract(const Duration(minutes: 20)),
          ),
        ],
      ).timelineFor(FocusChainType.appointment).runs.single.entries.single;

      expect(entry.effectiveSeconds, 0);
    });

    test('非 accepted 的预约残留既不编号也不断链', () {
      final history = buildFocusChainHistory(
        appointments: [
          _appointment(
            'legacy',
            DateTime(2026, 11, 15, 9),
            reviewDisposition: FocusRecordDisposition.duplicate,
          ),
          _appointment('a2', DateTime(2026, 11, 15, 10)),
        ],
      );
      final timeline = history.timelineFor(FocusChainType.appointment);

      expect(timeline.runs.single.entries.single.id, 'a2');
      expect(timeline.runs.single.entries.single.streakLabel, '#1');
      expect(timeline.currentStreak, 1);
    });
  });
}

FocusSession _session({
  required String id,
  required DateTime at,
  String taskId = 'task-1',
  FocusChainMode mode = FocusChainMode.elite,
  FocusSessionStatus status = FocusSessionStatus.completed,
  DateTime? completedAt,
  FocusSessionCompletionType completionType =
      FocusSessionCompletionType.countdown,
  String? completionRuleText,
  String? failureReason,
  FocusRecordDisposition reviewDisposition = FocusRecordDisposition.accepted,
  List<FocusTimeInterval> effectiveIntervals = const [],
}) => FocusSession(
  id: id,
  taskId: taskId,
  mode: mode,
  durationSeconds: 1500,
  startedAt: at.subtract(const Duration(minutes: 25)),
  endsAt: at,
  status: status,
  completedAt: completedAt ?? at,
  effectiveSeconds: status == FocusSessionStatus.failed ? 300 : 1500,
  completionType: completionType,
  completionRuleText: completionRuleText,
  failureReason: failureReason,
  reviewDisposition: reviewDisposition,
  effectiveIntervals: effectiveIntervals,
);

FocusSession _completed(
  String id,
  DateTime at, {
  FocusChainMode mode = FocusChainMode.elite,
  FocusSessionCompletionType completionType =
      FocusSessionCompletionType.countdown,
  String? completionRuleText,
}) => _session(
  id: id,
  at: at,
  mode: mode,
  completionType: completionType,
  completionRuleText: completionRuleText,
);

FocusSession _failed(
  String id,
  DateTime at, {
  FocusChainMode mode = FocusChainMode.elite,
  String? reason,
}) => _session(
  id: id,
  at: at,
  mode: mode,
  status: FocusSessionStatus.failed,
  failureReason: reason,
);

FocusSession _awaitingClockReview(
  String id,
  DateTime at, {
  FocusChainMode mode = FocusChainMode.elite,
  FocusSessionStatus status = FocusSessionStatus.completed,
}) => _session(
  id: id,
  at: at,
  mode: mode,
  status: status,
  effectiveIntervals: [
    FocusTimeInterval(
      startedAt: at.subtract(const Duration(minutes: 25)),
      endedAt: at,
      measuredDurationSeconds: 1500,
      clockReviewStatus: FocusClockReviewStatus.pending,
    ),
  ],
);

AppointmentPreparation _appointment(
  String id,
  DateTime at, {
  AppointmentPreparationStatus status = AppointmentPreparationStatus.succeeded,
  String? reason,
  DateTime? settledAt,
  FocusRecordDisposition reviewDisposition = FocusRecordDisposition.accepted,
}) => AppointmentPreparation(
  id: id,
  taskId: 'task-1',
  mode: FocusChainMode.regular,
  durationSeconds: 1500,
  startedAt: at.subtract(const Duration(minutes: 15)),
  endsAt: at,
  status: status,
  settledAt: settledAt ?? at,
  updatedAt: at,
  failureReason: reason,
  preparationSeconds: 900,
  reviewDisposition: reviewDisposition,
);
