import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/tasks/task_database.dart';

const _schedulesAt31 = '''
  CREATE TABLE local_schedules (
    user_id TEXT NOT NULL,
    id TEXT NOT NULL,
    title TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    starts_at INTEGER NOT NULL,
    ends_at INTEGER NOT NULL,
    all_day INTEGER NOT NULL DEFAULT 0,
    all_day_start_date TEXT,
    all_day_end_date_exclusive TEXT,
    is_completed INTEGER NOT NULL DEFAULT 0,
    completed_at INTEGER,
    task_id TEXT,
    reminder_minutes_before INTEGER,
    origin TEXT NOT NULL DEFAULT 'owned',
    source_ids TEXT NOT NULL DEFAULT '[]',
    source_names TEXT NOT NULL DEFAULT '[]',
    source_event_id TEXT,
    occurrence_id TEXT,
    event_identity TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
  )
''';

Future<List<String>> _columns(PactaDatabase database, String table) async {
  final rows = await database.customSelect('PRAGMA table_info("$table")').get();
  return rows.map((row) => row.read<String>('name')).toList();
}

Future<Set<String>> _tables(PactaDatabase database) async {
  final rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

void main() {
  test('schema 31 升级补上重复规则表与实例列，且保留既有日程', () async {
    final createdAt = DateTime.utc(2026, 11, 15, 1);
    final database = PactaDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(_schedulesAt31);
          raw.execute(
            '''
            INSERT INTO local_schedules
              (user_id, id, title, starts_at, ends_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
            [
              'user-a',
              'schedule-1',
              '取快递',
              createdAt.millisecondsSinceEpoch ~/ 1000,
              createdAt.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                  1000,
              createdAt.millisecondsSinceEpoch ~/ 1000,
              createdAt.millisecondsSinceEpoch ~/ 1000,
            ],
          );
          raw.execute('PRAGMA user_version = 31');
        },
      ),
    );

    try {
      final tables = await _tables(database);
      expect(tables, contains('local_schedule_recurrences'));

      final ruleColumns = await _columns(
        database,
        'local_schedule_recurrences',
      );
      expect(
        ruleColumns,
        containsAll(<String>['shift_days', 'title', 'notes', 'task_id']),
      );

      final columns = await _columns(database, 'local_schedules');
      expect(
        columns,
        containsAll(<String>[
          'recurrence_id',
          'recurrence_series_id',
          'recurrence_date',
          'recurrence_time_zone_id',
          'recurrence_start_minutes',
          'is_recurrence_exception',
          'is_recurrence_cancelled',
        ]),
      );

      final rows = await database
          .customSelect('SELECT * FROM local_schedules')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('title'), '取快递');
      expect(rows.single.read<String?>('recurrence_id'), isNull);
      expect(rows.single.read<int>('is_recurrence_exception'), 0);
      expect(rows.single.read<int>('is_recurrence_cancelled'), 0);
    } finally {
      await database.close();
    }
  });

  test('并行票据已带重复表与实例列的中间版本不重复建表、不丢数据', () async {
    final createdAt = DateTime.utc(2026, 11, 15, 1);
    final database = PactaDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(_schedulesAt31);
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN recurrence_id TEXT',
          );
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN recurrence_series_id TEXT',
          );
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN recurrence_date TEXT',
          );
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN recurrence_time_zone_id TEXT',
          );
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN recurrence_start_minutes INTEGER',
          );
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN is_recurrence_exception INTEGER NOT NULL DEFAULT 0',
          );
          raw.execute(
            'ALTER TABLE local_schedules ADD COLUMN is_recurrence_cancelled INTEGER NOT NULL DEFAULT 0',
          );
          raw.execute('''
            CREATE TABLE local_schedule_recurrences (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              frequency TEXT NOT NULL,
              weekdays TEXT NOT NULL DEFAULT '[]',
              first_date TEXT NOT NULL,
              end_date TEXT,
              time_zone_id TEXT NOT NULL,
              all_day INTEGER NOT NULL DEFAULT 0,
              start_minutes_of_day INTEGER NOT NULL DEFAULT 0,
              duration_minutes INTEGER NOT NULL DEFAULT 60,
              day_span INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (user_id, id)
            )
          ''');
          final epoch = createdAt.millisecondsSinceEpoch ~/ 1000;
          raw.execute(
            '''
            INSERT INTO local_schedule_recurrences
              (user_id, id, frequency, first_date, time_zone_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
            [
              'user-a',
              'rule-1',
              'daily',
              '2026-11-16',
              'Asia/Shanghai',
              epoch,
              epoch,
            ],
          );
          raw.execute(
            '''
            INSERT INTO local_schedules
              (user_id, id, title, starts_at, ends_at, recurrence_id,
               recurrence_series_id, recurrence_date, recurrence_time_zone_id,
               recurrence_start_minutes, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
            [
              'user-a',
              'schedule-1',
              '晨会',
              epoch,
              epoch + 3600,
              'rule-1',
              'rule-1',
              '2026-11-16',
              'Asia/Shanghai',
              540,
              epoch,
              epoch,
            ],
          );
          raw.execute('PRAGMA user_version = 32');
        },
      ),
    );

    try {
      final rules = await database
          .customSelect('SELECT * FROM local_schedule_recurrences')
          .get();
      expect(rules, hasLength(1));
      expect(rules.single.read<String>('id'), 'rule-1');
      // 旧规则行缺少 r3 的模板/位移列：升级补列后从最早的非例外实例回填。
      expect(rules.single.read<int>('shift_days'), 0);
      expect(rules.single.read<String>('title'), '晨会');
      expect(rules.single.read<String?>('task_id'), isNull);

      final rows = await database
          .customSelect('SELECT * FROM local_schedules')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('recurrence_id'), 'rule-1');
      expect(rows.single.read<String?>('recurrence_date'), '2026-11-16');
    } finally {
      await database.close();
    }
  });
}
