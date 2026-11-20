import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app/app_providers.dart';
import 'src/auth/auth_repository.dart';
import 'src/auth/auth_screen.dart';
import 'src/auth/supabase_auth_repository.dart';
import 'src/auth/user_lifecycle.dart';
import 'src/calendar/calendar_provider.dart';
import 'src/calendar/calendar_repository.dart';
import 'src/focus/chain_signals_repository.dart';
import 'src/focus/focus_repository.dart';
import 'src/national_focus/national_focus_ai_access.dart';
import 'src/national_focus/national_focus_repository.dart';
import 'src/notifications/focus_notification_service.dart';
import 'src/notifications/schedule_reminder_plan.dart';
import 'src/profile/profile_remote.dart';
import 'src/profile/profile_repository.dart';
import 'src/schedules/schedule_repository.dart';
import 'src/sync/cloud_snapshot_repository.dart';
import 'src/sync/source_device_info.dart';
import 'src/tasks/task_database.dart';
import 'src/tasks/task_repository.dart';
import 'src/theme/pacta_theme.dart';

export 'src/app/app_providers.dart';
export 'src/app/app_shell.dart';
export 'src/auth/auth_screen.dart';
export 'src/board/board_page.dart';
export 'src/focus/focus_chain_page.dart';
export 'src/focus/focus_flow_helpers.dart';
export 'src/focus/focus_session_pages.dart';
export 'src/focus/focus_setup_dialog.dart';
export 'src/plan/goal_task_cards.dart';
export 'src/plan/plan_page.dart';
export 'src/profile/my_page.dart';
export 'src/theme/pacta_theme.dart';
export 'src/ui/pacta_card_header.dart';
export 'src/ui/pacta_date_format.dart';
export 'src/ui/pacta_error_text.dart';
export 'src/ui/pacta_hold_action_reorder.dart';

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
        scrollBehavior: const PactaScrollBehavior(),
        debugShowCheckedModeBanner: false,
        theme: pactaTheme(Brightness.light),
        darkTheme: pactaTheme(Brightness.dark),
        home: UserPurgeCleanupLifecycleObserver(
          cleanupRepository: userPurgeCleanupRepository,
          child: const AuthGate(),
        ),
      ),
    );
  }
}
