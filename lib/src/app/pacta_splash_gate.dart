import 'package:flutter/material.dart';

import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';

/// Google 风格开屏过渡层。
///
/// Android 原生启动层（`launch_background`）在引擎画出第一帧时就被移除，这里
/// 接住之后的画面：居中品牌锚点徽标弹性放大、主色光环柔和扩散，最后用交叉
/// 淡入淡出把画面交还 [child]，让冷启动到首屏之间不再出现白屏闪跳。
///
/// 动画结束后覆盖层整块卸载，既不残留拦截点击的透明层，也不继续占用 Ticker。
class PactaSplashGate extends StatefulWidget {
  const PactaSplashGate({
    super.key,
    required this.child,
    this.enableSplash,
    this.introDuration = defaultIntroDuration,
    this.fadeDuration = defaultFadeDuration,
  });

  /// 覆盖层根节点的 Key；开屏结束后该节点不再存在于树中。
  static const Key overlayKey = ValueKey('pacta-splash-overlay');

  /// 入场节奏：徽标弹性放大 + 光环扩散。
  static const Duration defaultIntroDuration = Duration(milliseconds: 620);

  /// 交接节奏：覆盖层淡出、首屏淡入。
  static const Duration defaultFadeDuration = Duration(milliseconds: 260);

  /// 首屏内容。开屏期间它已经构建完毕，所以淡出时不会再有第二段加载空档。
  final Widget child;

  /// 为空时由当前绑定决定：只有真实 app 的 [WidgetsFlutterBinding] 默认播放；
  /// [TestWidgetsFlutterBinding] 等测试绑定默认直接渲染 [child]、零等待，既有
  /// 测试的 `pumpAndSettle` 时序不受影响。显式传入 `true` 可在测试里完整走一遍
  /// 开屏动画。
  final bool? enableSplash;

  final Duration introDuration;
  final Duration fadeDuration;

  /// 真实运行绑定下默认开启开屏。
  static bool get defaultEnabled =>
      WidgetsBinding.instance.runtimeType.toString() == 'WidgetsFlutterBinding';

  @override
  State<PactaSplashGate> createState() => _PactaSplashGateState();
}

class _PactaSplashGateState extends State<PactaSplashGate>
    with TickerProviderStateMixin {
  AnimationController? _intro;
  AnimationController? _fade;
  late final Animation<double> _badgeScale;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;
  late final Animation<double> _overlayOpacity;
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    if (!(widget.enableSplash ?? PactaSplashGate.defaultEnabled)) return;
    _showOverlay = true;
    final intro = AnimationController(
      vsync: this,
      duration: widget.introDuration,
    );
    final fade = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
    );
    _intro = intro;
    _fade = fade;
    _badgeScale = Tween<double>(
      begin: 0.72,
      end: 1,
    ).animate(CurvedAnimation(parent: intro, curve: Curves.easeOutBack));
    _wordmarkOpacity = CurvedAnimation(
      parent: intro,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );
    _rippleScale = Tween<double>(begin: 0.55, end: 1.9).animate(
      CurvedAnimation(
        parent: intro,
        curve: const Interval(0.05, 1, curve: Curves.easeOutCubic),
      ),
    );
    _rippleOpacity = Tween<double>(begin: 0.32, end: 0).animate(
      CurvedAnimation(
        parent: intro,
        curve: const Interval(0.05, 0.9, curve: Curves.easeOut),
      ),
    );
    _overlayOpacity = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: fade, curve: Curves.easeInOut));
    intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) fade.forward();
    });
    fade.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showOverlay = false);
      }
    });
    intro.forward();
  }

  @override
  void dispose() {
    _intro?.dispose();
    _fade?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showOverlay) return widget.child;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: FadeTransition(
            opacity: _overlayOpacity,
            child: ColoredBox(
              key: PactaSplashGate.overlayKey,
              color: colors.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 涟漪最大直径约 132 × 1.9 ≈ 251，画布留到 260 才不会被裁边。
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _intro!,
                            builder: (context, _) => Transform.scale(
                              scale: _rippleScale.value,
                              child: Opacity(
                                opacity: _rippleOpacity.value,
                                child: Container(
                                  width: 132,
                                  height: 132,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.primary.withValues(
                                        alpha: 0.6,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ScaleTransition(
                            scale: _badgeScale,
                            child: _BrandBadge(colors: colors),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PactaSpacing.xl),
                    FadeTransition(
                      opacity: _wordmarkOpacity,
                      child: Text(
                        'Pacta',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          letterSpacing: 1.4,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 开屏品牌锚点：圆形浅底徽标 + 锚点图标，与《关于 Pacta》、登录页及桌面/安卓应用图标同源。
class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primaryContainer,
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.2),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(
        Icons.anchor_rounded,
        size: PactaIconSizes.heroLarge,
        color: colors.onPrimaryContainer,
      ),
    );
  }
}
