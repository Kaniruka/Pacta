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

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
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
    TaskSyncEntries,
    FocusSessions,
    FocusNodes,
    FocusChainRecords,
    FocusPreferences,
    FocusPrecedentRules,
    FocusAppointments,
    AppointmentChainRecords,
  ],
)
class PactaDatabase extends _$PactaDatabase {
  PactaDatabase(super.e);

  factory PactaDatabase.open() => PactaDatabase(driftDatabase(name: 'pacta'));

  @override
  int get schemaVersion => 6;

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
    },
  );
}
