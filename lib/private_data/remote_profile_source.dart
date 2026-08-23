import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/user_profile.dart';

abstract interface class RemoteProfileSource {
  Future<UserProfile?> fetch(AppUserId userId);
}

class RemoteProfileUnavailable implements Exception {
  const RemoteProfileUnavailable([this.cause]);

  final Object? cause;

  @override
  String toString() => 'RemoteProfileUnavailable($cause)';
}

class UnavailableRemoteProfileSource implements RemoteProfileSource {
  const UnavailableRemoteProfileSource();

  @override
  Future<UserProfile?> fetch(AppUserId userId) {
    throw const RemoteProfileUnavailable('Supabase is not configured.');
  }
}
