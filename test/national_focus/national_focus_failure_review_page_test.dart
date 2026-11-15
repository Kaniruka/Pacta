import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

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
}
