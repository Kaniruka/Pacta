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

  testWidgets('T13 从卡片库创建国策卡并在树画布选择位置', (tester) async {
    const userId = 'ticket-13-user';
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'pacta-ticket-13-',
    );
    final databaseFile = File('${temporaryDirectory.path}/pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(databaseFile));
    final repositories = <LocalNationalFocusRepository>[];
    LocalNationalFocusRepository createRepository(String requestedUserId) {
      final repository = LocalNationalFocusRepository(
        database: database,
        userId: requestedUserId,
      );
      repositories.add(repository);
      return repository;
    }

    final auth = FakeAuthRepository()..signedInUser = userId;

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
      expect(find.text('树画布还是空的'), findsOneWidget);

      await _createAndPlaceCard(
        tester,
        trigger: '坐到书桌前',
        action: '先完成计划中的第一项',
        scope: '仅工作日',
        exceptionNotes: '出差时顺延',
        placement: _Placement.topLevel,
      );
      await _createAndPlaceCard(
        tester,
        trigger: '完成第一项后',
        action: '整理下一步要用的资料',
        scope: '工作日',
        exceptionNotes: '',
        placement: _Placement.underFirstNode,
      );

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(find.text('坐到书桌前'), findsOneWidget);
      expect(find.text('先完成计划中的第一项'), findsOneWidget);
      expect(find.text('仅工作日'), findsOneWidget);
      expect(find.text('出差时顺延'), findsOneWidget);
      expect(find.text('完成第一项后'), findsOneWidget);
      expect(find.text('整理下一步要用的资料'), findsOneWidget);
      expect(find.text('熄灭'), findsNWidgets(2));

      final activeRepository = repositories.first;
      final placedCards = await activeRepository.getTreeCards();
      expect(placedCards, hasLength(2));
      final firstCard = placedCards.singleWhere(
        (card) => card.triggerCondition == '坐到书桌前',
      );
      final childCard = placedCards.singleWhere(
        (card) => card.triggerCondition == '完成第一项后',
      );
      expect(firstCard.isTopLevel, isTrue);
      expect(firstCard.parentId, isNull);
      expect(childCard.parentId, firstCard.id);
      expect(firstCard.state, NationalFocusCardState.extinguished);
      expect(childCard.state, NationalFocusCardState.extinguished);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await activeRepository.dispose();
      await database.close();
      database = PactaDatabase(NativeDatabase(databaseFile));
      final restartedRepository = createRepository(userId);
      final restored = await restartedRepository.getTreeCards();
      expect(restored, hasLength(2));
      expect(
        restored.singleWhere((card) => card.id == childCard.id).parentId,
        firstCard.id,
      );
      expect(
        restored.every(
          (card) => card.state == NationalFocusCardState.extinguished,
        ),
        isTrue,
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

Future<void> _createAndPlaceCard(
  WidgetTester tester, {
  required String trigger,
  required String action,
  required String scope,
  required String exceptionNotes,
  required _Placement placement,
}) async {
  await tester.tap(find.text('卡片库'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), trigger);
  await tester.enterText(fields.at(1), action);
  await tester.enterText(fields.at(2), scope);
  await tester.enterText(fields.at(3), exceptionNotes);
  await tester.tap(find.text('保存到卡片库'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('放入树画布'));
  await tester.pumpAndSettle();
  if (placement == _Placement.topLevel) {
    await tester.tap(find.text('顶层位置'));
  } else {
    await tester.tap(find.text('节点 1'));
  }
  await tester.pumpAndSettle();
}

enum _Placement { topLevel, underFirstNode }
