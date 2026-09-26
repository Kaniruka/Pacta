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

  testWidgets(
    'purge requires an eligible user and explicit irreversible confirmation',
    (tester) async {
      final auth = FakeAuthRepository()
        ..administrator = true
        ..managedUsers = [
          ManagedUserLifecycle(
            userId: 'eligible-user',
            email: 'member@example.test',
            createdAt: DateTime.utc(2026, 8, 1),
            isSuspended: true,
            suspendedAt: DateTime.utc(2026, 8, 1),
            purgeEligibleAt: DateTime.utc(2026, 8, 31),
            isEligibleForPurge: true,
          ),
          ManagedUserLifecycle(
            userId: 'not-yet-eligible-user',
            email: 'waiting@example.test',
            createdAt: DateTime.utc(2026, 8, 1),
            isSuspended: true,
            purgeEligibleAt: DateTime.utc(2026, 9, 30),
            isEligibleForPurge: false,
          ),
        ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminUserLifecycleCard(repository: auth)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('永久清除'), findsOneWidget);
      expect(find.text('清除云端身份'), findsNothing);
      await tester.tap(find.text('永久清除'));
      await tester.pumpAndSettle();

      expect(find.text('确认不可逆清除'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('member@example.test'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('离线设备'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(auth.purgedUserIds, isEmpty);

      await tester.tap(find.text('永久清除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除云端身份'));
      await tester.pumpAndSettle();

      expect(auth.purgedUserIds, ['eligible-user']);
      expect(find.text('member@example.test'), findsNothing);
      expect(find.text('waiting@example.test'), findsOneWidget);
    },
  );

  testWidgets('a failed purge leaves the target listed and shows the error', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..purgeError = StateError('service unavailable')
      ..managedUsers = [
        ManagedUserLifecycle(
          userId: 'eligible-user',
          email: 'member@example.test',
          createdAt: DateTime.utc(2026, 8, 1),
          isSuspended: true,
          isEligibleForPurge: true,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminUserLifecycleCard(repository: auth)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久清除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除云端身份'));
    await tester.pumpAndSettle();

    expect(auth.purgedUserIds, ['eligible-user']);
    expect(find.text('member@example.test'), findsOneWidget);
    expect(find.textContaining('service unavailable'), findsOneWidget);
  });
}
