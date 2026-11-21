import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';

/// Ticket 11 复审视觉修复的回归：历史树在窄窗里要可读，
/// 父子边与独立根要画对，冻结详情要保持完整内容与历史措辞。
void main() {
  NationalFocusCardSnapshot snapshot({
    required String id,
    required String name,
    required String action,
    String? parentId,
  }) => NationalFocusCardSnapshot(
    id: id,
    name: name,
    triggerCondition: name,
    action: action,
    isInTree: true,
    state: NationalFocusCardState.pendingTodayConfirmation,
    successfulDays: 1,
    currentConsecutiveDays: 1,
    bestConsecutiveDays: 1,
    maintenanceCycleStarted: false,
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 11, 15),
    parentId: parentId,
  );

  const longName = '把这个季度的复盘、风险与下季度计划一次写完';
  const longAction = '先列出三个必须交付的结论，再逐条补齐证据、负责人和截止时间';

  NationalFocusFailure failure() => NationalFocusFailure(
    id: 'failure-1',
    batchId: 'batch-1',
    cardId: 'parent',
    checkpointAt: DateTime.utc(2026, 11, 15, 4),
    cause: NationalFocusFailureCause.missedConfirmation,
    failureReason: '未完成今日确认',
    sharedExplanation: null,
    treeSnapshot: [
      snapshot(id: 'parent', name: longName, action: longAction),
      snapshot(
        id: 'child',
        name: '周三前发出评审邀请',
        action: '列出五个必须到场的评审人',
        parentId: 'parent',
      ),
      snapshot(id: 'root', name: '独立根：整理桌面', action: '清空收件箱'),
    ],
  );

  testWidgets('历史树 360 宽按可读尺寸显示，父子边、独立根与冻结详情正确', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusFailureTreePage(
          failure: failure(),
          checkpointLabel: '2026-11-15 12:00',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 可读下限：不再把两列的森林压到 0.65 的字号。
    final canvas = tester.widget<Transform>(
      find.byKey(const ValueKey('national-focus-canvas')),
    );
    final scale = canvas.transform.entry(0, 0).abs();
    expect(scale, greaterThanOrEqualTo(0.85), reason: '360 宽的历史树应保持可读的初始拟合比例');
    expect(scale, lessThanOrEqualTo(1.0));

    // 完整冻结内容：三个节点都在。
    expect(find.text(longName), findsOneWidget);
    expect(find.text('周三前发出评审邀请'), findsOneWidget);
    expect(find.text('独立根：整理桌面'), findsOneWidget);

    // 历史措辞：描述当时状态，而不是实时动作标签。
    expect(find.text('待今日确认 · 连续 1 天'), findsWidgets);
    expect(find.text('确认 · 连续 1 天'), findsNothing);

    // 节点卡必须浮在 surfaceContainerLow 画布之上：卡片底色 + 细边框 +
    // 页面级 20dp 圆角，不再与画布同色融成一片。
    final colors = Theme.of(
      tester.element(find.byType(NationalFocusFailureTreePage)),
    ).colorScheme;
    final parentCard = tester.widget<Card>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey('national-focus-history-node-parent'),
            ),
            matching: find.byType(Card),
          )
          .first,
    );
    expect(parentCard.color, isNot(colors.surfaceContainerLow));
    final cardShape = parentCard.shape! as RoundedRectangleBorder;
    expect(
      cardShape.borderRadius,
      BorderRadius.circular(PactaSpacing.cardRadius),
    );
    expect(cardShape.side.color, colors.outlineVariant);
    expect(cardShape.side.width, greaterThan(0));

    // 正确边：子节点在父节点正下方；独立根另起一段。
    final parentRect = tester.getRect(
      find.byKey(const ValueKey('national-focus-history-node-parent')),
    );
    final childRect = tester.getRect(
      find.byKey(const ValueKey('national-focus-history-node-child')),
    );
    final rootRect = tester.getRect(
      find.byKey(const ValueKey('national-focus-history-node-root')),
    );
    expect(childRect.top, greaterThan(parentRect.bottom));
    expect(childRect.left, closeTo(parentRect.left, 0.5));
    expect(rootRect.top, greaterThan(childRect.bottom));

    // 冻结详情：完整长要求与历史措辞都保持。
    final parentNode = find.byKey(
      const ValueKey('national-focus-history-node-parent'),
    );
    await tester.ensureVisible(parentNode);
    await tester.tap(parentNode);
    await tester.pumpAndSettle();
    expect(find.text('冻结要求'), findsOneWidget);
    expect(find.text('当时状态'), findsOneWidget);
    expect(find.text('待今日确认'), findsWidgets);
    expect(find.text(longAction), findsWidgets);
    expect(find.text('确认'), findsNothing, reason: '历史详情不得使用实时动作标签');
  });

  testWidgets('历史树「适应屏幕」全览大森林，节点可达且保持只读冻结语义', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 大森林：两棵各带三个兄弟分支的宽树，再加三个独立根把森林拉高。
    NationalFocusFailure largeFailure() => NationalFocusFailure(
      id: 'failure-large',
      batchId: 'batch-large',
      cardId: 'wide-a',
      checkpointAt: DateTime.utc(2026, 11, 15, 4),
      cause: NationalFocusFailureCause.missedConfirmation,
      failureReason: '未完成今日确认',
      sharedExplanation: null,
      treeSnapshot: [
        snapshot(id: 'wide-a', name: longName, action: longAction),
        snapshot(
          id: 'wide-a-1',
          name: '周三前发出评审邀请',
          action: '列出五个必须到场的评审人',
          parentId: 'wide-a',
        ),
        snapshot(
          id: 'wide-a-2',
          name: '补齐三条证据',
          action: '为每条结论附上来源与负责人',
          parentId: 'wide-a',
        ),
        snapshot(
          id: 'wide-a-3',
          name: '确认交付日期',
          action: '和负责人核对最后的日期',
          parentId: 'wide-a',
        ),
        snapshot(id: 'wide-b', name: '第二棵树：整理季度目标', action: '把目标拆成可交付结果'),
        snapshot(
          id: 'wide-b-1',
          name: '写下三个必须交付的结论',
          action: '按影响排序',
          parentId: 'wide-b',
        ),
        snapshot(
          id: 'wide-b-2',
          name: '补齐风险清单',
          action: '标出概率与影响',
          parentId: 'wide-b',
        ),
        snapshot(
          id: 'wide-b-3',
          name: '安排复盘会',
          action: '邀请直接相关的人',
          parentId: 'wide-b',
        ),
        snapshot(id: 'tall-3', name: '独立根：清空收件箱', action: '只保留今天要处理的邮件'),
        snapshot(id: 'tall-4', name: '独立根：整理桌面', action: '把资料按项目归档'),
        snapshot(id: 'tall-5', name: '独立根：写下明天第一件事', action: '落到具体时间与地点'),
      ],
    );

    final failure = largeFailure();
    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusFailureTreePage(
          failure: failure,
          checkpointLabel: '2026-11-15 12:00',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    final surface = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final viewport = tester.getRect(surface);
    final ids = [for (final card in failure.treeSnapshot) card.id];
    final nodes = [
      for (final id in ids)
        find.byKey(ValueKey('national-focus-history-node-$id')),
    ];
    for (final node in nodes) {
      expect(node, findsOneWidget);
    }

    double scale() =>
        tester.widget<Transform>(canvas).transform.entry(0, 0).abs();
    Rect rectOf(String id) =>
        tester.getRect(find.byKey(ValueKey('national-focus-history-node-$id')));
    bool overflows(Rect node) =>
        node.left < viewport.left - 0.5 ||
        node.right > viewport.right + 0.5 ||
        node.top < viewport.top - 0.5 ||
        node.bottom > viewport.bottom + 0.5;

    // 初始取景保留 0.85 可读下限；大森林因此允许超出画布，仍需缩放/平移查看。
    expect(scale(), closeTo(0.85, 0.001), reason: '初始取景仍按可读下限显示');
    expect(
      ids.where((id) => overflows(rectOf(id))),
      isNotEmpty,
      reason: '大森林的初始可读取景不要求装下整片森林',
    );

    // 显式「适应屏幕」必须真正全览：整片冻结森林都落在画布内。
    await tester.tap(find.byTooltip('适应屏幕'));
    await tester.pump();
    expect(scale(), lessThan(0.85), reason: '显式全览不应停在可读下限');
    for (final id in ids) {
      final node = rectOf(id);
      expect(node.width, greaterThan(0), reason: '节点 $id 应仍被渲染');
      expect(node.height, greaterThan(0), reason: '节点 $id 应仍被渲染');
      expect(
        node.left,
        greaterThanOrEqualTo(viewport.left - 0.5),
        reason: '节点 $id 左边界应落在画布内',
      );
      expect(
        node.right,
        lessThanOrEqualTo(viewport.right + 0.5),
        reason: '节点 $id 右边界应落在画布内',
      );
      expect(
        node.top,
        greaterThanOrEqualTo(viewport.top - 0.5),
        reason: '节点 $id 上边界应落在画布内',
      );
      expect(
        node.bottom,
        lessThanOrEqualTo(viewport.bottom + 0.5),
        reason: '节点 $id 下边界应落在画布内',
      );
    }

    // 全览后最远的冻结节点仍可达，且只读冻结语义、措辞保持不变。
    final farNode = find.byKey(
      const ValueKey('national-focus-history-node-tall-5'),
    );
    await tester.ensureVisible(farNode);
    await tester.tap(farNode);
    await tester.pumpAndSettle();
    expect(find.text('冻结要求'), findsOneWidget);
    expect(find.text('此页只读：不能恢复、改写或用当前规则重算当时状态。'), findsOneWidget);
    expect(find.text('落到具体时间与地点'), findsWidgets);
    expect(find.text('待今日确认'), findsWidgets);
    expect(find.text('确认'), findsNothing, reason: '历史详情不得使用实时动作标签');
    expect(
      find.byKey(const ValueKey('national-focus-mark-reviewed')),
      findsNothing,
      reason: '当时树页面不提供标记回顾等写入入口',
    );
  });
}
