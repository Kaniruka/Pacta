import 'dart:async';

import 'package:http/http.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/remote_profile_source.dart';
import 'package:pacta/private_data/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileSource implements RemoteProfileSource {
  SupabaseProfileSource(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile?> fetch(AppUserId userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('user_id, display_name, updated_at')
          .eq('user_id', userId.value)
          .maybeSingle();
      if (row == null) return null;

      return UserProfile(
        userId: AppUserId(row['user_id'] as String),
        displayName: row['display_name'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      );
    } on ClientException catch (error) {
      throw RemoteProfileUnavailable(error);
    } on TimeoutException catch (error) {
      throw RemoteProfileUnavailable(error);
    }
  }
}
