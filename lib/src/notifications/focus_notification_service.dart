import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../focus/focus_models.dart';
import 'focus_device_preferences.dart';
import 'focus_notification_plan.dart';
import 'national_focus_reminder_plan.dart';
import 'national_focus_reminder_state.dart';

class FocusNotificationService {
  FocusNotificationService({
    this.preferencesStore,
    this.nationalFocusReminderStateStore,
    FlutterLocalNotificationsPlugin? androidNotifications,
    MethodChannel? windowsChannel,
    DateTime Function()? now,
  }) : _androidNotifications =
           androidNotifications ?? FlutterLocalNotificationsPlugin(),
       _windowsChannel =
           windowsChannel ?? const MethodChannel('com.pacta/focus_status'),
       _now = now ?? DateTime.now;

  static const _statusNotificationId = 2200;
  static const _appointmentStatusNotificationId = 2201;
  static const _appointmentTransitionNotificationId = 2202;
  static const _sessionEndNotificationId = 2203;
  static const _nationalFocusReminderNotificationId = 2204;
  static const _statusChannelId = 'pacta_focus_status';
  static const _eventChannelId = 'pacta_focus_events';
  static const _nationalFocusReminderChannelId =
      'pacta_national_focus_reminders';
  static const _ownedNotificationIds = {
    _statusNotificationId,
    _appointmentStatusNotificationId,
    _appointmentTransitionNotificationId,
    _sessionEndNotificationId,
    _nationalFocusReminderNotificationId,
  };

  final FocusDevicePreferencesStore? preferencesStore;
  final NationalFocusReminderStateStore? nationalFocusReminderStateStore;
  final FlutterLocalNotificationsPlugin _androidNotifications;
  final MethodChannel _windowsChannel;
  final DateTime Function() _now;
  final _openFlowRequests = StreamController<String>.broadcast();

  FocusDevicePreferencesStore? _resolvedPreferencesStore;
  NationalFocusReminderStateStore? _resolvedNationalFocusReminderStateStore;
  FocusNotificationPlan? _currentPlan;
  Timer? _windowsTicker;
  Timer? _windowsNationalFocusReminderTimer;
  Future<void> _nationalFocusReminderWork = Future<void>.value();
  bool? _hasPendingNationalFocusConfirmations;
  bool _initialized = false;
  bool _timeZonesInitialized = false;
  bool _windowsTransitionPending = false;
  bool _windowsEndPending = false;
  String? _pendingOpenRequest;
  final Set<String> _notifiedAppointmentTransitions = {};
  final Set<String> _notifiedSessionEnds = {};
  final Set<String> _acknowledgedSessionEndKeys = {};

