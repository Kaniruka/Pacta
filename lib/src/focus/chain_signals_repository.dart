import 'package:drift/drift.dart';

import '../auth/user_lifecycle.dart';
import '../tasks/task_database.dart' as db;
import 'focus_models.dart';

class ChainSignalTexts {
  const ChainSignalTexts({
    this.appointmentTriggerSignal = '',
    this.eliteFocusMarker = '',
    this.regularFocusMarker = '',
  });

  final String appointmentTriggerSignal;
  final String eliteFocusMarker;
  final String regularFocusMarker;

  String focusMarker(FocusChainMode mode) =>
      mode == FocusChainMode.elite ? eliteFocusMarker : regularFocusMarker;
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

  ChainSignalTexts _texts(db.ChainSignal? row) => row == null
      ? const ChainSignalTexts()
      : ChainSignalTexts(
          appointmentTriggerSignal: row.appointmentTriggerSignal,
          eliteFocusMarker: row.eliteFocusMarker,
          regularFocusMarker: row.regularFocusMarker,
        );

  Future<ChainSignalTexts> get() async =>
      _texts(await _query().getSingleOrNull());

  Stream<ChainSignalTexts> watch() => _query().watchSingleOrNull().map(_texts);

  Future<void> save(ChainSignalTexts texts) async {
    await lifecycleAccess.requireActive();
    await database
        .into(database.chainSignals)
        .insertOnConflictUpdate(
          db.ChainSignalsCompanion.insert(
            userId: userId,
            appointmentTriggerSignal: Value(
              texts.appointmentTriggerSignal.trim(),
            ),
            eliteFocusMarker: Value(texts.eliteFocusMarker.trim()),
            regularFocusMarker: Value(texts.regularFocusMarker.trim()),
            updatedAt: _now(),
          ),
        );
  }
}
