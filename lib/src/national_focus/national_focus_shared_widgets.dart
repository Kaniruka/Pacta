import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_status_colors.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_grouped_list.dart';
import 'national_focus_icons.dart';
import 'national_focus_models.dart';

class NationalFocusTreeCanvasScale extends InheritedWidget {
  const NationalFocusTreeCanvasScale({
    super.key,
    required this.scale,
    required super.child,
  });

  final double scale;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NationalFocusTreeCanvasScale>()
          ?.scale ??
      1;

  @override
  bool updateShouldNotify(NationalFocusTreeCanvasScale oldWidget) =>
      oldWidget.scale != scale;
}

/// Touch drags stay in the surrounding scroll view until a second finger
/// joins. Mouse drags can claim the canvas with one pointer.
class _CanvasScaleRecognizer extends ScaleGestureRecognizer {
  final Set<int> _touchPointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touchPointers.add(event.pointer);
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent && _touchPointers.length >= 2) {
      super.resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touchPointers.remove(event.pointer);
    }
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted &&
        _touchPointers.isNotEmpty &&
        pointerCount < 2) {
      return;
    }
    super.resolve(disposition);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _touchPointers.clear();
  }
}

class NationalFocusTreeCanvas extends StatefulWidget {
  const NationalFocusTreeCanvas({
    super.key,
    required this.treeWidth,
    required this.treeHeight,
    required this.child,
    this.minimumFitScale = 0,
    this.fitViewportToContent = false,
  });

  final double treeWidth;
  final double treeHeight;
  final Widget child;

  /// 初始取景允许的最小可读比例。0 表示沿用现有树的行为：
  /// 只在需要时缩小，绝不放大原始尺寸的内容；历史视角用 0.85 保证初始
  /// 字号可读，显式「适应屏幕」仍按全览拟合。
  final double minimumFitScale;

  /// 视口高度是否贴合内容高度。历史小森林据此不再漂浮在整屏空白里；
  /// 现有树保持固定视口比例不变。
  final bool fitViewportToContent;

  @override
  State<NationalFocusTreeCanvas> createState() =>
      NationalFocusTreeCanvasState();
}

