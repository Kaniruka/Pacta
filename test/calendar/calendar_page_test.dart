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
