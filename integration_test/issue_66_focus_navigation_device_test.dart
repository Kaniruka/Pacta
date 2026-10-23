import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _inspectPause = String.fromEnvironment('ISSUE66_INSPECT_PAUSE');
const _userId = 'issue-66-offline-device-fixture';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Issue 66 二级任务选择与专注流程恢复（本地设备）', (tester) async {
    final tempRoot = await getTemporaryDirectory();
    final runDirectory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}'
      'pacta-issue66-${DateTime.now().microsecondsSinceEpoch}',
    );
    await runDirectory.create();
    final screenshotDirectory = Directory(
      '${runDirectory.path}${Platform.pathSeparator}screenshots',
    );
    await screenshotDirectory.create();
    final databaseFile = File(
      '${runDirectory.path}${Platform.pathSeparator}issue66.sqlite',
    );
    final taskRemote = InMemoryTaskRemote();
    final focusRemote = InMemoryFocusRemote();
    final initialNow = DateTime.now().toUtc();
    var now = initialNow;
    var database = PactaDatabase(NativeDatabase(databaseFile));
    var tasks = LocalTaskRepository(
      database: database,
      userId: _userId,
      remote: taskRemote,
      cloudSyncEnabled: false,
      now: () => now,
    );
    var focus = LocalFocusRepository(
      database: database,
      userId: _userId,
      remote: focusRemote,
      cloudSyncEnabled: false,
      now: () => now,
    );
    var tree = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
    );

    try {
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: 'Issue 66 大量任务验收目标',
          classification: TaskClassification.both,
        ),
      );
      final seededTasks = <String, Task>{};
      for (var index = 0; index < 80; index++) {
        final classification = switch (index) {
          0 => TaskClassification.regular,
          1 => TaskClassification.elite,
          2 => TaskClassification.both,
          _ when index % 3 == 0 => TaskClassification.regular,
          _ when index % 3 == 1 => TaskClassification.elite,
          _ => TaskClassification.both,
        };
        final suffix = switch (classification) {
          TaskClassification.regular => '普通',
          TaskClassification.elite => '精锐',
          TaskClassification.both => '两者',
        };
        final title = 'I66-${index.toString().padLeft(2, '0')}-$suffix';
        seededTasks[title] = await tasks.createTask(
          goal.id,
          TaskDraft(
            title: title,
            classification: classification,
            estimatedMinutes: index == 1 ? 40 : null,
          ),
        );
      }

      // Create real local focus progress so the picker can show a non-zero value.
      final progressSession = await focus.startSession(
        taskId: seededTasks['I66-02-两者']!.id,
        mode: FocusChainMode.regular,
        duration: const Duration(hours: 1),
      );
      now = now.add(const Duration(minutes: 3));
      await focus.completeEarlySession(
        sessionId: progressSession.id,
        ruleText: 'Issue 66 本地验收样例',
      );
      // Reopen with the real wall clock so later appointment/session times are current.
      await focus.dispose();
      await tasks.dispose();
      await tree.dispose();
      await database.close();
      now = DateTime.now().toUtc();
      database = PactaDatabase(NativeDatabase(databaseFile));
      tasks = _newTaskRepository(database, taskRemote);
      focus = _newFocusRepository(database, focusRemote, () => now);
      tree = _newTreeRepository(database);

      final completedGoal = await tasks.createGoal(
        const GoalDraft(
          title: 'Issue 66 已完成任务目标',
          classification: TaskClassification.regular,
        ),
      );
      final completedTask = await tasks.createTask(
        completedGoal.id,
        const TaskDraft(
          title: 'I66-completed-excluded',
          classification: TaskClassification.both,
        ),
      );
      await tasks.setTaskCompletion(completedTask.id, isComplete: true);

      final deletedGoal = await tasks.createGoal(
        const GoalDraft(
          title: 'Issue 66 已删除任务目标',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        deletedGoal.id,
        const TaskDraft(
          title: 'I66-deleted-excluded',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.deleteGoal(deletedGoal.id);

      await _mountApp(tester, tasks, focus, tree);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      }
      await _openFocusHome(tester);
      await _capture(binding, tester, screenshotDirectory, 'issue66-overview');
      if (await _manualCheckpoint(tester, 'overview')) {
        return;
      }

      expect(find.text('I66-00-普通'), findsNothing);
      expect(find.text('I66-01-精锐'), findsNothing);
      expect(find.text('I66-02-两者'), findsNothing);
      expect(find.textContaining('可选任务'), findsOneWidget);
      expect(find.textContaining('80'), findsWidgets);

      await _openPicker(tester);
      await _capture(
        binding,
        tester,
        screenshotDirectory,
        'issue66-task-picker',
      );
      if (await _manualCheckpoint(tester, 'picker')) {
        return;
      }
      expect(find.text('选择任务'), findsWidgets);
      expect(find.text('I66-00-普通'), findsOneWidget);
      expect(find.text('I66-01-精锐'), findsOneWidget);
      expect(find.text('I66-02-两者'), findsOneWidget);
      final bottomTask = 'I66-79-${_classificationSuffix(79)}';
      await _scrollTo(tester, bottomTask);
      expect(find.text(bottomTask), findsOneWidget);
      await _scrollTo(tester, 'I66-00-普通', reverse: true);
      expect(find.text('I66-completed-excluded'), findsNothing);
      expect(find.text('I66-deleted-excluded'), findsNothing);
      expect(find.textContaining('Issue 66 大量任务验收目标'), findsWidgets);
      expect(find.textContaining('未设置'), findsWidgets);
      expect(find.textContaining('40'), findsWidgets);
      expect(find.textContaining('已专注'), findsWidgets);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(
        binding,
        tester,
        screenshotDirectory,
        'issue66-picker-large-text',
      );
      if (await _manualCheckpoint(tester, 'picker-large-text')) {
        return;
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();

      await _selectFilter(tester, '精锐');
      expect(find.text('I66-00-普通'), findsNothing);
      expect(find.text('I66-01-精锐'), findsOneWidget);
      expect(find.text('I66-02-两者'), findsOneWidget);
      expect(find.text('I66-completed-excluded'), findsNothing);
      await _selectFilter(tester, '普通');
      expect(find.text('I66-00-普通'), findsOneWidget);
      expect(find.text('I66-01-精锐'), findsNothing);
      expect(find.text('I66-02-两者'), findsOneWidget);
      await _selectFilter(tester, '全部');

      // Cancel and system back both return to the same filtered, scrolled list.
      await _selectFilter(tester, '精锐');
      final bottomElite = 'I66-79-${_classificationSuffix(79)}';
      await _scrollTo(tester, bottomElite);
      final pickerTaskY = tester.getTopLeft(find.text(bottomElite).last).dy;
      await tester.tap(find.text(bottomElite));
      await tester.pumpAndSettle();
      expect(find.text('选择任务'), findsWidgets);
      expect(find.text('开始倒计时'), findsOneWidget);
      await _capture(
        binding,
        tester,
        screenshotDirectory,
        'issue66-task-setup',
      );
      if (await _manualCheckpoint(tester, 'setup-cancel')) {
        return;
      }
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text(bottomElite), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(bottomElite).last).dy,
        closeTo(pickerTaskY, 1),
      );
      await tester.tap(find.text(bottomElite));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(bottomElite), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(bottomElite).last).dy,
        closeTo(pickerTaskY, 1),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('选择任务'), findsOneWidget);

      // Direct start; returning to the shell leaves the exact same session active.
      await _openPicker(tester);
      await _selectFilter(tester, '全部');
      await _chooseTask(tester, 'I66-00-普通');
      expect(find.text('开始倒计时'), findsOneWidget);
      await tester.tap(find.text('开始倒计时'));
      await tester.pumpAndSettle();
      final direct = (await focus.getActiveSession())!;
      final sessionCountAfterDirect = (await focus.getSessions()).length;
      await _capture(
        binding,
        tester,
        screenshotDirectory,
        'issue66-direct-session',
      );
      if (await _manualCheckpoint(tester, 'execution')) {
        return;
      }
      expect(find.text('I66-00-普通'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('选择任务'), findsOneWidget);
      expect(await focus.getActiveSession(), isNotNull);
      expect((await focus.getActiveSession())!.id, direct.id);

      // The task entry prioritizes the existing session over creating a new one.
      await _openPicker(tester);
      expect(find.text('专注进行中'), findsOneWidget);
      expect(find.text('I66-00-普通'), findsOneWidget);
      expect((await focus.getActiveSession())!.id, direct.id);
      expect((await focus.getSessions()).length, sessionCountAfterDirect);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await focus.pauseSession(direct.id, ruleText: 'Issue 66 恢复验证');
      await tasks.setTaskCompletion(
        seededTasks['I66-00-普通']!.id,
        isComplete: true,
      );
      await tester.pumpAndSettle();
      expect((await focus.getSession(direct.id))!.isPaused, isTrue);

      // A file-backed reopen proves the paused session survives an app/repository rebuild.
      await _unmountAndClose(tester, tasks, focus, tree, database);
      database = PactaDatabase(NativeDatabase(databaseFile));
      tasks = _newTaskRepository(database, taskRemote);
      focus = _newFocusRepository(database, focusRemote, () => now);
      tree = _newTreeRepository(database);
      final persistedPaused = await focus.getActiveSession();
      expect(persistedPaused?.id, direct.id);
      expect(persistedPaused?.isPaused, isTrue);
      await _mountApp(tester, tasks, focus, tree);
      await _openFocusHome(tester);
      await _openPicker(tester);
      expect(find.text('专注进行中'), findsOneWidget);
      expect(find.textContaining('本次专注已暂停'), findsOneWidget);
      expect((await focus.getActiveSession())!.id, direct.id);
      expect((await focus.getSession(direct.id))!.isPaused, isTrue);
      expect((await focus.getSessions()).length, sessionCountAfterDirect);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await focus.abandonSession(
        sessionId: direct.id,
        failureReason: 'Issue 66 设备验收清理',
      );

      // Appointment recovery uses another goal so its original task can be deleted alone.
      final appointmentGoal = await tasks.createGoal(
        const GoalDraft(
          title: 'Issue 66 已删除预约任务目标',
          classification: TaskClassification.regular,
        ),
      );
      final appointmentTask = await tasks.createTask(
        appointmentGoal.id,
        const TaskDraft(
          title: 'I66-appointment-deleted',
          classification: TaskClassification.regular,
        ),
      );
      await _openPicker(tester);
      await _chooseTask(tester, appointmentTask.title);
      expect(find.textContaining('开始准备'), findsOneWidget);
      await tester.tap(find.textContaining('开始准备').first);
      await tester.pumpAndSettle();
      final appointment = (await focus.getActiveAppointment())!;
      expect(appointment.taskId, appointmentTask.id);
      await _capture(
        binding,
        tester,
        screenshotDirectory,
        'issue66-appointment',
      );
      if (await _manualCheckpoint(tester, 'appointment')) {
        return;
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tasks.deleteGoal(appointmentGoal.id);
      await _openPicker(tester);
      expect(find.text('预约准备'), findsOneWidget);
      expect((await focus.getActiveAppointment())!.id, appointment.id);
      expect((await focus.getActiveAppointment())!.taskId, appointmentTask.id);
      expect(await focus.getActiveSession(), isNull);
      expect((await focus.getAppointments()).length, 1);

      // Early entry from the restored appointment keeps its identity on the session.
      await tester.tap(find.text('提前进入专注'));
      await tester.pumpAndSettle();
      final enteredSession = (await focus.getActiveSession())!;
      expect(enteredSession.appointmentId, appointment.id);
      expect(enteredSession.taskId, appointmentTask.id);
      final totalSessions = (await focus.getSessions()).length;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('选择任务'), findsOneWidget);
      expect((await focus.getActiveSession())!.id, enteredSession.id);
      expect((await focus.getSessions()).length, totalSessions);

      // Reopen the database a second time and check the linked appointment/session IDs.
      await _unmountAndClose(tester, tasks, focus, tree, database);
      database = PactaDatabase(NativeDatabase(databaseFile));
      tasks = _newTaskRepository(database, taskRemote);
      focus = _newFocusRepository(database, focusRemote, () => now);
      tree = _newTreeRepository(database);
      final persistedEnteredSession = await focus.getActiveSession();
      expect(persistedEnteredSession?.id, enteredSession.id);
      expect(persistedEnteredSession?.appointmentId, appointment.id);
      expect(persistedEnteredSession?.taskId, appointmentTask.id);
      expect((await focus.getAppointments()).single.id, appointment.id);
      await _mountApp(tester, tasks, focus, tree);
      await _openFocusHome(tester);
      await _openPicker(tester);
      expect(find.text('专注进行中'), findsOneWidget);
      expect((await focus.getActiveSession())!.id, enteredSession.id);
      expect((await focus.getSessions()).length, totalSessions);
      await _capture(
        binding,
        tester,
        screenshotDirectory,
        'issue66-restored-execution',
      );
      expect(tester.takeException(), isNull);
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await focus.dispose();
      await tasks.dispose();
      await tree.dispose();
      await database.close();
      if (await databaseFile.exists()) await databaseFile.delete();
    }
  });
}

