import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('CachedProfileRow')
class CachedProfiles extends Table {
  TextColumn get userId => text()();

  TextColumn get displayName => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

@DataClassName('CachedGoalRow')
class CachedGoals extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get title => text()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get mutationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id, userId};

  @override
  List<String> get customConstraints => ['CHECK (length(trim(title)) > 0)'];
}

@DataClassName('CachedTaskRow')
class CachedTasks extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get goalId => text()();

  TextColumn get title => text()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get deadline => dateTime().nullable()();

  IntColumn get estimatedSeconds => integer().nullable()();

  TextColumn get classification => text()();

  IntColumn get focusProgressSeconds =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get completedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get mutationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id, userId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (user_id, goal_id) REFERENCES cached_goals (user_id, id) ON DELETE CASCADE',
    "CHECK (length(trim(title)) > 0)",
    "CHECK (classification IN ('elite', 'regular', 'both'))",
    'CHECK (estimated_seconds IS NULL OR estimated_seconds > 0)',
    'CHECK (focus_progress_seconds >= 0)',
  ];
}

@DataClassName('GoalTaskOutboxRow')
class GoalTaskOutbox extends Table {
  TextColumn get userId => text()();

  TextColumn get entityType => text()();

  TextColumn get entityId => text()();

  TextColumn get mutationId => text()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, entityType, entityId};

  @override
  List<String> get customConstraints => [
    "CHECK (entity_type IN ('goal', 'task'))",
  ];
}

@DriftDatabase(
  tables: [CachedProfiles, CachedGoals, CachedTasks, GoalTaskOutbox],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults()
    : super(
        driftDatabase(
          name: 'pacta_private',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.createTable(cachedGoals);
        await migrator.createTable(cachedTasks);
        await migrator.createTable(goalTaskOutbox);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
