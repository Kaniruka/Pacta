import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/theme/pacta_theme.dart';
import 'package:pacta/src/ui/pacta_horizontal_pager.dart';

/// 横向分页原语的桌面行为：吸附物理、滚轮/Shift+滚轮、快捷键与安全隔离。
///
/// 全部用真实指针与键盘事件驱动，不读源码、不跳过任何分支。

const _pagerKey = ValueKey('pager-under-test');
const _statusKey = ValueKey('pager-status');

class _PagerHost extends StatefulWidget {
  const _PagerHost({
    this.pageCount = 3,
    this.enableKeyboardShortcuts = true,
    this.enablePointerScroll = true,
    this.leading,
  });

  final int pageCount;
  final bool enableKeyboardShortcuts;
  final bool enablePointerScroll;

  /// 挂在分页区上方的附加控件（例如输入框），用于隔离测试。
  final Widget? leading;

  @override
  State<_PagerHost> createState() => _PagerHostState();
}

class _PagerHostState extends State<_PagerHost> {
  late final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int step) {
    final int next = (_page + step).clamp(0, widget.pageCount - 1);
    if (next == _page) return;
    setState(() => _page = next);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PactaHorizontalPagerScope(
        pageCount: widget.pageCount,
        currentPage: _page,
        onStepPage: _step,
        enableKeyboardShortcuts: widget.enableKeyboardShortcuts,
        enablePointerScroll: widget.enablePointerScroll,
        child: Column(
          children: [
            if (widget.leading != null) widget.leading!,
            SizedBox(height: 32, key: _statusKey, child: Text('page=$_page')),
            Expanded(
              child: ScrollConfiguration(
                behavior: const PactaScrollBehavior(),
                child: PageView.builder(
                  key: _pagerKey,
                  controller: _controller,
                  pageSnapping: false,
                  physics: const PactaPageScrollPhysics(),
                  onPageChanged: (page) => setState(() => _page = page),
                  itemCount: widget.pageCount,
                  itemBuilder: (context, index) => PactaPagerWheelCatcher(
                    child: index == 0
                        ? ListView.builder(
                            key: const PageStorageKey<String>('pager-list-0'),
                            padding: const EdgeInsets.all(8),
                            itemCount: 40,
                            itemBuilder: (context, item) =>
                                SizedBox(height: 48, child: Text('列表项 $item')),
                          )
                        : Center(
                            child: Text(
                              '第 $index 页内容',
                              key: ValueKey('page-content-$index'),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 上方压一层对话框/输入框、或把分页塞进 IndexedStack 的外壳。
class _OverlayHost extends StatefulWidget {
  const _OverlayHost({this.mode = _OverlayMode.dialog});

  final _OverlayMode mode;

  @override
  State<_OverlayHost> createState() => _OverlayHostState();
}

enum _OverlayMode { dialog, field, hiddenInStack }

class _OverlayHostState extends State<_OverlayHost> {
  int _stackIndex = 0;

  Future<void> _openDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('压在最上面的对话框'),
        content: TextField(autofocus: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.mode) {
      case _OverlayMode.dialog:
        return Scaffold(
          body: Column(
            children: [
              TextButton(
                key: const ValueKey('open-dialog'),
                onPressed: _openDialog,
                child: const Text('打开对话框'),
              ),
              const Expanded(child: _PagerHost()),
            ],
          ),
        );
      case _OverlayMode.field:
        return const _PagerHost(
          leading: Padding(
            padding: EdgeInsets.all(8),
            child: TextField(key: ValueKey('leading-field')),
          ),
        );
      case _OverlayMode.hiddenInStack:
        return Scaffold(
          body: Column(
            children: [
              TextButton(
                key: const ValueKey('toggle-stack'),
                onPressed: () =>
                    setState(() => _stackIndex = _stackIndex == 0 ? 1 : 0),
                child: const Text('切换隐藏页'),
              ),
              Expanded(
                child: IndexedStack(
                  index: _stackIndex,
                  children: const [
                    _PagerHost(),
                    Center(child: Text('另一页')),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

Future<void> _pumpHost(
  WidgetTester tester,
  Widget host, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: pactaTheme(Brightness.light), home: host),
  );
  await tester.pumpAndSettle();
}

PageController _controller(WidgetTester tester) =>
    tester.widget<PageView>(find.byKey(_pagerKey)).controller!;

int _statusPage(WidgetTester tester) {
  final text = tester.widget<Text>(find.textContaining('page=')).data!;
  return int.parse(text.split('=').last);
}

/// 慢拖：分三段移动，松手前静止 200ms，保证没有飞划速度。
Future<void> _slowDrag(
  WidgetTester tester,
  Offset start,
  Offset delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final TestGesture gesture = await tester.startGesture(start, kind: kind);
  await tester.pump(const Duration(milliseconds: 16));
  // 分 10 小步：真实鼠标/触控板只会发密集小位移，首步被识别器吃掉的那
  // 一点滑距因此与真机一致，不会把整段拖拽吞掉。
  for (var step = 0; step < 10; step++) {
    await gesture.moveBy(delta / 10);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _scroll(
  WidgetTester tester,
  Offset delta, {
  Offset? position,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: position ?? tester.getCenter(find.byKey(_pagerKey)),
      scrollDelta: delta,
      kind: kind,
    ),
  );
  await tester.pump();
}

void main() {
  group('PactaPageScrollPhysics', () {
    testWidgets('1280x800 宽视口：慢拖 150dp 翻页、反向回退、轻触回弹', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);
      final Offset center = tester.getCenter(find.byKey(_pagerKey));
      expect(controller.page, 0.0);

      await _slowDrag(tester, center, const Offset(-150, 0));
      expect(controller.page, 1.0, reason: '宽屏慢拖 150dp 足以翻页');
      expect(_statusPage(tester), 1);

      await _slowDrag(tester, center, const Offset(150, 0));
      expect(controller.page, 0.0, reason: '反向慢拖回到第 0 页');
      expect(_statusPage(tester), 0);

      await _slowDrag(tester, center, const Offset(-40, 0));
      expect(controller.page, 0.0, reason: '轻触 40dp 回弹原页');
      expect(_statusPage(tester), 0);
    });

    testWidgets('首尾边界不回绕，页面对齐时不会向后跳页', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);
      final Offset center = tester.getCenter(find.byKey(_pagerKey));

      await _slowDrag(tester, center, const Offset(180, 0));
      expect(controller.page, 0.0, reason: '首端右拖不回绕');

      await _slowDrag(tester, center, const Offset(-180, 0));
      await _slowDrag(tester, center, const Offset(-180, 0));
      expect(controller.page, 2.0, reason: '连续两次慢拖到末页');

      await _slowDrag(tester, center, const Offset(-180, 0));
      expect(controller.page, 2.0, reason: '末端左拖不回绕');

      // 已经对齐在末页：松手时绝不能因取整退回上一页。
      await _slowDrag(tester, center, const Offset(-10, 0));
      expect(controller.page, 2.0, reason: '对齐页码不后退');
    });

    testWidgets('快速飞划按速度至少前进一页', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);
      await tester.fling(find.byKey(_pagerKey), const Offset(-120, 0), 1600);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0);
    });
  });

  group('滚轮与 Shift+滚轮', () {
    testWidgets('Shift+滚轮上下各一格切页，方向与滚动一致', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _scroll(tester, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: 'Shift+滚轮向下 = 下一页');

      await tester.pump(const Duration(milliseconds: 400));
      await _scroll(tester, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: 'Shift+滚轮向上 = 上一页');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('原生横向滚轮直接切页，两页时停在末页', (tester) async {
      await _pumpHost(tester, const _PagerHost(pageCount: 2));
      final PageController controller = _controller(tester);

      await _scroll(tester, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.page, 1.0);
      expect(_statusPage(tester), 1);

      await tester.pump(const Duration(milliseconds: 400));
      await _scroll(tester, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: '末页继续横向滚不越界');
    });

    testWidgets('普通竖直滚轮不翻页，且照常滚动页内列表', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);
      final ScrollPosition listPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;

      await _scroll(tester, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '竖直滚轮不抢分页');
      expect(listPosition.pixels, greaterThan(0), reason: '页内列表照常滚动');
    });

    testWidgets('Ctrl+滚轮属于缩放，不切页', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _scroll(tester, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: 'Ctrl+滚轮属于缩放，不翻页');

      await _scroll(tester, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '连续 Ctrl+滚轮也不翻页');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('短时间连发滚轮只翻一页，首尾边界不回绕', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var burst = 0; burst < 5; burst++) {
        await _scroll(tester, const Offset(0, 100));
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: '冷却期内连发只算一次');

      // 首端向上滚不越界。
      await tester.pump(const Duration(milliseconds: 400));
      await _scroll(tester, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '首端不回绕');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });
  });

  group('键盘快捷键', () {
    testWidgets('左右方向键与 Ctrl+Tab / Ctrl+Shift+Tab 切页', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: '→ 下一页');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '← 上一页');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: 'Ctrl+Tab 下一页');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: 'Ctrl+Shift+Tab 上一页');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('首端方向键不翻页，Ctrl+Tab 在边界被吃掉', (tester) async {
      await _pumpHost(tester, const _PagerHost());
      final PageController controller = _controller(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '边界不循环');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('输入框内方向键归文本编辑器，不翻页', (tester) async {
      await _pumpHost(tester, const _OverlayHost(mode: _OverlayMode.field));
      final PageController controller = _controller(tester);

      await tester.tap(find.byKey(const ValueKey('leading-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('leading-field')),
        '光标在文字里',
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '正在输入时不抢方向键');
      expect(tester.takeException(), isNull);
    });

    testWidgets('IndexedStack 隐藏页不响应快捷键', (tester) async {
      await _pumpHost(
        tester,
        const _OverlayHost(mode: _OverlayMode.hiddenInStack),
      );
      final PageController controller = _controller(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: '可见时正常翻页');

      await tester.tap(find.byKey(const ValueKey('toggle-stack')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0, reason: '隐藏页吃不到方向键');
      expect(tester.takeException(), isNull);
    });

    testWidgets('上方弹出对话框时背景页不翻页', (tester) async {
      await _pumpHost(tester, const _OverlayHost(mode: _OverlayMode.dialog));
      final PageController controller = _controller(tester);

      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();
      expect(find.text('压在最上面的对话框'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0, reason: '对话框盖住时背景页不翻');

      // 关闭对话框后恢复响应，证明确实是路由层级在拦截。
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('压在最上面的对话框'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('可关闭的入口', () {
    testWidgets('关掉快捷键后方向键与 Ctrl+Tab 都不翻页', (tester) async {
      await _pumpHost(tester, const _PagerHost(enableKeyboardShortcuts: false));
      final PageController controller = _controller(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 0.0);

      // 滚轮入口独立于快捷键：同一份宿主仍能切页。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _scroll(tester, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(controller.page, 1.0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关掉滚轮入口后 Shift+滚轮不翻页，快捷键仍可用', (tester) async {
      await _pumpHost(tester, const _PagerHost(enablePointerScroll: false));
      final PageController controller = _controller(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _scroll(tester, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(controller.page, 0.0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 1.0);
      expect(tester.takeException(), isNull);
    });
  });
}
