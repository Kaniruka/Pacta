import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pacta_calendar_colors.dart';
import 'pacta_fonts.dart';
import 'pacta_spacing.dart';
import 'pacta_status_colors.dart';
import 'pacta_surfaces.dart';

TextTheme _pactaTextTheme(TextTheme theme) {
  TextStyle? weight(TextStyle? style, FontWeight value) =>
      style?.copyWith(fontWeight: value);
  return theme.copyWith(
    displayLarge: weight(theme.displayLarge, PactaFonts.regular),
    displayMedium: weight(theme.displayMedium, PactaFonts.regular),
    displaySmall: weight(theme.displaySmall, PactaFonts.regular),
    headlineLarge: weight(theme.headlineLarge, PactaFonts.regular),
    headlineMedium: weight(theme.headlineMedium, PactaFonts.regular),
    headlineSmall: weight(theme.headlineSmall, PactaFonts.regular),
    titleLarge: weight(theme.titleLarge, PactaFonts.medium),
    titleMedium: weight(theme.titleMedium, PactaFonts.medium),
    titleSmall: weight(theme.titleSmall, PactaFonts.medium),
    bodyLarge: weight(theme.bodyLarge, PactaFonts.regular),
    bodyMedium: weight(theme.bodyMedium, PactaFonts.regular),
    bodySmall: weight(theme.bodySmall, PactaFonts.regular),
    labelLarge: weight(theme.labelLarge, PactaFonts.medium),
    labelMedium: weight(theme.labelMedium, PactaFonts.medium),
    labelSmall: weight(theme.labelSmall, PactaFonts.medium),
  );
}

/// The app theme, shared with offline layout fixtures so evidence never
/// invents a second visual language.
ThemeData pactaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff0b57d0),
        brightness: brightness,
      ).copyWith(
        primary: Color(dark ? 0xffa8c7fa : 0xff0b57d0),
        onPrimary: Color(dark ? 0xff062e6f : 0xffffffff),
        primaryContainer: Color(dark ? 0xff0842a0 : 0xffd3e3fd),
        onPrimaryContainer: Color(dark ? 0xffd3e3fd : 0xff041e49),
        secondary: Color(dark ? 0xffb4c8e8 : 0xff355e92),
        onSecondary: Color(dark ? 0xff1a3353 : 0xffffffff),
        secondaryContainer: Color(dark ? 0xff2d4667 : 0xffe1ecff),
        onSecondaryContainer: Color(dark ? 0xffd6e5ff : 0xff1a3353),
        tertiary: Color(dark ? 0xfff5c451 : 0xff7f5700),
        onTertiary: Color(dark ? 0xff402d00 : 0xffffffff),
        tertiaryContainer: Color(dark ? 0xff5b4300 : 0xfffff1c2),
        onTertiaryContainer: Color(dark ? 0xffffe8aa : 0xff3f2a00),
        surface: Color(dark ? 0xff111318 : 0xfff8fafd),
        onSurface: Color(dark ? 0xffe3e3e3 : 0xff1f1f1f),
        onSurfaceVariant: Color(dark ? 0xffc4c7c5 : 0xff444746),
        surfaceContainerLowest: Color(dark ? 0xff0d0f14 : 0xffffffff),
        surfaceContainerLow: Color(dark ? 0xff1b1d23 : 0xfff0f4f9),
        surfaceContainer: Color(dark ? 0xff23262d : 0xffe9eef6),
        surfaceContainerHigh: Color(dark ? 0xff2b2e36 : 0xffe3eaf5),
        surfaceContainerHighest: Color(dark ? 0xff34373f : 0xffdee5f0),
        outline: Color(dark ? 0xff8e918f : 0xff747775),
        outlineVariant: Color(dark ? 0xff444746 : 0xffc4c7c5),
      );
  final surfaces = dark ? PactaSurfaces.dark : PactaSurfaces.light;
  final base = ThemeData(
    fontFamily: PactaFonts.family,
    colorScheme: colors,
    useMaterial3: true,
  );
  // 主题是字体的唯一入口：所有语义字号（含 label 系列和 primary）都显式
  // 收敛到 MiSans，页面/组件不得再声明第二个字体族。
  final textTheme = _pactaTextTheme(
    base.textTheme.apply(fontFamily: PactaFonts.family),
  );
  final primaryTextTheme = _pactaTextTheme(
    base.primaryTextTheme.apply(fontFamily: PactaFonts.family),
  );
  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    extensions: [
      dark ? PactaStatusColors.dark : PactaStatusColors.light,
      dark ? PactaCalendarColors.dark : PactaCalendarColors.light,
      surfaces,
    ],
    scaffoldBackgroundColor: surfaces.page,
    // Google 服务式 Material 3：页面浅蓝灰、卡片纯白零投影、统一 20dp 圆角。
    // 层级由底色差与圆角表达，不用投影或描边；底部固定操作区另有一套语义。
    cardTheme: CardThemeData(
      elevation: 0,
      color: surfaces.card,
      shadowColor: surfaces.cardShadow,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PactaSpacing.cardRadius),
      ),
      margin: EdgeInsets.zero,
    ),
    // 弹出菜单与卡片同一表面语言：白底、12dp 圆角、轻微抬起。
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.card,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // 分组列表的 1dp 细分隔线：只用来切分同一容器内的相邻行。
    dividerTheme: DividerThemeData(
      color: surfaces.hairline,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: colors.outlineVariant),
      selectedColor: colors.secondaryContainer,
      backgroundColor: surfaces.card,
    ),
    // ListTile 的 contentPadding 会以 SafeArea 形式加在整行外侧：vertical 4
    // 会让每行无差别长高 8dp，破坏 M3 固定的 56/72dp 行高，并把《通知与设备
    // 权限》的第三个分组挤出 ListView 预构建范围。这里只固定 Google 式的
    // 16dp 水平内容边距，纵向呼吸交给 ListTile 自身的行高规格。
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: surfaces.page,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaces.card,
      surfaceTintColor: Colors.transparent,
      // 中文弹窗标题折行时标题级别过重会压住输入区，统一到 titleLarge。
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: PactaFonts.semibold,
        color: colors.onSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaces.actionBar,
      indicatorColor: colors.primaryContainer,
      elevation: 3,
      shadowColor: surfaces.actionBarShadow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surfaces.card,
      indicatorColor: colors.primaryContainer,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaces.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// 桌面端与触屏一致的滚动设备集合。
///
/// Flutter 默认的 [MaterialScrollBehavior] 不把鼠标列为拖动设备，Windows
/// 上按住左键拖动列表不会滚动。这里显式补齐鼠标、触控笔与触控板，让桌面
/// 与移动端共用同一套"按住拖动"的肌肉记忆。
class PactaScrollBehavior extends MaterialScrollBehavior {
  const PactaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}
