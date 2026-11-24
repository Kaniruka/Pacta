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
import '../schedules/schedule_models.dart';
import 'daily_open_reminder_plan.dart';
import 'daily_open_reminder_state.dart';
import 'device_permission_gateway.dart';
import 'focus_device_preferences.dart';
import 'focus_notification_plan.dart';
import 'focus_timer_service_gateway.dart';
import 'national_focus_reminder_plan.dart';
import 'national_focus_reminder_state.dart';
import 'schedule_reminder_plan.dart';
import 'windows_notification_adapter.dart';

class FocusNotificationService {
  FocusNotificationService({
    this.preferencesStore,
    this.nationalFocusReminderStateStore,
    this.dailyOpenReminderStateStore,
    FlutterLocalNotificationsPlugin? androidNotifications,
    MethodChannel? windowsChannel,
    DateTime Function()? now,
    this.localTimeZone,
    this.permissionGateway,
    this.windowsNotifications,
    this.accountTimeZoneReader,
    this.timerServiceGateway,
    Timer Function(Duration delay, void Function() callback)? reminderTimers,
  }) : _androidNotifications =
           androidNotifications ?? FlutterLocalNotificationsPlugin(),
       _windowsChannel =
           windowsChannel ?? const MethodChannel('com.pacta/focus_status'),
       _now = now ?? DateTime.now,
       _reminderTimers = reminderTimers ?? Timer.new;

  static const _statusNotificationId = 2200;
  static const _appointmentStatusNotificationId = 2201;
  static const _appointmentTransitionNotificationId = 2202;
  static const _sessionEndNotificationId = 2203;
  static const _nationalFocusReminderNotificationId = 2204;
  static const _dailyOpenReminderNotificationId = 2205;
  // v2：渠道的重要性创建后不可改，升级强提醒只能换新 id 并重建。
  static const _statusChannelId = 'pacta_focus_status_v2';
  static const _eventChannelId = 'pacta_focus_events_v2';
  static const _nationalFocusReminderChannelId =
      'pacta_national_focus_reminders_v2';
  static const _dailyOpenReminderChannelId = 'pacta_daily_open_reminders_v2';
  static const _scheduleReminderChannelId = 'pacta_schedule_reminders_v2';

  /// 旧 v1 渠道：创建时按"默认重要性"落地，无法原地升级，初始化时删掉。
  static const _legacyChannelIds = <String>[
    'pacta_focus_status',
    'pacta_focus_events',
    'pacta_national_focus_reminders',
    'pacta_daily_open_reminders',
    'pacta_schedule_reminders',
  ];
  static const _ownedNotificationIds = {
    _statusNotificationId,
    _appointmentStatusNotificationId,
    _appointmentTransitionNotificationId,
    _sessionEndNotificationId,
    _nationalFocusReminderNotificationId,
    _dailyOpenReminderNotificationId,
  };

  final FocusDevicePreferencesStore? preferencesStore;
  final NationalFocusReminderStateStore? nationalFocusReminderStateStore;
  final DailyOpenReminderStateStore? dailyOpenReminderStateStore;
  final FlutterLocalNotificationsPlugin _androidNotifications;
  final MethodChannel _windowsChannel;
  final DateTime Function() _now;
  final Future<String> Function()? localTimeZone;
  final DevicePermissionGateway? permissionGateway;
  final WindowsNotificationAdapter? windowsNotifications;

  /// 专注进度前台服务的可测试边界；为空时按平台取生产实现。
  final FocusTimerServiceGateway? timerServiceGateway;

  /// 账号时区（IANA）。国策待确认提醒按该时区的当地墙钟排程；未提供时沿用
  /// 北京时间，旧调用方与旧测试的行为不变。
  final Future<String> Function()? accountTimeZoneReader;

  final Timer Function(Duration delay, void Function() callback)
  _reminderTimers;
  final _openFlowRequests = StreamController<String>.broadcast();
  final _openScheduleRequests =
      StreamController<ScheduleReminderRequest>.broadcast();

  FocusDevicePreferencesStore? _resolvedPreferencesStore;
  NationalFocusReminderStateStore? _resolvedNationalFocusReminderStateStore;
  DailyOpenReminderStateStore? _resolvedDailyOpenReminderStateStore;
  FocusNotificationPlan? _currentPlan;
  Timer? _windowsTicker;
  Timer? _windowsNationalFocusReminderTimer;
  Timer? _dailyOpenReminderTimer;
  Future<void> _nationalFocusReminderWork = Future<void>.value();
  Future<void> _dailyOpenReminderWork = Future<void>.value();
  String? _ownerUserId;
  int _ownerGeneration = 0;
  bool _permissionRequestInFlight = false;

  /// Pending owner release; null means the previous owner is fully settled.
  Future<void>? _ownerSwitch;

  /// Replaces the slow cancellation of an owner switch in tests.
  @visibleForTesting
  Future<void> Function()? ownerSwitchWork;
  bool? _hasPendingNationalFocusConfirmations;
  bool _initialized = false;
  bool _timeZonesInitialized = false;
  bool _windowsTransitionPending = false;
  bool _windowsEndPending = false;
  WindowsNotificationAdapter? _resolvedWindowsNotifications;
  bool _windowsNotificationsInitialized = false;
  bool _windowsScheduleReady = false;
  FocusTimerServiceGateway? _resolvedTimerServiceGateway;
  final Map<int, _WindowsScheduledEvent> _windowsFocusScheduled = {};
  final Map<int, ScheduleReminderPlan> _plannedScheduleReminders = {};
  _ScheduleReminderSnapshot? _lastScheduleSnapshot;
  Future<void> _scheduleReminderWork = Future<void>.value();
  Future<void> _windowsPlanWork = Future<void>.value();
  int _windowsPlanRevision = 0;
  int _scheduleReminderEpoch = 0;
  String? _pendingOpenRequest;
  final Set<String> _notifiedAppointmentTransitions = {};
  final Set<String> _notifiedSessionEnds = {};
  final Set<String> _acknowledgedSessionEndKeys = {};

  Stream<String> get openFlowRequests => _openFlowRequests.stream;

  /// Clicks on ordinary schedule reminders.
  ///
  /// They stay separate from [openFlowRequests]: a reminder is not a focus
  /// commitment, so the Plan destination owns the follow-up navigation.
  Stream<ScheduleReminderRequest> get openScheduleRequests =>
      _openScheduleRequests.stream;

  /// The account this service currently schedules reminders for.
  ///
  /// Null means signed out: no schedule may be registered until a later
  /// [setUserId] binds an owner.
  String? get ownerUserId => _ownerUserId;

