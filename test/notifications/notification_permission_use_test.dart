import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'the permission is requested once per device and recorded for the owner',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FocusDevicePreferencesStore(prefs, userId: 'user-a');
      await store.save(
        const FocusDevicePreferences(
          notificationsEnabled: true,
          backgroundRunningEnabled: false,
        ),
      );
      final service = _PermissionProbe();
      addTearDown(service.dispose);
      await service.setUserId('user-a');

      expect(await service.ensureNotificationPermissionForUse(), isTrue);
      expect(service.requestCalls, 1);
      expect((await store.load()).notificationPermissionRequested, isTrue);
      expect(
        (await store.load()).dailyOpenReminderMinutesAfterMidnight,
        9 * 60,
      );

      expect(await service.ensureNotificationPermissionForUse(), isTrue);
      expect(
        service.requestCalls,
        1,
        reason: 'A recorded decision must not prompt again.',
      );
    },
    skip: !Platform.isWindows,
  );

  test('concurrent user actions share one permission request', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = FocusDevicePreferencesStore(prefs, userId: 'user-a');
    await store.save(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
      ),
    );
    final service = _PermissionProbe()..gatePermission = true;
    addTearDown(service.dispose);
    await service.setUserId('user-a');

    final first = service.ensureNotificationPermissionForUse();
    await _settle();
    expect(service.requestCalls, 1);
    final second = service.ensureNotificationPermissionForUse();
    expect(await second, isFalse);
    service.completePermission(true);
    expect(await first, isTrue);

    expect(service.requestCalls, 1);
    expect((await store.load()).notificationPermissionRequested, isTrue);
  }, skip: !Platform.isWindows);

  test('a permission answered after a user switch is not recorded for the new '
      'user and leaves their settings intact', () async {
    final prefs = await SharedPreferences.getInstance();
    final userA = FocusDevicePreferencesStore(prefs, userId: 'user-a');
    final userB = FocusDevicePreferencesStore(prefs, userId: 'user-b');
    await userA.save(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
      ),
    );
    await userB.save(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
        dailyOpenReminderMinutesAfterMidnight: 7 * 60,
        dailyOpenReminderTimeChosen: true,
      ),
    );
    final service = _PermissionProbe()..gatePermission = true;
    addTearDown(service.dispose);
    await service.setUserId('user-a');

    final pending = service.ensureNotificationPermissionForUse();
    await _settle();
    expect(service.requestCalls, 1);
    await service.setUserId('user-b');
    service.completePermission(true);

    expect(await pending, isTrue);
    expect(
      (await userB.load()).notificationPermissionRequested,
      isFalse,
      reason: "The previous user's answer must not be written to the new one.",
    );
    expect(
      (await userB.load()).dailyOpenReminderMinutesAfterMidnight,
      7 * 60,
      reason: 'Other settings of the new user must stay untouched.',
    );
    expect((await userA.load()).notificationPermissionRequested, isFalse);
  }, skip: !Platform.isWindows);

  test(
    'a failing platform permission does not escape into the user action',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FocusDevicePreferencesStore(prefs, userId: 'user-a');
      await store.save(
        const FocusDevicePreferences(
          notificationsEnabled: true,
          backgroundRunningEnabled: false,
        ),
      );
      final service = _PermissionProbe()..permissionError = StateError('boom');
      addTearDown(service.dispose);
      await service.setUserId('user-a');

      expect(await service.ensureNotificationPermissionForUse(), isFalse);
      expect((await store.load()).notificationPermissionRequested, isFalse);
      expect(service.requestCalls, 1);
    },
    skip: !Platform.isWindows,
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _PermissionProbe extends FocusNotificationService {
  _PermissionProbe()
    : super(
        windowsChannel: const MethodChannel('issue95/permission_probe'),
        localTimeZone: () async => 'Asia/Shanghai',
      );

  int requestCalls = 0;
  bool allowed = false;
  bool gatePermission = false;
  Object? permissionError;
  Completer<bool>? _pending;

  @override
  Future<bool> notificationsAllowed() async => allowed;

  @override
  Future<bool> requestNotificationPermission() async {
    requestCalls++;
    final error = permissionError;
    if (error != null) throw error;
    if (!gatePermission) {
      allowed = true;
      return true;
    }
    final pending = Completer<bool>();
    _pending = pending;
    return pending.future;
  }

  void completePermission(bool value) {
    allowed = value;
    _pending?.complete(value);
    _pending = null;
  }
}
