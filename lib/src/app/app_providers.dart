import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../auth/auth_repository.dart';
import '../auth/supabase_auth_repository.dart';
import '../auth/user_lifecycle.dart';
import '../calendar/calendar_repository.dart';
import '../focus/chain_signals_repository.dart';
import '../focus/focus_repository.dart';
import '../focus/focus_time_zones.dart';
import '../national_focus/national_focus_ai_access.dart';
import '../national_focus/national_focus_repository.dart';
import '../notifications/focus_notification_service.dart';
import '../notifications/schedule_reminder_plan.dart';
import '../profile/account_time_zone.dart';
import '../profile/avatar_picker.dart';
import '../profile/profile_overview.dart';
import '../profile/profile_repository.dart';
import '../schedules/schedule_repository.dart';
import '../sync/cloud_auto_upload.dart';
import '../sync/cloud_auto_upload_preference.dart';
import '../sync/cloud_auto_upload_queue.dart';
import '../sync/cloud_snapshot_repository.dart';
import '../sync/cloud_version_check.dart';
import '../tasks/task_repository.dart';

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
