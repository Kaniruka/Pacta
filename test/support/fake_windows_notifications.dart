import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pacta/src/notifications/windows_notification_adapter.dart';

class ScheduledWindowsNotification {
  const ScheduledWindowsNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime at;
  final String? payload;
}

/// Fake at the Windows platform boundary: it only mimics what the OS queue
/// would report, so tests observe scheduling behavior, not internals.
class FakeWindowsNotificationAdapter implements WindowsNotificationAdapter {
  FakeWindowsNotificationAdapter({
    this.ready = true,
    Iterable<int> pending = const [],
  }) : initialPending = [...pending];

  final bool ready;
  final List<int> initialPending;
  final Map<int, ScheduledWindowsNotification> scheduled = {};
  final List<int> cancelled = [];
  final List<int> scheduleCalls = [];
  bool initialized = false;

  /// Blocks the next platform registration to expose async races.
  Future<void> Function()? beforeSchedule;
  Future<void> Function()? beforePending;

  @override
  Future<bool> initialize({
    DidReceiveNotificationResponseCallback? onResponse,
  }) async {
    initialized = true;
    return ready;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    await beforeSchedule?.call();
    scheduleCalls.add(id);
    scheduled[id] = ScheduledWindowsNotification(
      id: id,
      title: title,
      body: body,
      at: at,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<List<int>> pendingIds() async {
    await beforePending?.call();
    return {...initialPending, ...scheduled.keys}.toList();
  }

  @override
  Future<void> dispose() async {}
}
