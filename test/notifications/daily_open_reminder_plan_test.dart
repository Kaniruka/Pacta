import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/daily_open_reminder_plan.dart';

void main() {
  test('a reminder later today keeps the local date', () {
    final plan = DailyOpenReminderPlan.next(
      now: DateTime(2026, 11, 13, 18, 30, 45),
      minuteOfDay: 19 * 60,
    );

    expect(plan.dayKey, '2026-11-13');
    expect(plan.scheduledAt, DateTime(2026, 11, 13, 19));
    expect(plan.scheduledAt.isUtc, isFalse);
  });

  test('a reminder time already reached moves to the next local day', () {
    final plan = DailyOpenReminderPlan.next(
      now: DateTime(2026, 11, 13, 19),
      minuteOfDay: 19 * 60,
    );

    expect(plan.dayKey, '2026-11-14');
    expect(plan.scheduledAt, DateTime(2026, 11, 14, 19));
  });

  test('a past reminder time never replays the current day', () {
    final plan = DailyOpenReminderPlan.next(
      now: DateTime(2026, 11, 13, 8, 0, 1),
      minuteOfDay: 0,
    );

    expect(plan.dayKey, '2026-11-14');
    expect(plan.scheduledAt, DateTime(2026, 11, 14));
  });

  test('after gaps the reminder resumes on the current local day', () {
    final plan = DailyOpenReminderPlan.next(
      now: DateTime(2026, 11, 30, 23, 59),
      minuteOfDay: 8 * 60,
    );

    expect(plan.dayKey, '2026-12-01');
    expect(plan.scheduledAt, DateTime(2026, 12, 1, 8));
  });

  test('the plan rejects an impossible wall clock minute', () {
    expect(
      () => DailyOpenReminderPlan.next(
        now: DateTime(2026, 11, 13, 12),
        minuteOfDay: 24 * 60,
      ),
      throwsRangeError,
    );
  });
}