  ScheduleReminderRequest? _pendingScheduleRequest;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isWindows) {
      // The Windows tray sends the payload back when its reminder is clicked.
      _windowsChannel.setMethodCallHandler(_handleWindowsCall);
      // Ordinary reminders and focus transitions are registered with the OS
      // scheduler so they survive a normal process exit. The tray channel stays
      // the in-process countdown surface only.
      try {
        final adapter =
            windowsNotifications ??
            (_resolvedWindowsNotifications =
                RunnerWindowsNotificationAdapter());
        _windowsNotificationsInitialized = true;
        _windowsScheduleReady = await adapter.initialize(
          onResponse: handleNotificationResponse,
        );
      } catch (_) {
        // Hosts without the native plugin (unit tests, unsupported builds)
        // keep the tray channel; ordinary reminders stay unregistered there.
        _windowsScheduleReady = false;
      }
      return;
    }
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
    await _ensureAndroidChannels();
    await _attachFocusTimerChannel();
    final launchDetails = await _androidNotifications
        .getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true && response != null) {
      handleNotificationResponse(response);
    }
  }

  /// 删掉 5 个 v1 渠道并预创建 5 个 v2 渠道。
  ///
  /// 渠道重要性一旦创建就不可修改，所以"升级为强提醒"只能换 id：旧渠道删掉
  /// 之后系统设置里不会同时留下两套语义冲突的开关。预创建让用户在第一条通知
  /// 出现之前就能看到并使用最终的重要性、声音与锁屏可见性。
  Future<void> _ensureAndroidChannels() async {
    final android = _androidNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final channelId in _legacyChannelIds) {
      try {
        await android.deleteNotificationChannel(channelId: channelId);
      } catch (_) {
        // 删除一个从未创建过的渠道不是状态变化。
      }
    }
    for (final channel in _androidChannels()) {
      try {
        await android.createNotificationChannel(channel);
      } catch (_) {
        // 宿主不支持渠道管理时，通知自身仍会按详情里的语义创建渠道。
      }
    }
  }

  /// 5 个 v2 渠道的声明，与各通知细节里的重要性保持一一对应。
  List<AndroidNotificationChannel> _androidChannels() => const [
    AndroidNotificationChannel(
      _statusChannelId,
      '专注状态',
      description: '显示正在进行的预约或专注倒计时。',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    ),
    AndroidNotificationChannel(
      _eventChannelId,
      '专注转换提醒',
      description: '预约进入专注或专注会话结束时提醒。',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      _nationalFocusReminderChannelId,
      '国策待确认',
      description: '有国策待确认时提醒。',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      _dailyOpenReminderChannelId,
      '每日打开提醒',
      description: '每天在本机当地时间提醒打开 Pacta 看板。',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      _scheduleReminderChannelId,
      '日程提醒',
      description: '普通日程到点时提醒；不开始专注，也不改变链记录。',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ),
  ];

  /// 连接前台服务通道：点按实时进度通知回到进行中的会话，冷启动补取负载。
  Future<void> _attachFocusTimerChannel() async {
    final gateway = _timerService;
    if (gateway is! MethodChannelFocusTimerServiceGateway) return;
    gateway.attach(onTapped: _handleFocusTimerPayload);
    _handleFocusTimerPayload(await gateway.takePendingLaunchPayload());
  }

  void _handleFocusTimerPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    // 复用同一条响应路径：普通会话负载与日程提醒负载的解析规则保持一致。
    handleNotificationResponse(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: payload,
      ),
    );
  }

  Future<dynamic> _handleWindowsCall(MethodCall call) async {
    if (call.method != 'notificationClicked') return null;
    final payload = call.arguments;
    if (payload is! String || payload.isEmpty) return null;
    _pendingOpenRequest = payload;
    _openFlowRequests.add(payload);
    return null;
  }

  Future<FocusDevicePreferences> getPreferences() async =>
      (await _settingsStore).load();

  Future<void> updatePreferences(FocusDevicePreferences preferences) async {
    await (await _settingsStore).save(preferences);
    await _applyCurrentPlan();
    // Disabling must cancel the ordinary reminders immediately; enabling only
    // re-registers future instances, never the missed ones.
    await _reconcileFromLastSnapshot();
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

  /// Asks for the notification permission at the first user action that needs
  /// it, and never repeats the system prompt afterwards.
  ///
  /// The lock is taken synchronously, the settings store is captured for this
  /// attempt, and the outcome is only recorded for the same owner that asked.
  /// Other device settings are never rewritten and no failure escapes into the
  /// calling business action.
  Future<bool> ensureNotificationPermissionForUse() async {
    if (_permissionRequestInFlight) return false;
    _permissionRequestInFlight = true;
    final generation = _ownerGeneration;
    try {
      final store = await _settingsStore;
      final preferences = await store.load();
      // 常驻倒计时状态通知也依赖通知权限：只开了后台运行开关时同样要申请，
      // 否则状态栏永远不出现倒计时。
      if (!preferences.notificationsEnabled &&
          !preferences.backgroundRunningEnabled) {
        return false;
      }
      if (await notificationsAllowed()) return true;
      if (preferences.notificationPermissionRequested) return false;
      if (_staleOwner(generation)) return false;

      final allowed = await requestNotificationPermission();
      if (_staleOwner(generation)) return allowed;
      await store.markNotificationPermissionRequested();
      if (allowed) {
        unawaited(_applyCurrentPlan().catchError((Object _) {}));
        unawaited(_reconcileFromLastSnapshot().catchError((Object _) {}));
      }
      return allowed;
    } catch (_) {
      // A platform or store failure must not break the user's action.
      return false;
    } finally {
      _permissionRequestInFlight = false;
    }
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

  /// Opens the system screen that owns this app's notification permission.
  Future<void> openNotificationSettings() =>
      _permissions.openNotificationSettings();

  /// Opens this app's system settings page, where calendar access lives.
  Future<void> openAppSettings() => _permissions.openAppSettings();

  DevicePermissionGateway get _permissions =>
      permissionGateway ?? createDevicePermissionGateway();

  /// Android 上是真实的前台服务通道，其余平台是空实现。
  FocusTimerServiceGateway get _timerService =>
      timerServiceGateway ??
      (_resolvedTimerServiceGateway ??= createFocusTimerServiceGateway());

  /// The Windows OS scheduling adapter, or null when this process may not use
  /// one (not Windows, not initialized yet, or the OS registration failed).
  Future<WindowsNotificationAdapter?> _scheduleAdapter() async {
    if (!Platform.isWindows) return null;
    final injected = windowsNotifications;
    final adapter =
        injected ??
        (_windowsNotificationsInitialized
            ? _resolvedWindowsNotifications
            : null);
    if (adapter == null) return null;
    if (!_windowsNotificationsInitialized) {
      _windowsNotificationsInitialized = true;
      _windowsScheduleReady = await adapter.initialize(
        onResponse: handleNotificationResponse,
      );
    }
    return _windowsScheduleReady ? adapter : null;
  }

  /// Stops this process's listeners and timers when the shell goes away.
  ///
  /// A normal exit must keep future OS-scheduled reminders: an explicit sign-out
  /// or account switch is the only path that cancels them.
  Future<void> detachForProcessExit() async {
    _windowsTicker?.cancel();
    _windowsTicker = null;
    _windowsNationalFocusReminderTimer?.cancel();
    _dailyOpenReminderTimer?.cancel();
    _dailyOpenReminderTimer = null;
    if (Platform.isWindows) _windowsChannel.setMethodCallHandler(null);
  }

  /// Reconciles the ordinary schedule reminders the OS should still deliver.
  ///
  /// Only future instances are registered; a missed reminder is never replayed
  /// in a batch. Ordinary reminders never start a session, settle a chain or
  /// write a record of their own.
  Future<void> syncScheduleReminders({
    required List<Schedule> schedules,
    required String timeZoneId,
  }) {
    // Owner and epoch are captured when the caller submits the list, not when
    // the queued callback eventually runs: a list from a previous account must
    // never be accepted by a newer owner generation.
    final snapshot = _ScheduleReminderSnapshot(
      ownerId: _ownerUserId,
      generation: _ownerGeneration,
      epoch: ++_scheduleReminderEpoch,
      schedules: List<Schedule>.unmodifiable(schedules),
      timeZoneId: timeZoneId,
    );
    _lastScheduleSnapshot = snapshot;
    final operation = _scheduleReminderWork.then(
      (_) => _reconcileScheduleReminders(snapshot),
    );
    _scheduleReminderWork = operation.catchError((Object _) {});
    return operation;
  }

  /// Re-applies the last submitted schedule list, for example after the user
  /// enabled reminders again or granted the permission.
  Future<void> _reconcileFromLastSnapshot() {
    final snapshot = _lastScheduleSnapshot;
    if (snapshot == null || snapshot.ownerId != _ownerUserId) {
      return Future<void>.value();
    }
    return syncScheduleReminders(
      schedules: snapshot.schedules,
      timeZoneId: snapshot.timeZoneId,
    );
  }

  Future<void> _reconcileScheduleReminders(
    _ScheduleReminderSnapshot snapshot,
  ) async {
    final owner = snapshot.ownerId;
    await _awaitOwnerSettled();
    if (!snapshot.isCurrent(this)) return;
    if (owner == null) {
      // No signed-in owner can own a pending reminder; the release path already
      // cancels the namespace, this only prevents registering the old list.
      return;
    }
    final preferences = await (await _settingsStore).load();
    if (!snapshot.isCurrent(this)) return;
    // A refused permission never blocks schedules, imports or focus; it only
    // means nothing is registered until the user allows reminders again, and
    // already missed reminders are not replayed.
    final canDeliver =
        preferences.notificationsEnabled &&
        (!Platform.isAndroid || await notificationsAllowed());
    if (!snapshot.isCurrent(this)) return;
    final plans = canDeliver
        ? ScheduleReminderPlanner.plan(
            schedules: snapshot.schedules,
            now: _now(),
            timeZoneId: snapshot.timeZoneId,
            ownerId: owner,
          )
        : const <ScheduleReminderPlan>[];
    final desired = {for (final plan in plans) plan.notificationId: plan};
    final pendingIds = (await _scheduleReminderPendingIds()).toSet();
    if (!snapshot.isCurrent(this)) return;
    for (final id in pendingIds.where(
      ScheduleReminderPlanner.ownsNotificationId,
    )) {
      if (desired.containsKey(id)) continue;
      await _cancelScheduleReminderNotification(id);
    }
    _plannedScheduleReminders.removeWhere((id, _) => !desired.containsKey(id));

    for (final plan in plans) {
      if (!snapshot.isCurrent(this)) return;
      final known = _plannedScheduleReminders[plan.notificationId];
      final registrationLive = pendingIds.contains(plan.notificationId);
      if (known != null && known.sameRegistration(plan) && registrationLive) {
        continue;
      }
      await _scheduleScheduleReminderNotification(plan);
      // A reconciliation that arrived while this call was in flight owns the
      // queue now; the just-registered item must not outlive its cancellation.
      if (!snapshot.isCurrent(this)) {
        await _cancelScheduleReminderNotification(plan.notificationId);
        _plannedScheduleReminders.remove(plan.notificationId);
        return;
      }
      _plannedScheduleReminders[plan.notificationId] = plan;
      pendingIds.add(plan.notificationId);
    }
  }

  Future<List<int>> _scheduleReminderPendingIds() async {
    try {
      final adapter = await _scheduleAdapter();
      if (adapter != null) return await adapter.pendingIds();
      if (Platform.isAndroid) {
        final pending = await _androidNotifications
            .pendingNotificationRequests();
        return [for (final request in pending) request.id];
      }
    } catch (_) {
      // An unreadable platform queue keeps the app usable; a later
      // reconciliation retries the same ids.
    }
    return const [];
  }

  Future<void> _scheduleScheduleReminderNotification(
    ScheduleReminderPlan plan,
  ) async {
    final adapter = await _scheduleAdapter();
    if (adapter != null) {
      await adapter.schedule(
        id: plan.notificationId,
        title: plan.title,
        body: plan.body,
        at: plan.deliverAt,
        payload: plan.payload,
      );
      return;
    }
    if (!Platform.isAndroid) return;
    final exactAllowed = await exactAlarmsAllowed();
    await _androidNotifications.zonedSchedule(
      id: plan.notificationId,
      title: plan.title,
      body: plan.body,
      scheduledDate: timezone.TZDateTime.from(
        plan.deliverAt.toUtc(),
        _locationForTimeZone('Etc/UTC'),
      ),
      notificationDetails: _scheduleReminderDetails(),
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: plan.payload,
    );
  }

  Future<void> _cancelScheduleReminderNotification(int id) async {
    try {
      final adapter = await _scheduleAdapter();
      if (adapter != null) {
        await adapter.cancel(id);
        return;
      }
      if (Platform.isAndroid) await _androidNotifications.cancel(id: id);
    } catch (_) {
      // Cancelling a stale reminder is best effort.
    }
  }

  /// Drops every pending ordinary reminder of the owner that just left.
  Future<void> _cancelPlannedScheduleReminders() async {
    // The owner generation already invalidates in-flight work; the epoch only
    // tracks explicit reconciliations so a queued sync for the new owner runs.
    _plannedScheduleReminders.clear();
    try {
      for (final id in await _scheduleReminderPendingIds()) {
        if (!ScheduleReminderPlanner.ownsNotificationId(id)) continue;
        await _cancelScheduleReminderNotification(id);
      }
    } catch (_) {
      // The next owner still reconciles from the platform queue.
    }
  }

  NotificationDetails _scheduleReminderDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _scheduleReminderChannelId,
      '日程提醒',
      channelDescription: '普通日程到点时提醒；不开始专注，也不改变链记录。',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    ),
  );

  String? takePendingOpenRequest() {
    final request = _pendingOpenRequest;
    _pendingOpenRequest = null;
    return request;
  }

  ScheduleReminderRequest? takePendingScheduleRequest() {
    final request = _pendingScheduleRequest;
    _pendingScheduleRequest = null;
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
            body: '任务：$taskTitle',
            payload: 'appointment:$appointmentId',
            tag: notificationTag,
          );
        }
      } else if (Platform.isWindows) {
        // The OS already holds the scheduled transition; the tray balloon is a
        // fallback only when OS scheduling is unavailable in this process.
        if (await _scheduleAdapter() == null) {
          await _showWindowsEvent(title: '已进入专注', body: '任务：$taskTitle');
        }
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
            body: '任务：$taskTitle',
            payload: 'session:$sessionId',
            tag: notificationTag,
          );
        }
      } else if (Platform.isWindows) {
        if (await _scheduleAdapter() == null) {
          await _showWindowsEvent(title: ending, body: '任务：$taskTitle');
        }
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
    _windowsNationalFocusReminderTimer = null;
    _dailyOpenReminderTimer?.cancel();
    _dailyOpenReminderTimer = null;
    await _stopFocusTimer();
    if (Platform.isAndroid) {
      await _cancelPendingAndroidNotifications(_ownedNotificationIds);
      await _androidNotifications.cancel(id: _statusNotificationId);
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
    } else if (Platform.isWindows) {
      await _windowsChannel.invokeMethod<void>('clearStatus');
      final adapter = await _scheduleAdapter();
      if (adapter != null) {
        // 登出/清理同样要撤掉系统通知中心里的提醒，避免离线期间误发。
        await adapter.cancel(_nationalFocusReminderNotificationId);
        await adapter.cancel(_dailyOpenReminderNotificationId);
      }
    }
    await (await _reminderStateStore).clearScheduled();
    await (await _dailyReminderStateStore).clearScheduled();
  }

  Future<void> dispose() async {
    _windowsTicker?.cancel();
    _windowsNationalFocusReminderTimer?.cancel();
    _dailyOpenReminderTimer?.cancel();
    final timerGateway = _resolvedTimerServiceGateway;
    if (timerGateway is MethodChannelFocusTimerServiceGateway) {
      timerGateway.detach();
    }
    if (Platform.isWindows) _windowsChannel.setMethodCallHandler(null);
    await _resolvedWindowsNotifications?.dispose();
    _resolvedWindowsNotifications = null;
    _windowsNotificationsInitialized = false;
    _windowsScheduleReady = false;
    await _openFlowRequests.close();
    await _openScheduleRequests.close();
  }

  Future<FocusDevicePreferencesStore> get _settingsStore async {
    final supplied = preferencesStore;
    if (supplied != null) return supplied;
    return _resolvedPreferencesStore ??= FocusDevicePreferencesStore(
      await SharedPreferences.getInstance(),
      userId: _ownerUserId,
    );
  }

  /// Binds reminder settings to the signed-in user of this installation.
  ///
  /// Switching accounts cancels everything the previous user had scheduled so
  /// nobody receives another person's reminder, and invalidates in-flight work
  /// so a slow reconciliation cannot reschedule the previous user's alarm.
  Future<void> setUserId(String? userId) async {
    if (_ownerUserId == userId) return;
    final previousUserId = _ownerUserId;
    _ownerUserId = userId;
    _ownerGeneration++;
    _resolvedPreferencesStore = null;
    _resolvedNationalFocusReminderStateStore = null;
    _resolvedDailyOpenReminderStateStore = null;
    _currentPlan = null;
    _hasPendingNationalFocusConfirmations = null;
    _windowsTicker?.cancel();
    _windowsNationalFocusReminderTimer?.cancel();
    _dailyOpenReminderTimer?.cancel();
    _dailyOpenReminderTimer = null;
    // Only an explicit cancellation invalidates the reminder queue epoch; an
    // owner change is caught by the generation so a queued reconciliation for
    // the new owner still runs after the previous owner is released.
    _plannedScheduleReminders.clear();
    _windowsFocusScheduled.clear();
    _lastScheduleSnapshot = null;
    // A cold-start activation arrives before the first owner binding; only a
    // request that belongs to a different account is dropped.
    final pendingSchedule = _pendingScheduleRequest;
    if (pendingSchedule != null && pendingSchedule.ownerId != userId) {
      _pendingScheduleRequest = null;
    }

    // New work waits behind this barrier, so the previous owner's alarms are
    // removed before the next owner may schedule anything.
    final previousSwitch = _ownerSwitch;
    final switchWork = _releasePreviousOwner(previousSwitch, previousUserId);
    _ownerSwitch = switchWork.catchError((Object _) {});
    await _ownerSwitch;
  }

  Future<void> _releasePreviousOwner(
    Future<void>? previousSwitch,
    String? previousUserId,
  ) async {
    if (previousSwitch != null) await previousSwitch;
    await (ownerSwitchWork?.call() ?? _cancelOwnedNotifications());
    await _cancelPlannedScheduleReminders();
    await _clearOutgoingSchedule(previousUserId);
  }

  Future<void> _cancelOwnedNotifications() async {
    // 切号与登出不经过 clear()：前台进度服务必须先停下，否则上一位用户的
    // 倒计时通知会留在通知栏，下一位用户登录后还会看到它。
    await _stopFocusTimer();
    try {
      if (Platform.isAndroid) {
        await _cancelPendingAndroidNotifications(_ownedNotificationIds);
        // 已展示的状态通知不在"待投递"队列里，必须单独撤下（与 clear() 一致）。
        await _androidNotifications.cancel(id: _statusNotificationId);
        await _androidNotifications.cancel(
          id: _appointmentStatusNotificationId,
        );
      }
      final adapter = await _scheduleAdapter();
      if (adapter != null) {
        // Invalidate any in-flight plan and queue the removal behind it, so a
        // slow registration cannot resurrect an event after the release.
        final revision = ++_windowsPlanRevision;
        final generation = _ownerGeneration;
        final operation = _windowsPlanWork.then((_) async {
          if (revision != _windowsPlanRevision ||
              generation != _ownerGeneration) {
            return;
          }
          for (final id in [
            _appointmentTransitionNotificationId,
            _sessionEndNotificationId,
            // 切号/登出：上一位用户的 2204 与 2205 必须一起离开系统通知中心。
            _nationalFocusReminderNotificationId,
            _dailyOpenReminderNotificationId,
          ]) {
            await adapter.cancel(id);
          }
          _windowsFocusScheduled.clear();
        });
        _windowsPlanWork = operation.catchError((Object _) {});
        await operation;
      }
    } catch (_) {
      // Cancelling a previous owner's alarm is best effort.
    }
  }

  /// Awaits any owner switch that is still releasing the previous account.
  Future<void> _awaitOwnerSettled() async {
    while (true) {
      final barrier = _ownerSwitch;
      if (barrier == null) return;
      await barrier;
      if (identical(barrier, _ownerSwitch)) return;
    }
  }

  /// Drops the transient schedule markers of the user who just left, so a
  /// signed-out or switched installation advertises no pending reminder.
  /// Their saved choices stay scoped to them and are replanned on return.
  Future<void> _clearOutgoingSchedule(String? previousUserId) async {
    if (previousUserId == null) return;
    if (dailyOpenReminderStateStore != null ||
        nationalFocusReminderStateStore != null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await DailyOpenReminderStateStore(
      preferences,
      userId: previousUserId,
    ).clearScheduled();
    await NationalFocusReminderStateStore(
      preferences,
      userId: previousUserId,
    ).clearScheduled();
  }

  /// Releases the shell of [userId] without touching a newer user's reminders.
  ///
  /// Signing out deactivates the owner entirely: the daily reminder, the
  /// National Focus reminder and every pending alarm are cancelled, so nothing
  /// fires for an account that is no longer signed in.
  Future<void> releaseUser(String? userId) async {
    if (_ownerUserId != userId) return;
    await setUserId(null);
  }

  Future<DailyOpenReminderStateStore> get _dailyReminderStateStore async {
    final supplied = dailyOpenReminderStateStore;
    if (supplied != null) return supplied;
    return _resolvedDailyOpenReminderStateStore ??= DailyOpenReminderStateStore(
      await SharedPreferences.getInstance(),
      userId: _ownerUserId,
    );
  }

  Future<NationalFocusReminderStateStore> get _reminderStateStore async {
    final supplied = nationalFocusReminderStateStore;
    if (supplied != null) return supplied;
    return _resolvedNationalFocusReminderStateStore ??=
        NationalFocusReminderStateStore(
          await SharedPreferences.getInstance(),
          userId: _ownerUserId,
        );
  }

  Future<void> _applyCurrentPlan() async {
    // 计划属于捕获它的 owner：读取设置的 await 期间用户可能已经切号或登出，
    // 迟到的计划不能替上一位（或下一位）用户重新拉起计时与提醒。
    await _awaitOwnerSettled();
    final generation = _ownerGeneration;
    final preferences = await (await _settingsStore).load();
    if (_staleOwner(generation)) return;
    if (Platform.isWindows) {
      await _applyWindowsPlan(preferences);
    } else if (Platform.isAndroid) {
      await _applyAndroidPlan(preferences, generation: generation);
    }
    await _queueNationalFocusReminderReconciliation();
    await _queueDailyOpenReminderReconciliation();
  }

  /// Reconciles the device-local daily open-Pacta reminder with its settings.
  ///
  /// Safe to call on every app start or resume: an unchanged plan keeps the one
  /// pending reminder instead of creating another.
  Future<void> syncDailyOpenReminder() =>
      _queueDailyOpenReminderReconciliation();

  /// Drains the reminder work queued by reconciliation and by delivery.
  @visibleForTesting
  Future<void> get pendingDailyReminderWork async {
    Future<void> current;
    do {
      current = _dailyOpenReminderWork;
      await current;
    } while (!identical(current, _dailyOpenReminderWork));
  }

  Future<void> _queueDailyOpenReminderReconciliation() {
    final operation = _dailyOpenReminderWork.then(
      (_) => _reconcileDailyOpenReminder(),
    );
    _dailyOpenReminderWork = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _reconcileDailyOpenReminder() async {
    await _awaitOwnerSettled();
    final generation = _ownerGeneration;
    final preferences = await (await _settingsStore).load();
    if (generation != _ownerGeneration) return;
    final state = await _dailyReminderStateStore;
    if (!preferences.dailyOpenReminderEnabled ||
        (!Platform.isAndroid && !Platform.isWindows)) {
      await _cancelDailyOpenReminder(state);
      return;
    }
    if (Platform.isAndroid && !await notificationsAllowed()) {
      await _cancelDailyOpenReminder(state);
      return;
    }

    final now = _now();
    final plan = DailyOpenReminderPlan.next(
      now: now,
      minuteOfDay: preferences.dailyOpenReminderMinutesAfterMidnight,
    );
    final timeZoneId = await _currentTimeZoneId();
    if (generation != _ownerGeneration) return;
    if (Platform.isWindows) {
      await _applyWindowsDailyOpenReminder(
        plan,
        timeZoneId,
        state,
        now,
        generation,
      );
      return;
    }
    await _applyAndroidDailyOpenReminder(
      plan,
      timeZoneId,
      state,
      now,
      generation,
    );
  }

  /// True once another user owns the reminders, so in-flight work must stop.
  bool _staleOwner(int generation) => generation != _ownerGeneration;

  Future<void> _cancelDailyOpenReminder(
    DailyOpenReminderStateStore state,
  ) async {
    _dailyOpenReminderTimer?.cancel();
    _dailyOpenReminderTimer = null;
    // 系统通知中心持有的是 2205 本身：切号/登出必须显式撤掉它，否则下一位
    // 用户会在同一台设备上收到上一位用户的提醒。
    final adapter = await _scheduleAdapter();
    if (adapter != null) {
      await adapter.cancel(_dailyOpenReminderNotificationId);
    }
    if (Platform.isAndroid) {
      await _androidNotifications.cancel(id: _dailyOpenReminderNotificationId);
    }
    await state.clearScheduled();
  }

  Future<void> _applyWindowsDailyOpenReminder(
    DailyOpenReminderPlan plan,
    String timeZoneId,
    DailyOpenReminderStateStore state,
    DateTime now,
    int generation,
  ) async {
    if (_staleOwner(generation)) return;
    final adapter = await _scheduleAdapter();
    if (_staleOwner(generation)) return;
    final scheduled = state.loadScheduled();
    final unchanged =
        scheduled != null &&
        scheduled.dayKey == plan.dayKey &&
        scheduled.scheduledAt.isAtSameMomentAs(plan.scheduledAt) &&
        scheduled.timeZoneId == timeZoneId;

    if (adapter != null) {
      // Windows 通知中心可以跨进程存活：优先交给 OS，完全退出后仍会送达。
      await _scheduleWindowsDailyOpenReminder(
        adapter,
        plan,
        timeZoneId,
        state,
        unchanged,
      );
      return;
    }

    // 没有 OS 适配器（单元测试或桥不可用）时才退回进程内 Timer。
    if (unchanged && _dailyOpenReminderTimer?.isActive == true) return;

    if (!unchanged) {
      _dailyOpenReminderTimer?.cancel();
      await state.saveScheduled(
        DailyOpenReminderSchedule(
          dayKey: plan.dayKey,
          scheduledAt: plan.scheduledAt,
          timeZoneId: timeZoneId,
        ),
      );
      if (_staleOwner(generation)) return;
    }
    // A restarted app keeps the stored plan but still needs its own timer.
    final delay = plan.scheduledAt.difference(now);
    final dayKey = plan.dayKey;
    _dailyOpenReminderTimer = _reminderTimers(
      delay.isNegative ? Duration.zero : delay,
      () => _queueDailyOpenReminderDelivery(dayKey),
    );
  }

  /// 把每日提醒写进 Windows 通知中心；相同计划不重复注册。
  Future<void> _scheduleWindowsDailyOpenReminder(
    WindowsNotificationAdapter adapter,
    DailyOpenReminderPlan plan,
    String timeZoneId,
    DailyOpenReminderStateStore state,
    bool unchanged,
  ) async {
    // 交给 OS 之后进程内不再持有计时器，避免同一天提醒两次。
    _dailyOpenReminderTimer?.cancel();
    _dailyOpenReminderTimer = null;
    if (unchanged &&
        (await adapter.pendingIds()).contains(
          _dailyOpenReminderNotificationId,
        )) {
      return;
    }
    await adapter.schedule(
      id: _dailyOpenReminderNotificationId,
      title: '打开 Pacta',
      body: '查看今天的看板。',
      at: plan.scheduledAt,
      payload: 'daily-open-reminder:${plan.dayKey}',
    );
    await state.saveScheduled(
      DailyOpenReminderSchedule(
        dayKey: plan.dayKey,
        scheduledAt: plan.scheduledAt,
        timeZoneId: timeZoneId,
      ),
    );
  }

  Future<void> _applyAndroidDailyOpenReminder(
    DailyOpenReminderPlan plan,
    String timeZoneId,
    DailyOpenReminderStateStore state,
    DateTime now,
    int generation,
  ) async {
    if (_staleOwner(generation)) return;
    final scheduled = state.loadScheduled();
    final pending = await _androidNotifications.pendingNotificationRequests();
    if (_staleOwner(generation)) return;
    final hasPendingReminder = pending.any(
      (request) => request.id == _dailyOpenReminderNotificationId,
    );
    final unchanged =
        hasPendingReminder &&
        scheduled != null &&
        scheduled.dayKey == plan.dayKey &&
        scheduled.scheduledAt.isAtSameMomentAs(plan.scheduledAt) &&
        scheduled.timeZoneId == timeZoneId;
    if (unchanged) return;

    // Reusing this id replaces the pending alarm, which keeps time changes and
    // restarts from stacking several daily reminders.
    final exactAllowed = await exactAlarmsAllowed();
    await _androidNotifications.zonedSchedule(
      id: _dailyOpenReminderNotificationId,
      title: '打开 Pacta',
      body: '查看今天的看板。',
      scheduledDate: timezone.TZDateTime.from(
        plan.scheduledAt,
        _locationForTimeZone(timeZoneId),
      ),
      notificationDetails: _dailyOpenReminderDetails(),
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'daily-open-reminder:${plan.dayKey}',
      // The daily component repeats on the device wall clock, so a single
      // pending alarm never accumulates one notification per missed day.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    await state.saveScheduled(
      DailyOpenReminderSchedule(
        dayKey: plan.dayKey,
        scheduledAt: plan.scheduledAt,
        timeZoneId: timeZoneId,
      ),
    );
  }

  void _queueDailyOpenReminderDelivery(String dayKey) {
    final operation = _dailyOpenReminderWork.then(
      (_) => _deliverDailyOpenReminder(dayKey),
    );
    _dailyOpenReminderWork = operation.catchError((Object _) {});
  }

  Future<void> _deliverDailyOpenReminder(String dayKey) async {
    final generation = _ownerGeneration;
    final state = await _dailyReminderStateStore;
    // A reminder for the previous user must never appear under a new one.
    if (_staleOwner(generation)) return;
    if (Platform.isAndroid) {
      await state.markSent(dayKey);
      return;
    }
    try {
      await _showWindowsEvent(
        title: '打开 Pacta',
        body: '查看今天的看板。',
        payload: 'daily-open-reminder:$dayKey',
      );
      await state.markSent(dayKey);
    } catch (_) {
      // A tray delivery failure must not leave the reminder stuck on one day.
    }
    if (_staleOwner(generation)) return;
    // Queued instead of awaited so delivery never waits on its own work chain.
    unawaited(_queueDailyOpenReminderReconciliation());
  }

  Future<String> _currentTimeZoneId() async {
    try {
      final identifier = await localTimeZone?.call();
      if (identifier != null && identifier.isNotEmpty) return identifier;
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      // An unreadable zone still lets the local clock schedule the reminder;
      // the offset keeps a zone change detectable.
      final offset = _now().timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final hours = offset.inHours.abs().toString().padLeft(2, '0');
      final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      return 'UTC$sign$hours:$minutes';
    }
  }

  timezone.Location _locationForTimeZone(String timeZoneId) {
    if (!_timeZonesInitialized) {
      timezone_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    try {
      return timezone.getLocation(timeZoneId);
    } catch (_) {
      // An unlisted identifier such as the emulator's "GMT" keeps the device
      // location that initialize() resolved; UTC is the last resort.
      try {
        return timezone.local;
      } catch (_) {
        return timezone.getLocation('Etc/UTC');
      }
    }
  }

  Future<void> _queueNationalFocusReminderReconciliation() {
    final operation = _nationalFocusReminderWork.then(
      (_) => _reconcileNationalFocusReminder(),
    );
    _nationalFocusReminderWork = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _reconcileNationalFocusReminder() async {
    await _awaitOwnerSettled();
    final generation = _ownerGeneration;
    final preferences = await (await _settingsStore).load();
    if (_staleOwner(generation)) return;
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
    final timeZoneId = await _nationalFocusReminderTimeZoneId();
    final lastSentDayKey = state.loadLastSentDayKey();
    final reminder = NationalFocusReminderPlan.next(
      now: now,
      minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
      hasPendingConfirmations: true,
      lastNotifiedDayKey: lastSentDayKey,
      activeFlow: _currentPlan,
      timeZoneId: timeZoneId,
    );
    if (reminder == null) {
      await _cancelNationalFocusReminder(state);
      return;
    }

    if (Platform.isWindows) {
      await _applyWindowsNationalFocusReminder(
        reminder,
        preferences,
        state,
        generation,
        timeZoneId,
      );
      return;
    }

    await _applyAndroidNationalFocusReminder(
      reminder,
      preferences,
      state,
      generation,
      timeZoneId,
    );
  }

  /// 国策提醒使用的账号时区；读不到时回到北京时间。
  Future<String> _nationalFocusReminderTimeZoneId() async {
    final reader = accountTimeZoneReader;
    if (reader == null) return NationalFocusReminderPlan.defaultTimeZoneId;
    try {
      final zoneId = await reader();
      return zoneId.trim().isEmpty
          ? NationalFocusReminderPlan.defaultTimeZoneId
          : zoneId;
    } catch (_) {
      return NationalFocusReminderPlan.defaultTimeZoneId;
    }
  }

  Future<void> _cancelNationalFocusReminder(
    NationalFocusReminderStateStore state,
  ) async {
    _windowsNationalFocusReminderTimer?.cancel();
    _windowsNationalFocusReminderTimer = null;
    final adapter = await _scheduleAdapter();
    if (adapter != null) {
      await adapter.cancel(_nationalFocusReminderNotificationId);
    }
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
    int generation,
    String timeZoneId,
  ) async {
    _windowsNationalFocusReminderTimer?.cancel();
    _windowsNationalFocusReminderTimer = null;
    if (reminder == null) return;
    if (_staleOwner(generation)) return;
    final adapter = await _scheduleAdapter();
    if (_staleOwner(generation)) return;

    final now = _now().toUtc();
    if (adapter != null) {
      // 进程不在场时 OS 已经替我们送达了 2204：通知中心不再持有这个 id，而
      // 本地还留着"已排程"标记就说明是关闭期间的这次投递。只推进状态并在
      // 系统队列里排下一天，绝不再补一张即时 toast，否则同一天提醒两次。
      final scheduled = state.loadScheduled();
      final pendingIds = await adapter.pendingIds();
      if (_staleOwner(generation)) return;
      if (scheduled != null &&
          !scheduled.scheduledAt.isAfter(now) &&
          !pendingIds.contains(_nationalFocusReminderNotificationId)) {
        await state.markSent(scheduled.dayKey);
        final advanced = NationalFocusReminderPlan.next(
          now: _now(),
          minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
          hasPendingConfirmations:
              _hasPendingNationalFocusConfirmations == true,
          lastNotifiedDayKey: scheduled.dayKey,
          activeFlow: _currentPlan,
          timeZoneId: timeZoneId,
        );
        if (advanced == null || !advanced.scheduledAt.isAfter(_now())) {
          await _cancelNationalFocusReminder(state);
          return;
        }
        await state.saveScheduled(
          NationalFocusReminderSchedule(
            dayKey: advanced.dayKey,
            scheduledAt: advanced.scheduledAt,
            repeatsDaily: false,
          ),
        );
        await _armWindowsNationalFocusReminder(
          adapter,
          advanced.scheduledAt.difference(_now()),
          advanced.scheduledAt,
          advanced.dayKey,
        );
        return;
      }
    }

    if (reminder.scheduledAt.isAfter(now)) {
      await state.saveScheduled(
        NationalFocusReminderSchedule(
          dayKey: reminder.dayKey,
          scheduledAt: reminder.scheduledAt,
          repeatsDaily: false,
        ),
      );
      await _armWindowsNationalFocusReminder(
        adapter,
        reminder.scheduledAt.difference(now),
        reminder.scheduledAt,
        reminder.dayKey,
      );
      return;
    }

    await _showWindowsEvent(title: '国策待确认', body: '请确认今日仍有效的国策。');
    await state.markSent(reminder.dayKey);
    final nextReminder = NationalFocusReminderPlan.next(
      now: _now(),
      minuteOfDay: preferences.nationalFocusReminderMinutesAfterMidnight,
      hasPendingConfirmations: _hasPendingNationalFocusConfirmations == true,
      lastNotifiedDayKey: reminder.dayKey,
      activeFlow: _currentPlan,
      timeZoneId: timeZoneId,
    );
    if (nextReminder != null && nextReminder.scheduledAt.isAfter(_now())) {
      await state.saveScheduled(
        NationalFocusReminderSchedule(
          dayKey: nextReminder.dayKey,
          scheduledAt: nextReminder.scheduledAt,
          repeatsDaily: false,
        ),
      );
      await _armWindowsNationalFocusReminder(
        adapter,
        nextReminder.scheduledAt.difference(_now()),
        nextReminder.scheduledAt,
        nextReminder.dayKey,
      );
    }
  }

  /// 下一次国策提醒：有 OS 适配器就写进通知中心，否则退回进程内 Timer。
  Future<void> _armWindowsNationalFocusReminder(
    WindowsNotificationAdapter? adapter,
    Duration delay,
    DateTime scheduledAt,
    String dayKey,
  ) async {
    if (adapter != null) {
      await adapter.schedule(
        id: _nationalFocusReminderNotificationId,
        title: '国策待确认',
        body: '请确认今日仍有效的国策。',
        at: scheduledAt,
        payload: 'national-focus-reminder:$dayKey',
      );
      return;
    }
    _windowsNationalFocusReminderTimer = Timer(
      delay,
      () => unawaited(_queueNationalFocusReminderReconciliation()),
    );
  }

  Future<void> _applyAndroidNationalFocusReminder(
    NationalFocusReminderPlan reminder,
    FocusDevicePreferences preferences,
    NationalFocusReminderStateStore state,
    int generation,
    String timeZoneId,
  ) async {
    if (_staleOwner(generation)) return;
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
        timeZoneId: timeZoneId,
      );
      if (nextReminder == null) {
        await _cancelNationalFocusReminder(state);
        return;
      }
      await _scheduleAndroidNationalFocusReminder(
        nextReminder,
        state,
        now,
        timeZoneId,
      );
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
          timeZoneId: timeZoneId,
        );
        if (nextReminder != null) {
          await _scheduleAndroidNationalFocusReminder(
            nextReminder,
            state,
            now,
            timeZoneId,
          );
        }
        return;
      }

      await _androidNotifications.cancel(
        id: _nationalFocusReminderNotificationId,
      );
      await _androidNotifications.show(
        id: _nationalFocusReminderNotificationId,
        title: '国策待确认',
        body: '请确认今日仍有效的国策。',
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
        timeZoneId: timeZoneId,
      );
      if (nextReminder != null) {
        await _scheduleAndroidNationalFocusReminder(
          nextReminder,
          state,
          _now().toUtc(),
          timeZoneId,
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

    await _scheduleAndroidNationalFocusReminder(
      reminder,
      state,
      now,
      timeZoneId,
    );
  }

  Future<void> _scheduleAndroidNationalFocusReminder(
    NationalFocusReminderPlan reminder,
    NationalFocusReminderStateStore state,
    DateTime now,
    String timeZoneId,
  ) async {
    final repeatsDaily = !reminder.isDeferred;
    if (!reminder.scheduledAt.isAfter(now)) {
      await _androidNotifications.cancel(
        id: _nationalFocusReminderNotificationId,
      );
      await _androidNotifications.show(
        id: _nationalFocusReminderNotificationId,
        title: '国策待确认',
        body: '请确认今日仍有效的国策。',
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
        timeZoneId: timeZoneId,
      );
      if (nextReminder != null) {
        await _scheduleAndroidNationalFocusReminder(
          nextReminder,
          state,
          _now().toUtc(),
          timeZoneId,
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
      body: '请确认今日仍有效的国策。',
      scheduledDate: timezone.TZDateTime.from(
        reminder.scheduledAt,
        _locationForTimeZone(timeZoneId),
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

  Future<void> _applyAndroidPlan(
    FocusDevicePreferences preferences, {
    int? generation,
  }) async {
    final gen = generation ?? _ownerGeneration;
    final plan = _currentPlan;
    // 计划也有身份：切号会清空 _currentPlan，另一次 sync() 会替换它。任何一次
    // await 之后都要重新确认，否则恢复执行时会按过期计划重排通知。
    bool stale() => _staleOwner(gen) || !identical(plan, _currentPlan);
    final notificationsPermitted = await notificationsAllowed();
    if (stale()) return;
    final permissionAllowed =
        preferences.notificationsEnabled && notificationsPermitted;
    // 常驻倒计时只在"后台运行"开关下出现，与事件提醒开关相互独立。
    final showStatus =
        notificationsPermitted && preferences.backgroundRunningEnabled;
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
      _dailyOpenReminderNotificationId,
    });
    // 从这里开始只剩副作用：拉起/停掉前台服务、展示与排程通知。owner 或计划
    // 变过就整段放弃，晚到的计划不能再给新会话叠一张倒计时。
    if (stale()) return;

    if (!showStatus || plan == null) {
      // 结束、关闭开关或登出：前台服务与静态状态通知都必须一起消失。
      await _stopFocusTimer();
      await _androidNotifications.cancel(id: _statusNotificationId);
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
    } else if (plan.isPreparing) {
      // 准备窗口本身就是一段倒计时：交给前台服务按秒刷新进度条。
      await _startFocusTimer(
        plan,
        titlePrefix: '预约准备中',
        endsAt: plan.stageEndsAt!,
      );
      final transitionAt = plan.stageEndsAt!;
      if (transitionAt.isAfter(_now())) {
        await _scheduleAndroidNotification(
          id: _appointmentTransitionNotificationId,
          title: '已进入专注',
          body: '任务：${plan.taskTitle}',
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
          title: '专注已完成',
          body: '任务：${plan.taskTitle}',
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
      // 暂停时不再计时：撤下前台服务，换一张带静态进度条的暂停通知。
      await _stopFocusTimer();
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
      await _androidNotifications.cancel(id: _statusNotificationId);
      final secondsRemaining = plan.remainingSecondsAt(_now());
      await _androidNotifications.show(
        id: _statusNotificationId,
        title: '专注已暂停',
        body: '${plan.taskTitle} · 剩余 ${_formatClock(secondsRemaining)}',
        notificationDetails: _statusDetails(
          showProgress: true,
          maxProgress: plan.progressTotalSeconds,
          progress: plan.elapsedSecondsAt(_now()),
        ),
        payload: plan.notificationPayload,
      );
    } else {
      await _startFocusTimer(
        plan,
        titlePrefix: '专注中',
        endsAt: plan.focusEndsAt,
      );
      await _androidNotifications.cancel(id: _appointmentStatusNotificationId);
      if (plan.focusEndsAt.isAfter(_now())) {
        await _scheduleAndroidNotification(
          id: _sessionEndNotificationId,
          title: '专注已完成',
          body: '任务：${plan.taskTitle}',
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

  /// 启动或刷新动态进度前台服务。
  ///
  /// Android 12+ 在后台启动前台服务可能被系统拒绝，此时回退到静态进度通知：
  /// 用户仍然看到进度与剩余时间，只是不再按秒刷新。
  Future<void> _startFocusTimer(
    FocusNotificationPlan plan, {
    required String titlePrefix,
    required DateTime endsAt,
  }) async {
    try {
      await _timerService.startOrUpdate(
        FocusTimerRequest(
          notificationId: _statusNotificationId,
          titlePrefix: titlePrefix,
          taskTitle: plan.taskTitle,
          modeLabel: plan.modeLabel,
          startedAt: plan.startedAt ?? _now(),
          endsAt: endsAt,
          totalSeconds: plan.progressTotalSeconds,
          payload: plan.notificationPayload,
        ),
      );
    } catch (_) {
      await _showAndroidStatus(
        id: _statusNotificationId,
        title: titlePrefix,
        body: '${plan.taskTitle} · ${plan.modeLabel}',
        endAt: endsAt,
        timeoutAt: endsAt,
        payload: plan.notificationPayload,
        showProgress: true,
        maxProgress: plan.progressTotalSeconds,
        progress: plan.elapsedSecondsAt(_now()),
      );
    }
  }

  Future<void> _stopFocusTimer() async {
    try {
      await _timerService.stop();
    } catch (_) {
      // 服务本来就不在运行时停止是幂等的。
    }
  }

  /// Serializes every Windows focus registration through one queue.
  ///
  /// A newer plan (or an owner release) bumps the revision, so an older queued
  /// run stops before its next native call and a registration that completed in
  /// flight is compensated instead of outliving the newer decision.
  Future<void> _applyWindowsPlan(FocusDevicePreferences preferences) {
    final revision = ++_windowsPlanRevision;
    final owner = _ownerUserId;
    final generation = _ownerGeneration;
    final operation = _windowsPlanWork.then(
      (_) => _runWindowsPlan(revision, owner, generation, preferences),
    );
    _windowsPlanWork = operation.catchError((Object _) {});
    return operation;
  }

  bool _windowsPlanCurrent(int revision, String? owner, int generation) =>
      revision == _windowsPlanRevision &&
      owner == _ownerUserId &&
      generation == _ownerGeneration;

  Future<void> _runWindowsPlan(
    int revision,
    String? owner,
    int generation,
    FocusDevicePreferences preferences,
  ) async {
    bool current() => _windowsPlanCurrent(revision, owner, generation);
    if (!current()) return;
    await _windowsChannel.invokeMethod<void>(
      'setBackgroundRunningEnabled',
      preferences.backgroundRunningEnabled,
    );
    _windowsTicker?.cancel();
    _windowsTicker = null;
    if (!current()) return;
    final adapter = await _scheduleAdapter();
    if (!current()) return;
    if (adapter != null) {
      await _applyWindowsFocusSchedule(adapter, preferences, current);
      if (!current()) return;
    }
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

  /// Registers the persisted appointment transition and focus end with the OS.
  ///
  /// Delivery must not depend on this process staying alive, so the times come
  /// from the persisted plan and an unchanged registration is not re-added.
  Future<void> _applyWindowsFocusSchedule(
    WindowsNotificationAdapter adapter,
    FocusDevicePreferences preferences,
    bool Function() current,
  ) async {
    if (!current()) return;
    final plan = _currentPlan;
    final now = _now();
    final pending = (await adapter.pendingIds()).toSet();
    if (!current()) return;
    final desired = <int, _WindowsScheduledEvent>{};
    if (plan != null && preferences.notificationsEnabled) {
      final transitionAt = plan.stageEndsAt;
      if (plan.isPreparing &&
          transitionAt != null &&
          transitionAt.isAfter(now)) {
        desired[_appointmentTransitionNotificationId] = _WindowsScheduledEvent(
          at: transitionAt,
          title: '已进入专注',
          body: '任务：${plan.taskTitle}',
          payload: plan.notificationPayload,
        );
      }
      if (!plan.isPaused && plan.focusEndsAt.isAfter(now)) {
        desired[_sessionEndNotificationId] = _WindowsScheduledEvent(
          at: plan.focusEndsAt,
          title: '专注已完成',
          body: '任务：${plan.taskTitle}',
          payload: plan.notificationPayload,
        );
      }
    }
    for (final id in const [
      _appointmentTransitionNotificationId,
      _sessionEndNotificationId,
    ]) {
      if (!current()) return;
      final target = desired[id];
      if (target == null) {
        if (pending.contains(id) || _windowsFocusScheduled.containsKey(id)) {
          await adapter.cancel(id);
          _windowsFocusScheduled.remove(id);
        }
        continue;
      }
      if (pending.contains(id) && _windowsFocusScheduled[id] == target) {
        continue;
      }
      if (!current()) return;
      await adapter.schedule(
        id: id,
        title: target.title,
        body: target.body,
        at: target.at,
        payload: target.payload,
      );
      if (!current()) {
        // This registration lost its plan while it was in flight; the newer
        // plan or the release already owns the id.
        await adapter.cancel(id);
        _windowsFocusScheduled.remove(id);
        return;
      }
      _windowsFocusScheduled[id] = target;
    }
  }

  Future<void> _showWindowsEvent({
    required String title,
    required String body,
    String? payload,
  }) => _windowsChannel.invokeMethod<void>('showNotification', {
    'title': title,
    'body': body,
    'payload': ?payload,
  });

  Future<void> _showAndroidStatus({
    required int id,
    required String title,
    required String body,
    required DateTime? endAt,
    required DateTime? timeoutAt,
    Duration? timeoutAfter,
    required String payload,
    bool showProgress = false,
    int maxProgress = 0,
    int progress = 0,
  }) => _androidNotifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: _statusDetails(
      endAt: endAt,
      timeoutAt: timeoutAt,
      timeoutAfter: timeoutAfter,
      showProgress: showProgress,
      maxProgress: maxProgress,
      progress: progress,
    ),
    payload: payload,
  );

  NotificationDetails _nationalFocusReminderDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _nationalFocusReminderChannelId,
      '国策待确认',
      channelDescription: '有国策待确认时提醒。',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      onlyAlertOnce: true,
    ),
  );

  NotificationDetails _dailyOpenReminderDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _dailyOpenReminderChannelId,
      '每日打开提醒',
      channelDescription: '每天在本机当地时间提醒打开 Pacta 看板。',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    ),
  );

  NotificationDetails _statusDetails({
    DateTime? endAt,
    DateTime? timeoutAt,
    Duration? timeoutAfter,
    bool showProgress = false,
    int maxProgress = 0,
    int progress = 0,
  }) {
    final timeout =
        timeoutAfter?.inMilliseconds ??
        timeoutAt?.difference(_now()).inMilliseconds;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        '专注状态',
        channelDescription: '显示正在进行的预约或专注倒计时。',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        silent: true,
        playSound: false,
        enableVibration: false,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.public,
        showProgress: showProgress,
        maxProgress: maxProgress,
        progress: progress,
        // Android 只在 showWhen 为 true 时才渲染 usesChronometer 的倒计时，
        // 这不是"显示时间戳"，而是倒计时的开关。
        showWhen: endAt != null,
        usesChronometer: endAt != null,
        chronometerCountDown: endAt != null,
        when: endAt?.millisecondsSinceEpoch,
        timeoutAfter: timeout == null || timeout <= 0 ? null : timeout,
      ),
    );
  }

  /// 常驻倒计时通知的平台细节，供测试断言 `showWhen`/`usesChronometer`。
  @visibleForTesting
  NotificationDetails statusNotificationDetails({
    DateTime? endAt,
    DateTime? timeoutAt,
    Duration? timeoutAfter,
    bool showProgress = false,
    int maxProgress = 0,
    int progress = 0,
  }) => _statusDetails(
    endAt: endAt,
    timeoutAt: timeoutAt,
    timeoutAfter: timeoutAfter,
    showProgress: showProgress,
    maxProgress: maxProgress,
    progress: progress,
  );

  NotificationDetails _eventDetails({required String tag}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _eventChannelId,
          '专注转换提醒',
          channelDescription: '预约进入专注或专注会话结束时提醒。',
          // 进入专注与自然完成是必须打断用户的时刻：最高重要性 + alarm 类别，
          // 锁屏上也完整可见，不能被降级成静默更新。
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          playSound: true,
          enableVibration: true,
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
    final scheduleRequest = ScheduleReminderRequest.tryParse(payload);
    if (scheduleRequest != null) {
      _pendingScheduleRequest = scheduleRequest;
      _openScheduleRequests.add(scheduleRequest);
      return;
    }
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
    if (ScheduleReminderRequest.tryParse(payload) != null) return null;
    if (payload.startsWith('appointment:')) return payload.substring(12);
    if (payload.startsWith('session:')) return payload.substring(8);
    return null;
  }
}

class _ScheduleReminderSnapshot {
  const _ScheduleReminderSnapshot({
    required this.ownerId,
    required this.generation,
    required this.epoch,
    required this.schedules,
    required this.timeZoneId,
  });

  final String? ownerId;
  final int generation;
  final int epoch;
  final List<Schedule> schedules;
  final String timeZoneId;

  bool isCurrent(FocusNotificationService service) =>
      service._ownerUserId == ownerId &&
      service._ownerGeneration == generation &&
      service._scheduleReminderEpoch == epoch;
}

class _WindowsScheduledEvent {
  const _WindowsScheduledEvent({
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final DateTime at;
  final String title;
  final String body;
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is _WindowsScheduledEvent &&
      other.at.isAtSameMomentAs(at) &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode =>
      Object.hash(at.microsecondsSinceEpoch, title, body, payload);
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
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> releaseUser(String? userId) async {}

  @override
  Future<bool> ensureNotificationPermissionForUse() async => false;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openAppSettings() async {}

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
  Future<void> syncScheduleReminders({
    required List<Schedule> schedules,
    required String timeZoneId,
  }) async {}

  @override
  ScheduleReminderRequest? takePendingScheduleRequest() => null;

  @override
  Future<void> detachForProcessExit() async {}

  @override
  Future<void> dispose() async {}
}
