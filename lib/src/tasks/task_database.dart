import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'task_database.g.dart';

class LocalGoals extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get classification => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalTasks extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  TextColumn get title => text()();
  TextColumn get classification => text()();
  IntColumn get estimatedMinutes => integer().nullable()();
  DateTimeColumn get deadline => dateTime().nullable()();
  BoolColumn get isComplete => boolean().withDefault(const Constant(false))();
  IntColumn get focusProgressSeconds =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalNationalFocusCards extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get triggerCondition => text()();
  TextColumn get action => text()();
  TextColumn get scope => text().nullable()();
  TextColumn get exceptionNotes => text().nullable()();
  BoolColumn get isInTree => boolean().withDefault(const Constant(false))();
  TextColumn get parentId => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('extinguished'))();
  IntColumn get successfulDays => integer().withDefault(const Constant(0))();
  IntColumn get currentConsecutiveDays =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestConsecutiveDays =>
      integer().withDefault(const Constant(0))();
  BoolColumn get maintenanceCycleStarted =>
      boolean().withDefault(const Constant(false))();
  TextColumn get failureReason => text().nullable()();
  TextColumn get cascadeSourceCardId => text().nullable()();
  TextColumn get cascadePriorState => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class LocalNationalFocusMaintenance extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get lastSettledCheckpointAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class LocalNationalFocusFailures extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get batchId => text()();
  TextColumn get cardId => text()();
  DateTimeColumn get checkpointAt => dateTime()();
  TextColumn get cause => text()();
  TextColumn get failureReason => text().nullable()();
  TextColumn get sharedExplanation => text().nullable()();
  TextColumn get treeSnapshot => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusSessions extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get appointmentId => text().nullable()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  IntColumn get durationSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get effectiveSeconds => integer().withDefault(const Constant(0))();
  TextColumn get completionType =>
      text().withDefault(const Constant('countdown'))();
  TextColumn get completionRuleText => text().nullable()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
  IntColumn get pausedSeconds => integer().withDefault(const Constant(0))();
  TextColumn get pauseRuleText => text().nullable()();
  TextColumn get failureReason => text().nullable()();
  TextColumn get effectiveIntervals =>
      text().withDefault(const Constant('[]'))();
  TextColumn get reviewDisposition =>
      text().withDefault(const Constant('accepted'))();
  DateTimeColumn get reviewDispositionUpdatedAt => dateTime().nullable()();
  TextColumn get configurationBasisSourceId => text().nullable()();
  TextColumn get outcomeBasisSourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusAppointments extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  IntColumn get durationSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get settledAt => dateTime().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get reviewDisposition =>
      text().withDefault(const Constant('accepted'))();
  DateTimeColumn get reviewDispositionUpdatedAt => dateTime().nullable()();
  TextColumn get configurationBasisSourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusSourceDevices extends Table {
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusSyncSources extends Table {
  TextColumn get userId => text()();
  TextColumn get sourceId => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get parentSourceId => text().nullable()();
  TextColumn get parentSourceIds => text().withDefault(const Constant('[]'))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, sourceId};
}

class AppointmentChainRecords extends Table {
  TextColumn get userId => text()();
  IntColumn get currentConsecutive =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestConsecutive => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusNodes extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get effectiveSeconds => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusChainRecords extends Table {
  TextColumn get userId => text()();
  TextColumn get mode => text()();
  IntColumn get currentConsecutive =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestConsecutive => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, mode};
}

class FocusPreferences extends Table {
  TextColumn get userId => text()();
  TextColumn get lastMode => text()();
  TextColumn get displayTimeZoneId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class FocusPrecedentRules extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get ruleText => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class TaskSyncEntries extends Table {
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, entityType, entityId};
}

@DriftDatabase(
  tables: [
    LocalGoals,
    LocalTasks,
    LocalNationalFocusCards,
    LocalNationalFocusMaintenance,
    LocalNationalFocusFailures,
    TaskSyncEntries,
    FocusSessions,
    FocusNodes,
    FocusChainRecords,
    FocusPreferences,
    FocusPrecedentRules,
    FocusAppointments,
    AppointmentChainRecords,
    FocusSourceDevices,
    FocusSyncSources,
  ],
)
class PactaDatabase extends _$PactaDatabase {
  PactaDatabase(super.e);

