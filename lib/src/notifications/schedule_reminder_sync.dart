import 'dart:async';

import '../schedules/schedule_models.dart';
import '../schedules/schedule_repository.dart';
import 'focus_notification_service.dart';
import 'schedule_reminder_plan.dart';

/// Keeps the OS queue in step with this account's owned schedules.
///
/// One subscription per repository: every create, edit, reschedule, completion,
/// deletion, repeat split and cloud restore reaches the shell as a new list, so
/// the same reconciliation also cancels the items that no longer apply. The
/// window is bounded and only future instances are delivered; missed reminders
/// are never replayed.
class ScheduleReminderSync {
  ScheduleReminderSync({
    required FocusNotificationService notificationService,
    required Future<String> Function() accountTimeZoneId,
    DateTime Function()? now,
    Duration window = ScheduleReminderPlanner.horizon,
  }) : _service = notificationService,
       _displayTimeZoneId = accountTimeZoneId,
       _now = now ?? DateTime.now,
       _horizon = window;

  final FocusNotificationService _service;
  final Future<String> Function() _displayTimeZoneId;
  final DateTime Function() _now;
  final Duration _horizon;

  ScheduleRepository? _repository;
  StreamSubscription<List<Schedule>>? _subscription;
  Future<void> _work = Future<void>.value();
  int _revision = 0;

  /// Completes when the reconciliation queued so far finished.
  Future<void> get settled => _work;

  ScheduleRepository? get repository => _repository;

  /// Subscribes to [repository]; a different repository replaces the old
  /// subscription. A null repository only detaches: the absence of a wired
  /// destination must not cancel reminders that are already registered.
  Future<void> attach(ScheduleRepository? repository) async {
    if (identical(repository, _repository)) return;
    await _subscription?.cancel();
    _subscription = null;
    _repository = repository;
    if (repository == null) return;
    final clock = _now();
    _subscription = repository
        .watchSchedules(
          from: clock.subtract(const Duration(days: 1)),
          to: clock.add(_horizon),
        )
        .listen(
          (schedules) => unawaited(_push(schedules)),
          onError: (Object _) {
            // A local read failure leaves the current OS queue untouched; the
            // next schedule change reconciles again.
          },
        );
  }

  /// Re-reads the bounded window, for example after the app resumed.
  Future<void> reconcileOnce() async {
    final repository = _repository;
    if (repository == null) return;
    final clock = _now();
    try {
      final schedules = await repository.getSchedules(
        from: clock.subtract(const Duration(days: 1)),
        to: clock.add(_horizon),
      );
      await _push(schedules);
    } catch (_) {
      // A local read failure keeps the app usable.
    }
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
    _repository = null;
  }

  Future<void> _push(List<Schedule> schedules) {
    final revision = ++_revision;
    _work = _work
        .then((_) async {
          if (revision != _revision) return;
          final timeZoneId = await _displayTimeZoneId();
          if (revision != _revision) return;
          await _service.syncScheduleReminders(
            schedules: schedules,
            timeZoneId: timeZoneId,
          );
        })
        .catchError((Object _) {
          // Delivery is optional and must never break schedule editing.
        });
    return _work;
  }
}
