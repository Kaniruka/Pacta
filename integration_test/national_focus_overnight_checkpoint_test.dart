import 'dart:io';

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

  testWidgets('01:00 点亮后关闭数据库，08:00 重开仅待确认且不创建失败', (tester) async {
    final directory = await Directory.systemTemp.createTemp('pacta-overnight-');
    final file = File('${directory.path}/pacta.sqlite');
    var now = DateTime.utc(2026, 10, 18, 17); // 北京时间 10 月 19 日 01:00。
    var database = PactaDatabase(NativeDatabase(file));
    LocalNationalFocusRepository createRepository() =>
        LocalNationalFocusRepository(
          database: database,
          userId: 'overnight-fixture',
          cloudSyncEnabled: false,
          now: () => now,
        );
    var repository = createRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.dispose();
      await database.close();
      await directory.delete(recursive: true);
    });

    final parent = await repository.createCard(
      const NationalFocusCardDraft(name: '阅读', action: '读十页'),
    );
    final child = await repository.createCard(
      const NationalFocusCardDraft(name: '笔记', action: '记录收获'),
    );
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    expect(
      (await repository.getTreeCards()).every(
        (card) => card.state == NationalFocusCardState.lit,
      ),
      isTrue,
    );
    await repository.dispose();
    await database.close();

    now = DateTime.utc(2026, 10, 19); // 同一天北京时间 08:00。
    database = PactaDatabase(NativeDatabase(file));
    repository = createRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cards = await repository.getTreeCards();
    expect(cards, hasLength(2));
    for (final card in cards) {
      expect(card.state, NationalFocusCardState.pendingTodayConfirmation);
      expect(card.successfulDays, 1);
      expect(card.currentConsecutiveDays, 1);
    }
    expect(await repository.getFailures(), isEmpty);
    expect(tester.takeException(), isNull);

    // 对照：再过一个检查点仍未确认，必须产生真实失败，且不重复结算。
    now = DateTime.utc(2026, 10, 19, 20);
    await repository.settleDueCheckpoints();
    final failures = await repository.getFailures();
    expect(failures, isNotEmpty);
    expect(
      failures.every(
        (failure) =>
            failure.cause == NationalFocusFailureCause.missedConfirmation,
      ),
      isTrue,
    );
    expect(
      (await repository.getTreeCards()).every(
        (card) => card.state == NationalFocusCardState.extinguished,
      ),
      isTrue,
    );
    await repository.settleDueCheckpoints();
    expect(await repository.getFailures(), hasLength(failures.length));
  });
}
