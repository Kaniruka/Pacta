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

  testWidgets('T15 父节点级联失败、独立来源标记和历史快照跨重启保留', (tester) async {
    const userId = 'ticket-15-user';
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'pacta-ticket-15-',
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
    final repository = createRepository(userId);
    final parent = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始工作前', action: '打开计划'),
    );
    final child = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '计划打开后', action: '先做第一项'),
    );
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);

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

      final parentExtinguish = find.text('主动熄灭').first;
      await tester.ensureVisible(parentExtinguish);
      await tester.tap(parentExtinguish);
      await tester.pumpAndSettle();
      expect(find.textContaining('也会熄灭 1 个后代'), findsOneWidget);
      await tester.tap(find.text('暂不填写'));
      await tester.pumpAndSettle();

      expect(
        (await repository.getCard(child.id)).state,
        NationalFocusCardState.extinguished,
      );
      expect(find.textContaining('因「开始工作前」连带熄灭'), findsOneWidget);
      final lightButtons = find.widgetWithText(FilledButton, '点亮');
      expect(lightButtons, findsNWidgets(2));
      expect(tester.widget<FilledButton>(lightButtons.last).onPressed, isNull);

      now = DateTime.utc(2026, 9, 25, 20);
      await repository.settleDueCheckpoints();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看失败记录'));
      await tester.tap(find.text('查看失败记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('· 1 个节点'));
      await tester.pumpAndSettle();

      expect(find.textContaining('独立失败来源'), findsOneWidget);
      expect(find.textContaining('因「开始工作前」连带熄灭'), findsOneWidget);
      final failures = await repository.getFailures();
      expect(failures, hasLength(1));
      expect(failures.single.cardId, parent.id);
      expect(
        failures.single.treeSnapshot
            .singleWhere((card) => card.id == child.id)
            .failureSourceCardId,
        parent.id,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final openRepository in repositories) {
        await openRepository.dispose();
      }
      await database.close();
      database = PactaDatabase(NativeDatabase(databaseFile));
      final restartedRepository = createRepository(userId);
      final restoredFailures = await restartedRepository.getFailures();
      expect(restoredFailures, hasLength(1));
      expect(
        restoredFailures.single.treeSnapshot
            .singleWhere((card) => card.id == child.id)
            .failureSourceCardId,
        parent.id,
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
