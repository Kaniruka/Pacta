import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_library_page.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'unsaved-user',
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 11, 25, 9),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<NationalFocusCard> seedCard() => repository.createCard(
    const NationalFocusCardDraft(
      name: '阅读',
      action: '阅读 5 页',
      iconKey: 'lucide:book-open',
      strengtheningLevels: [
        NationalFocusStrengtheningLevel(levelNumber: 1, action: '阅读 10 页'),
        NationalFocusStrengtheningLevel(levelNumber: 2, action: '阅读 20 页'),
      ],
      updateStrengthening: true,
    ),
  );

  Future<void> pumpEditor(
    WidgetTester tester, {
    NationalFocusCard? card,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => NationalFocusCardEditorPage(
                      repository: repository,
                      card: card,
                    ),
                  ),
                ),
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
  }

  Future<void> openStrengthening(WidgetTester tester) async {
    final entry = find.text('强化要求');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  testWidgets('返回未保存编辑时提供放弃、继续编辑与保存三选一', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = await seedCard();
    await pumpEditor(tester, card: card);

    await tester.enterText(find.byType(TextFormField).at(0), '晨读');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('尚未保存更改'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('national-focus-editor-keep-editing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('尚未保存更改'), findsNothing);
    expect(find.text('编辑国策卡'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('national-focus-editor-discard')),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开编辑器'), findsOneWidget);
    expect((await repository.getCard(card.id)).name, '阅读');
  });

  testWidgets('未保存确认里的保存会校验并提交后退出', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = await seedCard();
    await pumpEditor(tester, card: card);

    await tester.enterText(find.byType(TextFormField).at(0), '晨读');
    await tester.enterText(find.byType(TextFormField).at(1), '阅读 6 页');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('national-focus-editor-save')));
    await tester.pumpAndSettle();

    expect(find.text('打开编辑器'), findsOneWidget);
    final updated = await repository.getCard(card.id);
    expect(updated.name, '晨读');
    expect(updated.action, '阅读 6 页');
    expect(updated.strengtheningLevels, hasLength(2));
  });

  testWidgets('强化档位作为草稿随编辑页唯一保存一次落盘', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = await seedCard();
    await pumpEditor(tester, card: card);
    await openStrengthening(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-2')),
        matching: find.text('选择'),
      ),
    );
    await tester.pumpAndSettle();
    // 草稿页不写库。
    expect(
      (await repository.getCard(card.id)).activeStrengtheningLevel,
      isNull,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('当前正使用强化等级 2，此处修改的是基础要求。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('打开编辑器'), findsOneWidget);
    final updated = await repository.getCard(card.id);
    expect(updated.activeStrengtheningLevel, 2);
    expect(updated.effectiveAction, '阅读 20 页');
    expect(updated.iconKey, 'lucide:book-open');
  });

  testWidgets('新建卡片时也可进入强化草稿并随卡片创建', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpEditor(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '早睡');
    await tester.enterText(find.byType(TextFormField).at(1), '23 点关灯');
    await tester.pumpAndSettle();
    await openStrengthening(tester);
    await tester.tap(find.text('新建强化要求'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('strengthened-rule')),
      '22:30 关灯',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('national-focus-strengthening-level-1')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存到卡片库'));
    await tester.pumpAndSettle();

    final created = (await repository.getLibraryCards()).single;
    expect(created.name, '早睡');
    expect(created.action, '23 点关灯');
    expect(created.strengtheningLevels.single.action, '22:30 关灯');
  });

  testWidgets('强化子编辑页有未保存输入时返回先确认', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final card = await seedCard();
    await pumpEditor(tester, card: card);
    await openStrengthening(tester);
    await tester.tap(find.byTooltip('编辑强化等级 1'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('strengthened-rule')),
      '阅读 12 页',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byKey(const ValueKey('strengthened-rule')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.text('国策强化要求'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-1')),
        matching: find.text('阅读 10 页'),
      ),
      findsOneWidget,
    );
  });
}
