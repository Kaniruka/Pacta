import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_auto_upload.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_card.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

const _userId = 'user-a';
const _autoUploadSubtitle = '今日确认成功后上传一次；关闭即停止待上传请求。';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() {
    // Each simulated device has its own independent in-memory executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets('首次上传仍需显式覆盖确认，取消不写云端', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryCloudSnapshotRemote();
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'phone-a',
      deviceName: '我的手机',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: repository,
            onDownloaded: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);
    // 云端没有内容时没有可更新的方向，首次上传即该表面的主操作。
    expect(find.text('下载'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '上传'))
          .onPressed,
      isNotNull,
    );
    // 首份快照的含义属于覆盖确认，不占用操作面板。
    expect(find.text('本机数据将作为首份云端快照。'), findsNothing);
    await tester.ensureVisible(find.text('上传'));
    await tester.tap(find.text('上传'));
    await tester.pumpAndSettle();
    expect(find.text('上传并覆盖云端？'), findsOneWidget);
    expect(find.text('本机数据将作为首份云端快照。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await remote.inspect(userId: _userId), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets('云端较旧也可明确下载覆盖，并显示设备来源', (tester) async {
    final phone = PactaDatabase(NativeDatabase.memory());
    final desktop = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryCloudSnapshotRemote();
    final phoneTasks = LocalTaskRepository(
      database: phone,
      userId: _userId,
      remote: InMemoryTaskRemote(),
      now: () => DateTime.utc(2026, 10, 4, 10),
    );
    final desktopTasks = LocalTaskRepository(
      database: desktop,
      userId: _userId,
      remote: InMemoryTaskRemote(),
      now: () => DateTime.utc(2026, 10, 3, 10),
    );
    await phoneTasks.createGoal(
      const GoalDraft(title: '手机独有', classification: TaskClassification.both),
    );
    await desktopTasks.createGoal(
      const GoalDraft(title: '电脑记录', classification: TaskClassification.both),
    );
    final desktopSync = CloudSnapshotRepository(
      database: desktop,
      remote: remote,
      userId: _userId,
      deviceId: 'desktop-a',
      deviceName: '家里的电脑',
    );
    final state = await desktopSync.captureLocalState();
    await desktopSync.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    final phoneSync = CloudSnapshotRepository(
      database: phone,
      remote: remote,
      userId: _userId,
      deviceId: 'phone-a',
      deviceName: '手机',
    );
    var refreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: phoneSync,
            onDownloaded: () async {
              refreshed = true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    expect(find.text('云端来源：家里的电脑'), findsOneWidget);
    // 来源只显示名称与平台，不再单列设备标识或厂商型号。
    expect(find.textContaining('设备标识'), findsNothing);
    expect(find.textContaining('型号未知'), findsNothing);
    // 数据时间与新旧判断只在所选方向的确认里出现。
    expect(find.textContaining('本地数据时间较新'), findsNothing);
    await tester.ensureVisible(find.text('下载'));
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.text('下载并覆盖本地？'), findsOneWidget);
    expect(find.text('本地数据时间较新，请选择要保留的数据。'), findsOneWidget);
    expect(find.text('来源：家里的电脑'), findsOneWidget);
    await tester.tap(find.text('确认下载'));
    await tester.pumpAndSettle();
    expect((await phoneTasks.getGoals()).single.title, '电脑记录');
    expect(refreshed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await phoneTasks.dispose();
    await desktopTasks.dispose();
    await phone.close();
    await desktop.close();
  });

  testWidgets('卡片标题同时服务自动与手动同步', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = CloudSnapshotRepository(
      database: database,
      remote: InMemoryCloudSnapshotRemote(),
      userId: _userId,
      deviceId: 'phone-a',
      deviceName: '我的手机',
    );
    final coordinator = await _autoUpload(repository);
    addTearDown(coordinator.dispose);
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
    expect(find.text('数据同步'), findsOneWidget);
    expect(find.text('手动云同步'), findsNothing);
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    // 自动同步偏好与手动动作在同一张卡片的同一表面，不另起标题。
    expect(find.text('今日确认后自动上传'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets('操作面板只留来源、方向动作、自动上传偏好与历史入口', (tester) async {
    final fixture = await _CloudFixture.create();
    final coordinator = await _autoUpload(fixture.phoneSync);
    addTearDown(coordinator.dispose);
    try {
      await fixture.pump(tester, autoUpload: coordinator);
      await tester.tap(find.byTooltip('查看云同步'));
      await tester.pumpAndSettle();

      expect(find.text('云端来源：家里的电脑'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '下载'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '上传'), findsOneWidget);
      expect(find.text('今日确认后自动上传'), findsOneWidget);
      expect(
        find.text(_autoUploadSubtitle),
        findsOneWidget,
        reason: '开关副文案只保留一句必要说明。',
      );
      expect(find.text('历史备份'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);

      // 两端时间、记录数、基线判断与覆盖后果都不占用操作面板。
      for (final detail in [
        '本机数据更新：',
        '本机记录：',
        '云端数据更新：',
        '云端记录：',
        '上传时间：',
        '设备设置和登录状态不变。',
        '请选择要保留的数据',
        '丢弃',
      ]) {
        expect(
          find.textContaining(detail),
          findsNothing,
          reason: '操作面板不该铺开 $detail',
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.dispose();
    }
  });

  testWidgets('选择上传后才显示两端必要数据与云来源，取消不传输', (tester) async {
    final fixture = await _CloudFixture.create();
    try {
      await fixture.pump(tester);
      await tester.tap(find.byTooltip('查看云同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();

      expect(find.text('上传并覆盖云端？'), findsOneWidget);
      final local = await fixture.phoneSync.captureLocalState();
      expect(
        find.text('本机记录：${local.rowCount} 条'),
        findsOneWidget,
        reason: '确认必须给出本机记录数。',
      );
      expect(find.textContaining('本机数据更新：'), findsOneWidget);
      expect(find.textContaining('云端数据更新：'), findsOneWidget);
      expect(find.text('云端记录：${fixture.cloudRowCount} 条'), findsOneWidget);
      expect(find.text('来源：家里的电脑'), findsOneWidget);
      expect(
        find.text('将用本机整份业务数据替换云端数据。云端独有的记录将被丢弃，其他设备需手动下载才能更新。'),
        findsOneWidget,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.remote.uploadCalls, 1, reason: '取消不得写入云端。');
      expect(
        (await fixture.remote.inspect(userId: _userId))!.revision,
        1,
        reason: '云端版本保持准备时的状态。',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.dispose();
    }
  });

  testWidgets('选择下载后才显示覆盖后果与基线判断，取消保留待上传请求', (tester) async {
    final fixture = await _CloudFixture.create();
    final store = InMemoryCloudAutoUploadQueueStore();
    final coordinator = CloudAutoUploadCoordinator(
      userId: _userId,
      repository: fixture.phoneSync,
      preference: const CloudAutoUploadPreference(),
      queueStore: store,
      canAccess: () async => true,
      isAccessible: () async => true,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(coordinator.dispose);
    await store.save(
      _userId,
      const CloudAutoUploadQueue().recordIntent(DateTime.utc(2026, 11, 13)),
    );
    try {
      await fixture.pump(tester, autoUpload: coordinator);
      await tester.tap(find.byTooltip('查看云同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载'));
      await tester.pumpAndSettle();

      expect(find.text('下载并覆盖本地？'), findsOneWidget);
      expect(
        find.text('将用来自“家里的电脑”的整份云端业务数据替换本机数据。本机独有的记录将被丢弃。'),
        findsOneWidget,
      );
      expect(find.text('本机有尚未同步的修改；下载将丢弃这些修改。'), findsOneWidget);
      expect(find.text('来源：家里的电脑'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.remote.downloadCalls, 0, reason: '取消不得下载。');
      expect(
        (await store.load(_userId)).hasWork,
        isTrue,
        reason: '取消不得清掉既有自动上传队列。',
      );
      expect((await fixture.goalTitles()), ['手机独有']);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.dispose();
    }
  });

  testWidgets('同步记录读取失败在操作面板内可读，不当成正常状态', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = CloudSnapshotRepository(
      database: database,
      remote: InMemoryCloudSnapshotRemote(),
      userId: _userId,
      deviceId: 'phone-a',
      deviceName: '我的手机',
      syncResultStore: _ThrowingResultStore(),
    );
    var restored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: repository,
            onDownloaded: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(restored, isFalse);
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    expect(find.text('同步记录读取失败，请重新查看云端。'), findsOneWidget);
    // 读取失败不阻断手动上传这一安全动作。
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '上传'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets('320 dp和200%文字下覆盖选择仍可操作', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final database = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryCloudSnapshotRemote();
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: '12345678-1234-1234-1234-123456789abc',
      deviceName: '放在家里书房使用的个人电脑设备',
    );
    final state = await repository.captureLocalState();
    await repository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: state.fingerprint,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              CloudSyncCard(repository: repository, onDownloaded: () async {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('查看云同步'));
    await tester.tap(find.byTooltip('查看云同步'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('下载'));
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('下载并覆盖本地？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });
}

/// 与 App 组合一致的自动上传协调器：开关只在配置了云端连接的卡片里出现。
Future<CloudAutoUploadCoordinator> _autoUpload(
  CloudSnapshotRepository repository,
) async {
  final coordinator = CloudAutoUploadCoordinator(
    userId: _userId,
    repository: repository,
    preference: const CloudAutoUploadPreference(),
    queueStore: InMemoryCloudAutoUploadQueueStore(),
    canAccess: () async => true,
    isAccessible: () async => true,
    requestIdFactory: () => 'request-1',
  );
  await coordinator.load();
  return coordinator;
}

/// 两台设备的真实仓储 + 内存云端：云端已有「家里的电脑」的快照，本机另有记录。
class _CloudFixture {
  _CloudFixture._({
    required this.phone,
    required this.desktop,
    required this.remote,
    required this.tasks,
    required this.phoneSync,
    required this.cloudRowCount,
  });

  final PactaDatabase phone;
  final PactaDatabase desktop;
  final _CountingRemote remote;
  final LocalTaskRepository tasks;
  final CloudSnapshotRepository phoneSync;
  final int cloudRowCount;

  static Future<_CloudFixture> create() async {
    final phone = PactaDatabase(NativeDatabase.memory());
    final desktop = PactaDatabase(NativeDatabase.memory());
    final remote = _CountingRemote();
    final desktopTasks = LocalTaskRepository(
      database: desktop,
      userId: _userId,
      remote: InMemoryTaskRemote(),
      now: () => DateTime.utc(2026, 10, 3, 10),
    );
    await desktopTasks.createGoal(
      const GoalDraft(title: '电脑记录', classification: TaskClassification.both),
    );
    final desktopSync = CloudSnapshotRepository(
      database: desktop,
      remote: remote,
      userId: _userId,
      deviceId: 'desktop-a',
      deviceName: '家里的电脑',
    );
    final desktopState = await desktopSync.captureLocalState();
    final cloud = await desktopSync.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: desktopState.fingerprint,
    );
    await desktopTasks.dispose();

    final tasks = LocalTaskRepository(
      database: phone,
      userId: _userId,
      remote: InMemoryTaskRemote(),
      now: () => DateTime.utc(2026, 10, 4, 10),
    );
    await tasks.createGoal(
      const GoalDraft(title: '手机独有', classification: TaskClassification.both),
    );
    final phoneSync = CloudSnapshotRepository(
      database: phone,
      remote: remote,
      userId: _userId,
      deviceId: 'phone-a',
      deviceName: '我的手机',
    );
    // 旧格式基线：无法确认本机是否有未同步修改，下载确认必须说明这一点。
    await const CloudSyncResultStore().save(
      _userId,
      CloudSyncResult(
        succeededAt: DateTime.utc(2026, 10, 3, 10),
        localFingerprint: 'v2:previous-session-fingerprint',
        cloudRevision: cloud.revision,
      ),
    );
    return _CloudFixture._(
      phone: phone,
      desktop: desktop,
      remote: remote,
      tasks: tasks,
      phoneSync: phoneSync,
      cloudRowCount: cloud.rowCount,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    CloudAutoUploadCoordinator? autoUpload,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSyncCard(
            repository: phoneSync,
            autoUpload: autoUpload,
            onDownloaded: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<String>> goalTitles() async =>
      (await tasks.getGoals()).map((goal) => goal.title).toList();

  Future<void> dispose() async {
    await tasks.dispose();
    await phone.close();
    await desktop.close();
  }
}

class _ThrowingResultStore extends CloudSyncResultStore {
  @override
  Future<CloudSyncResult?> load(String userId) async {
    throw StateError('unreadable');
  }
}

class _CountingRemote extends InMemoryCloudSnapshotRemote {
  int uploadCalls = 0;
  int downloadCalls = 0;

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

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    downloadCalls++;
    return super.download(userId: userId);
  }
}
