import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

const _userId = 'manual-cloud-device-user';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() {
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

  testWidgets(
    'signing out during upload suppresses stale completion feedback',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = _StreamingAuthRepository()..signedInUser = _userId;
      final cloudRemote = _TrackingCloudSnapshotRemote()
        ..uploadGate = Completer<void>();
      final cloudRepository = CloudSnapshotRepository(
        database: database,
        remote: cloudRemote,
        userId: _userId,
        deviceId: 'device-a',
        deviceName: 'Device A',
      );
      try {
        await tester.pumpWidget(
          PactaApp(
            authRepository: auth,
            taskRepositoryFactory: (userId) => LocalTaskRepository(
              database: database,
              userId: userId,
              remote: InMemoryTaskRemote(),
              cloudSyncEnabled: false,
            ),
            focusRepositoryFactory: (userId) => LocalFocusRepository(
              database: database,
              userId: userId,
              remote: InMemoryFocusRemote(),
              cloudSyncEnabled: false,
            ),
            nationalFocusRepositoryFactory: (userId) =>
                LocalNationalFocusRepository(
                  database: database,
                  userId: userId,
                  cloudSyncEnabled: false,
                ),
            calendarRepositoryFactory: (userId) => LocalCalendarRepository(
              database: database,
              userId: userId,
              provider: const UnsupportedCalendarProvider(),
              remote: InMemoryCalendarRemote(),
              cloudSyncEnabled: false,
            ),
            cloudSnapshotRepositoryFactory: (_) => cloudRepository,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('上传'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认上传'));
        await tester.pumpAndSettle();
        expect(find.text('处理中…'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('退出登录'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('退出登录'));
        await tester.pumpAndSettle();
        expect(find.byType(AuthScreen), findsOneWidget);
        cloudRemote.uploadGate!.complete();
        await tester.pumpAndSettle();
        expect((await cloudRemote.inspect(userId: _userId))!.revision, 1);
        expect(find.text('上传完成，已覆盖云端数据。'), findsNothing);
        expect(find.textContaining('数据已上传，但本机同步记录未保存'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await auth.changes.close();
        await database.close();
      }
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$platform $brightness: explicit sync and persisted summary through AppShell',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.platformDispatcher.clearPlatformBrightnessTestValue();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final database = PactaDatabase(NativeDatabase.memory());
          final cloudRemote = _TrackingCloudSnapshotRemote();
          final resultStore = _FailingResultStore();
          final cloudRepository = CloudSnapshotRepository(
            database: database,
            remote: cloudRemote,
            syncResultStore: resultStore,
            userId: _userId,
            deviceId: 'android-emulator-device',
            deviceName: 'Android emulator test mirror',
            deviceManufacturer: platform == TargetPlatform.android
                ? 'google'
                : 'ASUSTeK COMPUTER INC.',
            deviceModel: platform == TargetPlatform.android
                ? 'Pixel 8'
                : 'ASUS TUF Gaming A15 FA507UV_FA507UV',
            now: () => DateTime(2026, 10, 23, 12, 34, 56),
          );
          final taskSeeder = LocalTaskRepository(
            database: database,
            userId: _userId,
            remote: InMemoryTaskRemote(),
            cloudSyncEnabled: false,
          );
          final goal = await taskSeeder.createGoal(
            const GoalDraft(
              title: 'Device snapshot before upload',
              classification: TaskClassification.regular,
            ),
          );
          final task = await taskSeeder.createTask(
            goal.id,
            const TaskDraft(title: 'Local business row', classification: null),
          );
          await taskSeeder.dispose();

          Future<void> closeApp() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await database.close();
          }

          try {
            await tester.pumpWidget(
              PactaApp(
                authRepository: FakeAuthRepository()..signedInUser = _userId,
                taskRepositoryFactory: (userId) => LocalTaskRepository(
                  database: database,
                  userId: userId,
                  remote: InMemoryTaskRemote(),
                  cloudSyncEnabled: false,
                ),
                focusRepositoryFactory: (userId) => LocalFocusRepository(
                  database: database,
                  userId: userId,
                  remote: InMemoryFocusRemote(),
                  cloudSyncEnabled: false,
                ),
                nationalFocusRepositoryFactory: (userId) =>
                    LocalNationalFocusRepository(
                      database: database,
                      userId: userId,
                      cloudSyncEnabled: false,
                    ),
                calendarRepositoryFactory: (userId) => LocalCalendarRepository(
                  database: database,
                  userId: userId,
                  provider: const UnsupportedCalendarProvider(),
                  remote: InMemoryCalendarRemote(),
                  cloudSyncEnabled: false,
                ),
                cloudSnapshotRepositoryFactory: (_) => cloudRepository,
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
            await tester.pumpAndSettle();
            expect(find.byType(AppShell), findsOneWidget);
            expect(cloudRemote.inspectCalls, 0);

            final localBeforeUpload = await cloudRepository.captureLocalState();
            expect(localBeforeUpload.rowCount, greaterThanOrEqualTo(2));

            await tester.tap(find.text('我的'));
            await tester.pumpAndSettle();
            expect(find.text('尚未同步'), findsOneWidget);
            await tester.ensureVisible(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            expect(cloudRemote.inspectCalls, 1);
            expect(
              find.byType(BottomSheet),
              platform == TargetPlatform.android
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(find.textContaining('尚无可靠的本地同步基线'), findsOneWidget);
            expect(
              find.text('本地记录：${localBeforeUpload.rowCount} 条'),
              findsOneWidget,
            );
            expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);

            await tester.tap(find.text('上传'));
            await tester.pumpAndSettle();
            expect(find.text('上传并覆盖云端？'), findsOneWidget);
            await tester.tap(find.text('确认上传'));
            await tester.pumpAndSettle();
            expect(cloudRemote.uploadCalls, 1);
            expect(find.text('上传完成，已覆盖云端数据。'), findsOneWidget);
            expect(find.text('2026-10-23 12:34:56'), findsOneWidget);
            final successfulTime =
                (await cloudRepository.loadSyncResult())!.succeededAt;

            await (database.update(
              database.localGoals,
            )..where((row) => row.userId.equals(_userId))).write(
              const LocalGoalsCompanion(
                title: Value('Local-only edit to replace'),
              ),
            );
            await tester.tap(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            expect(
              find.text('云端来源：Android emulator test mirror'),
              findsOneWidget,
            );
            expect(
              find.text(
                platform == TargetPlatform.android ? 'google · Pixel 8' : 'ASUSTeK COMPUTER INC. · ASUS TUF Gaming A15 FA507UV_FA507UV',
              ),
              findsOneWidget,
            );
            expect(find.text('本机有尚未同步的修改；下载将丢弃这些修改。'), findsOneWidget);
            expect(
              (await cloudRepository.loadSyncResult())!.succeededAt,
              successfulTime,
            );
            await tester.tap(find.text('下载'));
            await tester.pumpAndSettle();
            expect(find.text('下载并覆盖本地？'), findsOneWidget);
            final failResultSave =
                platform == TargetPlatform.windows &&
                brightness == Brightness.dark;
            resultStore.failSave = failResultSave;
            await tester.tap(find.text('确认下载'));
            await tester.pumpAndSettle();
            expect(cloudRemote.downloadCalls, 1);
            if (failResultSave) {
              expect(find.textContaining('数据已下载，但本机同步记录未保存'), findsWidgets);
              expect(find.textContaining('同步未完成'), findsNothing);
              expect(resultStore.successfulSaves, 1);
              await tester.tap(find.text('看板'));
              await tester.pumpAndSettle();
              expect(
                find.text('Device snapshot before upload'),
                findsOneWidget,
              );
              expect(find.text('Local-only edit to replace'), findsNothing);
              expect(
                (await cloudRepository.loadSyncResult())!.succeededAt,
                successfulTime,
              );
              return;
            }
            expect(find.text('下载完成，已覆盖本机数据。'), findsOneWidget);

            final restoredGoal = await (database.select(
              database.localGoals,
            )..where((row) => row.userId.equals(_userId))).getSingle();
            expect(restoredGoal.title, 'Device snapshot before upload');
            await tester.tap(find.text('看板'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('我的'));
            await tester.pumpAndSettle();
            expect(find.text('2026-10-23 12:34:56'), findsOneWidget);
            await cloudRemote.publishOtherDevice();
            await tester.tap(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            expect(find.text('型号未知'), findsOneWidget);
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
            expect(find.text('云端有待处理更新'), findsOneWidget);
            expect(
              (await cloudRepository.loadSyncResult())!.succeededAt,
              successfulTime,
            );
            final focusSeeder = LocalFocusRepository(
              database: database,
              userId: _userId,
              remote: InMemoryFocusRemote(),
              cloudSyncEnabled: false,
            );
            await focusSeeder.startAppointment(
              taskId: task.id,
              mode: FocusChainMode.regular,
              duration: const Duration(minutes: 25),
            );
            await tester.tap(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            expect(find.text('本机有未结束的专注或预约，请先处理后再下载。'), findsOneWidget);
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, '下载'),
                  )
                  .onPressed,
              isNull,
            );
            await tester.tap(find.text('上传'));
            await tester.pumpAndSettle();
            expect(find.text('上传并覆盖云端？'), findsOneWidget);
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
            await focusSeeder.dispose();
            await tester.tap(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('上传'));
            await tester.pumpAndSettle();
            await (database.update(
              database.localGoals,
            )..where((row) => row.userId.equals(_userId))).write(
              const LocalGoalsCompanion(title: Value('Changed after preview')),
            );
            await tester.tap(find.text('确认上传'));
            await tester.pumpAndSettle();
            expect(find.textContaining('请重新查看云端数据后再选择方向'), findsOneWidget);
            expect(cloudRemote.uploadCalls, 1);
            expect(
              (await cloudRepository.loadSyncResult())!.succeededAt,
              successfulTime,
            );
            cloudRemote.failInspect = true;
            await tester.tap(find.byTooltip('查看云端并选择方向'));
            await tester.pumpAndSettle();
            expect(find.textContaining('同步未完成'), findsOneWidget);
            expect(
              (await cloudRepository.loadSyncResult())!.succeededAt,
              successfulTime,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await closeApp();
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
}

class _TrackingCloudSnapshotRemote extends InMemoryCloudSnapshotRemote {
  Completer<void>? uploadGate;
  bool failInspect = false;
  Future<void> publishOtherDevice() async {
    final snapshot = await super.download(userId: _userId);
    await super.upload(
      userId: _userId,
      expectedRevision: snapshot.revision,
      payload: snapshot.payload!,
      deviceId: 'other-device',
      deviceName: '另一台设备',
      dataUpdatedAt: snapshot.dataUpdatedAt,
      rowCount: snapshot.rowCount,
    );
  }

  int inspectCalls = 0;
  int uploadCalls = 0;
  int downloadCalls = 0;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) {
    inspectCalls++;
    if (failInspect) throw StateError('测试网络不可用');
    return super.inspect(userId: userId);
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
    String? deviceManufacturer,
    String? deviceModel,
  }) async {
    uploadCalls++;
    await uploadGate?.future;
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
    );
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    downloadCalls++;
    return super.download(userId: userId);
  }
}

class _FailingResultStore extends CloudSyncResultStore {
  bool failSave = false;
  int successfulSaves = 0;
  @override
  Future<void> save(String userId, CloudSyncResult result) async {
    if (failSave) throw StateError('disk full');
    await super.save(userId, result);
    successfulSaves++;
  }
}

class _StreamingAuthRepository extends FakeAuthRepository {
  final changes = StreamController<String?>.broadcast();
  @override
  Stream<String?> get authState => changes.stream;
  @override
  Future<void> signOut() async {
    await super.signOut();
    changes.add(null);
  }
}
