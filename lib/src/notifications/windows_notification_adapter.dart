import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The Windows platform boundary used by [FocusNotificationService].
///
/// The production adapter talks to the Flutter runner, which owns the Windows
/// App SDK registration and the OS-scheduled queue. The locked
/// `flutter_local_notifications_windows` plugin is deliberately not used here:
/// its `initialize` writes its own COM activator over the SDK's registration,
/// which is what the R5 probe proved must not happen.
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
  });

  final String appName;
  final String appUserModelId;
}

/// Production adapter over the runner's native bridge.
///
/// The bridge method names and the click event are declared in
/// `windows/runner/windows_notification_bridge.{h,cpp}`. Every call returns the
/// real platform verdict: an unavailable SDK, a rejected identity or a refused
/// schedule is reported, never hidden behind a successful no-op.
class RunnerWindowsNotificationAdapter implements WindowsNotificationAdapter {
  RunnerWindowsNotificationAdapter({
    MethodChannel? channel,
    this.identity = const WindowsNotificationIdentity(),
  }) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.pacta/windows_notifications';

  final MethodChannel _channel;
  final WindowsNotificationIdentity identity;

  bool _ready = false;
  bool _handlerAttached = false;
  DidReceiveNotificationResponseCallback? _onResponse;

  /// What the process actually registered, as reported by the runner. The Dart
  /// side only asserts the expected identity; the bridge decides it.
  String? registeredAumid;
  String? identitySource;

  @override
  Future<bool> initialize({
    DidReceiveNotificationResponseCallback? onResponse,
  }) async {
    if (onResponse != null) _onResponse = onResponse;
    if (!_handlerAttached) {
      _handlerAttached = true;
      _channel.setMethodCallHandler(_handlePlatformCall);
    }
    if (_ready) return true;
    try {
      final reply = await _channel.invokeMapMethod<Object?, Object?>(
        'initialize',
        {'expectedAumid': identity.appUserModelId},
      );
      _ready = reply != null && reply['ready'] == true;
      registeredAumid = reply?['aumid'] is String
          ? reply!['aumid']! as String
          : null;
      identitySource = reply?['identitySource'] is String
          ? reply!['identitySource']! as String
          : null;
    } on PlatformException {
      _ready = false;
    } on MissingPluginException {
      _ready = false;
    }
    return _ready;
  }

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'notificationClicked') return null;
    final payload = call.arguments;
    if (payload is! String || payload.isEmpty) return null;
    _onResponse?.call(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: payload,
      ),
    );
    return null;
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
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'dueUnixMs': at.toUtc().millisecondsSinceEpoch,
        'payload': payload ?? '',
      });
    } on PlatformException {
      // A refused registration leaves the in-process tray countdown intact; the
      // caller keeps its bookkeeping because nothing was queued.
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on PlatformException {
      // Cancelling an id the OS no longer holds is not a state change.
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    if (!_ready) return const [];
    try {
      final ids = await _channel.invokeListMethod<Object?>('pendingIds');
      if (ids == null) return const [];
      return [
        for (final id in ids)
          if (id is int) id,
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      _ready = false;
      return const [];
    }
  }

  /// Read-only view of the OS notification switch. Never writes a setting.
  Future<bool> notificationsEnabled() async {
    if (!_ready) return false;
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Fixture-only permanent deregistration for a `Pacta.Test.*` identity.
  ///
  /// It exists so native acceptance can leave no SDK registration behind; the
  /// bridge refuses the product identity and non-fixture processes.
  Future<void> unregisterAllForTestIdentity() async {
    await _channel.invokeMethod<void>('unregisterAllForTestIdentity');
  }

  @override
  Future<void> dispose() async {
    if (_handlerAttached) {
      _handlerAttached = false;
      _channel.setMethodCallHandler(null);
    }
    if (_ready) {
      try {
        await _channel.invokeMethod<void>('dispose');
      } on PlatformException {
        // The process is going away; the registration outlives this adapter.
      } on MissingPluginException {
        // Nothing to detach from.
      }
    }
    _ready = false;
  }
}
