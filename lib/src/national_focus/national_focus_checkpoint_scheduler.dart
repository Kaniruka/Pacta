import 'dart:async';

import 'national_focus_checkpoints.dart';

/// Refreshes due National Focus checkpoints while the app stays in foreground.
class NationalFocusCheckpointScheduler {
  NationalFocusCheckpointScheduler({
    required this.settleDueCheckpoints,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<void> Function() settleDueCheckpoints;
  final DateTime Function() _now;
  Timer? _timer;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    _scheduleNextCheckpoint();
  }

  void _scheduleNextCheckpoint() {
    final now = _now().toUtc();
    final next = nextNationalFocusCheckpoint(now);
    _timer = Timer(next.difference(now), () {
      _timer = null;
      unawaited(_settleAndReschedule());
    });
  }

  Future<void> _settleAndReschedule() async {
    try {
      await settleDueCheckpoints();
    } catch (_) {
      // Resume and the next checkpoint provide another chance to settle.
    }
    if (!_disposed) _scheduleNextCheckpoint();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
