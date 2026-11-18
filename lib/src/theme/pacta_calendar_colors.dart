import 'package:flutter/material.dart';

/// 计划日历的日格状态色。
///
/// 背景只表达“这一天有什么”：有安排=柔和黄、选中=柔和蓝、当日安排全部
/// 完成=柔和绿。放假日使用独立的薰衣草调，蓝色专属选中态，避免两者撞色。
/// 颜色按亮暗主题各一套，保持低饱和；正文前景与背景的对比度均 ≥ 4.5:1。
///
/// 优先级由页面决定：选中 > 全部完成 > 有安排；放假日底色只在三者都
/// 不适用时作为兜底。今天使用中性描边，选中使用主蓝描边，二者可同时显示。
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
  });

  /// 有安排、但当天还有未完成安排时的底色。
  final Color hasPlansBackground;

  /// 对应 [hasPlansBackground] 的正文前景。
  final Color hasPlansForeground;

  /// 选中日期的底色；蓝色只用于选中态。
  final Color selectedBackground;

  /// 对应 [selectedBackground] 的正文前景。
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
  );

  static PactaCalendarColors of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<PactaCalendarColors>();
    assert(colors != null, 'PactaCalendarColors is missing from ThemeData.');
    return colors ?? (theme.brightness == Brightness.dark ? dark : light);
  }

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
    );
  }
}