  factory PactaDatabase.open() => PactaDatabase(driftDatabase(name: 'pacta'));

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(localTasks, localTasks.focusProgressSeconds);
        await m.createTable(focusSessions);
        await m.createTable(focusNodes);
        await m.createTable(focusChainRecords);
        await m.createTable(focusPreferences);
      }
      if (from < 3) {
        await m.addColumn(focusSessions, focusSessions.pausedAt);
        await m.addColumn(focusSessions, focusSessions.pausedSeconds);
        await m.addColumn(focusSessions, focusSessions.failureReason);
        await m.addColumn(focusNodes, focusNodes.note);
      }
      if (from < 4) {
        await m.addColumn(focusSessions, focusSessions.pauseRuleText);
      }
      if (from < 5) {
        await m.addColumn(focusSessions, focusSessions.completionType);
        await m.addColumn(focusSessions, focusSessions.completionRuleText);
        await m.createTable(focusPrecedentRules);
      }
      if (from < 6) {
        await m.addColumn(focusSessions, focusSessions.appointmentId);
        await m.createTable(focusAppointments);
        await m.createTable(appointmentChainRecords);
      }
      if (from < 7) {
        await m.addColumn(focusSessions, focusSessions.effectiveIntervals);
        await m.addColumn(focusSessions, focusSessions.reviewDisposition);
        await m.addColumn(
          focusSessions,
          focusSessions.reviewDispositionUpdatedAt,
        );
        await m.addColumn(focusPreferences, focusPreferences.displayTimeZoneId);
      }
      if (from < 8) {
        await m.addColumn(localGoals, localGoals.deletedAt);
        await m.addColumn(localTasks, localTasks.deletedAt);
      }
      if (from < 9) {
        await m.createTable(focusSourceDevices);
        await m.createTable(focusSyncSources);
      }
      if (from < 10) {
        await m.addColumn(
          focusAppointments,
          focusAppointments.reviewDisposition,
        );
        await m.addColumn(
          focusAppointments,
          focusAppointments.reviewDispositionUpdatedAt,
        );
      }
      if (from < 11) {
        await m.addColumn(
          focusAppointments,
          focusAppointments.configurationBasisSourceId,
        );
      }
      if (from < 12) {
        await m.addColumn(
          focusSessions,
          focusSessions.configurationBasisSourceId,
        );
        await m.addColumn(focusSessions, focusSessions.outcomeBasisSourceId);
        await m.addColumn(focusSyncSources, focusSyncSources.parentSourceIds);
      }
      if (from < 13) {
        await m.createTable(localNationalFocusCards);
      }
      if (from < 14) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.successfulDays,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.currentConsecutiveDays,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.bestConsecutiveDays,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.maintenanceCycleStarted,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.failureReason,
        );
        await m.createTable(localNationalFocusMaintenance);
        await m.createTable(localNationalFocusFailures);
      }
      if (from < 15) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.cascadeSourceCardId,
        );
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.cascadePriorState,
        );
        await _cascadeLegacyActiveDescendants(this);
      }
      if (from < 16) {
        await m.addColumn(
          localNationalFocusCards,
          localNationalFocusCards.deletedAt,
        );
      }
    },
  );
}

Future<void> _cascadeLegacyActiveDescendants(PactaDatabase database) async {
  final cards = await (database.select(
    database.localNationalFocusCards,
  )..where((card) => card.isInTree.equals(true))).get();
  final failures = await database
      .select(database.localNationalFocusFailures)
      .get();
  final latestFailureByCard = <String, Map<String, DateTime>>{};
  for (final failure in failures) {
    final userFailures = latestFailureByCard.putIfAbsent(
      failure.userId,
      () => {},
    );
    final previous = userFailures[failure.cardId];
    if (previous == null || failure.checkpointAt.isAfter(previous)) {
      userFailures[failure.cardId] = failure.checkpointAt;
    }
  }
  final cardsByUser = <String, Map<String, LocalNationalFocusCard>>{};
  for (final card in cards) {
    cardsByUser.putIfAbsent(card.userId, () => {})[card.id] = card;
  }

  for (final card in cards) {
    if (card.state != 'lit' && card.state != 'pending_today_confirmation') {
      continue;
    }

    final userCards = cardsByUser[card.userId]!;
    final visited = <String>{card.id};
    var ancestorId = card.parentId;
    String? sourceCardId;
    LocalNationalFocusCard? sourceCard;
    while (ancestorId != null && visited.add(ancestorId)) {
      final ancestor = userCards[ancestorId];
      if (ancestor == null) break;
      if (ancestor.state == 'extinguished') {
        sourceCardId = ancestor.id;
        sourceCard = ancestor;
        break;
      }
      ancestorId = ancestor.parentId;
    }
    if (sourceCardId == null) continue;

    final sourceFailureAt = latestFailureByCard[card.userId]?[sourceCardId];
    final sourceFailureWasSettled =
        sourceFailureAt != null && !sourceCard!.maintenanceCycleStarted;

    await (database.update(database.localNationalFocusCards)
          ..where((candidate) => candidate.userId.equals(card.userId))
          ..where((candidate) => candidate.id.equals(card.id)))
        .write(
          LocalNationalFocusCardsCompanion(
            state: const Value('extinguished'),
            currentConsecutiveDays: Value(
              sourceFailureWasSettled ? 0 : card.currentConsecutiveDays,
            ),
            maintenanceCycleStarted: Value(
              sourceFailureWasSettled ? false : card.maintenanceCycleStarted,
            ),
            failureReason: const Value(null),
            cascadeSourceCardId: Value(sourceCardId),
            cascadePriorState: Value(
              sourceFailureWasSettled ? 'lit' : card.state,
            ),
          ),
        );
  }
}
