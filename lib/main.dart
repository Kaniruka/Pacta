import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/auth_repository.dart';
import 'src/auth/admin_password_reset_card.dart';
import 'src/auth/admin_user_lifecycle_card.dart';
import 'src/auth/supabase_auth_repository.dart';
import 'src/auth/user_lifecycle.dart';
import 'src/auth/user_lifecycle_models.dart';
import 'src/board/national_focus_summary_card.dart';
import 'src/calendar/calendar_page.dart';
import 'src/calendar/calendar_provider.dart';
import 'src/calendar/calendar_repository.dart';
import 'src/focus/focus_models.dart';
import 'src/focus/focus_repository.dart';
import 'src/focus/focus_clock_review_page.dart';
import 'src/focus/focus_reconciliation_page.dart';
import 'src/focus/focus_time_zones.dart';
import 'src/national_focus/national_focus_repository.dart';
import 'src/national_focus/national_focus_tree_page.dart';
import 'src/notifications/focus_notification_service.dart';
import 'src/notifications/focus_notification_settings_page.dart';
import 'src/tasks/task_database.dart' show PactaDatabase;
import 'src/tasks/task_models.dart';
import 'src/tasks/task_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final focusNotificationService = FocusNotificationService();
  await focusNotificationService.initialize();
  final url = const String.fromEnvironment('SUPABASE_URL');
  final key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  AuthRepository repository = const UnavailableAuthRepository();
  final database = PactaDatabase.open();
  TaskRemoteDataSource remote = const UnavailableTaskRemoteDataSource();
  FocusRemoteDataSource focusRemote = const UnavailableFocusRemoteDataSource();
  NationalFocusRemoteDataSource nationalFocusRemote =
      const UnavailableNationalFocusRemoteDataSource();
  CalendarRemoteDataSource calendarRemote =
      const UnavailableCalendarRemoteDataSource();
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    repository = SupabaseAuthRepository(Supabase.instance.client);
    remote = SupabaseTaskRemoteDataSource(Supabase.instance.client);
    focusRemote = SupabaseFocusRemoteDataSource(Supabase.instance.client);
    nationalFocusRemote = SupabaseNationalFocusRemoteDataSource(
      Supabase.instance.client,
    );
    calendarRemote = SupabaseCalendarRemoteDataSource(Supabase.instance.client);
  }
  runApp(
    PactaApp(
      authRepository: repository,
      focusNotificationService: focusNotificationService,
      taskRepositoryFactory: (userId) => LocalTaskRepository(
        database: database,
        userId: userId,
        remote: remote,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      focusRepositoryFactory: (userId) => LocalFocusRepository(
        database: database,
        userId: userId,
        remote: focusRemote,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      nationalFocusRepositoryFactory: (userId) => LocalNationalFocusRepository(
        database: database,
        userId: userId,
        remote: nationalFocusRemote,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      calendarRepositoryFactory: (userId) => LocalCalendarRepository(
        database: database,
        userId: userId,
        provider: Platform.isAndroid
            ? const AndroidCalendarProvider()
            : const UnsupportedCalendarProvider(),
        remote: calendarRemote,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      userLifecycleRepositoryFactory: (userId) => UserLifecycleRepository(
        authRepository: repository,
        localAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
    ),
  );
}

class PactaApp extends StatelessWidget {
  const PactaApp({
    super.key,
    required this.authRepository,
    this.focusNotificationService,
    this.taskRepositoryFactory,
    this.focusRepositoryFactory,
    this.nationalFocusRepositoryFactory,
    this.calendarRepositoryFactory,
    this.userLifecycleRepositoryFactory,
  });

  final AuthRepository authRepository;
  final FocusNotificationService? focusNotificationService;
  final TaskRepository Function(String userId)? taskRepositoryFactory;
  final FocusRepository Function(String userId)? focusRepositoryFactory;
  final NationalFocusRepository Function(String userId)?
  nationalFocusRepositoryFactory;
  final CalendarRepository Function(String userId)? calendarRepositoryFactory;
  final UserLifecycleStatusRepository Function(String userId)?
  userLifecycleRepositoryFactory;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        focusNotificationServiceProvider.overrideWithValue(
          focusNotificationService ?? DisabledFocusNotificationService(),
        ),
        taskRepositoryFactoryProvider.overrideWithValue(
          taskRepositoryFactory ?? (_) => const UnavailableTaskRepository(),
        ),
        focusRepositoryFactoryProvider.overrideWithValue(
          focusRepositoryFactory ?? (_) => const UnavailableFocusRepository(),
        ),
        nationalFocusRepositoryFactoryProvider.overrideWithValue(
          nationalFocusRepositoryFactory ??
              (_) => const UnavailableNationalFocusRepository(),
        ),
        calendarRepositoryFactoryProvider.overrideWithValue(
          calendarRepositoryFactory ??
              (_) => const UnavailableCalendarRepository(),
        ),
        userLifecycleRepositoryFactoryProvider.overrideWithValue(
          userLifecycleRepositoryFactory ??
              (_) => const UnavailableUserLifecycleStatusRepository(),
        ),
      ],
      child: MaterialApp(
        title: 'Pacta',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff385a52),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff8faf8),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return const UnavailableAuthRepository();
});

final focusNotificationServiceProvider = Provider<FocusNotificationService>((
  ref,
) {
  return DisabledFocusNotificationService();
});

final taskRepositoryFactoryProvider =
    Provider<TaskRepository Function(String userId)>((ref) {
      return (_) => const UnavailableTaskRepository();
    });

final focusRepositoryFactoryProvider =
    Provider<FocusRepository Function(String userId)>((ref) {
      return (_) => const UnavailableFocusRepository();
    });

final taskRepositoryProvider = Provider.autoDispose<TaskRepository>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUserId;
  if (userId == null) return const UnavailableTaskRepository();
  final repository = ref.watch(taskRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final focusRepositoryProvider = Provider.autoDispose<FocusRepository>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUserId;
  if (userId == null) return const UnavailableFocusRepository();
  final repository = ref.watch(focusRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final nationalFocusRepositoryFactoryProvider =
    Provider<NationalFocusRepository Function(String userId)>((ref) {
      return (_) => const UnavailableNationalFocusRepository();
    });

final nationalFocusRepositoryProvider =
    Provider.autoDispose<NationalFocusRepository>((ref) {
      final userId = ref.watch(authRepositoryProvider).currentUserId;
      if (userId == null) return const UnavailableNationalFocusRepository();
      final repository = ref.watch(nationalFocusRepositoryFactoryProvider)(
        userId,
      );
      ref.onDispose(repository.dispose);
      return repository;
    });

final calendarRepositoryFactoryProvider =
    Provider<CalendarRepository Function(String userId)>((ref) {
      return (_) => const UnavailableCalendarRepository();
    });

final calendarRepositoryProvider = Provider.autoDispose<CalendarRepository>((
  ref,
) {
  final userId = ref.watch(authRepositoryProvider).currentUserId;
  if (userId == null) return const UnavailableCalendarRepository();
  final repository = ref.watch(calendarRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final userLifecycleRepositoryFactoryProvider =
    Provider<UserLifecycleStatusRepository Function(String userId)>((ref) {
      return (_) => const UnavailableUserLifecycleStatusRepository();
    });

final userLifecycleStatusRepositoryProvider =
    Provider.autoDispose<UserLifecycleStatusRepository>((ref) {
      final userId = ref.watch(authRepositoryProvider).currentUserId;
      if (userId == null) {
        return const UnavailableUserLifecycleStatusRepository();
      }
      return ref.watch(userLifecycleRepositoryFactoryProvider)(userId);
    });

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(authRepositoryProvider);
    return StreamBuilder<String?>(
      stream: repository.authState,
      initialData: repository.currentUserIdentifier,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == null ? const AuthScreen() : const AppShell();
      },
    );
  }
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => _error = '请输入有效邮箱，以及至少 8 位密码。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (_isRegistering) {
        await repository.signUp(email: email, password: password);
      } else {
        await repository.signIn(email: email, password: password);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is AuthException) {
      if (error.message.toLowerCase().contains('eligib')) {
        return '该标识没有可用的注册资格，请联系管理员。';
      }
      return error.message;
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.anchor_rounded, size: 48, color: colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      '进入 Pacta',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegistering ? '使用管理员发放的资格创建你的访问凭据。' : '把注意力带回眼前的一步。',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegistering ? '注册' : '登录'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _error = null;
                            }),
                      child: Text(
                        _isRegistering ? '已有账号？返回登录' : '还没有资格？请联系管理员发放注册资格',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  late final StreamSubscription<String> _notificationOpenSubscription;

  static const _destinations = [
    _Destination('看板', Icons.dashboard_outlined, Icons.dashboard),
    _Destination('国策树', Icons.account_tree_outlined, Icons.account_tree),
    _Destination('专注链', Icons.bolt_outlined, Icons.bolt),
    _Destination('我的', Icons.person_outline, Icons.person),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      unawaited(_syncPendingData());
    });
    _notificationOpenSubscription = ref
        .read(focusNotificationServiceProvider)
        .openFlowRequests
        .listen((payload) {
          ref.read(focusNotificationServiceProvider).takePendingOpenRequest();
          unawaited(_openFocusFlow(payload));
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncPendingData());
      final request = ref
          .read(focusNotificationServiceProvider)
          .takePendingOpenRequest();
      if (request != null) unawaited(_openFocusFlow(request));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncPendingData());
  }

  Future<void> _syncPendingData() async {
    try {
      await ref.read(userLifecycleStatusRepositoryProvider).refresh();
    } catch (_) {
      // A failed status check preserves the last status known on this device.
    }
    try {
      await ref.read(focusRepositoryProvider).sync();
    } catch (_) {
      // Focus records remain local and are retried on resume or reconnect.
    }
    await _syncFocusStatus();
    try {
      await ref.read(taskRepositoryProvider).sync();
    } catch (_) {
      // Offline edits stay local and are retried on resume or reconnect.
    }
    try {
      await ref.read(nationalFocusRepositoryProvider).sync();
    } catch (_) {
      // National Focus edits stay local and are retried on resume or reconnect.
    }
    try {
      await ref.read(calendarRepositoryProvider).sync();
    } catch (_) {
      // Calendar Blocks stay local and are retried on resume or reconnect.
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
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            appointment: activeAppointment,
            session: activeSession,
            taskTitle: taskId == null
                ? '当前任务'
                : _findTaskTitle(goals, taskId) ?? '当前任务',
          );
    } catch (_) {
      // A local focus flow stays usable when the notification adapter is unavailable.
    }
  }

  Future<void> _openFocusFlow(String payload) async {
    if (!mounted) return;
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
      final title = _findTaskTitle(goals, taskId) ?? '已删除的任务';
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    _notificationOpenSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nationalFocusRepository = ref.watch(nationalFocusRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final lifecycleStatusRepository = ref.watch(
      userLifecycleStatusRepositoryProvider,
    );
    final pages = [
      BoardPage(onOpenNationalFocus: () => setState(() => _index = 1)),
      NationalFocusTreePage(
        repository: nationalFocusRepository,
        displayTimeZoneLoader: () async {
          final deviceZone = await FlutterTimezone.getLocalTimezone();
          final dashboard = await focusRepository.getDashboardMetrics(
            deviceTimeZoneId: deviceZone.identifier,
          );
          return dashboard.displayTimeZoneId;
        },
      ),
      const FocusChainPage(),
      const MyPage(),
    ];
    final destination = _destinations[_index];
    return Scaffold(
      appBar: AppBar(title: Text(destination.label)),
      body: StreamBuilder<UserLifecycleStatus?>(
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
      bottomNavigationBar: NavigationBar(
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

class _FocusReconciliationPrompt extends StatelessWidget {
  const _FocusReconciliationPrompt({
    required this.focusRepository,
    required this.taskRepository,
  });

  final FocusRepository focusRepository;
  final TaskRepository taskRepository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FocusReconciliationCase>>(
      stream: focusRepository.watchFocusReconciliations(),
      builder: (context, snapshot) {
        final pendingCount = (snapshot.data ?? const [])
            .where((item) => item.isPendingReview)
            .length;
        if (pendingCount == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text('$pendingCount 组专注记录待核对'),
              subtitle: const Text('争议记录暂不计入统计，其他任务仍可继续。'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FocusReconciliationPage(
                    focusRepository: focusRepository,
                    taskRepository: taskRepository,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusClockReviewPrompt extends StatelessWidget {
  const _FocusClockReviewPrompt({required this.repository});

  final FocusRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FocusClockReviewCase>>(
      stream: repository.watchClockReviewCases(),
      builder: (context, snapshot) {
        final cases = snapshot.data ?? const <FocusClockReviewCase>[];
        if (cases.isEmpty) return const SizedBox.shrink();
        final deferredCount = cases.where((item) => item.isDeferred).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text('${cases.length} 段专注时间待核对'),
              subtitle: Text(
                deferredCount == 0
                    ? '时钟变化后的区间保留待核对，不会直接判为失败。'
                    : '$deferredCount 段已暂缓；可靠时间仍可继续使用。',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FocusClockReviewPage(repository: repository),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key, required this.onOpenNationalFocus});

  final VoidCallback onOpenNationalFocus;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  late final Future<String> _deviceTimeZoneId;

  @override
  void initState() {
    super.initState();
    _deviceTimeZoneId = _loadDeviceTimeZoneId();
  }

  Future<String> _loadDeviceTimeZoneId() async {
    final timeZone = await FlutterTimezone.getLocalTimezone();
    if (!FocusTimeZones.contains(timeZone.identifier)) {
      throw StateError('设备返回了无法识别的 IANA 时区。');
    }
    return timeZone.identifier;
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final nationalFocusRepository = ref.watch(nationalFocusRepositoryProvider);
    final calendarRepository = ref.watch(calendarRepositoryProvider);
    return FutureBuilder<String>(
      future: _deviceTimeZoneId,
      builder: (context, timeZoneSnapshot) {
        final deviceTimeZoneId = timeZoneSnapshot.data ?? 'Etc/UTC';
        return StreamBuilder<List<Goal>>(
          stream: taskRepository.watchGoals(),
          initialData: const [],
          builder: (context, goalSnapshot) =>
              StreamBuilder<FocusDashboardMetrics>(
                stream: focusRepository.watchDashboardMetrics(
                  deviceTimeZoneId: deviceTimeZoneId,
                ),
                builder: (context, metricsSnapshot) => _BoardContent(
                  repository: taskRepository,
                  focusRepository: focusRepository,
                  nationalFocusRepository: nationalFocusRepository,
                  calendarRepository: calendarRepository,
                  onOpenNationalFocus: widget.onOpenNationalFocus,
                  goals: goalSnapshot.data ?? const [],
                  metrics: metricsSnapshot.data,
                  displayTimeZoneId:
                      metricsSnapshot.data?.displayTimeZoneId ??
                      (timeZoneSnapshot.hasError ? deviceTimeZoneId : null),
                  deviceTimeZoneError: timeZoneSnapshot.hasError,
                ),
              ),
        );
      },
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({
    required this.repository,
    required this.focusRepository,
    required this.nationalFocusRepository,
    required this.calendarRepository,
    required this.onOpenNationalFocus,
    required this.goals,
    required this.metrics,
    required this.displayTimeZoneId,
    required this.deviceTimeZoneError,
  });

  final TaskRepository repository;
  final FocusRepository focusRepository;
  final NationalFocusRepository nationalFocusRepository;
  final CalendarRepository calendarRepository;
  final VoidCallback onOpenNationalFocus;
  final List<Goal> goals;
  final FocusDashboardMetrics? metrics;
  final String? displayTimeZoneId;
  final bool deviceTimeZoneError;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '今天先做什么',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _createGoal(context),
              icon: const Icon(Icons.add),
              label: const Text('新建目标'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _FocusReconciliationPrompt(
          focusRepository: focusRepository,
          taskRepository: repository,
        ),
        _FocusClockReviewPrompt(repository: focusRepository),
        if (goals.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48),
                  SizedBox(height: 12),
                  Text('暂无任务', style: TextStyle(fontSize: 22)),
                  SizedBox(height: 8),
                  Text('创建目标和任务后，它们会优先出现在这里。'),
                ],
              ),
            ),
          )
        else
          for (final goal in goals)
            _GoalCard(
              repository: repository,
              goal: goal,
              focusProgressSecondsByTask: metrics?.focusProgressSecondsByTask,
              pendingReviewTaskIds: metrics?.pendingReviewTaskIds ?? const {},
            ),
        const SizedBox(height: 12),
        NationalFocusSummaryCard(
          repository: nationalFocusRepository,
          displayTimeZoneId: displayTimeZoneId,
          onOpenTree: onOpenNationalFocus,
        ),
        const SizedBox(height: 12),
        _RecentFocusActivityCard(
          repository: focusRepository,
          metrics: metrics,
          deviceTimeZoneId: displayTimeZoneId ?? 'Etc/UTC',
          deviceTimeZoneError: deviceTimeZoneError,
        ),
        const SizedBox(height: 12),
        CalendarAgendaCard(repository: calendarRepository),
      ],
    );
  }

  Future<void> _createGoal(BuildContext context) async {
    final draft = await _showGoalDialog(context);
    if (draft != null) await repository.createGoal(draft);
  }
}

class _RecentFocusActivityCard extends StatelessWidget {
  const _RecentFocusActivityCard({
    required this.repository,
    required this.metrics,
    required this.deviceTimeZoneId,
    required this.deviceTimeZoneError,
  });

  static const _followDevice = '__follow_device__';

  final FocusRepository repository;
  final FocusDashboardMetrics? metrics;
  final String deviceTimeZoneId;
  final bool deviceTimeZoneError;

  @override
  Widget build(BuildContext context) {
    final value = metrics;
    final hasRecentActivity =
        value?.recentActivity.any((day) => day.activeSeconds > 0) ?? false;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '近期专注活动',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Tooltip(
                  message: '显示时区：${value?.displayTimeZoneId ?? '加载中'}',
                  child: TextButton.icon(
                    onPressed: value == null
                        ? null
                        : () => _chooseTimeZone(context, value),
                    icon: const Icon(Icons.schedule_outlined),
                    label: const Text('时区'),
                  ),
                ),
              ],
            ),
            if (deviceTimeZoneError)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('无法读取设备时区，当前按 UTC 显示。可手动选择时区。'),
              ),
            if (value == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text(
                '近 7 天 · ${value.followsDeviceTimeZone ? '设备' : '显示'}时区 '
                '${value.displayTimeZoneId} · 累计有效专注 '
                '${_formatDuration(value.totalAcceptedFocusSeconds)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (value.hasPendingReview)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('存在待核对专注记录；争议部分暂不计入上述统计。'),
                ),
              const SizedBox(height: 12),
              if (!hasRecentActivity)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.timelapse_outlined),
                      SizedBox(width: 10),
                      Expanded(child: Text('近 7 天暂无专注活动。')),
                    ],
                  ),
                )
              else
                for (final day in value.recentActivity)
                  _FocusActivityDayRow(
                    day: day,
                    maximumSeconds: value.recentActivity.fold<int>(
                      0,
                      (maximum, item) => item.activeSeconds > maximum
                          ? item.activeSeconds
                          : maximum,
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _chooseTimeZone(
    BuildContext context,
    FocusDashboardMetrics current,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => _FocusTimeZonePickerDialog(
        deviceTimeZoneId: deviceTimeZoneId,
        selectedTimeZoneId: current.displayTimeZoneId,
        followsDeviceTimeZone: current.followsDeviceTimeZone,
      ),
    );
    if (choice == null) return;
    await repository.setDisplayTimeZonePreference(
      choice == _followDevice ? null : choice,
    );
  }
}

class _FocusActivityDayRow extends StatelessWidget {
  const _FocusActivityDayRow({required this.day, required this.maximumSeconds});

  final FocusActivityDay day;
  final int maximumSeconds;

  @override
  Widget build(BuildContext context) {
    final dayName = switch (day.date.weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      _ => '周日',
    };
    final label = '${day.date.month}月${day.date.day}日 · $dayName';
    final progress = maximumSeconds == 0
        ? 0.0
        : (day.activeSeconds / maximumSeconds).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        label: '$label，${_formatDuration(day.activeSeconds)}',
        child: Row(
          children: [
            SizedBox(width: 118, child: Text(label)),
            Expanded(
              child: ExcludeSemantics(
                child: LinearProgressIndicator(value: progress),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 68,
              child: Text(
                _formatDuration(day.activeSeconds),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusTimeZonePickerDialog extends StatefulWidget {
  const _FocusTimeZonePickerDialog({
    required this.deviceTimeZoneId,
    required this.selectedTimeZoneId,
    required this.followsDeviceTimeZone,
  });

  final String deviceTimeZoneId;
  final String selectedTimeZoneId;
  final bool followsDeviceTimeZone;

  @override
  State<_FocusTimeZonePickerDialog> createState() =>
      _FocusTimeZonePickerDialogState();
}

class _FocusTimeZonePickerDialogState
    extends State<_FocusTimeZonePickerDialog> {
  final _search = TextEditingController();
  late final List<String> _timeZones = FocusTimeZones.identifiers.toList()
    ..sort();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = _timeZones
        .where((zone) => zone.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
      title: const Text('显示时区'),
      content: SizedBox(
        width: 360,
        height: 440,
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('跟随设备时区'),
              subtitle: Text(widget.deviceTimeZoneId),
              trailing: widget.followsDeviceTimeZone
                  ? const Icon(Icons.check, semanticLabel: '当前选择')
                  : null,
              onTap: () => Navigator.pop(
                context,
                _RecentFocusActivityCard._followDevice,
              ),
            ),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索 IANA 时区',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('没有匹配的时区'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final zone = filtered[index];
                        final selected =
                            !widget.followsDeviceTimeZone &&
                            zone == widget.selectedTimeZoneId;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          title: Text(zone),
                          trailing: selected
                              ? const Icon(Icons.check, semanticLabel: '当前选择')
                              : null,
                          onTap: () => Navigator.pop(context, zone),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.repository,
    required this.goal,
    required this.focusProgressSecondsByTask,
    required this.pendingReviewTaskIds,
  });

  final TaskRepository repository;
  final Goal goal;
  final Map<String, int>? focusProgressSecondsByTask;
  final Set<String> pendingReviewTaskIds;

  Future<void> _confirmDeleteGoal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除目标和任务？'),
        content: Text(
          '“${goal.title}”及其全部任务将从工作清单移除，且不能恢复。'
          '已有预约、专注和暂停会继续有效，历史会保留原任务名称并标记为已删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.deleteGoal(goal.id);
  }

  @override
  Widget build(BuildContext context) {
    final status = goal.tasks.isEmpty
        ? '暂无任务 · 未完成'
        : goal.isComplete
        ? '已完成'
        : '进行中';
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(goal.title),
              subtitle: Text('${goal.classification.label} · $status'),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: '编辑目标',
                    onPressed: () async {
                      final draft = await _showGoalDialog(
                        context,
                        initial: goal,
                      );
                      if (draft != null) {
                        await repository.updateGoal(goal.id, draft);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '删除目标',
                    onPressed: () => _confirmDeleteGoal(context),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            if (goal.tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('暂无任务，先添加一个可执行的下一步。'),
              )
            else
              for (final task in goal.tasks)
                _TaskTile(
                  repository: repository,
                  task: focusProgressSecondsByTask == null
                      ? task
                      : task.copyWith(
                          focusProgressSeconds:
                              focusProgressSecondsByTask![task.id] ?? 0,
                        ),
                  hasPendingReview: pendingReviewTaskIds.contains(task.id),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final draft = await _showTaskDialog(context, goal: goal);
                  if (draft != null) {
                    await repository.createTask(goal.id, draft);
                  }
                },
                icon: const Icon(Icons.add_task),
                label: const Text('添加任务'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({
    required this.repository,
    required this.task,
    this.hasPendingReview = false,
  });

  final TaskRepository repository;
  final Task task;
  final bool hasPendingReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadline = task.deadline == null
        ? null
        : '截止 ${_formatDateTime(task.deadline!.toLocal())}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: task.isComplete,
        onChanged: (value) {
          if (value != null) {
            repository.setTaskCompletion(task.id, isComplete: value);
          }
        },
      ),
      title: Text(
        task.title,
        style: task.isComplete
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        [
          task.classification.label,
          if (task.estimatedMinutes != null) '${task.estimatedMinutes} 分钟',
          if (task.focusProgressSeconds > 0)
            '已专注 ${_formatDuration(task.focusProgressSeconds)}',
          if (hasPendingReview) '待核对（争议部分暂不计入专注统计）',
          ?deadline,
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: '开始专注',
        onPressed: () async {
          final focusRepository = ref.read(focusRepositoryProvider);
          final activeAppointment = await focusRepository
              .getActiveAppointment();
          if (!context.mounted) return;
          if (activeAppointment != null) {
            final goals = await repository.getGoals(includeDeleted: true);
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AppointmentPreparationPage(
                  appointment: activeAppointment,
                  taskTitle:
                      _findTaskTitle(goals, activeAppointment.taskId) ??
                      '原预约任务',
                ),
              ),
            );
            return;
          }
          final activeSession = await focusRepository.getActiveSession();
          if (!context.mounted) return;
          if (activeSession != null) {
            final goals = await repository.getGoals(includeDeleted: true);
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FocusSessionPage(
                  session: activeSession,
                  taskTitle:
                      _findTaskTitle(goals, activeSession.taskId) ?? '原任务',
                ),
              ),
            );
            return;
          }
          final mode = await focusRepository.getLastMode();
          if (!context.mounted) return;
          final result = await showDialog<Object>(
            context: context,
            builder: (_) => FocusSetupDialog(task: task, initialMode: mode),
          );
          if (result is FocusSession && context.mounted) {
            var taskTitle = task.title;
            if (result.taskId != task.id) {
              final goals = await repository.getGoals(includeDeleted: true);
              if (!context.mounted) return;
              taskTitle = _findTaskTitle(goals, result.taskId) ?? '原任务';
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    FocusSessionPage(session: result, taskTitle: taskTitle),
              ),
            );
          }
          if (result is AppointmentPreparation && context.mounted) {
            var taskTitle = task.title;
            if (result.taskId != task.id) {
              final goals = await repository.getGoals(includeDeleted: true);
              if (!context.mounted) return;
              taskTitle = _findTaskTitle(goals, result.taskId) ?? '原任务';
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AppointmentPreparationPage(
                  appointment: result,
                  taskTitle: taskTitle,
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.play_arrow_rounded),
      ),
      onTap: () async {
        final draft = await _showTaskDialog(context, task: task);
        if (draft != null) await repository.updateTask(task.id, draft);
      },
    );
  }
}

Future<GoalDraft?> _showGoalDialog(BuildContext context, {Goal? initial}) {
  return showDialog<GoalDraft>(
    context: context,
    builder: (_) => _GoalDialog(initial: initial),
  );
}

Future<TaskDraft?> _showTaskDialog(
  BuildContext context, {
  Goal? goal,
  Task? task,
}) {
  return showDialog<TaskDraft>(
    context: context,
    builder: (_) => _TaskDialog(goal: goal, initial: task),
  );
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({this.initial});

  final Goal? initial;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _title;
  late TaskClassification _classification;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _classification =
        widget.initial?.classification ?? TaskClassification.regular;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建目标' : '编辑目标'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(labelText: '目标名称'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TaskClassification>(
          initialValue: _classification,
          decoration: const InputDecoration(labelText: '新任务默认分类'),
          items: [
            for (final classification in TaskClassification.values)
              DropdownMenuItem(
                value: classification,
                child: Text(classification.label),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _classification = value);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          GoalDraft(title: _title.text, classification: _classification),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({this.goal, this.initial});

  final Goal? goal;
  final Task? initial;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _estimatedMinutes;
  late TaskClassification _classification;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _estimatedMinutes = TextEditingController(
      text: widget.initial?.estimatedMinutes?.toString(),
    );
    _classification =
        widget.initial?.classification ??
        widget.goal?.classification ??
        TaskClassification.regular;
    _deadline = widget.initial?.deadline?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _estimatedMinutes.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final initialDate = _deadline ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initialDate,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline ?? DateTime.now()),
    );
    if (!mounted || time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建任务' : '编辑任务'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '任务名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskClassification>(
            initialValue: _classification,
            decoration: const InputDecoration(labelText: '任务分类'),
            items: [
              for (final classification in TaskClassification.values)
                DropdownMenuItem(
                  value: classification,
                  child: Text(classification.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _classification = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _estimatedMinutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '预计时长（分钟，可选）'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _deadline == null
                      ? '未设置截止时间'
                      : '截止 ${_formatDateTime(_deadline!)}',
                ),
              ),
              IconButton(
                tooltip: '设置截止时间',
                onPressed: _pickDeadline,
                icon: const Icon(Icons.event_outlined),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: '清除截止时间',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          TaskDraft(
            title: _title.text,
            classification: _classification,
            estimatedMinutes: int.tryParse(_estimatedMinutes.text.trim()),
            deadline: _deadline,
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '$minutes分${remainingSeconds.toString().padLeft(2, '0')}秒';
}

class FocusChainPage extends ConsumerStatefulWidget {
  const FocusChainPage({super.key});

  @override
  ConsumerState<FocusChainPage> createState() => _FocusChainPageState();
}

class _FocusChainPageState extends ConsumerState<FocusChainPage> {
  TaskClassification? _filter;
  FocusChainMode _lastMode = FocusChainMode.regular;
  FocusRepository? _projectionRepository;
  String? _projectionSignature;
  late Future<List<FocusChainRecord>> _chainRecordsFuture;
  late Future<AppointmentChainRecord> _appointmentChainRecordFuture;
  late Future<AppointmentPreparation?> _activeAppointmentFuture;
  Future<List<FocusNode>> _nodesFuture = Future.value(const []);

  @override
  void initState() {
    super.initState();
    _activeAppointmentFuture = ref
        .read(focusRepositoryProvider)
        .getActiveAppointment();
    unawaited(_loadLastMode());
  }

  void _refreshActiveAppointment() {
    if (mounted) {
      setState(() {
        final repository = ref.read(focusRepositoryProvider);
        _activeAppointmentFuture = repository.getActiveAppointment();
        _appointmentChainRecordFuture = repository.getAppointmentChainRecord();
      });
    }
  }

  Future<void> _loadLastMode() async {
    final mode = await ref.read(focusRepositoryProvider).getLastMode();
    if (mounted) setState(() => _lastMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    return StreamBuilder<List<Goal>>(
      stream: taskRepository.watchGoals(includeDeleted: true),
      initialData: const [],
      builder: (context, snapshot) {
        final taskTitles = <String, String>{
          for (final goal in snapshot.data ?? const <Goal>[])
            for (final task in goal.tasks) task.id: _taskDisplayTitle(task),
        };
        final allTasks = [
          for (final goal in snapshot.data ?? const <Goal>[]) ...goal.tasks,
        ];
        final tasks = [
          for (final task in allTasks)
            if (!task.isDeleted && !task.isComplete && _matchesFilter(task))
              task,
        ];
        return StreamBuilder<List<FocusSession>>(
          stream: focusRepository.watchSessions(),
          initialData: const [],
          builder: (context, sessionsSnapshot) {
            final sessions = sessionsSnapshot.data ?? const <FocusSession>[];
            _updateProjectionFutures(focusRepository, sessions);
            final active = sessions
                .where((session) => session.isUnfinished)
                .firstOrNull;
            final activeTask = active == null
                ? null
                : allTasks
                      .where((task) => task.id == active.taskId)
                      .firstOrNull;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              children: [
                Text('专注链', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text('选择一个未完成任务，设定本次模式和时长。'),
                if (active != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('已有进行中的专注'),
                      subtitle: Text(
                        activeTask == null
                            ? '原任务'
                            : _taskDisplayTitle(activeTask),
                      ),
                      trailing: FilledButton(
                        onPressed: () => _openSession(
                          active,
                          taskTitles[active.taskId] ?? '原任务',
                        ),
                        child: const Text('返回专注'),
                      ),
                    ),
                  ),
                ],
                FutureBuilder<AppointmentPreparation?>(
                  future: _activeAppointmentFuture,
                  builder: (context, appointmentSnapshot) {
                    final appointment = appointmentSnapshot.data;
                    if (appointment == null) return const SizedBox.shrink();
                    final title = taskTitles[appointment.taskId] ?? '原预约任务';
                    return Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.event_available),
                              title: const Text('已有预约准备'),
                              subtitle: Text(
                                appointment.isPendingReview
                                    ? '$title · 待核对'
                                    : title,
                              ),
                            ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _openAppointment(appointment, title),
                                  child: const Text('返回准备'),
                                ),
                                FilledButton.tonal(
                                  onPressed: () =>
                                      _enterAppointment(appointment, title),
                                  child: const Text('提前进入专注'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _cancelAppointment(appointment),
                                  child: const Text('取消预约'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                SegmentedButton<TaskClassification?>(
                  segments: const [
                    ButtonSegment<TaskClassification?>(
                      value: null,
                      label: Text('全部'),
                    ),
                    ButtonSegment<TaskClassification?>(
                      value: TaskClassification.elite,
                      label: Text('精锐'),
                    ),
                    ButtonSegment<TaskClassification?>(
                      value: TaskClassification.regular,
                      label: Text('普通'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (values) =>
                      setState(() => _filter = values.single),
                ),
                const SizedBox(height: 12),
                if (tasks.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('当前筛选下没有可开始的任务。'),
                    ),
                  )
                else
                  for (final task in tasks)
                    Card(
                      child: ListTile(
                        title: Text(task.title),
                        subtitle: Text(
                          '${task.classification.label} · 已专注 '
                          '${_formatDuration(task.focusProgressSeconds)}',
                        ),
                        trailing: Tooltip(
                          message: '开始任务：${task.title}',
                          child: FilledButton.tonal(
                            onPressed: () => _showSetup(task),
                            child: const Text('开始'),
                          ),
                        ),
                      ),
                    ),
                const SizedBox(height: 16),
                FutureBuilder<List<FocusChainRecord>>(
                  future: _chainRecordsFuture,
                  builder: (context, recordSnapshot) {
                    final records = recordSnapshot.data ?? const [];
                    if (records.isEmpty) return const SizedBox.shrink();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '连续记录',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final record in records)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(record.mode.label),
                                trailing: Text(
                                  record.hasPendingReview
                                      ? '待核对'
                                      : '${record.currentConsecutive} 次 · 最佳 ${record.bestConsecutive} 次',
                                ),
                                subtitle: record.hasPendingReview
                                    ? const Text('争议结果暂不计入连续记录。')
                                    : null,
                              ),
                            FutureBuilder<AppointmentChainRecord>(
                              future: _appointmentChainRecordFuture,
                              builder: (context, appointmentSnapshot) {
                                final record = appointmentSnapshot.data;
                                if (record == null) {
                                  return const SizedBox.shrink();
                                }
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('预约链'),
                                  trailing: Text(
                                    record.hasPendingReview
                                        ? '待核对'
                                        : '${record.currentConsecutive} 次 · 最佳 ${record.bestConsecutive} 次',
                                  ),
                                  subtitle: record.hasPendingReview
                                      ? const Text('争议结果暂不计入连续记录。')
                                      : null,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (sessions.any((session) => !session.isUnfinished))
                  FutureBuilder<List<FocusNode>>(
                    future: _nodesFuture,
                    builder: (context, nodeSnapshot) => _FocusHistoryCard(
                      repository: focusRepository,
                      sessions: sessions
                          .where((session) => !session.isUnfinished)
                          .toList(),
                      nodes: nodeSnapshot.data ?? const [],
                      taskTitles: taskTitles,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateProjectionFutures(
    FocusRepository repository,
    List<FocusSession> sessions,
  ) {
    final signature = sessions
        .map(
          (session) =>
              '${session.id}:${session.taskId}:${session.mode.storageValue}:'
              '${session.status.storageValue}:${session.reviewDisposition.storageValue}:'
              '${session.effectiveSeconds}:${session.completedAt}',
        )
        .join('|');
    if (identical(_projectionRepository, repository) &&
        _projectionSignature == signature) {
      return;
    }
    _projectionRepository = repository;
    _projectionSignature = signature;
    _chainRecordsFuture = repository.getChainRecords();
    _appointmentChainRecordFuture = repository.getAppointmentChainRecord();
    _nodesFuture = sessions.any((session) => !session.isUnfinished)
        ? repository.getNodes()
        : Future.value(const []);
  }

  bool _matchesFilter(Task task) {
    return switch (_filter) {
      null => true,
      TaskClassification.elite =>
        task.classification == TaskClassification.elite ||
            task.classification == TaskClassification.both,
      TaskClassification.regular =>
        task.classification == TaskClassification.regular ||
            task.classification == TaskClassification.both,
      TaskClassification.both => true,
    };
  }

  FocusChainMode get _selectedMode => switch (_filter) {
    TaskClassification.elite => FocusChainMode.elite,
    TaskClassification.regular => FocusChainMode.regular,
    _ => _lastMode,
  };

  Future<void> _showSetup(Task task) async {
    final repository = ref.read(focusRepositoryProvider);
    final activeAppointment = await repository.getActiveAppointment();
    if (activeAppointment != null && mounted) {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      await _openAppointment(
        activeAppointment,
        _findTaskTitle(goals, activeAppointment.taskId) ?? task.title,
      );
      return;
    }
    final activeSession = await repository.getActiveSession();
    if (activeSession != null && mounted) {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      _openSession(
        activeSession,
        _findTaskTitle(goals, activeSession.taskId) ?? task.title,
      );
      return;
    }
    if (!mounted) return;
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => FocusSetupDialog(task: task, initialMode: _selectedMode),
    );
    if (result is FocusSession && mounted) {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      _openSession(result, _findTaskTitle(goals, result.taskId) ?? task.title);
    }
    if (result is AppointmentPreparation && mounted) {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      await _openAppointment(
        result,
        _findTaskTitle(goals, result.taskId) ?? task.title,
      );
    }
    if (result is FocusSession) {
      setState(() => _lastMode = result.mode);
    } else if (result is AppointmentPreparation) {
      setState(() => _lastMode = result.mode);
    }
    _refreshActiveAppointment();
  }

  Future<void> _openAppointment(
    AppointmentPreparation appointment,
    String taskTitle,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentPreparationPage(
          appointment: appointment,
          taskTitle: taskTitle,
        ),
      ),
    );
    _refreshActiveAppointment();
  }

  Future<void> _enterAppointment(
    AppointmentPreparation appointment,
    String taskTitle,
  ) async {
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .enterAppointmentEarly(appointment.id);
      if (!mounted) return;
      await ref
          .read(focusNotificationServiceProvider)
          .appointmentEnteredFocus(
            appointmentId: appointment.id,
            taskTitle: taskTitle,
          );
      await ref
          .read(focusNotificationServiceProvider)
          .sync(session: session, taskTitle: taskTitle);
      _openSession(session, taskTitle);
    } catch (error) {
      if (mounted) _showFocusError(context, error);
    } finally {
      _refreshActiveAppointment();
    }
  }

  Future<void> _cancelAppointment(AppointmentPreparation appointment) async {
    final reason = await _showTextEditor(
      context,
      title: '取消预约准备',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    try {
      await ref
          .read(focusRepositoryProvider)
          .cancelAppointment(
            appointmentId: appointment.id,
            failureReason: reason,
          );
      await ref.read(focusNotificationServiceProvider).sync(taskTitle: '当前任务');
      _refreshActiveAppointment();
    } catch (error) {
      if (mounted) _showFocusError(context, error);
    }
  }

  void _openSession(FocusSession session, String taskTitle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FocusSessionPage(session: session, taskTitle: taskTitle),
      ),
    );
  }
}

String? _findTaskTitle(List<Goal> goals, String taskId) {
  for (final goal in goals) {
    for (final task in goal.tasks) {
      if (task.id == taskId) return _taskDisplayTitle(task);
    }
  }
  return null;
}

String _taskDisplayTitle(Task task) =>
    task.isDeleted ? '${task.title}（已删除）' : task.title;

void _showFocusError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
  );
}

class _FocusHistoryCard extends StatelessWidget {
  const _FocusHistoryCard({
    required this.repository,
    required this.sessions,
    required this.nodes,
    required this.taskTitles,
  });

  final FocusRepository repository;
  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final Map<String, String> taskTitles;

  @override
  Widget build(BuildContext context) {
    final nodesBySession = {for (final node in nodes) node.sessionId: node};
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('专注历史', style: Theme.of(context).textTheme.titleMedium),
            for (final session in sessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(taskTitles[session.taskId] ?? '原任务'),
                subtitle: Text(
                  session.isFailed
                      ? '失败 · ${_formatDuration(session.effectiveSeconds)}\n原因：${session.failureReason ?? '未填写'}'
                      : session.isEarlyCompleted
                      ? '获准提前完成 · ${_formatDuration(session.effectiveSeconds)}\n依据：${session.completionRuleText ?? '未记录'}'
                      : '正常完成 · ${_formatDuration(session.effectiveSeconds)}',
                ),
                trailing: Wrap(
                  children: [
                    if (session.isFailed)
                      IconButton(
                        tooltip: '编辑失败原因',
                        icon: const Icon(Icons.edit_note_outlined),
                        onPressed: () async {
                          final reason = await _showTextEditor(
                            context,
                            title: '编辑失败原因',
                            label: '失败原因',
                            initial: session.failureReason ?? '',
                            required: true,
                          );
                          if (reason != null) {
                            await repository.updateFailureReason(
                              sessionId: session.id,
                              failureReason: reason,
                            );
                          }
                        },
                      ),
                    if (nodesBySession[session.id] case final node?)
                      IconButton(
                        tooltip: '编辑节点备注',
                        icon: const Icon(Icons.sticky_note_2_outlined),
                        onPressed: () async {
                          final note = await _showTextEditor(
                            context,
                            title: '编辑节点备注',
                            label: '备注（可选）',
                            initial: node.note ?? '',
                          );
                          if (note != null) {
                            await repository.updateNodeNote(
                              nodeId: node.id,
                              note: note,
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showTextEditor(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextEditorDialog(
      title: title,
      label: label,
      initial: initial,
      required: required,
    ),
  );
}

class _TextEditorDialog extends StatefulWidget {
  const _TextEditorDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.required = false,
  });

  final String title;
  final String label;
  final String initial;
  final bool required;

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late final TextEditingController _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = '请填写${widget.label}。');
      return;
    }
    if (value.length > 500) {
      setState(() => _error = '内容不能超过 500 字。');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLines: 4,
      maxLength: 500,
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}

Future<String?> _showPrecedentRulePicker(
  BuildContext context, {
  required FocusRepository repository,
  required List<PrecedentRule> rules,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PrecedentRulePickerDialog(
      repository: repository,
      rules: rules,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PrecedentRulePickerDialog extends StatefulWidget {
  const _PrecedentRulePickerDialog({
    required this.repository,
    required this.rules,
    required this.confirmLabel,
  });

  final FocusRepository repository;
  final List<PrecedentRule> rules;
  final String confirmLabel;

  @override
  State<_PrecedentRulePickerDialog> createState() =>
      _PrecedentRulePickerDialogState();
}

class _PrecedentRulePickerDialogState
    extends State<_PrecedentRulePickerDialog> {
  late List<PrecedentRule> _rules;
  String? _selectedRuleId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rules = [...widget.rules];
  }

  Future<void> _createAndUse() async {
    final text = await _showTextEditor(
      context,
      title: '新建并使用下必为例',
      label: '下必为例',
      initial: '',
      required: true,
    );
    if (text == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final rule = await widget.repository.createPrecedentRule(text: text);
      if (!mounted) return;
      setState(() {
        _rules = [rule, ..._rules];
        _selectedRuleId = rule.id;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择下必为例'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('选择已有规则，或新建一条并立即使用。'),
          const SizedBox(height: 12),
          if (_rules.isEmpty)
            const Text('还没有共享规则，请先新建。')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: _selectedRuleId,
                  onChanged: _busy
                      ? (_) {}
                      : (value) => setState(() => _selectedRuleId = value),
                  child: Column(
                    children: [
                      for (final rule in _rules)
                        RadioListTile<String>(
                          value: rule.id,
                          title: Text(rule.text),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _createAndUse,
            icon: const Icon(Icons.add),
            label: const Text('新建并使用'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy || _selectedRuleId == null
            ? null
            : () {
                final selected = _rules.firstWhere(
                  (rule) => rule.id == _selectedRuleId,
                );
                Navigator.pop(context, selected.text);
              },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

class FocusSetupDialog extends ConsumerStatefulWidget {
  const FocusSetupDialog({
    super.key,
    required this.task,
    required this.initialMode,
  });

  final Task task;
  final FocusChainMode initialMode;

  @override
  ConsumerState<FocusSetupDialog> createState() => _FocusSetupDialogState();
}

class _FocusSetupDialogState extends ConsumerState<FocusSetupDialog> {
  late FocusChainMode _mode;
  late final TextEditingController _duration;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _duration = TextEditingController(text: '25');
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      setState(() => _error = '请输入大于 0 的分钟数。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .startSession(
            taskId: widget.task.id,
            mode: _mode,
            duration: Duration(minutes: minutes),
          );
      if (mounted) Navigator.of(context).pop(session);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startAppointment() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      setState(() => _error = '请输入大于 0 的分钟数。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final appointment = await ref
          .read(focusRepositoryProvider)
          .startAppointment(
            taskId: widget.task.id,
            mode: _mode,
            duration: Duration(minutes: minutes),
          );
      if (mounted) Navigator.of(context).pop(appointment);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('开始专注'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.task.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        DropdownButtonFormField<FocusChainMode>(
          initialValue: _mode,
          decoration: const InputDecoration(labelText: '本次专注模式'),
          items: [
            for (final mode in FocusChainMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: _busy ? null : (value) => setState(() => _mode = value!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '时长（分钟）'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        const Text('启动信号由你执行，App 不检测现实动作。可立即开始专注，或先进行固定 15 分钟准备；准备结束会自动进入专注。'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _startAppointment,
        child: const Text('开始准备（15分钟）'),
      ),
      FilledButton(
        onPressed: _busy ? null : _start,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('开始倒计时'),
      ),
    ],
  );
}

class AppointmentPreparationPage extends ConsumerStatefulWidget {
  const AppointmentPreparationPage({
    super.key,
    required this.appointment,
    required this.taskTitle,
  });

  final AppointmentPreparation appointment;
  final String taskTitle;

  @override
  ConsumerState<AppointmentPreparationPage> createState() =>
      _AppointmentPreparationPageState();
}

class _AppointmentPreparationPageState
    extends ConsumerState<AppointmentPreparationPage> {
  Timer? _timer;
  AppointmentPreparation? _current;
  List<Task>? _tasks;
  List<FocusAppointmentSourceOption> _configurationSources = const [];
  late FocusChainMode _mode;
  late String _taskId;
  late final TextEditingController _duration;
  bool _busy = false;
  bool _loadingConfigurationSources = false;
  bool _configurationSourcesRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.appointment;
    _mode = widget.appointment.mode;
    _taskId = widget.appointment.taskId;
    _duration = TextEditingController(
      text: _minutesFor(widget.appointment.durationSeconds).toString(),
    );
    unawaited(_syncAppointmentNotification(widget.appointment));
    unawaited(_loadTasks());
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    try {
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      final tasks = [
        for (final goal in goals)
          for (final task in goal.tasks)
            if ((!task.isComplete && !task.isDeleted) || task.id == _taskId)
              task,
      ];
      if (mounted) setState(() => _tasks = tasks);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    }
  }

  Future<void> _refresh() async {
    final current = await ref
        .read(focusRepositoryProvider)
        .getAppointment(widget.appointment.id);
    if (!mounted || current == null) return;
    if (current.isSucceeded && !current.isPendingReview) {
      final session = await ref
          .read(focusRepositoryProvider)
          .getSession(current.sessionId ?? current.id);
      if (!mounted || session == null) return;
      await ref
          .read(focusNotificationServiceProvider)
          .appointmentEnteredFocus(
            appointmentId: current.id,
            taskTitle: _taskTitle(current.taskId),
          );
      if (!mounted) return;
      unawaited(_syncFocusNotification(session));
      _timer?.cancel();
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => FocusSessionPage(
            session: session,
            taskTitle: _taskTitle(current.taskId),
          ),
        ),
      );
      return;
    }
    if (current.isFailed) {
      _timer?.cancel();
      unawaited(_syncAppointmentNotification(null));
    }
    if (mounted) setState(() => _current = current);
    if (current.isPendingReview && !_configurationSourcesRequested) {
      unawaited(_loadConfigurationSources());
    }
  }

  Future<void> _syncAppointmentNotification(
    AppointmentPreparation? appointment,
  ) async {
    try {
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            appointment: appointment?.isActive == true ? appointment : null,
            taskTitle: appointment == null
                ? widget.taskTitle
                : _taskTitle(appointment.taskId),
          );
    } catch (_) {
      // A notification failure does not affect the appointment flow.
    }
  }

  Future<void> _syncFocusNotification(FocusSession session) async {
    try {
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            session: session.isUnfinished ? session : null,
            taskTitle: _taskTitle(session.taskId),
          );
    } catch (_) {
      // A notification failure does not affect the focus session.
    }
  }

  Future<void> _loadConfigurationSources({bool force = false}) async {
    if (_loadingConfigurationSources ||
        (!force && _configurationSourcesRequested)) {
      return;
    }
    _configurationSourcesRequested = true;
    _loadingConfigurationSources = true;
    if (mounted) setState(() {});
    try {
      final sources = await ref
          .read(focusRepositoryProvider)
          .getAppointmentConfigurationSources(widget.appointment.id);
      if (mounted) setState(() => _configurationSources = sources);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      _loadingConfigurationSources = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _selectConfigurationSource(
    FocusAppointmentSourceOption source,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(focusRepositoryProvider)
          .selectAppointmentConfigurationSource(
            appointmentId: widget.appointment.id,
            sourceId: source.sourceId,
          );
      _taskId = updated.taskId;
      _mode = updated.mode;
      _duration.text = _minutesFor(updated.durationSeconds).toString();
      if (mounted) setState(() => _current = updated);
      unawaited(_syncAppointmentNotification(updated));
      _configurationSourcesRequested = false;
      await _loadConfigurationSources(force: true);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveConfig() async {
    final current = _current;
    final minutes = int.tryParse(_duration.text.trim());
    if (current == null || !current.isActive) return;
    if (minutes == null || minutes <= 0) {
      setState(() => _error = '请输入大于 0 的分钟数。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(focusRepositoryProvider)
          .updateAppointment(
            appointmentId: current.id,
            taskId: _taskId,
            mode: _mode,
            duration: Duration(minutes: minutes),
          );
      if (mounted) setState(() => _current = updated);
      unawaited(_syncAppointmentNotification(updated));
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterEarly() async {
    final current = _current;
    if (current == null || !current.isActive || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .enterAppointmentEarly(current.id);
      if (!mounted) return;
      await ref
          .read(focusNotificationServiceProvider)
          .appointmentEnteredFocus(
            appointmentId: current.id,
            taskTitle: _taskTitle(session.taskId),
          );
      await _syncFocusNotification(session);
      if (!mounted) return;
      _timer?.cancel();
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => FocusSessionPage(
            session: session,
            taskTitle: _taskTitle(session.taskId),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelAppointment() async {
    final current = _current;
    if (current == null || !current.isActive || _busy) return;
    final reason = await _showTextEditor(
      context,
      title: '取消预约准备',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(focusRepositoryProvider)
          .cancelAppointment(appointmentId: current.id, failureReason: reason);
      await _syncAppointmentNotification(null);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyFocusError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _taskTitle(String taskId) {
    for (final task in _tasks ?? const <Task>[]) {
      if (task.id == taskId) return _taskDisplayTitle(task);
    }
    return taskId == widget.appointment.taskId ? widget.taskTitle : '原预约任务';
  }

  String _friendlyFocusError(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  @override
  Widget build(BuildContext context) {
    final appointment = _current ?? widget.appointment;
    final now = DateTime.now().toUtc();
    final remainingSeconds = appointment.isActive
        ? appointment.endsAt.difference(now).inSeconds.clamp(0, 15 * 60)
        : 0;
    final progress = 1 - (remainingSeconds / (15 * 60));
    final tasks = _tasks;
    final canEdit = !_busy && !appointment.isPendingReview;
    final canProceed = !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('预约准备')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _taskTitle(appointment.taskId),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                appointment.isPendingReview
                    ? '两端对这份预约的配置存在分歧，自动交接已暂停，当前来源待核对。你仍可继续此预约或取消。'
                    : appointment.isActive
                    ? '准备结束后自动进入专注，不需要再次点击或执行启动信号。'
                    : appointment.isFailed
                    ? '预约已取消，预约链当前记录已清零。'
                    : '预约已成功进入专注。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Text(
                appointment.isActive ? _formatClock(remainingSeconds) : '00:00',
                style: Theme.of(context).textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              const SizedBox(height: 16),
              if (appointment.isPendingReview)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '配置来源对比',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_loadingConfigurationSources)
                          const Center(child: CircularProgressIndicator())
                        else if (_configurationSources.isEmpty)
                          const Text('当前待核对记录没有不同的预约配置来源。')
                        else
                          for (final source in _configurationSources) ...[
                            const Divider(),
                            Text(
                              '设备 ${source.deviceId.substring(0, source.deviceId.length < 8 ? source.deviceId.length : 8)} · ${source.occurredAt.toLocal()}',
                            ),
                            Text('任务：${_taskTitle(source.taskId)}'),
                            Text(
                              '模式：${source.mode.label} · 时长：${_minutesFor(source.durationSeconds)} 分钟',
                            ),
                            OutlinedButton(
                              onPressed:
                                  _busy ||
                                      appointment.configurationBasisSourceId ==
                                          source.sourceId
                                  ? null
                                  : () => _selectConfigurationSource(source),
                              child: Text(
                                appointment.configurationBasisSourceId ==
                                        source.sourceId
                                    ? '当前配置依据'
                                    : '采用此来源作为配置依据',
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
              if (appointment.isPendingReview) const SizedBox(height: 16),
              if (appointment.isActive)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '准备配置',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (tasks == null)
                          const Center(child: CircularProgressIndicator())
                        else
                          DropdownButtonFormField<String>(
                            initialValue:
                                tasks.any((task) => task.id == _taskId)
                                ? _taskId
                                : null,
                            decoration: const InputDecoration(labelText: '任务'),
                            items: [
                              for (final task in tasks)
                                DropdownMenuItem(
                                  value: task.id,
                                  child: Text(task.title),
                                ),
                            ],
                            onChanged: !canEdit
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _taskId = value);
                                    }
                                  },
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<FocusChainMode>(
                          initialValue: _mode,
                          decoration: const InputDecoration(
                            labelText: '本次专注模式',
                          ),
                          items: [
                            for (final mode in FocusChainMode.values)
                              DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ),
                          ],
                          onChanged: !canEdit
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _mode = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _duration,
                          enabled: canEdit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '专注时长（分钟）',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: canEdit ? _saveConfig : null,
                          child: const Text('保存配置（不重置准备时间）'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              if (appointment.isActive) ...[
                FilledButton(
                  onPressed: canProceed ? _enterEarly : null,
                  child: const Text('提前进入专注'),
                ),
                TextButton(
                  onPressed: canProceed ? _cancelAppointment : null,
                  child: const Text('取消预约并填写失败原因'),
                ),
                const Text(
                  '准备阶段不能暂停，也不限制你在现实中的行为。',
                  textAlign: TextAlign.center,
                ),
              ] else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回专注链'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    super.key,
    required this.session,
    required this.taskTitle,
  });

  final FocusSession session;
  final String taskTitle;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage> {
  Timer? _timer;
  FocusSession? _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.session;
    unawaited(_syncSessionNotification(widget.session));
    _refresh();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    final session = await ref
        .read(focusRepositoryProvider)
        .getSession(widget.session.id);
    if (!mounted) return;
    if (session != null) {
      final previous = _current;
      if (previous?.status != session.status ||
          previous?.endsAt != session.endsAt ||
          previous?.pausedAt != session.pausedAt) {
        setState(() => _current = session);
        if (previous?.isUnfinished == true && !session.isUnfinished) {
          unawaited(
            ref
                .read(focusNotificationServiceProvider)
                .sessionEnded(
                  sessionId: session.id,
                  appointmentId: session.appointmentId,
                  taskTitle: widget.taskTitle,
                  status: session.status,
                ),
          );
        }
        unawaited(_syncSessionNotification(session));
      }
    }
  }

  Future<void> _syncSessionNotification(FocusSession? session) async {
    try {
      await ref
          .read(focusNotificationServiceProvider)
          .sync(
            session: session?.isUnfinished == true ? session : null,
            taskTitle: widget.taskTitle,
          );
    } catch (_) {
      // A notification failure does not affect the focus session.
    }
  }

  Future<void> _togglePause() async {
    final session = _current;
    if (session == null || _busy) return;
    String? ruleText;
    if (!session.isPaused) {
      final repository = ref.read(focusRepositoryProvider);
      final rules = await repository.getPrecedentRules();
      if (!mounted) return;
      ruleText = await _showPrecedentRulePicker(
        context,
        repository: repository,
        rules: rules,
        confirmLabel: '确认暂停',
      );
      if (ruleText == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(focusRepositoryProvider);
      _current = session.isPaused
          ? await repository.resumeSession(session.id)
          : await repository.pauseSession(session.id, ruleText: ruleText!);
      await _syncSessionNotification(_current);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeEarly() async {
    final session = _current;
    if (session == null || !session.isUnfinished || _busy) return;
    final repository = ref.read(focusRepositoryProvider);
    final rules = await repository.getPrecedentRules();
    if (!mounted) return;
    final ruleText = await _showPrecedentRulePicker(
      context,
      repository: repository,
      rules: rules,
      confirmLabel: '选择依据',
    );
    if (ruleText == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认提前完成？'),
        content: Text('本次专注将按实际有效时间完成，并生成一个专注节点。\n依据：$ruleText'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('提前完成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      _current = await ref
          .read(focusRepositoryProvider)
          .completeEarlySession(sessionId: session.id, ruleText: ruleText);
      await ref
          .read(focusNotificationServiceProvider)
          .sessionEnded(
            sessionId: session.id,
            appointmentId: session.appointmentId,
            taskTitle: widget.taskTitle,
            status: _current!.status,
          );
      await _syncSessionNotification(_current);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon() async {
    final session = _current;
    if (session == null || !session.isUnfinished || _busy) return;
    final reason = await _showTextEditor(
      context,
      title: '放弃本次专注',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      _current = await ref
          .read(focusRepositoryProvider)
          .abandonSession(sessionId: session.id, failureReason: reason);
      await ref
          .read(focusNotificationServiceProvider)
          .sessionEnded(
            sessionId: session.id,
            appointmentId: session.appointmentId,
            taskTitle: widget.taskTitle,
            status: _current!.status,
          );
      await _syncSessionNotification(_current);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _current ?? widget.session;
    final now = DateTime.now().toUtc();
    final reference = session.isPaused ? (session.pausedAt ?? now) : now;
    final remaining = session.endsAt.difference(reference);
    final remainingSeconds = remaining.inSeconds.clamp(
      0,
      session.durationSeconds,
    );
    final progress = session.durationSeconds == 0
        ? 1.0
        : 1 - (remainingSeconds / session.durationSeconds);
    final settled = !session.isUnfinished;
    final needsReview =
        session.reviewDisposition == FocusRecordDisposition.pendingReview;
    return Scaffold(
      appBar: AppBar(title: const Text('专注进行中')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.taskTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(session.mode.label, textAlign: TextAlign.center),
                const SizedBox(height: 36),
                Text(
                  settled ? '00:00' : _formatClock(remainingSeconds),
                  style: Theme.of(context).textTheme.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: settled ? 1 : progress),
                const SizedBox(height: 20),
                Text(
                  needsReview
                      ? '两端对这次专注的记录存在分歧，当前结果和计时已暂停，待核对来源。'
                      : session.isFailed
                      ? '本次专注已失败，已保留有效投入时间。任务仍需你单独确认完成。\n失败原因：${session.failureReason ?? '未填写'}'
                      : session.isEarlyCompleted
                      ? '本次专注已获准提前完成，已生成一个专注节点并记录有效时间。\n依据：${session.completionRuleText ?? '未记录'}'
                      : session.status == FocusSessionStatus.completed
                      ? '本次专注已完成，已生成一个专注节点并记录有效时间。任务仍需你单独确认完成。'
                      : session.isPaused
                      ? '本次专注已暂停，暂停时间不计入有效投入。'
                      : '倒计时归零后自动结算。返回其他页面不会使本次专注失败。',
                  textAlign: TextAlign.center,
                ),
                if (session.isUnfinished) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _togglePause,
                        icon: Icon(
                          session.isPaused ? Icons.play_arrow : Icons.pause,
                        ),
                        label: Text(session.isPaused ? '继续' : '暂停'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _completeEarly,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('依据规则提前完成'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _abandon,
                        child: const Text('放弃本次专注'),
                      ),
                    ],
                  ),
                ],
                if (settled) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回专注链'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatClock(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
}

int _minutesFor(int seconds) => (seconds / 60).ceil();

class MyPage extends ConsumerStatefulWidget {
  const MyPage({super.key});

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage> {
  late Future<bool> _isAdministrator;

  @override
  void initState() {
    super.initState();
    _isAdministrator = ref.read(authRepositoryProvider).isAdministrator();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    final calendarRepository = ref.watch(calendarRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(repository.currentUserIdentifier ?? '当前用户'),
            subtitle: const Text('个人数据仅属于你'),
          ),
        ),
        FutureBuilder<bool>(
          future: _isAdministrator,
          builder: (context, snapshot) => snapshot.data == true
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      AdminUserLifecycleCard(repository: repository),
                      const SizedBox(height: 12),
                      const AdminEligibilityCard(),
                      const SizedBox(height: 12),
                      AdminPasswordResetCard(repository: repository),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        const _FocusReconciliationPageLink(),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('日历块'),
            subtitle: Text(
              Platform.isAndroid ? '选择只读导入的系统日历来源' : '查看从 Android 同步的规划参考',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CalendarSourcesPage(
                  repository: calendarRepository,
                  isAndroid: Platform.isAndroid,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const PrecedentRulesCard(),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            subtitle: const Text('专注通知与本设备后台状态'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => FocusNotificationSettingsPage(
                  service: ref.read(focusNotificationServiceProvider),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}

class _FocusReconciliationPageLink extends ConsumerWidget {
  const _FocusReconciliationPageLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusRepository = ref.watch(focusRepositoryProvider);
    final taskRepository = ref.watch(taskRepositoryProvider);
    return StreamBuilder<List<FocusReconciliationCase>>(
      stream: focusRepository.watchFocusReconciliations(),
      builder: (context, snapshot) {
        final pendingCount = (snapshot.data ?? const [])
            .where((item) => item.isPendingReview)
            .length;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('专注记录核对'),
            subtitle: Text(
              pendingCount == 0
                  ? '查看已完成的核对结果和来源依据'
                  : '$pendingCount 组待核对 · 争议部分暂不计入统计',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FocusReconciliationPage(
                  focusRepository: focusRepository,
                  taskRepository: taskRepository,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PrecedentRulesCard extends ConsumerStatefulWidget {
  const PrecedentRulesCard({super.key});

  @override
  ConsumerState<PrecedentRulesCard> createState() => _PrecedentRulesCardState();
}

class _PrecedentRulesCardState extends ConsumerState<PrecedentRulesCard> {
  List<PrecedentRule> _rules = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await ref.read(focusRepositoryProvider).getPrecedentRules();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _create() async {
    final text = await _showTextEditor(
      context,
      title: '新建下必为例',
      label: '下必为例',
      initial: '',
      required: true,
    );
    if (text == null || !mounted) return;
    await _run(() async {
      await ref.read(focusRepositoryProvider).createPrecedentRule(text: text);
    });
  }

  Future<void> _edit(PrecedentRule rule) async {
    final text = await _showTextEditor(
      context,
      title: '编辑下必为例',
      label: '下必为例',
      initial: rule.text,
      required: true,
    );
    if (text == null || !mounted) return;
    await _run(() async {
      await ref
          .read(focusRepositoryProvider)
          .updatePrecedentRule(ruleId: rule.id, text: text);
    });
  }

  Future<void> _delete(PrecedentRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除下必为例？'),
        content: const Text('删除后不会再出现在新的中断操作中，已经确认的记录保留原文字。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(focusRepositoryProvider).deletePrecedentRule(rule.id),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('下必为例', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('专注中断时可直接选择或新建；规则含义由你自己判断。'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有共享规则。'),
            )
          else
            for (final rule in _rules)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(rule.text),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: '编辑下必为例',
                      onPressed: _busy ? null : () => _edit(rule),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '删除下必为例',
                      onPressed: _busy ? null : () => _delete(rule),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('新建规则'),
          ),
        ],
      ),
    ),
  );
}

class AdminEligibilityCard extends ConsumerStatefulWidget {
  const AdminEligibilityCard({super.key});

  @override
  ConsumerState<AdminEligibilityCard> createState() =>
      _AdminEligibilityCardState();
}

class _AdminEligibilityCardState extends ConsumerState<AdminEligibilityCard> {
  final _email = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _grant() async {
    await _run(
      () => ref
          .read(authRepositoryProvider)
          .grantEligibility(email: _email.text.trim()),
      '资格已发放',
    );
  }

  Future<void> _revoke() async {
    await _run(() async {
      final changed = await ref
          .read(authRepositoryProvider)
          .revokeEligibility(email: _email.text.trim());
      if (!changed) throw StateError('资格不存在、已使用或已被撤销。');
    }, '资格已撤销');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _message = '请输入有效的邮箱地址。');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _message = success);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('管理员：注册资格', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('资格不发送消息，也不验证标识所有权。'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: '邮箱'),
                ),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _grant,
                  child: const Text('发放资格'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _revoke,
                  child: const Text('撤销未用资格'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
