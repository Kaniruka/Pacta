import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('failed login leaves the existing local task cache intact', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final remote = InMemoryTaskRemote();
    final cachedTasks = LocalTaskRepository(
      database: database,
      userId: 'user@example.com',
      remote: remote,
    );
    addTearDown(cachedTasks.dispose);
    await cachedTasks.createGoal(
      const GoalDraft(
        title: 'Existing cached goal',
        classification: TaskClassification.regular,
      ),
    );

    final auth = FakeAuthRepository()
      ..signInError = StateError('Invalid login credentials');
    final app = PactaApp(
      authRepository: auth,
      taskRepositoryFactory: (userId) => LocalTaskRepository(
        database: database,
        userId: userId,
        remote: remote,
      ),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'incorrect-password');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(auth.currentUserId, isNull);

    auth.signInError = null;
    await auth.signIn(email: 'user@example.com', password: 'valid-password');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Existing cached goal'), findsOneWidget);
  });
}
