/// 横向分页的统一桌面交互原语：吸附物理、滚轮/快捷键切页与页内滚轮捕获。
///
/// 五个分页视图（专注历史、选择任务、计划、国策卡片库、看板窄屏顶槽）共用
/// 这一层，避免每处各写一套滚轮与快捷键门槛，桌面与触控板行为因此始终一致。
///
/// 约定：使用 [PactaPageScrollPhysics] 的 PageView 必须同时传
/// `pageSnapping: false`，否则 Flutter 的 PageView 会再包一层默认
/// [PageScrollPhysics]，慢拖仍按 50% 视口门槛回弹。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 分页吸附物理：宽视口下慢拖也能可靠翻页，轻触回弹原页。
///
/// Flutter 自带的 [PageScrollPhysics] 以半个视口为慢拖门槛：1280dp 桌面必须
/// 拖过 640dp 才翻页，鼠标几乎永远拖不到。这里把门槛改为
/// `min(半视口, [maxDragSnapDistance])`，并用拖动方向决定落点，保证对齐
/// 页码时不会因为浮点误差向后跳页。
class PactaPageScrollPhysics extends ScrollPhysics {
  const PactaPageScrollPhysics({
    super.parent,
    this.maxDragSnapDistance = 120.0,
  });

  /// 慢拖翻页所需的位移上限（dp）：视口再宽也不必拖过半屏。
  final double maxDragSnapDistance;

  @override
  PactaPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PactaPageScrollPhysics(
      parent: buildParent(ancestor),
      maxDragSnapDistance: maxDragSnapDistance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // 越界且正往外拖：交给父物理把位置收回边界，不在边界外算页。
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double viewport = position.viewportDimension;
    if (viewport <= 0) return null;
    final double page = position is PageMetrics && position.page != null
        ? position.page!
        : position.pixels / viewport;
    final double targetPage;
    if (velocity < -tolerance.velocity) {
      // 向左飞划：至少前进一页。
      targetPage = (page - 0.5).roundToDouble();
    } else if (velocity > tolerance.velocity) {
      // 向右飞划：至少回退一页。
      targetPage = (page + 0.5).roundToDouble();
    } else {
      // 慢拖松手：按已拖出的比例与拖动方向决定吸附到哪一页。
      final double floor = page.floorToDouble();
      final double fraction = page - floor;
      if (fraction == 0.0) {
        // 页面对齐：绝不允许因取整把用户推去下一页。
        targetPage = floor;
      } else {
        final double thresholdFraction =
            math.min(viewport * 0.5, maxDragSnapDistance) / viewport;
        final ScrollDirection direction = position is ScrollPosition
            ? position.userScrollDirection
            : ScrollDirection.idle;
        if (direction == ScrollDirection.reverse) {
          // 左拖向下一页。
          targetPage = fraction >= thresholdFraction ? floor + 1.0 : floor;
        } else if (direction == ScrollDirection.forward) {
          // 右拖向上一页：剩余距离够门槛才回去，否则退回对齐的下一页。
          targetPage = (1.0 - fraction) >= thresholdFraction
              ? floor
              : floor + 1.0;
        } else {
          targetPage = page.roundToDouble();
        }
      }
    }
    final double targetPixels = (targetPage * viewport)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((targetPixels - position.pixels).abs() > tolerance.distance) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        targetPixels,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}

/// 分页作用域：把「当前页 + 切页回调」变成滚轮与键盘快捷键的统一入口。
///
/// 只在自己可见（[Visibility.of] 覆盖 [IndexedStack] 的隐藏页）且所在路由在最
/// 顶层时响应，对话框、二级页与输入框因此都不会误翻底层页。滚轮累计与冷却
/// 只用 [Timer]，测试里的假时钟可以直接推进。
class PactaHorizontalPagerScope extends StatefulWidget {
  const PactaHorizontalPagerScope({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.onStepPage,
    required this.child,
    this.enabled = true,
    this.enableKeyboardShortcuts = true,
    this.enablePointerScroll = true,
  });

