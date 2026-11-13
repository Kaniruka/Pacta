import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _userId = 'manual-cloud-device-user';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'My offers explicit cloud upload and download through the real app shell',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = _userId;
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
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 15),
        );
        await database.close();
      }

      try {
        await tester.pumpWidget(
          PactaApp(
            authRepository: auth,
            userLifecycleRepositoryFactory: (userId) => UserLifecycleRepository(
              authRepository: auth,
              localAccess: LocalUserLifecycleAccess(
                database: database,
                userId: userId,
              ),
            ),
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
        final initialChecks = cloudRemote.inspectCalls;
        expect(cloudRemote.uploadCalls, 0);
        expect(cloudRemote.downloadCalls, 0);
        final localBeforeUpload = await cloudRepository.captureLocalState();
        expect(localBeforeUpload.rowCount, greaterThanOrEqualTo(2));

        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('查看云同步'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看云同步'));
        await tester.pumpAndSettle();
        expect(cloudRemote.inspectCalls, initialChecks + 1);
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

        await (database.update(
          database.localGoals,
        )..where((row) => row.userId.equals(_userId))).write(
          const LocalGoalsCompanion(title: Value('Local-only edit to replace')),
        );
        await tester.tap(find.byTooltip('查看云同步'));
        await tester.pumpAndSettle();
        expect(find.text('云端来源：Android emulator test mirror'), findsOneWidget);
        await tester.tap(find.text('从云端更新'));
        await tester.pumpAndSettle();
        expect(find.text('下载并覆盖本地？'), findsOneWidget);
        await tester.tap(find.text('确认下载'));
        await tester.pumpAndSettle();
        expect(cloudRemote.downloadCalls, 1);
        expect(find.text('下载完成，已覆盖本机数据。'), findsOneWidget);

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
