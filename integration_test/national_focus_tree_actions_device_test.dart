import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android node actions add a library card under the selected parent',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final repository = LocalNationalFocusRepository(
        database: database,
        userId: 'tree-actions-device-fixture',
        cloudSyncEnabled: false,
        now: () => DateTime.utc(2026, 10, 5, 10),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await repository.dispose();
        await database.close();
      });
      final parent = await repository.createCard(
        const NationalFocusCardDraft(
          name: '每日阅读',
          triggerCondition: '晚饭后',
          action: '读十页书',
        ),
      );
      await repository.placeCard(cardId: parent.id, parentId: null);
      await repository.lightCard(parent.id);
      final child = await repository.createCard(
        const NationalFocusCardDraft(
          name: '记录收获',
          triggerCondition: '读书结束后',
          action: '记下一句话',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NationalFocusTreePage(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('检查点与失败记录'), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('national-focus-node-${parent.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加子节点'), findsOneWidget);
      await tester.ensureVisible(find.text('添加子节点'));
      await tester.tap(find.text('添加子节点'));
      await tester.pumpAndSettle();
      expect(find.text('国策卡片库'), findsOneWidget);
      await tester.tap(find.text('放入国策树'));
      await tester.pumpAndSettle();
      final placed = await repository.getCard(child.id);
      expect(placed.parentId, parent.id);
      expect(placed.state, NationalFocusCardState.extinguished);
      expect(find.text('国策卡片库'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查点与失败记录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('下次检查点'), findsOneWidget);
      expect(find.text('查看失败记录'), findsOneWidget);
    },
  );
}