  /// 总页数；小于 2 时整层退化为纯容器。
  final int pageCount;

  /// 当前页下标，用于边界判断与快捷键落点计算。
  final int currentPage;

  /// 切页回调：只会收到 `+1` 或 `-1`。
  final ValueChanged<int> onStepPage;

  /// 分页内容；作用域只负责输入，不改变布局。
  final Widget child;

  /// 关掉后滚轮与快捷键都不再响应（看板顶槽只在有切换胶囊时打开）。
  final bool enabled;

  /// 是否接受 ←/→ 与 Ctrl+Tab；默认开启，逐页视图可按需关闭。
  final bool enableKeyboardShortcuts;

  /// 是否接受 Shift+滚轮与原生横向滚轮；默认开启。
  final bool enablePointerScroll;

  @override
  State<PactaHorizontalPagerScope> createState() =>
      _PactaHorizontalPagerScopeState();
}

class _PactaHorizontalPagerScopeState extends State<PactaHorizontalPagerScope> {
  /// 滚轮一次翻页至少累计的位移（dp）：单格标准滚轮约 100dp，
  /// 细腻的横向滚轮累计到 24dp 也能稳定触发，不会卡在两格之间。
  static const double _wheelStepThreshold = 24.0;

  /// 滚轮累计的静默窗口：停手 200ms 后重新计。
  static const Duration _wheelResetDelay = Duration(milliseconds: 200);

  /// 翻页后的冷却：一次滚轮爆发只翻一页。
  static const Duration _wheelCooldownDuration = Duration(milliseconds: 280);

  bool _isVisible = true;
  bool _isCurrentRoute = true;

  double _wheelAccumulator = 0;
  int _wheelDirection = 0;
  bool _wheelCooldown = false;
  Timer? _wheelResetTimer;
  Timer? _wheelCooldownTimer;

