import 'package:drift/drift.dart';

import '../auth/user_lifecycle.dart';
import '../tasks/task_database.dart' as db;

class ChainSignalTexts {
  const ChainSignalTexts({
    this.appointmentTriggerSignal = '',
    this.focusMarker = '',
  });

  /// The commitment action for the single Appointment Chain.
  final String appointmentTriggerSignal;

  /// The single Focus Marker shared by the Elite and Regular Focus Chains.
  ///
  /// The chains keep independent consecutive records; only the commitment
  /// action is shared, so one edited value applies to both launch summaries.
  final String focusMarker;
}

/// User-owned commitment actions, included in whole-data cloud snapshots.
class ChainSignalsRepository {
  ChainSignalsRepository({
    required this.database,
    required this.userId,
    UserLifecycleAccess? lifecycleAccess,
    DateTime Function()? now,
  }) : lifecycleAccess =
           lifecycleAccess ?? const AlwaysActiveUserLifecycleAccess(),
       _now = now ?? DateTime.now;

  final db.PactaDatabase database;
  final String userId;
  final UserLifecycleAccess lifecycleAccess;
  final DateTime Function() _now;

  SimpleSelectStatement<db.ChainSignals, db.ChainSignal> _query() =>
      database.select(database.chainSignals)
        ..where((row) => row.userId.equals(userId));

  /// The shared Focus Marker is stored in both marker columns, so either one
  /// carries the current value; the elite column is the canonical read.
  ChainSignalTexts _texts(db.ChainSignal? row) => row == null
      ? const ChainSignalTexts()
      : ChainSignalTexts(
          appointmentTriggerSignal: row.appointmentTriggerSignal,
          focusMarker: row.eliteFocusMarker,
        );

  Future<ChainSignalTexts> get() async =>
      _texts(await _query().getSingleOrNull());

  Stream<ChainSignalTexts> watch() => _query().watchSingleOrNull().map(_texts);

  Future<void> save(ChainSignalTexts texts) async {
    await lifecycleAccess.requireActive();
    final marker = texts.focusMarker.trim();
    await database
        .into(database.chainSignals)
        .insertOnConflictUpdate(
          db.ChainSignalsCompanion.insert(
            userId: userId,
            appointmentTriggerSignal: Value(
              texts.appointmentTriggerSignal.trim(),
            ),
            // Both existing marker fields hold the same shared Focus Marker.
            eliteFocusMarker: Value(marker),
            regularFocusMarker: Value(marker),
            updatedAt: _now(),
          ),
        );
  }
}
