import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 合并后的页面更长：用高视口让三组设置同时参与布局。
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(page);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'National Focus reminder settings default to Beijing 22:00 and persist opt-out',
    (tester) async {
      const channel = MethodChannel('ticket_23/reminder_settings');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = FocusNotificationService(
        preferencesStore: FocusDevicePreferencesStore(
          await SharedPreferences.getInstance(),
        ),
        windowsChannel: channel,
      );
      addTearDown(() async {
        await service.clear();
        await service.dispose();
      });

      await _pumpPage(
        tester,
        MaterialApp(home: FocusNotificationSettingsPage(service: service)),
      );

      expect(find.text('国策待确认提醒'), findsOneWidget);
      expect(find.text('提醒时间（北京时间）'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
      final switchTile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('国策待确认提醒'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(switchTile.value, isTrue);

      await tester.tap(find.text('国策待确认提醒'));
      await tester.pumpAndSettle();

      expect(
        (await service.getPreferences()).nationalFocusReminderEnabled,
        isFalse,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.ancestor(
                of: find.text('国策待确认提醒'),
                matching: find.byType(SwitchListTile),
              ),
            )
            .value,
        isFalse,
      );
    },
    skip: !Platform.isWindows,
  );
}
