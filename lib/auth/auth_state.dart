import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/auth/supabase_auth_session.dart';

final authSessionProvider = Provider<AuthSession>((ref) {
  return const UnconfiguredAuthSession();
});

final authenticatedUserProvider = StreamProvider<AppUserId?>((ref) {
  return ref.watch(authSessionProvider).userChanges;
});
