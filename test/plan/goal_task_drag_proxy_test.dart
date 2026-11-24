import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/plan/goal_task_cards.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_hold_action_reorder.dart';

/// 工单 05：未完成任务行的拖拽代理实底与 12dp 圆角。
///
/// 任务行本身没有 Card：代理内层必须自带与卡片同值的不透明底色，动画
/// 刚产生 elevation 的那几帧阴影才不会从透明区域透出来形成孤立暗块。
const _user = 'goal-task-drag-proxy';

void main() {
  late PactaDatabase database;
  late LocalTaskRepository tasks;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
  });

  tearDown(() async {
    await tasks.dispose();
    await database.close();
  });

  Future<Goal> seedGoal() async {
    final goal = await tasks.createGoal(
      const GoalDraft(title: '发布', classification: TaskClassification.regular),
    );
    for (final title in ['甲', '乙', '丙']) {
      await tasks.createTask(goal.id, TaskDraft(title: title));
    }
    return (await tasks.getGoals()).singleWhere((item) => item.id == goal.id);
  }

  Future<void> pumpCard(
    WidgetTester tester,
    Brightness brightness,
    Goal goal,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: pactaTheme(brightness),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(PactaSpacing.lg),
              child: GoalCard(
                repository: tasks,
                goal: goal,
                focusProgressSecondsByTask: null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder nestedList() => find.descendant(
    of: find.byType(GoalCard),
    matching: find.byType(PactaHoldReorderList),
  );

  // 代理内层的实底必须完全不透明：亮色与暗色主题都要成立。
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}：任务行代理外层透明、内层实底完全不透明且 12dp 圆角', (
      tester,
    ) async {
      final goal = await seedGoal();
      await pumpCard(tester, brightness, goal);

      expect(nestedList(), findsOneWidget, reason: '目标卡里只有一份未完成任务列表');
      final list = tester.widget<PactaHoldReorderList>(nestedList());
      expect(list.proxyBorderRadius, 12, reason: '任务行圆角固定 12dp');
      expect(list.itemSpacing, 0, reason: '任务行距由 TaskTile 自身承担');

      final base = list.proxyBaseColor;
      final lift = list.proxyBackgroundColor;
      expect(base, isNotNull);
      expect(lift, isNotNull);
      expect(base!.a, greaterThanOrEqualTo(0.999), reason: '代理实底必须完全不透明');
      expect(lift!.a, greaterThanOrEqualTo(0.999), reason: '代理浮起底色必须完全不透明');
      expect(
        base.toARGB32(),
        PactaSurfaces.cardFor(brightness).toARGB32(),
        reason: '实底就是所在卡片的底色',
      );
      expect(lift.toARGB32(), isNot(base.toARGB32()), reason: '浮起时要有可辨的抬升');

      final decorator = tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .proxyDecorator!;
      Widget proxyAt(double t) => decorator(
        PactaHoldReorderListener(
          index: 0,
          child: const SizedBox(height: 56, width: 320),
        ),
        0,
        AlwaysStoppedAnimation<double>(t),
      );

      // 外层外包必须保持透明 + 固定 Key：实底只能由内层承担。
      final surface = (proxyAt(0.5) as InheritedWidget).child as Material;
      expect(surface.type, MaterialType.transparency);
      expect(surface.key, const ValueKey('pacta-hold-reorder-proxy-surface'));

      for (final t in <double>[0, 0.5, 1]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: pactaTheme(brightness),
            home: Scaffold(
              body: Align(alignment: Alignment.topLeft, child: proxyAt(t)),
            ),
          ),
        );
        await tester.pump();
        final highlight = tester.widget<Material>(
          find.byKey(const ValueKey('pacta-hold-reorder-proxy-highlight')),
        );
        final shape = highlight.shape! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          BorderRadius.circular(12),
          reason: '${brightness.name} t=$t 圆角必须是 12dp',
        );
        expect(
          highlight.color!.a,
          greaterThanOrEqualTo(0.999),
          reason: '${brightness.name} t=$t 实底必须完全不透明，不能透出底层阴影',
        );
        if (t == 0) {
          expect(highlight.color, base, reason: 't=0 就是卡片本色，刚起拖时也没有透明穿透');
        }
        if (t == 1) expect(highlight.color, lift, reason: 't=1 抵达浮起色调');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TaskTile 的 ListTile 使用 12dp 圆角形状且不改内边距', (tester) async {
    final goal = await seedGoal();
    await pumpCard(tester, Brightness.light, goal);

    final tiles = tester.widgetList<ListTile>(
      find.descendant(
        of: find.byType(GoalCard),
        matching: find.byType(ListTile),
      ),
    );
    expect(tiles, hasLength(3));
    for (final tile in tiles) {
      final shape = tile.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(12),
        reason: '按住水波纹与高亮从首帧起按 12dp 圆角裁切',
      );
      expect(tile.contentPadding, EdgeInsets.zero, reason: '圆角不改变行内边距');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('按住拖动任务：实时代理保持 12dp 圆角与不透明实底', (tester) async {
    final goal = await seedGoal();
    await pumpCard(tester, Brightness.light, goal);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('甲')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 100));

    final surface = find.byKey(
      const ValueKey('pacta-hold-reorder-proxy-surface'),
    );
    expect(surface, findsOneWidget, reason: '只有任务行自己的代理，目标卡不参与');
    expect(tester.widget<Material>(surface).type, MaterialType.transparency);
    final highlight = tester.widget<Material>(
      find.byKey(const ValueKey('pacta-hold-reorder-proxy-highlight')),
    );
    final shape = highlight.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(12));
    expect(
      highlight.color!.a,
      greaterThanOrEqualTo(0.999),
      reason: '拖拽中任何一帧都不能是透明底',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未配置代理底色时保持透明：外层实底 Card 的列表回退不变', (tester) async {
    final card = PactaHoldReorderList(
      itemCount: 1,
      onReorder: (_, _) {},
      itemBuilder: (context, index) =>
          const SizedBox(key: ValueKey('default-proxy-item'), height: 64),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(body: card),
        ),
      ),
    );
    final decorator = tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .proxyDecorator!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: decorator(
                PactaHoldReorderListener(
                  index: 0,
                  child: const SizedBox(height: 64, width: 320),
                ),
                0,
                const AlwaysStoppedAnimation<double>(0.5),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final highlight = tester.widget<Material>(
      find.byKey(const ValueKey('pacta-hold-reorder-proxy-highlight')),
    );
    expect(highlight.color, Colors.transparent);
    expect(tester.takeException(), isNull);
  });
}
