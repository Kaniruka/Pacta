import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 打开计划目的地：宽屏用 NavigationRail，窄屏用 NavigationBar。
///
/// 07 之后目标/任务的完整管理只在计划页；看板只保留摘要。
Future<void> openPlan(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('计划')));
  await tester.pumpAndSettle();
}

/// 回到看板目的地。
Future<void> openBoard(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('看板')));
  await tester.pumpAndSettle();
}
