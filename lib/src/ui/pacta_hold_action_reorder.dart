import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';

/// 操作面板中的一项。
class PactaActionItem {
  const PactaActionItem({
    required this.id,
    required this.label,
    this.icon,
    this.destructive = false,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onTap;
}

/// 跨端统一的操作面板：Material 3 底部弹层，危险操作固定排在最后。
Future<void> showPactaActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<PactaActionItem> actions,
}) {
  final ordered = [
    for (final action in actions)
      if (!action.destructive) action,
    for (final action in actions)
      if (action.destructive) action,
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final action in ordered)
                ListTile(
                  key: ValueKey('pacta-action-${action.id}'),
                  leading: action.icon == null
                      ? null
                      : Icon(
                          action.icon,
                          color: action.destructive ? colors.error : null,
                        ),
                  title: Text(
                    action.label,
                    style: action.destructive
                        ? TextStyle(color: colors.error)
                        : null,
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    action.onTap();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 长按/拖拽列表的共享状态：是否允许排序，以及本轮手势是否真的换位。
class PactaHoldReorderController extends ChangeNotifier {
  PactaHoldReorderController({this.enabled = true});

  /// 由列表读取；调用方改值后重建列表即生效。
  bool enabled;

  bool _reordered = false;
  bool get reorderedInGesture => _reordered;

  void beginGesture() {
    _reordered = false;
  }

  void markReordered() {
    _reordered = true;
  }
}

/// 跨端统一的「按住原地不动 = 操作菜单；按住上下移动 = 拖拽排序」列表。
///
/// 列表自身不滚动（`shrinkWrap` + `NeverScrollableScrollPhysics`），通常嵌在
/// 页面滚动视图里。排序由 [ReorderableListView] 承担；每一项外层的
/// [PactaHoldReorderListener] 在 350ms 后启动拖拽，同时记录指针位移：
/// 位移不超过 8dp 且没有实际换位时，抬起指针打开 [onHoldMenu]。
///
/// 拖拽代理只负责让卡片本体浮起：高亮描边与阴影画在 [itemSpacing] 内层，
/// 与卡片圆角严丝合缝；间距区域保持完全透明，不出现白色直角块。
class PactaHoldReorderList extends StatefulWidget {
  const PactaHoldReorderList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.onHoldMenu,
    this.enabled = true,
    this.controller,
    this.padding,
    this.itemExtent,
    this.itemSpacing = 0,
    this.proxyBorderRadius = PactaSpacing.cardRadius,
    this.holdDelay = const Duration(milliseconds: 350),
    this.moveThreshold = 8.0,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// 已按 Flutter `onReorderItem` 契约归一成 **post-removal** 下标：
  /// 可直接 `removeAt(oldIndex)` 后 `insert(newIndex, moved)`，无需再
  /// 对向下拖动做 `newIndex -= 1` 修正。`ReorderableListView` 的旧
  /// `onReorder` 才需要调用方自行修正。
  final ReorderCallback onReorder;
  final ValueChanged<int>? onHoldMenu;
  final bool enabled;
  final PactaHoldReorderController? controller;
  final EdgeInsets? padding;
  final double? itemExtent;

  /// 每项顶部附加的视觉间距；0 表示由调用方在卡片内部自行留白。
  ///
  /// 间距加在 [PactaHoldReorderListener] 外层，拖拽代理的高亮只包卡片本体。
  final double itemSpacing;

  /// 拖拽代理高亮描边与阴影的圆角，应等于卡片本身的圆角。
  final double proxyBorderRadius;

  final Duration holdDelay;
  final double moveThreshold;

  @override
  State<PactaHoldReorderList> createState() => _PactaHoldReorderListState();
}

class _PactaHoldReorderListState extends State<PactaHoldReorderList> {
  PactaHoldReorderController? _ownedController;

  PactaHoldReorderController get _controller =>
      widget.controller ?? (_ownedController ??= PactaHoldReorderController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canReorder =
        widget.enabled && widget.itemCount > 1 && _controller.enabled;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: widget.padding,
      itemCount: widget.itemCount,
      itemExtent: widget.itemExtent,
      proxyDecorator: _buildProxy,
      onReorderItem: (oldIndex, newIndex) {
        _controller.markReordered();
        widget.onReorder(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final child = widget.itemBuilder(context, index);
        // ReorderableListView 要求 itemBuilder 的直接返回值带 key。外层用
        // 包裹 key 保留条目身份，但值不等于 child 自身的 Key：否则同一个
        // 值会同时出现在父子两个节点，finder/语义树会把一项当成两项。
        final childKey = child.key;
        final itemKey = childKey == null || childKey is GlobalKey
            ? ValueKey<Object>('pacta-hold-item-$index')
            : _PactaHoldItemKey(childKey);
        Widget item = child;
        if (canReorder || widget.onHoldMenu != null) {
          // 手势宿主只包卡片本体，不包含 [itemSpacing]：拖拽代理的描边与
          // 阴影因此严格贴合卡片圆角，顶部间距区域保持完全透明。
          item = PactaHoldReorderListener(
            index: index,
            enabled: canReorder,
            controller: _controller,
            onHoldMenu: widget.onHoldMenu,
            holdDelay: widget.holdDelay,
            moveThreshold: widget.moveThreshold,
            child: child,
          );
        }
        if (widget.itemSpacing > 0) {
          // 间距统一加在每项顶部，调用方不必再在 Card 上写 margin；拖拽时
          // 这段间距留在高亮之外，不会形成白色直角阴影块。
          item = Padding(
            padding: EdgeInsets.only(top: widget.itemSpacing),
            child: item,
          );
        }
        return KeyedSubtree(key: itemKey, child: item);
      },
    );
  }

  /// 透明外包：清掉框架默认的白底与动态投影，只向下传递拖拽动画。
  ///
  /// 真正的高亮由 [PactaHoldReorderListener] 在卡片本体内绘制；这里保留
  /// 列表元素本身（Flutter 用 GlobalKey 复用元素），展开/折叠等 State 不会
  /// 在拖拽期间被重建。
  Widget _buildProxy(Widget child, int index, Animation<double> animation) {
    return _PactaReorderProxyScope(
      animation: animation,
      borderRadius: widget.proxyBorderRadius,
      child: Material(
        key: const ValueKey('pacta-hold-reorder-proxy-surface'),
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}

/// 单项手势宿主：350ms 延迟拖拽 + 原地长按分流。
class PactaHoldReorderListener extends StatefulWidget {
  const PactaHoldReorderListener({
    super.key,
    required this.index,
    required this.child,
    this.enabled = false,
    this.onHoldMenu,
    this.controller,
    this.holdDelay = const Duration(milliseconds: 350),
    this.moveThreshold = 8.0,
  });

  final int index;
  final Widget child;
  final bool enabled;
  final ValueChanged<int>? onHoldMenu;
  final PactaHoldReorderController? controller;
  final Duration holdDelay;
  final double moveThreshold;

  @override
  State<PactaHoldReorderListener> createState() =>
      _PactaHoldReorderListenerState();
}

class _PactaHoldReorderListenerState extends State<PactaHoldReorderListener> {
  /// 一次指针手势只归最内层可交互的列表项所有。
  ///
  /// 嵌套列表时，内层任务与外层目标都会在命中路径上收到同一个
  /// `PointerDownEvent`；内层先认领后，外层不再启动定时器或
  /// `startItemDragReorder`，避免抬起时同时弹两层菜单。指针 ID 在
  /// up/cancel/dispose 时释放，不复用、不泄漏。
  static final Set<int> _claimedPointers = <int>{};

  /// 拖拽时代理会在 listener 外包一层 Material；卡片内容用 GlobalKey 在
  /// 同一帧内跨位置复用元素，展开/折叠等 State 不会被重建。
  final GlobalKey _childHostKey = GlobalKey();

  int? _pointer;
  Offset? _start;
  double _maxDistance = 0;
  Timer? _holdTimer;
  bool _holdReached = false;
  bool _menuScheduled = false;

  bool get _moved => _maxDistance > widget.moveThreshold;

  /// 不可排序但要在长按时弹菜单：此时必须把手势放进 [GestureArena]。
  ///
  /// 只靠 [Timer] 打开底部菜单不会拒绝子组件的 TapGestureRecognizer；
  /// 用户按住 350ms 弹出菜单后一抬手，ListTile.onTap / InkWell.onTap 仍会
  /// 赢下手势竞技场，在菜单之上再弹一层「编辑任务」等对话框。
  bool get _holdMenuHandledByArena =>
      !widget.enabled && widget.onHoldMenu != null;

  void _onPointerDown(PointerDownEvent event) {
    if (widget.onHoldMenu == null && !widget.enabled) return;
    if (event.buttons != 0 && (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    // 同一次按住的第二根手指不覆盖当前手势，避免丢失已认领的指针。
    if (_pointer != null) return;
    // add 同时完成「检查 + 认领」：内层先收到事件并认领，外层直接退出。
    if (!_claimedPointers.add(event.pointer)) return;
    _holdTimer?.cancel();
    _pointer = event.pointer;
    _start = event.position;
    _maxDistance = 0;
    _holdReached = false;
    _menuScheduled = false;
    widget.controller?.beginGesture();
    if (widget.enabled) {
      // 排序路径：拖拽识别器会赢得竞技场，这里只记录「按住已满时长」。
      _holdTimer = Timer(widget.holdDelay, _onHoldElapsed);
      final list = SliverReorderableList.maybeOf(context);
      list?.startItemDragReorder(
        index: widget.index,
        event: event,
        recognizer: DelayedMultiDragGestureRecognizer(
          delay: widget.holdDelay,
          debugOwner: this,
        ),
      );
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    if (start == null) return;
    final distance = (event.position - start).distance;
    if (distance > _maxDistance) _maxDistance = distance;
  }

  void _onHoldElapsed() {
    // 仅排序路径使用：抬手且没有位移、没有换位时由 [_onPointerUp] 打开菜单。
    _holdReached = true;
  }

  /// [LongPressGestureRecognizer] 在 holdDelay 后赢得竞技场时调用。
  ///
  /// 它同时向子组件的 TapGestureRecognizer 发出
  /// [GestureDisposition.rejected]，因此抬手不会再触发 onTap；短点
  /// （小于 holdDelay）和快速拖动（超过 touchSlop）由识别器自行放弃，
  /// 菜单不会打开。
  void _onLongPressStart(LongPressStartDetails details) {
    // 双保险：识别器只在 _pointer 匹配时才登记进竞技场；这里再挡一次
    // 指针未认领/已释放与位移超阈值的情况。
    if (_pointer == null || _moved) return;
    _showMenu();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _holdTimer?.cancel();
    _claimedPointers.remove(event.pointer);
    final shouldOpen =
        _holdReached &&
        !_moved &&
        !(widget.controller?.reorderedInGesture ?? false) &&
        widget.onHoldMenu != null;
    _pointer = null;
    _start = null;
    if (shouldOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showMenu();
      });
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _holdTimer?.cancel();
    _claimedPointers.remove(event.pointer);
    _pointer = null;
    _start = null;
  }

  void _showMenu() {
    if (_menuScheduled || !mounted) return;
    _menuScheduled = true;
    widget.onHoldMenu?.call(widget.index);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    final pointer = _pointer;
    if (pointer != null) _claimedPointers.remove(pointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listener = Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: KeyedSubtree(key: _childHostKey, child: widget.child),
    );
    final Widget content;
    if (!_holdMenuHandledByArena) {
      content = listener;
    } else {
      // RawGestureDetector 包在 Listener 外层：命中路径由内向外派发，本节点
      // 的 Listener._onPointerDown 先完成 _claimedPointers 认领，内层列表项
      // 的 Listener 又先于本节点执行。识别器再以 _pointer 作为准入条件，被
      // 内层认领的指针根本不会登记进本节点的 GestureArena——内层中途卸载、
      // holdDelay 更长或未挂在 SliverReorderableList 下时，外层都不会在超时
      // 后误弹操作菜单。
      content = RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          _ClaimedPointerLongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _ClaimedPointerLongPressGestureRecognizer
              >(
                () => _ClaimedPointerLongPressGestureRecognizer(
                  duration: widget.holdDelay,
                  debugOwner: this,
                  // 与 _onPointerDown 的主键判定一致：右键/中键长按不打开菜单。
                  allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
                  onPointerAllowed: (pointer) => _pointer == pointer,
                ),
                (recognizer) {
                  // supportedDevices 默认 null：touch / mouse / stylus 等全部
                  // 设备都参与，与排序路径的拖拽识别器一致。
                  recognizer.onLongPressStart = _onLongPressStart;
                },
              ),
        },
        child: listener,
      );
    }
    final proxy = _PactaReorderProxyScope.maybeOf(context);
    if (proxy == null) return content;
    // 只有拖拽代理子树能读到这个作用域：浮起阴影与高亮描边加在卡片本体，
    // 外层的 itemSpacing 仍由透明 Material 承载，绝不会被边框一起包住。
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: proxy.animation,
      builder: (context, child) {
        final curve = Curves.easeInOut.transform(proxy.animation.value);
        return Material(
          key: const ValueKey('pacta-hold-reorder-proxy-highlight'),
          color: Colors.transparent,
          elevation: lerpDouble(0, 6, curve)!,
          shadowColor: colors.shadow.withValues(alpha: 0.25),
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(proxy.borderRadius),
            side: BorderSide(
              color: colors.primary.withValues(alpha: 0.45 * curve),
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
      child: content,
    );
  }
}

/// 列表项外层 Key：按 child 的 Key 保持稳定身份，但不与 child 同名。
@immutable
class _PactaHoldItemKey extends Key {
  const _PactaHoldItemKey(this.itemKey) : super.empty();

  final Key itemKey;

  @override
  bool operator ==(Object other) =>
      other is _PactaHoldItemKey && other.itemKey == itemKey;

  @override
  int get hashCode => itemKey.hashCode;
}

/// 只在拖拽代理子树中出现的动画作用域。
///
/// [PactaHoldReorderList] 的 proxyDecorator 只把框架默认的白底和投影换成
/// 透明表面，并把拖拽动画从这里向下传递；高亮由卡片本体的
/// [PactaHoldReorderListener] 绘制，所以描边与卡片圆角严丝合缝。
class _PactaReorderProxyScope extends InheritedWidget {
  const _PactaReorderProxyScope({
    required this.animation,
    required this.borderRadius,
    required super.child,
  });

  /// 框架的拖拽动画（0 → 1，250ms）。
  final Animation<double> animation;

  /// 高亮描边与阴影的圆角。
  final double borderRadius;

  static _PactaReorderProxyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PactaReorderProxyScope>();

  @override
  bool updateShouldNotify(_PactaReorderProxyScope oldWidget) =>
      animation != oldWidget.animation ||
      borderRadius != oldWidget.borderRadius;
}

/// 只在指针已被本节点 Listener 认领时才进入 GestureArena 的长按识别器。
///
/// 外层监听器在内层已认领指针时 _pointer 为空，此时若仍把识别器登记进
/// 竞技场，一旦内层在按住期间卸载（如 stream 重建替换子树），外层会在
/// LongPressGestureRecognizer 的 deadline 赢得竞技场并误弹菜单。
class _ClaimedPointerLongPressGestureRecognizer
    extends LongPressGestureRecognizer {
  _ClaimedPointerLongPressGestureRecognizer({
    required this.onPointerAllowed,
    super.duration,
    super.debugOwner,
    super.allowedButtonsFilter,
  });

  /// 指针准入判定：必须由本节点认领（_pointer == event.pointer）。
  final bool Function(int pointer) onPointerAllowed;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && onPointerAllowed(event.pointer);
}
