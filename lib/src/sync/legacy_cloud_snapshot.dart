import 'dart:convert';

import 'package:drift/native.dart';

import '../national_focus/national_focus_repository.dart';
import '../tasks/task_database.dart';
import 'cloud_snapshot_repository.dart';

/// Converts rows from the legacy, normalized Supabase tables into the current
/// whole-account snapshot format without touching the signed-in device.
class LegacyCloudSnapshotConverter {
  static const _legacyTables = <String>[
    'goals',
    'tasks',
    'focus_appointments',
    'focus_sessions',
    'focus_nodes',
    'focus_chain_records',
    'appointment_chain_records',
    'focus_precedent_rules',
    'focus_sync_sources',
    'calendar_sources',
    'calendar_blocks',
  ];

  static const _localTableByLegacyTable = <String, String>{
    'goals': 'local_goals',
    'tasks': 'local_tasks',
    'focus_sessions': 'focus_sessions',
    'focus_appointments': 'focus_appointments',
    'focus_nodes': 'focus_nodes',
    'focus_chain_records': 'focus_chain_records',
    'appointment_chain_records': 'appointment_chain_records',
    'focus_precedent_rules': 'focus_precedent_rules',
    'focus_sync_sources': 'focus_sync_sources',
    'calendar_sources': 'local_calendar_sources',
    'calendar_blocks': 'local_calendar_blocks',
  };

  static const _columnAliases = <String, Map<String, String>>{
    'calendar_blocks': {'is_all_day': 'all_day'},
  };

  static const _dateTimeColumns = <String, Set<String>>{
    'local_goals': {'created_at', 'updated_at', 'deleted_at'},
    'local_tasks': {'deadline', 'created_at', 'updated_at', 'deleted_at'},
    'focus_sessions': {
      'started_at',
      'ends_at',
      'completed_at',
      'paused_at',
      'review_disposition_updated_at',
    },
    'focus_appointments': {
      'started_at',
      'ends_at',
      'settled_at',
      'updated_at',
      'review_disposition_updated_at',
    },
    'focus_nodes': {'created_at'},
    'focus_chain_records': {'updated_at'},
    'appointment_chain_records': {'updated_at'},
    'focus_precedent_rules': {'created_at', 'updated_at', 'deleted_at'},
    'focus_sync_sources': {'occurred_at'},
    'local_calendar_sources': {'updated_at'},
    'local_calendar_blocks': {'starts_at', 'ends_at', 'updated_at'},
  };

  static const _booleanColumns = <String, Set<String>>{
    'local_tasks': {'is_complete'},
    'local_calendar_sources': {'is_stale'},
    'local_calendar_blocks': {'all_day'},
  };

  static const _jsonTextColumns = <String, Set<String>>{
    'focus_sessions': {'effective_intervals'},
    'focus_sync_sources': {'parent_source_ids', 'payload'},
  };

  /// Returns `null` when every legacy business table is empty.
  ///
  /// Rows are materialized into an isolated in-memory database first. The
  /// National Focus source log is then projected with the repository's
  /// read-only replay path before the ordinary snapshot exporter serializes
  /// the result.
  Future<CloudSnapshotLocalState?> convert({
    required String userId,
    required Map<String, dynamic> records,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户标识不能为空。');
    }
    final validatedRecords = _validateRecords(userId, records);
    if (validatedRecords.values.every((rows) => rows.isEmpty)) return null;

    final database = PactaDatabase(NativeDatabase.memory());
    try {
      await database.transaction(() async {
        for (final legacyTable in _legacyTables) {
          final localTable = _localTableByLegacyTable[legacyTable]!;
          final columnInfo = await _localColumnInfo(database, localTable);
          for (final record in validatedRecords[legacyTable]!) {
            final row = _mapRow(
              legacyTable: legacyTable,
              localTable: localTable,
              record: record,
              columnInfo: columnInfo,
            );
            await _insertRow(database, localTable, row);
          }
        }
      });

      final hasNationalFocusSources = validatedRecords['focus_sync_sources']!
          .any((row) => row['entity_type'] == 'national_focus_tree');
      if (hasNationalFocusSources) {
        final repository = LocalNationalFocusRepository(
          database: database,
          userId: userId,
          remote: const UnavailableNationalFocusRemoteDataSource(),
          cloudSyncEnabled: false,
        );
        try {
          await repository.restoreLegacyCloudProjection();
        } finally {
          await repository.dispose();
        }
      }

      return await CloudSnapshotRepository(
        database: database,
        remote: const UnavailableCloudSnapshotRemote(),
        userId: userId,
        deviceName: 'Legacy cloud conversion',
      ).captureLocalState();
    } finally {
      await database.close();
    }
  }

