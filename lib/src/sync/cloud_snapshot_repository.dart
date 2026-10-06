import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../tasks/task_database.dart';
import 'legacy_cloud_snapshot.dart';

/// A whole-account business-data snapshot. Device identity, local preferences,
/// lifecycle state, and the legacy per-entity upload queue are intentionally
/// kept outside this payload.
class CloudSnapshotMetadata {
  const CloudSnapshotMetadata({
    required this.revision,
    required this.deviceId,
    required this.deviceName,
    required this.dataUpdatedAt,
    required this.uploadedAt,
    required this.rowCount,
    this.isLegacy = false,
    this.legacyToken,
    this.payload,
  });

  final int revision;
  final String deviceId;
  final String deviceName;
  final DateTime dataUpdatedAt;
  final DateTime uploadedAt;
  final int rowCount;
  final bool isLegacy;
  final String? legacyToken;
  final Map<String, dynamic>? payload;
}

abstract interface class CloudSnapshotRemote {
  Future<CloudSnapshotMetadata?> inspect({required String userId});

  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  });

  Future<CloudSnapshotMetadata> download({required String userId});
}

class SupabaseCloudSnapshotRemote implements CloudSnapshotRemote {
  SupabaseCloudSnapshotRemote(this.client);

  final SupabaseClient client;
  final Map<String, String> _legacyTokensByUser = {};

  void _assertCurrentUser(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('当前登录用户已变化，请重新打开同步页面。');
    }
  }

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    _assertCurrentUser(userId);
    final row = await client
        .from('cloud_business_snapshots')
        .select(
          'revision,device_id,device_name,data_updated_at,uploaded_at,row_count',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (row != null) {
      _legacyTokensByUser.remove(userId);
      return _metadataFromJson(row);
    }
    return _readLegacySnapshot(userId);
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    _assertCurrentUser(userId);
    final row = await client
        .from('cloud_business_snapshots')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row != null) {
      _legacyTokensByUser.remove(userId);
      return _metadataFromJson(row);
    }
    final legacy = await _readLegacySnapshot(userId);
    if (legacy == null) throw StateError('Cloud snapshot does not exist.');
    return legacy;
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  }) async {
    _assertCurrentUser(userId);
    final String? expectedLegacyToken;
    final int remoteRevision;
    if (expectedRevision < 0) {
      expectedLegacyToken = _legacyTokensByUser[userId];
      if (expectedLegacyToken == null) {
        throw StateError('请重新检查旧版云数据后再上传，避免覆盖期间变化的数据。');
      }
      if (_legacyRevision(expectedLegacyToken) != expectedRevision) {
        throw StateError('旧版云数据预览已变化，请重新检查后再上传。');
      }
      remoteRevision = 0;
    } else {
      expectedLegacyToken = null;
      remoteRevision = expectedRevision;
    }
    final Object? result;
    try {
      result = await client.rpc(
        'save_cloud_business_snapshot',
        params: {
          'p_expected_revision': remoteRevision,
          'p_payload': payload,
          'p_device_id': deviceId,
          'p_device_name': deviceName,
          'p_data_updated_at': dataUpdatedAt.toUtc().toIso8601String(),
          'p_row_count': rowCount,
          'p_expected_legacy_token': expectedLegacyToken,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PT409') {
        throw StateError('云端数据在确认期间发生变化，请重新查看并选择覆盖方向。');
      }
      if (error.code == '42501') {
        throw StateError('当前用户无法同步，请检查登录或停用状态。');
      }
      rethrow;
    }
    final Map<String, dynamic> row;
    if (result is List && result.length == 1 && result.single is Map) {
      row = Map<String, dynamic>.from(result.single as Map);
    } else if (result is Map) {
      row = Map<String, dynamic>.from(result);
    } else {
      throw StateError('Cloud snapshot RPC returned an invalid result.');
    }
    final saved = _metadataFromJson(row);
    _legacyTokensByUser.remove(userId);
    return saved;
  }

  Future<CloudSnapshotMetadata?> _readLegacySnapshot(String userId) async {
    _assertCurrentUser(userId);
    final response = await client.rpc('read_legacy_business_records');
    if (response == null) {
      _legacyTokensByUser.remove(userId);
      return null;
    }
    if (response is! Map) {
      throw StateError('Legacy cloud records returned an invalid result.');
    }
    final result = Map<String, dynamic>.from(response);
    final records = result['records'];
    final token = result['token'];
    if (records is! Map ||
        token is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      throw StateError(
        'Legacy cloud records are missing their revision token.',
      );
    }
    final local = await LegacyCloudSnapshotConverter().convert(
      userId: userId,
      records: Map<String, dynamic>.from(records),
    );
    if (local == null) {
      _legacyTokensByUser.remove(userId);
      return null;
    }
    _legacyTokensByUser[userId] = token;
    return CloudSnapshotMetadata(
      revision: _legacyRevision(token),
      deviceId: 'legacy',
      deviceName: '旧版云数据（来源设备未记录）',
      dataUpdatedAt: local.dataUpdatedAt,
      uploadedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      rowCount: local.rowCount,
      isLegacy: true,
      legacyToken: token,
      payload: local.payload,
    );
  }

  int _legacyRevision(String token) =>
      -(int.parse(token.substring(0, 15), radix: 16) + 1);

  CloudSnapshotMetadata _metadataFromJson(Map<String, dynamic> row) =>
      CloudSnapshotMetadata(
        revision: row['revision'] as int,
        deviceId: row['device_id'] as String,
        deviceName: row['device_name'] as String,
        dataUpdatedAt: DateTime.parse(row['data_updated_at'] as String).toUtc(),
        uploadedAt: DateTime.parse(row['uploaded_at'] as String).toUtc(),
        rowCount: row['row_count'] as int,
        isLegacy: false,
        payload: row['payload'] == null
            ? null
            : Map<String, dynamic>.from(row['payload'] as Map),
      );
}

