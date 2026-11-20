import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/user_lifecycle_models.dart';
import '../board/board_page.dart';
import '../focus/focus_chain_page.dart';
import '../focus/focus_flow_helpers.dart';
import '../focus/focus_models.dart';
import '../focus/focus_session_pages.dart';
import '../national_focus/national_focus_ai_access.dart';
import '../national_focus/national_focus_ai_analysis_page.dart';
import '../national_focus/national_focus_checkpoint_scheduler.dart';
import '../national_focus/national_focus_models.dart';
import '../national_focus/national_focus_tree_page.dart';
import '../notifications/focus_notification_service.dart';
import '../notifications/schedule_reminder_plan.dart';
import '../notifications/schedule_reminder_sync.dart';
import '../plan/plan_page.dart';
import '../plan/plan_target.dart';
import '../profile/account_time_zone.dart';
import '../profile/my_page.dart';
import '../profile/profile_models.dart';
import '../schedules/schedule_models.dart';
import '../theme/pacta_spacing.dart';
import 'app_providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  PlanTarget? _planTarget;
  late final FocusNotificationService _focusNotificationService;
  late final String? _reminderOwnerUserId;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  late final StreamSubscription<String> _notificationOpenSubscription;
  late final StreamSubscription<ScheduleReminderRequest>
  _scheduleOpenSubscription;
  late final ScheduleReminderSync _scheduleReminderSync;
  StreamSubscription<ProfileAccount>? _profileReminderSubscription;
  String? _reminderTimeZoneId;
  late StreamSubscription<List<NationalFocusCard>>
  _nationalFocusReminderSubscription;
  late final NationalFocusCheckpointScheduler _nationalFocusCheckpointScheduler;

  static const _destinations = [
    _Destination('看板', Icons.dashboard_outlined, Icons.dashboard),
    _Destination('计划', Icons.event_note_outlined, Icons.event_note),
    _Destination('国策树', Icons.account_tree_outlined, Icons.account_tree),
    _Destination('专注链', Icons.bolt_outlined, Icons.bolt),
    _Destination('我的', Icons.person_outline, Icons.person),
  ];

  /// 目的地下标：新增计划后所有跳转都按名字固定，避免再散落魔法数字。
  static const _boardIndex = 0;
  static const _planIndex = 1;
  static const _nationalFocusIndex = 2;

  @override
  void initState() {
    super.initState();
    _focusNotificationService = ref.read(focusNotificationServiceProvider);
    // Reminder settings belong to this installation's current user, so the
    // owner is bound before any reconciliation runs. The identifier is kept in
    // a field because dispose() must not read providers.
    _reminderOwnerUserId = ref.read(authRepositoryProvider).currentUserId;
    unawaited(_focusNotificationService.setUserId(_reminderOwnerUserId));
    _nationalFocusCheckpointScheduler = NationalFocusCheckpointScheduler(
      settleDueCheckpoints: () =>
          ref.read(nationalFocusRepositoryProvider).settleDueCheckpoints(),
    )..start();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      unawaited(_refreshLocalState());
    });
    _notificationOpenSubscription = _focusNotificationService.openFlowRequests
        .listen((payload) {
          _focusNotificationService.takePendingOpenRequest();
          unawaited(_openFocusFlow(payload));
        });
    _scheduleReminderSync = ScheduleReminderSync(
      notificationService: _focusNotificationService,
      accountTimeZoneId: () async {
        final profile = await ref.read(profileRepositoryProvider).getProfile();
        return AccountTimeZones.effectiveId(profile.displayTimeZoneId);
      },
      // The reminder query window is anchored to the same injected clock the
      // calendar uses, so the system clock cannot drift the window past a
      // schedule that the display clock still considers upcoming.
      now: ref.read(displayClockProvider),
    );
    _scheduleOpenSubscription = _focusNotificationService.openScheduleRequests
        .listen((request) => unawaited(_openScheduleReminder(request)));
    _nationalFocusReminderSubscription = ref
        .read(nationalFocusRepositoryProvider)
        .watchTreeCards()
        .listen(
          (cards) => unawaited(_syncNationalFocusReminder(cards)),
          onError: (Object _) {
            // Notification reconciliation never changes National Focus state.
          },
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshLocalState(checkCloud: true));
      // The daily reminder belongs to this device, so it is reconciled on
      // every start instead of relying on a business data change.
      unawaited(_focusNotificationService.syncDailyOpenReminder());
      final request = _focusNotificationService.takePendingOpenRequest();
      if (request != null) unawaited(_openFocusFlow(request));
      unawaited(
        _scheduleReminderSync.attach(ref.read(scheduleRepositoryProvider)),
      );
      _watchProfileTimeZone();
      // A cold-start reminder activation must be drained once the shell is
      // ready; the stream only covers clicks that arrive while it is listening.
      final scheduleRequest = _focusNotificationService
          .takePendingScheduleRequest();
      if (scheduleRequest != null) {
        unawaited(_openScheduleReminder(scheduleRequest));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLocalState(checkCloud: true));
      // A resume can cross the bounded window; reconcile without replaying.
      unawaited(_scheduleReminderSync.reconcileOnce());
    }
  }

  Future<void> _refreshLocalState({bool checkCloud = false}) async {
    final userId = ref.read(authRepositoryProvider).currentUserId;
    try {
      await ref.read(userLifecycleStatusRepositoryProvider).refresh();
    } catch (_) {
      // Local use remains available when lifecycle refresh is offline.
    }
    if (!mounted || ref.read(authRepositoryProvider).currentUserId != userId) {
      return;
    }
    if (checkCloud) {
      unawaited(
        ref.read(cloudVersionCheckProvider)?.check() ?? Future<void>.value(),
      );
    }
    // 登录、联网或生命周期恢复后重试待上传请求；访问判定在协调器内完成。
    unawaited(
      ref.read(cloudAutoUploadCoordinatorProvider)?.trigger() ??
          Future<void>.value(),
    );
    // Lifecycle and local notification refresh never transfer business records.
    try {
      await ref.read(focusRepositoryProvider).settleDueSessions();
      await ref.read(nationalFocusRepositoryProvider).settleDueCheckpoints();
    } catch (_) {
      // Local recovery can be retried without uploading or discarding records.
    }
    await _syncFocusStatus();
    // 账号时区迁移：已有账号值优先；没有时由本轮启动只写入一次原子初始化，
    // 失败就保持统一 fallback 并在下次启动/恢复重试。
    await _ensureAccountDisplayTimeZone();
    // A resume can cross midnight or a device time zone change; the reminder is
    // replanned from the current local wall clock without replaying old days.
    unawaited(_focusNotificationService.syncDailyOpenReminder());
  }

  Future<void> _ensureAccountDisplayTimeZone() async {
    final userId = ref.read(authRepositoryProvider).currentUserId;
    try {
      final deviceTimeZoneId = await ref.read(deviceTimeZoneIdReaderProvider)();
      if (!mounted ||
          ref.read(authRepositoryProvider).currentUserId != userId) {
        return;
      }
      await ref
          .read(profileRepositoryProvider)
          .ensureDisplayTimeZone(deviceTimeZoneId: deviceTimeZoneId);
    } catch (_) {
      // 迁移失败不阻塞启动：显示使用统一 fallback，稍后重试同一条路径。
    }
  }

  Future<void> _syncFocusStatus() async {
    try {
      final focusRepository = ref.read(focusRepositoryProvider);
      final activeSession = await focusRepository.getActiveSession();
      final activeAppointment = activeSession == null
          ? await focusRepository.getActiveAppointment()
          : null;
      final taskId = activeSession?.taskId ?? activeAppointment?.taskId;
      final goals = await ref.read(taskRepositoryProvider).getGoals();
      await _focusNotificationService.sync(
        appointment: activeAppointment,
        session: activeSession,
        taskTitle: taskId == null
            ? '当前任务'
            : findTaskTitle(goals, taskId) ?? '当前任务',
      );
    } catch (_) {
      // A local focus flow stays usable when the notification adapter is unavailable.
    }
  }

  Future<void> _syncNationalFocusReminder(List<NationalFocusCard> cards) async {
    try {
      await _focusNotificationService.syncNationalFocusReminder(
        hasPendingConfirmations: cards.any(
          (card) =>
              card.state == NationalFocusCardState.pendingTodayConfirmation,
        ),
      );
    } catch (_) {
      // Reminder delivery is optional and cannot block National Focus actions.
    }
  }

  /// Watches the account time zone so all-day reminders follow a change.
  ///
  /// The profile stream is the only notification a time zone edit produces, so
  /// an existing plan must be rebuilt without waiting for a schedule edit.
  void _watchProfileTimeZone() {
    unawaited(_profileReminderSubscription?.cancel());
    _profileReminderSubscription = ref
        .read(profileRepositoryProvider)
        .watchProfile()
        .listen(
          (profile) {
            final zone = AccountTimeZones.effectiveId(
              profile.displayTimeZoneId,
            );
            final previous = _reminderTimeZoneId;
            _reminderTimeZoneId = zone;
            if (previous != null && previous != zone) {
              unawaited(_scheduleReminderSync.reconcileOnce());
            }
          },
          onError: (Object _) {
            // An unreadable profile keeps the current plan; the next edit or
            // resume reconciles again.
          },
        );
  }

  Future<void> _openScheduleReminder(ScheduleReminderRequest request) async {
    if (!mounted) return;
    _focusNotificationService.takePendingScheduleRequest();
    final userId = ref.read(authRepositoryProvider).currentUserId;
    // A notification shown before an account switch must never open the next
    // account's data: the payload carries the owner that registered it.
    if (userId == null || request.ownerId != userId) return;
    final repository = ref.read(scheduleRepositoryProvider);
    final date = DateTime.tryParse(request.dateKey);
    if (date == null) return;
    List<Schedule> rows;
    try {
      rows = await repository.getSchedules(
        from: date.subtract(const Duration(days: 1)),
        to: date.add(const Duration(days: 2)),
      );
    } catch (_) {
      // A reminder whose rows cannot be read must not navigate to a guess.
      return;
    }
    final owned = rows.any(
      (row) => row.id == request.scheduleId && !row.isRecurrenceCancelled,
    );
    if (!owned) return;
    if (!mounted) return;
    final handler = ref.read(scheduleReminderOpenHandlerProvider);
    if (handler != null) {
      await handler(request);
      return;
    }
    // 计划目的地已集成：按真正的日历日与已拥有安排定位，不进入专注流程。
    final day = DateTime(date.year, date.month, date.day);
    setState(() {
      _index = _planIndex;
      _planTarget = PlanTarget(day: day, scheduleId: request.scheduleId);
    });
  }

  Future<void> _openFocusFlow(String payload) async {
    if (!mounted) return;
    // 普通安排提醒只打开计划页的日历日/安排，不进入专注流程。
    final planTarget = PlanTarget.tryParse(payload);
    if (planTarget != null) {
      setState(() {
        _index = _planIndex;
        _planTarget = planTarget;
      });
      return;
    }
    if (payload.startsWith('daily-open-reminder:')) {
      setState(() => _index = _boardIndex);
      return;
    }
    if (payload.startsWith('national-focus-reminder:')) {
      setState(() => _index = _nationalFocusIndex);
      return;
    }
    final separator = payload.indexOf(':');
    if (separator <= 0 || separator == payload.length - 1) return;
    final kind = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    final focusRepository = ref.read(focusRepositoryProvider);
    final taskRepository = ref.read(taskRepositoryProvider);
    try {
      FocusSession? session;
      AppointmentPreparation? appointment;
      if (kind == 'session') {
        session = await focusRepository.getSession(id);
      } else if (kind == 'appointment') {
        await focusRepository.settleDueAppointments();
        appointment = await focusRepository.getAppointment(id);
        final sessionId = appointment?.sessionId;
        if (sessionId != null) {
          session = await focusRepository.getSession(sessionId);
        }
      }
      final taskId = session?.taskId ?? appointment?.taskId;
      if (taskId == null || !mounted) return;
      final goals = await taskRepository.getGoals();
      if (!mounted) return;
      final title = findTaskTitle(goals, taskId) ?? '已删除的任务';
      if (session != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                FocusSessionPage(session: session!, taskTitle: title),
          ),
        );
      } else if (appointment != null && appointment.isActive) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AppointmentPreparationPage(
              appointment: appointment!,
              taskTitle: title,
            ),
          ),
        );
      }
    } catch (_) {
      // Opening a stale notification never changes a settled focus record.
    }
  }

  void _openNationalFocusAiAnalysis() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationalFocusAiAnalysisPage(
          onOpenSync: () => openAiManualSync(context, ref),
          mcpUrl: ref.read(nationalFocusMcpUrlProvider),
          repository: ref.read(nationalFocusAiGrantRepositoryProvider),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    _notificationOpenSubscription.cancel();
    _scheduleOpenSubscription.cancel();
    unawaited(_profileReminderSubscription?.cancel());
    _nationalFocusReminderSubscription.cancel();
    _nationalFocusCheckpointScheduler.dispose();
    unawaited(_scheduleReminderSync.detach());
    // 正常退出只停止本进程监听，未来 OS 提醒继续排队；登出/切号走 releaseUser。
    unawaited(_focusNotificationService.detachForProcessExit());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(nationalFocusRepositoryProvider, (previous, next) {
      unawaited(_nationalFocusReminderSubscription.cancel());
      _nationalFocusReminderSubscription = next.watchTreeCards().listen(
        (cards) => unawaited(_syncNationalFocusReminder(cards)),
        onError: (Object _) {},
      );
    });
    ref.listen(focusRepositoryProvider, (previous, next) {
      unawaited(_syncFocusStatus());
    });
    ref.watch(scheduleRepositoryProvider);
    ref.listen(scheduleRepositoryProvider, (previous, next) {
      unawaited(_scheduleReminderSync.attach(next));
    });
    ref.watch(profileRepositoryProvider);
    ref.listen(profileRepositoryProvider, (previous, next) {
      _watchProfileTimeZone();
    });
    ref.listen(authUserIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        // 切换账号作废旧用户的待上传请求，避免随后按错误身份继续。
        unawaited(ref.read(cloudAutoUploadQueueStoreProvider).clear(previous));
        // 登出/切号时取消旧账号已登记的提醒；正常退出不会走到这里。
        unawaited(_focusNotificationService.releaseUser(previous));
      }
    });
    ref.watch(cloudVersionCheckProvider);
    final autoUpload = ref.watch(cloudAutoUploadCoordinatorProvider);
    final nationalFocusRepository = ref.watch(nationalFocusRepositoryProvider);
    final lifecycleStatusRepository = ref.watch(
      userLifecycleStatusRepositoryProvider,
    );
    final pages = [
      BoardPage(
        onOpenNationalFocus: () => setState(() => _index = _nationalFocusIndex),
        onOpenPlan: () => setState(() => _index = _planIndex),
      ),
      PlanPage(
        displayTimeZoneLoader: () => resolveAccountDisplayTimeZoneId(
          ref.read(profileRepositoryProvider),
        ),
        navigationTarget: _planTarget,
      ),
      NationalFocusTreePage(
        key: ValueKey(ref.watch(authRepositoryProvider).currentUserId),
        userId: ref.watch(authRepositoryProvider).currentUserId,
        repository: nationalFocusRepository,
        onOpenAiAnalysis: _openNationalFocusAiAnalysis,
        onTodayConfirmed: autoUpload?.enqueue,
        onNotificationCapabilityUse: () => unawaited(
          _focusNotificationService.ensureNotificationPermissionForUse(),
        ),
        // 检查点本身固定北京时间 04:00；这里只决定显示用的账号时区。
        displayTimeZoneLoader: () async {
          final profile = await ref
              .read(profileRepositoryProvider)
              .getProfile();
          return AccountTimeZones.effectiveId(profile.displayTimeZoneId);
        },
      ),
      const FocusChainPage(),
      const MyPage(),
    ];

    final wide = MediaQuery.sizeOf(context).width >= 840;
    final content = SafeArea(
      child: StreamBuilder<UserLifecycleStatus?>(
        stream: lifecycleStatusRepository.watchStatus(),
        builder: (context, snapshot) => Column(
          children: [
            if (snapshot.data?.isSuspended == true)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pause_circle_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '此用户已停用。新业务操作和同步已暂停；本机保留的流程仍按原时间线继续，恢复后再同步。',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      body: Row(
        children: [
          if (wide) ...[
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final item in _destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _index == _nationalFocusIndex
                      ? double.infinity
                      : PactaSpacing.maxContentWidth,
                ),
                child: content,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final item in _destinations)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
