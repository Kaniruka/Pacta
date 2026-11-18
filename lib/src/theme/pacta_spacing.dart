import 'package:flutter/widgets.dart';

/// 全站横向节奏的唯一来源。
///
/// 页面、卡片与底部固定操作区都从这里取边距，页面里不再写 14/20 之类的
/// 字面量：窄屏与宽屏的差别只在这一处决定。
abstract final class PactaSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 窄屏页边距（手机与窄窗口）。
  static const double compactGutter = lg;

  /// 宽屏页边距。
  static const double wideGutter = xl;

  /// 达到该逻辑宽度后按宽屏排版。
  static const double wideBreakpoint = 720;

  /// 正文内容的最大宽度，与 AppShell 的目的地约束一致。
  static const double maxContentWidth = 960;

  /// 卡片圆角：页面级卡片统一用一个值，避免每处各写一遍。
  static const double cardRadius = 20;

  /// 底部固定操作区的顶部圆角。
  static const double actionBarRadius = 20;

  static bool isWide(double width) => width >= wideBreakpoint;

  static double gutterFor(double width) =>
      isWide(width) ? wideGutter : compactGutter;

  /// 页面左右边距：窄屏 16、宽屏 24。
  static EdgeInsets pageInsets(
    BuildContext context, {
    double top = lg,
    double bottom = xl,
  }) {
    final gutter = gutterFor(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(gutter, top, gutter, bottom);
  }
}
