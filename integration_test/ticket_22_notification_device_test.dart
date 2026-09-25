import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phase = String.fromEnvironment('T22_NOTIFICATION_PHASE');
const _userId = 'ticket-22-device-user';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T22 Android permission and background notification delivery', (
    tester,
  ) async {
    expect(_phase, anyOf('denied', 'allowed'));

    final database = PactaDatabase(NativeDatabase.memory());
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: _userId,
      remote: InMemoryTaskRemote(),
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: _userId,
      remote: InMemoryFocusRemote(),
    );
    final goal = await taskRepository.createGoal(
      const GoalDraft(
        title: 'Ticket 22 本地验收',
        classification: TaskClassification.both,
      ),
    );
    final task = await taskRepository.createTask(
      goal.id,
      const TaskDraft(
        title: '后台专注通知验收',
        classification: TaskClassification.both,
      ),
    );

    final preferences = await SharedPreferences.getInstance();
    final preferencesStore = FocusDevicePreferencesStore(preferences);
    final notifications = FlutterLocalNotificationsPlugin();
    final service = FocusNotificationService(
      preferencesStore: preferencesStore,
      androidNotifications: notifications,
    );
    final restartedService = FocusNotificationService(
      preferencesStore: preferencesStore,
      androidNotifications: FlutterLocalNotificationsPlugin(),
    );
    final responseService = FocusNotificationService(
      preferencesStore: preferencesStore,
      androidNotifications: FlutterLocalNotificationsPlugin(),
    );
    addTearDown(() async {
      await service.clear();
      await service.dispose();
      await restartedService.clear();
      await restartedService.dispose();
      await responseService.clear();
      await responseService.dispose();
      await notifications.cancelAll();
      await focusRepository.dispose();
      await taskRepository.dispose();
      await database.close();
    });

    await service.initialize();
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: true,
      ),
    );

    var notificationPermission = await service.notificationsAllowed();
    if (_phase == 'denied') {
      expect(notificationPermission, isFalse);
      final session = await focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 2),
      );
      await service.sync(session: session, taskTitle: task.title);
      expect(
        (await database.select(database.focusSessions).getSingle()).status,
        FocusSessionStatus.active.storageValue,
      );

      final paused = await focusRepository.pauseSession(
        session.id,
        ruleText: '通知权限拒绝时仍可暂停',
      );
      await service.sync(session: paused, taskTitle: task.title);
      expect(paused.status, FocusSessionStatus.paused);
      final resumed = await focusRepository.resumeSession(session.id);
      await service.sync(session: resumed, taskTitle: task.title);
      expect(resumed.status, FocusSessionStatus.active);
      final failed = await focusRepository.abandonSession(
        sessionId: session.id,
        failureReason: '通知权限拒绝时仍可结束',
      );
      await service.sync(session: failed, taskTitle: task.title);
      expect(failed.status, FocusSessionStatus.failed);
      expect(await notifications.getActiveNotifications(), isEmpty);
      debugPrint('T22_PERMISSION_DENIED_LOCAL_FOCUS_FLOW_COMPLETED');
      return;
    }

    if (!notificationPermission) {
      debugPrint('T22_NOTIFICATION_PERMISSION_PROMPT_REQUIRED');
      notificationPermission = await service.requestNotificationPermission();
    }
    expect(notificationPermission, isTrue);
    expect(
      await service.exactAlarmsAllowed(),
      isTrue,
      reason: 'Exact alarms must be enabled before background delivery checks.',
    );

    final startedAppointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 22),
    );
    final now = DateTime.now();
    final transitionAt = now.add(const Duration(seconds: 12));
    await (database.update(database.focusAppointments)
          ..where((row) => row.userId.equals(_userId))
          ..where((row) => row.id.equals(startedAppointment.id)))
        .write(
          FocusAppointmentsCompanion(
            endsAt: Value(transitionAt),
            updatedAt: Value(now),
          ),
        );
    final appointment = AppointmentPreparation(
      id: startedAppointment.id,
      taskId: startedAppointment.taskId,
      mode: startedAppointment.mode,
      durationSeconds: startedAppointment.durationSeconds,
      startedAt: startedAppointment.startedAt,
      endsAt: transitionAt,
      status: AppointmentPreparationStatus.active,
      settledAt: null,
      updatedAt: now,
    );

    await service.sync(appointment: appointment, taskTitle: task.title);
    await service.sync(appointment: appointment, taskTitle: task.title);
    var active = await notifications.getActiveNotifications();
    expect(active.any((notification) => notification.id == 2200), isTrue);
    var pending = await notifications.pendingNotificationRequests();
    expect(
      pending.map((notification) => notification.id).toSet(),
      {2201, 2202, 2203},
      reason:
          'Repeated synchronization must replace rather than duplicate alarms.',
    );

    await restartedService.initialize();
    await restartedService.sync(
      appointment: appointment,
      taskTitle: task.title,
    );
    pending = await notifications.pendingNotificationRequests();
    expect(
      pending.map((notification) => notification.id).toSet(),
      {2201, 2202, 2203},
      reason:
          'Startup reconciliation must leave one alarm per future transition.',
    );
    expect(
      (await database.select(database.focusAppointments).getSingle()).status,
      AppointmentPreparationStatus.active.storageValue,
      reason:
          'Scheduling notifications must not settle the business appointment.',
    );
    expect(await database.select(database.focusSessions).get(), isEmpty);
    debugPrint('T22_APPOINTMENT_STATUS_AND_TRANSITIONS_SCHEDULED');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 18)),
    );
    active = await notifications.getActiveNotifications();
    expect(
      active.any((notification) => notification.id == 2201),
      isTrue,
      reason: 'Appointment transition should replace preparation status with focus status.',
    );
    expect(
      active.any((notification) => notification.id == 2202),
      isTrue,
      reason: 'The appointment-to-focus event should be delivered.',
    );
    await focusRepository.settleDueAppointments();
    final session = await focusRepository.getActiveSession();
    expect(session?.status, FocusSessionStatus.active);
    expect(session?.appointmentId, appointment.id);
    final activeSession =
        session ?? fail('Automatic transition did not create a session.');
    await restartedService.sync(session: activeSession, taskTitle: task.title);
    await restartedService.appointmentEnteredFocus(
      appointmentId: appointment.id,
      taskTitle: task.title,
    );
    active = await notifications.getActiveNotifications();
    expect(
      active.where((notification) => notification.id == 2202),
      hasLength(1),
      reason: 'The scheduled transition and observed business transition must not replay.',
    );
    debugPrint('T22_APPOINTMENT_TRANSITION_DELIVERED_AND_SETTLED_ONCE');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 20)),
    );
    final rawSession =
        await (database.select(database.focusSessions)
              ..where((row) => row.userId.equals(_userId))
              ..where((row) => row.id.equals(activeSession.id)))
            .getSingle();
    expect(rawSession.status, FocusSessionStatus.completed.storageValue);
    await focusRepository.settleDueSessions();
    final completed = await focusRepository.getSession(activeSession.id);
    expect(completed?.status, FocusSessionStatus.completed);
    await restartedService.sessionEnded(
      sessionId: activeSession.id,
      appointmentId: appointment.id,
      taskTitle: task.title,
      status: FocusSessionStatus.completed,
    );
    await restartedService.sync(session: completed, taskTitle: task.title);
    active = await notifications.getActiveNotifications();
    expect(active.any((notification) => notification.id == 2203), isTrue);
    expect(
      active.any((notification) => notification.id == 2201),
      isFalse,
      reason: 'The ongoing focus status must clear at the real focus end.',
    );
    pending = await notifications.pendingNotificationRequests();
    expect(
      pending.any((notification) => notification.id == 2202),
      isFalse,
      reason:
          'Delivered transition alerts must not remain scheduled for replay.',
    );
    debugPrint('T22_SESSION_END_DELIVERED_WITHOUT_TRANSITION_REPLAY');

    final nextAppointment = await focusRepository.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 20),
    );
    await restartedService.sync(
      appointment: nextAppointment,
      taskTitle: task.title,
    );
    await restartedService.appointmentEnteredFocus(
      appointmentId: nextAppointment.id,
      taskTitle: task.title,
    );
    active = await notifications.getActiveNotifications();
    final transitionAlerts = active
        .where((notification) => notification.id == 2202)
        .toList();
    expect(transitionAlerts, hasLength(2));
    expect(
      transitionAlerts.map((notification) => notification.tag).toSet(),
      containsAll({
        'pacta-transition-${appointment.id}',
        'pacta-transition-${nextAppointment.id}',
      }),
    );

    await restartedService.sessionEnded(
      sessionId: 'ticket-22-second-session',
      appointmentId: nextAppointment.id,
      taskTitle: task.title,
      status: FocusSessionStatus.completed,
    );
    active = await notifications.getActiveNotifications();
    final endAlerts = active
        .where((notification) => notification.id == 2203)
        .toList();
    expect(endAlerts, hasLength(2));
    expect(
      endAlerts.map((notification) => notification.tag).toSet(),
      containsAll({
        'pacta-session-end-${appointment.id}',
        'pacta-session-end-${nextAppointment.id}',
      }),
    );
    debugPrint('T22_SEQUENTIAL_FOCUS_EVENTS_REMAIN_DISTINCT');

    await notifications.cancel(
      id: 2202,
      tag: 'pacta-transition-${nextAppointment.id}',
    );
    responseService.handleNotificationResponse(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 2202,
        payload: 'appointment:${nextAppointment.id}',
      ),
    );
    await responseService.appointmentEnteredFocus(
      appointmentId: nextAppointment.id,
      taskTitle: task.title,
    );

    await notifications.cancel(
      id: 2203,
      tag: 'pacta-session-end-${nextAppointment.id}',
    );
    responseService.handleNotificationResponse(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 2203,
        payload: 'appointment:${nextAppointment.id}',
      ),
    );
    await responseService.sessionEnded(
      sessionId: 'ticket-22-second-session',
      appointmentId: nextAppointment.id,
      taskTitle: task.title,
      status: FocusSessionStatus.completed,
    );
    active = await notifications.getActiveNotifications();
    expect(
      active.where(
        (notification) =>
            notification.tag == 'pacta-transition-${nextAppointment.id}' ||
            notification.tag == 'pacta-session-end-${nextAppointment.id}',
      ),
      isEmpty,
      reason: 'Opening a scheduled event must not display it a second time.',
    );
    debugPrint('T22_TAPPED_SCHEDULED_EVENTS_NOT_REPLAYED');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
