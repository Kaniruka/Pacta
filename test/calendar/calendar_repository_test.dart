import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_calendar_provider.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late PactaDatabase database;
  late FakeCalendarProvider provider;
  late InMemoryCalendarRemote remote;
  late LocalCalendarRepository repository;
  Directory? temporaryDirectory;

  final now = DateTime.utc(2026, 9, 25, 8);
  final source = CalendarSource(
    id: 'source-work',
    displayName: '工作日历',
    timeZoneId: 'Asia/Shanghai',
    localCalendarId: '7',
  );

  CalendarEventOccurrence event({
    required String occurrenceId,
    required String identity,
    required String title,
    required DateTime start,
    required DateTime end,
    String? sourceId,
    String? sourceEventId,
    CalendarAvailability availability = CalendarAvailability.busy,
    bool allDay = false,
    String? allDayStartDate,
    String? allDayEndDateExclusive,
  }) => CalendarEventOccurrence(
    sourceId: sourceId ?? source.id,
    sourceEventId: sourceEventId ?? 'provider-event-$identity',
    occurrenceId: occurrenceId,
    eventIdentity: identity,
    title: title,
    startsAt: start,
    endsAt: end,
    allDay: allDay,
    allDayStartDate: allDayStartDate,
    allDayEndDateExclusive: allDayEndDateExclusive,
    availability: availability,
    timeZoneId: source.timeZoneId,
  );

  setUp(() {
    temporaryDirectory = null;
    database = PactaDatabase(NativeDatabase.memory());
    provider = FakeCalendarProvider(
      sources: [source],
      permission: CalendarPermissionState.granted,
    );
    remote = InMemoryCalendarRemote();
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: provider,
      remote: remote,
      now: () => now,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
    final directory = temporaryDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('导入只读活动、展开重复项并按忙碌区间并集计算占用', () async {
    provider.events = [
      event(
        occurrenceId: 'meeting:20260925T090000',
        identity: 'meeting:20260925T090000',
        title: '团队会议',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
      event(
        occurrenceId: 'meeting:20260926T090000',
        identity: 'meeting:20260926T090000',
        title: '团队会议',
        start: DateTime.utc(2026, 9, 25, 9, 30),
        end: DateTime.utc(2026, 9, 25, 10, 30),
        availability: CalendarAvailability.unknown,
      ),
      event(
        occurrenceId: 'free:20260925T103000',
        identity: 'free:20260925T103000',
        title: '自由时段',
        start: DateTime.utc(2026, 9, 25, 10, 30),
        end: DateTime.utc(2026, 9, 25, 11, 30),
        availability: CalendarAvailability.free,
      ),
      event(
        occurrenceId: 'holiday:20260925',
        identity: 'holiday:20260925',
        title: '全天提醒',
        start: DateTime.utc(2026, 9, 25),
        end: DateTime.utc(2026, 9, 26),
        allDay: true,
        allDayStartDate: '2026-09-25',
        allDayEndDateExclusive: '2026-09-26',
      ),
    ];

    final permission = await repository.requestAccess();
    expect(permission.permission, CalendarPermissionState.granted);
    await repository.importCalendars({source.id});
    await repository.importCalendars({source.id});

    final agenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );

    expect(agenda.blocks, hasLength(4));
    expect(agenda.occupiedDuration, const Duration(minutes: 90));
    final allDay = agenda.blocks.singleWhere((block) => block.allDay);
    expect(allDay.allDayStartDate, '2026-09-25');
    expect(allDay.allDayEndDateExclusive, '2026-09-26');
    expect(agenda.blocks.map((block) => block.title), contains('自由时段'));
  });

  test('日历刷新更新修改项并只移除已取消的重复发生次', () async {
    provider.events = [
      event(
        occurrenceId: 'weekly:20260925T090000',
        identity: 'weekly:20260925T090000',
        sourceEventId: 'weekly-meeting',
        title: '旧标题',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
      event(
        occurrenceId: 'weekly:20261002T090000',
        identity: 'weekly:20261002T090000',
        sourceEventId: 'weekly-meeting',
        title: '旧标题',
        start: DateTime.utc(2026, 10, 2, 9),
        end: DateTime.utc(2026, 10, 2, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});

    provider.events = [
      event(
        occurrenceId: 'weekly:20260925T090000',
        identity: 'weekly:20260925T090000',
        sourceEventId: 'weekly-meeting',
        title: '改期后的标题',
        start: DateTime.utc(2026, 9, 25, 11),
        end: DateTime.utc(2026, 9, 25, 12),
      ),
    ];
    await repository.sync();

    final agenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 10, 3),
    );
    expect(agenda.blocks, hasLength(1));
    expect(agenda.blocks.single.title, '改期后的标题');
    expect(agenda.blocks.single.startsAt, DateTime.utc(2026, 9, 25, 11));
    expect(agenda.blocks.single.occurrenceId, 'weekly:20260925T090000');
  });

  test('撤掉一个来源会同步删除，但同一活动的另一来源仍保留', () async {
    const secondSource = CalendarSource(
      id: 'source-personal',
      displayName: '个人日历',
      timeZoneId: 'Asia/Shanghai',
      localCalendarId: '8',
    );
    provider.sources.add(secondSource);
    provider.events = [
      event(
        occurrenceId: 'meeting:one',
        identity: 'meeting:one',
        sourceEventId: 'meeting',
        title: '同一活动',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
      event(
        sourceId: secondSource.id,
        occurrenceId: 'meeting:one',
        identity: 'meeting:one',
        sourceEventId: 'meeting',
        title: '同一活动',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id, secondSource.id});

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDevice = LocalCalendarRepository(
      database: secondDatabase,
      userId: 'user-a',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
      now: () => now,
    );
    addTearDown(secondDevice.dispose);
    addTearDown(secondDatabase.close);
    await secondDevice.sync();

    await repository.removeSources({source.id});
    await secondDevice.sync();

    final agenda = await secondDevice.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(agenda.blocks, hasLength(1));
    expect(agenda.blocks.single.sourceIds, [secondSource.id]);
  });

  test('系统日历读取失败时保留缓存并将来源状态同步为未更新', () async {
    provider.events = [
      event(
        occurrenceId: 'cached:one',
        identity: 'cached:one',
        title: '保留缓存',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});

    provider.failingReadSourceIds.add(source.id);
    await repository.sync();

    final localState = await repository.loadImportState();
    final localAgenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(localState.importedSources.single.isStale, isTrue);
    expect(localAgenda.isStale, isTrue);
    expect(localAgenda.blocks.single.title, '保留缓存');

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDevice = LocalCalendarRepository(
      database: secondDatabase,
      userId: 'user-a',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
      now: () => now,
    );
    addTearDown(secondDevice.dispose);
    addTearDown(secondDatabase.close);
    await secondDevice.sync();
    final remoteState = await secondDevice.loadImportState();
    final remoteAgenda = await secondDevice.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(remoteState.importedSources.single.isStale, isTrue);
    expect(remoteAgenda.isStale, isTrue);
    expect(remoteAgenda.blocks.single.title, '保留缓存');
  });

  test('撤销读取权限本身不会删除日历缓存', () async {
    provider.events = [
      event(
        occurrenceId: 'cached:permission-revoked',
        identity: 'cached:permission-revoked',
        title: '权限撤销后的缓存',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});
    provider.permission = CalendarPermissionState.denied;

    await repository.sync();

    final state = await repository.loadImportState();
    final agenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(state.permission, CalendarPermissionState.denied);
    expect(state.importedSources.single.isStale, isTrue);
    expect(agenda.blocks.single.title, '权限撤销后的缓存');
  });

  test('权限状态未知时保留已导入日历并标记未更新', () async {
    provider.events = [
      event(
        occurrenceId: 'cached:unknown',
        identity: 'cached:unknown',
        title: '权限未知时保留',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});
    provider.failPermissionCheck = true;

    final state = await repository.loadImportState();
    final agenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );

    expect(state.permission, CalendarPermissionState.unknown);
    expect(state.importedSources.single.isStale, isTrue);
    expect(agenda.isStale, isTrue);
    expect(agenda.blocks.single.title, '权限未知时保留');
  });

  test('平台返回未知权限状态时也保留缓存并标记未更新', () async {
    provider.events = [
      event(
        occurrenceId: 'cached:reported-unknown',
        identity: 'cached:reported-unknown',
        title: '平台未知权限时保留',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});
    provider.permission = CalendarPermissionState.unknown;

    final state = await repository.loadImportState();
    final agenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );

    expect(state.permission, CalendarPermissionState.unknown);
    expect(state.importedSources.single.isStale, isTrue);
    expect(agenda.isStale, isTrue);
    expect(agenda.blocks.single.title, '平台未知权限时保留');
  });

  test('离线时保留日历缓存并在连接恢复后完成同步', () async {
    provider.events = [
      event(
        occurrenceId: 'cached:offline',
        identity: 'cached:offline',
        title: '离线缓存活动',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});
    remote.available = false;

    await expectLater(repository.sync(), throwsStateError);

    final offlineState = await repository.loadImportState();
    final offlineAgenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(offlineState.importedSources.single.isStale, isTrue);
    expect(offlineAgenda.blocks.single.title, '离线缓存活动');
    expect(offlineAgenda.isStale, isTrue);

    remote.available = true;
    await repository.sync();
    expect((await repository.loadImportState()).hasPendingUpdates, isFalse);
  });

  test('拒绝日历权限会明确返回状态且不影响已有本地数据', () async {
    provider.permission = CalendarPermissionState.denied;

    final state = await repository.requestAccess();

    expect(state.permission, CalendarPermissionState.denied);
    expect(state.availableSources, isEmpty);
    expect(
      await repository.getAgenda(
        from: DateTime.utc(2026, 9, 25),
        to: DateTime.utc(2026, 9, 26),
      ),
      isA<CalendarAgenda>(),
    );
  });

  test('重新打开本机数据库后仍能读取已导入的日历块', () async {
    final directory = await Directory.systemTemp.createTemp('pacta-calendar-');
    temporaryDirectory = directory;
    final databasePath = '${directory.path}/calendar.sqlite';
    await repository.dispose();
    await database.close();
    database = PactaDatabase(NativeDatabase(File(databasePath)));
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: provider,
      remote: remote,
      now: () => now,
    );
    provider.events = [
      event(
        occurrenceId: 'saved:one',
        identity: 'saved:one',
        title: '重启后保留',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});

    await repository.dispose();
    await database.close();
    database = PactaDatabase(NativeDatabase(File(databasePath)));
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
      now: () => now,
    );

    final agenda = await repository.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(agenda.blocks.single.title, '重启后保留');
  });

  test('同步到第二设备后可读取相同来源和活动且不同用户互相隔离', () async {
    provider.events = [
      event(
        occurrenceId: 'event:one',
        identity: 'event:one',
        title: '只读活动',
        start: DateTime.utc(2026, 9, 25, 9),
        end: DateTime.utc(2026, 9, 25, 10),
      ),
    ];
    await repository.requestAccess();
    await repository.importCalendars({source.id});
    await repository.sync();

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDevice = LocalCalendarRepository(
      database: secondDatabase,
      userId: 'user-a',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
      now: () => now,
    );
    final otherUser = LocalCalendarRepository(
      database: secondDatabase,
      userId: 'user-b',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
      now: () => now,
    );
    addTearDown(secondDevice.dispose);
    addTearDown(otherUser.dispose);
    addTearDown(secondDatabase.close);

    await secondDevice.sync();
    await otherUser.sync();

    final secondAgenda = await secondDevice.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    final isolatedAgenda = await otherUser.getAgenda(
      from: DateTime.utc(2026, 9, 25),
      to: DateTime.utc(2026, 9, 26),
    );
    expect(secondAgenda.blocks.single.title, '只读活动');
    expect(secondAgenda.blocks.single.sourceIds, contains(source.id));
    expect(isolatedAgenda.blocks, isEmpty);
  });
}
