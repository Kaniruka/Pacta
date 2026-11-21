import 'package:flutter/material.dart';

/// 计划日历与专注热力的日格状态色。
///
/// 三层语义严格分开：
/// 1. 背景只表达业务数据，按业务分两套档位：
///    - 计划日历三档：全部完成=[allCompleteBackground]（柔和绿）、有安排=
///      [hasPlansBackground]（柔和黄）、放假日=[holidayBackground]（柔和薰衣草）；
///    - 专注热力五档：[heat0Background]..[heat4Background]（`heat0..heat4`，
///      由浅到深的绿阶）。
///    选中与今天都不覆写背景，业务色始终可见。
/// 2. 描边只表达选中/今天：单层、与单元格等大，选中优先于今天。
/// 3. 今天另用独立 '今' 角标（[todayBadgeBackground]/[todayBadgeForeground]）
///    表达，不依赖描边，也不与右上角状态标记抢位置。
///
/// [selectedBackground]/[selectedForeground] 是历史保留字段：选中态早已改用
/// 描边表达、不再覆写底色，这两个值只作为回归负向断言（“业务底色不被选中蓝
/// 覆写”）的参考，任何渲染路径都不得把它们当作背景。
///
/// 颜色按亮暗主题各一套；所有前景与背景的对比度均 ≥ 4.5:1。
@immutable
class PactaCalendarColors extends ThemeExtension<PactaCalendarColors> {
  const PactaCalendarColors({
    required this.hasPlansBackground,
    required this.hasPlansForeground,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.selectedBorder,
    required this.allCompleteBackground,
    required this.allCompleteForeground,
    required this.holidayBackground,
    required this.holidayForeground,
    required this.todayBorder,
    required this.heat0Background,
    required this.heat0Foreground,
    required this.heat1Background,
    required this.heat1Foreground,
    required this.heat2Background,
    required this.heat2Foreground,
    required this.heat3Background,
    required this.heat3Foreground,
    required this.heat4Background,
    required this.heat4Foreground,
    required this.todayBadgeBackground,
    required this.todayBadgeForeground,
    required this.failureDotColor,
  });

  /// 有安排、但当天还有未完成安排时的底色。
  final Color hasPlansBackground;

  /// 对应 [hasPlansBackground] 的正文前景。
  final Color hasPlansForeground;

  /// 历史保留字段：旧版选中态底色（柔和蓝）。
  ///
  /// 选中现在只画 [selectedBorder] 描边、不覆写业务背景；本字段仅作回归负向
  /// 断言的参考值，不得在任何渲染路径中当作背景使用。
  final Color selectedBackground;

  /// 历史保留字段：对应 [selectedBackground] 的正文前景，同样只作回归参考。
  final Color selectedForeground;

  /// 选中日期的清晰描边。
  final Color selectedBorder;

  /// 当天安排全部完成时的底色。
  final Color allCompleteBackground;

  /// 对应 [allCompleteBackground] 的正文前景。
  final Color allCompleteForeground;

  /// 放假日（无安排/未选中）的柔性薰衣草底色。
  final Color holidayBackground;

  /// 放假日短标签的前景；也可叠加在黄/绿/蓝状态底上。
  final Color holidayForeground;

  /// 今天的中性石板描边；不抢占选中态的蓝色焦点。
  final Color todayBorder;

  /// 专注热力 0 档（0 秒）背景。
  final Color heat0Background;

  /// 专注热力 0 档前景。
  final Color heat0Foreground;

  /// 专注热力 1 档（> 0 且 < 30 分钟）背景。
  final Color heat1Background;

  /// 专注热力 1 档前景。
  final Color heat1Foreground;

  /// 专注热力 2 档（30 分钟..< 90 分钟）背景。
  final Color heat2Background;

  /// 专注热力 2 档前景。
  final Color heat2Foreground;

  /// 专注热力 3 档（90 分钟..< 180 分钟）背景。
  final Color heat3Background;

  /// 专注热力 3 档前景。
  final Color heat3Foreground;

  /// 专注热力 4 档（≥ 180 分钟）背景。
  final Color heat4Background;

  /// 专注热力 4 档前景。
  final Color heat4Foreground;

  /// '今' 角标底色；在无背景及绿/黄/薰衣草底上都保持高对比。
  final Color todayBadgeBackground;

  /// '今' 角标前景。
  final Color todayBadgeForeground;

