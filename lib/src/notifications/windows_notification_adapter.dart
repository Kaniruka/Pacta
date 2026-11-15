import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as timezone;

/// The Windows platform boundary used by [FocusNotificationService].
///
/// The production adapter wraps the already locked
/// `flutter_local_notifications_windows` plugin so notifications are registered
/// with the OS scheduler instead of an in-process timer: they must survive a
/// normal process exit. Tests inject a fake adapter at this seam.
abstract interface class WindowsNotificationAdapter {
  /// Registers this app's AUMID and the click callback, and returns whether the
  /// OS accepted the registration.
  Future<bool> initialize({DidReceiveNotificationResponseCallback? onResponse});

  /// Registers one one-shot notification at [at].
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  });

  Future<void> cancel(int id);

  /// Ids the OS still holds for this app, used to cancel stale reminders after
  /// a restart without trusting in-memory bookkeeping.
  Future<List<int>> pendingIds();

  Future<void> dispose();
}

/// Stable product identity for the Windows notification registration.
///
/// The identity is a distribution concern, not a business value: reminders use
/// the same registration whether the app was started from a bundle or a
/// shortcut. A test fixture overrides it so it never shares the product's
/// notification registration.
class WindowsNotificationIdentity {
  const WindowsNotificationIdentity({
    this.appName = 'Pacta',
    this.appUserModelId = 'Pacta.Desktop.Focus',
    this.guid = '6f1a3c2e-8d4b-4f7a-9c21-3a5d7e9b4c60',
  });

  final String appName;
  final String appUserModelId;
  final String guid;
}

/// Production adapter over the locked Windows plugin.
class LocalNotificationsWindowsAdapter implements WindowsNotificationAdapter {
  LocalNotificationsWindowsAdapter({
    FlutterLocalNotificationsWindows? plugin,
    this.identity = const WindowsNotificationIdentity(),
  }) : _plugin = plugin ?? FlutterLocalNotificationsWindows();

  final FlutterLocalNotificationsWindows _plugin;
  final WindowsNotificationIdentity identity;
  bool _ready = false;

  @override
  Future<bool> initialize({
    DidReceiveNotificationResponseCallback? onResponse,
  }) async {
    if (_ready) return true;
    try {
      _ready = await _plugin.initialize(
        settings: WindowsInitializationSettings(
          appName: identity.appName,
          appUserModelId: identity.appUserModelId,
          guid: identity.guid,
        ),
        onDidReceiveNotificationResponse: onResponse,
      );
    } catch (_) {
      // An unavailable shell registration must not break the app; scheduling
      // and delivery then stay unavailable and stay reported as unverified.
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    if (!_ready) return;
    // Windows keeps several scheduled toasts per id; cancel first so an edit
    // leaves exactly one pending item.
    await _plugin.cancel(id: id);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: timezone.TZDateTime.from(at.toUtc(), timezone.UTC),
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<List<int>> pendingIds() async {
    if (!_ready) return const [];
    final pending = await _plugin.pendingNotificationRequests();
    return [for (final request in pending) request.id];
  }

  @override
  Future<void> dispose() async => _plugin.dispose();
}
