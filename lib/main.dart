import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as flutter show FocusNode;
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
import 'src/schedules/schedule_models.dart';
import 'src/schedules/schedule_repository.dart';
import 'src/focus/focus_models.dart';
import 'src/focus/effective_duration_text.dart';
import 'src/focus/focus_month_page.dart';
import 'src/focus/chain_signals_repository.dart';
import 'src/focus/chain_signals_card.dart';
import 'src/focus/focus_statistics.dart';
import 'src/focus/focus_repository.dart';
import 'src/focus/focus_clock_review_page.dart';
import 'src/focus/focus_reconciliation_page.dart';
import 'src/focus/focus_time_zones.dart';
import 'src/national_focus/national_focus_repository.dart';
import 'src/national_focus/national_focus_checkpoint_scheduler.dart';
import 'src/national_focus/national_focus_models.dart';
import 'src/national_focus/national_focus_ai_access.dart';
import 'src/national_focus/national_focus_ai_analysis_page.dart';
import 'src/national_focus/national_focus_tree_page.dart';
import 'src/notifications/focus_notification_service.dart';
import 'src/notifications/schedule_reminder_plan.dart';
import 'src/notifications/schedule_reminder_sync.dart';
import 'src/profile/account_time_zone.dart';
import 'src/profile/avatar_picker.dart';
import 'src/profile/profile_card.dart';
import 'src/profile/profile_models.dart';
import 'src/profile/profile_overview.dart';
import 'src/profile/profile_remote.dart';
import 'src/profile/profile_repository.dart';
import 'src/notifications/focus_notification_settings_page.dart';
import 'src/plan/plan_calendar_view.dart';
import 'src/plan/plan_target.dart';
import 'src/tasks/task_database.dart' show PactaDatabase;
import 'src/tasks/task_models.dart';
import 'src/tasks/task_repository.dart';
import 'src/sync/cloud_auto_upload.dart';
import 'src/sync/cloud_auto_upload_preference.dart';
import 'src/sync/cloud_auto_upload_queue.dart';
import 'src/sync/cloud_snapshot_repository.dart';
import 'src/sync/source_device_info.dart';
import 'src/sync/cloud_sync_card.dart';
import 'src/sync/cloud_version_check.dart';
import 'src/theme/pacta_status_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sourceDevice = await SourceDeviceInfo.load();
  final focusNotificationService = FocusNotificationService();
  await focusNotificationService.initialize();
  final url = const String.fromEnvironment('SUPABASE_URL');
  final key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  AuthRepository repository = const UnavailableAuthRepository();
  final database = PactaDatabase.open();
  CloudSnapshotRemote? cloudRemote;
  ProfileRemote profileRemote = const UnavailableProfileRemote();
  NationalFocusAiGrantRepository Function(String userId)?
  nationalFocusAiGrantRepositoryFactory;
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    repository = SupabaseAuthRepository(Supabase.instance.client);
    cloudRemote = SupabaseCloudSnapshotRemote(Supabase.instance.client);
    profileRemote = SupabaseProfileRemote(Supabase.instance.client);
    nationalFocusAiGrantRepositoryFactory = (userId) =>
        SupabaseNationalFocusAiGrantRepository(
          client: Supabase.instance.client,
          userId: userId,
        );
  }
  final purgeCleanupRepository = UserPurgeCleanupRepository(
    authRepository: repository,
    database: database,
  );
  runApp(
    PactaApp(
      authRepository: repository,
      nationalFocusMcpUrl: _nationalFocusMcpUrl(url),
      nationalFocusAiGrantRepositoryFactory:
          nationalFocusAiGrantRepositoryFactory,
      userPurgeCleanupRepository: purgeCleanupRepository,
      focusNotificationService: focusNotificationService,
      taskRepositoryFactory: (userId) => LocalTaskRepository(
        database: database,
        userId: userId,
        remote: const UnavailableTaskRemoteDataSource(),
        cloudSyncEnabled: false,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      focusRepositoryFactory: (userId) => LocalFocusRepository(
        database: database,
        userId: userId,
        remote: const UnavailableFocusRemoteDataSource(),
        cloudSyncEnabled: false,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      nationalFocusRepositoryFactory: (userId) => LocalNationalFocusRepository(
        database: database,
        userId: userId,
        remote: const UnavailableNationalFocusRemoteDataSource(),
        cloudSyncEnabled: false,
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
        remote: const UnavailableCalendarRemoteDataSource(),
        cloudSyncEnabled: false,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      scheduleRepositoryFactory: (userId) => LocalScheduleRepository(
        database: database,
        userId: userId,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      chainSignalsRepositoryFactory: (userId) => ChainSignalsRepository(
        database: database,
        userId: userId,
        lifecycleAccess: LocalUserLifecycleAccess(
          database: database,
          userId: userId,
        ),
      ),
      profileRepositoryFactory: (userId) => LocalProfileRepository(
        database: database,
        userId: userId,
        remote: profileRemote,
      ),
      cloudSnapshotRepositoryFactory: cloudRemote == null
          ? null
          : (userId) => CloudSnapshotRepository(
              database: database,
              remote: cloudRemote!,
              userId: userId,
              deviceName: sourceDevice.sourceLabel,
              deviceManufacturer: sourceDevice.manufacturer,
              deviceModel: sourceDevice.model,
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

String? _nationalFocusMcpUrl(String supabaseUrl) {
  final baseUrl = supabaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (baseUrl.isEmpty) return null;
  return '$baseUrl/functions/v1/national-focus-mcp/mcp';
}

class PactaApp extends StatelessWidget {
  const PactaApp({
    super.key,
    required this.authRepository,
    this.nationalFocusMcpUrl,
    this.nationalFocusAiGrantRepositoryFactory,
    this.userPurgeCleanupRepository,
    this.focusNotificationService,
    this.taskRepositoryFactory,
    this.focusRepositoryFactory,
    this.nationalFocusRepositoryFactory,
    this.calendarRepositoryFactory,
    this.scheduleRepositoryFactory,
    this.scheduleReminderOpenHandler,
    this.userLifecycleRepositoryFactory,
    this.cloudSnapshotRepositoryFactory,
    this.cloudCheckClock = DateTime.now,
    this.displayClock = DateTime.now,
    this.chainSignalsRepositoryFactory,
    this.profileRepositoryFactory,
    this.deviceTimeZoneIdReader = readDeviceTimeZoneId,
  });

  final ProfileRepository Function(String userId)? profileRepositoryFactory;

  /// Reads this device's IANA zone. It is only a one-time migration input for
  /// the account display time zone, never a display value.
  final Future<String?> Function() deviceTimeZoneIdReader;

  final CloudSnapshotRepository Function(String userId)?
  cloudSnapshotRepositoryFactory;

  final ChainSignalsRepository Function(String userId)?
  chainSignalsRepositoryFactory;

  final DateTime Function() cloudCheckClock;

  /// Wall clock used by countdown surfaces; tests pass the same mutable clock
  /// as their repository so display and persistence agree.
  final DateTime Function() displayClock;

  final AuthRepository authRepository;
  final String? nationalFocusMcpUrl;
  final NationalFocusAiGrantRepository Function(String userId)?
  nationalFocusAiGrantRepositoryFactory;
  final UserPurgeCleanupRepository? userPurgeCleanupRepository;
  final FocusNotificationService? focusNotificationService;
  final TaskRepository Function(String userId)? taskRepositoryFactory;
  final FocusRepository Function(String userId)? focusRepositoryFactory;
  final NationalFocusRepository Function(String userId)?
  nationalFocusRepositoryFactory;
  final CalendarRepository Function(String userId)? calendarRepositoryFactory;
  final ScheduleRepository Function(String userId)? scheduleRepositoryFactory;

  /// Opens an ordinary schedule reminder once the Plan destination is wired.
  final Future<void> Function(ScheduleReminderRequest)?
  scheduleReminderOpenHandler;
  final UserLifecycleStatusRepository Function(String userId)?
  userLifecycleRepositoryFactory;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        cloudCheckClockProvider.overrideWithValue(cloudCheckClock),
        displayClockProvider.overrideWithValue(displayClock),
        chainSignalsRepositoryFactoryProvider.overrideWithValue(
          chainSignalsRepositoryFactory,
        ),
        profileRepositoryFactoryProvider.overrideWithValue(
          profileRepositoryFactory,
        ),
        deviceTimeZoneIdReaderProvider.overrideWithValue(
          deviceTimeZoneIdReader,
        ),
        cloudSnapshotRepositoryFactoryProvider.overrideWithValue(
          cloudSnapshotRepositoryFactory,
        ),
        authRepositoryProvider.overrideWithValue(authRepository),
        nationalFocusMcpUrlProvider.overrideWithValue(nationalFocusMcpUrl),
        nationalFocusAiGrantRepositoryFactoryProvider.overrideWithValue(
          nationalFocusAiGrantRepositoryFactory,
        ),
        userPurgeCleanupRepositoryProvider.overrideWithValue(
          userPurgeCleanupRepository,
        ),
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
        scheduleRepositoryFactoryProvider.overrideWithValue(
          scheduleRepositoryFactory ??
              (_) => const UnavailableScheduleRepository(),
        ),
        scheduleReminderOpenHandlerProvider.overrideWithValue(
          scheduleReminderOpenHandler,
        ),
        userLifecycleRepositoryFactoryProvider.overrideWithValue(
          userLifecycleRepositoryFactory ??
              (_) => const UnavailableUserLifecycleStatusRepository(),
        ),
      ],
      child: MaterialApp(
        title: 'Pacta',
        debugShowCheckedModeBanner: false,
        theme: pactaTheme(Brightness.light),
        darkTheme: pactaTheme(Brightness.dark),
        home: _UserPurgeCleanupLifecycleObserver(
          cleanupRepository: userPurgeCleanupRepository,
          child: const AuthGate(),
        ),
      ),
    );
  }
}

/// The app theme, shared with offline layout fixtures so evidence never
/// invents a second visual language.
ThemeData pactaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff0b57d0),
        brightness: brightness,
      ).copyWith(
        primary: Color(dark ? 0xffa8c7fa : 0xff0b57d0),
        onPrimary: Color(dark ? 0xff062e6f : 0xffffffff),
        primaryContainer: Color(dark ? 0xff0842a0 : 0xffd3e3fd),
        onPrimaryContainer: Color(dark ? 0xffd3e3fd : 0xff041e49),
        secondary: Color(dark ? 0xffb4c8e8 : 0xff355e92),
        onSecondary: Color(dark ? 0xff1a3353 : 0xffffffff),
        secondaryContainer: Color(dark ? 0xff2d4667 : 0xffe1ecff),
        onSecondaryContainer: Color(dark ? 0xffd6e5ff : 0xff1a3353),
        tertiary: Color(dark ? 0xfff5c451 : 0xff7f5700),
        onTertiary: Color(dark ? 0xff402d00 : 0xffffffff),
        tertiaryContainer: Color(dark ? 0xff5b4300 : 0xfffff1c2),
        onTertiaryContainer: Color(dark ? 0xffffe8aa : 0xff3f2a00),
        surface: Color(dark ? 0xff111318 : 0xfff8fafd),
        onSurface: Color(dark ? 0xffe3e3e3 : 0xff1f1f1f),
        onSurfaceVariant: Color(dark ? 0xffc4c7c5 : 0xff444746),
        surfaceContainerLowest: Color(dark ? 0xff0d0f14 : 0xffffffff),
        surfaceContainerLow: Color(dark ? 0xff1b1d23 : 0xfff0f4f9),
        surfaceContainer: Color(dark ? 0xff23262d : 0xffe9eef6),
        surfaceContainerHigh: Color(dark ? 0xff2b2e36 : 0xffe3eaf5),
        surfaceContainerHighest: Color(dark ? 0xff34373f : 0xffdee5f0),
        outline: Color(dark ? 0xff8e918f : 0xff747775),
        outlineVariant: Color(dark ? 0xff444746 : 0xffc4c7c5),
      );
  return ThemeData(
    fontFamily: 'MiSans',
    colorScheme: colors,
    useMaterial3: true,
    extensions: [dark ? PactaStatusColors.dark : PactaStatusColors.light],
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainerLow,
      indicatorColor: colors.primaryContainer,
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surfaceContainerLow,
      indicatorColor: colors.primaryContainer,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

final _authUserIdChangesProvider = StreamProvider<String?>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return auth.authState.map((_) => auth.currentUserId).distinct();
});
final authUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return ref
      .watch(_authUserIdChangesProvider)
      .when(
        data: (userId) => userId,
        loading: () => auth.currentUserId,
        error: (_, _) => auth.currentUserId,
      );
});

