import 'schedule_reminder_plan.dart';

/// The reminder clicks the shell could not open yet.
///
/// The Plan destination claims them once it is integrated; until then the
/// request stays visible instead of being silently dropped or redirected into
/// the focus flow.
class ScheduleReminderInbox {
  ScheduleReminderRequest? pending;

  ScheduleReminderRequest? take() {
    final request = pending;
    pending = null;
    return request;
  }
}
