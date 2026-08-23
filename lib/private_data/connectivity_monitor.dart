import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityMonitor {
  ConnectivityMonitor({
    Connectivity? connectivity,
    this.retryInterval = const Duration(seconds: 30),
  }) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final Duration retryInterval;

  Stream<bool> get onlineChanges => _connectivity.onConnectivityChanged
      .map(
        (connections) =>
            connections.any((result) => result != ConnectivityResult.none),
      )
      .distinct();

  /// Requests a sync immediately when connectivity returns and periodically
  /// while an interface stays connected. The periodic retry covers captive
  /// portals and transient Supabase failures that do not change interface
  /// connectivity.
  Stream<void> get retryTriggers {
    late final StreamController<void> controller;
    StreamSubscription<bool>? connectivitySubscription;
    Timer? retryTimer;

    controller = StreamController<void>(
      onListen: () {
        connectivitySubscription = onlineChanges
            .where((isOnline) => isOnline)
            .listen(controller.add, onError: controller.addError);
        retryTimer = Timer.periodic(retryInterval, (_) => controller.add(null));
      },
      onCancel: () async {
        retryTimer?.cancel();
        await connectivitySubscription?.cancel();
      },
    );

    return controller.stream;
  }
}
