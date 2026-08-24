import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/app/app_configuration.dart';
import 'package:pacta/app/pacta_app.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/auth/auth_state.dart';
import 'package:pacta/auth/supabase_auth_session.dart';
import 'package:pacta/features/focus_chain/data/drift_focus_session_repository.dart';
import 'package:pacta/features/focus_chain/data/focus_session_state.dart';
import 'package:pacta/features/focus_chain/data/supabase_focus_session_source.dart';
import 'package:pacta/features/goals_tasks/data/goal_task_state.dart';
import 'package:pacta/features/goals_tasks/data/drift_goal_task_repository.dart';
import 'package:pacta/features/goals_tasks/data/supabase_goal_task_source.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_repository.dart';
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
  RemoteGoalTaskSource remoteGoalTasks =
      const UnavailableRemoteGoalTaskSource();
  RemoteFocusSessionSource remoteFocusSessions =
      const UnavailableRemoteFocusSessionSource();

  if (configuration.hasSupabase) {
    await Supabase.initialize(
      url: configuration.supabaseUrl,
      publishableKey: configuration.publishableKey,
    );
    final client = Supabase.instance.client;
    authSession = SupabaseAuthSession(client);
    remoteProfiles = SupabaseProfileSource(client);
    remoteGoalTasks = SupabaseGoalTaskSource(client);
    remoteFocusSessions = SupabaseFocusSessionSource(client);
  }

  final database = AppDatabase.defaults();
  final privateDataStore = OfflineFirstPrivateDataStore(
    cache: DriftProfileCache(database),
    remote: remoteProfiles,
  );
  final goalTaskRepository = DriftGoalTaskRepository(
    database: database,
    remote: remoteGoalTasks,
  );
  final focusSessionRepository = DriftFocusSessionRepository(
    database: database,
    remote: remoteFocusSessions,
  );
  final connectivity = ConnectivityMonitor();

  runApp(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWithValue(authSession),
        privateDataStoreProvider.overrideWithValue(privateDataStore),
        goalTaskRepositoryProvider.overrideWithValue(goalTaskRepository),
        focusSessionRepositoryProvider.overrideWithValue(
          focusSessionRepository,
        ),
        syncRetryTriggersProvider.overrideWithValue(connectivity.retryTriggers),
      ],
      child: const PactaApp(),
    ),
  );
}