final cloudSnapshotRepositoryFactoryProvider =
    Provider<CloudSnapshotRepository Function(String userId)?>((ref) => null);

final cloudSnapshotRepositoryProvider =
    Provider.autoDispose<CloudSnapshotRepository?>((ref) {
      final userId = ref.watch(authUserIdProvider);
      final factory = ref.watch(cloudSnapshotRepositoryFactoryProvider);
      return userId == null || factory == null ? null : factory(userId);
    });

final cloudCheckClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Wall clock used by countdown surfaces. Production defaults to the system
/// clock; tests override it with the same mutable clock as their repository.
final displayClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final cloudVersionCheckProvider = Provider.autoDispose<CloudVersionCheck?>((
  ref,
) {
  final repository = ref.watch(cloudSnapshotRepositoryProvider);
  if (repository == null) return null;
  final lifecycle = ref.watch(userLifecycleStatusRepositoryProvider);
  final auth = ref.watch(authRepositoryProvider);
  final userId = repository.userId;
  final check = CloudVersionCheck(
    repository: repository,
    now: ref.watch(cloudCheckClockProvider),
    canAccess: () async {
      if (auth.currentUserId != userId) return false;
      final status = await lifecycle.refresh();
      return auth.currentUserId == userId && !status.isSuspended;
    },
    isAccessible: () async {
      if (auth.currentUserId != userId) return false;
      final status = await lifecycle.readCachedStatus();
      return auth.currentUserId == userId &&
          status != null &&
          !status.isSuspended;
    },
  );
  ref.onDispose(check.dispose);
  return check;
});

final cloudAutoUploadPreferenceProvider = Provider<CloudAutoUploadPreference>(
  (ref) => const CloudAutoUploadPreference(),
);
final cloudAutoUploadQueueStoreProvider = Provider<CloudAutoUploadQueueStore>(
  (ref) => const SharedPreferencesCloudAutoUploadQueueStore(),
);

