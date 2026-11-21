import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_hold_action_reorder.dart';

void main() {
  test('PactaScrollBehavior 把鼠标、触控笔与触控板列为拖动设备', () {
    const behavior = PactaScrollBehavior();
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.stylus));
    expect(behavior.dragDevices, contains(PointerDeviceKind.invertedStylus));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
  });

  testWidgets('桌面端鼠标左键按住可拖动列表滚动', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const PactaScrollBehavior(),
        home: ListView(
          controller: controller,
          children: [
            for (var index = 0; index < 40; index++)
              SizedBox(height: 48, child: Text('row $index')),
          ],
        ),
      ),
    );
    expect(controller.offset, 0);
    await tester.drag(
      find.byType(ListView),
      const Offset(0, -320),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('${kind.name} 长按原地不动打开操作面板', (tester) async {
      final menuCalls = <int>[];
      await tester.pumpWidget(_Harness(onMenu: menuCalls.add));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('A')),
        kind: kind,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(menuCalls, [0]);
      expect(find.text('操作 A'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });
  }

  testWidgets('长按后拖动超过 8dp 触发排序且不弹操作菜单', (tester) async {
    final menuCalls = <int>[];
    final reorders = <(int, int)>[];
    await tester.pumpWidget(
      _Harness(onMenu: menuCalls.add, onReorder: reorders.add),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 400));
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorders, isNotEmpty);
    expect(menuCalls, isEmpty);
    expect(find.text('操作 A'), findsNothing);
  });

  testWidgets('三项列表向下拖动：onReorder 给出 post-removal 下标', (tester) async {
    final menuCalls = <int>[];
    final reorders = <(int, int)>[];
    await tester.pumpWidget(
      _Harness(
        initialItems: const ['A', 'B', 'C'],
        onMenu: menuCalls.add,
        onReorder: reorders.add,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 400));
    // 约两行（120dp）：A 越过 C。旧 onReorder 会给出 (0, 3)，这里必须是
    // 已扣除移除项的 (0, 2)，上层才能直接 removeAt/insert。
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorders.last, (0, 2));
    expect(find.text('order=B,C,A'), findsOneWidget);
    expect(menuCalls, isEmpty);
  });

  testWidgets('三项列表向上拖动：onReorder 给出 post-removal 下标', (tester) async {
    final menuCalls = <int>[];
    final reorders = <(int, int)>[];
    await tester.pumpWidget(
      _Harness(
        initialItems: const ['A', 'B', 'C'],
        onMenu: menuCalls.add,
        onReorder: reorders.add,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('C')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 400));
    // 向上越过 A：oldIndex 2 先移除，再插入到 0。
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorders.last, (2, 0));
    expect(find.text('order=C,A,B'), findsOneWidget);
    expect(menuCalls, isEmpty);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('${kind.name} 嵌套列表：按住内层任务只弹内层菜单', (tester) async {
      final menuCalls = <String>[];
      await tester.pumpWidget(_NestedHarness(onMenu: menuCalls.add));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('任务 A')),
        kind: kind,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(menuCalls, ['inner-0']);
      expect(find.text('内层菜单0'), findsOneWidget);
      expect(find.text('外层菜单'), findsNothing);
    });
  }

  testWidgets('嵌套列表：按住外层标题只弹外层菜单', (tester) async {
    final menuCalls = <String>[];
    await tester.pumpWidget(_NestedHarness(onMenu: menuCalls.add));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('外层标题')),
      kind: PointerDeviceKind.touch,
      buttons: kPrimaryButton,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(menuCalls, ['outer']);
    expect(find.text('外层菜单'), findsOneWidget);
    expect(find.textContaining('内层菜单'), findsNothing);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('${kind.name} 单项列表短按抬起只触发子组件 onTap', (tester) async {
      final menuCalls = <int>[];
      final taps = <String>[];
      await tester.pumpWidget(
        _SingleItemHarness(onMenu: menuCalls.add, onTap: () => taps.add('tap')),
      );
      await tester.tap(find.text('单行'), kind: kind, buttons: kPrimaryButton);
      await tester.pumpAndSettle();
      expect(taps, ['tap']);
      expect(menuCalls, isEmpty);
      expect(find.text('单行菜单'), findsNothing);
    });

    testWidgets('${kind.name} 单项列表长按只回调菜单时不触发子组件 onTap', (tester) async {
      final menuCalls = <int>[];
      final taps = <String>[];
      await tester.pumpWidget(
        _SingleItemHarness(
          onMenu: menuCalls.add,
          onTap: () => taps.add('tap'),
          openSheet: false,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('单行')),
        kind: kind,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(menuCalls, [0]);
      expect(taps, isEmpty);
    });

    testWidgets('${kind.name} 单项列表长按 400ms 抬起只弹菜单且不触发 onTap', (tester) async {
      final menuCalls = <int>[];
      final taps = <String>[];
      await tester.pumpWidget(
        _SingleItemHarness(onMenu: menuCalls.add, onTap: () => taps.add('tap')),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('单行')),
        kind: kind,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(menuCalls, [0]);
      expect(taps, isEmpty);
      expect(find.text('单行菜单'), findsOneWidget);
      expect(find.text('编辑任务'), findsOneWidget);
    });

    testWidgets('${kind.name} 嵌套列表内层单项长按抬手只弹内层菜单', (tester) async {
      final menuCalls = <String>[];
      final taps = <String>[];
      await tester.pumpWidget(
        _NestedSingleHarness(
          onMenu: menuCalls.add,
          onInnerTap: () => taps.add('tap'),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('唯一任务')),
        kind: kind,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(menuCalls, ['inner-0']);
      expect(taps, isEmpty);
      expect(find.text('内层单项菜单'), findsOneWidget);
      expect(find.text('外层菜单'), findsNothing);
    });
  }

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('${kind.name} 外层禁用监听器：内层按住 150ms 卸载后不误弹外层菜单', (tester) async {
      final menuCalls = <String>[];
      final taps = <String>[];
      final harnessKey = GlobalKey<_UnmountDuringHoldHarnessState>();
      await tester.pumpWidget(
        _UnmountDuringHoldHarness(
          key: harnessKey,
          onMenu: menuCalls.add,
          onInnerTap: () => taps.add('tap'),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('任务 X')),
        kind: kind,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 150));
      // 模拟 stream 重建：按住期间内层子树整体卸载。
      harnessKey.currentState!.removeInner();
      await tester.pump();
      expect(find.text('任务 X'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(menuCalls, isEmpty);
      expect(taps, isEmpty);
      expect(find.text('外层菜单'), findsNothing);
      expect(find.text('内层单项菜单'), findsNothing);
    });
  }

  testWidgets('itemSpacing：拖拽代理透明外包，高亮描边只包卡片本体', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PactaHoldReorderList(
            itemCount: 3,
            itemSpacing: 12,
            proxyBorderRadius: 24,
            onReorder: (_, _) {},
            itemBuilder: (context, index) => SizedBox(
              key: ValueKey('spacing-item-$index'),
              height: 96,
              child: Card(child: Center(child: Text('卡片 $index'))),
            ),
          ),
        ),
      ),
    );
    final firstItem = find.byKey(const ValueKey('spacing-item-0'));
    expect(tester.getSize(firstItem).height, 96);
    expect(find.byType(Card), findsNWidgets(3));

    final gesture = await tester.startGesture(
      tester.getCenter(firstItem),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 100));

    final surface = find.byKey(
      const ValueKey('pacta-hold-reorder-proxy-surface'),
    );
    expect(surface, findsOneWidget);
    // 外层 Material 完全透明：itemSpacing 区域没有白底、没有直角阴影块。
    expect(tester.widget<Material>(surface).type, MaterialType.transparency);
    expect(tester.getSize(surface).height, 108);

    final highlight = find.byKey(
      const ValueKey('pacta-hold-reorder-proxy-highlight'),
    );
    expect(highlight, findsOneWidget);
    final highlightMaterial = tester.widget<Material>(highlight);
    expect(highlightMaterial.color, Colors.transparent);
    expect(highlightMaterial.elevation, greaterThan(0));
    final shape = highlightMaterial.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(24));
    expect(shape.side.width, 1.5);
    expect(shape.side.color.a, greaterThan(0));
    // 高亮与卡片本体等大，并整体下移 itemSpacing：间距不在边框内。
    expect(tester.getSize(highlight).height, 96);
    expect(tester.getTopLeft(highlight).dy - tester.getTopLeft(surface).dy, 12);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(highlight, findsNothing);
  });

  testWidgets('拖拽代理复用卡片 State：折叠态不丢失', (tester) async {
    _CollapsibleCardState.created = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PactaHoldReorderList(
            itemCount: 2,
            itemSpacing: 8,
            onReorder: (_, _) {},
            itemBuilder: (context, index) => index == 0
                ? const _CollapsibleCard()
                : const SizedBox(
                    key: ValueKey('second-item'),
                    height: 80,
                    child: Center(child: Text('第二项')),
                  ),
          ),
        ),
      ),
    );
    expect(find.text('展开'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('collapsible-toggle')));
    await tester.pump();
    expect(find.text('已收起'), findsOneWidget);
    expect(find.text('展开'), findsNothing);
    expect(_CollapsibleCardState.created, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('已收起')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump(const Duration(milliseconds: 100));
    // 代理仍复用同一个元素，内部折叠状态不会被重置成默认展开。
    expect(_CollapsibleCardState.created, 1);
    expect(find.text('已收起'), findsOneWidget);
    expect(find.text('展开'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_CollapsibleCardState.created, 1);
    expect(find.text('已收起'), findsOneWidget);
  });
}