class NationalFocusTreeCanvasState extends State<NationalFocusTreeCanvas> {
  final GlobalKey _gestureKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  double _scale = 1;
  double _gestureStartScale = 1;
  Offset _gestureSceneFocal = Offset.zero;
  bool _gestureIsTouch = false;
  Size? _viewport;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_syncScale);
  }

  @override
  void didUpdateWidget(covariant NationalFocusTreeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.treeWidth != widget.treeWidth ||
        oldWidget.treeHeight != widget.treeHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _viewport != null) _fit(_viewport!);
      });
    }
  }

  void _syncScale() {
    // The canvas only scales in X/Y. Matrix4's max-axis helper includes Z=1,
    // so it reports 100% for every fitted tree below 100%.
    final scale = _transform.value.entry(0, 0).abs();
    _scale = scale;
  }

  @override
  void dispose() {
    _transform.removeListener(_syncScale);
    _transform.dispose();
    super.dispose();
  }

  void _onGestureStart(ScaleStartDetails details) {
    _gestureIsTouch = details.kind == PointerDeviceKind.touch;
    _gestureStartScale = _scale;
    _gestureSceneFocal = _transform.toScene(details.localFocalPoint);
  }

  void _onGestureUpdate(ScaleUpdateDetails details) {
    if (_gestureIsTouch && details.pointerCount < 2) return;
    final viewport = _viewport;
    if (viewport == null) return;
    final next = (_gestureStartScale * details.scale).clamp(
      _minimumScale(viewport),
      3.0,
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        details.localFocalPoint.dx - _gestureSceneFocal.dx * next,
        details.localFocalPoint.dy - _gestureSceneFocal.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, 1, 1);
  }

  void _zoomAt(Offset focal, double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final next = (_scale * factor).clamp(_minimumScale(viewport), 3.0);
    final sceneFocal = _transform.toScene(focal);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        focal.dx - sceneFocal.dx * next,
        focal.dy - sceneFocal.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, 1, 1);
  }

  /// 全览拟合比例：把整棵树放进视口，不套用可读下限。
  ///
  /// 「适应屏幕」按这个比例取景，保证宽兄弟与高森林都能完整看到。
  double _fitAllScale(Size viewport) => math.min(
    1.0,
    math.min(
      math.max(1, viewport.width - 24) / widget.treeWidth,
      math.max(1, viewport.height - 24) / widget.treeHeight,
    ),
  );

  /// 初始取景比例：在全览比例之上套用可读下限。
  ///
  /// 历史视角因此一开始就把字号保持在 85% 以上，即便森林更大；
  /// 现有树的 minimumFitScale 为 0，初始取景与全览完全一致。
  double _initialFitScale(Size viewport) =>
      math.max(_fitAllScale(viewport), widget.minimumFitScale.clamp(0.0, 1.0));

  double _minimumScale(Size viewport) =>
      math.min(0.01, _initialFitScale(viewport));

  void _fit(Size viewport, {bool fitAll = false}) {
    _viewport = viewport;
    final scale = fitAll ? _fitAllScale(viewport) : _initialFitScale(viewport);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - widget.treeWidth * scale) / 2,
        (viewport.height - widget.treeHeight * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _scale = scale);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableHeight = (MediaQuery.sizeOf(context).height * 0.65).clamp(
        360.0,
        720.0,
      );
      final viewport = Size(
        constraints.maxWidth,
        widget.fitViewportToContent
            ? (widget.treeHeight + 24).clamp(200.0, availableHeight)
            : availableHeight,
      );
      if (_viewport != viewport) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(viewport);
        });
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: SizedBox(
          height: viewport.height,
          child: Stack(
            children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is! PointerScrollEvent ||
                      !HardwareKeyboard.instance.isControlPressed) {
                    return;
                  }
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (resolved) {
                      final renderBox = _gestureKey.currentContext
                          ?.findRenderObject();
                      if (renderBox is! RenderBox) return;
                      final focal = renderBox.globalToLocal(resolved.position);
                      _zoomAt(focal, math.exp(-event.scrollDelta.dy / 200));
                    },
                  );
                },
                child: ClipRect(
                  child: RawGestureDetector(
                    key: _gestureKey,
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      _CanvasScaleRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _CanvasScaleRecognizer
                          >(
                            () => _CanvasScaleRecognizer(),
                            (recognizer) => recognizer
                              ..onStart = _onGestureStart
                              ..onUpdate = _onGestureUpdate,
                          ),
                    },
                    child: SizedBox.expand(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            child: ValueListenableBuilder<Matrix4>(
                              valueListenable: _transform,
                              builder: (context, matrix, _) => Transform(
                                key: const ValueKey('national-focus-canvas'),
                                transform: matrix,
                                child: SizedBox(
                                  width: widget.treeWidth,
                                  height: widget.treeHeight,
                                  child: NationalFocusTreeCanvasScale(
                                    scale: _scale,
                                    child: widget.child,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: IconButton(
                    tooltip: '适应屏幕',
                    onPressed: () => _fit(viewport, fitAll: true),
                    icon: const Icon(Icons.fit_screen, size: PactaIconSizes.md),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class NationalFocusFieldText extends StatelessWidget {
  const NationalFocusFieldText({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(
        value.isEmpty ? '未设置' : value,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ],
  );
}

/// 国策卡状态图标井：40dp 圆形底 + 语义前景色。
///
/// 三态与国策树简洁节点（[NationalFocusCardState] 的亮 / 待确认 / 熄灭）完全
/// 同源：点亮取成功容器色，待确认取三级提醒容器色，熄灭取中性容器色；描边
/// 固定用 [ColorScheme.outlineVariant]，让同一状态在树与详情页读成同一个点。
///
/// 图标固定在 [PactaIconSizes.md]、井固定在 [PactaIconSizes.hero]：三态在
/// 任何页面都是同一枚 40dp 圆点，调用方不再各自覆写像素。
class NationalFocusStatusWell extends StatelessWidget {
  const NationalFocusStatusWell({super.key, required this.state, this.iconKey});

  final NationalFocusCardState state;

  /// 卡片自定义图标键；点亮与熄灭态直接渲染它，空值/未知键回落默认灯泡，
  /// 待今日确认态保留沙漏语义图标。
  final String? iconKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = PactaStatusColors.of(context);
    final customIcon = nationalFocusIconData(iconKey);
    final (Color background, Color foreground, IconData icon) = switch (state) {
      NationalFocusCardState.lit => (
        status.successContainer,
        status.onSuccessContainer,
        customIcon,
      ),
      NationalFocusCardState.pendingTodayConfirmation => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        Icons.hourglass_top,
      ),
      NationalFocusCardState.extinguished => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        customIcon,
      ),
    };
    return Container(
      width: PactaIconSizes.hero,
      height: PactaIconSizes.hero,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Icon(icon, size: PactaIconSizes.md, color: foreground),
    );
  }
}

/// 卡片自定义图标的圆形图标井：列表头与失败记录节点行共用。
///
/// 井径默认 40dp（详情/身份卡尺度），列表可传 [PactaIconSizes.lg] 收紧；
/// 井内图标固定 [PactaIconSizes.sm]，几何只由井径决定。空值/未知键回落
/// 默认灯泡，颜色取中性前景，不与三态语义色抢注意力。
class NationalFocusCardIconWell extends StatelessWidget {
  const NationalFocusCardIconWell({
    super.key,
    required this.iconKey,
    this.diameter = PactaIconSizes.hero,
    this.foreground,
    this.background,
  });

  final String? iconKey;
  final double diameter;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ?? colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Icon(
        nationalFocusIconData(iconKey),
        size: PactaIconSizes.sm,
        color: foreground ?? colors.onSurfaceVariant,
      ),
    );
  }
}

/// 卡内柔化提示槽：`surfaceContainerLow` 底、12dp 圆角、行内 ⓘ。
///
/// 身份卡的连带说明与编辑页的强化档位提示共用这一块，避免两处各写一遍
/// 底色、圆角、图标尺度与正文样式。
class NationalFocusInfoCallout extends StatelessWidget {
  const NationalFocusInfoCallout({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: PactaIconSizes.sm,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: PactaSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片状态胶囊：把三态映射到 [PactaStatusBadge] 的语义语气。
///
/// 点亮用成功、待确认用提醒、熄灭用中性；文字始终保留，不靠颜色单独表达状态。
class NationalFocusStateBadge extends StatelessWidget {
  const NationalFocusStateBadge({super.key, required this.state});

  final NationalFocusCardState state;

  @override
  Widget build(BuildContext context) => PactaStatusBadge(
    label: state.label,
    tone: switch (state) {
      NationalFocusCardState.lit => PactaStatusBadgeTone.success,
      NationalFocusCardState.pendingTodayConfirmation =>
        PactaStatusBadgeTone.warning,
      NationalFocusCardState.extinguished => PactaStatusBadgeTone.neutral,
    },
  );
}

/// 内化进度轨：圆端、4dp（详情页 6dp），已内化时取成功前景色封顶。
///
/// 语义标签只报一次百分比，读屏不会把进度条读成一段没有数值的图形。
class NationalFocusInternalizationBar extends StatelessWidget {
  const NationalFocusInternalizationBar({
    super.key,
    required this.card,
    this.height = 4,
  });

  final NationalFocusCard card;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = PactaStatusColors.of(context);
    final progress = card.internalizationProgress.clamp(0.0, 100.0);
    return Semantics(
      label: '内化进度 ${progress.toStringAsFixed(1)}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: progress / 100,
          minHeight: height,
          backgroundColor: colors.surfaceContainerHigh,
          valueColor: AlwaysStoppedAnimation<Color>(
            card.isInternalized ? status.onSuccessContainer : colors.primary,
          ),
        ),
      ),
    );
  }
}

/// 国策卡身份总览卡：状态井 + 名称与连击胶囊 + 状态徽标 + 可选的连带说明。
///
/// 详情页与只读镜像共用同一张卡，避免两处各写一套头部。名称与
/// [NationalFocusStreakTags] 必须同处一个 [Wrap]：短名称时胶囊紧跟名称右侧，
/// 长名称自动换行，而不是被挤到下一行的最左缘。
class NationalFocusCardIdentityCard extends StatelessWidget {
  const NationalFocusCardIdentityCard({
    super.key,
    required this.card,
    this.cascadeNote,
  });

  final NationalFocusCard card;

  /// 连带熄灭 / 恢复说明；为空时整块提示槽不占位。
  final String? cascadeNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = cascadeNote;
    return Card(
      child: Padding(
        padding: PactaSpacing.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NationalFocusStatusWell(
                  state: card.state,
                  iconKey: card.iconKey,
                ),
                const SizedBox(width: PactaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: PactaSpacing.sm,
                        runSpacing: 6,
                        children: [
                          Text(
                            card.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: PactaFonts.semibold,
                            ),
                          ),
                          NationalFocusStreakTags(
                            currentConsecutiveDays: card.currentConsecutiveDays,
                            bestConsecutiveDays: card.bestConsecutiveDays,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          NationalFocusStateBadge(state: card.state),
                          if (card.isInternalized)
                            const PactaStatusBadge(
                              label: '已内化',
                              icon: Icons.verified_outlined,
                              tone: PactaStatusBadgeTone.success,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: PactaSpacing.md),
              NationalFocusInfoCallout(message: note),
            ],
          ],
        ),
      ),
    );
  }
}

/// 详情页规则卡：主蓝「国策规则」标题 + 可选强化档位胶囊 + 可复制正文。
///
/// 可编辑详情与只读镜像共用这一张卡：[footer] 承载页面各自的判例呈现
/// （可编辑页用折叠层，只读页用静态段落），卡身结构零分叉。
class NationalFocusDetailRulesCard extends StatelessWidget {
  const NationalFocusDetailRulesCard({
    super.key,
    required this.card,
    this.footer,
  });

  final NationalFocusCard card;

  /// 规则下方的附加阅读层；为空时连 1dp 发丝线与留白一起省略。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaces = PactaSurfaces.of(context);
    final footerWidget = footer;
    return Card(
      child: Padding(
        padding: PactaSpacing.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '国策规则',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: PactaFonts.medium,
                    ),
                  ),
                ),
                if (card.activeStrengtheningLevel != null)
                  PactaStatusBadge(
                    label: '强化等级 ${card.activeStrengtheningLevel}',
                    icon: Icons.trending_up,
                    tone: PactaStatusBadgeTone.primary,
                  ),
              ],
            ),
            const SizedBox(height: PactaSpacing.sm),
            SelectableText(
              card.effectiveAction.isEmpty ? '未设置' : card.effectiveAction,
              style: theme.textTheme.bodyLarge,
            ),
            if (footerWidget != null) ...[
              const SizedBox(height: PactaSpacing.md),
              Container(height: 1, color: surfaces.hairline),
              const SizedBox(height: PactaSpacing.xs),
              footerWidget,
            ],
          ],
        ),
      ),
    );
  }
}

