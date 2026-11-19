import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// Ticket 11：回顾状态随整份国策快照同步。
///
/// 换设备后状态一致；旧版载荷没有回顾字段时显式转换为未回顾，
/// 绝不臆测历史记录已被回顾，也不改动失败结果与冻结要求。
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory directory;
  late PactaDatabase firstDatabase;
  late PactaDatabase secondDatabase;
  late LocalNationalFocusRepository firstDevice;
  late LocalNationalFocusRepository secondDevice;
  late InMemoryNationalFocusRemoteDataSource remote;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pacta-t11-sync-');
    firstDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/first.sqlite')),
    );
    secondDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/second.sqlite')),
    );
    now = DateTime.utc(2026, 9, 25, 19, 59);
    remote = InMemoryNationalFocusRemoteDataSource();
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-11-user',
      remote: remote,
      now: () => now,
    );
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-11-user',
      remote: remote,
      now: () => now,
    );
  });

  tearDown(() async {
    await firstDevice.dispose();
    await secondDevice.dispose();
    await firstDatabase.close();
    await secondDatabase.close();
    await directory.delete(recursive: true);
  });

  Future<void> createFailureOnFirstDevice() async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '开始阅读',
        triggerCondition: '开始阅读',
        action: '阅读 5 页',
      ),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    now = DateTime.utc(2026, 9, 25, 20);
    await firstDevice.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await firstDevice.settleDueCheckpoints();
    expect(await firstDevice.getFailures(), isNotEmpty);
  }

  test('换设备后回顾状态与说明一致，失败结果与冻结要求不变', () async {
    await createFailureOnFirstDevice();
    final beforeSync = await firstDevice.getFailures();
    final batchId = beforeSync.first.batchId;

    await firstDevice.sync();
    await secondDevice.sync();
    expect(
      (await secondDevice.getFailures()).every((failure) => failure.isReviewed),
      isFalse,
      reason: '未回顾状态同样要同步过去。',
    );

    await firstDevice.markFailureReviewed(batchId: batchId);
    await firstDevice.updateFailureExplanation(
      batchId: batchId,
      explanation: '那天在通勤',
    );
    await firstDevice.sync();
    now = DateTime.utc(2026, 9, 27, 9);
    await secondDevice.sync();

    final afterSync = await secondDevice.getFailures();
    expect(afterSync, hasLength(beforeSync.length));
    expect(afterSync.every((failure) => failure.isReviewed), isTrue);
    expect(afterSync.every((failure) => failure.needsReflection), isFalse);
    expect(afterSync.map((failure) => failure.sharedExplanation).toSet(), {
      '那天在通勤',
    });
    expect(
      afterSync.map(
        (failure) =>
            '${failure.cardId}|${failure.batchId}|'
            '${failure.cause}|${failure.failureReason}|'
            '${failure.checkpointAt.toUtc().toIso8601String()}|'
            '${failure.treeSnapshot.length}',
      ),
      beforeSync.map(
        (failure) =>
            '${failure.cardId}|${failure.batchId}|'
            '${failure.cause}|${failure.failureReason}|'
            '${failure.checkpointAt.toUtc().toIso8601String()}|'
            '${failure.treeSnapshot.length}',
      ),
      reason: '回顾只是标记，不同步改写失败结果与冻结快照。',
    );

    // 回到第一台设备再同步一次：已回顾状态不会被旧副本回退。
    await firstDevice.sync();
    expect(
      (await firstDevice.getFailures()).every((failure) => failure.isReviewed),
      isTrue,
    );
  });

  test('旧版快照缺少回顾字段时按未回顾导入且保留事实', () async {
    await createFailureOnFirstDevice();
    final batchId = (await firstDevice.getFailures()).first.batchId;
    await firstDevice.markFailureReviewed(batchId: batchId);
    await firstDevice.sync();

    final sources = await remote.pull(userId: 'ticket-11-user');
    final latest = sources.last;
    final legacyPayload = jsonDecode(latest.payload) as Map<String, dynamic>;
    for (final raw in (legacyPayload['failures'] as List)) {
      (raw as Map<String, dynamic>).remove('reviewedAt');
    }

    final legacyDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/legacy.sqlite')),
    );
    final legacyRemote = InMemoryNationalFocusRemoteDataSource();
    await legacyRemote.upsertSources(
      userId: 'legacy-user',
      sources: [
        NationalFocusSyncSource(
          sourceId: 'legacy-source-1',
          deviceId: 'old-device',
          parentSourceIds: const [],
          occurredAt: now,
          payload: jsonEncode(legacyPayload),
        ),
      ],
    );
    final legacyDevice = LocalNationalFocusRepository(
      database: legacyDatabase,
      userId: 'legacy-user',
      remote: legacyRemote,
      now: () => now,
    );
    addTearDown(() async {
      await legacyDevice.dispose();
      await legacyDatabase.close();
    });

    await legacyDevice.sync();
    final imported = await legacyDevice.getFailures();
    expect(imported, isNotEmpty);
    expect(imported.every((failure) => failure.isReviewed), isFalse);
    expect(imported.every((failure) => failure.needsReflection), isTrue);
    expect(imported.every((failure) => failure.reviewedAt == null), isTrue);
    expect(
      imported.map(
        (failure) =>
            '${failure.cause}|${failure.failureReason}|'
            '${failure.treeSnapshot.length}',
      ),
      (await firstDevice.getFailures()).map(
        (failure) =>
            '${failure.cause}|${failure.failureReason}|'
            '${failure.treeSnapshot.length}',
      ),
      reason: '旧载荷升级不得改写失败结果与冻结要求。',
    );
  });
}
