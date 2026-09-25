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

  testWidgets('T17 编辑强化要求、保留生效版本并跨重启显示', (tester) async {
    const userId = 'ticket-17-user';
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'pacta-ticket-17-',
    );
    final databaseFile = File('${temporaryDirectory.path}/pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(databaseFile));
    final repositories = <LocalNationalFocusRepository>[];
    LocalNationalFocusRepository createRepository(String requestedUserId) {
      final repository = LocalNationalFocusRepository(
        database: database,
        userId: requestedUserId,
        now: () => DateTime.utc(2026, 9, 25, 19, 59),
      );
      repositories.add(repository);
      return repository;
    }

    final auth = FakeAuthRepository()..signedInUser = userId;
    final repository = createRepository(userId);
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        triggerCondition: '完成当天阅读',
        action: '每天阅读 5 页',
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);

    try {
      await _openApp(tester, auth, createRepository);
      await _openStrengtheningManager(tester);
      await tester.tap(find.text('新建强化等级'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('strengthened-action')),
        '每天阅读 10 页',
      );
      await tester.tap(find.text('保存强化等级'));
      await tester.pumpAndSettle();

      await _reveal(tester, find.text('采用强化等级 1'));
      await tester.tap(find.text('采用强化等级 1'));
      await tester.pumpAndSettle();
      var savedCard = await repository.getCard(card.id);
      expect(savedCard.activeStrengtheningLevel, 1);
      expect(savedCard.effectiveTriggerCondition, '完成当天阅读');
      expect(savedCard.effectiveAction, '每天阅读 10 页');
      expect(savedCard.state, NationalFocusCardState.extinguished);
      expect(savedCard.successfulDays, 0);

      await _reveal(tester, find.byTooltip('编辑强化等级 1'));
      await tester.tap(find.byTooltip('编辑强化等级 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('strengthened-action')),
        '每天阅读 12 页',
      );
      await tester.tap(find.text('保存强化等级'));
      await tester.pumpAndSettle();

      savedCard = await repository.getCard(card.id);
      expect(savedCard.activeStrengtheningLevel, 1);
      expect(savedCard.effectiveAction, '每天阅读 12 页');
      expect(savedCard.requirementVersions, hasLength(3));
      expect(savedCard.requirementVersions[1].effectiveAction, '每天阅读 10 页');
      expect(savedCard.requirementVersions[1].effectiveUntil, isNotNull);
      expect(savedCard.requirementVersions[2].effectiveAction, '每天阅读 12 页');
      expect(savedCard.requirementVersions[2].effectiveUntil, isNull);
      expect(savedCard.state, NationalFocusCardState.extinguished);
      expect(savedCard.successfulDays, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final openRepository in repositories) {
        await openRepository.dispose();
      }
      repositories.clear();
      await database.close();
      database = PactaDatabase(NativeDatabase(databaseFile));
      final restartedRepository = createRepository(userId);
      final restartedCard = await restartedRepository.getCard(card.id);
      expect(restartedCard.activeStrengtheningLevel, 1);
      expect(restartedCard.effectiveTriggerCondition, '完成当天阅读');
      expect(restartedCard.effectiveAction, '每天阅读 12 页');
      expect(restartedCard.requirementVersions, hasLength(3));
      expect(restartedCard.requirementVersions[1].effectiveAction, '每天阅读 10 页');
      expect(restartedCard.requirementVersions[1].effectiveUntil, isNotNull);
      expect(restartedCard.requirementVersions[2].effectiveUntil, isNull);

      await _openApp(tester, auth, createRepository);
      await _openStrengtheningManager(tester);
      expect(find.text('每天阅读 12 页'), findsNWidgets(2));
      expect(find.text('当前采用 · 强化等级 1'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final openRepository in repositories) {
        await openRepository.dispose();
      }
      await database.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });
}

Future<void> _openApp(
  WidgetTester tester,
  FakeAuthRepository auth,
  NationalFocusRepository Function(String userId) createRepository,
) async {
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
  await tester.tap(find.text('详情'));
  await tester.pumpAndSettle();
}

Future<void> _openStrengtheningManager(WidgetTester tester) async {
  final manageButton = find.text('管理强化要求');
  await _reveal(tester, manageButton);
  await tester.tap(manageButton);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