Future<void> _mountApp(
  WidgetTester tester,
  LocalTaskRepository tasks,
  LocalFocusRepository focus,
  LocalNationalFocusRepository tree,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('issue66-screenshot-root'),
      child: PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _userId,
        focusNotificationService: DisabledFocusNotificationService(),
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmountAndClose(
  WidgetTester tester,
  LocalTaskRepository tasks,
  LocalFocusRepository focus,
  LocalNationalFocusRepository tree,
  PactaDatabase database,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await focus.dispose();
  await tasks.dispose();
  await tree.dispose();
  await database.close();
}

LocalTaskRepository _newTaskRepository(
  PactaDatabase database,
  InMemoryTaskRemote remote,
) => LocalTaskRepository(
  database: database,
  userId: _userId,
  remote: remote,
  cloudSyncEnabled: false,
);

LocalFocusRepository _newFocusRepository(
  PactaDatabase database,
  InMemoryFocusRemote remote,
  DateTime Function() now,
) => LocalFocusRepository(
  database: database,
  userId: _userId,
  remote: remote,
  cloudSyncEnabled: false,
  now: now,
);

LocalNationalFocusRepository _newTreeRepository(PactaDatabase database) =>
    LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
    );

Future<void> _openFocusHome(WidgetTester tester) async {
  final navigation = find.byWidgetPredicate(
    (widget) => widget is NavigationBar || widget is NavigationRail,
  );
  final focusDestination = find.descendant(
    of: navigation,
    matching: find.text('专注链'),
  );
  if (focusDestination.evaluate().isNotEmpty) {
    await tester.tap(focusDestination.last);
    await tester.pumpAndSettle();
  }
  expect(find.text('专注链'), findsWidgets);
}

