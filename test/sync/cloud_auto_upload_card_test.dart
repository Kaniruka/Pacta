import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_auto_upload.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_card.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'user-a';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late PactaDatabase database;
  late _CountingRemote remote;
  late InMemoryCloudAutoUploadQueueStore store;
  late CloudSnapshotRepository repository;
  late CloudAutoUploadCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    remote = _CountingRemote();
    store = InMemoryCloudAutoUploadQueueStore();
    repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
      now: () => DateTime.utc(2026, 11, 13, 9, 30),
    );
    coordinator = CloudAutoUploadCoordinator(
      userId: _userId,
      repository: repository,
      preference: const CloudAutoUploadPreference(),
      queueStore: store,
      canAccess: () async => true,
      isAccessible: () async => true,
      requestIdFactory: () => 'request-1',
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await database.close();
  });

  Future<void> seedGoal(String title) async {
    final now = DateTime.utc(2026, 11, 13);
    await database
        .into(database.localGoals)
        .insertOnConflictUpdate(
          LocalGoalsCompanion.insert(
            userId: _userId,
            id: 'goal-$title',
            title: title,
            classification: 'regular',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: repository,
            autoUpload: coordinator,
            onDownloaded: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
  }

  testWidgets('操作层的自动上传开关默认关闭，开启后按本机用户保存', (tester) async {
    await seedGoal('Only');
    await pumpCard(tester);

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);
    expect(coordinator.enabled, isFalse);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(coordinator.enabled, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('pacta.device.cloud_auto_upload.enabled.$_userId'),
      isTrue,
    );
    expect(remote.uploadCalls, 0);
  });

  Future<void> settleAsync(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('手动从云端更新前取消待上传请求', (tester) async {
    await seedGoal('First');
    final state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await seedGoal('Second');
    await store.save(
      _userId,
      const CloudAutoUploadQueue().recordIntent(DateTime.utc(2026, 11, 13)),
    );

    await pumpCard(tester);
    await tester.ensureVisible(find.text('下载'));
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认下载'));
    await settleAsync(tester);
    await settleAsync(tester);

    expect((await store.load(_userId)).hasWork, isFalse);
    final goals = await (database.select(database.localGoals)).get();
    expect(goals.map((goal) => goal.title), ['First']);
  });

  testWidgets('自动上传被云端版本挡住时在卡片与面板提示', (tester) async {
    await seedGoal('Local');
    await remote.upload(
      userId: _userId,
      expectedRevision: 0,
      payload: const {'schemaVersion': 1, 'userId': _userId, 'tables': {}},
      deviceId: 'other-device',
      deviceName: '另一台设备（Windows）',
      dataUpdatedAt: DateTime.utc(2026, 11, 13, 8),
      rowCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: repository,
            autoUpload: coordinator,
            onDownloaded: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await coordinator.setEnabled(true);
      await coordinator.enqueue();
    });
    await tester.pumpAndSettle();

    expect(
      find.textContaining('自动上传已停止：$cloudAutoUploadUnhandledCloudReason'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('自动上传已停止：'), findsWidgets);
    expect(remote.uploadCalls, 1);
  });
}

class _CountingRemote extends InMemoryCloudSnapshotRemote {
  int uploadCalls = 0;

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  }) {
    uploadCalls++;
    return super.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt,
      rowCount: rowCount,
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      requestId: requestId,
    );
  }
}
