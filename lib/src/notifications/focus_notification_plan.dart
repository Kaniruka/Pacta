import '../focus/focus_models.dart';

enum FocusNotificationStage { preparation, active, paused }

/// The device-local status and transition times for one unfinished focus flow.
class FocusNotificationPlan {
  const FocusNotificationPlan({
    required this.flowId,
    required this.taskTitle,
    required this.modeLabel,
    required this.stage,
    required this.stageEndsAt,
    required this.focusEndsAt,
    this.appointmentId,
    this.sessionId,
    this.pausedAt,
  });

  factory FocusNotificationPlan.forAppointment(
    AppointmentPreparation appointment, {
    required String taskTitle,
  }) => FocusNotificationPlan(
    flowId: appointment.id,
    appointmentId: appointment.id,
    taskTitle: taskTitle,
    modeLabel: appointment.mode.label,
    stage: FocusNotificationStage.preparation,
    stageEndsAt: appointment.endsAt,
    focusEndsAt: appointment.endsAt.add(
      Duration(seconds: appointment.durationSeconds),
    ),
  );

  factory FocusNotificationPlan.forSession(
    FocusSession session, {
    required String taskTitle,
  }) => FocusNotificationPlan(
    flowId: session.id,
    appointmentId: session.appointmentId,
    sessionId: session.id,
    taskTitle: taskTitle,
    modeLabel: session.mode.label,
    stage: session.isPaused
        ? FocusNotificationStage.paused
        : FocusNotificationStage.active,
    stageEndsAt: session.isPaused ? null : session.endsAt,
    focusEndsAt: session.endsAt,
    pausedAt: session.isPaused ? session.pausedAt : null,
  );

  final String flowId;
  final String? appointmentId;
  final String? sessionId;
  final DateTime? pausedAt;
  final String taskTitle;
  final String modeLabel;
  final FocusNotificationStage stage;
  final DateTime? stageEndsAt;
  final DateTime focusEndsAt;

  String get notificationPayload => appointmentId == null
      ? 'session:$sessionId'
      : 'appointment:$appointmentId';

  bool get isPaused => stage == FocusNotificationStage.paused;
  bool get isPreparing => stage == FocusNotificationStage.preparation;

  int remainingSecondsAt(DateTime now) {
    final reference = isPaused ? pausedAt ?? now : now;
    return focusEndsAt.difference(reference).inSeconds.clamp(0, 24 * 60 * 60);
  }
}