  Map<String, List<Map<String, dynamic>>> _validateRecords(
    String userId,
    Map<String, dynamic> records,
  ) {
    final validated = <String, List<Map<String, dynamic>>>{};
    for (final table in _legacyTables) {
      final rawRows = records[table];
      if (rawRows is! List) {
        throw FormatException('旧版云端数据缺少 $table 记录数组。');
      }
      final rows = <Map<String, dynamic>>[];
      for (final rawRow in rawRows) {
        if (rawRow is! Map) {
          throw FormatException('旧版云端 $table 包含无效记录。');
        }
        final row = Map<String, dynamic>.from(rawRow);
        if (row['user_id'] != userId) {
          throw StateError('旧版云端 $table 记录不属于当前用户。');
        }
        rows.add(row);
      }
      validated[table] = rows;
    }
    return validated;
  }

  Map<String, Object?> _mapRow({
    required String legacyTable,
    required String localTable,
    required Map<String, dynamic> record,
    required Map<String, _LocalColumnInfo> columnInfo,
  }) {
    final aliases = _columnAliases[legacyTable] ?? const <String, String>{};
    final row = <String, Object?>{};
    for (final entry in record.entries) {
      final column = aliases[entry.key] ?? entry.key;
      // Ignore legacy-only columns (for example, future calendar freshness
      // metadata) while preserving every column represented by the local
      // business schema.
      if (!columnInfo.containsKey(column)) continue;
      if (row.containsKey(column)) {
        throw FormatException('旧版云端字段映射重复：$legacyTable.$column。');
      }
      row[column] = _sqliteValue(
        localTable: localTable,
        column: column,
        value: entry.value,
      );
    }

    if (row['user_id'] != record['user_id']) {
      throw StateError('旧版云端 $legacyTable 用户归属无效。');
    }
    for (final entry in columnInfo.entries) {
      if (row.containsKey(entry.key)) continue;
      if (entry.value.notNull && !entry.value.hasDefault) {
        throw FormatException('旧版云端 $legacyTable 缺少必需字段 ${entry.key}。');
      }
    }
    return row;
  }

  Object? _sqliteValue({
    required String localTable,
    required String column,
    required Object? value,
  }) {
    if (value == null) return null;
    if (_dateTimeColumns[localTable]?.contains(column) == true) {
      return _epochSeconds(value);
    }
    if (_jsonTextColumns[localTable]?.contains(column) == true) {
      return _jsonText(value);
    }
    if (_booleanColumns[localTable]?.contains(column) == true) {
      if (value is bool) return value ? 1 : 0;
      if (value is num && (value == 0 || value == 1)) return value.toInt();
      throw FormatException('旧版云端 $localTable.$column 不是布尔值。');
    }
    if (value is bool) return value ? 1 : 0;
    return value;
  }

  int _epochSeconds(Object value) {
    if (value is DateTime) {
      return value.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    throw FormatException('旧版云端日期字段无效：$value');
  }

  String _jsonText(Object value) {
    if (value is String) {
      try {
        jsonDecode(value);
        return value;
      } on FormatException {
        // A JSONB string value needs its JSON quotes retained in SQLite text.
      }
    }
    return jsonEncode(value);
  }

  Future<Map<String, _LocalColumnInfo>> _localColumnInfo(
    PactaDatabase database,
    String table,
  ) async {
    final rows = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    if (rows.isEmpty) throw StateError('本地数据库缺少快照表 $table。');
    return {
      for (final row in rows)
        row.read<String>('name'): _LocalColumnInfo(
          notNull: row.read<int>('notnull') == 1,
          hasDefault: row.data['dflt_value'] != null,
        ),
    };
  }

  Future<void> _insertRow(
    PactaDatabase database,
    String table,
    Map<String, Object?> row,
  ) async {
    final columns = row.keys.toList();
    final names = columns
        .map((column) => '"${_quoteIdentifier(column)}"')
        .join(',');
    final placeholders = List.filled(columns.length, '?').join(',');
    await database.customStatement(
      'INSERT INTO "${_quoteIdentifier(table)}" ($names) VALUES ($placeholders)',
      [for (final column in columns) row[column]],
    );
  }

  String _quoteIdentifier(String identifier) =>
      identifier.replaceAll('"', '""');
}

class _LocalColumnInfo {
  const _LocalColumnInfo({required this.notNull, required this.hasDefault});

  final bool notNull;
  final bool hasDefault;
}
