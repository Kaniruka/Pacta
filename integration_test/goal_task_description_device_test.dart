import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _phase = String.fromEnvironment(
  'DESCRIPTION_PHASE',
  defaultValue: 'write',
);
const _pauseSeconds = int.fromEnvironment(
  'DESCRIPTION_SCREENSHOT_PAUSE_SECONDS',
);
const _userId = 'issue64-device-fixture';
const _goalDescription = '重启后保留的目标描述';
const _taskDescription = '重启后保留的任务描述';

/// Uses an independent file, fake authentication and real app/repositories.
/// Run write then verify in separate native processes without uninstalling.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('目标任务描述设备编辑与跨进程保留：$_phase', (tester) async {
    expect(_phase, anyOf('write', 'verify'));
    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/issue64-description-fixture.sqlite');
    final database = PactaDatabase(NativeDatabase(file));
    final tasks = LocalTaskRepository(
      database: database,
      userId: _userId,
      remote: const UnavailableTaskRemoteDataSource(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _userId,
      remote: const UnavailableFocusRemoteDataSource(),
      cloudSyncEnabled: false,
    );
    final national = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      cloudSyncEnabled: false,
    );
    try {
      if (_phase == 'write') {
        expect(
          await tasks.getGoals(includeDeleted: true),
          isEmpty,
          reason: 'Fixture must be fresh; never clear a pre-existing database.',
        );
      } else {
        final restored = (await tasks.getGoals()).single;
        expect(restored.title, '设备描述验收目标');
        expect(restored.description, _goalDescription);
        expect(restored.tasks.single.title, '设备描述验收任务');
        expect(restored.tasks.single.description, _taskDescription);
      }
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = _userId,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => national,
        ),
      );
      await tester.pumpAndSettle();
      if (_phase == 'write') {
        await _tap(tester, find.text('新建目标'));
        await tester.enterText(_field('目标名称'), '设备描述验收目标');
        await tester.enterText(_field('描述（可选）'), '  新增目标\n描述  ');
        await _tap(tester, find.text('保存'));
        expect((await tasks.getGoals()).single.description, '新增目标 描述');
        await _tap(tester, find.byTooltip('编辑目标'));
        await tester.enterText(_field('描述（可选）'), '修改后的目标描述');
        await _tap(tester, find.text('保存'));
        expect((await tasks.getGoals()).single.description, '修改后的目标描述');
        await _tap(tester, find.byTooltip('编辑目标'));
        await tester.enterText(_field('描述（可选）'), '  ');
        await _tap(tester, find.text('保存'));
        expect((await tasks.getGoals()).single.description, isEmpty);
        await _tap(tester, find.byTooltip('编辑目标'));
        await tester.enterText(_field('描述（可选）'), _goalDescription);
        await _tap(tester, find.text('保存'));

        await _tap(tester, find.text('添加任务'));
        await tester.enterText(_field('任务名称'), '设备描述验收任务');
        await tester.enterText(_field('描述（可选）'), '  新增任务\r\n描述  ');
        await _tap(tester, find.text('保存'));
        expect(
          (await tasks.getGoals()).single.tasks.single.description,
          '新增任务 描述',
        );
        await _tap(tester, find.text('设备描述验收任务'));
        await tester.enterText(_field('描述（可选）'), '修改后的任务描述');
        await _tap(tester, find.text('保存'));
        expect(
          (await tasks.getGoals()).single.tasks.single.description,
          '修改后的任务描述',
        );
        await _tap(tester, find.text('设备描述验收任务'));
        await tester.enterText(_field('描述（可选）'), '');
        await _tap(tester, find.text('保存'));
        expect(
          (await tasks.getGoals()).single.tasks.single.description,
          isEmpty,
        );
        await _tap(tester, find.text('设备描述验收任务'));
        await tester.enterText(_field('描述（可选）'), _taskDescription);
        await _tap(tester, find.text('保存'));
      }
      await tester.ensureVisible(find.text(_goalDescription));
      await tester.pumpAndSettle();
      expect(find.text(_goalDescription), findsOneWidget);
      expect(find.text(_taskDescription), findsOneWidget);
      await _tap(tester, find.byTooltip('收起任务'));
      expect(find.text(_goalDescription), findsOneWidget);
      expect(find.text(_taskDescription), findsNothing);
      await _tap(tester, find.byTooltip('展开任务'));
      await _tap(tester, find.text('设备描述验收任务'));
      expect(
        tester.widget<TextField>(_field('描述（可选）')).controller!.text,
        _taskDescription,
      );
      await _tap(tester, find.text('取消'));
      expect(tester.takeException(), isNull);
      if (_pauseSeconds > 0) {
        debugPrint('ISSUE64_SCREENSHOT_READY');
        await tester.runAsync(
          () => Future<void>.delayed(Duration(seconds: _pauseSeconds)),
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tasks.dispose();
      await focus.dispose();
      await national.dispose();
      await database.close();
      await tester.pump(const Duration(milliseconds: 1));
      if (_phase == 'verify') {
        await file.delete();
      }
    }
  });
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
