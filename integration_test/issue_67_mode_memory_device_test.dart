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

const _phase = String.fromEnvironment('ISSUE67_PHASE', defaultValue: 'seed');
const _user = 'issue67-native-isolated';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Issue 67 native mode memory $_phase', (tester) async {
    final root = await getApplicationSupportDirectory();
    final file = File(
      '${root.path}${Platform.pathSeparator}issue67-native.sqlite',
    );
    if (_phase == 'seed' && await file.exists()) await file.delete();
    final database = PactaDatabase(NativeDatabase(file));
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
      if (_phase == 'seed') {
        final goal = await tasks.createGoal(
          const GoalDraft(
            title: 'Issue67 isolated goal',
            classification: TaskClassification.both,
          ),
        );
        await tasks.createTask(
          goal.id,
          const TaskDraft(
            title: 'I67 task',
            classification: TaskClassification.both,
          ),
        );
        expect(await focus.getLastMode(), FocusChainMode.regular);
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('issue67-capture'),
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = _user,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
            focusNotificationService: DisabledFocusNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigation = find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is NavigationRail,
      );
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('专注链')).last,
      );
      await tester.pumpAndSettle();
      if (_phase == 'seed') {
        await _setup(tester);
        _expectMode(tester, FocusChainMode.regular);
        await _mode(tester, FocusChainMode.elite);
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        expect(await focus.getLastMode(), FocusChainMode.regular);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await _setup(tester, filter: '精锐');
        _expectMode(tester, FocusChainMode.elite);
        await _mode(tester, FocusChainMode.regular);
        _expectMode(tester, FocusChainMode.regular);
        await _mode(tester, FocusChainMode.elite);
        await tester.tap(find.text('开始倒计时'));
        await tester.pumpAndSettle();
        expect((await focus.getActiveSession())?.mode, FocusChainMode.elite);
        expect(await focus.getLastMode(), FocusChainMode.elite);
        final other = LocalFocusRepository(
          database: database,
          userId: 'issue67-other',
          remote: InMemoryFocusRemote(),
          cloudSyncEnabled: false,
        );
        expect(await other.getLastMode(), FocusChainMode.regular);
        await other.dispose();
      } else if (_phase == 'direct-restart') {
        expect(await focus.getLastMode(), FocusChainMode.elite);
        final session = (await focus.getActiveSession())!;
        await tester.tap(find.text('选择任务').first);
        await tester.pumpAndSettle();
        expect(find.text('专注进行中'), findsOneWidget);
        expect((await focus.getActiveSession())?.id, session.id);
        expect(await focus.getLastMode(), FocusChainMode.elite);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await focus.abandonSession(
          sessionId: session.id,
          failureReason: 'isolated fixture',
        );
        await tester.pumpAndSettle();
        await _setup(tester);
        _expectMode(tester, FocusChainMode.elite);
        await _mode(tester, FocusChainMode.regular);
        await tester.tap(find.textContaining('开始准备').first);
        await tester.pumpAndSettle();
        expect(
          (await focus.getActiveAppointment())?.mode,
          FocusChainMode.regular,
        );
        expect(await focus.getLastMode(), FocusChainMode.regular);
      } else {
        expect(await focus.getLastMode(), FocusChainMode.regular);
        final appointment = (await focus.getActiveAppointment())!;
        await tester.tap(find.text('选择任务').first);
        await tester.pumpAndSettle();
        expect(find.text('预约准备'), findsOneWidget);
        expect((await focus.getActiveAppointment())?.id, appointment.id);
        await _capture(tester, 'restored-appointment');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await focus.cancelAppointment(
          appointmentId: appointment.id,
          failureReason: 'isolated fixture',
        );
        expect(await focus.getLastMode(), FocusChainMode.regular);
        await tester.pumpAndSettle();
        await _setup(tester, filter: '精锐');
        await database.customStatement(
          "CREATE TRIGGER issue67_fail BEFORE UPDATE ON focus_preferences BEGIN SELECT RAISE(ABORT, 'issue67 write failure'); END",
        );
        await tester.tap(find.text('开始倒计时'));
        await tester.pumpAndSettle();
        expect(find.textContaining('issue67 write failure'), findsOneWidget);
        expect(await focus.getActiveSession(), isNull);
        expect(await focus.getLastMode(), FocusChainMode.regular);
        await tester.tap(find.textContaining('开始准备').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('issue67 write failure'), findsOneWidget);
        expect(await focus.getActiveAppointment(), isNull);
        expect(await focus.getLastMode(), FocusChainMode.regular);
        await _capture(tester, 'error');
        await database.customStatement('DROP TRIGGER issue67_fail');
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        final other = LocalFocusRepository(
          database: database,
          userId: 'issue67-other',
          remote: InMemoryFocusRemote(),
          cloudSyncEnabled: false,
        );
        expect(await other.getLastMode(), FocusChainMode.regular);
        await other.dispose();
      }
      expect(tester.takeException(), isNull);
      await _capture(tester, _phase);
      // ignore: avoid_print
      print(
        'ISSUE67_NATIVE_PASS platform=${Platform.operatingSystem} pid=$pid phase=$_phase database=${file.path} mode=${await focus.getLastMode()}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await focus.dispose();
      await tasks.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}

Future<void> _setup(WidgetTester tester, {String? filter}) async {
  await tester.tap(find.text('选择任务').first);
  await tester.pumpAndSettle();
  if (filter != null) {
    await tester.tap(find.text(filter).first);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('I67 task').last);
  await tester.pumpAndSettle();
  await _capture(tester, 'setup-${filter ?? 'all'}');
}

Future<void> _capture(WidgetTester tester, String stage) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('issue67-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}${Platform.pathSeparator}issue67-$stage.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

void _expectMode(WidgetTester tester, FocusChainMode mode) {
  expect(
    find
        .descendant(
          of: find.byType(DropdownButtonFormField<FocusChainMode>),
          matching: find.text(mode.label),
        )
        .hitTestable(),
    findsOneWidget,
  );
}

Future<void> _mode(WidgetTester tester, FocusChainMode mode) async {
  await tester.tap(find.byType(DropdownButtonFormField<FocusChainMode>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode.label).last);
  await tester.pumpAndSettle();
}
