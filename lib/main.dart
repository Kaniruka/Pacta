import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/app/app_configuration.dart';
import 'package:pacta/app/pacta_app.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/auth/auth_state.dart';
import 'package:pacta/auth/supabase_auth_session.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:pacta/private_data/connectivity_monitor.dart';
import 'package:pacta/private_data/offline_first_private_data_store.dart';
import 'package:pacta/private_data/private_data_state.dart';
import 'package:pacta/private_data/profile_cache.dart';
import 'package:pacta/private_data/remote_profile_source.dart';
import 'package:pacta/private_data/supabase_profile_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const configuration = AppConfiguration.fromEnvironment();
  AuthSession authSession = const UnconfiguredAuthSession();
  RemoteProfileSource remoteProfiles = const UnavailableRemoteProfileSource();

  if (configuration.hasSupabase) {
    await Supabase.initialize(
      url: configuration.supabaseUrl,
      publishableKey: configuration.publishableKey,
    );
    final client = Supabase.instance.client;
    authSession = SupabaseAuthSession(client);
    remoteProfiles = SupabaseProfileSource(client);
  }

  final database = AppDatabase.defaults();
  final privateDataStore = OfflineFirstPrivateDataStore(
    cache: DriftProfileCache(database),
    remote: remoteProfiles,
  );
  final connectivity = ConnectivityMonitor();

  runApp(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWithValue(authSession),
        privateDataStoreProvider.overrideWithValue(privateDataStore),
        syncRetryTriggersProvider.overrideWithValue(connectivity.retryTriggers),
      ],
      child: const PactaApp(),
    ),
  );
}
