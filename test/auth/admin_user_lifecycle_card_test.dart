import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/admin_user_lifecycle_card.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('administrator can suspend and restore a user', (tester) async {
    final auth = FakeAuthRepository()
      ..administrator = true
      ..managedUsers = [
        ManagedUserLifecycle(
          userId: 'managed-user',
          email: 'member@example.test',
          createdAt: DateTime.utc(2026, 8, 1),
          isSuspended: false,
          isEligibleForPurge: false,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminUserLifecycleCard(repository: auth)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('member@example.test'), findsOneWidget);
    expect(find.textContaining('正常用户'), findsOneWidget);
    await tester.tap(find.text('停用'));
    await tester.pumpAndSettle();

    expect(auth.suspendedUserIds, ['managed-user']);
    expect(find.textContaining('已停用'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(auth.restoredUserIds, ['managed-user']);
    expect(find.textContaining('正常用户'), findsOneWidget);
    expect(find.text('停用'), findsOneWidget);
  });
}
