import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/daily_open_reminder_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a scheduled daily reminder survives a restart', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = DailyOpenReminderStateStore(preferences);
    final scheduledAt = DateTime(2026, 11, 13, 8, 30);

    await store.saveScheduled(
      DailyOpenReminderSchedule(
        dayKey: '2026-11-13',
        scheduledAt: scheduledAt,
        timeZoneId: 'Asia/Shanghai',
      ),
    );

    final restored = DailyOpenReminderStateStore(preferences).loadScheduled();

    expect(restored?.dayKey, '2026-11-13');
    expect(restored?.timeZoneId, 'Asia/Shanghai');
    expect(restored?.scheduledAt.isAtSameMomentAs(scheduledAt), isTrue);
  });

  test('delivered days are remembered until the reminder changes', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = DailyOpenReminderStateStore(preferences);

    await store.saveScheduled(
      DailyOpenReminderSchedule(
        dayKey: '2026-11-13',
        scheduledAt: DateTime(2026, 11, 13, 8, 30),
        timeZoneId: 'Asia/Shanghai',
      ),
    );
    await store.markSent('2026-11-13');

    final restored = DailyOpenReminderStateStore(preferences);
    expect(restored.loadLastSentDayKey(), '2026-11-13');
    expect(restored.loadScheduled(), isNull);
  });

  test('clearing the schedule keeps no stale reminder behind', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = DailyOpenReminderStateStore(preferences);
    await store.saveScheduled(
      DailyOpenReminderSchedule(
        dayKey: '2026-11-13',
        scheduledAt: DateTime(2026, 11, 13, 8, 30),
        timeZoneId: 'Etc/UTC',
      ),
    );

    await store.clearScheduled();

    expect(DailyOpenReminderStateStore(preferences).loadScheduled(), isNull);
  });
}