class UnavailableCloudSnapshotRemote implements CloudSnapshotRemote {
  const UnavailableCloudSnapshotRemote();

  StateError _error() => StateError('当前未配置云端整份同步。');

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async =>
      throw _error();

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async =>
      throw _error();

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  }) async => throw _error();
}

/// In-memory cloud implementation for application and repository tests.
class InMemoryCloudSnapshotRemote implements CloudSnapshotRemote {
  final Map<String, CloudSnapshotMetadata> _snapshots = {};
  final Map<String, CloudSnapshotMetadata> _legacySnapshots = {};
  final Map<String, String> _observedLegacyTokens = {};
  bool available = true;
  bool suspended = false;

  void seedLegacySnapshot({
    required String userId,
    required String token,
    required CloudSnapshotLocalState state,
  }) {
    _legacySnapshots[userId] = CloudSnapshotMetadata(
      revision: -(int.parse(token.substring(0, 15), radix: 16) + 1),
      deviceId: 'legacy',
      deviceName: '旧版云数据（来源设备未记录）',
      dataUpdatedAt: state.dataUpdatedAt,
      uploadedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      rowCount: state.rowCount,
      isLegacy: true,
      legacyToken: token,
      payload: state.payload,
    );
  }

  void _checkAccess() {
    if (!available) throw StateError('Cloud snapshot service is offline.');
    if (suspended) throw StateError('Suspended users cannot sync snapshots.');
  }

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    _checkAccess();
    final snapshot = _snapshots[userId];
    if (snapshot != null) {
      _observedLegacyTokens.remove(userId);
      return snapshot;
    }
    final legacy = _legacySnapshots[userId];
    if (legacy != null) _observedLegacyTokens[userId] = legacy.legacyToken!;
    return legacy;
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    _checkAccess();
    final snapshot = _snapshots[userId] ?? _legacySnapshots[userId];
    if (snapshot == null) throw StateError('Cloud snapshot does not exist.');
    return snapshot;
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  }) async {
    _checkAccess();
    final legacy = _legacySnapshots[userId];
    if (legacy != null && legacy.legacyToken != null) {
      if (_legacyRevision(legacy.legacyToken!) != legacy.revision) {
        throw StateError('Invalid in-memory legacy token.');
      }
    }
    if (expectedRevision < 0 &&
        _observedLegacyTokens[userId] != legacy?.legacyToken) {
      throw StateError('Legacy cloud snapshot changed; inspect it again.');
    }
    if (expectedRevision < 0 &&
        _legacyRevision(_observedLegacyTokens[userId]!) != expectedRevision) {
      throw StateError('Legacy cloud snapshot preview is stale.');
    }
    if (expectedRevision == 0 && legacy != null) {
      throw StateError('Legacy cloud snapshot exists; inspect it before sync.');
    }
    final currentRevision = _snapshots[userId]?.revision ?? 0;
    final targetRevision = expectedRevision < 0 ? 0 : expectedRevision;
    if (currentRevision != targetRevision) {
      throw StateError('Cloud snapshot changed; inspect it again before sync.');
    }
    final snapshot = CloudSnapshotMetadata(
      revision: currentRevision + 1,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt.toUtc(),
      uploadedAt: DateTime.now().toUtc(),
      rowCount: rowCount,
      payload: jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
    );
    _snapshots[userId] = snapshot;
    _legacySnapshots.remove(userId);
    _observedLegacyTokens.remove(userId);
    return snapshot;
  }

  int _legacyRevision(String token) =>
      -(int.parse(token.substring(0, 15), radix: 16) + 1);
}

