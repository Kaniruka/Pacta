import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_page.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_calendar_provider.dart';

void main() {
  late PactaDatabase database;
  late InMemoryCalendarRemote remote;
  late LocalCalendarRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCalendarRemote();
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  testWidgets(
    'Windows states that reading the system calendar is unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarSourcesPage(
            repository: repository,
            isAndroid: false,
            displayTimeZoneIdLoader: () async => 'Etc/UTC',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Windows 暂不支持读取系统日历'), findsOneWidget);
      expect(find.text('导入系统日历'), findsNothing);
      expect(find.text('刷新本机日历'), findsNothing);
    },
  );

  testWidgets('Android offers the manual import entry and no refresh control', (
    tester,
  ) async {
    await repository.dispose();
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: FakeCalendarProvider(
        sources: const [],
        permission: CalendarPermissionState.granted,
      ),
      remote: remote,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarSourcesPage(
          repository: repository,
          isAndroid: true,
          displayTimeZoneIdLoader: () async => 'Etc/UTC',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导入系统日历'), findsOneWidget);
    expect(find.text('已允许读取日历'), findsOneWidget);
    expect(find.text('刷新本机日历'), findsNothing);
  });

  testWidgets('Board shows remote events and their merged busy occupancy', (
    tester,
  ) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 9).toUtc();
    await remote.upsertSources(
      userId: 'user-a',
      sources: const [
        CalendarSource(
          id: 'stable-source-id',
          displayName: '工作日历',
          timeZoneId: 'Asia/Shanghai',
        ),
      ],
    );
    await remote.upsertEvents(
      userId: 'user-a',
      events: [
        CalendarEventOccurrence(
          sourceId: 'stable-source-id',
          sourceEventId: 'meeting',
          occurrenceId: 'meeting:one',
          eventIdentity: 'meeting:one',
          title: '同步的活动',
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)),
          allDay: false,
          availability: CalendarAvailability.busy,
          timeZoneId: 'Asia/Shanghai',
        ),
        CalendarEventOccurrence(
          sourceId: 'stable-source-id',
          sourceEventId: 'meeting-two',
          occurrenceId: 'meeting:two',
          eventIdentity: 'meeting:two',
          title: '重叠活动',
          startsAt: start.add(const Duration(minutes: 30)),
          endsAt: start.add(const Duration(minutes: 90)),
          allDay: false,
          availability: CalendarAvailability.unknown,
          timeZoneId: 'Asia/Shanghai',
        ),
      ],
    );
    await repository.sync();

    await tester.pumpWidget(
      MaterialApp(home: CalendarAgendaCard(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('同步的活动'), findsOneWidget);
    expect(find.text('重叠活动'), findsOneWidget);
    expect(find.text('今日占用 1 小时 30 分钟'), findsOneWidget);
  });

  testWidgets('全天源日期跨越不同时区的瞬时时间仍保持不变', (tester) async {
    final today = DateTime.now();
    final date =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final sourceMidnightUtc = DateTime.utc(today.year, today.month, today.day);
    await remote.upsertSources(
      userId: 'user-a',
      sources: const [
        CalendarSource(
          id: 'source-kiritimati',
          displayName: '太平洋东部',
          timeZoneId: 'Pacific/Kiritimati',
        ),
        CalendarSource(
          id: 'source-pago-pago',
          displayName: '太平洋西部',
          timeZoneId: 'Pacific/Pago_Pago',
        ),
      ],
    );
    await remote.upsertEvents(
      userId: 'user-a',
      events: [
        CalendarEventOccurrence(
          sourceId: 'source-kiritimati',
          sourceEventId: 'holiday-east',
          occurrenceId: 'holiday-east:$date',
          eventIdentity: 'holiday-east:$date',
          title: '东部全天样例',
          startsAt: sourceMidnightUtc.subtract(const Duration(hours: 14)),
          endsAt: sourceMidnightUtc.add(const Duration(hours: 10)),
          allDay: true,
          allDayStartDate: date,
          allDayEndDateExclusive: DateTime.utc(
            today.year,
            today.month,
            today.day + 1,
          ).toIso8601String().substring(0, 10),
          availability: CalendarAvailability.busy,
          timeZoneId: 'Pacific/Kiritimati',
        ),
        CalendarEventOccurrence(
          sourceId: 'source-pago-pago',
          sourceEventId: 'holiday-west',
          occurrenceId: 'holiday-west:$date',
          eventIdentity: 'holiday-west:$date',
          title: '西部全天样例',
          startsAt: sourceMidnightUtc.add(const Duration(hours: 11)),
          endsAt: sourceMidnightUtc.add(const Duration(hours: 35)),
          allDay: true,
          allDayStartDate: date,
          allDayEndDateExclusive: DateTime.utc(
            today.year,
            today.month,
            today.day + 1,
          ).toIso8601String().substring(0, 10),
          availability: CalendarAvailability.busy,
          timeZoneId: 'Pacific/Pago_Pago',
        ),
      ],
    );
    await repository.sync();

    await tester.pumpWidget(
      MaterialApp(home: CalendarAgendaCard(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('东部全天样例'), findsOneWidget);
    expect(find.text('西部全天样例'), findsOneWidget);
    expect(find.textContaining('$date · 全天'), findsNWidgets(2));
    expect(find.text('今日占用 0 分钟'), findsOneWidget);
  });

  testWidgets('未授权日历时说明原因并保留核心功能提示', (tester) async {
    await repository.dispose();
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: FakeCalendarProvider(
        sources: const [],
        permission: CalendarPermissionState.denied,
      ),
      remote: remote,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarSourcesPage(
          repository: repository,
          isAndroid: true,
          displayTimeZoneIdLoader: () async => 'Etc/UTC',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设备日历权限已关闭'), findsOneWidget);
    expect(find.textContaining('其他功能'), findsOneWidget);
    expect(find.text('导入系统日历'), findsOneWidget);
  });

  testWidgets('Windows keeps synced cache visible without a refresh control', (
    tester,
  ) async {
    await remote.upsertSources(
      userId: 'user-a',
      sources: const [
        CalendarSource(
          id: 'stale-source',
          displayName: '未更新的日历',
          timeZoneId: 'Asia/Shanghai',
          isStale: true,
        ),
      ],
    );
    await repository.sync();

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarSourcesPage(
          repository: repository,
          isAndroid: false,
          displayTimeZoneIdLoader: () async => 'Etc/UTC',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows 暂不支持读取系统日历'), findsOneWidget);
    expect(find.text('刷新本机日历'), findsNothing);
    expect(find.text('日历数据未更新'), findsNothing);
  });

  testWidgets('撤销设备权限后保留缓存，且不再提供来源删除入口', (tester) async {
    await repository.dispose();
    final provider = FakeCalendarProvider(
      sources: const [
        CalendarSource(
          id: 'revoked-source',
          displayName: '权限撤销日历',
          timeZoneId: 'Asia/Shanghai',
          localCalendarId: '9',
        ),
      ],
      permission: CalendarPermissionState.granted,
      events: [
        CalendarEventOccurrence(
          sourceId: 'revoked-source',
          sourceEventId: 'event-one@example.com',
          occurrenceId: 'event-one@example.com@1',
          eventIdentity: 'event-one@example.com@1',
          title: '仍保留的缓存活动',
          startsAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          endsAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
          allDay: false,
          availability: CalendarAvailability.busy,
          timeZoneId: 'Asia/Shanghai',
        ),
      ],
    );
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: provider,
      remote: remote,
    );
    await repository.requestAccess();
    await repository.importCalendars({'revoked-source'});
    provider.permission = CalendarPermissionState.denied;

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarSourcesPage(
          repository: repository,
          isAndroid: true,
          displayTimeZoneIdLoader: () async => 'Etc/UTC',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设备日历权限已关闭'), findsOneWidget);
    expect(find.text('仍保留的缓存活动'), findsNothing);
    expect(find.text('确认撤权并移除所有来源'), findsNothing);
    expect(find.text('去系统设置开启日历权限'), findsOneWidget);
    expect(
      await database.select(database.localCalendarBlocks).get(),
      hasLength(1),
    );
  });
}
