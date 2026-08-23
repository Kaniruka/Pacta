import 'package:flutter/foundation.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/profile_cache.dart';
import 'package:pacta/private_data/remote_profile_source.dart';
import 'package:pacta/private_data/user_profile.dart';

@immutable
class PrivateDataBootstrap {
  const PrivateDataBootstrap({required this.profile, required this.isOffline});

  final UserProfile? profile;
  final bool isOffline;
}

abstract interface class PrivateDataStore {
  Future<PrivateDataBootstrap> bootstrap(AppUserId userId);
}

class OfflineFirstPrivateDataStore implements PrivateDataStore {
  OfflineFirstPrivateDataStore({
    required ProfileCache cache,
    required RemoteProfileSource remote,
  }) : _cache = cache,
       _remote = remote;

  final ProfileCache _cache;
  final RemoteProfileSource _remote;

  @override
  Future<PrivateDataBootstrap> bootstrap(AppUserId userId) async {
    final cachedProfile = await _cache.read(userId);

    try {
      final remoteProfile = await _remote.fetch(userId);
      if (remoteProfile != null && remoteProfile.userId != userId) {
        throw StateError('Remote profile does not belong to the current User.');
      }
      if (remoteProfile != null) await _cache.write(remoteProfile);
      return PrivateDataBootstrap(
        profile: remoteProfile ?? cachedProfile,
        isOffline: false,
      );
    } on RemoteProfileUnavailable {
      return PrivateDataBootstrap(profile: cachedProfile, isOffline: true);
    }
  }
}