class CloudSnapshotLocalState {
  const CloudSnapshotLocalState({
    required this.fingerprint,
    required this.payload,
    required this.rowCount,
    required this.dataUpdatedAt,
    required this.hasUnfinishedFlow,
  });

  final String fingerprint;
  final Map<String, dynamic> payload;
  final int rowCount;
  final DateTime dataUpdatedAt;
  final bool hasUnfinishedFlow;
}

/// Replaces only the explicitly listed business tables for [userId]. The user
/// must pass the fingerprint captured before showing a destructive choice.
class CloudSnapshotRepository {
  CloudSnapshotRepository({
    required this.database,
    required this.remote,
    required this.userId,
    this.deviceId,
    required this.deviceName,
  }) {
    if (userId.isEmpty ||
        (deviceId != null && deviceId!.isEmpty) ||
        deviceName.trim().isEmpty) {
      throw ArgumentError('User and device identity must be present.');
    }
  }

  final PactaDatabase database;
  final CloudSnapshotRemote remote;
  final String userId;
  final String? deviceId;
  final String deviceName;

  /// Calendar source columns tied to one physical device are deliberately
  /// omitted. A download reuses this device's matching source mapping when one
  /// exists; otherwise the restored source remains unselected.
  static const _calendarSourceExcluded = {'local_calendar_id', 'is_selected'};

  /// Keep this table list explicit. It excludes per-device preferences,
  /// lifecycle state, device identity, and the legacy upload queue.
  static const _businessTables = <String>[
    'local_goals',
    'local_tasks',
    'local_national_focus_cards',
    'local_national_focus_strengthening_levels',
    'local_national_focus_requirement_versions',
    'local_national_focus_maintenance',
    'local_national_focus_failures',
    'focus_precedent_rules',
    'focus_appointments',
    'focus_sessions',
    'focus_nodes',
    'focus_chain_records',
    'appointment_chain_records',
    'focus_sync_sources',
    'local_calendar_sources',
    'local_calendar_blocks',
  ];

  Future<CloudSnapshotMetadata?> inspectCloud() =>
      remote.inspect(userId: userId);

  Future<CloudSnapshotLocalState> captureLocalState() async {
    return database.transaction(_captureLocalState);
  }

  Future<CloudSnapshotLocalState> _captureLocalState() async {
    final payload = await _exportPayload();
    final rowCount = (payload['tables'] as Map<String, dynamic>).values
        .cast<List<dynamic>>()
        .fold<int>(0, (total, rows) => total + rows.length);
    final hasUnfinished = await _hasUnfinishedFlow();
    final json = jsonEncode(payload);
    return CloudSnapshotLocalState(
      fingerprint: _fingerprint(json),
      payload: payload,
      rowCount: rowCount,
      dataUpdatedAt: _latestDataTimestamp(payload) ?? DateTime.now().toUtc(),
      hasUnfinishedFlow: hasUnfinished,
    );
  }

