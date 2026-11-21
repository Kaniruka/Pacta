import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_library_page.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';

import '../support/fake_auth_repository.dart';

/// Phase 5 Wave 4b：最后四个推入式二级页在 1280x800 桌面上必须居中且正文
/// 不超过 800dp。此前《专注历史》横向撑满 1248dp（桌面基线截图实证）。
const _user = 'secondary-route-width';
const _viewport = Size(1280, 800);
const _maxBodyWidth = 800.0;

void main() {
  void useDesktopView(WidgetTester tester) {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void expectCenteredBody(WidgetTester tester, Finder target, String reason) {
    final rect = tester.getRect(target);
    expect(rect.width, lessThanOrEqualTo(_maxBodyWidth), reason: reason);
    expect(
      rect.center.dx,
      moreOrLessEquals(_viewport.width / 2, epsilon: 0.5),
      reason: reason,
    );
  }

  /// 有限推进：只关心最终布局宽度，不依赖「所有动画都停下」。
  ///
  /// 多帧推进同时把真实异步（Drift 查询、FutureBuilder）让出事件循环，
  /// 又不要求加载菊花停下——菊花是无限动画，pumpAndSettle 会一直等。
  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 轮询到目标出现；用于等真实异步数据落地。
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('专注历史 1280x800：三链切换、统计摘要与时间轴同受 800dp 居中约束', (tester) async {
    useDesktopView(tester);
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime(2026, 11, 12, 9);
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    // Provider 的 autoDispose 会在应用卸载时释放仓储；这里只关数据库，
    // 与 focus_chain_layout_test 同一收尾口径（重复 dispose 会等在途订阅）。
    addTearDown(database.close);
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '宽屏阅读线',
        classification: TaskClassification.regular,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '整理发布说明',
        classification: TaskClassification.regular,
      ),
    );
    await focus.startSession(
      taskId: (await tasks.getGoals()).single.tasks.single.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    now = now.add(const Duration(minutes: 25));
    await focus.settleDueSessions();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('专注链'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('focus-history-entry')));
    await settle(tester);
    expect(find.byType(FocusHistoryPage), findsOneWidget);
    await waitFor(
      tester,
      find.byKey(const ValueKey('focus-history-chain-switch')),
    );
    // 默认落在第一条有记录的链：这里就是普通链，正文已渲染。
    await waitFor(tester, find.byKey(const ValueKey('focus-history-timeline')));

    expectCenteredBody(
      tester,
      find.byKey(const ValueKey('focus-history-chain-switch')),
      '三链切换不再横向撑满桌面',
    );
    expectCenteredBody(
      tester,
      find.byKey(const ValueKey('focus-history-summary')),
      '统计摘要卡与时间轴同一条阅读线',
    );
    expectCenteredBody(
      tester,
      find.byKey(const ValueKey('focus-history-timeline')),
      '时间轴正文不超过 800dp',
    );
    expect(tester.takeException(), isNull);

    // 返回与滚动仍不被居中约束影响。
    await tester.pageBack();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FocusHistoryPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('下必为例 1280x800：正文居中且不超过 800dp', (tester) async {
    useDesktopView(tester);
    // 直接挂载路由体：本用例只量正文宽度，不重复首屏入口的导航成本。
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: const PrecedentRulesPage(),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(PrecedentRulesPage), findsOneWidget);

    expectCenteredBody(
      tester,
      find.descendant(
        of: find.byType(PrecedentRulesPage),
        matching: find.byType(ListView),
      ),
      '下必为例正文按 800dp 居中',
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('国策卡详情 1280x800：对称边距与 800dp 居中正文', (tester) async {
    useDesktopView(tester);
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 11, 12, 10),
    );
    addTearDown(database.close);
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        name: '开始前先写一步',
        triggerCondition: '开始前',
        action: '写下今天的第一步',
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: NationalFocusCardDetailPage(
          repository: repository,
          card: card,
          lightBlocked: false,
          cascadeSourceLabel: null,
        ),
      ),
    );
    await settle(tester);

    expectCenteredBody(tester, find.byType(ListView), '国策卡详情正文按 800dp 居中');
    // 对称页边距：正文块 800dp 居中（左右各 240dp），内容再让出一档
    // gutter，不再用旧的左 20 / 右 20 字面量。
    final bodyLeft = (_viewport.width - _maxBodyWidth) / 2;
    final name = tester.getRect(find.text('开始前先写一步'));
    expect(
      name.left,
      moreOrLessEquals(bodyLeft + PactaSpacing.wideGutter),
      reason: '正文左缘 = 居中块左缘 + 宽屏 gutter',
    );
    expect(name.left, greaterThanOrEqualTo(bodyLeft), reason: '正文不得贴住桌面左缘');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('手动同步 1280x800：正文居中且不超过 800dp', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (innerContext) => FilledButton(
                    onPressed: () => openAiManualSync(innerContext, ref),
                    child: const Text('打开手动同步'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('打开手动同步'));
    await settle(tester);

    expect(find.text('手动同步'), findsOneWidget);
    expectCenteredBody(tester, find.byType(ListView), '手动同步正文按 800dp 居中');
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('打开手动同步'), findsOneWidget);
    await unmount(tester);
  });
}
