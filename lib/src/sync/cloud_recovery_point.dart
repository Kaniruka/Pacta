import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../tasks/task_database.dart';

/// 保存恢复点的原因，用于在“找回本机数据”入口区分上下文。
enum CloudRecoveryReason { beforeCloudRestore, beforeRecoveryRestore }

/// 恢复前持久保存的本机业务快照。
///
/// 它与云端 15 份备份分开保存：恢复准备动作因此不会先覆盖当前云端数据。
class CloudRecoveryPoint {
  const CloudRecoveryPoint({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.reason,
    required this.dataUpdatedAt,
    required this.rowCount,
    required this.payload,
    this.sourceDeviceName,
  });

  final String id;
  final String userId;
  final DateTime createdAt;
  final CloudRecoveryReason reason;
  final DateTime dataUpdatedAt;
  final int rowCount;
  final Map<String, dynamic> payload;
  final String? sourceDeviceName;
}

/// 列表与选择只需要的恢复点元数据。
class CloudRecoveryPointSummary {
  const CloudRecoveryPointSummary({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.dataUpdatedAt,
    required this.rowCount,
    this.sourceDeviceName,
  });

  final String id;
  final DateTime createdAt;
  final CloudRecoveryReason reason;
  final DateTime dataUpdatedAt;
  final int rowCount;
  final String? sourceDeviceName;
}

/// 本机恢复点的持久存储。保存失败必须抛出，调用方据此取消恢复。
abstract interface class CloudRecoveryPointStore {
  Future<void> save(CloudRecoveryPoint point);

  Future<List<CloudRecoveryPointSummary>> list(String userId);

  Future<CloudRecoveryPoint?> load(String userId, String pointId);
}

/// Drift 存储：写入后立即可读，跨重启保留，并按用户隔离。
class DriftCloudRecoveryPointStore implements CloudRecoveryPointStore {
  const DriftCloudRecoveryPointStore(this.database);

  final PactaDatabase database;

  /// 每用户保留的恢复点数量；恢复点含整份业务快照，需要上限。
  static const int keepPerUser = 5;

  @override
  Future<void> save(CloudRecoveryPoint point) async {
    await database.transaction(() async {
      await database
          .into(database.localCloudRecoveryPoints)
          .insert(
            LocalCloudRecoveryPointsCompanion.insert(
              id: point.id,
              userId: point.userId,
              createdAt: point.createdAt,
              reason: point.reason.name,
              sourceDeviceName: drift.Value(point.sourceDeviceName),
              dataUpdatedAt: point.dataUpdatedAt,
              rowCount: point.rowCount,
              payload: _encodePayload(point.payload),
            ),
          );
      final rows =
          await (database.select(database.localCloudRecoveryPoints)
                ..where((row) => row.userId.equals(point.userId))
                ..orderBy([
                  (row) => drift.OrderingTerm.desc(row.createdAt),
                  (row) => drift.OrderingTerm.desc(row.id),
                ]))
              .get();
      for (final stale in rows.skip(keepPerUser)) {
        await (database.delete(
          database.localCloudRecoveryPoints,
        )..where((row) => row.id.equals(stale.id))).go();
      }
    });
  }

  @override
  Future<List<CloudRecoveryPointSummary>> list(String userId) async {
    final rows =
        await (database.select(database.localCloudRecoveryPoints)
              ..where((row) => row.userId.equals(userId))
              ..orderBy([
                (row) => drift.OrderingTerm.desc(row.createdAt),
                (row) => drift.OrderingTerm.desc(row.id),
              ]))
            .get();
    return [
      for (final row in rows)
        CloudRecoveryPointSummary(
          id: row.id,
          createdAt: row.createdAt.toUtc(),
          reason: _reason(row.reason),
          dataUpdatedAt: row.dataUpdatedAt.toUtc(),
          rowCount: row.rowCount,
          sourceDeviceName: row.sourceDeviceName,
        ),
    ];
  }

  @override
  Future<CloudRecoveryPoint?> load(String userId, String pointId) async {
    final row =
        await (database.select(database.localCloudRecoveryPoints)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.id.equals(pointId)))
            .getSingleOrNull();
    if (row == null) return null;
    return CloudRecoveryPoint(
      id: row.id,
      userId: row.userId,
      createdAt: row.createdAt.toUtc(),
      reason: _reason(row.reason),
      dataUpdatedAt: row.dataUpdatedAt.toUtc(),
      rowCount: row.rowCount,
      payload: _decodePayload(row.payload),
      sourceDeviceName: row.sourceDeviceName,
    );
  }

  static CloudRecoveryReason _reason(String value) =>
      CloudRecoveryReason.values.firstWhere(
        (candidate) => candidate.name == value,
        orElse: () => CloudRecoveryReason.beforeCloudRestore,
      );

  static String _encodePayload(Map<String, dynamic> payload) =>
      jsonEncode(payload);

  static Map<String, dynamic> _decodePayload(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw StateError('本机恢复点内容无效，无法找回。');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
