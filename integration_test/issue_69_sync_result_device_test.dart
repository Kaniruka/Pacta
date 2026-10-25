import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _phase = String.fromEnvironment('ISSUE69_PHASE', defaultValue: 'write');
const _run = String.fromEnvironment('ISSUE69_RUN', defaultValue: '20261023');
const _user = 'issue69-native-$_run';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Issue69 native sync result $_phase', (tester) async {
    final root = await getApplicationSupportDirectory();
    final file = File('${root.path}/issue69-$_run.sqlite');
    final database = PactaDatabase(NativeDatabase(file));
    final remote = InMemoryCloudSnapshotRemote();
    final auth = FakeAuthRepository()..signedInUser = _user;
    var syncTime = _phase == 'cross-entry'
        ? DateTime(2026, 10, 26, 10)
        : DateTime.now();
    final sync = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: _user,
      deviceId: 'issue69-${Platform.operatingSystem}',
      deviceName: 'Issue69 isolated native device',
      now: () => _phase == 'cross-entry' ? syncTime : DateTime.now(),
    );
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
    );
    try {
      if (_phase == 'write') {
        await tasks.createGoal(
          const GoalDraft(
            title: 'Issue69 preserved native goal',
            classification: TaskClassification.regular,
          ),
        );
      } else if (_phase == 'cross-entry') {
        await tasks.createGoal(
          const GoalDraft(
            title: 'Issue69 cross-entry original goal',
            classification: TaskClassification.regular,
          ),
        );
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('issue69-capture'),
          child: PactaApp(
            authRepository: auth,
            userLifecycleRepositoryFactory: (userId) => UserLifecycleRepository(
              authRepository: auth,
              localAccess: LocalUserLifecycleAccess(
                database: database,
                userId: userId,
              ),
            ),
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
            cloudSnapshotRepositoryFactory: (_) => sync,
            focusNotificationService: DisabledFocusNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigation = find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is NavigationRail,
      );
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('我的')).last,
      );
      await tester.pumpAndSettle();
      if (_phase == 'write') {
        expect(find.text('尚未同步'), findsOneWidget);
        await _open(tester);
        await _capture(tester, 'choice');
        // Native platform return/cancel must leave the destination untouched.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('选择同步方式'), findsNothing);
        expect(await remote.inspect(userId: _user), isNull);
        await _open(tester);
        await tester.tap(find.text('上传'));
        await tester.pumpAndSettle();
        await _capture(tester, 'confirmation');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await remote.inspect(userId: _user), isNull);
        await _open(tester);
        await tester.tap(find.text('上传'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认上传'));
        await tester.pumpAndSettle();
        expect(find.text('上传完成，已覆盖云端数据。'), findsOneWidget);
        expect(find.text('尚未同步'), findsNothing);
        final saved = await sync.loadSyncResult();
        expect(saved, isNotNull);
        await File('${root.path}/issue69-$_run-result.txt')
            .writeAsString(saved!.succeededAt.toIso8601String());
      } else if (_phase == 'cross-entry') {
        expect(find.text('尚未同步'), findsOneWidget);
        await _openAiSyncEntry(tester);
        await _uploadThroughAiEntry(tester);
        await _returnTwice(tester);
        expect(find.text('2026-10-26 10:00:00'), findsOneWidget);
        await _capture(tester, 'cross-entry-first-summary');

        await tester.tap(find.text('看板').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('新建目标'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '目标名称'),
          'Issue69 changed between uploads',
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('我的').last);
        await tester.pumpAndSettle();
        await _open(tester);
        expect(find.text('本机有尚未同步的修改；下载将丢弃这些修改。'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        syncTime = DateTime(2026, 10, 26, 11, 30);
        await _openAiSyncEntry(tester);
        await _uploadThroughAiEntry(tester);
        await _returnTwice(tester);
        expect(find.text('2026-10-26 11:30:00'), findsOneWidget);
        expect(find.text('2026-10-26 10:00:00'), findsNothing);
        await _capture(tester, 'cross-entry-second-summary');

        await _open(tester);
        expect(find.text('本机数据与上次成功同步时一致。'), findsOneWidget);
        expect(find.textContaining('本机有尚未同步的修改'), findsNothing);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('2026-10-26 11:30:00'), findsOneWidget);
      } else {
        expect(
          (await tasks.getGoals()).single.title,
          'Issue69 preserved native goal',
        );
        expect(find.text('尚未同步'), findsNothing);
        final saved = await sync.loadSyncResult();
        final previous = await File('${root.path}/issue69-$_run-result.txt')
            .readAsString();
        expect(saved!.succeededAt.toIso8601String(), previous);
        await _open(tester);
        expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('尚未同步'), findsNothing);
        expect(
          (await sync.loadSyncResult())!.succeededAt.toIso8601String(),
          previous,
        );
      }
      await _capture(tester, _phase);
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print(
        'ISSUE69_NATIVE_PASS platform=${Platform.operatingSystem} pid=$pid phase=$_phase db=${file.path}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tasks.dispose();
      await focus.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}

Future<void> _openAiSyncEntry(WidgetTester tester) async {
  await tester.tap(find.text('我的').last);
  await tester.pumpAndSettle();
  final aiEntry = find.byKey(const ValueKey('national-focus-ai-entry'));
  await tester.ensureVisible(aiEntry);
  await tester.pumpAndSettle();
  await tester.tap(aiEntry);
  await tester.pumpAndSettle();
  final syncEntry = find.text('前往手动同步');
  await tester.ensureVisible(syncEntry);
  await tester.pumpAndSettle();
  await tester.tap(syncEntry);
  await tester.pumpAndSettle();
  expect(find.text('手动同步'), findsOneWidget);
}

Future<void> _uploadThroughAiEntry(WidgetTester tester) async {
  await tester.tap(find.byTooltip('查看云端并选择方向'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('上传'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认上传'));
  await tester.pumpAndSettle();
  expect(find.text('上传完成，已覆盖云端数据。'), findsOneWidget);
}

Future<void> _returnTwice(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byTooltip('查看云端并选择方向'),
    -300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  final entry = find.byTooltip('查看云端并选择方向');
  await tester.scrollUntilVisible(
    entry,
    -300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.text('选择同步方式'), findsOneWidget);
}

Future<void> _capture(WidgetTester tester, String phase) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('issue69-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final root = await getApplicationSupportDirectory();
  await File('${root.path}/issue69-$phase.png')
      .writeAsBytes(bytes!.buffer.asUint8List());
}
