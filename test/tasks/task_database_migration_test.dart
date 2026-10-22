import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  test(
    'schema 24 upgrade preserves goal and task records without descriptions',
    () async {
      final timestamp = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      final database = PactaDatabase(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase.execute('''
            CREATE TABLE local_goals (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              title TEXT NOT NULL,
              classification TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              PRIMARY KEY (user_id, id)
            )
          ''');
            rawDatabase.execute('''
            CREATE TABLE local_tasks (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              goal_id TEXT NOT NULL,
              title TEXT NOT NULL,
              classification TEXT NOT NULL,
              estimated_minutes INTEGER,
              deadline INTEGER,
              is_complete INTEGER NOT NULL DEFAULT 0,
              focus_progress_seconds INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              PRIMARY KEY (user_id, id)
            )
          ''');
            rawDatabase.execute(
              '''
              INSERT INTO local_goals
                (user_id, id, title, classification, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?)
            ''',
              ['user-a', 'goal-1', '保留的目标', 'regular', timestamp, timestamp],
            );
            rawDatabase.execute(
              '''
              INSERT INTO local_tasks
                (user_id, id, goal_id, title, classification,
                 created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
              [
                'user-a',
                'task-1',
                'goal-1',
                '保留的任务',
                'both',
                timestamp,
                timestamp,
              ],
            );
            rawDatabase.execute('PRAGMA user_version = 24');
          },
        ),
      );

      try {
        final repository = LocalTaskRepository(
          database: database,
          userId: 'user-a',
          remote: UnavailableTaskRemoteDataSource(),
        );
        final goal = (await repository.getGoals()).single;

        expect(goal.title, '保留的目标');
        expect(goal.description, isEmpty);
        expect(goal.tasks.single.title, '保留的任务');
        expect(goal.tasks.single.description, isEmpty);
        await repository.dispose();
      } finally {
        await database.close();
      }
    },
  );
}
