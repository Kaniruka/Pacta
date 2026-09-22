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
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  IntColumn get durationSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get effectiveSeconds => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};
}

class FocusNodes extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get taskId => text()();
  TextColumn get mode => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get effectiveSeconds => integer()();

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
  ],
)
class PactaDatabase extends _$PactaDatabase {
  PactaDatabase(super.e);

  factory PactaDatabase.open() => PactaDatabase(driftDatabase(name: 'pacta'));

  @override
  int get schemaVersion => 2;

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
    },
  );
}
