import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/tasks/task_database.dart';
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
    expect(find.text('从任务开始一次专注'), findsOneWidget);

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
}
