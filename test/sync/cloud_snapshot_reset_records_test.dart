import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_recovery_point.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「重置所有记录」：清空运行期记录与进度，保留卡片、树布局、规则与任务结构。
void main() {
  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late CloudSnapshotRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
      now: () => DateTime.utc(2026, 11, 20, 4),
    );
    await _seed(database);
  });

  tearDown(() => database.close());

  test('重置保留卡片、规则与任务结构，只清空记录与进度', () async {
    final before = await repository.captureLocalState();
    expect(before.hasUnfinishedFlow, isFalse);

    await repository.resetAllRecords(expectedFingerprint: before.fingerprint);

    // 国策树：失败记录、结算进度与软删除卡片一起清空。
    expect(
      await _count(database, 'local_national_focus_failures', 'user-a'),
      0,
    );
    expect(
      await _count(database, 'local_national_focus_maintenance', 'user-a'),
      0,
    );
    final cards = await _rows(
      database,
      'SELECT id, name, trigger_condition, action, scope, exception_notes, '
      'is_in_tree, parent_id, state, successful_days, current_consecutive_days, '
      'best_consecutive_days, maintenance_cycle_started, failure_reason, '
      'cascade_source_card_id, cascade_prior_state, review_disposition, '
      'active_strengthening_level FROM local_national_focus_cards '
      "WHERE user_id = 'user-a' ORDER BY id",
    );
    expect(cards.map((row) => row['id']), [
      'card-child',
      'card-lib',
      'card-root',
    ]);
    for (final card in cards) {
      expect(card['state'], 'extinguished');
      expect(card['successful_days'], 0);
      expect(card['current_consecutive_days'], 0);
      expect(card['best_consecutive_days'], 0);
      expect(card['maintenance_cycle_started'], 0);
      expect(card['failure_reason'], isNull);
      expect(card['cascade_source_card_id'], isNull);
      expect(card['cascade_prior_state'], isNull);
      expect(card['review_disposition'], 'accepted');
    }
    final root = cards.firstWhere((row) => row['id'] == 'card-root');
    expect(root['name'], '根国策');
    expect(root['trigger_condition'], '打开待办清单');
    expect(root['action'], '先写第一步');
    expect(root['scope'], '工作');
    expect(root['is_in_tree'], 1);
    expect(root['active_strengthening_level'], 2, reason: '强化等级本身仍在');
    final child = cards.firstWhere((row) => row['id'] == 'card-child');
    expect(child['parent_id'], 'card-root', reason: '父节点保留时子卡仍挂在树上');
    expect(child['is_in_tree'], 1);
    expect(child['exception_notes'], '有例外');
    expect(
      child['active_strengthening_level'],
      isNull,
      reason: '指向不存在的强化等级时该字段收敛为空',
    );

    // 要求版本：每张保留卡一条 version_number = 1、未结束的当前生效版本。
    final versions = await _rows(
      database,
      'SELECT card_id, version_number, strengthening_level_number, '
      'effective_trigger_condition, effective_action, scope, exception_notes, '
      'effective_until FROM local_national_focus_requirement_versions '
      "WHERE user_id = 'user-a' ORDER BY card_id",
    );
    expect(versions.map((row) => row['card_id']), [
      'card-child',
      'card-lib',
      'card-root',
    ]);
    for (final version in versions) {
      expect(version['version_number'], 1);
      expect(version['effective_until'], isNull);
    }
    final rootVersion = versions.firstWhere(
      (row) => row['card_id'] == 'card-root',
    );
    expect(rootVersion['strengthening_level_number'], 2);
    expect(rootVersion['effective_trigger_condition'], '强化条件');
    expect(rootVersion['effective_action'], '先写第一步');
    expect(rootVersion['scope'], '工作');

    // 专注链：记录全部清空，有效规则与信号保留。
    for (final table in const [
      'focus_sessions',
      'focus_appointments',
      'focus_nodes',
      'focus_chain_records',
      'appointment_chain_records',
      'focus_sync_sources',
    ]) {
      expect(await _count(database, table, 'user-a'), 0, reason: table);
    }
    expect(
      (await _rows(
        database,
        'SELECT id FROM focus_precedent_rules ORDER BY id',
      )).map((row) => row['id']),
      ['rule-active'],
    );
    expect(await _count(database, 'chain_signals', 'user-a'), 1);

    // 目标与任务：软删除的行与孤儿任务清掉，保留结构并把完成状态归零。
    final goals = await _rows(
      database,
      'SELECT id, is_pinned, sort_order FROM local_goals ORDER BY id',
    );
    expect(goals.map((row) => row['id']), ['goal-b', 'goal-keep']);
    expect(goals.last['is_pinned'], 1);
    expect(goals.last['sort_order'], 3);
    final tasks = await _rows(
      database,
      'SELECT id, goal_id, is_complete, focus_progress_seconds FROM local_tasks '
      "WHERE user_id = 'user-a'",
    );
    expect(tasks.map((row) => row['id']), ['task-keep']);
    expect(tasks.single['goal_id'], 'goal-keep');
    expect(tasks.single['is_complete'], 0);
    expect(tasks.single['focus_progress_seconds'], 0);

    // 日程：日程、重复规则与导入副本清空，日历来源连同本机映射保留。
    for (final table in const [
      'local_schedules',
      'local_schedule_recurrences',
      'local_calendar_blocks',
    ]) {
      expect(await _count(database, table, 'user-a'), 0, reason: table);
    }
    final sources = await _rows(
      database,
      'SELECT source_id, local_calendar_id, is_selected FROM '
      "local_calendar_sources WHERE user_id = 'user-a'",
    );
    expect(sources.single['source_id'], 'source-1');
    expect(sources.single['local_calendar_id'], 'cal-1');
    expect(sources.single['is_selected'], 1);
  });

  test('重置后的快照仍能通过校验，并能从重置前备份完整找回', () async {
    final before = await repository.captureLocalState();
    await repository.resetAllRecords(expectedFingerprint: before.fingerprint);

    final points = await repository.listLocalRecoveryPoints();
    expect(points, hasLength(1));
    expect(points.single.reason, CloudRecoveryReason.beforeRecordReset);
    expect(points.single.rowCount, before.rowCount);

    // 上传再下载会走完整的 _validatePayload：表集合、列集合、值类型与引用
    // 完整性都必须成立，否则这里直接抛错。
    final afterReset = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: afterReset.fingerprint,
    );
    await repository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: afterReset.fingerprint,
    );

    final restoredState = await repository.captureLocalState();
    await repository.restoreLocalRecoveryPoint(
      pointId: points.single.id,
      expectedFingerprint: restoredState.fingerprint,
    );

    final restored = await repository.captureLocalState();
    expect(restored.fingerprint, before.fingerprint, reason: '重置前的全部数据必须能完整找回');
    expect(restored.rowCount, before.rowCount);
  });

  test('重置换掉同步基线：清空后不再声称与云端一致', () async {
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: (await repository.captureLocalState()).fingerprint,
    );
    expect(await repository.loadSyncResult(), isNotNull);

    final before = await repository.captureLocalState();
    await repository.resetAllRecords(expectedFingerprint: before.fingerprint);

    expect(await repository.loadSyncResult(), isNull);
  });

  test('未结束的预约或专注阻止重置，且不改表也不留恢复点', () async {
    await database.customStatement(
      "UPDATE focus_appointments SET status = 'active' WHERE id = 'appointment-1'",
    );
    final before = await repository.captureLocalState();
    expect(before.hasUnfinishedFlow, isTrue);

    await expectLater(
      repository.resetAllRecords(expectedFingerprint: before.fingerprint),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '预约或专注尚未结束，暂不能重置数据。',
        ),
      ),
    );
    expect(await repository.listLocalRecoveryPoints(), isEmpty);
    expect(await _count(database, 'focus_sessions', 'user-a'), 1);
    expect(await _count(database, 'local_tasks', 'user-a'), 3);
  });

  test('确认期间本机数据变化时整体放弃', () async {
    final before = await repository.captureLocalState();
    await database.customStatement(
      "UPDATE local_goals SET title = '别处改过的标题' WHERE id = 'goal-keep'",
    );

    await expectLater(
      repository.resetAllRecords(expectedFingerprint: before.fingerprint),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '本机数据在确认期间发生变化，请重新检查后再重置。',
        ),
      ),
    );
    expect(await repository.listLocalRecoveryPoints(), isEmpty);
    expect(await _count(database, 'focus_sessions', 'user-a'), 1);
    expect(
      await _count(database, 'local_national_focus_failures', 'user-a'),
      1,
    );
  });

  test('恢复点没有真正落盘时一行都不改', () async {
    final broken = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
      recoveryPointStore: _NeutralizingRecoveryPointStore(
        DriftCloudRecoveryPointStore(database),
      ),
    );
    final before = await broken.captureLocalState();

    await expectLater(
      broken.resetAllRecords(expectedFingerprint: before.fingerprint),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '本机恢复点未正确保存，已取消重置。',
        ),
      ),
    );
    expect(await _rows(database, 'SELECT id FROM local_tasks'), hasLength(4));
    expect(await _count(database, 'focus_sessions', 'user-a'), 1);
  });

  test('只重置当前用户，其他账号的行不受影响', () async {
    final before = await repository.captureLocalState();
    await repository.resetAllRecords(expectedFingerprint: before.fingerprint);

    expect(
      (await _rows(
        database,
        "SELECT id FROM local_national_focus_cards WHERE user_id = 'user-b'",
      )).map((row) => row['id']),
      ['card-b'],
    );
    expect(
      (await _rows(
        database,
        "SELECT state, successful_days FROM local_national_focus_cards "
        "WHERE id = 'card-b'",
      )).single['successful_days'],
      9,
    );
    expect(
      (await _rows(
        database,
        "SELECT is_complete FROM local_tasks WHERE user_id = 'user-b'",
      )).single['is_complete'],
      1,
    );
  });
}

