import 'package:flutter/material.dart';

/// 页面 / 卡片 / 底部固定操作区三层表面的语义令牌。
///
/// Google 服务式 Material 3 扁平层级：浅蓝灰页面、纯白卡片、零投影边界。
/// 卡片靠底色差与 20dp 圆角分开，不再用投影表达层级；只有底部固定操作区
/// 保留一层很浅的投影，避免与可滚动内容粘连。暗色主题沿用同层色阶，
/// 投影对暗色几乎不可见，层级仍由色差承担。
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

  /// 卡片底色，与页面明确分层。
  final Color card;

  /// 底部固定操作区底色，与卡片同层或再抬一档。
  final Color actionBar;

  /// 同层之间的细分隔线，不用来表达卡片边界。
  final Color hairline;

  /// 卡片投影；Google 扁平卡片为全透明，保留字段供页面兼容调用。
  final Color cardShadow;

  /// 底部操作区与导航栏的投影。
  final Color actionBarShadow;

  static const PactaSurfaces light = PactaSurfaces(
    page: Color(0xfff2f6fc),
    card: Color(0xffffffff),
    actionBar: Color(0xffffffff),
    hairline: Color(0xffe3e8ef),
    cardShadow: Color(0x00000000),
    actionBarShadow: Color(0x1f000000),
  );

  static const PactaSurfaces dark = PactaSurfaces(
    page: Color(0xff0e1116),
    card: Color(0xff1c2129),
    actionBar: Color(0xff252b36),
    hairline: Color(0xff2d333d),
    cardShadow: Color(0x00000000),
    actionBarShadow: Color(0x66000000),
  );

  static PactaSurfaces of(BuildContext context) {
    final surfaces = Theme.of(context).extension<PactaSurfaces>();
    assert(surfaces != null, 'PactaSurfaces is missing from ThemeData.');
    return surfaces ?? light;
  }

  /// 独立路由兜底：预览或测试宿主可能只提供裸 [ThemeData]，此时补一层
  /// [PactaSurfaces]，让分组列表等依赖表面的组件始终有定义；已注入时原样返回。
  static Widget wrapIfMissing(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    if (theme.extension<PactaSurfaces>() != null) return child;
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values,
          theme.brightness == Brightness.dark ? dark : light,
        ],
      ),
      child: child,
    );
  }

  /// 按亮度直接取卡片底色。
  ///
  /// 画布内嵌组件（例如只读历史节点）不一定继承注入了 [PactaSurfaces] 的
  /// 主题（灰盒测试只用裸 MaterialApp）；按亮度取同一份语义令牌，既保持
  /// 卡片与 `surfaceContainerLow` 画布的分层，也不把断言带进组件树。
  static Color cardFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark.card : light.card;

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
