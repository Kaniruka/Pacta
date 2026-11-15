import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 一个可见日期的重复实例只能有一条，且计划页的订阅要看得见别的写入路径。
///
/// 这些用例都走公开 API：不 mock 展开算法，也不断言私有方法，只检查仓储在
/// 并发、多个仓储实例和整份快照替换之后对外呈现的结果。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('并发读取同一天只物化一条实例', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'concurrent-readers',
      now: () => DateTime.utc(2026, 11, 15),
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });
    await repository.createRecurringSchedule(
      draft: _dailyDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );

    final results = await Future.wait([
      for (var index = 0; index < 8; index++)
        repository.getSchedules(from: _farFrom, to: _farTo),
    ]);

    for (final rows in results) {
      expect(rows, hasLength(1), reason: '同一个可见日期只能有一条实例，即使多个观察者同时请求');
    }
    final ids = {for (final rows in results) rows.single.id};
    expect(ids, hasLength(1), reason: '并发读取必须看到同一身份，而不是各自生成的 UUID');
    expect(await _instanceRows(database), hasLength(1));
  });

  test('同一数据库的两个仓储实例并发读取仍只有一条实例', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final first = LocalScheduleRepository(
      database: database,
      userId: 'concurrent-readers',
      now: () => DateTime.utc(2026, 11, 15),
    );
    final second = LocalScheduleRepository(
      database: database,
      userId: 'concurrent-readers',
      now: () => DateTime.utc(2026, 11, 15),
    );
    addTearDown(() async {
      await first.dispose();
      await second.dispose();
      await database.close();
    });
    await first.createRecurringSchedule(
      draft: _dailyDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );

    final results = await Future.wait([
      for (var index = 0; index < 8; index++)
        (index.isEven ? first : second).getSchedules(
          from: _farFrom,
          to: _farTo,
        ),
    ]);

    for (final rows in results) {
      expect(rows, hasLength(1), reason: '跨仓储实例也一样：事务在数据库上，不在对象上');
    }
    expect(await _instanceRows(database), hasLength(1));
  });

  test('重复调用与显式展开都不会增加第二条实例', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'repeated-expansion',
      now: () => DateTime.utc(2026, 11, 15),
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });
    await repository.createRecurringSchedule(
      draft: _dailyDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );

    for (var round = 0; round < 5; round++) {
      expect(
        await repository.getSchedules(from: _farFrom, to: _farTo),
        hasLength(1),
      );
    }
    expect(await repository.expandRecurrences(from: _farFrom, to: _farTo), 0);
    expect(await repository.expandRecurrences(from: _farFrom, to: _farTo), 0);
    expect(await _instanceRows(database), hasLength(1));
  });

  test('并发展开后的结果能随整份账号快照往返', () async {
    final remote = InMemoryCloudSnapshotRemote();
    final source = PactaDatabase(NativeDatabase.memory());
    final sourceRepository = LocalScheduleRepository(
      database: source,
      userId: 'round-trip',
      now: () => DateTime.utc(2026, 11, 15),
    );
    final target = PactaDatabase(NativeDatabase.memory());
    final targetRepository = LocalScheduleRepository(
      database: target,
      userId: 'round-trip',
      now: () => DateTime.utc(2026, 11, 15, 2),
    );
    addTearDown(() async {
      await sourceRepository.dispose();
      await targetRepository.dispose();
      await source.close();
      await target.close();
    });
    await sourceRepository.createRecurringSchedule(
      draft: _dailyDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );
    final results = await Future.wait([
      for (var index = 0; index < 8; index++)
        sourceRepository.getSchedules(from: _farFrom, to: _farTo),
    ]);
    final identity = results.first.single;

    final sourceSnapshot = CloudSnapshotRepository(
      database: source,
      remote: remote,
      userId: 'round-trip',
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
    final captured = await sourceSnapshot.captureLocalState();
    final saved = await sourceSnapshot.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: captured.fingerprint,
    );

    final targetSnapshot = CloudSnapshotRepository(
      database: target,
      remote: remote,
      userId: 'round-trip',
      deviceId: 'device-b',
      deviceName: 'Tablet B',
    );
    final local = await targetSnapshot.captureLocalState();
    await targetSnapshot.downloadCloud(
      expectedRevision: saved.revision,
      expectedFingerprint: local.fingerprint,
    );

    final restored = await targetRepository.getSchedules(
      from: _farFrom,
      to: _farTo,
    );
    expect(restored, hasLength(1));
    expect(restored.single.id, identity.id);
    expect(restored.single.recurrenceDate, '2027-05-01');
    expect(restored.single.recurrenceSeriesId, identity.recurrenceSeriesId);
    expect(await _instanceRows(target), hasLength(1));
  });

  test('另一个仓储实例写入会通知已有订阅', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final watcher = LocalScheduleRepository(
      database: database,
      userId: 'watch-cross-repo',
      now: () => DateTime.utc(2026, 11, 15),
    );
    final writer = LocalScheduleRepository(
      database: database,
      userId: 'watch-cross-repo',
      now: () => DateTime.utc(2026, 11, 15),
    );
    addTearDown(() async {
      await watcher.dispose();
      await writer.dispose();
      await database.close();
    });

    final emissions = <List<Schedule>>[];
    final subscription = watcher.watchSchedules().listen(emissions.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(emissions, hasLength(1));

    await writer.createSchedule(_draft(title: '另一个实例写入'));
    await pumpEventQueue();
    expect(emissions.last.map((schedule) => schedule.title), [
      '另一个实例写入',
    ], reason: '订阅边界必须是数据库，而不是某个仓储对象的写入口');
  });

  test('整份快照恢复后订阅看到新安排、旧安排消失', () async {
    final remote = InMemoryCloudSnapshotRemote();
    final local = PactaDatabase(NativeDatabase.memory());
    final localRepository = LocalScheduleRepository(
      database: local,
      userId: 'watch-restore',
      now: () => DateTime.utc(2026, 11, 15),
    );
    final cloud = PactaDatabase(NativeDatabase.memory());
    final cloudRepository = LocalScheduleRepository(
      database: cloud,
      userId: 'watch-restore',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    addTearDown(() async {
      await localRepository.dispose();
      await cloudRepository.dispose();
      await local.close();
      await cloud.close();
    });

    await localRepository.createSchedule(_draft(title: '本机旧安排'));
    await cloudRepository.createSchedule(
      _draft(title: '云端新安排', startsAt: DateTime.utc(2026, 11, 17, 9)),
    );
    final cloudSnapshot = CloudSnapshotRepository(
      database: cloud,
      remote: remote,
      userId: 'watch-restore',
      deviceId: 'device-cloud',
      deviceName: 'Cloud',
    );
    final cloudState = await cloudSnapshot.captureLocalState();
    final saved = await cloudSnapshot.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: cloudState.fingerprint,
    );

    final emissions = <List<Schedule>>[];
    final subscription = localRepository
        .watchSchedules(
          from: DateTime.utc(2026, 11, 1),
          to: DateTime.utc(2026, 11, 30),
        )
        .listen(emissions.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(emissions.last.map((schedule) => schedule.title), ['本机旧安排']);

    final localSnapshot = CloudSnapshotRepository(
      database: local,
      remote: remote,
      userId: 'watch-restore',
      deviceId: 'device-local',
      deviceName: 'Local',
    );
    final localState = await localSnapshot.captureLocalState();
    await localSnapshot.downloadCloud(
      expectedRevision: saved.revision,
      expectedFingerprint: localState.fingerprint,
    );
    await pumpEventQueue();

    expect(emissions.last.map((schedule) => schedule.title), [
      '云端新安排',
    ], reason: '公开快照恢复是整份事务替换，订阅必须重新读到替换后的内容');
    expect(emissions.last, hasLength(1));
  });

  test('取消订阅后不再推送，也不会因为迟到的查询结果复活旧值', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'watch-cancel',
      now: () => DateTime.utc(2026, 11, 15),
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });
    await repository.createSchedule(_draft(title: '取消前'));

    final emissions = <List<Schedule>>[];
    final subscription = repository.watchSchedules().listen(emissions.add);
    await pumpEventQueue();
    expect(emissions, hasLength(1));

    await subscription.cancel();
    await repository.createSchedule(_draft(title: '取消后'));
    await pumpEventQueue();
    expect(emissions, hasLength(1), reason: '取消订阅必须立即停止推送');
  });

  test('范围物化不会自触发成重复推送', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'watch-expansion',
      now: () => DateTime.utc(2026, 11, 15),
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });
    await repository.createRecurringSchedule(
      draft: _dailyDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );

    final emissions = <List<Schedule>>[];
    final subscription = repository
        .watchSchedules(from: _farFrom, to: _farTo)
        .listen(emissions.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    final settled = emissions.length;
    await pumpEventQueue();

    expect(emissions.length, settled, reason: '物化写入之后必须收敛，不能持续自触发');
    expect(settled, lessThanOrEqualTo(2), reason: '首帧之后最多再补一帧完整结果');
    expect(
      emissions
          .map((rows) => rows.map((schedule) => schedule.id).join(','))
          .toSet(),
      hasLength(emissions.length),
      reason: '相同结果不重复推送',
    );
    expect(emissions.last, hasLength(1));
    expect(await _instanceRows(database), hasLength(1));
  });

  test('与整份快照恢复交错时不会复活旧规则的实例', () async {
    final remote = InMemoryCloudSnapshotRemote();
    final local = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: local,
      userId: 'watch-restore-race',
      now: () => DateTime.utc(2026, 11, 15),
    );
    final cloud = PactaDatabase(NativeDatabase.memory());
    final cloudRepository = LocalScheduleRepository(
      database: cloud,
      userId: 'watch-restore-race',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    addTearDown(() async {
      await repository.dispose();
      await cloudRepository.dispose();
      await local.close();
      await cloud.close();
    });

    await repository.createRecurringSchedule(
      draft: _dailyDraft(),
      repeat: const ScheduleRepeatSpec(
        frequency: ScheduleRepeatFrequency.daily,
      ),
      timeZoneId: 'Etc/UTC',
    );
    // 云端的这份数据里没有重复规则，只有一条普通安排。
    await cloudRepository.createSchedule(
      _draft(title: '恢复后的安排', startsAt: DateTime.utc(2026, 11, 17, 9)),
    );
    final cloudSnapshot = CloudSnapshotRepository(
      database: cloud,
      remote: remote,
      userId: 'watch-restore-race',
      deviceId: 'device-cloud',
      deviceName: 'Cloud',
    );
    final cloudState = await cloudSnapshot.captureLocalState();
    final saved = await cloudSnapshot.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: cloudState.fingerprint,
    );

    // 恢复事务已写完业务行、尚未提交时发起一次远区间展开：它必须排在恢复之后
    // 执行，读到的只能是替换后的规则集合（空），不能拿旧规则去补实例。
    Future<List<Schedule>>? pendingExpansion;
    final localSnapshot = CloudSnapshotRepository(
      database: local,
      remote: remote,
      userId: 'watch-restore-race',
      deviceId: 'device-local',
      deviceName: 'Local',
      onRestoreStage: (stage) async {
        if (stage == CloudRestoreStage.afterReplacement) {
          // 恢复事务的 zone 会把数据库调用路由到它自己的连接；这里必须离开该
          // zone，让展开排在恢复事务之后（真实的跨事务交错），而不是加入它。
          pendingExpansion = Zone.root.run(
            () => repository.getSchedules(from: _farFrom, to: _farTo),
          );
        }
      },
    );
    final localState = await localSnapshot.captureLocalState();
    await localSnapshot.downloadCloud(
      expectedRevision: saved.revision,
      expectedFingerprint: localState.fingerprint,
    );
    final expansion = await pendingExpansion!;

    expect(expansion, isEmpty, reason: '旧规则已随整份替换消失，展开不能补出新实例');
    expect(await repository.getRecurrenceRules(), isEmpty);
    final visible = await repository.getSchedules(
      from: DateTime.utc(2026, 11, 1),
      to: DateTime.utc(2026, 11, 30),
    );
    expect(visible.map((schedule) => schedule.title), ['恢复后的安排']);
    expect(await _instanceRows(local), isEmpty);
  });
}

final _farFrom = DateTime.utc(2027, 5, 1);
final _farTo = DateTime.utc(2027, 5, 2);

ScheduleDraft _dailyDraft() => ScheduleDraft(
  title: '每日站立会',
  window: ScheduleWindow.timed(
    startsAt: DateTime.utc(2026, 11, 16, 9),
    endsAt: DateTime.utc(2026, 11, 16, 10),
  ),
);

ScheduleDraft _draft({required String title, DateTime? startsAt}) {
  final start = startsAt ?? DateTime.utc(2026, 11, 16, 9);
  return ScheduleDraft(
    title: title,
    window: ScheduleWindow.timed(
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    ),
  );
}

/// 指定可见日期上的实例行数（不经过仓储，只读同一数据库核对落库结果）。
Future<List<LocalSchedule>> _instanceRows(PactaDatabase database) =>
    (database.select(
      database.localSchedules,
    )..where((row) => row.recurrenceDate.equals('2027-05-01'))).get();
