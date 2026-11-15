import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 服务端 v3 迁移与探针共用的载荷 fixture 必须就是客户端真实导出的形状。
///
/// 探针 SQL 里嵌着同一份 JSON（`$snapshot_v3_fixture$` 之间），这里把它读回来，
/// 与真实 `CloudSnapshotRepository.captureLocalState()` 的导出逐表逐列比对：
/// 表集合必须完全一致；fixture 里出现的每一行必须带齐该表在 Drift 里的全部列
/// （客户端导出时逐列 SELECT，不会只写几个字段）。
const _fixtureTag = r'$snapshot_v3_fixture$';
const _fixturePath = 'supabase/tests/cloud_snapshot_schema_v3.sql';
const _migrationPath =
    'supabase/migrations/202611150003_cloud_snapshot_schema_v3.sql';
const _ownerPlaceholder = '__OWNER_ID__';
const _fixtureOwner = '11111111-2222-3333-4444-555555555555';

/// `local_calendar_sources` 的两列是本机设备事实，不随快照上传。
const _deviceOnlyCalendarColumns = {'local_calendar_id', 'is_selected'};

void main() {
  late PactaDatabase database;
  late CloudSnapshotRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = CloudSnapshotRepository(
      database: database,
      remote: InMemoryCloudSnapshotRemote(),
      userId: _fixtureOwner,
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
  });

  tearDown(() => database.close());

  test('探针 fixture 覆盖客户端导出的全部业务表', () async {
    final fixture = _fixture();
    final exported = (await repository.captureLocalState()).payload;

    expect(fixture['schemaVersion'], '3');
    expect(fixture['userId'], _fixtureOwner);

    final fixtureTables = (fixture['tables'] as Map).keys
        .cast<String>()
        .toSet();
    final exportedTables = (exported['tables'] as Map).keys
        .cast<String>()
        .toSet();
    expect(fixtureTables, exportedTables);
  });

  test('fixture 的每一行都带齐该表在客户端里的全部列', () async {
    final tables = _fixture()['tables'] as Map<String, dynamic>;
    for (final entry in tables.entries) {
      final rows = entry.value as List<dynamic>;
      final columns = await _columns(database, entry.key);
      final expected = entry.key == 'local_calendar_sources'
          ? columns.difference(_deviceOnlyCalendarColumns)
          : columns;
      for (final row in rows) {
        expect(
          (row as Map).keys.cast<String>().toSet(),
          expected,
          reason: entry.key,
        );
      }
    }
  });

  test('星期集合是客户端写出的 JSON 文本而不是 jsonb 数组', () {
    final rules =
        (_fixture()['tables'] as Map)['local_schedule_recurrences']
            as List<dynamic>;
    final weekdays = (rules.single as Map)['weekdays'];
    expect(weekdays, isA<String>());
    expect(jsonDecode(weekdays as String), <int>[1]);
  });

  test('迁移按客户端文本形状严格校验星期集合', () {
    final sql = File(_migrationPath).readAsStringSync();
    expect(sql, contains('cloud_snapshot_weekday_values'));
    expect(sql, isNot(contains("jsonb_typeof(rule -> 'weekdays') = 'array'")));
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

Future<Set<String>> _columns(PactaDatabase database, String table) async {
  final info = await database.customSelect('PRAGMA table_info("$table")').get();
  return info.map((row) => row.read<String>('name')).toSet();
}
