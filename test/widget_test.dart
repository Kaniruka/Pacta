import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('未登录用户看到登录入口而不是伪造业务数据', (tester) async {
    await tester.pumpWidget(PactaApp(authRepository: FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('进入 Pacta'), findsOneWidget);
    expect(find.text('还没有资格？请联系管理员发放注册资格'), findsOneWidget);
    expect(find.text('示例任务'), findsNothing);
  });

  testWidgets('登录后默认进入看板并可访问四个目的地', (tester) async {
    final repository = FakeAuthRepository()..signedInUser = 'user@example.com';
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('看板'), findsWidgets);
    expect(find.text('今天先做什么'), findsOneWidget);
    expect(find.text('暂无任务'), findsOneWidget);

    await tester.tap(find.text('国策树'));
    await tester.pumpAndSettle();
    expect(find.text('国策树还是空的'), findsOneWidget);

    await tester.tap(find.text('专注链'));
    await tester.pumpAndSettle();
    expect(find.text('当前筛选下没有可开始的任务。'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('user@example.com'), findsOneWidget);
  });

  testWidgets('看板可以维护目标、任务并明确完成任务', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LocalTaskRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryTaskRemote(),
    );
    final auth = FakeAuthRepository()..signedInUser = 'user@example.com';

    await tester.pumpWidget(
      PactaApp(authRepository: auth, taskRepositoryFactory: (_) => repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建目标'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '发布版本');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('发布版本'), findsOneWidget);

    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '检查构建');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('检查构建'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('已完成'), findsOneWidget);
  });

  testWidgets('云端 UTC 截止时间按设备本地时间显示', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LocalTaskRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryTaskRemote(),
    );
    final goal = await repository.createGoal(
      const GoalDraft(
        title: '跨端目标',
        classification: TaskClassification.regular,
      ),
    );
    final deadline = DateTime.utc(2030, 1, 2, 3, 4);
    await repository.createTask(
      goal.id,
      TaskDraft(title: '云端截止任务', classification: null, deadline: deadline),
    );
    final auth = FakeAuthRepository()..signedInUser = 'user@example.com';

    await tester.pumpWidget(
      PactaApp(authRepository: auth, taskRepositoryFactory: (_) => repository),
    );
    await tester.pumpAndSettle();

    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final localDeadline = deadline.toLocal();
    final expected =
        '截止 ${localDeadline.year}-${twoDigits(localDeadline.month)}-'
        '${twoDigits(localDeadline.day)} ${twoDigits(localDeadline.hour)}:'
        '${twoDigits(localDeadline.minute)}';
    expect(find.textContaining(expected), findsOneWidget);
  });

  testWidgets('专注设置界面选择模式和时长后启动会话', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final focusRemote = InMemoryFocusRemote();
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryTaskRemote(),
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user@example.com',
      remote: focusRemote,
    );
    addTearDown(focusRepository.dispose);
    final goal = await taskRepository.createGoal(
      const GoalDraft(title: '交付', classification: TaskClassification.regular),
    );
    final task = await taskRepository.createTask(
      goal.id,
      const TaskDraft(title: '写报告', classification: TaskClassification.regular),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [focusRepositoryProvider.overrideWithValue(focusRepository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showDialog<FocusSession>(
                  context: context,
                  builder: (_) => FocusSetupDialog(
                    task: task,
                    initialMode: FocusChainMode.regular,
                  ),
                ),
                child: const Text('打开专注设置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开专注设置'));
    await tester.pumpAndSettle();
    expect(find.text('开始专注'), findsOneWidget);
    await tester.tap(find.text('开始倒计时'));
    await tester.pumpAndSettle();
    expect(await focusRepository.getActiveSession(), isNotNull);
    expect(find.text('打开专注设置'), findsOneWidget);
  });
}
