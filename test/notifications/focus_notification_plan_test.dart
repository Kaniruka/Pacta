import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/notifications/focus_notification_plan.dart';

void main() {
  final startedAt = DateTime.utc(2026, 9, 26, 10);

  test(
    'appointment plan exposes its preparation and following focus times',
    () {
      final appointment = AppointmentPreparation(
        id: 'appointment-1',
        taskId: 'task-1',
        mode: FocusChainMode.regular,
        durationSeconds: 30 * 60,
        startedAt: startedAt,
        endsAt: startedAt.add(const Duration(minutes: 15)),
        status: AppointmentPreparationStatus.active,
        settledAt: null,
        updatedAt: startedAt,
      );

      final plan = FocusNotificationPlan.forAppointment(
        appointment,
        taskTitle: 'Write a report',
      );

      expect(plan.flowId, 'appointment-1');
      expect(plan.stage, FocusNotificationStage.preparation);
      expect(plan.taskTitle, 'Write a report');
      expect(plan.stageEndsAt, startedAt.add(const Duration(minutes: 15)));
      expect(plan.focusEndsAt, startedAt.add(const Duration(minutes: 45)));
    },
  );

  test('paused session plan keeps the original session and remaining time', () {
    final session = FocusSession(
      id: 'session-1',
      taskId: 'task-1',
      mode: FocusChainMode.elite,
      durationSeconds: 30 * 60,
      startedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 30)),
      status: FocusSessionStatus.paused,
      completedAt: null,
      effectiveSeconds: 10 * 60,
      pausedAt: startedAt.add(const Duration(minutes: 10)),
      pausedSeconds: 0,
      pauseRuleText: 'A permitted interruption',
    );

    final plan = FocusNotificationPlan.forSession(
      session,
      taskTitle: 'Write a report',
    );

    expect(plan.flowId, 'session-1');
    expect(plan.stage, FocusNotificationStage.paused);
    expect(plan.stageEndsAt, isNull);
    expect(plan.focusEndsAt, session.endsAt);
    expect(
      plan.remainingSecondsAt(session.pausedAt!.add(const Duration(hours: 6))),
      20 * 60,
    );
  });
}