/// 写入后读回不到：模拟恢复点存储不可信。
class _NeutralizingRecoveryPointStore implements CloudRecoveryPointStore {
  _NeutralizingRecoveryPointStore(this._delegate);

  final CloudRecoveryPointStore _delegate;

  @override
  Future<void> save(CloudRecoveryPoint point) => _delegate.save(point);

  @override
  Future<List<CloudRecoveryPointSummary>> list(String userId) =>
      _delegate.list(userId);

  @override
  Future<CloudRecoveryPoint?> load(String userId, String pointId) async => null;
}

int _seconds(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

Future<void> _insert(
  PactaDatabase database,
  String table,
  Map<String, Object?> values,
) {
  final columns = values.keys.toList();
  final names = columns.map((column) => '"$column"').join(',');
  final placeholders = List.filled(columns.length, '?').join(',');
  return database.customStatement(
    'INSERT INTO "$table" ($names) VALUES ($placeholders)',
    [for (final column in columns) values[column]],
  );
}

Future<int> _count(PactaDatabase database, String table, String userId) async {
  final rows = await database
      .customSelect(
        "SELECT COUNT(*) AS total FROM \"$table\" WHERE user_id = ?",
        variables: [Variable<String>(userId)],
      )
      .get();
  return rows.single.read<int>('total');
}

Future<List<Map<String, Object?>>> _rows(
  PactaDatabase database,
  String sql,
) async {
  final result = await database.customSelect(sql).get();
  return [for (final row in result) Map<String, Object?>.from(row.data)];
}

Future<void> _seed(PactaDatabase database) async {
  final created = _seconds(DateTime.utc(2026, 11, 1, 1));
  final updated = _seconds(DateTime.utc(2026, 11, 5, 2));
  final appointmentStart = _seconds(DateTime.utc(2026, 11, 6, 1));

  await _insert(database, 'local_goals', {
    'user_id': 'user-a',
    'id': 'goal-keep',
    'title': '保留目标',
    'description': '保留描述',
    'classification': 'regular',
    'created_at': created,
    'updated_at': updated,
    'is_pinned': 1,
    'sort_order': 3,
    'deleted_at': null,
  });
  await _insert(database, 'local_goals', {
    'user_id': 'user-a',
    'id': 'goal-gone',
    'title': '已删除目标',
    'description': '',
    'classification': 'regular',
    'created_at': created,
    'updated_at': updated,
    'is_pinned': 0,
    'sort_order': null,
    'deleted_at': updated,
  });
  await _insert(database, 'local_goals', {
    'user_id': 'user-b',
    'id': 'goal-b',
    'title': '其他用户目标',
    'description': '',
    'classification': 'regular',
    'created_at': created,
    'updated_at': updated,
    'is_pinned': 0,
    'sort_order': null,
    'deleted_at': null,
  });

  Map<String, Object?> task(String id, String goalId) => {
    'user_id': 'user-a',
    'id': id,
    'goal_id': goalId,
    'title': '任务$id',
    'description': '',
    'classification': 'regular',
    'estimated_minutes': 25,
    'deadline': null,
    'is_complete': 1,
    'focus_progress_seconds': 600,
    'created_at': created,
    'updated_at': updated,
    'deleted_at': null,
  };
  await _insert(database, 'local_tasks', task('task-keep', 'goal-keep'));
  await _insert(database, 'local_tasks', {
    ...task('task-deleted', 'goal-keep'),
    'deleted_at': updated,
  });
  await _insert(database, 'local_tasks', task('task-orphan', 'goal-gone'));
  await _insert(database, 'local_tasks', {
    ...task('task-b', 'goal-b'),
    'user_id': 'user-b',
  });

  Map<String, Object?> card({
    required String id,
    required String name,
    required int isInTree,
    String? parentId,
    required String state,
    int activeLevel = 0,
    int? deletedAt,
    String? exceptionNotes,
  }) => {
    'user_id': 'user-a',
    'id': id,
    'name': name,
    'trigger_condition': '条件$id',
    'action': '动作$id',
    'scope': null,
    'exception_notes': exceptionNotes,
    'is_in_tree': isInTree,
    'parent_id': parentId,
    'state': state,
    'successful_days': 5,
    'current_consecutive_days': 3,
    'best_consecutive_days': 4,
    'maintenance_cycle_started': 1,
    'failure_reason': '漏确认',
    'cascade_source_card_id': 'card-lib',
    'cascade_prior_state': 'lit',
    'review_disposition': 'accepted',
    'active_strengthening_level': activeLevel == 0 ? null : activeLevel,
    'created_at': created,
    'updated_at': updated,
    'deleted_at': deletedAt,
  };
  await _insert(
    database,
    'local_national_focus_cards',
    card(
        id: 'card-root',
        name: '根国策',
        isInTree: 1,
        state: 'lit',
        activeLevel: 2,
      )
      ..['trigger_condition'] = '打开待办清单'
      ..['action'] = '先写第一步'
      ..['scope'] = '工作',
  );
  await _insert(
    database,
    'local_national_focus_cards',
    card(
      id: 'card-child',
      name: '子国策',
      isInTree: 1,
      parentId: 'card-root',
      state: 'pending_today_confirmation',
      activeLevel: 9,
      exceptionNotes: '有例外',
    ),
  );
  await _insert(
    database,
    'local_national_focus_cards',
    card(id: 'card-lib', name: '库国策', isInTree: 0, state: 'extinguished'),
  );
  await _insert(
    database,
    'local_national_focus_cards',
    card(
      id: 'card-deleted',
      name: '已删除国策',
      isInTree: 0,
      state: 'lit',
      deletedAt: updated,
    ),
  );
  await _insert(database, 'local_national_focus_cards', {
    'user_id': 'user-b',
    'id': 'card-b',
    'name': '其他用户国策',
    'trigger_condition': '条件',
    'action': '动作',
    'scope': null,
    'exception_notes': null,
    'is_in_tree': 1,
    'parent_id': null,
    'state': 'lit',
    'successful_days': 9,
    'current_consecutive_days': 2,
    'best_consecutive_days': 2,
    'maintenance_cycle_started': 1,
    'failure_reason': null,
    'cascade_source_card_id': null,
    'cascade_prior_state': null,
    'review_disposition': 'accepted',
    'active_strengthening_level': null,
    'created_at': created,
    'updated_at': updated,
    'deleted_at': null,
  });

  Map<String, Object?> level(String cardId, int number, String? trigger) => {
    'user_id': 'user-a',
    'card_id': cardId,
    'level_number': number,
    'trigger_condition_override': trigger,
    'action_override': null,
    'created_at': created,
    'updated_at': updated,
  };
  await _insert(
    database,
    'local_national_focus_strengthening_levels',
    level('card-root', 2, '强化条件'),
  );
  await _insert(
    database,
    'local_national_focus_strengthening_levels',
    level('card-lib', 1, '库强化'),
  );
  await _insert(
    database,
    'local_national_focus_strengthening_levels',
    level('card-deleted', 1, '已删强化'),
  );

  Map<String, Object?> version(String id, String cardId, int number) => {
    'user_id': 'user-a',
    'id': id,
    'card_id': cardId,
    'version_number': number,
    'strengthening_level_number': null,
    'effective_trigger_condition': '旧条件',
    'effective_action': '旧动作',
    'scope': null,
    'exception_notes': null,
    'effective_from': created,
    'effective_until': updated,
  };
  await _insert(
    database,
    'local_national_focus_requirement_versions',
    version('ver-root-1', 'card-root', 1),
  );
  await _insert(database, 'local_national_focus_requirement_versions', {
    ...version('ver-root-2', 'card-root', 2),
    'strengthening_level_number': 2,
    'effective_trigger_condition': '强化条件',
    'effective_action': '先写第一步',
    'scope': '工作',
    'effective_until': null,
  });
  await _insert(database, 'local_national_focus_requirement_versions', {
    ...version('ver-lib-1', 'card-lib', 1),
    'strengthening_level_number': 1,
    'effective_until': null,
  });
  await _insert(database, 'local_national_focus_requirement_versions', {
    ...version('ver-deleted-1', 'card-deleted', 1),
    'effective_until': null,
  });

  await _insert(database, 'local_national_focus_maintenance', {
    'user_id': 'user-a',
    'last_settled_checkpoint_at': updated,
  });
  await _insert(database, 'local_national_focus_failures', {
    'user_id': 'user-a',
    'id': 'failure-1',
    'batch_id': 'batch-1',
    'card_id': 'card-root',
    'checkpoint_at': updated,
    'cause': 'missed_confirmation',
    'failure_reason': '漏确认',
    'shared_explanation': null,
    'tree_snapshot': '[]',
    'review_disposition': 'accepted',
    'reviewed_at': null,
  });

  await _insert(database, 'focus_appointments', {
    'user_id': 'user-a',
    'id': 'appointment-1',
    'task_id': 'task-keep',
    'mode': 'regular',
    'duration_seconds': 1500,
    'started_at': appointmentStart,
    'ends_at': appointmentStart + 1500,
    'status': 'completed',
    'settled_at': appointmentStart + 1500,
    'session_id': 'session-1',
    'failure_reason': null,
    'updated_at': updated,
    'review_disposition': 'accepted',
    'review_disposition_updated_at': null,
    'configuration_basis_source_id': null,
    'preparation_seconds': 600,
  });
  await _insert(database, 'focus_sessions', {
    'user_id': 'user-a',
    'id': 'session-1',
    'appointment_id': 'appointment-1',
    'task_id': 'task-keep',
    'mode': 'regular',
    'duration_seconds': 1500,
    'started_at': appointmentStart,
    'ends_at': appointmentStart + 1500,
    'status': 'completed',
    'completed_at': appointmentStart + 1500,
    'effective_seconds': 1500,
    'completion_type': 'countdown',
    'completion_rule_text': null,
    'paused_at': null,
    'paused_seconds': 0,
    'pause_rule_text': null,
    'failure_reason': null,
    'effective_intervals': '[]',
    'review_disposition': 'accepted',
    'review_disposition_updated_at': null,
    'configuration_basis_source_id': null,
    'outcome_basis_source_id': null,
  });
  await _insert(database, 'focus_nodes', {
    'user_id': 'user-a',
    'id': 'node-1',
    'session_id': 'session-1',
    'task_id': 'task-keep',
    'mode': 'regular',
    'created_at': appointmentStart,
    'effective_seconds': 1500,
    'note': null,
  });
  await _insert(database, 'focus_chain_records', {
    'user_id': 'user-a',
    'mode': 'regular',
    'current_consecutive': 2,
    'best_consecutive': 3,
    'updated_at': updated,
  });
  await _insert(database, 'appointment_chain_records', {
    'user_id': 'user-a',
    'current_consecutive': 1,
    'best_consecutive': 2,
    'updated_at': updated,
  });
  await _insert(database, 'focus_sync_sources', {
    'user_id': 'user-a',
    'source_id': 'source-sync-1',
    'device_id': 'device-a',
    'entity_type': 'task',
    'entity_id': 'task-keep',
    'parent_source_id': null,
    'parent_source_ids': '[]',
    'occurred_at': updated,
    'payload': '{}',
  });
  await _insert(database, 'chain_signals', {
    'user_id': 'user-a',
    'appointment_trigger_signal': '预约信号',
    'elite_focus_marker': '精英信号',
    'regular_focus_marker': '常规信号',
    'updated_at': updated,
  });
  await _insert(database, 'focus_precedent_rules', {
    'user_id': 'user-a',
    'id': 'rule-active',
    'rule_text': '有效下必为例',
    'created_at': created,
    'updated_at': updated,
    'deleted_at': null,
  });
  await _insert(database, 'focus_precedent_rules', {
    'user_id': 'user-a',
    'id': 'rule-deleted',
    'rule_text': '已删除下必为例',
    'created_at': created,
    'updated_at': updated,
    'deleted_at': updated,
  });
  await _insert(database, 'local_calendar_sources', {
    'user_id': 'user-a',
    'source_id': 'source-1',
    'display_name': '工作日历',
    'time_zone_id': 'Asia/Shanghai',
    'local_calendar_id': 'cal-1',
    'is_selected': 1,
    'is_stale': 0,
    'is_deleted': 0,
    'updated_at': updated,
  });
  await _insert(database, 'local_calendar_blocks', {
    'user_id': 'user-a',
    'source_id': 'source-1',
    'source_event_id': 'event-1',
    'occurrence_id': 'occurrence-1',
    'event_identity': 'identity-1',
    'title': '导入事件',
    'starts_at': appointmentStart,
    'ends_at': appointmentStart + 3600,
    'all_day': 0,
    'all_day_start_date': null,
    'all_day_end_date_exclusive': null,
    'availability': 'busy',
    'time_zone_id': 'Asia/Shanghai',
    'updated_at': updated,
  });
  await _insert(database, 'local_schedule_recurrences', {
    'user_id': 'user-a',
    'id': 'recurrence-1',
    'frequency': 'daily',
    'weekdays': '[]',
    'first_date': '2026-11-05',
    'end_date': null,
    'time_zone_id': 'Asia/Shanghai',
    'all_day': 0,
    'start_minutes_of_day': 540,
    'duration_minutes': 60,
    'day_span': 1,
    'shift_days': 0,
    'title': '重复日程',
    'notes': '',
    'task_id': 'task-keep',
    'reminder_minutes_before': 15,
    'created_at': created,
    'updated_at': updated,
  });
  await _insert(database, 'local_schedules', {
    'user_id': 'user-a',
    'id': 'schedule-1',
    'title': '日程',
    'notes': '',
    'starts_at': appointmentStart,
    'ends_at': appointmentStart + 3600,
    'all_day': 0,
    'all_day_start_date': null,
    'all_day_end_date_exclusive': null,
    'is_completed': 0,
    'completed_at': null,
    'task_id': 'task-keep',
    'reminder_minutes_before': 15,
    'origin': 'owned',
    'source_ids': '[]',
    'source_names': '[]',
    'source_event_id': null,
    'occurrence_id': null,
    'event_identity': null,
    'recurrence_id': 'recurrence-1',
    'recurrence_series_id': 'series-1',
    'recurrence_date': '2026-11-05',
    'recurrence_time_zone_id': 'Asia/Shanghai',
    'recurrence_start_minutes': 540,
    'is_recurrence_exception': 0,
    'is_recurrence_cancelled': 0,
    'created_at': created,
    'updated_at': updated,
  });
}
