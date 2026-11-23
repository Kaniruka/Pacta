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

  test('the reminder follows the account time zone wall clock', () {
    // 东京 2026-09-26 21:00 → 当地 22:00 = 13:00Z。
    final tokyo = NationalFocusReminderPlan.next(
      now: DateTime.utc(2026, 9, 26, 12),
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
      timeZoneId: 'Asia/Tokyo',
    );
    expect(tokyo?.dayKey, '2026-09-26');
    expect(tokyo?.scheduledAt, DateTime.utc(2026, 9, 26, 13));

    // 纽约 2026-09-25 22:00 EDT（02:00Z 次日）仍是 9/25 的提醒。
    final newYork = NationalFocusReminderPlan.next(
      now: DateTime.utc(2026, 9, 26, 1),
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
      timeZoneId: 'America/New_York',
    );
    expect(newYork?.dayKey, '2026-09-25');
    expect(newYork?.scheduledAt, DateTime.utc(2026, 9, 26, 2));

    // 同一时刻按北京时间算已经是 9/26 上午，提醒日是 9/26。
    final beijing = NationalFocusReminderPlan.next(
      now: DateTime.utc(2026, 9, 26, 1),
      minuteOfDay: 22 * 60,
      hasPendingConfirmations: true,
    );
    expect(beijing?.dayKey, '2026-09-26');
    expect(beijing?.scheduledAt, DateTime.utc(2026, 9, 26, 14));
  });

  test('跨夏令时切换的提醒时刻仍由 IANA 规则决定', () {
    // 纽约夏令时（EDT -04）：22:00 = 次日 02:00Z。
    expect(
      NationalFocusReminderPlan.next(
        now: DateTime.utc(2026, 7, 15, 12),
        minuteOfDay: 22 * 60,
        hasPendingConfirmations: true,
        timeZoneId: 'America/New_York',
      )?.scheduledAt,
      DateTime.utc(2026, 7, 16, 2),
    );
    // 纽约标准时（EST -05）：22:00 = 次日 03:00Z。
    expect(
      NationalFocusReminderPlan.next(
        now: DateTime.utc(2026, 1, 15, 12),
        minuteOfDay: 22 * 60,
        hasPendingConfirmations: true,
        timeZoneId: 'America/New_York',
      )?.scheduledAt,
      DateTime.utc(2026, 1, 16, 3),
    );
    // 伦敦夏令时（BST +01）：22:00 = 21:00Z。
    expect(
      NationalFocusReminderPlan.next(
        now: DateTime.utc(2026, 7, 15, 12),
        minuteOfDay: 22 * 60,
        hasPendingConfirmations: true,
        timeZoneId: 'Europe/London',
      )?.scheduledAt,
      DateTime.utc(2026, 7, 15, 21),
    );
    // 未知时区回落到北京时间。
    expect(
      NationalFocusReminderPlan.next(
        now: DateTime.utc(2026, 9, 26, 13, 59),
        minuteOfDay: 22 * 60,
        hasPendingConfirmations: true,
        timeZoneId: 'Mars/Olympus',
      )?.scheduledAt,
      DateTime.utc(2026, 9, 26, 14),
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
