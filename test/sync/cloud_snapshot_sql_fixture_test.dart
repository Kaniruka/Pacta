import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 探针 SQL 里嵌着的 v3 载荷必须就是客户端真实导出的形状。
///
/// 这里不再逐字比对 SQL 源码，也不镜像 PRAGMA 列名，而是走公共契约：
/// 把 fixture 通过 `InMemoryCloudSnapshotRemote` 上传，再用
/// `CloudSnapshotRepository.downloadCloud` 恢复，最后用公开的
/// `captureLocalState()` 再导出一次，往返结果必须与 fixture 完全一致。
/// 客户端恢复路径本身就是最严格的形状检查——fixture 不真实就会在此失败。
const _fixtureTag = r'$snapshot_v3_fixture$';
const _fixturePath = 'supabase/tests/cloud_snapshot_schema_v3.sql';
const _ownerPlaceholder = '__OWNER_ID__';
const _fixtureOwner = '11111111-2222-3333-4444-555555555555';

/// 客户端导出的一定是这些业务表，与顺序无关。
const _businessTables = <String>{
  'local_goals',
  'local_tasks',
  'local_national_focus_cards',
  'local_national_focus_strengthening_levels',
  'local_national_focus_requirement_versions',
  'local_national_focus_maintenance',
  'local_national_focus_failures',
  'focus_precedent_rules',
  'focus_appointments',
  'focus_sessions',
  'focus_nodes',
  'focus_chain_records',
  'appointment_chain_records',
  'chain_signals',
  'focus_sync_sources',
  'local_calendar_sources',
  'local_calendar_blocks',
  'local_schedules',
  'local_schedule_recurrences',
};

void main() {
  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late CloudSnapshotRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _fixtureOwner,
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
  });

  tearDown(() => database.close());

  test('公开 capture 导出的永远是同一组业务表', () async {
    final captured = (await repository.captureLocalState()).payload;
    expect(
      (captured['tables'] as Map).keys.cast<String>().toSet(),
      _businessTables,
    );
    expect(captured['schemaVersion'], cloudSnapshotSchemaVersion);
  });

  test('fixture 经公共恢复路径完整往返', () async {
    final fixture = _fixture();
    expect(fixture['userId'], _fixtureOwner);
    expect(fixture['schemaVersion'], cloudSnapshotSchemaVersion);
    expect(
      (fixture['tables'] as Map).keys.cast<String>().toSet(),
      _businessTables,
    );

    await remote.upload(
      userId: _fixtureOwner,
      expectedRevision: 0,
      payload: fixture,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: DateTime.utc(2026, 11, 15),
      rowCount: 3,
    );

    final before = await repository.captureLocalState();
    await repository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: before.fingerprint,
    );
    final after = await repository.captureLocalState();

    expect(after.payload['tables'], equals(fixture['tables']));
  });

  test('快照替换前拒绝公历之外的 0000 年日期', () async {
    final fixture = _fixture();
    final tables = fixture['tables'] as Map<String, dynamic>;
    final rules = tables['local_schedule_recurrences'] as List<dynamic>;
    (rules.single as Map<String, dynamic>)['first_date'] = '0000-01-01';
    await remote.upload(
      userId: _fixtureOwner,
      expectedRevision: 0,
      payload: fixture,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: DateTime.utc(2026, 11, 15),
      rowCount: 3,
    );
    final before = await repository.captureLocalState();
    await expectLater(
      repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: before.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('恢复后的星期集合仍是客户端写出的 JSON 文本', () async {
    final fixture = _fixture();
    await remote.upload(
      userId: _fixtureOwner,
      expectedRevision: 0,
      payload: fixture,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: DateTime.utc(2026, 11, 15),
      rowCount: 3,
    );
    final before = await repository.captureLocalState();
    await repository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: before.fingerprint,
    );
    final captured = (await repository.captureLocalState()).payload;
    final rules =
        (captured['tables'] as Map)['local_schedule_recurrences']
            as List<dynamic>;
    final weekdays = (rules.single as Map)['weekdays'];
    expect(weekdays, isA<String>());
    expect(jsonDecode(weekdays as String), <int>[1]);
  });
}

Map<String, dynamic> _fixture() {
  final sql = File(_fixturePath).readAsStringSync();
  final start = sql.indexOf(_fixtureTag);
  final end = sql.indexOf(_fixtureTag, start + _fixtureTag.length);
  if (start < 0 || end < 0) {
    throw StateError('SQL v3 probe is missing its json fixture block.');
  }
  final raw = sql
      .substring(start + _fixtureTag.length, end)
      .replaceAll(_ownerPlaceholder, _fixtureOwner);
  return jsonDecode(raw) as Map<String, dynamic>;
}
