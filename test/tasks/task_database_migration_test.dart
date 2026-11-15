import 'package:drift/drift.dart' show Value;
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

  group('account profile time zone columns', () {
    PactaDatabase openProfileFixture({
      required int version,
      required bool withTimeZone,
      required bool withPendingUpload,
    }) => PactaDatabase(
      NativeDatabase.memory(
        setup: (rawDatabase) {
          final columns = [
            'user_id TEXT NOT NULL PRIMARY KEY',
            "display_name TEXT NOT NULL DEFAULT ''",
            'avatar_mime_type TEXT',
            'avatar_bytes BLOB',
            'pending_save INTEGER NOT NULL DEFAULT 0',
            'sync_error TEXT',
            'updated_at INTEGER NOT NULL',
            'edit_sequence INTEGER NOT NULL DEFAULT 0',
            if (withTimeZone) 'time_zone_id TEXT',
            if (withPendingUpload)
              'pending_time_zone_upload INTEGER NOT NULL DEFAULT 0',
          ];
          rawDatabase.execute(
            'CREATE TABLE local_profile_accounts (${columns.join(', ')})',
          );
          rawDatabase.execute(
            "INSERT INTO local_profile_accounts (user_id, display_name, "
            "updated_at, edit_sequence) VALUES ('user-a', '小林', 1, 3)",
          );
          rawDatabase.execute('PRAGMA user_version = $version');
        },
      ),
    );

    Future<Set<String>> columnNames(PactaDatabase database) async {
      final rows = await database
          .customSelect('PRAGMA table_info(local_profile_accounts)')
          .get();
      return rows.map((row) => row.read<String>('name')).toSet();
    }

    test(
      'schema 29 upgrade adds both time zone columns and keeps the row',
      () async {
        final database = openProfileFixture(
          version: 29,
          withTimeZone: false,
          withPendingUpload: false,
        );
        try {
          final profile = (await database
              .select(database.localProfileAccounts)
              .getSingle());
          expect(profile.displayName, '小林');
          expect(profile.timeZoneId, isNull);
          expect(profile.pendingTimeZoneUpload, isFalse);
          expect(
            await columnNames(database),
            containsAll(<String>['time_zone_id', 'pending_time_zone_upload']),
          );
        } finally {
          await database.close();
        }
      },
    );

    test('provisional schema 30 with the zone column only gains the upload '
        'intent without losing the stored value', () async {
      final database = openProfileFixture(
        version: 30,
        withTimeZone: true,
        withPendingUpload: false,
      );
      try {
        final profile = (await database
            .select(database.localProfileAccounts)
            .getSingle());
        expect(profile.displayName, '小林');
        expect(profile.timeZoneId, isNull);
        expect(profile.pendingTimeZoneUpload, isFalse);
        expect(
          await columnNames(database),
          containsAll(<String>['time_zone_id', 'pending_time_zone_upload']),
        );

        // 迁移后写入的账号值仍可在同一行读取。
        await database
            .update(database.localProfileAccounts)
            .write(
              const LocalProfileAccountsCompanion(
                timeZoneId: Value('Asia/Tokyo'),
              ),
            );
        expect(
          (await database.select(database.localProfileAccounts).getSingle())
              .timeZoneId,
          'Asia/Tokyo',
        );
      } finally {
        await database.close();
      }
    });

    test(
      'schema 31 fixture without either column is upgraded defensively',
      () async {
        final database = openProfileFixture(
          version: 31,
          withTimeZone: false,
          withPendingUpload: false,
        );
        try {
          expect(
            await columnNames(database),
            containsAll(<String>['time_zone_id', 'pending_time_zone_upload']),
          );
          expect(
            (await database.select(database.localProfileAccounts).getSingle())
                .displayName,
            '小林',
          );
        } finally {
          await database.close();
        }
      },
    );
  });
}
