import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T14 独立国策节点离线点亮、每日确认、漏确认结算并跨重启保留记录', (tester) async {
    const userId = 'ticket-14-user';
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'pacta-ticket-14-',
    );
    final databaseFile = File('${temporaryDirectory.path}/pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(databaseFile));
    var now = DateTime.utc(2026, 9, 25, 19, 59);
    final repositories = <LocalNationalFocusRepository>[];
    LocalNationalFocusRepository createRepository(String requestedUserId) {
      final repository = LocalNationalFocusRepository(
        database: database,
        userId: requestedUserId,
        now: () => now,
      );
      repositories.add(repository);
      return repository;
    }

    final auth = FakeAuthRepository()..signedInUser = userId;
    final setupRepository = createRepository(userId);
    final firstCard = await setupRepository.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始工作前', action: '写下第一步'),
    );
    final secondCard = await setupRepository.createCard(
      const NationalFocusCardDraft(triggerCondition: '午饭后', action: '读十分钟'),
    );
    await setupRepository.placeCard(cardId: firstCard.id, parentId: null);
    await setupRepository.placeCard(cardId: secondCard.id, parentId: null);

    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          nationalFocusRepositoryFactory: createRepository,
        ),
      );
      await tester.pumpAndSettle();
      final treeDestination = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('国策树'),
      );
      await tester.tap(treeDestination);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('点亮').first);
      await tester.tap(find.text('点亮').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('点亮').first);
      await tester.tap(find.text('点亮').first);
      await tester.pumpAndSettle();
      expect(
        (await setupRepository.getTreeCards()).where(
          (card) => card.state == NationalFocusCardState.lit,
        ),
        hasLength(2),
      );

      now = DateTime.utc(2026, 9, 25, 20);
      await setupRepository.settleDueCheckpoints();
      await tester.pumpAndSettle();
      final confirmationAction = find.text('确认今日继续有效').first;
      if (Platform.isWindows) {
        await tester.ensureVisible(confirmationAction);
        final button = tester.widget<FilledButton>(
          find
              .ancestor(
                of: confirmationAction,
                matching: find.byType(FilledButton),
              )
              .first,
        );
        expect(button.onPressed, isNotNull);
        await setupRepository.lightCard(firstCard.id);
      } else {
        await tester.tap(confirmationAction);
      }
      await tester.pumpAndSettle();
      expect(
        (await setupRepository.getCard(firstCard.id)).state,
        NationalFocusCardState.lit,
      );

      now = DateTime.utc(2026, 9, 26, 20);
      await setupRepository.settleDueCheckpoints();
      await tester.pumpAndSettle();
      final firstAfterSettlement = await setupRepository.getCard(firstCard.id);
      final missedAfterSettlement = await setupRepository.getCard(
        secondCard.id,
      );
      expect(
        firstAfterSettlement.state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
      expect(firstAfterSettlement.successfulDays, 2);
      expect(missedAfterSettlement.state, NationalFocusCardState.extinguished);
      expect(missedAfterSettlement.currentConsecutiveDays, 0);
      expect(missedAfterSettlement.bestConsecutiveDays, 1);

      final failure = (await setupRepository.getFailures()).single;
      expect(failure.cause, NationalFocusFailureCause.missedConfirmation);
      expect(failure.treeSnapshot, hasLength(2));
      await tester.tap(find.text('查看失败记录'));
      await tester.pumpAndSettle();
      expect(find.text('国策失败记录'), findsOneWidget);
      expect(find.textContaining('· 1 个节点'), findsOneWidget);
      await tester.tap(find.textContaining('· 1 个节点'));
      await tester.pumpAndSettle();
      expect(find.text('检查点时的完整树快照'), findsOneWidget);
      if (Platform.isWindows) {
        await setupRepository.updateFailureExplanation(
          batchId: failure.batchId,
          explanation: '临时处理紧急事务',
        );
      } else {
        await tester.tap(find.text('补充说明'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '临时处理紧急事务');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
      }
      expect(
        (await setupRepository.getFailures()).single.sharedExplanation,
        '临时处理紧急事务',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await setupRepository.dispose();
      await database.close();
      database = PactaDatabase(NativeDatabase(databaseFile));
      final restartedRepository = createRepository(userId);
      expect(
        (await restartedRepository.getCard(missedAfterSettlement.id))
            .successfulDays,
        1,
      );
      expect(
        (await restartedRepository.getFailures()).single.sharedExplanation,
        '临时处理紧急事务',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final repository in repositories) {
        await repository.dispose();
      }
      await database.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });
}
