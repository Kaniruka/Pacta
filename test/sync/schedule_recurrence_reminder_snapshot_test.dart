import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 重复提醒模板与实例覆盖都必须随整份业务快照往返，恢复后仍可继续懒展开。
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

  test('规则提醒与实例覆盖随快照往返，恢复后仍按模板懒展开', () async {
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
        draft: draft('每日', DateTime.utc(2026, 11, 16, 1)),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
        ),
        timeZoneId: 'Etc/UTC',
        reminderMinutesBefore: 30,
      );
      await schedulesA.setScheduleReminder(
        series.occurrences
            .firstWhere((schedule) => schedule.recurrenceDate == '2026-11-17')
            .id,
        minutesBefore: 15,
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

      final rules = await schedulesB.getRecurrenceRules();
      expect(rules.single.reminderMinutesBefore, 30);
      expect(rules.single.hasReminder, isTrue);
      expect(rules.single.title, '每日');

      final restored = await schedulesB.getSchedules(
        from: DateTime.utc(2026, 11, 16),
        to: DateTime.utc(2026, 11, 19),
      );
      expect(
        {
          for (final schedule in restored)
            schedule.recurrenceDate: schedule.reminderMinutesBefore,
        },
        {'2026-11-16': 30, '2026-11-17': 15, '2026-11-18': 30},
      );

      final expanded = await schedulesB.getSchedules(
        from: DateTime.utc(2027, 2, 20),
        to: DateTime.utc(2027, 2, 22),
      );
      expect(expanded.map((schedule) => schedule.reminderMinutesBefore), [
        30,
        30,
      ]);
    } finally {
      await schedulesA.dispose();
      await schedulesB.dispose();
      await deviceA.database.close();
      await deviceB.database.close();
    }
  });

  test('契约边界的规则与实例提醒（0、10080、null）都能往返', () async {
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
      await schedulesA.createRecurringSchedule(
        draft: draft('零分钟', DateTime.utc(2026, 11, 16, 1)),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
          endDate: '2026-11-16',
        ),
        timeZoneId: 'Etc/UTC',
        reminderMinutesBefore: 0,
      );
      await schedulesA.createRecurringSchedule(
        draft: draft('上边界', DateTime.utc(2026, 11, 16, 2)),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
          endDate: '2026-11-16',
        ),
        timeZoneId: 'Etc/UTC',
        reminderMinutesBefore: 10080,
      );
      await schedulesA.createRecurringSchedule(
        draft: draft('不提醒', DateTime.utc(2026, 11, 16, 3)),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
          endDate: '2026-11-16',
        ),
        timeZoneId: 'Etc/UTC',
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

      final rules = await schedulesB.getRecurrenceRules();
      expect(
        {for (final rule in rules) rule.title: rule.reminderMinutesBefore},
        {'零分钟': 0, '上边界': 10080, '不提醒': null},
      );
      final restored = await schedulesB.getSchedules(
        from: DateTime.utc(2026, 11, 16),
        to: DateTime.utc(2026, 11, 17),
      );
      expect(
        {
          for (final schedule in restored)
            schedule.title: schedule.reminderMinutesBefore,
        },
        {'零分钟': 0, '上边界': 10080, '不提醒': null},
      );
    } finally {
      await schedulesA.dispose();
      await schedulesB.dispose();
      await deviceA.database.close();
      await deviceB.database.close();
    }
  });
}
