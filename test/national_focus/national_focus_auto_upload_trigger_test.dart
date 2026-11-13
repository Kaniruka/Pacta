import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;
  var now = DateTime.utc(2026, 9, 25, 19, 59);
  var confirmed = 0;

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 19, 59);
    confirmed = 0;
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'auto-upload-trigger-user',
      cloudSyncEnabled: false,
      now: () => now,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<NationalFocusCard> createPlacedCard({
    required String name,
    String? exceptionNotes,
  }) async {
    final card = await repository.createCard(
      NationalFocusCardDraft(
        name: name,
        action: '执行「$name」',
        exceptionNotes: exceptionNotes,
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);
    return card;
  }

  Future<void> settleUi(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            onTodayConfirmed: () async {
              confirmed++;
            },
          ),
        ),
      ),
    );
    await settleUi(tester);
  }

  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> moveToPending() async {
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
  }

  testWidgets('批量普通确认结束只触发一次自动上传', (tester) async {
    final first = await createPlacedCard(name: '第一张');
    final second = await createPlacedCard(name: '第二张');
    await repository.lightCard(first.id);
    await repository.lightCard(second.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (2)'));
    await settleUi(tester);
    expect(confirmed, 1);
    expect(
      (await repository.getCard(first.id)).state,
      NationalFocusCardState.lit,
    );
    await closePage(tester);
  });

  testWidgets('单点确认触发一次，普通点亮不触发', (tester) async {
    final card = await createPlacedCard(name: '单点节点');
    await pumpPage(tester);

    await tester.tap(find.byKey(ValueKey('national-focus-node-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('点亮'));
    await settleUi(tester);
    expect(confirmed, 0);

    await moveToPending();
    await settleUi(tester);
    await tester.tap(find.byKey(ValueKey('national-focus-node-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await settleUi(tester);
    expect(confirmed, 1);
    await closePage(tester);
  });

  testWidgets('普通与例外混合批量：逐项确认后整批只触发一次', (tester) async {
    final plain = await createPlacedCard(name: '普通节点');
    final exceptional = await createPlacedCard(
      name: '例外节点',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(plain.id);
    await repository.lightCard(exceptional.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (2)'));
    await settleUi(tester);
    expect(find.text('确认今日继续有效？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await settleUi(tester);

    expect(confirmed, 1);
    expect(
      (await repository.getCard(exceptional.id)).state,
      NationalFocusCardState.lit,
    );
    await closePage(tester);
  });

  testWidgets('部分成功随后关闭例外面板仍为已成功变更触发一次', (tester) async {
    final plain = await createPlacedCard(name: '已确认节点');
    final first = await createPlacedCard(name: '例外一', exceptionNotes: '第一个例外');
    now = now.add(const Duration(seconds: 2));
    final second = await createPlacedCard(name: '例外二', exceptionNotes: '第二个例外');
    await repository.lightCard(plain.id);
    await repository.lightCard(first.id);
    await repository.lightCard(second.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (3)'));
    await settleUi(tester);
    await tester.tap(find.text('确认'));
    await settleUi(tester);
    await tester.tap(find.text('关闭'));
    await settleUi(tester);

    expect(confirmed, 1);
    expect(
      (await repository.getCard(plain.id)).state,
      NationalFocusCardState.lit,
    );
    expect(
      (await repository.getCard(second.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    await closePage(tester);
  });

  testWidgets('熄灭不触发自动上传', (tester) async {
    final card = await createPlacedCard(name: '熄灭节点');
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.byKey(ValueKey('national-focus-node-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('熄灭'));
    await settleUi(tester);
    await tester.tap(find.text('暂不填写'));
    await settleUi(tester);

    expect(confirmed, 0);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.extinguished,
    );
    await closePage(tester);
  });
}
