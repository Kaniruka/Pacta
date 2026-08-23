import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/offline_first_private_data_store.dart';

final privateDataStoreProvider = Provider<PrivateDataStore>((ref) {
  throw StateError(
    'PrivateDataStore must be configured at the application root.',
  );
});

final syncRetryTriggersProvider = Provider<Stream<void>>((ref) {
  return const Stream.empty();
});

final privateBootstrapProvider =
    StreamProvider.family<PrivateDataBootstrap, AppUserId>((
      ref,
      userId,
    ) async* {
      final store = ref.watch(privateDataStoreProvider);
      yield await store.bootstrap(userId);

      await for (final _ in ref.watch(syncRetryTriggersProvider)) {
        yield await store.bootstrap(userId);
      }
    });
