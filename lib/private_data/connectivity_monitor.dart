import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

class ConnectivityMonitor with WidgetsBindingObserver {
  ConnectivityMonitor({
    Connectivity? connectivity,
    this.retryInterval = const Duration(seconds: 30),
  }) : _connectivity = connectivity ?? Connectivity() {
    WidgetsBinding.instance.addObserver(this);
  }

  final Connectivity _connectivity;
  final Duration retryInterval;
  final _resumeTriggers = StreamController<void>.broadcast();

  Stream<bool> get onlineChanges => _connectivity.onConnectivityChanged
      .map(
        (connections) =>
            connections.any((result) => result != ConnectivityResult.none),
      )
      .distinct();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeTriggers.add(null);
    }
  }

  /// Requests a sync immediately when connectivity returns, the app resumes,
  /// and periodically while an interface stays connected.
  Stream<void> get retryTriggers {
    late final StreamController<void> controller;
    StreamSubscription<bool>? connectivitySubscription;
    StreamSubscription<void>? resumeSubscription;
    Timer? retryTimer;

    controller = StreamController<void>.broadcast(
      onListen: () {
        connectivitySubscription = onlineChanges
            .where((isOnline) => isOnline)
            .listen(controller.add, onError: controller.addError);
        resumeSubscription = _resumeTriggers.stream.listen(controller.add);
        retryTimer = Timer.periodic(retryInterval, (_) => controller.add(null));
      },
      onCancel: () async {
        retryTimer?.cancel();
        await connectivitySubscription?.cancel();
        await resumeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTriggers.close();
  }
}
