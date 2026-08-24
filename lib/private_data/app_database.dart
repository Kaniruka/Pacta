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

@DataClassName('FocusSessionRow')
class CachedFocusSessions extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get taskId => text()();

  TextColumn get mode => text()();

  IntColumn get plannedSeconds => integer()();

  DateTimeColumn get startedAt => dateTime()();

  IntColumn get actualElapsedSeconds =>
      integer().withDefault(const Constant(0))();

  TextColumn get outcome => text().nullable()();

  DateTimeColumn get completedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get mutationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id, userId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (user_id, task_id) REFERENCES cached_tasks (user_id, id) ON DELETE CASCADE',
    "CHECK (mode IN ('elite', 'regular'))",
    'CHECK (planned_seconds > 0)',
    'CHECK (actual_elapsed_seconds >= 0 AND actual_elapsed_seconds <= planned_seconds)',
    "CHECK (outcome IS NULL OR outcome = 'completed')",
    "CHECK ((outcome IS NULL AND completed_at IS NULL AND actual_elapsed_seconds = 0) OR (outcome = 'completed' AND completed_at IS NOT NULL AND actual_elapsed_seconds = planned_seconds))",
  ];
}

@DataClassName('FocusNodeRow')
class CachedFocusNodes extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get sessionId => text()();

  TextColumn get taskId => text()();

  TextColumn get mode => text()();

  IntColumn get elapsedSeconds => integer()();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get mutationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id, userId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (user_id, session_id) REFERENCES cached_focus_sessions (user_id, id) ON DELETE CASCADE',
    'FOREIGN KEY (user_id, task_id) REFERENCES cached_tasks (user_id, id) ON DELETE CASCADE',
    'UNIQUE (user_id, session_id)',
    'CHECK (elapsed_seconds > 0)',
    "CHECK (mode IN ('elite', 'regular'))",
  ];
}

@DataClassName('FocusSessionOutboxRow')
class FocusSessionOutbox extends Table {
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
    "CHECK (entity_type IN ('session', 'node'))",
  ];
}

@DriftDatabase(
  tables: [
    CachedProfiles,
    CachedGoals,
    CachedTasks,
    GoalTaskOutbox,
    CachedFocusSessions,
    CachedFocusNodes,
    FocusSessionOutbox,
  ],
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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.createTable(cachedGoals);
        await migrator.createTable(cachedTasks);
        await migrator.createTable(goalTaskOutbox);
      }
      if (from < 3) {
        await migrator.createTable(cachedFocusSessions);
        await migrator.createTable(cachedFocusNodes);
        await migrator.createTable(focusSessionOutbox);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