/// 用于验证拖拽代理复用元素：静态计数只在真正创建 State 时递增。
class _CollapsibleCard extends StatefulWidget {
  const _CollapsibleCard();

  @override
  State<_CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<_CollapsibleCard> {
  static int created = 0;

  var _expanded = true;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Column(
      children: [
        Expanded(child: Center(child: Text(_expanded ? '展开' : '已收起'))),
        TextButton(
          key: const ValueKey('collapsible-toggle'),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: const Text('切换'),
        ),
      ],
    ),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.onMenu,
    this.onReorder,
    this.initialItems = const ['A', 'B'],
  });

  final ValueChanged<int> onMenu;
  final ValueChanged<(int, int)>? onReorder;
  final List<String> initialItems;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final List<String> _items = [...widget.initialItems];

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            Text('order=${_items.join(',')}'),
            PactaHoldReorderList(
              itemCount: _items.length,
              itemExtent: 56,
              onHoldMenu: (index) {
                widget.onMenu(index);
                showPactaActionSheet(
                  context,
                  title: '操作 ${_items[index]}',
                  actions: [
                    PactaActionItem(id: 'edit', label: '编辑', onTap: () {}),
                    PactaActionItem(
                      id: 'delete',
                      label: '删除',
                      destructive: true,
                      onTap: () {},
                    ),
                  ],
                );
              },
              onReorder: (oldIndex, newIndex) {
                widget.onReorder?.call((oldIndex, newIndex));
                setState(() {
                  final moved = _items.removeAt(oldIndex);
                  _items.insert(newIndex, moved);
                });
              },
              itemBuilder: (context, index) => SizedBox(
                key: ValueKey(_items[index]),
                height: 56,
                child: Center(child: Text(_items[index])),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NestedHarness extends StatelessWidget {
  const _NestedHarness({required this.onMenu});

  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => PactaHoldReorderList(
          itemCount: 1,
          itemExtent: 180,
          onHoldMenu: (_) {
            onMenu('outer');
            showPactaActionSheet(
              context,
              title: '外层菜单',
              actions: [
                PactaActionItem(id: 'outer-edit', label: '编辑目标', onTap: () {}),
              ],
            );
          },
          onReorder: (_, _) {},
          itemBuilder: (context, index) => Column(
            key: const ValueKey('outer-item'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56, child: Center(child: Text('外层标题'))),
              PactaHoldReorderList(
                key: const ValueKey('inner-list'),
                itemCount: 2,
                itemExtent: 56,
                onHoldMenu: (innerIndex) {
                  onMenu('inner-$innerIndex');
                  showPactaActionSheet(
                    context,
                    title: '内层菜单$innerIndex',
                    actions: [
                      PactaActionItem(
                        id: 'inner-edit-$innerIndex',
                        label: '编辑任务',
                        onTap: () {},
                      ),
                    ],
                  );
                },
                onReorder: (_, _) {},
                itemBuilder: (context, innerIndex) => SizedBox(
                  key: ValueKey('inner-$innerIndex'),
                  height: 56,
                  child: Center(child: Text(innerIndex == 0 ? '任务 A' : '任务 B')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SingleItemHarness extends StatelessWidget {
  const _SingleItemHarness({
    required this.onMenu,
    required this.onTap,
    this.openSheet = true,
  });

  final ValueChanged<int> onMenu;
  final VoidCallback onTap;

  /// false 时不推入底部弹层，只记录回调：用于证明长按抬手后子组件点按
  /// 是被手势竞技场拒绝，而不是靠路由推入时的指针取消副作用。
  final bool openSheet;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => PactaHoldReorderList(
          itemCount: 1,
          itemExtent: 64,
          onHoldMenu: (index) {
            onMenu(index);
            if (!openSheet) return;
            showPactaActionSheet(
              context,
              title: '单行菜单',
              actions: [
                PactaActionItem(id: 'single-edit', label: '编辑任务', onTap: () {}),
              ],
            );
          },
          onReorder: (_, _) {},
          itemBuilder: (context, index) => SizedBox(
            key: const ValueKey('single-item'),
            height: 64,
            child: InkWell(
              key: const ValueKey('single-item-tap'),
              onTap: onTap,
              child: const Center(child: Text('单行')),
            ),
          ),
        ),
      ),
    ),
  );
}

class _NestedSingleHarness extends StatelessWidget {
  const _NestedSingleHarness({required this.onMenu, required this.onInnerTap});

  final ValueChanged<String> onMenu;
  final VoidCallback onInnerTap;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => PactaHoldReorderList(
          itemCount: 1,
          itemExtent: 180,
          onHoldMenu: (_) {
            onMenu('outer');
            showPactaActionSheet(
              context,
              title: '外层菜单',
              actions: [
                PactaActionItem(id: 'outer-edit', label: '编辑目标', onTap: () {}),
              ],
            );
          },
          onReorder: (_, _) {},
          itemBuilder: (context, index) => Column(
            key: const ValueKey('outer-single-item'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56, child: Center(child: Text('外层标题'))),
              PactaHoldReorderList(
                key: const ValueKey('inner-single-list'),
                itemCount: 1,
                itemExtent: 56,
                onHoldMenu: (innerIndex) {
                  onMenu('inner-$innerIndex');
                  showPactaActionSheet(
                    context,
                    title: '内层单项菜单',
                    actions: [
                      PactaActionItem(
                        id: 'inner-single-edit',
                        label: '编辑任务',
                        onTap: () {},
                      ),
                    ],
                  );
                },
                onReorder: (_, _) {},
                itemBuilder: (context, innerIndex) => SizedBox(
                  key: const ValueKey('inner-single-task'),
                  height: 56,
                  child: InkWell(
                    key: const ValueKey('inner-single-tap'),
                    onTap: onInnerTap,
                    child: const Center(child: Text('唯一任务')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _UnmountDuringHoldHarness extends StatefulWidget {
  const _UnmountDuringHoldHarness({
    super.key,
    required this.onMenu,
    required this.onInnerTap,
  });

  final ValueChanged<String> onMenu;
  final VoidCallback onInnerTap;

  @override
  State<_UnmountDuringHoldHarness> createState() =>
      _UnmountDuringHoldHarnessState();
}

class _UnmountDuringHoldHarnessState extends State<_UnmountDuringHoldHarness> {
  var _showInner = true;

  /// 模拟 stream 重建：按住期间移除内层子树。
  void removeInner() => setState(() => _showInner = false);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => PactaHoldReorderList(
          itemCount: 1,
          itemExtent: 180,
          onHoldMenu: (_) {
            widget.onMenu('outer');
            showPactaActionSheet(
              context,
              title: '外层菜单',
              actions: [
                PactaActionItem(id: 'outer-edit', label: '编辑目标', onTap: () {}),
              ],
            );
          },
          onReorder: (_, _) {},
          itemBuilder: (context, index) => Column(
            key: const ValueKey('unmount-outer-item'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56, child: Center(child: Text('外层标题'))),
              if (_showInner)
                PactaHoldReorderList(
                  key: const ValueKey('unmount-inner-list'),
                  itemCount: 1,
                  itemExtent: 56,
                  onHoldMenu: (_) {
                    widget.onMenu('inner');
                    showPactaActionSheet(
                      context,
                      title: '内层单项菜单',
                      actions: [
                        PactaActionItem(
                          id: 'inner-edit',
                          label: '编辑任务',
                          onTap: () {},
                        ),
                      ],
                    );
                  },
                  onReorder: (_, _) {},
                  itemBuilder: (context, innerIndex) => SizedBox(
                    key: const ValueKey('unmount-inner-item'),
                    height: 56,
                    child: InkWell(
                      key: const ValueKey('unmount-inner-tap'),
                      onTap: widget.onInnerTap,
                      child: const Center(child: Text('任务 X')),
                    ),
                  ),
                )
              else
                const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    ),
  );
}