  Stream<String> get openFlowRequests => _openFlowRequests.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isWindows) return;
    if (!Platform.isAndroid) return;

    timezone_data.initializeTimeZones();
    _timeZonesInitialized = true;
    try {
      final localTimeZone = await FlutterTimezone.getLocalTimezone();
      timezone.setLocalLocation(timezone.getLocation(localTimeZone.identifier));
    } catch (_) {
      timezone.setLocalLocation(timezone.getLocation('Etc/UTC'));
    }

    await _androidNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('pacta_notification'),
      ),
      onDidReceiveNotificationResponse: handleNotificationResponse,
    );
    final launchDetails = await _androidNotifications
        .getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true && response != null) {
      handleNotificationResponse(response);
    }
  }

  Future<FocusDevicePreferences> getPreferences() async =>
      (await _settingsStore).load();

  Future<void> updatePreferences(FocusDevicePreferences preferences) async {
    await (await _settingsStore).save(preferences);
    await _applyCurrentPlan();
  }

  Future<void> syncNationalFocusReminder({
    required bool hasPendingConfirmations,
  }) async {
    _hasPendingNationalFocusConfirmations = hasPendingConfirmations;
    await _queueNationalFocusReminderReconciliation();
  }

  Future<bool> notificationsAllowed() async {
    if (Platform.isWindows) return true;
    if (!Platform.isAndroid) return false;
    final android = _androidNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<bool> requestNotificationPermission() async {
    if (Platform.isWindows) return true;
    if (!Platform.isAndroid) return false;
    final android = _androidNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> exactAlarmsAllowed() async {
    if (!Platform.isAndroid) return true;
    final android = _androidNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  Future<bool> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    final android = _androidNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestExactAlarmsPermission() ?? false;
  }

  String? takePendingOpenRequest() {
    final request = _pendingOpenRequest;
    _pendingOpenRequest = null;
    return request;
  }

  Future<void> sync({
    AppointmentPreparation? appointment,
    FocusSession? session,
    required String taskTitle,
  }) async {
    final previousPlan = _currentPlan;
    if (session != null && session.isUnfinished) {
      _currentPlan = FocusNotificationPlan.forSession(
        session,
        taskTitle: taskTitle,
      );
    } else if (appointment != null && appointment.isActive) {
      _currentPlan = FocusNotificationPlan.forAppointment(
        appointment,
        taskTitle: taskTitle,
      );
    } else {
      _currentPlan = null;
    }
    final nextPlan = _currentPlan;
    final enteredAppointmentId =
        previousPlan?.isPreparing == true &&
            previousPlan?.appointmentId != null &&
            nextPlan?.sessionId != null &&
            previousPlan!.appointmentId == nextPlan!.appointmentId
        ? previousPlan.appointmentId
        : null;
    if (enteredAppointmentId != null && nextPlan != null) {
      await appointmentEnteredFocus(
        appointmentId: enteredAppointmentId,
        taskTitle: nextPlan.taskTitle,
      );
    }
    await _applyCurrentPlan();
  }

  Future<void> appointmentEnteredFocus({
    required String appointmentId,
    required String taskTitle,
  }) async {
    final preferences = await (await _settingsStore).load();
    if (!preferences.notificationsEnabled || !await notificationsAllowed()) {
      return;
    }
    if (!_notifiedAppointmentTransitions.add(appointmentId)) return;
    try {
      if (Platform.isAndroid) {
        final notificationTag = _appointmentTransitionTag(appointmentId);
        final alreadyVisible =
            (await _androidNotifications.getActiveNotifications()).any(
              (notification) =>
                  notification.id == _appointmentTransitionNotificationId &&
                  notification.tag == notificationTag,
            );
        if (!alreadyVisible) {
          await _cancelPendingAndroidNotifications({
            _appointmentTransitionNotificationId,
          });
          await _showAndroidEvent(
            id: _appointmentTransitionNotificationId,
            title: '已进入专注',
            body: '预约准备结束，$taskTitle 开始专注。',
            payload: 'appointment:$appointmentId',
            tag: notificationTag,
          );
        }
      } else if (Platform.isWindows) {
        await _showWindowsEvent(
          title: '已进入专注',
          body: '预约准备结束，$taskTitle 开始专注。',
        );
      }
    } catch (_) {
      _notifiedAppointmentTransitions.remove(appointmentId);
    }
  }

  Future<void> sessionEnded({
    required String sessionId,
    required String taskTitle,
    required FocusSessionStatus status,
    String? appointmentId,
  }) async {
    final preferences = await (await _settingsStore).load();
    if (!preferences.notificationsEnabled || !await notificationsAllowed()) {
      return;
    }
    final eventKey = appointmentId ?? sessionId;
    final sessionWasAcknowledged = _acknowledgedSessionEndKeys.remove(
      sessionId,
    );
    final appointmentWasAcknowledged =
        appointmentId != null &&
        _acknowledgedSessionEndKeys.remove(appointmentId);
    if (sessionWasAcknowledged || appointmentWasAcknowledged) {
      _notifiedSessionEnds.add(eventKey);
      return;
    }
    if (!_notifiedSessionEnds.add(eventKey)) return;
    final ending = switch (status) {
      FocusSessionStatus.completed => '专注已完成',
      FocusSessionStatus.failed => '专注已结束',
      _ => '专注已结束',
    };
    try {
      if (Platform.isAndroid) {
        final notificationTag = _sessionEndTag(eventKey);
        final alreadyVisible =
            (await _androidNotifications.getActiveNotifications()).any(
              (notification) =>
                  notification.id == _sessionEndNotificationId &&
                  notification.tag == notificationTag,
            );
        if (!alreadyVisible) {
          await _cancelPendingAndroidNotifications({_sessionEndNotificationId});
          await _showAndroidEvent(
            id: _sessionEndNotificationId,
            title: ending,
            body: '$taskTitle 的专注会话已结束。',
            payload: 'session:$sessionId',
            tag: notificationTag,
          );
        }
      } else if (Platform.isWindows) {
        await _showWindowsEvent(title: ending, body: '$taskTitle 的专注会话已结束。');
      }
    } catch (_) {
      _notifiedSessionEnds.remove(eventKey);
    }
  }

  Future<void> clear() async {
    _currentPlan = null;
    _hasPendingNationalFocusConfirmations = false;
    _windowsTicker?.cancel();
    _windowsNationalFocusReminderTimer?.cancel();
    if (Platform.isAndroid) {
      await _cancelPendingAndroidNotifications(_ownedNotificationIds);
      await _androidNotifications.cancel(id: _statusNotificationId);
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
    } else if (Platform.isWindows) {
      await _windowsChannel.invokeMethod<void>('clearStatus');
    }
    await (await _reminderStateStore).clearScheduled();
  }

  Future<void> dispose() async {
    _windowsTicker?.cancel();
    _windowsNationalFocusReminderTimer?.cancel();
    await _openFlowRequests.close();
  }

  Future<FocusDevicePreferencesStore> get _settingsStore async {
    final supplied = preferencesStore;
    if (supplied != null) return supplied;
    return _resolvedPreferencesStore ??= FocusDevicePreferencesStore(
      await SharedPreferences.getInstance(),
    );
  }

  Future<NationalFocusReminderStateStore> get _reminderStateStore async {
    final supplied = nationalFocusReminderStateStore;
    if (supplied != null) return supplied;
    return _resolvedNationalFocusReminderStateStore ??=
        NationalFocusReminderStateStore(await SharedPreferences.getInstance());
  }

  Future<void> _applyCurrentPlan() async {
    final preferences = await (await _settingsStore).load();
    if (Platform.isWindows) {
      await _applyWindowsPlan(preferences);
    } else if (Platform.isAndroid) {
      await _applyAndroidPlan(preferences);
    }
    await _queueNationalFocusReminderReconciliation();
  }

  Future<void> _queueNationalFocusReminderReconciliation() {
    final operation = _nationalFocusReminderWork.then(
      (_) => _reconcileNationalFocusReminder(),
    );
    _nationalFocusReminderWork = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _reconcileNationalFocusReminder() async {
    final preferences = await (await _settingsStore).load();
    final state = await _reminderStateStore;
    if (_hasPendingNationalFocusConfirmations == null &&
        preferences.nationalFocusReminderEnabled) {
      return;
    }

    if (!preferences.nationalFocusReminderEnabled ||
        _hasPendingNationalFocusConfirmations != true ||
        (!Platform.isAndroid && !Platform.isWindows) ||
        (Platform.isAndroid && !await notificationsAllowed())) {
      await _cancelNationalFocusReminder(state);
      return;
    }

    final now = _now().toUtc();
    final lastSentDayKey = state.loadLastSentDayKey();
    var reminder = NationalFocusReminderPlan.next(
      now: now,
      minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
      hasPendingConfirmations: true,
      lastNotifiedDayKey: lastSentDayKey,
      activeFlow: _currentPlan,
    );
    if (reminder == null) {
      await _cancelNationalFocusReminder(state);
      return;
    }

    if (Platform.isWindows) {
      await _applyWindowsNationalFocusReminder(reminder, preferences, state);
      return;
    }

    await _applyAndroidNationalFocusReminder(reminder, preferences, state);
  }

  Future<void> _cancelNationalFocusReminder(
    NationalFocusReminderStateStore state,
  ) async {
    _windowsNationalFocusReminderTimer?.cancel();
    if (Platform.isAndroid) {
      await _androidNotifications.cancel(
        id: _nationalFocusReminderNotificationId,
      );
    }
    await state.clearScheduled();
  }

  Future<void> _applyWindowsNationalFocusReminder(
    NationalFocusReminderPlan? reminder,
    FocusDevicePreferences preferences,
    NationalFocusReminderStateStore state,
  ) async {
    _windowsNationalFocusReminderTimer?.cancel();
    if (reminder == null) return;

    final now = _now().toUtc();
    if (reminder.scheduledAt.isAfter(now)) {
      await state.saveScheduled(
        NationalFocusReminderSchedule(
          dayKey: reminder.dayKey,
          scheduledAt: reminder.scheduledAt,
          repeatsDaily: false,
        ),
      );
      _windowsNationalFocusReminderTimer = Timer(
        reminder.scheduledAt.difference(now),
        () => unawaited(_queueNationalFocusReminderReconciliation()),
      );
      return;
    }

    await _showWindowsEvent(title: '国策待确认', body: '请确认今天仍然有效的国策。');
    await state.markSent(reminder.dayKey);
    final nextReminder = NationalFocusReminderPlan.next(
      now: _now(),
      minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
      hasPendingConfirmations: _hasPendingNationalFocusConfirmations == true,
      lastNotifiedDayKey: reminder.dayKey,
      activeFlow: _currentPlan,
    );
    if (nextReminder != null && nextReminder.scheduledAt.isAfter(_now())) {
      await state.saveScheduled(
        NationalFocusReminderSchedule(
          dayKey: nextReminder.dayKey,
          scheduledAt: nextReminder.scheduledAt,
          repeatsDaily: false,
        ),
      );
      _windowsNationalFocusReminderTimer = Timer(
        nextReminder.scheduledAt.difference(_now()),
        () => unawaited(_queueNationalFocusReminderReconciliation()),
      );
    }
  }

  Future<void> _applyAndroidNationalFocusReminder(
    NationalFocusReminderPlan reminder,
    FocusDevicePreferences preferences,
    NationalFocusReminderStateStore state,
  ) async {
    final now = _now().toUtc();
    final scheduled = state.loadScheduled();
    final pending = await _androidNotifications.pendingNotificationRequests();
    final hasPendingReminder = pending.any(
      (request) => request.id == _nationalFocusReminderNotificationId,
    );

    if (scheduled != null &&
        !scheduled.scheduledAt.isAfter(now) &&
        !hasPendingReminder) {
      await state.markSent(scheduled.dayKey);
      final nextReminder = NationalFocusReminderPlan.next(
        now: now,
        minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
        hasPendingConfirmations: true,
        lastNotifiedDayKey: scheduled.dayKey,
        activeFlow: _currentPlan,
      );
      if (nextReminder == null) {
        await _cancelNationalFocusReminder(state);
        return;
      }
      await _scheduleAndroidNationalFocusReminder(nextReminder, state, now);
      return;
    }

    if (!reminder.scheduledAt.isAfter(now)) {
      if (hasPendingReminder &&
          scheduled?.repeatsDaily == true &&
          state.loadLastSentDayKey() != reminder.dayKey) {
        await state.markSent(reminder.dayKey);
        final nextReminder = NationalFocusReminderPlan.next(
          now: now,
          minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
          hasPendingConfirmations: true,
          lastNotifiedDayKey: reminder.dayKey,
          activeFlow: _currentPlan,
        );
        if (nextReminder != null) {
          await _scheduleAndroidNationalFocusReminder(nextReminder, state, now);
        }
        return;
      }

      await _androidNotifications.cancel(
        id: _nationalFocusReminderNotificationId,
      );
      await _androidNotifications.show(
        id: _nationalFocusReminderNotificationId,
        title: '国策待确认',
        body: '请确认今天仍然有效的国策。',
        notificationDetails: _nationalFocusReminderDetails(),
        payload: 'national-focus-reminder:${reminder.dayKey}',
      );
      await state.markSent(reminder.dayKey);
      final nextReminder = NationalFocusReminderPlan.next(
        now: _now(),
        minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
        hasPendingConfirmations: true,
        lastNotifiedDayKey: reminder.dayKey,
        activeFlow: _currentPlan,
      );
      if (nextReminder != null) {
        await _scheduleAndroidNationalFocusReminder(
          nextReminder,
          state,
          _now().toUtc(),
        );
      }
      return;
    }

    final isAlreadyScheduled =
        hasPendingReminder &&
        scheduled != null &&
        scheduled.dayKey == reminder.dayKey &&
        scheduled.scheduledAt.isAtSameMomentAs(reminder.scheduledAt) &&
        scheduled.repeatsDaily == !reminder.isDeferred;
    if (isAlreadyScheduled) return;

    await _scheduleAndroidNationalFocusReminder(reminder, state, now);
  }

  Future<void> _scheduleAndroidNationalFocusReminder(
    NationalFocusReminderPlan reminder,
    NationalFocusReminderStateStore state,
    DateTime now,
  ) async {
    final repeatsDaily = !reminder.isDeferred;
    if (!reminder.scheduledAt.isAfter(now)) {
      await _androidNotifications.cancel(
        id: _nationalFocusReminderNotificationId,
      );
      await _androidNotifications.show(
        id: _nationalFocusReminderNotificationId,
        title: '国策待确认',
        body: '请确认今天仍然有效的国策。',
        notificationDetails: _nationalFocusReminderDetails(),
        payload: 'national-focus-reminder:${reminder.dayKey}',
      );
      await state.markSent(reminder.dayKey);
      final preferences = await (await _settingsStore).load();
      final nextReminder = NationalFocusReminderPlan.next(
        now: _now(),
        minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
        hasPendingConfirmations: _hasPendingNationalFocusConfirmations == true,
        lastNotifiedDayKey: reminder.dayKey,
        activeFlow: _currentPlan,
      );
      if (nextReminder != null) {
        await _scheduleAndroidNationalFocusReminder(
          nextReminder,
          state,
          _now().toUtc(),
        );
      }
      return;
    }

    // Reusing this id replaces the pending alarm; cancelling first would also
    // dismiss a reminder that was just shown with the same id.
    final exactAllowed = await exactAlarmsAllowed();
    await _androidNotifications.zonedSchedule(
      id: _nationalFocusReminderNotificationId,
      title: '国策待确认',
      body: '请确认今天仍然有效的国策。',
      scheduledDate: timezone.TZDateTime.from(
        reminder.scheduledAt,
        _beijingLocation,
      ),
      notificationDetails: _nationalFocusReminderDetails(),
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'national-focus-reminder:${reminder.dayKey}',
      matchDateTimeComponents: repeatsDaily ? DateTimeComponents.time : null,
    );
    await state.saveScheduled(
      NationalFocusReminderSchedule(
        dayKey: reminder.dayKey,
        scheduledAt: reminder.scheduledAt,
        repeatsDaily: repeatsDaily,
      ),
    );
  }

  timezone.Location get _beijingLocation {
    if (!_timeZonesInitialized) {
      timezone_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    return timezone.getLocation('Asia/Shanghai');
  }

  Future<void> _applyAndroidPlan(FocusDevicePreferences preferences) async {
    final plan = _currentPlan;
    final permissionAllowed =
        preferences.notificationsEnabled && await notificationsAllowed();
    final showStatus =
        permissionAllowed && preferences.backgroundRunningEnabled;
    final expectedPendingIds = <int>{};
    if (permissionAllowed && plan != null) {
      if (plan.isPreparing) {
        final transitionAt = plan.stageEndsAt!;
        if (transitionAt.isAfter(_now())) {
          expectedPendingIds.addAll({
            _appointmentTransitionNotificationId,
            _appointmentStatusNotificationId,
            _sessionEndNotificationId,
          });
        }
      } else if (!plan.isPaused && plan.focusEndsAt.isAfter(_now())) {
        expectedPendingIds.add(_sessionEndNotificationId);
      }
    }
    // National Focus reminder reconciliation owns this id and must distinguish
    // a delivered alarm from an alarm removed while updating focus state.
    await _cancelStalePendingAndroidNotifications({
      ...expectedPendingIds,
      _nationalFocusReminderNotificationId,
    });

    if (!showStatus || plan == null) {
      await _androidNotifications.cancel(id: _statusNotificationId);
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
    } else if (plan.isPreparing) {
      await _showAndroidStatus(
        id: _statusNotificationId,
        title: '预约准备中',
        body: '${plan.taskTitle} · ${plan.modeLabel}',
        endAt: plan.stageEndsAt,
        timeoutAt: plan.stageEndsAt,
        payload: plan.notificationPayload,
      );
      final transitionAt = plan.stageEndsAt!;
      if (transitionAt.isAfter(_now())) {
        await _scheduleAndroidNotification(
          id: _appointmentTransitionNotificationId,
          title: '已进入专注',
          body: '预约准备结束，${plan.taskTitle} 开始专注。',
          at: transitionAt,
          payload: plan.notificationPayload,
          details: _eventDetails(
            tag: _appointmentTransitionTag(plan.appointmentId ?? plan.flowId),
          ),
        );
        await _scheduleAndroidNotification(
          id: _appointmentStatusNotificationId,
          title: '专注中',
          body: '${plan.taskTitle} · ${plan.modeLabel}',
          at: transitionAt,
          payload: plan.notificationPayload,
          details: _statusDetails(
            endAt: plan.focusEndsAt,
            timeoutAfter: Duration(
              seconds: plan.focusEndsAt.difference(transitionAt).inSeconds,
            ),
          ),
        );
        await _scheduleAndroidNotification(
          id: _sessionEndNotificationId,
          title: '专注已结束',
          body: '${plan.taskTitle} 的专注会话已结束。',
          at: plan.focusEndsAt,
          payload: plan.notificationPayload,
          details: _eventDetails(
            tag: _sessionEndTag(
              plan.appointmentId ?? plan.sessionId ?? plan.flowId,
            ),
          ),
        );
      }
    } else if (plan.isPaused) {
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
      await _androidNotifications.cancel(id: _statusNotificationId);
      final secondsRemaining = plan.remainingSecondsAt(_now());
      await _androidNotifications.show(
        id: _statusNotificationId,
        title: '专注已暂停',
        body: '${plan.taskTitle} · 剩余 ${_formatClock(secondsRemaining)}',
        notificationDetails: _statusDetails(),
        payload: plan.notificationPayload,
      );
    } else {
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
      await _showAndroidStatus(
        id: _statusNotificationId,
        title: '专注中',
        body: '${plan.taskTitle} · ${plan.modeLabel}',
        endAt: plan.focusEndsAt,
        timeoutAt: plan.focusEndsAt,
        payload: plan.notificationPayload,
      );
      if (plan.focusEndsAt.isAfter(_now())) {
        await _scheduleAndroidNotification(
          id: _sessionEndNotificationId,
          title: '专注已结束',
          body: '${plan.taskTitle} 的专注会话已结束。',
          at: plan.focusEndsAt,
          payload: plan.notificationPayload,
          details: _eventDetails(
            tag: _sessionEndTag(
              plan.appointmentId ?? plan.sessionId ?? plan.flowId,
            ),
          ),
        );
      }
    }
  }

  Future<void> _applyWindowsPlan(FocusDevicePreferences preferences) async {
    await _windowsChannel.invokeMethod<void>(
      'setBackgroundRunningEnabled',
      preferences.backgroundRunningEnabled,
    );
    _windowsTicker?.cancel();
    final plan = _currentPlan;
    if (plan == null) {
      await _windowsChannel.invokeMethod<void>('clearStatus');
      return;
    }
    _windowsTransitionPending =
        plan.isPreparing && plan.stageEndsAt!.isAfter(_now());
    _windowsEndPending = !plan.isPaused && plan.focusEndsAt.isAfter(_now());
    await _renderWindowsStatus(plan, preferences);
    _windowsTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tickWindows(plan, preferences));
    });
  }

  Future<void> _tickWindows(
    FocusNotificationPlan plan,
    FocusDevicePreferences preferences,
  ) async {
    final now = _now();
    if (plan.isPreparing &&
        _windowsTransitionPending &&
        !plan.stageEndsAt!.isAfter(now)) {
      _windowsTransitionPending = false;
      await appointmentEnteredFocus(
        appointmentId: plan.appointmentId ?? plan.flowId,
        taskTitle: plan.taskTitle,
      );
    }
    if (!plan.isPaused &&
        _windowsEndPending &&
        !plan.focusEndsAt.isAfter(now)) {
      _windowsEndPending = false;
      await sessionEnded(
        sessionId: plan.sessionId ?? plan.flowId,
        appointmentId: plan.appointmentId,
        taskTitle: plan.taskTitle,
        status: FocusSessionStatus.completed,
      );
      _currentPlan = null;
      _windowsTicker?.cancel();
      await _windowsChannel.invokeMethod<void>('clearStatus');
      return;
    }
    if (identical(_currentPlan, plan)) {
      await _renderWindowsStatus(plan, preferences);
    }
  }

  Future<void> _renderWindowsStatus(
    FocusNotificationPlan plan,
    FocusDevicePreferences preferences,
  ) async {
    String status;
    var active = true;
    if (plan.isPaused) {
      final seconds = plan.remainingSecondsAt(_now());
      status = '专注已暂停 · ${_formatClock(seconds)} · ${plan.taskTitle}';
    } else if (plan.isPreparing && plan.stageEndsAt!.isAfter(_now())) {
      final seconds = plan.stageEndsAt!.difference(_now()).inSeconds;
      status = '预约准备中 · ${_formatClock(seconds)} · ${plan.taskTitle}';
    } else {
      final seconds = plan.focusEndsAt
          .difference(_now())
          .inSeconds
          .clamp(0, 24 * 60 * 60);
      status = '专注中 · ${_formatClock(seconds)} · ${plan.taskTitle}';
    }
    if (!preferences.backgroundRunningEnabled) active = false;
    await _windowsChannel.invokeMethod<void>('updateStatus', {
      'text': status,
      'active': active,
    });
  }

  Future<void> _showWindowsEvent({
    required String title,
    required String body,
  }) => _windowsChannel.invokeMethod<void>('showNotification', {
    'title': title,
    'body': body,
  });

  Future<void> _showAndroidStatus({
    required int id,
    required String title,
    required String body,
    required DateTime? endAt,
    required DateTime? timeoutAt,
    Duration? timeoutAfter,
    required String payload,
  }) => _androidNotifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: _statusDetails(
      endAt: endAt,
      timeoutAt: timeoutAt,
      timeoutAfter: timeoutAfter,
    ),
    payload: payload,
  );

  NotificationDetails _nationalFocusReminderDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _nationalFocusReminderChannelId,
      '国策待确认',
      channelDescription: '有待今日确认的国策时提醒。',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      autoCancel: true,
      onlyAlertOnce: true,
    ),
  );

  NotificationDetails _statusDetails({
    DateTime? endAt,
    DateTime? timeoutAt,
    Duration? timeoutAfter,
  }) {
    final timeout =
        timeoutAfter?.inMilliseconds ??
        timeoutAt?.difference(_now()).inMilliseconds;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        '专注状态',
        channelDescription: '显示正在进行的预约或专注倒计时。',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: false,
        usesChronometer: endAt != null,
        chronometerCountDown: endAt != null,
        when: endAt?.millisecondsSinceEpoch,
        timeoutAfter: timeout == null || timeout <= 0 ? null : timeout,
      ),
    );
  }

  NotificationDetails _eventDetails({required String tag}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _eventChannelId,
          '专注转换提醒',
          channelDescription: '预约进入专注或专注会话结束时提醒。',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.event,
          autoCancel: true,
          onlyAlertOnce: true,
          tag: tag,
        ),
      );

  Future<void> _scheduleAndroidNotification({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required String payload,
    required NotificationDetails details,
  }) async {
    if (!at.isAfter(_now())) return;
    final exactAllowed = await exactAlarmsAllowed();
    await _androidNotifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: timezone.TZDateTime.from(at, timezone.local),
      notificationDetails: details,
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  Future<void> _showAndroidEvent({
    required int id,
    required String title,
    required String body,
    required String payload,
    required String tag,
  }) => _androidNotifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: _eventDetails(tag: tag),
    payload: payload,
  );

  Future<void> _cancelStalePendingAndroidNotifications(
    Set<int> expectedIds,
  ) async {
    await _cancelPendingAndroidNotifications(
      _ownedNotificationIds.difference(expectedIds),
    );
  }

  Future<void> _cancelPendingAndroidNotifications(Set<int> ids) async {
    final pending = await _androidNotifications.pendingNotificationRequests();
    for (final request in pending) {
      if (ids.contains(request.id)) {
        await _androidNotifications.cancel(id: request.id);
      }
    }
  }

  @visibleForTesting
  void handleNotificationResponse(NotificationResponse response) {
    if (response.notificationResponseType !=
        NotificationResponseType.notificationDismissed) {
      final payload = response.payload;
      if (response.id == _appointmentTransitionNotificationId &&
          payload?.startsWith('appointment:') == true) {
        _notifiedAppointmentTransitions.add(payload!.substring(12));
      } else if (response.id == _sessionEndNotificationId && payload != null) {
        final eventKey = _eventKeyFromPayload(payload);
        if (eventKey != null) _acknowledgedSessionEndKeys.add(eventKey);
      }
    }
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _pendingOpenRequest = payload;
    _openFlowRequests.add(payload);
  }

  String _formatClock(int seconds) {
    final bounded = seconds.clamp(0, 24 * 60 * 60);
    final minutes = bounded ~/ 60;
    final remainder = bounded % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  String _appointmentTransitionTag(String appointmentId) =>
      'pacta-transition-$appointmentId';

  String _sessionEndTag(String eventKey) => 'pacta-session-end-$eventKey';

  String? _eventKeyFromPayload(String payload) {
    if (payload.startsWith('appointment:')) return payload.substring(12);
    if (payload.startsWith('session:')) return payload.substring(8);
    return null;
  }
}

class DisabledFocusNotificationService extends FocusNotificationService {
  DisabledFocusNotificationService()
    : super(androidNotifications: FlutterLocalNotificationsPlugin());

  @override
  Future<void> initialize() async {}

  @override
  Future<FocusDevicePreferences> getPreferences() async =>
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: false,
        nationalFocusReminderEnabled: false,
      );

  @override
  Future<void> updatePreferences(FocusDevicePreferences preferences) async {}

  @override
  Future<bool> notificationsAllowed() async => false;

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<bool> exactAlarmsAllowed() async => false;

  @override
  Future<bool> requestExactAlarmPermission() async => false;

  @override
  String? takePendingOpenRequest() => null;

  @override
  Future<void> sync({
    AppointmentPreparation? appointment,
    FocusSession? session,
    required String taskTitle,
  }) async {}

  @override
  Future<void> syncNationalFocusReminder({
    required bool hasPendingConfirmations,
  }) async {}

  @override
  Future<void> appointmentEnteredFocus({
    required String appointmentId,
    required String taskTitle,
  }) async {}

  @override
  Future<void> sessionEnded({
    required String sessionId,
    String? appointmentId,
    required String taskTitle,
    required FocusSessionStatus status,
  }) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}
