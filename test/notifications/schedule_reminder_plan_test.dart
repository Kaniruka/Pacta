import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/schedule_reminder_plan.dart';
import 'package:pacta/src/schedules/schedule_models.dart';

Schedule schedule({
  required String id,
  required DateTime startsAt,
  DateTime? endsAt,
  int? reminderMinutesBefore,
  bool isCompleted = false,
  bool allDay = false,
  String? allDayStartDate,
  String? allDayEndDateExclusive,
  String? recurrenceId,
  String? recurrenceSeriesId,
  String? recurrenceDate,
}) => Schedule(
  id: id,
  title: '取快递',
  startsAt: startsAt,
  endsAt: endsAt ?? startsAt.add(const Duration(hours: 1)),
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 1),
  reminderMinutesBefore: reminderMinutesBefore,
  isCompleted: isCompleted,
  allDay: allDay,
  allDayStartDate: allDayStartDate,
  allDayEndDateExclusive: allDayEndDateExclusive,
  recurrenceId: recurrenceId,
  recurrenceSeriesId: recurrenceSeriesId,
  recurrenceDate: recurrenceDate,
);

void main() {
  final now = DateTime.utc(2026, 11, 15, 1);

  test(
    'timed reminder delivers the stored offset before the start instant',
    () {
      final plans = ScheduleReminderPlanner.plan(
        schedules: [
          schedule(
            id: 's-1',
            startsAt: DateTime.utc(2026, 11, 16, 10),
            reminderMinutesBefore: 30,
          ),
        ],
        now: now,
        timeZoneId: 'Asia/Tokyo',
      );

      expect(plans, hasLength(1));
      expect(plans.single.deliverAt, DateTime.utc(2026, 11, 16, 9, 30));
      expect(plans.single.scheduleId, 's-1');
      expect(plans.single.notificationId, greaterThanOrEqualTo(230000));
      expect(plans.single.notificationId, lessThan(330000));
    },
  );

  test(
    'each schedule keeps its own offset and no-reminder entries are skipped',
    () {
      final plans = ScheduleReminderPlanner.plan(
        schedules: [
          schedule(
            id: 's-0',
            startsAt: DateTime.utc(2026, 11, 16, 10),
            reminderMinutesBefore: 0,
          ),
          schedule(
            id: 's-15',
            startsAt: DateTime.utc(2026, 11, 16, 10),
            reminderMinutesBefore: 15,
          ),
          schedule(id: 's-none', startsAt: DateTime.utc(2026, 11, 16, 10)),
        ],
        now: now,
        timeZoneId: 'Asia/Tokyo',
      );

      expect(
        {for (final plan in plans) plan.scheduleId: plan.deliverAt},
        {
          's-0': DateTime.utc(2026, 11, 16, 10),
          's-15': DateTime.utc(2026, 11, 16, 9, 45),
        },
      );
    },
  );

  test('past, completed and beyond-horizon reminders are not planned', () {
    final plans = ScheduleReminderPlanner.plan(
      schedules: [
        schedule(
          id: 'past',
          startsAt: DateTime.utc(2026, 11, 15),
          reminderMinutesBefore: 10,
        ),
        schedule(
          id: 'completed',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: 10,
          isCompleted: true,
        ),
        schedule(
          id: 'beyond',
          startsAt: DateTime.utc(2027, 3, 1),
          reminderMinutesBefore: 10,
        ),
      ],
      now: now,
      timeZoneId: 'Asia/Tokyo',
    );

    expect(plans, isEmpty);
  });

  test('all-day reminders resolve the account civil midnight, never the device zone', () {
    final plans = ScheduleReminderPlanner.plan(
      schedules: [
        schedule(
          id: 'all-day',
          startsAt: DateTime.utc(2026, 11, 15),
          endsAt: DateTime.utc(2026, 11, 16),
          allDay: true,
          allDayStartDate: '2026-11-15',
          allDayEndDateExclusive: '2026-11-16',
          reminderMinutesBefore: 30,
        ),
      ],
      now: DateTime.utc(2026, 11, 14, 1),
      timeZoneId: 'Asia/Tokyo',
    );

    expect(plans.single.deliverAt, DateTime.utc(2026, 11, 14, 14, 30));
  });

  test('all-day midnight follows the account zone daylight-saving offset', () {
    final plans = ScheduleReminderPlanner.plan(
      schedules: [
        schedule(
          id: 'dst',
          startsAt: DateTime.utc(2027, 3, 15),
          endsAt: DateTime.utc(2027, 3, 16),
          allDay: true,
          allDayStartDate: '2027-03-15',
          allDayEndDateExclusive: '2027-03-16',
          reminderMinutesBefore: 0,
        ),
      ],
      now: DateTime.utc(2027, 3, 1),
      timeZoneId: 'America/New_York',
    );

    expect(plans.single.deliverAt, DateTime.utc(2027, 3, 15, 4));
  });

  test(
    'timed reminders keep the persisted instant across a wall-clock change',
    () {
      final plans = ScheduleReminderPlanner.plan(
        schedules: [
          schedule(
            id: 'timed-dst',
            startsAt: DateTime.utc(2027, 3, 15, 13),
            reminderMinutesBefore: 60,
          ),
        ],
        now: DateTime.utc(2027, 3, 1),
        timeZoneId: 'America/New_York',
      );

      expect(plans.single.deliverAt, DateTime.utc(2027, 3, 15, 12));
    },
  );

  test(
    'recurring instances keep their original identity and stay distinct',
    () {
      final plans = ScheduleReminderPlanner.plan(
        schedules: [
          schedule(
            id: 'row-1',
            startsAt: DateTime.utc(2026, 11, 16, 10),
            reminderMinutesBefore: 10,
            recurrenceId: 'rule-a',
            recurrenceSeriesId: 'series-a',
            recurrenceDate: '2026-11-16',
          ),
          schedule(
            id: 'row-2',
            startsAt: DateTime.utc(2026, 11, 17, 10),
            reminderMinutesBefore: 10,
            recurrenceId: 'rule-a',
            recurrenceSeriesId: 'series-a',
            recurrenceDate: '2026-11-17',
          ),
        ],
        now: now,
        timeZoneId: 'Asia/Tokyo',
      );

      expect(plans.map((plan) => plan.identity).toSet(), hasLength(2));
      expect(plans.map((plan) => plan.deliverAt), [
        DateTime.utc(2026, 11, 16, 9, 50),
        DateTime.utc(2026, 11, 17, 9, 50),
      ]);
      expect(
        plans.every((plan) => plan.payload.startsWith('schedule-reminder:')),
        isTrue,
      );
    },
  );

  test('stable ids avoid collisions and the reserved focus ids', () {
    final schedules = [
      for (var index = 0; index < 60; index += 1)
        schedule(
          id: 's-$index',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: index,
        ),
    ];
    final first = ScheduleReminderPlanner.plan(
      schedules: schedules,
      now: now,
      timeZoneId: 'Asia/Tokyo',
    );
    final second = ScheduleReminderPlanner.plan(
      schedules: schedules.reversed,
      now: now,
      timeZoneId: 'Asia/Tokyo',
    );

    final ids = first.map((plan) => plan.notificationId).toList();
    expect(ids.toSet(), hasLength(schedules.length));
    expect(ids.every((id) => id > 2205), isTrue);
    expect(
      {for (final plan in second) plan.scheduleId: plan.notificationId},
      {for (final plan in first) plan.scheduleId: plan.notificationId},
    );
  });

  test('payload round-trips the schedule and its account civil day', () {
    final request = ScheduleReminderRequest.tryParse(
      'schedule-reminder:s-1:2026-11-16',
    );
    expect(request?.scheduleId, 's-1');
    expect(request?.dateKey, '2026-11-16');
    expect(request?.toPayload(), 'schedule-reminder:s-1:2026-11-16');
    expect(ScheduleReminderRequest.tryParse('appointment:a-1'), isNull);
    expect(ScheduleReminderRequest.tryParse('schedule-reminder:s-1'), isNull);
  });
}
