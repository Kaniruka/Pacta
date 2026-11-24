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

  test('准备窗口同时给出进度分母与已过去的秒数', () {
    final appointment = AppointmentPreparation(
      id: 'appointment-2',
      taskId: 'task-1',
      mode: FocusChainMode.regular,
      durationSeconds: 30 * 60,
      startedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 15)),
      status: AppointmentPreparationStatus.active,
      settledAt: null,
      updatedAt: startedAt,
      preparationSeconds: 15 * 60,
    );

    final plan = FocusNotificationPlan.forAppointment(
      appointment,
      taskTitle: 'Write a report',
    );

    expect(plan.startedAt, startedAt);
    expect(plan.totalSeconds, 15 * 60);
    expect(plan.progressTotalSeconds, 15 * 60);
    expect(
      plan.elapsedSecondsAt(startedAt.add(const Duration(minutes: 5))),
      5 * 60,
    );
    // 进度条不会超过分母，也不会因为设备时钟回拨变成负数。
    expect(
      plan.elapsedSecondsAt(startedAt.add(const Duration(hours: 3))),
      15 * 60,
    );
    expect(
      plan.elapsedSecondsAt(startedAt.subtract(const Duration(minutes: 5))),
      0,
    );
  });

  test('暂停中的会话把进度冻结在暂停时刻', () {
    final session = FocusSession(
      id: 'session-2',
      taskId: 'task-1',
      mode: FocusChainMode.regular,
      durationSeconds: 30 * 60,
      startedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 20)),
      status: FocusSessionStatus.paused,
      completedAt: null,
      effectiveSeconds: 10 * 60,
      pausedAt: startedAt.add(const Duration(minutes: 10)),
    );

    final plan = FocusNotificationPlan.forSession(
      session,
      taskTitle: 'Write a report',
    );

    expect(plan.totalSeconds, 30 * 60);
    expect(plan.progressTotalSeconds, 30 * 60);
    expect(
      plan.elapsedSecondsAt(session.pausedAt!.add(const Duration(hours: 4))),
      10 * 60,
      reason: '暂停之后进度条必须停住，不能继续往后爬',
    );
  });

  test('暂停后恢复的会话按剩余反推进度，不会把进度条一次画满', () {
    // 10:00 开始、10:10 暂停、10:40 恢复：结束时刻整体后移到 11:30。暂停的
    // 30 分钟只是把终点推后，不能被算成"已经专注过"。
    final session = FocusSession(
      id: 'session-3',
      taskId: 'task-1',
      mode: FocusChainMode.regular,
      durationSeconds: 30 * 60,
      startedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 90)),
      status: FocusSessionStatus.active,
      completedAt: null,
      effectiveSeconds: 10 * 60,
      pausedSeconds: 30 * 60,
    );

    final plan = FocusNotificationPlan.forSession(session, taskTitle: '写报告');
    final fiveMinutesAfterResume = startedAt.add(const Duration(minutes: 45));

    expect(plan.progressTotalSeconds, 30 * 60);
    expect(
      plan.elapsedSecondsAt(fiveMinutesAfterResume),
      0,
      reason: '按"分母 - 剩余"反推；旧的按起点相减会把 45 分钟全画进进度条',
    );
    expect(plan.remainingSecondsAt(fiveMinutesAfterResume), 45 * 60);

    // 剩余落回分母以内后，进度与剩余必须共享同一个分母，不会各算各的。
    final lastWindow = session.endsAt.subtract(const Duration(minutes: 20));
    expect(plan.elapsedSecondsAt(lastWindow), 10 * 60);
    expect(
      plan.elapsedSecondsAt(lastWindow) + plan.remainingSecondsAt(lastWindow),
      plan.progressTotalSeconds,
    );

    // 全程只增不减，也永远越不过分母。
    var previous = 0;
    for (var minutes = 0; minutes <= 120; minutes += 5) {
      final elapsed = plan.elapsedSecondsAt(
        startedAt.add(Duration(minutes: minutes)),
      );
      expect(elapsed, inInclusiveRange(previous, plan.progressTotalSeconds));
      previous = elapsed;
    }
  });

  test('没有起点时进度退化为不确定进度', () {
    final plan = FocusNotificationPlan(
      flowId: 'flow-1',
      taskTitle: 'Write a report',
      modeLabel: '常规',
      stage: FocusNotificationStage.active,
      stageEndsAt: null,
      focusEndsAt: _focusEnd,
    );

    expect(plan.startedAt, isNull);
    expect(plan.totalSeconds, isNull);
    expect(plan.progressTotalSeconds, 1);
    expect(plan.elapsedSecondsAt(_focusEnd), 0);
  });
}

final DateTime _focusEnd = DateTime.utc(2026, 9, 26, 10, 30);
