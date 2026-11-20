import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'national_focus_repository.dart';
import 'national_focus_strengthening_page.dart';

void syncNationalFocusInBackground(NationalFocusRepository repository) {
  unawaited(repository.sync().catchError((Object _) {}));
}

Future<void> pushStrengtheningManager({
  required BuildContext context,
  required NationalFocusRepository repository,
  required String cardId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) =>
        NationalFocusStrengtheningPage(repository: repository, cardId: cardId),
  ),
);

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
                    icon: const Icon(Icons.fit_screen),
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

class NationalFocusReviewNotice extends StatelessWidget {
  const NationalFocusReviewNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.sync_problem, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '同步操作存在分歧，状态和统计待核对；核对前暂不能修改这张卡。',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
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