/// 详情页记录卡：主蓝「记录」标题 + 右上等宽百分比 + 6dp 进度轨。
///
/// 底部只解释「怎么算」：百分比已经在右上角出现一次，这里不再抄第二遍，
/// 但仍保留「成功日」「内化进度」两个词，读屏与检索都能对上语义。
class NationalFocusDetailRecordsCard extends StatelessWidget {
  const NationalFocusDetailRecordsCard({super.key, required this.card});

  final NationalFocusCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = card.internalizationProgress.clamp(0.0, 100.0);
    return Card(
      child: Padding(
        padding: PactaSpacing.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '记录',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: PactaFonts.medium,
                    ),
                  ),
                ),
                Text(
                  '${progress.toStringAsFixed(1)}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: PactaFonts.semibold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: PactaSpacing.md),
            NationalFocusInternalizationBar(card: card, height: 6),
            const SizedBox(height: PactaSpacing.sm),
            Wrap(
              spacing: PactaSpacing.md,
              runSpacing: PactaSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '累计成功日 ${card.successfulDays} 天',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '内化进度（按成功日累计计算）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 嵌在纯白卡片里的表单输入框：柔化填充 + 12dp 描边 + 主色聚焦。
///
/// 页面底色是浅蓝灰，输入框再直接用页面底会读成"卡片上开了个洞"；这里统一
/// 取 [ColorScheme.surfaceContainerLow] 作为凹陷底，边框只在未聚焦时用
/// [ColorScheme.outlineVariant] 轻轻收口。
InputDecoration pactaCardInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? helperText,
  bool alignLabelWithHint = false,
}) {
  final colors = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: colors.surfaceContainerLow,
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.primary, width: 1.5),
    ),
  );
}

