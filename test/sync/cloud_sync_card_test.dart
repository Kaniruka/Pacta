import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_card.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  setUpAll(() {
    // Each simulated device has its own independent in-memory executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  testWidgets('首次上传需要方向选择和覆盖确认，取消不写云端', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryCloudSnapshotRemote();
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
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
    await tester.tap(find.text('查看云端并选择方向'));
    await tester.pumpAndSettle();
    expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '下载'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('上传'));
    await tester.pumpAndSettle();
    expect(find.text('上传并覆盖云端？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await remote.inspect(userId: 'user-a'), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets('云端较旧也可明确下载覆盖，并显示设备来源', (tester) async {
    final phone = PactaDatabase(NativeDatabase.memory());
    final desktop = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryCloudSnapshotRemote();
    final phoneTasks = LocalTaskRepository(
      database: phone,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => DateTime.utc(2026, 10, 4, 10),
    );
    final desktopTasks = LocalTaskRepository(
      database: desktop,
      userId: 'user-a',
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
      userId: 'user-a',
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
      userId: 'user-a',
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
    await tester.tap(find.text('查看云端并选择方向'));
    await tester.pumpAndSettle();
    expect(find.text('云端来源：家里的电脑'), findsOneWidget);
    expect(find.text('本地数据时间较新，请选择要保留的数据。'), findsOneWidget);
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.text('下载并覆盖本地？'), findsOneWidget);
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
      userId: 'user-a',
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
    await tester.ensureVisible(find.text('查看云端并选择方向'));
    await tester.tap(find.text('查看云端并选择方向'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('下载'), findsOneWidget);
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
