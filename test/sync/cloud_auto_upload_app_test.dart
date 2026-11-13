import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_checkpoints.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_auto_upload.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

const _userId = 'auto-upload-app-user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
  });

  Future<void> settleUi(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seedPendingConfirmation(PactaDatabase database) async {
    final checkpoint = nationalFocusCheckpointAtOrBefore(
      DateTime.now().toUtc(),
    );
    final marker = checkpoint.subtract(nationalFocusCheckpointPeriod);
    final seeding = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
      now: () => marker,
    );
    await seeding.settleDueCheckpoints();
    final card = await seeding.createCard(
      const NationalFocusCardDraft(
        name: '每日复盘',
        triggerCondition: '坐下',
        action: '写下今天的一步',
      ),
    );
    await seeding.placeCard(cardId: card.id, parentId: null);
    await seeding.lightCard(card.id);
    await seeding.dispose();
    final settling = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
      now: DateTime.now,
    );
    await settling.settleDueCheckpoints();
    await settling.dispose();
  }

  Future<void> advanceToNextCheckpoint(PactaDatabase database) async {
    final next = nationalFocusCheckpointAtOrBefore(DateTime.now().toUtc())
        .add(nationalFocusCheckpointPeriod);
    final repo = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
      now: () => next,
    );
    await repo.settleDueCheckpoints();
    await repo.dispose();
  }

  Future<void> addLitCard(PactaDatabase database, String name) async {
    final repo = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
    );
    final card = await repo.createCard(
      NationalFocusCardDraft(name: name, action: '执行「$name」'),
    );
    await repo.placeCard(cardId: card.id, parentId: null);
    await repo.lightCard(card.id);
    await repo.dispose();
  }

  PactaApp appFor(
    PactaDatabase database,
    FakeAuthRepository auth,
    CloudSnapshotRepository repository, {
    DateTime Function()? clock,
  }) => PactaApp(
    authRepository: auth,
    cloudCheckClock: clock ?? () => DateTime.utc(2026, 11, 13, 12),
    taskRepositoryFactory: (id) => LocalTaskRepository(
      database: database,
      userId: id,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    ),
    focusRepositoryFactory: (id) => LocalFocusRepository(
      database: database,
      userId: id,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
    ),
    nationalFocusRepositoryFactory: (id) => LocalNationalFocusRepository(
      database: database,
      userId: id,
      cloudSyncEnabled: false,
    ),
    calendarRepositoryFactory: (id) => LocalCalendarRepository(
      database: database,
      userId: id,
      provider: const UnsupportedCalendarProvider(),
      remote: InMemoryCalendarRemote(),
      cloudSyncEnabled: false,
    ),
    userLifecycleRepositoryFactory: (id) => UserLifecycleRepository(
      authRepository: auth,
      localAccess: LocalUserLifecycleAccess(database: database, userId: id),
    ),
    cloudSnapshotRepositoryFactory: (id) => id == repository.userId
        ? repository
        : CloudSnapshotRepository(
            database: database,
            remote: repository.remote,
            userId: id,
            deviceName: 'Other（Windows）',
          ),
  );

  testWidgets('默认关闭：批量确认不上传，开启后整批只上传一次，普通编辑不触发', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()..signedInUser = _userId;
    final remote = _TrackingRemote();
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
      now: () => DateTime.utc(2026, 11, 13, 12),
    );
    final store = const SharedPreferencesCloudAutoUploadQueueStore();
    await seedPendingConfirmation(database);
    try {
      await tester.pumpWidget(appFor(database, auth, repository));
      await settleUi(tester);

      await tester.tap(find.text('国策树'));
      await settleUi(tester);
      expect(find.text('全部确认 (1)'), findsOneWidget);
      await tester.tap(find.text('全部确认 (1)'));
      await settleUi(tester);
      expect(remote.uploadCalls, 0);

      // 下一个检查点后两张卡都待确认；在操作层开启自动上传。
      await addLitCard(database, '第二次复盘');
      await advanceToNextCheckpoint(database);
      await settleUi(tester);
      expect(find.text('全部确认 (2)'), findsOneWidget);
      await tester.tap(find.text('我的'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('查看云同步'));
      await settleUi(tester);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.byType(SwitchListTile));
      await settleUi(tester);
      expect(await const CloudAutoUploadPreference().load(_userId), isTrue);
      await tester.tap(find.text('关闭'));
      await settleUi(tester);

      await tester.tap(find.text('国策树'));
      await settleUi(tester);
      await tester.tap(find.text('全部确认 (2)'));
      await settleUi(tester);
      expect(remote.uploadCalls, 1);
      expect(await remote.history(userId: _userId), hasLength(1));
      expect((await store.load(_userId)).hasWork, isFalse);

      // 普通业务编辑不单独触发上传。
      await tester.tap(find.text('看板'));
      await settleUi(tester);
      await tester.tap(find.text('新建目标'));
      await settleUi(tester);
      await tester.enterText(find.widgetWithText(TextField, '目标名称'), '普通编辑');
      await tester.tap(find.text('保存'));
      await settleUi(tester);
      expect(remote.uploadCalls, 1);
      expect((await repository.loadSyncResult())!.cloudRevision, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      await database.close();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('未处理的云端新版本停止自动覆盖，仍需用户处理', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()..signedInUser = _userId;
    final remote = _TrackingRemote();
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
      now: () => DateTime.utc(2026, 11, 13, 12),
    );
    await remote.upload(
      userId: _userId,
      expectedRevision: 0,
      payload: const {'schemaVersion': 1, 'userId': _userId, 'tables': {}},
      deviceId: 'other-device',
      deviceName: '另一台设备（Windows）',
      dataUpdatedAt: DateTime.utc(2026, 11, 12),
      rowCount: 0,
    );
    await seedPendingConfirmation(database);
    try {
      await tester.pumpWidget(appFor(database, auth, repository));
      await settleUi(tester);
      // 冷启动的版本检查会先询问用户；忽略提示不构成覆盖授权。
      if (find.text('云端与本机').evaluate().isNotEmpty) {
        await tester.tap(find.text('关闭'));
        await settleUi(tester);
      }
      await tester.tap(find.text('我的'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('查看云同步'));
      await settleUi(tester);
      await tester.tap(find.byType(SwitchListTile));
      await settleUi(tester);
      await tester.tap(find.text('关闭'));
      await settleUi(tester);

      await tester.tap(find.text('国策树'));
      await settleUi(tester);
      await tester.tap(find.text('全部确认 (1)'));
      await settleUi(tester);
      await settleUi(tester);

      expect(remote.uploadCalls, 1);
      final queue = await const SharedPreferencesCloudAutoUploadQueueStore()
          .load(_userId);
      expect(queue.pending, isTrue);
      expect(queue.blockedReason, cloudAutoUploadUnhandledCloudReason);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      await database.close();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('离线确认后联网恢复时重试同一请求，只落一份备份', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()..signedInUser = _userId;
    final remote = _TrackingRemote()..failUploads = true;
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
      now: () => DateTime.utc(2026, 11, 13, 12),
    );
    final store = const SharedPreferencesCloudAutoUploadQueueStore();
    await seedPendingConfirmation(database);
    try {
      await tester.pumpWidget(appFor(database, auth, repository));
      await settleUi(tester);
      await tester.tap(find.text('我的'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('查看云同步'));
      await settleUi(tester);
      await tester.tap(find.byType(SwitchListTile));
      await settleUi(tester);
      await tester.tap(find.text('关闭'));
      await settleUi(tester);

      await tester.tap(find.text('国策树'));
      await settleUi(tester);
      await tester.tap(find.text('全部确认 (1)'));
      await settleUi(tester);
      await settleUi(tester);
      expect(remote.uploadCalls, 1);
      final pending = await store.load(_userId);
      expect(pending.request, isNotNull);
      final requestId = pending.request!.requestId;

      remote.failUploads = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleUi(tester);
      await settleUi(tester);

      expect(remote.requestIds, [requestId, requestId]);
      expect(await remote.history(userId: _userId), hasLength(1));
      expect((await store.load(_userId)).hasWork, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      await database.close();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('切换账号清除上一账号的待上传请求且不代为上传', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = _StreamingAuth()..signedInUser = _userId;
    final remote = _TrackingRemote()..failUploads = true;
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _userId,
      deviceId: 'device-a',
      deviceName: 'Device A（Windows）',
      now: () => DateTime.utc(2026, 11, 13, 12),
    );
    final store = const SharedPreferencesCloudAutoUploadQueueStore();
    await seedPendingConfirmation(database);
    try {
      await tester.pumpWidget(appFor(database, auth, repository));
      await settleUi(tester);
      await tester.tap(find.text('我的'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('查看云同步'));
      await settleUi(tester);
      await tester.tap(find.byType(SwitchListTile));
      await settleUi(tester);
      await tester.tap(find.text('关闭'));
      await settleUi(tester);

      await tester.tap(find.text('国策树'));
      await settleUi(tester);
      await tester.tap(find.text('全部确认 (1)'));
      await settleUi(tester);
      await settleUi(tester);
      expect(remote.uploadCalls, 1);
      expect((await store.load(_userId)).hasWork, isTrue);

      await auth.signOut();
      await settleUi(tester);
      await settleUi(tester);

      expect(find.byType(AuthScreen), findsOneWidget);
      expect((await store.load(_userId)).hasWork, isFalse);
      expect(remote.uploadCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      await auth.changes.close();
      await database.close();
      await tester.binding.setSurfaceSize(null);
    }
  });
}

class _StreamingAuth extends FakeAuthRepository {
  final changes = StreamController<String?>.broadcast();

  @override
  Stream<String?> get authState => changes.stream;

  @override
  String? get currentUserIdentifier => 'device-user@example.test';

  @override
  Future<void> signOut() async {
    await super.signOut();
    changes.add(null);
  }
}

class _TrackingRemote extends InMemoryCloudSnapshotRemote {
  final List<String?> requestIds = [];
  int uploadCalls = 0;
  bool failUploads = false;

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
    requestIds.add(requestId);
    if (failUploads) throw StateError('测试网络不可用');
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