  Future<CloudSnapshotMetadata> uploadLocal({
    required int expectedRevision,
    required String expectedFingerprint,
  }) async {
    final state = await captureLocalState();
    if (state.fingerprint != expectedFingerprint) {
      throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
    }
    return remote.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: state.payload,
      deviceId: await _getDeviceId(),
      deviceName: deviceName,
      dataUpdatedAt: state.dataUpdatedAt,
      rowCount: state.rowCount,
    );
  }

  Future<void> downloadCloud({
    required int expectedRevision,
    required String expectedFingerprint,
  }) async {
    final localBefore = await captureLocalState();
    if (localBefore.hasUnfinishedFlow) {
      throw StateError('预约或专注尚未结束，暂不能覆盖本机数据。');
    }
    if (localBefore.fingerprint != expectedFingerprint) {
      throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
    }
    final cloud = await remote.download(userId: userId);
    if (cloud.revision != expectedRevision) {
      throw StateError('云端快照已变化，请重新检查后再同步。');
    }
    final payload = cloud.payload;
    if (payload == null) throw StateError('Cloud snapshot has no payload.');
    final validatedRows = await _validatePayload(payload);
    final latestCloud = await remote.inspect(userId: userId);
    if (latestCloud?.revision != expectedRevision) {
      throw StateError('云端快照已变化，请重新检查后再同步。');
    }

    // Repeat both safety checks immediately before the transaction. Nothing is
    // deleted until the entire schema and every row has passed validation.
    await database.transaction(() async {
      final localAtCommit = await _captureLocalState();
      if (localAtCommit.hasUnfinishedFlow) {
        throw StateError('预约或专注尚未结束，暂不能覆盖本机数据。');
      }
      if (localAtCommit.fingerprint != expectedFingerprint) {
        throw StateError('本机数据在确认期间发生变化，请重新检查后再同步。');
      }
      final calendarDeviceData = await _localCalendarDeviceData();
      for (final table in _businessTables.reversed) {
        await database.customStatement(
          'DELETE FROM "${_quoteIdentifier(table)}" WHERE user_id = ?',
          [userId],
        );
      }
      for (final table in _businessTables) {
        for (final row in validatedRows[table]!) {
          if (table == 'local_calendar_sources') {
            final sourceId = row['source_id'] as String;
            final local = calendarDeviceData[sourceId];
            row['local_calendar_id'] = local?.localCalendarId;
            row['is_selected'] = local?.isSelected == true ? 1 : 0;
          }
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
      }
    });
    database.notifyUpdates({
      for (final table in database.allTables)
        if (_businessTables.contains(table.actualTableName))
          drift.TableUpdate.onTable(table),
    });
  }

  Future<Map<String, LocalCalendarSource>> _localCalendarDeviceData() async {
    final rows = await (database.select(
      database.localCalendarSources,
    )..where((row) => row.userId.equals(userId))).get();
    return {for (final row in rows) row.sourceId: row};
  }

  Future<Map<String, dynamic>> _exportPayload() async {
    final registeredTables = database.allTables
        .map((table) => table.actualTableName)
        .toSet();
    for (final table in _businessTables) {
      if (!registeredTables.contains(table)) {
        throw StateError('Snapshot table is not registered in Drift: $table');
      }
    }
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _businessTables) {
      final allColumns = await _tableColumns(table);
      final columns = allColumns
          .where(
            (column) =>
                table != 'local_calendar_sources' ||
                !_calendarSourceExcluded.contains(column),
          )
          .toList();
      final orderBy = await _primaryKey(table, allColumns);
      final rows = await database
          .customSelect(
            'SELECT ${columns.map((column) => '"${_quoteIdentifier(column)}"').join(',')} '
            'FROM "${_quoteIdentifier(table)}" WHERE user_id = '
            '? ORDER BY $orderBy',
            variables: [drift.Variable<String>(userId)],
          )
          .get();
      tables[table] = [
        for (final row in rows)
          {for (final column in columns) column: _jsonValue(row.data[column])},
      ];
    }
    return {'schemaVersion': 1, 'userId': userId, 'tables': tables};
  }

  Future<Map<String, List<Map<String, Object?>>>> _validatePayload(
    Map<String, dynamic> payload,
  ) async {
    if (payload['schemaVersion'] != 1 || payload['userId'] != userId) {
      throw StateError('Snapshot version or user identity is invalid.');
    }
    final rawTables = payload['tables'];
    if (rawTables is! Map<String, dynamic> ||
        rawTables.keys.length != _businessTables.length ||
        !_businessTables.every(rawTables.containsKey)) {
      throw StateError('Snapshot table set is invalid.');
    }
    final registeredTables = database.allTables
        .map((table) => table.actualTableName)
        .toSet();
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in _businessTables) {
      if (!registeredTables.contains(table)) {
        throw StateError('Snapshot table is not registered in Drift: $table');
      }
      final localColumns = await _tableColumns(table);
      final expectedColumns = localColumns
          .where(
            (column) =>
                table != 'local_calendar_sources' ||
                !_calendarSourceExcluded.contains(column),
          )
          .toSet();
      final columnInfo = await _tableColumnInfo(table);
      final rawRows = rawTables[table];
      if (rawRows is! List) throw StateError('Invalid rows for $table.');
      final rows = <Map<String, Object?>>[];
      for (final item in rawRows) {
        if (item is! Map<String, dynamic> ||
            item.keys.length != expectedColumns.length ||
            !expectedColumns.every(item.containsKey) ||
            item['user_id'] != userId) {
          throw StateError('Invalid columns or user ownership in $table.');
        }
        for (final column in expectedColumns) {
          if (!_isValidSqliteValue(item[column], columnInfo[column]!)) {
            throw StateError('Invalid value type in $table.$column.');
          }
        }
        final row = <String, Object?>{
          for (final column in expectedColumns)
            column: _sqliteValue(item[column]),
        };
        rows.add(row);
      }
      result[table] = rows;
    }
    await _validateReferences(result);
    return result;
  }

  Future<Map<String, Map<String, Object?>>> _tableColumnInfo(
    String table,
  ) async {
    final rows = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    return {
      for (final row in rows)
        row.read<String>('name'): {
          'type': row.read<String>('type').toUpperCase(),
          'notnull': row.read<int>('notnull') == 1,
          'pk': row.read<int>('pk') > 0,
        },
    };
  }

  bool _isValidSqliteValue(Object? value, Map<String, Object?> column) {
    if (value == null) return column['notnull'] != true && column['pk'] != true;
    final type = column['type'] as String;
    if (type.contains('INT')) return value is int;
    if (type.contains('CHAR') ||
        type.contains('CLOB') ||
        type.contains('TEXT')) {
      return value is String;
    }
    if (type.contains('REAL') ||
        type.contains('FLOA') ||
        type.contains('DOUB')) {
      return value is num;
    }
    if (type.contains('BLOB')) return value is String;
    return value is num || value is String;
  }

  Future<void> _validateReferences(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    Set<Object?> ids(String table) => {
      for (final row in tables[table]!) row['id'],
    };
    final goalIds = ids('local_goals');
    final taskIds = ids('local_tasks');
    final cardIds = ids('local_national_focus_cards');
    final sessionIds = ids('focus_sessions');
    final appointmentIds = ids('focus_appointments');
    final sourceIds = {
      for (final row in tables['local_calendar_sources']!) row['source_id'],
    };
    void requireReference(bool valid, String label) {
      if (!valid) throw StateError('Snapshot contains an unknown $label.');
    }

    for (final row in tables['local_tasks']!) {
      requireReference(goalIds.contains(row['goal_id']), 'Goal reference');
    }
    for (final table in const [
      'local_national_focus_strengthening_levels',
      'local_national_focus_requirement_versions',
      'local_national_focus_failures',
    ]) {
      for (final row in tables[table]!) {
        requireReference(
          cardIds.contains(row['card_id']),
          'National Focus card reference',
        );
      }
    }
    for (final row in tables['local_national_focus_cards']!) {
      final name = row['name'];
      requireReference(
        name is String && name.trim().isNotEmpty,
        'National Focus card name',
      );
      final parentId = row['parent_id'];
      if (parentId != null) {
        requireReference(cardIds.contains(parentId), 'parent card reference');
      }
    }
    for (final row in tables['focus_appointments']!) {
      requireReference(
        taskIds.contains(row['task_id']),
        'appointment Task reference',
      );
    }
    for (final row in tables['focus_sessions']!) {
      requireReference(
        taskIds.contains(row['task_id']),
        'Session Task reference',
      );
      final appointmentId = row['appointment_id'];
      if (appointmentId != null) {
        requireReference(
          appointmentIds.contains(appointmentId),
          'Appointment reference',
        );
      }
    }
    for (final row in tables['focus_nodes']!) {
      requireReference(
        sessionIds.contains(row['session_id']),
        'Focus Session reference',
      );
      requireReference(
        taskIds.contains(row['task_id']),
        'Focus Node Task reference',
      );
    }
    for (final row in tables['local_calendar_blocks']!) {
      requireReference(
        sourceIds.contains(row['source_id']),
        'calendar source reference',
      );
    }
  }

  Future<List<String>> _tableColumns(String table) async {
    final result = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    final columns = result.map((row) => row.read<String>('name')).toList();
    if (!columns.contains('user_id')) {
      throw StateError('Snapshot table has no user ownership column: $table');
    }
    return columns;
  }

  Future<String> _primaryKey(String table, List<String> columns) async {
    final info = await database
        .customSelect('PRAGMA table_info("${_quoteIdentifier(table)}")')
        .get();
    final primaryKeyColumns = [
      for (final row in info)
        if (row.read<int>('pk') > 0)
          (position: row.read<int>('pk'), name: row.read<String>('name')),
    ]..sort((left, right) => left.position.compareTo(right.position));
    if (primaryKeyColumns.isEmpty ||
        primaryKeyColumns.any((entry) => !columns.contains(entry.name))) {
      throw StateError('Snapshot table has no supported primary key: $table');
    }
    return primaryKeyColumns
        .map((entry) => '"${_quoteIdentifier(entry.name)}"')
        .join(',');
  }

  Future<bool> _hasUnfinishedFlow() async {
    final appointments = await database
        .customSelect(
          'SELECT 1 FROM focus_appointments WHERE user_id = ? AND status = ? LIMIT 1',
          variables: [
            drift.Variable<String>(userId),
            drift.Variable<String>('active'),
          ],
        )
        .get();
    if (appointments.isNotEmpty) return true;
    final sessions = await database
        .customSelect(
          'SELECT 1 FROM focus_sessions WHERE user_id = ? AND status IN (?, ?) LIMIT 1',
          variables: [
            drift.Variable<String>(userId),
            drift.Variable<String>('active'),
            drift.Variable<String>('paused'),
          ],
        )
        .get();
    return sessions.isNotEmpty;
  }

  Future<String> _getDeviceId() async {
    if (deviceId case final provided?) return provided;
    final existing = await (database.select(
      database.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (existing != null) return existing.deviceId;
    final generated = const Uuid().v4();
    await database
        .into(database.focusSourceDevices)
        .insertOnConflictUpdate(
          FocusSourceDevicesCompanion.insert(
            userId: userId,
            deviceId: generated,
          ),
        );
    return generated;
  }

  DateTime? _latestDataTimestamp(Map<String, dynamic> payload) {
    const timestampKeys = {
      'updated_at',
      'occurred_at',
      'created_at',
      'started_at',
      'completed_at',
      'settled_at',
      'paused_at',
      'deleted_at',
      'review_disposition_updated_at',
      'effective_from',
      'checkpoint_at',
      'last_settled_checkpoint_at',
    };
    DateTime? latest;
    final tables = payload['tables'] as Map<String, dynamic>;
    for (final rows in tables.values.cast<List<dynamic>>()) {
      for (final raw in rows.cast<Map<String, dynamic>>()) {
        for (final key in raw.keys.where(timestampKeys.contains)) {
          final value = raw[key];
          if (value is int) {
            final timestamp = DateTime.fromMillisecondsSinceEpoch(
              value * 1000,
              isUtc: true,
            );
            if (latest == null || timestamp.isAfter(latest)) latest = timestamp;
          } else if (value is String) {
            final timestamp = DateTime.tryParse(value)?.toUtc();
            if (timestamp != null &&
                (latest == null || timestamp.isAfter(latest))) {
              latest = timestamp;
            }
          }
        }
      }
    }
    return latest;
  }

  Object? _jsonValue(Object? value) => switch (value) {
    DateTime dateTime => dateTime.toUtc().millisecondsSinceEpoch ~/ 1000,
    Uint8List bytes => base64Encode(bytes),
    _ => value,
  };

  Object? _sqliteValue(Object? value) => value;

  String _fingerprint(String value) {
    // FNV-1a is only a local change detector, never an integrity boundary.
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _quoteIdentifier(String identifier) =>
      identifier.replaceAll('"', '""');
}
