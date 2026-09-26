import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_notification_plan.dart';
import 'package:pacta/src/notifications/national_focus_reminder_plan.dart';

void main() {
  test('the default reminder is scheduled at 22:00 Beijing time', () {
    final reminder = NationalFocusReminderPlan.next(
      now: DateTime.utc(2026, 9, 26, 13, 59),
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
    );

    expect(reminder?.dayKey, '2026-09-26');
    expect(reminder?.scheduledAt, DateTime.utc(2026, 9, 26, 14));
  });

  test('a reminder already due is sent once the flow has ended', () {
    final reminder = NationalFocusReminderPlan.next(
      now: DateTime.utc(2026, 9, 26, 14, 5),
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
    );

    expect(reminder?.dayKey, '2026-09-26');
    expect(reminder?.scheduledAt, DateTime.utc(2026, 9, 26, 14, 5));
  });

  test('an unfinished focus flow defers a due reminder until its end', () {
    final now = DateTime.utc(2026, 9, 26, 13, 59);
    final focus = FocusNotificationPlan(
      flowId: 'session-1',
      sessionId: 'session-1',
      taskTitle: 'Write a report',
      modeLabel: '普通链',
      stage: FocusNotificationStage.active,
      stageEndsAt: DateTime.utc(2026, 9, 26, 15, 15),
      focusEndsAt: DateTime.utc(2026, 9, 26, 15, 15),
    );

    final reminder = NationalFocusReminderPlan.next(
      now: now,
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
      activeFlow: focus,
    );

    expect(reminder?.scheduledAt, DateTime.utc(2026, 9, 26, 15, 15));
  });

  test('an approved pause keeps the due reminder deferred', () {
    final pausedFocus = FocusNotificationPlan(
      flowId: 'session-1',
      sessionId: 'session-1',
      taskTitle: 'Write a report',
      modeLabel: '普通链',
      stage: FocusNotificationStage.paused,
      stageEndsAt: null,
      focusEndsAt: DateTime.utc(2026, 9, 26, 15, 15),
      pausedAt: DateTime.utc(2026, 9, 26, 13),
    );

    expect(
      NationalFocusReminderPlan.next(
        now: DateTime.utc(2026, 9, 26, 14, 5),
        minuteOfDay: 22 * 60,
        hasPendingConfirmations: true,
        activeFlow: pausedFocus,
      ),
      isNull,
    );
  });

  test('confirmed nodes skip the reminder and a sent day advances once', () {
    expect(
      NationalFocusReminderPlan.next(
        now: DateTime.utc(2026, 9, 26, 13),
        minuteOfDay: 22 * 60,
        hasPendingConfirmations: false,
      ),
      isNull,
    );

    final nextDay = NationalFocusReminderPlan.next(
      now: DateTime.utc(2026, 9, 26, 13),
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
      lastNotifiedDayKey: '2026-09-26',
    );

    expect(nextDay?.dayKey, '2026-09-27');
    expect(nextDay?.scheduledAt, DateTime.utc(2026, 9, 27, 14));
  });
}