  /// 失败标记的小红点；不承担正文语义，仅作辅助标记。
  final Color failureDotColor;

  static const PactaCalendarColors light = PactaCalendarColors(
    hasPlansBackground: Color(0xfffff3c4),
    hasPlansForeground: Color(0xff3d2e00),
    selectedBackground: Color(0xffd8e7ff),
    selectedForeground: Color(0xff0b2a55),
    selectedBorder: Color(0xff0b57d0),
    allCompleteBackground: Color(0xffd9f2df),
    allCompleteForeground: Color(0xff0e3b22),
    holidayBackground: Color(0xffefe9fb),
    holidayForeground: Color(0xff4a357a),
    todayBorder: Color(0xff5c6470),
    heat0Background: Color(0xffeef2f6),
    heat0Foreground: Color(0xff1f1f1f),
    heat1Background: Color(0xffceead6),
    heat1Foreground: Color(0xff0d3b1e),
    heat2Background: Color(0xff81c995),
    heat2Foreground: Color(0xff0b2e17),
    heat3Background: Color(0xff188038),
    heat3Foreground: Color(0xffffffff),
    heat4Background: Color(0xff0d652d),
    heat4Foreground: Color(0xffffffff),
    todayBadgeBackground: Color(0xff0b57d0),
    todayBadgeForeground: Color(0xffffffff),
    failureDotColor: Color(0xffc5221f),
  );

  static const PactaCalendarColors dark = PactaCalendarColors(
    hasPlansBackground: Color(0xff3b3210),
    hasPlansForeground: Color(0xffffe9a8),
    selectedBackground: Color(0xff1d3654),
    selectedForeground: Color(0xffd7e6ff),
    selectedBorder: Color(0xff8ab4f8),
    allCompleteBackground: Color(0xff173b24),
    allCompleteForeground: Color(0xffb8f0c6),
    holidayBackground: Color(0xff2a223b),
    holidayForeground: Color(0xffd6c6fb),
    todayBorder: Color(0xff9aa3b2),
    heat0Background: Color(0xff232730),
    heat0Foreground: Color(0xffc4c7c5),
    heat1Background: Color(0xff133822),
    heat1Foreground: Color(0xffb7e4c7),
    heat2Background: Color(0xff185732),
    heat2Foreground: Color(0xffd8f3dc),
    heat3Background: Color(0xff1e7e45),
    heat3Foreground: Color(0xffffffff),
    heat4Background: Color(0xff34a853),
    heat4Foreground: Color(0xff07210f),
    todayBadgeBackground: Color(0xffa8c7fa),
    todayBadgeForeground: Color(0xff062e6f),
    failureDotColor: Color(0xfff28b82),
  );

  static PactaCalendarColors of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<PactaCalendarColors>();
    assert(colors != null, 'PactaCalendarColors is missing from ThemeData.');
    return colors ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  /// 专注秒数到热力档位：0 秒为 0 档，其余按 30/90/180 分钟分档。
  static int heatLevelForSeconds(int seconds) {
    if (seconds <= 0) return 0;
    if (seconds < 1800) return 1;
    if (seconds < 5400) return 2;
    if (seconds < 10800) return 3;
    return 4;
  }

  /// 取指定档位（自动夹到 0..4）的背景与前景。
  (Color background, Color foreground) heatColorsForLevel(int level) =>
      switch (level.clamp(0, 4)) {
        0 => (heat0Background, heat0Foreground),
        1 => (heat1Background, heat1Foreground),
        2 => (heat2Background, heat2Foreground),
        3 => (heat3Background, heat3Foreground),
        _ => (heat4Background, heat4Foreground),
      };

