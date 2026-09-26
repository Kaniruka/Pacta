import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/tasks/task_database.dart'
    show LocalGoalsCompanion, PactaDatabase;

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T27 startup cleanup and explicit admin purge flow', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()
      ..signedInUser = 'ticket-27-admin'
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
      ];
    final cleanup = UserPurgeCleanupRepository(
      authRepository: auth,
      database: database,
    );

    try {
      await _seedGoal(database, 'old-user-id');
      await _seedGoal(database, 'new-user-id');
      auth.lookupPurgeReceipts['old-user-id'] = UserPurgeReceipt(
        userId: 'old-user-id',
        status: UserPurgeStatus.completed,
        purgedAt: DateTime.utc(2026, 9, 26),
      );
      auth.lookupPurgeReceipts['new-user-id'] = UserPurgeReceipt(
        userId: 'new-user-id',
        status: UserPurgeStatus.pending,
        purgedAt: null,
      );

      await tester.pumpWidget(
        PactaApp(authRepository: auth, userPurgeCleanupRepository: cleanup),
      );
      await tester.pumpAndSettle();

      final cleanupCompleted = await tester.runAsync(() async {
        for (var attempt = 0; attempt < 60; attempt++) {
          if (await _goalCount(database, 'old-user-id') == 0) return true;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return false;
      });
      expect(cleanupCompleted, isTrue);
      expect(await _goalCount(database, 'new-user-id'), 1);
      expect(auth.currentUserId, 'ticket-27-admin');

      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('member@example.test'), findsOneWidget);
      await tester.ensureVisible(find.text('永久清除'));
      await tester.tap(find.text('永久清除'));
      await tester.pumpAndSettle();
      expect(find.text('确认不可逆清除'), findsOneWidget);
      expect(find.textContaining('离线设备'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(auth.purgedUserIds, isEmpty);

      await tester.ensureVisible(find.text('永久清除'));
      await tester.tap(find.text('永久清除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除云端身份'));
      await tester.pumpAndSettle();
      expect(auth.purgedUserIds, ['eligible-user']);
      expect(find.text('member@example.test'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    }
  });
}

Future<void> _seedGoal(PactaDatabase database, String userId) => database
    .into(database.localGoals)
    .insert(
      LocalGoalsCompanion.insert(
        userId: userId,
        id: 'goal-$userId',
        title: 'Local cache',
        classification: 'regular',
        createdAt: DateTime.utc(2026, 9, 26),
        updatedAt: DateTime.utc(2026, 9, 26),
      ),
    );

Future<int> _goalCount(PactaDatabase database, String userId) async =>
    (await (database.select(
      database.localGoals,
    )..where((row) => row.userId.equals(userId))).get()).length;
