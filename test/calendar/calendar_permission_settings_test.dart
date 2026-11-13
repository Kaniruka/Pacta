import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_page.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/notifications/device_permission_gateway.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_calendar_provider.dart';

void main() {
  late PactaDatabase database;
  late LocalCalendarRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalCalendarRepository(
      database: database,
      userId: 'user-a',
      provider: FakeCalendarProvider(
        sources: const [],
        permission: CalendarPermissionState.denied,
      ),
      remote: InMemoryCalendarRemote(),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  testWidgets(
    'a denied calendar permission still reaches the system settings',
    (tester) async {
      final gateway = _RecordingPermissionGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarSourcesPage(
            repository: repository,
            isAndroid: true,
            permissionGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('日历权限尚未开启'), findsOneWidget);
      final settingsButton = find.byKey(
        const Key('calendar-open-system-settings'),
      );
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(gateway.appSettingsOpened, 1);
    },
  );
}

class _RecordingPermissionGateway implements DevicePermissionGateway {
  int appSettingsOpened = 0;

  @override
  Future<void> openAppSettings() async {
    appSettingsOpened++;
  }

  @override
  Future<void> openNotificationSettings() async {}
}
