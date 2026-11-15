import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// r3 复审的公开快照回归：分段改写后的墓碑必须能随整份快照往返，
/// 不可用的时区与不存在的日历日必须在替换本机数据之前整体拒绝。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late InMemoryCloudSnapshotRemote remote;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remote = InMemoryCloudSnapshotRemote();
  });

  ScheduleDraft draft(String title, DateTime start) => ScheduleDraft(
    title: title,
    window: ScheduleWindow.timed(
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    ),
  );

  Future<({PactaDatabase database, CloudSnapshotRepository snapshot})> device(
    String id,
    String name, {
    required DateTime now,
  }) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final snapshot = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: id,
      deviceName: name,
      now: () => now,
    );
    return (database: database, snapshot: snapshot);
  }

  test('分段改写留下的墓碑随整份快照完整往返', () async {
    final deviceA = await device(
      'device-a',
      'Phone A',
      now: DateTime.utc(2026, 11, 15, 3),
    );
    final schedulesA = LocalScheduleRepository(
      database: deviceA.database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 3),
    );
    final deviceB = await device(
      'device-b',
      'Tablet B',
      now: DateTime.utc(2026, 11, 15, 5),
    );
    final schedulesB = LocalScheduleRepository(
      database: deviceB.database,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 11, 15, 5),
    );
    try {
      final series = await schedulesA.createRecurringSchedule(
        draft: draft('每日', DateTime.utc(2026, 11, 16, 9)),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
        ),
        timeZoneId: 'Etc/UTC',
      );
      await schedulesA.deleteSchedule(
        series.occurrences
            .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-18')
            .id,
      );
      // 从首个实例改写：原规则被整体移除，墓碑必须改挂到接手的规则上。
      await schedulesA.editRecurringSchedule(
        series.occurrences
            .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-16')
            .id,
        draft: draft('改后', DateTime.utc(2026, 11, 16, 9)),
        scope: ScheduleRepeatScope.thisAndFuture,
      );

      final localA = await deviceA.snapshot.captureLocalState();
      final saved = await deviceA.snapshot.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: localA.fingerprint,
      );

      final localB = await deviceB.snapshot.captureLocalState();
      await deviceB.snapshot.downloadCloud(
        expectedRevision: saved.revision,
        expectedFingerprint: localB.fingerprint,
      );

      final restored = await schedulesB.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 21),
      );
      expect(restored.map((schedule) => schedule.title), [
        '改后',
        '改后',
        '改后',
        '改后',
      ]);
      expect(restored.map((schedule) => schedule.recurrenceDate), [
        '2026-11-16',
        '2026-11-17',
        '2026-11-19',
        '2026-11-20',
      ]);
      final rules = await schedulesB.getRecurrenceRules();
      expect(rules, hasLength(1));
      expect(rules.single.title, '改后');
      expect(rules.single.shiftDays, 0);
    } finally {
      await schedulesA.dispose();
      await schedulesB.dispose();
      await deviceA.database.close();
      await deviceB.database.close();
    }
  });

  test('快照拒绝不可用的重复时区且不改动本机', () async {
    await _expectRejectedPayload(
      remote: remote,
      deviceFactory: device,
      draft: draft,
      tamper: (payload) {
        for (final row
            in (payload['tables'] as Map)['local_schedule_recurrences']
                as List) {
          (row as Map)['time_zone_id'] = 'Mars/Olympus';
        }
        for (final row
            in (payload['tables'] as Map)['local_schedules'] as List) {
          if ((row as Map)['recurrence_id'] != null) {
            row['recurrence_time_zone_id'] = 'Mars/Olympus';
          }
        }
      },
    );
  });

  for (final cancelledDuplicate in [0, 1]) {
    test('快照拒绝同一原始身份但不同行 id 的副本（墓碑标记 $cancelledDuplicate）', () async {
      await _expectRejectedPayload(
        remote: remote,
        deviceFactory: device,
        draft: draft,
        tamper: (payload) {
          final rows = (payload['tables'] as Map)['local_schedules'] as List;
          final original = rows.firstWhere(
            (row) => (row as Map)['recurrence_date'] == '2026-11-17',
          ) as Map;
          rows.add({
            ...original,
            'id': 'duplicate-$cancelledDuplicate',
            'is_recurrence_cancelled': cancelledDuplicate,
          });
        },
      );
    });
  }

  test('快照拒绝顺移的日历日且不改动本机', () async {
    await _expectRejectedPayload(
      remote: remote,
      deviceFactory: device,
      draft: draft,
      tamper: (payload) {
        for (final row
            in (payload['tables'] as Map)['local_schedule_recurrences']
                as List) {
          (row as Map)['first_date'] = '2026-02-30';
        }
        for (final row
            in (payload['tables'] as Map)['local_schedules'] as List) {
          if ((row as Map)['recurrence_id'] != null) {
            row['recurrence_date'] = '2026-02-30';
          }
        }
      },
    );
  });
}

typedef _DeviceFactory =
    Future<({PactaDatabase database, CloudSnapshotRepository snapshot})>
    Function(String id, String name, {required DateTime now});

Future<void> _expectRejectedPayload({
  required InMemoryCloudSnapshotRemote remote,
  required _DeviceFactory deviceFactory,
  required ScheduleDraft Function(String title, DateTime start) draft,
  required void Function(Map<String, dynamic> payload) tamper,
}) async {
  final deviceA = await deviceFactory(
    'device-a',
    'Phone A',
    now: DateTime.utc(2026, 11, 15, 3),
  );
  final schedulesA = LocalScheduleRepository(
    database: deviceA.database,
    userId: 'user-a',
    now: () => DateTime.utc(2026, 11, 15, 3),
  );
  final deviceB = await deviceFactory(
    'device-b',
    'Tablet B',
    now: DateTime.utc(2026, 11, 15, 5),
  );
  final schedulesB = LocalScheduleRepository(
    database: deviceB.database,
    userId: 'user-a',
    now: () => DateTime.utc(2026, 11, 15, 5),
  );
  try {
    await schedulesA.createRecurringSchedule(
      draft: draft('每日', DateTime.utc(2026, 11, 16, 9)),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );
    final keep = await schedulesB.createSchedule(
      draft('本机日程', DateTime.utc(2026, 11, 17, 9)),
    );

    final localA = await deviceA.snapshot.captureLocalState();
    final saved = await deviceA.snapshot.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: localA.fingerprint,
    );
    final payload =
        jsonDecode(jsonEncode(saved.payload)) as Map<String, dynamic>;
    tamper(payload);
    await remote.upload(
      userId: 'user-a',
      expectedRevision: saved.revision,
      payload: payload,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: localA.dataUpdatedAt,
      rowCount: saved.rowCount,
    );

    final localB = await deviceB.snapshot.captureLocalState();
    await expectLater(
      deviceB.snapshot.downloadCloud(
        expectedRevision: saved.revision + 1,
        expectedFingerprint: localB.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );

    // 拒绝对本机是原子的：原有日程仍在，也没有导入任何规则。
    final surviving = await schedulesB.getSchedules();
    expect(surviving.map((schedule) => schedule.id), [keep.id]);
    expect(await schedulesB.getRecurrenceRules(), isEmpty);
  } finally {
    await schedulesA.dispose();
    await schedulesB.dispose();
    await deviceA.database.close();
    await deviceB.database.close();
  }
}
