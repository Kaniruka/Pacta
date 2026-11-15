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
/// window is bounded, rolls on resume, and only future instances are delivered;
/// missed reminders are never replayed.
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
  int _epoch = 0;
  int _revision = 0;

  /// Completes when the reconciliation queued so far finished.
  Future<void> get settled => _work;

  ScheduleRepository? get repository => _repository;

  /// Subscribes to [repository]; a different repository replaces the old
  /// subscription. A null repository only detaches: the absence of a wired
  /// destination must not cancel reminders that are already registered.
  Future<void> attach(ScheduleRepository? repository) async {
    if (identical(repository, _repository) && _subscription != null) return;
    await _closeSubscription();
    _repository = repository;
    if (repository == null) return;
    await _subscribe(repository);
  }

  /// Re-subscribes with a window anchored at the current clock.
  ///
  /// A resume or a long foreground session must not keep querying the range
  /// that was current at attach time, and an edited row outside that old range
  /// must not cancel reminders that are now inside it.
  Future<void> refreshWindow() async {
    final repository = _repository;
    if (repository == null || _subscription == null) return;
    await _subscribe(repository);
  }

  /// Re-reads the bounded window and waits for its reconciliation.
  ///
  /// Re-subscribing alone is not enough: the new subscription's first event is
  /// delivered asynchronously, so awaiting [settled] could return before any
  /// read reached the service. This call therefore reads the window itself and
  /// waits for that push, while the fresh subscription keeps later edits inside
  /// the rolling range.
  Future<void> reconcileOnce() async {
    final repository = _repository;
    if (repository == null) return;
    await refreshWindow();
    await _readAndPush(repository);
  }

  Future<void> detach() async {
    await _closeSubscription();
    _repository = null;
  }

  Future<void> _closeSubscription() async {
    // Every queued or in-flight push of the old subscription is invalidated
    // before its repository is replaced or released.
    _epoch += 1;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _subscribe(ScheduleRepository repository) async {
    _epoch += 1;
    final epoch = _epoch;
    await _subscription?.cancel();
    final window = _window();
    _subscription = repository
        .watchSchedules(from: window.from, to: window.to)
        .listen(
          (schedules) {
            if (epoch != _epoch || !identical(repository, _repository)) return;
            unawaited(_push(schedules, epoch, repository));
          },
          onError: (Object _) {
            // A local read failure leaves the current OS queue untouched; the
            // next schedule change reconciles again.
          },
        );
  }

  /// The bounded query window anchored at the current clock.
  ///
  /// A reminder may target an event that starts after the delivery horizon when
  /// its stored offset is large, so the query must reach past the horizon.
  ({DateTime from, DateTime to}) _window() {
    final clock = _now();
    return (
      from: clock.subtract(const Duration(days: 1)),
      to: ScheduleReminderPlanner.queryEnd(clock, horizon: _horizon),
    );
  }

  /// Reads the current window and waits for that push to reach the service.
  Future<void> _readAndPush(ScheduleRepository repository) async {
    final epoch = _epoch;
    final window = _window();
    final List<Schedule> schedules;
    try {
      schedules = await repository.getSchedules(
        from: window.from,
        to: window.to,
      );
    } catch (_) {
      // A local read failure leaves the OS queue for the next change.
      return;
    }
    if (epoch != _epoch || !identical(repository, _repository)) return;
    await _push(schedules, epoch, repository);
  }

  Future<void> _push(
    List<Schedule> schedules,
    int epoch,
    ScheduleRepository repository,
  ) {
    final revision = ++_revision;
    bool current() =>
        epoch == _epoch &&
        revision == _revision &&
        identical(repository, _repository);
    _work = _work
        .then((_) async {
          if (!current()) return;
          final timeZoneId = await _displayTimeZoneId();
          // The account, the repository or the clock window may have changed
          // while the time zone was being read.
          if (!current()) return;
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
