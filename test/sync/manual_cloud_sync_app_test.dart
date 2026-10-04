import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

const _userId = 'manual-cloud-device-user';

void main() {
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
    'My offers explicit cloud upload and download through the real app shell',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final cloudRemote = _TrackingCloudSnapshotRemote();
      final cloudRepository = CloudSnapshotRepository(
        database: database,
        remote: cloudRemote,
        userId: _userId,
        deviceId: 'android-emulator-device',
        deviceName: 'Android emulator test mirror',
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
      await taskSeeder.createTask(
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
        await tester.ensureVisible(find.text('查看云端并选择方向'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看云端并选择方向'));
        await tester.pumpAndSettle();
        expect(cloudRemote.inspectCalls, 1);
        expect(
          find.text('本地记录：${localBeforeUpload.rowCount} 条'),
          findsOneWidget,
        );
        expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);

        await tester.tap(find.text('本地覆盖云端'));
        await tester.pumpAndSettle();
        expect(find.text('上传并覆盖云端？'), findsOneWidget);
        await tester.tap(find.text('确认上传覆盖'));
        await tester.pumpAndSettle();
        expect(cloudRemote.uploadCalls, 1);
        expect(find.text('已上传整份本地数据。'), findsOneWidget);

        await (database.update(
          database.localGoals,
        )..where((row) => row.userId.equals(_userId))).write(
          const LocalGoalsCompanion(title: Value('Local-only edit to replace')),
        );
        await tester.tap(find.text('查看云端并选择方向'));
        await tester.pumpAndSettle();
        expect(find.text('云端来源：Android emulator test mirror'), findsOneWidget);
        await tester.tap(find.text('云端覆盖本地'));
        await tester.pumpAndSettle();
        expect(find.text('下载并覆盖本地？'), findsOneWidget);
        await tester.tap(find.text('确认下载覆盖'));
        await tester.pumpAndSettle();
        expect(cloudRemote.downloadCalls, 1);
        expect(find.text('已用云端数据覆盖本地。'), findsOneWidget);

        final restoredGoal = await (database.select(
          database.localGoals,
        )..where((row) => row.userId.equals(_userId))).getSingle();
        expect(restoredGoal.title, 'Device snapshot before upload');
      } finally {
        await closeApp();
      }
    },
  );
}

class _TrackingCloudSnapshotRemote extends InMemoryCloudSnapshotRemote {
  int inspectCalls = 0;
  int uploadCalls = 0;
  int downloadCalls = 0;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) {
    inspectCalls++;
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
    );
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    downloadCalls++;
    return super.download(userId: userId);
  }
}
