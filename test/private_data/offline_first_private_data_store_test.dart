import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/offline_first_private_data_store.dart';
import 'package:pacta/private_data/profile_cache.dart';
import 'package:pacta/private_data/remote_profile_source.dart';
import 'package:pacta/private_data/user_profile.dart';

void main() {
  test(
    'reopens from cache offline and synchronizes when remote returns',
    () async {
      const userId = AppUserId('user-a');
      final cached = UserProfile(
        userId: userId,
        displayName: 'Cached name',
        updatedAt: DateTime.utc(2026, 8, 23),
      );
      final remote = UserProfile(
        userId: userId,
        displayName: 'Fresh name',
        updatedAt: DateTime.utc(2026, 8, 24),
      );
      final cache = _MemoryProfileCache()..profiles[userId] = cached;
      final source = _ControllableRemoteProfileSource()
        ..failure = const RemoteProfileUnavailable('offline');
      final store = OfflineFirstPrivateDataStore(cache: cache, remote: source);

      final offlineBootstrap = await store.bootstrap(userId);

      expect(offlineBootstrap.profile, cached);
      expect(offlineBootstrap.isOffline, isTrue);

      source
        ..failure = null
        ..profile = remote;
      final synchronizedBootstrap = await store.bootstrap(userId);

      expect(synchronizedBootstrap.profile, remote);
      expect(synchronizedBootstrap.isOffline, isFalse);
      expect(await cache.read(userId), remote);
      expect(source.requestedUsers, [userId, userId]);
    },
  );
}

class _MemoryProfileCache implements ProfileCache {
  final profiles = <AppUserId, UserProfile>{};

  @override
  Future<UserProfile?> read(AppUserId userId) async => profiles[userId];

  @override
  Future<void> write(UserProfile profile) async {
    profiles[profile.userId] = profile;
  }
}

class _ControllableRemoteProfileSource implements RemoteProfileSource {
  final requestedUsers = <AppUserId>[];
  Object? failure;
  UserProfile? profile;

  @override
  Future<UserProfile?> fetch(AppUserId userId) async {
    requestedUsers.add(userId);
    if (failure case final failure?) throw failure;
    return profile;
  }
}