  @override
  PactaCalendarColors copyWith({
    Color? hasPlansBackground,
    Color? hasPlansForeground,
    Color? selectedBackground,
    Color? selectedForeground,
    Color? selectedBorder,
    Color? allCompleteBackground,
    Color? allCompleteForeground,
    Color? holidayBackground,
    Color? holidayForeground,
    Color? todayBorder,
    Color? heat0Background,
    Color? heat0Foreground,
    Color? heat1Background,
    Color? heat1Foreground,
    Color? heat2Background,
    Color? heat2Foreground,
    Color? heat3Background,
    Color? heat3Foreground,
    Color? heat4Background,
    Color? heat4Foreground,
    Color? todayBadgeBackground,
    Color? todayBadgeForeground,
    Color? failureDotColor,
  }) => PactaCalendarColors(
    hasPlansBackground: hasPlansBackground ?? this.hasPlansBackground,
    hasPlansForeground: hasPlansForeground ?? this.hasPlansForeground,
    selectedBackground: selectedBackground ?? this.selectedBackground,
    selectedForeground: selectedForeground ?? this.selectedForeground,
    selectedBorder: selectedBorder ?? this.selectedBorder,
    allCompleteBackground: allCompleteBackground ?? this.allCompleteBackground,
    allCompleteForeground: allCompleteForeground ?? this.allCompleteForeground,
    holidayBackground: holidayBackground ?? this.holidayBackground,
    holidayForeground: holidayForeground ?? this.holidayForeground,
    todayBorder: todayBorder ?? this.todayBorder,
    heat0Background: heat0Background ?? this.heat0Background,
    heat0Foreground: heat0Foreground ?? this.heat0Foreground,
    heat1Background: heat1Background ?? this.heat1Background,
    heat1Foreground: heat1Foreground ?? this.heat1Foreground,
    heat2Background: heat2Background ?? this.heat2Background,
    heat2Foreground: heat2Foreground ?? this.heat2Foreground,
    heat3Background: heat3Background ?? this.heat3Background,
    heat3Foreground: heat3Foreground ?? this.heat3Foreground,
    heat4Background: heat4Background ?? this.heat4Background,
    heat4Foreground: heat4Foreground ?? this.heat4Foreground,
    todayBadgeBackground: todayBadgeBackground ?? this.todayBadgeBackground,
    todayBadgeForeground: todayBadgeForeground ?? this.todayBadgeForeground,
    failureDotColor: failureDotColor ?? this.failureDotColor,
  );

  @override
  PactaCalendarColors lerp(
    ThemeExtension<PactaCalendarColors>? other,
    double t,
  ) {
    if (other is! PactaCalendarColors) return this;
    return PactaCalendarColors(
      hasPlansBackground: Color.lerp(
        hasPlansBackground,
        other.hasPlansBackground,
        t,
      )!,
      hasPlansForeground: Color.lerp(
        hasPlansForeground,
        other.hasPlansForeground,
        t,
      )!,
      selectedBackground: Color.lerp(
        selectedBackground,
        other.selectedBackground,
        t,
      )!,
      selectedForeground: Color.lerp(
        selectedForeground,
        other.selectedForeground,
        t,
      )!,
      selectedBorder: Color.lerp(selectedBorder, other.selectedBorder, t)!,
      allCompleteBackground: Color.lerp(
        allCompleteBackground,
        other.allCompleteBackground,
        t,
      )!,
      allCompleteForeground: Color.lerp(
        allCompleteForeground,
        other.allCompleteForeground,
        t,
      )!,
      holidayBackground: Color.lerp(
        holidayBackground,
        other.holidayBackground,
        t,
      )!,
      holidayForeground: Color.lerp(
        holidayForeground,
        other.holidayForeground,
        t,
      )!,
      todayBorder: Color.lerp(todayBorder, other.todayBorder, t)!,
      heat0Background: Color.lerp(heat0Background, other.heat0Background, t)!,
      heat0Foreground: Color.lerp(heat0Foreground, other.heat0Foreground, t)!,
      heat1Background: Color.lerp(heat1Background, other.heat1Background, t)!,
      heat1Foreground: Color.lerp(heat1Foreground, other.heat1Foreground, t)!,
      heat2Background: Color.lerp(heat2Background, other.heat2Background, t)!,
      heat2Foreground: Color.lerp(heat2Foreground, other.heat2Foreground, t)!,
      heat3Background: Color.lerp(heat3Background, other.heat3Background, t)!,
      heat3Foreground: Color.lerp(heat3Foreground, other.heat3Foreground, t)!,
      heat4Background: Color.lerp(heat4Background, other.heat4Background, t)!,
      heat4Foreground: Color.lerp(heat4Foreground, other.heat4Foreground, t)!,
      todayBadgeBackground: Color.lerp(
        todayBadgeBackground,
        other.todayBadgeBackground,
        t,
      )!,
      todayBadgeForeground: Color.lerp(
        todayBadgeForeground,
        other.todayBadgeForeground,
        t,
      )!,
      failureDotColor: Color.lerp(failureDotColor, other.failureDotColor, t)!,
    );
  }
}
