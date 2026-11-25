import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  test('schema 39 -> 40 幂等删除生效版本表并补 icon_key 列', () async {
    final database = PactaDatabase(
      NativeDatabase.memory(
        setup: (rawDatabase) {
          rawDatabase.execute('''
            CREATE TABLE local_national_focus_cards (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              name TEXT NOT NULL,
              trigger_condition TEXT NOT NULL,
              action TEXT NOT NULL,
              PRIMARY KEY (user_id, id)
            )
          ''');
          rawDatabase.execute('''
            CREATE TABLE local_national_focus_requirement_versions (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              card_id TEXT NOT NULL,
              version_number INTEGER NOT NULL,
              effective_trigger_condition TEXT NOT NULL,
              effective_action TEXT NOT NULL,
              effective_from INTEGER NOT NULL,
              PRIMARY KEY (user_id, id)
            )
          ''');
          rawDatabase.execute(
            'INSERT INTO local_national_focus_requirement_versions '
            '(user_id, id, card_id, version_number, '
            'effective_trigger_condition, effective_action, effective_from) '
            "VALUES ('user-a', 'version-1', 'card-1', 1, '旧触发', '旧行动', 1)",
          );
          rawDatabase.execute('PRAGMA user_version = 39');
        },
      ),
    );

    try {
      expect(database.schemaVersion, 40);
      final columns = await database
          .customSelect('PRAGMA table_info(local_national_focus_cards)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('icon_key'),
        reason: 'v40 必须给卡片补上跨端自定义图标键',
      );
      final versionTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'local_national_focus_requirement_versions'",
          )
          .get();
      expect(versionTable, isEmpty, reason: '生效版本记录整表在 v40 升级时丢弃，不留兼容读取');
    } finally {
      await database.close();
    }
  });

  test('全新数据库直接具备 v40 结构与 icon_key', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    try {
      expect(database.schemaVersion, 40);
      expect(
        database.allTables.map((table) => table.actualTableName),
        isNot(contains('local_national_focus_requirement_versions')),
      );
      final columns = await database
          .customSelect('PRAGMA table_info(local_national_focus_cards)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('icon_key'),
      );
    } finally {
      await database.close();
    }
  });
}
