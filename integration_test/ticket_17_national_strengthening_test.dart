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

  testWidgets('T17 编辑强化要求、随卡片保存并跨重启显示', (tester) async {
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
        name: '完成当天阅读',
        triggerCondition: '完成当天阅读',
        action: '每天阅读 5 页',
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);

    try {
      await _openApp(tester, auth, createRepository);
      await _openStrengtheningManager(tester);
      await tester.tap(find.text('新建强化要求'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('strengthened-rule')),
        '每天阅读 10 页',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final firstLevelRow = find.byKey(
        const ValueKey('national-focus-strengthening-level-1'),
      );
      final selectFirstLevel = find.descendant(
        of: firstLevelRow,
        matching: find.text('选择'),
      );
      await _reveal(tester, selectFirstLevel);
      await tester.tap(selectFirstLevel);
      await tester.pumpAndSettle();

      await _reveal(tester, find.byTooltip('编辑强化等级 1'));
      await tester.tap(find.byTooltip('编辑强化等级 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('strengthened-rule')),
        '每天阅读 12 页',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 档位增改与选中都还是草稿：返回编辑页点唯一「保存」才落盘。
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final savedCard = await repository.getCard(card.id);
      expect(savedCard.activeStrengtheningLevel, 1);
      expect(savedCard.effectiveTriggerCondition, '完成当天阅读');
      expect(savedCard.effectiveAction, '每天阅读 12 页');
      expect(savedCard.strengtheningLevels, hasLength(1));
      expect(savedCard.strengtheningLevels.single.action, '每天阅读 12 页');
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
      expect(restartedCard.strengtheningLevels, hasLength(1));
      expect(restartedCard.strengtheningLevels.single.action, '每天阅读 12 页');

      await _openApp(tester, auth, createRepository);
      await _openStrengtheningManager(tester);
      // 顶部不再复述当前要求：同一条规则只由选中段保留一次。
      expect(find.text('每天阅读 12 页'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('national-focus-strengthening-level-1'),
          ),
          matching: find.text('正在使用'),
        ),
        findsOneWidget,
      );
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
  // Strengthening management lives behind the card editor's top-bar action.
  final editButton = find.byKey(const ValueKey('national-focus-detail-edit'));
  await _reveal(tester, editButton);
  await tester.tap(editButton);
  await tester.pumpAndSettle();
  final manageButton = find.text('强化要求');
  await _reveal(tester, manageButton);
  await tester.tap(manageButton);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