/// 今日确认后的自动上传协调器。它与版本检查共用同一仓储、访问判定与时钟，
/// 因此自动上传和手动同步看到的是同一份云端状态。
final cloudAutoUploadCoordinatorProvider =
    Provider.autoDispose<CloudAutoUploadCoordinator?>((ref) {
      final repository = ref.watch(cloudSnapshotRepositoryProvider);
      if (repository == null) return null;
      final lifecycle = ref.watch(userLifecycleStatusRepositoryProvider);
      final auth = ref.watch(authRepositoryProvider);
      final userId = repository.userId;
      final coordinator = CloudAutoUploadCoordinator(
        userId: userId,
        repository: repository,
        preference: ref.watch(cloudAutoUploadPreferenceProvider),
        queueStore: ref.watch(cloudAutoUploadQueueStoreProvider),
        versionCheck: ref.watch(cloudVersionCheckProvider),
        now: ref.watch(cloudCheckClockProvider),
        canAccess: () async {
          if (auth.currentUserId != userId) return false;
          final status = await lifecycle.refresh();
          return auth.currentUserId == userId && !status.isSuspended;
        },
        isAccessible: () async {
          if (auth.currentUserId != userId) return false;
          final status = await lifecycle.readCachedStatus();
          return auth.currentUserId == userId &&
              status != null &&
              !status.isSuspended;
        },
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

final chainSignalsRepositoryFactoryProvider =
    Provider<ChainSignalsRepository Function(String userId)?>((ref) => null);
final chainSignalsRepositoryProvider =
    Provider.autoDispose<ChainSignalsRepository?>((ref) {
      final userId = ref.watch(authUserIdProvider);
      final factory = ref.watch(chainSignalsRepositoryFactoryProvider);
      return userId == null || factory == null ? null : factory(userId);
    });

final profileRepositoryFactoryProvider =
    Provider<ProfileRepository Function(String userId)?>((ref) => null);

final profileRepositoryProvider = Provider.autoDispose<ProfileRepository>((
  ref,
) {
  final userId = ref.watch(authUserIdProvider);
  final factory = ref.watch(profileRepositoryFactoryProvider);
  if (userId == null || factory == null) {
    return const UnavailableProfileRepository();
  }
  final repository = factory(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

/// 设备 IANA 时区，只作为账号显示时区的一次性迁移输入。
///
/// 显示路径不读它：账号没有值时用 [AccountTimeZones.fallbackId]，切换设备或
/// 设备时区变化都不会改变已有账号值的显示。
final deviceTimeZoneIdReaderProvider = Provider<Future<String?> Function()>(
  (ref) => readDeviceTimeZoneId,
);

/// 读取设备时区；读不到时返回 null（本次不迁移，稍后重试）。
Future<String?> readDeviceTimeZoneId() async {
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    return FocusTimeZones.contains(zone.identifier) ? zone.identifier : null;
  } catch (_) {
    return null;
  }
}

final avatarPickerProvider = Provider<AvatarPicker>(
  (ref) => const SystemAvatarPicker(),
);

final profileOverviewSourceProvider =
    Provider.autoDispose<ProfileOverviewSource>(
      (ref) => RepositoryProfileOverviewSource(
        nationalFocusRepository: ref.watch(nationalFocusRepositoryProvider),
        focusRepository: ref.watch(focusRepositoryProvider),
      ),
    );

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return const UnavailableAuthRepository();
});

final nationalFocusAiGrantRepositoryProvider =
    Provider.autoDispose<NationalFocusAiGrantRepository?>((ref) {
      final userId = ref.watch(authUserIdProvider);
      final factory = ref.watch(nationalFocusAiGrantRepositoryFactoryProvider);
      return userId == null || factory == null ? null : factory(userId);
    });

final userPurgeCleanupRepositoryProvider =
    Provider<UserPurgeCleanupRepository?>((ref) => null);

final focusNotificationServiceProvider = Provider<FocusNotificationService>((
  ref,
) {
  return DisabledFocusNotificationService();
});

/// Opens one ordinary schedule reminder.
///
/// The Plan destination owns this navigation; the provider only exists so a
/// fixture or a test can observe the request instead of driving the real page.
final scheduleReminderOpenHandlerProvider =
    Provider<Future<void> Function(ScheduleReminderRequest)?>((ref) => null);

final taskRepositoryFactoryProvider =
    Provider<TaskRepository Function(String userId)>((ref) {
      return (_) => const UnavailableTaskRepository();
    });

final focusRepositoryFactoryProvider =
    Provider<FocusRepository Function(String userId)>((ref) {
      return (_) => const UnavailableFocusRepository();
    });

final taskRepositoryProvider = Provider.autoDispose<TaskRepository>((ref) {
  final userId = ref.watch(authUserIdProvider);
  if (userId == null) return const UnavailableTaskRepository();
  final repository = ref.watch(taskRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final focusRepositoryProvider = Provider.autoDispose<FocusRepository>((ref) {
  final userId = ref.watch(authUserIdProvider);
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
      final userId = ref.watch(authUserIdProvider);
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
  final userId = ref.watch(authUserIdProvider);
  if (userId == null) return const UnavailableCalendarRepository();
  final repository = ref.watch(calendarRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final scheduleRepositoryFactoryProvider =
    Provider<ScheduleRepository Function(String userId)>((ref) {
      return (_) => const UnavailableScheduleRepository();
    });

final scheduleRepositoryProvider = Provider.autoDispose<ScheduleRepository>((
  ref,
) {
  final userId = ref.watch(authUserIdProvider);
  if (userId == null) return const UnavailableScheduleRepository();
  final repository = ref.watch(scheduleRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final userLifecycleRepositoryFactoryProvider =
    Provider<UserLifecycleStatusRepository Function(String userId)>((ref) {
      return (_) => const UnavailableUserLifecycleStatusRepository();
    });

final userLifecycleStatusRepositoryProvider =
    Provider.autoDispose<UserLifecycleStatusRepository>((ref) {
      final userId = ref.watch(authUserIdProvider);
      if (userId == null) {
        return const UnavailableUserLifecycleStatusRepository();
      }
      return ref.watch(userLifecycleRepositoryFactoryProvider)(userId);
    });

class _UserPurgeCleanupLifecycleObserver extends StatefulWidget {
  const _UserPurgeCleanupLifecycleObserver({
    required this.cleanupRepository,
    required this.child,
  });

  final UserPurgeCleanupRepository? cleanupRepository;
  final Widget child;

  @override
  State<_UserPurgeCleanupLifecycleObserver> createState() =>
      _UserPurgeCleanupLifecycleObserverState();
}

class _UserPurgeCleanupLifecycleObserverState
    extends State<_UserPurgeCleanupLifecycleObserver>
    with WidgetsBindingObserver {
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      unawaited(_runCleanup());
    });
    unawaited(_runCleanup());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_runCleanup());
  }

  Future<void> _runCleanup() async {
    final repository = widget.cleanupRepository;
    if (repository == null || _running) return;
    _running = true;
    try {
      await repository.purgeLocallyConfirmedUsers();
    } catch (_) {
      // Offline or invalid receipt responses keep local rows for a later retry.
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
        return snapshot.data == null
            ? const AuthScreen()
            : AppShell(key: ValueKey(repository.currentUserId));
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
                      _isRegistering ? '使用注册资格创建密码。' : '把注意力带回眼前的一步。',
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
                        _isRegistering ? '已有账号？返回登录' : '没有注册资格？联系管理员。',
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
            : _findTaskTitle(goals, taskId) ?? '当前任务',
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

  void _openNationalFocusAiAnalysis() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationalFocusAiAnalysisPage(
          onOpenSync: () => _openAiManualSync(context, ref),
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
                      : 960,
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

enum _PlanView { goals, calendar }

/// 计划目的地：目标与日历两个视图，承载既有目标/任务管理与自有日程。
///
/// 显示时区由调用方以账号值解析后传入（02 合并前是适配器），本页不读取
/// 设备级显示偏好；目标/任务的创建、编辑、完成、删除都在这里完成。
/// 账号显示时区（02 合并前的窄适配器）。
///
/// 账号显示时区（02 合入后由账号资料提供）。
///
/// 保留这个窄入口：计划页只关心"显示用哪个时区"，不必知道来源。账号还没有
/// 有效值时用统一 fallback 常量，不退回本设备时区，也不写入任何偏好。
Future<String> resolveAccountDisplayTimeZoneId(
  ProfileRepository profileRepository,
) async {
  final profile = await profileRepository.getProfile();
  return AccountTimeZones.effectiveId(profile.displayTimeZoneId);
}

class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({
    super.key,
    required this.displayTimeZoneLoader,
    this.navigationTarget,
  });

  final Future<String> Function() displayTimeZoneLoader;

  /// 普通安排提醒点开的目标（06 通知）；null 表示正常进入计划页。
  final PlanTarget? navigationTarget;

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  late var _view = widget.navigationTarget == null
      ? _PlanView.goals
      : _PlanView.calendar;
  late final Future<String> _fallbackDisplayTimeZoneId = widget
      .displayTimeZoneLoader();

  /// 内容区左右滑动与分段按钮共用同一个页码。
  late final PageController _pageController = PageController(
    initialPage: _view.index,
  );

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectView(_PlanView next) {
    if (_view == next) return;
    setState(() => _view = next);
    if (!_pageController.hasClients) return;
    final current = _pageController.page?.round();
    if (current == next.index) return;
    _pageController.animateToPage(
      next.index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(PlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationTarget == null ||
        widget.navigationTarget == oldWidget.navigationTarget) {
      return;
    }
    _selectView(_PlanView.calendar);
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final scheduleRepository = ref.watch(scheduleRepositoryProvider);
    final profileRepository = ref.watch(profileRepositoryProvider);
    // 账号时区是页面唯一的显示来源：资料流更新（含另一台设备写入）后
    // 日历与目标卡立即按新时区重建；设备时区只在资料为空时提供固定 fallback。
    return FutureBuilder<String>(
      future: _fallbackDisplayTimeZoneId,
      builder: (context, fallbackSnapshot) => StreamBuilder<ProfileAccount>(
        stream: profileRepository.watchProfile(),
        builder: (context, profileSnapshot) {
          final displayTimeZoneId = profileSnapshot.hasData
              ? AccountTimeZones.effectiveId(
                  profileSnapshot.data!.displayTimeZoneId,
                )
              : (fallbackSnapshot.data ?? 'Etc/UTC');
          return StreamBuilder<List<Goal>>(
            stream: taskRepository.watchGoals(),
            initialData: const [],
            builder: (context, snapshot) {
              final goals = snapshot.data ?? const <Goal>[];
              // 日历视图左右内边距收到 12：360 宽下 7 列日期仍保有 ≥48×48
              // 的命中区（(360-24)/7 = 48）。标题行补回 4，和其他目的地
              // 一样从 16 起排，视觉左边界不变。
              final calendar = _view == _PlanView.calendar;
              final horizontal = calendar ? 12.0 : 16.0;
              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 0),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: calendar ? 4 : 0,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          Text(
                            '计划',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          SegmentedButton<_PlanView>(
                            segments: const [
                              ButtonSegment(
                                value: _PlanView.goals,
                                icon: Icon(Icons.flag_outlined),
                                label: Text('目标'),
                              ),
                              ButtonSegment(
                                value: _PlanView.calendar,
                                icon: Icon(Icons.calendar_month_outlined),
                                label: Text('日历'),
                              ),
                            ],
                            selected: {_view},
                            onSelectionChanged: (selection) =>
                                _selectView(selection.first),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 头部留在滑动区之外：分段控件与标题不随页面移动。
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      // 手势只在内容区：页面本身的水平拖动与两条分页边界由
                      // PageView 负责，两端停住不循环。
                      onPageChanged: (index) =>
                          setState(() => _view = _PlanView.values[index]),
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                          children: _buildGoals(
                            context,
                            taskRepository,
                            goals,
                            displayTimeZoneId,
                          ),
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                          children: [
                            _buildCalendar(
                              context,
                              taskRepository,
                              scheduleRepository,
                              goals,
                              displayTimeZoneId,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildGoals(
    BuildContext context,
    TaskRepository taskRepository,
    List<Goal> goals,
    String displayTimeZoneId,
  ) {
    final pinned = [
      for (final goal in goals)
        if (goal.isPinned) goal,
    ];
    final others = [
      for (final goal in goals)
        if (!goal.isPinned) goal,
    ];
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '目标与任务',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: () => _createGoal(context, taskRepository),
            icon: const Icon(Icons.add),
            label: const Text('新建目标'),
          ),
        ],
      ),
      if (goals.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.inbox_outlined, size: 48),
                const SizedBox(height: 12),
                Text('还没有目标', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('新建目标后在这里管理任务；看板只显示置顶目标摘要。'),
              ],
            ),
          ),
        ),
      if (pinned.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          '置顶目标 · 手动顺序',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        for (var index = 0; index < pinned.length; index++)
          _goalCard(
            taskRepository,
            pinned[index],
            displayTimeZoneId: displayTimeZoneId,
            canMoveUp: index > 0,
            canMoveDown: index < pinned.length - 1,
            onMoveUp: () => _movePinned(taskRepository, pinned, index, -1),
            onMoveDown: () => _movePinned(taskRepository, pinned, index, 1),
          ),
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          pinned.isEmpty ? '全部目标' : '其他目标',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        for (final goal in others)
          _goalCard(taskRepository, goal, displayTimeZoneId: displayTimeZoneId),
      ],
    ];
  }

  Widget _goalCard(
    TaskRepository taskRepository,
    Goal goal, {
    required String displayTimeZoneId,
    bool canMoveUp = false,
    bool canMoveDown = false,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final focusRepository = ref.watch(focusRepositoryProvider);
    return StreamBuilder<FocusDashboardMetrics>(
      stream: focusRepository.watchDashboardMetrics(
        timeZoneId: displayTimeZoneId,
      ),
      builder: (context, metricsSnapshot) {
        final metrics = metricsSnapshot.data;
        return _GoalCard(
          key: ValueKey(goal.id),
          repository: taskRepository,
          goal: goal,
          showPinControls: true,
          canMoveUp: canMoveUp,
          canMoveDown: canMoveDown,
          onTogglePin: () =>
              taskRepository.setGoalPinned(goal.id, isPinned: !goal.isPinned),
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          focusProgressSecondsByTask: metrics?.focusProgressSecondsByTask,
          pendingReviewTaskIds:
              metrics?.pendingReviewTaskIds ?? const <String>{},
        );
      },
    );
  }

  /// 日历要能读出"已删除的任务"名称：按普通目标列表变化时刷新一次带墓碑的读取。
  List<Goal>? _calendarGoalsSource;
  Future<List<Goal>>? _calendarGoalsFuture;

  Future<List<Goal>> _calendarGoals(
    TaskRepository repository,
    List<Goal> goals,
  ) {
    if (!identical(_calendarGoalsSource, goals)) {
      _calendarGoalsSource = goals;
      _calendarGoalsFuture = repository.getGoals(includeDeleted: true);
    }
    return _calendarGoalsFuture!;
  }

  Widget _buildCalendar(
    BuildContext context,
    TaskRepository taskRepository,
    ScheduleRepository scheduleRepository,
    List<Goal> goals,
    String displayTimeZoneId,
  ) {
    return FutureBuilder<List<Goal>>(
      future: _calendarGoals(taskRepository, goals),
      builder: (context, goalSnapshot) => PlanCalendarView(
        repository: scheduleRepository,
        goals: goalSnapshot.data ?? goals,
        displayTimeZoneId: displayTimeZoneId,
        calendarRepository: ref.watch(calendarRepositoryProvider),
        initialDay: widget.navigationTarget?.day,
        highlightScheduleId: widget.navigationTarget?.scheduleId,
        // 与专注倒计时共用同一个注入时钟：日期、今天标记和月视图都能
        // 在同一份 fixture 里被固定，页面不各自读取系统时间。
        now: ref.watch(displayClockProvider),
      ),
    );
  }

  Future<void> _createGoal(
    BuildContext context,
    TaskRepository taskRepository,
  ) async {
    final draft = await _showGoalDialog(context);
    if (draft != null) await taskRepository.createGoal(draft);
  }

  Future<void> _movePinned(
    TaskRepository taskRepository,
    List<Goal> pinned,
    int index,
    int delta,
  ) async {
    final target = index + delta;
    if (target < 0 || target >= pinned.length) return;
    final ids = [for (final goal in pinned) goal.id];
    final moved = ids.removeAt(index);
    ids.insert(target, moved);
    await taskRepository.reorderPinnedGoals(ids);
  }
}

/// Ticket 11：看板对未回顾失败记录的提示入口。
///
/// 提示只负责把用户带到国策树里的失败记录页（10 号已有的入口），
/// 标记回顾不会介入专注、预约或结算。
class _FailureReviewPrompt extends StatelessWidget {
  const _FailureReviewPrompt({
    required this.repository,
    required this.displayTimeZoneId,
  });

  final NationalFocusRepository repository;
  final String displayTimeZoneId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NationalFocusFailure>>(
      stream: repository.watchFailures(),
      builder: (context, snapshot) {
        final pendingBatches = <String>{
          for (final failure in snapshot.data ?? const <NationalFocusFailure>[])
            if (failure.needsReflection) failure.batchId,
        };
        if (pendingBatches.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              key: const ValueKey('board-failure-review-hint'),
              leading: const Icon(Icons.history_toggle_off),
              title: Text('${pendingBatches.length} 组国策失败待回顾'),
              subtitle: const Text('稍后再看也可以；回顾只做标记，不改动当时的失败结果。'),
              trailing: const Icon(Icons.chevron_right),
              // 直达 10 号已有的失败记录页，而不是只切换主导航；
              // 完整回顾仍在那一页里进入冻结树二级页。
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NationalFocusFailureHistoryPage(
                    repository: repository,
                    displayTimeZoneId: displayTimeZoneId,
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

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({
    super.key,
    required this.onOpenNationalFocus,
    required this.onOpenPlan,
  });

  final VoidCallback onOpenNationalFocus;
  final VoidCallback onOpenPlan;

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  /// 重试只换订阅：递增代次让带 key 的 StreamBuilder 换元素，旧的读取随元素
  /// 释放，重新订阅一次当前仓储与时区。它不写任何数据，也不改仓储实例。
  var _projectionGeneration = 0;

  void _retryProjection() {
    if (!mounted) return;
    setState(() => _projectionGeneration += 1);
  }

  /// 看板只提供入口：投影、时区门禁、错误重试都由月历页自己负责，
  /// 这里不复制它的读取或写入路径。owner 与时钟在打开时绑定，
  /// 账号变化由路由自己退出，避免显示上一个账号的月份。
  void _openFocusMonth() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _FocusMonthRoute(
          ownerUserId: ref.read(authUserIdProvider),
          repository: ref.read(focusRepositoryProvider),
          profileRepository: ref.read(profileRepositoryProvider),
          now: ref.read(displayClockProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final nationalFocusRepository = ref.watch(nationalFocusRepositoryProvider);
    final scheduleRepository = ref.watch(scheduleRepositoryProvider);
    final profileRepository = ref.watch(profileRepositoryProvider);
    // 看板是只读投影：一个（资料, 目标, 专注仓储 + 重试代次）对应一次显式订阅，
    // 身份一变就换 key，旧状态连同订阅一起释放；因此上一账号/上一时区的数字
    // 不会留在屏上，也不需要通用回放层。读取失败交给状态里可见的错误与重试。
    return _BoardProjectionScope(
      key: ValueKey<Object>((
        'board-projection',
        profileRepository,
        taskRepository,
        focusRepository,
        _projectionGeneration,
      )),
      profileRepository: profileRepository,
      taskRepository: taskRepository,
      focusRepository: focusRepository,
      builder: (context, projection) => _BoardContent(
        displayTimeZoneId: projection.displayTimeZoneId,
        now: ref.read(displayClockProvider),
        repository: taskRepository,
        focusRepository: focusRepository,
        nationalFocusRepository: nationalFocusRepository,
        scheduleRepository: scheduleRepository,
        onOpenNationalFocus: widget.onOpenNationalFocus,
        onOpenPlan: widget.onOpenPlan,
        onOpenFocusMonth: _openFocusMonth,
        goals: projection.goals,
        metrics: projection.metrics,
        accountFailed: projection.accountFailed,
        metricsFailed: projection.metricsFailed,
        goalsFailed: projection.goalsFailed,
        onRetryProjection: _retryProjection,
      ),
    );
  }
}

/// 看板一次读取的结果：账号时区、目标、近期投影与失败标记。
class _BoardProjection {
  const _BoardProjection({
    required this.displayTimeZoneId,
    required this.goals,
    required this.metrics,
    required this.accountFailed,
    required this.metricsFailed,
    required this.goalsFailed,
  });

  final String displayTimeZoneId;
  final List<Goal> goals;
  final FocusDashboardMetrics? metrics;

  /// 账号资料读取失败：时区按统一兜底值显示，但屏幕必须说明这一点。
  final bool accountFailed;

  /// 近期投影读取失败：不再显示成"正在加载"。
  final bool metricsFailed;

  /// 目标列表读取失败：不能渲染成"还没有置顶目标"。
  final bool goalsFailed;
}

/// 看板的只读订阅宿主。
///
/// 身份由外层 key 决定：仓储或重试代次一变就是新的 State，旧订阅随
/// [dispose] 一起取消。这里不缓存旧快照——换时区时先清空投影再订阅，所以
/// 屏上不会出现上一个账号/时区的数字，也不需要一层通用回放流；读取失败
/// 以可见标记上报，重试只是换 key 重新订阅，不写任何数据。
class _BoardProjectionScope extends StatefulWidget {
  const _BoardProjectionScope({
    super.key,
    required this.profileRepository,
    required this.taskRepository,
    required this.focusRepository,
    required this.builder,
  });

  final ProfileRepository profileRepository;
  final TaskRepository taskRepository;
  final FocusRepository focusRepository;
  final Widget Function(BuildContext context, _BoardProjection projection)
  builder;

  @override
  State<_BoardProjectionScope> createState() => _BoardProjectionScopeState();
}

class _BoardProjectionScopeState extends State<_BoardProjectionScope> {
  StreamSubscription<ProfileAccount>? _profileSubscription;
  StreamSubscription<FocusDashboardMetrics>? _metricsSubscription;
  StreamSubscription<List<Goal>>? _goalsSubscription;
  String _displayTimeZoneId = AccountTimeZones.fallbackId;
  List<Goal> _goals = const [];
  FocusDashboardMetrics? _metrics;
  bool _accountFailed = false;
  bool _metricsFailed = false;
  bool _goalsFailed = false;
  bool _hasBuilt = false;

  /// Whether the account profile produced its first value or error.
  ///
  /// Until then the display zone is unknown, and querying the projection with
  /// the fallback zone would paint UTC-allocated bars before the account's own
  /// zone arrives. The board waits instead of showing a number it cannot stand
  /// behind.
  bool _profileResolved = false;

  @override
  void initState() {
    super.initState();
    _subscribeProfile();
    _subscribeGoals();
  }

  @override
  void dispose() {
    unawaited(_profileSubscription?.cancel());
    unawaited(_metricsSubscription?.cancel());
    unawaited(_goalsSubscription?.cancel());
    super.dispose();
  }

  /// 首帧之前的同步事件直接改字段，避免在挂载途中 setState。
  void _apply(VoidCallback change) {
    if (!mounted) return;
    if (_hasBuilt) {
      setState(change);
    } else {
      change();
    }
  }

  void _subscribeProfile() {
    _profileSubscription = widget.profileRepository.watchProfile().listen(
      (profile) {
        final nextZone = AccountTimeZones.effectiveId(
          profile.displayTimeZoneId,
        );
        final zoneChanged = nextZone != _displayTimeZoneId;
        final firstValue = !_profileResolved;
        _apply(() {
          _accountFailed = false;
          _profileResolved = true;
          if (!zoneChanged) return;
          // 换时区先丢掉旧投影：新流首帧到达前屏上是加载态，不是旧数字。
          _displayTimeZoneId = nextZone;
          _metrics = null;
          _metricsFailed = false;
        });
        if (zoneChanged || firstValue) _subscribeMetrics();
      },
      onError: (Object error, StackTrace stackTrace) {
        final firstValue = !_profileResolved;
        _apply(() {
          _accountFailed = true;
          _profileResolved = true;
        });
        if (firstValue) _subscribeMetrics();
      },
    );
  }

  void _subscribeGoals() {
    _goalsSubscription = widget.taskRepository.watchGoals().listen(
      (goals) => _apply(() {
        _goals = goals;
        _goalsFailed = false;
      }),
      onError: (Object error, StackTrace stackTrace) {
        _apply(() {
          _goals = const [];
          _goalsFailed = true;
        });
      },
    );
  }

  void _subscribeMetrics() {
    unawaited(_metricsSubscription?.cancel());
    final timeZoneId = _displayTimeZoneId;
    _metricsSubscription = widget.focusRepository
        .watchDashboardMetrics(timeZoneId: timeZoneId)
        .listen(
          (metrics) => _apply(() {
            _metrics = metrics;
            _metricsFailed = false;
          }),
          onError: (Object error, StackTrace stackTrace) {
            _apply(() {
              _metrics = null;
              _metricsFailed = true;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    _hasBuilt = true;
    return widget.builder(
      context,
      _BoardProjection(
        displayTimeZoneId: _displayTimeZoneId,
        goals: _goals,
        metrics: _metrics,
        accountFailed: _accountFailed,
        metricsFailed: _metricsFailed,
        goalsFailed: _goalsFailed,
      ),
    );
  }
}

/// 只读月历路由：owner 变化时退出，不把上一个账号的投影留在屏幕上。
class _FocusMonthRoute extends ConsumerWidget {
  const _FocusMonthRoute({
    required this.ownerUserId,
    required this.repository,
    required this.profileRepository,
    required this.now,
  });

  final String? ownerUserId;
  final FocusRepository repository;
  final ProfileRepository profileRepository;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authUserIdProvider) != ownerUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const SizedBox.shrink();
    }
    return FocusMonthPage(
      repository: repository,
      accountTimeZoneIds: () => profileRepository.watchProfile().map(
        (profile) => profile.displayTimeZoneId,
      ),
      now: now,
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({
    required this.displayTimeZoneId,
    required this.now,
    required this.repository,
    required this.focusRepository,
    required this.nationalFocusRepository,
    required this.scheduleRepository,
    required this.onOpenNationalFocus,
    required this.onOpenPlan,
    required this.onOpenFocusMonth,
    required this.goals,
    required this.metrics,
    required this.accountFailed,
    required this.metricsFailed,
    required this.goalsFailed,
    required this.onRetryProjection,
  });

  final String displayTimeZoneId;

  /// Shared display clock: the board's "today" must be the same day the Plan
  /// calendar starts on, so an injected clock fixes both surfaces at once.
  final DateTime Function() now;
  final TaskRepository repository;
  final FocusRepository focusRepository;
  final NationalFocusRepository nationalFocusRepository;
  final ScheduleRepository scheduleRepository;
  final VoidCallback onOpenNationalFocus;
  final VoidCallback onOpenPlan;
  final VoidCallback onOpenFocusMonth;
  final List<Goal> goals;
  final FocusDashboardMetrics? metrics;

  /// 账号资料读取失败：时区退回统一兜底值，卡片里要说明这一点。
  final bool accountFailed;

  /// 近期投影读取失败。失败不能被当成"暂无数据"渲染；
  /// 卡片给出可见说明和只读重试。
  final bool metricsFailed;

  /// 目标列表读取失败；同样不能静默显示成"没有置顶目标"。
  final bool goalsFailed;
  final VoidCallback onRetryProjection;

  @override
  Widget build(BuildContext context) {
    final pinned = [
      for (final goal in goals)
        if (goal.isPinned) goal,
    ];
    final primary = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Text('今天先做什么', style: Theme.of(context).textTheme.headlineSmall),
          TextButton.icon(
            onPressed: onOpenPlan,
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('打开计划'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _TodayArrangementsCard(
        repository: scheduleRepository,
        displayTimeZoneId: displayTimeZoneId,
        now: now,
        onOpenPlan: onOpenPlan,
      ),
      const SizedBox(height: 8),
      _FocusReconciliationPrompt(
        focusRepository: focusRepository,
        taskRepository: repository,
      ),
      _FocusClockReviewPrompt(repository: focusRepository),
      _FailureReviewPrompt(
        repository: nationalFocusRepository,
        displayTimeZoneId: displayTimeZoneId,
      ),
      const SizedBox(height: 8),
      _PinnedGoalSummarySection(
        goals: pinned,
        onOpenPlan: onOpenPlan,
        failed: goalsFailed,
        onRetry: onRetryProjection,
      ),
    ];
    final secondary = <Widget>[
      NationalFocusSummaryCard(
        repository: nationalFocusRepository,
        onOpenTree: onOpenNationalFocus,
      ),
      const SizedBox(height: 12),
      _RecentFocusActivityCard(
        metrics: metrics,
        failed: metricsFailed,
        accountFailed: accountFailed,
        onRetry: onRetryProjection,
        onOpenFocusMonth: onOpenFocusMonth,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children:
            constraints.maxWidth >= 960 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.6
            ? [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: primary,
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 320,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: secondary,
                      ),
                    ),
                  ],
                ),
              ]
            : [...primary, const SizedBox(height: 20), ...secondary],
      ),
    );
  }
}

/// 看板今日安排：只读摘要，安排的管理动作全部在计划页。
class _TodayArrangementsCard extends StatelessWidget {
  const _TodayArrangementsCard({
    required this.repository,
    required this.displayTimeZoneId,
    required this.now,
    required this.onOpenPlan,
  });

  final ScheduleRepository repository;
  final String displayTimeZoneId;
  final DateTime Function() now;
  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final today = scheduleToday(displayTimeZoneId, now: now());
    final window = scheduleQueryWindow(today, displayTimeZoneId);
    return StreamBuilder<List<Schedule>>(
      stream: repository.watchSchedules(from: window.from, to: window.to),
      builder: (context, snapshot) {
        final todays = schedulesOnDay(
          snapshot.data ?? const <Schedule>[],
          today,
          displayTimeZoneId,
        );
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '今天 · ${todays.length} 项安排',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(onPressed: onOpenPlan, child: const Text('安排')),
                  ],
                ),
                const SizedBox(height: 4),
                if (todays.isEmpty)
                  Text(
                    '今天还没有安排。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final schedule in todays)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            schedule.isCompleted
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: schedule.isCompleted
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              schedule.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: schedule.isCompleted
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            scheduleTimeLabel(schedule, displayTimeZoneId),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 置顶目标摘要：标题 + 下一项任务；无任务时显示空态，不伪造占位任务。
class _PinnedGoalSummarySection extends StatelessWidget {
  const _PinnedGoalSummarySection({
    required this.goals,
    required this.onOpenPlan,
    required this.failed,
    required this.onRetry,
  });

  final List<Goal> goals;
  final VoidCallback onOpenPlan;

  /// 目标列表读取失败时不能渲染成"还没有置顶目标"。
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '置顶目标',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onOpenPlan, child: const Text('管理')),
          ],
        ),
        if (failed)
          _BoardReadFailure(message: '暂时不能读取目标列表。', onRetry: onRetry)
        else if (goals.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('还没有置顶目标'),
              subtitle: const Text('在计划里置顶多个目标并手动排序，这里只显示摘要与下一项任务。'),
              trailing: TextButton(
                onPressed: onOpenPlan,
                child: const Text('去计划'),
              ),
            ),
          )
        else
          for (final goal in goals)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: const Icon(Icons.push_pin, size: 20),
                title: Text(
                  goal.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  goal.nextTask == null
                      ? '暂无任务'
                      : '下一项：${goal.nextTask!.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
      ],
    );
  }
}

/// 看板可读失败的最小呈现：说明 + 只读重试（只重新订阅，不写数据）。
class _BoardReadFailure extends StatelessWidget {
  const _BoardReadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _RecentFocusActivityCard extends StatelessWidget {
  const _RecentFocusActivityCard({
    required this.metrics,
    required this.failed,
    required this.accountFailed,
    required this.onRetry,
    required this.onOpenFocusMonth,
  });

  final FocusDashboardMetrics? metrics;

  /// 读取失败且没有可用值时，显示可见错误而不是一直转圈；重试只换订阅。
  final bool failed;

  /// 账号时区没有读到：数字仍按统一兜底时区显示，但必须说明来源。
  final bool accountFailed;
  final VoidCallback onRetry;
  final VoidCallback onOpenFocusMonth;

  @override
  Widget build(BuildContext context) {
    final value = metrics;
    final hasRecentActivity =
        value?.recentActivity.any((day) => day.activeSeconds > 0) ?? false;
    // The label promises a seven-day window; the lifetime total is a different
    // number and must not be shown under it.
    final recentSeconds =
        value?.recentActivity.fold<int>(
          0,
          (sum, day) => sum + day.activeSeconds,
        ) ??
        0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '近期专注活动',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenFocusMonth,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('打开月历'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (accountFailed)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('暂时不能确认账号时区，以下按 UTC 显示。')),
                  ],
                ),
              ),
            if (value == null)
              if (failed)
                _BoardReadFailure(message: '暂时不能读取专注投影。', onRetry: onRetry)
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
            else ...[
              Text(
                '近 7 天 · 累计有效专注 '
                '${formatEffectiveDuration(recentSeconds)}',
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
        label: '$label，${formatEffectiveDuration(day.activeSeconds)}',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final bar = ExcludeSemantics(
              child: LinearProgressIndicator(value: progress),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(label),
                      Text(formatEffectiveDuration(day.activeSeconds)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  bar,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 118, child: Text(label)),
                Expanded(child: bar),
                const SizedBox(width: 12),
                SizedBox(
                  width: 68,
                  child: Text(
                    formatEffectiveDuration(day.activeSeconds),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GoalCard extends StatefulWidget {
  const _GoalCard({
    super.key,
    required this.repository,
    required this.goal,
    required this.focusProgressSecondsByTask,
    required this.pendingReviewTaskIds,
    this.showPinControls = false,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onTogglePin,
    this.onMoveUp,
    this.onMoveDown,
  });

  final TaskRepository repository;
  final Goal goal;

  /// 计划页显示置顶与手动排序控件；看板不再渲染完整目标卡。
  final bool showPinControls;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onTogglePin;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Map<String, int>? focusProgressSecondsByTask;
  final Set<String> pendingReviewTaskIds;

  @override
  State<_GoalCard> createState() => _GoalCardState();
}

/// 目标卡头部：动作按钮各占 48 逻辑像素，标题剩余宽度不足时改为单独一行，
/// 避免普通短标题被挤成两行、元信息碎成多段。用最大动作数判断，置顶前后
/// 布局一致，不会因为多出上移/下移而突然换排版。
const double _goalHeaderComfortableTitleWidth = 160;
const double _goalHeaderActionSlotWidth = 48;
const int _goalHeaderMaxActionCount = 6;

bool _useStackedGoalHeader(double availableWidth) =>
    availableWidth - _goalHeaderMaxActionCount * _goalHeaderActionSlotWidth <
    _goalHeaderComfortableTitleWidth;

class _GoalCardState extends State<_GoalCard> {
  var _tasksExpanded = true;

  Future<void> _confirmDeleteGoal(BuildContext context) async {
    final goal = widget.goal;
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
    if (confirmed == true) await widget.repository.deleteGoal(goal.id);
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final status = goal.tasks.isEmpty
        ? '暂无任务 · 未完成'
        : goal.isComplete
        ? '已完成'
        : '进行中';
    final summary = '${goal.tasks.length} 项任务 · $status';
    // 标题块与动作按钮分开构造：窄屏时动作另起一行，宽屏才与标题并排，
    // 这样普通短标题不会被多个图标挤成两行、元信息也不会碎成多段。
    final header = Semantics(
      key: ValueKey('goal-header-${goal.id}'),
      container: true,
      expanded: _tasksExpanded,
      button: true,
      value: _tasksExpanded ? '已展开' : '已折叠',
      child: Tooltip(
        message: _tasksExpanded ? '收起任务' : '展开任务',
        child: InkWell(
          onTap: () => setState(() => _tasksExpanded = !_tasksExpanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (goal.description.isNotEmpty)
                        Text(
                          goal.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        _tasksExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final actions = <Widget>[
      IconButton(
        tooltip: '编辑目标',
        onPressed: () async {
          final draft = await _showGoalDialog(context, initial: goal);
          if (draft != null) {
            await widget.repository.updateGoal(goal.id, draft);
          }
        },
        icon: const Icon(Icons.edit_outlined),
      ),
      IconButton(
        tooltip: '删除目标',
        onPressed: () => _confirmDeleteGoal(context),
        icon: const Icon(Icons.delete_outline),
      ),
      // 置顶与手动排序是次级管理动作，排在编辑/删除之后：
      // 既有操作顺序（标题 → 编辑 → 删除）不变，鼠标与触摸入口一致。
      if (widget.showPinControls)
        IconButton(
          tooltip: goal.isPinned ? '取消置顶' : '置顶目标',
          onPressed: widget.onTogglePin,
          icon: Icon(goal.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
        ),
      if (widget.showPinControls && goal.isPinned) ...[
        IconButton(
          tooltip: '上移置顶目标',
          onPressed: widget.canMoveUp ? widget.onMoveUp : null,
          icon: const Icon(Icons.arrow_upward),
        ),
        IconButton(
          tooltip: '下移置顶目标',
          onPressed: widget.canMoveDown ? widget.onMoveDown : null,
          icon: const Icon(Icons.arrow_downward),
        ),
      ],
    ];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_useStackedGoalHeader(constraints.maxWidth)) ...[
                header,
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(children: actions),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    Wrap(children: actions),
                  ],
                ),
              if (_tasksExpanded) ...[
                if (goal.tasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('暂无任务，先添加一个可执行的下一步。'),
                  )
                else
                  for (final task in goal.tasks)
                    _TaskTile(
                      repository: widget.repository,
                      task: widget.focusProgressSecondsByTask == null
                          ? task
                          : task.copyWith(
                              focusProgressSeconds:
                                  widget.focusProgressSecondsByTask![task.id] ??
                                  0,
                            ),
                      hasPendingReview: widget.pendingReviewTaskIds.contains(
                        task.id,
                      ),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final draft = await _showTaskDialog(context, goal: goal);
                      if (draft != null) {
                        await widget.repository.createTask(goal.id, draft);
                      }
                    },
                    icon: const Icon(Icons.add_task),
                    label: const Text('添加任务'),
                  ),
                ),
              ],
            ],
          ),
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
    final hasMeta =
        task.estimatedMinutes != null ||
        task.focusProgressSeconds > 0 ||
        hasPendingReview ||
        deadline != null;
    final hasDescription = task.description.isNotEmpty;
    return ListTile(
      isThreeLine: hasMeta && hasDescription,
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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: task.isComplete
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: !hasMeta && !hasDescription
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMeta)
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      if (task.estimatedMinutes != null)
                        Text('${task.estimatedMinutes} 分钟'),
                      if (task.focusProgressSeconds > 0)
                        Text(
                          '已专注 ${formatEffectiveDuration(task.focusProgressSeconds)}',
                        ),
                      if (hasPendingReview) const Text('待核对（争议部分暂不计入专注统计）'),
                      if (deadline != null) Text(deadline),
                    ],
                  ),
                if (hasDescription)
                  Text(
                    task.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '删除任务',
            onPressed: () => _confirmDeleteTask(context, repository, task),
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
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
                builder: (_) => FocusSetupDialog(
                  task: task,
                  initialMode: _initialFocusModeFor(task.classification, mode),
                ),
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
        ],
      ),
      onTap: () async {
        final draft = await _showTaskDialog(context, task: task);
        if (draft != null) await repository.updateTask(task.id, draft);
      },
    );
  }
}

Future<void> _confirmDeleteTask(
  BuildContext context,
  TaskRepository repository,
  Task task,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除任务？'),
      content: Text(
        '“${task.title}”将从目标中移除，且不能恢复。'
        '已安排到这条任务的日程仍然保留，历史会保留原任务名称并标记为已删除。',
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
  if (confirmed == true) await repository.deleteTask(task.id);
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

final _descriptionInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.deny(
    RegExp(r'\r\n|[\r\n\u000b\u000c\u0085\u2028\u2029]'),
    replacementString: ' ',
  ),
];

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.multiline,
    minLines: 2,
    maxLines: 4,
    maxLength: taskDescriptionMaxGraphemes,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    inputFormatters: _descriptionInputFormatters,
    decoration: const InputDecoration(
      labelText: '描述（可选）',
      helperText: '单段，最多200个字符',
      helperMaxLines: 2,
      alignLabelWithHint: true,
    ),
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
  late final TextEditingController _description;
  late TaskClassification _classification;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _description = TextEditingController(text: widget.initial?.description);
    _classification =
        widget.initial?.classification ?? TaskClassification.regular;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建目标' : '编辑目标'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '目标名称'),
          ),
          const SizedBox(height: 12),
          _DescriptionField(controller: _description),
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          GoalDraft(
            title: _title.text,
            description: _description.text,
            classification: _classification,
          ),
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
  late final TextEditingController _description;
  late final TextEditingController _estimatedValue;
  late TaskClassification _classification;
  _EstimateUnit _estimateUnit = _EstimateUnit.minutes;
  String? _estimateError;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _description = TextEditingController(text: widget.initial?.description);
    _estimatedValue = TextEditingController(
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
    _description.dispose();
    _estimatedValue.dispose();
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

  /// 仅防 int 存储溢出（2^53-1，double 可精确表示的最大整数）。
  static const _maxStoredMinutes = 9007199254740991;

  /// 浮点误差级容差：只用于消掉 1/60*60 这类噪声，不改变用户输入。
  static const _minuteEpsilon = 1e-7;

  /// 原始输入折算成的分钟数；空串、非法输入或非有限值返回 null。
  double? _estimatedMinutesValue() {
    final text = _estimatedValue.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    final minutes = value * _estimateUnit.minutesPerUnit;
    if (!minutes.isFinite || minutes <= 0) return null;
    return minutes;
  }

  void _switchEstimateUnit(_EstimateUnit unit) {
    if (unit == _estimateUnit) return;
    final minutes = _estimatedMinutesValue();
    setState(() {
      if (minutes != null) {
        final converted = minutes / unit.minutesPerUnit;
        // 只抹掉浮点噪声（如 1/60*60 = 0.9999999999999999），不截断精度。
        final rounded = converted.roundToDouble();
        final shown = (converted - rounded).abs() <= _minuteEpsilon
            ? rounded
            : converted;
        final text = shown.toString();
        _estimatedValue.text = text.endsWith('.0')
            ? text.substring(0, text.length - 2)
            : text;
      }
      _estimateUnit = unit;
      _estimateError = null;
    });
  }

  /// 空输入表示不设置；统一折算成分钟保存，内部字段仍是分钟。
  int? _parseEstimatedMinutes() {
    final minutes = _estimatedMinutesValue();
    if (minutes == null) return null;
    final rounded = minutes.round();
    if (rounded < 1 || (minutes - rounded).abs() > _minuteEpsilon) return null;
    return rounded;
  }

  bool _validateEstimatedValue() {
    final text = _estimatedValue.text.trim();
    if (text.isEmpty) {
      setState(() => _estimateError = null);
      return true;
    }
    final minutes = _estimatedMinutesValue();
    if (minutes == null) {
      setState(() => _estimateError = '请输入大于 0 的数字，留空表示不设置');
      return false;
    }
    if (minutes > _maxStoredMinutes) {
      setState(() => _estimateError = '数值超出可存储范围，请使用更小的值');
      return false;
    }
    final rounded = minutes.round();
    if (rounded < 1) {
      setState(() => _estimateError = '按分钟至少 1 分钟');
      return false;
    }
    if ((minutes - rounded).abs() > _minuteEpsilon) {
      setState(() => _estimateError = '按分钟需为整数，例如 1.5 小时');
      return false;
    }
    setState(() => _estimateError = null);
    return true;
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
          _DescriptionField(controller: _description),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskClassification>(
            initialValue: _classification,
            decoration: const InputDecoration(labelText: '适用专注链'),
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
            controller: _estimatedValue,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '预计时长（可选）',
              errorText: _estimateError,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 132,
              child: DropdownButtonFormField<String>(
                initialValue: _estimateUnit.name,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '单位'),
                items: [
                  for (final unit in _EstimateUnit.values)
                    DropdownMenuItem(value: unit.name, child: Text(unit.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _switchEstimateUnit(
                    _EstimateUnit.values.firstWhere(
                      (unit) => unit.name == value,
                    ),
                  );
                },
              ),
            ),
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
        onPressed: () {
          if (!_validateEstimatedValue()) return;
          Navigator.pop(
            context,
            TaskDraft(
              title: _title.text,
              description: _description.text,
              classification: _classification,
              estimatedMinutes: _parseEstimatedMinutes(),
              deadline: _deadline,
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

enum _EstimateUnit {
  minutes('分钟', 1),
  hours('小时', 60);

  const _EstimateUnit(this.label, this.minutesPerUnit);

  final String label;
  final int minutesPerUnit;
}

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class FocusChainPage extends ConsumerStatefulWidget {
  const FocusChainPage({super.key});

  @override
  ConsumerState<FocusChainPage> createState() => _FocusChainPageState();
}

class _FocusChainPageState extends ConsumerState<FocusChainPage> {
  bool _openingTaskPicker = false;
  FocusRepository? _projectionRepository;
  String? _projectionSignature;
  late Future<List<FocusChainRecord>> _chainRecordsFuture;
  late Future<AppointmentChainRecord> _appointmentChainRecordFuture;
  late Stream<AppointmentPreparation?> _activeAppointmentStream;
  late Future<List<PrecedentRule>> _precedentRulesFuture;

  @override
  void initState() {
    super.initState();
    _activeAppointmentStream = ref
        .read(focusRepositoryProvider)
        .watchActiveAppointment();
    _precedentRulesFuture = ref
        .read(focusRepositoryProvider)
        .getPrecedentRules();
  }

  void _refreshActiveAppointment() {
    if (mounted) {
      setState(() {
        final repository = ref.read(focusRepositoryProvider);
        _activeAppointmentStream = repository.watchActiveAppointment();
        _appointmentChainRecordFuture = repository.getAppointmentChainRecord();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    final signalsRepository = ref.watch(chainSignalsRepositoryProvider);
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
          for (final goal in snapshot.data ?? const <Goal>[])
            if (!goal.isDeleted)
              for (final task in goal.tasks)
                if (!task.isDeleted && !task.isComplete) task,
        ];
        return StreamBuilder<List<FocusSession>>(
          stream: focusRepository.watchSessions(),
          initialData: const [],
          builder: (context, sessionsSnapshot) {
            final sessions = sessionsSnapshot.data ?? const <FocusSession>[];
            _updateProjectionFutures(focusRepository, sessions);
            final statistics = focusStatisticsByMode(sessions);
            final active = sessions
                .where((session) => session.isUnfinished)
                .firstOrNull;
            final activeTask = active == null
                ? null
                : allTasks
                      .where((task) => task.id == active.taskId)
                      .firstOrNull;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        key: const ValueKey('focus-chain-list'),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '专注链',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton.icon(
                                key: const ValueKey('focus-history-entry'),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(64, 48),
                                ),
                                icon: const Icon(Icons.history, size: 20),
                                label: const Text('历史'),
                                onPressed: () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const FocusHistoryPage(),
                                      ),
                                    ),
                              ),
                            ],
                          ),
                          if (active != null)
                            _FocusRecoveryStrip(
                              icon: Icons.timer_outlined,
                              title: '已有进行中的专注',
                              subtitle: activeTask == null
                                  ? '原任务'
                                  : _taskDisplayTitle(activeTask),
                              trailing: FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(96, 48),
                                ),
                                onPressed: () => _openSession(
                                  active,
                                  taskTitles[active.taskId] ?? '原任务',
                                ),
                                child: const Text('返回专注'),
                              ),
                            ),
                          StreamBuilder<AppointmentPreparation?>(
                            key: const ValueKey('focus-active-appointment'),
                            stream: _activeAppointmentStream,
                            builder: (context, appointmentSnapshot) {
                              final appointment = appointmentSnapshot.data;
                              if (appointment == null) {
                                return const SizedBox.shrink();
                              }
                              final title =
                                  taskTitles[appointment.taskId] ?? '原预约任务';
                              return _FocusRecoveryStrip(
                                icon: Icons.event_available,
                                title: '已有预约准备',
                                subtitle: appointment.isPendingReview
                                    ? '$title · 待核对'
                                    : title,
                                tone: _RecoveryStripTone.secondary,
                                actions: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: () =>
                                        _openAppointment(appointment, title),
                                    child: const Text('返回准备'),
                                  ),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: () =>
                                        _enterAppointment(appointment, title),
                                    child: const Text('提前进入专注'),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: () =>
                                        _cancelAppointment(appointment),
                                    child: const Text('取消预约'),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          FutureBuilder<List<FocusChainRecord>>(
                            future: _chainRecordsFuture,
                            builder: (context, recordSnapshot) {
                              if (recordSnapshot.hasError) {
                                return _recordReadError();
                              }
                              if (!recordSnapshot.hasData) {
                                return const LinearProgressIndicator();
                              }
                              return FutureBuilder<AppointmentChainRecord>(
                                future: _appointmentChainRecordFuture,
                                builder: (context, appointmentSnapshot) {
                                  if (appointmentSnapshot.hasError) {
                                    return _recordReadError();
                                  }
                                  if (!appointmentSnapshot.hasData) {
                                    return const LinearProgressIndicator();
                                  }
                                  return FocusChainOverview(
                                    repository: signalsRepository,
                                    records: recordSnapshot.data!,
                                    appointmentRecord: appointmentSnapshot.data,
                                    statistics: statistics,
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          _allowanceEntry(context),
                          const SizedBox(height: 4),
                          Text(
                            '累计与平均包含失败专注的有效时间，不含暂停。',
                            key: const ValueKey('focus-chain-footnote'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _FocusStartBar(
                      taskCount: tasks.length,
                      busy: _openingTaskPicker,
                      onPressed: _openTaskPicker,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The 下必为例 entry point: the first screen only links to the full manager.
  Widget _allowanceEntry(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FutureBuilder<List<PrecedentRule>>(
      future: _precedentRulesFuture,
      builder: (context, snapshot) {
        final count = snapshot.data?.length;
        final subtitle = snapshot.hasError
            ? '读取失败，进入管理后可重试'
            : count == null
            ? '读取中…'
            : '$count 条持续许可';
        return Container(
          key: const ValueKey('focus-allowance-entry'),
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下必为例',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                key: const ValueKey('focus-allowance-manage'),
                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: _openPrecedentRules,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('管理'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _recordReadError() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('链记录读取失败，请重试。'),
        TextButton(
          onPressed: () => setState(() {
            final repository = ref.read(focusRepositoryProvider);
            _chainRecordsFuture = repository.getChainRecords();
            _appointmentChainRecordFuture = repository
                .getAppointmentChainRecord();
          }),
          child: const Text('重试'),
        ),
      ],
    ),
  );

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
  }

  Future<void> _openTaskPicker() async {
    if (_openingTaskPicker) return;
    setState(() => _openingTaskPicker = true);
    try {
      final repository = ref.read(focusRepositoryProvider);
      final activeSession = await repository.getActiveSession();
      final activeAppointment = activeSession == null
          ? await repository.getActiveAppointment()
          : null;
      final mode = activeSession == null && activeAppointment == null
          ? await repository.getLastMode()
          : FocusChainMode.regular;
      if (!mounted) return;
      final result =
          activeSession ??
          activeAppointment ??
          await Navigator.of(context).push<Object>(
            MaterialPageRoute<Object>(
              builder: (_) => FocusTaskPickerPage(initialMode: mode),
            ),
          );
      if (!mounted || result == null) return;
      final goals = await ref
          .read(taskRepositoryProvider)
          .getGoals(includeDeleted: true);
      if (!mounted) return;
      if (result is FocusSession) {
        _openSession(result, _findTaskTitle(goals, result.taskId) ?? '原任务');
      } else if (result is AppointmentPreparation) {
        await _openAppointment(
          result,
          _findTaskTitle(goals, result.taskId) ?? '原预约任务',
        );
      }
      _refreshActiveAppointment();
    } catch (error) {
      if (mounted) _showFocusError(context, error);
    } finally {
      if (mounted) setState(() => _openingTaskPicker = false);
    }
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

  Future<void> _openPrecedentRules() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PrecedentRulesPage()),
    );
    if (!mounted) return;
    setState(() {
      _precedentRulesFuture = ref
          .read(focusRepositoryProvider)
          .getPrecedentRules();
    });
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

enum _RecoveryStripTone { primary, secondary }

/// Compact recovery strip for an unfinished session or a waiting appointment.
class _FocusRecoveryStrip extends StatelessWidget {
  const _FocusRecoveryStrip({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.actions = const [],
    this.tone = _RecoveryStripTone.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> actions;
  final _RecoveryStripTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = tone == _RecoveryStripTone.primary;
    final background = primary
        ? colors.primaryContainer
        : colors.secondaryContainer;
    final foreground = primary
        ? colors.onPrimaryContainer
        : colors.onSecondaryContainer;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: primary ? colors.primary : colors.secondary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing case final action?) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 2),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Full 下必为例 manager, opened from the Focus Chain first screen.
class PrecedentRulesPage extends StatelessWidget {
  const PrecedentRulesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('下必为例')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: const [PrecedentRulesCard()],
    ),
  );
}

/// The pinned start action: choosing a task never requires scrolling away.
class _FocusStartBar extends StatelessWidget {
  const _FocusStartBar({
    required this.taskCount,
    required this.busy,
    required this.onPressed,
  });

  final int taskCount;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                '开始一次专注',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '可选任务 $taskCount 个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            key: const ValueKey('focus-task-picker-entry'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: busy ? null : onPressed,
            icon: const Icon(Icons.playlist_play),
            label: const Text('选择任务'),
          ),
        ],
      ),
    );
  }
}

class FocusTaskPickerPage extends ConsumerStatefulWidget {
  const FocusTaskPickerPage({
    super.key,
    this.initialMode = FocusChainMode.regular,
  });

  final FocusChainMode initialMode;

  @override
  ConsumerState<FocusTaskPickerPage> createState() =>
      _FocusTaskPickerPageState();
}

class _FocusTaskPickerPageState extends ConsumerState<FocusTaskPickerPage> {
  TaskClassification? _filter;
  bool _openingSetup = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('选择任务')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<TaskClassification?>(
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
            ),
            Expanded(
              child: StreamBuilder<List<Goal>>(
                stream: ref.watch(taskRepositoryProvider).watchGoals(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('任务读取失败，请返回后重试。'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final goals = snapshot.data!;
                  final entries = [
                    for (final goal in goals)
                      if (!goal.isDeleted)
                        for (final task in goal.tasks)
                          if (!task.isDeleted &&
                              !task.isComplete &&
                              _matchesFilter(task))
                            (goal: goal, task: task),
                  ];
                  if (entries.isEmpty) {
                    return const Center(child: Text('当前筛选下没有可开始的任务。'));
                  }
                  return ListView.builder(
                    key: const PageStorageKey('focus-task-picker-list'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final task = entry.task;
                      final estimate = task.estimatedMinutes == null
                          ? '未设置'
                          : '${task.estimatedMinutes} 分钟';
                      return Card(
                        child: ListTile(
                          title: Text(task.title),
                          subtitle: Text(
                            '目标：${entry.goal.title} · ${task.classification.label} · '
                            '预计时长：$estimate · 已专注 ${formatEffectiveDuration(task.focusProgressSeconds)}',
                          ),
                          onTap: () => _showSetup(task),
                          trailing: Tooltip(
                            message: '开始任务：${task.title}',
                            child: FilledButton.tonal(
                              onPressed: () => _showSetup(task),
                              child: const Text('开始'),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

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

  Future<void> _showSetup(Task task) async {
    if (_openingSetup) return;
    _openingSetup = true;
    try {
      final repository = ref.read(focusRepositoryProvider);
      final activeSession = await repository.getActiveSession();
      final activeAppointment = activeSession == null
          ? await repository.getActiveAppointment()
          : null;
      if (!mounted) return;
      final result =
          activeSession ??
          activeAppointment ??
          await showDialog<Object>(
            context: context,
            builder: (_) => FocusSetupDialog(
              task: task,
              initialMode: _initialFocusModeFor(
                task.classification,
                widget.initialMode,
              ),
            ),
          );
      if (mounted && result != null) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) _showFocusError(context, error);
    } finally {
      _openingSetup = false;
    }
  }
}

FocusChainMode _initialFocusModeFor(
  TaskClassification classification,
  FocusChainMode fallbackMode,
) => switch (classification) {
  TaskClassification.elite => FocusChainMode.elite,
  TaskClassification.regular => FocusChainMode.regular,
  TaskClassification.both => fallbackMode,
};

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

class FocusHistoryPage extends ConsumerStatefulWidget {
  const FocusHistoryPage({super.key});

  @override
  ConsumerState<FocusHistoryPage> createState() => _FocusHistoryPageState();
}

class _FocusHistoryPageState extends ConsumerState<FocusHistoryPage> {
  FocusRepository? _nodesRepository;
  String? _nodesSessionSignature;
  late Future<List<FocusNode>> _nodesFuture;

  @override
  void initState() {
    super.initState();
    _loadNodes(ref.read(focusRepositoryProvider));
  }

  void _loadNodes(FocusRepository repository) {
    _nodesRepository = repository;
    _nodesSessionSignature = null;
    _nodesFuture = repository.getNodes();
  }

  void _refreshNodesForSessions(
    FocusRepository repository,
    List<FocusSession> sessions,
  ) {
    final signature = sessions.map((session) => session.id).join('|');
    if (!identical(_nodesRepository, repository) ||
        _nodesSessionSignature != signature) {
      _nodesRepository = repository;
      _nodesSessionSignature = signature;
      _nodesFuture = repository.getNodes();
    }
  }

  void _reloadNodes(FocusRepository repository) {
    if (!mounted) return;
    setState(() {
      _nodesFuture = repository.getNodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(focusRepositoryProvider);
    if (!identical(_nodesRepository, repository)) _loadNodes(repository);
    final taskRepository = ref.watch(taskRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('专注历史')),
      body: StreamBuilder<List<Goal>>(
        stream: taskRepository.watchGoals(includeDeleted: true),
        builder: (context, goalsSnapshot) {
          if (goalsSnapshot.hasError) {
            return const Center(child: Text('暂时无法读取任务名称。'));
          }
          if (!goalsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final taskTitles = <String, String>{
            for (final goal in goalsSnapshot.data!)
              for (final task in goal.tasks) task.id: _taskDisplayTitle(task),
          };
          return StreamBuilder<List<FocusSession>>(
            stream: repository.watchSessions(),
            builder: (context, sessionsSnapshot) {
              if (sessionsSnapshot.hasError) {
                return const Center(child: Text('暂时无法读取专注历史。'));
              }
              if (!sessionsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final sessions = sessionsSnapshot.data!
                  .where((session) => !session.isUnfinished)
                  .toList();
              _refreshNodesForSessions(repository, sessions);
              if (sessions.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('完成或结束专注后，记录会显示在这里。'),
                  ),
                );
              }
              return FutureBuilder<List<FocusNode>>(
                future: _nodesFuture,
                builder: (context, nodesSnapshot) => _FocusHistoryList(
                  repository: repository,
                  sessions: sessions,
                  nodes: nodesSnapshot.data ?? const [],
                  taskTitles: taskTitles,
                  nodeError: nodesSnapshot.hasError,
                  onNodeNoteUpdated: () => _reloadNodes(repository),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FocusHistoryList extends StatelessWidget {
  const _FocusHistoryList({
    required this.repository,
    required this.sessions,
    required this.nodes,
    required this.taskTitles,
    required this.nodeError,
    required this.onNodeNoteUpdated,
  });

  final FocusRepository repository;
  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final Map<String, String> taskTitles;
  final bool nodeError;
  final VoidCallback onNodeNoteUpdated;

  @override
  Widget build(BuildContext context) {
    final nodesBySession = {for (final node in nodes) node.sessionId: node};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (nodeError)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('节点备注暂时不可用，专注记录仍可查看。'),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${sessions.length} 次已结算专注',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final session in sessions)
          Card(
            child: ListTile(
              title: Text(taskTitles[session.taskId] ?? '原任务'),
              subtitle: Text(
                session.isFailed
                    ? '失败 · ${formatEffectiveDuration(session.effectiveSeconds)}\n原因：${session.failureReason ?? '未填写'}'
                    : session.isEarlyCompleted
                    ? '获准提前完成 · ${formatEffectiveDuration(session.effectiveSeconds)}\n依据：${session.completionRuleText ?? '未记录'}'
                    : '正常完成 · ${formatEffectiveDuration(session.effectiveSeconds)}',
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
                          onNodeNoteUpdated();
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
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
  final _errorKey = GlobalKey();
  final _durationKey = GlobalKey();
  final _durationFocus = flutter.FocusNode();
  late FocusChainMode _mode;
  late final TextEditingController _duration;
  late final TextEditingController _preparation;
  late int _preparationMinutes;
  late bool _customPreparation;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _durationFocus.addListener(_revealFocusedDuration);
    _mode = widget.initialMode;
    _duration = TextEditingController(text: '25');
    _preparationMinutes = AppointmentPreparationDuration.defaultMinutes;
    _customPreparation = false;
    _preparation = TextEditingController(text: '$_preparationMinutes');
  }

  @override
  void dispose() {
    _durationFocus.dispose();
    _duration.dispose();
    _preparation.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      _showDurationError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // The first focus flow is a real user action that relies on the reminder
    // notification, so this is where the permission is requested once.
    unawaited(
      ref
          .read(focusNotificationServiceProvider)
          .ensureNotificationPermissionForUse(),
    );
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

  /// 本场准备时长；自定义非法时返回 null，由界面就地拒绝而不是截断。
  Duration? _resolvedPreparation() {
    if (!_customPreparation) {
      return AppointmentPreparationDuration.validateMinutes(
        _preparationMinutes,
      );
    }
    final minutes = int.tryParse(_preparation.text.trim());
    if (minutes == null) return null;
    try {
      return AppointmentPreparationDuration.validateMinutes(minutes);
    } on ArgumentError {
      return null;
    }
  }

  String get _preparationButtonLabel {
    final preparation = _resolvedPreparation();
    if (preparation == null) return '开始准备（自定义）';
    return '开始准备（${preparation.inMinutes}分钟）';
  }

  void _showPreparationError() {
    setState(() => _error = AppointmentPreparationDuration.invalidMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _errorKey.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  Future<void> _startAppointment() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      _showDurationError();
      return;
    }
    final preparation = _resolvedPreparation();
    if (preparation == null) {
      _showPreparationError();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    unawaited(
      ref
          .read(focusNotificationServiceProvider)
          .ensureNotificationPermissionForUse(),
    );
    try {
      final appointment = await ref
          .read(focusRepositoryProvider)
          .startAppointment(
            taskId: widget.task.id,
            mode: _mode,
            duration: Duration(minutes: minutes),
            preparation: preparation,
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

  void _showDurationError() {
    setState(() => _error = '请输入大于 0 的分钟数。');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _errorKey.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  void _revealFocusedDuration() {
    if (!_durationFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_durationFocus.hasFocus) return;
      final context = _errorKey.currentContext ?? _durationKey.currentContext;
      if (context != null) Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('开始专注'),
    content: NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _revealFocusedDuration();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.task.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<FocusChainMode>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: '专注模式'),
                items: [
                  for (final mode in FocusChainMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _mode = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                key: _durationKey,
                focusNode: _durationFocus,
                controller: _duration,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '时长（分钟）'),
              ),
              const SizedBox(height: 14),
              Text('预约准备时长', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final minutes in AppointmentPreparationDuration.presets)
                    ChoiceChip(
                      label: Text('$minutes 分钟'),
                      selected:
                          !_customPreparation && _preparationMinutes == minutes,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _customPreparation = false;
                              _preparationMinutes = minutes;
                            }),
                    ),
                  ChoiceChip(
                    label: const Text('自定义'),
                    selected: _customPreparation,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _customPreparation = true;
                            _preparation.text = '$_preparationMinutes';
                          }),
                  ),
                ],
              ),
              if (_customPreparation) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _preparation,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '自定义准备时长（分钟）',
                    helperText: '1–60 分钟；超出范围或非整数不会开始预约。',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: _errorKey,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              if (ref.watch(chainSignalsRepositoryProvider)
                  case final repository?) ...[
                ChainSignalInstructions(repository: repository, mode: _mode),
                const SizedBox(height: 10),
              ],
              const Text(
                '触发信号和专注标志由你执行。可立即开始专注，或先按本场准备时长准备；准备结束自动进入专注，无需再次执行专注标志。',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _startAppointment,
        child: Text(_preparationButtonLabel),
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
    final pageRoute = ModalRoute.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(focusRepositoryProvider)
          .cancelAppointment(appointmentId: current.id, failureReason: reason);
      await _syncAppointmentNotification(null);
      if (mounted && pageRoute?.isActive == true) {
        if (pageRoute!.isCurrent) {
          pageRoute.navigator?.pop();
        } else {
          pageRoute.navigator?.removeRoute(pageRoute);
        }
      }
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
    final now = ref.watch(displayClockProvider)().toUtc();
    final preparationSeconds = appointment.effectivePreparationSeconds;
    final remainingSeconds = appointment.isActive
        ? appointment.endsAt
              .difference(now)
              .inSeconds
              .clamp(0, preparationSeconds)
        : 0;
    final progress = preparationSeconds <= 0
        ? 0.0
        : 1 - (remainingSeconds / preparationSeconds);
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
                    ? '本场准备 ${AppointmentPreparationDuration.describe(preparationSeconds)}，结束后自动进入专注，不需要再次点击或执行专注标志。'
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
                            isExpanded: true,
                            initialValue:
                                tasks.any((task) => task.id == _taskId)
                                ? _taskId
                                : null,
                            decoration: const InputDecoration(labelText: '任务'),
                            items: [
                              for (final task in tasks)
                                DropdownMenuItem(
                                  value: task.id,
                                  child: Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                          decoration: const InputDecoration(labelText: '专注模式'),
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
    final now = ref.watch(displayClockProvider)().toUtc();
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
          child: SingleChildScrollView(
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
                    child: const Text('返回上一页'),
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
    final scheduleRepository = ref.watch(scheduleRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('我的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        MyProfileCard(
          repository: ref.watch(profileRepositoryProvider),
          overview: ref.watch(profileOverviewSourceProvider),
          avatarPicker: ref.watch(avatarPickerProvider),
          accountIdentifier: repository.currentUserIdentifier,
        ),
        const SizedBox(height: 12),
        CloudSyncCard(
          repository: ref.watch(cloudSnapshotRepositoryProvider),
          versionCheck: ref.watch(cloudVersionCheckProvider),
          autoUpload: ref.watch(cloudAutoUploadCoordinatorProvider),
          focusRepository: ref.watch(focusRepositoryProvider),
          onDownloaded: () async {
            ref.invalidate(taskRepositoryProvider);
            ref.invalidate(focusRepositoryProvider);
            ref.invalidate(nationalFocusRepositoryProvider);
            ref.invalidate(calendarRepositoryProvider);
            await ref
                .read(nationalFocusRepositoryProvider)
                .settleDueCheckpoints();
          },
        ),
        const SizedBox(height: 12),
        NationalFocusAiAnalysisEntry(
          onOpenSync: () => _openAiManualSync(context, ref),
          mcpUrl: ref.watch(nationalFocusMcpUrlProvider),
          repository: ref.watch(nationalFocusAiGrantRepositoryProvider),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('日历块'),
            subtitle: Text(
              Platform.isAndroid ? '选择只读导入的系统日历来源' : '查看 Android 导入的日历',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CalendarSourcesPage(
                  repository: calendarRepository,
                  isAndroid: Platform.isAndroid,
                  scheduleRepository: scheduleRepository,
                  displayTimeZoneIdLoader: () =>
                      resolveAccountDisplayTimeZoneId(
                        ref.read(profileRepositoryProvider),
                      ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('提醒与通知'),
            subtitle: const Text('专注、国策与每日打开提醒；仅本机生效'),
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
        const _FocusReconciliationPageLink(),
        const SizedBox(height: 12),
        FutureBuilder<bool>(
          future: _isAdministrator,
          builder: (context, snapshot) => snapshot.data == true
              ? Card(
                  key: const ValueKey('admin-users-entry'),
                  child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('用户管理'),
                    subtitle: const Text('注册资格、用户状态与密码重置'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminUsersPage(),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final userId = ref.read(authRepositoryProvider).currentUserId;
            // 明确登出才取消已登记的提醒；正常关应用保留未来项。
            await ref
                .read(focusNotificationServiceProvider)
                .releaseUser(userId);
            await ref.read(authRepositoryProvider).signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
        const SizedBox(height: 12),
        Text(
          '本应用使用 MiSans 字体',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  AuthRepository? _checkedRepository;
  late Future<bool> _isAdministrator;

  @override
  void initState() {
    super.initState();
    _checkAdministrator(ref.read(authRepositoryProvider));
  }

  void _checkAdministrator(AuthRepository repository) {
    _checkedRepository = repository;
    _isAdministrator = repository.isAdministrator();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    if (!identical(_checkedRepository, repository)) {
      _checkAdministrator(repository);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('用户管理')),
      body: FutureBuilder<bool>(
        future: _isAdministrator,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法确认管理员身份。'),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _checkAdministrator(repository)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.data != true) {
            return const Center(child: Text('仅管理员可访问用户管理。'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(
                '注册资格、用户状态与密码重置',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              AdminUserLifecycleCard(repository: repository),
              const SizedBox(height: 12),
              const AdminEligibilityCard(),
              const SizedBox(height: 12),
              AdminPasswordResetCard(repository: repository),
            ],
          );
        },
      ),
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

void _openAiManualSync(BuildContext context, WidgetRef ref) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('手动同步')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('选择上传本机，并在现有预览中核对整份覆盖范围。仅进入本页不会上传或下载。'),
              const SizedBox(height: 12),
              CloudSyncCard(
                repository: ref.read(cloudSnapshotRepositoryProvider),
                versionCheck: ref.read(cloudVersionCheckProvider),
                autoUpload: ref.read(cloudAutoUploadCoordinatorProvider),
                onDownloaded: () async {
                  ref.invalidate(taskRepositoryProvider);
                  ref.invalidate(focusRepositoryProvider);
                  ref.invalidate(nationalFocusRepositoryProvider);
                  ref.invalidate(calendarRepositoryProvider);
                  await ref
                      .read(nationalFocusRepositoryProvider)
                      .settleDueCheckpoints();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
