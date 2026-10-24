import 'package:flutter/foundation.dart';

import 'cloud_snapshot_repository.dart';

/// Read-only discovery state for one signed-in user's AppShell lifetime.
class CloudVersionCheck extends ChangeNotifier {
  CloudVersionCheck({
    required this.repository,
    required this.now,
    required this.canAccess,
    required this.isAccessible,
  });

  final CloudSnapshotRepository repository;
  final DateTime Function() now;
  final Future<bool> Function() canAccess;
  final Future<bool> Function() isAccessible;
  int _generation = 0;
  DateTime? _lastAttempt;
  bool _disposed = false;
  bool checking = false;
  bool failed = false;
  bool hasPendingVersion = false;
  CloudSnapshotMetadata? metadata;

  Future<void> check({bool force = false}) async {
    if (_disposed || checking) return;
    final instant = now();
    if (!force &&
        _lastAttempt != null &&
        instant.difference(_lastAttempt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastAttempt = instant;
    final generation = _generation;
    checking = true;
    failed = false;
    notifyListeners();
    try {
      if (!await canAccess()) {
        if (!_disposed) {
          hasPendingVersion = false;
          metadata = null;
        }
        return;
      }
      final cloud = await repository.inspectCloud();
      final handled = await repository.loadSyncResult();
      final accessible = await isAccessible();
      if (_disposed || generation != _generation || !accessible) return;
      metadata = cloud;
      hasPendingVersion =
          cloud != null &&
          (cloud.isLegacy
              ? handled?.legacyToken != cloud.legacyToken
              : handled?.cloudRevision != cloud.revision ||
                    handled?.legacyToken != null);
    } catch (_) {
      if (_disposed || generation != _generation) return;
      failed = true;
    } finally {
      if (!_disposed) {
        checking = false;
        notifyListeners();
      }
    }
  }

  void handled() {
    if (_disposed) return;
    _generation++;
    metadata = null;
    hasPendingVersion = false;
    failed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
