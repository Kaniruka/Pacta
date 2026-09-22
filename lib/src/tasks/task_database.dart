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
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

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

@DriftDatabase(tables: [LocalGoals, LocalTasks, TaskSyncEntries])
class PactaDatabase extends _$PactaDatabase {
  PactaDatabase(super.e);

  factory PactaDatabase.open() => PactaDatabase(driftDatabase(name: 'pacta'));

  @override
  int get schemaVersion => 1;
}
