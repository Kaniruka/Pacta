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
    this.startedAt,
    this.totalSeconds,
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
    startedAt: appointment.startedAt,
    // 进度分母取准备窗口本身：显式存过的准备时长优先，旧记录退回起止时刻。
    totalSeconds: appointment.effectivePreparationSeconds,
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
    startedAt: session.startedAt,
    totalSeconds: session.durationSeconds,
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

  /// 本段计时的起点；旧调用方不传时进度条退化为不确定进度。
  final DateTime? startedAt;

  /// 本段计时的总秒数；[startedAt] 缺失或非正时由起止时刻推导。
  final int? totalSeconds;

  String get notificationPayload => appointmentId == null
      ? 'session:$sessionId'
      : 'appointment:$appointmentId';

  bool get isPaused => stage == FocusNotificationStage.paused;
  bool get isPreparing => stage == FocusNotificationStage.preparation;

  /// 进度条分母：排程给出的总秒数优先，缺失时退回起止时刻差，最后兜底 1。
  int get progressTotalSeconds {
    final supplied = totalSeconds;
    if (supplied != null && supplied > 0) return supplied;
    final start = startedAt;
    if (start == null) return 1;
    final derived = focusEndsAt.difference(start).inSeconds;
    return derived > 0 ? derived : 1;
  }

  /// 已经过去的秒数；暂停时冻结在暂停时刻，进度条不会自己往前爬。
  ///
  /// 恢复后的会话把 [focusEndsAt] 整体向后平移了暂停时长，直接拿
  /// [startedAt] 相减会把暂停的时间也算成"专注过"，进度条一次跳满。改为
  /// 用分母减去剩余时间反推，暂停只体现为结束时刻后移，不再污染进度。
  int elapsedSecondsAt(DateTime now) {
    final start = startedAt;
    if (start == null) return 0;
    if (isPaused) {
      final frozen = pausedAt ?? now;
      return frozen.difference(start).inSeconds.clamp(0, progressTotalSeconds);
    }
    final targetEnd = isPreparing ? (stageEndsAt ?? focusEndsAt) : focusEndsAt;
    final remaining = targetEnd.difference(now).inSeconds;
    return (progressTotalSeconds - remaining).clamp(0, progressTotalSeconds);
  }

  int remainingSecondsAt(DateTime now) {
    final reference = isPaused ? pausedAt ?? now : now;
    return focusEndsAt.difference(reference).inSeconds.clamp(0, 24 * 60 * 60);
  }
}
