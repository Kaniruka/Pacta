import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_failure_pages.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_shared_widgets.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

/// Ticket 11：回顾入口与看板提示。
///
/// 记录页给出「未回顾 → 已回顾」的标记动作，标记不要求填写说明；
/// 完整回顾仍走 10 号的冻结树二级页，不新开第三条路径。
void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;

  var now = DateTime.utc(2026, 9, 25, 19, 59);

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    now = DateTime.utc(2026, 9, 25, 19, 59);
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      cloudSyncEnabled: false,
      now: () => now,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<String> createFailedBatch(LocalNationalFocusRepository target) async {
    for (var index = 0; index < 2; index++) {
      final card = await target.createCard(
        NationalFocusCardDraft(
          name: '触发 $index',
          triggerCondition: '触发 $index',
          action: '行动 $index',
        ),
      );
      await target.placeCard(cardId: card.id, parentId: null);
      await target.lightCard(card.id);
    }
    now = DateTime.utc(2026, 9, 25, 20);
    await target.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await target.settleDueCheckpoints();
    final failures = await target.getFailures();
    expect(failures, isNotEmpty);
    return failures.first.batchId;
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('标记已回顾不需要说明，且同一入口仍可查看当时树', (tester) async {
    await createFailedBatch(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusFailureHistoryPage(
          repository: repository,
          displayTimeZoneId: 'UTC',
        ),
      ),
    );
    await pumpPage(tester);

    await tester.tap(find.textContaining('2 个节点'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未回顾'), findsWidgets);
    expect(find.text('标记已回顾'), findsOneWidget);

    await tester.tap(find.text('标记已回顾'));
    await tester.pumpAndSettle();

    expect(find.text('标记已回顾'), findsNothing);
    expect(find.textContaining('已回顾'), findsWidgets);
    final failures = await repository.getFailures();
    expect(failures.every((failure) => failure.isReviewed), isTrue);
    expect(
      failures.every((failure) => failure.sharedExplanation == null),
      isTrue,
      reason: '不填写说明也能标为已回顾。',
    );

    await tester.tap(find.text('查看当时树'));
    await tester.pumpAndSettle();
    expect(find.text('当时树（只读）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('失败记录页无检查点说明，批次卡用图标井与高对比结构', (tester) async {
    final batchId = await createFailedBatch(repository);
    Widget page() => MaterialApp(
      home: NationalFocusFailureHistoryPage(
        key: UniqueKey(),
        repository: repository,
        displayTimeZoneId: 'UTC',
      ),
    );
    await tester.pumpWidget(page());
    await pumpPage(tester);

    // 检查点说明折叠卡整块下线，页内只剩分组标题与批次卡。
    expect(find.text('检查点说明'), findsNothing);
    expect(find.textContaining('下次检查点'), findsNothing);
    expect(find.text('失败记录'), findsOneWidget);
    expect(find.textContaining('未回顾 1 / 共 1 批'), findsOneWidget);
    expect(find.textContaining('2 个节点'), findsOneWidget);
    expect(find.byType(NationalFocusCardIconWell), findsNWidgets(2));
    // 「未回顾 / 已回顾」胶囊紧跟在原因胶囊同排 Wrap 内，且位于批次标题下方。
    final titleRect = tester.getRect(find.textContaining('2 个节点'));
    final causeBadge = find.descendant(
      of: find.byType(Wrap).first,
      matching: find.text('未完成今日确认'),
    );
    final reviewBadge = find.descendant(
      of: find.byType(Wrap).first,
      matching: find.text('未回顾'),
    );
    expect(causeBadge, findsOneWidget);
    expect(reviewBadge, findsOneWidget);
    final causeRect = tester.getRect(causeBadge);
    final reviewRect = tester.getRect(reviewBadge);
    expect(
      (causeRect.center.dy - reviewRect.center.dy).abs(),
      lessThanOrEqualTo(4.0),
    );
    expect(reviewRect.top, greaterThanOrEqualTo(titleRect.bottom));
    // 没有共同说明时不出现提示槽。
    expect(find.byType(NationalFocusInfoCallout), findsNothing);

    await repository.updateFailureExplanation(
      batchId: batchId,
      explanation: '共同说明：当天加班',
    );
    await tester.pumpWidget(page());
    await pumpPage(tester);
    expect(find.byType(NationalFocusInfoCallout), findsOneWidget);
    expect(find.text('共同说明：当天加班'), findsOneWidget);
    expect(find.text('检查点说明'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('看板提示未回顾失败，标记已回顾后提示消失', (tester) async {
    const user = 'support';
    final tasks = LocalTaskRepository(
      database: database,
      userId: user,
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: user,
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    addTearDown(tree.dispose);
    final batchId = await createFailedBatch(tree);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      ),
    );
    await tester.pumpAndSettle();
    await pumpPage(tester);

    expect(find.text('1 组国策失败待回顾'), findsOneWidget);

    await tree.markFailureReviewed(batchId: batchId);
    await tester.pumpAndSettle();
    await pumpPage(tester);

    expect(find.text('1 组国策失败待回顾'), findsNothing);
    expect(
      (await tree.getFailures()).every((failure) => failure.isReviewed),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('看板提示直接打开失败记录页，返回后保持同一记录上下文', (tester) async {
    const user = 'support';
    final tasks = LocalTaskRepository(
      database: database,
      userId: user,
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: user,
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: user,
      cloudSyncEnabled: false,
      now: () => now,
    );
    addTearDown(tree.dispose);
    await createFailedBatch(tree);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      ),
    );
    await tester.pumpAndSettle();
    await pumpPage(tester);

    final hint = find.text('1 组国策失败待回顾');
    expect(hint, findsOneWidget);
    await tester.tap(hint);
    await tester.pumpAndSettle();
    await pumpPage(tester);

    // 直达记录页，而不是只把主导航切到国策树。
    expect(find.byType(NationalFocusFailureHistoryPage), findsOneWidget);
    expect(find.text('国策失败记录'), findsOneWidget);
    expect(find.byType(BoardPage), findsNothing);

    // 沿用 10 号的冻结树二级页。
    await tester.tap(find.textContaining('2 个节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看当时树'));
    await tester.pumpAndSettle();
    expect(find.text('当时树（只读）'), findsOneWidget);

    // 返回后仍是同一条记录上下文，可直接标记回顾。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NationalFocusFailureHistoryPage), findsOneWidget);
    expect(find.textContaining('2 个节点'), findsOneWidget);
    expect(find.text('标记已回顾'), findsOneWidget);

    await tester.tap(find.text('标记已回顾'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已回顾'), findsWidgets);
    expect(
      (await tree.getFailures()).every((failure) => failure.isReviewed),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
