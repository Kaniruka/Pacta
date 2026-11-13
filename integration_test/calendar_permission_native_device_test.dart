import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart' show pactaTheme;
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/notifications/device_permission_gateway.dart';

const _expectDenied = bool.fromEnvironment('CALENDAR_EXPECT_DENIED');
const _openSettings = bool.fromEnvironment('CALENDAR_OPEN_SETTINGS');
const _permissionTimeout = Duration(minutes: 5);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'requests Android calendar permission through the system',
    (tester) async {
      final provider = const AndroidCalendarProvider();
      final permissionResult = Completer<CalendarPermissionState>();
      CalendarPermissionState? visibleState;

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(
            appBar: AppBar(title: const Text('日历权限验收')),
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(visibleState?.name ?? '等待操作'),
                    FilledButton(
                      onPressed: () async {
                        // Read only permission metadata; no calendars or events.
                        await provider.permissionStatus();
                        // ignore: avoid_print
                        print('CALENDAR_PERMISSION_OPENED');
                        try {
                          final state = await provider.requestPermission();
                          setState(() => visibleState = state);
                          permissionResult.complete(state);
                        } catch (error, stackTrace) {
                          permissionResult.completeError(error, stackTrace);
                        }
                      },
                      child: const Text('申请日历权限'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('申请日历权限'));
      await tester.pump();
      final state = await permissionResult.future.timeout(_permissionTimeout);

      // ignore: avoid_print
      print('CALENDAR_PERMISSION_RESULT ${state.name}');
      expect(
        state,
        _expectDenied
            ? CalendarPermissionState.denied
            : CalendarPermissionState.granted,
      );

      if (_openSettings) {
        await createDevicePermissionGateway().openAppSettings();
        // ignore: avoid_print
        print('CALENDAR_SETTINGS_OPENED; observe for 15 seconds');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 15)),
        );
      }
      // The action remains available after the permission result.
      expect(find.text('申请日历权限'), findsOneWidget);
      // ignore: avoid_print
      print('PASS');
    },
    timeout: const Timeout(_permissionTimeout),
    skip: !Platform.isAndroid,
  );
}
