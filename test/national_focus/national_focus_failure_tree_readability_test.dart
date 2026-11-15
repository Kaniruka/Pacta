import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';

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
}