Future<void> _openPicker(WidgetTester tester) async {
  final entry = find.text('选择任务');
  expect(entry, findsWidgets);
  await tester.tap(entry.first);
  await tester.pumpAndSettle();
}

Future<void> _chooseTask(WidgetTester tester, String title) async {
  final target = find.text(title);
  if (target.evaluate().isEmpty) {
    await _scrollTo(tester, title);
  }
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle();
}

Future<void> _selectFilter(WidgetTester tester, String label) async {
  final target = find.text(label);
  expect(target, findsWidgets);
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(
  WidgetTester tester,
  String title, {
  bool reverse = false,
}) async {
  final target = find.text(title);
  if (target.evaluate().isNotEmpty) {
    final bounds = tester.getRect(target.last);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (bounds.top >= 0 && bounds.bottom <= size.height) {
      return;
    }
  }
  await tester.scrollUntilVisible(
    target,
    reverse ? 400 : -400,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

String _classificationSuffix(int index) => switch (index % 3) {
  0 => '普通',
  1 => '精锐',
  _ => '两者',
};

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Directory screenshotDirectory,
  String name,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('issue66-screenshot-root')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Unable to encode screenshot: $name');
  final file = File(
    '${screenshotDirectory.path}${Platform.pathSeparator}$name.png',
  );
  await file.writeAsBytes(bytes.buffer.asUint8List());
  // ignore: avoid_print
  print('ISSUE66_SCREENSHOT:${file.path}');
  if (Platform.isAndroid) {
    await tester.pump();
    await binding.takeScreenshot(name);
  }
}

Future<bool> _manualCheckpoint(WidgetTester tester, String stage) async {
  if (_inspectPause != stage) {
    return false;
  }
  // Bounded pause lets the host use real platform input at one selected stage.
  // ignore: avoid_print
  print('ISSUE66_INSPECT_PAUSE:$stage');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 45)),
  );
  return true;
}
