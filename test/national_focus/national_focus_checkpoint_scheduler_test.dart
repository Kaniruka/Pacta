import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_checkpoint_scheduler.dart';

void main() {
  testWidgets('settles at the next checkpoint while app remains open', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 26, 19, 59);
    var settleCount = 0;
    final scheduler = NationalFocusCheckpointScheduler(
      now: () => now,
      settleDueCheckpoints: () async {
        settleCount++;
      },
    );

    scheduler.start();
    now = DateTime.utc(2026, 9, 26, 20);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(settleCount, 1);
    scheduler.dispose();
  });

  testWidgets('dispose cancels the pending checkpoint refresh', (tester) async {
    var settleCount = 0;
    final scheduler = NationalFocusCheckpointScheduler(
      now: () => DateTime.utc(2026, 9, 26, 19, 59),
      settleDueCheckpoints: () async {
        settleCount++;
      },
    );

    scheduler.start();
    scheduler.dispose();
    await tester.pump(const Duration(minutes: 1));

    expect(settleCount, 0);
  });
}
