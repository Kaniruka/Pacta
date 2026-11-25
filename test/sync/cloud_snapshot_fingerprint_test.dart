import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 旧实现的逐字复刻：整包深拷贝后归一化 focus_sessions 的区间字段。
///
/// 新的浅拷贝 + 后台 isolate 指纹必须与它逐字节一致；这里把它留作对照基线，
/// 任何归一化顺序、键序或重新编码的偏差都会让两个摘要分叉。
String legacyFingerprint(Map<String, dynamic> payload) {
  final normalized = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
  final tables = normalized['tables'];
  final sessions = tables is Map<String, dynamic>
      ? tables['focus_sessions']
      : null;
  if (sessions is List) {
    for (final row in sessions) {
      if (row is! Map<String, dynamic>) continue;
      final encoded = row['effective_intervals'];
      if (encoded is! String) continue;
      final decoded = jsonDecode(encoded);
      if (decoded is! List) continue;
      for (final interval in decoded) {
        if (interval is! Map<String, dynamic>) continue;
        interval
          ..remove('monotonic_checkpoint_microseconds')
          ..remove('last_observed_wall_time');
      }
      row['effective_intervals'] = jsonEncode(decoded);
    }
  }
  final value = jsonEncode(normalized);
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return 'v2:${hash.toRadixString(16).padLeft(16, '0')}';
}

void main() {
  late PactaDatabase database;
  late CloudSnapshotRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = CloudSnapshotRepository(
      database: database,
      remote: const UnavailableCloudSnapshotRemote(),
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
  });

  tearDown(() => database.close());

  Future<void> insertSession({
    required String id,
    required String intervals,
  }) => database.customStatement(
    'INSERT INTO focus_sessions (user_id, id, task_id, mode, duration_seconds, '
    'started_at, ends_at, status, effective_intervals) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'user-a',
      id,
      'task-1',
      'countdown',
      1500,
      1763251200,
      1763252700,
      'completed',
      intervals,
    ],
  );

  test('异步指纹与旧的整包深拷贝算法逐字一致', () async {
    await insertSession(
      id: 'session-1',
      intervals:
          '[{"start": "2026-11-25T00:00:00.000Z", '
          '"monotonic_checkpoint_microseconds": 171234, '
          '"last_observed_wall_time": 987654, '
          '"end": "2026-11-25T00:25:00.000Z"}]',
    );
    await insertSession(
      id: 'session-2',
      intervals:
          '[{"start":"2026-11-25T01:00:00.000Z","end":'
          '"2026-11-25T01:10:00.000Z"}]',
    );
    await insertSession(id: 'session-3', intervals: '[]');

    final state = await repository.captureLocalState();
    final expected = legacyFingerprint(state.payload);

    expect(state.fingerprint, expected, reason: 'Isolate.run 后的摘要必须与旧实现逐字一致');
    expect(
      repository.fingerprintOfPayload(state.payload),
      expected,
      reason: '同步指纹与异步指纹共用同一套归一化与摘要',
    );
    expect(state.fingerprint, startsWith('v2:'));
    // 旧实现直接对 Dart 有符号 64 位整数取十六进制，负摘要带前导 '-'；
    // 这里锁的是"逐字一致"，包括这条既有格式。
    expect(state.fingerprint.length, expected.length);
    expect(state.fingerprint, matches(RegExp(r'^v2:-?[0-9a-f]{15,16}$')));
  });

  test('大快照走后台 isolate，摘要仍与深拷贝基线一致', () async {
    // 超过 2000 行才会进入 Isolate.run 分支：纯 Dart test（非 FakeAsync）
    // 才能真实等待 OS isolate 的结果。
    for (var index = 0; index < 2100; index++) {
      await insertSession(
        id: 'bulk-session-$index',
        intervals:
            '[{"start":"2026-11-25T00:00:00.000Z","monotonic_checkpoint_microseconds":$index,"last_observed_wall_time":$index,"end":"2026-11-25T00:25:00.000Z"}]',
      );
    }
    final state = await repository.captureLocalState();
    expect(state.fingerprint, legacyFingerprint(state.payload));
  });
}
