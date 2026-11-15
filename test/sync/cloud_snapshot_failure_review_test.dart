import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ticket 11 复审缺陷 2：回顾状态必须走真实的
/// CloudSnapshotRepository 通道（整份快照上传/下载/恢复），
/// 而不是国策模块内部的 sync source。
///
/// v1 整份快照没有 reviewed_at：显式补 null（未回顾）；
/// v2 严格形状缺字段必须整体拒绝，且不改动本机数据与失败事实。
void main() {
  const userId = 'cloud-review-user';

  late PactaDatabase database;
  late InMemoryCloudSnapshotRemote remote;
  late CloudSnapshotRepository repository;
  late LocalNationalFocusRepository tree;
  late DateTime now;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 9, 25, 19, 59);
    database = PactaDatabase(NativeDatabase.memory());
    remote = InMemoryCloudSnapshotRemote();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: userId,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      now: () => now,
    );
    tree = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
      now: () => now,
    );
  });

  tearDown(() async {
    await tree.dispose();
    await database.close();
  });

  Future<String> createFailedBatch() async {
    for (var index = 0; index < 2; index++) {
      final card = await tree.createCard(
        NationalFocusCardDraft(
          name: '触发 $index',
          triggerCondition: '触发 $index',
          action: '行动 $index',
        ),
      );
      await tree.placeCard(cardId: card.id, parentId: null);
      await tree.lightCard(card.id);
    }
    now = DateTime.utc(2026, 9, 25, 20);
    await tree.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await tree.settleDueCheckpoints();
    final failures = await tree.getFailures();
    expect(failures, isNotEmpty);
    return failures.first.batchId;
  }

  String facts(NationalFocusFailure failure) =>
      '${failure.cardId}|${failure.batchId}|${failure.cause}|'
      '${failure.failureReason}|${failure.sharedExplanation}|'
      '${failure.checkpointAt.toUtc().toIso8601String()}|'
      '${failure.treeSnapshot.map((card) => '${card.id}|${card.name}|${card.state}|${card.effectiveAction}').join(',')}';

  Map<String, dynamic> payloadCopy(Map<String, dynamic> payload) =>
      jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

  List<Map<String, dynamic>> failureRowsOf(Map<String, dynamic> payload) =>
      (((payload['tables'] as Map)['local_national_focus_failures'] as List))
          .cast<Map<String, dynamic>>();

  Future<void> uploadRaw({
    required Map<String, dynamic> payload,
    required int expectedRevision,
    required int rowCount,
  }) async {
    await remote.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: 'device-a',
      deviceName: 'Phone A',
      dataUpdatedAt: now,
      rowCount: rowCount,
    );
  }

  test('回顾状态经整份快照上传下载往返，失败事实不变', () async {
    final batchId = await createFailedBatch();
    await tree.markFailureReviewed(batchId: batchId);
    await tree.updateFailureExplanation(batchId: batchId, explanation: '通勤中');
    final before = await tree.getFailures();
    expect(before.every((failure) => failure.isReviewed), isTrue);

    final local = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: local.fingerprint,
    );

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(secondDatabase.close);
    final secondRepository = CloudSnapshotRepository(
      database: secondDatabase,
      remote: remote,
      userId: userId,
      deviceId: 'device-b',
      deviceName: 'Phone B',
      now: () => now,
    );
    final target = await secondRepository.captureLocalState();
    await secondRepository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: target.fingerprint,
    );

    final restoredTree = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: userId,
      cloudSyncEnabled: false,
      now: () => now,
    );
    addTearDown(restoredTree.dispose);
    final restored = await restoredTree.getFailures();
    expect(restored, hasLength(before.length));
    expect(restored.every((failure) => failure.isReviewed), isTrue);
    expect(restored.every((failure) => failure.needsReflection), isFalse);
    expect(restored.map(facts), before.map(facts));
  });

  test('v1 整份快照含失败记录时按未回顾导入', () async {
    final batchId = await createFailedBatch();
    await tree.markFailureReviewed(batchId: batchId);
    final before = await tree.getFailures();

    final local = await repository.captureLocalState();
    final legacy = payloadCopy(local.payload);
    legacy['schemaVersion'] = 1;
    // 真正的 v1 快照早于日程表：旧载荷没有 local_schedules 键。
    (legacy['tables'] as Map<String, dynamic>).remove('local_schedules');
    final legacyRows = failureRowsOf(legacy);
    expect(legacyRows, isNotEmpty);
    for (final row in legacyRows) {
      expect(row.remove('reviewed_at'), isNotNull);
    }
    await uploadRaw(
      payload: legacy,
      expectedRevision: 0,
      rowCount: local.rowCount,
    );

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(secondDatabase.close);
    final secondRepository = CloudSnapshotRepository(
      database: secondDatabase,
      remote: remote,
      userId: userId,
      deviceId: 'device-b',
      deviceName: 'Phone B',
      now: () => now,
    );
    final target = await secondRepository.captureLocalState();
    await secondRepository.downloadCloud(
      expectedRevision: 1,
      expectedFingerprint: target.fingerprint,
    );

    final legacyTree = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: userId,
      cloudSyncEnabled: false,
      now: () => now,
    );
    addTearDown(legacyTree.dispose);
    final imported = await legacyTree.getFailures();
    expect(imported, hasLength(before.length));
    expect(imported.every((failure) => failure.isReviewed), isFalse);
    expect(imported.every((failure) => failure.reviewedAt == null), isTrue);
    expect(imported.map(facts), before.map(facts));
  });

  test('v2 快照缺 reviewed_at 时整体拒绝且本机数据不变', () async {
    final batchId = await createFailedBatch();
    await tree.markFailureReviewed(batchId: batchId);
    final before = await tree.getFailures();

    final local = await repository.captureLocalState();
    final malformed = payloadCopy(local.payload);
    expect(malformed['schemaVersion'], cloudSnapshotSchemaVersion);
    for (final row in failureRowsOf(malformed)) {
      row.remove('reviewed_at');
    }
    await uploadRaw(
      payload: malformed,
      expectedRevision: 0,
      rowCount: local.rowCount,
    );

    await expectLater(
      repository.downloadCloud(
        expectedRevision: 1,
        expectedFingerprint: local.fingerprint,
      ),
      throwsA(isA<StateError>()),
    );

    final afterFailure = await tree.getFailures();
    expect(afterFailure, hasLength(before.length));
    expect(afterFailure.every((failure) => failure.isReviewed), isTrue);
    expect(afterFailure.map(facts), before.map(facts));
  });
}
