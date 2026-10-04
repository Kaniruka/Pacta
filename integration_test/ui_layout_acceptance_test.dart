import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('四入口和向下国策分支布局', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'layout-user',
      remote: InMemoryTaskRemote(),
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: 'layout-user',
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'layout-user',
      remote: InMemoryFocusRemote(),
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '完成本周的阅读计划',
        classification: TaskClassification.both,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '阅读第一章并写下三个要点',
        classification: TaskClassification.both,
        estimatedMinutes: 30,
      ),
    );
    final root = await tree.createCard(
      const NationalFocusCardDraft(
        triggerCondition: '开始一天之前',
        action: '确定今天最重要的一步',
      ),
    );
    await tree.placeCard(cardId: root.id, parentId: null);
    for (final condition in ['坐到书桌前', '结束一天之后']) {
      final child = await tree.createCard(
        NationalFocusCardDraft(triggerCondition: condition, action: '记录一次具体行动'),
      );
      await tree.placeCard(cardId: child.id, parentId: root.id);
    }
    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'layout-user',
          taskRepositoryFactory: (_) => tasks,
          nationalFocusRepositoryFactory: (_) => tree,
          focusRepositoryFactory: (_) => focus,
        ),
      );
      await tester.pumpAndSettle();
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      for (final entry in {
        'board': '看板',
        'tree': '国策树',
        'focus': '专注链',
        'my': '我的',
      }.entries) {
        await tester.tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) => widget is NavigationBar || widget is NavigationRail,
            ),
            matching: find.text(entry.value),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final width = MediaQuery.sizeOf(tester.element(find.byType(AppShell)))
            .width;
        final prefix = width >= 840 ? 'wide' : 'compact';
        if (Platform.isAndroid) {
          await binding.takeScreenshot('$prefix-${entry.key}');
        }
        if (entry.key == 'tree') {
          await tester.ensureVisible(find.text('开始一天之前'));
          await tester.pumpAndSettle();
          if (Platform.isAndroid) {
            await binding.takeScreenshot('$prefix-tree-branches');
          }
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tree.dispose();
      await database.close();
    }
  });
}