  /// 只有可见、路由在最顶层、页数足够且被显式启用时才接管输入。
  bool get _isActive =>
      mounted &&
      widget.enabled &&
      widget.pageCount > 1 &&
      _isVisible &&
      _isCurrentRoute;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅只在依赖变化时发生：键盘回调里读 Visibility/ModalRoute 会在
    // 事件分发期间触发断言，也会让隐藏页继续吃键。
    _isVisible = Visibility.of(context);
    _isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _wheelResetTimer?.cancel();
    _wheelCooldownTimer?.cancel();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isActive || !widget.enableKeyboardShortcuts) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // 正在输入文字或拖动滑杆时，方向键属于控件本身。
    if (_focusIsTextEntry()) return false;
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab &&
        keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      // Ctrl+Tab 在边界也要吃掉：否则焦点会跳出当前分页作用域。
      return _stepBy(keyboard.isShiftPressed ? -1 : 1, boundaryConsumes: true);
    }
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return _stepBy(-1, boundaryConsumes: false);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return _stepBy(1, boundaryConsumes: false);
    }
    return false;
  }

  bool _stepBy(int step, {required bool boundaryConsumes}) {
    final int next = (widget.currentPage + step).clamp(0, widget.pageCount - 1);
    if (next == widget.currentPage) return boundaryConsumes;
    widget.onStepPage(step);
    return true;
  }

  /// 焦点是否落在文本输入或滑杆上：这两类控件把方向键当作自己的输入。
  bool _focusIsTextEntry() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final Element? element = focusContext is Element ? focusContext : null;
    if (element == null) return false;
    if (_isTextEntryWidget(element.widget)) return true;
    var found = false;
    element.visitAncestorElements((Element ancestor) {
      if (_isTextEntryWidget(ancestor.widget)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  static bool _isTextEntryWidget(Widget widget) =>
      widget is EditableText || widget is Slider;

  /// 滚轮与 Shift+滚轮：只认明确的横向意图，绝不抢占普通垂直滚动。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isActive || !widget.enablePointerScroll) return;
    if (event is! PointerScrollEvent) return;
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    // Ctrl/Alt/Meta + 滚轮属于缩放与系统手势，一律放过。
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return;
    }
    final double rawDelta = _horizontalDelta(event, keyboard.isShiftPressed);
    if (rawDelta == 0.0) return;
    final int step = rawDelta > 0 ? 1 : -1;
    final int probe = widget.currentPage + step;
    final bool canStep = probe >= 0 && probe < widget.pageCount;
    // 边界外仍要吃掉冷却期内的信号，避免 Flutter 自带 Scrollable 微移弹回。
    if (!canStep && !_wheelCooldown) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      _resolveWheel(resolved, rawDelta, step);
    });
  }

  double _horizontalDelta(PointerScrollEvent event, bool shiftPressed) {
    double rawDelta;
    if (shiftPressed && event.kind == PointerDeviceKind.mouse) {
      // 鼠标滚轮只有纵向一格：Shift 把它读成横向意图。
      rawDelta = event.scrollDelta.dy != 0
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
    } else if (event.scrollDelta.dx != 0 &&
        event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() * 1.5) {
      // 原生横向滚轮/横摇滚轮：只在横向明显占优时接管。
      rawDelta = event.scrollDelta.dx;
    } else {
      return 0.0;
    }
    if (Directionality.maybeOf(context) == TextDirection.rtl) {
      rawDelta = -rawDelta;
    }
    return rawDelta;
  }

  void _resolveWheel(PointerSignalEvent resolved, double rawDelta, int step) {
    if (resolved is! PointerScrollEvent) return;
    if (_wheelCooldown) {
      _wheelAccumulator = 0;
      resolved.respond(allowPlatformDefault: false);
      return;
    }
    if (_wheelDirection != 0 && _wheelDirection != step) {
      // 反向滚动重新计：换方向的半格不能被上一方向吃掉。
      _wheelAccumulator = 0;
    }
    _wheelDirection = step;
    _wheelAccumulator += rawDelta;
    _wheelResetTimer?.cancel();
    _wheelResetTimer = Timer(_wheelResetDelay, () => _wheelAccumulator = 0);
    if (_wheelAccumulator.abs() >= _wheelStepThreshold) {
      final int resolvedStep = _wheelAccumulator > 0 ? 1 : -1;
      _wheelAccumulator = 0;
      _wheelResetTimer?.cancel();
      _wheelResetTimer = null;
      _wheelCooldown = true;
      _wheelCooldownTimer?.cancel();
      _wheelCooldownTimer = Timer(
        _wheelCooldownDuration,
        () => _wheelCooldown = false,
      );
      final int next = widget.currentPage + resolvedStep;
      if (next >= 0 && next < widget.pageCount) {
        widget.onStepPage(resolvedStep);
      }
    }
    resolved.respond(allowPlatformDefault: false);
  }

  @override
  Widget build(BuildContext context) {
    return _PactaPagerWheelScope(
      handlePointerSignal: _handlePointerSignal,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handlePointerSignal,
        child: widget.child,
      ),
    );
  }
}

/// 页内滚轮捕获：放在每个 PageView 子页最外层。
///
/// 它比 PageView 自己的 [Scrollable] 更深，命中测试时先向
/// [GestureBinding.pointerSignalResolver] 注册，横向与 Shift+滚轮因此优先
/// 交给分页作用域，不会被 Scrollable 截胡后再弹回。
class PactaPagerWheelCatcher extends StatelessWidget {
  const PactaPagerWheelCatcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _PactaPagerWheelScope? scope = _PactaPagerWheelScope.maybeOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: scope?.handlePointerSignal,
      child: child,
    );
  }
}

/// 把作用域的滚轮处理下发给 [PactaPagerWheelCatcher]。
class _PactaPagerWheelScope extends InheritedWidget {
  const _PactaPagerWheelScope({
    required this.handlePointerSignal,
    required super.child,
  });

  final void Function(PointerSignalEvent event) handlePointerSignal;

  static _PactaPagerWheelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PactaPagerWheelScope>();

  @override
  bool updateShouldNotify(_PactaPagerWheelScope oldWidget) => true;
}
