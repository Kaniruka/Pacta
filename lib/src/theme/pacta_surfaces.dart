import 'package:flutter/material.dart';

/// 页面 / 卡片 / 底部固定操作区三层表面的语义令牌。
///
/// 只靠 `surfaceContainerLow` 一档色差，在亮暗两套主题里都不足以分开层级：
/// 页面最低、卡片抬起一层、操作区再抬起一层。亮色主题用极浅投影补足边界，
/// 暗色主题投影不可见，靠色阶本身区分。卡片不再靠描边表达层级。
@immutable
class PactaSurfaces extends ThemeExtension<PactaSurfaces> {
  const PactaSurfaces({
    required this.page,
    required this.card,
    required this.actionBar,
    required this.hairline,
    required this.cardShadow,
    required this.actionBarShadow,
  });

  /// 页面底色（Scaffold 背景）。
  final Color page;

  /// 卡片底色，比页面亮一档。
  final Color card;

  /// 底部固定操作区底色，比卡片再亮/抬一档。
  final Color actionBar;

  /// 同层之间的细分隔线，不用来表达卡片边界。
  final Color hairline;

  /// 亮色主题的卡片投影；暗色主题为全透明。
  final Color cardShadow;

  /// 底部操作区与导航栏的投影。
  final Color actionBarShadow;

  static const PactaSurfaces light = PactaSurfaces(
    page: Color(0xfff2f6fc),
    card: Color(0xffffffff),
    actionBar: Color(0xffffffff),
    hairline: Color(0xffd9e2ef),
    cardShadow: Color(0x14000000),
    actionBarShadow: Color(0x1f000000),
  );

  static const PactaSurfaces dark = PactaSurfaces(
    page: Color(0xff0d1015),
    card: Color(0xff1c2129),
    actionBar: Color(0xff232932),
    hairline: Color(0xff2f3641),
    cardShadow: Color(0x00000000),
    actionBarShadow: Color(0x66000000),
  );

  static PactaSurfaces of(BuildContext context) {
    final surfaces = Theme.of(context).extension<PactaSurfaces>();
    assert(surfaces != null, 'PactaSurfaces is missing from ThemeData.');
    return surfaces ?? light;
  }

  @override
  PactaSurfaces copyWith({
    Color? page,
    Color? card,
    Color? actionBar,
    Color? hairline,
    Color? cardShadow,
    Color? actionBarShadow,
  }) => PactaSurfaces(
    page: page ?? this.page,
    card: card ?? this.card,
    actionBar: actionBar ?? this.actionBar,
    hairline: hairline ?? this.hairline,
    cardShadow: cardShadow ?? this.cardShadow,
    actionBarShadow: actionBarShadow ?? this.actionBarShadow,
  );

  @override
  PactaSurfaces lerp(ThemeExtension<PactaSurfaces>? other, double t) {
    if (other is! PactaSurfaces) return this;
    return PactaSurfaces(
      page: Color.lerp(page, other.page, t)!,
      card: Color.lerp(card, other.card, t)!,
      actionBar: Color.lerp(actionBar, other.actionBar, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      actionBarShadow: Color.lerp(actionBarShadow, other.actionBarShadow, t)!,
    );
  }
}
