import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// Phase 5 / T02：旧多端核对流程废除后，打开既有库时直接把残留的非
/// `accepted` 裁定掰正为 `accepted`，同时单设备时钟跳变核对模型保持完整。
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pacta-review-purge');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> insertLegacyRows(PactaDatabase database) async {
    await database.customStatement(
      'INSERT INTO focus_sessions (user_id, id, task_id, mode, '
      'duration_seconds, started_at, ends_at, status, effective_seconds, '
      'effective_intervals, review_disposition) VALUES '
      "(?, 'session-1', 'task-1', 'regular', 600, 0, 600, 'completed', 600, "
      "'[]', 'pending_review')",
      ['user-a'],
    );
    await database.customStatement(
      'INSERT INTO focus_appointments (user_id, id, task_id, mode, '
      'duration_seconds, started_at, ends_at, status, updated_at, '
      'review_disposition) VALUES '
      "(?, 'appointment-1', 'task-1', 'regular', 600, 0, 600, 'succeeded', 0, "
      "'duplicate')",
      ['user-a'],
    );
    await database.customStatement(
      'INSERT INTO local_national_focus_cards (user_id, id, name, '
      'trigger_condition, action, is_in_tree, state, created_at, updated_at, '
      'review_disposition) VALUES '
      "(?, 'card-1', '晨光校准', '闹钟响', '开灯', 1, 'lit', 0, 0, "
      "'pending_review')",
      ['user-a'],
    );
  }

  Future<Map<String, String?>> dispositions(PactaDatabase database) async {
    final sessions = await database
        .customSelect("SELECT review_disposition FROM focus_sessions")
        .get();
    final appointments = await database
        .customSelect("SELECT review_disposition FROM focus_appointments")
        .get();
    final cards = await database
        .customSelect(
          "SELECT review_disposition FROM local_national_focus_cards",
        )
        .get();
    return {
      'session': sessions.single.read<String?>('review_disposition'),
      'appointment': appointments.single.read<String?>('review_disposition'),
      'card': cards.single.read<String?>('review_disposition'),
    };
  }

  test('打开既有库时把残留的待核对与重复裁定直接掰正为正常记录', () async {
    final file = File('${directory.path}/pacta.sqlite');
    final first = PactaDatabase(NativeDatabase(file));
    await insertLegacyRows(first);
    expect(await dispositions(first), {
      'session': 'pending_review',
      'appointment': 'duplicate',
      'card': 'pending_review',
    });
    await first.close();

    final reopened = PactaDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(await dispositions(reopened), {
      'session': 'accepted',
      'appointment': 'accepted',
      'card': 'accepted',
    });
    // 掰正动作不改 schema：版本号仍是冻结的 39。
    expect(reopened.schemaVersion, 39);
  });

  test('新建库不触发旧数据掰正，且 schema 版本保持冻结', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final rows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(
      rows.map((row) => row.read<String>('name')),
      containsAll(<String>['focus_sessions', 'local_national_focus_cards']),
    );
    expect(database.schemaVersion, 39);
  });

  test('单设备时钟跳变核对模型仍完整可用', () {
    final startedAt = DateTime.utc(2026, 11, 21, 1);
    final endedAt = startedAt.add(const Duration(minutes: 9, seconds: 59));
    final interval = FocusTimeInterval(
      startedAt: startedAt,
      endedAt: endedAt,
      measuredDurationSeconds: 599,
      observedStartedAt: startedAt.subtract(const Duration(hours: 2)),
      observedEndedAt: endedAt.subtract(const Duration(hours: 2)),
      clockDiscrepancySeconds: 7200,
      clockReviewStatus: FocusClockReviewStatus.pending,
    );
    expect(interval.isAwaitingClockReview, isTrue);

    final pending = FocusClockReviewCase(
      id: 'case-1',
      sessionId: 'session-1',
      taskId: 'task-1',
      direction: FocusClockChangeDirection.backward,
      reliableSeconds: 599,
      interval: interval,
    );
    expect(pending.isDeferred, isFalse);
    expect(pending.canAcceptMonotonicEstimate, isTrue);
    expect(pending.uncertainSeconds, 599);

    final deferred = FocusClockReviewCase(
      id: 'case-2',
      sessionId: 'session-1',
      taskId: 'task-1',
      direction: FocusClockChangeDirection.backward,
      reliableSeconds: 599,
      interval: interval.copyWith(
        clockReviewStatus: FocusClockReviewStatus.deferred,
      ),
    );
    expect(deferred.isDeferred, isTrue);
    expect(deferred.interval.isAwaitingClockReview, isTrue);

    final resolved = interval.copyWith(
      clockReviewStatus: FocusClockReviewStatus.resolved,
    );
    expect(resolved.isAwaitingClockReview, isFalse);
  });
}
