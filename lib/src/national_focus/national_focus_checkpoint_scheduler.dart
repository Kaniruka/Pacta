import 'dart:async';

import '../profile/account_time_zone.dart';
import 'national_focus_checkpoints.dart';

/// Refreshes due National Focus checkpoints while the app stays in foreground.
///
/// 检查点按账号时区当地 04:00 结算，因此排程前先问一次账号时区；读不到时
/// 沿用北京时间的旧行为，绝不让一次读失败停掉倒计时。
class NationalFocusCheckpointScheduler {
  NationalFocusCheckpointScheduler({
    required this.settleDueCheckpoints,
    DateTime Function()? now,
    this.timeZoneIdReader,
  }) : _now = now ?? DateTime.now;

  final Future<void> Function() settleDueCheckpoints;
  final DateTime Function() _now;
  final Future<String> Function()? timeZoneIdReader;
  Timer? _timer;
  bool _scheduling = false;
  bool _rescheduleRequested = false;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null || _scheduling) return;
    _scheduleNextCheckpoint();
  }

  /// 账号显示时区变更等场景下重算下一次 04:00 结算定时器。
  void reschedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (_scheduling) {
      _rescheduleRequested = true;
      return;
    }
    _scheduleNextCheckpoint();
  }

  void _scheduleNextCheckpoint() {
    if (_disposed || _scheduling) return;
    _scheduling = true;
    unawaited(_scheduleNextCheckpointAsync());
  }

  Future<void> _scheduleNextCheckpointAsync() async {
    try {
      final now = _now().toUtc();
      final next = nextNationalFocusCheckpoint(
        now,
        timeZoneId: await _accountTimeZoneId(),
      );
      if (_disposed || _timer != null) return;
      final delay = next.difference(now);
      _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
        _timer = null;
        unawaited(_settleAndReschedule());
      });
    } finally {
      _scheduling = false;
      if (_rescheduleRequested && !_disposed && _timer == null) {
        _rescheduleRequested = false;
        _scheduleNextCheckpoint();
      }
    }
  }

  Future<String> _accountTimeZoneId() async {
    final reader = timeZoneIdReader;
    if (reader == null) return AccountTimeZones.defaultNationalFocusTimeZoneId;
    try {
      return AccountTimeZones.checkpointTimeZoneId(await reader());
    } catch (_) {
      return AccountTimeZones.defaultNationalFocusTimeZoneId;
    }
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
