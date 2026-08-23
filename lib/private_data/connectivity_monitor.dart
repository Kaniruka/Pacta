import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityMonitor {
  ConnectivityMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onlineChanges => _connectivity.onConnectivityChanged
      .map(
        (connections) =>
            connections.any((result) => result != ConnectivityResult.none),
      )
      .distinct();
}