/// 节点名称旁的连续点亮矢量胶囊：当前连续与历史最高连续。
///
/// 只用 [PactaIconSizes.micro] 图标 + 半粗数字，不占额外一行：放进调用方的
/// [Wrap] 后短名称与胶囊同排、长名称自动换行，窄屏也不会溢出。0 天用中性
/// 浅灰，点亮中的连续天数取点亮态容器色，历史最高取主色容器色。
///
/// [compact] 是给国策树详细卡片头部这类高密度位置的收敛档：内边距、图标与
/// 数字之间的缝隙、行高都压到最小可读尺度，历史最高不再用高饱和的主色容器
/// （暗色下它亮得像并排的第二颗按钮），改成与「已内化」同源的次色容器，只
/// 保留 55% 不透明度，读成内嵌元信息。默认 `false`，详情页、弹层等大尺寸
/// 位置的观感完全不变。
class NationalFocusStreakTags extends StatelessWidget {
  const NationalFocusStreakTags({
    super.key,
    required this.currentConsecutiveDays,
    required this.bestConsecutiveDays,
    this.compact = false,
  });

  final int currentConsecutiveDays;
  final int bestConsecutiveDays;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = PactaStatusColors.of(context);
    final currentActive = currentConsecutiveDays > 0;
    return Wrap(
      key: const ValueKey('national-focus-streak-tags'),
      spacing: compact ? 4 : 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StreakPill(
          key: const ValueKey('national-focus-streak-current'),
          icon: Icons.lightbulb_outline,
          label: '${currentConsecutiveDays}d',
          semanticsLabel: '当前连续点亮 $currentConsecutiveDays 天',
          background: currentActive
              ? status.successContainer
              : colors.surfaceContainerHighest,
          foreground: currentActive
              ? status.onSuccessContainer
              : colors.onSurfaceVariant,
          compact: compact,
        ),
        _StreakPill(
          key: const ValueKey('national-focus-streak-best'),
          icon: Icons.track_changes,
          label: '${bestConsecutiveDays}d',
          semanticsLabel: '历史最高连续点亮 $bestConsecutiveDays 天',
          // 紧凑档把历史最高降回次色容器：与「已内化」同源，但只留 55%
          // 不透明度，和点亮态 / 当前连续的色阶拉开层次，不再抢状态色。
          background: compact
              ? colors.secondaryContainer.withValues(alpha: 0.55)
              : colors.primaryContainer,
          foreground: compact
              ? colors.onSecondaryContainer
              : colors.onPrimaryContainer,
          compact: compact,
        ),
      ],
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.background,
    required this.foreground,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final Color background;
  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    // 字号仍取 labelSmall（语义字阶的最小一档），紧凑档只收行高与内边距：
    // 图标与字号再往下掉，180d 这类三位数就失去可读性，也会跌破 14dp 的
    // 图标语义尺度。
    final textStyle = style?.copyWith(
      color: foreground,
      fontWeight: PactaFonts.semibold,
      height: compact ? 1.25 : style.height,
    );
    return Tooltip(
      message: semanticsLabel,
      child: Semantics(
        label: semanticsLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(5, 1, 6, 1)
                : const EdgeInsets.fromLTRB(6, 1, 8, 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: PactaIconSizes.micro, color: foreground),
                SizedBox(width: compact ? 2 : 3),
                Text(label, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NationalFocusTreeMessage extends StatelessWidget {
  const NationalFocusTreeMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: PactaIconSizes.hero,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class NationalFocusInlineError extends StatelessWidget {
  const NationalFocusInlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}

class NationalFocusBranchConnectorPainter extends CustomPainter {
  const NationalFocusBranchConnectorPainter({
    required this.childWidths,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> childWidths;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final centers = <double>[];
    var offset = 0.0;
    for (final width in childWidths) {
      centers.add(offset + width / 2);
      offset += width;
    }
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, middle),
      paint,
    );
    canvas.drawLine(
      Offset(centers.first, middle),
      Offset(centers.last, middle),
      paint,
    );
    for (final center in centers) {
      canvas.drawLine(
        Offset(center, middle),
        Offset(center, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(NationalFocusBranchConnectorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      !listEquals(oldDelegate.childWidths, childWidths);
}
