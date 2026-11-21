import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/ui/pacta_page_header.dart';

import '../support/fake_auth_repository.dart';

/// 工单 04：看板置顶目标"按住拖动排序 / 按住不动开面板"，触屏与鼠标一致。
const _user = 'board-goal-reorder-user';

class _Harness {
  _Harness(this.database, this.tasks, this.focus);

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;

  static _Harness create() {
    final database = PactaDatabase(NativeDatabase.memory());
    return _Harness(
      database,
      LocalTaskRepository(
        database: database,
        userId: _user,
        remote: InMemoryTaskRemote(),
      ),
      LocalFocusRepository(
        database: database,
        userId: _user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await focus.dispose();
    await database.close();
  }
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

Future<bool> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (await condition()) return true;
    await tester.pump(const Duration(milliseconds: 50));
  }
  return false;
}

/// FakeAsync 下手势竞技场偶尔让页面滚动先认领同一指针：重试一次即可
/// 稳定复现真实长按拖动，不改变被测行为。
Future<void> _dragUntilReordered(
  WidgetTester tester,
  Finder target,
  PointerDeviceKind kind,
  Future<bool> Function() done,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: kind,
      buttons: kPrimaryButton,
    );
    await tester.pump(const Duration(milliseconds: 400));
    for (var step = 0; step < 15; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    if (await _pumpUntil(tester, done)) return;
  }
  fail('连续三次拖动都没有触发置顶目标重排');
}

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('${kind.name} 按住拖动置顶目标改顺序，不弹操作面板', (tester) async {
      final harness = _Harness.create();
      try {
        final first = await harness.tasks.createGoal(
          const GoalDraft(
            title: '甲目标',
            classification: TaskClassification.regular,
          ),
        );
        final second = await harness.tasks.createGoal(
          const GoalDraft(
            title: '乙目标',
            classification: TaskClassification.regular,
          ),
        );
        await harness.tasks.setGoalPinned(first.id, isPinned: true);
        await harness.tasks.setGoalPinned(second.id, isPinned: true);
        await harness.pump(tester);

        expect(
          _top(tester, find.text('甲目标')),
          lessThan(_top(tester, find.text('乙目标'))),
        );
        // 工单 09 / #3：间距由列表的 itemSpacing 承担，卡片零外边距，
        // 长按提起的高亮描边因此严格贴合 20dp 圆角。
        final firstCard = find.byKey(ValueKey('board-pinned-goal-${first.id}'));
        final secondCard = find.byKey(
          ValueKey('board-pinned-goal-${second.id}'),
        );
        expect(
          tester.getTopLeft(secondCard).dy - tester.getBottomLeft(firstCard).dy,
          8,
          reason: '置顶目标之间是 itemSpacing 的 8dp，不是卡片 margin',
        );
        expect(tester.widget<Card>(firstCard).margin, EdgeInsets.zero);

        await _dragUntilReordered(
          tester,
          find.text('甲目标'),
          kind,
          () async => (await harness.tasks.getGoals()).first.id == second.id,
        );

        final ordered = await harness.tasks.getGoals();
        expect(ordered.map((goal) => goal.id).toList(), [second.id, first.id]);
        expect(
          _top(tester, find.text('乙目标')),
          lessThan(_top(tester, find.text('甲目标'))),
        );
        expect(find.text('在计划中查看'), findsNothing, reason: '拖动不弹操作面板');
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    });
  }

  testWidgets('按住置顶目标不动打开操作面板并可取消置顶', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '发布',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(goal.id, const TaskDraft(title: '整理素材'));
      await harness.tasks.setGoalPinned(goal.id, isPinned: true);
      await harness.pump(tester);

      expect(find.text('下一项：整理素材'), findsOneWidget);
      await tester.longPress(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.text('在计划中查看'), findsOneWidget);
      expect(find.text('取消置顶'), findsOneWidget);

      await tester.tap(find.text('取消置顶'));
      await tester.pumpAndSettle();
      expect((await harness.tasks.getGoals()).single.isPinned, isFalse);
      // 空置顶目标不再有占位：标题、管理入口与「还没有置顶目标」空卡片
      // 全部消失，融合卡直接接管页头下方。
      expect(find.text('还没有置顶目标'), findsNothing);
      expect(find.text('置顶目标'), findsNothing);
      expect(find.text('发布'), findsNothing);
      expect(find.text('专注与国策'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('board-focus-national-card')))
            .top,
        moreOrLessEquals(
          tester.getRect(find.byType(PactaPageHeader)).bottom,
          epsilon: 0.5,
        ),
        reason: '无置顶目标时融合卡紧贴页头，没有多余死空间',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
